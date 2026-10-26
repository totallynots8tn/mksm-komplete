-- Shaolin Shuffle 0.7 preload rules: a map that preloads one regular enemy
-- type gets one outsider appended (cap raised so the preload isn't skipped);
-- two-type lists, bosses, MK characters and versus keep the authored roster,
-- which is restored on every visit.
package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m = H.load(arg[1])
local LOAD_GROUPS, PRELOAD = 0x00014D2C, 0x00015DEE
local STACK, GM = 0xD00F0000, 0x81200000
-- the variant's own pool (0.9: Wild and Chaos widen it), read from the script
local POOL = {}
local pool_line = assert(io.open(arg[1], "rb")):read("a"):match("local OUTSIDERS%s*=%s*(%b{})")
for id in assert(pool_line, "no OUTSIDERS line"):gmatch("%d+") do POOL[tonumber(id)] = true end
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

local GORO = desc(0x004FD000, 1, { 15, NONE })
local TWO  = desc(0x004FD100, 3, { 14, 26, NONE })
local ONI  = desc(0x004FD200, 3, { 36, NONE })
local SCORP = desc(0x004FD300, 1, { 80, NONE })
local EMPTY = desc(0x004FD400, 3, { NONE })

local seen = {}
for visit = 1, 12 do
  H.w32(0x005CE878, visit * 7919)            -- frame counter feeds the seed
  new_area(); preload(GORO)
  local a, b, c = list(GORO)
  assert(a == 15, "authored type stays first")
  assert(POOL[b] and b ~= 15, "outsider from the pool, not the area's own type: " .. tostring(b))
  assert(c == NONE, "list stays -1 terminated")
  assert(H.r32(GORO + 0x20) == 2, "cap raised to 2 so the preload isn't skipped")
  seen[b] = true
end
local kinds = 0 for _ in pairs(seen) do kinds = kinds + 1 end
assert(kinds >= 3, "outsiders vary between visits (saw " .. kinds .. ")")

for _, d in ipairs({ TWO, ONI, SCORP, EMPTY }) do
  local before = { list(d) }; local cap = H.r32(d + 0x20)
  new_area(); preload(d)
  local after = { list(d) }
  assert(after[1] == before[1] and after[2] == before[2] and after[3] == before[3] and H.r32(d + 0x20) == cap,
    "only single regular-type maps get an outsider")
end

-- versus: the authored roster comes back, garbage after the terminator included
H.w32(GM + 0x88, 2)
new_area(); preload(GORO)
local a, b, c = list(GORO)
assert(a == 15 and b == NONE and c == 0x55555555 and H.r32(GORO + 0x20) == 1, "versus restores the authored roster")
H.w32(GM + 0x88, 0)
new_area(); preload(GORO)
assert(POOL[select(2, list(GORO))], "single player gets an outsider again")

assert(#H.failed == 0, "script error: " .. tostring(H.failed[1]))
print("max_writes", H.max_writes, "max_instr", H.max_instr)
print("PASS shuffle 0.7 preload rules")
