-- Solo Co-op Paths 0.6 -- colored-plate diagnostics (read-only, changes nothing).
-- Companion to coop_solo.lua. Ship this script to turn the diagnostics ON; it
-- writes ONE report to the session log when the game saves (0x1272A0, the
-- HardDisk write every save ends in), as a script error that then disables
-- only this script for the session. coop_solo.lua keeps running. Play, stand
-- on the colored plates, save, quit.
--
-- Colored co-op plates activate when someone stands on them (no button). A
-- plate is a map trigger with the condition stonecolor:C (0x15574 -> 0x20B90):
-- it passes when the activating player's color [[entity+0x2B6C]+4] equals C.
-- A plate that fires runs events such as addstonepower (0x11938 -> 0x20C30,
-- adds its amount to the stone power at 0x581B48) and gameevent (0x13134 ->
-- 0xA4A80, sets event flag [[0x5ACEBC]+0x4874+id] = value != 0). The door is a
-- trigger with stonepowatleast:N (0x13F94 -> 0x20CB0: power >= N) or
-- eventcomplete conditions. coop_solo.lua 0.6 lets a player pass stonecolor of
-- any color in single player.
--
-- The report shows, per map ("m<map>T<index>"), every co-op trigger's
-- conditions and how often it passed its checks and fired; each stonecolor
-- check (plate color, player color, result); each addstonepower and
-- gameevent with the trigger that ran it; each stonepowatleast check against
-- the power; and every change of the 200 event flags, frame by frame.
--
-- This script must be listed BEFORE coop_solo.lua in the mod routines so its
-- CHECK hook snapshots the original condition list before coop_solo rewrites it.
local DEBUG = true            -- diagnostics toggle; set false to ship an inert script

if not DEBUG then
    return {}
end

local CHECK         = 0x0016F4B0
local TRY_FIRE      = 0x0016F560   -- counts a pass; returns 1 when the trigger fires
local FIRE_EVENTS   = 0x0016ED90   -- runs a trigger's events (record = ecx - 0x68)
local STONE_COLOR   = 0x00015574
local STONE_ATLEAST = 0x00013F94
local ADD_STONE     = 0x00011938
local GAME_EVENT    = 0x00013134
local SAVE_GAME     = 0x001272A0
local TRIG_MGR_PTR  = 0x00682020
local TRIG_STRIDE   = 0xD8
local FRAME         = 0x005CE878
local GAME_MANAGER  = 0x005ACEBC
local EVENT_FLAGS   = 0x4874       -- game manager + id, 200 bytes
local EVENT_DWORDS  = 50
local STONE_POWER   = 0x00581B48
local CHAR_TABLE    = 0x005D1AB8
local CHAR_STRIDE   = 0x3238
local STATS_LINK    = 0x2B6C

local MAX_TRIGGERS  = 16
local EVENT_CAP     = 120     -- event-flag changes kept
local LOG_CAP       = 120     -- stone/gameevent records kept

local NAMES = {
    [0x000146A1] = "actionButton", [0x00014606] = "buttonthrough",
    [0x0001420A] = "OtherPlayerInvisible", [0x00012E55] = "istwoplayer",
    [0x000156CD] = "isoneplayer", [0x00014BCE] = "eventnotcomplete",
    [0x00013F94] = "stonepowatleast", [0x00014EDA] = "enabletether",
    [0x00011938] = "addstonepower", [0x00016A4B] = "eventcomplete",
    [0x00015574] = "stonecolor", [0x000152C7] = "setspawncolor",
    [0x00013134] = "gameevent", [0x0001512D] = "randomtrigger",
}
local COOP = { stonecolor = true, stonepowatleast = true, istwoplayer = true,
    isoneplayer = true, OtherPlayerInvisible = true, eventcomplete = true, eventnotcomplete = true }

local function ok(p)
    return p >= 0x10000 and (p < 0x7FFE0000 or (p >= 0x80000000 and p < 0x84000000)
        or (p >= 0xB0000000 and p < 0xC0000000) or (p >= 0xD0000000 and p < 0xE0000000)
        or (p >= 0xF0000000 and p < 0xF4000000))
end
local function hex(v) return string.format("%X", v) end
local function signed(v) if v >= 0x80000000 then return v - 0x100000000 end return v end

local map = 0
local cur_mgr = nil
local conds = {}              -- key -> condition text (co-op triggers), false otherwise
local stats = {}              -- key -> { checks, passes, fired, events }
local order = {}
local log, events = {}, {}
local flags_prev, flags_frame = nil, nil
local fire_stack, firing = {}, nil
local pending_color, pending_atleast = nil, nil
local done = false

local function resolve_execute(mgr, slot)
    if slot < 0 or slot > game.read_u32(mgr + 0x1254C) then return nil end
    local obj = game.read_u32(mgr + slot * 24 + 0x11C00)
    if not ok(obj) then return nil end
    local vtable = game.read_u32(obj)
    if not ok(vtable) then return nil end
    local execute = game.read_u32(vtable)
    if not ok(execute) then return nil end
    return execute
end

local function manager()
    local mgr = game.read_u32(TRIG_MGR_PTR)
    if not ok(mgr) then return nil end
    if mgr ~= cur_mgr then
        cur_mgr = mgr
        map = map + 1
    end
    return mgr
end

local function key_of(rec)
    local mgr = manager()
    if mgr == nil or rec < mgr or (rec - mgr) % TRIG_STRIDE ~= 0 then return nil end
    local index = (rec - mgr) // TRIG_STRIDE
    if index >= game.read_u32(mgr + 0xA8C0) then return nil end
    return "m" .. map .. "T" .. index
end

local function note_trigger(mgr, rec, key)
    conds[key] = false
    local count = game.read_u32(rec + 0x58)
    if count <= 0 or count > 12 then return end
    local slots = game.read_u32(rec + 0x5C)
    local args  = game.read_u32(rec + 0x60)
    if not ok(slots) or not ok(args) then return end
    local list, coop = {}, false
    for j = 0, count - 1 do
        local execute = resolve_execute(mgr, game.read_u32(slots + j * 4))
        local name = execute and (NAMES[execute] or ("sub_" .. hex(execute))) or "?"
        if COOP[name] then coop = true end
        local arg = game.read_u32(args + j * 4)
        list[#list + 1] = arg ~= 0 and (name .. ":" .. hex(arg)) or name
    end
    if not coop then return end
    local def = game.read_u32(rec + 0xC)
    local flags = ok(def) and game.read_u32(def + 0x70) or 0
    conds[key] = "{f" .. hex(flags) .. "}" .. table.concat(list, ",")
end

local function stat(key)
    local s = stats[key]
    if s == nil then
        s = { checks = 0, passes = 0, fired = 0, events = 0 }
        stats[key] = s
        order[#order + 1] = key
    end
    return s
end

local function record(text)
    if #log < LOG_CAP then log[#log + 1] = "f" .. game.read_u32(FRAME) .. ":" .. text end
end

-- Once per frame: log every event flag that changed since the last frame.
local function scan_flags()
    local frame = game.read_u32(FRAME)
    if frame == flags_frame then return end
    flags_frame = frame
    local gm = game.read_u32(GAME_MANAGER)
    if not ok(gm) then return end
    local now = {}
    for k = 0, EVENT_DWORDS - 1 do now[k] = game.read_u32(gm + EVENT_FLAGS + k * 4) end
    if flags_prev then
        for k = 0, EVENT_DWORDS - 1 do
            if now[k] ~= flags_prev[k] then
                for b = 0, 3 do
                    local old = (flags_prev[k] >> (b * 8)) & 0xFF
                    local new = (now[k] >> (b * 8)) & 0xFF
                    if old ~= new and #events < EVENT_CAP then
                        events[#events + 1] = "f" .. frame .. ":E" .. (k * 4 + b) .. "=" .. new
                    end
                end
            end
        end
    end
    flags_prev = now
end

local function player_color(idx)
    if idx < 0 or idx >= 12 then return -1 end
    local link = game.read_u32(CHAR_TABLE + idx * CHAR_STRIDE + STATS_LINK)
    if not ok(link) then return -1 end
    return signed(game.read_u32(link + 4))
end

local function report(reason)
    done = true
    local gm = game.read_u32(GAME_MANAGER)
    local mode = ok(gm) and game.read_u32(gm + 0x88) or -1
    table.sort(order, function(x, y)
        local a, b = stats[x], stats[y]
        if a.fired ~= b.fired then return a.fired > b.fired end
        return a.checks > b.checks
    end)
    local parts = {}
    for i = 1, math.min(#order, MAX_TRIGGERS) do
        local k = order[i]
        local s = stats[k]
        parts[#parts + 1] = k .. (conds[k] or "{?}") .. " chk" .. s.checks .. " pass" .. s.passes
            .. " fired" .. s.fired .. " ev" .. s.events
    end
    error("PLATE060 " .. reason .. " mode=" .. mode .. " maps=" .. map
        .. " stone=" .. signed(game.read_u32(STONE_POWER))
        .. " | " .. table.concat(parts, " | ")
        .. (#log > 0 and (" | LOG " .. table.concat(log, " ")) or "")
        .. (#events > 0 and (" | FLAGS " .. table.concat(events, " ")) or ""), 0)
end

return {
    {
        address = SAVE_GAME,
        before = function(ctx)
            if not done and (#order > 0 or #events > 0) then report("save") end
        end,
    },
    {
        address = CHECK,
        before = function(ctx)
            if done then return end
            scan_flags()
            local key = key_of(ctx.ecx)
            if key == nil then return end
            if conds[key] == nil then note_trigger(cur_mgr, ctx.ecx, key) end
            if conds[key] then stat(key).checks = stat(key).checks + 1 end
        end,
        after = function(ctx)
            if done then return end
            local key = key_of(ctx.ecx)
            if key and conds[key] and (ctx.eax & 0xFF) ~= 0 then stat(key).passes = stat(key).passes + 1 end
        end,
    },
    {
        address = TRY_FIRE,
        before = function(ctx)
            fire_stack[#fire_stack + 1] = ctx.ecx
        end,
        after = function(ctx)
            local rec = table.remove(fire_stack)
            if done or rec == nil or (ctx.eax & 0xFF) == 0 then return end
            local key = key_of(rec)
            if key and conds[key] then stat(key).fired = stat(key).fired + 1 end
        end,
    },
    {
        address = FIRE_EVENTS,
        before = function(ctx)
            if done then return end
            firing = key_of(ctx.ecx - 0x68)
            if firing and conds[firing] then stat(firing).events = stat(firing).events + 1 end
        end,
        after = function(ctx)
            firing = nil
        end,
    },
    {
        address = STONE_COLOR,
        before = function(ctx)
            if done then return end
            local ref = game.read_u32(ctx.esp + 4)
            local idx = ok(ref) and signed(game.read_u32(ref + 0x10)) or -1
            local rec = ok(ctx.ecx) and game.read_u32(ctx.ecx + 8) or 0
            pending_color = { key = key_of(rec) or "m?T?", idx = idx,
                plate = signed(game.read_u32(ctx.ecx + 4)), color = player_color(idx) }
        end,
        after = function(ctx)
            local d = pending_color
            pending_color = nil
            if done or d == nil then return end
            record("SC" .. d.key .. "i" .. d.idx .. "c" .. d.color .. "/" .. d.plate .. "r" .. (ctx.eax & 0xFF))
        end,
    },
    {
        address = STONE_ATLEAST,
        before = function(ctx)
            if done then return end
            local rec = ok(ctx.ecx) and game.read_u32(ctx.ecx + 8) or 0
            pending_atleast = { key = key_of(rec) or "m?T?", need = signed(game.read_u32(ctx.ecx + 4)),
                power = signed(game.read_u32(STONE_POWER)) }
        end,
        after = function(ctx)
            local d = pending_atleast
            pending_atleast = nil
            if done or d == nil then return end
            record("SP" .. d.key .. ":" .. d.power .. ">=" .. d.need .. "r" .. (ctx.eax & 0xFF))
        end,
    },
    {
        address = ADD_STONE,
        before = function(ctx)
            if done then return end
            local def = game.read_u32(ctx.esp + 4)
            local args = ok(def) and game.read_u32(def + 8) or 0
            local amount = ok(args) and signed(game.read_u32(args)) or 0
            record("AS" .. (firing or "-") .. ":+" .. amount .. "@" .. signed(game.read_u32(STONE_POWER)))
        end,
    },
    {
        address = GAME_EVENT,
        before = function(ctx)
            if done then return end
            local def = game.read_u32(ctx.esp + 4)
            local args = ok(def) and game.read_u32(def + 8) or 0
            if not ok(args) then return end
            record("GE" .. (firing or "-") .. ":" .. game.read_u32(args) .. "=" .. game.read_u32(args + 4))
        end,
    },
}
