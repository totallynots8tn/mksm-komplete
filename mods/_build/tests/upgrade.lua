package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m = H.load(arg[1])

local MGR, BLOB, TEXTS, STR = 0x80300000, 0x80100000, 0x80200000, 0x80210000
local SYNC, CAN, COMBO, BUY, UPGRADE, LEVELUP = 0x13A12, 0x116CC, 0x15EDE, 0x13954, 0x1647E, 0x1116D
local TICK = 0x16965
local LEVEL0, LEVEL1 = MGR + 0x4978, MGR + 0x49C8
local SHOP0, SHOP1 = MGR + 0x1C4 + 27, MGR + 0x1C4 + 0x1C + 27
local STAM, STAM_N = 0x4E6598, 0x4E65E0
local ACT = { 0x80400000, 0x80401000 }
H.w32(0x5ACEBC, MGR)
H.w32(MGR + 0x88, 0)
H.w32(0x4EFA88, BLOB)
H.w32(0x4EFA60, 0)
H.w32(LEVEL0, 1)

-- health: the game's table (solo, co-op columns), both player actors, and the
-- map-load apply that writes vanilla values
local HP_ROWS = { { 200, 400 }, { 300, 600 }, { 400, 800 }, { 500, 1000 }, { 600, 1200 } }
for ups = 0, 4 do
    H.w32(0x50B544 + ups * 20, HP_ROWS[ups + 1][1]); H.w32(0x50B544 + ups * 20 + 4, HP_ROWS[ups + 1][2])
end
for p = 0, 1 do H.w32(0x5D1AB8 + p * 0x3238 + 0x200, ACT[p + 1]) end
local function vanilla_hp(ups, area, mode)
    mode = mode or 0
    H.w32(MGR + 0x88, mode); H.w32(MGR + 0xE0, ups); H.w32(MGR + 0x90, area)
    local base = HP_ROWS[ups + 1][mode == 1 and 2 or 1]
    H.w32(MGR + 0x94, base); H.wf32(MGR + 0x8C, base)
    for p = 0, mode == 1 and 1 or 0 do
        local v = base * area // (mode == 1 and 2 or 1)
        H.w32(ACT[p + 1] + 0x370, v); H.w32(ACT[p + 1] + 0x368, v)
    end
end
local function hp(p) return H.r32(ACT[p + 1] + 0x368), H.r32(ACT[p + 1] + 0x370) end

-- stamina: one record per player, costs copied from the character template
local function template(p) for i, c in ipairs({ 10, 20, 100, 3 }) do H.w32(STAM + p * 0x24 + (i - 1) * 4, c) end end
local function costs(p)
    local t = {}
    for i = 1, 4 do t[i] = H.r32(STAM + p * 0x24 + (i - 1) * 4) end
    return table.concat(t, ",")
end
local function tick(p, mod) H.invoke(mod or m, TICK, { ecx = STAM + p * 0x24 }, nil) end
H.w32(STAM_N, 2); template(0); template(1)
vanilla_hp(0, 1)

-- text table: every entry a 45-byte placeholder of its own
H.w32(0x5B04A4, TEXTS)
H.w32(0x5AC508, 1751)
local function placeholder(i, len)
    local p = STR + i * 64
    for k = 0, len - 1 do H.w8(p + k, 0x58) end
    H.w8(p + len, 0)
    H.w32(TEXTS + i * 4, p)
end
for i = 0, 1750 do placeholder(i, 45) end
local function text(i)
    local p, s = H.r32(TEXTS + i * 4), {}
    while H.r8(p + #s) ~= 0 do s[#s + 1] = string.char(H.r8(p + #s)) end
    return table.concat(s)
end

-- tree: one root with Basic Moves (3 groups of 4), Combos, Skill (4 leaves),
-- Team (2 leaves) and Fatalities (3 leaves, the first already discovered)
local next_node = BLOB + 0x100
local function node(kind, name, parent, n)
    local p = next_node
    next_node = next_node + 0x30 + n * 4
    H.w32(p + 4, kind); H.w32(p + 0x0C, n); H.w32(p + 0x10, parent or 0)
    H.w32(p + 0x14, p + 0x30); H.w32(p + 0x18, name); H.w32(p + 0x1C, name + 100)
    return p
end
local function child(parent, i, c) H.w32(parent + 0x30 + i * 4, c) end
local root = node(3, 0, nil, 5)
local basic = node(2, 402, root, 3)
local combos = node(1, 463, root, 2)
local skill = node(1, 464, root, 4)
local team = node(1, 465, root, 2)
local fatal = node(1, 400, root, 3)
child(root, 0, basic); child(root, 1, combos); child(root, 2, skill); child(root, 3, team); child(root, 4, fatal)
local group, rows = {}, {}
for j = 1, 3 do
    group[j] = node(1, 402 + j, basic, 4); child(basic, j - 1, group[j])
    rows[j] = {}
    for k = 1, 4 do
        rows[j][k] = node(0, 480 + j * 4 + k, group[j], 0); child(group[j], k - 1, rows[j][k])
        H.w32(rows[j][k] + 0x2C, 1)
    end
end
local combo_leaf = {}
for k = 0, 1 do
    combo_leaf[k] = node(0, 920 + k, combos, 0); child(combos, k, combo_leaf[k])
    H.w32(combo_leaf[k] + 0x28, 5000)
end
local ex = {}
for k = 1, 4 do
    ex[k] = node(0, 1409 + k, skill, 0); child(skill, k - 1, ex[k])
    H.w32(ex[k] + 0x2C, 1)
end
local gear = {}
for k = 1, 2 do
    gear[k] = node(0, 1021 + k, team, 0); child(team, k - 1, gear[k])
    H.w32(gear[k] + 0x2C, 1)
end
local fat = {}
for k = 1, 3 do
    fat[k] = node(0, 1061 + k, fatal, 0); child(fatal, k - 1, fat[k])
    H.w32(fat[k] + 0x1C, 1181 + k)                 -- the input text
end
local FAT_LIST, FAT_COUNT = 0x4DF5DC, 0x4DFC1C
H.w32(FAT_LIST, 1062); H.w32(FAT_COUNT, 1)         -- Shaolin Soccer, performed once
H.w32(fat[1] + 0x2C, 1)                            -- so SyncOwned showed its input
-- a second character (Kung Lao, id 1) with its own Basic Moves
local root2 = node(3, 1, nil, 1)
local basic2 = node(2, 402, root2, 2)
child(root2, 0, basic2)
local kl = {}
for j = 1, 2 do
    local g = node(1, 402 + j, basic2, 4); child(basic2, j - 1, g); kl[j] = g
    for k = 1, 4 do child(g, k - 1, node(0, 480 + j * 4 + k, g, 0)) end
end
H.w32(MGR + 0xD0, 1)
H.w32(BLOB + 0x0C, 2); H.w32(BLOB + 0x10, BLOB + 0x20); H.w32(BLOB + 0x20, root); H.w32(BLOB + 0x24, root2)
local health, stamina = rows[1], rows[2]

local function xp(v, player) H.w32(MGR + 0x4940 + (player or 0) * 0x50, v) end
-- CanPurchase's callers by return address: the purchase dispatcher (the
-- default here), the "anything to buy" search, and the two that run while a
-- row is hovered (description panel, preview video)
local TO_BUY, FOR_ANY, DESCRIPTION, PREVIEW = 0x9E5D9, 0x9BC0E, 0x9CE58, 0x9D3A0
local function ask_with(mod, address, node_ptr, vanilla, from)
    local ctx = { esp = 0xD0000100, eax = 0xABCDEF00 | vanilla }
    H.w32(ctx.esp, from or TO_BUY); H.w32(ctx.esp + 4, node_ptr)
    H.invoke(mod, address, ctx, nil)
    return ctx.eax & 0xFF, ctx.eax >> 8
end
local function ask(address, node_ptr, vanilla, from) return ask_with(m, address, node_ptr, vanilla, from) end

-- before the menu opens the shop is off: vanilla answers stand
assert(ask(CAN, health[1], 0) == 0 and ask(CAN, ex[1], 0) == 0, "shop active before sync")

-- 1. sync: Basic Moves becomes Upgrades with Health and Stamina (4 rows
-- each), Skill and Team stay vanilla. The strings don't fit in
-- one callback, so the menu's CanPurchase calls resume it.
H.invoke(m, SYNC, {}, nil)
for _ = 1, 4 do ask(CAN, ex[1], 0) end
assert(#H.failed == 0, H.failed[1])
assert(H.r32(basic + 0x18) == 598 and text(598) == "Upgrades", "category")
assert(text(H.r32(basic + 0x1C)) == "Spend EXP on health and stamina.", "category desc")
assert(H.r32(group[1] + 0x18) == 574 and text(574) == "Health", "health group")
assert(H.r32(group[2] + 0x18) == 599 and text(599) == "Stamina", "stamina group")
assert(text(H.r32(group[1] + 0x1C)) == "Extra health on top of the game's.", "health group desc")
assert(text(H.r32(group[2] + 0x1C)) == "Blocks and specials cost less stamina.", "stamina group desc")
assert(H.r32(group[1] + 0x0C) == 4 and H.r32(group[2] + 0x0C) == 4, "row counts")
assert(text(H.r32(health[1] + 0x18)) == "Health +1" and text(H.r32(stamina[3] + 0x18)) == "Stamina +3",
    "row names")
assert(text(H.r32(health[4] + 0x1C)) == "Max health +800,\non top of the game's.", "health desc")
assert(text(H.r32(stamina[1] + 0x1C)) == "Stamina 125%.\nBlocks and specials\ncost less.", "stamina desc")
assert(text(H.r32(stamina[4] + 0x1C)) == "Stamina 300%.\nBlocks and specials\ncost less.", "stamina desc 4")
for k = 1, 4 do
    assert(H.r32(health[k] + 0x28) == 5000 * k and H.r32(health[k] + 0x2C) == 0, "health row " .. k)
    assert(H.r32(stamina[k] + 0x28) == 5000 * k and H.r32(stamina[k] + 0x2C) == 0, "stamina row " .. k)
end
-- Running Attacks became Weapons; with no weapon in the area it shows one
-- "none here" row that can't be bought
assert(H.r32(group[3] + 0x18) == 617 and text(617) == "Weapons", "weapons group")
assert(text(H.r32(group[3] + 0x1C)) == "Summon this area's weapons.", "weapons group desc")
assert(H.r32(group[3] + 0x0C) == 1, "weapon rows with none in the area: " .. H.r32(group[3] + 0x0C))
assert(text(H.r32(rows[3][1] + 0x18)) == "None here       " and H.r32(rows[3][1] + 0x28) == 0, "none-here row")
-- Skill became the EX store: four rows, none owned (no flags yet)
assert(H.r32(skill + 0x18) == 614 and text(614) == "EX Moves", "ex store")
assert(text(H.r32(skill + 0x1C)) == "Hold L2 with a special for its EX version.", "ex store desc")
-- (rows carry the tier: Liu Kang's * ~ | ^ top out at 4 4 3 5; tier 1 costs 5000)
for k, label in ipairs({ "EX * 0/4  ", "EX ~ 0/4  ", "EX | 0/3  ", "EX ^ 0/5  " }) do
    assert(text(H.r32(ex[k] + 0x18)) == label and H.r32(ex[k] + 0x28) == 5000
        and H.r32(ex[k] + 0x2C) == 0, "ex row " .. k .. ": " .. text(H.r32(ex[k] + 0x18)))
end
assert(text(H.r32(ex[1] + 0x1C)) == "L2 + *: top-tier move.\nCosts extra stamina.", "ex row desc")
assert(H.r32(team + 0x18) == 465 and H.r32(gear[1] + 0x18) == 1022 and H.r32(gear[1] + 0x2C) == 1,
    "team touched")
assert(H.r32(combo_leaf[0] + 0x18) == 920, "combos touched")
assert(H.r32(basic2 + 0x18) == 402 and H.r32(kl[1] + 0x18) == 403, "other character patched")
local first_writes = H.max_writes

-- 2. can-buy: in order and affordable only; other rows keep vanilla answers
xp(4999)
local al, high = ask(CAN, health[1], 0)
assert(al == 0 and high == 0xABCDEF, "affordable at 4999")
xp(5000)
assert(ask(CAN, health[1], 0) == 1, "not buyable at 5000")
assert(ask(CAN, health[2], 0) == 0, "row 2 before row 1")
assert(ask(CAN, stamina[1], 0) == 1 and ask(CAN, stamina[2], 0) == 0, "stamina order")
assert(ask(CAN, ex[1], 0) == 1, "ex tier 1 not for sale at 5000")
xp(4999)
assert(ask(CAN, ex[1], 0) == 0 and ask(CAN, ex[1], 1) == 0, "ex tier 1 affordable at 4999")
xp(5000)
assert(ask(CAN, gear[1], 0) == 0 and ask(COMBO, gear[1], 0) == 0, "team answers changed")
assert(ask(CAN, combo_leaf[0], 1) == 1 and ask(CAN, combo_leaf[1], 0) == 0, "combo answer changed")
assert(ask(COMBO, health[3], 0) == 1 and ask(COMBO, stamina[2], 0) == 1, "shop rows not routed as combos")
assert(ask(COMBO, ex[1], 0) == 1, "ex rows not routed as combos")
assert(ask(COMBO, combo_leaf[0], 1) == 1 and ask(COMBO, rows[3][1], 0) == 0, "IsCombo changed elsewhere")

-- 3. a confirmed purchase: the game deducts XP and bumps a combo slot; we
-- restore the slot and apply the shop effect at once
local function buy(row_node, index, confirm)
    H.w32(0x4EFB38, row_node)
    local ctx = { esp = 0xD0000100, eax = 0 }
    H.invoke(m, BUY, ctx, function(c)
        if not confirm then c.eax = 0 return end
        local player = H.r32(0x4EFA60)
        local up = { esp = 0xD0000200 }
        H.w32(up.esp + 4, player); H.w32(up.esp + 8, 13 + index - 1)
        H.invoke(m, UPGRADE, up, function()
            H.w8(MGR + 0x1C4 + player * 0x1C + 13 + index - 1, 1)              -- SetLevel
            H.w32(MGR + 0xE4 + (player * 0x1C + 13 + index - 1) * 4, 0)
        end)
        local xpa = MGR + 0x4940 + player * 0x50
        H.w32(xpa, H.r32(xpa) - H.r32(row_node + 0x28))
        H.w32(row_node + 0x2C, 1)
        c.eax = 1
    end)
end
H.w32(MGR + 0xE4 + 13 * 4, 0x3F800000)         -- a nonzero timer to prove the restore
xp(5000)
buy(health[1], 1, true)
assert(#H.failed == 0, H.failed[1])
assert(H.r8(SHOP0) == 0x81, "health level not recorded")
assert(H.r32(MGR + 0xE0) == 0, "the game's own health count touched")
assert(H.r32(MGR + 0x94) == 300 and H.rf32(MGR + 0x8C) == 200, "base max health not raised, or +0x8C touched")
local cur, max = hp(0)
assert(cur == 300 and max == 300, "actor health " .. cur .. "/" .. max)
assert(H.r8(MGR + 0x1C4 + 13) == 0, "combo slot left unlocked")
assert(H.r32(MGR + 0xE4 + 13 * 4) == 0x3F800000, "timer not restored")
assert(H.r32(MGR + 0x4940) == 0, "XP not deducted")

-- 4. declined: nothing changes
xp(20000)
buy(health[2], 2, false)
assert(H.r8(SHOP0) == 0x81 and H.r32(MGR + 0x4940) == 20000, "declined purchase applied")

-- 4b. fatalities: the rows SyncOwned left unowned got a price; buying one
-- appends its name to the discovered list (the game saves it), and only once
assert(H.r32(fat[1] + 0x28) == 0, "discovered fatality priced")
assert(H.r32(fatal + 0x1C) == 616 and text(616) == "Buy a ??? fatality's\ninput with EXP.", "fatalities hint")
assert(H.r32(fat[2] + 0x28) == 5000 and H.r32(fat[3] + 0x28) == 5000, "undiscovered fatalities not priced")
assert(H.r32(fat[2] + 0x18) == 1063 and H.r32(fat[2] + 0x1C) == 1183, "fatality text touched")
assert(ask(CAN, fat[1], 0) == 0 and ask(COMBO, fat[1], 0) == 0, "discovered fatality for sale")
assert(ask(CAN, fat[2], 0) == 1 and ask(COMBO, fat[2], 0) == 1, "fatality not for sale")
-- hovering it must not reveal the input or the video: those callers get the
-- game's own answer, while the category still reads as having something to buy
assert(ask(CAN, fat[2], 0, DESCRIPTION) == 0, "hover shows the fatality input")
assert(ask(CAN, fat[2], 0, PREVIEW) == 0, "hover plays the fatality video")
assert(ask(CAN, fat[2], 0, FOR_ANY) == 1, "fatalities category not marked buyable")
assert(ask(CAN, health[2], 0, DESCRIPTION) == 1, "shop row description hidden")    -- +2 is next
xp(4999)
assert(ask(CAN, fat[2], 0) == 0, "fatality affordable at 4999")
xp(20000)
buy(fat[2], 2, true)
assert(#H.failed == 0, H.failed[1])
assert(H.r32(FAT_COUNT) == 2 and H.r32(FAT_LIST + 4) == 1063, "fatality not revealed")
assert(H.r32(FAT_LIST) == 1062, "discovered list reordered")
assert(H.r32(MGR + 0x4940) == 15000, "fatality XP")
assert(H.r8(MGR + 0x1C4 + 14) == 0, "combo slot left unlocked by a fatality")
H.w32(fat[2] + 0x2C, 0)                            -- even if a row reads unowned again
assert(ask(CAN, fat[2], 0) == 0, "revealed fatality for sale twice")
H.w32(fat[2] + 0x2C, 1)
H.w32(FAT_COUNT, 400)
assert(ask(CAN, fat[3], 0) == 0, "for sale with the list full")
H.w32(FAT_COUNT, 401)
assert(ask(CAN, fat[3], 0) == 0, "for sale with a count we don't understand")
H.w32(FAT_COUNT, 2)
H.w32(MGR + 0x88, 2)
assert(ask(CAN, fat[3], 0) == 0, "fatality for sale in versus")
H.w32(MGR + 0x88, 0)
assert(H.r32(FAT_COUNT) == 2, "list changed without a purchase")
xp(20000)

-- 4c. weapons: one row per weapon type in the area (first halves with a
-- model, placed at a node or lying as a body); buying one sets its home to
-- the buyer's feet, refills it and starts the countdown, for both halves of
-- a pair, and the row stays for sale
local WPN = 0x5A3AC0
local function weapon(i, name, half, body, node, model)
    local w = WPN + 8 + i * 0x27C
    for k = 1, #name do H.w8(w + 0x0C + k - 1, name:byte(k)) end
    H.w8(w + 0x0C + #name, 0)
    H.w8(w + 0x178, half); H.w32(w + 0x124, body); H.w32(w + 0x174, node); H.w32(w + 0x12C, model)
    H.w32(w + 0x268, 1000); H.w32(w + 0x26C, 400); H.w32(w + 0x10C, 0); H.w32(w + 0x230, 0)
    return w
end
local sword = weapon(0, "sword", 0, 0, 0xFFFFFFFF, 0x122)                 -- not in this area
local slot = weapon(1, "weapon_pickup00", 0, 0, 5, 0xFFFFFFFF)            -- no model: never sold
local kama1 = weapon(2, "kama01", 0, 0x81824F00, 0xFFFFFFFF, 0x11A)       -- lying on the floor
local kama2 = weapon(3, "kama02", 1, 0x8182C700, 0xFFFFFFFF, 0x11C)
H.w32(kama1 + 0x17C, kama2)
local function level_home(w)                     -- where the level put the kamas (the gate)
    H.wf32(w + 0x234, 4518.25); H.wf32(w + 0x238, -5941.75); H.wf32(w + 0x23C, 3748.5)
    H.w8(w + 0x244, 1); H.wf32(w + 0x220, 4400.5)
end
level_home(kama1); level_home(kama2)
H.w32(WPN + 0x56FC, 4)
local POS1 = 0x5D1AB8 + 0x80
H.wf32(POS1, 100); H.wf32(POS1 + 4, -200); H.wf32(POS1 + 8, 300)
local function resync() H.invoke(m, SYNC, {}, nil); for _ = 1, 3 do ask(CAN, combo_leaf[0], 1) end end
resync()
assert(#H.failed == 0, H.failed[1])
local wrow = rows[3]
assert(H.r32(group[3] + 0x0C) == 1 and text(H.r32(wrow[1] + 0x18)) == "Kamas           ", "kama row")
assert(H.r32(wrow[1] + 0x28) == 2000 and H.r32(wrow[1] + 0x2C) == 0, "kama row price")
assert(text(H.r32(wrow[1] + 0x1C)) == "Appears where you buy it.\nThrown, it returns.", "weapon row desc")
xp(20000)
assert(ask(CAN, wrow[1], 0) == 1 and ask(COMBO, wrow[1], 0) == 1, "kamas not for sale")
assert(ask(CAN, wrow[1], 0, DESCRIPTION) == 1, "weapon description hidden")
assert(ask(CAN, wrow[1], 0, PREVIEW) == 0, "weapon row plays a running-attack video")
H.w32(kama1 + 0x10C, 0x5D1AB8)
assert(ask(CAN, wrow[1], 0) == 0, "for sale while held")
H.w32(kama1 + 0x10C, 0)
xp(1999)
assert(ask(CAN, wrow[1], 0) == 0, "affordable at 1999")
xp(20000)
H.w8(MGR + 0x1C4 + 15, 0)
buy(wrow[1], 3, true)
assert(#H.failed == 0, H.failed[1])
for _, w in ipairs({ kama1, kama2 }) do
    assert(H.rf32(w + 0x234) == 250 and H.rf32(w + 0x238) == -257 and H.rf32(w + 0x23C) == 300,
        string.format("home %s,%s,%s", H.rf32(w + 0x234), H.rf32(w + 0x238), H.rf32(w + 0x23C)))
    assert(H.r8(w + 0x244) == 1 and H.r32(w + 0x26C) == 1000 and H.r32(w + 0x230) == 1, "summon fields")
end
assert(H.r32(sword + 0x230) == 0 and H.r32(sword + 0x26C) == 400, "sword touched")
assert(H.r32(MGR + 0x4940) == 18000, "weapon XP")
assert(H.r32(wrow[1] + 0x2C) == 1, "row not left bought for the jingle")
resync()
assert(H.r32(wrow[1] + 0x2C) == 0 and ask(CAN, wrow[1], 0) == 1, "not for sale again after the next menu open")
assert(H.r8(MGR + 0x1C4 + 15) == 0, "combo slot left unlocked by a weapon")
local RESPAWN = 0x12BEE
local function respawn(w) H.invoke(m, RESPAWN, { ecx = w }, nil) end
local function at_gate(w)
    return H.rf32(w + 0x234) == 4518.25 and H.rf32(w + 0x238) == -5941.75 and H.rf32(w + 0x23C) == 3748.5
        and H.r8(w + 0x244) == 1 and H.rf32(w + 0x220) == 4400.5
end
-- thrown (durability left): it flies back to the purchase spot
respawn(kama1); respawn(kama2)
assert(H.rf32(kama1 + 0x234) == 250 and H.rf32(kama2 + 0x234) == 250, "thrown kamas sent to the gate")
-- bought again elsewhere: the new spot, and the level's home still on record
H.wf32(POS1, 1000)
buy(wrow[1], 3, true)
assert(H.rf32(kama1 + 0x234) == 1150 and H.rf32(kama2 + 0x234) == 1150, "re-buy spot")
-- broken (the first half's durability decides): both halves go back to the gate
H.w32(kama1 + 0x26C, 0xFFFFFFF6)
respawn(kama1); respawn(kama2)
assert(#H.failed == 0, H.failed[1])
assert(at_gate(kama1) and at_gate(kama2), "broken kamas not sent back to the gate: " .. H.rf32(kama1 + 0x234))
-- after that the record is gone: a later respawn changes nothing
H.wf32(kama1 + 0x234, 77)
respawn(kama1)
assert(H.rf32(kama1 + 0x234) == 77, "respawn of an unsummoned weapon touched")
level_home(kama1)
-- the level placed the kamas again (a new area) after a purchase: the old
-- record is stale and a break leaves the new home alone
buy(wrow[1], 3, true)
H.wf32(kama1 + 0x234, 9999)
H.w32(kama1 + 0x26C, 0)
respawn(kama1)
assert(H.rf32(kama1 + 0x234) == 9999, "stale record applied")
level_home(kama1); level_home(kama2)
H.wf32(POS1, 100)
-- a second type in the area gets the next row; a model-less slot never does
H.w32(sword + 0x174, 7)
resync()
assert(H.r32(group[3] + 0x0C) == 2, "rows with two weapon types: " .. H.r32(group[3] + 0x0C))
assert(text(H.r32(wrow[1] + 0x18)) == "Sword           " and text(H.r32(wrow[2] + 0x18)) == "Kamas           ",
    "two rows: " .. text(H.r32(wrow[1] + 0x18)) .. "|" .. text(H.r32(wrow[2] + 0x18)))
-- the area loses its weapons: one "none here" row again, not for sale
H.w32(sword + 0x174, 0xFFFFFFFF); H.w32(kama1 + 0x124, 0); H.w32(kama2 + 0x124, 0)
resync()
assert(H.r32(group[3] + 0x0C) == 1 and text(H.r32(wrow[1] + 0x18)) == "None here       ", "none here again")
assert(H.r32(wrow[1] + 0x28) == 0 and ask(CAN, wrow[1], 0) == 0, "none-here row for sale")
H.w32(kama1 + 0x124, 0x81824F00); H.w32(kama2 + 0x124, 0x8182C700)
resync()
assert(text(H.r32(wrow[1] + 0x18)) == "Kamas           ", "kamas back")
xp(20000)
-- the "new abilities" popup announces an area's weapons once: while the
-- Moves list opens (the popup is modal inside it) its flag is set and its
-- text is ours; afterwards both are the game's again
local MOVES, FLAG = 0x1425F, 0x4EE890
local POPUP_MSG = "Weapons for sale here:\nUpgrades > Weapons."
local function open_moves()
    local seen = {}
    H.invoke(m, MOVES, {}, function() seen.text = text(407); seen.flag = H.r8(FLAG) end)
    assert(#H.failed == 0, H.failed[1])
    return seen
end
local vanilla407 = text(407)
local MAP = 0x505970
H.w32(MAP, 64)
H.w8(FLAG, 0)
local seen = open_moves()
assert(seen.text == POPUP_MSG and seen.flag == 1, "popup not armed: " .. seen.text)
assert(text(407) == vanilla407 and H.r8(FLAG) == 0, "popup text or flag not put back")
seen = open_moves()
assert(seen.text == vanilla407 and seen.flag == 0, "same area announced twice")
-- back in the same area later (the kamas get new bodies): still announced
H.w32(kama1 + 0x124, 0x81825000); resync()
seen = open_moves()
assert(seen.text == vanilla407 and seen.flag == 0, "same map announced on a revisit")
-- nothing affordable in a new area: no announcement (the game wouldn't show
-- it anyway), but the area stays unannounced until one is
H.w32(MAP, 71); xp(1999)
seen = open_moves()
assert(seen.text == vanilla407 and seen.flag == 0, "announced without the XP")
-- once affordable it is announced; a flag the game had set itself stays set
xp(20000); H.w8(FLAG, 1)
seen = open_moves()
assert(seen.text == POPUP_MSG and seen.flag == 1, "new area not announced")
assert(text(407) == vanilla407 and H.r8(FLAG) == 1, "the game's own flag cleared")
H.w8(FLAG, 0); H.w32(MAP, 64)
H.w32(kama1 + 0x124, 0x81824F00); resync()
xp(20000)

-- 5. stamina: the menu player's costs shrink at once, the other player's don't
buy(stamina[1], 1, true)
assert(#H.failed == 0, H.failed[1])
assert(H.r8(SHOP0) == 0x89 and H.r8(SHOP1) == 0, "stamina level not recorded for player 1 only")
assert(costs(0) == "8,16,80,2" and costs(1) == "10,20,100,3", "stamina 125%: " .. costs(0))
assert(H.r8(MGR + 0x1C4 + 13) == 0, "combo slot left unlocked by stamina")
assert(H.r32(MGR + 0x4940) == 15000, "stamina XP")
assert(ask(CAN, stamina[2], 0) == 1, "stamina row 2 not next")
buy(stamina[2], 2, true)
assert(H.r8(SHOP0) == 0x91 and costs(0) == "7,13,67,2", "stamina 150%: " .. costs(0))
assert(H.r32(LEVEL0) == 1, "meter level touched")

-- 6. player 2's menu: Health is shared, Stamina is their own
H.w32(0x4EFA60, 1)
xp(50000, 1)
assert(ask(CAN, health[1], 0) == 0 and ask(CAN, health[2], 0) == 1, "player 2 health ladder")
assert(ask(CAN, stamina[1], 0) == 1 and ask(CAN, stamina[3], 0) == 0, "player 2 stamina ladder")
H.invoke(m, SYNC, {}, nil)                     -- player 2 opens the menu: their character
assert(H.r32(basic2 + 0x18) == 598 and H.r32(kl[2] + 0x18) == 599 and H.r32(kl[2] + 0x0C) == 4,
    "player 2 character not patched")
buy(stamina[1], 1, true)
assert(H.r8(SHOP1) == 0x88 and costs(1) == "8,16,80,2" and costs(0) == "7,13,67,2", "player 2 stamina")
buy(health[2], 2, true)
assert(H.r8(SHOP0) == 0x92 and H.r32(MGR + 0x94) == 400, "shared health from player 2")
cur, max = hp(0)
assert(cur == 400 and max == 400, "player 1 actor after player 2's health " .. cur .. "/" .. max)
H.w32(0x4EFA60, 0)

-- 7. a vanilla combo purchase is untouched by the slot restore
H.w32(0x4EFB38, combo_leaf[0])
H.invoke(m, BUY, { esp = 0xD0000100, eax = 0 }, function(c)
    local up = { esp = 0xD0000200 }
    H.w32(up.esp + 4, 0); H.w32(up.esp + 8, 13)
    H.invoke(m, UPGRADE, up, function() H.w8(MGR + 0x1C4 + 13, 1) end)
    c.eax = 1
end)
assert(H.r8(MGR + 0x1C4 + 13) == 1 and H.r8(SHOP0) == 0x92, "vanilla combo purchase changed")

-- 8. the story's level-up after an early 0.2/0.3 purchase is clamped at 3
H.w32(LEVEL0, 4); H.w32(LEVEL1, 2)
H.invoke(m, LEVELUP, {}, nil)
assert(H.r32(LEVEL0) == 3 and H.r32(LEVEL1) == 2, "meter level not clamped")
H.w32(LEVEL0, 1)

-- 9. the tick keeps the shop on top of whatever the game rewrites
H.max_writes = 0
template(0)                                    -- Init copied the template again
tick(0); tick(1)
-- (the 3-cost dithers frame to frame, so only the whole costs are fixed)
assert(costs(0):match("^7,13,67,") and costs(1):match("^8,16,80,"), "costs after re-init: " .. costs(0))
tick(0); tick(1)
assert(H.max_writes <= 6, "steady tick wrote " .. H.max_writes)
vanilla_hp(0, 2)                               -- map load, area level 2
tick(0)
cur, max = hp(0)
assert(H.r32(MGR + 0x94) == 400 and H.rf32(MGR + 0x8C) == 200 and cur == 800 and max == 800,
    "map load " .. cur .. "/" .. max)
vanilla_hp(1, 2)                               -- the game's own health upgrade, picked up
tick(0)
cur, max = hp(0)
assert(H.r32(MGR + 0x94) == 500 and cur == 1000 and max == 1000, "on top of a pickup " .. cur .. "/" .. max)
H.w32(ACT[1] + 0x368, 250)                     -- damaged: max already ours, no heal
tick(0)
assert(hp(0) == 250, "healed while steady")
H.w32(ACT[1] + 0x370, 600); H.w32(ACT[1] + 0x368, 0)
tick(0)
cur, max = hp(0)
assert(cur == 0 and max == 1000, "revived " .. cur .. "/" .. max)
H.w32(ACT[1] + 0x370, 777)                     -- not a value the game's apply writes
tick(0)
assert(select(2, hp(0)) == 777, "foreign max touched")
vanilla_hp(1, 2, 1)                            -- co-op: the column doubles, each character gets half
tick(0)
assert(H.r32(MGR + 0x94) == 1000, "co-op base " .. H.r32(MGR + 0x94))
for p = 0, 1 do
    cur, max = hp(p)
    assert(cur == 1000 and max == 1000, "co-op player " .. p + 1 .. ": " .. cur .. "/" .. max)
end
vanilla_hp(1, 2, 2)                            -- versus: nothing of ours
H.w32(ACT[1] + 0x370, 600)
template(0)
tick(0)
assert(select(2, hp(0)) == 600 and costs(0) == "10,20,100,3", "versus touched")
vanilla_hp(1, 2)
tick(0)
assert(costs(0) == "7,13,67,2" and select(2, hp(0)) == 1000, "back from versus")
H.invoke(m, TICK, { ecx = STAM + 0x10 }, nil)  -- not a record start
H.w32(STAM_N, 1); template(1)                  -- only one record in use
tick(1)
assert(costs(1) == "10,20,100,3", "unused record scaled")
H.w32(STAM_N, 2)
tick(1)
assert(costs(1) == "8,16,80,2", "record 2 not scaled once in use")
assert(#H.failed == 0, H.failed[1])

-- 9b. the Tick's sustained drain (1.0 every 5th frame, no cost table) gets
-- the bigger bar's share back; regen, an emptied bar and level 0 don't
local function drain_tick(p, start, delta)
    local now = STAM + p * 0x24 + 0x10
    H.wf32(now, start)
    H.invoke(m, TICK, { ecx = STAM + p * 0x24 }, function()
        local v = H.rf32(now) + delta
        H.wf32(now, v > 0 and v or 0)
    end)
    return H.rf32(now)
end
local function near(a, b) return math.abs(a - b) < 1e-4 end
local v = drain_tick(0, 50, -1)                                    -- SHOP0 0x92: Stamina +2
assert(near(v, 49 + 50 / 150), "drain at +2: " .. v)
v = drain_tick(1, 50, -1)                                          -- SHOP1 0x88: Stamina +1
assert(near(v, 49.2), "drain at +1: " .. v)
assert(drain_tick(0, 50, 1) == 51, "regen refunded")
assert(drain_tick(0, 0.5, -1) == 0, "emptied bar refilled")
H.w8(SHOP1, 0x80)
assert(drain_tick(1, 50, -1) == 49, "drain refunded at level 0")
H.w8(SHOP1, 0x88)
H.w32(MGR + 0x88, 2)
assert(drain_tick(0, 50, -1) == 49, "drain refunded in versus")
H.w32(MGR + 0x88, 0)
H.w8(SHOP0, 0xA2)                                                  -- Stamina +4 (300%): a third
local spent = 100
H.wf32(STAM + 0x10, 100)
for _ = 1, 30 do spent = drain_tick(0, spent, -1) end
assert(near(spent, 90), "30 drains at +4 left " .. spent)
H.w8(SHOP0, 0x92)
assert(m[0x8DF60] == nil, "HUD bar still hooked")
assert(#H.failed == 0, H.failed[1])

-- 10. re-sync: owned follows the shop levels, cheaply; the game's own count
-- plays no part. (Player 2 opened the menu last: one sync puts player 1's
-- EX tier labels back first.)
H.invoke(m, SYNC, {}, nil); for _ = 1, 3 do ask(CAN, combo_leaf[0], 1) end
H.w8(SHOP0, 0x93)
H.w32(MGR + 0xE0, 4)
H.max_writes = 0
H.invoke(m, SYNC, {}, nil)
for k = 1, 4 do assert(H.r32(health[k] + 0x2C) == (k <= 3 and 1 or 0), "health owned after sync " .. k) end
assert(H.r32(stamina[2] + 0x2C) == 1 and H.r32(stamina[3] + 0x2C) == 0, "stamina owned after sync")
assert(H.max_writes <= 6, "re-sync rewrote " .. H.max_writes)
xp(20000)
assert(ask(CAN, health[4], 0) == 1, "health 4 not next at level 3")
H.w8(SHOP0, 0x94)
assert(ask(CAN, health[4], 0) == 0, "buyable past 4")

-- 11. the 0.3.0 weapon count in slot 27 reads as nothing bought
H.w8(SHOP0, 2)
vanilla_hp(1, 1)
tick(0)
assert(H.r32(MGR + 0x94) == 300 and costs(0) == "10,20,100,3", "legacy byte read as levels")
xp(5000)
assert(ask(CAN, health[1], 0) == 1, "health 1 not buyable over the legacy byte")
buy(health[1], 1, true)
assert(H.r8(SHOP0) == 0x81 and H.r32(MGR + 0x94) == 400, "legacy byte not replaced")

-- 12. versus mode: no shop answers
H.w32(MGR + 0x88, 2)
assert(ask(CAN, health[1], 0) == 0 and ask(CAN, ex[1], 0) == 0, "versus")
H.w32(MGR + 0x88, 0)

-- 13. EX moves: buying a row raises its button's tier (leaf * ~ | ^ -> game
-- slot 0 2 1 3 -> level slot 19 + it), one tier at a time, up to the top. While L2 is held, the move system's
-- question (and only it) gets the exact top tier, if the stamina covers the
-- cost, which comes off once, when the move spends its own
H.w32(STAM_N, 2)
xp(7500)
assert(ask(CAN, ex[1], 0) == 1 and ask(CAN, ex[2], 0) == 1, "ex rows not for sale")
buy(ex[2], 2, true)
assert(#H.failed == 0, H.failed[1])
assert(H.r8(MGR + 0x1C4 + 21) == 1 and H.r8(MGR + 0x1C4 + 20) == 0, "ex tier for ~ not in slot 21")
assert(H.r32(MGR + 0x4940) == 2500, "ex XP: " .. H.r32(MGR + 0x4940))
assert(ask(CAN, ex[2], 0) == 0, "tier 2 for sale before the menu reopens (row still prices tier 1)")
H.invoke(m, SYNC, {}, nil); for _ = 1, 3 do ask(CAN, combo_leaf[0], 1) end
assert(text(H.r32(ex[2] + 0x18)) == "EX ~ 1/4  " and H.r32(ex[2] + 0x28) == 10000, "tier 2 row")
xp(10000)
assert(ask(CAN, ex[2], 0) == 1, "tier 2 not for sale")
H.w8(MGR + 0x1C4 + 21, 4)                      -- ~ at its top: owned, not for sale
H.invoke(m, SYNC, {}, nil); for _ = 1, 3 do ask(CAN, combo_leaf[0], 1) end
assert(H.r32(ex[2] + 0x2C) == 1 and ask(CAN, ex[2], 0) == 0, "maxed ex row for sale")
H.w8(MGR + 0x1C4 + 19, 4)                      -- * at tier 4 too (game slot 0)
local NOW0 = STAM + 0x10
local PAD = 0x63AC20                           -- joypad object of port p at + p * 0xE4
local LT, RT, X, Y, B = 8, 9, 4, 5, 3          -- its analog bytes
local EVAL = 0x1CDB21                          -- a return address inside the evaluator
local function pad(player, held)               -- one frame of the pad translator
    local obj = PAD + player * 0xE4
    for k = 2, 9 do H.w8(obj + k, held[k] or 0) end
    H.invoke(m, 0x129480, { eax = obj }, nil)
    assert(#H.failed == 0, H.failed[1])
    return H.r8(obj + LT), H.r8(obj + RT)
end
local function level(player, slot, real, from)
    local ctx = { esp = 0xD0000300, eax = real }
    H.w32(ctx.esp, from or EVAL); H.w32(ctx.esp + 4, player); H.w32(ctx.esp + 8, slot)
    H.invoke(m, 0x111C2, ctx, nil)
    assert(#H.failed == 0, H.failed[1])
    return ctx.eax
end
local function spend(player)
    local ctx = { esp = 0xD0000400 }
    H.w32(ctx.esp + 4, player); H.w32(ctx.esp + 8, 2)
    H.invoke(m, 0x1406B, ctx, nil)
    assert(#H.failed == 0, H.failed[1])
end
local function stam(player) return H.rf32(NOW0 + (player or 0) * 0x24) end
H.w32(0x5CE878, 1000); H.wf32(NOW0, 100)
-- L2 + X (* owned): the game sees R2 + X, the special is EX
local lt, rt = pad(0, { [LT] = 0xFF, [X] = 0xFF })
assert(lt == 0 and rt == 0xFF, "L2 + X not turned into R2 + X")
assert(level(0, 0, 2) == 4 and stam() == 100, "EX special not at its top tier, or charged at the pick")
spend(0)
assert(stam() == 75, "EX stamina not charged: " .. stam())
spend(0)
assert(stam() == 75, "charged twice for one move")
-- still holding X: the press stays R2, but it isn't a new EX
H.w32(0x5CE878, 1010)
lt, rt = pad(0, { [LT] = 0xFF, [X] = 0xFF })
assert(rt == 0xFF, "held EX press lost its R2")
spend(0)
assert(stam() == 75, "a held press charged again")
pad(0, { [LT] = 0xFF })                        -- X released
-- untouched: L2 + an unbought button (B is |, slot 1), L2 + R2, a brushed
-- trigger, no stamina, the demo, versus
lt, rt = pad(0, { [LT] = 0xFF, [B] = 0xFF })
assert(lt == 0xFF and rt == 0, "L2 + an unbought button remapped")
lt, rt = pad(0, { [LT] = 0xFF, [RT] = 0xFF, [X] = 0xFF })
assert(lt == 0xFF and rt == 0xFF, "L2 + R2 + X touched")
pad(0, {})
lt, rt = pad(0, { [LT] = 0x80, [X] = 0xFF })
assert(lt == 0x80 and rt == 0, "a brushed trigger remapped")
pad(0, {})
H.wf32(NOW0, 24)
lt, rt = pad(0, { [LT] = 0xFF, [X] = 0xFF })
assert(lt == 0xFF and rt == 0, "remapped without the stamina")
pad(0, {}); H.wf32(NOW0, 100)
H.w8(0x5143A5, 1)
lt, rt = pad(0, { [LT] = 0xFF, [X] = 0xFF })
assert(rt == 0, "remapped in the demo")
H.w8(0x5143A5, 0); pad(0, {})
H.w32(MGR + 0x88, 2)
lt, rt = pad(0, { [LT] = 0xFF, [X] = 0xFF })
assert(rt == 0, "remapped in versus")
H.w32(MGR + 0x88, 0); pad(0, {})
-- a plain R2 special is never boosted or charged extra, and nothing but the
-- evaluator is answered
H.w32(0x5CE878, 2000)
assert(level(0, 0, 2) == 2, "a plain special boosted")
pad(0, { [LT] = 0xFF, [Y] = 0xFF })            -- Y is ~ (slot 2), owned
assert(level(0, 2, 1, 0x9D650) == 1, "boosted for the menu")
assert(level(0, 2, 1) == 4, "~ not boosted to its top tier 4")
assert(level(0, 2, 4) == 4, "a maxed special changed")
H.w8(MGR + 0x1C4 + 21, 2)                      -- EX ~ tier 2: the tier-2 variant, whatever R2 owns
pad(0, {}); pad(0, { [LT] = 0xFF, [Y] = 0xFF })
assert(level(0, 2, 4) == 2 and level(0, 2, 1) == 2, "EX tier 2 not reported as 2")
H.w8(MGR + 0x1C4 + 21, 4)
spend(0)
assert(stam() == 75, "EX on ~ not charged")
-- a press whose move never spends: its extra expires
pad(0, {}); H.wf32(NOW0, 100)
pad(0, { [LT] = 0xFF, [Y] = 0xFF })
H.w32(0x5CE878, 2100)
spend(0)
assert(stam() == 100, "an expired EX charged")
assert(level(0, 2, 1) == 1, "an expired EX boosted")
pad(0, {})
-- Stamina +2 (150%): the extra is scaled too
H.w8(SHOP0, 0x91)
pad(0, { [LT] = 0xFF, [X] = 0xFF })
spend(0)
assert(math.abs(stam() - (100 - 25 / 1.5)) < 1e-3, "scaled EX cost: " .. stam())
pad(0, {})
H.w8(SHOP0, 0x81)
-- player 2 (Kung Lao, port 1): his own flags, top tiers and stamina
H.w32(MGR + 0xCC + 4, 1); H.w8(MGR + 0x1C4 + 0x1C + 21, 3); H.wf32(NOW0 + 0x24, 100)
lt, rt = pad(1, { [LT] = 0xFF, [Y] = 0xFF })
assert(rt == 0xFF and level(1, 2, 1) == 3, "KL ~ EX")
spend(1)
assert(stam(1) == 80, "player 2's charge (Stamina +1: 20): " .. stam(1))
pad(1, {})
H.w32(MGR + 0xCC + 4, 0); H.w8(MGR + 0x1C4 + 0x1C + 21, 0)
H.w8(MGR + 0x1C4 + 19, 0); H.w8(MGR + 0x1C4 + 21, 0)

-- 15. Spanish (the game's own placeholders: 54-62 bytes): strings in cp1252
local es = H.load(arg[1])
local function put(i, s)
    local p = H.r32(TEXTS + i * 4)
    for k = 1, #s do H.w8(p + k - 1, s:byte(k)) end
    H.w8(p + #s, 0)
end
put(455, "Mejorar")
for _, i in ipairs({ 574, 598 }) do placeholder(i, 62) end
for _, i in ipairs({ 581, 582, 583, 584, 593, 594, 599, 601, 602, 603, 604, 611, 612, 613,
                     614, 616, 617, 618, 619, 683, 684, 693, 694, 696, 697, 698, 699,
                     701, 702, 703, 704, 711, 712, 718, 719, 783, 784 }) do
    placeholder(i, 56)
end
for _, i in ipairs({ 596, 597 }) do placeholder(i, 54) end
H.invoke(es, SYNC, {}, nil)
for _ = 1, 3 do ask_with(es, CAN, ex[1], 0) end
assert(#H.failed == 0, H.failed[1])
assert(text(598) == "Mejoras" and text(574) == "Salud" and text(599) == "Energ\237a", "spanish names")
assert(text(597) == "Vida m\225xima +800,\nadem\225s de la del juego.", "spanish desc: " .. text(597))
assert(text(784) == "Energ\237a 300%.\nBloquear y especiales\ncuestan menos.", "spanish stamina desc")
assert(text(718) == "Energ\237a +3", "spanish stamina row 3")
assert(H.r32(skill + 0x18) == 614 and text(614) == "Movimientos EX" and H.r32(team + 0x18) == 465, "spanish tree")
assert(text(616) == "Compra la secuencia de\nun ??? con EXP.", "spanish fatalities hint")
assert(text(617) == "Armas" and text(684) == "Kamas           ", "spanish weapons")
assert(text(698) == "Armas a la venta aqu\237:\nMejoras > Armas.", "spanish popup")

-- 16. the text table reloads with placeholders too short: every field is put back
local vanilla = { [basic + 0x18] = 402, [group[1] + 0x18] = 403, [group[2] + 0x18] = 404,
                  [group[2] + 0x0C] = 4, [health[1] + 0x18] = 485, [health[1] + 0x1C] = 585,
                  [health[1] + 0x28] = 0, [health[1] + 0x2C] = 1, [stamina[2] + 0x18] = 490,
                  [stamina[4] + 0x28] = 0, [skill + 0x18] = 464, [ex[1] + 0x18] = 1410,
                  [fat[3] + 0x28] = 0, [fatal + 0x1C] = 500,
                  [group[3] + 0x18] = 405, [group[3] + 0x0C] = 4, [rows[3][1] + 0x18] = 493 }
-- (the first instance holds the vanilla values; a second one would only
-- ever see a fresh tree in the game)
for _, i in ipairs({ 582, 584, 594, 597, 784 }) do placeholder(i, 20) end
H.invoke(m, SYNC, {}, nil)
for addr, v in pairs(vanilla) do
    assert(H.r32(addr) == v, string.format("not restored at %X: %d", addr, H.r32(addr)))
end
assert(ask(CAN, health[1], 0) == 0 and ask(CAN, ex[1], 0) == 0, "shop still answering")

-- 17. a write budget too small for one callback: the sync finishes over the
-- CanPurchase calls the menu makes while it draws
local src = assert(io.open(arg[1], "rb")):read("a")
local small, n = src:gsub("local BUDGET        = 200", "local BUDGET        = 40")
assert(n == 1, "BUDGET line not found")
local tmp = os.tmpname()
assert(io.open(tmp, "wb")):write(small):close()
local tiny = H.load(tmp)
os.remove(tmp)
for _, i in ipairs({ 574, 598, 581, 582, 583, 584, 593, 594, 596, 597, 599, 601, 602, 603, 604,
                     611, 612, 613, 614, 616, 617, 618, 619, 683, 684, 693, 694, 696, 697, 698, 699,
                     701, 702, 703, 704, 711, 712, 718, 719, 783, 784 }) do
    placeholder(i, 56)
end
H.w8(SHOP0, 0x81)
H.invoke(tiny, SYNC, {}, nil)
assert(#H.failed == 0, H.failed[1])
assert(H.r32(basic + 0x18) == 402, "finished in one callback despite the budget")
for _ = 1, 24 do ask_with(tiny, CAN, combo_leaf[0], 1) end
assert(#H.failed == 0, H.failed[1])
assert(H.r32(basic + 0x18) == 598 and H.r32(group[2] + 0x18) == 599, "resume did not finish")
assert(H.r32(health[1] + 0x2C) == 1 and H.r32(health[2] + 0x2C) == 0 and H.r32(health[4] + 0x28) == 20000,
    "resumed rows wrong")
assert(H.r32(stamina[4] + 0x28) == 20000 and H.r32(stamina[1] + 0x2C) == 0, "resumed stamina rows")
assert(H.r32(skill + 0x18) == 614, "resume did not finish the ex store")
assert(text(604) == "Energ\237a 150%.\nBloquear y especiales\ncuestan menos.", "resumed text")    -- still Spanish
-- 18. Stamina +4 plays as 300%: every cost a third on average. The
-- per-frame 3 becomes 1; the others alternate floor and ceiling (10 / 3 =
-- 3, 3, 4 ...) so they average exact
H.w8(SHOP0, 0xA0)
template(0)
local sum = { 0, 0, 0, 0 }
for f = 1, 99 do
    tick(0)
    for i = 1, 4 do sum[i] = sum[i] + H.r32(STAM + (i - 1) * 4) end
end
for i, want in ipairs({ 330, 660, 3300, 99 }) do
    assert(math.abs(sum[i] - want) <= 1, "99 frames of cost " .. i .. " at +4: " .. sum[i])
end
H.w8(SHOP0, 0x88)                              -- +1: 3 * 0.8 = 2.4 a frame
local drained = 0
for f = 1, 100 do tick(0); drained = drained + H.r32(STAM + 12) end
assert(drained >= 239 and drained <= 241, "100 frames at +1 drained " .. drained)

-- 19. Health +3 and +4 add 4 and 8 table steps: 600 -> 1000 -> 1400 solo
vanilla_hp(4, 1)
H.w8(SHOP0, 0x83)
tick(0)
assert(H.r32(MGR + 0x94) == 1000 and select(2, hp(0)) == 1000, "health +3: " .. H.r32(MGR + 0x94))
H.w8(SHOP0, 0x84)
tick(0)
assert(H.r32(MGR + 0x94) == 1400 and select(2, hp(0)) == 1400, "health +4: " .. H.r32(MGR + 0x94))
vanilla_hp(4, 1)                               -- the next map load writes 600 again
tick(0)
assert(H.r32(MGR + 0x94) == 1400, "health +4 not re-applied: " .. H.r32(MGR + 0x94))
H.w8(SHOP0, 0x87)                              -- a stray level 7 reads as 4
tick(0)
assert(#H.failed == 0 and H.r32(MGR + 0x94) == 1400, "level 7: " .. H.r32(MGR + 0x94))

assert(#H.failed == 0, H.failed[1])
print("errors", #H.failed, "first sync writes", first_writes, "max_instr", H.max_instr)
print("xp shop: health, stamina, weapons, EX, fatalities, tick, languages, fallback all pass")
