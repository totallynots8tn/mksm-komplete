-- MKSMK Probe 0.11.2: heartbeat copy k reports after k*45000 gameplay frames with
-- one sample per 2500 frames since copy k-1, plus a sample at each save; it
-- ignores repeated frames, never writes, and stays inside the instruction budget.
-- Usage: lua tests/probe_heartbeat.lua <probe_heartbeat.lua> <probe_heartbeat_2.lua>
package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m1 = H.load(arg[1])
local m2 = H.load(arg[2])
local GM, STACK = 0x81200000, 0xD00F0000
local CHECK, SAVE = 0x0016F4B0, 0x001272A0
H.w32(0x005ACEBC, GM)
H.w32(GM + 0x4940, 0x1830)                  -- XP
H.w32(0x00505970, 100)                      -- map
for i = 0, 5 do H.w32(0x006CA69C + i * 4, 0xFFFFFFFF) end
H.w32(0x006CA69C, 0xE); H.w32(0x006CA6A0, 0x1A)
H.w8(0x006DBFB0 + 0x2092A, 0)               -- spawner idle
H.w16(0x006DBFB0 + 0x20920, 15); H.w16(0x006DBFB0 + 0x20922, 4)
H.w16(0x006C0168, 15); H.w32(0x006C0168 + 4, 2); H.w8(0x006C0168 + 8, 0)
H.w16(0x006C0168 + 12, 0xFFFF)              -- group -1
local frame = 1000
local function frames(n)
  for _ = 1, n do
    H.w32(0x005CE878, frame); frame = frame + 1
    H.invoke(m1, CHECK, { esp = STACK, ecx = 0 }, nil)
    H.invoke(m1, CHECK, { esp = STACK, ecx = 0 }, nil)   -- same frame twice: counted once
    H.invoke(m2, CHECK, { esp = STACK, ecx = 0 }, nil)
  end
end
frames(7000)
H.invoke(m1, SAVE, { esp = STACK }, nil)
H.invoke(m2, SAVE, { esp = STACK }, nil)    -- copy #2's window has not started: ignored
frames(37999)
assert(#H.failed == 0, "reported early")
frames(1)
assert(#H.failed == 1, "copy #1 reports at 45000 frames")
local r1 = tostring(H.failed[1])
print("report #1:", r1)
assert(r1:find("HEARTBEAT#1 frames=45000 saves=1 | t2500 f", 1, true), "header and first sample")
assert(r1:find("m100 xp6192 sp0,15,4 tyE,1A wc[15:2:0 -1:0:0] hp- mv0", 1, true), "sample fields")
assert(r1:find("| save@7000 ", 1, true), "save sample")
assert(r1:find("| t45000 ", 1, true), "last sample")
local _, n = r1:gsub("| t%d+ ", "")
assert(n == 18, "eighteen samples")
frames(45000)
assert(#H.failed == 2, "copy #2 reports at 90000 frames")
local r2 = tostring(H.failed[2])
assert(r2:find("HEARTBEAT#2 frames=90000 saves=0 | t47500 ", 1, true), "copy #2 covers only its window")
assert(not r2:find("save@", 1, true), "copy #2 ignored the earlier save")
frames(20000)
assert(#H.failed == 2, "each copy reports once")
assert(H.max_writes == 0, "probe wrote to game memory")
print("max_instr", H.max_instr)
print("PASS probe_heartbeat windows, samples, saves")
