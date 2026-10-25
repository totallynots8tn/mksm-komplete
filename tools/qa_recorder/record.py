"""MKSMK QA recorder: keep every save.dat version and every game log.

Run it before you start the game and leave it open while you play:

  python tools/qa_recorder/record.py                 new run folder qa/run-<date>-<time>
  python tools/qa_recorder/record.py --run run1      continue/name a run folder qa/run1
  python tools/qa_recorder/record.py --once          one sync pass, then exit

Every time the game writes save.dat, a timestamped copy goes to qa/<run>/saves/
and a line goes to qa/<run>/index.csv (time, size, SHA-256, the save slots'
"CHARACTER.MAP.PLAYTIME" labels). Game logs (Recomp keeps only the newest 30)
and crash dumps written after the recorder starts are copied to qa/<run>/logs/
and qa/<run>/crashes/ as they change (--all-logs also copies older ones). The game's own folders are only read, never written. Stop with Ctrl+C.
"""
import argparse, csv, hashlib, os, re, shutil, sys, time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = Path(os.environ.get("LOCALAPPDATA", "")) / "Shaolin Monks Recomp"
SAVES = Path(os.environ.get("USERPROFILE", "")) / "Saved Games" / "Shaolin Monks" / "hdd"
LABEL = re.compile(rb"[A-Z][A-Z \-]{1,20}\.\d{3}\.\d\d:\d\d:\d\d")
POLL = 2.0          # seconds between checks
SETTLE = 1.5        # a file must be unchanged this long before it is copied
LOG_EVERY = 10.0    # seconds between log syncs


def stamp():
    return datetime.now().strftime("%H:%M:%S")


def state(path):
    try:
        st = path.stat()
        return (st.st_size, st.st_mtime_ns)
    except OSError:
        return None


def settled(path):
    first = state(path)
    if first is None:
        return False
    time.sleep(SETTLE)
    return state(path) == first


class Recorder:
    def __init__(self, run):
        self.dir = ROOT / "qa" / run
        for sub in ("saves", "logs", "crashes"):
            (self.dir / sub).mkdir(parents=True, exist_ok=True)
        self.index = self.dir / "index.csv"
        if not self.index.exists():
            with open(self.index, "w", newline="", encoding="utf-8") as f:
                csv.writer(f).writerow(["time", "archived_as", "source", "size", "sha256", "slots"])
        self.seen = {}          # path -> (size, mtime) last handled
        self.last_hash = {}     # save path -> sha256 of the last archived copy
        self.saves = 0
        self.last_log_sync = 0.0
        self.known = set()          # log/dump names already announced

    def save_files(self):
        # the live saves only: Recomp's own .backups copies are skipped
        if not SAVES.is_dir():
            return []
        return sorted(p for p in SAVES.glob("**/save.dat")
                      if not any(part.startswith(".") for part in p.relative_to(SAVES).parts))

    def check_saves(self):
        for path in self.save_files():
            now = state(path)
            if now is None or self.seen.get(path) == now:
                continue
            if not settled(path):
                continue
            try:
                data = path.read_bytes()
            except OSError:
                continue            # locked while the game writes it; next pass
            digest = hashlib.sha256(data).hexdigest()
            self.seen[path] = state(path)
            if self.last_hash.get(path) == digest:
                continue
            self.last_hash[path] = digest
            name = f"save_{datetime.now().strftime('%Y%m%d-%H%M%S')}.dat"
            (self.dir / "saves" / name).write_bytes(data)
            slots = sorted({m.group().decode("ascii") for m in LABEL.finditer(data)})
            with open(self.index, "a", newline="", encoding="utf-8") as f:
                csv.writer(f).writerow([datetime.now().isoformat(timespec="seconds"), name,
                                        str(path.relative_to(SAVES)), len(data), digest, " | ".join(slots)])
            self.saves += 1
            print(f"[{stamp()}] save #{self.saves} archived as {name}  ({', '.join(slots) or 'no slot labels'})")

    def sync_folder(self, source, target, pattern):
        copied, new = 0, []
        if not source.is_dir():
            return 0, []
        for path in sorted(source.glob(pattern)):
            now = state(path)
            if now is None or self.seen.get(path) == now:
                continue
            try:
                shutil.copy2(path, target / path.name)
            except OSError:
                continue            # the game may be writing it; next pass
            self.seen[path] = now
            copied += 1
            if path.name not in self.known:
                self.known.add(path.name)
                new.append(path.name)
        return copied, new

    def sync_logs(self, force=False):
        if not force and time.time() - self.last_log_sync < LOG_EVERY:
            return
        self.last_log_sync = time.time()
        logs, new_logs = self.sync_folder(DATA / "logs", self.dir / "logs", "*.log")
        dumps, new_dumps = self.sync_folder(DATA / "crashes", self.dir / "crashes", "*.dmp")
        if force and (logs or dumps):
            print(f"[{stamp()}] synced {logs} log(s), {dumps} crash dump(s)")
        elif new_logs or new_dumps:
            # the active log is copied every pass; only new files are announced
            print(f"[{stamp()}] new: {', '.join(new_logs + new_dumps)}")

    def skip_existing(self):
        # logs and dumps from earlier sessions are already in earlier run
        # folders; copying all 30 into every run filled qa/ with duplicates.
        # Only files that change after the recorder starts are copied.
        skipped = 0
        for source, pattern in ((DATA / "logs", "*.log"), (DATA / "crashes", "*.dmp")):
            if not source.is_dir():
                continue
            for path in source.glob(pattern):
                now = state(path)
                if now is not None:
                    self.seen[path] = now
                    self.known.add(path.name)
                    skipped += 1
        return skipped

    def run(self, once, all_logs=False):
        print(f"Recording to {self.dir}")
        print(f"  saves from {SAVES}")
        print(f"  logs from  {DATA / 'logs'}")
        if not all_logs:
            print(f"  skipping {self.skip_existing()} log(s)/dump(s) from earlier sessions (--all-logs copies them)")
        # the current save is the baseline copy of this run
        self.check_saves()
        self.sync_logs(force=True)
        if once:
            return
        print("Recording. Play the game; press Ctrl+C here when you are done.")
        try:
            while True:
                time.sleep(POLL)
                self.check_saves()
                self.sync_logs()
        except KeyboardInterrupt:
            pass
        self.sync_logs(force=True)
        print(f"Stopped. {self.saves} save(s) archived in {self.dir}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--run", help="run folder name under qa/ (default: run-<date>-<time>)")
    parser.add_argument("--once", action="store_true", help="one sync pass, then exit")
    parser.add_argument("--all-logs", action="store_true",
                        help="also copy logs/dumps that existed before the recorder started")
    args = parser.parse_args()
    run = args.run or datetime.now().strftime("run-%Y%m%d-%H%M")
    if not re.fullmatch(r"[A-Za-z0-9._\-]+", run):
        print("--run may only use letters, digits, '.', '_' and '-'")
        return 2
    Recorder(run).run(args.once, args.all_logs)
    return 0


if __name__ == "__main__":
    sys.exit(main())
