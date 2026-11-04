-- Shaolin Shuffle 0.13.0 swaps: a full roster on a map that loaded live with
-- the swap (SWAPS) trades its listed type for an outsider in place (the list
-- keeps its length and cap), and every spawn entry of that type, disabled
-- groups included, becomes the outsider at the preload. No swap when one of
-- those entries isn't plain, when the map isn't in SWAPS, or when the roster
-- still has room (the outsider is appended as before). A re-preload keeps the
-- swap without converting again; a cutscene evicting the outsider puts the
-- entries back and the next preload restores the authored roster.
--   lua tests/shuffle_swap.lua ../randomizer/pack/scripts/randomizer.lua
package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m = H.load(arg[1])
local LOAD_GROUPS, PRELOAD, SPAWN_TICK = 0x00014D2C, 0x00015DEE, 0x001D23F0
local STACK, GM, NONE = 0xD00F0000, 0x81200000, 0xFFFFFFFF
local MANAGER, LOADED = 0x006DBFB0, 0x006CA69C
local POOL = {}
local pool_line = assert(io.open(arg[1], "rb")):read("a"):match("local OUTSIDERS%s*=%s*(%b{})")
for id in assert(pool_line, "no OUTSIDERS line"):gmatch("%d+") do POOL[tonumber(id)] = true end
H.w32(0x005ACEBC, GM); H.w32(GM + 0x88, 0)
for id = 0, 90 do H.w32(0x004FA9F0 + id * 0x30 + 4, (id == 47 or id == 57) and 2 or 1) end

local function desc(addr, cap, list)
  H.w32(addr + 0x20, cap)
  for i = 0, 7 do H.w32(addr + 0x24 + i * 4, list[i + 1] or 0x55555555) end
  return addr
end
local function listed(d) local t = {} for i = 0, 4 do t[i + 1] = H.r32(d + 0x24 + i * 4) end return t end
local function new_area() H.invoke(m, LOAD_GROUPS, { esp = STACK }, nil) end
local function preload(d) H.w32(STACK + 4, d); H.invoke(m, PRELOAD, { esp = STACK }, nil) end
local function entry(g, s) return MANAGER + g * 0xA6C + 0x18 + s * 0x74 end
-- groups: { { enabled, { type, plain }... }... }; plain entries have no flag, state -1 and mover -1
local function groups(list)
  for g = 0, 2 do H.w16(MANAGER + g * 0xA6C + 0xA68, 0) end
  for g, spec in ipairs(list) do
    local base = MANAGER + (g - 1) * 0xA6C
    H.w16(base + 0xA68, #spec - 1); H.w8(base + 0xA6A, spec[1] and 1 or 0)
    for s = 2, #spec do
      local e = entry(g - 1, s - 2)
      H.w32(e, spec[s][1]); H.w8(e + 0x58, spec[s][2] and 0 or 1)
      H.w32(e + 0x5C, NONE); H.w32(e + 0x10, NONE)
    end
  end
end

-- map 74, the Pit II: four types, all four slots (SWAPS: its captains, 10)
local PIT = desc(0x004FE990, 4, { 10, 11, 13, 39, NONE })
groups({ { true, { 10, true }, { 11, true }, { 10, true } }, { false, { 10, true }, { 13, true } } })
local outsiders = {}
for visit = 1, 8 do
  H.w32(0x005CE878, visit * 7919)
  groups({ { true, { 10, true }, { 11, true }, { 10, true } }, { false, { 10, true }, { 13, true } } })
  new_area(); preload(PIT)
  local l = listed(PIT)
  local o = l[1]
  assert(POOL[o] and o ~= 10 and o ~= 11 and o ~= 13, "the captains' place goes to an outsider: " .. tostring(o))
  assert(l[2] == 11 and l[3] == 13 and l[4] == 39 and l[5] == NONE, "the other types stay, the list keeps its length")
  assert(H.r32(PIT + 0x20) == 4, "the cap is unchanged")
  assert(H.r32(entry(0, 0)) == o and H.r32(entry(0, 2)) == o and H.r32(entry(1, 0)) == o,
    "every captain entry is the outsider, the disabled group's too")
  assert(H.r32(entry(0, 1)) == 11 and H.r32(entry(1, 1)) == 13, "other types' entries untouched")
  outsiders[o] = true
end
local n = 0 for _ in pairs(outsiders) do n = n + 1 end
assert(n >= 3, "the outsider varies between visits (saw " .. n .. ")")

-- a re-preload in the same area (after a cutscene) keeps the swap, no new conversion
local o = H.r32(PIT + 0x24)
preload(PIT)
assert(H.r32(PIT + 0x24) == o and H.r32(entry(0, 0)) == o, "a re-preload keeps the swap")

-- a cutscene evicts the outsider: its entries go back to captains, then the
-- re-preload restores the authored roster
for i = 0, 5 do H.w32(LOADED + i * 4, ({ 0, 1, 11, 13, 39, NONE })[i + 1]) end
H.invoke(m, SPAWN_TICK, { ecx = MANAGER, esp = STACK }, nil)
assert(H.r32(entry(0, 0)) == 10 and H.r32(entry(0, 2)) == 10 and H.r32(entry(1, 0)) == 10, "the captains come back")
preload(PIT)
local l = listed(PIT)
assert(l[1] == 10 and l[2] == 11 and l[3] == 13 and l[4] == 39, "the evicted area keeps its authored roster")

-- no swap when a captain entry isn't plain (a scripted entrance needs its type)
groups({ { true, { 10, true }, { 10, false } }, { true, { 11, true } } })
new_area(); preload(PIT)
l = listed(PIT)
assert(l[1] == 10 and H.r32(entry(0, 0)) == 10 and H.r32(entry(0, 1)) == 10, "no swap with a scripted captain")

-- no swap on a full map that wasn't tested (map 6's roster at a made-up address)
local UNTESTED = desc(0x004FD700, 4, { 27, 14, 46, 22, NONE })
groups({ { true, { 27, true }, { 14, true } } })
new_area(); preload(UNTESTED)
l = listed(UNTESTED)
assert(l[1] == 27 and l[2] == 14 and l[3] == 46 and l[4] == 22 and H.r32(entry(0, 0)) == 27, "untested maps keep their roster")

-- map 64: three types; its groups author only them, so the fourth slot is
-- free and the outsider is appended as before
local FOUNDRY = desc(0x004FE318, 3, { 12, 15, 13, NONE })
groups({ { true, { 12, true }, { 15, true }, { 13, true } } })
new_area(); preload(FOUNDRY)
l = listed(FOUNDRY)
assert(l[1] == 12 and l[2] == 15 and l[3] == 13 and POOL[l[4]] and l[5] == NONE and H.r32(FOUNDRY + 0x20) == 4,
  "room left: appended, not swapped")
assert(H.r32(entry(0, 0)) == 12, "no entry converted at the preload")
-- with a group bringing in a type of its own, the fourth slot stays free: swap
groups({ { true, { 12, true }, { 15, true }, { 0x16, true } }, { true, { 12, true } } })
new_area(); preload(FOUNDRY)
l = listed(FOUNDRY)
assert(POOL[l[1]] and l[1] ~= 12 and l[2] == 15 and l[3] == 13 and l[4] == NONE and H.r32(FOUNDRY + 0x20) == 3,
  "no room: the archers' place goes to an outsider")
assert(H.r32(entry(0, 0)) == l[1] and H.r32(entry(1, 0)) == l[1], "the archers' entries are the outsider")

-- versus: the authored roster
H.w32(GM + 0x88, 2)
groups({ { true, { 10, true } } })
new_area(); preload(PIT)
l = listed(PIT)
assert(l[1] == 10 and H.r32(entry(0, 0)) == 10, "versus keeps the roster")
H.w32(GM + 0x88, 0)

assert(#H.failed == 0, "script error: " .. tostring(H.failed[1]))
print("max_writes", H.max_writes, "max_instr", H.max_instr)
print("PASS shuffle 0.13.0 swaps")
