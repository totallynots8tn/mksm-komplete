-- MKSMK Probe: Shaolin Shuffle eligibility snapshot (diagnostics only).
-- Walks each loaded area once shortly after its first group starts and logs
-- every authored enemy type with its census count and, per type, whether it is
-- in the 6-slot spawn gate (L) and whether it owns a character-memory heap (H).
-- That distinguishes "model resident but not gated in" (a reservation could
-- spawn it) from "not resident at all" (only engine streaming would help), so
-- low shuffle variety can be traced to the exact binding constraint. Changes
-- nothing; reports every area seen when the game saves (probe_save.lua).
local MANAGER        = 0x006DBFB0
local GROUP_STRIDE   = 0xA6C
local GROUP_LIMIT    = 50
local ENTRY_BASE     = 0x18
local ENTRY_STRIDE   = 0x74
local COUNT_OFFSET   = 0xA68
local ENABLED_OFFSET = 0xA6A
local ENTRY_SLOTS    = 22
local LOADED_TYPES   = 0x006CA69C
local LOADED_SLOTS   = 6
local NO_TYPE        = 0xFFFFFFFF
local INTERFACE      = 0x006322F8
local SLOT_COUNT     = 0x10
local SLOT_TABLE     = 0x24
local SLOT_STRIDE    = 20
local SLOT_TYPE      = 4
local FRAME          = 0x005CE878
local GAME_MANAGER   = 0x005ACEBC
local LOAD_GROUPS    = 0x00014D2C
local START_GROUP    = 0x001D2600
local SPAWN_TICK     = 0x001D23F0

local function ok(p)
    return p >= 0x10000 and p % 4 == 0 and (p < 0x7FFE0000
        or (p >= 0x80000000 and p < 0x84000000)
        or (p >= 0xB0000000 and p < 0xC0000000)
        or (p >= 0xD0000000 and p < 0xE0000000)
        or (p >= 0xF0000000 and p < 0xF4000000))
end
local function hex(v) return string.format("%X", v) end

local started = false
local snapped = false             -- this area's snapshot is taken
local done = false

local function group_count(base)
    local count = game.read_u16(base + COUNT_OFFSET)
    if count > ENTRY_SLOTS then return nil end
    return count
end

-- The six-slot table of types that can spawn right now.
local function loaded_set()
    local set = {}
    for slot = 0, LOADED_SLOTS - 1 do
        set[game.read_u32(LOADED_TYPES + slot * 4)] = true
    end
    return set
end

-- Types that own a character-memory heap, from the game memory interface.
local function heap_set()
    local set = {}
    local count = game.read_u32(INTERFACE + SLOT_COUNT)
    local table_ptr = game.read_u32(INTERFACE + SLOT_TABLE)
    if count == 0 or count > 16 or not ok(table_ptr) then return set end
    for slot = 0, count - 1 do
        local base = table_ptr + slot * SLOT_STRIDE
        if game.read_u32(base) < 0x80 then
            set[game.read_u32(base + SLOT_TYPE)] = true
        end
    end
    return set
end

-- One snapshot per area, taken at its first spawn tick after a group starts.
-- They are kept in the shared log and written when the game saves.
local function snapshot()
    snapped = true
    local census = {}
    local total_slots, eligible_slots = 0, 0
    for group = 0, GROUP_LIMIT - 1 do
        local base = MANAGER + group * GROUP_STRIDE
        if game.read_u8(base + ENABLED_OFFSET) ~= 0 then
            local count = group_count(base)
            if count then
                for slot = 0, count - 1 do
                    local kind = game.read_u32(base + ENTRY_BASE + slot * ENTRY_STRIDE)
                    census[kind] = (census[kind] or 0) + 1
                    total_slots = total_slots + 1
                end
            end
        end
    end
    local loaded, heaps = loaded_set(), heap_set()
    local loaded_names, free_gates = {}, 0
    for slot = 0, LOADED_SLOTS - 1 do
        local v = game.read_u32(LOADED_TYPES + slot * 4)
        if v == NO_TYPE then free_gates = free_gates + 1 end
        loaded_names[#loaded_names + 1] = v == NO_TYPE and "-" or hex(v)
    end
    -- Per type: census, then L/l = in the 6-slot spawn gate, H/h = owns a
    -- character-memory heap. A common type that is `l..H` has its model
    -- resident but is not gated in (a reservation could spawn it); `l..h` has
    -- neither, so only the engine streaming it in would help.
    local parts = {}
    for kind, n in pairs(census) do
        if kind ~= NO_TYPE then
            local elig = n >= 2 and loaded[kind] and heaps[kind]
            if elig then eligible_slots = eligible_slots + n end
            parts[#parts + 1] = hex(kind) .. "=" .. n
                .. (n >= 2 and "" or "once")
                .. (loaded[kind] and "L" or "l")
                .. (heaps[kind] and "H" or "h")
        end
    end
    table.sort(parts)
    local manager = game.read_u32(GAME_MANAGER)
    local mode = ok(manager) and game.read_u32(manager + 0x88) or -1
    log_add("{mode=" .. mode .. " frame=" .. game.read_u32(FRAME)
        .. " slots=" .. total_slots .. " eligible=" .. eligible_slots
        .. " freegates=" .. free_gates
        .. " loaded=[" .. table.concat(loaded_names, ",") .. "] | "
        .. table.concat(parts, " ") .. "}")
end

local function report(reason)
    done = true
    error("SHUFFLE " .. reason .. " areas=" .. log_count() .. " " .. log_text(), 0)
end

local hooks = {
    {   address = LOAD_GROUPS,
        after = function(ctx) started = false; snapped = false end },
    {   address = START_GROUP,
        before = function(ctx)
            if ctx.ecx == MANAGER then started = true end
        end },
    {   address = SPAWN_TICK,
        before = function(ctx)
            if not done and not snapped and started and ctx.ecx == MANAGER then snapshot() end
        end },
    {   address = SAVE_GAME,
        before = function(ctx)
            if save_due() and not done and log_count() > 0 then report(save_tag("save")) end
        end },
}
return hooks
