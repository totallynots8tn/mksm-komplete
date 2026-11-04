-- Shaolin Shuffle 0.12.1 preload rules: a map whose roster has a regular enemy
-- type gets one outsider appended (cap raised so the preload isn't skipped)
-- when the roster plus the outsider fit in 3 memory slots, or in all 4 when
-- the area's freshly loaded spawn groups author no type outside the roster.
-- Otherwise the roster is left as authored (0.11.2's in-place swap crashed
-- map 104). Boss-only and MK-only lists and versus keep the authored
-- roster, which is restored on every visit. 0.12: some outsiders are
-- Mortal Kombat warriors, never in a boss arena, never a type the area's
-- groups author, and only when the groups were freshly loaded.
package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m = H.load(arg[1])
local LOAD_GROUPS, PRELOAD = 0x00014D2C, 0x00015DEE
local STACK, GM = 0xD00F0000, 0x81200000
-- the outsider pool, read from the script
local POOL = {}
local pool_line = assert(io.open(arg[1], "rb")):read("a"):match("local OUTSIDERS%s*=%s*(%b{})")
for id in assert(pool_line, "no OUTSIDERS line"):gmatch("%d+") do POOL[tonumber(id)] = true end
local WARRIORS = {}
local warrior_line = assert(io.open(arg[1], "rb")):read("a"):match("local MK_WARRIORS%s*=%s*(%b{})")
for id in assert(warrior_line, "no MK_WARRIORS line"):gmatch("%d+") do WARRIORS[tonumber(id)] = true end
local warriors_seen, regulars_seen = 0, 0
local function outsider_ok(kind, own)
  if own[kind] then return false end
  if WARRIORS[kind] then warriors_seen = warriors_seen + 1; return true end
  if POOL[kind] then regulars_seen = regulars_seen + 1; return true end
  return false
end
local NONE = 0xFFFFFFFF
H.w32(0x005ACEBC, GM); H.w32(GM + 0x88, 0)

local function desc(addr, cap, list)
  H.w32(addr + 0x20, cap)
  for i = 0, 7 do H.w32(addr + 0x24 + i * 4, list[i + 1] or 0x55555555) end
  return addr
end
local function list(addr) return H.r32(addr + 0x24), H.r32(addr + 0x28), H.r32(addr + 0x2C) end
local function new_area() H.invoke(m, LOAD_GROUPS, { esp = STACK }, nil) end
local function preload(addr) H.w32(STACK + 4, addr); H.invoke(m, PRELOAD, { esp = STACK }, nil) end

-- character table: slots needed per ID (47 and 57 take two)
for id = 0, 90 do H.w32(0x004FA9F0 + id * 0x30 + 4, (id == 47 or id == 57) and 2 or 1) end

local GORO = desc(0x004FD000, 1, { 15, NONE })
local TWO  = desc(0x004FD100, 2, { 14, 26, NONE })
local BOSSY = desc(0x004FD500, 3, { 15, 26, 36, NONE })   -- map 101: three slots already
local WIDE = desc(0x004FD600, 1, { 14, 47, NONE })          -- a two-slot boss: three slots
local FULL = desc(0x004FD700, 4, { 27, 14, 46, 22, NONE })  -- map 6: all four slots
-- spawn group 0 of the manager: count at +0xA68, entry types from +0x18, 0x74 apart
local MANAGER = 0x006DBFB0
local function groups(types)
  H.w16(MANAGER + 0xA68, #types)
  for i, t in ipairs(types) do H.w32(MANAGER + 0x18 + (i - 1) * 0x74, t) end
end
local ONI  = desc(0x004FD200, 3, { 36, NONE })
local SCORP = desc(0x004FD300, 1, { 80, NONE })
local EMPTY = desc(0x004FD400, 3, { NONE })

local seen = {}
for visit = 1, 12 do
  H.w32(0x005CE878, visit * 7919)            -- frame counter feeds the seed
  new_area(); preload(GORO)
  local a, b, c = list(GORO)
  assert(a == 15, "authored type stays first")
  assert(outsider_ok(b, { [15] = true }), "outsider from the pools, not the area's own type: " .. tostring(b))
  assert(c == NONE, "list stays -1 terminated")
  assert(H.r32(GORO + 0x20) == 2, "cap raised to 2 so the preload isn't skipped")
  seen[b] = true
end
local kinds = 0 for _ in pairs(seen) do kinds = kinds + 1 end
assert(kinds >= 3, "outsiders vary between visits (saw " .. kinds .. ")")

-- 0.11: a two-type roster gets a third type from elsewhere
for visit = 1, 6 do
  H.w32(0x005CE878, visit * 104729)
  new_area(); preload(TWO)
  local a, b, c = list(TWO)
  local d = H.r32(TWO + 0x30)
  assert(a == 14 and b == 26, "authored types stay in place")
  assert(outsider_ok(c, { [14] = true, [26] = true }), "outsider from the pools, not one of the area's types: " .. tostring(c))
  assert(d == NONE, "list stays -1 terminated")
  assert(H.r32(TWO + 0x20) == 3, "cap raised to the new list length")
end

-- 0.11.1: three-slot rosters take the fourth slot when their groups author
-- only roster types, and keep it free when a group streams another type in
for _, d in ipairs({ BOSSY, WIDE }) do
  local first, n = H.r32(d + 0x24), (d == BOSSY) and 3 or 2
  groups({ first, first })
  new_area(); preload(d)
  local o = H.r32(d + 0x24 + n * 4)
  assert(POOL[o], "fourth slot outsider when every authored type is listed (never a warrior: the roster has a boss): " .. tostring(o))
  assert(H.r32(d + 0x28 + n * 4) == NONE and H.r32(d + 0x20) == n + 1, "terminated, cap raised")
  groups({ first, 0x16 })                    -- a group authors a type the roster lacks
  new_area(); preload(d)
  assert(H.r32(d + 0x24 + n * 4) == NONE, "no fourth slot when the level streams a type in on the spot")
  groups({ first })
  preload(d)                                 -- no fresh groups since the last preload
  assert(H.r32(d + 0x24 + n * 4) == NONE, "no fourth slot without freshly loaded groups")
end

-- 0.11.3: a roster that can't take one more type keeps every listed type
-- (the scene places characters of them outside the spawn groups)
groups({ 15, 0x16 })
for _, d in ipairs({ BOSSY, WIDE, FULL }) do
  local before = {}
  for i = 0, 5 do before[i] = H.r32(d + 0x24 + i * 4) end
  local cap = H.r32(d + 0x20)
  new_area(); preload(d)
  for i = 0, 5 do assert(H.r32(d + 0x24 + i * 4) == before[i], "listed types are never replaced") end
  assert(H.r32(d + 0x20) == cap, "cap unchanged")
end
groups({})

for _, d in ipairs({ ONI, SCORP, EMPTY }) do
  local before = { list(d) }; local cap = H.r32(d + 0x20); local fourth = H.r32(d + 0x30)
  new_area(); preload(d)
  local after = { list(d) }
  assert(after[1] == before[1] and after[2] == before[2] and after[3] == before[3]
    and H.r32(d + 0x30) == fourth and H.r32(d + 0x20) == cap,
    "four-slot, boss-only and MK-only rosters keep their authored list")
end

-- the two-type map back in versus: its authored list and the word after it return
H.w32(GM + 0x88, 2)
new_area(); preload(TWO)
assert(H.r32(TWO + 0x2C) == NONE and H.r32(TWO + 0x30) == 0x55555555 and H.r32(TWO + 0x20) == 2,
  "versus restores the two-type roster")
H.w32(GM + 0x88, 0)

-- versus: the authored roster comes back, garbage after the terminator included
H.w32(GM + 0x88, 2)
new_area(); preload(GORO)
local a, b, c = list(GORO)
assert(a == 15 and b == NONE and c == 0x55555555 and H.r32(GORO + 0x20) == 1, "versus restores the authored roster")
H.w32(GM + 0x88, 0)
new_area(); preload(GORO)
assert(outsider_ok(select(2, list(GORO)), { [15] = true }), "single player gets an outsider again")

-- 0.12: warriors come in, but never one the area's groups author, and only
-- with freshly loaded groups to check
assert(warriors_seen > 0 and regulars_seen > 0, "both warriors and regular outsiders show up")
local authored_warrior = next(WARRIORS)
groups({ 15, authored_warrior })
for visit = 1, 30 do
  H.w32(0x005CE878, visit * 7907)
  new_area(); preload(GORO)
  local o = select(2, list(GORO))
  assert(o ~= authored_warrior and o ~= 15 and (POOL[o] or WARRIORS[o]), "no warrior the area authors: " .. tostring(o))
end
groups({ 15 })
for visit = 1, 30 do
  H.w32(0x005CE878, visit * 7901)
  preload(GORO)                              -- no fresh groups: nothing to check them against
  assert(POOL[select(2, list(GORO))], "no warrior without freshly loaded groups")
end
groups({})

assert(#H.failed == 0, "script error: " .. tostring(H.failed[1]))
print("max_writes", H.max_writes, "max_instr", H.max_instr)
print("warriors seen:", warriors_seen, "regular outsiders seen:", regulars_seen)
print("PASS shuffle 0.12.1 preload rules")
