package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m = H.load(arg[1] or "../env_kill_xp/pack/scripts/env_kill_xp.lua")
local STACK, REF, MGR = 0xD00F0000, 0xD00F8000, 0x81100000
local STATS1, STATS2 = 0x81400000, 0x81410000
for i,c in ipairs({0x63,0x68,0x61,0x72,0}) do H.w8(0x496C80+i-1,c); H.w8(REF+i-1,c) end
H.w32(0x5ACEBC, MGR); H.w32(MGR+0x88, 0); H.w32(0x5CE878, 1000)
local function entity(i) return 0x5D1AB8 + i*0x3238 end
local function actor(i) return 0x81300000 + i*0x1000 end
for i=0,11 do
  H.w32(entity(i)+0x200, actor(i)); H.w32(actor(i)+0x368, 100)
  H.w32(entity(i)+0x68, i+1); H.w16(entity(i)+0x1DFE, 15)       -- type 15 = 50 XP grunt
end
H.w16(entity(9)+0x1DFE, 36)                                      -- an elite (500 XP)
H.w8(0x6C6ED8 + (8+1)*32 + 4, 1)                                 -- char 8 flagged no-XP
H.w32(entity(0)+0x2B6C, 0x81500000); H.w32(0x81500000+0x50, STATS1)
H.w32(entity(1)+0x2B6C, 0x81510000); H.w32(0x81510000+0x50, STATS2)
local function kills(stats, t) return H.r8(stats+0x118+t) end
local function cmd(addr, idx, effect) H.w32(REF+0x10, idx); H.w32(STACK+8, REF); H.invoke(m, addr, {esp=STACK}, effect) end
local function instakill(idx) H.w32(STACK+4, entity(idx)); H.invoke(m, 0x1F2500, {esp=STACK}, function() H.w32(actor(idx)+0x368, 0) end) end
instakill(5)                                                   print("off-map kill -> P1 kills[15]:", kills(STATS1,15))
instakill(5)                                                   print("same victim again (still 1):", kills(STATS1,15))
cmd(0x153DC0, 6, function() H.w32(actor(6)+0x368, 0) end)     print("spike kill -> kills[15]:", kills(STATS1,15))
cmd(0x153DC0, 7, function() H.w32(actor(7)+0x368, 40) end)    print("spike hurt only (still 2):", kills(STATS1,15))
cmd(0x1F25B0, 9, nil)                                          print("pit kill elite -> kills[36]:", kills(STATS1,36))
instakill(8)                                                   print("no-XP flagged victim (still 2):", kills(STATS1,15))
H.w32(STACK+4, entity(0)); H.invoke(m, 0x1F2500, {esp=STACK})   print("player fell (still 2):", kills(STATS1,15))
H.w32(MGR+0x88, 1); H.w32(STATS2+0xC4, 30); instakill(10)      print("co-op, P2 longer combo -> P2 kills[15]:", kills(STATS2,15), "P1:", kills(STATS1,15))
H.w32(MGR+0x88, 2); instakill(11)                              print("versus (P1 still 2, P2 still 1):", kills(STATS1,15), kills(STATS2,15))
print("errors:", #H.failed, H.failed[1] or "")
