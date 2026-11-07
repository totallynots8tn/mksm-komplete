"""Record the memory slots, loaded types, enemies and the rift's group while the game runs,
   one line per change (at most every 0.2 s), so a crash leaves the last steps behind.
   python rift_watch.py <out file> [hours]      (run from the worktree root)"""
import os, subprocess, sys, time
sys.path.insert(0, os.path.join(os.getcwd(), 'tools', 'livemem'))
import peek
from peek import u8, u16, u32

out_path = sys.argv[1]
hours = float(sys.argv[2]) if len(sys.argv) > 2 else 3
S, M, P1, STRIDE = 0x6322F8, 0x6DBFB0, 0x5D1AB8, 0x3238
s32 = lambda v: v - (1 << 32) if v & 0x80000000 else v


def running():
    out = subprocess.run(['tasklist', '/fi', 'imagename eq ShaolinMonksRecomp.exe', '/fo', 'csv', '/nh'],
                         capture_output=True, text=True).stdout
    return '"' in out


def state():
    rows = u32(S + 0x24)
    slots = [s32(u32(rows + i * 20 + 4)) for i in range(min(u32(S + 0x10), 6))]
    br = u32(S + 0x1C)
    blocks = ['%d:%d' % (s32(u32(br + i * 20 + 4)), u32(br + i * 20 + 0x10)) for i in range(min(u32(S + 8), 6))]
    loaded = [s32(u32(0x6CA69C + 4 * k)) for k in range(2, 6)]
    flags = u32(0x51004C)
    ents = sorted(u16(P1 + i * STRIDE + 0x1DFE) for i in range(2, 12) if u16(flags + i * 2))
    g = M + 49 * 0xA6C
    grp = (u16(g + 0xA68), u8(g + 0xA6A), u32(g + 0xA10) == 0x54464952, [u32(g + 0x18 + i * 0x74) for i in range(min(u16(g + 0xA68), 3))])
    return (u32(0x505970), tuple(slots), tuple(blocks), tuple(loaded), tuple(ents), grp, u8(M + 0x2092A), u16(M + 0x20920) * 1000 + u16(M + 0x20922))


end = time.time() + hours * 3600
last, lines = None, []
with open(out_path, 'a', encoding='utf-8') as f:
    f.write('--- watch started %s\n' % time.strftime('%H:%M:%S'))
    while time.time() < end:
        if not running():
            if last is not None:
                f.write('%s game gone\n' % time.strftime('%H:%M:%S'))
                f.flush()
                last = None
            time.sleep(2)
            continue
        try:
            s = state()
        except Exception as e:
            s = ('read error', str(e)[:60])
        if s != last:
            m, slots, blocks, loaded, ents, grp, active, group = s if len(s) == 8 else (None,) * 8
            if m is None:
                f.write('%s %s\n' % (time.strftime('%H:%M:%S'), s))
            else:
                f.write('%s map%d slots%s blocks%s loaded%s ents%s g49%s act%d grp%d\n' % (
                    time.strftime('%H:%M:%S'), m, list(slots), list(blocks), list(loaded), list(ents), grp, active, group))
            f.flush()
            last = s
        time.sleep(0.2)
