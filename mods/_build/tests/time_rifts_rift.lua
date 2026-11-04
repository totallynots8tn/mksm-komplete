-- Time Rifts 0.12.0: walk P1 to a rift's spot and emulate the frame tail's
-- call gate (as tests/callgate.lua), the load request and the reload, the
-- memory slots as the arena leaves them (three loaded types), modelstream
-- loading the boss a second later, the spawn manager's group start and the
-- fight's end; expect one TIMERIFT report, one frame after the verdict, with
-- esp balanced every frame.
-- Map 110 (no spawn file): the last map's groups are switched off, an Orochi.
-- Map 132 (its own groups stay on, no reload): the portal's A prompt
-- (messagetext, kept up by its timer), A swallowed, the pull-in reaction
-- (P1 in state 0xC for 90 frames), set-position to the shrine deck, then
-- Mileena in her arena once P1 is back within 1500 of her spot.
-- Cases: beaten (the game sets the boss's health to 0), vanish (the boss
-- disappears with health left), failed (P1 goes down), left (the map
-- changes mid-fight), once (a rift beaten on this save never opens), stuck
-- (map 132: the pull-in never starts and set-position doesn't hold).
--   lua tests/time_rifts_rift.lua ../time_rifts/pack/scripts/time_rifts.lua [110|132] [case]
package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m = H.load(arg[1])

local GAMEPLAY, PRE_GATE, POST_GATE = 0x00154F60, 0x00012284, 0x00012C93
local INSTANCE, SINGLETON, VTABLE = 0x00589270, 0x005892A8, 0x00497C60
local VANILLA_SLOT, GATE_RET = 0x00013512, 0x000C753A
local LOADMAP, START_GROUP, MODELSTREAM, PRELOAD = 0x00012883, 0x001D2600, 0x0017BA00, 0x00015DEE
local SET_HEALTH = 0x00153CD0
local SET_POSITION, MESSAGETEXT, PAD_MAP, PADS, MESSAGES = 0x0015DC30, 0x00012847, 0x00129480, 0x0063AC20, 0x004E6E20
local REACTION = 0x00016A00
local MILEENA = arg[2] == "132"
local CASE = arg[3] or "beaten"
local MAP, MANAGER, PLAYER = 0x00505970, 0x006DBFB0, 0x005D1AB8
local DESC = MILEENA and 0x004FF5C8 or 0x004FF2E8
local E0, STACK = 0xD005FC5C, 0xD00F0000
local PX, PY, PZ = -7337.944, -1076.305, 841.819
local SPOT = { -4049, -1088, -258 }
local ARRIVE = { 63824.207, -1200.248, -20076.363 }      -- map 132: the shrine deck
if MILEENA then PX, PY, PZ = 92509.586, -1139.231, -19890.369; SPOT = { 87947, -1139, -19956 } end
local MGR = 0x81100000
local CLEARED = MGR + 0x1C4 + 22                         -- player 1's level slot 22
local MARK = 0x54464952                                  -- "RIFT", group record +0xA10

H.w32(INSTANCE, SINGLETON); H.w32(SINGLETON, VTABLE); H.w32(VTABLE + 0x18, VANILLA_SLOT)
H.w32(MAP, MILEENA and 132 or 110)
H.w32(DESC + 0x7C, MILEENA and 0xDFB or 0xFFFFFFFF)      -- the map's spawn-group file
H.w32(0x005ACEBC, MGR)
-- entities by in-use flag index (0 = P1): types kept after death; actors with health
local FLAGS = 0x81000000
H.w32(0x0051004C, FLAGS)
local ACT = {}
for i = 0, 11 do
  H.w16(FLAGS + i * 2, i < 2 and 1 or 0); H.w16(PLAYER + i * 0x3238 + 0x1DFE, i)
  ACT[i] = 0x81200000 + i * 0x1000
  H.w32(PLAYER + i * 0x3238 + 0x200, ACT[i]); H.w32(ACT[i] + 0x368, 600); H.w32(ACT[i] + 0x370, 600)
end
H.w16(PLAYER + 3 * 0x3238 + 0x1DFE, 30)                 -- a dead Orochi's leftover type
local function set_alive(i, kind) H.w16(FLAGS + i * 2, kind and 1 or 0); if kind then H.w16(PLAYER + i * 0x3238 + 0x1DFE, kind) end end
-- memory slots (count 3 of 4): 14, 71, 77 loaded; slot 3 free
local SLOTS, ROWS, LOADED = 0x006322F8, 0x81001000, 0x006CA69C
H.w32(SLOTS + 0x10, 3); H.w32(SLOTS + 0x24, ROWS)
for i, kind in ipairs({ 14, 71, 77, 0xFFFFFFFF }) do
  H.w32(ROWS + (i - 1) * 20 + 4, kind); H.w32(ROWS + (i - 1) * 20 + 0x10, kind == 0xFFFFFFFF and 4 or 6)
end
for i, kind in ipairs({ 0, 1, 14, 71, 77, 0xFFFFFFFF }) do H.w32(LOADED + (i - 1) * 4, kind) end
-- the manager still holds the last map's groups (they author 14: slot 0's type)
for g = 0, 5 do
  local base = MANAGER + g * 0xA6C
  H.w16(base + 0xA68, 3); H.w8(base + 0xA6A, 1)
  for e = 0, 2 do H.w32(base + 0x18 + e * 0x74, 14) end
end
local function stand(x, y, z) H.wf32(PLAYER + 0x80, x); H.wf32(PLAYER + 0x84, y); H.wf32(PLAYER + 0x88, z) end
if CASE == "once" then H.w8(CLEARED, MILEENA and 0xA2 or 0xA1) end
H.w32(MESSAGES + 0x6D4, 0xFFFFFFFF)                      -- no message shows

local load_request, streamed, started = nil, nil, nil
local streams = 0
local stream_log = {}
local prompt, warped, reacted = nil, nil, nil
local prompts = 0
local react_until = nil                                  -- test frame the pull-in ends
local frames = 0
local behaviour = {
  [REACTION] = { pop = 12, run = function(ctx)
      local E, target, from = H.r32(ctx.esp + 4), H.r32(ctx.esp + 8), H.r32(ctx.esp + 12)
      local args, rest = H.r32(E + 8), 0
      for i = 4, 15 do rest = rest | H.r32(args + i * 4) end
      reacted = { count = H.r32(E + 4), anim = H.r32(args), alt = H.r32(args + 8), rest = rest | H.r32(args + 4) | H.r32(args + 12),
                  kind = H.r32(target), index = H.r32(target + 0x10),
                  x = H.rf32(from + 4), y = H.rf32(from + 8), z = H.rf32(from + 12) }
      if CASE ~= "stuck" then H.w32(PLAYER + 0x1E04, 0xC); react_until = frames + 90 end
    end },
  [MESSAGETEXT] = { pop = 12, run = function(ctx)
      local args = H.r32(H.r32(ctx.esp + 4) + 8)
      prompt = { text = H.r32(args), kind = H.r32(args + 4) }
      prompts = prompts + 1
      H.w32(MESSAGES + 0x6D4, prompt.kind); H.w32(MESSAGES + 0x6F0, 30)
    end },
  [SET_POSITION] = { pop = 4, run = function(ctx)
      assert(ctx.ecx == PLAYER, "set-position is a thiscall on P1's entity")
      local v = H.r32(ctx.esp + 4)
      warped = { x = H.rf32(v), y = H.rf32(v + 4), z = H.rf32(v + 8), w = H.r32(v + 12) }
      if CASE ~= "stuck" then stand(warped.x, warped.y, warped.z) end
    end },
  [VANILLA_SLOT] = { pop = 0, run = function(ctx) end },
  [LOADMAP] = { pop = 12, run = function(ctx)
      local object = H.r32(ctx.esp + 4)
      local args = H.r32(object + 8)
      load_request = { count = H.r32(object + 4), map = H.r32(args), entry = H.r32(args + 4) }
    end },
  [MODELSTREAM] = { pop = 12, run = function(ctx)
      local args = H.r32(H.r32(ctx.esp + 4) + 8)
      streamed = { slot = H.r32(args), kind = H.r32(args + 4) }
      streams = streams + 1
      stream_log[streams] = streamed
    end },
  [START_GROUP] = { pop = 12, run = function(ctx)
      assert(ctx.ecx == MANAGER, "START_GROUP is a manager thiscall")
      assert(H.r32(ctx.esp + 8) == 0xFFFFFFFF and H.r32(ctx.esp + 12) == 0, "started like callspawn: (group, -1, 0)")
      started = H.r32(ctx.esp + 4)
    end },
}

local pad_a, pad_seen = 0, nil                           -- port 0's A byte, and what the game reads
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
  -- the message manager: a shown message counts down and hides at 0
  if H.r32(MESSAGES + 0x6D4) ~= 0xFFFFFFFF then
    local t = H.r32(MESSAGES + 0x6F0)
    if t <= 1 then H.w32(MESSAGES + 0x6D4, 0xFFFFFFFF); H.w32(MESSAGES + 0x6F0, 0) else H.w32(MESSAGES + 0x6F0, t - 1) end
  end
end
local function run(n)
  for _ = 1, n do
    frame(); frames = frames + 1
    if react_until and frames >= react_until then H.w32(PLAYER + 0x1E04, 0); react_until = nil end
    -- 0x17BA40 swaps the slot's type at once; the type can spawn ~1 s later
    if streamed and not streamed.at then
      streamed.at = frames + 60
      H.w32(ROWS + streamed.slot * 20 + 4, streamed.kind)
      H.w32(LOADED + (2 + streamed.slot) * 4, 0xFFFFFFFF)
    end
    if streamed and frames == streamed.at then H.w32(LOADED + (2 + streamed.slot) * 4, streamed.kind) end
    if #H.failed > 0 then return end
  end
end
local function expect(verdict)
  local report = H.failed[1]
  print(report)
  assert(report and report:find("^TIMERIFT 0.12.0 " .. verdict), "expected " .. verdict .. ", got: " .. tostring(report))
end
local function done(name)
  print("max writes:", H.max_writes, "max instr:", H.max_instr)
  print("PASS time rifts 0.12.0 " .. name .. (MILEENA and " (map 132)" or " (map 110)"))
  os.exit(0)
end
local function near(a, b) return math.abs(a - b) < 0.01 end

stand(PX, PY, PZ); run(30)
assert(H.r8(0x005ACEDC) == 0, "no rift without walking up to the spot first")
assert(prompts == 0, "no prompt before the rift arms")
stand(PX + 1000, PY, PZ); run(10)
if MILEENA then pad_a = 0xFF end                         -- walk up holding A (a jump): not a press
stand(PX + 60, PY, PZ + 40); run(10)
if CASE == "once" then
  run(400)
  assert(H.r8(0x005ACEDC) == 0 and not streamed and not warped and prompts == 0 and #H.failed == 0,
    "a rift beaten on this save opened again")
  done("once")
end
if MILEENA then
  assert(H.r8(0x005ACEDC) == 0, "no reload in map 132")
  assert(pad_seen == 0 and not warped, "a held A is swallowed in front of the portal, but is no press")
  pad_a = 0; run(30)
  assert(prompts == 1 and prompt.text == 391 and prompt.kind == 4, "one messagetext call: the A icon (391), type 4")
  assert(H.r32(MESSAGES + 0x6D4) == 4, "the prompt is kept up while P1 stands there")
  assert(not warped and not reacted, "no rift without A")
  -- some momentum and a camera state, as the respawn teleport finds them
  H.w32(PLAYER + 0xD0, 0x42C80000); H.w32(PLAYER + 0x3184, 0x42C80000); H.w8(0x00599534, 7)
  pad_a = 0xFF; run(1)
  assert(pad_seen == 0, "the A that opens the rift doesn't jump")
  assert(reacted and reacted.count == 16 and reacted.anim == 0x26 and reacted.alt == 0x26 and reacted.rest == 0
    and reacted.kind == 0x72616863 and reacted.index == 0 and near(reacted.x, PX + 400) and near(reacted.z, PZ),
    "the pull-in: the portals' reaction 0x26 on char 0, turned by the wall")
  run(5)
  assert(pad_seen == 0, "A stays swallowed until it is let go")
  pad_a = 0; run(1); pad_a = 0xFF; run(1)
  assert(pad_seen == 0xFF, "after the rift opens, A jumps again")
  pad_a = 0
  if CASE ~= "stuck" then                                -- (stuck: no pull-in, the warp came 3 frames after A)
    run(60)
    assert(not warped, "the warp waits for the pull-in to end")
    run(30)
  end
  assert(warped and near(warped.x, ARRIVE[1]) and near(warped.y, ARRIVE[2] - 16) and near(warped.z, ARRIVE[3])
    and warped.w == 0, "set-position: P1 to the shrine deck, 16 above")
  assert(H.r32(PLAYER + 0xD0) == 0 and H.r32(PLAYER + 0x3184) == 0, "momentum cleared")
  assert(near(H.rf32(PLAYER + 0x94), -800.937), "P1 faces the way the deck spot was read")
  assert(H.r8(0x004E640C) == 1 and H.r8(0x00599534) == 0 and math.abs(H.rf32(0x004E641C) - 1 / 6) < 1e-6,
    "the camera told to cut")
else
  assert(H.r8(0x005ACEDC) == 1 and H.r32(0x004FC160) == 110 and H.r32(0x004FC164) == 1
    and H.r32(0x005ACEE0) == 0, "load request: the rift's map, entry 1, as loadmap writes it")
  assert(H.r8(PLAYER + 0x3217) == 1 and H.r8(PLAYER + 0x3238 + 0x3217) == 1, "both players marked as loading")
end
assert(not streamed, "nothing loads before the reload")

-- the reload: the preload runs, gameplay resumes at the arena's entrance
if not MILEENA then H.w32(STACK + 4, DESC); H.invoke(m, PRELOAD, { esp = STACK }, nil) end
if MILEENA then
  run(200)                                               -- P1 on the deck (stuck: still at the portal)
  assert(not streamed, "Mileena waits for P1 to come back to her arena")
  stand(SPOT[1] + 1600, SPOT[2], SPOT[3]); run(30)
  assert(not streamed, "1600 from her spot is not near enough")
  stand(SPOT[1] + 1400, SPOT[2], SPOT[3]); run(2)
else
  stand(PX + 1500, PY, PZ)
  run(30)
  assert(not streamed, "the boss loads after the arena settles")
  run(40)
end
local first = MILEENA and 66 or 30
-- map 110: the Orochi, 5 burning monks (77: loaded) and 3 priests (27: streamed in
-- after him, into slot 0); map 132: Mileena and 4 Tarkatans (14: loaded)
local boss_slot = MILEENA and 2 or 1
assert(stream_log[1] and stream_log[1].slot == boss_slot and stream_log[1].kind == first,
  "modelstream the boss first, into a slot nobody alive uses and no group authors, never its extras' (77)")
run(30)
assert(not started, "the group waits for the boss to finish loading")
for _ = 1, 50 do if started then break end; run(10) end     -- each load rests 90 frames
assert(started == 49, "rift group (the highest empty one) started: " .. tostring(started) .. " " .. tostring(H.failed[1]))
if MILEENA then
  assert(streams == 1, "the Tarkatans were loaded already")
else
  assert(streams == 2 and stream_log[2].slot == 0 and stream_log[2].kind == 27, "the priests streamed in after the Orochi, into slot 0")
end
local g = MANAGER + 49 * 0xA6C
local extras = MILEENA and { 14, 14, 14, 14 } or { 77, 77, 77, 77, 77, 27, 27, 27 }
assert(H.r16(g + 0xA68) == 1 + #extras and H.r32(g + 0x18) == first, "the boss's entry first, then its company")
for i, kind in ipairs(extras) do
  local e = g + 0x18 + i * 0x74
  assert(H.r32(e) == kind and H.r16(e + 0x5A) == i * 45 and H.r8(e + 0x58) == 1, "extra " .. i .. ": its type, 45 frames apart")
end
assert(H.r32(g + 0xA10) == MARK, "the boss's group carries the RIFT mark (LDK and Shuffle skip it)")
local function vanilla_header(g)
  return H.r32(g) == 0 and H.r16(g + 4) == 0x10 and H.r32(g + 8) == 4 and H.r32(g + 0xC) == 0
    and H.r16(g + 0x10) == 0xFFFF and H.r16(g + 0x12) == 0xFFFF and H.r16(g + 0x14) == 0xFFFF
end
assert(vanilla_header(g), "the group's header as a vanilla wave's (else its enemies never attack)")
assert(H.r32(g + 0x18 + 0x18) == (SPOT[1] & 0xFFFFFFFF) and H.r32(g + 0x18 + 0x1C) == ((SPOT[2] - 65) & 0xFFFFFFFF)
  and H.r32(g + 0x18 + 0x20) == (SPOT[3] & 0xFFFFFFFF), "integer world coordinates of the boss's spot, lifted 64")
for k = 0, 5 do
  assert(H.r8(MANAGER + k * 0xA6C + 0xA6A) == (MILEENA and 1 or 0),
    MILEENA and "the map's own groups stay on" or "the last map's groups are switched off")
end

run(20)
assert(#H.failed == 0, "a dead boss's leftover type is not a live boss: " .. tostring(H.failed[1]))
set_alive(4, first); H.wf32(PLAYER + 4 * 0x3238 + 0x84, SPOT[2] - 10)
H.w8(ACT[4] + 0xD4, 0)                                   -- its AI setup: can't die (MK bosses)
run(300)
assert(#H.failed == 0, "no report while the boss is up: " .. tostring(H.failed[1]))
assert(H.r8(ACT[4] + 0xD4) == 1, "the boss was left unkillable")
local function emptied() return H.r32(g + 0xA10) == 0 and H.r16(g + 0xA68) == 0 and H.r8(g + 0xA6A) == 0 end

if CASE == "beaten" or CASE == "stuck" then
  H.w32(ACT[4] + 0x368, 120)
  H.w32(STACK + 4, 0); H.invoke(m, SET_HEALTH, { ecx = ACT[4], esp = STACK }, nil)   -- the killing blow
  run(1)
  assert(#H.failed == 0, "reported in the verdict's own frame (its cleanup would be dropped)")
  assert(emptied(), "rift group not emptied")
  assert(H.r8(CLEARED) == (MILEENA and 0xA2 or 0xA1), "beaten rift not remembered in the save: " .. H.r8(CLEARED))
  run(1)
  expect("BEATEN")
  assert(H.failed[1]:find("killable@%+%d+"), "clearing the boss's can't-die flag not noted")
  if MILEENA then
    local stuck = CASE == "stuck"
    assert(H.failed[1]:find(stuck and "pull@%+3%(none,s=0%)" or "pull@%+9%d%(seen,s=0%)"), "the pull-in not noted")
    assert(H.failed[1]:find(stuck and "warp@%+0%(d=%d+%)" or "warp@%+0%(d=16%)"), "where set-position put P1 not noted")
    assert(H.failed[1]:find("near@%+%d+%(d=1400,a=%d+%)"), "P1's distances at the drop not noted")
  end
  done(CASE)
elseif CASE == "vanish" then
  H.w32(ACT[4] + 0x368, 450); run(1)                     -- hurt, then gone with health left
  set_alive(4, nil); run(1)
  if MILEENA then
    -- the next boss streams in: Johnny Cage, into the same group
    started = nil
    run(200)                                             -- the load, then its 90-frame rest
    assert(#H.failed == 0 and streams == 2 and streamed.kind == 78, "no fallback to Johnny Cage")
    assert(started == 49 and H.r32(g + 0x18) == 78 and H.r32(g + 0xA10) == MARK, "Johnny Cage not in the rift's group")
    done("vanish, next boss")
  end
  run(1)
  expect("VANISHED")
  assert(H.failed[1]:find("30 gone@%+%d+%(hp=450/600"), "the vanished boss's health not noted")
  assert(emptied() and H.r8(CLEARED) == 0, "a vanished boss: group not emptied, or remembered as beaten")
  done("vanish")
elseif CASE == "failed" then
  H.w32(ACT[0] + 0x368, 0); run(2)
  expect("FAILED")
  assert(emptied() and H.r8(CLEARED) == 0, "a failed rift: group not emptied, or remembered as beaten")
  done("failed")
elseif CASE == "left" then
  H.w32(MAP, 104); run(2)
  expect("LEFT")
  assert(emptied() and H.r8(CLEARED) == 0, "a left rift: group still marked, or remembered as beaten")
  done("left")
end
error("unknown case " .. CASE)
