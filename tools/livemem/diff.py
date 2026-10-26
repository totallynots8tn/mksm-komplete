"""Find which game values change when you do something: a live memory diff.

Read-only. Snapshots the player-related memory of the running Shaolin Monks
Recomp (the game manager, both player characters, their actors and stats),
lets you act in game, snapshots again and lists every 32-bit value that
changed, with its address and its value read as hex, integer and float.
Values that also change while you stand still (timers, animation) are
filtered out as noise.

  python tools/livemem/diff.py watch [--out FILE]
      Interactive. It first records 3 seconds of idle noise (don't touch the
      pad), then for each step: do one thing in game (block for 2 seconds,
      throw a special...), come back and press Enter, optionally typing a
      label. Each step's changes are printed and appended to FILE
      (default qa/diff/watch-<time>.txt). Type q to stop. At the end it lists
      the values that changed in every step with the same label.

  python tools/livemem/diff.py snap NAME      save a snapshot to qa/diff/NAME.snap
  python tools/livemem/diff.py diff A B [--noise C]
      compare two saved snapshots (C: a third one taken idle, for noise)

  --range ADDR:LEN   also watch this guest range (hex), repeatable
"""
import argparse, os, pickle, struct, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import peek  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
OUT_DIR = os.path.join(ROOT, 'qa', 'diff')

GAME_MANAGER = 0x5ACEBC
MANAGER_SIZE = 0x5200         # one save slot's worth (slot pitch 0x51AC)
CHAR_TABLE = 0x5D1AB8         # player entities, 0x3238 apart
CHAR_STRIDE = 0x3238
ACTOR = 0x200                 # entity -> actor (health at +0x368)
ACTOR_SIZE = 0x1000
STATS = 0x2B6C                # entity -> stats link
STATS_SIZE = 0x400


def plausible(p):
    return p >= 0x10000 and p % 4 == 0 and (p < 0x7FFE0000 or 0x80000000 <= p < 0x84000000)


def regions(extra):
    """(name, base, size) for everything we watch, resolved now."""
    out = []
    mgr = peek.u32(GAME_MANAGER)
    if plausible(mgr):
        out.append(('manager', mgr, MANAGER_SIZE))
    for p in range(2):
        ent = CHAR_TABLE + p * CHAR_STRIDE
        out.append((f'p{p}.entity', ent, CHAR_STRIDE))
        actor = peek.u32(ent + ACTOR)
        if plausible(actor):
            out.append((f'p{p}.actor', actor, ACTOR_SIZE))
        stats = peek.u32(ent + STATS)
        if plausible(stats):
            out.append((f'p{p}.stats', stats, STATS_SIZE))
            # the two per-player meter objects the HUD draws from: +0x54 is the
            # fatality meter (0x59D350 for P1, init 0x80260), +0x50 its sibling
            for off, size in ((0x50, 0x358), (0x54, 0x578)):
                obj = peek.u32(stats + off)
                if plausible(obj):
                    out.append((f'p{p}.meter{off:X}', obj, size))
    for i, (base, size) in enumerate(extra):
        out.append((f'range{i}', base, size))
    return out


def snapshot(extra):
    snap = {'time': time.time(), 'regions': {}}
    for name, base, size in regions(extra):
        try:
            snap['regions'][name] = (base, peek.rd(base, size))
        except OSError:
            pass
    return snap


def changes(a, b):
    """{(region, offset): (address, old, new)} for every dword that differs."""
    out = {}
    for name, (base, old) in a['regions'].items():
        if name not in b['regions'] or b['regions'][name][0] != base:
            continue                              # pointer moved: not comparable
        new = b['regions'][name][1]
        for off in range(0, min(len(old), len(new)) - 3, 4):
            o, n = old[off:off + 4], new[off:off + 4]
            if o != n:
                out[(name, off)] = (base + off, struct.unpack('<I', o)[0], struct.unpack('<I', n)[0])
    return out


def describe(v):
    s = v - (1 << 32) if v >= 1 << 31 else v
    f = struct.unpack('<f', struct.pack('<I', v))[0]
    text = f'{v:08X} int {s}'
    if f == f and 1e-3 <= abs(f) <= 1e7:          # f == f: not NaN
        text += f' f32 {f:g}'
    return text


def report(step, label, diff, noise, out):
    keys = [k for k in sorted(diff) if k not in noise]
    lines = [f'== step {step}: {label or "(no label)"} - {len(keys)} changed ({len(diff) - len(keys)} more were idle noise)']
    for k in keys:
        addr, old, new = diff[k]
        lines.append(f'  {k[0]:>11} +{k[1]:04X}  @{addr:08X}  {describe(old)}  ->  {describe(new)}')
    text = '\n'.join(lines)
    print(text)
    if out is not sys.stdout:
        out.write(text + '\n')
        out.flush()
    return set(keys)


def parse_ranges(values):
    ranges = []
    for v in values or []:
        a, n = v.split(':')
        ranges.append((int(a, 16), int(n, 16)))
    return ranges


def watch(args):
    extra = parse_ranges(args.range)
    os.makedirs(OUT_DIR, exist_ok=True)
    path = args.out or os.path.join(OUT_DIR, time.strftime('watch-%Y%m%d-%H%M%S.txt'))
    with open(path, 'a', encoding='utf-8') as out:
        print('Recording idle noise: leave the pad alone for 3 seconds...')
        first = snapshot(extra)
        noise = set()
        for _ in range(3):
            time.sleep(1)
            noise |= set(changes(first, snapshot(extra)))
        out.write(f'# {time.ctime()}  idle noise: {len(noise)} values\n')
        print(f'{len(noise)} values change on their own; they are ignored below.')
        by_label = {}
        step = 0
        while True:
            before = snapshot(extra)
            label = input('\nDo one thing in game, then press Enter (type a label first, q to quit): ').strip()
            if label.lower() == 'q':
                break
            step += 1
            keys = report(step, label, changes(before, snapshot(extra)), noise, out)
            by_label.setdefault(label, []).append(keys)
        summary = []
        for label, sets in by_label.items():
            if len(sets) > 1:
                common = set.intersection(*sets)
                summary.append(f'"{label}" x{len(sets)}: changed every time: ' +
                               (', '.join(f'{n}+{o:04X}' for n, o in sorted(common)) or 'nothing'))
        if summary:
            text = '== summary\n' + '\n'.join(summary)
            print(text)
            out.write(text + '\n')
    print(f'\nSaved to {path}')


def trace(extra=(), idle=3.0, seconds=10.0, rate=10.0, top=20, on_go=None):
    """Sample everything `rate` times a second: `idle` seconds hands-off, then
    `seconds` while the player acts. Returns report lines ranking the values
    that dropped and then climbed back (a meter being spent and refilling),
    which a two-snapshot diff misses when the meter refills before Step."""
    step = 1.0 / rate
    noise, base = set(), snapshot(list(extra))
    end = time.time() + idle
    while time.time() < end:
        time.sleep(step)
        noise |= set(changes(base, snapshot(list(extra))))
    series = {}                                   # (region, off) -> [u32 values]
    if on_go:
        on_go()
    frames = [snapshot(list(extra))]
    end = time.time() + seconds
    while time.time() < end:
        time.sleep(step)
        frames.append(snapshot(list(extra)))
    for name, (base_addr, first) in frames[0]['regions'].items():
        for off in range(0, len(first) - 3, 4):
            key = (name, off)
            if key in noise:
                continue
            vals = []
            for fr in frames:
                reg = fr['regions'].get(name)
                if reg is None or reg[0] != base_addr:
                    break
                vals.append(struct.unpack_from('<I', reg[1], off)[0])
            if len(vals) == len(frames) and len(set(vals)) > 2:
                series[key] = (base_addr + off, vals)
    ranked = []
    for key, (addr, vals) in series.items():
        for kind in ('f32', 'u16lo', 'u16hi', 'i32'):
            if kind == 'f32':
                xs = [struct.unpack('<f', struct.pack('<I', v))[0] for v in vals]
                if not all(x == x and abs(x) < 1e7 for x in xs):
                    continue
            elif kind == 'u16lo':
                xs = [v & 0xFFFF for v in vals]
            elif kind == 'u16hi':
                xs = [v >> 16 for v in vals]
            else:
                xs = [v - (1 << 32) if v >= 1 << 31 else v for v in vals]
            lo = min(xs)
            i = xs.index(lo)
            dip, back = xs[0] - lo, xs[-1] - lo
            span = (max(xs) - lo) or 1
            rises = sum(1 for a, b in zip(xs[i:], xs[i + 1:]) if b > a)
            falls = sum(1 for a, b in zip(xs[i:], xs[i + 1:]) if b < a)
            if dip <= 0 or back <= 0 or rises < 3 or falls > rises // 3:
                continue                         # not "spent, then refilling"
            score = (dip / span) * (back / span) * rises
            ranked.append((score, key, addr, kind, xs))
            break
    ranked.sort(key=lambda r: -r[0])
    lines = [f'== trace: {len(frames)} samples over {seconds:g}s, {len(noise)} idle-noise values ignored, '
             f'{len(ranked)} dip-and-refill candidates']
    for score, (name, off), addr, kind, xs in ranked[:top]:
        pick = [xs[int(j * (len(xs) - 1) / 9)] for j in range(10)]
        lines.append(f'  {name:>11} +{off:04X} @{addr:08X} {kind:5} start {xs[0]:g} min {min(xs):g} '
                     f'end {xs[-1]:g} max {max(xs):g} | ' + ' '.join(f'{p:g}' for p in pick))
    return lines


def trace_cmd(args):
    print(f'Hands off for {args.idle:g} seconds, then do the thing (throw specials) for {args.seconds:g} seconds...')
    lines = trace(parse_ranges(args.range), idle=args.idle, seconds=args.seconds)
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, time.strftime('trace-%Y%m%d-%H%M%S.txt'))
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')
    print('\n'.join(lines))
    print('saved', path)


def snap_cmd(args):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, args.name + '.snap')
    with open(path, 'wb') as f:
        pickle.dump(snapshot(parse_ranges(args.range)), f)
    print('saved', path)


def load(name):
    path = name if os.path.exists(name) else os.path.join(OUT_DIR, name + '.snap')
    with open(path, 'rb') as f:
        return pickle.load(f)


def diff_cmd(args):
    a, b = load(args.a), load(args.b)
    noise = set(changes(a, load(args.noise))) if args.noise else set()
    report(1, f'{args.a} -> {args.b}', changes(a, b), noise, sys.stdout)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    w = sub.add_parser('watch'); w.add_argument('--out'); w.add_argument('--range', action='append')
    s = sub.add_parser('snap'); s.add_argument('name'); s.add_argument('--range', action='append')
    d = sub.add_parser('diff'); d.add_argument('a'); d.add_argument('b'); d.add_argument('--noise')
    t = sub.add_parser('trace'); t.add_argument('--range', action='append')
    t.add_argument('--idle', type=float, default=3.0); t.add_argument('--seconds', type=float, default=10.0)
    args = ap.parse_args()
    {'watch': watch, 'snap': snap_cmd, 'diff': diff_cmd, 'trace': trace_cmd}[args.cmd](args)


if __name__ == '__main__':
    main()
