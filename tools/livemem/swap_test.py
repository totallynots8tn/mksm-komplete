"""Swap one listed enemy type for an outsider in a map's preload list, load the map (entry 1),
   watch it for a few seconds, then put the type back.   python swap_test.py map:type:outsider ...
   Stops at the first crash (run from the worktree root)."""
import json, os, struct, subprocess, sys, time
sys.path.insert(0, os.path.join(os.getcwd(), 'tools', 'livemem'))
from peek import u8, u16, u32, write

P1, M, STRIDE = 0x5D1AB8, 0x6DBFB0, 0x3238
MAPS = {m['map']: m for m in json.load(open(os.path.join('analysis', 'xbox_roster', 'maps.json'), encoding='utf-8'))}


def running():
    out = subprocess.run(['tasklist', '/fi', 'imagename eq ShaolinMonksRecomp.exe', '/fo', 'csv', '/nh'],
                         capture_output=True, text=True).stdout
    return '"' in out


def enemies():
    flags = u32(0x51004C)
    return sorted(u16(P1 + i * STRIDE + 0x1DFE) for i in range(2, 12) if u16(flags + i * 2))


for spec in sys.argv[1:]:
    target, kind, outsider = (int(v) for v in spec.split(':'))
    if not running():
        print('GAME NOT RUNNING before', spec)
        break
    m = MAPS[target]
    lst = int(m['list_va'], 16)
    cap = u32(int(m['desc'], 16) + 0x20)
    listed = [u32(lst + 4 * k) for k in range(cap)]
    if kind not in listed:
        print(spec, 'SKIP: type not listed', listed)
        continue
    k = listed.index(kind)
    write(lst + 4 * k, struct.pack('<I', outsider))
    write(P1 + 0x3217, b'\x01')
    write(P1 + STRIDE + 0x3217, b'\x01')
    write(0x5ACEE0, struct.pack('<I', 1))
    write(0x4FC160, struct.pack('<I', target))
    write(0x4FC164, struct.pack('<I', 1))
    write(0x5ACEDC, b'\x01')
    t0, arrived, verdict = time.time(), None, None
    while time.time() - t0 < 50:
        if not running():
            verdict = 'CRASH %s (%.0fs after the request%s)' % (
                'after arrival' if arrived else 'during the load', time.time() - t0,
                ', %.1fs after arrival, group %s active %d' % (time.time() - arrived, u16(M + 0x20920) if False else '?', 0) if arrived else '')
            break
        try:
            if arrived is None and u32(0x505970) == target:
                arrived = time.time()
            if arrived and time.time() - arrived > 8:
                break
        except Exception:
            pass
        time.sleep(0.25)
    if verdict:
        print(spec, verdict, '| listed', listed)
        sys.exit(0)
    write(lst + 4 * k, struct.pack('<I', kind))          # the type back in the list
    if not arrived:
        print(spec, 'NOT LOADED (map %d)' % u32(0x505970))
        continue
    print(spec, 'OK loaded %.0fs | slots %s | enemies %s | active %d' % (
        arrived - t0, [u32(u32(0x6322F8 + 0x24) + i * 20 + 4) for i in range(u32(0x6322F8 + 0x10))],
        enemies(), u8(M + 0x2092A)))
    sys.stdout.flush()
