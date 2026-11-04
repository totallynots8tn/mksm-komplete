-- Time Rifts 0.12.0, Goro's Lair (map 102): the A prompt, the pull-in, the
-- reload (entry 1), set-position back to the spot, Raiden's line written over
-- the unused text 34 and shown as a speaker line (type 5), then the rush:
-- 3 enemies of the loaded types (Oni 15, Tarkatan 14) with 2 clones each,
-- written over two frames; once the wave has run and none are left, Goro:
-- slot 1 unloaded, Goro streamed into slot 0 (two memory blocks), his fight,
-- then Oni and Tarkatan streamed back once his body is gone, then BEATEN.
-- Emulates the call gate, the text table (128-byte string slots), memory
-- slots and blocks, the spawn manager's running group and the entities.
-- Cases: beaten (Spanish text), english, noroom (packed strings: no line,
-- the rush still comes), failed (P1 goes down in the rush), nogoro (one
-- block with memory: no Goro, BEATEN after the rush).
--   lua tests/time_rifts_rush.lua ../time_rifts/pack/scripts/time_rifts.lua [case]
package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m = H.load(arg[1])
local CASE = arg[2] or "beaten"

local GAMEPLAY, PRE_GATE, POST_GATE = 0x00154F60, 0x00012284, 0x00012C93
local INSTANCE, SINGLETON, VTABLE = 0x00589270, 0x005892A8, 0x00497C60
local VANILLA_SLOT, GATE_RET = 0x00013512, 0x000C753A
local START_GROUP, MODELSTREAM, PRELOAD = 0x001D2600, 0x0017BA00, 0x00015DEE
local SET_POSITION, MESSAGETEXT, PAD_MAP, PADS, MESSAGES = 0x0015DC30, 0x00012847, 0x00129480, 0x0063AC20, 0x004E6E20
local REACTION, UNLOAD, SET_HEALTH = 0x00016A00, 0x0017B280, 0x00153CD0
local MAP, MANAGER, PLAYER, DESC = 0x00505970, 0x006DBFB0, 0x005D1AB8, 0x004FEE98
local E0, STACK = 0xD005FC5C, 0xD00F0000
local SPOT = { 6666.973, -190.785, -5098.718 }
local MGR = 0x81100000
local CLEARED = MGR + 0x1C4 + 22
local FLAGS = 0x81000000

H.w32(INSTANCE, SINGLETON); H.w32(SINGLETON, VTABLE); H.w32(VTABLE + 0x18, VANILLA_SLOT)
H.w32(MAP, 102)
H.w32(DESC + 0x7C, 0xBA3)                                -- map 102 has its own spawn groups
H.w32(0x005ACEBC, MGR)
H.w32(0x0051004C, FLAGS)
for i = 0, 11 do
  H.w16(FLAGS + i * 2, i < 2 and 1 or 0); H.w16(PLAYER + i * 0x3238 + 0x1DFE, i)
  H.w32(PLAYER + i * 0x3238 + 0x200, 0x81200000 + i * 0x1000); H.w32(0x81200000 + i * 0x1000 + 0x368, 600)
end
local function set_alive(i, kind) H.w16(FLAGS + i * 2, kind and 1 or 0); if kind then H.w16(PLAYER + i * 0x3238 + 0x1DFE, kind) end end
-- map 102 as read live: two memory slots, Oni and Tarkatan, each in one of
-- the two blocks that have memory (blocks 2 and 3 have none)
local SLOTS, ROWS, BLOCKS, LOADED = 0x006322F8, 0x81001000, 0x81002000, 0x006CA69C
H.w32(SLOTS + 0x08, CASE == "nogoro" and 1 or 4); H.w32(SLOTS + 0x10, 2)
H.w32(SLOTS + 0x1C, BLOCKS); H.w32(SLOTS + 0x24, ROWS)
for i, kind in ipairs({ 15, 14, 0xFFFFFFFF, 0xFFFFFFFF }) do
  H.w32(ROWS + (i - 1) * 20 + 4, kind); H.w32(ROWS + (i - 1) * 20 + 8, i - 1); H.w32(ROWS + (i - 1) * 20 + 0xC, 1)
  H.w32(BLOCKS + (i - 1) * 20 + 4, kind); H.w32(BLOCKS + (i - 1) * 20 + 0x10, i <= 2 and 6 or 0)
end
-- Shuffle's outsider in slot 2: a tree mouth, which the rush must leave out
for i, kind in ipairs({ 0, 1, 15, 14, 42, 0xFFFFFFFF }) do H.w32(LOADED + (i - 1) * 4, kind) end
H.w32(0x004FA9F0 + 57 * 0x30 + 4, 2)                     -- Goro needs two memory blocks (character table)
local streams, unloaded, loads = {}, nil, {}
-- what 0x17B280 does to a slot: its blocks free, its loaded entry gone
local function unload(slot)
  local kind = H.r32(ROWS + slot * 20 + 4)
  if kind == 0xFFFFFFFF then return end
  for b = 0, (kind == 57 and 2 or 1) - 1 do
    H.w32(BLOCKS + (slot + b) * 20 + 4, 0xFFFFFFFF); H.w32(BLOCKS + (slot + b) * 20 + 0x10, 4)
  end
  H.w32(ROWS + slot * 20 + 4, 0xFFFFFFFF); H.w32(LOADED + (2 + slot) * 4, 0xFFFFFFFF)
end
for g = 1, 16 do                                         -- the map's own groups (cleared)
  H.w16(MANAGER + g * 0xA6C + 0xA68, g < 15 and 1 or 2); H.w8(MANAGER + g * 0xA6C + 0xA6A, 1)
end
-- the text table: 128-byte slots (as the Spanish pack loads it), or packed
local TEXT_PTRS, LIST, TEXTS = 0x005B04A4, 0x81300000, 0x81310000
H.w32(TEXT_PTRS, LIST); H.w32(0x005AC508, 1751)
local function put(addr, s) for k = 1, #s do H.w8(addr + k - 1, s:byte(k)) end; H.w8(addr + #s, 0) end
local first_text = CASE == "english" and "= Exit" or "= Salir"
local vanilla34 = CASE == "english" and "Raiden:\nTutorial Message 13." or "Raiden:\nMensaje de tutorial 13."
local slot = CASE == "noroom" and (#vanilla34 + 9) or 128
H.w32(LIST, TEXTS); put(TEXTS, first_text)
H.w32(LIST + 34 * 4, TEXTS + 0x200); put(TEXTS + 0x200, vanilla34)
H.w32(LIST + 35 * 4, TEXTS + 0x200 + slot); put(TEXTS + 0x200 + slot, "Raiden:\nTutorial 14.")
H.w32(MESSAGES + 0x6D4, 0xFFFFFFFF)
local function stand(x, y, z) H.wf32(PLAYER + 0x80, x); H.wf32(PLAYER + 0x84, y); H.wf32(PLAYER + 0x88, z) end

local frames, react_until = 0, nil
local load_request, started, warped, reacted = nil, nil, nil, nil
local messages = {}
local behaviour = {
  [VANILLA_SLOT] = { pop = 0, run = function(ctx) end },
  [MESSAGETEXT] = { pop = 12, run = function(ctx)
      local args = H.r32(H.r32(ctx.esp + 4) + 8)
      messages[#messages + 1] = { text = H.r32(args), kind = H.r32(args + 4) }
      if H.r32(args + 4) == 4 then H.w32(MESSAGES + 0x6D4, 4); H.w32(MESSAGES + 0x6F0, 30) end
    end },
  [REACTION] = { pop = 12, run = function(ctx)
      reacted = true; H.w32(PLAYER + 0x1E04, 0xC); react_until = frames + 90
    end },
  [SET_POSITION] = { pop = 4, run = function(ctx)
      local v = H.r32(ctx.esp + 4)
      warped = { x = H.rf32(v), y = H.rf32(v + 4), z = H.rf32(v + 8) }
      stand(warped.x, warped.y, warped.z)
    end },
  [UNLOAD] = { pop = 0, run = function(ctx) unloaded = H.r32(ctx.esp + 4); unload(unloaded) end },
  [MODELSTREAM] = { pop = 12, run = function(ctx)
      local args = H.r32(H.r32(ctx.esp + 4) + 8)
      local slot, kind = H.r32(args), H.r32(args + 4)
      streams[#streams + 1] = { slot = slot, kind = kind }
      unload(slot)                                       -- a stream unloads the slot first
      for b = 0, (kind == 57 and 2 or 1) - 1 do
        assert(H.r32(BLOCKS + (slot + b) * 20 + 0x10) == 4, "a stream into a block that isn't free")
        H.w32(BLOCKS + (slot + b) * 20 + 4, kind); H.w32(BLOCKS + (slot + b) * 20 + 0x10, 6)
      end
      H.w32(ROWS + slot * 20 + 4, kind)
      loads[#loads + 1] = { at = frames + 60, index = 2 + slot, kind = kind }
    end },
  [START_GROUP] = { pop = 12, run = function(ctx)
      assert(ctx.ecx == MANAGER and H.r32(ctx.esp + 8) == 0xFFFFFFFF, "started like callspawn")
      started = H.r32(ctx.esp + 4)
    end },
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
local function near(a, b) return math.abs(a - b) < 0.01 end
local function done()
  print(H.failed[1])
  print("max writes:", H.max_writes, "max instr:", H.max_instr)
  print("PASS time rifts 0.12.0 rush " .. CASE .. " (map 102)")
  os.exit(0)
end

-- walk up to the spot: the prompt; A pulls P1 in, then the arena reloads
stand(SPOT[1] + 1000, SPOT[2], SPOT[3]); run(10)
stand(SPOT[1] + 50, SPOT[2], SPOT[3]); run(10)
assert(#messages == 1 and messages[1].text == 391 and messages[1].kind == 4, "the A prompt at the spot")
pad_a = 0xFF; run(1); pad_a = 0
assert(pad_seen == 0 and reacted, "A swallowed, the pull-in plays")
run(100)
assert(H.r8(0x005ACEDC) == 1 and H.r32(0x004FC160) == 102 and H.r32(0x004FC164) == 1, "the arena reloads: map 102, entry 1")
assert(not warped, "nothing moves P1 before the reload")
-- the reload: the preload runs, P1 is at the map's entry
H.w8(0x005ACEDC, 0)
H.w32(STACK + 4, DESC); H.invoke(m, PRELOAD, { esp = STACK }, nil)
stand(100, -190, 100)
run(59)
assert(not warped, "P1 is put back once the arena settles")
run(2)
assert(warped and near(warped.x, SPOT[1]) and near(warped.y, SPOT[2] - 16) and near(warped.z, SPOT[3]), "back to the spot")
assert(near(H.rf32(PLAYER + 0x94), -585.0), "facing as read")
run(61)
-- Raiden's line
local p34 = TEXTS + 0x200
if CASE == "noroom" then
  assert(#messages == 1, "no room: no line")
  local s = {}
  for k = 0, #vanilla34 - 1 do s[#s + 1] = string.char(H.r8(p34 + k)) end
  assert(table.concat(s) == vanilla34, "no room: text 34 left alone")
else
  assert(#messages == 2 and messages[2].text == 34 and messages[2].kind == 5, "Raiden's line: text 34 as a speaker line")
  local s = {}
  for k = 0, 127 do local c = H.r8(p34 + k); if c == 0 then break end; s[#s + 1] = string.char(c) end
  local line = table.concat(s)
  assert(line:sub(1, 8) == "Raiden:\n", "a Raiden line")
  if CASE == "english" then
    assert(line:find("Rifts are opening"), "English line: " .. line)
  else
    assert(line:find("Shang Tsung") and line:find("\xA1Prep\xE1rate"), "Spanish line in cp1252: " .. line)
  end
  assert(H.r8(p34 + #line) == 0 and H.r8(p34 + 127) == 0, "NUL-terminated inside the slot")
  assert(H.r8(p34 + 128) == string.byte("R"), "text 35 untouched")
end
-- the rush comes 240 frames after the line
run(200)
assert(not started, "the rush waits for Raiden")
run(50)
assert(started == 49, "the rush group (the highest empty one) started: " .. tostring(started) .. " " .. tostring(H.failed[1]))
local g = MANAGER + 49 * 0xA6C
assert(H.r16(g + 0xA68) == 9 and H.r32(g + 0xA10) == 0x54464952 and H.r8(g + 0xA6A) == 1, "9 entries, marked as the rift's")
local function vanilla_header(g)
  return H.r32(g) == 0 and H.r16(g + 4) == 0x10 and H.r32(g + 8) == 4 and H.r32(g + 0xC) == 0
    and H.r16(g + 0x10) == 0xFFFF and H.r16(g + 0x12) == 0xFFFF and H.r16(g + 0x14) == 0xFFFF
end
assert(vanilla_header(g), "the rush group's header as a vanilla wave's (else its enemies never attack)")
local want = { 15, 14, 15, 15, 14, 15, 15, 14, 15 }
for i = 1, 9 do
  local e = g + 0x18 + (i - 1) * 0x74
  assert(H.r32(e) == want[i] and H.r16(e + 0x5A) == (i - 1) * 20, "rush entry " .. i .. ": loaded types in turn, 20 frames apart")
  assert(H.r32(e + 0x1C) == (math.floor(SPOT[2] - 64) & 0xFFFFFFFF), "dropped 64 above the spot")
end
for k = 1, 16 do assert(H.r8(MANAGER + k * 0xA6C + 0xA6A) == 1, "the map's own groups stay on") end
-- the wave runs: the manager spawns all 9 (some alive at a time)
H.w8(MANAGER + 0x2092A, 1); H.w16(MANAGER + 0x20920, 49)
for n = 1, 9 do
  H.w16(MANAGER + 0x20922, n); set_alive(2 + (n - 1) % 8, want[n]); run(20)
end
assert(#H.failed == 0, "no verdict while the wave runs")
if CASE == "failed" then
  H.w32(0x81200000 + 0x368, 0); run(2)
  assert(H.failed[1] and H.failed[1]:find("^TIMERIFT 0.12.0 FAILED"), "P1 down: FAILED")
  done()
end
-- all dead, the manager clears the group: now Goro
for i = 2, 9 do set_alive(i, nil) end
H.w8(MANAGER + 0x2092A, 0)
run(5)
if CASE == "nogoro" then
  assert(H.failed[1] and H.failed[1]:find("^TIMERIFT 0.12.0 BEATEN") and H.failed[1]:find("57=noroom"),
    "no room for Goro: BEATEN after the rush, got: " .. tostring(H.failed[1]))
  assert(#streams == 0 and not unloaded, "nothing unloaded or streamed without the room")
  done()
end
assert(#H.failed == 0, "no verdict before Goro: " .. tostring(H.failed[1]))
assert(unloaded == 1, "slot 1 (the Tarkatan's block) unloaded for Goro's second block")
assert(#streams == 1 and streams[1].slot == 0 and streams[1].kind == 57, "Goro streamed into slot 0")
run(160)                                                        -- his load, then the rest
assert(H.r16(g + 0xA68) == 1 and H.r32(g + 0x18) == 57 and H.r32(g + 0xA10) == 0x54464952, "Goro's group: one entry, the rift's")
local goro = 0x81200000 + 4 * 0x1000
set_alive(4, 57); H.w8(goro + 0xD4, 0); run(10)
assert(H.r8(goro + 0xD4) == 1, "Goro made killable")
H.w32(STACK + 4, 0); H.invoke(m, SET_HEALTH, { ecx = goro, esp = STACK }, nil); run(30)
assert(#H.failed == 0 and #streams == 1, "the map's types wait for Goro's body to go")
set_alive(4, nil); run(2)
assert(#streams == 2 and streams[2].slot == 0 and streams[2].kind == 15, "the Oni back into slot 0")
run(155)
assert(#streams == 3 and streams[3].slot == 1 and streams[3].kind == 14, "the Tarkatan back into slot 1")
run(155)
assert(H.failed[1] and H.failed[1]:find("^TIMERIFT 0.12.0 BEATEN"), "expected BEATEN, got: " .. tostring(H.failed[1]))
assert(H.failed[1]:find("rush9/9@%+%d+") and H.failed[1]:find("unload1%(14%)") and H.failed[1]:find("57 beaten@")
  and H.failed[1]:find("restored@"), "the rush, the unload, Goro and the restore not noted")
assert(H.r32(LOADED + 2 * 4) == 15 and H.r32(LOADED + 3 * 4) == 14, "the map's types are back")
assert(H.failed[1]:find(CASE == "noroom" and "raiden=noroom" or "raiden@%+0"), "Raiden's line not noted")
assert(H.r8(CLEARED) == 0xA4, "beaten rift (bit 2) not remembered in the save: " .. H.r8(CLEARED))
done()
