
-- ===== Boss Invasion =====
-- Types authored only once in a level are its bosses and elites. The last
-- reinforcement of a doubled group may turn into one of them as it spawns,
-- but only when that type is loaded and its own heap has measured room, so
-- an invader never starves the real boss fight of model memory. Costs are
-- measured on real spawns, so invaders show up once the level's elite has
-- appeared at least once.
local INVADER_CHANCE     = 60  -- percent of doubled groups that try an invader
local INVADERS_PER_LEVEL = 6
local INVADER_HEADROOM   = 1   -- the level's own copy has already spawned (cost is known)

local invaders = 0
local invader_key = nil

after_expand = function(group, first_clone, target)
    if invader_key ~= census_key then
        invader_key = census_key
        invaders = 0
    end
    if rnd() % 100 < INVADER_CHANCE then
        groups_invader = groups_invader or {}
        groups_invader[group] = target - 1
    end
end

before_clone = function(entry, group, slot)
    if groups_invader == nil or groups_invader[group] ~= slot then
        return
    end
    groups_invader[group] = nil
    if invaders >= INVADERS_PER_LEVEL then
        return
    end
    local elites = {}
    for index = 0, LOADED_SLOTS - 1 do
        local kind = game.read_u32(LOADED_TYPES + index * 4)
        if kind ~= NO_TYPE and census[kind] == 1 and can_afford(kind, INVADER_HEADROOM) then
            elites[#elites + 1] = kind
        end
    end
    if #elites == 0 then
        return
    end
    game.write_u32(entry, elites[(rnd() % #elites) + 1])
    invaders = invaders + 1
end
