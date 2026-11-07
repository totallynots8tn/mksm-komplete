"""Load each map (entry 1) and log which enemies exist before and as its waves start.
   python scene_tour.py <map> [<map> ...]      (run from the worktree root)"""
import os, struct, subprocess, sys, time
sys.path.insert(0, os.path.join(os.getcwd(), 'tools', 'livemem'))
from peek import rd, u8, u16, u32, write

P1, M, S, STRIDE = 0x5D1AB8, 0x6DBFB0, 0x6322F8, 0x3238
s32 = lambda v: v - (1 << 32) if v & 0x80000000 else v


def running():
    out = subprocess.run(['tasklist', '/fi', 'imagename eq ShaolinMonksRecomp.exe', '/fo', 'csv', '/nh'],
                         capture_output=True, text=True).stdout
    return '"' in out


def snapshot():
    flags = u32(0x51004C)
    ents = []
    for i in range(2, 12):
        if u16(flags + i * 2):
            e = P1 + i * STRIDE
            ents.append(u16(e + 0x1DFE))
    return (u8(M + 0x2092A), u16(M + 0x20920), u16(M + 0x20922), tuple(sorted(ents)))


def slots():
    rows = u32(S + 0x24)
    return [s32(u32(rows + i * 20 + 4)) for i in range(u32(S + 0x10))]


for target in [int(a) for a in sys.argv[1:]]:
    if not running():
        print('GAME NOT RUNNING before map', target)
        break
    start = u32(0x505970)
    write(P1 + 0x3217, b'\x01')
    write(P1 + STRIDE + 0x3217, b'\x01')
    write(0x5ACEE0, struct.pack('<I', 1))
    write(0x4FC160, struct.pack('<I', target))
    write(0x4FC164, struct.pack('<I', 1))
    write(0x5ACEDC, b'\x01')
    t0 = time.time()
    while time.time() - t0 < 45:
        if not running():
            print('CRASH loading map %d (from %d)' % (target, start))
            sys.exit(0)
        try:
            if u32(0x505970) == target:
                break
        except Exception:
            pass
        time.sleep(0.2)
    else:
        print('map %d NOT LOADED (still %d)' % (target, u32(0x505970)))
        continue
    t1 = time.time()
    seen, last = [], None
    while time.time() - t1 < 6:
        if not running():
            print('CRASH after loading map %d' % target)
            sys.exit(0)
        try:
            snap = snapshot()
        except Exception:
            snap = None
        if snap and snap != last:
            seen.append('%.1f:a%d g%d s%d %s' % (time.time() - t1, snap[0], snap[1], snap[2], list(snap[3])))
            last = snap
        time.sleep(0.25)
    print('map %d loaded %.0fs | slots %s | %s' % (target, t1 - t0, slots(), ' ; '.join(seen)))
    sys.stdout.flush()
