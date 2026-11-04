"""MKSM Komplete+ launcher logic, kept apart from the window so it can be tested.

Which packages ship with the launcher, what is installed, what Install/Update
would change, and the instant on/off switches. Every file it writes goes
through mods/_build/modtool.py (the same SHA-256 checks as the Recomp
launcher's "Install from file...", removed mods moved to
mods\\.mksmk-backup\\<time>\\), so the launcher installs exactly like modtool.

Install/Update installs every mod of the set that is missing, older, or a
different build of the same version, and removes retired ids. Mods that are
not part of the set (language packs, dev diagnostics, other people's mods)
are left alone, and a newer build of a set mod is kept unless Repair is used.
Switches on installed mods only flip their enabled flag in installed.toml.
"""
from __future__ import annotations

import ctypes, json, os, re, shutil, subprocess, sys
from dataclasses import dataclass, field
from pathlib import Path

FROZEN = getattr(sys, "frozen", False)
HERE = Path(__file__).resolve().parent
BUNDLE = Path(getattr(sys, "_MEIPASS", HERE))          # PyInstaller's unpacked data
EXE_DIR = Path(sys.executable).resolve().parent if FROZEN else HERE
SOURCE_ROOT = None if FROZEN else HERE.parents[1]       # the project folder when run from source
if SOURCE_ROOT and str(SOURCE_ROOT / "mods" / "_build") not in sys.path:
    sys.path.insert(0, str(SOURCE_ROOT / "mods" / "_build"))
import modtool  # noqa: E402

ToolError = modtool.ToolError
PROCESS = modtool.PROCESS
ROUTINE_LIMIT = 64          # the Recomp doesn't boot with more active routine scripts
LEVELS = dict(modtool.LDK_VARIANTS)                     # {"ldk": "x2", "ldk_x3": "x3", "ldk_x4": "x4"}
LDK_IDS = tuple(LEVELS)
LEVEL_NAMES = {"x2": "x2", "x3": "x3 Hard", "x4": "x4 Legendary"}
PROBE = "mksmk_probe"
PROJECT_URL = "https://github.com/totallynots8tn/mksm-komplete"
RECOMP_URL = "https://github.com/OAleex/ShaolinMonksRecomp"
COFFEE_URL = "https://buymeacoffee.com/S8tn"           # as in README.md and release/site
COFFEE_LABEL = "Insert coin: buy me a coffee"


# ------------------------------------------------------------ the game process
def process_running(name=PROCESS):
    """True while the Recomp (launcher or game) runs. Uses a process snapshot
    instead of tasklist, so the windowed .exe never flashes a console."""
    if os.name != "nt":
        return False
    from ctypes import wintypes

    class Entry(ctypes.Structure):
        _fields_ = [("dwSize", wintypes.DWORD), ("cntUsage", wintypes.DWORD),
                    ("th32ProcessID", wintypes.DWORD), ("th32DefaultHeapID", ctypes.c_size_t),
                    ("th32ModuleID", wintypes.DWORD), ("cntThreads", wintypes.DWORD),
                    ("th32ParentProcessID", wintypes.DWORD), ("pcPriClassBase", ctypes.c_long),
                    ("dwFlags", wintypes.DWORD), ("szExeFile", ctypes.c_wchar * 260)]
    k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    k32.CreateToolhelp32Snapshot.argtypes = [wintypes.DWORD, wintypes.DWORD]
    k32.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
    k32.Process32FirstW.argtypes = k32.Process32NextW.argtypes = [wintypes.HANDLE, ctypes.POINTER(Entry)]
    k32.Process32FirstW.restype = k32.Process32NextW.restype = wintypes.BOOL
    k32.CloseHandle.argtypes = [wintypes.HANDLE]
    snap = k32.CreateToolhelp32Snapshot(0x2, 0)             # TH32CS_SNAPPROCESS
    if not snap or snap == ctypes.c_void_p(-1).value:
        return _tasklist_running(name)
    try:
        entry = Entry()
        entry.dwSize = ctypes.sizeof(Entry)
        ok = k32.Process32FirstW(snap, ctypes.byref(entry))
        while ok:
            if entry.szExeFile.lower() == name.lower():
                return True
            ok = k32.Process32NextW(snap, ctypes.byref(entry))
    finally:
        k32.CloseHandle(snap)
    return False


def _tasklist_running(name):
    try:
        out = subprocess.run(["tasklist", "/FI", f"IMAGENAME eq {name}", "/NH"], capture_output=True,
                             text=True, timeout=15, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0)).stdout
    except (OSError, subprocess.SubprocessError):
        return False
    return name.lower() in out.lower()


# modtool.Session refuses to work while the game runs; give it the check
# that doesn't open a console window (looked up at call time, so tests can
# replace process_running).
modtool.game_running = lambda: process_running()


# ------------------------------------------------------------ what ships
@dataclass(frozen=True)
class Tile:
    key: str
    title: str
    mono: str            # the big letters on the tile
    blurb: str           # one line, player words
    accent: str
    ids: tuple = ()
    default_on: bool = True
    short: str = ""      # the name on the tile, when the full one is too long

    @property
    def mod_ids(self):
        return self.ids or (self.key,)

    @property
    def label(self):
        return self.short or self.title


KNOWN_TILES = (
    Tile("ldk", "Legendary Dark Knight", "LDK", "2x, 3x or 4x the enemies in every fight, Boss Invasion built in",
         "#c0392b", LDK_IDS, short="Dark Knight"),
    Tile("randomizer", "Shaolin Shuffle", "SHUF", "Enemy randomizer, with outsiders from other areas and MK warriors",
         "#f0975a"),
    Tile("mk_upgrade", "XP Shop", "XP", "Spend XP on health, stamina, meter, weapons, fatalities and EX moves",
         "#f5b942"),
    Tile("time_rifts", "Time Rifts", "RIFT", "Rift boss fights in four areas, and Smoke's Survival gauntlet",
         "#a78bfa"),
    Tile("env_kill_xp", "Env Kill XP", "ENV", "Hazard kills pay XP like normal kills", "#5fd39a"),
    Tile("coop_solo", "Solo Co-op Paths", "CO-OP", "Co-op routes and secret areas in single player", "#38bdf8"),
    Tile("unlock_all", "Unlock All", "ALL", "Every character, arena and extra unlocked", "#e3b341"),
    Tile(PROBE, "MKSMK Probe", "PROBE", "Diagnostics for bug reports; changes nothing in the game", "#7fb2e6",
         default_on=False),
)
TILE_OF = {mid: t for t in KNOWN_TILES for mid in t.mod_ids}


def version_key(text):
    return modtool.version_key(text)


def newest_release(root):
    """release/v1.x with the highest version that has packages, or None."""
    best = None
    for folder in (root / "release").glob("v*"):
        m = re.fullmatch(r"v(\d+(?:\.\d+)*)", folder.name)
        if m and folder.is_dir() and any(folder.glob("*.tar.xz")):
            key = tuple(int(x) for x in m.group(1).split("."))
            if best is None or key > best[0]:
                best = (key, folder)
    return best[1] if best else None


def package_sources():
    """Folders to read packages from; a later folder wins for the same mod id."""
    sources = []
    if FROZEN:
        sources.append(BUNDLE / "packages")
    elif SOURCE_ROOT:
        release = newest_release(SOURCE_ROOT)
        if release:
            sources.append(release)
    overlay = EXE_DIR / "packages"          # a hotfix folder next to the .exe
    if overlay.is_dir() and any(overlay.glob("*.tar.xz")) and overlay not in sources:
        sources.append(overlay)
    return sources


def load_bundle(sources=None):
    """({id: package}, [problem text], [source folders]) for the set this launcher installs.
    The newest version of a mod wins across folders (a later folder wins a tie), so an
    old packages folder left next to a newer .exe can't downgrade the set."""
    sources = package_sources() if sources is None else sources
    bundle, problems = {}, []
    for folder in sources:
        found, trouble = modtool.find_packages(Path(folder))
        problems += trouble
        for mid, package in found.items():
            old = bundle.get(mid)
            if mid not in modtool.RETIRED and (old is None or version_key(package["manifest"]["version"]) >=
                                                version_key(old["manifest"]["version"])):
                bundle[mid] = package
    if not FROZEN and SOURCE_ROOT:
        _add_source_ldk_variants(bundle, problems)
    return bundle, problems, sources


def _add_source_ldk_variants(bundle, problems):
    """From the project folder: the frozen set ships only LDK x3; offer x2 and
    x4 when build.py made them at the same version (build_exe.py checks that
    they come from the same source before it bundles them)."""
    present = [bundle[m]["manifest"]["version"] for m in LDK_IDS if m in bundle]
    if not present:
        return
    version = present[0]
    for mid in LDK_IDS:
        if mid in bundle:
            continue
        archive = SOURCE_ROOT / "mods" / mid / "dist" / f"{mid}-{version}.tar.xz"
        if archive.is_file():
            try:
                package = modtool.inspect(archive)
            except Exception as e:  # a broken dev build must not stop the launcher
                problems.append(f"{archive.name}: {e}")
                continue
            package["archive"] = archive
            bundle[mid] = package


def set_info(sources=None):
    """(title, date, notes) of the set, from the README.txt that ships with it."""
    sources = package_sources() if sources is None else sources
    candidates = ([BUNDLE / "README.txt"] if FROZEN else []) + [Path(s) / "README.txt" for s in sources]
    for path in candidates:
        if path.is_file():
            return parse_readme(path.read_text(encoding="utf-8", errors="replace"))
    return ("", "", "")


def parse_readme(text):
    lines = text.splitlines()
    title = date = ""
    m = re.match(r"MKSM Komplete\+\s+(v[\d.]+)\s*(?:\((.*?)\))?", lines[0].strip()) if lines else None
    if m:
        extra = [p.strip() for p in (m.group(2) or "").split(",") if p.strip()]
        date = next((p for p in extra if re.fullmatch(r"\d{4}-\d{2}-\d{2}", p)), "")
        title = " ".join([m.group(1)] + [p for p in extra if p != date])
    notes = []
    for line in lines[1:]:
        if re.match(r"\s*(Install|Requires|Checksums)\b", line):
            break
        if line.startswith("  ") and notes and notes[-1]:      # a wrapped bullet: join it back
            notes[-1] += " " + line.strip()
        else:
            notes.append(line.rstrip())
    return title, date, "\n".join(notes).strip()


def tag_of(manifest):
    name = manifest.get("name", "").lower()
    if "(diagnostics)" in name:
        return "Diagnostics"
    if "(preview)" in name:
        return "Preview"
    return "Stable"


# ------------------------------------------------------------ what is installed
def data_folder(data=None):
    return modtool.data_folder(data)


def read_rows(data=None):
    """(rows, problem): installed.toml rows, or None and why not."""
    root = data_folder(data) / "mods"
    if not root.is_dir():
        return None, ("Start Shaolin Monks Recomp once so it makes its mods folder, close it, then press Install.")
    try:
        return modtool.read_registry(root), None
    except Exception as e:  # unreadable or inconsistent registry
        return None, str(e)


def registry_stamp(data=None):
    try:
        return (data_folder(data) / "mods" / "installed.toml").stat().st_mtime_ns
    except OSError:
        return None


def routine_count(rows):
    return sum(len(r["manifest"].get("routines", [])) for r in rows if r["enabled"])


def enabled_problem(rows):
    """Why this set of enabled mods can't run together, or None."""
    enabled = {r["id"]: r for r in rows if r["enabled"]}
    for mid, row in enabled.items():
        name = row["manifest"].get("name", mid)
        for other in row["manifest"].get("conflicts", []):
            if other in enabled and other != mid:
                return f"{name} can't be on together with {enabled[other]['manifest'].get('name', other)}."
        for dep in row["manifest"].get("dependencies", []):
            if dep.get("id") not in enabled:
                return f"{name} needs {dep.get('id')} switched on."
    count = routine_count(rows)
    if count > ROUTINE_LIMIT:
        return (f"That would run {count} routine scripts, and the Recomp only starts with {ROUTINE_LIMIT} "
                f"or fewer. Switch another mod off first.")
    return None


# ------------------------------------------------------------ one view per tile
@dataclass
class ModView:
    tile: Tile
    packages: dict              # id -> bundled package
    rows: dict                  # id -> installed row
    on: bool
    level: str | None = None    # LDK: the level that is (or will be) on
    levels: list = field(default_factory=list)
    status: str = "ok"          # ok | missing | update | newer | partial
    version: str = ""
    bundled: str = ""

    @property
    def installed(self):
        return bool(self.rows)

    @property
    def is_ldk(self):
        return self.tile.key == "ldk"

    def manifest(self):
        """The manifest to describe: the chosen LDK level's, else the installed or bundled one."""
        ids = list(self.tile.mod_ids)
        if self.is_ldk and self.level:
            ids.sort(key=lambda m: LEVELS.get(m) != self.level)
        for mid in ids:
            if mid in self.packages:
                return self.packages[mid]["manifest"]
            if mid in self.rows:
                return self.rows[mid]["manifest"]
        return {}

    @property
    def tag(self):
        return tag_of(self.manifest())


def generic_tile(manifest):
    name = manifest.get("name", manifest["id"])
    plain = re.sub(r"\s*\(.*?\)", "", name).strip() or manifest["id"]
    words = re.findall(r"[A-Za-z0-9]+", plain)
    mono = "".join(w[0] for w in words[:3]).upper() or plain[:3].upper()
    summary = manifest.get("summary", "")
    blurb = re.split(r"(?<=[.!?])\s", summary, maxsplit=1)[0][:90]
    return Tile(manifest["id"], plain, mono, blurb, "#a1a1aa", default_on=True)


def build_views(bundle, rows, prefs):
    """One ModView per tile of the set (known tiles first, then any extra
    package a hotfix folder brought). prefs: {"on": {tile key: bool}, "level": "x3"}
    for mods that aren't installed yet."""
    rows = rows or []
    installed = {r["id"]: r for r in rows}
    tiles = [t for t in KNOWN_TILES if any(m in bundle for m in t.mod_ids)]
    tiles += [generic_tile(p["manifest"]) for mid, p in sorted(bundle.items()) if mid not in TILE_OF]
    views = []
    for tile in tiles:
        ids = tile.mod_ids
        packages = {m: bundle[m] for m in ids if m in bundle}
        mine = {m: installed[m] for m in ids if m in installed}
        on_pref = prefs.get("on", {}).get(tile.key, tile.default_on)
        view = ModView(tile, packages, mine, on_pref)
        if tile.key == "ldk":
            view.levels = [lvl for m, lvl in LEVELS.items() if m in packages or m in mine]
            enabled = [LEVELS[m] for m, r in mine.items() if r["enabled"]]
            pref_level = prefs.get("level") or "x3"
            if enabled:
                view.on, view.level = True, enabled[0]
            else:
                if mine:
                    view.on = False
                view.level = pref_level if pref_level in view.levels else (
                    "x3" if "x3" in view.levels else (view.levels[0] if view.levels else None))
        elif mine:
            view.on = any(r["enabled"] for r in mine.values())
        # status and versions
        states = []
        for m in ids:
            p, r = packages.get(m), mine.get(m)
            if p is None:
                continue
            if r is None:
                states.append("missing")
            else:
                c = _cmp(r["version"], p["manifest"]["version"])
                states.append("update" if c < 0 or (c == 0 and r["raw"] != p["raw"]) else
                              ("newer" if c > 0 else "ok"))
        if not mine:
            view.status = "missing"
        elif "update" in states:
            view.status = "update"
        elif "missing" in states:
            view.status = "partial"
        elif "newer" in states:
            view.status = "newer"
        else:
            view.status = "ok"
        shown = view.manifest()
        view.bundled = shown.get("version", "")
        pick = next((mine[m] for m in ids if m in mine and (not view.is_ldk or LEVELS[m] == view.level)), None)
        pick = pick or next(iter(mine.values()), None)
        view.version = pick["version"] if pick else view.bundled
        views.append(view)
    return views


def others(bundle, rows):
    """Installed rows that aren't part of this set (language packs, dev mods, other people's mods)."""
    ours = set(bundle) | {m for t in KNOWN_TILES for m in t.mod_ids if any(x in bundle for x in t.mod_ids)}
    return [r for r in (rows or []) if r["id"] not in ours]


def prefs_from(views, prefs):
    """Make prefs mirror what is installed, so Install/Update keeps it."""
    out = {"on": dict(prefs.get("on", {})), "level": prefs.get("level") or "x3"}
    for v in views:
        if v.installed:
            out["on"][v.tile.key] = v.on
        if v.is_ldk and v.level:
            out["level"] = v.level
    return out


# ------------------------------------------------------------ Install / Update
@dataclass
class Change:
    kind: str                   # install | update | reinstall | downgrade | remove
    id: str
    name: str
    old: str | None = None
    new: str | None = None
    package: dict | None = None

    def text(self):
        if self.kind == "install":
            return f"Install {self.name} {self.new}"
        if self.kind == "update":
            return f"Update {self.name} {self.old} → {self.new}"
        if self.kind == "reinstall":
            return f"Reinstall {self.name} {self.new}"
        if self.kind == "downgrade":
            return f"Replace {self.name} {self.old} with the set's {self.new}"
        return f"Remove {self.name} {self.old} (retired)"


def _cmp(a, b):
    ka, kb = version_key(a), version_key(b)
    return (ka > kb) - (ka < kb)


def _order(mid):
    tile = TILE_OF.get(mid)
    return (KNOWN_TILES.index(tile) if tile else len(KNOWN_TILES), mid)


def display_name(mid, manifest):
    """A mod's name for messages: the LDK variants by level, the rest without "(preview)" and such."""
    if mid in LEVELS:
        return f"Legendary Dark Knight {LEVELS[mid]}"
    tile = TILE_OF.get(mid)
    return tile.title if tile else manifest.get("name", mid)


def describe_sources(sources):
    """Where the packages come from, in words (not the .exe's temp folder)."""
    out = []
    for folder in sources:
        folder = Path(folder)
        if FROZEN and folder == BUNDLE / "packages":
            out.append("built into this launcher")
        elif folder == EXE_DIR / "packages":
            out.append("the packages folder next to the launcher")
        elif SOURCE_ROOT and SOURCE_ROOT in folder.parents:
            out.append(str(folder.relative_to(SOURCE_ROOT)))
        else:
            out.append(str(folder))
    if not FROZEN and SOURCE_ROOT:
        out.append("LDK x2/x4 from mods\\ldk*\\dist")
    return ", ".join(out) or "nowhere"


def plan(bundle, rows, force=False):
    """The changes Install/Update makes. force (Repair) also reinstalls up-to-date
    mods and replaces newer builds with the set's."""
    installed = {r["id"]: r for r in rows or []}
    out = []
    for mid in sorted(bundle, key=_order):
        if mid in modtool.RETIRED:
            continue
        package = bundle[mid]
        m = package["manifest"]
        row = installed.get(mid)
        name = display_name(mid, m)
        if row is None:
            out.append(Change("install", mid, name, None, m["version"], package))
            continue
        c = _cmp(row["version"], m["version"])
        if c < 0:
            kind = "update"
        elif c == 0 and (row["raw"] != package["raw"] or force):
            kind = "reinstall"
        elif c > 0 and force:
            kind = "downgrade"
        else:
            continue
        out.append(Change(kind, mid, name, row["version"], m["version"], package))
    for row in rows or []:
        if row["id"] in modtool.RETIRED:
            out.append(Change("remove", row["id"], display_name(row["id"], row["manifest"]), row["version"]))
    return out


def wanted(mid, prefs):
    """Whether a mod that is installed now starts switched on."""
    tile = TILE_OF.get(mid)
    on = prefs.get("on", {}).get(tile.key if tile else mid, tile.default_on if tile else True)
    if mid in LEVELS:
        return on and LEVELS[mid] == (prefs.get("level") or "x3")
    return on


def _settle_ldk(rows, prefs):
    """Exactly one LDK level on when LDK is switched on, none when it's off."""
    ldk = [r for r in rows if r["id"] in LEVELS]
    if not ldk:
        return
    on = prefs.get("on", {}).get("ldk", True)
    level = prefs.get("level") or "x3"
    pick = None
    if on:
        by_level = {LEVELS[r["id"]]: r for r in ldk}
        pick = by_level.get(level) or by_level.get("x3") or ldk[0]
    for r in ldk:
        r["enabled"] = r is pick


@dataclass
class Result:
    changes: list
    notes: list
    rows: list
    backup: Path | None


def _session(data):
    return modtool.Session(data_folder(data))


def _install_all(session, changes, prefs):
    """Install the packages of `changes`, settle LDK and conflicts, save. If one
    package fails, what was installed before it is still registered, then the
    error is raised (so installed.toml always matches the files)."""
    newcomers, notes, error = set(), [], None
    for ch in changes:
        if ch.kind == "remove":
            continue
        is_new = not any(r["id"] == ch.id for r in session.rows)
        try:
            session.install(ch.package, enabled=wanted(ch.id, prefs))
        except Exception as e:  # report after saving what is done
            error = e
            break
        if is_new:
            newcomers.add(ch.id)
    if any(ch.id in LEVELS and ch.kind != "remove" for ch in changes):
        _settle_ldk(session.rows, prefs)
    notes += session.resolve_conflicts(newcomers)
    session.save()
    if error:
        raise error if isinstance(error, ToolError) else ToolError(f"Install stopped: {error}")
    problem = enabled_problem(session.rows)
    if problem:
        notes.append(problem)
    return notes


def install_set(data, bundle, prefs, force=False):
    """Install/Update (or Repair, with force): bring the set's mods to the bundled builds."""
    session = _session(data)
    changes = plan(bundle, session.rows, force)
    for ch in changes:
        if ch.kind == "remove":
            row = next(r for r in session.rows if r["id"] == ch.id)
            session.stash(row["manifest"]["install_dir"])
            session.rows.remove(row)
            session.changed = True
    notes = _install_all(session, changes, prefs)
    return Result(changes, notes, session.rows, session.backup if session.changed else None)


def install_folder(data, folder, prefs):
    """Install the newest package of every mod in a folder (dev builds, a test set);
    like `modtool.py install <folder>`, but other mods stay as they are."""
    packages, problems = modtool.find_packages(Path(folder))
    packages = {m: p for m, p in packages.items() if m not in modtool.RETIRED}
    if not packages:
        raise ToolError("No mod packages (.tar.xz) in that folder." +
                        (" Skipped: " + "; ".join(problems) if problems else ""))
    session = _session(data)
    changes = []
    for mid in sorted(packages, key=_order):
        package, m = packages[mid], packages[mid]["manifest"]
        row = next((r for r in session.rows if r["id"] == mid), None)
        changes.append(Change("install" if row is None else "reinstall", mid, display_name(mid, m),
                              row["version"] if row else None, m["version"], package))
    notes = [f"Skipped {p}" for p in problems] + _install_all(session, changes, prefs)
    return Result(changes, notes, session.rows, session.backup if session.changed else None)


def uninstall_all(data):
    session = _session(data)
    removed = session.uninstall_all()
    session.save()
    return removed


def switch(data, enable):
    """Turn installed mods on or off right away: {id: bool}. Only installed.toml
    changes. Switching something on is refused if the result couldn't run
    (conflict, missing dependency, over the routine-script limit); switching
    off is always allowed."""
    session = _session(data)
    rows = {r["id"]: r for r in session.rows}
    turning_on = False
    for mid, on in enable.items():
        if mid not in rows:
            raise ToolError(f"{mid} isn't installed; press Install first.")
        turning_on |= bool(on) and not rows[mid]["enabled"]
        rows[mid]["enabled"] = bool(on)
    if turning_on:
        problem = enabled_problem(session.rows)
        if problem:
            raise ToolError(problem)
    modtool.write_registry(session.root, session.rows)
    return session.rows


def switch_tile(data, view, on, level=None):
    """Apply a tile's switch, or an LDK level pick, at once (installed mods only)."""
    if not view.rows:
        raise ToolError(f"{view.tile.title} isn't installed yet; press Install first.")
    if view.is_ldk:
        level = level or view.level or "x3"
        target = next((m for m in view.rows if LEVELS[m] == level), None)
        if on and target is None:
            raise ToolError(f"LDK {level} isn't installed yet; press Update first.")
        return switch(data, {m: bool(on) and m == target for m in view.rows})
    return switch(data, {m: on for m in view.rows})


# ------------------------------------------------------------ the game, folders, settings
def settings_path():
    base = Path(os.environ.get("LOCALAPPDATA") or (Path.home() / "AppData" / "Local"))
    return base / "MKSMK" / "launcher.json"


def load_settings():
    try:
        return json.loads(settings_path().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def save_settings(values):
    path = settings_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(values, indent=2), encoding="utf-8")
    except OSError:
        pass


def find_game(data=None):
    """ShaolinMonksRecomp.exe: the one picked by hand, else the folder the newest Recomp log names."""
    picked = load_settings().get("game_exe")
    if picked and Path(picked).is_file():
        return Path(picked)
    logs = data_folder(data) / "logs"
    try:
        newest = sorted(logs.glob("*.log"), key=lambda p: p.stat().st_mtime, reverse=True)
    except OSError:
        return None
    for log in newest[:5]:
        try:
            with open(log, encoding="utf-8", errors="replace") as f:
                for _, line in zip(range(40), f):
                    m = re.search(r"\] Path: (.+)$", line.strip())
                    if m:
                        exe = Path(m.group(1)) / PROCESS
                        if exe.is_file():
                            return exe
        except OSError:
            continue
    return None


def game_ready(data=None):
    """The Recomp has a game disc registered (else its own launcher must run first)."""
    return (data_folder(data) / "game-source.toml").is_file()


def child_env():
    """The environment for programs we start: without the PyInstaller and Tcl/Tk
    variables of this .exe, which would break a Python started from it."""
    env = dict(os.environ)
    for key in list(env):
        if key.startswith(("_MEI", "_PYI", "TCL_", "TK_", "TCLLIBPATH")) or key in ("TCL_LIBRARY", "TK_LIBRARY"):
            env.pop(key, None)
    return env


def start(args, **kw):
    """Popen for programs we start. The frozen .exe's DLL folder is cleared while
    the child starts, so the game can't pick up DLLs bundled in this .exe."""
    kernel32 = ctypes.windll.kernel32 if FROZEN and os.name == "nt" else None
    if kernel32:
        kernel32.SetDllDirectoryW(None)
    try:
        return subprocess.Popen(args, env=child_env(), close_fds=True, **kw)
    finally:
        if kernel32:
            kernel32.SetDllDirectoryW(str(BUNDLE))


def launch_game(exe, direct=True):
    return start([str(exe)] + (["--no-launcher"] if direct else []), cwd=str(Path(exe).parent))


def open_path(path):
    path = Path(path)
    if not path.exists():
        raise ToolError(f"{path} doesn't exist yet.")
    os.startfile(str(path))  # noqa: S606  (Explorer)


def project_root():
    """The MKSMK project folder (for the QA console), when this runs from it."""
    if SOURCE_ROOT:
        return SOURCE_ROOT
    for folder in [EXE_DIR, *EXE_DIR.parents][:5]:
        if (folder / "tools" / "qa_console" / "qa_console.py").is_file() and \
                (folder / "mods" / "_build" / "modtool.py").is_file():
            return folder
    return None


def python_command():
    if shutil.which("py"):
        return ["py", "-3"]
    for name in ("python", "python3"):
        if shutil.which(name):
            return [name]
    return None


def open_qa_console(root):
    """Console Python in a minimized window, as MKSMK.bat does (the console polls
    tasklist, and without a console of its own every poll flashes a window)."""
    python = python_command()
    if not python:
        raise ToolError("The QA console needs Python 3.11+ (python.org).")
    script = Path(root) / "tools" / "qa_console" / "qa_console.py"
    info = subprocess.STARTUPINFO()
    info.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    info.wShowWindow = 7                    # SW_SHOWMINNOACTIVE
    start(python + [str(script)], cwd=str(root), startupinfo=info, creationflags=subprocess.CREATE_NEW_CONSOLE)
