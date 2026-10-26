-- Extended Upgrades 0.5.3: XP shop, Health and Stamina only.
--
-- Turns the pause menu's Basic Moves category into the XP shop. Nothing new
-- is added to the menu; existing rows get new text, costs and behaviour, and
-- everything sold comes on top of what the game itself gives:
--   * Basic Moves -> Upgrades: Basic Attacks -> Health (+1-4: 1, 2, 4 and 8
--     game health-upgrade steps, above the game's own four) and Air Attacks
--     -> Stamina (+1-4: everything that spends the blue bar costs less, as if
--     it held 125, 150, 200 and 300%). Running Attacks stays vanilla.
-- Skill and Team keep their vanilla rows. EX moves, weapons and fatalities
-- come later, each as its own step (a failing callback switches the whole
-- script off, so they ship apart). See analysis/xp_shop/REPORT.md section 9.
-- Analysis: analysis/xp_shop/REPORT.md (sections 7, 9 and 11).
--
-- How the menu works (default.xbe):
--   * The menu is data: the "M&PD" tree (GAMEDATA.WAD record 713), copied into
--     memory by MPDatabase::ImportData. [0x4EFA88] holds the copy; roots at
--     [blob+0x10] (count blob+0x0C). Node: +0x04 type (2 category, 1 group,
--     0 row), +0x0C child count, +0x10 parent, +0x14 children, +0x18 name and
--     +0x1C description (text indices), +0x28 XP cost, +0x2C owned.
--     Skill (464) is a type-1 category whose leaves hang directly off it, so
--     a bought leaf's index is its category position.
--   * Opening the menu runs SyncOwned (thunk 0x13A12), which recomputes +0x2C
--     for Specials, Combos, Platform and Fatalities. Our categories are never
--     synced, so after it runs we set their text, costs and owned flags
--     ourselves.
--   * Only Specials and Combos can be bought. The purchase dispatcher asks
--     CanPurchase (thunk 0x116CC) and IsCombo (thunk 0x15EDE); we answer yes for
--     our rows, so the game's Purchase_combo (thunk 0x13954) runs its own yes/no
--     dialog, deducts the row's cost from XP and marks it owned.
--   * Purchase_combo also calls Upgrade(player, 13 + row) (thunk 0x1647E), which
--     would unlock a combo for free. We save that level byte and restore it.
--   * Shop levels live in level slot 27 (no fixed-slot readers): player 0's
--     byte holds Health (bits 0-2, shared like the game's own count), each
--     player's byte holds their Stamina (bits 3-5). Bit 7 marks the byte as
--     ours; 0.3.0 kept a weapon count there, which reads as nothing bought.
--   * Health: the game's max health is the table at 0x50B544, read as
--     [min(ups, 4) * 5 + mode] (ups = manager +0xE0, mode +0x88: 0 solo,
--     1 co-op) into manager +0x94 (int; +0x8C is current health as a float,
--     not a max: it follows damage, so we leave it alone), then each
--     player actor (+0x200 of entity 0x5D1AB8 + p * 0x3238) gets +0x370 =
--     +0x94 times the area's level +0x90 (1-15), halved per character in co-op,
--     and is healed to it (0xD4760, 0xD4790 on map load and after the
--     healthupgrade command). We add table steps (the 3 -> 4 difference) on
--     top: HP_STEPS by shop level. Whenever the game has rewritten those values
--     (it only ever writes vanilla ones), the stamina tick adds ours back and
--     heals by what max health gained.
--   * Stamina: one 0x24-byte record per player at 0x4E6598 (count 0x4E65E0).
--     It drains two ways. Consume(level) subtracts the record's cost[level - 1]
--     (+0x00..+0x0C: 10, 20, 100, 3); CanAfford compares the same cost. And
--     while the player is in a sustained state (the long jump, for one), the
--     Tick (0x76300, through 0x75F20) takes 1.0 off the bar every 5th frame
--     without a cost. The 100 cap is an immediate in Add, Tick and the HUD, so
--     a bigger bar is cheaper costs: cost * 100 / BAR[level], and the
--     sustained drain gets the same share refunded after each Tick. Init
--     (0x76690) copies the record from a per-character template, so the tick
--     re-scales whenever the costs are no longer the ones we wrote. (0.4/0.5
--     also drew the bar taller; the HUD frame over it has a fixed window, so
--     the extra height only showed below the frame.)
--   * Meter (0.2/0.3 sold its levels early): the story's setfatalitylevel
--     (thunk 0x1116D) adds without a cap, and the HUD has layouts for levels
--     1-3 only, so we still clamp it at 3 for saves that bought a level.
--   * Text: the strings are a pointer array at [0x5B04A4] (count [0x5AC508]).
--     We write our strings over unused "(PH)" move-list placeholders, only where
--     they fit, and point our rows at them. Every value we change is remembered,
--     and put back if a reloaded text table no longer has room for ours.
local GAME_MANAGER  = 0x005ACEBC
local GAME_MODE     = 0x88          -- 0 single player, 1 co-op, 2 versus
local XP            = 0x4940        -- XP of player p at +0x4940 + p * 0x50
local PLAYER_STRIDE = 0x50
local LEVELS        = 0x1C4         -- level byte of player p, slot s: +0x1C4 + p * 0x1C + s
local HEALTH_UPS    = 0xE0          -- the game's health-upgrade count, 0-4
local METER_LEVEL   = 0x4978        -- meter level of player p at +0x4978 + p * 0x50
local METER_MAX     = 3
local MAX_HP        = 0x94          -- base max health (int)
local HP_LEVEL      = 0x90          -- the area's level multiplier, 1-15
local HP_TABLE      = 0x0050B544    -- base max health, [min(ups, 4) * 5 + mode]
local HP_MAX_UPS    = 4
local HP_LEVEL_MAX  = 15
local HP_TEXT_STEP  = 100           -- the solo table step, as the row text shows it
local ENTITY        = 0x005D1AB8    -- player entity p at + p * 0x3238
local ENTITY_STRIDE = 0x3238
local ACTOR         = 0x200         -- the entity's actor
local ACTOR_HP      = 0x368         -- current health (int)
local ACTOR_MAX_HP  = 0x370         -- max health (int)
local STAMINA       = 0x004E6598    -- stamina record of player p at + p * 0x24
local STAMINA_STRIDE = 0x24
local STAMINA_COUNT = 0x004E65E0
local COSTS         = 4             -- cost by cost level 1-4 at +0x00..+0x0C
local STAMINA_NOW   = 0x10          -- current stamina (f32, 0-100)
local SHOP_SLOT     = 27            -- shop levels (see above)
local SHOP_MARK     = 0x80
local SHOP_ROWS     = 4
local HP_STEPS      = { [0] = 0, 1, 2, 4, 8 }           -- health table steps by shop level
local BAR           = { [0] = 100, 125, 150, 200, 300 } -- the bar each Stamina level plays as (%)
local ABILITY_BASE  = 0xE4          -- per-ability timers (float) and records hang off here
local MPD           = 0x004EFA88    -- MPDatabase: [+0] tree copy
local MENU_PLAYER   = 0x004EFA60    -- player (0 or 1) whose pause menu is open
local SELECTED      = 0x004EFB38    -- the highlighted menu node
local TEXT_PTRS     = 0x005B04A4
local TEXT_COUNT    = 0x005AC508

local SYNC_OWNED    = 0x00013A12
local CAN_PURCHASE  = 0x000116CC
local IS_COMBO      = 0x00015EDE
local BUY_COMBO     = 0x00013954
local UPGRADE       = 0x0001647E
local METER_LEVELUP = 0x0001116D    -- the setfatalitylevel script command
local STAMINA_TICK  = 0x00016965    -- Tick(record), fastcall: once per record per frame

local BASIC_TEXT    = 402           -- "Basic Moves" category
local UPGRADE_TEXT  = 455           -- "Upgrade" in the loaded language tells us which it is

-- Text in the game's code page (cp1252). The "(PH)" placeholders we overwrite
-- are 45-62 bytes in the five built-in languages (English is the shortest).
-- health[3] takes the bonus health and stamina[3] the bar size in percent.
local LANGUAGES = {
    { tag = "Upgr", category = { "Upgrades", "Spend EXP on health and stamina." },
      health = { "Health", "Health +%d", "Max health +%d,\non top of the game's.",
                 "Extra health on top of the game's." },
      stamina = { "Stamina", "Stamina +%d", "Stamina %d%%.\nBlocks and specials\ncost less.",
                  "Blocks and specials cost less stamina." } },
    { tag = "Mejo", category = { "Mejoras", "Gasta EXP en salud y energ\237a." },
      health = { "Salud", "Salud +%d", "Vida m\225xima +%d,\nadem\225s de la del juego.",
                 "Salud extra, adem\225s de la del juego." },
      stamina = { "Energ\237a", "Energ\237a +%d", "Energ\237a %d%%.\nBloquear y especiales\ncuestan menos.",
                  "Bloquear y especiales gastan menos." } },
    { tag = "Verb", category = { "Verbesserungen", "EXP f\252r Leben und Ausdauer ausgeben." },
      health = { "Leben", "Leben +%d", "Max. Leben +%d,\nzus\228tzlich zum Spiel.",
                 "Mehr Leben, zus\228tzlich zum Spiel." },
      stamina = { "Ausdauer", "Ausdauer +%d", "Ausdauer %d%%.\nBlock, Spezial\nkosten weniger.",
                  "Blocken und Spezial kosten weniger." } },
    { tag = "Pote", category = { "Potenziamenti", "Spendi EXP per salute ed energia." },
      health = { "Salute", "Salute +%d", "Salute max +%d,\noltre a quella del gioco.",
                 "Salute extra oltre a quella del gioco." },
      stamina = { "Energia", "Energia +%d", "Energia %d%%.\nParate e speciali\ncostano meno.",
                  "Parate e speciali costano meno." } },
    { tag = "Am\233l", category = { "Am\233liorations", "D\233pensez l'EXP en sant\233 et endurance." },
      health = { "Sant\233", "Sant\233 +%d", "Sant\233 max +%d,\nen plus de celle du jeu.",
                 "Sant\233 en plus de celle du jeu." },
      stamina = { "Endurance", "Endurance +%d", "Endurance %d%%.\nGarde, sp\233ciaux\nmoins chers.",
                  "Garde et sp\233ciaux co\251tent moins." } },
}

-- Each shop group takes over one Basic Moves group (source = its vanilla
-- name, slot = its position). Row k is owned once the shop level has reached
-- k and can be bought when it is k - 1; buying sets it to k.
local SHOP = {
    category = { text = 598, desc = 611 },
    groups = {
        { kind = "health", source = 403, slot = 0, text = 574, desc = 612,
          rows = { { cost = 5000,  name = 581, desc = 582 }, { cost = 10000, name = 583, desc = 584 },
                   { cost = 15000, name = 593, desc = 594 }, { cost = 20000, name = 596, desc = 597 } } },
        { kind = "stamina", source = 404, slot = 1, text = 599, desc = 613,
          rows = { { cost = 5000,  name = 601, desc = 602 }, { cost = 10000, name = 603, desc = 604 },
                   { cost = 15000, name = 718, desc = 719 }, { cost = 20000, name = 783, desc = 784 } } },
    },
}

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
    if game.read_u32(m + GAME_MODE) == 2 then return nil end
    return m
end

local CHARACTER     = 0xCC          -- character id of player p at +0xCC + p * 4
local BUDGET        = 200           -- writes per callback (the runtime allows 256)

local ready = false             -- our strings are in place and rows retitled
local writes = 0                -- writes staged in this callback
local resume = false            -- a sync ran out of budget; finish it next callback
local pending = nil             -- { kind, store, k } while the game runs our purchase
local saved = nil               -- the level slot Upgrade is about to change
local asked = nil               -- node passed to CanPurchase / IsCombo
local tree = nil                -- the tree copy our changes were made to
local changed = {}              -- [address] = { was = vanilla value, now = ours }
local costs = {}                -- per player: { base = vanilla costs, now = ours, level }
local ticked = nil              -- { record, stamina before } around one Tick

-- Exact powers of two, so f32 <-> Lua number conversions don't drift.
local POW2 = {}
do
    local v = 1.0 for e = 0, 127 do POW2[e] = v v = v * 2.0 end
    v = 1.0 for e = 0, 150 do POW2[-e] = v v = v / 2.0 end
end

local function f32_to(u)
    local exp = (u >> 23) & 0xFF
    if exp == 0xFF then return nil end          -- inf/nan: never a stamina value
    local frac = u & 0x7FFFFF
    local x = exp == 0 and frac * POW2[-149] or (frac + 0x800000) * POW2[exp - 150]
    return u >> 31 ~= 0 and -x or x
end

-- (The game's Lua 5.4 has no math.frexp, so the exponent is found by hand.)
local function f32_from(x)
    if x ~= x then return 0x7FC00000 end        -- nan
    local sign = x < 0 and 1 or 0
    x = x < 0 and -x or x
    if x == 0 then return sign << 31 end
    if x >= POW2[127] * 2.0 then return sign << 31 | 0x7F800000 end
    local e = 0                                 -- 2^e <= x < 2^(e+1)
    while e < 127 and x >= POW2[e + 1] do e = e + 1 end
    while e > -149 and x < POW2[e] do e = e - 1 end
    if e < -126 then return sign << 31 | math.floor(x / POW2[-149] + 0.5) end
    local frac = math.floor((x / POW2[e] - 1.0) * 0x800000 + 0.5)
    if frac == 0x800000 then frac, e = 0, e + 1 end
    if e > 127 then return sign << 31 | 0x7F800000 end
    return sign << 31 | (e + 127) << 23 | frac
end

-- String at text index i, as an address (strings need not be aligned).
local function text_at(i)
    if i >= game.read_u32(TEXT_COUNT) then return nil end
    local list = game.read_u32(TEXT_PTRS)
    if not plausible(list) then return nil end
    local p = game.read_u32(list + i * 4)
    if not plausible(p - p % 4) then return nil end
    return p
end

-- The built-in language whose "Upgrade" word is loaded; English otherwise.
local function language()
    local p = text_at(UPGRADE_TEXT)
    if p ~= nil then
        for _, lang in ipairs(LANGUAGES) do
            local hit = true
            for k = 1, #lang.tag do
                if game.read_u8(p + k - 1) ~= lang.tag:byte(k) then hit = false break end
            end
            if hit then return lang end
        end
    end
    return LANGUAGES[1]
end

-- Puts s at text index i if it fits in the bytes already there: true when it
-- is in place, false when it can't fit, nil when this callback's budget is
-- spent. Written in whole words; the last word keeps the bytes after our NUL.
local function put_text(i, s)
    local p = text_at(i)
    if p == nil then return false end
    local same = game.read_u8(p + #s) == 0
    for k = 1, #s do
        local b = game.read_u8(p + k - 1)
        if b == 0 then return false end         -- too short for our string
        if b ~= s:byte(k) then same = false end
    end
    if same then return true end
    local bytes = s .. "\0"
    if writes + (#bytes + 3) // 4 > BUDGET then return nil end
    for k = 0, #bytes - 1, 4 do
        local word = 0
        for j = 0, 3 do
            local b = k + j < #bytes and bytes:byte(k + j + 1) or game.read_u8(p + k + j)
            word = word | b << (8 * j)
        end
        game.write_u32(p + k, word)
        writes = writes + 1
    end
    return true
end

-- What row k's description shows: the health it adds in total, or the size
-- the stamina bar now plays as.
local function row_figure(kind, k)
    if kind == "health" then return HP_STEPS[k] * HP_TEXT_STEP end
    return BAR[k]
end

-- Our strings, in the loaded language: true, false if any of them can't
-- fit, nil when the budget ran out first. Checked on every menu open, so a
-- reloaded text table is caught. The order is fixed, so a resumed sync picks
-- up where the last one stopped.
local function place_text()
    local lang = language()
    local all = { { SHOP.category.text, lang.category[1] }, { SHOP.category.desc, lang.category[2] } }
    for _, group in ipairs(SHOP.groups) do
        local words = lang[group.kind]
        all[#all + 1] = { group.text, words[1] }
        all[#all + 1] = { group.desc, words[4] }
        for k, row in ipairs(group.rows) do
            all[#all + 1] = { row.name, string.format(words[2], k) }
            all[#all + 1] = { row.desc, string.format(words[3], row_figure(group.kind, k)) }
        end
    end
    local result = true
    for _, t in ipairs(all) do
        local placed = put_text(t[1], t[2])
        if placed == false then return false end
        if placed == nil then result = nil end
    end
    return result
end

-- A tree field we change, remembering the vanilla value the first time.
-- False when this callback's budget is spent.
local function patch(addr, value)
    local now = game.read_u32(addr)
    if now ~= value and writes >= BUDGET then return false end
    if changed[addr] == nil then changed[addr] = { was = now } end
    changed[addr].now = value
    if now ~= value then
        game.write_u32(addr, value)
        writes = writes + 1
    end
    return true
end

-- Puts every changed field back where it still holds our value.
local function unpatch()
    for addr, c in pairs(changed) do
        if game.read_u32(addr) == c.now then game.write_u32(addr, c.was) end
    end
    changed = {}
end

-- The shop byte a level lives in: Health is shared (player 0's byte), Stamina
-- is per player.
local function shop_addr(m, player, kind)
    return m + LEVELS + (kind == "health" and 0 or player) * 0x1C + SHOP_SLOT
end

local function shop_level(m, player, kind)
    local b = game.read_u8(shop_addr(m, player, kind))
    if b & SHOP_MARK == 0 then return 0 end
    local level = kind == "health" and b & 7 or (b >> 3) & 7
    return level < SHOP_ROWS and level or SHOP_ROWS
end

local function set_shop_level(m, player, kind, v)
    local addr = shop_addr(m, player, kind)
    local b = game.read_u8(addr)
    if b & SHOP_MARK == 0 then b = SHOP_MARK end
    if kind == "health" then b = (b & ~7) | v else b = (b & ~0x38) | v << 3 end
    game.write_u8(addr, b)
end

-- The menu player, or nil.
local function menu_player()
    local player = game.read_u32(MENU_PLAYER)
    if player > 1 then return nil end
    return player
end

-- Max health with the shop's steps on top. The game only ever writes vanilla
-- values (base plus nothing), so any value of the form base + l steps is one
-- we may raise to base + level steps; anything else isn't ours to touch.
local function ensure_health(m)
    local mode = game.read_u32(m + GAME_MODE)
    if mode > 1 then return end
    local function table_hp(ups) return game.read_u32(HP_TABLE + (ups * 5 + mode) * 4) end
    local ups = game.read_u32(m + HEALTH_UPS)
    local base = table_hp(ups < HP_MAX_UPS and ups or HP_MAX_UPS)
    local step = table_hp(HP_MAX_UPS) - table_hp(HP_MAX_UPS - 1)
    if base < 1 or base > 100000 or step < 1 or step > 100000 then return end
    local want = base + HP_STEPS[shop_level(m, 0, "health")] * step
    local function known(v, scale, div)
        for l = 0, HP_STEPS[SHOP_ROWS] do
            if v == (base + l * step) * scale // div then return true end
        end
        return false
    end
    local now = game.read_u32(m + MAX_HP)
    if now ~= want and known(now, 1, 1) then
        game.write_u32(m + MAX_HP, want)
    end
    local area = game.read_u32(m + HP_LEVEL)
    if area < 1 or area > HP_LEVEL_MAX then return end
    local div = mode == 1 and 2 or 1
    for player = 0, mode do
        local actor = game.read_u32(ENTITY + player * ENTITY_STRIDE + ACTOR)
        if plausible(actor) then
            local max, new = game.read_u32(actor + ACTOR_MAX_HP), want * area // div
            if max ~= new and known(max, area, div) then
                game.write_u32(actor + ACTOR_MAX_HP, new)
                local hp = game.read_u32(actor + ACTOR_HP)
                if hp > 0 and hp < 0x80000000 then       -- heal by what max gained, never revive
                    if new > max then hp = hp + new - max end
                    game.write_u32(actor + ACTOR_HP, hp < new and hp or new)
                end
            end
        end
    end
end

-- A stamina cost as the bigger bar sees it: cost * 100 / BAR[level],
-- exact (it may have a fraction; see ensure_stamina).
local function scaled(c, level)
    if c < 1 or c > 100000 then return c end
    return c * 100 / BAR[level]
end

-- Player p's stamina costs, scaled to their Stamina level. Costs that are no
-- longer the ones we wrote were just copied from the character's template.
-- The costs are integers, and the smallest (3, drained every frame by moves
-- like the long jump) would round 1.5 up to 2 at Stamina +4. So a fractional
-- cost alternates between its floor and ceiling from frame to frame, carrying
-- the remainder, and averages out exact.
local function ensure_stamina(m, rec)
    local off = rec - STAMINA
    if off < 0 or off % STAMINA_STRIDE ~= 0 then return end
    local player = off // STAMINA_STRIDE
    if player > 1 or player >= game.read_u32(STAMINA_COUNT) then return end
    local level = shop_level(m, player, "stamina")
    local cur = {}
    for i = 1, COSTS do cur[i] = game.read_u32(rec + (i - 1) * 4) end
    local s = costs[player + 1]
    local fresh = s == nil
    if s then
        for i = 1, COSTS do if cur[i] ~= s.now[i] then fresh = true end end
        if not fresh and s.level == level and not s.dither then return end
    end
    local base = fresh and cur or s.base
    local carry = (not fresh and s.level == level) and s.carry or { 0.5, 0.5, 0.5, 0.5 }
    local now, dither = {}, false
    for i = 1, COSTS do
        local exact = scaled(base[i], level)
        if exact == math.floor(exact) then
            now[i] = math.tointeger(exact)
        else
            dither = true
            local due = carry[i] + exact
            now[i] = math.floor(due)
            if now[i] < 1 then now[i] = 1 end
            carry[i] = due - now[i]
        end
        if now[i] ~= cur[i] then game.write_u32(rec + (i - 1) * 4, now[i]) end
    end
    costs[player + 1] = { base = base, now = now, level = level, carry = carry, dither = dither }
end

-- After a Tick: whatever it took off the bar was the sustained drain (regen
-- only adds, and is skipped while draining). Give back the share a bigger
-- bar wouldn't have spent, unless the drain emptied the bar and ended the
-- state.
local function refund_drain(m, t)
    local rec, before = t[1], t[2]
    local player = (rec - STAMINA) // STAMINA_STRIDE
    local level = shop_level(m, player, "stamina")
    if level == 0 then return end
    local after = f32_to(game.read_u32(rec + STAMINA_NOW))
    if after == nil or after <= 0 or after >= before then return end
    local back = (before - after) * (BAR[level] - 100) / BAR[level]
    game.write_u32(rec + STAMINA_NOW, f32_from(after + back))
end

-- The Basic Moves category under a character root, and the vanilla group
-- each shop group takes over (nil where it doesn't look as expected).
local function shop_nodes(root)
    local n, kids = game.read_u32(root + 0x0C), game.read_u32(root + 0x14)
    if n > 16 or not plausible(kids) then return nil end
    for i = 0, n - 1 do
        local c = game.read_u32(kids + i * 4)
        if plausible(c) and game.read_u32(c + 4) == 2 then
            local name = game.read_u32(c + 0x18)
            local count, list = game.read_u32(c + 0x0C), game.read_u32(c + 0x14)
            if (name == BASIC_TEXT or name == SHOP.category.text) and plausible(list) then
                local groups = {}
                for j, group in ipairs(SHOP.groups) do
                    local g = group.slot < count and game.read_u32(list + group.slot * 4) or 0
                    if plausible(g) and game.read_u32(g + 4) == 1 then
                        local gname, rows = game.read_u32(g + 0x18), game.read_u32(g + 0x0C)
                        if (gname == group.source or gname == group.text) and rows == #group.rows then
                            groups[j] = g
                        end
                    end
                end
                return c, groups
            end
        end
    end
    return nil
end

-- The shop kind, store and row index (1-n) when node is one of our shop rows.
local function shop_row(node)
    if not ready or not plausible(node) or game.read_u32(node + 4) ~= 0 then return nil end
    local g = game.read_u32(node + 0x10)
    if not plausible(g) then return nil end
    local gname = game.read_u32(g + 0x18)
    local kids = game.read_u32(g + 0x14)
    for _, group in ipairs(SHOP.groups) do
        if gname == group.text then
            for k = 1, #group.rows do
                if game.read_u32(kids + (k - 1) * 4) == node then return "basic", group, k end
            end
        end
    end
    return nil
end

local function char_of(m, player)
    local id = game.read_u32(m + CHARACTER + player * 4)
    if id ~= 0 and id ~= 1 and id ~= 0x58 and id ~= 0x52 then id = 0 end
    return id
end

-- The menu player's character root, matched the way SyncOwned matches it
-- (ids other than the four playable characters fall back to Liu Kang).
local function menu_root(m, blob)
    local player = menu_player()
    if player == nil then return nil end
    local id = char_of(m, player)
    local roots, list = game.read_u32(blob + 0x0C), game.read_u32(blob + 0x10)
    if roots > 8 or not plausible(list) then return nil end
    for r = 0, roots - 1 do
        local root = game.read_u32(list + r * 4)
        if plausible(root) and game.read_u32(root + 0x18) == id then return root end
    end
    return nil
end

-- Our rows under one character root; false when the budget ran out.
local function patch_root(m, root)
    local player = menu_player()
    local c, groups = shop_nodes(root)
    if c and player ~= nil then
        if not (patch(c + 0x18, SHOP.category.text) and patch(c + 0x1C, SHOP.category.desc)) then
            return false
        end
        for j, group in ipairs(SHOP.groups) do
            local g, value = groups[j], shop_level(m, player, group.kind)
            if g then
                if not (patch(g + 0x18, group.text) and patch(g + 0x1C, group.desc)) then return false end
                local kids = game.read_u32(g + 0x14)
                for k, row in ipairs(group.rows) do
                    local node = game.read_u32(kids + (k - 1) * 4)
                    if plausible(node) and not (patch(node + 0x18, row.name) and patch(node + 0x1C, row.desc)
                            and patch(node + 0x28, row.cost)
                            and patch(node + 0x2C, value >= k and 1 or 0)) then
                        return false
                    end
                end
            end
        end
    end
    return true
end

-- After the game syncs the menu: our text, costs and owned flags on the
-- menu player's character, or the vanilla rows back when our text has no
-- room. If the write budget runs out, the next CanPurchase call (the menu
-- asks it every frame while it draws) finishes the job.
local function sync()
    writes, resume = 0, false
    local m = manager()
    local blob = game.read_u32(MPD)
    if m == nil or not plausible(blob) then return end
    if blob ~= tree then changed = {}; tree = blob end     -- a fresh copy is vanilla
    local placed = place_text()
    if placed == false then ready = false; unpatch() return end
    if placed == nil then resume = true return end
    ready = true
    local root = menu_root(m, blob)
    if root and not patch_root(m, root) then resume = true end
end

-- The row is the next to buy in its store, affordable, and its cost really
-- is ours.
local function can_buy(node, kind, store, k)
    local m = manager()
    if m == nil then return false end
    if game.read_u32(node + 0x28) ~= store.rows[k].cost then return false end
    local player = menu_player()
    if player == nil then return false end
    if shop_level(m, player, store.kind) ~= k - 1 then return false end
    return game.read_u32(m + XP + player * PLAYER_STRIDE) >= store.rows[k].cost
end

-- Record the bought row and apply it at once (the pause menu shows the new
-- max health straight away).
local function apply_purchase(m, kind, store, k)
    local player = menu_player()
    if player == nil then return end
    if shop_level(m, player, store.kind) ~= k - 1 then return end
    set_shop_level(m, player, store.kind, k)
    if store.kind == "health" then
        ensure_health(m)
    else
        ensure_stamina(m, STAMINA + player * STAMINA_STRIDE)
    end
end

local function set_al(ctx, v)
    ctx.eax = (ctx.eax & 0xFFFFFF00) | v
end

return {
    { address = SYNC_OWNED, after = function(ctx) sync() end },
    {
        address = CAN_PURCHASE,
        before = function(ctx)
            if resume then sync() end
            asked = game.read_u32(ctx.esp + 4)
        end,
        after = function(ctx)
            local node = asked
            asked = nil
            local kind, store, k
            if node then kind, store, k = shop_row(node) end
            if kind then set_al(ctx, can_buy(node, kind, store, k) and 1 or 0) end
        end,
    },
    {
        address = IS_COMBO,
        before = function(ctx) asked = game.read_u32(ctx.esp + 4) end,
        after = function(ctx)
            local node = asked
            asked = nil
            if node and shop_row(node) then set_al(ctx, 1) end
        end,
    },
    {
        address = BUY_COMBO,
        before = function(ctx)
            local node = game.read_u32(SELECTED)
            local kind, store, k = shop_row(node)
            pending = kind and can_buy(node, kind, store, k) and { kind, store, k } or nil
        end,
        after = function(ctx)
            local p = pending
            pending = nil
            local m = manager()
            if p == nil or m == nil or ctx.eax & 0xFF ~= 1 then return end
            apply_purchase(m, p[1], p[2], p[3])
        end,
    },
    {
        -- Upgrade(player, slot, timer), cdecl. During our purchase it is called
        -- with a combo slot; put that slot back the way it was.
        address = UPGRADE,
        before = function(ctx)
            saved = nil
            local m = manager()
            if pending == nil or m == nil then return end
            local player, slot = game.read_u32(ctx.esp + 4), game.read_u32(ctx.esp + 8)
            if player > 1 or slot > 27 then return end
            local i = player * 0x1C + slot
            local timer = m + ABILITY_BASE + i * 4
            local records = m + ABILITY_BASE + 0x118 + i * 0x24 + 0x20
            saved = { level = m + LEVELS + i, l = game.read_u8(m + LEVELS + i),
                      timer = timer, t = game.read_u32(timer),
                      records = records, r = game.read_u32(records) }
        end,
        after = function(ctx)
            local s = saved
            saved = nil
            if s == nil then return end
            if game.read_u8(s.level) ~= s.l then game.write_u8(s.level, s.l) end
            if game.read_u32(s.timer) ~= s.t then game.write_u32(s.timer, s.t) end
            if game.read_u32(s.records) ~= s.r then game.write_u32(s.records, s.r) end
        end,
    },
    {
        -- The story's meter level-up adds without a cap; keep it within the
        -- HUD's three levels for saves where 0.2/0.3 sold a level early.
        address = METER_LEVELUP,
        after = function(ctx)
            local m = manager()
            if m == nil then return end
            for player = 0, 1 do
                local addr = m + METER_LEVEL + player * PLAYER_STRIDE
                if game.read_u32(addr) > METER_MAX then game.write_u32(addr, METER_MAX) end
            end
        end,
    },
    {
        -- Once per stamina record per frame: keep that player's costs scaled,
        -- (on player 0's record) the shop's health on top, and afterwards
        -- scale what the sustained drain took.
        address = STAMINA_TICK,
        before = function(ctx)
            ticked = nil
            local m = manager()
            if m == nil then return end
            local rec = ctx.ecx
            ensure_stamina(m, rec)
            if rec == STAMINA then ensure_health(m) end
            local off = rec - STAMINA
            if off >= 0 and off % STAMINA_STRIDE == 0 and off // STAMINA_STRIDE <= 1 then
                local now = f32_to(game.read_u32(rec + STAMINA_NOW))
                if now then ticked = { rec, now } end
            end
        end,
        after = function(ctx)
            local t = ticked
            ticked = nil
            local m = manager()
            if t and m then refund_drain(m, t) end
        end,
    },
}
