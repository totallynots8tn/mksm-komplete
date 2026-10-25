
-- ===== Shaolin Shuffle 0.8.1 =====
-- Shuffles enemy types across every spawn slot of the current area. Model
-- memory is never freed when an enemy dies, and each type's heap is sized
-- for how many of it the area authors in total. A shuffle keeps those totals
-- exactly, so memory use stays vanilla however much changes. The shuffle is
-- planned and written in one spawn-tick callback per area (at most MAX_SLOTS
-- writes), so the per-type totals other mods read are never half-applied. Bosses and once-per-area elites keep their places, as do
-- characters without an enemy memory slot (players, allies).
local LOAD_GROUPS = 0x00014D2C
local START_GROUP = 0x001D2600
local SPAWN_ENTRY = 0x001D1D40
local SPAWN_TICK  = 0x001D23F0
local FIX_PASSES  = 3            -- passes that swap away unchanged entries
local MAX_SLOTS   = 150          -- entries shuffled per area (write and instruction budgets)

-- 0.7: outsiders. An area that preloads a single regular enemy type (Goro's
-- Lair: type 0xF only) has nothing to shuffle. The map's roster is a static,
-- writable preload list read by 0xCFAB0(desc) (thunk 0x15DEE) after the spawn
-- groups load: desc+0x24 holds -1 terminated character IDs, and desc+0x20 is
-- how many listed types may be missing before the whole preload is skipped.
-- Appending one regular type from another level makes the game load it into a
-- free memory slot itself, with its own heap. The shuffle then turns plain
-- entries into it: OUTSIDER_MIN in every group that has a plain entry (0.8:
-- every room gets one, the area's first group included), and OUTSIDER_CHANCE
-- percent of the rest, up to OUTSIDER_PER_GROUP per group and OUTSIDER_TOTAL
-- per area. build.py makes the Wild and Chaos variants by raising these.
--
-- There are 4 enemy memory slots. Over 164 logged group starts, vanilla never
-- had more than 3 enemy types loaded at once, so the outsider takes the slot
-- the game leaves spare. Scripted loads (modelstream, 0x17BA00) go through the
-- replace queue (0x17BA40), which unloads whatever holds the target slot
-- first, so a cutscene can still evict the outsider. If that happens, the
-- converted entries go back to their own type and the area keeps its authored
-- roster from then on. The outsider pool is the regular types the probe saw
-- spawning as common enemies; all of them need one memory slot.
local PRELOAD            = 0x00015DEE
local DESC_CAP           = 0x20
local DESC_LIST          = 0x24
local GAME_MANAGER       = 0x005ACEBC
local GAME_MODE          = 0x88         -- 2 = versus
local OUTSIDERS          = { 10, 11, 12, 13, 14, 15, 26, 27 }
local OUTSIDER_MIN       = 1            -- outsiders guaranteed per group with a plain entry
local OUTSIDER_CHANCE    = 25           -- percent of the other plain entries that also become one
local OUTSIDER_PER_GROUP = 3
local OUTSIDER_TOTAL     = 30

local planned = false
local witnesses = {}             -- a few shuffled entries; a revert means a reload
local area_serial = 0            -- bumped when an area's spawn groups load
local rosters = {}               -- desc -> authored {cap, first, second, third}
local outsider = nil             -- { kind, desc } chosen for the loading area
local released = nil             -- { desc, area } whose outsider was evicted
local converted = {}             -- { entry, from } turned into the outsider

local function versus()
    local manager = game.read_u32(GAME_MANAGER)
    return plausible(manager) and game.read_u32(manager + GAME_MODE) == 2
end

-- Runs before 0xCFAB0 reads the preload list. Restores the map's authored
-- roster (an earlier visit may have appended to this static list) and, for a
-- single regular type, appends an outsider. A re-preload while the area still
-- has converted entries (0xD1910, after a cutscene) keeps the same outsider;
-- none of this depends on whether the spawn groups load before the preload.
local function plan_preload(desc)
    if not plausible(desc) or desc >= 0x01000000 then
        return
    end
    local roster = rosters[desc]
    if roster == nil then
        roster = { cap = game.read_u32(desc + DESC_CAP),
                   first = game.read_u32(desc + DESC_LIST),
                   second = game.read_u32(desc + DESC_LIST + 4),
                   third = game.read_u32(desc + DESC_LIST + 8) }
        rosters[desc] = roster
    end
    local kind = nil
    local single = roster.first >= 2 and roster.first <= 49 and not is_boss(roster.first)
        and roster.second == NO_TYPE and not fatality_area()
    local evicted = released and released.desc == desc and released.area == area_serial
    if single and not evicted and not versus() then
        if outsider and outsider.desc == desc and #converted > 0 then
            kind = outsider.kind
        else
            reseed(desc ~ area_serial)
            local pool = {}
            for _, candidate in ipairs(OUTSIDERS) do
                if candidate ~= roster.first then
                    pool[#pool + 1] = candidate
                end
            end
            kind = pool[rnd() % #pool + 1]
        end
    end
    if kind then
        game.write_u32(desc + DESC_LIST + 4, kind)
        game.write_u32(desc + DESC_LIST + 8, NO_TYPE)
        if roster.cap < 2 then
            game.write_u32(desc + DESC_CAP, 2)
        end
        outsider = { kind = kind, desc = desc }
    else
        if game.read_u32(desc + DESC_LIST + 4) ~= roster.second then
            game.write_u32(desc + DESC_LIST + 4, roster.second)
            game.write_u32(desc + DESC_LIST + 8, roster.third)
        end
        if game.read_u32(desc + DESC_CAP) ~= roster.cap then
            game.write_u32(desc + DESC_CAP, roster.cap)
        end
        outsider = nil           -- every map load preloads its own roster
    end
end

-- The outsider type when it is loaded for this area, else nil.
local function outsider_kind()
    if outsider == nil then
        return nil
    end
    if is_loaded(outsider.kind) and heap_of(outsider.kind) ~= nil then
        return outsider.kind
    end
    return nil
end

-- A cutscene's modelstream evicted the outsider: put the converted entries
-- back to their own type so they don't stream it into another free slot.
local function release_outsider()
    if #converted == 0 or outsider == nil or is_loaded(outsider.kind) then
        return
    end
    for _, c in ipairs(converted) do
        if game.read_u32(c.entry) == outsider.kind then
            game.write_u32(c.entry, c.from)
        end
    end
    converted = {}
    -- those entries now hold their own type again: not a sign of a reload
    local kept = {}
    for _, w in ipairs(witnesses) do
        if w.to ~= outsider.kind then
            kept[#kept + 1] = w
        end
    end
    witnesses = kept
    released = { desc = outsider.desc, area = area_serial }
    outsider = nil
end

-- Turn plain entries into the outsider: OUTSIDER_MIN per group first, so every
-- room gets one, then OUTSIDER_CHANCE percent of the rest, within
-- OUTSIDER_PER_GROUP per group and OUTSIDER_TOTAL per area. A re-plan that
-- finds earlier conversions still in place keeps them instead of adding more.
local function convert_outsiders(plain)
    local kind = outsider_kind()
    if kind == nil then
        converted = {}
        return
    end
    local kept = {}
    for _, c in ipairs(converted) do
        if game.read_u32(c.entry) == kind then
            kept[#kept + 1] = c
        end
    end
    converted = kept
    if #converted > 0 then
        return
    end
    for i = #plain, 2, -1 do
        local j = rnd() % i + 1
        plain[i], plain[j] = plain[j], plain[i]
    end
    local per_group = {}
    local function convert(slot)
        local from = game.read_u32(slot.entry)
        if from == kind then
            return
        end
        game.write_u32(slot.entry, kind)
        converted[#converted + 1] = { entry = slot.entry, from = from }
        per_group[slot.group] = (per_group[slot.group] or 0) + 1
        slot.done = true
        if #witnesses < 4 then
            witnesses[#witnesses + 1] = { entry = slot.entry, from = from, to = kind }
        end
    end
    for _, slot in ipairs(plain) do
        if #converted >= OUTSIDER_TOTAL then
            return
        end
        if (per_group[slot.group] or 0) < OUTSIDER_MIN then
            convert(slot)
        end
    end
    for _, slot in ipairs(plain) do
        if #converted >= OUTSIDER_TOTAL then
            return
        end
        if not slot.done and (per_group[slot.group] or 0) < OUTSIDER_PER_GROUP
            and rnd() % 100 < OUTSIDER_CHANCE then
            convert(slot)
        end
    end
end

local function shuffle_area(skip_started)
    planned = true
    if fatality_area() then
        return                   -- fatality room: vanilla (core.lua)
    end
    local classes = {}           -- signature -> { slots = {}, kinds = {} }
    local eligible = {}          -- type -> may be shuffled (cached per call)
    local plain = {}             -- plain eligible entries, outsider candidates
    local total = 0
    for group = 0, GROUP_LIMIT - 1 do
        local base = group_base(group)
        if game.read_u8(base + ENABLED_OFFSET) ~= 0 and not skip_started[group] then
            local count = group_count(base)
            for slot = 0, (count or 0) - 1 do
                local kind = game.read_u32(entry_address(group, slot))
                local ok = eligible[kind]
                if ok == nil then
                    ok = is_common(kind) and is_loaded(kind) and heap_of(kind) ~= nil
                    eligible[kind] = ok
                end
                if total < MAX_SLOTS and ok then
                    local entry = entry_address(group, slot)
                    local sig = signature(entry)
                    local class = classes[sig] or { slots = {}, kinds = {} }
                    class.slots[#class.slots + 1] = { entry = entry, from = kind }
                    class.kinds[#class.kinds + 1] = kind
                    classes[sig] = class
                    total = total + 1
                    if sig == GENERIC then
                        plain[#plain + 1] = { entry = entry, group = group }
                    end
                end
            end
        end
    end
    -- the group spawning now stays out of the shuffle, but its entries that
    -- haven't spawned yet can still take the outsider (0.8: the area's first
    -- room gets one too)
    if game.read_u8(MANAGER + ST_ACTIVE) ~= 0 then
        local group = game.read_u16(MANAGER + ST_GROUP)
        local base = group_base(group)
        if group < GROUP_LIMIT and skip_started[group] and game.read_u8(base + ENABLED_OFFSET) ~= 0 then
            local count = group_count(base) or 0
            for slot = game.read_u16(MANAGER + ST_SPAWNED), count - 1 do
                local entry = entry_address(group, slot)
                local kind = game.read_u32(entry)
                local ok = eligible[kind]
                if ok == nil then
                    ok = is_common(kind) and is_loaded(kind) and heap_of(kind) ~= nil
                    eligible[kind] = ok
                end
                if ok and signature(entry) == GENERIC then
                    plain[#plain + 1] = { entry = entry, group = group }
                end
            end
        end
    end
    witnesses = {}
    for _, class in pairs(classes) do
        local slots, kinds = class.slots, class.kinds
        local n = #kinds
        for i = n, 2, -1 do
            local j = rnd() % i + 1
            kinds[i], kinds[j] = kinds[j], kinds[i]
        end
        -- Swap away entries that kept their own type where a swap changes both.
        for _ = 1, FIX_PASSES do
            for i = 1, n do
                if kinds[i] == slots[i].from then
                    local j = rnd() % n + 1
                    if kinds[j] ~= slots[i].from and kinds[i] ~= slots[j].from then
                        kinds[i], kinds[j] = kinds[j], kinds[i]
                    end
                end
            end
        end
        for i = 1, n do
            if kinds[i] ~= slots[i].from then
                game.write_u32(slots[i].entry, kinds[i])
                if #witnesses < 4 then
                    witnesses[#witnesses + 1] = { entry = slots[i].entry, from = slots[i].from, to = kinds[i] }
                end
            end
        end
    end
    convert_outsiders(plain)
end

local function reverted()
    for _, w in ipairs(witnesses) do
        if game.read_u32(w.entry) == w.from then
            return true
        end
    end
    return false
end

local seen_started = {}

local hooks = {
    {
        address = LOAD_GROUPS,
        after = function(ctx)
            census_key = nil
            planned = false
            seen_started = {}
            area_serial = area_serial + 1
            converted = {}
        end,
    },
    {
        address = PRELOAD,
        before = function(ctx)
            plan_preload(game.read_u32(ctx.esp + 4))
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
            local reloaded = memory_reloaded()
            local new_area = refresh_census()
            if new_area or reloaded then
                allocs = {}          -- the heaps were rebuilt: no instances to recycle yet
            end
            if new_area or reloaded or (planned and reverted()) then
                planned = false
                seen_started = {}
            end
            -- groups that already ran, and this one (another mod may have
            -- expanded it already), stay out of the area's shuffle
            seen_started[index] = true
            -- the shuffle runs in the next spawn tick, its own callback, so the
            -- census and the shuffle never share one instruction budget
        end,
    },
    {
        address = SPAWN_TICK,
        before = function(ctx)
            if ctx.ecx ~= MANAGER then
                return
            end
            release_outsider()
            if census_key == nil or planned then
                return
            end
            if not census_ready() then
                census_step()
            else
                shuffle_area(seen_started)
            end
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
            if entry_index(entry) then
                guard_spawn(entry)
            end
        end,
        after = function(ctx)
            guard_restore()
            measure_after(ctx.eax)
        end,
    },
}
