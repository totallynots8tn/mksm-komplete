"""MKSMK QA Console: one window for a playtest.

  python tools/qa_console/qa_console.py        (or double-click "QA - console.bat")

- Recording: keeps every save.dat version, game log and crash dump in
  qa/<run>/ while you play (the same recorder as "QA - start recorder.bat").
- Live game state: XP, health, meter, EX flags, health upgrades, loaded enemy
  types, the spawner, fatality counters, read from the running game twice a
  second. Script errors from any mod show up here as they happen.
- Mark a moment: type what you saw (a bug, a soft-lock, "bought Energy") and
  press Enter. It goes to qa/<run>/notes.md with the live state at that moment.
- Find a value: record 3 seconds of idle, do one thing in game, press Step.
  Every value that changed is listed (qa/<run>/diff.txt).
- Build summary: qa/<run>/summary.md, the short file Claude reads afterwards.
  It is also built when you stop recording.

Read-only towards the game: it never writes game memory or game files.
"""
import os, queue, re, struct, sys, threading, time, tkinter as tk
from datetime import datetime
from pathlib import Path
from tkinter import scrolledtext, ttk

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path[:0] = [str(HERE), str(ROOT / "tools" / "livemem"), str(ROOT / "tools" / "qa_recorder")]
import peek  # noqa: E402
import diff as livediff  # noqa: E402
import record  # noqa: E402
import summary  # noqa: E402

DATA = Path(os.environ.get("LOCALAPPDATA", "")) / "Shaolin Monks Recomp"
GAME_MANAGER, FRAME, MAP = 0x5ACEBC, 0x5CE878, 0x505970
CHAR_TABLE, CHAR_STRIDE = 0x5D1AB8, 0x3238
LOADED_TYPES, SPAWNER = 0x6CA69C, 0x6DBFB0
FAT_FOUND, FAT_DONE, MENU_PLAYER = 0x4DFC1C, 0x4DF5D8, 0x4EFA60
PROBE = ("SAVESTAT", "HEARTBEAT", "SAVEDIFF", "EVENTS", "SHUFFLE", "PLATE", "UPGRADE", "PROBE", "TRACE")


def plausible(p):
    return p >= 0x10000 and p % 4 == 0 and (p < 0x7FFE0000 or 0x80000000 <= p < 0x84000000)


def f32(addr):
    return struct.unpack("<f", peek.rd(addr, 4))[0]


def live_state():
    """Text lines describing the running game; raises if it isn't running."""
    u32, u8, u16 = peek.u32, peek.u8, peek.u16
    mgr = u32(GAME_MANAGER)
    lines = [f"frame {u32(FRAME)}   map {u32(MAP)}   menu player {u32(MENU_PLAYER)}"]
    if not plausible(mgr):
        return lines + ["(no game in progress)"]
    lines[0] += f"   mode {u32(mgr + 0x88)}"
    lines.append(f"health upgrades {u32(mgr + 0xE0)}   max health {u32(mgr + 0x94)}   "
                 f"area health level {u32(mgr + 0x90)}   fatalities found/done "
                 f"{u32(FAT_FOUND)}/{u32(FAT_DONE)}")
    for p in range(2):
        slots = mgr + 0x1C4 + p * 0x1C
        actor = u32(CHAR_TABLE + p * CHAR_STRIDE + 0x200)
        hp = f"{u32(actor + 0x368)}/{u32(actor + 0x370)}" if plausible(actor) else "-"
        ex = "".join(str(u8(slots + s)) for s in range(19, 23))
        specials = " ".join(str(u8(slots + s)) for s in range(4))
        lines.append(f"P{p + 1}  char {u32(mgr + 0xCC + p * 4)}  xp {u32(mgr + 0x4940 + p * 0x50)}  hp {hp}  "
                     f"fatality meter {f32(mgr + 0x4954 + p * 0x50):.0f} lvl {u32(mgr + 0x4978 + p * 0x50)}  "
                     f"EX {ex}  specials {specials}")
    types = [f"{t:X}" for t in (u32(LOADED_TYPES + i * 4) for i in range(6)) if t != 0xFFFFFFFF]
    lines.append(f"loaded enemy types {','.join(types) or '-'}   spawner active {u8(SPAWNER + 0x2092A)} "
                 f"group {u16(SPAWNER + 0x20920)} spawned {u16(SPAWNER + 0x20922)}")
    return lines


class LogWatch:
    """Follows the newest game log: routine-script count and non-probe script errors."""
    def __init__(self):
        self.path, self.pos, self.scripts, self.errors = None, 0, "?", []

    def poll(self):
        logs = sorted((DATA / "logs").glob("*.log"), key=lambda p: p.stat().st_mtime) if (DATA / "logs").is_dir() else []
        if not logs:
            return []
        if logs[-1] != self.path:
            self.path, self.pos, self.scripts, self.errors = logs[-1], 0, "?", []
        new = []
        try:
            with open(self.path, encoding="utf-8", errors="replace") as f:
                f.seek(self.pos)
                chunk = f.read()
                self.pos = f.tell()
        except OSError:
            return []
        for line in chunk.splitlines():
            m = re.search(r"Mods: (\d+) routine scripts active", line)
            if m:
                self.scripts = m.group(1)
            m = re.search(r"Mod routine: ([\w.-]+): (.*)", line)
            if m and not m.group(2).startswith(PROBE):
                self.errors.append(f"{m.group(1)}: {m.group(2)[:200]}")
                new.append(self.errors[-1])
            elif m:
                new.append(f"probe report: {m.group(2)[:90]}...")
        return new


class Console:
    def __init__(self, root):
        self.root = root
        self.messages = queue.Queue()
        self.run_dir = None
        self.recorder = None
        self.recording = False
        self.logwatch = LogWatch()
        self.noise, self.baseline, self.steps = None, None, 0
        root.title("MKSMK QA Console")
        root.geometry("820x760")
        self.build()
        self.tick()

    # ---------- layout ----------
    def build(self):
        pad = {"padx": 6, "pady": 3}
        top = ttk.Frame(self.root); top.pack(fill="x", **pad)
        self.status = ttk.Label(top, text="", font=("Segoe UI", 10, "bold"))
        self.status.pack(side="left")
        self.on_top = tk.BooleanVar(value=False)
        ttk.Checkbutton(top, text="Keep on top", variable=self.on_top,
                        command=lambda: self.root.attributes("-topmost", self.on_top.get())).pack(side="right")

        rec = ttk.LabelFrame(self.root, text="Recording (saves, logs, crash dumps)"); rec.pack(fill="x", **pad)
        ttk.Label(rec, text="Run name").pack(side="left", padx=4)
        self.run_name = tk.StringVar(value=datetime.now().strftime("run-%Y%m%d-%H%M"))
        ttk.Entry(rec, textvariable=self.run_name, width=22).pack(side="left")
        self.rec_button = ttk.Button(rec, text="Start recording", command=self.toggle_recording)
        self.rec_button.pack(side="left", padx=6)
        self.rec_info = ttk.Label(rec, text="not recording")
        self.rec_info.pack(side="left", padx=6)

        live = ttk.LabelFrame(self.root, text="Live game state"); live.pack(fill="x", **pad)
        self.live = tk.Text(live, height=7, font=("Consolas", 10), state="disabled", wrap="none")
        self.live.pack(fill="x", padx=4, pady=4)

        mark = ttk.LabelFrame(self.root, text="Mark a moment (what you saw; Enter saves it with the live state)")
        mark.pack(fill="x", **pad)
        self.mark_text = tk.StringVar()
        entry = ttk.Entry(mark, textvariable=self.mark_text)
        entry.pack(side="left", fill="x", expand=True, padx=4, pady=4)
        entry.bind("<Return>", lambda e: self.mark())
        ttk.Button(mark, text="Mark", command=self.mark).pack(side="left", padx=4)

        find = ttk.LabelFrame(self.root, text="Find a value: record idle, do ONE thing in game, then Step")
        find.pack(fill="x", **pad)
        self.idle_button = ttk.Button(find, text="1. Record idle (3 s, hands off)", command=self.record_idle)
        self.idle_button.pack(side="left", padx=4, pady=4)
        ttk.Label(find, text="label").pack(side="left")
        self.step_label = tk.StringVar(value="special")
        ttk.Entry(find, textvariable=self.step_label, width=16).pack(side="left", padx=4)
        self.step_button = ttk.Button(find, text="2. Step", command=self.step, state="disabled")
        self.step_button.pack(side="left", padx=4)
        self.trace_button = ttk.Button(find, text="Trace (3 s still, then 10 s of action)", command=self.trace)
        self.trace_button.pack(side="left", padx=8)

        bottom = ttk.Frame(self.root); bottom.pack(fill="x", **pad)
        ttk.Button(bottom, text="Build summary", command=self.build_summary).pack(side="left")
        ttk.Button(bottom, text="Open run folder", command=self.open_run).pack(side="left", padx=6)

        self.log = scrolledtext.ScrolledText(self.root, font=("Consolas", 9), state="disabled")
        self.log.pack(fill="both", expand=True, **pad)

    # ---------- helpers ----------
    def say(self, text):
        self.messages.put(f"[{datetime.now():%H:%M:%S}] {text}")

    def ensure_run(self):
        if self.run_dir is None:
            name = self.run_name.get().strip() or datetime.now().strftime("run-%Y%m%d-%H%M")
            if not re.fullmatch(r"[A-Za-z0-9._\-]+", name):
                name = datetime.now().strftime("run-%Y%m%d-%H%M")
            self.run_dir = ROOT / "qa" / name
            for sub in ("saves", "logs", "crashes"):
                (self.run_dir / sub).mkdir(parents=True, exist_ok=True)
        return self.run_dir

    def write_live(self, lines):
        self.live.configure(state="normal")
        self.live.delete("1.0", "end")
        self.live.insert("end", "\n".join(lines))
        self.live.configure(state="disabled")

    # ---------- periodic ----------
    def tick(self):
        try:
            lines = live_state()
            game = "game running"
        except BaseException:          # not running, or restarted: reopen next time
            peek._read = None
            lines, game = ["The game isn't running."], "game not running"
        for msg in self.logwatch.poll():
            self.say(msg if msg.startswith("probe report") else "SCRIPT ERROR " + msg)
        errors = len(self.logwatch.errors)
        self.status.configure(text=f"{game}   |   {self.logwatch.scripts} routine scripts   |   "
                                   f"script errors: {errors}", foreground="red" if errors else "black")
        self.write_live(lines)
        while not self.messages.empty():
            self.log.configure(state="normal")
            self.log.insert("end", self.messages.get() + "\n")
            self.log.see("end")
            self.log.configure(state="disabled")
        if self.recorder:
            self.rec_info.configure(text=f"{self.recorder.saves} save(s) archived in qa/{self.run_dir.name}"
                                    + ("" if self.recording else " (stopped)"))
        self.root.after(500, self.tick)

    # ---------- recording ----------
    def toggle_recording(self):
        if self.recording:
            self.recording = False
            self.rec_button.configure(text="Start recording")
            return
        run = self.ensure_run()
        record.print = lambda *a, **k: self.say(" ".join(str(x) for x in a))
        self.recorder = record.Recorder(run.name)
        self.recording = True
        self.rec_button.configure(text="Stop recording")
        threading.Thread(target=self.record_loop, daemon=True).start()

    def record_loop(self):
        rec = self.recorder
        self.say(f"Recording to {rec.dir} (skipped {rec.skip_existing()} older log(s))")
        rec.check_saves()
        rec.sync_logs(force=True)
        while self.recording:
            time.sleep(record.POLL)
            try:
                rec.check_saves()
                rec.sync_logs()
            except Exception as e:      # keep recording through a locked file
                self.say(f"recorder: {e}")
        rec.sync_logs(force=True)
        self.say(f"Stopped. {rec.saves} save(s) archived.")
        self.build_summary()

    # ---------- markers ----------
    def mark(self):
        text = self.mark_text.get().strip()
        if not text:
            return
        run = self.ensure_run()
        try:
            lines = live_state()
        except BaseException:
            peek._read = None
            lines = ["(game not running)"]
        with open(run / "notes.md", "a", encoding="utf-8") as f:
            f.write(f"- **{datetime.now():%H:%M:%S}** {text}\n" + "".join(f"  - `{l}`\n" for l in lines))
        self.mark_text.set("")
        self.say(f"marked: {text}")

    # ---------- diff ----------
    def record_idle(self):
        try:
            first = livediff.snapshot([])
        except BaseException:
            peek._read = None
            self.say("Find a value: the game isn't running.")
            return
        self.noise = set()
        self.idle_button.configure(state="disabled")
        self.step_button.configure(state="disabled")
        self.say("Recording idle noise: hands off for 3 seconds...")

        def sample(left):
            snap = livediff.snapshot([])
            self.noise |= set(livediff.changes(first, snap))
            if left > 1:
                self.root.after(1000, sample, left - 1)
            else:
                self.baseline = snap
                self.idle_button.configure(state="normal")
                self.step_button.configure(state="normal")
                self.say(f"{len(self.noise)} values change on their own and are ignored. "
                         "Now do ONE thing in game, then press Step.")
        self.root.after(1000, sample, 3)

    def step(self):
        run = self.ensure_run()
        try:
            now = livediff.snapshot([])
        except BaseException:
            peek._read = None
            self.say("Find a value: the game isn't running.")
            return
        self.steps += 1
        changed = {k: v for k, v in livediff.changes(self.baseline, now).items() if k not in self.noise}
        label = self.step_label.get().strip() or "(no label)"
        lines = [f"== step {self.steps}: {label} - {len(changed)} changed"]
        for (region, off), (addr, old, new) in sorted(changed.items()):
            lines.append(f"  {region:>11} +{off:04X} @{addr:08X}  {livediff.describe(old)} -> {livediff.describe(new)}")
        with open(run / "diff.txt", "a", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        for line in lines[:40]:
            self.say(line)
        if len(lines) > 40:
            self.say(f"  ... {len(lines) - 40} more in diff.txt")
        self.baseline = now

    def trace(self):
        """For meters that refill within seconds: samples 10x a second and ranks
        values that drop and climb back (qa/<run>/trace.txt)."""
        run = self.ensure_run()
        label = self.step_label.get().strip() or "(no label)"
        self.trace_button.configure(state="disabled")
        self.say(f"Trace '{label}': hands off for 3 seconds...")

        def work():
            try:
                lines = livediff.trace(on_go=lambda: self.say("GO: do it now, for 10 seconds (e.g. throw specials)"))
            except BaseException as e:
                peek._read = None
                lines = [f"trace failed: {e} (is the game running?)"]
            with open(run / "trace.txt", "a", encoding="utf-8") as f:
                f.write(f"# {datetime.now():%H:%M:%S} {label}\n" + "\n".join(lines) + "\n")
            for line in lines[:25]:
                self.say(line)
            self.say("Trace done: saved to trace.txt")
            self.root.after(0, lambda: self.trace_button.configure(state="normal"))
        threading.Thread(target=work, daemon=True).start()

    # ---------- summary ----------
    def build_summary(self):
        if self.run_dir is None:
            self.say("No run yet: start recording or mark a moment first.")
            return
        try:
            self.say(f"Summary written: {summary.summarize(self.run_dir)}")
        except Exception as e:
            self.say(f"summary failed: {e}")

    def open_run(self):
        os.startfile(self.ensure_run())


def main():
    root = tk.Tk()
    Console(root)
    root.mainloop()


if __name__ == "__main__":
    main()
