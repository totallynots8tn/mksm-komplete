-- Regression test for Solo Co-op Paths 0.5 plate condition rewrite.
-- Builds a fake trigger manager with two plate triggers and checks that
-- coop_solo.lua rewrites player-2 conditions into player-1 copies in place.
package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m = H.load(arg[1])

local MGR        = 0x81100000
local STACK      = 0xD00F0000
local GM         = 0x81200000     -- game manager object
local OBJ_AB     = 0x81300000     -- actionButton command object
local VT_AB      = 0x81300100
local OBJ_OPI    = 0x81300200     -- OtherPlayerInvisible command object
local VT_OPI     = 0x81300300
local SLOTS0     = 0x81400000
local ARGS0      = 0x81400100
local DEF0       = 0x81400200
local SLOTS1     = 0x81400300
local ARGS1      = 0x81400400
local DEF1       = 0x81400500
local SLOTS2     = 0x81400600     -- a non-plate trigger (no actionButton)
local ARGS2      = 0x81400700
local DEF2       = 0x81400800

local ACTION_BUTTON = 0x000146A1
local OTHER_PLAYER  = 0x0001420A
local ISONEPLAYER   = 0x000156CD

-- manager pointers
H.w32(0x00682020, MGR)            -- TRIG_MGR_PTR
H.w32(0x005ACEBC, GM)             -- GAME_MANAGER
H.w32(GM + 0x88, 0)               -- mode = solo
H.w32(MGR + 0xA8C0, 3)            -- trigger count
H.w32(MGR + 0x1254C, 10)          -- command slot bound

-- command objects: obj[0] = vtable, vtable[0] = execute address
H.w32(MGR + 1*24 + 0x11C00, OBJ_AB)
H.w32(OBJ_AB, VT_AB); H.w32(VT_AB, ACTION_BUTTON)
H.w32(MGR + 2*24 + 0x11C00, OBJ_OPI)
H.w32(OBJ_OPI, VT_OPI); H.w32(VT_OPI, OTHER_PLAYER)
H.w32(MGR + 3*24 + 0x11C00, OBJ_AB)  -- slot 3 also resolves (unused)

local function rec(i) return MGR + i*0xD8 end

-- T0: two actionButton conditions, arg 0 (p1) and arg 1 (p2). The p2 arg must
-- be rewritten to 0.
H.w32(rec(0) + 0x58, 2)
H.w32(rec(0) + 0x5C, SLOTS0); H.w32(SLOTS0 + 0, 1); H.w32(SLOTS0 + 4, 1)
H.w32(rec(0) + 0x60, ARGS0);  H.w32(ARGS0 + 0, 0);  H.w32(ARGS0 + 4, 1)
H.w32(rec(0) + 0x0C, DEF0);   H.w32(DEF0 + 0x70, 0x5000); H.w8(DEF0 + 0x79, 0)
H.w32(rec(0) + 0xCC, 0)

-- T1: actionButton(arg0) + OtherPlayerInvisible. OtherPlayerInvisible is always
-- a player-2 gate, so its slot+arg must be copied from the player-1 actionButton.
H.w32(rec(1) + 0x58, 2)
H.w32(rec(1) + 0x5C, SLOTS1); H.w32(SLOTS1 + 0, 1); H.w32(SLOTS1 + 4, 2)
H.w32(rec(1) + 0x60, ARGS1);  H.w32(ARGS1 + 0, 0);  H.w32(ARGS1 + 4, 0x77)
H.w32(rec(1) + 0x0C, DEF1);   H.w32(DEF1 + 0x70, 0x5000); H.w8(DEF1 + 0x79, 0)
H.w32(rec(1) + 0xCC, 0)

-- T2: isoneplayer only (not a plate). Must be left untouched.
H.w32(rec(2) + 0x58, 1)
H.w32(rec(2) + 0x5C, SLOTS2); H.w32(SLOTS2 + 0, 4)  -- slot 4 unresolved -> not a plate
H.w32(rec(2) + 0x60, ARGS2);  H.w32(ARGS2 + 0, 0x99)
H.w32(rec(2) + 0x0C, DEF2);   H.w32(DEF2 + 0x70, 3); H.w8(DEF2 + 0x79, 0)
H.w32(rec(2) + 0xCC, 0)

local function check(r)
    H.invoke(m, 0x0016F4B0, { ecx = r, esp = STACK }, nil)
end

check(rec(0)); check(rec(1)); check(rec(2))
-- second pass must be cached (no error, no extra writes beyond budget)
check(rec(0)); check(rec(1))

print("T0 actionButton args:", H.r32(ARGS0), H.r32(ARGS0 + 4), "(expect 0 0)")
print("T1 slots:", H.r32(SLOTS1), H.r32(SLOTS1 + 4), "args:", H.r32(ARGS1), H.r32(ARGS1 + 4),
      "(expect 1 1 0 0)")
print("T2 arg untouched:", H.r32(ARGS2), "(expect 153=0x99)")
print("errors", #H.failed, "max_writes", H.max_writes)

assert(H.r32(ARGS0 + 4) == 0, "T0 player-2 actionButton arg not rewritten to 0")
assert(H.r32(SLOTS1 + 4) == 1, "T1 OtherPlayerInvisible slot not copied from player-1")
assert(H.r32(ARGS1 + 4) == 0, "T1 OtherPlayerInvisible arg not copied from player-1")
assert(H.r32(ARGS2) == 0x99, "T2 non-plate trigger was modified")
assert(#H.failed == 0, "coop_solo raised: " .. tostring(H.failed[1]))
print("PASS coop_solo 0.5 plate rewrite")
