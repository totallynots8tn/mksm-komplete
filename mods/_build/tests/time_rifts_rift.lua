-- Time Rifts 0.6.0: walk P1 to the portal spot in map 110 and emulate the
-- frame tail's call gate (as tests/callgate.lua), the load request and the reload, the
-- memory slots as the arena leaves them (three, holding the Wu Shi entrance's
-- types), modelstream loading the Oni a second later, the spawn manager's
-- group start and the Oni's death; expect one TIMERIFT OK report with esp
-- balanced every frame.
--   lua tests/time_rifts_rift.lua ../time_rifts/pack/scripts/time_rifts.lua
package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m = H.load(arg[1])

local GAMEPLAY, PRE_GATE, POST_GATE = 0x00154F60, 0x00012284, 0x00012C93
local INSTANCE, SINGLETON, VTABLE = 0x00589270, 0x005892A8, 0x00497C60
local VANILLA_SLOT, GATE_RET = 0x00013512, 0x000C753A
local LOADMAP, START_GROUP, MODELSTREAM, PRELOAD = 0x00012883, 0x001D2600, 0x0017BA00, 0x00015DEE
local MAP, DESC, MANAGER, PLAYER = 0x00505970, 0x004FF2E8, 0x006DBFB0, 0x005D1AB8
local E0, STACK = 0xD005FC5C, 0xD00F0000
local PX, PY, PZ = -7337.944, -1076.305, 841.819

H.w32(INSTANCE, SINGLETON); H.w32(SINGLETON, VTABLE); H.w32(VTABLE + 0x18, VANILLA_SLOT)
H.w32(MAP, 110)
-- entities by in-use flag index (0 = P1): types kept after death
local FLAGS = 0x81000000
H.w32(0x0051004C, FLAGS)
for i = 0, 11 do H.w16(FLAGS + i * 2, i < 2 and 1 or 0); H.w16(PLAYER + i * 0x3238 + 0x1DFE, i) end
H.w16(PLAYER + 3 * 0x3238 + 0x1DFE, 30)                 -- a dead Orochi's leftover type
local function set_alive(i, kind) H.w16(FLAGS + i * 2, kind and 1 or 0); if kind then H.w16(PLAYER + i * 0x3238 + 0x1DFE, kind) end end
-- memory slots (count 3 of 4): 14, 71, 77 loaded; slot 3 free
local SLOTS, ROWS, LOADED = 0x006322F8, 0x81001000, 0x006CA69C
H.w32(SLOTS + 0x10, 3); H.w32(SLOTS + 0x24, ROWS)
for i, kind in ipairs({ 14, 71, 77, 0xFFFFFFFF }) do
  H.w32(ROWS + (i - 1) * 20 + 4, kind); H.w32(ROWS + (i - 1) * 20 + 0x10, kind == 0xFFFFFFFF and 4 or 6)
end
for i, kind in ipairs({ 0, 1, 14, 71, 77, 0xFFFFFFFF }) do H.w32(LOADED + (i - 1) * 4, kind) end
-- the manager still holds the last map's groups
for g = 0, 5 do
  local base = MANAGER + g * 0xA6C
  H.w16(base + 0xA68, 3); H.w8(base + 0xA6A, 1)
  for e = 0, 2 do H.w32(base + 0x18 + e * 0x74, 14) end
end
local function stand(x, y, z) H.wf32(PLAYER + 0x80, x); H.wf32(PLAYER + 0x84, y); H.wf32(PLAYER + 0x88, z) end

local load_request, streamed, stream_at, started = nil, nil, nil, nil
local behaviour = {
  [VANILLA_SLOT] = { pop = 0, run = function(ctx) end },
  [LOADMAP] = { pop = 12, run = function(ctx)
      local object = H.r32(ctx.esp + 4)
      local args = H.r32(object + 8)
      load_request = { count = H.r32(object + 4), map = H.r32(args), entry = H.r32(args + 4) }
    end },
  [MODELSTREAM] = { pop = 12, run = function(ctx)
      local args = H.r32(H.r32(ctx.esp + 4) + 8)
      streamed = { slot = H.r32(args), kind = H.r32(args + 4) }
    end },
  [START_GROUP] = { pop = 12, run = function(ctx)
      assert(ctx.ecx == MANAGER, "START_GROUP is a manager thiscall")
      assert(H.r32(ctx.esp + 8) == 0xFFFFFFFF and H.r32(ctx.esp + 12) == 0, "started like callspawn: (group, -1, 0)")
      started = H.r32(ctx.esp + 4)
    end },
}

local function frame()
  H.invoke(m, GAMEPLAY, { esp = E0 - 4 }, nil)
  H.invoke(m, PRE_GATE, { esp = E0 }, nil)
  local target = H.r32(H.r32(SINGLETON) + 0x18)
  local b = assert(behaviour[target], string.format("the gate called unknown code %08X", target))
  local ctx = { esp = E0 - 4, ecx = SINGLETON, eax = 1 }
  H.w32(E0 - 4, GATE_RET)
  H.invoke(m, target, ctx, function(c) b.run(c); c.esp = c.esp + 4 + b.pop end)
  assert(ctx.esp == E0, string.format("esp off after the gate call: %+d", ctx.esp - E0))
  H.invoke(m, POST_GATE, { esp = E0 - 4 }, nil)
  assert(H.r32(SINGLETON) == VTABLE, "vtable left swapped after the frame")
end
local frames = 0
local function run(n)
  for _ = 1, n do
    frame(); frames = frames + 1
    -- 0x17BA40 swaps the slot's type at once; the type can spawn ~1 s later
    if streamed and not stream_at then
      stream_at = frames + 60
      H.w32(ROWS + streamed.slot * 20 + 4, streamed.kind)
      H.w32(LOADED + (2 + streamed.slot) * 4, 0xFFFFFFFF)
    end
    if stream_at and frames == stream_at then H.w32(LOADED + (2 + streamed.slot) * 4, streamed.kind) end
    if #H.failed > 0 then return end
  end
end

stand(PX, PY, PZ); run(30)
assert(H.r8(0x005ACEDC) == 0, "no rift without walking up to the spot first")
stand(PX + 1000, PY, PZ); run(10)
stand(PX + 60, PY, PZ + 40); run(10)
assert(H.r8(0x005ACEDC) == 1 and H.r32(0x004FC160) == 110 and H.r32(0x004FC164) == 1 and H.r32(0x005ACEE0) == 0,
  "load request: map 110, entry 1, as loadmap writes it")
assert(H.r8(PLAYER + 0x3217) == 1 and H.r8(PLAYER + 0x3238 + 0x3217) == 1, "both players marked as loading")
assert(not streamed, "nothing loads before the reload")

-- the reload: the preload runs, gameplay resumes at the arena's entrance
H.w32(STACK + 4, DESC); H.invoke(m, PRELOAD, { esp = STACK }, nil)
stand(PX + 1500, PY, PZ)
run(30)
assert(not streamed, "the Oni loads after the arena settles")
run(40)
assert(streamed and streamed.slot == 2 and streamed.kind == 30, "modelstream the Orochi into slot 2 (77, nobody alive)")
run(30)
assert(not started, "the group waits for the Oni to finish loading")
run(40)
assert(started == 1, "rift group started: " .. tostring(started) .. " " .. tostring(H.failed[1]))
local g1 = MANAGER + 0xA6C
assert(H.r16(g1 + 0xA68) == 1 and H.r32(g1 + 0x18) == 30, "one Orochi entry")
assert(H.r32(g1 + 0x18 + 0x18) == (-4049 & 0xFFFFFFFF) and H.r32(g1 + 0x18 + 0x1C) == (-1088 & 0xFFFFFFFF)
  and H.r32(g1 + 0x18 + 0x20) == (-258 & 0xFFFFFFFF), "integer world coordinates of the Oni's spot, mid-arena")
for g = 0, 5 do assert(H.r8(MANAGER + g * 0xA6C + 0xA6A) == (g == 1 and 1 or 0), "only the rift group is on") end

run(20)
assert(#H.failed == 0, "a dead Oni's leftover type is not a live Oni: " .. tostring(H.failed[1]))
set_alive(4, 30); run(300)
assert(#H.failed == 0, "no report while the Oni is up")
set_alive(4, nil); run(5)
local report = H.failed[1]
print(report)
assert(report and report:find("^TIMERIFT 0.6.0 OK"), "expected an OK report, got: " .. tostring(report))
print("max writes:", H.max_writes, "max instr:", H.max_instr)
print("PASS time rifts 0.6.0")
