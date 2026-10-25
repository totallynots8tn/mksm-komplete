"""MKSM Komplete+ installer: a small window over modtool, made for players.

Every mod found is ticked; press Install, then Play. It does what
"Mods - reinstall latest.bat" does: uninstall every mod (language packs are
left alone), then install and enable the ticked ones. Removed mods go to
mods\\.mksmk-backup\\<time>\\, as with modtool. A mod that ships several
variants (LDK in the dev builds) shows a level choice; one variant shows none.

Packages come from a "packages" folder next to this file (or next to the
.exe built by build_exe.py), otherwise from the project's release\\v1 folder.
Play starts ShaolinMonksRecomp.exe from the folder the newest Recomp log
names, so it works once the game has been started at least once.
"""
import os, re, sys, subprocess, tkinter as tk
from pathlib import Path
from tkinter import ttk, messagebox

FROZEN = getattr(sys, "frozen", False)          # running as the PyInstaller .exe
HERE = Path(sys.executable).resolve().parent if FROZEN else Path(__file__).resolve().parent
ROOT = HERE.parents[1] if not FROZEN else HERE
if not FROZEN:
    for candidate in (HERE, ROOT / "mods" / "_build"):
        if (candidate / "modtool.py").is_file():
            sys.path.insert(0, str(candidate))
            break
import modtool  # noqa: E402

TITLE = "MKSM Komplete+"
GROUPS = (
    ("Legendary Dark Knight", modtool.LDK_VARIANTS, ("x2", "x3", "x4")),
    ("Shaolin Shuffle", modtool.SHUFFLE_VARIANTS, ("normal", "wild", "chaos")),
)
OFF_BY_DEFAULT = {"mksmk_probe", "mk_upgrade"}
BLURBS = {      # one line per mod, in player words
    "Legendary Dark Knight": "3x the enemies in every fight",
    "Shaolin Shuffle": "enemy randomizer",
    "env_kill_xp": "hazard kills give XP",
    "coop_solo": "co-op routes and secrets in single player",
    "unlock_all": "unlock every character and extra",
    "mksmk_probe": "diagnostics for bug reports (changes nothing)",
}


def package_folder():
    for folder in (HERE / "packages", ROOT / "release" / "v1"):
        if folder.is_dir() and any(folder.glob("*.tar.xz")):
            return folder
    return None


def load_packages(folder):
    packages, problems = modtool.find_packages(folder)
    return packages, problems


def find_game(data=None):
    """ShaolinMonksRecomp.exe from the newest log's 'Path:' line, or None."""
    logs = modtool.data_folder(data) / "logs"
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
                        exe = Path(m.group(1)) / "ShaolinMonksRecomp.exe"
                        if exe.is_file():
                            return exe
        except OSError:
            continue
    return None


def plan(packages, chosen, levels):
    """[(package, enabled)] for the chosen mods. A variant group installs every
    variant it has and enables the chosen level (the others conflict)."""
    out = []
    for mid, package in sorted(packages.items()):
        group = next((g for g in GROUPS if mid in g[1]), None)
        if group:
            name, variants, _ = group
            if name not in chosen:
                continue
            out.append((package, variants[mid] == levels.get(name)))
        elif mid in chosen:
            out.append((package, True))
    return out


def apply(packages, chosen, levels, data=None):
    """Uninstall everything, install the plan. Returns (installed rows text, notes)."""
    session = modtool.Session(modtool.data_folder(data))
    session.uninstall_all()
    newcomers = set()
    for package, enabled in plan(packages, chosen, levels):
        session.install(package, enabled=enabled)
        newcomers.add(package["manifest"]["id"])
    notes = session.resolve_conflicts(newcomers)
    session.save()
    return modtool.describe(session.rows), notes


def uninstall(data=None):
    session = modtool.Session(modtool.data_folder(data))
    removed = session.uninstall_all()
    session.save()
    return removed


def installed_text(data=None):
    root = modtool.data_folder(data) / "mods"
    if not root.is_dir():
        return "Start Shaolin Monks Recomp once (so it creates its mods folder), close it, then press Install."
    try:
        rows = modtool.read_registry(root)
    except modtool.ToolError as e:
        return str(e)
    return modtool.describe(rows) or "  (no mods installed)"


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title(f"{TITLE} Installer")
        self.minsize(520, 460)
        self.folder = package_folder()
        self.packages, problems = load_packages(self.folder) if self.folder else ({}, [])
        self.checks, self.levels = {}, {}
        self.game = find_game()

        ttk.Label(self, text=TITLE, font=("Segoe UI", 20, "bold")).pack(anchor="w", padx=16, pady=(14, 0))
        ttk.Label(self, text="1. Close the game.   2. Press Install.   3. Press Play.",
                  font=("Segoe UI", 11)).pack(anchor="w", padx=16, pady=(2, 8))

        box = ttk.LabelFrame(self, text="Mods (untick any you don't want)")
        box.pack(fill="x", padx=16, pady=4)
        seen = set()
        for mid, package in sorted(self.packages.items(), key=lambda kv: kv[1]["manifest"].get("name", kv[0])):
            group = next((g for g in GROUPS if mid in g[1]), None)
            if group:
                name, variants, order = group
                if name in seen:
                    continue
                seen.add(name)
                have = [lvl for lvl in order if any(variants.get(m) == lvl for m in self.packages)]
                row = ttk.Frame(box)
                row.pack(fill="x", padx=8, pady=2)
                var = tk.BooleanVar(value=True)
                self.checks[name] = var
                label = f"{name}: {BLURBS[name]}" if name in BLURBS else name
                ttk.Checkbutton(row, text=label, variable=var).pack(side="left")
                if len(have) > 1:
                    level = tk.StringVar(value="x3" if "x3" in have else have[0])
                    self.levels[name] = level
                    for lvl in have:
                        ttk.Radiobutton(row, text=lvl, value=lvl, variable=level).pack(side="left", padx=4)
                else:
                    self.levels[name] = tk.StringVar(value=have[0] if have else "")
                continue
            var = tk.BooleanVar(value=mid not in OFF_BY_DEFAULT)
            self.checks[mid] = var
            name = package["manifest"].get("name", mid)
            label = f"{name}: {BLURBS[mid]}" if mid in BLURBS else name
            ttk.Checkbutton(box, text=label, variable=var).pack(anchor="w", padx=8, pady=2)

        style = ttk.Style(self)
        style.configure("Big.TButton", font=("Segoe UI", 13, "bold"), padding=(18, 8))
        buttons = ttk.Frame(self)
        buttons.pack(fill="x", padx=16, pady=10)
        ttk.Button(buttons, text="Install", style="Big.TButton", command=self.install).pack(side="left")
        self.play_button = ttk.Button(buttons, text="Play", style="Big.TButton", command=self.play,
                                      state="normal" if self.game else "disabled")
        self.play_button.pack(side="left", padx=10)
        ttk.Button(buttons, text="Uninstall all", command=self.remove).pack(side="right")

        self.message = ttk.Label(self, text="", font=("Segoe UI", 11, "bold"), wraplength=480)
        self.message.pack(anchor="w", padx=16)
        ttk.Label(self, text="Installed now ([x] = on):", foreground="#666").pack(anchor="w", padx=16, pady=(8, 0))
        self.status = tk.Text(self, height=8, wrap="none", font=("Consolas", 10))
        self.status.pack(fill="both", expand=True, padx=16, pady=(2, 14))
        if not self.packages:
            self.say("No mod packages found. Keep this program next to its \"packages\" folder.")
        elif not self.game:
            self.say("Tip: start Shaolin Monks Recomp once so Play can find it.")
        self.show(installed_text() + ("\n\nSkipped packages:\n" + "\n".join(problems) if problems else ""))

    def say(self, text):
        self.message.configure(text=text)

    def show(self, text):
        self.status.configure(state="normal")
        self.status.delete("1.0", "end")
        self.status.insert("1.0", text)
        self.status.configure(state="disabled")

    def chosen(self):
        return {key for key, var in self.checks.items() if var.get()}

    def run(self, action):
        self.configure(cursor="watch")
        self.update()
        try:
            return action()
        except modtool.ToolError as e:
            messagebox.showerror(TITLE, str(e))
        except Exception as e:  # keep the window alive and report
            messagebox.showerror(TITLE, f"Unexpected error: {e}")
        finally:
            self.configure(cursor="")
        return None

    def install(self):
        if not self.packages:
            messagebox.showerror(TITLE, "No mod packages found.")
            return
        levels = {name: var.get() for name, var in self.levels.items()}
        result = self.run(lambda: apply(self.packages, self.chosen(), levels))
        if result:
            text, notes = result
            self.show(text + ("\n\nNotes:\n" + "\n".join(notes) if notes else ""))
            self.game = self.game or find_game()
            if self.game:
                self.play_button.configure(state="normal")
                self.say("Installed! Press Play.")
            else:
                self.say("Installed! Start Shaolin Monks Recomp and play.")

    def play(self):
        if not self.game:
            return
        try:
            subprocess.Popen([str(self.game)], cwd=str(self.game.parent))
        except OSError as e:
            messagebox.showerror(TITLE, f"Couldn't start the game: {e}")
            return
        self.destroy()

    def remove(self):
        if not messagebox.askyesno(TITLE, "Uninstall every mod (language packs stay)?"):
            return
        if self.run(uninstall) is not None:
            self.show(installed_text())
            self.say("All mods removed.")


if __name__ == "__main__":
    App().mainloop()
