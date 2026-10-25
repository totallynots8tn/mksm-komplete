-- Environmental Kill XP 2.0: hazard kills count exactly like normal kills.
--
-- How the game pays kill XP: every player has a combo stats object
-- ([[entity+0x2B6C]+0x50], getter 0x1579F). A normal kill goes through
-- RegisterKill (0x7E750 via thunk 0x1246E, from the combat code at 0x17879F
-- and 0x17CAE1), whose AddKill (0x7DC60) bumps kills[victim type] in the
-- byte array at stats+0x118 (type = victim entity +0x1DFE). When the combo
-- times out (0x7EA94) the game sums kills x the per-type XP table at
-- 0x508238 (50 for most grunts, more for elites), applies the combo
-- multiplier, shows the "+XP" popup and pays it. Level hazards kill through
-- other paths that never call RegisterKill, so those kills were simply lost.
--
-- This mod does what AddKill does for hazard kills, through these paths:
--   instant kill         (0x1F2500)  thrown off the map / over walls, kill zones
--   killandhidecharacter (0x1F25B0)  pits and drops that remove a live enemy
--   applydamage          (0x153DC0)  spikes, saws, fire and other hazard damage
--   bodydamage           (0x180CA0)  hazard dismemberment
-- The game then shows and pays the XP itself, with your multiplier.
local KILL_AND_HIDE  = 0x001F25B0
local APPLY_DAMAGE   = 0x00153DC0
local BODY_DAMAGE    = 0x00180CA0
local INSTANT_KILL   = 0x001F2500   -- thiscall, [esp+4] = character entity

local CHAR_TAG       = 0x00496C80   -- "char"
local CHAR_TABLE     = 0x005D1AB8   -- entity of character index 0 (player 1)
local CHAR_STRIDE    = 0x3238
local CHAR_LIMIT     = 12
local FIRST_ENEMY    = 2
local ACTOR_OFFSET   = 0x200
local HEALTH         = 0x368
local CHAR_ID        = 0x68         -- entity: 1-based character id
local KILL_TYPE      = 0x1DFE       -- entity: s16 index into the XP table
local STATS_LINK     = 0x2B6C       -- entity: -> [+0x50] combo stats
local STATS_KILLS    = 0x118        -- stats: u8 kills[91]
local STATS_HITS     = 0xC4         -- stats: combo hits
local KILL_TYPES     = 91
local NO_XP_FLAGS    = 0x006C6ED8   -- [+id*32+4] != 0: kill not counted (AddKill)

local GAME_MANAGER   = 0x005ACEBC
local GAME_MODE      = 0x88         -- 0 single player, 1 co-op, 2 versus
local FRAME_COUNTER  = 0x005CE878
local PAY_ONCE       = 300          -- frames during which one victim counts once

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

local function signed(value, bits)
    local limit = 1 << (bits - 1)
    if value >= limit then
        return value - (1 << bits)
    end
    return value
end

local function entity_of(index)
    return CHAR_TABLE + index * CHAR_STRIDE
end

local function stats_of(entity)
    local link = game.read_u32(entity + STATS_LINK)
    if not plausible(link) then
        return nil
    end
    local stats = game.read_u32(link + 0x50)
    if not plausible(stats) then
        return nil
    end
    return stats
end

-- The player whose combo gets the kill: player 1, or in co-op whoever has
-- the longer combo running.
local function killer_stats()
    local manager = game.read_u32(GAME_MANAGER)
    if not plausible(manager) then
        return nil
    end
    local mode = game.read_u32(manager + GAME_MODE)
    if mode == 2 then
        return nil              -- versus has no XP
    end
    local best = stats_of(entity_of(0))
    if mode == 1 then
        local other = stats_of(entity_of(1))
        if other and (best == nil or
            game.read_u32(other + STATS_HITS) > game.read_u32(best + STATS_HITS)) then
            best = other
        end
    end
    return best
end

local counted = {}

-- AddKill (0x7DC60) for a hazard kill of `entity`.
local function register_kill(entity)
    local now = game.read_u32(FRAME_COUNTER)
    local last = counted[entity]
    if last and now >= last and now - last < PAY_ONCE then
        return
    end
    local id = game.read_u32(entity + CHAR_ID)
    if id > 64 or game.read_u8(NO_XP_FLAGS + id * 32 + 4) ~= 0 then
        return
    end
    local kind = signed(game.read_u16(entity + KILL_TYPE), 16)
    if kind < 0 or kind >= KILL_TYPES then
        return
    end
    local stats = killer_stats()
    if stats == nil then
        return
    end
    local slot = stats + STATS_KILLS + kind
    local kills = game.read_u8(slot)
    if kills < 255 then
        game.write_u8(slot, kills + 1)
    end
    counted[entity] = now
end

local function health_of(actor)
    return signed(game.read_u32(actor + HEALTH), 32)
end

-- Entity of the enemy a "char" script reference points at, or nil.
local function target_entity(ctx)
    local reference = game.read_u32(ctx.esp + 8)
    if not plausible(reference) then
        return nil
    end
    for i = 0, 4 do
        if game.read_u8(reference + i) ~= game.read_u8(CHAR_TAG + i) then
            return nil
        end
    end
    local index = game.read_u32(reference + 0x10)
    if index < FIRST_ENEMY or index >= CHAR_LIMIT then
        return nil
    end
    return entity_of(index)
end

local function alive(entity)
    local actor = game.read_u32(entity + ACTOR_OFFSET)
    return plausible(actor) and health_of(actor) > 0, actor
end

local pending = {}

local function remember(ctx, key)
    local entity = target_entity(ctx)
    pending[key] = nil
    if entity then
        local is_alive, actor = alive(entity)
        if is_alive then
            pending[key] = { entity = entity, actor = actor }
        end
    end
end

local function settle(key)
    local p = pending[key]
    pending[key] = nil
    if p and health_of(p.actor) <= 0 then
        register_kill(p.entity)
    end
end

return {
    {
        address = INSTANT_KILL,
        before = function(ctx)
            local entity = game.read_u32(ctx.esp + 4)
            if entity < entity_of(FIRST_ENEMY) or entity >= entity_of(CHAR_LIMIT)
                or (entity - CHAR_TABLE) % CHAR_STRIDE ~= 0 then
                return
            end
            if alive(entity) then
                register_kill(entity)
            end
        end,
    },
    {
        address = KILL_AND_HIDE,
        before = function(ctx)
            local entity = target_entity(ctx)
            if entity and alive(entity) then
                register_kill(entity)
            end
        end,
    },
    {
        address = APPLY_DAMAGE,
        before = function(ctx) remember(ctx, "apply") end,
        after = function(ctx) settle("apply") end,
    },
    {
        address = BODY_DAMAGE,
        before = function(ctx) remember(ctx, "body") end,
        after = function(ctx) settle("body") end,
    },
}
