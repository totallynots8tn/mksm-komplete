"""Build the player and contributor downloads for a release.

  pip install pyinstaller
  python tools/installer/build_release.py            (from the project folder)

Writes release/dist/:
  MKSM-Komplete-v1.zip                     for players: the one-click installer
                                           (.exe, no Python needed), packages/
                                           with every v1 mod except the probe,
                                           README.txt
  MKSM-Komplete-v1-contributor-tools.zip   for contributors and testers: the
                                           probe package, the QA recorder and
                                           the live-memory peek tool
The packages come from release/v1 and must match its SHA256SUMS.txt.
"""
import hashlib, os, shutil, subprocess, sys, tempfile, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
V1 = ROOT / "release" / "v1"
OUT = ROOT / "release" / "dist"
EXE_NAME = "MKSM Komplete Installer"
PROBE = "mksmk_probe"

PLAYER_README = """MKSM Komplete+ v1
=================
Free fan mods for Mortal Kombat: Shaolin Monks on Shaolin Monks Recomp.

You need: Shaolin Monks Recomp 0.2.0 or newer, set up with your own copy of
the game, started at least once.

1. Close the game.
2. Double-click "MKSM Komplete Installer.exe".
3. Press Install, then Play.

Keep the "packages" folder next to the installer. Untick any mod you don't
want. "Uninstall all" removes the mods again (language packs stay).

Windows may warn about an unknown publisher the first time, because the
installer isn't code-signed: choose "More info" > "Run anyway". If you'd
rather not run it, install each .tar.xz in packages/ yourself from the
Recomp launcher: Mods > Install from file.

Project, roadmap and support: see the GitHub page.
"""

CONTRIB_README = """MKSM Komplete+ contributor tools
================================
For testers and contributors. Players don't need any of this.

- mksmk_probe-*.tar.xz: the MKSMK Probe. Changes nothing in the game; writes
  diagnostic reports to the Recomp session log (at each statue save, plus a
  heartbeat every few minutes of play). Install it from the Recomp launcher
  (Mods > Install from file) next to the v1 mods.
- "QA - start recorder.bat": start it before the game. It keeps every
  save.dat version and the session logs in qa/run-<date>-<time>/. Stop it
  with Ctrl+C after you quit the game. Needs Python 3.11+.
- tools/livemem/peek.py: if the game soft-locks, run it while the game is
  still open to capture the spawner and enemy-memory state.

Send the run folder's logs/ (and saves/ if relevant) with a line on what
happened and where. CONTRIBUTING.md on the GitHub page has the details.
"""


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_sums():
    sums = {}
    for line in (V1 / "SHA256SUMS.txt").read_text(encoding="utf-8").splitlines():
        digest, name = line.split(maxsplit=1)
        sums[name.lstrip("*")] = digest
    packages = sorted(V1.glob("*.tar.xz"))
    for p in packages:
        if sums.get(p.name) != sha256(p):
            sys.exit(f"{p.name} doesn't match release/v1/SHA256SUMS.txt")
    return packages


def build_exe(work):
    subprocess.run([sys.executable, "-m", "PyInstaller", "--noconfirm", "--onefile", "--windowed",
                    "--name", EXE_NAME, "--paths", str(ROOT / "mods" / "_build"), "--hidden-import", "modtool",
                    "--distpath", str(work / "dist"), "--workpath", str(work / "build"),
                    "--specpath", str(work), str(ROOT / "tools" / "installer" / "mksmk_installer.pyw")],
                   check=True)
    return work / "dist" / f"{EXE_NAME}.exe"


def write_zip(path, entries):
    """entries: [(name in zip, bytes or Path)]"""
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in entries:
            if isinstance(data, Path):
                z.write(data, name)
            else:
                z.writestr(name, data)
    print(f"{path.name}: {path.stat().st_size // 1024} KiB, {len(entries)} files")


def main():
    packages = check_sums()
    players = [p for p in packages if not p.name.startswith(PROBE + "-")]
    probes = [p for p in packages if p.name.startswith(PROBE + "-")]
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        exe = build_exe(Path(tmp))
        sums = "".join(f"{sha256(p)} *{p.name}\n" for p in players)
        write_zip(OUT / "MKSM-Komplete-v1.zip",
                  [(f"{EXE_NAME}.exe", exe), ("README.txt", PLAYER_README),
                   ("packages/SHA256SUMS.txt", sums)]
                  + [(f"packages/{p.name}", p) for p in players])
    write_zip(OUT / "MKSM-Komplete-v1-contributor-tools.zip",
              [("README.txt", CONTRIB_README),
               ("QA - start recorder.bat", ROOT / "tools" / "qa_recorder" / "QA - start recorder.bat"),
               ("tools/qa_recorder/record.py", ROOT / "tools" / "qa_recorder" / "record.py"),
               ("tools/livemem/peek.py", ROOT / "tools" / "livemem" / "peek.py")]
              + [(p.name, p) for p in probes])
    return 0


if __name__ == "__main__":
    sys.exit(main())
