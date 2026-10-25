-- MKSMK Probe 0.11: savestat copy k reports the XP balance, playtime, upgrade
-- counters and the save call's arguments at the k-th save, once.
-- Usage: lua tests/probe_savestat.lua <probe_savestat.lua> <probe_savestat_2.lua>
package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m1 = H.load(arg[1])
local m2 = H.load(arg[2])
local GM, STACK = 0x81200000, 0xD00F0000
local SAVE = 0x001272A0
H.w32(0x005ACEBC, GM)
H.w32(GM, 0x0002DF55)                       -- playtime
H.w32(GM + 0x4940, 23330)
H.w32(GM + 0xCC, 3); H.w32(GM + 0xD0, 0xFFFFFFFF)
H.w32(GM + 0x1C4, 0x00030400)
H.w32(0x00505970, 7); H.w32(0x005CE878, 0x1234)
for i = 1, 4 do H.w32(STACK + i * 4, i) end
H.invoke(m1, SAVE, { esp = STACK, ecx = 0x5ACE00 }, nil)
H.invoke(m2, SAVE, { esp = STACK, ecx = 0x5ACE00 }, nil)
assert(#H.failed == 1, "only copy #1 reports at the first save")
local r1 = tostring(H.failed[1])
print("report #1:", r1)
assert(r1 == "SAVESTAT save#1 frame=1234 map=7 gm=81200000 playtime=2DF55 xp=23330 chars=3,FFFFFFFF"
  .. " +DC=0 +1C4=30400 +1D0=0 ecx=5ACE00 args=1,2,3,4", "report fields")
H.w32(GM + 0x4940, 1830)
H.invoke(m1, SAVE, { esp = STACK, ecx = 0 }, nil)
H.invoke(m2, SAVE, { esp = STACK, ecx = 0 }, nil)
assert(#H.failed == 2, "copy #2 reports at the second save; copy #1 is done")
assert(tostring(H.failed[2]):find("SAVESTAT save#2 .* xp=1830 "), "copy #2 sees the new XP")
assert(H.max_writes == 0, "probe wrote to game memory")
print("max_instr", H.max_instr)
print("PASS probe_savestat fields, save index")
