-- Extended Upgrades 0.1.0 (PROTOTYPE — experimental).
--
-- Goal: give the extra XP from Legendary Dark Knight more to buy, as "loose"
-- passive unlocks — blade dismemberment (behead / sever limbs), EX moves that
-- reuse brutality animations, and stamina upgrades.
--
-- What is LIVE in 0.1.0: the spine. It watches each player's XP, accumulates a
-- monotonic lifetime total (so it is unaffected by spending), and unlocks the
-- upgrades below as that total crosses each threshold.
--
-- What is INERT: every gameplay EFFECT. A routine mod may only read/write
-- memory and hook addresses — it can NEVER call the game's animation,
-- mutilation or upgrade functions. So each effect needs a verified memory
-- target (a flag or field that, when written, makes the game play the brutality
-- anim / detach the bone / raise the stamina cap). probe_upgrade (MKSMK Probe
-- 0.7) captures those targets; until then apply() writes nothing. This script
-- performs ZERO writes to game memory, so it is safe to have installed.
--
-- The upgrade registry is the design surface: add/rename/re-cost entries here.
local GAME_MANAGER  = 0x005ACEBC
local GAME_MODE     = 0x88          -- 0 single player, 1 co-op, 2 versus (no XP)
local XP_BASE       = 0x48F0        -- manager: player XP, stride 0x50 (confirm index via probe_upgrade)
local XP_STRIDE     = 0x50
local PLAYERS       = 2
local SPAWN_TICK    = 0x001D23F0    -- runs every frame in fights; the XP poll tick
local START_GROUP   = 0x001D2600    -- area/group transitions
local ADD_XP        = 0x00013A53    -- script command: award experience

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

local function manager()
    local m = game.read_u32(GAME_MANAGER)
    if not plausible(m) then return nil end
    return m
end

local function mode(m)
    return game.read_u32(m + GAME_MODE)
end

local function xp_of(m, player)
    return game.read_u32(m + XP_BASE + player * XP_STRIDE)
end

-- kind groups the effect mechanism (see apply); xp is the lifetime-XP threshold.
local UPGRADES = {
    -- Blade dismemberment. Will drive enemy_detach_bone (0x1A33E0) /
    -- enemy_detach_group (0x1A34A0) / mutilate_collision (0x1A3450).
    { id = "decapitate", kind = "dismember", xp = 2000,  name = "Decapitate",
      note = "blade finishing hits behead (enemy_detach_bone, head)" },
    { id = "sever",      kind = "dismember", xp = 5000,  name = "Sever Limbs",
      note = "blade hits can sever arms and legs (enemy_detach_group)" },
    { id = "cleaver",    kind = "dismember", xp = 9000,  name = "Cleaver",
      note = "higher dismember chance on blades (mutilate_collision)" },
    -- EX / new moves reusing brutality animations. Will drive startanim
    -- (0x18AAC0) or the brutality/fatality trigger state.
    { id = "ex_finisher", kind = "move",     xp = 3000,  name = "EX Finisher",
      note = "a brutality anim as an enhanced special move" },
    { id = "ex_breaker",  kind = "move",     xp = 7000,  name = "EX Combo Breaker",
      note = "a brutality anim as a combo-ending EX move" },
    -- Stamina / guard. Field address unknown; probe_upgrade hunts it.
    { id = "endurance",  kind = "stamina",   xp = 1500,  name = "Endurance",
      note = "larger stamina/guard meter" },
    { id = "recuperate", kind = "stamina",   xp = 4000,  name = "Recuperate",
      note = "faster stamina recovery" },
    { id = "ironlungs",  kind = "stamina",   xp = 12000, name = "Iron Lungs",
      note = "longer sprint and dodge" },
}

local owned = {}        -- [player] -> { [id] = true }
local earned = {}       -- [player] -> lifetime XP gained this session
local last_xp = {}      -- [player] -> last observed XP value

-- Where an unlocked upgrade changes the game. INERT in 0.1.0: no target is
-- verified yet, so this writes nothing. Each kind maps to a mechanism that
-- probe_upgrade will pin down:
--   dismember -> a per-player flag an enemy_detach/bodydamage hook reads, to
--                force the bone/group detach on blade hits
--   move      -> the brutality-anim trigger state fired on the EX input
--   stamina   -> the (to-be-found) stamina max / regen fields
local function apply(player, up)
    return player, up           -- placeholder: keeps the signature for 0.2
end

local function unlock(m, player, total)
    local have = owned[player]
    for i = 1, #UPGRADES do
        local up = UPGRADES[i]
        if total >= up.xp and not (have and have[up.id]) then
            owned[player] = owned[player] or {}
            owned[player][up.id] = true
            apply(player, up)
        end
    end
end

local function poll()
    local m = manager()
    if m == nil or mode(m) == 2 then
        return
    end
    for player = 0, PLAYERS - 1 do
        local xp = xp_of(m, player)
        local prev = last_xp[player]
        if prev == nil then
            earned[player] = 0
        elseif xp > prev then
            earned[player] = (earned[player] or 0) + (xp - prev)
        end
        last_xp[player] = xp
        unlock(m, player, earned[player] or 0)
    end
end

return {
    { address = SPAWN_TICK,  before = function(ctx) poll() end },
    { address = START_GROUP, before = function(ctx) poll() end },
    { address = ADD_XP,      before = function(ctx) poll() end },
}
