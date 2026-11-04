-- Time Rifts 0.12.0, the Survival gauntlet (Smoke's secret area, map 146).
--   beaten: Smoke's rift line (Spanish), the A prompt once P1 has walked
--     away and back, the pull-in, the load into Survival 2 (161, entry 1),
--     each stage's way out pointed at the next stage's entry (Survival 31 at
--     entry 0, the stage's own reload left alone), a stage left on idle,
--     then back to Smoke (146, entry 2): his reward line, 10,000 XP, bit 4.
--   portal: the rift open, Smoke's own portal (loadmap 75, the Pit II) goes
--     into the gauntlet instead (English lines); another map than the next
--     stage ends the run: LEFT.
--   closed: the Pit II not beaten on this save: no line, no prompt, the
--     portal still loads the Pit II.
--   lua tests/gauntlet.lua ../time_rifts/pack/scripts/gauntlet.lua beaten
package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m = H.load(arg[1])
local CASE = arg[2] or "beaten"

local GAMEPLAY, PRE_GATE, POST_GATE = 0x00154F60, 0x00012284, 0x00012C93
local INSTANCE, SINGLETON, VTABLE = 0x00589270, 0x005892A8, 0x00497C60
local VANILLA_SLOT, GATE_RET = 0x00013512, 0x000C753A
local MESSAGETEXT, REACTION, ADDEXPERIENCE, LOADMAP = 0x00012847, 0x00016A00, 0x00013A53, 0x00012883
local PAD_MAP, PADS, MESSAGES = 0x00129480, 0x0063AC20, 0x004E6E20
local MAP, MANAGER, PLAYER = 0x00505970, 0x006DBFB0, 0x005D1AB8
local LOAD_REQUEST, LOAD_PORTAL, LOAD_MAP, LOAD_ENTRY = 0x005ACEDC, 0x005ACEE0, 0x004FC160, 0x004FC164
local E0, STACK = 0xD005FC5C, 0xD00F0000
local PORTAL = { 105810.266, -1427.247, 63.655 }
local MGR, FLAGS = 0x81100000, 0x81000000
local LIST, SLOT34 = 0x81400000, 0x81401000
local DEF, ARGS = 0x81300000, 0x81300100
local STAGES = { { 161, 1 }, { 162, 1 }, { 163, 1 }, { 165, 1 }, { 166, 1 }, { 187, 1 }, { 191, 1 }, { 190, 0 }, { 169, 1 } }

H.w32(INSTANCE, SINGLETON); H.w32(SINGLETON, VTABLE); H.w32(VTABLE + 0x18, VANILLA_SLOT)
H.w32(MAP, 146)
H.w32(0x005ACEBC, MGR)
if CASE ~= "closed" then H.w8(MGR + 0x4874 + 115, 1) end    -- the Pit II's way out
H.w8(0x005A378C, 1)                                          -- MK2 unlocked
H.w32(0x0051004C, FLAGS)
for i = 0, 11 do H.w16(FLAGS + i * 2, i < 2 and 1 or 0); H.w16(PLAYER + i * 0x3238 + 0x1DFE, i) end
local function set_alive(i, kind) H.w16(FLAGS + i * 2, kind and 1 or 0); if kind then H.w16(PLAYER + i * 0x3238 + 0x1DFE, kind) end end
-- the text table: text 0 ("= Salir" in Spanish), text 34 in its 128-byte slot
local function put(a, s) for k = 1, #s do H.w8(a + k - 1, s:byte(k)) end H.w8(a + #s, 0) end
H.w32(0x005B04A4, LIST); H.w32(0x005AC508, 800)
H.w32(LIST, 0x81402000); put(0x81402000, CASE == "beaten" and "= Salir" or "= Exit")
H.w32(LIST + 34 * 4, SLOT34); H.w32(LIST + 35 * 4, SLOT34 + 128)
put(SLOT34, "Raiden:\nTutorial Message 13.")
local function slot_text()
  local o, a = {}, SLOT34
  while H.r8(a) ~= 0 do o[#o + 1] = string.char(H.r8(a)); a = a + 1 end
  return table.concat(o)
end
H.w32(MESSAGES + 0x6D4, 0xFFFFFFFF)
local function stand(x, y, z) H.wf32(PLAYER + 0x80, x); H.wf32(PLAYER + 0x84, y); H.wf32(PLAYER + 0x88, z) end

local frames, react_until = 0, nil
local shown, reacted, xp = {}, nil, nil
local behaviour = {
  [VANILLA_SLOT] = { pop = 0, run = function(ctx) end },
  [MESSAGETEXT] = { pop = 12, run = function(ctx)
      local a = H.r32(H.r32(ctx.esp + 4) + 8)
      local text, kind = H.r32(a), H.r32(a + 4)
      shown[#shown + 1] = { text = text, kind = kind, line = text == 34 and slot_text() or nil }
      H.w32(MESSAGES + 0x6D4, kind); H.w32(MESSAGES + 0x6F0, kind == 5 and 300 or 30)
    end },
  [REACTION] = { pop = 12, run = function(ctx)
      reacted = true; H.w32(PLAYER + 0x1E04, 0xC); react_until = frames + 90
    end },
  [ADDEXPERIENCE] = { pop = 12, run = function(ctx)
      local event, target = H.r32(ctx.esp + 4), H.r32(ctx.esp + 8)
      xp = { amount = H.r32(H.r32(event + 8)), kind = H.r32(target), index = H.r32(target + 0x10) }
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
    if #H.failed > 0 then return end
  end
end
-- a loadmap command fired by the map's triggers; returns its (possibly redirected) arguments
local function loadmap(to, entry)
  H.w32(DEF + 8, ARGS); H.w32(ARGS, to); H.w32(ARGS + 4, entry); H.w32(ARGS + 8, 1)
  H.w32(STACK + 4, DEF)
  H.invoke(m, LOADMAP, { esp = STACK }, nil)
  return H.r32(ARGS), H.r32(ARGS + 4), H.r32(ARGS + 8)
end
-- the load the game makes: the new map's frames start, no message up
local function load(map)
  H.w8(LOAD_REQUEST, 0); H.w32(MAP, map); H.w32(MESSAGES + 0x6D4, 0xFFFFFFFF); run(1)
end
local function last_line() for i = #shown, 1, -1 do if shown[i].line then return shown[i].line end end end

if CASE == "closed" then
  stand(PORTAL[1] + 1000, PORTAL[2], PORTAL[3]); run(400)
  stand(PORTAL[1] + 100, PORTAL[2], PORTAL[3]); run(100)
  assert(#shown == 0, "the rift stays closed before the Pit II is beaten")
  local to, entry = loadmap(75, 1)
  assert(to == 75 and entry == 1, "Smoke's portal still loads the Pit II")
  print("PASS time rifts 0.12.0 gauntlet closed")
  return
end

if CASE == "portal" then
  stand(PORTAL[1] + 2000, PORTAL[2], PORTAL[3]); run(300)
  assert(last_line() and last_line():find("My portal has become a rift", 1, true), "Smoke's rift line in English: " .. tostring(last_line()))
  local to, entry, portal = loadmap(75, 1)
  assert(to == 162 and entry == 1 and portal == 1, "Smoke's portal goes into Survival 2 instead of the Pit II")
  load(161); run(200)
  assert(last_line():find("This is the true Survival:\n9 battles", 1, true), "the gauntlet's first line: " .. last_line())
  load(64); run(2)                                              -- somewhere else than Survival 3
  local report = H.failed[1]
  print(report)
  assert(report and report:find("^GAUNTLET 0.12.0 LEFT") and report:find("portal@") and report:find("left@64"),
    "expected LEFT, got: " .. tostring(report))
  print("PASS time rifts 0.12.0 gauntlet portal")
  return
end

-- beaten: P1 arrives in front of the portal (the Pit II's way back)
stand(PORTAL[1] + 100, PORTAL[2], PORTAL[3]); run(30)
assert(#shown == 0, "nothing before the area settles")
run(250)
assert(#shown == 1 and shown[1].kind == 5 and shown[1].line:find("^Smoke:\nAlgo ha rasgado el tiempo"),
  "Smoke's rift line (Spanish), once the area is quiet: " .. tostring(shown[1] and shown[1].line))
run(400)
assert(#shown == 1, "no prompt before P1 has walked away from the portal")
stand(PORTAL[1] + 800, PORTAL[2], PORTAL[3]); run(10)
stand(PORTAL[1] + 200, PORTAL[2], PORTAL[3]); run(10)
assert(#shown == 2 and shown[2].text == 391 and shown[2].kind == 4, "the A prompt in front of the portal")
pad_a = 0xFF; run(1); pad_a = 0
assert(pad_seen == 0 and reacted, "A swallowed, the pull-in plays")
run(92)
assert(H.r8(LOAD_REQUEST) == 1 and H.r32(LOAD_MAP) == 161 and H.r32(LOAD_ENTRY) == 1 and H.r32(LOAD_PORTAL) == 1
  and H.r8(PLAYER + 0x3217) == 1, "the load into Survival 2 at entry 1")
load(161); run(200)
assert(last_line():find("Esta es la verdadera Supervivencia:\n9 batallas", 1, true), "the first stage's line: " .. last_line())
set_alive(3, 56); run(20)                                       -- Baraka
local to, entry = loadmap(162, 1)
assert(to == 162 and entry == 1, "the stage's own reload is left alone")
set_alive(3, nil)
to, entry = loadmap(163, 0)                                     -- Survival 2's link: Survival 3 at entry 0
assert(to == 163 and entry == 1, "Survival 2's way out goes to Survival 3 at entry 1: " .. to .. "/" .. entry)
to, entry = loadmap(163, 0)
assert(to == 163 and entry == 1, "a repeat call while the load is under way: the same")
load(162); run(200)
assert(last_line():find("Batalla 2 de 9", 1, true), "stage 2's line: " .. last_line())
-- a stage that never sends P1 on: nobody up and no wave for 30 s
set_alive(4, 10); run(30); set_alive(4, 42)                     -- only a tree mouth left: no wave waits on it
run(1790)
assert(H.r8(LOAD_REQUEST) == 0, "not before 30 s")
run(15)
assert(H.r8(LOAD_REQUEST) == 1 and H.r32(LOAD_MAP) == 163 and H.r32(LOAD_ENTRY) == 1, "stage 2 left on idle: Survival 4")
set_alive(4, nil)
for i = 3, #STAGES do
  load(STAGES[i][1]); run(200)
  local want = i == #STAGES and "La \xFAltima batalla" or ("Batalla " .. i .. " de 9")
  assert(last_line():find(want, 1, true), "stage " .. i .. "'s line: " .. last_line())
  set_alive(5, 70); run(10); set_alive(5, nil)
  local nxt = STAGES[i + 1] or { 146, 2 }
  to, entry = loadmap(1, 2)                                     -- whatever the stage's own link says
  assert(to == nxt[1] + 1 and entry == nxt[2], "stage " .. i .. " goes on to map " .. nxt[1] .. " entry " .. nxt[2]
    .. ": " .. to - 1 .. "/" .. entry)
end
load(146); run(200)
assert(last_line():find("Recompensa: 10.000 de experiencia", 1, true), "Smoke's reward line: " .. last_line())
run(2)
assert(xp and xp.amount == 10000 and xp.kind == 0x72616863 and xp.index == 0, "10,000 XP to player 1")
local report = H.failed[1]
print(report)
assert(report and report:find("^GAUNTLET 0.12.0 BEATEN"), "expected BEATEN, got: " .. tostring(report))
assert(report:find("open@") and report:find("s1=link162") and report:find("s2=idle") and report:find("s8=link0")
  and report:find("xp%+10000"), "the run's notes")
assert(H.r8(MGR + 0x1C4 + 22) == 0xB0, "the gauntlet (bit 4) remembered in the save: " .. H.r8(MGR + 0x1C4 + 22))
print("max writes:", H.max_writes, "max instr:", H.max_instr)
print("PASS time rifts 0.12.0 gauntlet beaten")
