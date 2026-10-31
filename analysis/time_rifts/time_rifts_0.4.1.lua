-- ===== Time Rifts 0.4.1 QA: Oni Warlord encounter in Wu Shi co-op arena =====
-- The game already streams outsider types through its normal preload and
-- spawn-entry path. This QA build uses that path in map 110 only: it provides
-- one director group, preloads the Oni Warlord, and redirects the arena's
-- native callspawn command to that group. It does not rewrite common spawn
-- rosters or use Shuffle's area-wide outsider planner.
-- The portal prop/trigger is separate scene data and is not part of this
-- boss-encounter test build.

local LOADMAP       = 0x00012883
local LOAD_GROUPS   = 0x00014D2C
local PRELOAD       = 0x00015DEE
local CALLSPAWN     = 0x001D2710
local START_GROUP   = 0x001D2600
local SPAWN_ENTRY   = 0x001D1D40

local CURRENT_MAP   = 0x00505970
local ARENA_MAP     = 110
local ARENA_TARGET  = ARENA_MAP + 1 -- LOADMAP stores map IDs one-based
local ARENA_DESC    = 0x004FF2E8
local SPAWN_FILE    = 0x00000BCB -- Wu Shi entrance group data; map 110 has none
local NO_SPAWN_FILE = 0xFFFFFFFF
local GROUP_MANAGER = 0x006DBFB0
local GROUP_STRIDE  = 0xA6C
local GROUP_LIMIT   = 50
local ENTRY_BASE    = 0x18
local ENTRY_COUNT   = 0xA68
local ENTRY_ENABLED = 0xA6A
local ENTRY_SLOTS   = 22
local BOSS_GROUP    = 1 -- present in the borrowed Wu Shi entrance group data
local ONI_WARLORD   = 36 -- 34 is the club-wielding warlord
local PRELOAD_CAP   = 0x20
local PRELOAD_LIST  = 0x24
local PLAYER_ENTITY = 0x005D1AB8

local pending_arena_load = false
local arena_groups_ready = false
local boss_director = false
local boss_spawn_pending = false
local boss_spawned = false

local function plausible(p)
    return p >= 0x10000 and p % 4 == 0 and (p < 0x7FFE0000
        or (p >= 0x80000000 and p < 0x84000000)
        or (p >= 0xB0000000 and p < 0xC0000000)
        or (p >= 0xD0000000 and p < 0xE0000000)
        or (p >= 0xF0000000 and p < 0xF4000000))
end

local function loadmap_args(ctx)
    if not plausible(ctx.esp) then return nil end
    local def = game.read_u32(ctx.esp + 4)
    if not plausible(def) then return nil end
    local args = game.read_u32(def + 8)
    if not plausible(args) then return nil end
    return args
end

local function add_oni_to_arena_preload(desc)
    if desc ~= ARENA_DESC then return end
    local cap = game.read_u32(desc + PRELOAD_CAP)
    if cap == 0 or cap > 8 then return end
    local list = desc + PRELOAD_LIST
    local free = nil
    for i = 0, cap - 1 do
        local kind = game.read_u32(list + i * 4)
        if kind == ONI_WARLORD then return end
        if kind == NO_SPAWN_FILE and free == nil then free = i end
    end
    if free ~= nil then
        game.write_u32(list + free * 4, ONI_WARLORD)
        if free + 1 < cap then game.write_u32(list + (free + 1) * 4, NO_SPAWN_FILE) end
    end
end

local function silence_borrowed_groups()
    for i = 0, GROUP_LIMIT - 1 do
        local base = GROUP_MANAGER + i * GROUP_STRIDE
        local count = game.read_u16(base + ENTRY_COUNT)
        if count <= ENTRY_SLOTS then
            game.write_u8(base + ENTRY_ENABLED, 0)
        end
    end
end

local function prepare_boss_group(group)
    if group ~= BOSS_GROUP then return false end
    local base = GROUP_MANAGER + group * GROUP_STRIDE
    local count = game.read_u16(base + ENTRY_COUNT)
    if count == 0 or count > ENTRY_SLOTS then return false end
    game.write_u32(base + ENTRY_BASE, ONI_WARLORD)
    game.write_u16(base + ENTRY_COUNT, 1)
    game.write_u8(base + ENTRY_ENABLED, 1)
    boss_spawn_pending = true
    boss_spawned = true
    boss_director = false
    return true
end

local function set_spawn_near_player(entry)
    if not boss_spawn_pending or entry ~= GROUP_MANAGER + BOSS_GROUP * GROUP_STRIDE + ENTRY_BASE then
        return
    end
    boss_spawn_pending = false
    local x = game.read_f32(PLAYER_ENTITY + 0x80)
    local y = game.read_f32(PLAYER_ENTITY + 0x84)
    local z = game.read_f32(PLAYER_ENTITY + 0x88)
    game.write_f32(entry + 0x18, x)
    game.write_f32(entry + 0x1C, y)
    game.write_f32(entry + 0x20, z)
end

return {
    {
        address = LOADMAP,
        before = function(ctx)
            local args = loadmap_args(ctx)
            if not args then return end
            if game.read_u32(args) == ARENA_TARGET then
                -- Map 110 has no spawn-group file. Supply the entrance's
                -- authored group table for the arena's native callspawn event.
                game.write_u32(ARENA_DESC + 0x7C, SPAWN_FILE)
                pending_arena_load = true
                arena_groups_ready = false
                boss_director = false
                boss_spawn_pending = false
                boss_spawned = false
            elseif game.read_u32(CURRENT_MAP) == ARENA_MAP then
                arena_groups_ready = false
                boss_director = false
                boss_spawn_pending = false
            end
        end,
    },
    {
        address = LOAD_GROUPS,
        after = function()
            if not pending_arena_load then return end
            silence_borrowed_groups()
            game.write_u32(ARENA_DESC + 0x7C, NO_SPAWN_FILE)
            pending_arena_load = false
            local base = GROUP_MANAGER + BOSS_GROUP * GROUP_STRIDE
            local count = game.read_u16(base + ENTRY_COUNT)
            arena_groups_ready = count > 0 and count <= ENTRY_SLOTS
        end,
    },
    {
        address = PRELOAD,
        before = function(ctx)
            local desc = game.read_u32(ctx.esp + 4)
            if plausible(desc) then add_oni_to_arena_preload(desc) end
            -- Fallback restore if the loader skipped a group-file callback.
            if desc == ARENA_DESC and pending_arena_load then
                game.write_u32(ARENA_DESC + 0x7C, NO_SPAWN_FILE)
                pending_arena_load = false
            end
        end,
    },
    {
        address = CALLSPAWN,
        before = function(ctx)
            if game.read_u32(CURRENT_MAP) ~= ARENA_MAP or not arena_groups_ready or boss_spawned then
                return
            end
            local object = game.read_u32(ctx.esp + 4)
            if not plausible(object) then return end
            local args = game.read_u32(object + 8)
            if not plausible(args) then return end
            -- Redirect only this map's own director command to our isolated
            -- one-entry group. Other maps and all Shuffle groups stay vanilla.
            game.write_u32(args, BOSS_GROUP)
            boss_director = true
        end,
    },
    {
        address = START_GROUP,
        before = function(ctx)
            if ctx.ecx ~= GROUP_MANAGER or game.read_u32(CURRENT_MAP) ~= ARENA_MAP
                or not arena_groups_ready or not boss_director then
                return
            end
            local group = game.read_u32(ctx.esp + 4)
            if group < GROUP_LIMIT then prepare_boss_group(group) end
        end,
    },
    {
        address = SPAWN_ENTRY,
        before = function(ctx)
            if ctx.ecx ~= GROUP_MANAGER or game.read_u32(CURRENT_MAP) ~= ARENA_MAP then return end
            local entry = game.read_u32(ctx.esp + 4)
            if plausible(entry) then set_spawn_near_player(entry) end
        end,
    },
}
