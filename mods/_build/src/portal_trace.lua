-- Portal Trace 0.3.1 (diagnostics): finds the game code behind a portal jump.
-- Every map load the game asks for goes through the loadmap command (thunk
-- 0x12883); this records each request's map, target, entry, how many times it
-- repeated, and the code addresses on the stack above it (the callers), and
-- writes them all as one PORTALTRACE line when the game saves (the statue
-- save's HardDisk write 0x1272A0) by failing with error(), which also
-- switches the script off. Walking exits ask for their load every frame the
-- player stands in them; the portal in map 107 asked once, at the end of its
-- pull-in animation, so its caller chain is the one to decompile.
--
-- 0.2: every trigger event the game runs goes through 0x1F2E90 (thiscall,
-- ecx = the event E: +0 -> its command's name, +4 argument count, +8 -> the
-- arguments, +0x10 -> the command, whose +0x10 object's vtable[0] is the exec,
-- called as exec(E, arg1, arg2)). This also records each distinct event in
-- order: the map, the command name, the exec address, E and its arguments.
-- (0.2 read the arguments from the wrong pointer.) The portal's prompt, pull-in and load are among
-- them; Time Rifts can then replay the same commands. Events are recorded in
-- the Portals (map 192) and the Evil Monastery (196) only, so other maps'
-- events don't use up the record.
local LOADMAP     = 0x00012883
local SAVE_GAME   = 0x001272A0
local GAMEPLAY    = 0x00154F60
local CURRENT_MAP = 0x00505970
local CODE_LO, CODE_HI = 0x00010000, 0x003D0000
local SCAN_WORDS  = 160            -- stack words above the call
local CHAIN       = 10             -- code addresses kept per request
local MAX_LOADS   = 8
local RUN_EVENT   = 0x001F2E90
local MAX_EVENTS  = 120
local EVENT_MAPS  = { [192] = true, [196] = true }   -- the Portals and the Evil Monastery
local ARG_WORDS   = 8

local loads = {}                    -- { key, text, count, first, last }
local events = {}                   -- { key, count, first } in first-seen order
local seen = {}                     -- key -> event
local frames = 0

local function hex(v)
    return string.format("%X", v)
end

local function chain(esp)
    local found = {}
    for i = 0, SCAN_WORDS - 1 do
        local v = game.read_u32(esp + i * 4)
        if v >= CODE_LO and v < CODE_HI then
            found[#found + 1] = hex(v) .. "@" .. hex(i * 4)
            if #found >= CHAIN then
                break
            end
        end
    end
    return table.concat(found, "/")
end

local function plausible(p)
    return p >= 0x10000 and p % 4 == 0 and (p < 0x00900000 or (p >= 0x80000000 and p < 0x84000000))
end

-- A command definition's arguments: "n<count>:w0,w1,..."
local function def_args(def)
    if not plausible(def) then
        return hex(def)
    end
    local count, args = game.read_u32(def + 4), game.read_u32(def + 8)
    if count > 16 or not plausible(args) then
        return hex(def)
    end
    local words = {}
    for i = 0, math.min(count, ARG_WORDS) - 1 do
        words[#words + 1] = hex(game.read_u32(args + i * 4))
    end
    return "n" .. count .. ":" .. table.concat(words, ",")
end

return {
    {
        address = RUN_EVENT,
        before = function(ctx)
            local event = ctx.ecx
            if not EVENT_MAPS[game.read_u32(CURRENT_MAP)] or not plausible(event) then
                return
            end
            local name = game.read_u32(event)
            local text = {}
            if plausible(name) then
                for i = 0, 15 do
                    local c = game.read_u8(name + i)
                    if c < 32 or c > 126 then
                        break
                    end
                    text[#text + 1] = string.char(c)
                end
            end
            local exec, object = 0, 0
            local command = game.read_u32(event + 0x10)
            if plausible(command) then
                object = game.read_u32(command + 0x10)
                if plausible(object) and plausible(game.read_u32(object)) then
                    exec = game.read_u32(game.read_u32(object))
                end
            end
            -- the replay needs the object the exec runs on (ecx) and what the
            -- dispatcher passes along (a1 -> exec arg1, a2 -> arg2, a3 -> [ecx+4])
            local key = hex(game.read_u32(CURRENT_MAP)) .. " " .. table.concat(text) .. "@" .. hex(exec)
                .. " C" .. hex(object) .. " E" .. hex(event) .. " " .. def_args(event)
                .. " a" .. hex(game.read_u32(ctx.esp + 4)) .. "," .. hex(game.read_u32(ctx.esp + 8))
                .. "," .. hex(game.read_u32(ctx.esp + 12))
            local e = seen[key]
            if e then
                e.count = e.count + 1
                return
            end
            if #events >= MAX_EVENTS then
                return
            end
            e = { key = key, count = 1, first = frames }
            seen[key] = e
            events[#events + 1] = e
        end,
    },
    {
        address = GAMEPLAY,
        before = function(ctx)
            frames = frames + 1
        end,
    },
    {
        address = LOADMAP,
        before = function(ctx)
            local object = game.read_u32(ctx.esp + 4)
            local args = game.read_u32(object + 8)
            local key = hex(game.read_u32(CURRENT_MAP)) .. ">" .. hex(game.read_u32(args))
                .. ":" .. game.read_u32(args + 4) .. ":" .. hex(object)
            for _, l in ipairs(loads) do
                if l.key == key then
                    l.count = l.count + 1
                    l.last = frames
                    return
                end
            end
            if #loads >= MAX_LOADS then
                return
            end
            loads[#loads + 1] = { key = key, count = 1, first = frames, last = frames,
                text = "n" .. game.read_u32(object + 4) .. " ret=" .. chain(ctx.esp) }
        end,
    },
    {
        address = SAVE_GAME,
        before = function(ctx)
            local out = {}
            for _, l in ipairs(loads) do
                out[#out + 1] = string.format("{%s x%d f%d-%d %s}", l.key, l.count, l.first, l.last, l.text)
            end
            local ev = {}
            for _, e in ipairs(events) do
                ev[#ev + 1] = string.format("[f%d x%d %s]", e.first, e.count, e.key)
            end
            error("PORTALTRACE 0.3 | " .. table.concat(out, " ") .. " | EVENTS " .. table.concat(ev, " "), 0)
        end,
    },
}
