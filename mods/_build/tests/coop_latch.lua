-- coop_solo 0.6.1 plate latch: in single player a plate flag cleared soon after
-- being set stays set for LATCH_FRAMES, then is released; long-lived flags,
-- co-op and versus are untouched.
package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m = H.load(arg[1])
local GAME_EVENT, CHECK = 0x00013134, 0x0016F4B0
local GM, STACK, DEF, ARGS = 0x81200000, 0xD00F0000, 0x81400000, 0x81400100
local FLAG = GM + 0x4874
H.w32(0x005ACEBC, GM); H.w32(0x00682020, 0)
H.w32(STACK + 4, DEF); H.w32(DEF + 8, ARGS)
local function frame(n) H.w32(0x005CE878, n) end
local function event(id, value)
  H.w32(ARGS, id); H.w32(ARGS + 4, value)
  H.invoke(m, GAME_EVENT, { esp = STACK, ecx = 0 }, function() H.w8(FLAG + id, value ~= 0 and 1 or 0) end)
end
local function tick() H.invoke(m, CHECK, { esp = STACK, ecx = 0 }, nil) end
H.w32(GM + 0x88, 0)                      -- single player
frame(1000); event(28, 1)                -- step on plate A
frame(1021); event(28, 0)                -- step off 21 frames later
assert(H.r8(FLAG + 28) == 1, "plate flag should be latched after stepping off")
frame(1500); tick()
assert(H.r8(FLAG + 28) == 1, "still latched before the time is up")
frame(1921); tick()
assert(H.r8(FLAG + 28) == 0, "released after LATCH_FRAMES")
frame(2000); event(5, 1)                 -- a long-lived flag
frame(3000); event(5, 0)
assert(H.r8(FLAG + 5) == 0, "a flag cleared long after being set is not latched")
H.w32(GM + 0x88, 1)                      -- co-op: untouched
frame(4000); event(29, 1); frame(4010); event(29, 0)
assert(H.r8(FLAG + 29) == 0, "co-op must keep the real clear")
assert(#H.failed == 0, "script error: " .. tostring(H.failed[1]))
print("max_writes", H.max_writes)
print("PASS coop_solo 0.6.1 plate latch")
