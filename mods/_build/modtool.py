"""MKSMK mod tool: bulk uninstall / install for Shaolin Monks Recomp.

Close the launcher and the game first. Run MKSMK.bat in the project folder
for a menu, or:

  python modtool.py refresh [folder...] uninstall all mods, then install the newest
                                       package of every mod in [folder] (release\\v1 is
                                       the players' set); without it: dist/*.tar.xz of
                                       every mod under ..\\..\\mods. With several folders
                                       a later one wins for the same mod, so
                                       "refresh release\\v1 mods\\mk_upgrade" is v1 plus
                                       the dev XP shop.
  python modtool.py uninstall-all      remove every mod except language packs
  python modtool.py install <folder...> install the newest package of each mod found
                                       in <folder> (a mod folder with dist/, a folder
                                       of mod folders, or a folder of .tar.xz files)
  python modtool.py list               show installed mods

Options: --skip id1,id2   leave these mod ids out (always skips the retired
                          ldk_bosses; skips mksmk_probe unless --with-probe)
         --ldk x2|x3|x4  which Legendary Dark Knight variant is enabled (default
                          x3, the only one in release/v1); other variants found are
                          installed but disabled. If the chosen variant isn't in the
                          folder, the one that is gets enabled.
         --shuffle normal|wild|chaos  which Shaolin Shuffle variant is enabled
                          (default normal); the others are installed but disabled
         --with-probe     include the MKSMK Probe diagnostics mod
         --data <folder>  the launcher's data folder, if you moved it

It writes the launcher's own registry (mods\\installed.toml) the same way the
launcher does, verifies every package the way "Install from file..." does,
never touches language packs, and moves removed mods to
mods\\.mksmk-backup\\<time>\\ instead of deleting them.
"""
import hashlib, io, json, lzma, os, re, shutil, subprocess, sys, tarfile, tempfile, time
try:
    import tomllib
except ModuleNotFoundError:          # Python < 3.11
    try:
        import tomli as tomllib
    except ModuleNotFoundError:
        print("This tool needs Python 3.11 or newer (or `pip install tomli`).")
        sys.exit(1)
from pathlib import Path, PurePosixPath

GAME_SHA = "48240902bf4a04eb89376217c529531032d3370749bcce91a194878cc49db74a"
RECOMP_VERSION = "0.2.0"
HERE = Path(__file__).resolve().parent
DEFAULT_SOURCE = HERE.parent          # ...\MKSMK\mods
PROCESS = "ShaolinMonksRecomp.exe"
# Legendary Dark Knight ships as three conflicting variants; one is enabled.
LDK_VARIANTS = {"ldk": "x2", "ldk_x3": "x3", "ldk_x4": "x4"}
# So does Shaolin Shuffle (how many outsider enemies each room gets).
SHUFFLE_VARIANTS = {"randomizer": "normal", "randomizer_wild": "wild", "randomizer_chaos": "chaos"}


class ToolError(Exception):
    pass


# ---------------------------------------------------------------- locations
def data_folder(explicit):
    if explicit:
        return Path(explicit)
    base = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local")) / "Shaolin Monks Recomp"
    locator = base / "paths.toml"
    if locator.is_file():
        try:
            with open(locator, "rb") as f:
                prefs = tomllib.load(f)
            for key in ("data", "data_folder", "data_path"):
                value = prefs.get(key)
                if isinstance(value, str) and value:
                    return Path(value)
        except (OSError, tomllib.TOMLDecodeError):
            pass
    return base


def game_running():
    if os.name != "nt":
        return False
    try:
        out = subprocess.run(["tasklist", "/FI", f"IMAGENAME eq {PROCESS}", "/NH"],
                             capture_output=True, text=True, timeout=15).stdout
    except (OSError, subprocess.SubprocessError):
        return False
    return PROCESS.lower() in out.lower()


# ---------------------------------------------------------------- registry
def toml_string(value):
    out = ['"']
    for ch in value:
        code = ord(ch)
        if ch == '"':
            out.append('\\"')
        elif ch == "\\":
            out.append("\\\\")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif code < 0x20 or code == 0x7F:
            out.append(f"\\u{code:04X}")
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def read_registry(root):
    path = root / "installed.toml"
    if not path.exists():
        return []
    with open(path, "rb") as f:
        table = tomllib.load(f)
    rows = []
    for row in table.get("mods", []):
        manifest = json.loads(row["manifest"])
        if manifest.get("id") != row.get("id") or manifest.get("version") != row.get("version"):
            raise ToolError("installed.toml is inconsistent; open the launcher once to repair it")
        rows.append({"id": row["id"], "version": row["version"], "enabled": bool(row.get("enabled", False)),
                     "raw": row["manifest"], "manifest": manifest})
    return rows


def write_registry(root, rows):
    lines = ["schema = 1", f"generation = {toml_string('state-mksmk-' + str(int(time.time() * 1000)))}"]
    if not rows:
        lines.append("mods = []")
    else:
        lines.append("mods = [")
        for row in rows:
            lines.append("  { " + ", ".join([
                f"id = {toml_string(row['id'])}",
                f"version = {toml_string(row['version'])}",
                f"enabled = {'true' if row['enabled'] else 'false'}",
                f"manifest = {toml_string(row['raw'])}"]) + " },")
        lines.append("]")
    text = "\n".join(lines) + "\n"
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", newline="\n", dir=root, delete=False,
                                     prefix=".installed-", suffix=".toml") as f:
        f.write(text)
        temp = Path(f.name)
    with open(temp, "rb") as f:          # make sure what we wrote parses back identically
        check = tomllib.load(f)
    if len(check.get("mods", [])) != len(rows) or any(
            a["manifest"] != b["raw"] for a, b in zip(check.get("mods", []), rows)):
        temp.unlink()
        raise ToolError("internal error: registry did not round-trip; nothing was changed")
    os.replace(temp, root / "installed.toml")


def safe_relative(path):
    p = PurePosixPath(path)
    return path and not p.is_absolute() and ".." not in p.parts and "\\" not in path and ":" not in path


# ---------------------------------------------------------------- packages
def version_key(text):
    return tuple(int(x) if x.isdigit() else 0 for x in re.split(r"[.\-+]", text))


def inspect(archive):
    """Read and verify a package like the launcher's InspectPackage."""
    with open(archive, "rb") as f:
        data = lzma.decompress(f.read())
    members = {}
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        for m in tar.getmembers():
            if m.isdir():
                continue
            if not m.isfile() or not safe_relative(m.name):
                raise ToolError(f"{archive.name}: unsafe entry {m.name}")
            members[m.name] = tar.extractfile(m).read()
    if "manifest.json" in members:
        raise ToolError(f"{archive.name}: legacy manifest.json packages aren't supported by this tool")
    if "mod.json" not in members:
        raise ToolError(f"{archive.name}: no mod.json")
    raw = members["mod.json"].decode("utf-8")
    m = json.loads(raw)
    if m.get("schema") not in (1, 2) or m.get("game", {}).get("xbe_sha256") != GAME_SHA:
        raise ToolError(f"{archive.name}: built for a different game version")
    if version_key(m.get("recomp", "0")) > version_key(RECOMP_VERSION):
        raise ToolError(f"{archive.name}: needs a newer Shaolin Monks Recomp")
    if m.get("patches"):
        raise ToolError(f"{archive.name}: has xdelta patches; install it with the launcher instead")
    install_dir = m.get("install_dir", "")
    if not safe_relative(install_dir) or not (install_dir.startswith("packages/") or install_dir.startswith("languages/")):
        raise ToolError(f"{archive.name}: invalid install_dir")
    expected = {"mod.json"}
    for f in m.get("files", []):
        data = members.get(f["path"])
        if data is None or len(data) != f["size"] or hashlib.sha256(data).hexdigest() != f["sha256"]:
            raise ToolError(f"{archive.name}: file failed SHA-256 verification: {f['path']}")
        expected.add(f["path"])
    extra = set(members) - expected
    if extra:
        raise ToolError(f"{archive.name}: undeclared files: {', '.join(sorted(extra))}")
    for script in m.get("routines", []):
        if not (script.startswith("scripts/") and script.endswith(".lua")) or script not in expected:
            raise ToolError(f"{archive.name}: routine {script} is not a declared scripts/*.lua file")
    return {"manifest": m, "raw": raw, "files": {p: members[p] for p in expected if p != "mod.json"}}


def find_packages(source):
    """Newest .tar.xz per mod id under `source`."""
    archives = []
    if (source / "dist").is_dir():
        archives = list((source / "dist").glob("*.tar.xz"))
    else:
        archives = list(source.glob("*/dist/*.tar.xz")) + list(source.glob("*.tar.xz"))
    newest = {}
    problems = []
    for archive in sorted(archives):
        try:
            package = inspect(archive)
        except ToolError as e:
            problems.append(str(e))
            continue
        except Exception as e:  # corrupt archive etc.
            problems.append(f"{archive.name}: {e}")
            continue
        mid = package["manifest"]["id"]
        if mid not in newest or version_key(package["manifest"]["version"]) > version_key(newest[mid]["manifest"]["version"]):
            package["archive"] = archive
            newest[mid] = package
    return newest, problems


# ---------------------------------------------------------------- operations
class Session:
    def __init__(self, data):
        self.root = data / "mods"
        if not self.root.is_dir():
            raise ToolError(f"No mods folder at {self.root}. Open the launcher once, or pass --data.")
        if game_running():
            raise ToolError("Close Shaolin Monks Recomp (launcher and game) first.")
        if (self.root / "transaction.toml").exists():
            raise ToolError("The launcher has an unfinished mod operation. Open and close the launcher once, then retry.")
        self.rows = read_registry(self.root)
        self.backup = self.root / ".mksmk-backup" / time.strftime("%Y%m%d-%H%M%S")
        self.changed = False

    def stash(self, install_dir):
        folder = self.root / install_dir
        if folder.exists():
            target = self.backup / install_dir
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(folder), str(target))

    def save(self):
        if not self.changed:
            return
        self.backup.mkdir(parents=True, exist_ok=True)
        registry = self.root / "installed.toml"
        if registry.exists() and not (self.backup / "installed.toml").exists():
            shutil.copy2(registry, self.backup / "installed.toml")
        write_registry(self.root, self.rows)
        prune_backups(self.root / ".mksmk-backup")

    def uninstall_all(self):
        keep, removed = [], []
        if self.rows:
            self.backup.mkdir(parents=True, exist_ok=True)
            shutil.copy2(self.root / "installed.toml", self.backup / "installed.toml")
        for row in self.rows:
            if row["manifest"].get("type") == "language":
                keep.append(row)
                continue
            self.stash(row["manifest"]["install_dir"])
            removed.append(f"{row['manifest'].get('name', row['id'])} {row['version']}")
            self.changed = True
        self.rows = keep
        return removed

    def install(self, package, enabled=True):
        m = package["manifest"]
        existing = next((r for r in self.rows if r["id"] == m["id"]), None)
        if existing and existing["manifest"]["install_dir"] != m["install_dir"]:
            raise ToolError(f"{m['id']}: an update must keep its installation folder")
        for r in self.rows:
            if r["id"] != m["id"]:
                a, b = r["manifest"]["install_dir"].rstrip("/") + "/", m["install_dir"].rstrip("/") + "/"
                if a.startswith(b) or b.startswith(a):
                    raise ToolError(f"{m['id']}: installation folder overlaps {r['id']}")
        if self.root.joinpath(m["install_dir"]).exists() and not existing:
            self.stash(m["install_dir"])      # unregistered leftover folder
        stage = Path(tempfile.mkdtemp(prefix=".mksmk-install-", dir=self.root))
        try:
            for path, data in package["files"].items():
                target = stage / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
                if hashlib.sha256(target.read_bytes()).hexdigest() != hashlib.sha256(data).hexdigest():
                    raise ToolError(f"{m['id']}: write verification failed for {path}")
            (stage / "mod.json").write_text(package["raw"], encoding="utf-8", newline="")
            if existing:
                self.stash(m["install_dir"])
            destination = self.root / m["install_dir"]
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(stage), str(destination))
        finally:
            if stage.exists():
                shutil.rmtree(stage, ignore_errors=True)
        row = {"id": m["id"], "version": m["version"], "raw": package["raw"], "manifest": m,
               "enabled": existing["enabled"] if existing else enabled}
        if existing:
            self.rows[self.rows.index(existing)] = row
        else:
            self.rows.append(row)
        self.changed = True
        return row

    def resolve_conflicts(self, newcomers):
        notes = []
        enabled = {r["id"]: r for r in self.rows if r["enabled"]}
        for row in self.rows:
            if not row["enabled"]:
                continue
            m = row["manifest"]
            clash = [c for c in m.get("conflicts", []) if c in enabled and c != row["id"]]
            clash += [r["id"] for r in enabled.values() if row["id"] in r["manifest"].get("conflicts", [])]
            missing = [d["id"] for d in m.get("dependencies", []) if d["id"] not in enabled]
            if (clash or missing) and row["id"] in newcomers:
                row["enabled"] = False
                enabled.pop(row["id"], None)
                why = f"conflicts with {', '.join(sorted(set(clash)))}" if clash else f"needs {', '.join(missing)}"
                notes.append(f"{m.get('name', row['id'])} installed but left disabled ({why}).")
        return notes


def prune_backups(folder, keep=5):
    if not folder.is_dir():
        return
    old = sorted(p for p in folder.iterdir() if p.is_dir())[:-keep]
    for p in old:
        shutil.rmtree(p, ignore_errors=True)


def describe(rows):
    if not rows:
        return "  (no mods installed)"
    return "\n".join(f"  [{'x' if r['enabled'] else ' '}] {r['manifest'].get('name', r['id'])} {r['version']}" for r in rows)


def main(argv):
    args = argv[1:]
    def take(flag):
        if flag in args:
            i = args.index(flag)
            value = args[i + 1] if i + 1 < len(args) else ""
            del args[i:i + 2]
            return value
        return None
    data = take("--data")
    skip_text = take("--skip")
    ldk_choice = (take("--ldk") or "x3").lower()
    if ldk_choice not in LDK_VARIANTS.values():
        raise ToolError("--ldk must be x2, x3 or x4")
    shuffle_choice = (take("--shuffle") or "normal").lower()
    if shuffle_choice not in SHUFFLE_VARIANTS.values():
        raise ToolError("--shuffle must be normal, wild or chaos")
    with_probe = "--with-probe" in args
    if with_probe:
        args.remove("--with-probe")
    skip = set(filter(None, (skip_text or "").split(",")))
    skip.add("ldk_bosses")            # retired: Boss Invasion is part of LDK 3.x
    if not with_probe:
        skip.add("mksmk_probe")
    if not args:                      # no command: help, never an implicit refresh/uninstall
        print(__doc__)
        return 2
    command = args[0]

    session = Session(data_folder(data))
    print(f"Mods folder: {session.root}")
    if command == "list":
        print(describe(session.rows))
        return 0
    if command not in ("refresh", "uninstall-all", "install"):
        print(__doc__)
        return 2

    notes = []
    if command in ("refresh", "uninstall-all"):
        removed = session.uninstall_all()
        print("Uninstalled:" if removed else "Nothing to uninstall.")
        for line in removed:
            print("  - " + line)
    if command in ("refresh", "install"):
        packages, problems = {}, []
        for source in [Path(a) for a in args[1:]] or [DEFAULT_SOURCE]:
            found, trouble = find_packages(source.resolve())
            packages.update(found)        # a later folder wins for the same mod
            problems += trouble
        for problem in problems:
            print("  skipped: " + problem)
        newcomers = set()
        offered = {mid for mid in packages if mid not in skip}

        def available(choice, variants, preferred):
            # release/v1 ships one LDK variant (x3); fall back to what is there
            present = [level for mid, level in variants.items() if mid in offered]
            if not present or choice in present:
                return choice
            pick = preferred if preferred in present else present[0]
            notes.append(f"{choice} is not in this folder; enabling {pick}")
            return pick
        ldk_level = available(ldk_choice, LDK_VARIANTS, "x3")
        shuffle_level = available(shuffle_choice, SHUFFLE_VARIANTS, "normal")
        for mid, package in sorted(packages.items()):
            if mid in skip:
                continue
            enabled = ((mid not in LDK_VARIANTS or LDK_VARIANTS[mid] == ldk_level)
                       and (mid not in SHUFFLE_VARIANTS or SHUFFLE_VARIANTS[mid] == shuffle_level))
            row = session.install(package, enabled=enabled)
            newcomers.add(mid)
            print(f"Installed {package['manifest'].get('name', mid)} {row['version']} ({package['archive'].name})")
        notes += session.resolve_conflicts(newcomers)
    session.save()
    for note in notes:
        print("Note: " + note)
    print("\nNow installed:")
    print(describe(session.rows))
    if session.changed:
        print(f"\nRemoved/replaced files were moved to {session.backup}")
    return 0


if __name__ == "__main__":
    try:
        code = main(sys.argv)
    except ToolError as e:
        print("Error: " + str(e))
        code = 1
    sys.exit(code)
