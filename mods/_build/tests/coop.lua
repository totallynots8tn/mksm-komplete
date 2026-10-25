package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m = H.load(arg[1])
local STACK, REF, MGR = 0xD00F0000, 0xD00F8000, 0x81100000
for i,c in ipairs({0x63,0x68,0x61,0x72,0}) do H.w8(0x496C80+i-1,c); H.w8(REF+i-1,c) end
H.w32(0x5ACEBC, MGR); H.w32(STACK+4, REF)
local function ask(addr, mode)
  H.w32(MGR+0x88, mode)
  local ctx = {esp=STACK, eax=0x12345600}
  H.invoke(m, addr, ctx, function() ctx.eax = (ctx.eax & 0xFFFFFF00) | (addr == 0x12E55 and (mode==1 and 1 or 0) or (mode==0 and 1 or 0)) end)
  return ctx.eax & 0xFF
end
print("solo:   istwoplayer", ask(0x12E55,0), "isoneplayer", ask(0x156CD,0))
print("co-op:  istwoplayer", ask(0x12E55,1), "isoneplayer", ask(0x156CD,1))
print("versus: istwoplayer", ask(0x12E55,2), "isoneplayer", ask(0x156CD,2))
-- 0.4: a caller inside the trigger-condition walk (0x16F4B0..0x16F560) must get
-- the honest isoneplayer answer, so solo-progression plate triggers can pass.
H.w32(STACK+0, 0x0016F500)   -- a live return address into CHECK
print("solo/trigger-cond: isoneplayer", ask(0x156CD,0), "(expect 1)")
H.w32(STACK+0, 0)            -- clear it again
print("solo/layout:         isoneplayer", ask(0x156CD,0), "(expect 0)")
print("errors", #H.failed)
assert(#H.failed == 0, "coop_solo raised: " .. tostring(H.failed[1]))
