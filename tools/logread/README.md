# logread — QA log reader

Turns a Shaolin Monks Recomp launch log into a short human summary: what the
session did, whether any mod script actually errored, what the diagnostic
routines reported, and what the gamepad did.

Read-only. It opens `%LOCALAPPDATA%\Shaolin Monks Recomp\logs\*.log` and
`..\crashes\*.dmp` (for timestamps only) and writes nothing anywhere. Python
standard library only.

## Usage

```
python tools/logread/logread.py newest      # the newest log (also the default)
python tools/logread/logread.py --last 2    # the 2 newest logs
python tools/logread/logread.py --log 071   # one specific log
```

`--log` accepts `071` or `71`. Log numbers come from the filename
`shaolin-recomp_NNN.log`; one file is written per game launch.

## What it prints

**A. Session** — start datetime and duration (last timestamp in the file),
`Mods: N routine scripts active`, every save, whether the log ends with
`Exit (0)`, and any crash dump in `..\crashes\` whose modified time falls
inside the session.

A *save* is an `open U:\<container>\save.dat` line that immediately follows an
`open U:\<container>\SaveMeta.xbx` line for the same container; both timestamps
are printed. The session window used for crash matching runs from the datetime
in the log's first line to that datetime plus the last timestamp.

**B. Mod errors** — every `Mod routine:` line whose message does *not* start
with a known report tag. These are real script errors and are printed in full.
Empty in every log to date.

**C. Reports** — one block per routine-mod report. A report is a single log
line of the form
`Mod routine: <mod>: <TAG> <reason> <fields> | <body> ... Script disabled for
this session.` (a routine script logs by raising an error, which disables it
for the rest of the session; the trailing sentence is stripped before
parsing).

| tag | mod | what the block shows |
| --- | --- | --- |
| `EVENTS` | mksmk_probe | deaths and instant kills per character slot, damage-applied / body-damage counts per slot, total XP awarded + biggest single award + XP set calls, group starts (ids, entry counts, pool free), spawns per type (count, average heap cost, failures), and the lowest heap free seen per type as a percentage of that heap's total |
| `SHUFFLE` | mksmk_probe | one line per area (mode, frame, slots, eligible, free gates, loaded types) plus the area's types grouped by their exact flag string (`once`, `L`/`l` loaded, `H`/`h` owns a heap) |
| `UPGRADE` | mksmk_probe | header fields, sampled commands grouped by name with their argument/caller tuples and counts, the `ANIM` histogram sorted by count, and the `STATE` transitions |
| `PLATE`, `PLATE051/052/054/060` | mksmk_probe, coop_solo | header fields, then body tokens one per line, first 40 |

Anything that does not match the documented grammar is printed raw under
`unparsed:` rather than guessed at. Real example: logs 073 and 075 carry a bare
`ARM` marker inside the `UPGRADE` sampled-command stream (it follows a
`mutilate[...]@1A2871/1818F5` command); its meaning is not documented, so it
is reported unparsed.

**D. Input** — how many `input: gamepad port=N buttons=XXXX A=.. B=..` lines
the log has, per port, and the distinct non-zero `buttons` values with counts.

## Documented decisions and GUESSes

- **Number base (GUESS):** a field made only of digits is read as decimal
  (HP, XP, combo, counts); a field containing a hex letter is read as hex
  (addresses, heap sizes, type ids). The probe prints both, without saying
  which.
- **`ANIM` key split (GUESS):** key = owner (`p` or `o`), then optionally `F`
  for fatality mode, then a hex event type. A literal `F` directly after the
  owner counts as the fatality marker only when at least one more hex digit
  follows it; otherwise the whole remainder is the event type. So `p1F4` =
  owner `p`, event `1F4`, and a hypothetical `pF4` = owner `p`, fatality,
  event `4`. A bare `pF` is read as event `F`, because single-digit hex events
  `A`–`F` are common in real logs. Fatality keys render as `p[F]4`, plain ones
  as `p.1F4`. No log to date contains a key this rule reads as fatality mode,
  so the `[F]` form is unexercised.
- **Older probe tags:** `TRACE`, `PROBE25` and `PROBE90` come from older
  mksmk_probe builds. They are reports, not script errors, so they are printed
  raw in section C and deliberately *not* counted in section B.
- **Bracketed tokens:** argument lists such as
  `reaction[ecx=506B28 68EB98 68411C(c0) 8279CC58]@1F2F91/...` and the
  `...(1285 dropped)...` omission marker contain spaces, so tokenising keeps
  bracketed groups and dropped markers intact.
- **Length:** the target is under 60 lines per log, but the PLATE rule (first
  40 body tokens, one per line) dominates: a log with two PLATE reports prints
  about 130 lines.
- A live log (game still running) is handled: it simply reports no `Exit (0)`
  line.

## Example output

`python tools/logread/logread.py --log 071` (excerpt, PLATE bodies cut):

```
=== shaolin-recomp_071.log ===
A. Session
  start: 2026-10-24 09:48:32 | duration: 328.4s | last line: [  328.360] [info] [te77f] Exit (0)
  Mods: 11 routine scripts active
  saves: 4
    12.814 -> 12.815  U:\80482ECC5634\save.dat
    18.877 -> 18.880  U:\80482ECC5634\save.dat
    322.050 -> 322.052  U:\80482ECC5634\save.dat
    323.730 -> 323.731  U:\80482ECC5634\save.dat
  ends with: Exit (0)
  crash dumps in this session: none
B. Mod errors (0)
  none
C. Reports (5)
  [323.729] coop_solo: PLATE052  reason=save  mode=0 edges=27 latch0/0
    T24{f5000,c0}actionButton
    n192
    ...
    ... 100 more body token(s)
  [323.729] mksmk_probe: EVENTS  reason=save  mode=0 n=55
    deaths/slot: 2:3 3:3 4:1 5:1 6:1
    instant kills/slot: 2:1 3:2 4:2 5:2 7:1
    XP awarded: 13,950 over 8 award(s), biggest 7,700
    XP set calls: p1=+100 c0 @AF336/A8C40/A8CE4/AEE2C
    group starts: 8 | ids 17(n2) x2, 15(n4) x2, 15(n2) x2, 17(n4) x1, 18(n6) x1 | pool free 10 x8
    heap low water (% of total): E 5.2% (0x1D300/0x232000) | A 28.3% (0x9F500/0x232000) | 1A 43.1% (0xF2380/0x232000) | 1B 44.0% (0xF7080/0x232000) | 4D 58.3% (0x147A80/0x232000) | 2E 90.7% (0x1FD800/0x232000)
    spawns: A x5 avg 0x25580 | E x2 avg 0x25D00 | 1A x8 avg 0x24900 | 1B x2 avg 0x21A80
    spawn failures (bare F): 4
  [323.730] mksmk_probe: SHUFFLE  reason=save  areas=4
    area1 mode=0 frame=276 slots=26 eligible=10 freegates=1 loaded=[0,1,E,1A,4D,-]
      flags oncelh: 14=1 1B=1 1E=1 24=1 2=1 2E=1 33=1 39=1 3F=1 F=1
      flags LH: 1A=5 E=5
      flags lh: 30=2 47=2 48=2
    area2 mode=0 frame=3363 slots=26 eligible=10 freegates=1 loaded=[0,1,E,1A,4D,-]
      ...
  [323.730] mksmk_probe: UPGRADE  reason=save  frame=16233 mode=0 hp=300 xp=0 combo=0
    sampled commands: reaction x4, startanim x3
      reaction[ecx=506B28 68EB98 68411C(c0) 8279CC58]@1F2F91/17015A/16E14D x1
      ...
D. Input
  gamepad lines: 465 (ports 0 x464, 1 x1)
  distinct non-zero buttons: 0002 x9, 0010 x2, 0004 x1
```

From log 073, a `UPGRADE` report that has the animation histogram:

```
    ANIM histogram (31 keys, 19,449 samples), sorted by count:
      o.0=3740 p.0=1774 o.1=1754 p.3=1585 p.2=1466 p.1F4=809 o.4=796 p.7=781 p.1=770 o.7=536 p.6=483 o.64=400 p.D=387
      p.E=387 p.A=378 p.48=331 p.B=313 o.258=311 p.7D=311 p.F=253 p.C=251 o.73=239 p.258=208 o.1F4=207 o.26=176
      p.32=156 p.1B=154 p.12C=149 p.28=143 o.3F7=140 o.F=61
      key = <owner p|o> then ".<hex event>" or "[F]<hex event>" = fatality mode (GUESS split rule)
    STATE transitions: f0=-1/-1/1000/1000  f62=1/1/1000/1000
```

And two edge cases from real logs — a session that died (048, last line is the
error dialog) and a clean session whose window happens to contain a dump
written by a second launch (059):

```
=== shaolin-recomp_048.log ===
A. Session
  start: 2026-10-23 13:16:13 | duration: 142.3s | last line: [  142.280] [info] [t577e] Error dialog closed. Application data folder: C:\Users\Arcade Machine 1\A
  Mods: 3 routine scripts active
  saves: 1
    58.774 -> 58.799  U:\80482ECC5634\save.dat
  ends with: no "Exit (0)" line (killed, crashed or still running)
  crash dumps in this session:
    ShaolinMonksRecomp.2026.10.23_13.17.21.dmp  (mtime 2026-10-23 13:17:22.967532)

=== shaolin-recomp_059.log ===
  ends with: Exit (0)
  crash dumps in this session:
    ShaolinMonksRecomp.2026.10.23_19.39.05.dmp  (mtime 2026-10-23 19:39:05.299283)
    note: this log ends with Exit (0), so the dump may belong to a second, overlapping launch
```

Five logs (049, 054, 056, 060, 063) are **0 bytes**: launches that died before
writing a header. For those, section A prints the file's mtime instead of a
session window, and crash matching falls back to a 5-minute window before that
mtime (labelled GUESS in the output).

Bad arguments exit non-zero with a one-line message instead of a traceback:
`no log numbered 999 (have 46..75)`, `unknown target 'bogus' (use "newest",
--last N or --log NNN)`, `--last needs N >= 1`.
