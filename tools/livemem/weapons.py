"""Read-only view of the weapon manager in the running game (weapon store RE).

  python tools/livemem/weapons.py          one dump
  python tools/livemem/weapons.py watch    print every change, 4 times a second,
                                           until the game closes or Ctrl+C

Layout (default.xbe, 2026-10-26; analysis/xp_shop/REPORT.md section 12):
- Weapon manager at 0x5A3AC0 (vtable 0x4A2588, built by 0xBE070 at boot). Its
  table of weapon objects starts at +8, 0x27C bytes each, count at +0x56FC
  (at most 35). Every weapon type exists once, in every map; a map places one,
  it doesn't create it.
- Weapon object (vtable 0x4A24D4): +0x04 class id (0x54 sword, 0x55 broadsword,
  0x57 ?, 0x58 dual), +0x0C name, +0x10C holder (character entity, 0 = free),
  +0x120 flag, +0x124 physics body or attach parent (0 = none), +0x12C/+0x130
  model ids, +0x174 scene node it is placed at (-1 = not placed; 0xBAA90),
  +0x178 second half of a pair, +0x17C next half, +0x264 name text,
  +0x268/+0x26C durability max/now. Pickable (0xBC080): placed or has a body,
  no holder, not a second half, near the player.
- Pickup markers: the list at [0x5ACEAC] (count at +0x50, entries from +0),
  name at +0x20, position +0x04..+0x0C. Picking a weapon up deletes the marker
  with its name (FindAndRemove 0xABE40).
- Players: entity 0x5D1AB8 + p * 0x3238, position +0x80..+0x88, held weapon
  +0x2794.
"""
import csv, io, struct, subprocess, sys, time

sys.path.insert(0, __import__('os').path.dirname(__file__))
import peek  # noqa: E402

MANAGER, STRIDE, COUNT = 0x5A3AC0, 0x27C, 0x56FC
MARKERS = 0x5ACEAC
ENTITY, ENTITY_STRIDE = 0x5D1AB8, 0x3238


def game_pid():
    out = subprocess.run(['tasklist', '/fi', 'imagename eq ShaolinMonksRecomp.exe', '/fo', 'csv', '/nh'],
                         capture_output=True, text=True).stdout
    rows = [r for r in csv.reader(io.StringIO(out)) if len(r) > 4]
    if not rows:
        raise SystemExit("ShaolinMonksRecomp.exe isn't running")
    size = lambda r: int(''.join(c for c in r[4] if c.isdigit()) or 0)
    return int(max(rows, key=size)[1])      # the game, not the launcher


def u32(a): return peek.u32(a)
def f32(a): return struct.unpack('<f', peek.rd(a, 4))[0]
def s32(a): return struct.unpack('<i', peek.rd(a, 4))[0]


def cstr(a, n=24):
    return peek.rd(a, n).split(b'\0')[0].decode('latin1')


def snapshot():
    rows = {}
    n = u32(MANAGER + COUNT)
    if n > 35:
        return {'error': f'weapon count {n}: not the manager we expect'}
    for k in range(n):
        e = MANAGER + 8 + k * STRIDE
        rows[f'weapon {k:2} {cstr(e + 0x0C):12}'] = (
            f'id={u32(e + 4):#x} holder={u32(e + 0x10C):#x} body={u32(e + 0x124):#x} '
            f'node={s32(e + 0x174)} half={peek.u8(e + 0x178)} next={u32(e + 0x17C):#x} '
            f'dur={s32(e + 0x26C)}/{s32(e + 0x268)} models={u32(e + 0x12C):#x},{u32(e + 0x130):#x}')
    pool = u32(MARKERS)
    if pool:
        m = u32(pool + 0x50)
        rows['markers'] = f'list {pool:#x} count {m}'
        for k in range(min(m, 20)):
            p = u32(pool + k * 4)
            if p:
                rows[f'marker {k:2}'] = (f'{cstr(p + 0x20):16} vt={u32(p):#x} '
                                         f'at {f32(p + 4):.1f},{f32(p + 8):.1f},{f32(p + 0xC):.1f}')
    for p in range(2):
        e = ENTITY + p * ENTITY_STRIDE
        rows[f'player {p + 1}'] = (f'at {f32(e + 0x80):.1f},{f32(e + 0x84):.1f},{f32(e + 0x88):.1f} '
                                   f'holds {u32(e + 0x2794):#x}')
    return rows


def main():
    pid = game_pid()
    peek.pid = lambda: pid
    if len(sys.argv) > 1 and sys.argv[1] == 'watch':
        last = {}
        while True:
            try:
                now = snapshot()
            except OSError:
                print('game closed'); return
            for k, v in now.items():
                if last.get(k) != v:
                    print(f'{time.strftime("%H:%M:%S")} {k}: {v}')
            last = now
            time.sleep(0.25)
    for k, v in snapshot().items():
        print(f'{k}: {v}')


if __name__ == '__main__':
    main()
