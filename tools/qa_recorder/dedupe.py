"""Shrink qa/ by hard-linking byte-identical logs and crash dumps.

Older recorder runs copied all 30 Recomp logs into every run folder, so most
files under qa/ are exact copies of each other. This keeps every path (scripts
and reports that point at qa/<run>/logs/... keep working) but makes identical
files share one copy on disk. Nothing is deleted: each duplicate is replaced
by a hard link to the first copy with the same SHA-256.

  python tools/qa_recorder/dedupe.py            report what would be linked
  python tools/qa_recorder/dedupe.py --apply    do it
"""
import argparse, hashlib, os, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
QA = ROOT / "qa"
PATTERNS = ("*.log", "*.dmp")


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apply", action="store_true", help="replace duplicates with hard links")
    args = parser.parse_args()

    files = sorted(p for pattern in PATTERNS for p in QA.rglob(pattern) if p.is_file())
    first = {}                  # sha256 -> first path
    linked = saved = already = 0
    for path in files:
        key = digest(path)
        keep = first.setdefault(key, path)
        if keep == path:
            continue
        if os.path.samefile(keep, path):
            already += 1
            continue
        size = path.stat().st_size
        if args.apply:
            tmp = path.with_name(path.name + ".dedupe-tmp")
            os.link(keep, tmp)          # link first, then swap, so a failure loses nothing
            os.replace(tmp, path)
        linked += 1
        saved += size
    verb = "linked" if args.apply else "would link"
    print(f"{len(files)} files, {len(first)} unique; {verb} {linked} duplicate(s), "
          f"{saved / 2**30:.2f} GiB; {already} already linked")
    return 0


if __name__ == "__main__":
    sys.exit(main())
