package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m = H.load(arg[1])
local MGR = 0x500000
H.w32(0x5ACEBC, MGR)          -- game manager pointer
H.w32(MGR + 0x88, 0)          -- single player

-- the spine must poll on the fight tick, group starts and script XP awards
assert(m[0x001D23F0], "no SPAWN_TICK hook")
assert(m[0x001D2600], "no START_GROUP hook")
assert(m[0x00013A53], "no ADD_XP hook")

local ctx = { ecx = 0, esp = 0xD00F0000, eax = 0 }

-- ramp XP well past every threshold; poll must never error and never write
for xp = 0, 20000, 250 do
  H.w32(MGR + 0x48F0, xp)             -- player 0 XP
  H.w32(MGR + 0x48F0 + 0x50, 0)       -- player 1 XP
  H.invoke(m, 0x001D23F0, ctx)
end

-- versus mode must be ignored (no XP), and a bad manager pointer must not crash
H.w32(MGR + 0x88, 2); H.w32(MGR + 0x48F0, 30000); H.invoke(m, 0x001D23F0, ctx)
H.w32(0x5ACEBC, 0xDEAD); H.invoke(m, 0x001D23F0, ctx)

print("errors", #H.failed, "max_writes", H.max_writes, "max_instr", H.max_instr)
assert(#H.failed == 0, "upgrade raised: " .. tostring(H.failed[1]))
assert(H.max_writes == 0, "upgrade wrote to game memory; it must be inert")
print("upgrade spine: read-only, no errors, thresholds swept")
