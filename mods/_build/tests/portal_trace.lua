-- Portal Trace 0.3: two loadmap requests (one repeated, as a walking exit),
-- two trigger events, then a save; expect one PORTALTRACE line naming them.
--   lua tests/portal_trace.lua ../portal_trace/pack/scripts/portal_trace.lua
package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m = H.load(arg[1])
local STACK, OBJ, ARGS = 0xD00F0000, 0x81400000, 0x81400100
H.w32(0x00505970, 107)
H.w32(OBJ + 4, 2); H.w32(OBJ + 8, ARGS)
H.w32(STACK + 8, 0x0016EE10); H.w32(STACK + 0x20, 0x81234567); H.w32(STACK + 0x30, 0x000C753A)
local function loadmap(to, entry)
  H.w32(ARGS, to); H.w32(ARGS + 4, entry); H.w32(STACK + 4, OBJ)
  H.invoke(m, 0x00012883, { esp = STACK }, nil)
end
for _ = 1, 3 do H.invoke(m, 0x00154F60, { esp = STACK }, nil); loadmap(105, 2) end
loadmap(193, 1)
-- trigger events in the Portals (map 192); one in 107 isn't recorded
H.invoke(m, 0x001F2E90, { esp = STACK, ecx = OBJ }, nil)
H.w32(0x00505970, 192)
-- ecx = the event: +0 -> name, +4 count, +8 -> args, +0x10 -> command -> +0x10 object -> vtable -> exec
local NAME, COMMAND, CMDOBJ, VT = 0x81500000, 0x81500100, 0x81500200, 0x81500300
for i, c in ipairs({ string.byte("loadmap", 1, -1) }) do H.w8(NAME + i - 1, c) end
H.w32(OBJ, NAME); H.w32(OBJ + 0x10, COMMAND); H.w32(COMMAND + 0x10, CMDOBJ); H.w32(CMDOBJ, VT); H.w32(VT, 0x000D0E00)
for _ = 1, 2 do H.invoke(m, 0x001F2E90, { esp = STACK, ecx = OBJ }, nil) end
H.invoke(m, 0x001272A0, { esp = STACK }, nil)
local report = H.failed[1]
print(report)
assert(report:find("^PORTALTRACE 0.3") and report:find("EVENTS %[f3 x2 C0 loadmap@D0E00 C81500200 E81400000 n2:C1,1 a81400000,16EE10,0%]$") and report:find("6B>69:2:81400000 x3") and report:find("6B>C1:1:81400000 x1")
  and report:find("ret=16EE10@8/C753A@30"), "both loads with counts and callers")
print("PASS portal trace")
