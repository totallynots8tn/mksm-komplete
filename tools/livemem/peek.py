"""Read (and, with care, write) the running Shaolin Monks Recomp guest memory.

The Recomp maps the 4 GiB Xbox guest space at host 0x100000000 (logged at
startup as "memory: guest space at 0000000100000000"), so guest address A is
host address 0x100000000 + A in ShaolinMonksRecomp.exe.

  python tools/livemem/peek.py            spawner, loaded types, memory slots, waves
  python -i tools/livemem/peek.py         then use u8/u16/u32/rd(...) interactively

Reading is harmless. write() changes the live game: only use it to rescue a
soft-locked session, and don't save afterwards if anything looks off.
"""
import ctypes, ctypes.wintypes as wt, struct, subprocess

BASE = 0x100000000
k32 = ctypes.WinDLL('kernel32', use_last_error=True)
k32.OpenProcess.restype = wt.HANDLE
k32.ReadProcessMemory.argtypes = [wt.HANDLE, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
k32.WriteProcessMemory.argtypes = [wt.HANDLE, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]


def pid():
    out = subprocess.run(['tasklist', '/fi', 'imagename eq ShaolinMonksRecomp.exe', '/fo', 'csv', '/nh'],
                         capture_output=True, text=True).stdout
    if '"' not in out:
        raise SystemExit("ShaolinMonksRecomp.exe isn't running")
    return int(out.split(',')[1].strip('"'))


_read = None
_write = None


def rd(addr, n):
    global _read
    if _read is None:
        _read = k32.OpenProcess(0x0010 | 0x0400, False, pid())      # VM_READ | QUERY_INFORMATION
    buf = ctypes.create_string_buffer(n)
    got = ctypes.c_size_t()
    if not k32.ReadProcessMemory(_read, BASE + addr, buf, n, ctypes.byref(got)):
        raise OSError(ctypes.get_last_error())
    return buf.raw


def write(addr, data):
    global _write
    if _write is None:
        _write = k32.OpenProcess(0x0008 | 0x0020 | 0x0010, False, pid())   # VM_OPERATION | VM_WRITE | VM_READ
    got = ctypes.c_size_t()
    if not k32.WriteProcessMemory(_write, BASE + addr, data, len(data), ctypes.byref(got)):
        raise OSError(ctypes.get_last_error())


def u8(a): return rd(a, 1)[0]
def u16(a): return struct.unpack('<H', rd(a, 2))[0]
def s16(a): return struct.unpack('<h', rd(a, 2))[0]
def u32(a): return struct.unpack('<I', rd(a, 4))[0]


SPAWNER = 0x6DBFB0            # 50 groups, 0xA6C apart; entries 0x74 from +0x18; count +0xA68
WAVES_CLEARED = 0x6C0168      # 20 x {s16 group, u32 alive, u8 cleared}; next slot at 0x6C0258
TRIGGERS = 0x682020           # -> records 0xD8 apart, count +0xA8C0, fired frame +0x10


def report():
    h = lambda v: '-' if v == 0xFFFFFFFF else f'{v:x}'
    print('frame', u32(0x5CE878), '| map', u32(0x505968 + 8))
    print('loaded types', [h(u32(0x6CA69C + i * 4)) for i in range(6)])
    iface = 0x6322F8
    table, count = u32(iface + 0x24), u32(iface + 0x10)
    for i in range(min(count, 8)):
        heap, kind = u32(table + i * 20), u32(table + i * 20 + 4)
        rec = 0x62EC60 + heap * 0x68
        free = u32(rec + 0xC) - u32(rec + 8) if heap < 0x80 and u32(rec + 0x1C) == 0 else None
        print(f'  memory slot {i}: type {h(kind)} heap {heap:#x} fresh {free:#x}' if free is not None else
              f'  memory slot {i}: type {h(kind)} heap {heap:#x}')
    print('spawner active', u8(SPAWNER + 0x2092A), 'group', u16(SPAWNER + 0x20920), 'spawned', u16(SPAWNER + 0x20922))
    for g in range(50):
        base = SPAWNER + g * 0xA6C
        n = s16(base + 0xA68)
        if u8(base + 0xA6A) and 0 < n <= 22:
            print(f'  wave {g:2d}: ' + ' '.join(h(u32(base + 0x18 + e * 0x74)) for e in range(n)))
    flags = u32(0x51004C)
    print('actors', [u16(flags + k * 2) for k in range(12)])
    print('waves cleared', [(s16(WAVES_CLEARED + i * 12), u32(WAVES_CLEARED + i * 12 + 4), u8(WAVES_CLEARED + i * 12 + 8))
                            for i in range(20) if s16(WAVES_CLEARED + i * 12)])


if __name__ == '__main__':
    report()
