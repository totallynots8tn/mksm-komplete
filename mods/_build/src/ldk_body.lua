
-- ===== Legendary Dark Knight 3.9.1 (with Boss Invasion) =====
-- 3.6: a single-enemy group of a regular type is multiplied too when its
-- entry has a plain entrance (early levels such as Goro's Lair are mostly
-- single-enemy waves). Entries with a scripted entrance stay as authored.
-- Built as three variants (ldk x2, ldk_x3, ldk_x4): MULTIPLIER and
-- BOSS_MULTIPLIER are set per variant by build.py; only one may be enabled.
-- Each multi-enemy group gets clones appended after its authored entries
-- (up to 2x, 12 max). Clones are reinforcements: the spawn tick holds one back
-- while the 12-slot character pool is full. When a clone spawns it is given a
-- type the level can afford: its own if that heap has surplus beyond every
-- authored spawn still to come, otherwise another loaded common type that
-- does, otherwise it is cancelled. Sometimes the last clone of a group is a
-- boss or elite instead (Boss Invasion), under the same memory rule. A type
-- change is only made when the area authors that type in an entry with the
-- same behaviour signature, so nobody spawns into a slot it can't use.
-- 3.4: boss fights are cloned too (Boss clones, below).
local MAX_ENTRIES      = 12
local MULTIPLIER       = 2
local RESERVE_SLOTS    = 2        -- pool slots always left for scripted spawns
local STAGGER          = 20       -- frames between clones of one wave
local RETRY            = 20       -- frames before re-checking a full pool
local MAX_WAIT         = 60 * 90  -- stop holding clones back after ~90 seconds
local INVADER_CHANCE   = 50       -- percent of doubled groups that try an invader
local INVADERS_PER_AREA = 6
local ACTOR_CAPACITY   = 0x005142B8
local RUNTIME_FIELDS   = { [0x04] = true, [0x08] = true, [0x10] = true, [0x14] = true, [0x2C] = true }
local UNTOUCHED_FIELD  = 0x3C
local DELAY_DWORD      = 0x58

local LOAD_GROUPS      = 0x00014D2C
local INIT_GROUP       = 0x001D1B80
local START_GROUP      = 0x001D2600
local SPAWN_TICK       = 0x001D23F0
local SPAWN_ENTRY      = 0x001D1D40

-- Boss clones. A boss entry (even alone in its group, i.e. its arena) with a
-- plain entrance gets BOSS_MULTIPLIER - 1 clones, spawned and memory-checked
-- like any other clone: a clone that does not fit becomes a regular enemy with
-- the same entrance behaviour or is cancelled. A boss with a scripted entrance
-- is not cloned (its clone loses the entrance data). The boss lists live in
-- core.lua. 3.5.1: only Mortal Kombat characters are cloned; super bosses
-- (Oni Warlord, Orochi, Goro, Kintaro, Shang Tsung, Shao Kahn...) stay
-- vanilla unless SUPER_CLONES is set, and never invade other groups.
local BOSS_MULTIPLIER = 2
local SUPER_CLONES    = false
-- 3.9: MK characters keep their boss AI when cloned or used as reinforcements
-- (a second Kitana runs her damage-triggered throw, which carried the player
-- out of bounds, and could not be killed). Benched until the UMK phase can
-- give them versus-style behaviour.
local MK_CLONES       = false

-- MK roster reinforcements (3.8). Any clone may come in as a Mortal Kombat
-- character the area already has loaded (the story streams Johnny Cage,
-- Raiden and others into some areas), ROSTER_CHANCE percent of the time,
-- up to ROSTER_PER_AREA per area. Only into plain spawn entries (no scripted
-- entrance), and only when that character's memory has room under the
-- recycling-aware rule. Super bosses are never used.
local ROSTER = { [76] = true,  -- Johnny Cage
                 [70] = true } -- Raiden
for kind in pairs(MK_BOSSES) do ROSTER[kind] = true end
local ROSTER_CHANCE   = 0         -- 3.9: benched (boss AI, see MK_CLONES); was 30
local ROSTER_PER_AREA = 6 * (MULTIPLIER - 1)

local groups = {}
local controllers_seen = false
local invaders = 0

local roster_spawns = 0

local function reset_area()
    roster_spawns = 0
    groups = {}
    started = {}
    need = {}
    peak = {}
    allocs = {}
    invaders = 0
end

local function ensure_capacity()
    if controllers_seen then
        return
    end
    if game.read_u32(ACTOR_CAPACITY) < MAX_ENTRIES then
        game.write_u32(ACTOR_CAPACITY, MAX_ENTRIES)
    end
end

local function entry_cap()
    local capacity = game.read_u32(ACTOR_CAPACITY)
    if capacity < MAX_ENTRIES then
        return capacity
    end
    return MAX_ENTRIES
end

local function copy_entry(group, destination, source, wave)
    local dst = entry_address(group, destination)
    local src = entry_address(group, source)
    local offset = 0
    while offset < ENTRY_STRIDE do
        if offset == DELAY_DWORD then
            local word = game.read_u32(src + offset)
            local delay = (word >> 16) + STAGGER * wave
            if delay > 0xFFF0 then
                delay = 0xFFF0
            end
            game.write_u32(dst + offset, (word & 0xFFFF) | (delay << 16))
        elseif RUNTIME_FIELDS[offset] then
            game.write_u32(dst + offset, 0xFFFFFFFF)
        elseif offset ~= UNTOUCHED_FIELD then
            game.write_u32(dst + offset, game.read_u32(src + offset))
        end
        offset = offset + 4
    end
end

local function plan_expansion(group)
    local base = group_base(group)
    if game.read_u8(base + ENABLED_OFFSET) == 0 then
        return
    end
    local count = group_count(base)
    if count == nil then
        return
    end
    if fatality_area() then
        groups[group] = { orig = count, target = count }   -- fatality room: vanilla
        return
    end
    local state = groups[group]
    if state then
        if count == state.target then
            rebuild_need(group, state.orig)
            return
        end
        groups[group] = nil      -- the level reloaded this group
    end
    rebuild_need(group, count)
    local cap = entry_cap()
    if count >= cap then
        groups[group] = { orig = count, target = count }
        return
    end
    local eligible, bosses = {}, {}
    for slot = 0, count - 1 do
        local kind = game.read_u32(entry_address(group, slot))
        if is_common(kind) and heap_of(kind) then
            eligible[#eligible + 1] = slot
        elseif ((MK_CLONES and MK_BOSSES[kind]) or (SUPER_CLONES and SUPER_BOSSES[kind]))
            and signature(entry_address(group, slot)) == GENERIC then
            bosses[#bosses + 1] = slot
        end
    end
    -- boss clones first, right after the authored entries
    local target = count
    for _, slot in ipairs(bosses) do
        for _ = 1, BOSS_MULTIPLIER - 1 do
            if target < cap then
                copy_entry(group, target, slot, target - count + 1)
                target = target + 1
            end
        end
    end
    local boss_end = target
    -- then the regular reinforcements: multi-enemy groups, and single-enemy
    -- groups whose entry has a plain entrance
    if #eligible > 0 and (count >= 2 or signature(entry_address(group, eligible[1])) == GENERIC) then
        local extra = count * (MULTIPLIER - 1)
        if target + extra > cap then
            extra = cap - target
        end
        for wave = 1, extra do
            copy_entry(group, target, eligible[((wave - 1) % #eligible) + 1], target - count + 1)
            target = target + 1
        end
    end
    if target > count then
        game.write_u16(base + COUNT_OFFSET, target)
    end
    groups[group] = { orig = count, target = target,
                      invader = target > boss_end and rnd() % 100 < INVADER_CHANCE and target - 1 or nil }
end

-- Loaded types with a heap, as {common = {...}, elite = {...}}, minus `skip`.
local function loaded_kinds(skip)
    local common, elite, seen = {}, {}, {}
    for index = 0, LOADED_SLOTS - 1 do
        local kind = game.read_u32(LOADED_TYPES + index * 4)
        if kind ~= NO_TYPE and kind ~= skip and not seen[kind] and heap_of(kind) then
            seen[kind] = true
            if is_common(kind) then
                common[#common + 1] = kind
            elseif census[kind] == 1 and not is_boss(kind) then
                elite[#elite + 1] = kind
            end
        end
    end
    return common, elite
end

local function first_with_surplus(list, entry)
    local count = #list
    if count == 0 then
        return nil
    end
    local first = rnd() % count
    for i = 0, count - 1 do
        local kind = list[((first + i) % count) + 1]
        if fits(kind, entry) and surplus_for(kind) then
            return kind
        end
    end
    return nil
end

-- Loaded MK roster characters that can take this (plain) entry and have room.
local function roster_pick(entry)
    if roster_spawns >= ROSTER_PER_AREA or signature(entry) ~= GENERIC then
        return nil
    end
    local list, seen = {}, {}
    for index = 0, LOADED_SLOTS - 1 do
        local kind = game.read_u32(LOADED_TYPES + index * 4)
        if ROSTER[kind] and not SUPER_BOSSES[kind] and not seen[kind] and heap_of(kind) then
            seen[kind] = true
            list[#list + 1] = kind
        end
    end
    local count = #list
    if count == 0 then
        return nil
    end
    local first = rnd() % count
    for i = 0, count - 1 do
        local kind = list[((first + i) % count) + 1]
        if surplus_for(kind) then
            return kind
        end
    end
    return nil
end

-- Decide what a clone spawns as, or cancel it. Runs in 0x1D1D40's before.
local function prepare_clone(entry, state, slot)
    if free_char_slots() - RESERVE_SLOTS < 1 then
        guard_hide(game.read_u32(entry))
        return
    end
    local kind = game.read_u32(entry)
    local pick = nil
    if state.invader == slot and invaders < INVADERS_PER_AREA then
        local _, elite = loaded_kinds(nil)
        pick = first_with_surplus(elite, entry)
        if pick then
            invaders = invaders + 1
        end
    end
    if pick == nil and rnd() % 100 < ROSTER_CHANCE then
        pick = roster_pick(entry)
        if pick then
            roster_spawns = roster_spawns + 1
        end
    end
    if pick == nil and surplus_for(kind) then
        pick = kind
    end
    if pick == nil then
        local common = loaded_kinds(kind)
        pick = first_with_surplus(common, entry)
    end
    if pick == nil then
        guard_hide(kind)
        return
    end
    if pick ~= kind then
        game.write_u32(entry, pick)
    end
end

-- A group that started while the census was being built spawned as authored.
-- When the census completes and that group is still the one spawning, expand
-- it then: its clones follow its authored entries.
local function expand_deferred()
    if game.read_u8(MANAGER + ST_ACTIVE) == 0 then
        return
    end
    local group = game.read_u16(MANAGER + ST_GROUP)
    local state = groups[group]
    if state and state.deferred and state.target == state.orig then
        groups[group] = nil
        plan_expansion(group)
    end
end

local function gate_clones()
    if game.read_u8(MANAGER + ST_ACTIVE) == 0 or game.read_u16(MANAGER + ST_FORCE) ~= 0 then
        return
    end
    local group = game.read_u16(MANAGER + ST_GROUP)
    local state = groups[group]
    if state == nil or state.target <= state.orig then
        return
    end
    local base = group_base(group)
    if game.read_u16(base + COUNT_OFFSET) ~= state.target then
        groups[group] = nil
        return
    end
    local slot = game.read_u16(MANAGER + ST_SPAWNED)
    if slot >= state.target then
        return
    end
    local start = game.read_u32(MANAGER + ST_START)
    local now = game.read_u32(FRAME_COUNTER)
    local room = free_char_slots() - RESERVE_SLOTS
    while slot < state.target do
        local entry = entry_address(group, slot)
        if now < start + game.read_u16(entry + DELAY_OFFSET) then
            return
        end
        if slot < state.orig or room >= 1 then
            room = room - 1
        else
            local controller = game.read_u32(MANAGER + ST_CONTROLLER)
            if not plausible(controller) or game.read_u16(controller + CTRL_ALIVE) == 0 then
                return           -- nobody left to wait for; the spawn entry hook decides
            end
            state.wait = state.wait or now
            if now - state.wait > MAX_WAIT then
                return
            end
            local delay = now - start + RETRY
            if delay < 0xFFF0 then
                game.write_u16(entry + DELAY_OFFSET, delay)
            end
            return
        end
        slot = slot + 1
    end
end

local hooks = {
    {
        address = LOAD_GROUPS,
        after = function(ctx)
            reset_area()
            census_key = nil
        end,
    },
    {
        address = INIT_GROUP,
        before = function(ctx)
            ensure_capacity()
            controllers_seen = true
        end,
    },
    {
        address = START_GROUP,
        before = function(ctx)
            if ctx.ecx ~= MANAGER then
                return
            end
            local index = game.read_u32(ctx.esp + 4)
            if index >= GROUP_LIMIT then
                return
            end
            ensure_capacity()
            if refresh_census() or memory_reloaded() then
                reset_area()
            end
            started[index] = true
            if not census_ready() then
                -- the census is still being built; the group starts as
                -- authored and is expanded when the census completes, if it
                -- is still spawning (3.9)
                local count = group_count(group_base(index)) or 0
                groups[index] = { orig = count, target = count, deferred = true }
                return
            end
            plan_expansion(index)
        end,
    },
    {
        address = SPAWN_ENTRY,
        before = function(ctx)
            measure_before(game.read_u32(ctx.esp + 4))
            if ctx.ecx ~= MANAGER then
                return
            end
            local entry = game.read_u32(ctx.esp + 4)
            local group, slot = entry_index(entry)
            if group == nil then
                return
            end
            local state = groups[group]
            if state and slot >= state.orig and slot < state.target then
                prepare_clone(entry, state, slot)
            else
                spawned_authored(game.read_u32(entry))
                guard_spawn(entry)
            end
        end,
        after = function(ctx)
            guard_restore()
            measure_after(ctx.eax)
        end,
    },
    {
        address = SPAWN_TICK,
        before = function(ctx)
            if ctx.ecx ~= MANAGER then
                return
            end
            if census_key ~= nil and not census_ready() then
                census_step()
                if census_ready() then
                    expand_deferred()
                end
                return
            end
            gate_clones()
        end,
    },
}

-- ===== Legendary bosses (3.3, off by default since 3.4) =====
-- Boss characters can get BOSS_HP_MULT times their health. The actor's
-- health is at +0x368 and its maximum at +0x370; setHealth (0x153CD0, ecx =
-- actor, [esp+4] = new value) clamps to the maximum and updates the HUD. The
-- actor's entity is [actor+0x31C] (char table 0x5D1AB8, 0x3238 apart; slots 0
-- and 1 are the players) and its character ID is the s16 at entity+0x1DFE.
-- The first time a boss actor's health changes, its maximum and current
-- health are multiplied and the incoming value is moved by the same amount,
-- so the hit that triggered it still does its normal damage. A respawned
-- actor (maximum no longer the one written here) is scaled again.
local BOSS_HP_MULT = 1            -- 1 = off; 2 doubles boss health
local SET_HEALTH   = 0x00153CD0
local CHAR_BASE    = 0x005D1AB8
local CHAR_SIZE    = 0x3238
local boss_max = {}               -- actor -> maximum written by this mod

local function boss_actor(actor)
    if not plausible(actor) then return false end
    local entity = game.read_u32(actor + 0x31C)
    if entity < CHAR_BASE + 2 * CHAR_SIZE or (entity - CHAR_BASE) % CHAR_SIZE ~= 0 then return false end
    if (entity - CHAR_BASE) // CHAR_SIZE >= 12 then return false end
    return is_boss(game.read_u16(entity + 0x1DFE))
end

hooks[#hooks + 1] = {
    address = SET_HEALTH,
    before = function(ctx)
        if BOSS_HP_MULT <= 1 then return end
        local actor = ctx.ecx
        if not boss_actor(actor) then return end
        local max = game.read_u32(actor + 0x370)
        if max == 0 or max > 0x100000 or boss_max[actor] == max then return end
        local cur = game.read_u32(actor + 0x368)
        if cur > max then return end
        local new_max = max * BOSS_HP_MULT
        local new_cur = cur * BOSS_HP_MULT
        game.write_u32(actor + 0x370, new_max)
        game.write_u32(actor + 0x368, new_cur)
        local incoming = game.read_u32(ctx.esp + 4)
        if incoming >= 0x80000000 then incoming = incoming - 0x100000000 end
        local moved = incoming + (new_cur - cur)
        if moved < 0 then moved = 0 end
        if moved > new_max then moved = new_max end
        game.write_u32(ctx.esp + 4, moved)
        boss_max[actor] = new_max
    end,
}
