package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local mods = {}
for i = 1, #arg do mods[#mods+1] = H.load(arg[i]) end

local M = 0x6DBFB0; local GS = 0xA6C
local FRAME = 0x5CE878; local CAP = 0x5142B8; local POOLSZ = 0x5142A4
local FLAGS = 0x81000000; local LOADED = 0x6CA69C
local STACK = 0xD00F0000
H.w32(CAP, 7); H.w32(POOLSZ, 12); H.w32(0x51004C, FLAGS)
for i=0,11 do H.w16(FLAGS+i*2, i<2 and 1 or 0) end
-- per-type character heaps (slot table at 0x6322F8), sized for authored concurrency
local COST = { [3]=0x10000, [4]=0x14000, [7]=0x30000, [9]=0x28000 }
-- free at area start = cost * (authored total in the level + surplus)
local CONC = { [3]=7+1, [4]=7+5, [7]=1+3, [9]=2+0 }
if os.getenv("WUSHI") == "1" then CONC = { [3]=7, [4]=7+12, [7]=1+3, [9]=2 } end  -- 3 fully booked, 4 roomy
local slots = {3,4,7,9}
if os.getenv("BOSSES") == "1" then
  -- boss arenas: Oni Warlord (36, super boss, authored twice like the real
  -- area) and Baraka (54, MK character)
  -- each authored once, with heap room for a clone plus the spare LDK keeps
  COST = { [3]=0x10000, [4]=0x14000, [36]=0x60000, [54]=0x30000, [28]=0x60000 }
  CONC = { [3]=6+2, [4]=5+3, [36]=2+3, [54]=1+3, [28]=1+3 }
  slots = {3,4,36,54,28}
end
-- OUTSIDER=1: Goro's Lair. One regular type (15) authored across the area's
-- groups and the only type the map preloads, so Shaolin Shuffle 0.7 appends an
-- outsider to the preload list; the sim loads whatever it picked into the
-- second memory slot. OUTSIDER_EVICT=1 also has a cutscene evict the outsider
-- before the third group (modelstream into its slot).
local OUTSIDER = os.getenv("OUTSIDER") == "1"
local EVICT = os.getenv("OUTSIDER_EVICT") == "1"
-- LAIR=1: the map number is Goro's Lair's (98), where LDK 3.11 fills groups
if os.getenv("LAIR") == "1" then H.w32(0x505970, 98) end
if OUTSIDER then
  COST = { [15]=0x24D00 }
  CONC = { [15]=7+3 }
  slots = {15}
end
-- RESPAWN=1: the Goro's Lair fatality tutorial. One wave of three type-0xF
-- enemies is restarted every time it is cleared until the player performs a
-- fatality (20 restarts here). In the real map, earlier waves had already
-- used up type 0xF's fresh heap (0x21E80 free, 0x24D00 per instance), so the
-- heap here holds only 3 instances; later spawns must recycle.
local RESPAWN = os.getenv("RESPAWN") == "1" or os.getenv("CARRY") == "1"
-- CARRY=1: like RESPAWN, but the type stays loaded between visits (Goro's
-- Lair maps 98-100): its heap and dead instances carry over, and the heap
-- arrives full, so every later spawn must reuse an instance.
local CARRY = os.getenv("CARRY") == "1"
if RESPAWN then
  COST = { [15]=0x24D00 }
  CONC = { [15]=6 }    -- resized per visit in load_level
  slots = {15}
end
local SLOT_TBL = 0x81001000
H.w32(0x6322F8+0x10, #slots); H.w32(0x6322F8+0x24, SLOT_TBL)
local heapid = {}
local function add_heap(i, t)
  local hid = heapid[t] or (OUTSIDER and 40 + t or 10 + i); heapid[t] = hid   -- one heap per type
  H.w32(SLOT_TBL+(i-1)*20, hid); H.w32(SLOT_TBL+(i-1)*20+4, t)
  local rec = 0x62EC60 + hid*0x68
  local total = COST[t]*CONC[t] + 0x2000
  H.w32(rec+4, total); H.w32(rec+8, 0x82000000 + hid*0x100000); H.w32(rec+0xC, 0x82000000 + hid*0x100000 + total)
end
for i, t in ipairs(slots) do add_heap(i, t) end
local FREEONDEATH = os.getenv("FREE") == "1"
-- The game recycles a dead enemy's instance for the next spawn of its type
-- (probe run 2026-10-24); NORECYCLE=1 restores the old never-reused model.
local RECYCLE = os.getenv("NORECYCLE") ~= "1"
local pool = {}
local function heap_alloc(t)
  local rec = 0x62EC60 + heapid[t]*0x68
  local cur, last = H.r32(rec+8), H.r32(rec+0xC)
  if last - cur < COST[t] then return false end
  H.w32(rec+8, cur + COST[t]); return true
end
local function heap_free(t)
  if not FREEONDEATH then return end
  local rec = 0x62EC60 + heapid[t]*0x68; H.w32(rec+8, H.r32(rec+8) - COST[t])
end
local function heap_reset()
  for t, hid in pairs(heapid) do H.w32(0x62EC60+hid*0x68+8, 0x82000000 + hid*0x100000) end
  pool = {}
end
local level = {
  {types={3,3,3,3}, delay=0},
  {types={3,4,4}, delay=30},
  {types={9}, delay=0},            -- boss alone
  {types={9,3,3}, delay=0},        -- unique 9 appears twice? no: 9 appears in g3 too -> count 2
  {types={7,4,4,4,4,4}, delay=10}, -- 7 unique elite
}
if os.getenv("BIG") == "1" then
  -- worst case census: 50 groups x 22 entries, mixed behaviour signatures
  level = {}
  for g = 1, 50 do
    local types = {}
    for e = 1, 22 do types[e] = (e % 3 == 0) and 4 or 3 end
    level[g] = {types=types, delay=0}
  end
end
-- MIX=1: rooms that each author a single regular type, like most real areas.
-- The signature-class swap alone changes nothing here; Wild/Chaos must trade
-- plain slots between rooms (0.10) while keeping per-type totals exact.
local MIX = os.getenv("MIX") == "1"
if MIX then
  level = {
    {types={3,3,3,3}, delay=0},
    {types={4,4,4,4}, delay=0},
    {types={3,3,3,3}, delay=10},
    {types={4,4,4,4}, delay=0},
  }
  loaded = {3,4,0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF}
end
local loaded = {3,4,9,7,0xFFFFFFFF,0xFFFFFFFF}
if OUTSIDER then
  level = {
    {types={15,15,15}, delay=0},
    {types={15,15,15,15,15}, delay=0},
    {types={15,15,15,15}, delay=10},
    {types={15,15,15,15,15,15}, delay=0},
    {types={15,15,15}, delay=0},
    {types={15,15,15}, delay=20},
  }
  loaded = {15,0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF}
end
if RESPAWN then
  level = { {types={15,15,15}, delay=0} }
  loaded = {15,0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF}
end
-- FATALITY=1: the area's map triggers test isfatalityfull (a fatality
-- tutorial room); LDK and Shuffle must leave every wave as authored.
if os.getenv("FATALITY") == "1" then
  local TM = 0x81300000
  H.w32(0x682020, TM); H.w32(TM+0xA8C0, 2); H.w32(TM+0x1254C, 3)
  local VT, OBJ, SLOTS = 0x81310000, 0x81310100, 0x81310200
  H.w32(VT, 0x00013382); H.w32(OBJ, VT)            -- command slot 2 = isfatalityfull
  H.w32(TM + 2*24 + 0x11C00, OBJ)
  H.w32(TM + 1*0xD8 + 0x58, 1); H.w32(TM + 1*0xD8 + 0x5C, SLOTS); H.w32(SLOTS, 2)
end
local DESC = 0x004FD000
local outsider_kind = nil
if os.getenv("BOSSES") == "1" then
  level = {
    {types={3,3,3,4,4}, delay=0},
    {types={36}, delay=0},          -- Oni Warlord arena
    {types={54}, delay=0},          -- Baraka fight
    {types={3,36,4,4}, delay=10},   -- the Oni authored a second time, among grunts
    {types={28}, delay=0},          -- Orochi with a scripted entrance: never cloned
  }
  loaded = {3,4,36,54,28,0xFFFFFFFF}
end
authored = {}
local visits = 0
local function load_level(seedhdr)
  visits = visits + 1
  if CARRY and visits > 1 then
    local rec = 0x62EC60 + heapid[15]*0x68
    H.w32(rec+0xC, H.r32(rec+8) + 0x2000)     -- carried over and full
  else
    heap_reset()
  end
  if RESPAWN and not (CARRY and visits > 1) then
    -- first visit: room for 6 (recycling gets observed); later visits arrive
    -- with the heap already used up by earlier waves (room for 3)
    local rec = 0x62EC60 + heapid[15]*0x68
    local n = (visits == 1) and 6 or 3
    H.w32(rec+4, COST[15]*n + 0x2000); H.w32(rec+0xC, H.r32(rec+8) + COST[15]*n + 0x2000)
  end
  authored = {}
  for a = M, M + 0x20930 - 1 do H.mem[a] = nil end
  for g, def in ipairs(level) do
    local base = M + (g-1)*GS
    H.w32(base, 100+g+seedhdr); H.w32(base+8, 200+g); H.w32(base+0xC, 300+g)
    H.w8(base+0xA6A, 1); H.w16(base+0xA68, #def.types)
    for e, t in ipairs(def.types) do
      local ent = base + 0x18 + (e-1)*0x74
      H.w32(ent, t); for _, o in ipairs({4,8,0x10,0x14,0x2C}) do H.w32(ent+o, 0xFFFFFFFF) end
      H.w32(ent+0x18, e*100); H.w16(ent+0x5A, def.delay + (e-1)*5)
      H.w32(ent+0x5C, (t == 7 or t == 28 or e % 4 == 0) and 5 or 0xFFFFFFFF)   -- special entrance state
      if os.getenv("WUSHI") == "1" then H.w32(ent+0x70, t * 16); H.w32(ent+0x60, t) end  -- per-type navmesh / patrol
      authored[ent] = t
    end
  end
  for i,t in ipairs(loaded) do H.w32(LOADED+(i-1)*4, t) end
  if os.getenv("NOLOADHOOK") ~= "1" then for _, m in ipairs(mods) do H.invoke(m, 0x14D2C, {esp=STACK}) end end
  if OUTSIDER then
    -- the map's preload (0xCFAB0 via 0x15DEE) runs after the spawn groups load
    H.w32(DESC+0x20, 1); H.w32(DESC+0x24, 15); H.w32(DESC+0x28, 0xFFFFFFFF)
    H.w32(STACK+4, DESC)
    for _, m in ipairs(mods) do H.invoke(m, 0x15DEE, {esp=STACK}) end
    local o = H.r32(DESC+0x28)
    outsider_kind = nil
    if o ~= 0xFFFFFFFF and H.r32(DESC+0x20) >= 2 then
      outsider_kind = o
      COST[o] = 0x20000; CONC[o] = 8
      add_heap(2, o); H.w32(0x6322F8+0x10, 2)
      H.w32(LOADED+4, o)
    end
  end
end

local stats = {spawned={}, failed=0, overflow=0, maxalive=0, types={}, ctrlcap={}}
local alive = {}   -- list of {slot=,ctrl=}
local ctrl_count = 0
local function free_slot() for i=0,11 do if H.r16(FLAGS+i*2)==0 then return i end end end
local function is_loaded(t) for i=0,5 do if H.r32(LOADED+i*4)==t then return true end end return false end

local function invoke_all(addr, ctx, orig)
  -- emulate hook chaining across several mods: before all, original, after all
  local lists = {}
  for _, m in ipairs(mods) do for _, h in ipairs(m[addr] or {}) do lists[#lists+1]=h end end
  local fake = {[addr]=lists}
  H.invoke(fake, addr, ctx, orig)
end

local function spawn_entry(entry, g)
  local ok = false
  H.w32(STACK+4, entry)
  local ctx = {ecx=M, esp=STACK, eax=0}
  invoke_all(0x1D1D40, ctx, function()
    local t = H.r32(entry)
    if not is_loaded(t) then return end
    local slot = free_slot(); if not slot then return end
    if RECYCLE and (pool[t] or 0) > 0 then
      pool[t] = pool[t] - 1
    elseif not heap_alloc(t) then stats.crash = (stats.crash or 0) + 1; return end
    H.w16(FLAGS+slot*2, 1)
    H.w16(0x5D1AB8 + slot*0x3238 + 0x1DFE, t)
    local ctrl = H.r32(M+0x20924)
    local a = H.r16(ctrl+0xA0)
    if a + 1 > stats.ctrlcap[ctrl] then stats.overflow = stats.overflow + 1 end
    H.w16(ctrl+0xA0, a+1)
    alive[#alive+1] = {slot=slot, ctrl=ctrl, t=t}
    if OUTSIDER and outsider_kind and t == outsider_kind then
      stats.o_rooms = stats.o_rooms or {}
      stats.o_rooms[stats.loads .. ":" .. g] = true
    end
    stats.types[t] = (stats.types[t] or 0) + 1
    if authored[entry] then
      stats.orig_spawns = (stats.orig_spawns or 0) + 1
      if authored[entry] ~= t then
        stats.changed = (stats.changed or 0) + 1
        stats.changed_from = stats.changed_from or {}
        stats.changed_from[authored[entry]] = (stats.changed_from[authored[entry]] or 0) + 1
        stats.changed_to = stats.changed_to or {}
        stats.changed_to[t] = (stats.changed_to[t] or 0) + 1
      end
    else
      stats.extra = (stats.extra or 0) + 1
    end
    ok = true
    ctx.eax = 0x81F00000 + slot * 0x100   -- 0x1D1D40 returns the new actor
  end)
  return ok
end

local function tick_impl()
  if H.r8(M+0x2092A) == 0 then return end
  local g = H.r16(M+0x20920)
  local base = M + g*GS
  while true do
    local s = H.r16(M+0x20922)
    local ent = base + 0x18 + s*0x74
    local due = H.r32(M+0x2091C) + H.r16(ent+0x5A)
    if H.r32(FRAME) < due and H.r16(M+0x2092C) == 0 then return end
    local count = H.r16(base+0xA68)
    if spawn_entry(ent, g) then
      stats.spawned[g] = (stats.spawned[g] or 0) + 1
      H.w16(M+0x20922, s+1)
      if s+1 == count then H.w8(M+0x2092A, 0) return end
    else
      stats.failed = stats.failed + 1
      H.w16(M+0x20922, s+1)
      s = s + 1
      while s ~= count do
        if spawn_entry(base+0x18+s*0x74, g) then stats.spawned[g]=(stats.spawned[g] or 0)+1 else stats.failed=stats.failed+1 end
        s = s + 1; H.w16(M+0x20922, s)
        if s > 30 then error("runaway spawner") end
      end
      H.w8(M+0x2092A, 0) return
    end
  end
end
local function spawn_tick() invoke_all(0x1D23F0, {ecx=M, esp=STACK}, tick_impl) end

local function start_group(g)
  H.w32(STACK+4, g)
  invoke_all(0x1D2600, {ecx=M, esp=STACK}, function()
    local base = M + g*GS
    if H.r16(base+0xA68) == 0 or H.r8(base+0xA6A) == 0 then return end
    if H.r8(M+0x2092A) ~= 0 then H.w16(M+0x2092C,1); spawn_tick(); H.w16(M+0x2092C,0) end
    local ctrl
    invoke_all(0x1D1B80, {ecx=M, esp=STACK}, function()
      ctrl_count = ctrl_count + 1
      ctrl = 0x81002000 + ctrl_count*0x100
      stats.ctrlcap[ctrl] = H.r32(CAP)
      H.w16(ctrl+0xA0, 0)
    end)
    H.w32(M+0x2091C, H.r32(FRAME)); H.w8(M+0x2092A,1); H.w16(M+0x20920,g); H.w16(M+0x20922,0); H.w32(M+0x20924, ctrl)
    if os.getenv("SIMLOG") == "1" then
      local types = {}
      for e = 0, H.r16(base+0xA68) - 1 do types[#types+1] = H.r32(base + 0x18 + e*0x74) end
      print("start group", g, "frame", H.r32(FRAME), "entries", table.concat(types, ","))
    end
    spawn_tick()
  end)
end

local rng = 12345
local function r() rng = (rng * 1103515245 + 12345) % 2147483648; return rng end
local function run_level(hdr)
  stats.loads = (stats.loads or 0) + 1
  load_level(hdr)
  local order = {}
  for g = 0, #level-1 do order[#order+1] = g end
  if RESPAWN then for _ = 1, 19 do order[#order+1] = 0 end end
  for _, g in ipairs(order) do
    if OUTSIDER and EVICT and g == 2 and outsider_kind then
      H.w32(LOADED+4, 0x4C)                -- a cutscene streams Johnny Cage into the slot
      stats.evicted = (stats.evicted or 0) + 1
      local o = outsider_kind; outsider_kind = nil
      -- the unload (0x17B280 -> 0x17B220) destroys every live actor of the type
      for k = #alive, 1, -1 do
        local v = alive[k]
        if v.t == o then
          table.remove(alive, k)
          H.w16(FLAGS+v.slot*2, 0); H.w16(v.ctrl+0xA0, H.r16(v.ctrl+0xA0)-1)
          H.w16(0x5D1AB8 + v.slot*0x3238 + 0x1DFE, 0xFFFF)
        end
      end
      spawn_tick()                          -- Shuffle notices on the next tick
      for gg = 0, #level-1 do
        local base = M + gg*GS
        for e = 0, H.r16(base+0xA68)-1 do
          if H.r32(base+0x18+e*0x74) == o then stats.left_after_evict = (stats.left_after_evict or 0) + 1 end
        end
      end
    end
    start_group(g)
    local f = 0
    repeat
      H.w32(FRAME, H.r32(FRAME)+1); f = f + 1
      spawn_tick()
      if #alive - 0 > stats.maxalive then stats.maxalive = #alive end
      if #alive > 0 and r() % 40 == 0 then
        local k = (r() % #alive) + 1; local v = table.remove(alive, k)
        H.w16(FLAGS+v.slot*2, 0); H.w16(v.ctrl+0xA0, H.r16(v.ctrl+0xA0)-1); heap_free(v.t)
        H.w16(0x5D1AB8 + v.slot*0x3238 + 0x1DFE, 0xFFFF)
        if RECYCLE then pool[v.t] = (pool[v.t] or 0) + 1 end
      end
    until (H.r8(M+0x2092A) == 0 and #alive == 0) or f > 20000
    if f > 20000 then stats.stuck = (stats.stuck or 0) + 1 end
  end
end
run_level(0); run_level(0); run_level(50)
local function fmt(t) local o={} for k,v in pairs(t) do o[#o+1]=k.."="..v end table.sort(o) return table.concat(o," ") end
print("spawned per group:", fmt(stats.spawned))
print("types:", fmt(stats.types), "| authored spawns", stats.orig_spawns or 0, "re-typed", stats.changed or 0, "| extra", stats.extra or 0)
print("re-typed from:", fmt(stats.changed_from or {}), "| to:", fmt(stats.changed_to or {}))
print("stuck groups:", stats.stuck or 0, "CRASHES (heap exhausted):", stats.crash or 0)
print("failed:", stats.failed, "overflow:", stats.overflow, "max alive:", stats.maxalive)
print("max writes:", H.max_writes, "max instr:", H.max_instr)
print("script errors:", #H.failed) for _, e in ipairs(H.failed) do print("  ", e) end
if OUTSIDER then
  local o = 0
  for t, n in pairs(stats.types) do if t ~= 15 then o = o + n end end
  print("outsider spawns:", o, "evicted:", stats.evicted or 0, "outsider entries left after eviction:", stats.left_after_evict or 0)
  local rooms = 0 for _ in pairs(stats.o_rooms or {}) do rooms = rooms + 1 end
  print("rooms with an outsider spawn:", rooms, "of", stats.loads * #level)
end
if MIX then
  local mixed, totals = 0, {}
  for g = 0, #level - 1 do
    local base = M + g * GS
    local set = {}
    for e = 0, H.r16(base + 0xA68) - 1 do
      local t = H.r32(base + 0x18 + e * 0x74)
      set[t] = true
      totals[t] = (totals[t] or 0) + 1
    end
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    if n >= 2 then mixed = mixed + 1 end
  end
  -- the last of 3 loads of the area authors 8 entries per type
  assert(totals[3] == 8 and totals[4] == 8, "per-type totals changed: " .. fmt(totals))
  print("mixed rooms:", mixed, "of", stats.loads * #level, "| totals:", fmt(totals))
end
