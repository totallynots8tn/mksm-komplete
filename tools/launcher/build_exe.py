"""Build the MKSM Komplete+ launcher: one .exe with the mod packages inside.

  py -3 -m pip install pyinstaller pillow
  py -3 tools/launcher/build_exe.py [release folder]      (default: the newest release/v1.x)

Writes release/dist/MKSM Komplete+ <set>.exe (release/dist/ isn't committed;
attach the .exe to the GitHub release). Before building it checks that:
- every package in the release folder matches its SHA256SUMS.txt;
- LDK x2 and x4 come from the same source as the frozen x3. The frozen sets
  ship only x3, so build.py makes all three levels in a clean temp copy of
  mods/_build (LF line endings, as the repository stores them), and x2/x4 are
  bundled only if that x3 is byte-identical to the frozen one.
"""
import hashlib, os, shutil, subprocess, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path[:0] = [str(HERE), str(ROOT / "mods" / "_build")]
import launcher_art as art  # noqa: E402
import launcher_core as core  # noqa: E402
import modtool  # noqa: E402

LAUNCHER = HERE / "mksmk_launcher.pyw"


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def check_sums(release):
    sums = {}
    for line in (release / "SHA256SUMS.txt").read_text(encoding="utf-8").splitlines():
        if line.strip():
            digest, name = line.split(maxsplit=1)
            sums[name.lstrip("*")] = digest
    packages = sorted(release.glob("*.tar.xz"))
    for p in packages:
        if sums.get(p.name) != sha256(p):
            sys.exit(f"{p.name} doesn't match {release.name}/SHA256SUMS.txt")
    missing = sorted(set(sums) - {p.name for p in packages})
    if missing:
        sys.exit(f"missing from {release.name}: {', '.join(missing)}")
    return packages


def ldk_variants(release, work):
    """[x2, x4] packages built from the frozen x3's source, or [] (with the reason printed)."""
    x3 = next(iter(release.glob("ldk_x3-*.tar.xz")), None)
    if x3 is None:
        print("No LDK x3 in the release: LDK x2/x4 left out.")
        return []
    version = x3.name[len("ldk_x3-"):-len(".tar.xz")]
    tree = work / "ldk-build" / "mods" / "_build"
    shutil.copytree(ROOT / "mods" / "_build" / "src", tree / "src")
    shutil.copytree(ROOT / "mods" / "_build" / "readme", tree / "readme")
    shutil.copy2(ROOT / "mods" / "_build" / "build.py", tree / "build.py")
    for path in [*(tree / "src").rglob("*"), *(tree / "readme").rglob("*")]:
        if path.is_file():
            data = path.read_bytes()
            if b"\r\n" in data:           # a Windows checkout has CRLF; the release was built from LF
                path.write_bytes(data.replace(b"\r\n", b"\n"))
    subprocess.run([sys.executable, "build.py", "ldk", "ldk_x3", "ldk_x4"], cwd=tree, check=True,
                   stdout=subprocess.DEVNULL)
    built = {m: tree.parent / m / "dist" / f"{m}-{version}.tar.xz" for m in ("ldk", "ldk_x3", "ldk_x4")}
    if not all(p.is_file() for p in built.values()):
        print(f"build.py no longer makes LDK {version}: LDK x2/x4 left out.")
        return []
    if sha256(built["ldk_x3"]) != sha256(x3):
        print(f"LDK x3 built from today's source differs from the frozen {x3.name}: LDK x2/x4 left out.")
        return []
    for m in ("ldk", "ldk_x4"):
        modtool.inspect(built[m])
    print(f"LDK x2 and x4 {version}: built from the same source as the frozen x3 (verified).")
    return [built["ldk"], built["ldk_x4"]]


VERSION_INFO = """VSVersionInfo(
  ffi=FixedFileInfo(filevers=({v}), prodvers=({v}), mask=0x3f, flags=0x0, OS=0x40004, fileType=0x1,
                    subtype=0x0, date=(0, 0)),
  kids=[
    StringFileInfo([StringTable('040904B0', [
      StringStruct('CompanyName', 'totallynots8tn'),
      StringStruct('FileDescription', 'MKSM Komplete+ launcher'),
      StringStruct('FileVersion', '{dotted}'),
      StringStruct('InternalName', 'mksmk_launcher'),
      StringStruct('LegalCopyright', 'MIT license. Unofficial fan mods; no game files included.'),
      StringStruct('OriginalFilename', '{exe}'),
      StringStruct('ProductName', 'MKSM Komplete+'),
      StringStruct('ProductVersion', '{product}')])]),
    VarFileInfo([VarStruct('Translation', [1033, 1200])])
  ]
)
"""


def launcher_version():
    for line in LAUNCHER.read_text(encoding="utf-8").splitlines():
        if line.startswith("LAUNCHER_VERSION"):
            return line.split("=", 1)[1].strip().strip('"')
    return "0.0.0"


def main():
    release = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else core.newest_release(ROOT)
    if not release or not release.is_dir():
        sys.exit("No release folder with packages.")
    packages = check_sums(release)
    title, date, _ = core.parse_readme((release / "README.txt").read_text(encoding="utf-8"))
    name = f"MKSM Komplete+ {release.name}"
    out = ROOT / "release" / "dist"
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="mksmk-launcher-") as tmp:
        work = Path(tmp)
        stage = work / "packages"
        stage.mkdir()
        for p in packages + ldk_variants(release, work):
            shutil.copy2(p, stage)
        bundle, problems = modtool.find_packages(stage)
        if problems:
            sys.exit("Package problems: " + "; ".join(problems))
        shutil.copy2(release / "README.txt", work / "README.txt")
        icon = work / "icon.ico"
        art.save_icon(icon)
        version = launcher_version()
        parts = [int(x) for x in version.split(".")] + [0] * 4
        (work / "version.txt").write_text(VERSION_INFO.format(
            v=", ".join(str(x) for x in parts[:4]), dotted=".".join(str(x) for x in parts[:4]),
            exe=f"{name}.exe", product=f"{title or release.name} (launcher {version})"), encoding="utf-8")
        subprocess.run([
            sys.executable, "-m", "PyInstaller", "--noconfirm", "--clean", "--onefile", "--windowed",
            "--name", name, "--icon", str(icon), "--version-file", str(work / "version.txt"),
            "--paths", str(HERE), "--paths", str(ROOT / "mods" / "_build"), "--hidden-import", "modtool",
            "--add-data", f"{stage}{os.pathsep}packages", "--add-data", f"{work / 'README.txt'}{os.pathsep}.",
            "--exclude-module", "unittest", "--exclude-module", "pydoc", "--exclude-module", "numpy",
            "--distpath", str(work / "dist"), "--workpath", str(work / "build"), "--specpath", str(work),
            str(LAUNCHER)], check=True)
        exe = out / f"{name}.exe"
        shutil.copy2(work / "dist" / f"{name}.exe", exe)
    print(f"\n{exe}")
    print(f"  {exe.stat().st_size / 1e6:.1f} MB, sha256 {sha256(exe)}")
    print(f"  {title or release.name}{' (' + date + ')' if date else ''}, launcher {version}")
    for mid, package in sorted(bundle.items()):
        print(f"  {package['manifest'].get('name', mid)} {package['manifest']['version']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
