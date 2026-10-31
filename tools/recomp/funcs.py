"""Check routine hook and callgate target addresses against the Recomp's function table.

  python tools/recomp/funcs.py 0x12284 0x71A40          check addresses
  python tools/recomp/funcs.py --lua mods/_build/src/callgate_lib.lua
                                                        check every `address = 0x...` and
                                                        callgate.target(0x...) in a script

A routine hook (or a callgate target) must name a routine in the table; a jmp
thunk is one, the body it jumps to is not, and the game refuses to boot with
"routine target is unavailable or belongs to host compatibility code"
without saying which address. The table is the sorted u32 array of guest
addresses inside ShaolinMonksRecomp.exe (27,717 entries in 0.2.0); it is
found by expanding the ascending run around a known routine.
"""
import pathlib, re, struct, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
# the release folder sits in the main checkout, above any .claude worktree
EXE = next((p / 'ShaolinMonksRecomp-0.2.0-Windows-x64' / 'ShaolinMonksRecomp.exe'
            for p in (ROOT, *ROOT.parents)
            if (p / 'ShaolinMonksRecomp-0.2.0-Windows-x64' / 'ShaolinMonksRecomp.exe').exists()),
           ROOT / 'ShaolinMonksRecomp-0.2.0-Windows-x64' / 'ShaolinMonksRecomp.exe')
KNOWN = 0x001D23F0      # the spawn tick, hooked by every spawn mod


def load_table(exe=EXE):
    data = exe.read_bytes()
    u32 = lambda o: struct.unpack_from('<I', data, o)[0]
    needle = struct.pack('<I', KNOWN)
    best = []
    at = data.find(needle)
    while at != -1:
        if at % 4 == 0 and u32(at - 4) < KNOWN < u32(at + 4):
            start = at
            while start >= 4 and u32(start - 4) < u32(start):
                start -= 4
            end = at
            while end + 8 <= len(data) and u32(end + 4) > u32(end):
                end += 4
            if (end - start) // 4 + 1 > len(best):
                best = [u32(o) for o in range(start, end + 4, 4)]
        at = data.find(needle, at + 1)
    if len(best) < 1000:
        sys.exit(f'function table not found in {exe}')
    return set(best)


def lua_addresses(path):
    text = pathlib.Path(path).read_text(encoding='utf-8')
    found = re.findall(r'(?<!local )\baddress\s*=\s*(0x[0-9A-Fa-f]+)', text)
    found += re.findall(r'callgate\.target\(\s*(0x[0-9A-Fa-f]+)', text)
    # named constants used as `address = NAME` or callgate.target(NAME)
    consts = dict(re.findall(r'local\s+(\w+)\s*=\s*(0x[0-9A-Fa-f]+)', text))
    for name in re.findall(r'(?<!local )\baddress\s*=\s*([A-Z_][A-Z0-9_]*)', text) + \
                re.findall(r'callgate\.target\(\s*([A-Z_][A-Z0-9_]*)', text):
        if name in consts:
            found.append(consts[name])
    return sorted({int(a, 16) for a in found})


def main(argv):
    addresses, used = [], False
    while argv:
        arg = argv.pop(0)
        if arg == '--lua':
            addresses += lua_addresses(argv.pop(0))
        else:
            addresses.append(int(arg, 16))
        used = True
    if not used:
        sys.exit(__doc__)
    if not addresses:
        print('no hook addresses found')
        return
    table = load_table()
    bad = 0
    for a in addresses:
        ok = a in table
        bad += not ok
        print(f'{a:08X}  {"routine" if ok else "NOT A ROUTINE (hook its jmp thunk instead?)"}')
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main(sys.argv[1:])
