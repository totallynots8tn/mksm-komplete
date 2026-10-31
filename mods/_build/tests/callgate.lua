-- callgate library, through the Call Gate Test mod: emulates the frame
-- function 0xC74E0's tail (gameplay update, thunk 0x12284, the singleton's
-- vtable call at 0xC7537, thunk 0x12C93) and the three targets the test calls,
-- and checks that every frame leaves esp balanced and the vtable vanilla.
--   lua tests/callgate.lua ../callgate_test/pack/scripts/callgate.lua
package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m = H.load(arg[1])

local GAMEPLAY, PRE_GATE, POST_GATE = 0x00154F60, 0x00012284, 0x00012C93
local INSTANCE, SINGLETON, VTABLE = 0x00589270, 0x005892A8, 0x00497C60
local VANILLA_SLOT = 0x00013512             -- 0x36B40's thunk, vtable +0x18
local GATE_RET = 0x000C753A
local STONE = 0x00581B48
local E0 = 0xD005FC5C                       -- esp in 0xC74E0, from the 0.1.1 run

H.w32(INSTANCE, SINGLETON); H.w32(SINGLETON, VTABLE); H.w32(VTABLE + 0x18, VANILLA_SLOT)

-- what each routine does when the game runs it (esp at entry points at the
-- return address; `pop` is what its ret pops besides that)
local behaviour = {
  [VANILLA_SLOT] = { pop = 0, run = function(ctx) end },
  [0x00012CF2] = { pop = 0, run = function(ctx) H.w32(STONE, 0) end },
  [0x00011938] = { pop = 12, run = function(ctx)
      local args = H.r32(ctx.esp + 4)
      local amount = H.r32(H.r32(args + 8))
      H.w32(STONE, (H.r32(STONE) + amount) & 0xFFFFFFFF)
    end },
  [0x00011131] = { pop = 0, run = function(ctx) ctx.eax = SINGLETON end },
}

local vanilla_calls, gate_calls = 0, 0
local function frame()
  H.invoke(m, GAMEPLAY, { esp = E0 - 4 }, nil)
  H.invoke(m, PRE_GATE, { esp = E0 }, nil)                -- after hook: esp already back in 0xC74E0
  local target = H.r32(H.r32(SINGLETON) + 0x18)
  local b = assert(behaviour[target], string.format("the gate called unknown code %08X", target))
  local ctx = { esp = E0 - 4, ecx = SINGLETON, eax = 0 }
  H.w32(E0 - 4, GATE_RET)
  H.invoke(m, target, ctx, function(c)
    b.run(c)
    c.esp = c.esp + 4 + b.pop                              -- ret / ret n
  end)
  assert(ctx.esp == E0, string.format("esp off after the gate call: %+d", ctx.esp - E0))
  if target == VANILLA_SLOT then vanilla_calls = vanilla_calls + 1 else gate_calls = gate_calls + 1 end
  H.invoke(m, POST_GATE, { esp = E0 - 4 }, nil)
  assert(H.r32(SINGLETON) == VTABLE, "vtable left swapped after the frame")
end

local report
for _ = 1, 1200 do
  frame()
  if #H.failed > 0 then report = H.failed[1]; break end
end
print(report)
assert(report and report:find("^CALLGATE v0.2 OK"), "expected an OK report, got: " .. tostring(report))
assert(gate_calls == 3, "three gate calls, got " .. gate_calls)
print("frames through vanilla:", vanilla_calls, "gate calls:", gate_calls, "max writes:", H.max_writes, "max instr:", H.max_instr)
print("PASS callgate library")
