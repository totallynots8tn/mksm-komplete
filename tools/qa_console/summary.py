"""Turn a QA run folder into a short summary.md: what Claude reads after a playtest.

  python tools/qa_console/summary.py [qa/run-...]      (default: the newest run)

Reads the run's logs (copied by the recorder), its index.csv (archived saves),
mods.txt (the installed mods), notes.md (markers) and diff.txt (diff steps),
and writes qa/<run>/summary.md: the mod set, session facts, every script error
that isn't a probe report, crashes, one table row per statue save (SAVESTAT),
the heartbeat timeline and the other probe reports, shortened. Read-only
apart from summary.md.
"""
import csv, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
QA = ROOT / "qa"
PROBE_REPORTS = ("SAVESTAT", "HEARTBEAT", "SAVEDIFF", "EVENTS", "SHUFFLE", "PLATE", "UPGRADE", "PROBE", "TRACE")
ROUTINE = re.compile(r"^\[\s*([\d.]+)\] \[(\w+)\] \[\w+\] Mod routine: ([\w.-]+): (.*?)(?:\. Script disabled for this session\.)?$")
FIELD = re.compile(r"(\S+?)=(\S+)")
GROUP = re.compile(r"P(\d)\[([^\]]*)\]")


def newest_run():
    runs = sorted((p for p in QA.glob("run-*") if p.is_dir()), key=lambda p: p.stat().st_mtime)
    return runs[-1] if runs else None


def parse_log(path):
    facts, routines, crashes = [], [], []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = ROUTINE.match(line)
        if m:
            routines.append((float(m.group(1)), m.group(3), m.group(4)))
        elif "routine scripts active" in line or "Save directory:" in line or "Mods ready" in line:
            facts.append(line.split("] ", 3)[-1])
        elif re.search(r"exception|crash|fatal", line, re.I) and "shaolin input" not in line:
            crashes.append(line.strip()[:200])
    return facts, routines, crashes


def level_row(text):
    """The 28 level-row bytes of a SAVESTAT row= field (Probe 0.12.3+), or None."""
    if not text or len(text) != 56:
        return None
    try:
        return [int(text[i:i + 2], 16) for i in range(0, 56, 2)]
    except ValueError:
        return None


def savestat_row(t, text):
    f = dict(FIELD.findall(text))
    groups = {p: dict(FIELD.findall(body)) for p, body in GROUP.findall(text)}
    p0, p1 = groups.get("0", {}), groups.get("1", {})
    tag = text.split()[1] if len(text.split()) > 1 else "?"
    row = level_row(p0.get("row"))
    # XP Shop EX flags (slots 19-21; 0.11.3 used 23-25), Time Rifts' beaten
    # rifts (22) and the shop levels (27); older probes report ex= instead
    ex = ("/".join(f"{b:02X}" for b in row[19:22]) + f" r{row[22]:02X} s{row[27]:02X}"
          + (" old" + "/".join(f"{b:02X}" for b in row[23:26]) if any(row[23:26]) else "")) if row else p0.get("ex", "-")
    return (f"| {tag} | {t:.0f}s | {f.get('map', '-')} | {f.get('xp', '-')} | {f.get('+E0', '-')} | "
            f"{f.get('maxhp', '-')} | {p0.get('hp', '-')} | {p0.get('mv', '-')}/{p0.get('ml', '-')} | "
            f"{ex} | {p1.get('xp', '-')} | {f.get('fat', '-')} |")


def heartbeat_line(t, text):
    head = text.split(" | ")[0]
    samples = text.split(" | ")[1:]
    last = samples[-1] if samples else ""
    return f"- {t:.0f}s {head.replace('HEARTBEAT', 'HB')}: last sample `{last[:160]}`"


def summarize(run):
    run = Path(run)
    out = [f"# QA summary: {run.name}", ""]
    mods = run / "mods.txt"
    if mods.exists():
        out += ["## Mods installed", "", mods.read_text(encoding="utf-8", errors="replace").strip(), ""]
    else:
        out += ["- Mods installed: not recorded (mods.txt starts with recorder runs of 2026-11-01)", ""]
    logs = sorted((run / "logs").glob("*.log"))
    index = run / "index.csv"
    if index.exists():
        with open(index, encoding="utf-8") as f:
            rows = list(csv.DictReader(f))
        out.append(f"- Saves archived: {len(rows)}" + (f" (last slots: {rows[-1]['slots']})" if rows else ""))
    dumps = list((run / "crashes").glob("*.dmp"))
    out.append(f"- Logs: {len(logs)}, crash dumps: {len(dumps)}")
    for log in logs:
        facts, routines, crashes = parse_log(log)
        out += ["", f"## {log.name}", ""]
        out += [f"- {x}" for x in facts]
        errors = [(t, mod, text) for t, mod, text in routines if not text.startswith(PROBE_REPORTS)]
        out.append(f"- Script errors (not probe reports): {len(errors)}")
        out += [f"  - {t:.0f}s **{mod}**: {text[:300]}" for t, mod, text in errors]
        if crashes:
            out.append(f"- Crash/exception lines: {len(crashes)}")
            out += [f"  - `{c}`" for c in crashes[:5]]
        stats = [(t, text) for t, mod, text in routines if text.startswith("SAVESTAT")]
        if stats:
            out += ["", "| save | time | map | xp | +E0 | maxhp | P0 hp | P0 meter/lvl | P0 EX 19-21, rifts, shop | P1 xp | fat |",
                    "|---|---|---|---|---|---|---|---|---|---|---|"]
            out += [savestat_row(t, text) for t, text in stats]
        beats = [(t, text) for t, mod, text in routines if text.startswith("HEARTBEAT")]
        if beats:
            out += ["", "Heartbeats:"] + [heartbeat_line(t, text) for t, text in beats]
        other = [(t, text) for t, mod, text in routines
                 if text.startswith(PROBE_REPORTS) and not text.startswith(("SAVESTAT", "HEARTBEAT"))]
        if other:
            out += ["", "Other probe reports (shortened):"]
            out += [f"- {t:.0f}s `{text[:220]}`" for t, text in other]
    for name, title in (("notes.md", "Markers"), ("diff.txt", "Diff steps"), ("trace.txt", "Traces")):
        path = run / name
        if path.exists():
            text = path.read_text(encoding="utf-8", errors="replace").strip()
            out += ["", f"## {title}", "", text[:6000]]
    target = run / "summary.md"
    target.write_text("\n".join(out) + "\n", encoding="utf-8")
    return target


def main():
    run = Path(sys.argv[1]) if len(sys.argv) > 1 else newest_run()
    if run is None or not run.is_dir():
        print("No run folder found under qa/")
        return 1
    print(summarize(run))
    return 0


if __name__ == "__main__":
    sys.exit(main())
