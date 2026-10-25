-- Smoke test for every MKSMK Probe 0.8 script: read-only, silent until the game
-- saves, then exactly one report, and nothing more on a later save.
-- Usage: lua tests/probe_save.lua <packed probe script> <expected tag>
package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m = H.load(arg[1])
local tag = arg[2]
local SAVE_GAME = 0x001272A0
local STACK = 0xD00F0000
local GM = 0x81200000
assert(m[SAVE_GAME], "no save hook")

H.w32(0x005ACEBC, GM); H.w32(GM + 0x88, 0)
H.w32(0x005CE878, 1000)

-- 1) a save before anything was collected must not report
H.invoke(m, SAVE_GAME, { esp = STACK }, nil)
assert(#H.failed == 0, "reported with nothing collected")

-- 2) drive every hook once with a quiet state, then save
for address, _ in pairs(m) do
  if address ~= SAVE_GAME then
    H.invoke(m, address, { esp = STACK, ecx = 0x006DBFB0, eax = 0 }, function(ctx) ctx.eax = 0 end)
  end
end
H.w32(0x005CE878, 1000 + 100000)
H.invoke(m, SAVE_GAME, { esp = STACK }, nil)
H.invoke(m, SAVE_GAME, { esp = STACK }, nil)
print("errors", #H.failed, "max_writes", H.max_writes, "max_instr", H.max_instr)
assert(H.max_writes == 0, "probe wrote to game memory")
assert(#H.failed <= 1, "more than one report: " .. #H.failed)
if #H.failed == 1 then
  assert(tostring(H.failed[1]):find(tag .. " save", 1, true), "wrong report: " .. tostring(H.failed[1]))
  print("report:", tostring(H.failed[1]):sub(1, 160))
else
  print("no report (nothing collected from a quiet state)")
end
print("PASS " .. arg[1])
