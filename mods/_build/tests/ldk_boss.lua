-- LDK boss health (3.3, off by default since 3.4). By default boss health is
-- untouched. With BOSS_HP_MULT = 2 a boss actor's max and current health are
-- multiplied on its first health change, the triggering hit still lands, later
-- hits are normal, a respawn is scaled again, and players/regular enemies are
-- never touched.
package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local source = io.open(arg[1], "rb"):read("a")
assert(source:find("local BOSS_HP_MULT = 1 ", 1, true), "BOSS_HP_MULT should default to 1")
local default = H.load(arg[1])
local doubled_path = os.tmpname()
local f = io.open(doubled_path, "wb")
f:write((source:gsub("local BOSS_HP_MULT = 1 ", "local BOSS_HP_MULT = 2 ")))
f:close()
local m = H.load(doubled_path)
os.remove(doubled_path)
local SET_HEALTH = 0x00153CD0
local CHAR_BASE, CHAR_SIZE = 0x005D1AB8, 0x3238
local STACK = 0xD00F0000
local function actor_for(slot, id, actor, hp)
  local entity = CHAR_BASE + slot * CHAR_SIZE
  H.w16(entity + 0x1DFE, id)
  H.w32(actor + 0x31C, entity)
  H.w32(actor + 0x370, hp); H.w32(actor + 0x368, hp)
  return actor
end
local function hit(actor, new)
  H.w32(STACK + 4, new)
  H.invoke(m, SET_HEALTH, { esp = STACK, ecx = actor, eax = 0 }, function(ctx)
    local v = H.r32(STACK + 4); local max = H.r32(actor + 0x370)
    H.w32(actor + 0x368, v > max and max or v)
  end)
  return H.r32(actor + 0x368), H.r32(actor + 0x370)
end
-- default build: a boss is untouched
local off = actor_for(5, 34, 0x81630000, 1000)
H.w32(STACK + 4, 900)
H.invoke(default, SET_HEALTH, { esp = STACK, ecx = off, eax = 0 }, function() H.w32(off + 0x368, 900) end)
assert(H.r32(off + 0x370) == 1000 and H.r32(off + 0x368) == 900, "default build must not scale boss health")

local boss  = actor_for(3, 34, 0x81600000, 1000)   -- Oni Warlord
local grunt = actor_for(4, 14, 0x81610000, 300)    -- regular enemy
local p1    = actor_for(0, 34, 0x81620000, 500)    -- player slot, even with a boss id
local cur, max = hit(boss, 900)
print("boss first hit", cur, max)
assert(max == 2000 and cur == 1900, "boss should be doubled and take the 100 damage")
cur, max = hit(boss, 1850)
assert(max == 2000 and cur == 1850, "later hits are normal")
cur, max = hit(grunt, 250)
assert(max == 300 and cur == 250, "regular enemies are untouched")
cur, max = hit(p1, 450)
assert(max == 500 and cur == 450, "players are untouched")
H.w32(boss + 0x370, 1000); H.w32(boss + 0x368, 1000)  -- the actor respawns
cur, max = hit(boss, 1000)
assert(max == 2000 and cur == 2000, "a respawned boss is scaled again")
assert(#H.failed == 0, "script error: " .. tostring(H.failed[1]))
print("max_writes", H.max_writes)
print("PASS ldk boss health (off by default, x2 when enabled)")
