
-- Call Gate Test 0.2: exercises the callgate library once, about 15 s into
-- unpaused gameplay, and reports one CALLGATE line to the log 2 s after the
-- last call (by failing with error(), which also switches the script off).
--   reset: no arguments (0x20BF0 via thunk 0x12CF2: stone power = 0)
--   add:   stdcall, three arguments, a block holding a pointer to a block
--          (addstonepower command, thunk 0x11938: adds [[arg1+8]])
--   get:   return value (getter thunk 0x11131 returns the singleton 0x5892A8)
local GAMEPLAY      = 0x00154F60    -- gameplay update; skipped while paused
local STONE_POWER   = 0x00581B48
local RESET_STONE   = 0x00012CF2
local ADD_STONE     = 0x00011938
local GET_SINGLETON = 0x00011131
local SINGLETON     = 0x005892A8
local FIRE_AT       = 900
local SETTLE        = 120
local MARK          = 1234
local AMOUNT        = 25

callgate.target(RESET_STONE)
callgate.target(ADD_STONE)
callgate.target(GET_SINGLETON)

local frames, fired, report_at = 0, false, nil
local notes, failures = {}, 0

local function check(name, ok, text)
    notes[#notes + 1] = name .. (ok and "=ok(" or "=BAD(") .. text .. ")"
    if not ok then
        failures = failures + 1
    end
end

local function fire()
    game.write_u32(STONE_POWER, MARK)
    callgate.call(RESET_STONE, { done = function(eax, popped)
        local stone = game.read_u32(STONE_POWER)
        check("reset", eax ~= nil and stone == 0, "stone=" .. stone .. " popped=" .. tostring(popped))
    end })
    callgate.call(ADD_STONE, {
        args = { callgate.block{ 0, 0, callgate.block{ AMOUNT } }, 0, 0 },
        done = function(eax, popped)
            local stone = game.read_u32(STONE_POWER)
            check("add", eax ~= nil and stone == AMOUNT and popped == 12,
                "stone=" .. stone .. " popped=" .. tostring(popped))
        end })
    callgate.call(GET_SINGLETON, { done = function(eax, popped)
        check("get", eax == SINGLETON, string.format("eax=%s popped=%s",
            eax and string.format("%08X", eax) or "nil", tostring(popped)))
    end })
end

local hooks = {
    {
        address = GAMEPLAY,
        before = function(ctx)
            frames = frames + 1
            if not fired and frames >= FIRE_AT then
                fired = true
                fire()
            elseif fired and callgate.pending() == 0 then
                report_at = report_at or frames + SETTLE
                if frames >= report_at then
                    error("CALLGATE v0.2 " .. (failures == 0 and #notes == 3 and "OK" or "CHECK")
                        .. " | " .. table.concat(notes, " "), 0)
                end
            end
        end,
    },
}

return callgate.hooks(hooks)
