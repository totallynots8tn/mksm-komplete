# MKSM Komplete+ Installer

The one-click installer for players. In the release zip it is
**MKSM Komplete Installer.exe** next to a `packages` folder: close the game,
run it, press **Install**, then **Play**. No Python needed. Every mod is
ticked; untick any you don't want. **Uninstall all** removes every mod
(language packs stay). It refuses while the game or launcher is running.
**Play** starts `ShaolinMonksRecomp.exe` from the folder the newest Recomp
log names, so it appears once the game has been started at least once.

From the source folder, **MKSM Komplete Installer** also runs as
`pyw -3 tools/installer/mksmk_installer.pyw` (Python 3.11+), reading
`release/v1`.

Build the release downloads (the .exe, the player zip without the probe, and
the contributor-tools zip with the probe and QA tools) with:

    pip install pyinstaller
    python tools/installer/build_release.py

They land in `release/dist/`. The .exe isn't code-signed, so Windows
SmartScreen may warn on first run.

It installs exactly like `mods/_build/modtool.py`, which does the same SHA-256
checks as the launcher's "Install from file...". Removed mods are moved to
`mods\.mksmk-backup\<time>\` instead of being deleted. It reads packages
from a `packages` folder next to the installer if there is one (for a
download zip), otherwise from `release/v1`.

It needs Python 3.11 or newer. Players without Python can use the launcher's
**Mods > Install from file...** with the `.tar.xz` files. The long-term plan
is listing the mods in the launcher's Krypt catalog, so they install from the
Mods tab directly.
