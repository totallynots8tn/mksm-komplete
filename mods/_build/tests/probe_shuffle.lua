-- MKSMK Probe 0.8 probe_shuffle: one snapshot per area, written at save.
package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m = H.load(arg[1])
local MANAGER = 0x006DBFB0
local STACK = 0xD00F0000
H.w32(0x005ACEBC, 0x81200000); H.w32(0x81200000 + 0x88, 0)
H.w32(0x005CE878, 1000)
-- area 1: group 0 enabled with two entries of type 0xE
H.w8(MANAGER + 0xA6A, 1); H.w16(MANAGER + 0xA68, 2)
H.w32(MANAGER + 0x18, 0xE); H.w32(MANAGER + 0x18 + 0x74, 0xE)
for i = 0, 5 do H.w32(0x006CA69C + i * 4, 0xFFFFFFFF) end
H.w32(0x006CA69C + 8, 0xE)
local function visit()
  H.invoke(m, 0x00014D2C, { esp = STACK }, nil)                  -- LOAD_GROUPS (after hook)
  H.invoke(m, 0x001D2600, { esp = STACK, ecx = MANAGER }, nil)   -- START_GROUP
  H.invoke(m, 0x001D23F0, { esp = STACK, ecx = MANAGER }, nil)   -- SPAWN_TICK: snapshot
  H.invoke(m, 0x001D23F0, { esp = STACK, ecx = MANAGER }, nil)   -- no second snapshot
end
visit()
H.w32(MANAGER + 0x18 + 0x74, 0x1A)                               -- area 2 differs
visit()
assert(#H.failed == 0, "reported before the game saved")
H.invoke(m, 0x001272A0, { esp = STACK }, nil)
print("errors", #H.failed, "max_writes", H.max_writes)
local msg = tostring(H.failed[1])
print(msg:sub(1, 300))
assert(H.max_writes == 0 and #H.failed == 1, "expected one read-only report")
assert(msg:find("SHUFFLE save#1 areas=2", 1, true), "expected two area snapshots")
assert(msg:find("E=2", 1, true) and msg:find("1A=1once", 1, true), "expected both areas' census")
print("PASS probe_shuffle per-area snapshots at save")
