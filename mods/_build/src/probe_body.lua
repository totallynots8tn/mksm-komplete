-- MKSMK Probe: records what happens around kills, XP and spawns, and writes
-- it to the game log when the game saves (probe_save.lua; the runtime logs
-- "Mod routine: mksmk_probe: EVENTS ..."). It changes nothing in the game.
local SET_HEALTH    = 0x00153CD0
local KILL_AND_HIDE = 0x001F25B0
local APPLY_DAMAGE  = 0x00153DC0
local BODY_DAMAGE   = 0x00180CA0
local SET_XP        = 0x00015CD1
local START_GROUP   = 0x001D2600
local SPAWN_ENTRY   = 0x001D1D40
local CHAR_TABLE    = 0x005D1AB8
local CHAR_STRIDE   = 0x3238
local GAME_MANAGER  = 0x005ACEBC
local COMBO_COUNTER = 0x005ACE9C
local MANAGER       = 0x006DBFB0
local INTERFACE     = 0x006322F8
local HEAP_REGISTRY = 0x0062EC60
local CHAR_POOL     = 0x00510040
local CODE_LOW, CODE_HIGH = 0x11000, 0x3C6240

local function ok(p)
    return p >= 0x10000 and (p < 0x7FFE0000 or (p >= 0x80000000 and p < 0x84000000)
        or (p >= 0xB0000000 and p < 0xC0000000) or (p >= 0xD0000000 and p < 0xE0000000))
end
local function hex(v) return string.format("%X", v) end
local function signed(v) if v >= 0x80000000 then return v - 0x100000000 end return v end

local add = log_add
local done = false

local function report(reason)
    done = true
    local manager = game.read_u32(GAME_MANAGER)
    local mode = ok(manager) and game.read_u32(manager + 0x88) or -1
    error("EVENTS " .. reason .. " mode=" .. mode .. " n=" .. log_count() .. " | " .. log_text(), 0)
end

local function callers(esp)
    local found = {}
    for offset = 0, 0x7C, 4 do
        local value = game.read_u32(esp + offset)
        if value >= CODE_LOW and value < CODE_HIGH then
            found[#found + 1] = hex(value)
            if #found >= 4 then break end
        end
    end
    return table.concat(found, "/")
end

local function index_of(actor)
    if not ok(actor) then return -1 end
    local entity = game.read_u32(actor + 0x31C)
    if entity < CHAR_TABLE or (entity - CHAR_TABLE) % CHAR_STRIDE ~= 0 then return -1 end
    return (entity - CHAR_TABLE) // CHAR_STRIDE
end

local function char_ref(ctx, at)
    local reference = game.read_u32(ctx.esp + at)
    if not ok(reference) or game.read_u8(reference) ~= 0x63 then return nil end
    local index = game.read_u32(reference + 0x10)
    if index >= 12 then return nil end
    local actor = game.read_u32(CHAR_TABLE + index * CHAR_STRIDE + 0x200)
    return index, actor
end

local function heap_free(heap)
    if heap >= 0x80 then return -1, -1 end
    local record = HEAP_REGISTRY + heap * 0x68
    local total = game.read_u32(record + 4)
    if game.read_u32(record + 0x1C) ~= 0 then
        local node, free, n = game.read_u32(record + 0x20), 0, 0
        while node ~= 0 and n < 64 and ok(node) do
            local a, b = game.read_u32(node + 8), game.read_u32(node + 0xC)
            if b > a then free = free + b - a end
            node = game.read_u32(node + 4); n = n + 1
        end
        return free, total
    end
    return game.read_u32(record + 0xC) - game.read_u32(record + 8), total
end

local function slots()
    local count, tbl = game.read_u32(INTERFACE + 0x10), game.read_u32(INTERFACE + 0x24)
    local out = {}
    if count > 16 or not ok(tbl) then return out end
    for i = 0, count - 1 do
        local heap, kind = game.read_u32(tbl + i * 20), game.read_u32(tbl + i * 20 + 4)
        local free, total = heap_free(heap)
        out[#out + 1] = { kind = kind, heap = heap, free = free, total = total }
    end
    return out
end

-- XP watcher: the SetXP thunk is called directly and bypasses hooks, so
-- watch the XP values instead and log every increase with the combo count and
-- the last recorded death.
local last_xp = nil
local last_death = "-"
local function xp_watch()
    local manager = game.read_u32(GAME_MANAGER)
    if not ok(manager) then return end
    local xp = game.read_u32(manager + 0x48F0 + 0x50)
    if last_xp and xp > last_xp then
        local combo = game.read_u32(COMBO_COUNTER)
        local hits = ok(combo) and game.read_u32(combo) or -1
        add("XP+" .. (xp - last_xp) .. "c" .. hits .. "<" .. last_death)
    end
    last_xp = xp
end

local pending_damage = {}
local spawn_before = nil

return {
    {   address = SET_HEALTH,
        before = function(ctx)
            local actor = ctx.ecx
            if not ok(actor) then return end
            local old, new = signed(game.read_u32(actor + 0x368)), signed(game.read_u32(ctx.esp + 4))
            xp_watch()
            if old > 0 and new <= 0 then
                last_death = "D" .. index_of(actor) .. "@" .. callers(ctx.esp)
                add(last_death)
            end
        end },
    {   address = KILL_AND_HIDE,
        before = function(ctx)
            local index, actor = char_ref(ctx, 8)
            if index then
                local hp = ok(actor) and signed(game.read_u32(actor + 0x368)) or -999
                add("K" .. index .. ":" .. hp .. "@" .. callers(ctx.esp))
            end
        end },
    {   address = APPLY_DAMAGE,
        before = function(ctx)
            local index, actor = char_ref(ctx, 8)
            pending_damage.a = index and { index, actor, signed(game.read_u32(actor + 0x368)) } or nil
        end,
        after = function(ctx)
            local p = pending_damage.a
            if p and ok(p[2]) then add("A" .. p[1] .. ":" .. p[3] .. ">" .. signed(game.read_u32(p[2] + 0x368))) end
            pending_damage.a = nil
        end },
    {   address = BODY_DAMAGE,
        before = function(ctx)
            local index, actor = char_ref(ctx, 8)
            pending_damage.b = index and { index, actor, signed(game.read_u32(actor + 0x368)) } or nil
        end,
        after = function(ctx)
            local p = pending_damage.b
            if p and ok(p[2]) then add("B" .. p[1] .. ":" .. p[3] .. ">" .. signed(game.read_u32(p[2] + 0x368))) end
            pending_damage.b = nil
        end },
    {   address = SET_XP,
        before = function(ctx)
            local player, value = game.read_u32(ctx.esp + 4), game.read_u32(ctx.esp + 8)
            local manager = game.read_u32(GAME_MANAGER)
            if player > 4 or not ok(manager) then return end
            local old = game.read_u32(manager + 0x48F0 + player * 0x50)
            local combo = game.read_u32(COMBO_COUNTER)
            local hits = ok(combo) and game.read_u32(combo) or -1
            add("X" .. player .. ":+" .. (value - old) .. "c" .. hits .. "@" .. callers(ctx.esp))
        end },
    {   address = 0x001D23F0,          -- spawn tick: runs every frame in fights
        before = function(ctx) xp_watch() end },
    {   address = START_GROUP,
        before = function(ctx)
            xp_watch()
            if ctx.ecx ~= MANAGER then return end
            local group = game.read_u32(ctx.esp + 4)
            if group >= 50 then return end
            local flags, pool_free = game.read_u32(CHAR_POOL + 0xC), 0
            if ok(flags) then
                for i = 0, 11 do if game.read_u16(flags + i * 2) == 0 then pool_free = pool_free + 1 end end
            end
            local parts = {}
            for _, s in ipairs(slots()) do parts[#parts + 1] = hex(s.kind) .. "=" .. hex(s.free) .. "/" .. hex(s.total) end
            local loaded = {}
            for i = 0, 5 do loaded[#loaded + 1] = hex(game.read_u32(0x6CA69C + i * 4)) end
            add("G" .. group .. "n" .. game.read_u16(MANAGER + group * 0xA6C + 0xA68) .. "p" .. pool_free
                .. "[" .. table.concat(parts, ",") .. "]L" .. table.concat(loaded, ","))
        end },
    {   address = SPAWN_ENTRY,
        before = function(ctx)
            spawn_before = {}
            for i, s in ipairs(slots()) do spawn_before[i] = s end
        end,
        after = function(ctx)
            if spawn_before == nil then return end
            for i, s in ipairs(slots()) do
                local b = spawn_before[i]
                if b and b.heap == s.heap and s.free < b.free then
                    add("S" .. hex(s.kind) .. ":" .. hex(b.free - s.free) .. (ctx.eax == 0 and "!fail" or ""))
                end
            end
            if ctx.eax == 0 then add("F") end
            spawn_before = nil
        end },
    {   address = SAVE_GAME,
        before = function(ctx)
            if save_due() and not done and log_count() > 0 then report(save_tag("save")) end
        end },
}
