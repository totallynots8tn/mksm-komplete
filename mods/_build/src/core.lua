-- ===== shared spawn core v2 (identical in ldk, ldk_bosses and randomizer) =====
-- Spawn manager: 50 group records, 0xA6C bytes apart. A group holds 23 entry
-- slots of 0x74 bytes from +0x18; the signed 16-bit count at +0xA68 sits in
-- the last slot, so 22 slots are usable. Entry fields used here:
--   +0x00 enemy type   +0x5A u16 spawn delay in frames after the group start
-- The spawn tick (0x1D23F0) spawns entries in order once start+delay has
-- passed, and stops at the first entry that is not yet due.
local MANAGER        = 0x006DBFB0
local GROUP_STRIDE   = 0xA6C
local GROUP_LIMIT    = 50
local MANAGER_END    = MANAGER + GROUP_LIMIT * GROUP_STRIDE
local ENTRY_BASE     = 0x18
local ENTRY_STRIDE   = 0x74
local ENTRY_SLOTS    = 22
local COUNT_OFFSET   = 0xA68
local ENABLED_OFFSET = 0xA6A
local DELAY_OFFSET   = 0x5A
local ST_START       = 0x2091C
local ST_GROUP       = 0x20920
local ST_SPAWNED     = 0x20922
local ST_CONTROLLER  = 0x20924
local ST_ACTIVE      = 0x2092A
local ST_FORCE       = 0x2092C
local CTRL_ALIVE     = 0xA0
local FRAME_COUNTER  = 0x005CE878
-- Actor creation (0x16C550) refuses any type missing from this six-slot
-- table (0x1C1580), so it is the set of enemy types that can spawn right now.
local LOADED_TYPES   = 0x006CA69C
local LOADED_SLOTS   = 6
local NO_TYPE        = 0xFFFFFFFF
-- Character pool (0x510040): 12 slots including both players. Flags are a
-- u16 array at [pool+0x0C]; a zero flag is a free slot (0x16B630).
local CHAR_POOL      = 0x00510040
local CHAR_FLAGS     = 0x0C
local CHAR_POOL_SIZE = 0x005142A4

-- Guest memory on the Recomp is a 4 GiB space: game and user allocations
-- below 0x7FFE0000, physical RAM at 0x80000000 and 0xF0000000 (64 MiB each),
-- system pools at 0xB0000000 and thread stacks at 0xD0000000.
local function plausible(p)
    if p < 0x10000 or p % 4 ~= 0 then
        return false
    end
    return p < 0x7FFE0000
        or (p >= 0x80000000 and p < 0x84000000)
        or (p >= 0xB0000000 and p < 0xC0000000)
        or (p >= 0xD0000000 and p < 0xE0000000)
        or (p >= 0xF0000000 and p < 0xF4000000)
end

local function group_base(index)
    return MANAGER + index * GROUP_STRIDE
end

local function entry_address(group, slot)
    return group_base(group) + ENTRY_BASE + slot * ENTRY_STRIDE
end

-- Group and slot of an entry address inside the spawn manager, or nil.
local function entry_index(entry)
    if entry < MANAGER + ENTRY_BASE or entry >= MANAGER_END then
        return nil
    end
    local group = (entry - MANAGER) // GROUP_STRIDE
    local offset = (entry - MANAGER) % GROUP_STRIDE - ENTRY_BASE
    if offset < 0 or offset % ENTRY_STRIDE ~= 0 or offset // ENTRY_STRIDE >= ENTRY_SLOTS then
        return nil
    end
    return group, offset // ENTRY_STRIDE
end

local function group_count(base)
    local count = game.read_u16(base + COUNT_OFFSET)
    if count > ENTRY_SLOTS then
        return nil
    end
    return count
end

local rng_state = 0x2C9277B5

local function rnd()
    local x = rng_state
    x = x ~ ((x << 13) & 0xFFFFFFFF)
    x = x ~ (x >> 17)
    x = x ~ ((x << 5) & 0xFFFFFFFF)
    rng_state = x & 0xFFFFFFFF
    return rng_state
end

local function reseed(value)
    local seed = (value ~ game.read_u32(FRAME_COUNTER)) & 0xFFFFFFFF
    if seed == 0 then
        seed = 0x2C9277B5
    end
    rng_state = seed
    rnd()
end

-- Character memory slots (cGameMemInterface 0x6322F8): [+0x10] slot count,
-- [+0x24] table of 20-byte slots {heap id, enemy type, ...}. Each loaded enemy
-- type owns one slot, and its models are carved from that slot's heap when
-- an actor is created (0x1D7880 -> 0x114730). An exhausted heap returns null
-- there and the game crashes, so every spawn is checked against the real heap.
local INTERFACE      = 0x006322F8
local SLOT_COUNT     = 0x10
local SLOT_TABLE     = 0x24
local SLOT_STRIDE    = 20
local SLOT_TYPE      = 4
local HEAP_REGISTRY  = 0x0062EC60
local HEAP_STRIDE    = 0x68
local HEAP_TOTAL     = 0x04
local HEAP_CURRENT   = 0x08
local HEAP_END       = 0x0C
local HEAP_FRAGMENT  = 0x1C
local HEAP_LIST      = 0x20
local HEAP_MARGIN    = 0x4000

-- Free bytes (sum) and largest free block of a game heap, or nil.
local function heap_space(heap)
    if heap >= 0x80 then
        return nil
    end
    local record = HEAP_REGISTRY + heap * HEAP_STRIDE
    local total = game.read_u32(record + HEAP_TOTAL)
    if total == 0 or total > 0x10000000 then
        return nil
    end
    if game.read_u32(record + HEAP_FRAGMENT) ~= 0 then
        local node = game.read_u32(record + HEAP_LIST)
        local free, largest, walked = 0, 0, 0
        while node ~= 0 do
            if not plausible(node) or walked >= 256 then
                return nil
            end
            local first = game.read_u32(node + 8)
            local last = game.read_u32(node + 0xC)
            if last > first then
                free = free + (last - first)
                if last - first > largest then
                    largest = last - first
                end
            end
            node = game.read_u32(node + 4)
            walked = walked + 1
        end
        return free, largest
    end
    local current = game.read_u32(record + HEAP_CURRENT)
    local last = game.read_u32(record + HEAP_END)
    if last < current then
        return nil
    end
    return last - current, last - current
end

local function slot_table()
    local count = game.read_u32(INTERFACE + SLOT_COUNT)
    local table_ptr = game.read_u32(INTERFACE + SLOT_TABLE)
    if count == 0 or count > 16 or not plausible(table_ptr) then
        return nil, 0
    end
    return table_ptr, count
end

local function heap_of(kind)
    local table_ptr, count = slot_table()
    if table_ptr == nil then
        return nil
    end
    for slot = 0, count - 1 do
        local base = table_ptr + slot * SLOT_STRIDE
        if game.read_u32(base + SLOT_TYPE) == kind then
            local heap = game.read_u32(base)
            if heap < 0x80 then
                return heap
            end
            return nil
        end
    end
    return nil
end

-- Bytes one actor of each type took from its heap, measured on real spawns.
-- Model memory is never returned when an enemy dies (the probe showed every
-- slot heap only shrinking until the area reloads), so each extra enemy
-- permanently uses memory that a later authored spawn of that type needs.
local costs = {}
local DEFAULT_COST = 0x30000   -- above every cost measured so far (max 0x26780)

local function cost_of(kind)
    return costs[kind] or DEFAULT_COST
end

-- True when the type's heap can hold `count` more actors plus a margin.
-- Without a measured cost it answers false (used by the last-resort guard).
local function can_afford(kind, count)
    local cost = costs[kind]
    local heap = heap_of(kind)
    if cost == nil or heap == nil then
        return false
    end
    local _, largest = heap_space(heap)
    return largest ~= nil and largest >= cost * count + HEAP_MARGIN
end

-- Authored spawns still to come in this area, per type. Rebuilt when a group
-- starts and decremented as authored entries spawn.
local need = {}
local started = {}
-- The game recycles a dead enemy's model instance for the next spawn of its
-- type (probe, run 2026-10-24: type F's heap stopped shrinking after 5
-- instances while 18 more spawned and died). Memory follows how many are
-- alive at once, not how many spawn. peak[kind] is the largest authored wave
-- of a type in the groups still to come; allocs[kind] counts the instances
-- this area has allocated so far (heap drops seen at spawns).
local peak = {}
local allocs = {}
local ENTITY_BASE   = 0x005D1AB8   -- char table; pool slot i is entity i
local ENTITY_STRIDE = 0x3238
local ENTITY_KIND   = 0x1DFE

-- Live actors of a type (pool slots 2-11 in use with that character ID).
-- Their instances are held, so they cannot be recycled for the next wave.
local function alive_of(kind)
    local flags = game.read_u32(CHAR_POOL + CHAR_FLAGS)
    if not plausible(flags) then
        return 0
    end
    local n = 0
    for i = 2, 11 do
        if game.read_u16(flags + i * 2) ~= 0
            and game.read_u16(ENTITY_BASE + i * ENTITY_STRIDE + ENTITY_KIND) == kind then
            n = n + 1
        end
    end
    return n
end

local function rebuild_need(current, current_orig)
    need = {}
    peak = {}
    for group = 0, GROUP_LIMIT - 1 do
        local base = group_base(group)
        if game.read_u8(base + ENABLED_OFFSET) ~= 0 then
            local count = group_count(base)
            if group == current then
                count = current_orig
            elseif started[group] then
                count = 0
            end
            if count then
                local wave = {}
                for slot = 0, count - 1 do
                    local kind = game.read_u32(entry_address(group, slot))
                    need[kind] = (need[kind] or 0) + 1
                    wave[kind] = (wave[kind] or 0) + 1
                end
                for kind, n in pairs(wave) do
                    if n > (peak[kind] or 0) then peak[kind] = n end
                end
            end
        end
    end
end

local function spawned_authored(kind)
    if need[kind] and need[kind] > 0 then
        need[kind] = need[kind] - 1
    end
end

-- Can one EXTRA actor of this type spawn without starving any authored spawn
-- left in the area? Dead enemies' instances are recycled, so it leaves room for
-- the part of the largest authored wave to come that the area's free
-- (allocated but not held by a live actor) instances don't cover, plus this
-- extra and one spare.
local function surplus_for(kind)
    local heap = heap_of(kind)
    if heap == nil then
        return false
    end
    local _, largest = heap_space(heap)
    if largest == nil then
        return false
    end
    local missing = (peak[kind] or 0) - ((allocs[kind] or 0) - alive_of(kind))
    if missing < 0 then missing = 0 end
    return largest >= (2 + missing) * cost_of(kind) + HEAP_MARGIN
end

-- Slot heaps only shrink until the area reloads, so free memory going back up
-- is a reliable reload signal even when the level-load hook does not fire.
local last_free = {}
local heap_kind = {}

local function memory_reloaded()
    local table_ptr, count = slot_table()
    if table_ptr == nil then
        return false
    end
    local grew = false
    for slot = 0, count - 1 do
        local heap = game.read_u32(table_ptr + slot * SLOT_STRIDE)
        local kind = game.read_u32(table_ptr + slot * SLOT_STRIDE + SLOT_TYPE)
        if heap < 0x80 then
            local free = heap_space(heap)
            if free then
                if last_free[heap] and free > last_free[heap] + 0x10000 then
                    grew = true
                    allocs[kind] = 0             -- rebuilt: no instances to recycle
                end
                last_free[heap] = free
            end
            if heap_kind[heap] ~= kind then
                heap_kind[heap] = kind
                allocs[kind] = 0                 -- a new type took this heap
            end
        end
    end
    return grew
end

-- Spawn measurement: snapshot every slot heap before 0x1D1D40, attribute the
-- largest drop afterwards to the type that owns that heap.
local snapshot = nil
-- Recycling evidence, session-wide (it's how the engine works, not a property
-- of one area): a spawn that succeeded without taking memory from its type's
-- heap reused a dead enemy's instance. Until one is seen, the spawn guard
-- only trusts fresh memory. v1 patch 2 (2026-10-24, ported to the dev line
-- 2026-10-25): instances are counted per heap lifetime, not per map: a type
-- that stays loaded across maps keeps its heap and instances (Goro's Lair,
-- type 0xF), and memory_reloaded() resets a heap's count when the heap is
-- rebuilt or another type takes it. Costs stay session-wide, so the guard is
-- never blind (patch 1 reset them per map and the Kitana fight crashed on a
-- spawn with no memory for its model).
local recycling_seen = false
local pending_entry = nil

local function measure_before(entry)
    local table_ptr, count = slot_table()
    snapshot = nil
    pending_entry = nil
    if entry and entry_index(entry) then
        pending_entry = entry        -- read its type afterwards: a clone may be retyped first
    end
    if table_ptr == nil then
        return
    end
    snapshot = {}
    for slot = 0, count - 1 do
        local base = table_ptr + slot * SLOT_STRIDE
        local heap = game.read_u32(base)
        local free = heap < 0x80 and heap_space(heap) or nil
        snapshot[slot] = { kind = game.read_u32(base + SLOT_TYPE), heap = heap, free = free }
    end
end

local function measure_after(result)
    if snapshot == nil then
        return
    end
    local spawned = nil
    if pending_entry and result and result ~= 0 then
        spawned = game.read_u32(pending_entry)
    end
    for _, slot in pairs(snapshot) do
        if slot.free then
            local now = heap_space(slot.heap)
            if now and now < slot.free then
                local used = slot.free - now
                if used > (costs[slot.kind] or 0) then
                    costs[slot.kind] = used
                end
                allocs[slot.kind] = (allocs[slot.kind] or 0) + 1
            elseif now and slot.kind == spawned then
                recycling_seen = true
            end
        end
    end
    snapshot = nil
end

-- Spawn guard: hide a type from the allowed-type table for one 0x1D1D40 call.
-- 0x1C1580 then rejects it before anything is allocated, the game treats it
-- like any failed spawn and moves on. guard_restore() must run in the after.
local hidden = nil

local function guard_hide(kind)
    for slot = 0, LOADED_SLOTS - 1 do
        local address = LOADED_TYPES + slot * 4
        if game.read_u32(address) == kind then
            game.write_u32(address, NO_TYPE)
            hidden = { address = address, kind = kind }
            return
        end
    end
end

local function guard_restore()
    if hidden then
        if game.read_u32(hidden.address) == NO_TYPE then
            game.write_u32(hidden.address, hidden.kind)
        end
        hidden = nil
    end
end

-- Last resort: cancel a spawn whose heap cannot hold one more actor of its
-- measured cost (the game would crash in 0x113EF0). No margin here, so an
-- authored spawn that fits is never touched. A dead enemy's instance is
-- recycled for the next spawn of its type (once this session has seen it
-- happen), so a spawn with a free instance (allocated this area, not held by
-- a live actor) needs no new memory. 2026-10-24
-- soft-lock: after LDK's extras used up type 0xF's fresh heap, the guard
-- cancelled every spawn of the fatality tutorial's respawning wave in Goro's
-- Lair; the room never got enemies and the gate never opened.
local function guard_spawn(entry)
    local kind = game.read_u32(entry)
    local heap = heap_of(kind)
    if costs[kind] == nil or heap == nil then
        return true
    end
    local _, largest = heap_space(heap)
    if largest ~= nil and largest < costs[kind]
        and not (recycling_seen and (allocs[kind] or 0) - alive_of(kind) > 0) then
        guard_hide(kind)
        return false
    end
    return true
end

local function free_char_slots()
    local flags = game.read_u32(CHAR_POOL + CHAR_FLAGS)
    local size = game.read_u32(CHAR_POOL_SIZE)
    if not plausible(flags) or size == 0 or size > 32 then
        return 0
    end
    local free = 0
    for slot = 0, size - 1 do
        if game.read_u16(flags + slot * 2) == 0 then
            free = free + 1
        end
    end
    return free
end

local function is_loaded(kind)
    if kind == NO_TYPE then
        return false
    end
    for slot = 0, LOADED_SLOTS - 1 do
        if game.read_u32(LOADED_TYPES + slot * 4) == kind then
            return true
        end
    end
    return false
end

-- Level census: how often each enemy type is authored across all groups.
-- Types authored once per level are bosses or elites and are never cloned
-- or re-rolled. The census is rebuilt whenever the loaded level changes.
local census = {}
local census_key = nil

-- Spawn entries carry per-slot behaviour that suits the authored enemy: the
-- spawn-near-player flag (+0x58) and anchor (+0x24), the initial AI state
-- (+0x5C, e.g. climbing in from outside the arena), patrol/target (+0x60),
-- navmesh (+0x70) and special-mover data (+0x10). A type may only move into
-- an entry whose behaviour signature matches an entry the area authors for
-- that type, or it can end up stuck out of bounds (an Oni dropped into a
-- wall-climber's slot).
local SIGNATURE_FIELDS = { 0x10, 0x24, 0x5C, 0x60, 0x70 }
local sig_types = {}            -- signature -> { [type] = true }
local GENERIC = -1              -- signature shared by every plain entry

-- A plain entry has no special entrance: no spawn-near-player flag, no
-- initial AI state (the spawner treats -1 and 0xA as none) and no special
-- mover data. Any regular enemy the area spawns from plain entries can use
-- any plain entry. Special entries keep an exact-match signature.
local function signature(entry)
    local flag = game.read_u8(entry + 0x58)
    local state = game.read_u32(entry + 0x5C)
    local mover = game.read_u32(entry + 0x10)
    if flag == 0 and (state == 0xFFFFFFFF or state == 0xA) and mover == 0xFFFFFFFF then
        return GENERIC
    end
    local sig = flag
    for _, offset in ipairs(SIGNATURE_FIELDS) do
        sig = (sig * 1000003 + game.read_u32(entry + offset)) & 0xFFFFFFFFFFFF
    end
    return sig
end

local function fits(kind, entry)
    local types = sig_types[signature(entry)]
    return types ~= nil and types[kind] == true
end

local function level_key()
    local key = 0
    for group = 0, GROUP_LIMIT - 1 do
        local base = group_base(group)
        key = (key * 31 + game.read_u32(base) + game.read_u32(base + 8) * 7
            + game.read_u32(base + 0xC) * 13) & 0xFFFFFFFF
    end
    return key
end

-- The census is built a few groups per callback (each callback has a
-- 100,000-instruction budget and a full level can hold 50 x 22 entries).
-- Until census_ready() the spawn mods leave every group as authored.
local CENSUS_STEP = 10
local census_next = GROUP_LIMIT

local function census_step()
    local last = census_next + CENSUS_STEP - 1
    if last > GROUP_LIMIT - 1 then
        last = GROUP_LIMIT - 1
    end
    for group = census_next, last do
        local base = group_base(group)
        if game.read_u8(base + ENABLED_OFFSET) ~= 0 then
            local count = group_count(base)
            if count then
                for slot = 0, count - 1 do
                    local entry = entry_address(group, slot)
                    local kind = game.read_u32(entry)
                    census[kind] = (census[kind] or 0) + 1
                    local sig = signature(entry)
                    local types = sig_types[sig] or {}
                    types[kind] = true
                    sig_types[sig] = types
                end
            end
        end
    end
    census_next = last + 1
    return census_next >= GROUP_LIMIT
end

local function census_ready()
    return census_key ~= nil and census_next >= GROUP_LIMIT
end

-- Starts a new census when the loaded level changed. Returns true then.
local function refresh_census()
    local key = level_key()
    if key == census_key then
        return false
    end
    census_key = key
    census = {}
    sig_types = {}
    census_next = 0
    reseed(key)
    census_step()
    return true
end

-- Bosses are never "common", however many times an area authors them: the
-- Oni Warlord is authored twice in its area, so census alone made it a
-- regular enemy that Shaolin Shuffle and LDK could move into a grunt's spawn
-- entry outside the arena. Super bosses are the critical-path giants; Mortal
-- Kombat characters are the human-sized bosses.
local SUPER_BOSSES = {
    [28] = true,               -- Orochi
    [34] = true,               -- warlord (club)
    [36] = true,               -- Oni Warlord
    [45] = true, [55] = true,  -- Goro
    [47] = true,               -- two-slot boss
    [56] = true,               -- Kintaro
    [57] = true,               -- Reptile (two-slot)
    [60] = true, [61] = true,  -- Shang Tsung
    [62] = true,               -- Shao Kahn
}
local MK_BOSSES = {
    [50] = true, [53] = true,  -- Scorpion
    [51] = true,               -- Noob Saibot
    [52] = true,               -- Kano
    [54] = true,               -- Baraka
    [63] = true,               -- Kitana
    [64] = true,               -- Mileena
    [65] = true,               -- Jade
    [66] = true,               -- Ermac
    [67] = true,               -- Sub-Zero
    [68] = true,               -- Smoke
    [59] = true,               -- Reptile, story fight (map 144): authored in three
                               -- waves, so LDK cloned him as a common enemy (v1 patch 4)
    [82] = true,               -- Reptile (VS model)
}
local function is_boss(kind)
    return SUPER_BOSSES[kind] == true or MK_BOSSES[kind] == true
end

-- Fatality tutorial rooms (three in the game; Goro's Lair map 99 is one) gate
-- their exit on their own respawning wave and on a fatality. Changed waves
-- soft-locked map 99 twice on 2026-10-24, so an area whose map triggers test
-- isfatalityfull, fatalityover or fatalitytutor stays vanilla: LDK adds no
-- extras and Shuffle changes nothing there. Triggers: records 0xD8 apart from
-- [0x682020], count +0xA8C0, conditions +0x58 (count) / +0x5C (command slots);
-- a slot's command object is [mgr + slot*24 + 0x11C00], its execute [[obj]].
local TRIGGERS_PTR = 0x00682020
local FATALITY_TESTS = { [0x00013382] = true, [0x000166B3] = true, [0x000145ED] = true }
local fatality_seen_key, fatality_seen = nil, false

local function fatality_area()
    local mgr = game.read_u32(TRIGGERS_PTR)
    if not plausible(mgr) then
        return false
    end
    local count = game.read_u32(mgr + 0xA8C0)
    local key = mgr * 1000 + count
    if key == fatality_seen_key then
        return fatality_seen
    end
    fatality_seen_key, fatality_seen = key, false
    local commands = game.read_u32(mgr + 0x1254C)
    if count > 200 or commands > 200 then
        return false
    end
    for index = 0, count - 1 do
        local rec = mgr + index * 0xD8
        local n = game.read_u32(rec + 0x58)
        local slots = game.read_u32(rec + 0x5C)
        if n > 0 and n <= 12 and plausible(slots) then
            for j = 0, n - 1 do
                local slot = game.read_u32(slots + j * 4)
                if slot <= commands then
                    local object = game.read_u32(mgr + slot * 24 + 0x11C00)
                    local vtable = plausible(object) and game.read_u32(object) or 0
                    if plausible(vtable) and FATALITY_TESTS[game.read_u32(vtable)] then
                        fatality_seen = true
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function is_common(kind)
    return kind ~= NO_TYPE and (census[kind] or 0) >= 2 and not is_boss(kind)
end
-- ===== end shared spawn core =====
