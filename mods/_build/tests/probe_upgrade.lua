package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m = H.load(arg[1])

-- probe_upgrade only reads; it must never touch game memory.
local MGR = 0x500000
H.w32(0x5ACEBC, MGR)          -- game manager pointer
H.w32(MGR + 0x88, 0)          -- single player
H.w32(MGR + 0x48F0, 4200)     -- player 0 XP
H.w32(0x5CE878, 1000)         -- frame counter

-- player 1 character: entity slot 0, actor with positive health, combo link
local ENTITY = 0x005D1AB8
local ACTOR  = 0x700000
H.w32(ENTITY + 0x200, ACTOR)
H.w32(ACTOR + 0x368, 100)     -- health
local LINK = 0x710000
H.w32(ENTITY + 0x2B6C, LINK)
H.w32(LINK + 0x50, 0x720000)  -- combo stats
H.w32(0x720000 + 0xC4, 7)     -- combo hits

-- a "char" script reference resolving to enemy index 3
local REF = 0x600000
H.w8(REF, 0x63)
H.w32(REF + 0x10, 3)

-- the watched commands must be hooked
assert(m[0x001A33E0], "no enemy_detach_bone hook")
assert(m[0x0018AAC0], "no startanim hook")
assert(m[0x0013A53],  "no addexperience hook")

local STACK = 0xD00F0000
local function ctx_with(...)
  local a = { ... }
  for i, v in ipairs(a) do H.w32(STACK + i * 4, v) end
  return { ecx = 0, esp = STACK, eax = 0 }
end

-- sample a rare dismember command (arms the window) plus hot commands
H.invoke(m, 0x001A33E0, ctx_with(REF, 5, 0))     -- enemy_detach_bone(victim, bone)
H.invoke(m, 0x0018AAC0, ctx_with(REF, 0x2A, 0))  -- startanim
H.invoke(m, 0x0013A53,  ctx_with(0, 50, 0))      -- addexperience

-- per-command cap: hammering one command must not grow the report forever
for _ = 1, 20 do H.invoke(m, 0x001A33E0, ctx_with(REF, 5, 0)) end

-- 0.9: animation events, split by owner and fatality mode, plus state changes
assert(m[0x00180D30], "no animation-event hook")
assert(m[0x0010C600], "no engine detach_group hook")
H.w32(0x0058E068 + 0x1A0, 0); H.w32(0x0058E068 + 0x1A4, 0)
H.invoke(m, 0x00180D30, ctx_with(ENTITY, 0, 0x2A, 0))              -- player, normal
H.invoke(m, 0x00180D30, ctx_with(ENTITY + 3 * 0x3238, 0, 0x30, 0)) -- enemy, normal
H.w32(0x5CE878, 1001); H.w32(0x0058E068 + 0x1A0, 10)               -- fatality mode starts
H.invoke(m, 0x00180D30, ctx_with(ENTITY, 0, 0x2A, 0))
H.invoke(m, 0x00180D30, ctx_with(ENTITY, 0, 0x55, 0))
H.w32(0x0058E068 + 0x1A0, 0)

-- 0.8 reports only when the game saves: nothing may be written before that,
-- however long the session runs, and a second save adds nothing.
H.w32(0x5CE878, 1000 + 100000)
H.invoke(m, 0x001A33E0, ctx_with(REF, 5, 0))
assert(#H.failed == 0, "probe_upgrade reported before the game saved")
H.invoke(m, 0x001272A0, ctx_with())
H.invoke(m, 0x001272A0, ctx_with())

print("errors", #H.failed, "max_writes", H.max_writes, "max_instr", H.max_instr)
assert(H.max_writes == 0, "probe_upgrade wrote to game memory; it must be read-only")
assert(#H.failed == 1, "expected exactly one report, got " .. #H.failed)
assert(tostring(H.failed[1]):find("UPGRADE save"), "report missing UPGRADE save tag: " .. tostring(H.failed[1]))
assert(tostring(H.failed[1]):find("enemy_detach_bone"), "report missing sampled command")
local r = tostring(H.failed[1])
local function has(t) local i = 1; while true do local j = r:sub(i):len(); if j == 0 then return false end
  if r:sub(i, i + #t - 1) == t then return true end; i = i + 1 end end
assert(has(" | ANIM "), "report missing the animation histogram")
assert(has("p2A=1") and has("o30=1") and has("pF2A=1") and has("pF55=1"), "histogram keys wrong")
assert(has(" | STATE ") and has(":10/0/"), "report missing the fatality-mode change")
print("probe_upgrade: read-only, one report at save, caps held")
print(H.failed[1])
