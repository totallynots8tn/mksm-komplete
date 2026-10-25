-- MKSMK Probe 0.10: the save-data watcher records every changed dword of the
-- game manager with first/last value and count, reports at its save index, and
-- a copy with SAVE_INDEX 2 stays silent at the first save.
-- Usage: lua tests/probe_savediff.lua <probe_savediff.lua> <probe_savediff_2.lua>
package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m1 = H.load(arg[1])
local m2 = H.load(arg[2])
local GM, STACK = 0x81200000, 0xD00F0000
local CHECK, SAVE = 0x0016F4B0, 0x001272A0
H.w32(0x005ACEBC, GM)
for i = 0, 0x8000 - 4, 4 do H.w32(GM + i, 0) end
H.w32(GM + 0xCC, 3)
local frame = 100
local function frames(n)
  for _ = 1, n do
    H.w32(0x005CE878, frame); frame = frame + 1
    H.invoke(m1, CHECK, { esp = STACK, ecx = 0 }, nil)
    H.invoke(m2, CHECK, { esp = STACK, ecx = 0 }, nil)
  end
end
frames(32)                                  -- baseline: 32 KB at 1 KB per frame
H.w32(GM + 0x48F0, 250)                     -- XP-like field moves twice
frames(32)
H.w32(GM + 0x48F0, 900)
H.w8(GM + 0x4874 + 5, 1)                    -- event flag 5
frames(32)
assert(#H.failed == 0, "reported before the game saved")
H.invoke(m1, SAVE, { esp = STACK }, nil)
H.invoke(m2, SAVE, { esp = STACK }, nil)    -- copy #2: first save, stays silent
print("after first save:", #H.failed)
assert(#H.failed == 1, "only copy #1 reports at the first save")
local r1 = tostring(H.failed[1])
print("report #1:", r1:sub(1, 200))
assert(r1:find("SAVEDIFF save#1 gm=81200000 rebases=1 watched=8000 changed=2", 1, true), "header")
assert(r1:find("+48F0:0>384(2)", 1, true), "XP field first/last/count")
assert(r1:find("+4878:0>100(1)", 1, true), "event flag 5 is byte 1 of the dword at +0x4878")
H.invoke(m2, SAVE, { esp = STACK }, nil)    -- second save: copy #2 reports
assert(#H.failed == 2, "copy #2 reports at the second save")
assert(tostring(H.failed[2]):find("SAVEDIFF save#2", 1, true), "copy #2 tag")
assert(H.max_writes == 0, "probe wrote to game memory")
print("max_instr", H.max_instr)
print("PASS probe_savediff baseline, changes, save index")
