package.path = "tests/?.lua;" .. package.path
local H = require("harness")
-- the source runs with the callgate library in front, as build.py ships it
local function with_gate(path, edit)
    local src = assert(io.open("src/callgate_lib.lua", "rb")):read("a") .. assert(io.open(path, "rb")):read("a")
    if edit then src = edit(src) end
    local tmp = os.tmpname()
    assert(io.open(tmp, "wb")):write(src):close()
    local by = H.load(tmp)
    os.remove(tmp)
    return by
end
local m = with_gate(arg[1])

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
-- Team (2 leaves), Fatalities (3 leaves, the first already discovered) and
-- Platform (7 leaves, the story's first two abilities owned)
local next_node = BLOB + 0x100
local function node(kind, name, parent, n)
    local p = next_node
    next_node = next_node + 0x30 + n * 4
    H.w32(p + 4, kind); H.w32(p + 0x0C, n); H.w32(p + 0x10, parent or 0)
    H.w32(p + 0x14, p + 0x30); H.w32(p + 0x18, name); H.w32(p + 0x1C, name + 100)
    return p
end
local function child(parent, i, c) H.w32(parent + 0x30 + i * 4, c) end
local root = node(3, 0, nil, 7)
local basic = node(2, 402, root, 3)
local combos = node(1, 463, root, 2)
local skill = node(1, 464, root, 4)
local team = node(1, 465, root, 2)
local fatal = node(1, 400, root, 3)
local platform = node(1, 462, root, 7)
-- Specials: the X button's group with its four moves (description, video)
local specials = node(2, 461, root, 1)
local xgroup = node(1, 466, specials, 4); child(specials, 0, xgroup)
local move = {}
for j = 1, 4 do
    move[j] = node(0, 1530 + j, xgroup, 0); child(xgroup, j - 1, move[j])
    H.w32(move[j] + 0x1C, 1500 + j); H.w32(move[j] + 0x20, 0x1000 + j); H.w32(move[j] + 0x24, 0)
    H.w32(move[j] + 0x28, ({ 0, 3000, 6500, 10000 })[j]); H.w32(move[j] + 0x2C, j <= 2 and 1 or 0)
    local name = "Special " .. j                      -- the game's own row name
    local at = H.r32(TEXTS + (1530 + j) * 4)
    for c = 1, #name do H.w8(at + c - 1, name:byte(c)) end
    H.w8(at + #name, 0)
end
child(root, 0, basic); child(root, 1, combos); child(root, 2, skill); child(root, 3, team); child(root, 4, fatal)
child(root, 5, specials); child(root, 6, platform)
for slot, level in ipairs({ 4, 3, 4, 5 }) do H.w8(MGR + 0x1C4 + slot - 1, level) end   -- Liu Kang's R2 tiers
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
local up = {}
for k = 1, 4 do
    up[k] = node(0, 1409 + k, skill, 0); child(skill, k - 1, up[k])
    H.w32(up[k] + 0x2C, 1)
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
local arms = {}
for k = 1, 7 do
    arms[k] = node(0, 1395 + k, platform, 0); child(platform, k - 1, arms[k])
    H.w32(arms[k] + 0x1C, 1402 + k); H.w32(arms[k] + 0x2C, k <= 2 and 1 or 0)
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
assert(ask(CAN, health[1], 0) == 0 and ask(CAN, up[1], 0) == 0, "shop active before sync")

-- 1. sync: Basic Moves becomes Upgrades with Health and Stamina (4 rows
-- each), Skill and Team stay vanilla. The strings don't fit in
-- one callback, so the menu's CanPurchase calls resume it.
H.invoke(m, SYNC, {}, nil)
for _ = 1, 4 do ask(CAN, up[1], 0) end
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
-- Running Attacks became Items: the fatality meter's three refills
assert(H.r32(group[3] + 0x18) == 617 and text(617) == "Items", "items group")
assert(text(H.r32(group[3] + 0x1C)) == "Fatality meter refills.", "items group desc")
assert(H.r32(group[3] + 0x0C) == 3, "item rows: " .. H.r32(group[3] + 0x0C))
for j = 1, 3 do
    assert(text(H.r32(rows[3][j] + 0x18)) == "Meter refill +" .. j, "refill row name " .. j)
    assert(H.r32(rows[3][j] + 0x28) == ({ 3000, 5500, 7500 })[j] and H.r32(rows[3][j] + 0x2C) == 0, "refill row price " .. j)
end
assert(text(H.r32(rows[3][1] + 0x1C)) == "Fills 1 more level of\nthe fatality meter.", "refill row desc 1")
assert(text(H.r32(rows[3][3] + 0x1C)) == "Fills 3 more levels of\nthe fatality meter.", "refill row desc 3")
-- Skill became the Fatality meter's upgrades: +1 to +4, none bought yet
assert(H.r32(skill + 0x18) == 1020 and text(1020) == "Fatality meter", "fatality meter category")
assert(text(H.r32(skill + 0x1C)) == "The meter fills faster, lasts longer.", "fatality meter category desc")
for k = 1, 4 do
    assert(text(H.r32(up[k] + 0x18)) == "Meter +" .. k and H.r32(up[k] + 0x28) == 5000 * k
        and H.r32(up[k] + 0x2C) == 0, "meter upgrade row " .. k)
end
assert(text(H.r32(up[1] + 0x1C)) == "Fills at 125% and\nlasts 17% longer." and
    text(H.r32(up[4] + 0x1C)) == "Fills at 300% and\nlasts 67% longer.", "meter upgrade descs: " .. text(H.r32(up[1] + 0x1C)))
-- Platform became Weapons: a row per weapon type, each its own price
assert(H.r32(platform + 0x18) == 1047 and text(1047) == "Weapons", "weapons category")
assert(text(H.r32(platform + 0x1C)) == "Summon a weapon to your side.", "weapons category desc")
for k, name in ipairs({ "Shard", "Short shard", "Sword", "Kamas", "Broadsword", "Hook swords", "Axe" }) do
    assert(text(H.r32(arms[k] + 0x18)) == name and H.r32(arms[k] + 0x28) == 1250 + 250 * k
        and H.r32(arms[k] + 0x2C) == 0, "weapon row " .. k .. ": " .. text(H.r32(arms[k] + 0x18)))
end
assert(text(H.r32(arms[1] + 0x1C)) == "Appears where you buy it.\nThrown, it returns.", "weapon row desc")
-- Specials: X's moves 1 and 2 are owned on R2, none is EX yet: both are on
-- sale again as their EX; move 3 stays as the game has it
assert(H.r32(move[1] + 0x18) == 713 and text(713) == "Special 1 EX", "move 1's EX name: " .. text(713))
assert(H.r32(move[1] + 0x2C) == 0 and H.r32(move[1] + 0x28) == 5000, "move 1's EX not on sale")
assert(text(H.r32(move[2] + 0x18)) == "Special 2 EX" and H.r32(move[2] + 0x2C) == 0
    and H.r32(move[2] + 0x28) == 10000, "move 2's EX not on sale with move 1's")
assert(H.r32(move[3] + 0x18) == 1533 and H.r32(move[3] + 0x2C) == 0 and H.r32(move[3] + 0x28) == 6500,
    "move 3 (not owned on R2) changed")
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
assert(ask(CAN, up[1], 0) == 1 and ask(CAN, up[2], 0) == 0, "meter upgrades not for sale in order")
assert(ask(CAN, move[1], 0) == 1 and ask(0x12B71, move[1], 1) == 0, "move 1's EX not for sale as a combo")
assert(ask(COMBO, move[1], 0) == 1, "move 1's EX not routed as a combo")
assert(ask(CAN, move[3], 1) == 1 and ask(0x12B71, move[3], 1) == 1, "move 3's own purchase changed")
assert(ask(CAN, gear[1], 0) == 0 and ask(COMBO, gear[1], 0) == 0, "team answers changed")
assert(ask(CAN, combo_leaf[0], 1) == 1 and ask(CAN, combo_leaf[1], 0) == 0, "combo answer changed")
assert(ask(COMBO, health[3], 0) == 1 and ask(COMBO, stamina[2], 0) == 1, "shop rows not routed as combos")
assert(ask(COMBO, up[1], 0) == 1, "meter upgrade not routed as a combo")
assert(ask(COMBO, combo_leaf[0], 1) == 1 and ask(COMBO, rows[3][4], 0) == 0, "IsCombo changed elsewhere")
assert(ask(COMBO, rows[3][1], 0) == 1, "meter row not routed as a combo")

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
assert(ask(CAN, fat[2], 0, 0x9CAA7) == 0, "a ??? row drawn buyable (it shows the name)")
assert(m[0x1664A] == nil, "Under hooked")
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

-- 4c. weapons: Platform's rows sell every weapon type, in any area. One lying
-- in the area (a first half with a model, placed at a node or lying as a
-- body) comes over: buying it sets its home to the buyer's feet, refills it
-- and starts the countdown, for both halves of a pair; the row stays for sale
local WPN = 0x5A3AC0
local MAP = 0x505970
local function weapon(i, name, half, body, node, model)
    local w = WPN + 8 + i * 0x27C
    for k = 1, #name do H.w8(w + 0x0C + k - 1, name:byte(k)) end
    H.w8(w + 0x0C + #name, 0)
    H.w8(w + 0x178, half); H.w32(w + 0x124, body); H.w32(w + 0x174, node); H.w32(w + 0x12C, model)
    H.w32(w + 0x268, 1000); H.w32(w + 0x26C, 400); H.w32(w + 0x10C, 0); H.w32(w + 0x230, 0)
    H.w32(w + 8, 0x1000 + i)                                           -- its name hash
    return w
end
local sword = weapon(0, "sword", 0, 0, 0xFFFFFFFF, 0x122)                 -- not in this area
local slot = weapon(1, "weapon_pickup00", 0, 0, 5, 0xFFFFFFFF)            -- no model: never sold
local kama1 = weapon(2, "kama01", 0, 0x81824F00, 0xFFFFFFFF, 0x11A)       -- lying on the floor
local kama2 = weapon(3, "kama02", 1, 0x8182C700, 0xFFFFFFFF, 0x11C)
local axe = weapon(4, "axe", 0, 0, 0xFFFFFFFF, 0x114)                     -- not in this area
H.w32(kama1 + 0x17C, kama2)
local function level_home(w)                     -- where the level put the kamas (the gate)
    H.wf32(w + 0x234, 4518.25); H.wf32(w + 0x238, -5941.75); H.wf32(w + 0x23C, 3748.5)
    H.w8(w + 0x244, 1); H.wf32(w + 0x220, 4400.5)
end
level_home(kama1); level_home(kama2)
H.w32(WPN + 0x56FC, 5)
local POS1 = 0x5D1AB8 + 0x80
H.wf32(POS1, 100); H.wf32(POS1 + 4, -200); H.wf32(POS1 + 8, 300)
local function resync() H.invoke(m, SYNC, {}, nil); for _ = 1, 3 do ask(CAN, combo_leaf[0], 1) end end
resync()
assert(#H.failed == 0, H.failed[1])
local KAMAS, SWORD, AXE = arms[4], arms[3], arms[7]
assert(H.r32(KAMAS + 0x28) == 2250 and H.r32(KAMAS + 0x2C) == 0, "kama row price")
xp(20000)
assert(ask(CAN, KAMAS, 0) == 1 and ask(COMBO, KAMAS, 0) == 1, "kamas not for sale")
assert(ask(CAN, KAMAS, 0, DESCRIPTION) == 1, "weapon description hidden")
assert(ask(CAN, KAMAS, 0, PREVIEW) == 0, "weapon row plays a platform video")
assert(ask(CAN, arms[1], 0) == 0 and ask(CAN, arms[6], 0) == 0, "a type the game has no object for is for sale")
H.w32(kama1 + 0x10C, 0x5D1AB8)
assert(ask(CAN, KAMAS, 0) == 0, "for sale while held")
H.w32(kama1 + 0x10C, 0)
xp(2249)
assert(ask(CAN, KAMAS, 0) == 0, "affordable at 2249")
xp(20000)
H.w8(MGR + 0x1C4 + 15, 0)
buy(KAMAS, 3, true)
assert(#H.failed == 0, H.failed[1])
for _, w in ipairs({ kama1, kama2 }) do
    assert(H.rf32(w + 0x234) == 250 and H.rf32(w + 0x238) == -257 and H.rf32(w + 0x23C) == 300,
        string.format("home %s,%s,%s", H.rf32(w + 0x234), H.rf32(w + 0x238), H.rf32(w + 0x23C)))
    assert(H.r8(w + 0x244) == 1 and H.r32(w + 0x26C) == 1000 and H.r32(w + 0x230) == 1, "summon fields")
end
assert(H.r32(sword + 0x230) == 0 and H.r32(sword + 0x26C) == 400, "sword touched")
assert(H.r32(MGR + 0x4940) == 17750, "weapon XP")
assert(H.r32(KAMAS + 0x2C) == 1, "row not left bought for the jingle")
resync()
assert(H.r32(KAMAS + 0x2C) == 0 and ask(CAN, KAMAS, 0) == 1, "not for sale again after the next menu open")
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
buy(KAMAS, 3, true)
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
buy(KAMAS, 3, true)
H.wf32(kama1 + 0x234, 9999)
H.w32(kama1 + 0x26C, 0)
respawn(kama1)
assert(H.rf32(kama1 + 0x234) == 9999, "stale record applied")
level_home(kama1); level_home(kama2)
H.wf32(POS1, 100)
xp(20000)

-- 4c2. a type the area never placed: the game's own weaponspawn command
-- (exec thunk 0x11C8F, through the call gate on the next unpaused frame)
-- spawns it at the buyer's feet, upright: the command object's matrix
-- pointer [+4] points at the weapon's own home matrix for the call only.
-- One spawn at a time; one that doesn't appear gives its XP back.
local INSTANCE, SINGLETON, VTABLE = 0x589270, 0x5892A8, 0x497C60
local PRE_GATE, POST_GATE, GATE_RET, VANILLA_SLOT = 0x12284, 0x12C93, 0xC753A, 0x13512
local CMD, SPAWN, GATE_ESP = 0x4F34FC, 0x11C8F, 0xD005FC5C
H.w32(INSTANCE, SINGLETON); H.w32(SINGLETON, VTABLE); H.w32(VTABLE + 0x18, VANILLA_SLOT)
H.w32(CMD + 4, 0x81000040)                              -- the last script's context
local spawned = {}                                      -- what weaponspawn saw, call by call
local function gate_frame(appears)                      -- one frame of 0xC74E0's tail
    H.invoke(m, PRE_GATE, { esp = GATE_ESP }, nil)
    local target = H.r32(H.r32(SINGLETON) + 0x18)
    local ctx = { esp = GATE_ESP - 4, ecx = SINGLETON, eax = 0 }
    H.w32(GATE_ESP - 4, GATE_RET)
    H.invoke(m, target, ctx, function(c)
        if target ~= SPAWN then c.esp = c.esp + 4 return end
        local id, spot = H.r32(H.r32(H.r32(c.esp + 4) + 8)), H.r32(c.esp + 12)
        local w = WPN + 8 + (id - 0x1000) * 0x27C
        spawned[#spawned + 1] = { w = w, ecx = c.ecx, up = H.r32(H.r32(c.ecx + 4) + 0x18), x = H.rf32(spot + 4) }
        if appears then H.w32(w + 0x124, 0x81900000 + id) end
        c.eax = 1
        c.esp = c.esp + 4 + 12                          -- ret 0xC
    end)
    assert(ctx.esp == GATE_ESP, string.format("esp off after the gate call: %+d", ctx.esp - GATE_ESP))
    H.invoke(m, POST_GATE, { esp = GATE_ESP - 4 }, nil)
    assert(H.r32(SINGLETON) == VTABLE, "vtable left swapped after the frame")
    assert(#H.failed == 0, H.failed[1])
end
H.w32(MAP, 64); H.w32(0x5CE878, 5000)
assert(ask(CAN, SWORD, 0) == 1, "an unplaced sword not for sale")
buy(SWORD, 3, true)
assert(#H.failed == 0, H.failed[1])
assert(H.r32(MGR + 0x4940) == 18000, "spawned weapon XP")
assert(H.r32(CMD + 4) == sword + 0x1F0 - 0x18 and H.rf32(sword + 0x1F0) == 1 and H.rf32(sword + 0x220) == 250,
    "spawn context not set up")
assert(ask(CAN, AXE, 0) == 0 and ask(CAN, KAMAS, 0) == 1, "a second spawn sold while one is under way")
gate_frame(true)
assert(#spawned == 1 and spawned[1].w == sword and spawned[1].ecx == CMD and spawned[1].up == 0x3F800000
    and spawned[1].x == 250, "weaponspawn call")
assert(H.r32(CMD + 4) == 0x81000040, "command context not put back")
tick(0)                                                 -- the sword lies here now: done
assert(H.r32(MGR + 0x4940) == 18000, "refunded although it appeared")
resync()
assert(ask(CAN, AXE, 0) == 1, "the next spawn not for sale")
-- lying here now, it comes over like any placed weapon: no call
buy(SWORD, 3, true)
gate_frame(true)
assert(#spawned == 1 and H.rf32(sword + 0x234) == 250 and H.r32(sword + 0x230) == 1, "placed sword spawned again")
-- one that never appears (no PME slot or model for it here) gives its XP
-- back ARMS.WAIT frames after its call, and isn't sold again in this area
xp(20000)
buy(AXE, 3, true)
gate_frame(false)
H.w32(0x5CE878, 5299); tick(0)
assert(H.r32(MGR + 0x4940) == 17000, "refunded before the wait was over")
H.w32(0x5CE878, 5301); tick(0)
assert(H.r32(MGR + 0x4940) == 20000, "a spawn that never appeared not refunded")
resync()
assert(ask(CAN, AXE, 0) == 0, "a failed type sold again in this area")
H.w32(MAP, 65)
assert(ask(CAN, AXE, 0) == 1, "a failed type not sold in another area")
-- a call the gate armed but the game never made: its XP comes back at once
buy(AXE, 3, true)
H.invoke(m, PRE_GATE, { esp = GATE_ESP }, nil)
H.invoke(m, POST_GATE, { esp = GATE_ESP - 4 }, nil)
gate_frame(true)                                        -- the next frame reports it
assert(H.r32(MGR + 0x4940) == 20000 and H.r32(CMD + 4) == 0x81000040 and #spawned == 2,
    "a call that never ran not refunded, or the context not put back")
-- a pair the area never placed: both halves are spawned, one call a frame
H.w32(MAP, 64)
H.w32(kama1 + 0x124, 0); H.w32(kama2 + 0x124, 0)
resync()
buy(KAMAS, 3, true)
gate_frame(true); gate_frame(true)
assert(#spawned == 4 and spawned[3].w == kama1 and spawned[4].w == kama2, "pair halves not both spawned")
H.w32(0x5CE878, 5400); tick(0)
assert(H.r32(MGR + 0x4940) == 17750, "spawned pair refunded")
H.w32(kama1 + 0x124, 0x81824F00); H.w32(kama2 + 0x124, 0x8182C700)
H.w32(sword + 0x124, 0)
level_home(kama1); level_home(kama2)
resync()
xp(20000)
-- the "new abilities" popup announces an area's weapons once: while the
-- Moves list opens (the popup is modal inside it) its flag is set and its
-- text is ours; afterwards both are the game's again
local MOVES, FLAG = 0x1425F, 0x4EE890
local POPUP_MSG = "Weapons for sale in\nthe Weapons menu."
local function open_moves()
    local seen = {}
    H.invoke(m, MOVES, {}, function() seen.text = text(407); seen.flag = H.r8(FLAG) end)
    assert(#H.failed == 0, H.failed[1])
    return seen
end
local vanilla407 = text(407)
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

-- 4d. fatality meter fills: the rows after the weapons fill the menu
-- player's meter (f32 at +0x4954 + p * 0x50) by 1 to 3 levels, a level
-- being a third of the HUD meter's bar (entity +0x2B6C -> +0x54 -> +4),
-- within the levels it holds (+0x4978); for sale while that many more can
-- light up, never in fatality mode, and again after the next menu open
local METER0, METER1 = MGR + 0x4954, MGR + 0x49A4
local STATS, HUD = { 0x80600000, 0x80600100 }, { 0x80610000, 0x80611000 }
for p = 0, 1 do
    H.w32(0x5D1AB8 + p * 0x3238 + 0x2B6C, STATS[p + 1]); H.w32(STATS[p + 1] + 0x54, HUD[p + 1])
    H.wf32(HUD[p + 1] + 4, 1200)
end
local LV = 1200 * 0.3333333432674408           -- a level as the game computes it: 400.00001
local fill = { rows[3][1], rows[3][2], rows[3][3] }   -- Items' three rows
H.w32(LEVEL0, 3); H.wf32(METER0, 0)
xp(2999)
assert(ask(CAN, fill[1], 0) == 0, "meter +1 affordable at 2999")
xp(20000)
for j = 1, 3 do
    assert(ask(CAN, fill[j], 0) == 1 and ask(COMBO, fill[j], 0) == 1, "meter +" .. j .. " not for sale")
end
assert(ask(CAN, fill[1], 0, DESCRIPTION) == 1, "meter row description hidden")
assert(ask(CAN, fill[1], 0, PREVIEW) == 0, "meter row plays a running-attack video")
assert(ask(CAN, fill[1], 0, FOR_ANY) == 1, "items group not marked buyable for the meter")
-- +1 from empty: one level, rounded up past the game's unrounded level
buy(fill[1], 2, true)
assert(#H.failed == 0, H.failed[1])
assert(H.r32(METER0) == 0x43C80001 and H.rf32(METER0) >= LV, "meter after +1: " .. H.rf32(METER0))
assert(H.r32(MGR + 0x4940) == 17000, "meter XP")
assert(H.r8(MGR + 0x1C4 + 14) == 0, "combo slot left unlocked by a meter fill")
assert(H.r32(fill[1] + 0x2C) == 1, "row not left bought for the jingle")
assert(H.r32(METER1) == 0 and H.r32(LEVEL0) == 3, "player 2's meter or the levels touched")
-- one level lit, two to go: +3 no longer fits
assert(ask(CAN, fill[2], 0) == 1 and ask(CAN, fill[3], 0) == 0, "room after +1")
resync()
assert(H.r32(fill[1] + 0x2C) == 0 and ask(CAN, fill[1], 0) == 1, "meter +1 not for sale again")
-- a part-filled level is kept: 390 and one level
H.wf32(METER0, 390)
assert(ask(CAN, fill[3], 0) == 1, "+3 not for sale below one level")
buy(fill[1], 2, true)
assert(H.rf32(METER0) >= 390 + LV and H.rf32(METER0) - (390 + LV) < 1e-3, "390 and a level: " .. H.rf32(METER0))
-- one lit and most of another: +2 lights the last two, clamped to the three levels
assert(ask(CAN, fill[2], 0) == 1 and ask(CAN, fill[3], 0) == 0, "room at 1.97 levels")
buy(fill[2], 3, true)
assert(H.r32(METER0) == 0x44960001, "not clamped to three levels: " .. H.rf32(METER0))
for j = 1, 3 do assert(ask(CAN, fill[j], 0) == 0, "for sale with the meter full: +" .. j) end
-- a full level the game itself wrote (exactly 400.0) counts as lit
H.wf32(METER0, 400)
assert(ask(CAN, fill[2], 0) == 1 and ask(CAN, fill[3], 0) == 0, "400.0 not read as one level")
H.wf32(METER0, 399)
assert(ask(CAN, fill[3], 0) == 1, "399 read as one level")
-- the levels held: one (early in the story) sells +1 alone; none, nothing
H.w32(LEVEL0, 1); H.wf32(METER0, 0)
assert(ask(CAN, fill[1], 0) == 1 and ask(CAN, fill[2], 0) == 0, "one level held")
buy(fill[1], 2, true)
assert(H.r32(METER0) == 0x43C80001 and ask(CAN, fill[1], 0) == 0, "one level held: " .. H.rf32(METER0))
H.w32(LEVEL0, 0); H.wf32(METER0, 0)
assert(ask(CAN, fill[1], 0) == 0, "for sale with no level held")
H.w32(LEVEL0, 4)
assert(ask(CAN, fill[1], 0) == 0, "for sale with a level count we don't understand")
H.w32(LEVEL0, 3)
-- fatality mode, as the HUD asks it: the player's record names an entity in
-- one of its character's two mode states (here character 1's second)
local MODES, E0 = 0x80620000, 0x5D1AB8
H.w32(0x58D6A8, MODES); H.w32(MODES + 0x310 + 8, E0)
H.w16(E0 + 0x1DFE, 1); H.w32(0x5999FC + 0x6C, 0x51); H.w32(0x5999FC + 0x6C + 4, 0x52)
H.w32(E0 + 0x23C, 0x52)
assert(ask(CAN, fill[1], 0) == 0, "for sale in fatality mode")
H.w32(E0 + 0x23C, 0x50)
assert(ask(CAN, fill[1], 0) == 1, "not for sale outside fatality mode")
H.w32(E0 + 0x23C, 0); H.w16(E0 + 0x1DFE, 0)
-- without the HUD meter (no bar to measure a level by): nothing sold
H.w32(STATS[1] + 0x54, 0)
assert(ask(CAN, fill[1], 0) == 0, "for sale without the HUD meter")
H.w32(STATS[1] + 0x54, HUD[1])
-- declined: nothing changes
xp(20000)
buy(fill[3], 4, false)
assert(H.r32(METER0) == 0 and H.r32(MGR + 0x4940) == 20000, "declined fill applied")
-- player 2's menu: their own meter, levels and XP
H.w32(0x4EFA60, 1); H.w32(LEVEL1, 3); xp(20000, 1)
buy(fill[3], 4, true)
assert(#H.failed == 0, H.failed[1])
assert(H.r32(METER1) == 0x44960001 and H.r32(METER0) == 0, "player 2's fill: " .. H.rf32(METER1))
assert(H.r32(MGR + 0x4940 + 0x50) == 12500 and H.r32(MGR + 0x4940) == 20000, "player 2's XP")
H.w32(0x4EFA60, 0); H.w32(LEVEL0, 1); H.w32(LEVEL1, 0); H.w32(METER1, 0)
resync()
xp(20000)

-- 4e. Skill's Fatality meter upgrades, bought in order and shared like
-- Health (player 2's shop byte, bits 0-2): AddMeter (thunk 0x16AC8, ecx =
-- the HUD meter, entity and f32 amount on the stack) grows every gain of
-- either player to 125 / 150 / 200 / 300%; a spend (negative) is left alone
do
    local function gain(entity, amount)
        local ctx = { ecx = HUD[1], esp = 0xD0000A00 }
        H.w32(ctx.esp + 4, entity); H.wf32(ctx.esp + 8, amount)
        H.invoke(m, 0x16AC8, ctx, nil)
        assert(#H.failed == 0, H.failed[1])
        return H.rf32(ctx.esp + 8)
    end
    local P1, P2 = 0x5D1AB8, 0x5D1AB8 + 0x3238
    local shop0 = H.r8(SHOP0)
    assert(gain(P1, 20) == 20, "a gain grown before any upgrade")
    xp(5000)
    assert(ask(CAN, up[1], 0) == 1 and ask(CAN, up[2], 0) == 0, "meter upgrades not in order")
    buy(up[1], 1, true)
    assert(#H.failed == 0, H.failed[1])
    assert(H.r8(SHOP1) == 0x81 and H.r8(SHOP0) == shop0 and H.r32(MGR + 0x4940) == 0, "meter upgrade not recorded")
    assert(gain(P1, 20) == 25 and gain(P2, 8) == 10, "gains at +1 not 125%")
    assert(gain(P1, -400) == -400 and gain(P1 + 5 * 0x3238, 20) == 20, "a spend, or an enemy's gain, grown")
    xp(10000)
    assert(ask(CAN, up[2], 0) == 1 and ask(CAN, up[1], 0) == 0, "meter upgrade +2 not next")
    resync()
    assert(H.r32(up[1] + 0x2C) == 1 and H.r32(up[2] + 0x2C) == 0, "meter upgrade owned flags")
    H.w8(SHOP1, 0x84)
    assert(gain(P1, 20) == 60, "gains at +4 not 300%")
    -- and fatality mode lasts longer: its drain (thunk 0x126E4, ecx = a record
    -- at [0x58D6A8] + 0x318 + p * 8) takes one off a record's left per call;
    -- at +4 three fifths of each step stick (3 orbs last like 5), for the two
    -- players' records only, and the mode's own end (0, then 1000) is untouched
    local records = H.r32(0x58D6A8) + 0x318
    local function drain(i, n)
        local rec = records + i * 8
        for _ = 1, n do
            H.invoke(m, 0x126E4, { ecx = rec }, function()
                local left = H.r32(rec + 4) - 1
                H.w32(rec + 4, left < 1 and 1000 or left)   -- the end: back to 1000 for the next time
            end)
        end
        assert(#H.failed == 0, H.failed[1])
        return H.r32(rec + 4)
    end
    for i = 0, 2 do H.w32(records + i * 8 + 4, 1000) end
    local left0, left1 = drain(0, 100), drain(1, 50)
    assert(math.abs(left0 - 940) <= 1 and math.abs(left1 - 970) <= 1, "drain at +4 not 3/5: " .. left0 .. " " .. left1)
    assert(drain(2, 10) == 990, "another record's drain slowed")
    H.w32(records + 4, 1)
    assert(drain(0, 1) == 1000, "the mode's end touched")
    H.w8(SHOP1, 0x81); H.w32(records + 4, 1000)
    local plus1 = drain(0, 70)
    assert(math.abs(plus1 - 940) <= 1, "drain at +1 not 6/7: " .. plus1)
    H.w8(SHOP1, 0x84)
    H.w8(SHOP1, 0x04)
    assert(gain(P1, 20) == 20, "an unmarked byte read as bought")
    H.w8(SHOP1, 0x84); H.w32(MGR + 0x88, 2)
    assert(gain(P1, 20) == 20, "grown in versus")
    H.w32(MGR + 0x88, 0)
    -- player 2's Stamina shares that byte (bits 3-5): each keeps the other's bits
    H.w8(SHOP1, 0x8A)                                   -- Stamina +1, Fatality meter +2
    H.w32(0x4EFA60, 1); xp(15000, 1)
    buy(up[3], 3, true)
    assert(#H.failed == 0, H.failed[1])
    assert(H.r8(SHOP1) == 0x8B and H.r32(MGR + 0x4940 + 0x50) == 0, "player 2's purchase: " .. H.r8(SHOP1))
    H.w32(0x4EFA60, 0)
    H.w8(SHOP1, 0); resync(); xp(20000)
end

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
-- plays no part. (Player 2 opened the menu last: one sync for player 1 first.)
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
assert(ask(CAN, health[1], 0) == 0 and ask(CAN, up[1], 0) == 0, "versus")
H.w32(MGR + 0x88, 0)

-- 13. EX moves: every move owned on R2 is for sale as its EX, in any order
-- (Specials group X Y B -> game slot 0 1 2 -> level slot 19 + it: a bit per
-- move, bit 7 marks the form). While L2 is held, the move system's question
-- (and only it) passes exactly the EX moves, if the stamina covers the cost,
-- which comes off once, when the move spends its own
H.w32(STAM_N, 2)
H.w8(MGR + 0x1C4 + 19, 0)                      -- (X is Specials group 1 -> game slot 0 -> EX byte 19)
xp(10000)
assert(ask(CAN, move[2], 0) == 1, "move 2's EX not for sale before move 1's")
buy(move[2], 1, true)
assert(#H.failed == 0, H.failed[1])
assert(H.r8(MGR + 0x1C4 + 19) == 0x82 and H.r8(MGR + 0x1C4) == 4, "EX bit not set, or the R2 tier touched")
assert(H.r8(MGR + 0x1C4 + 23) == 0, "a purchase wrote the game's slot 23")
assert(H.r32(MGR + 0x4940) == 0, "EX XP")
assert(ask(CAN, move[2], 0) == 0, "move 2's EX for sale twice")
-- the next menu: move 2 shows as its EX, owned; move 1 is still on sale
H.w32(move[2] + 0x2C, 1)                       -- (SyncOwned: owned on R2)
resync()
assert(H.r32(move[2] + 0x2C) == 1 and text(H.r32(move[2] + 0x18)) == "Special 2 EX", "move 2 not shown as EX")
assert(text(H.r32(move[1] + 0x18)) == "Special 1 EX" and H.r32(move[1] + 0x2C) == 0
    and H.r32(move[1] + 0x28) == 5000, "move 1's EX not still on sale")
assert(H.r32(move[3] + 0x18) == 1533, "move 3 renamed before it is owned on R2")
xp(4999)
assert(ask(CAN, move[1], 0) == 0, "move 1's EX affordable at 4999")
xp(5000)
buy(move[1], 1, true)
assert(H.r8(MGR + 0x1C4 + 19) == 0x83, "move 1's EX not added to move 2's")
-- a byte without our mark is not a purchase (a 0.9.0 count, or anything
-- else that ever lands there)
H.w8(MGR + 0x1C4 + 19, 13)
H.w32(move[1] + 0x2C, 1)
resync()
assert(H.r32(move[1] + 0x2C) == 0 and H.r32(move[2] + 0x2C) == 0, "a foreign byte read as EX owned")
xp(10000)
buy(move[1], 1, true)
assert(H.r8(MGR + 0x1C4 + 19) == 0x81, "EX not bought over a foreign byte")
-- 0.11.3 kept the flags in the game's slots 23-25: a marked byte there joins
-- the one in 19-21 and the game's byte is cleared; an unmarked one (the
-- game's own) is left alone, for both players
H.w8(MGR + 0x1C4 + 19, 0x8C); H.w8(MGR + 0x1C4 + 23, 0x83); H.w8(MGR + 0x1C4 + 24, 1)
H.w8(MGR + 0x1C4 + 0x1C + 25, 0x84)
tick(0)
assert(H.r8(MGR + 0x1C4 + 19) == 0x8F and H.r8(MGR + 0x1C4 + 23) == 0, "0.11.3 flags not moved: "
    .. H.r8(MGR + 0x1C4 + 19) .. " " .. H.r8(MGR + 0x1C4 + 23))
assert(H.r8(MGR + 0x1C4 + 24) == 1 and H.r8(MGR + 0x1C4 + 20) == 0, "the game's own byte in 24 touched")
assert(H.r8(MGR + 0x1C4 + 0x1C + 21) == 0x84 and H.r8(MGR + 0x1C4 + 0x1C + 25) == 0, "player 2's flags not moved")
tick(0)
assert(H.r8(MGR + 0x1C4 + 19) == 0x8F, "moved twice")
H.w8(MGR + 0x1C4 + 24, 0); H.w8(MGR + 0x1C4 + 0x1C + 21, 0)
H.w8(MGR + 0x1C4 + 19, 0x8B)                   -- * moves 1, 2 and 4 are EX (R2 owns 1-4)
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
local function cond(player, id, real, from)     -- GetLevel, asked about condition id (in ebp)
    local ctx = { esp = 0xD0000300, eax = real, ebp = id }
    H.w32(ctx.esp, from or EVAL); H.w32(ctx.esp + 4, player); H.w32(ctx.esp + 8, 0)
    H.invoke(m, 0x111C2, ctx, nil)
    assert(#H.failed == 0, H.failed[1])
    return ctx.eax
end
local function level(player, slot, j, real, from)   -- ... about move j of a slot
    return cond(player, 0x3174 + slot * 5 + j - 1, real, from)
end
local function slot_level(player, flags, from, real)   -- SlotLevel, asked by the move filter
    local ctx = { esp = 0xD0000600, eax = real }
    H.w32(ctx.esp, from); H.w32(ctx.esp + 4, player); H.w32(ctx.esp + 8, flags)
    H.invoke(m, 0x12FD1, ctx, nil)
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
-- L2 + X (* has EX moves): the game sees R2 + X, and only the EX moves pass
local lt, rt = pad(0, { [LT] = 0xFF, [X] = 0xFF })
assert(lt == 0 and rt == 0xFF, "L2 + X not turned into R2 + X")
assert(level(0, 0, 1, 4) == 1 and level(0, 0, 4, 4) == 4 and stam() == 100,
    "EX move not picked, or charged at the pick")
assert(level(0, 0, 3, 4) == 0, "move 3 (no EX) picked on L2")
assert(level(0, 0, 4, 2) == 0, "the EX of a move not owned on R2 picked")
assert(cond(0, 0x3183, 3) == 3 and cond(0, 0x25B0, 1) == 1, "another condition touched")
-- the move filter's tier checks (one call site each) get the same answers
local X_MOVE = 0x10000000 | 0x0005               -- slot 0's flag (+ unrelated low bits)
assert(slot_level(0, X_MOVE, 0x77B3A, 4) == 1 and slot_level(0, X_MOVE, 0x77BC7, 4) == 4,
    "an EX move filtered out on L2")
assert(slot_level(0, X_MOVE, 0x77B98, 4) == 0, "move 3 (no EX) let through the move filter")
assert(slot_level(0, X_MOVE, 0x77B69, 1) == 0, "the EX of a move not owned on R2 let through")
assert(slot_level(0, X_MOVE, 0x77B0C, 4) == 4, "the special itself filtered out")
assert(slot_level(0, 0x40000000, 0x77B3A, 4) == 0, "B (no EX) let through during an X chain")
assert(slot_level(0, 0x80000000, 0x77B98, 4) == 4 and slot_level(0, X_MOVE, 0x7AB00, 4) == 4,
    "slot 3 or another caller touched")
spend(0)
assert(stam() == 50, "EX stamina not charged: " .. stam())
spend(0)
assert(stam() == 50, "charged twice for one move")
assert(level(0, 0, 3, 4) == 0, "a follow-up after the charge escaped the EX moves")
-- still holding X: the press stays R2, but it isn't a new EX
H.w32(0x5CE878, 1010)
lt, rt = pad(0, { [LT] = 0xFF, [X] = 0xFF })
assert(rt == 0xFF, "held EX press lost its R2")
spend(0)
assert(stam() == 50, "a held press charged again")
-- X released, L2 still held: the chain keeps R2 (not block), so R2 + X, X, X
-- goes through; the next X press is a new EX
lt, rt = pad(0, { [LT] = 0xFF })
assert(lt == 0 and rt == 0xFF, "EX chain dropped R2 between presses")
H.wf32(NOW0, 100)
H.w32(0x5CE878, 1020)
lt, rt = pad(0, { [LT] = 0xFF, [X] = 0xFF })
assert(rt == 0xFF, "second press of the chain lost R2")
spend(0)
assert(stam() == 50, "second EX press of the chain not charged: " .. stam())
-- out of stamina mid-chain: the press still goes through as R2, uncharged
pad(0, { [LT] = 0xFF }); H.wf32(NOW0, 10)
lt, rt = pad(0, { [LT] = 0xFF, [X] = 0xFF })
assert(rt == 0xFF, "chain broken by a press without the stamina")
spend(0)
assert(stam() == 10, "charged without the stamina")
H.wf32(NOW0, 75)
pad(0, {})                                     -- L2 let go: the chain is over
-- untouched: L2 + an unbought button (B, slot 2), L2 + R2, a brushed
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
assert(level(0, 0, 3, 2) == 2, "a plain special changed")
assert(slot_level(0, 0x10000000, 0x77B98, 4) == 4, "the move filter changed without L2")
H.w8(MGR + 0x1C4 + 20, 0x8F)                   -- Y is slot 1: moves 1-4 are EX
pad(0, { [LT] = 0xFF, [Y] = 0xFF })
assert(level(0, 1, 3, 1, 0x9D650) == 1, "answered for the menu")
assert(level(0, 1, 1, 1) == 1 and level(0, 1, 2, 1) == 0, "~ EX not limited to the moves owned on R2")
assert(level(0, 1, 4, 4) == 4, "~ EX move 4 not picked")
H.w8(MGR + 0x1C4 + 20, 0x82)                   -- EX ~ move 2 alone
pad(0, {}); pad(0, { [LT] = 0xFF, [Y] = 0xFF })
assert(level(0, 1, 2, 4) == 2 and level(0, 1, 1, 4) == 0, "EX ~ move 2 alone: not exactly it")
H.w8(MGR + 0x1C4 + 20, 0x8F)
spend(0)
assert(stam() == 50, "EX on ~ not charged: " .. stam())
-- a press whose move never spends: its extra expires
pad(0, {}); H.wf32(NOW0, 100)
pad(0, { [LT] = 0xFF, [Y] = 0xFF })
H.w32(0x5CE878, 2100)
spend(0)
assert(stam() == 100, "an expired EX charged")
pad(0, {})
-- Stamina +2 (150%): the extra is scaled too
H.w8(SHOP0, 0x91)
pad(0, { [LT] = 0xFF, [X] = 0xFF })
spend(0)
assert(math.abs(stam() - (100 - 50 / 1.5)) < 1e-3, "scaled EX cost: " .. stam())
pad(0, {})
H.w8(SHOP0, 0x81)
-- player 2 (Kung Lao, port 1): his own flags (moves 1-3 are EX) and stamina
H.w32(MGR + 0xCC + 4, 1); H.w8(MGR + 0x1C4 + 0x1C + 20, 0x87); H.wf32(NOW0 + 0x24, 100)
lt, rt = pad(1, { [LT] = 0xFF, [Y] = 0xFF })
assert(rt == 0xFF and level(1, 1, 3, 3) == 3 and level(1, 1, 4, 3) == 0, "KL ~ EX not his moves 1-3")
spend(1)
assert(stam(1) == 60, "player 2's charge (Stamina +1: 40): " .. stam(1))
pad(1, {})
H.w32(MGR + 0xCC + 4, 0); H.w8(MGR + 0x1C4 + 0x1C + 20, 0)
-- 14. EX power: a paid press makes the move EX. Its hits on others do 5x
-- (no impact pause: 0.12.0 took 0.11.3's out again), a fireball landing soon
-- after too; once the move's last event has played, it recovers at 3 frames
-- a tick
local E0 = 0x5D1AB8
local BANK, LISTS, LENGTHS, DATA, EV = 0x6C03E0, 0x710000, 0x711000, 0x712000, 0x713000
local ANIM = 0x21
H.w32(BANK, 0x40); H.w32(BANK + 4, LENGTHS); H.w32(BANK + 8, DATA); H.w32(BANK + 0xC, LISTS)
H.w32(LISTS + ANIM * 4, EV); H.w32(DATA + ANIM * 4, 0x714000)
H.w16(EV, 5); H.w16(EV + 2, 7)                 -- events on frames 5 and 12, then the end
H.w16(EV + 16, 12); H.w16(EV + 18, 9)
H.w16(EV + 32, 0xFFFF); H.w16(EV + 34, 0)
H.w32(0x6CA6C0 + ANIM * 4, 3); H.w32(LENGTHS + 3 * 16 + 8, 30)   -- 30 frames long
local function anim_tick() H.invoke(m, 0x1C4A60, {}, nil); assert(#H.failed == 0, H.failed[1]) end
local function hit(entity, damage)
    local ctx = { esp = 0xD0000700 }
    H.w32(ctx.esp + 4, entity); H.w32(ctx.esp + 8, 0xA4); H.w32(ctx.esp + 0xC, (-damage) & 0xFFFFFFFF)
    local actor = 0x80500000
    local dealt = { ecx = actor, esp = ctx.esp + 0x100 }
    H.w32(actor + 0xBC, entity); H.w32(dealt.esp + 4, damage)
    H.invoke(m, 0x180D30, ctx, function()
        H.invoke(m, 0x153E20, dealt, nil)
    end)
    assert(#H.failed == 0, H.failed[1])
    return H.r32(dealt.esp + 4)
end
local ENEMY = E0 + 5 * 0x3238
H.w32(0x5CE878, 3000); H.wf32(NOW0, 100); pad(0, {})
assert(hit(ENEMY, 40) == 40 and H.r32(0x6CD5C8) == 0, "a plain hit boosted")
pad(0, { [LT] = 0xFF, [X] = 0xFF })            -- a paid EX press at frame 3000
H.w32(E0 + 0x1E04, 6); H.w32(E0 + 0x24, ANIM); H.w32(E0 + 0x1C, 4); H.w8(E0 + 0x263A, 0)
anim_tick()
assert(H.r8(E0 + 0x263A) == 0, "EX sped up before its hits")
assert(hit(ENEMY, 40) == 200 and H.r32(0x6CD5C8) == 0, "EX hit not 5x, or an impact pause")
assert(hit(E0, 40) == 40 and hit(E0 + 0x3238, 40) == 40, "a hit on a player boosted")
H.w32(E0 + 0x1C, 12); anim_tick()
assert(H.r8(E0 + 0x263A) == 0, "sped up on its last event's frame")
H.w32(E0 + 0x1C, 13); anim_tick()
assert(H.r8(E0 + 0x263A) == 48, "EX recovery not 3x")
-- damage that reaches TakeDamage without message 164 while the EX move
-- plays: the move's in single player, not in co-op (the other player's)
local function dealt(entity, damage)
    local ctx = { ecx = 0x80500000, esp = 0xD0000900 }
    H.w32(ctx.ecx + 0xBC, entity); H.w32(ctx.esp + 4, damage)
    H.invoke(m, 0x153E20, ctx, nil)
    assert(#H.failed == 0, H.failed[1])
    return H.r32(ctx.esp + 4)
end
assert(dealt(ENEMY, 30) == 150 and dealt(E0, 30) == 30, "solo: damage during the EX move")
H.w32(MGR + 0x88, 1)
assert(dealt(ENEMY, 30) == 30, "co-op: damage without message 164 boosted")
H.w32(MGR + 0x88, 0)
assert(dealt(ENEMY, 0xFFFFFF00) == 0xFFFFFF00, "a value that isn't a hit's damage boosted")
H.w32(0x5CE878, 3010); anim_tick()
assert(H.r32(0x6CD5C8) == 0, "slow motion written")
H.w32(E0 + 0x1E04, 0); anim_tick()                  -- the move is over
H.w32(0x5CE878, 3080)
assert(hit(ENEMY, 40) == 200, "a late EX hit (a fireball) not boosted")
H.w32(0x5CE878, 3100); anim_tick()
assert(H.r32(0x6CD5C8) == 0 and hit(ENEMY, 40) == 40, "a hit long after the EX boosted")
assert(dealt(ENEMY, 30) == 30, "solo: damage after the EX move boosted")
pad(0, {})                                     -- a plain move is never sped up
H.w32(E0 + 0x1E04, 6); H.w32(E0 + 0x24, ANIM + 1); H.w32(E0 + 0x1C, 20); H.w8(E0 + 0x263A, 0)
anim_tick()
assert(H.r8(E0 + 0x263A) == 0, "a plain move sped up")
H.w32(E0 + 0x1E04, 0); anim_tick()

-- EX cancels. L2 + Y during an L2 + X EX move: the game sees Y released
-- until the X move's last event (frame 12) has played; then the move ends
-- (frame 0x7FFF) and Y comes back as R2 + Y, a paid EX of its own, held for
-- two frames. The same button again (X, X, X) is the chain: untouched.
H.w8(MGR + 0x1C4 + 20, 0x8F)                   -- Y's moves 1-4 have EX too
H.wf32(NOW0, 100); pad(0, {})
local function frame(f) H.w32(0x5CE878, f) end
local function in_move(anim, at) H.w32(E0 + 0x1E04, 6); H.w32(E0 + 0x24, anim); H.w32(E0 + 0x1C, at) end
local Y_PAD = PAD + Y
frame(4000); pad(0, { [LT] = 0xFF, [X] = 0xFF })        -- the X EX
in_move(ANIM, 2); H.w8(E0 + 0x263A, 0); anim_tick()
frame(4001); lt, rt = pad(0, { [LT] = 0xFF })            -- X let go, L2 held
frame(4002); lt, rt = pad(0, { [LT] = 0xFF, [X] = 0xFF })
assert(H.r8(PAD + X) == 0xFF and rt == 0xFF, "the chain's own button (X again) held back")
frame(4003); pad(0, { [LT] = 0xFF })
frame(4004); lt, rt = pad(0, { [LT] = 0xFF, [Y] = 0xFF })   -- Y: a cancel
assert(H.r8(Y_PAD) == 0 and rt == 0xFF, "the cancel press reached the game mid-move")
in_move(ANIM, 6); anim_tick()
assert(H.r32(E0 + 0x1C) == 6, "move ended before its last event")
frame(4005); pad(0, {})                                   -- a tap: Y already let go
assert(H.r8(Y_PAD) == 0, "cancel press shown before the move ended")
in_move(ANIM, 13); anim_tick()                            -- past the last event (12)
assert(H.r32(E0 + 0x1C) == 0x7FFF and H.r8(E0 + 0x263A) == 0, "EX move not ended for the cancel")
H.w32(E0 + 0x1E04, 0); H.w32(E0 + 0x24, 0); anim_tick()
frame(4006); lt, rt = pad(0, {})
assert(H.r8(Y_PAD) == 0xFF and lt == 0 and rt == 0xFF, "cancel press not played back as R2 + Y")
frame(4007); lt, rt = pad(0, {})
assert(H.r8(Y_PAD) == 0xFF and rt == 0xFF, "played-back press not held its second frame")
frame(4008); lt, rt = pad(0, {})
assert(H.r8(Y_PAD) == 0 and rt == 0, "played-back press stuck")
H.wf32(NOW0, 100); spend(0)
assert(stam() == 50, "the cancel's EX not charged: " .. stam())
in_move(ANIM + 2, 1); anim_tick()                         -- the Y move starts: an EX
assert(hit(ENEMY, 40) == 200, "the cancel's move not an EX")
H.w32(E0 + 0x1E04, 0); anim_tick()
-- a cancel press whose move never reaches its last event is let go
frame(4100); pad(0, {}); pad(0, { [LT] = 0xFF, [X] = 0xFF })
in_move(ANIM, 2); anim_tick()
frame(4101); pad(0, { [LT] = 0xFF, [X] = 0xFF, [Y] = 0xFF })
assert(H.r8(Y_PAD) == 0, "second cancel not held back")
frame(4101 + 46); in_move(ANIM, 3); anim_tick()
frame(4101 + 47); pad(0, { [LT] = 0xFF, [X] = 0xFF, [Y] = 0xFF })
assert(H.r8(Y_PAD) == 0xFF, "an expired cancel still holds the button")
-- the move cut short (hit) while a cancel waits: the press plays at once
H.w32(E0 + 0x1E04, 0); anim_tick(); pad(0, {})
frame(4200); pad(0, { [LT] = 0xFF, [X] = 0xFF })
in_move(ANIM, 2); anim_tick()
frame(4201); pad(0, { [LT] = 0xFF, [X] = 0xFF, [Y] = 0xFF })
H.w32(E0 + 0x1E04, 9); anim_tick()                        -- knocked out of the move
frame(4202); pad(0, { [LT] = 0xFF, [X] = 0xFF, [Y] = 0xFF })
assert(H.r8(Y_PAD) == 0xFF, "cancel lost when its move was cut short")
-- no cancel without the stamina for it, nor in an anim whose events can't be read
frame(4300); H.w32(E0 + 0x1E04, 0); anim_tick(); pad(0, {}); pad(0, {})
H.wf32(NOW0, 100); pad(0, { [LT] = 0xFF, [X] = 0xFF })
in_move(ANIM, 2); anim_tick(); H.wf32(NOW0, 10)
frame(4301); pad(0, { [LT] = 0xFF, [X] = 0xFF, [Y] = 0xFF })
assert(H.r8(Y_PAD) == 0xFF, "cancel held back without the stamina")
H.w32(E0 + 0x1E04, 0); anim_tick(); pad(0, {}); H.wf32(NOW0, 100)
H.w32(LISTS + 0x30 * 4, 0)                                -- anim 0x30: no event list
frame(4400); pad(0, { [LT] = 0xFF, [X] = 0xFF })
in_move(0x30, 2); anim_tick()
frame(4401); pad(0, { [LT] = 0xFF, [X] = 0xFF, [Y] = 0xFF })
assert(H.r8(Y_PAD) == 0xFF, "cancel held back in an anim whose last event is unknown")
H.w32(E0 + 0x1E04, 0); anim_tick(); pad(0, {})
H.w8(MGR + 0x1C4 + 19, 0); H.w8(MGR + 0x1C4 + 20, 0)

-- 15. Spanish (the game's own placeholders: 54-62 bytes): strings in cp1252
local es = with_gate(arg[1])
local function put(i, s)
    local p = H.r32(TEXTS + i * 4)
    for k = 1, #s do H.w8(p + k - 1, s:byte(k)) end
    H.w8(p + #s, 0)
end
put(455, "Mejorar")
for _, i in ipairs({ 574, 598 }) do placeholder(i, 62) end
for _, i in ipairs({ 581, 582, 583, 584, 593, 594, 599, 601, 602, 603, 604, 611, 612, 613,
                     614, 616, 617, 618, 619, 683, 684, 693, 694, 696, 697, 698, 699,
                     701, 702, 703, 704, 711, 712, 718, 719, 783, 784, 816, 817, 818, 819,
                     794, 801, 985, 986, 996, 1020, 1021, 1047, 1051 }) do
    placeholder(i, 56)
end
for _, i in ipairs({ 596, 597 }) do placeholder(i, 54) end
H.invoke(es, SYNC, {}, nil)
for _ = 1, 6 do ask_with(es, CAN, up[1], 0) end
assert(#H.failed == 0, H.failed[1])
assert(text(598) == "Mejoras" and text(574) == "Salud" and text(599) == "Energ\237a", "spanish names")
assert(text(597) == "Vida m\225xima +800,\nadem\225s de la del juego.", "spanish desc: " .. text(597))
assert(text(784) == "Energ\237a 300%.\nBloquear y especiales\ncuestan menos.", "spanish stamina desc")
assert(text(718) == "Energ\237a +3", "spanish stamina row 3")
assert(H.r32(skill + 0x18) == 1020 and H.r32(team + 0x18) == 465, "spanish tree")
assert(text(616) == "Compra la secuencia de\nun ??? con EXP.", "spanish fatalities hint")
assert(text(617) == "Objetos" and text(683) == "Recargas del medidor de Fatality.", "spanish items")
assert(text(698) == "Armas a la venta en\nel men\250 Armas.", "spanish popup")
assert(text(816) == "Recarga de medidor +1" and text(818) == "Recarga de medidor +3", "spanish refill rows")
assert(text(1020) == "Medidor de Fatality" and text(704) == "Medidor +1"
    and text(985) == "Se llena al 125% y\ndura un 17% m\225s.", "spanish meter upgrades: " .. text(985))
assert(text(1047) == "Armas" and text(684) == "Fragmento" and text(693) == "Fragmento corto"
    and text(703) == "Hacha", "spanish weapons")
assert(text(618) == "Llena 1 nivel m\225s del\nmedidor de Fatality."
    and text(619) == "Llena 2 niveles m\225s del\nmedidor de Fatality.", "spanish meter descs: " .. text(619))

-- 16. the text table reloads with placeholders too short: every field is put back
local vanilla = { [basic + 0x18] = 402, [group[1] + 0x18] = 403, [group[2] + 0x18] = 404,
                  [group[2] + 0x0C] = 4, [health[1] + 0x18] = 485, [health[1] + 0x1C] = 585,
                  [health[1] + 0x28] = 0, [health[1] + 0x2C] = 1, [stamina[2] + 0x18] = 490,
                  [stamina[4] + 0x28] = 0, [skill + 0x18] = 464, [up[1] + 0x18] = 1410,
                  [fat[3] + 0x28] = 0, [fatal + 0x1C] = 500,
                  [group[3] + 0x18] = 405, [group[3] + 0x0C] = 4, [rows[3][1] + 0x18] = 493,
                  [skill + 0x1C] = 564, [up[2] + 0x2C] = 1, [up[3] + 0x28] = 0,
                  [platform + 0x18] = 462, [arms[3] + 0x18] = 1398, [arms[3] + 0x28] = 0, [arms[1] + 0x2C] = 1 }
-- (the first instance holds the vanilla values; a second one would only
-- ever see a fresh tree in the game)
for _, i in ipairs({ 582, 584, 594, 597, 784 }) do placeholder(i, 20) end
H.invoke(m, SYNC, {}, nil)
for addr, v in pairs(vanilla) do
    assert(H.r32(addr) == v, string.format("not restored at %X: %d", addr, H.r32(addr)))
end
assert(ask(CAN, health[1], 0) == 0 and ask(CAN, up[1], 0) == 0, "shop still answering")

-- 17. a write budget too small for one callback: the sync finishes over the
-- CanPurchase calls the menu makes while it draws
local src = assert(io.open(arg[1], "rb")):read("a")    -- (with_gate puts the library in front)
local small, n = src:gsub("local BUDGET        = 200", "local BUDGET        = 40")
assert(n == 1, "BUDGET line not found")
local tmp = os.tmpname()
assert(io.open(tmp, "wb")):write(small):close()
local tiny = with_gate(tmp)
os.remove(tmp)
for _, i in ipairs({ 574, 598, 581, 582, 583, 584, 593, 594, 596, 597, 599, 601, 602, 603, 604,
                     611, 612, 613, 614, 616, 617, 618, 619, 683, 684, 693, 694, 696, 697, 698, 699,
                     701, 702, 703, 704, 711, 712, 718, 719, 783, 784, 816, 817, 818, 819,
                     794, 801, 985, 986, 996, 1020, 1021, 1047, 1051 }) do
    placeholder(i, 56)
end
H.w8(SHOP0, 0x81)
H.invoke(tiny, SYNC, {}, nil)
assert(#H.failed == 0, H.failed[1])
assert(H.r32(basic + 0x18) == 402, "finished in one callback despite the budget")
for _ = 1, 48 do ask_with(tiny, CAN, combo_leaf[0], 1) end
assert(#H.failed == 0, H.failed[1])
assert(H.r32(basic + 0x18) == 598 and H.r32(group[2] + 0x18) == 599, "resume did not finish")
assert(H.r32(health[1] + 0x2C) == 1 and H.r32(health[2] + 0x2C) == 0 and H.r32(health[4] + 0x28) == 20000,
    "resumed rows wrong")
assert(H.r32(stamina[4] + 0x28) == 20000 and H.r32(stamina[1] + 0x2C) == 0, "resumed stamina rows")
assert(H.r32(skill + 0x18) == 1020 and H.r32(platform + 0x18) == 1047, "resumed sync left Skill or Platform")
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

-- 20. every built-in language fits the game's own placeholders, at their
-- real byte lengths in its text table (one that didn't would leave the whole
-- shop vanilla in that language). Lengths: English, Spanish, German, Italian,
-- French; the placeholders sharing a length share a row.
do
    local A, B, C, D = { 45, 54, 53, 52, 57 }, { 50, 62, 57, 60, 67 }, { 47, 56, 55, 54, 59 }, { 46, 55, 54, 53, 58 }
    local E, F, G, I = { 52, 60, 57, 58, 65 }, { 47, 55, 52, 53, 60 }, { 50, 59, 58, 57, 62 }, { 49, 57, 54, 55, 62 }
    local J = { 50, 58, 55, 56, 63 }
    local K, L, N, O, Q = { 49, 56, 55, 54, 62 }, { 48, 56, 53, 54, 61 }, { 46, 53, 52, 51, 59 },
        { 46, 54, 51, 52, 59 }, { 52, 64, 58, 60, 69 }
    local caps = { [598] = A, [611] = A, [612] = A, [596] = A, [597] = A, [599] = A, [613] = A, [574] = B,
                   [581] = C, [582] = C, [583] = C, [584] = C, [593] = C, [594] = C,
                   [601] = D, [602] = D, [603] = D, [604] = D, [718] = E, [719] = E,
                   [783] = F, [784] = F, [696] = F, [697] = F, [698] = F,
                   [616] = G, [617] = G, [618] = G, [619] = G, [683] = I, [684] = I, [693] = I, [694] = I,
                   [816] = J, [817] = J, [818] = J, [819] = J, [1020] = K, [1021] = K,
                   [701] = L, [702] = L, [703] = L, [704] = L, [711] = F, [712] = F, [794] = F,
                   [985] = N, [986] = N, [996] = N, [801] = O, [1047] = Q, [1051] = Q }
    local langs = { { "Upgrade", "Upgrades", "Meter refill +3", "Fatality meter", "Axe" },
                    { "Mejorar", "Mejoras", "Recarga de medidor +3", "Medidor de Fatality", "Hacha" },
                    { "Verbessern", "Verbesserungen", "Anzeige auff\252llen +3", "Fatality-Anzeige", "Axt" },
                    { "Potenzia", "Potenziamenti", "Ricarica barra +3", "Barra fatality", "Ascia" },
                    { "Am\233liorer", "Am\233liorations", "Recharge de jauge +3", "Jauge de fatality", "Hache" } }
    for l, want in ipairs(langs) do
        local shop = with_gate(arg[1])
        put(455, want[1])
        for i, len in pairs(caps) do                 -- (128-byte slots: the longest is 67)
            local p = 0x80240000 + i * 128
            for k = 0, len[l] - 1 do H.w8(p + k, 0x58) end
            H.w8(p + len[l], 0)
            H.w32(TEXTS + i * 4, p)
        end
        H.invoke(shop, SYNC, {}, nil)
        for _ = 1, 10 do ask_with(shop, CAN, combo_leaf[0], 1) end
        assert(#H.failed == 0, H.failed[1])
        assert(H.r32(basic + 0x18) == 598 and text(598) == want[2], want[2] .. " doesn't fit: " .. text(598))
        assert(H.r32(group[3] + 0x18) == 617 and text(818) == want[3], want[2] .. " refill rows: " .. text(818))
        assert(text(1020) == want[4] and text(703) == want[5], want[2] .. " Skill or Platform: " .. text(1020))
    end
end

assert(#H.failed == 0, H.failed[1])
print("errors", #H.failed, "first sync writes", first_writes, "max_instr", H.max_instr)
print("xp shop: health, stamina, weapons, EX, fatalities, tick, languages, fallback all pass")
