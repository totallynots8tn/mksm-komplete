-- coop_solo 0.6: in single player a player passes stonecolor of any color;
-- enemies, co-op and versus are untouched.
package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m = H.load(arg[1])
local STONE_COLOR = 0x00015574
local GM, STACK, REF, CMD = 0x81200000, 0xD00F0000, 0xD00F8000, 0x81300000
H.w32(0x005ACEBC, GM)
H.w32(STACK + 4, REF)
local function check(mode, idx, original)
  H.w32(GM + 0x88, mode); H.w32(REF + 0x10, idx)
  local c = { esp = STACK, ecx = CMD, eax = 0 }
  H.invoke(m, STONE_COLOR, c, function(ctx) ctx.eax = original end)
  return c.eax & 0xFF
end
local solo_p1   = check(0, 0, 0)
local solo_p2   = check(0, 1, 0)
local solo_foe  = check(0, 5, 0)
local coop_p1   = check(1, 0, 0)
local vs_p1     = check(2, 0, 0)
local solo_pass = check(0, 0, 1)
print("solo P1", solo_p1, "solo P2", solo_p2, "solo enemy", solo_foe, "co-op", coop_p1, "versus", vs_p1, "already", solo_pass)
assert(solo_p1 == 1 and solo_p2 == 1 and solo_pass == 1, "solo players must pass stonecolor")
assert(solo_foe == 0 and coop_p1 == 0 and vs_p1 == 0, "enemies, co-op and versus must keep the real answer")
assert(#H.failed == 0, "script error: " .. tostring(H.failed[1]))
print("PASS coop_solo 0.6 solo stone plates")
