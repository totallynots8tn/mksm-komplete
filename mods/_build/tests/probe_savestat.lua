-- MKSMK Probe 0.12: savestat copy k reports the XP balance, playtime, upgrade
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
-- 0.12 fields: P0 meter 380.0 at level 2, EX on * and |, health 450/600
H.wf32(GM + 0x4954, 380.0); H.w32(GM + 0x4978, 2)
H.w8(GM + 0x1C4 + 19, 1); H.w8(GM + 0x1C4 + 21, 1)
local ACTOR = 0x81300000
H.w32(0x005D1AB8 + 0x200, ACTOR); H.w32(ACTOR + 0x368, 450); H.w32(ACTOR + 0x370, 600)
H.w32(GM + 0x94, 600); H.w32(GM + 0x90, 1)
H.w32(0x004DFC1C, 5); H.w32(0x004DF5D8, 37)
for i = 1, 4 do H.w32(STACK + i * 4, i) end
H.invoke(m1, SAVE, { esp = STACK, ecx = 0x5ACE00 }, nil)
H.invoke(m2, SAVE, { esp = STACK, ecx = 0x5ACE00 }, nil)
assert(#H.failed == 1, "only copy #1 reports at the first save")
local r1 = tostring(H.failed[1])
print("report #1:", r1)
assert(r1 == "SAVESTAT save#1 frame=1234 map=7 gm=81200000 playtime=2DF55 xp=23330 chars=3,FFFFFFFF"
  .. " +DC=0 +E0=0 +1C4=30400 +1D0=0"
  .. " P0[xp=23330 mv=380 ml=2 ex=1010 s27=0 hp=450/600] P1[xp=0 mv=0 ml=0 ex=0000 s27=0 hp=-]"
  .. " maxhp=600 hplvl=1 fat=5/37 ecx=5ACE00 args=1,2,3,4", "report fields: " .. r1)
H.w32(GM + 0x4940, 1830)
H.invoke(m1, SAVE, { esp = STACK, ecx = 0 }, nil)
H.invoke(m2, SAVE, { esp = STACK, ecx = 0 }, nil)
assert(#H.failed == 2, "copy #2 reports at the second save; copy #1 is done")
assert(tostring(H.failed[2]):find("SAVESTAT save#2 .* xp=1830 "), "copy #2 sees the new XP")
assert(H.max_writes == 0, "probe wrote to game memory")
print("max_instr", H.max_instr)
print("PASS probe_savestat fields, save index")
