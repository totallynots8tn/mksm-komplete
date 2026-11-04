-- Time Rifts 0.12.0, the co-op area (map 199): no prompt until its rush is
-- beaten (wave records, nobody up); the A prompt, the pull-in (P1 turned the
-- way the spot was read), the warp back, then Kintaro, streamed over the
-- Tarkatans' slot only (the priests' slot is never unloaded), dropping on
-- P1's trail in front of the chair with three of the area's priests; after
-- his fight, once his body is gone, the Tarkatans are streamed back, then
-- BEATEN.
--   lua tests/time_rifts_pack.lua ../time_rifts/pack/scripts/time_rifts.lua
package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m = H.load(arg[1])

local GAMEPLAY, PRE_GATE, POST_GATE = 0x00154F60, 0x00012284, 0x00012C93
local INSTANCE, SINGLETON, VTABLE = 0x00589270, 0x005892A8, 0x00497C60
local VANILLA_SLOT, GATE_RET = 0x00013512, 0x000C753A
local START_GROUP, MODELSTREAM = 0x001D2600, 0x0017BA00
local SET_POSITION, MESSAGETEXT, PAD_MAP, PADS, MESSAGES = 0x0015DC30, 0x00012847, 0x00129480, 0x0063AC20, 0x004E6E20
local REACTION, SET_HEALTH = 0x00016A00, 0x00153CD0
local MAP, MANAGER, PLAYER, DESC = 0x00505970, 0x006DBFB0, 0x005D1AB8, 0x00501790
local E0, STACK = 0xD005FC5C, 0xD00F0000
local SPOT = { -15246.421, -1466.247, -872.126 }
local MGR = 0x81100000
local FLAGS = 0x81000000
local function actor(i) return 0x81200000 + i * 0x1000 end

H.w32(INSTANCE, SINGLETON); H.w32(SINGLETON, VTABLE); H.w32(VTABLE + 0x18, VANILLA_SLOT)
H.w32(MAP, 199)
H.w32(DESC + 0x7C, 0x1337)                               -- map 199 has its own spawn groups
H.w32(0x005ACEBC, MGR)
H.w32(0x0051004C, FLAGS)
for i = 0, 11 do
  H.w16(FLAGS + i * 2, i < 2 and 1 or 0); H.w16(PLAYER + i * 0x3238 + 0x1DFE, i)
  H.w32(PLAYER + i * 0x3238 + 0x200, actor(i)); H.w32(actor(i) + 0x368, 600); H.w8(actor(i) + 0xD4, 1)
end
local function set_alive(i, kind) H.w16(FLAGS + i * 2, kind and 1 or 0); if kind then H.w16(PLAYER + i * 0x3238 + 0x1DFE, kind) end end
-- map 199 as read live: two memory slots, Tarkatan and priest, one block each
local SLOTS, ROWS, BLOCKS, LOADED = 0x006322F8, 0x81001000, 0x81002000, 0x006CA69C
H.w32(SLOTS + 0x08, 4); H.w32(SLOTS + 0x10, 2); H.w32(SLOTS + 0x1C, BLOCKS); H.w32(SLOTS + 0x24, ROWS)
for i, kind in ipairs({ 14, 27, 0xFFFFFFFF, 0xFFFFFFFF }) do
  H.w32(ROWS + (i - 1) * 20 + 4, kind); H.w32(ROWS + (i - 1) * 20 + 8, i - 1)
  H.w32(BLOCKS + (i - 1) * 20 + 4, kind); H.w32(BLOCKS + (i - 1) * 20 + 0x10, i <= 2 and 6 or 0)
end
for i, kind in ipairs({ 0, 1, 14, 27, 0xFFFFFFFF, 0xFFFFFFFF }) do H.w32(LOADED + (i - 1) * 4, kind) end
for _, t in ipairs({ 30, 54, 58, 14, 27 }) do H.w32(0x004FA9F0 + t * 0x30 + 4, 1) end
for g = 18, 22 do                                        -- the map's own groups: Tarkatans and priests
  local base = MANAGER + g * 0xA6C
  H.w16(base + 0xA68, 2); H.w8(base + 0xA6A, 1); H.w32(base + 0x18, 14); H.w32(base + 0x18 + 0x74, 27)
end
H.w32(MESSAGES + 0x6D4, 0xFFFFFFFF)
local function stand(x, y, z) H.wf32(PLAYER + 0x80, x); H.wf32(PLAYER + 0x84, y); H.wf32(PLAYER + 0x88, z) end

local frames, react_until = 0, nil
local started, warped, reacted, lifted = nil, nil, nil, nil
local streams, loads, prompts = {}, {}, 0
local behaviour = {
  [VANILLA_SLOT] = { pop = 0, run = function(ctx) end },
  [MESSAGETEXT] = { pop = 12, run = function(ctx) prompts = prompts + 1; H.w32(MESSAGES + 0x6D4, 4); H.w32(MESSAGES + 0x6F0, 30) end },
  [REACTION] = { pop = 12, run = function(ctx)
      reacted = true; H.w32(PLAYER + 0x1E04, 0xC); react_until = frames + 90; H.wf32(PLAYER + 0x94, 0)
    end },
  [SET_POSITION] = { pop = 4, run = function(ctx)
      local v = H.r32(ctx.esp + 4)
      if ctx.ecx == PLAYER then warped = true else lifted = ctx.ecx end
      H.wf32(ctx.ecx + 0x80, H.rf32(v)); H.wf32(ctx.ecx + 0x84, H.rf32(v + 4)); H.wf32(ctx.ecx + 0x88, H.rf32(v + 8))
    end },
  [MODELSTREAM] = { pop = 12, run = function(ctx)
      local args = H.r32(H.r32(ctx.esp + 4) + 8)
      local slot, kind = H.r32(args), H.r32(args + 4)
      streams[#streams + 1] = { slot = slot, kind = kind }
      H.w32(ROWS + slot * 20 + 4, kind); H.w32(BLOCKS + slot * 20 + 4, kind)
      H.w32(LOADED + (2 + slot) * 4, 0xFFFFFFFF)
      loads[#loads + 1] = { at = frames + 60, index = 2 + slot, kind = kind }
    end },
  [START_GROUP] = { pop = 12, run = function(ctx) started = H.r32(ctx.esp + 4) end },
}
local pad_a, pad_seen = 0, nil
local function frame()
  H.w8(PADS + 2, pad_a)
  H.invoke(m, PAD_MAP, { eax = PADS, esp = E0 - 4 }, nil)
  pad_seen = H.r8(PADS + 2)
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
  if H.r32(MESSAGES + 0x6D4) ~= 0xFFFFFFFF then
    local t = H.r32(MESSAGES + 0x6F0)
    if t <= 1 then H.w32(MESSAGES + 0x6D4, 0xFFFFFFFF) else H.w32(MESSAGES + 0x6F0, t - 1) end
  end
end
local function run(n)
  for _ = 1, n do
    frame(); frames = frames + 1
    if react_until and frames >= react_until then H.w32(PLAYER + 0x1E04, 0); react_until = nil end
    for _, l in ipairs(loads) do if frames == l.at then H.w32(LOADED + l.index * 4, l.kind) end end
    if #H.failed > 0 then return end
  end
end
local function until_started(limit)
  started = nil
  for _ = 1, limit do if started then return end; run(1) end
end

-- before the area's rush is beaten: no prompt (the rift would find no free slot)
stand(SPOT[1] + 1000, SPOT[2], SPOT[3]); run(20)
stand(SPOT[1] + 600, SPOT[2], SPOT[3]); run(20)                 -- the floor in front of the chair
stand(SPOT[1] + 40, SPOT[2], SPOT[3]); run(20)
assert(prompts == 0, "no prompt before the rush is beaten")
set_alive(3, 14)                                                -- a rush Tarkatan still up
for i, wave in ipairs({ 15, 16, 17, 19, 21, 22 }) do
  local record = 0x006C0168 + (i - 1) * 12
  H.w16(record, wave); H.w32(record + 4, 0); H.w8(record + 8, 1)
end
run(20)
assert(prompts == 0, "no prompt while an enemy is up")
set_alive(3, nil); run(10)
assert(prompts == 1, "the A prompt once the rush is beaten")
pad_a = 0xFF; run(1); pad_a = 0
assert(pad_seen == 0 and reacted, "A swallowed, the pull-in plays")
assert(math.abs(H.rf32(PLAYER + 0x94) - 935.0) < 0.01, "pulled in facing the way the spot was read")
run(92)
assert(warped and H.r8(0x005ACEDC) == 0, "no reload: the warp back")
-- Kintaro: streamed over the Tarkatans (slot 0) only, never the priests
until_started(400)
assert(started == 49, "Kintaro's group started: " .. tostring(started) .. " " .. tostring(H.failed[1]))
assert(#streams == 1 and streams[1].slot == 0 and streams[1].kind == 58, "Kintaro streamed over the Tarkatans' slot, not the priests'")
local g = MANAGER + 49 * 0xA6C
assert(H.r16(g + 0xA68) == 4 and H.r32(g + 0x18) == 58, "Kintaro's group: him first")
for i = 1, 3 do assert(H.r32(g + 0x18 + i * 0x74) == 27, "his company: the area's own priests") end
local drop_x = math.floor(SPOT[1] + 600 + 0.5)
assert(H.r32(g + 0x18 + 0x18) == (drop_x & 0xFFFFFFFF), "he drops on the floor P1 crossed in front of the chair, not on the chair")
assert(H.r16(g + 4) == 0x10 and H.r32(g + 8) == 4 and H.r16(g + 0x10) == 0xFFFF, "a vanilla wave's header")
set_alive(6, 58); H.wf32(PLAYER + 6 * 0x3238 + 0x84, SPOT[2] - 10); H.w8(actor(6) + 0xD4, 0); run(10)
assert(H.r8(actor(6) + 0xD4) == 1, "Kintaro made killable")
-- he falls through the floor: put back on the rift's spot, momentum cleared
local kintaro = PLAYER + 6 * 0x3238
H.wf32(kintaro + 0x84, SPOT[2] + 600); run(300)                 -- down the dais to the room floor
assert(not lifted and #H.failed == 0, "a lower floor is not a fall")
H.wf32(kintaro + 0x84, SPOT[2] + 12000); run(120)               -- a leap's moment far below
assert(not lifted and #H.failed == 0, "a moment far below is not a fall")
H.wf32(kintaro + 0x84, SPOT[2] - 10); run(5)
H.wf32(kintaro + 0x84, SPOT[2] + 5000); H.w32(kintaro + 0xD4, 0x42C80000); run(185)
assert(lifted == kintaro and math.abs(H.rf32(kintaro + 0x84) - (SPOT[2] - 64)) < 0.01
  and math.abs(H.rf32(kintaro + 0x80) - SPOT[1]) < 0.01, "a fallen Kintaro put back on the rift's spot")
assert(H.r32(kintaro + 0xD4) == 0, "his fall's momentum cleared")
assert(#H.failed == 0, "a fall is not the end of the fight: " .. tostring(H.failed[1]))
set_alive(7, 27); run(5)                                        -- a priest of his still up
H.w32(STACK + 4, 0); H.invoke(m, SET_HEALTH, { ecx = actor(6), esp = STACK }, nil); run(40)
assert(#H.failed == 0 and #streams == 1, "the Tarkatans wait for Kintaro's body to go")
-- his body goes: the Tarkatans back into slot 0 (the priest still up doesn't matter)
set_alive(6, nil); run(2)
assert(#streams == 2 and streams[2].slot == 0 and streams[2].kind == 14, "the Tarkatans back into slot 0")
run(155)
local report = H.failed[1]
print(report)
assert(report and report:find("^TIMERIFT 0.12.0 BEATEN"), "expected BEATEN, got: " .. tostring(report))
assert(report:find("drop%(%-14646,") and report:find("58 lift1@") and report:find("58 beaten@") and report:find("killable@") and report:find("restored@"),
  "the drop, Kintaro and the restore not noted")
assert(H.r32(LOADED + 2 * 4) == 14 and H.r32(LOADED + 3 * 4) == 27, "the map's types are back in their slots")
assert(H.r8(MGR + 0x1C4 + 22) == 0xA8, "beaten rift (bit 3) remembered in the save: " .. H.r8(MGR + 0x1C4 + 22))
print("max writes:", H.max_writes, "max instr:", H.max_instr)
print("PASS time rifts 0.12.0 Kintaro (map 199)")
