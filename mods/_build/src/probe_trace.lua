local TRACE = {
    { name = "istwoplayer", address = 0x00012E55 },
    { name = "isoneplayer", address = 0x000156CD },
    { name = "isvs", address = 0x000117EE },
    { name = "stonepowatleast", address = 0x00013F94 },
    { name = "addstonepower", address = 0x00011938 },
    { name = "stonecolor", address = 0x00015574 },
    { name = "enabletether", address = 0x00014EDA },
    { name = "OtherPlayerInvisible", address = 0x0001420A },
    { name = "buttonthrough", address = 0x00014606 },
    { name = "actionButton", address = 0x000146A1 },
    { name = "movetotrigger", address = 0x0015E150 },
    { name = "randomtrigger", address = 0x0001512D },
    { name = "gameevent", address = 0x00013134 },
    { name = "eventcomplete", address = 0x00016A4B },
    { name = "eventnotcomplete", address = 0x00014BCE },
    { name = "spawnunlockable", address = 0x00014E99 },
    { name = "spwn_trig_pos", address = 0x001DE670 },
    { name = "callspawn", address = 0x001D2710 },
    { name = "callspawnmerge", address = 0x001D2780 },
    { name = "spawnpickup", address = 0x00012423 },
    { name = "healthupgrade", address = 0x000128B0 },
    { name = "unlockchar", address = 0x000136CA },
    { name = "swapobject", address = 0x001DC4A0 },
    { name = "onbreak", address = 0x0001183E },
    { name = "breakcontainer", address = 0x0001568C },
}
-- MKSMK Probe script tracer: logs which co-op, stone-power, trigger and event
-- script commands run, with their result (al) and the co-op stone power
-- (0x581B48). Repeats of the same call collapse into "xN". Reports to the log
-- after REPORT_AT distinct entries, then switches itself off.
local REPORT_AT   = 60
local STONE_POWER = 0x00581B48
local GAME_MANAGER = 0x005ACEBC

local log, last, repeats = {}, nil, 0

local function flush_repeat()
    if repeats > 1 then
        log[#log] = log[#log] .. "x" .. repeats
    end
end

local function record(text)
    if text == last then
        repeats = repeats + 1
        return
    end
    flush_repeat()
    last, repeats = text, 1
    log[#log + 1] = text
    if #log >= REPORT_AT then
        flush_repeat()
        local manager = game.read_u32(GAME_MANAGER)
        local mode = -1
        if manager >= 0x80000000 and manager < 0x84000000 then
            mode = game.read_u32(manager + 0x88)
        end
        error("TRACE mode=" .. mode .. " | " .. table.concat(log, " "), 0)
    end
end

local hooks = {}
for _, item in ipairs(TRACE) do
    hooks[#hooks + 1] = {
        address = item.address,
        after = function(ctx)
            record(item.name .. "=" .. (ctx.eax & 0xFF) .. "/s" .. game.read_u32(STONE_POWER))
        end,
    }
end
return hooks
