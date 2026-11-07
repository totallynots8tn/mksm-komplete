
-- ===== Shaolin Shuffle 0.13.2 =====
-- 0.13.2: the tree mouth and tree arms are hazards (HAZARDS, core.lua): never
-- shuffled or mixed between rooms.
-- 0.13.1: maps 161-191 (the cut Survival stages and the versus arenas) are
-- Time Rifts' arenas and stay as authored: no outsider, no shuffle (SURVIVAL).
-- 0.13.0: outsiders in full areas too, by a swap where it was tested (SWAPS).
-- 0.12.1: no more tree mouths or tree arms as outsiders (OUTSIDERS, core.lua).
-- 0.12.0: Mortal Kombat warriors (see MK_WARRIORS below).
-- 0.11.5: the shared boss list (core.lua) with corrected character names
-- covers every Mortal Kombat character.
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
-- per area (0.11: the old Wild variant's values, now the only setting).
--
-- There are 4 enemy memory slots. Over 164 logged group starts, vanilla never
-- had more than 3 enemy types loaded at once, so the outsider takes the slot
-- the game leaves spare. Scripted loads (modelstream, 0x17BA00) go through the
-- replace queue (0x17BA40), which unloads whatever holds the target slot
-- first, so a cutscene can still evict the outsider. If that happens, the
-- converted entries go back to their own type and the area keeps its authored
-- roster from then on. The outsider pool is the regular types the probe saw
-- spawning as common enemies; all of them need one memory slot. 0.9 widened it
-- with the types the QA logs' area census saw as commons in 7+ areas.
--
-- 0.11: cross-area everywhere. Any map whose roster has a regular type gets an
-- outsider, as long as the roster plus the outsider fit in SLOT_BUDGET of the
-- 4 enemy memory slots. Each listed type costs its character-table slots
-- (+0x04: 1, or 2 for IDs 47 and 57), bosses and MK characters included. A
-- budget of 3 is vanilla's own observed maximum and keeps one slot spare for
-- scripted loads and types a level streams in on the spot. Every slot heap is
-- the same fixed size (0x232000), so the outsider's memory doesn't depend on
-- what the area authors. The list is a -1 padded array of 8 words, so one
-- more entry always fits; the words it overwrites are cached and restored.
--
-- 0.11.1: most of the main path preloads 3 types (QA run 2026-10-31: maps
-- 101, 104, 107, 192 all did), so 0.11.0 left it untouched. The budget rises
-- to all 4 slots (vanilla's own preload fills 4 on six maps) when the area's
-- spawn groups, which load before the preload, author no type the roster
-- doesn't list: then nothing in the level streams in on the spot, and a
-- cutscene's modelstream still evicts the outsider cleanly (release_outsider).
-- The scan only counts when this area's groups loaded since the last preload.
--
-- 0.11.3: 0.11.2 had the outsider replace one of the roster's common types
-- on maps that load three. It crashed loading the Wu Shi entrance (map 104,
-- roster 14/71/77; QA 2026-10-31 14:06 and 14:12, a null+0x68 read in the
-- loader's frame): the map's scene places characters of its listed types
-- outside the spawn groups, so every listed type must stay loaded. Removed;
-- the roster is only ever added to.
--
-- 0.11.4: a cutscene evicting the outsider and a re-shuffle could fall in one
-- spawn tick: up to 45 restored entries plus a whole shuffle (243 writes) is
-- over the runtime's 256 writes per callback, which disables the script. The
-- restore now has its tick to itself. Groups Time Rifts marks as its own
-- (core.lua) are never shuffled or converted. The outsider pool moved to
-- core.lua, so LDK can recognise the outsider.
local PRELOAD            = 0x00015DEE
local DESC_CAP           = 0x20
local DESC_LIST          = 0x24
local LIST_WORDS         = 8
local CHAR_TABLE         = 0x004FA9F0   -- 91 rows of 0x30, by character ID
local CHAR_ROW           = 0x30
local CHAR_SLOTS         = 0x04
local SLOT_BUDGET        = 3            -- when the level may stream a type in on the spot
local SLOT_BUDGET_FULL   = 4            -- when every authored type is in the roster
-- 0.13: outsiders in full areas. An area whose roster leaves no memory slot
-- for an outsider gets one by a swap instead: one listed regular type whose
-- spawn entries are all plain leaves the preload list for the outsider, and
-- every one of its entries becomes the outsider. 0.11.2's swap crashed the
-- Wu Shi entrance (see 0.11.3), so only pairs that loaded live without a
-- crash swap (2026-11-03: the type swapped in memory, the map loaded at entry
-- 1). Map 103's Tarkatans crashed like map 104's, and map 128 streamed its
-- corpses back over the outsider, so neither is here; the Wu Shi maps with
-- Tarkatans weren't tested. Keyed by map descriptor.
local SWAPS = {
    [0x004FE318] = 12,   -- map 64: archers (with Oni and handlers)
    [0x004FE6B0] = 10,   -- map 69: captains
    [0x004FE990] = 10,   -- map 74, the Pit II: captains
    [0x00501620] = 10,   -- map 197: captains
    [0x005013F8] = 10,   -- map 194: captains
    [0x00501288] = 27,   -- map 192, the Evil Monastery: priests
    [0x004FEDE0] = 15,   -- map 101: Oni
    [0x004FF458] = 4,    -- map 129: clay soldiers
    [0x004FF510] = 4,    -- map 130: clay soldiers
    [0x004FF680] = 17,   -- map 135: type 17
    [0x004FF738] = 18,   -- map 136: corpses
    [0x004FF7F0] = 18,   -- map 137: corpses
    [0x004FE038] = 9,    -- map 45: type 9
    [0x004FE260] = 31,   -- map 48: Shokan
}
local MAX_SWAP_ENTRIES   = 150          -- entries a swap may convert in the preload's callback (write budget)
-- 0.13.1: the cut Survival stages (and the versus arenas between them) are
-- only reached through Time Rifts, which loads its fights there and adds to
-- their preload lists (soul_rift.lua). Shuffle leaves them as authored.
local MAP_TABLE          = 0x005020E8   -- map number -> descriptor
local CURRENT_MAP        = 0x00505970
local SURVIVAL_FIRST, SURVIVAL_LAST = 161, 191
local survival_descs = nil
local function survival_desc(desc)
    if survival_descs == nil then
        survival_descs = {}
        for m = SURVIVAL_FIRST, SURVIVAL_LAST do
            survival_descs[game.read_u32(MAP_TABLE + m * 4)] = true
        end
    end
    return survival_descs[desc] == true
end
local GAME_MANAGER       = 0x005ACEBC
local GAME_MODE          = 0x88         -- 2 = versus
-- 0.11: one mod with what was the Wild variant: the v1 pool plus the regular
-- types the QA logs saw as commons in 7+ areas (OUTSIDERS, in core.lua).
local OUTSIDER_MIN       = 1            -- outsiders guaranteed per group with a plain entry
local OUTSIDER_CHANCE    = 50           -- percent of the other plain entries that also become one
local OUTSIDER_PER_GROUP = 5
local OUTSIDER_TOTAL     = 45
-- 0.12: Mortal Kombat warriors. An area that gets an outsider gets one of
-- these instead MK_CHANCE percent of the time: a human-sized Mortal Kombat
-- character with one memory slot and animations of its own
-- (analysis/mk_roster). Two things about them come from the game:
-- * Their per-character AI setup (the switch on the type at 0xE2F11) makes
--   most of them unkillable for their scripted boss fights: actor +0xD4 = 0,
--   and TakeDamage (0x153E20) then stops their health at 1 so the fight's
--   script can play its ending. Shuffle sets +0xD4 back to 1 on every live
--   warrior of its own (keep_killable).
-- * Character table +0x08 is how many model copies the type's memory slot is
--   built for (tgtProcessObjectModel 0x113B50): 2 for these. So only
--   MK_PER_AREA entries, one per group, become the warrior, and an entry
--   that would spawn one copy too many goes back to its own type first
--   (keep_copies).
-- No warrior where the roster lists a boss (a boss arena), where the area's
-- spawn groups author the warrior's type (its own scripted fight), or when the
-- groups weren't freshly loaded (they can't be checked).
local MK_WARRIORS        = { 52, 54, 55, 56, 59, 65, 66, 67, 68, 69 }
local MK_CHANCE          = 35           -- percent of outsider areas that get a warrior instead
local MK_PER_AREA        = 2
local CHAR_COPIES        = 0x08         -- character table: model copies the type's slot holds
local ACTOR              = 0x200        -- entity: its actor
local CAN_KILL           = 0xD4         -- actor: 0 = its health stops at 1
local warrior_kinds = {}
for _, kind in ipairs(MK_WARRIORS) do
    warrior_kinds[kind] = true
end
-- 0.10: room mixing. An area whose rooms each author one enemy type shows no
-- variety from the signature-class swap alone, and (before 0.11) the outsider
-- path needed a single-type roster. So it also swaps plain entries between two types
-- in different rooms: each swap keeps both per-type totals exact (the heap
-- invariant), and the room that gave an entry gains one of the other type.
local MIX_PER_ROOM       = 1            -- pairs swapped into each single-type room
local MIX_TOTAL          = 24            -- pairs per area (a pair is two writes)

local planned = false
local witnesses = {}             -- a few shuffled entries; a revert means a reload
local area_serial = 0            -- bumped when an area's spawn groups load
local preload_serial = 0         -- area_serial at the last preload (0: no groups loaded yet)
local rosters = {}               -- desc -> authored { cap, list = {types}, after = {next two words} }
local outsider = nil             -- { kind, desc, area } chosen for the loading area
local released = nil             -- { desc, area } whose outsider was evicted
local converted = {}             -- { entry, from } turned into the outsider

local function versus()
    local manager = game.read_u32(GAME_MANAGER)
    return plausible(manager) and game.read_u32(manager + GAME_MODE) == 2
end

-- Memory slots a character needs (character table +0x04: 1, or 2).
local function slots_needed(kind)
    if kind > 90 then
        return 1
    end
    local slots = game.read_u32(CHAR_TABLE + kind * CHAR_ROW + CHAR_SLOTS)
    if slots < 1 or slots > 2 then
        return 1
    end
    return slots
end

-- The map's authored roster, read on the first visit (the list is static, and
-- later visits find our outsider in it).
local function authored_roster(desc)
    local roster = rosters[desc]
    if roster ~= nil then
        return roster
    end
    roster = { cap = game.read_u32(desc + DESC_CAP), list = {}, after = {} }
    for i = 0, LIST_WORDS - 1 do
        local kind = game.read_u32(desc + DESC_LIST + i * 4)
        if kind == NO_TYPE then
            break
        end
        roster.list[#roster.list + 1] = kind
    end
    local n = #roster.list
    if n + 2 <= LIST_WORDS then
        roster.after = { game.read_u32(desc + DESC_LIST + n * 4), game.read_u32(desc + DESC_LIST + (n + 1) * 4) }
    end
    rosters[desc] = roster
    return roster
end

-- Whether a roster can take an outsider: it has a regular type for the
-- outsider to stand in for, room in the list, and the slot budget left.
local function takes_outsider(roster, budget)
    local n = #roster.list
    if n == 0 or n + 2 > LIST_WORDS then
        return false
    end
    local regular, slots = false, 1
    for _, kind in ipairs(roster.list) do
        if kind >= 2 and kind <= 49 and not is_boss(kind) then
            regular = true
        end
        slots = slots + slots_needed(kind)
    end
    return regular and slots <= budget
end

-- Every character the area's spawn groups author (disabled groups included:
-- a trigger may enable them later).
local function authored_types()
    local authored = {}
    -- worst case 50 x 22 reads, so the address math is inlined (instruction budget)
    local read = game.read_u32
    for base = MANAGER, MANAGER_END - 1, GROUP_STRIDE do
        local count = game.read_u16(base + COUNT_OFFSET)
        if count > ENTRY_SLOTS then
            count = 0
        end
        local entry = base + ENTRY_BASE
        for _ = 1, count do
            authored[read(entry)] = true
            entry = entry + ENTRY_STRIDE
        end
    end
    return authored
end

-- Whether the area's spawn groups author a character the roster doesn't list.
-- The game streams such a type in on the spot when its group starts, into a
-- free slot.
local function streams_on_the_spot(roster, authored)
    local listed = {}
    for _, kind in ipairs(roster.list) do
        listed[kind] = true
    end
    for kind in pairs(authored) do
        if kind <= 90 and not listed[kind] then
            return true
        end
    end
    return false
end

-- Every spawn entry of `kind` in the area's groups (disabled ones included: a
-- trigger may enable them later), or nil when one isn't plain (a scripted
-- entrance needs its own type loaded), one is in a Time Rifts group, there are
-- none, or there are more than one callback can convert.
local function swap_entries(kind)
    local entries = {}
    local read = game.read_u32
    for base = MANAGER, MANAGER_END - 1, GROUP_STRIDE do
        local count = game.read_u16(base + COUNT_OFFSET)
        if count > ENTRY_SLOTS then
            count = 0
        end
        local entry = base + ENTRY_BASE
        for _ = 1, count do
            if read(entry) == kind then
                if signature(entry) ~= GENERIC or rift_group(base) or #entries >= MAX_SWAP_ENTRIES then
                    return nil
                end
                entries[#entries + 1] = entry
            end
            entry = entry + ENTRY_STRIDE
        end
    end
    return #entries > 0 and entries or nil
end

-- The Mortal Kombat warriors this area may take (none in a boss arena).
local function warrior_pool(roster, own, authored)
    for _, kind in ipairs(roster.list) do
        if is_boss(kind) then
            return {}
        end
    end
    local pool = {}
    for _, kind in ipairs(MK_WARRIORS) do
        if not own[kind] and not authored[kind] then
            pool[#pool + 1] = kind
        end
    end
    return pool
end

-- Runs before 0xCFAB0 reads the preload list. Restores the map's authored
-- roster (an earlier visit may have changed this static list) and, when the
-- roster fits the slot budget, appends an outsider; a full roster in SWAPS
-- trades its type for one instead (0.13), and that type's entries become the
-- outsider right here, before anything reads the groups. A re-preload in the
-- same area (0xD1910, after a cutscene) keeps the same outsider.
local function plan_preload(desc)
    if not plausible(desc) or desc >= 0x01000000 then
        return
    end
    if survival_desc(desc) then
        outsider = nil           -- Time Rifts' arena: its list stays as Time Rifts left it
        return
    end
    local roster = authored_roster(desc)
    local n = #roster.list
    local kind, swap, entries = nil, nil, nil
    local evicted = released and released.desc == desc and released.area == area_serial
    local fresh = preload_serial ~= area_serial          -- this area's groups loaded since the last preload
    preload_serial = area_serial
    local eligible = not fatality_area() and not evicted and not versus()
    if eligible and outsider and outsider.desc == desc and outsider.area == area_serial then
        kind, swap = outsider.kind, outsider.swap        -- a re-preload (0xD1910) keeps it
    elseif eligible then
        local authored = fresh and authored_types() or nil
        local budget = SLOT_BUDGET
        if authored and not streams_on_the_spot(roster, authored) then
            budget = SLOT_BUDGET_FULL
        end
        local own, pool = {}, {}
        for _, k in ipairs(roster.list) do
            own[k] = true
        end
        if takes_outsider(roster, budget) then
            reseed(desc ~ area_serial)
            if authored and rnd() % 100 < MK_CHANCE then
                pool = warrior_pool(roster, own, authored)
            end
        elseif fresh and own[SWAPS[desc]] then
            entries = swap_entries(SWAPS[desc])
            if entries then
                reseed(desc ~ area_serial)
                swap = SWAPS[desc]
            end
        end
        if (swap or takes_outsider(roster, budget)) and #pool == 0 then
            for _, candidate in ipairs(OUTSIDERS) do
                if not own[candidate] then
                    pool[#pool + 1] = candidate
                end
            end
        end
        if #pool > 0 then
            kind = pool[rnd() % #pool + 1]
        else
            swap = nil
        end
    end
    for i, k in ipairs(roster.list) do
        if k == swap then
            k = kind                                     -- the swap: the outsider takes the type's place
        end
        local at = desc + DESC_LIST + (i - 1) * 4
        if game.read_u32(at) ~= k then
            game.write_u32(at, k)
        end
    end
    local slot = desc + DESC_LIST + n * 4
    if kind and not swap then
        game.write_u32(slot, kind)
        game.write_u32(slot + 4, NO_TYPE)
        if roster.cap < n + 1 then
            game.write_u32(desc + DESC_CAP, n + 1)
        end
        outsider = { kind = kind, desc = desc, area = area_serial }
        return
    end
    if #roster.after == 2 and game.read_u32(slot) ~= roster.after[1] then
        game.write_u32(slot, roster.after[1])
        game.write_u32(slot + 4, roster.after[2])
    end
    if game.read_u32(desc + DESC_CAP) ~= roster.cap then
        game.write_u32(desc + DESC_CAP, roster.cap)
    end
    if not swap then
        outsider = nil           -- every map load preloads its own roster
        return
    end
    outsider = { kind = kind, desc = desc, area = area_serial, swap = swap }
    for _, entry in ipairs(entries or {}) do                 -- none on a re-preload: they hold it already
        game.write_u32(entry, kind)
        converted[#converted + 1] = { entry = entry, from = swap }
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
-- True when it did (the callback's writes are then spent on it).
local function release_outsider()
    if #converted == 0 or outsider == nil or is_loaded(outsider.kind) then
        return false
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
    return true
end

-- Turn plain entries into the outsider: OUTSIDER_MIN per group first, so every
-- room gets one, then OUTSIDER_CHANCE percent of the rest, within
-- OUTSIDER_PER_GROUP per group and OUTSIDER_TOTAL per area. A re-plan that
-- finds earlier conversions still in place keeps them instead of adding more.
local function convert_outsiders(plain)
    if outsider and outsider.swap then
        return                   -- a swap's entries were converted at the preload (plan_preload)
    end
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
    local total, group_cap, chance = OUTSIDER_TOTAL, OUTSIDER_PER_GROUP, OUTSIDER_CHANCE
    if warrior_kinds[kind] then
        total, group_cap, chance = MK_PER_AREA, 1, 0
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
        if #converted >= total then
            return
        end
        if (per_group[slot.group] or 0) < OUTSIDER_MIN then
            convert(slot)
        end
    end
    for _, slot in ipairs(plain) do
        if #converted >= total then
            return
        end
        if not slot.done and (per_group[slot.group] or 0) < group_cap
            and rnd() % 100 < chance then
            convert(slot)
        end
    end
end

-- This area's live Mortal Kombat warriors stay killable: their AI setup set
-- +0xD4 to 0 for a scripted boss fight they aren't in. At most a few writes.
local function keep_killable()
    local kind = outsider and outsider.kind
    if not warrior_kinds[kind] then
        return
    end
    local flags = game.read_u32(CHAR_POOL + CHAR_FLAGS)
    if not plausible(flags) then
        return
    end
    for i = 2, 11 do
        local entity = ENTITY_BASE + i * ENTITY_STRIDE
        if game.read_u16(flags + i * 2) ~= 0 and game.read_u16(entity + ENTITY_KIND) == kind then
            local actor = game.read_u32(entity + ACTOR)
            if plausible(actor) and game.read_u8(actor + CAN_KILL) == 0 then
                game.write_u8(actor + CAN_KILL, 1)
            end
        end
    end
end

-- A warrior entry about to spawn one copy more than the type's slot holds
-- goes back to its own type for good.
local function keep_copies(entry)
    local kind = outsider and outsider.kind
    if not warrior_kinds[kind] or game.read_u32(entry) ~= kind then
        return
    end
    local copies = game.read_u32(CHAR_TABLE + kind * CHAR_ROW + CHAR_COPIES)
    if copies < 1 or copies > 66 then
        copies = 2
    end
    if alive_of(kind) < copies then
        return
    end
    for _, c in ipairs(converted) do
        if c.entry == entry then
            game.write_u32(entry, c.from)
            return
        end
    end
end

-- Swap plain entries between rooms so a room that authors a single regular
-- type ends up spawning two. Each pair moves one entry each way, so every
-- type's area total, and with it its heap use, stays exactly as authored.
local function mix_rooms(plain)
    if MIX_PER_ROOM == 0 then
        return
    end
    local per_group, stacks = {}, {}
    for _, p in ipairs(plain) do
        local kind = game.read_u32(p.entry)   -- the class swap has permuted kinds since
        local list = per_group[p.group]
        if list == nil then
            list = {}
            per_group[p.group] = list
        end
        local entries = list[kind]
        if entries == nil then
            entries = {}
            list[kind] = entries
        end
        entries[#entries + 1] = p
        local stack = stacks[kind]
        if stack == nil then
            stack = {}
            stacks[kind] = stack
        end
        stack[#stack + 1] = p
    end
    local kinds, groups = {}, {}
    for k in pairs(stacks) do
        kinds[#kinds + 1] = k
    end
    for g in pairs(per_group) do
        groups[#groups + 1] = g
    end
    table.sort(kinds)
    table.sort(groups)
    local swapped = 0
    for _, group in ipairs(groups) do
        local list, own = per_group[group], {}
        for k, entries in pairs(list) do
            if #entries > 0 then
                own[#own + 1] = k
            end
        end
        if #own == 1 then
            local a, order = own[1], {}
            for _, k in ipairs(kinds) do
                if k ~= a then
                    order[#order + 1] = k
                end
            end
            while #order > 0 and swapped < MIX_TOTAL do
                local b = table.remove(order, rnd() % #order + 1)
                for _ = 1, MIX_PER_ROOM do
                    if #list[a] == 0 or swapped >= MIX_TOTAL then
                        break
                    end
                    local stack, eb = stacks[b], nil
                    for i = #stack, 1, -1 do
                        if stack[i].group ~= group and not stack[i].done then
                            eb = table.remove(stack, i)
                            break
                        end
                    end
                    if eb == nil then
                        break
                    end
                    local ea = table.remove(list[a], rnd() % #list[a] + 1)
                    local other = per_group[eb.group][b]
                    for i = 1, #other do
                        if other[i] == eb then
                            table.remove(other, i)
                            break
                        end
                    end
                    game.write_u32(ea.entry, b)
                    game.write_u32(eb.entry, a)
                    ea.done, eb.done = true, true
                    if #witnesses < 4 then
                        witnesses[#witnesses + 1] = { entry = ea.entry, from = a, to = b }
                    end
                    swapped = swapped + 1
                end
            end
        end
    end
end

local function shuffle_area(skip_started)
    planned = true
    local map = game.read_u32(CURRENT_MAP)
    if map >= SURVIVAL_FIRST and map <= SURVIVAL_LAST then
        return                   -- Time Rifts' arena: as authored
    end
    if fatality_area() then
        return                   -- fatality room: vanilla (core.lua)
    end
    local classes = {}           -- signature -> { slots = {}, kinds = {} }
    local eligible = {}          -- type -> may be shuffled (cached per call)
    local plain = {}             -- plain eligible entries, outsider candidates
    local total = 0
    -- a swap's outsider stays where its type was: release_outsider restores it there
    local held = outsider and outsider.swap and outsider.kind
    for group = 0, GROUP_LIMIT - 1 do
        local base = group_base(group)
        if game.read_u8(base + ENABLED_OFFSET) ~= 0 and not skip_started[group] and not rift_group(base) then
            local count = group_count(base)
            for slot = 0, (count or 0) - 1 do
                local kind = game.read_u32(entry_address(group, slot))
                local ok = eligible[kind]
                if ok == nil then
                    ok = is_common(kind) and is_loaded(kind) and heap_of(kind) ~= nil and kind ~= held
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
                        plain[#plain + 1] = { entry = entry, group = group, kind = kind }
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
        if group < GROUP_LIMIT and skip_started[group] and game.read_u8(base + ENABLED_OFFSET) ~= 0
                and not rift_group(base) then
            local count = group_count(base) or 0
            for slot = game.read_u16(MANAGER + ST_SPAWNED), count - 1 do
                local entry = entry_address(group, slot)
                local kind = game.read_u32(entry)
                local ok = eligible[kind]
                if ok == nil then
                    ok = is_common(kind) and is_loaded(kind) and heap_of(kind) ~= nil and kind ~= held
                    eligible[kind] = ok
                end
                if ok and signature(entry) == GENERIC then
                    plain[#plain + 1] = { entry = entry, group = group, kind = kind }
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
    mix_rooms(plain)
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
            local reloaded = memory_reloaded()   -- also resets instance counts per heap (core.lua)
            if refresh_census() or reloaded or (planned and reverted()) then
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
            keep_killable()
            if release_outsider() then
                return               -- the re-plan waits for the next tick (write budget)
            end
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
            local entry = game.read_u32(ctx.esp + 4)
            if ctx.ecx == MANAGER and entry_index(entry) then
                keep_copies(entry)
            end
            measure_before(entry)
            if ctx.ecx ~= MANAGER then
                return
            end
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
