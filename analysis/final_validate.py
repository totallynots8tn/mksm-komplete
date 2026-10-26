import tarfile, json, hashlib, re, pathlib, struct, sys, lzma
from lupa import LuaRuntime

root = pathlib.Path(__file__).resolve().parent.parent
allowed = set(
    int(line.strip(), 16)
    for line in (root / 'analysis/routine_targets.txt').read_text().splitlines()
    if line.strip()
)
XBE = '48240902bf4a04eb89376217c529531032d3370749bcce91a194878cc49db74a'
pkgs = [
    ('ldk', 'mods/ldk/dist/ldk-3.2.0.tar.xz', '3.2.0'),
    ('unlock_all', 'mods/unlock_all_mod/dist/unlock_all-1.1.0.tar.xz', '1.1.0'),
    ('env_kill_xp', 'mods/env_kill_xp/dist/env_kill_xp-2.0.0.tar.xz', '2.0.0'),
    ('randomizer', 'mods/randomizer/dist/randomizer-0.6.0.tar.xz', '0.6.0'),
    ('coop_solo', 'mods/coop_solo/dist/coop_solo-0.5.4.tar.xz', '0.5.4'),
    ('mk_upgrade', 'mods/mk_upgrade/dist/mk_upgrade-0.3.0.tar.xz', '0.3.0'),
    ('mksmk_probe', 'mods/mksmk_probe/dist/mksmk_probe-0.8.2.tar.xz', '0.8.2'),
]
ok = True


def fail(msg):
    global ok
    ok = False
    print('FAIL:', msg)


mem = bytearray(16 * 1024 * 1024)

write_count = [0]
write_log = []
budget_on = [False]


def reset_budget():
    write_count[0] = 0
    write_log.clear()
    budget_on[0] = True


def count_write(address, width):
    if not budget_on[0]:
        return
    write_count[0] += 1
    if write_count[0] > 256:
        raise RuntimeError('routine write budget exceeded')
    write_log.append((address, width))


def r8(a):
    return mem[a]


def r16(a):
    return struct.unpack_from('<H', mem, a)[0]


def r32(a):
    return struct.unpack_from('<I', mem, a)[0]


def w8(a, v):
    count_write(a, 1)
    mem[a] = v & 0xFF


def w16(a, v):
    count_write(a, 2)
    struct.pack_into('<H', mem, a, v & 0xFFFF)


def w32(a, v):
    count_write(a, 4)
    struct.pack_into('<I', mem, a, v & 0xFFFFFFFF)


def lua_ctx(lua, esp=0, **kw):
    t = lua.table()
    t.esp = esp
    for k, v in kw.items():
        t[k] = v
    return t


def check_ustar(path):
    raw = lzma.decompress(path.read_bytes())
    pos = 0
    while True:
        hdr = raw[pos:pos + 512]
        if len(hdr) < 512:
            return 'truncated tar'
        if not any(hdr):
            return None
        # Recomp's tar_xz.cpp: Field(header+257, 6) must be "ustar".
        if hdr[257:263] != b'ustar\0':
            return 'non-USTAR magic'
        try:
            stored = int(hdr[148:156].split(b'\0')[0].strip() or b'0', 8)
        except ValueError:
            return 'bad tar checksum field'
        calc = sum(hdr[:148]) + 8 * 32 + sum(hdr[156:])
        if stored != calc:
            return 'bad tar checksum'
        try:
            size = int(hdr[124:136].split(b'\0')[0].strip() or b'0', 8)
        except ValueError:
            return 'bad tar size field'
        pos += 512 + ((size + 511) // 512) * 512


extracted = {}
for mid, rel, ver in pkgs:
    print('---', rel, '---')
    tar_error = check_ustar(root / rel)
    if tar_error:
        fail(tar_error)
    with tarfile.open(root / rel, 'r:xz') as tf:
        members = {m.name: m for m in tf.getmembers() if m.isfile()}
        if any(not m.isfile() for m in tf.getmembers()):
            fail('non-regular entry')
        m = json.loads(tf.extractfile('mod.json').read())
        if m['id'] != mid:
            fail('id mismatch')
        if m['install_dir'] != f'packages/{mid}':
            fail('install_dir mismatch')
        if m['type'] not in ('language', 'texture', 'gameplay', 'data', 'mixed'):
            fail('bad type')
        if m['schema'] not in (1, 2):
            fail('schema')
        if m['game']['xbe_sha256'] != XBE:
            fail('xbe sha')
        if m['version'] != ver:
            fail('version mismatch')
        if tuple(map(int, m['recomp'].split('.'))) > (0, 2, 0):
            fail('recomp too new')
        declared = set()
        for f in m['files']:
            p = f['path']
            if p in declared or p in ('mod.json', 'manifest.json') or p.endswith('.xdelta'):
                fail('reserved/dup ' + p)
            declared.add(p)
            if p not in members:
                fail('missing declared ' + p)
                continue
            data = tf.extractfile(p).read()
            if len(data) != f['size']:
                fail('size ' + p)
            if hashlib.sha256(data).hexdigest() != f['sha256']:
                fail('sha mismatch ' + p)
        undeclared = set(members) - declared - {'mod.json'}
        if undeclared:
            fail('undeclared ' + str(undeclared))
        if not m['routines']:
            fail('no routines')
        for r in m['routines']:
            if not (r.startswith('scripts/') and r.endswith('.lua')):
                fail('bad routine path ' + r)
            if r not in declared:
                fail('routine not declared ' + r)
        for feat in m.get('features', []):
            if feat not in ('files', 'gamedata', 'voices', 'fonts', 'movies', 'lua'):
                fail('feature ' + feat)
        for r in m['routines']:
            src = tf.extractfile(r).read()
            if len(src) > 1024 * 1024:
                fail('script over 1 MiB')
            text = src.decode()
            consts = {
                name: int(val, 16)
                for name, val in re.findall(r'local\s+(\w+)\s*=\s*0x([0-9A-Fa-f]+)', text)
            }
            addrs = []
            for line in text.splitlines():
                if line.lstrip().startswith('local '):
                    continue
                mm = re.search(r'address\s*=\s*(0x[0-9A-Fa-f]+|\w+)', line)
                if mm:
                    tok = mm.group(1)
                    if tok.startswith('0x'):
                        addrs.append(int(tok, 16))
                    elif tok in consts:
                        addrs.append(consts[tok])
            if len(set(addrs)) != len(addrs):
                fail('duplicate hook address')
            for a in addrs:
                if a not in allowed:
                    fail(f'hook {a:#x} not in routine_targets')
            print('hooks:', [hex(a) for a in addrs])
            extracted[mid] = text
        print('archive entries:', sorted(members))

if not ok:
    sys.exit(1)


def load_script(mid):
    lua = LuaRuntime(unpack_returned_tuples=True)
    game = lua.table(
        read_u8=r8, read_u16=r16, read_u32=r32,
        write_u8=w8, write_u16=w16, write_u32=w32,
    )
    lua.globals().game = game
    hooks = lua.execute(extracted[mid])
    out = {}
    for i in range(1, len(hooks) + 1):
        h = hooks[i]
        out[int(h['address'])] = h
        if not any(k in h for k in ('before', 'after', 'replace')):
            fail('hook without callback')
    return lua, out


# Character-heap fixtures: four CUSTOM_CHARACTER_MEMORY heap ids selected
# through the interface table, with registry records shaped like the game's.
INTERFACE = 0x6322F8
CUSTOM_COUNT = 0x10
CUSTOM_TABLE = 0x24
HEAP_REGISTRY = 0x62EC60
HEAP_STRIDE = 0x68
HEAP_TOTAL = 0x04
HEAP_CURRENT = 0x08
HEAP_END = 0x0C
HEAP_FRAGMENT = 0x1C
HEAP_LIST = 0x20
HEAP_IDS = (0x30, 0x31, 0x32, 0x33)
CUSTOM_TABLE_PTR = 0x210000
NODE_POOL = 0x220000


def heap_record(heap):
    return HEAP_REGISTRY + heap * HEAP_STRIDE


def set_heaps(free=0x20000, total=0x20000, fragment=False, ids=HEAP_IDS,
              count=None):
    w32(INTERFACE + CUSTOM_COUNT, len(ids) if count is None else count)
    w32(INTERFACE + CUSTOM_TABLE, CUSTOM_TABLE_PTR)
    for i, heap in enumerate(ids):
        w32(CUSTOM_TABLE_PTR + i * 20, heap)
        record = heap_record(heap)
        w32(record + HEAP_TOTAL, total)
        w32(record + HEAP_FRAGMENT, 1 if fragment else 0)
        if fragment:
            node = NODE_POOL + i * 0x10
            w32(node + 4, 0)
            w32(node + 8, 0x100000)
            w32(node + 0xC, 0x100000 + free)
            w32(record + HEAP_LIST, node)
        else:
            w32(record + HEAP_CURRENT, total - free)
            w32(record + HEAP_END, total)
            w32(record + HEAP_LIST, 0)


# LDK
lua, hooks = load_script('ldk')
load_hook = hooks[0x14D2C]
init_hook = hooks[0x1D1B80]
start_hook = hooks[0x1D2600]
tick_hook = hooks[0x1D23F0]
MANAGER = 0x6DBFB0
GROUP_STRIDE = 0xA6C
ENTRY_BASE = 0x18
ENTRY_STRIDE = 0x74
COUNT_OFFSET = 0xA68
ENABLED_OFFSET = 0xA6A
ACTOR_CAPACITY = 0x5142B8
STATE_GROUP = MANAGER + 0x20920
STATE_CONTROLLER = MANAGER + 0x20924
stack = 0x200000
table_ptr = 0x201000
groups_ptr = 0x202000

w32(ACTOR_CAPACITY, 7)
w32(STATE_GROUP, 0)
w32(STATE_CONTROLLER, 0)


def invoke(hook, name, **kw):
    reset_budget()
    hook[name](lua_ctx(lua, **kw))
    budget_on[0] = False
    return write_count[0]


def group_base(idx):
    return MANAGER + idx * GROUP_STRIDE


def set_group(idx, count, enabled=1):
    base = group_base(idx)
    for i in range(22):
        for off in range(0, 0x74, 4):
            w32(base + ENTRY_BASE + i * ENTRY_STRIDE + off, 0)
    for i in range(count):
        for off in range(0, 0x74, 4):
            w32(base + ENTRY_BASE + i * ENTRY_STRIDE + off,
                (idx << 24) | (i << 16) | off | 1)
    w16(base + COUNT_OFFSET, count)
    w8(base + ENABLED_OFFSET, enabled)
    return base


def entry_words(idx, i):
    base = group_base(idx) + ENTRY_BASE + i * ENTRY_STRIDE
    return [r32(base + off) for off in range(0, 0x74, 4)]


def init_group():
    return invoke(init_hook, 'before', esp=stack, ecx=MANAGER)


def current_group(idx):
    w32(STATE_GROUP, idx)


last_start_log = []


def start(idx):
    global last_start_log
    w32(stack + 4, idx)
    used = invoke(start_hook, 'before', esp=stack, ecx=MANAGER)
    last_start_log = list(write_log)
    if 'after' in start_hook:
        invoke(start_hook, 'after', esp=stack, ecx=MANAGER)
    return used


def tick():
    return invoke(tick_hook, 'before', esp=stack, ecx=MANAGER)


def load_level(total):
    w32(table_ptr + 8, groups_ptr)
    w32(groups_ptr, total)
    w32(stack + 4, table_ptr)
    invoke(load_hook, 'before', esp=stack, ecx=0)
    if 'after' in load_hook:
        invoke(load_hook, 'after', esp=stack, ecx=0)


def assert_expanded(idx, original, target):
    base = group_base(idx)
    assert r16(base + COUNT_OFFSET) == target
    assert r8(base + ENABLED_OFFSET) == 1
    for i in range(original, target):
        src = entry_words(idx, i % original)
        dst = entry_words(idx, i)
        assert dst[0x3C // 4] == 0
        for j, off in enumerate(range(0, 0x74, 4)):
            if off == 0x3C:
                continue
            assert dst[j] == src[j], (idx, i, off)


# The shared actor-array capacity is raised to the entry cap once, before the
# first group controller is allocated from it.
set_heaps()
assert r32(ACTOR_CAPACITY) == 7
assert init_group() == 1 and write_log == [(ACTOR_CAPACITY, 4)]
assert r32(ACTOR_CAPACITY) == 12
assert init_group() == 0 and r32(ACTOR_CAPACITY) == 12

# 3 enemies -> 6: the start callback only copies entries; the count must stay
# at its authored value until the spawner tick has verified the capacity.
set_group(3, 3)
used = start(3)
assert used == 84, used
count_addr = group_base(3) + COUNT_OFFSET
assert all(a != count_addr for a, _ in last_start_log)
assert r16(count_addr) == 3
current_group(3)
used = tick()
assert used == 1 and write_log == [(count_addr, 2)], (used, write_log)
assert r16(count_addr) == 6
assert_expanded(3, 3, 6)
# Already expanded: another wave must not multiply again.
assert start(3) == 0 and r16(count_addr) == 6

# 6 enemies -> 12 (worst case): every copy fits in the start callback and the
# spawner tick writes only the count.
set_group(5, 6)
assert start(5) == 168
assert r16(group_base(5) + COUNT_OFFSET) == 6
current_group(5)
used = tick()
assert used == 1, used
assert write_log[-1] == (group_base(5) + COUNT_OFFSET, 2)
assert_expanded(5, 6, 12)
assert tick() == 0

# 7 -> 12 and 12 -> 12 (already at the cap).
set_group(17, 7)
assert start(17) == 140
current_group(17)
assert tick() == 1
assert_expanded(17, 7, 12)
set_group(18, 12)
assert start(18) == 0
assert r16(group_base(18) + COUNT_OFFSET) == 12

# 2 enemies -> 4.
set_group(6, 2)
assert start(6) == 56
current_group(6)
assert tick() == 1
assert_expanded(6, 2, 4)

# Single-enemy, empty, maximum-size and disabled groups stay untouched.
for idx, count, enabled in ((2, 1, 1), (7, 0, 1), (8, 22, 1), (9, 4, 0)):
    set_group(idx, count, enabled)
    assert start(idx) == 0
    assert r16(group_base(idx) + COUNT_OFFSET) == count
    current_group(idx)
    assert tick() == 0
    assert r16(group_base(idx) + COUNT_OFFSET) == count

# Garbage in the loader-unused dword is not copied into duplicates.
set_group(10, 2)
w32(group_base(10) + ENTRY_BASE + 0x3C, 0xDEADBEEF)
assert start(10) == 56
current_group(10)
assert tick() == 1
assert_expanded(10, 2, 4)

# If the shared capacity is still at the original seven when the spawner tick
# runs, the deferred expansion is dropped without touching the count: a live
# controller may own 7-slot arrays. A later start retries it.
set_group(11, 6)
assert start(11) == 168
w32(ACTOR_CAPACITY, 7)
current_group(11)
assert tick() == 0
assert r16(group_base(11) + COUNT_OFFSET) == 6
w32(ACTOR_CAPACITY, 12)
assert start(11) == 168
current_group(11)
assert tick() == 1
assert_expanded(11, 6, 12)

# The guard is evaluated at tick time, after the controller exists.
set_group(12, 6)
w32(ACTOR_CAPACITY, 5)
assert start(12) == 168
w32(ACTOR_CAPACITY, 12)
current_group(12)
assert tick() == 1
assert_expanded(12, 6, 12)

# A tick for another group must keep the expansion pending.
set_group(15, 3)
assert start(15) == 84
current_group(4)
assert tick() == 0
assert r16(group_base(15) + COUNT_OFFSET) == 3
current_group(15)
assert tick() == 1
assert_expanded(15, 3, 6)

# Hooks ignore calls that do not come from the LDK group manager.
set_group(20, 3)
w32(stack + 4, 20)
assert invoke(start_hook, 'before', esp=stack, ecx=0x123456) == 0
assert r16(group_base(20) + COUNT_OFFSET) == 3
assert start(20) == 84
current_group(20)
assert invoke(tick_hook, 'before', esp=stack, ecx=0x123456) == 0
assert r16(group_base(20) + COUNT_OFFSET) == 3
assert tick() == 1
assert_expanded(20, 3, 6)

# A real level load resets the per-level expansion bookkeeping.
load_level(2)
set_group(3, 3)
assert r16(group_base(3) + COUNT_OFFSET) == 3
assert start(3) == 84
current_group(3)
assert tick() == 1
assert_expanded(3, 3, 6)

# A loader call that will not load (empty table) must not reset anything.
load_level(0)
assert start(3) == 0
assert r16(group_base(3) + COUNT_OFFSET) == 6

# Fresh sessions: an already-raised capacity is left alone and a lower one is
# raised to the entry cap. A controller that predates the script still owns
# seven slots, so the shared value must not be raised under it.
w32(STATE_CONTROLLER, 0)
w32(ACTOR_CAPACITY, 12)
lua, hooks = load_script('ldk')
assert invoke(hooks[0x1D1B80], 'before', esp=stack, ecx=MANAGER) == 0
assert r32(ACTOR_CAPACITY) == 12
w32(ACTOR_CAPACITY, 5)
lua, hooks = load_script('ldk')
assert invoke(hooks[0x1D1B80], 'before', esp=stack, ecx=MANAGER) == 1
assert r32(ACTOR_CAPACITY) == 12
w32(ACTOR_CAPACITY, 7)
w32(STATE_CONTROLLER, 0x400000)
lua, hooks = load_script('ldk')
assert invoke(hooks[0x1D1B80], 'before', esp=stack, ecx=MANAGER) == 0
assert r32(ACTOR_CAPACITY) == 7

# Sound pool capacities above the clamp are shrunk on the first constructor
# argument so the pools allocate small blocks from the character heap; values
# at or below the clamp are left untouched.
pool_hook = hooks[0x142B30]
w32(stack + 4, 0x100)
assert invoke(pool_hook, 'before', esp=stack, ecx=0x280000) == 1
assert r32(stack + 4) == 0x10
w32(stack + 4, 0x10)
assert invoke(pool_hook, 'before', esp=stack, ecx=0x280000) == 0
assert r32(stack + 4) == 0x10
w32(stack + 4, 0x8)
assert invoke(pool_hook, 'before', esp=stack, ecx=0x280000) == 0
assert r32(stack + 4) == 0x8
w32(stack + 4, 0x500)
assert invoke(pool_hook, 'before', esp=stack, ecx=0x280000) == 1
assert r32(stack + 4) == 0x10

# Character-heap guard. A full heap pays for the whole 2x expansion; a heap
# with room for only two extras shrinks the group; a heap at its reserve
# refuses and can retry later.
lua, hooks = load_script('ldk')
start_hook = hooks[0x1D2600]
tick_hook = hooks[0x1D23F0]
w32(ACTOR_CAPACITY, 12)
set_heaps()
set_group(26, 3)
assert start(26) == 84
current_group(26)
assert tick() == 1
assert_expanded(26, 3, 6)

set_heaps(free=0x8000 + 2 * 0x1000 + 0xFFF)
set_group(27, 3)
assert start(27) == 56
current_group(27)
assert tick() == 1
assert_expanded(27, 3, 5)

set_heaps(free=0x8000)
set_group(28, 3)
assert start(28) == 0
current_group(28)
assert tick() == 0
assert r16(group_base(28) + COUNT_OFFSET) == 3
set_heaps()
assert start(28) == 84
current_group(28)
assert tick() == 1
assert_expanded(28, 3, 6)

# Headroom that vanishes between start and tick shrinks or cancels the
# expansion; the count is never raised beyond what the heaps can pay for.
set_heaps()
set_group(29, 3)
assert start(29) == 84
set_heaps(free=0x8000 + 0x1000 + 1)
current_group(29)
assert tick() == 1
assert_expanded(29, 3, 4)

set_heaps()
set_group(32, 4)
assert start(32) == 112
set_heaps(free=0x8000)
current_group(32)
assert tick() == 0
assert r16(group_base(32) + COUNT_OFFSET) == 4
set_heaps()
assert start(32) == 112
current_group(32)
assert tick() == 1
assert_expanded(32, 4, 8)

# The allocator walks the fragment list when the heap has splits.
set_heaps(fragment=True)
set_group(33, 2)
assert start(33) == 56
current_group(33)
assert tick() == 1
assert_expanded(33, 2, 4)
set_heaps(fragment=True, free=0x8000)
set_group(34, 2)
assert start(34) == 0
assert r16(group_base(34) + COUNT_OFFSET) == 2

# Missing or malformed heap state fails closed: no expansion at all.
set_heaps(count=0)
set_group(35, 3)
assert start(35) == 0
set_heaps(ids=(0, 0x31, 0x32, 0x33))
set_group(36, 3)
assert start(36) == 0
set_heaps()
set_group(35, 3)
assert start(35) == 84
current_group(35)
assert tick() == 1
assert_expanded(35, 3, 6)

print('LDK actor-capacity, entry-duplication, heap-guard and sound-pool runtime ok')

# Unlock
w32(0x4FC348, 1)
w32(0x4FC34C, 2)
w32(0x4FC350, 4)
w32(0x4FC354, 8)
for i, bit in enumerate(range(14, 23)):
    w32(0x4FC380 + i * 4, 1 << bit)
w32(0x4FC3A8, 1 << 24)
w32(0x4FC3AC, 1 << 25)
w32(0x4FC3B0, 1 << 26)
w32(0x4FC3B8, 1 << 28)
w32(0x4FC3BC, 1 << 29)
w32(0x4FC3C0, 1 << 30)
w32(0x4FC3C4, 1 << 31)
lua, hooks = load_script('unlock_all')
BITSET = 0x5A375C
expected = [0] * 13
for first, last in ((101, 164), (166, 341), (343, 358)):
    for bit in range(first, last + 1):
        expected[bit // 32] |= 1 << (bit % 32)
for a in (0x4FC390, 0x4FC394, 0x4FC398, 0x4FC3A8, 0x4FC3AC, 0x4FC3B0,
          0x4FC3B8, 0x4FC3BC, 0x4FC3C0, 0x4FC3C4):
    expected[2] |= r32(a)
for a in (0x4FC348, 0x4FC34C, 0x4FC350, 0x4FC354):
    expected[3] |= r32(a)
for a in (0x4FC380, 0x4FC384, 0x4FC388, 0x4FC38C, 0x4FC390, 0x4FC394,
          0x4FC398, 0x4FC39C, 0x4FC3A0):
    expected[11] |= r32(a)
w32(BITSET, 0x12345678)
w32(BITSET + 48, 0x5A)
hooks[0x14D36]['after'](lua_ctx(lua))
words = [r32(BITSET + i * 4) for i in range(13)]
assert words[0] == 0x12345678
assert words[1] == 0
assert words[2] == 0xF71C0000
assert words[3] == 0xFFFFFFEF
assert words[5] == 0xFFFFFFDF
assert words[10] == 0xFFBFFFFF
assert words[4] == words[6] == words[7] == words[8] == words[9] == 0xFFFFFFFF
assert words[11] == 0x007FC07F
assert words[12] == 0x0101015A
for i in range(13):
    w32(BITSET + i * 4, 0)
hooks[0x127BB]['before'](lua_ctx(lua))
expected_reset = expected[:]
expected_reset[0] = 0
expected_reset[12] = 0x01010100
assert [r32(BITSET + i * 4) for i in range(13)] == expected_reset
before = [r32(BITSET + i * 4) for i in range(13)]
hooks[0x138F0]['before'](lua_ctx(lua))
assert [r32(BITSET + i * 4) for i in range(13)] == before
print('Unlock exact-mask/reapply/idempotence runtime ok')

# Env XP
lua, hooks = load_script('env_kill_xp')
kill = hooks[0x1F25B0]
rel = hooks[0x196360]
mgr = 0x700000
BASE = 0x6997D8
ALT = 0x680000
stack = 0x300000
cmd = 0x300100
SLOT = 3
P1 = 0x5D1AB8 + 0x200
P2 = 0x5D4CF0 + 0x200
w32(P1, 0x600000)
w32(P2, 0x610000)
w32(0x600000 + 0x2300, 0x620000)
w32(0x610000 + 0x2300, 0x630000)
w32(0x5ACEBC, mgr)
xp1 = mgr + 0x48F0 + 1 * 0x50
xp2 = mgr + 0x48F0 + 2 * 0x50
w32(xp1, 500)
w32(xp2, 500)
w32(stack + 8, cmd)


def env_award(hits=0, pid=0, owner=0x640000, slot=SLOT, table_base=BASE,
              command=cmd, manager=mgr, target=0x620000):
    w32(0x5ACEBC, manager)
    w32(target + 0x2308, hits)
    w32(stack + 8, command)
    if command >= 0x10000:
        w32(command + 0x10, pid)
    w32(stack + 4, slot)
    if table_base != 0:
        w32(table_base + slot * 0x30 + 0x10, owner)
    invoke(kill, 'before', esp=stack, ecx=0x510040)
    invoke(rel, 'before', esp=stack, ecx=table_base)
    invoke(kill, 'after', esp=stack, ecx=0x510040)


env_award(hits=0)
assert r32(xp1) == 550 and r32(xp2) == 550, (r32(xp1), r32(xp2))
env_award(hits=10)
assert r32(xp1) == 600 and r32(xp2) == 600, (r32(xp1), r32(xp2))
env_award(hits=20)
assert r32(xp1) == 700 and r32(xp2) == 700, (r32(xp1), r32(xp2))
env_award(hits=2000)
assert r32(xp1) == 1550 and r32(xp2) == 1550, (r32(xp1), r32(xp2))
env_award(hits=0xFFFFFFFF)
assert r32(xp1) == 1600 and r32(xp2) == 1600, (r32(xp1), r32(xp2))
env_award(hits=40, pid=1, target=0x630000)
assert r32(xp1) == 1800 and r32(xp2) == 1800, (r32(xp1), r32(xp2))
env_award(hits=40, owner=0x600000)
assert r32(xp1) == 1800 and r32(xp2) == 1800, (r32(xp1), r32(xp2))
env_award(hits=40, owner=0x610000)
assert r32(xp1) == 1800 and r32(xp2) == 1800, (r32(xp1), r32(xp2))
w32(stack + 4, SLOT)
invoke(rel, 'before', esp=stack, ecx=BASE)
assert r32(xp1) == 1800 and r32(xp2) == 1800, (r32(xp1), r32(xp2))
env_award(hits=40, owner=0)
assert r32(xp1) == 1800 and r32(xp2) == 1800, (r32(xp1), r32(xp2))
env_award(hits=40, manager=0)
assert r32(xp1) == 1800 and r32(xp2) == 1800, (r32(xp1), r32(xp2))
env_award(hits=10, command=0x2000)
assert r32(xp1) == 1850 and r32(xp2) == 1850, (r32(xp1), r32(xp2))
env_award(hits=30, pid=2)
assert r32(xp1) == 2000 and r32(xp2) == 2000, (r32(xp1), r32(xp2))
env_award(hits=20, slot=256)
assert r32(xp1) == 2000 and r32(xp2) == 2000, (r32(xp1), r32(xp2))
env_award(hits=20, table_base=0)
assert r32(xp1) == 2000 and r32(xp2) == 2000, (r32(xp1), r32(xp2))
w32(xp1, 0x7FFFFFFF)
env_award(hits=20)
assert r32(xp1) == 0x7FFFFFFF and r32(xp2) == 2100, (r32(xp1), r32(xp2))
env_award(hits=20, slot=4, table_base=ALT, owner=0x660000)
assert r32(xp2) == 2200, r32(xp2)
print('Env XP runtime ok')

# Randomizer: mirrors xorshift32 and the Lua shuffle so expected permutations
# can be asserted exactly.
MASK64 = (1 << 64) - 1


def xs32(state):
    x = state
    x = (x ^ ((x << 17) & MASK64)) & MASK64
    x = (x ^ (x >> 13)) & MASK64
    x = (x ^ ((x << 5) & MASK64)) & MASK64
    return x & 0xFFFFFFFF


def predicted_shuffle(count, seed):
    state = [seed]
    calls = []

    def rnd():
        state[0] = xs32(state[0])
        return state[0]

    types = [i for i in range(count)]
    for i in range(count - 1, 0, -1):
        j = rnd() % (i + 1)
        calls.append(('type', i, j))
        if j != i:
            types[i], types[j] = types[j], types[i]
    pos = [i for i in range(count)]
    for i in range(count - 1, 0, -1):
        j = rnd() % (i + 1)
        calls.append(('pos', i, j))
        if j != i:
            pos[i], pos[j] = pos[j], pos[i]
    shrunk = None
    if rnd() % 2 == 0:
        shrunk = (rnd() % count) + 1
    return types, pos, shrunk


lua, hooks = load_script('randomizer')
rz_load = hooks[0x14D2C]
rz_start = hooks[0x1D2600]
TYPE_OFF = 0x0
POS_OFF = 0x18


def rz_group_words(idx):
    base = group_base(idx) + ENTRY_BASE
    return [[r32(base + i * ENTRY_STRIDE + off) for off in range(0, 0x74, 4)]
            for i in range(22)]


# Two authored slots with distinct type and position markers.
set_group(21, 3)
g21_seed = (table_ptr ^ (2 << 8) ^ 1 ^ r32(group_base(0) + ENTRY_BASE)) & 0xFFFFFFFF
w32(table_ptr + 8, groups_ptr)
w32(groups_ptr, 2)
w32(stack + 4, table_ptr)
invoke(rz_load, 'before', esp=stack, ecx=0)
before21 = rz_group_words(21)
w32(stack + 4, 21)
used = invoke(rz_start, 'before', esp=stack, ecx=MANAGER)
types, pos, shrunk = predicted_shuffle(3, g21_seed)
after21 = rz_group_words(21)
for slot in range(3):
    assert after21[slot][TYPE_OFF // 4] == before21[types[slot]][TYPE_OFF // 4]
    for w in range(3):
        assert after21[slot][(POS_OFF + w * 4) // 4] == \
            before21[pos[slot]][(POS_OFF + w * 4) // 4]
assert (shrunk is None and r16(group_base(21) + COUNT_OFFSET) == 3) or \
       r16(group_base(21) + COUNT_OFFSET) == shrunk
# Every write stayed inside the group's entry region or the count field.
lo, hi = group_base(21) + ENTRY_BASE, group_base(21) + COUNT_OFFSET + 2
for a, _ in write_log:
    assert lo <= a < hi, hex(a)

# A second load reseeds: the same group randomizes differently (or at least
# the mod runs its shuffle again without errors and honors the budget).
w32(table_ptr + 8, groups_ptr)
w32(groups_ptr, 2)
w32(stack + 4, table_ptr)
invoke(rz_load, 'before', esp=stack, ecx=0)
w32(stack + 4, 21)
invoke(rz_start, 'before', esp=stack, ecx=MANAGER)
assert r16(group_base(21) + COUNT_OFFSET) <= 3

# Single/empty/disabled groups and foreign callers are ignored.
for idx, count, enabled in ((22, 1, 1), (23, 0, 1), (24, 3, 0)):
    set_group(idx, count, enabled)
    w32(stack + 4, idx)
    assert invoke(rz_start, 'before', esp=stack, ecx=MANAGER) == 0
    assert r16(group_base(idx) + COUNT_OFFSET) == count
set_group(25, 3)
w32(stack + 4, 25)
assert invoke(rz_start, 'before', esp=stack, ecx=0x99) == 0
assert r16(group_base(25) + COUNT_OFFSET) == 3

print('Randomizer shuffle/seed/guard runtime ok')

# LDK Boss Invasion: with an empty BOSS_TYPES it must match LDK 1.3.0.
lua, hooks = load_script('ldk_bosses')
bi_start = hooks[0x1D2600]
bi_tick = hooks[0x1D23F0]
bi_pool = hooks[0x142B30]
set_heaps()
w32(ACTOR_CAPACITY, 12)
w32(STATE_GROUP, 0)
w32(STATE_CONTROLLER, 0)
set_group(30, 3)
w32(stack + 4, 30)
assert invoke(bi_start, 'before', esp=stack, ecx=MANAGER) == 84
current_group(30)
assert invoke(bi_tick, 'before', esp=stack, ecx=MANAGER) == 1
assert r16(group_base(30) + COUNT_OFFSET) == 6
base30 = group_base(30) + ENTRY_BASE
for slot in range(3, 6):
    src = slot % 3
    for off in range(0, 0x74, 4):
        if off == 0x3C:
            continue
        assert r32(base30 + slot * ENTRY_STRIDE + off) == \
               r32(base30 + src * ENTRY_STRIDE + off), (slot, off)
w32(stack + 4, 0x100)
assert invoke(bi_pool, 'before', esp=stack, ecx=0x280000) == 1
assert r32(stack + 4) == 0x10

# The boss fork applies the same character-heap guard as the LDK core.
set_heaps(free=0x8000 + 0x1000 + 1)
set_group(32, 3)
w32(stack + 4, 32)
assert invoke(bi_start, 'before', esp=stack, ecx=MANAGER) == 28
current_group(32)
assert invoke(bi_tick, 'before', esp=stack, ecx=MANAGER) == 1
assert r16(group_base(32) + COUNT_OFFSET) == 4
set_heaps()

# With bosses configured, duplicated extras convert but authored slots and
# non-type fields stay identical to a plain LDK expansion.
patched = extracted['ldk_bosses'].replace(
    'local BOSS_TYPES     = {}',
    'local BOSS_TYPES     = {111, 222}', 1)
lua2 = LuaRuntime(unpack_returned_tuples=True)
game2 = lua2.table(read_u8=r8, read_u16=r16, read_u32=r32,
                   write_u8=w8, write_u16=w16, write_u32=w32)
lua2.globals().game = game2
hooks2 = lua2.execute(patched)
bi2_start = hooks2[3]
bi2_tick = hooks2[4]
for i in range(1, len(hooks2) + 1):
    h = hooks2[i]
    if int(h['address']) == 0x1D2600:
        bi2_start = h
    elif int(h['address']) == 0x1D23F0:
        bi2_tick = h
w32(ACTOR_CAPACITY, 12)
set_group(31, 3)
w32(stack + 4, 31)


def invoke2(hook, name, **kw):
    reset_budget()
    hook[name](lua_ctx(lua2, **kw))
    budget_on[0] = False
    return write_count[0]


assert invoke2(bi2_start, 'before', esp=stack, ecx=MANAGER) == 84
current_group(31)
assert invoke2(bi2_tick, 'before', esp=stack, ecx=MANAGER) == 4
count_addr31 = group_base(31) + COUNT_OFFSET
assert len(write_log) == 4, write_log
assert write_log[-1] == (count_addr31, 2), write_log
assert r16(count_addr31) == 6
base31 = group_base(31) + ENTRY_BASE
converted = 0
for slot in range(3, 6):
    t = r32(base31 + slot * ENTRY_STRIDE)
    if t in (111, 222):
        converted += 1
        src = slot % 3
        for off in range(4, 0x74, 4):
            if off == 0x3C:
                continue
            assert r32(base31 + slot * ENTRY_STRIDE + off) == \
                   r32(base31 + src * ENTRY_STRIDE + off), (slot, off)
assert converted == 3, converted
for slot in range(3):
    assert r32(base31 + slot * ENTRY_STRIDE) == (31 << 24) | (slot << 16) | 1

print('LDK Boss Invasion LDK-parity and injection runtime ok')
print('ALL ARCHIVES VALID AND RUNTIME TESTS PASSED')
