-- Time Rifts 0.14.3, the postgame rifts (postgame.lua).
--   soul / soul_evicted / soul_failed: the Soul Tombs (map 4) -> Survival 10
--     (map 169) with both dragon clans added to its preload list; Shang
--     Tsung's own fight, then Goro (the slot holding block 1 unloaded, Goro
--     into slot 0) with Red Dragons, Kintaro with Black Dragons, the young
--     Shang Tsung with both. evicted: the clans are gone from the stage's
--     slots and each phase streams its own back. failed: P1 goes down in
--     Goro's fight and is sent back, FAILED.
--   shrine: the Champion Shrine (map 108) -> Survival 31 (map 190, entry 0):
--     the four fighters, then the Scorpions with zombies and skeletons, two
--     Sub-Zeros with Black Dragons, two Reptiles with shadows, two Ermacs with
--     priests, two Kanos with Red Dragons, two Goros; every missing type
--     streamed into a slot holding no one, Goro's run unloaded first.
--   Both: each phase drops from the stage's rift (where P1 landed, the
--   portal raised there too), and a slot is only streamed over once nobody of
--   its type has been up for 600 frames.
--   Both: closed until the gauntlet is beaten; the Survival portal's rings,
--   rays and red ring on the spot; the Black prompt once P1 has walked away
--   and back; the stage's way out held during the chain; bosses made
--   killable; the reward and the way back to the spot.
--   lua tests/postgame.lua ../time_rifts/pack/scripts/postgame.lua soul
package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m = H.load(arg[1])
local CASE = arg[2] or "soul"
local SHRINE = CASE == "shrine"

local GAMEPLAY, PRE_GATE, POST_GATE = 0x00154F60, 0x00012284, 0x00012C93
local INSTANCE, SINGLETON, VTABLE = 0x00589270, 0x005892A8, 0x00497C60
local VANILLA_SLOT, GATE_RET = 0x00013512, 0x000C753A
local START_GROUP, MODELSTREAM, PRELOAD, UNLOAD = 0x001D2600, 0x0017BA00, 0x00015DEE, 0x0017B280
local SET_POSITION, MESSAGETEXT, REACTION, ADDEXPERIENCE = 0x0015DC30, 0x00012847, 0x00016A00, 0x00013A53
local PARTICLES, PAD_MAP, PADS, MESSAGES, LOADMAP = 0x001582A0, 0x00129480, 0x0063AC20, 0x004E6E20, 0x00012883
local MAP, MANAGER, PLAYER = 0x00505970, 0x006DBFB0, 0x005D1AB8
local LOAD_REQUEST, LOAD_MAP, LOAD_ENTRY = 0x005ACEDC, 0x004FC160, 0x004FC164
local E0, STACK = 0xD005FC5C, 0xD00F0000
local MGR, FLAGS, NONE = 0x81100000, 0x81000000, 0xFFFFFFFF
local R = SHRINE and {
  entrance = 108, spot = { 1403.788, -1010.621, 32438.879 }, stage = 190, entry = 0, desc = 0x00501118,
  list = { 59, 68, 69, 52, NONE, NONE }, cap = 4, slots = { 59, 68, 69, 52 }, first = { 59, 68, 69, 52 },
  reward = "Reward: 20,000 experience", xp = 20000,
  phases = { { bosses = { 55, 52 }, extras = { 8, 8, 8, 4, 4, 4 } }, { bosses = { 69, 69 }, extras = { 9, 9, 9, 9 } },
             { bosses = { 59, 59 }, extras = { 17, 17, 17, 17 } }, { bosses = { 68, 68 }, extras = { 27, 27, 27, 27 } },
             { bosses = { 54, 54 }, extras = { 16, 16, 16, 16 } }, { bosses = { 57, 57 }, extras = {} } },
} or {
  entrance = 4, spot = { -613.910, -47.872, 8419.954 }, stage = 169, entry = 1, desc = 0x005002B8,
  list = { 63, 27, NONE, NONE, 0x55555555, 0x55555555 }, cap = 2, slots = { 27, 63, 16, 9 }, first = { 63, 27 },
  reward = "Reward: 15,000 experience", xp = 15000,
  phases = { { bosses = { 57 }, extras = { 16, 16, 16, 16 } }, { bosses = { 58 }, extras = { 9, 9, 9, 9 } },
             { bosses = { 62 }, extras = { 16, 16, 9, 9 } } },
}

H.w32(INSTANCE, SINGLETON); H.w32(SINGLETON, VTABLE); H.w32(VTABLE + 0x18, VANILLA_SLOT)
H.w32(MAP, R.entrance)
H.w32(0x005ACEBC, MGR)
H.w32(0x0051004C, FLAGS)
local function actor(i) return 0x81200000 + i * 0x1000 end
for i = 0, 11 do
  H.w16(FLAGS + i * 2, i < 2 and 1 or 0); H.w16(PLAYER + i * 0x3238 + 0x1DFE, i)
  H.w32(PLAYER + i * 0x3238 + 0x200, actor(i)); H.w32(actor(i) + 0x368, 600); H.w8(actor(i) + 0xD4, 1)
end
local function set_alive(i, kind) H.w16(FLAGS + i * 2, kind and 1 or 0); if kind then H.w16(PLAYER + i * 0x3238 + 0x1DFE, kind) end end
H.w32(R.desc + 0x20, R.cap)
for i, w in ipairs(R.list) do H.w32(R.desc + 0x24 + (i - 1) * 4, w) end
local SLOTS, ROWS, BLOCKS, LOADED = 0x006322F8, 0x81001000, 0x81002000, 0x006CA69C
H.w32(SLOTS + 0x08, 4); H.w32(SLOTS + 0x10, 4); H.w32(SLOTS + 0x1C, BLOCKS); H.w32(SLOTS + 0x24, ROWS)
local function load_stage()
  for i, kind in ipairs(R.slots) do
    H.w32(ROWS + (i - 1) * 20 + 4, kind); H.w32(ROWS + (i - 1) * 20 + 8, i - 1); H.w32(ROWS + (i - 1) * 20 + 0xC, 1)
    H.w32(BLOCKS + (i - 1) * 20 + 4, kind); H.w32(BLOCKS + (i - 1) * 20 + 0x10, 6)
    H.w32(LOADED + (i + 1) * 4, kind)
  end
  H.w32(LOADED, 0); H.w32(LOADED + 4, 1)
end
for t = 0, 90 do H.w32(0x004FA9F0 + t * 0x30 + 4, t == 57 and 2 or 1) end
local function unload(slot)
  local kind = H.r32(ROWS + slot * 20 + 4)
  if kind == NONE then return end
  for b = 0, (kind == 57 and 2 or 1) - 1 do
    H.w32(BLOCKS + (slot + b) * 20 + 4, NONE); H.w32(BLOCKS + (slot + b) * 20 + 0x10, 4)
  end
  H.w32(ROWS + slot * 20 + 4, NONE); H.w32(LOADED + (2 + slot) * 4, NONE)
end
local LIST, TEXTS = 0x81300000, 0x81310000
H.w32(0x005B04A4, LIST); H.w32(0x005AC508, 800)
local function put(addr, s) for k = 1, #s do H.w8(addr + k - 1, s:byte(k)) end; H.w8(addr + #s, 0) end
H.w32(LIST, TEXTS); put(TEXTS, "= Exit")
H.w32(LIST + 34 * 4, TEXTS + 0x200); put(TEXTS + 0x200, "Raiden:\nTutorial Message 13.")
H.w32(LIST + 35 * 4, TEXTS + 0x280)
local function slot_text()
  local o, a = {}, TEXTS + 0x200
  while H.r8(a) ~= 0 do o[#o + 1] = string.char(H.r8(a)); a = a + 1 end
  return table.concat(o)
end
H.w32(MESSAGES + 0x6D4, NONE)
local function stand(x, y, z) H.wf32(PLAYER + 0x80, x); H.wf32(PLAYER + 0x84, y); H.wf32(PLAYER + 0x88, z) end
local SPOT = R.spot

local frames, react_until = 0, nil
local shown, streams, unloads, started, effects, xp, warped, reacted = {}, {}, {}, 0, {}, nil, nil, nil
local loads = {}
local behaviour = {
  [VANILLA_SLOT] = { pop = 0, run = function(ctx) end },
  [MESSAGETEXT] = { pop = 12, run = function(ctx)
      local a = H.r32(H.r32(ctx.esp + 4) + 8)
      local text, kind = H.r32(a), H.r32(a + 4)
      shown[#shown + 1] = { text = text, kind = kind, line = text == 34 and slot_text() or nil }
      H.w32(MESSAGES + 0x6D4, kind); H.w32(MESSAGES + 0x6F0, kind == 5 and 300 or 30)
    end },
  [REACTION] = { pop = 12, run = function(ctx) reacted = true; H.w32(PLAYER + 0x1E04, 0xC); react_until = frames + 90 end },
  [PARTICLES] = { pop = 12, run = function(ctx)
      local args, from = H.r32(H.r32(ctx.esp + 4) + 8), H.r32(ctx.esp + 12)
      effects[#effects + 1] = { bank = H.r32(args), id = H.r32(args + 4), life = H.r32(args + 8), pack = H.r32(args + 24), ecx = ctx.ecx,
                                x = H.rf32(from + 4), z = H.rf32(from + 12) }
    end },
  [ADDEXPERIENCE] = { pop = 12, run = function(ctx)
      xp = { amount = H.r32(H.r32(H.r32(ctx.esp + 4) + 8)), index = H.r32(H.r32(ctx.esp + 8) + 0x10) }
    end },
  [SET_POSITION] = { pop = 4, run = function(ctx)
      local v = H.r32(ctx.esp + 4)
      warped = { x = H.rf32(v), y = H.rf32(v + 4), z = H.rf32(v + 8) }
      stand(warped.x, warped.y, warped.z)
    end },
  [UNLOAD] = { pop = 0, run = function(ctx) local s = H.r32(ctx.esp + 4); unloads[#unloads + 1] = s; unload(s) end },
  [MODELSTREAM] = { pop = 12, run = function(ctx)
      local args = H.r32(H.r32(ctx.esp + 4) + 8)
      local slot, kind = H.r32(args), H.r32(args + 4)
      streams[#streams + 1] = { slot = slot, kind = kind }
      unload(slot)
      for b = 0, (kind == 57 and 2 or 1) - 1 do
        assert(H.r32(BLOCKS + (slot + b) * 20 + 0x10) == 4, "a stream into a block that isn't free: " .. kind .. " slot " .. slot)
        H.w32(BLOCKS + (slot + b) * 20 + 4, kind); H.w32(BLOCKS + (slot + b) * 20 + 0x10, 6)
      end
      H.w32(ROWS + slot * 20 + 4, kind)
      loads[#loads + 1] = { at = frames + 60, index = 2 + slot, kind = kind }
    end },
  [START_GROUP] = { pop = 12, run = function(ctx) started = started + 1 end },
}
local pad_black, pad_seen = 0, nil
local function frame()
  H.w8(PADS + 6, pad_black)
  H.invoke(m, PAD_MAP, { eax = PADS, esp = E0 - 4 }, nil)
  pad_seen = H.r8(PADS + 6)
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
  if H.r32(MESSAGES + 0x6D4) ~= NONE then
    local t = H.r32(MESSAGES + 0x6F0)
    if t <= 1 then H.w32(MESSAGES + 0x6D4, NONE) else H.w32(MESSAGES + 0x6F0, t - 1) end
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
local function load_map(map) H.w8(LOAD_REQUEST, 0); H.w32(MAP, map); H.w32(MESSAGES + 0x6D4, NONE); run(1) end
local function last_line() for i = #shown, 1, -1 do if shown[i].line then return shown[i].line end end end
local function group_types()
  local g, t = MANAGER + 49 * 0xA6C, {}
  for i = 0, H.r16(g + 0xA68) - 1 do t[#t + 1] = H.r32(g + 0x18 + i * 0x74) end
  return t
end
local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end
local function until_started(n)
  local s0 = started
  for _ = 1, 3000 do
    if started > s0 or #H.failed > 0 then run(2) return end
    run(1)
  end
  error("no group started in phase " .. n .. ": " .. tostring(H.failed[1]))
end

-- closed until the gauntlet is beaten
stand(SPOT[1] + 1000, SPOT[2], SPOT[3]); run(100)
stand(SPOT[1] + 50, SPOT[2], SPOT[3]); run(100)
assert(#shown == 0 and #effects == 0, "no rift before the gauntlet is beaten")
H.w8(MGR + 0x1C4 + 22, 0xB0)
load_map(0); load_map(R.entrance)
stand(SPOT[1] + 1000, SPOT[2], SPOT[3]); run(80)
assert(#effects == 3, "the Survival portal's three effects")
for i, want in ipairs({ { 0, 109 }, { 3, 105 }, { 3, 48 } }) do
  local e = effects[i]
  assert(e.bank == want[1] and e.id == want[2] and e.pack == 1 and e.ecx == 0x0050FFD0
    and math.abs(e.x - SPOT[1]) < 0.01 and math.abs(e.z - SPOT[3]) < 0.01, "effect " .. want[2] .. " on the spot")
end
stand(SPOT[1] + 50, SPOT[2], SPOT[3]); run(10)
assert(#shown == 1 and shown[1].text == 60 and shown[1].kind == 4, "the Black prompt on the spot")
pad_black = 0xFF; run(1); pad_black = 0
assert(pad_seen == 0 and reacted, "Black swallowed, the pull-in plays")
run(92)
assert(H.r8(LOAD_REQUEST) == 1 and H.r32(LOAD_MAP) == R.stage and H.r32(LOAD_ENTRY) == R.entry, "the load into the stage")
H.w32(STACK + 4, R.desc); H.invoke(m, PRELOAD, { esp = STACK }, nil)
if SHRINE then
  assert(H.r32(R.desc + 0x34) == NONE and H.r32(R.desc + 0x20) == 4, "Survival 31's list is left as it is")
else
  assert(H.r32(R.desc + 0x2C) == 16 and H.r32(R.desc + 0x30) == 9 and H.r32(R.desc + 0x34) == NONE
    and H.r32(R.desc + 0x20) == 4, "both dragon clans added to Survival 10's preload list")
end
load_stage(); load_map(R.stage)
if CASE == "soul_evicted" then
  for _, s in ipairs({ 2, 3 }) do unload(s) end
end
-- the stage's own fight, then quiet
for i, kind in ipairs(R.first) do set_alive(2 + i, kind) end
run(200)
assert(#streams == 0, "nothing streams while the stage's own fight runs")
for i = 1, #R.first do set_alive(2 + i, nil) end
run(140)
assert(#streams == 0, "not before the stage has been quiet a while")
run(200)
assert(last_line() and last_line():find("The rift isn't done with you", 1, true), "Smoke's line before the chain")
assert(#effects == 6, "the stage's rift flashes where P1 landed")
local rift_spot = { H.rf32(PLAYER + 0x80), H.rf32(PLAYER + 0x88) }
for i = 1, 3 do assert(effects[i].pack == 1 and effects[i].life == 0, "the entrance's portal stays up") end
for i = 4, 6 do
  assert(effects[i].pack == 0 and effects[i].life == 150 and math.abs(effects[i].x - rift_spot[1]) < 0.01
    and math.abs(effects[i].z - rift_spot[2]) < 0.01, "a 150-frame flash where P1 landed")
end
stand(rift_spot[1] + 2500, SPOT[2], rift_spot[2] + 2500)       -- P1 fights away from the rift
for n, p in ipairs(R.phases) do
  until_started(n)
  run(4)
  assert(#effects == 6 + 3 * n and effects[#effects].life == 150, "phase " .. n .. " drops out of a flash of the rift")
  local g0 = MANAGER + 49 * 0xA6C
  assert(H.r32(g0 + 0x18 + 0x18) == (math.floor(rift_spot[1] + 0.5) & 0xFFFFFFFF), "phase " .. n .. " drops from the rift, not on P1")
  local t = group_types()
  local want = {}
  for _, k in ipairs(p.bosses) do want[#want + 1] = k end
  for _, k in ipairs(p.extras) do want[#want + 1] = k end
  assert(same(t, want), "phase " .. n .. "'s group: " .. table.concat(t, ",") .. " (wanted " .. table.concat(want, ",") .. ")")
  local g = MANAGER + 49 * 0xA6C
  assert(H.r32(g + 0xA10) == 0x54464952, "the group is marked RIFT")
  for i, k in ipairs(p.bosses) do
    set_alive(5 + i, k); H.w8(actor(5 + i) + 0xD4, 0)
  end
  run(5)
  for i in ipairs(p.bosses) do assert(H.r8(actor(5 + i) + 0xD4) == 1, "phase " .. n .. "'s bosses made killable") end
  if n == 1 then
    H.w32(STACK + 4, 0x81500000)
    H.invoke(m, LOADMAP, { esp = STACK }, function() H.w8(LOAD_REQUEST, 1); H.w8(PLAYER + 0x3217, 1) end)
    assert(H.r8(LOAD_REQUEST) == 0 and H.r8(PLAYER + 0x3217) == 0, "the stage's way out stays shut during the chain")
    if CASE == "soul_failed" then
      H.w32(actor(0) + 0x368, 0); run(200)
      assert(H.r32(LOAD_MAP) == R.entrance and H.r8(LOAD_REQUEST) == 1, "P1 down: the way back")
      load_map(R.entrance); run(80)
      local report = H.failed[1]
      print(report)
      assert(report and report:find("^POSTGAME 0.14.3 soul FAILED") and report:find("p1 down"), "expected FAILED, got: " .. tostring(report))
      assert(H.r32(R.desc + 0x2C) == NONE and H.r32(R.desc + 0x20) == 2, "the stage's list as authored again")
      print("PASS time rifts 0.14.3 postgame soul_failed")
      return
    end
  end
  run(30)
  for i in ipairs(p.bosses) do set_alive(5 + i, nil) end      -- beaten, bodies gone
  run(40)
end
run(200)
assert(last_line():find(R.reward, 1, true), "the reward line: " .. last_line())
assert(xp and xp.amount == R.xp and xp.index == 0, "the XP to player 1")
assert(#effects == 9 + 3 * #R.phases and effects[#effects].life == 150, "the rift flashes once more when the chain is won")
run(260)
assert(H.r32(LOAD_MAP) == R.entrance and H.r8(LOAD_REQUEST) == 1, "the way back to the entrance")
load_map(R.entrance); run(80)
assert(warped and math.abs(warped.x - SPOT[1]) < 0.01 and math.abs(warped.z - SPOT[3]) < 0.01, "P1 put on the spot")
run(2)
local report = H.failed[1]
print(report)
assert(report and report:find("^POSTGAME 0.14.3 " .. (SHRINE and "shrine" or "soul") .. " BEATEN"), "expected BEATEN, got: " .. tostring(report))
assert(report:find("exit=held") and report:find("p" .. #R.phases .. " beaten"), "the chain noted")
-- a type that held a slot in the stage only ever streams back into it
local homes = {}
for i, kind in ipairs(R.slots) do homes[kind] = i - 1 end
for _, s in ipairs(streams) do
  if homes[s.kind] then
    assert(s.slot == homes[s.kind], "type " .. s.kind .. " streamed into slot " .. s.slot .. ", its home is " .. homes[s.kind])
  else
    homes[s.kind] = s.slot
  end
end
if SHRINE then
  assert(streams[1].kind == 52 and streams[1].slot == 3, "the stage's Scorpion streamed again into his own slot first")
  local goro = streams[#streams]
  assert(goro.kind == 57 and goro.slot == 0 and #unloads >= 1, "Goro into slot 0 after his run was unloaded")
else
  assert(H.r32(R.desc + 0x2C) == NONE and H.r32(R.desc + 0x34) == 0x55555555 and H.r32(R.desc + 0x20) == 2,
    "the stage's list as authored again")
end
print("streams:", #streams, "max writes:", H.max_writes, "max instr:", H.max_instr)
print("PASS time rifts 0.14.3 postgame " .. CASE)
