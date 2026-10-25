-- Regression test for coop_solo_debug.lua 0.6: read-only, keys co-op triggers
-- per map, logs stonecolor / stonepowatleast checks, addstonepower and
-- gameevent with the firing trigger, event-flag changes, and reports once when
-- the game saves.
package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m = H.load(arg[1])

local MGR, GM, STACK, REF = 0x81100000, 0x81200000, 0xD00F0000, 0xD00F8000
local OBJ_SC, VT_SC = 0x81300000, 0x81300100      -- stonecolor command object
local OBJ_SP, VT_SP = 0x81300200, 0x81300300      -- stonepowatleast command object
local SLOTS0, ARGS0, SLOTS1, ARGS1 = 0x81400000, 0x81400100, 0x81400200, 0x81400300
local DEF0, DEF1, EVDEF, EVARGS = 0x81400400, 0x81400500, 0x81400600, 0x81400700
local LINK = 0x81500000
local SAVE_GAME, CHECK, TRY_FIRE, FIRE_EVENTS = 0x001272A0, 0x0016F4B0, 0x0016F560, 0x0016ED90
local STONE_COLOR, STONE_ATLEAST, ADD_STONE, GAME_EVENT = 0x00015574, 0x00013F94, 0x00011938, 0x00013134
local T0, T1 = MGR, MGR + 0xD8

H.w32(0x005ACEBC, GM); H.w32(GM + 0x88, 0)
H.w32(0x00682020, MGR); H.w32(MGR + 0xA8C0, 2); H.w32(MGR + 0x1254C, 10)
H.w32(MGR + 1*24 + 0x11C00, OBJ_SC); H.w32(OBJ_SC, VT_SC); H.w32(VT_SC, STONE_COLOR)
H.w32(MGR + 2*24 + 0x11C00, OBJ_SP); H.w32(OBJ_SP, VT_SP); H.w32(VT_SP, STONE_ATLEAST)
-- T0: colored plate {stonecolor:1}; T1: door {stonepowatleast:2}
H.w32(T0 + 0x58, 1); H.w32(T0 + 0x5C, SLOTS0); H.w32(SLOTS0, 1); H.w32(T0 + 0x60, ARGS0); H.w32(ARGS0, 1)
H.w32(T0 + 0x0C, DEF0); H.w32(DEF0 + 0x70, 3)
H.w32(T1 + 0x58, 1); H.w32(T1 + 0x5C, SLOTS1); H.w32(SLOTS1, 2); H.w32(T1 + 0x60, ARGS1); H.w32(ARGS1, 2)
H.w32(T1 + 0x0C, DEF1); H.w32(DEF1 + 0x70, 3)
-- player 0 has color 0
H.w32(0x005D1AB8 + 0x2B6C, LINK); H.w32(LINK + 4, 0)
H.w32(STACK + 4, REF); H.w32(REF + 0x10, 0)
H.w32(0x00581B48, 0)

local function frame(n) H.w32(0x005CE878, n) end
frame(100)
H.invoke(m, CHECK, { ecx = T0, esp = STACK, eax = 0 }, function(ctx) ctx.eax = 1 end)
H.invoke(m, CHECK, { ecx = T1, esp = STACK, eax = 0 }, function(ctx) ctx.eax = 0 end)
-- the plate's stonecolor check (color 0 vs plate 1), passed by coop_solo's rule
H.w32(OBJ_SC + 8, T0); H.w32(OBJ_SC + 4, 1)
H.invoke(m, STONE_COLOR, { esp = STACK, ecx = OBJ_SC, eax = 0 }, function(ctx) ctx.eax = 1 end)
-- the plate fires: addstonepower +1 and gameevent 5 = 1
H.invoke(m, TRY_FIRE, { ecx = T0, esp = STACK, eax = 0 }, function(ctx) ctx.eax = 1 end)
H.w32(STACK + 4, EVDEF); H.w32(EVDEF + 8, EVARGS)
H.invoke(m, FIRE_EVENTS, { ecx = T0 + 0x68, esp = STACK }, function(ctx)
  H.w32(EVARGS, 1)
  H.invoke(m, ADD_STONE, { esp = STACK, ecx = 0 }, function() H.w32(0x00581B48, 1) end)
  H.w32(EVARGS, 5); H.w32(EVARGS + 4, 1)
  H.invoke(m, GAME_EVENT, { esp = STACK, ecx = 0 }, function() H.w8(GM + 0x4874 + 5, 1) end)
end)
H.w32(STACK + 4, REF)
-- next frame: the flag change is seen; the door checks the power
frame(101)
H.invoke(m, CHECK, { ecx = T1, esp = STACK, eax = 0 }, function(ctx) ctx.eax = 0 end)
H.w32(OBJ_SP + 8, T1); H.w32(OBJ_SP + 4, 2)
H.invoke(m, STONE_ATLEAST, { esp = STACK, ecx = OBJ_SP, eax = 0 }, function(ctx) ctx.eax = 0 end)
assert(#H.failed == 0, "reported before the game saved: " .. tostring(H.failed[1]))
H.invoke(m, SAVE_GAME, { esp = STACK }, nil)
H.invoke(m, SAVE_GAME, { esp = STACK }, nil)

local msg = H.failed[1] or ""
print("errors", #H.failed, "max_writes", H.max_writes)
print("report:", msg:sub(1, 600))
assert(H.max_writes == 0, "debug script wrote to guest memory")
assert(#H.failed == 1, "expected exactly one report, got " .. #H.failed)
assert(msg:find("PLATE060 save mode=0 maps=1 stone=1", 1, true), "header")
assert(msg:find("m1T0{f3}stonecolor:1 chk1 pass1 fired1 ev1", 1, true), "plate trigger stats")
assert(msg:find("m1T1{f3}stonepowatleast:2 chk2 pass0 fired0 ev0", 1, true), "door trigger stats")
assert(msg:find("SCm1T0i0c0/1r1", 1, true), "stonecolor detail")
assert(msg:find("ASm1T0:+1@0", 1, true), "addstonepower detail")
assert(msg:find("GEm1T0:5=1", 1, true), "gameevent detail")
assert(msg:find("SPm1T1:1>=2r0", 1, true), "stonepowatleast detail")
assert(msg:find("FLAGS f101:E5=1", 1, true), "event flag change")
print("PASS coop_solo_debug 0.6 stone diagnostics")
