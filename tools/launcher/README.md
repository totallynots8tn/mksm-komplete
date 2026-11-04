# MKSM Komplete+ launcher

One double-click Windows app for players and testers. It replaces the old
installer window (`tools/installer`) and, for everyday use, `MKSMK.bat`'s
menu. **MKSM Komplete+ v1.3.exe** carries the whole set inside it, so it
needs no `packages` folder, no Python and no install step.

- **Play**: install or update the set, then play. Play goes straight into
  the game (`--no-launcher`) once the Recomp has a game disc registered;
  **Recomp settings** opens the Recomp's own launcher instead.
- **Mods**: a tile per mod. A tile shows the mod's details; its switch takes
  effect at once (only `installed.toml` changes). Legendary Dark Knight
  has x2, x3 and x4, and only one is on at a time. Keys: arrows move, Space
  switches, 2/3/4 pick the LDK level.
- **Tester**: routine-script budget (the Recomp won't start above 64),
  other installed mods with their switches, install from a folder (dev
  builds, another test set), QA console (when run from the project folder),
  Repair, Uninstall all, and buttons to open the mods, logs, backups and
  game folders.
- **Credits**.

## What Install/Update does

Every write goes through `mods/_build/modtool.py`: the same SHA-256 checks
as the Recomp launcher's **Install from file...**, and removed or replaced
mods are moved to `mods\.mksmk-backup\<time>\`. It refuses while the
Recomp runs. Install/Update:

- installs every mod of the set that is missing or older, or that has the
  same version but different files (all three LDK levels, the chosen one on;
  the MKSMK Probe installed but off);
- keeps the switches of mods that are already installed;
- keeps a newer build of a set mod (**Repair** puts the set's back);
- removes retired ids (`ldk_bosses`, `randomizer_wild`, `randomizer_chaos`);
- leaves everything else alone: language packs, dev diagnostics, other
  people's mods.

A newer package in a `packages` folder next to the .exe replaces the
bundled one (a hotfix without a new .exe). An older one is ignored, so an
old installer's `packages` folder can't downgrade the set.

## Build

    py -3 -m pip install pyinstaller pillow
    py -3 tools/launcher/build_exe.py            (newest release/v1.x; or pass a release folder)

This writes `release/dist/MKSM Komplete+ v1.3.exe`, which isn't committed;
attach it to the GitHub release. The frozen sets ship only LDK x3. The build
makes x2 and x4 with `mods/_build/build.py` in a clean temp copy (LF line
endings, as the repository stores them). It bundles them only if the x3 it
builds there is byte-identical to the frozen one. It also checks every
package against the release's `SHA256SUMS.txt`. The .exe isn't code-signed,
so SmartScreen may warn on first run ("More info" > "Run anyway").

## From the project folder

    pyw -3 tools/launcher/mksmk_launcher.pyw     (or MKSMK.bat > 8)

It reads the newest `release/v1.x`, plus LDK x2/x4 from `mods\ldk*\dist`
when those have the same version as the release's x3.

Options (the .exe takes them too):

    --data <folder>    the Recomp's data folder, if it isn't %LOCALAPPDATA%\Shaolin Monks Recomp
    --page <name>      open on play, mods, tester or credits
    --install          no window: Install/Update the set and print what changed
    --report <file>    with --install: also write that to a file (the .exe has no console)

## Files

- `mksmk_launcher.pyw`: the window (Tk).
- `launcher_core.py`: what ships, what's installed, Install/Update and the
  switches. No window, so it can be tested.
- `launcher_art.py`: the art, all drawn by code with Pillow (no game assets).
- `build_exe.py`: the .exe build.
- `test_launcher_core.py`: tests against throwaway data folders.
  Run them with `py -3 -m unittest discover -s tools/launcher -p "test_*.py"`.
