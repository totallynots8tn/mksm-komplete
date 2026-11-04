-- MKSMK Probe: per-save stats (diagnostics only, changes nothing).
-- SAVEDIFF reports at saves 1-3 only, and never states the XP balance or which
-- slot was written; both had to be worked out from save.dat diffs. This copy
-- logs, at its SAVE_INDEX-th save of the session, the values that save writes:
-- playtime (+0x0), XP balance (+0x4940), the upgrade counters (+0xDC, +0x1C4,
-- +0x1D0), the health-upgrade count (+0xE0) and the characters (+0xCC/+0xD0) of the game manager, which uses the
-- same layout as a save.dat slot. The playtime matches the slot label
-- ("CHAR.MAP.PLAYTIME") of the slot written. The save routine's ecx and first
-- stack arguments are logged raw: the slot index is likely among them.
-- build.py ships copies with SAVE_INDEX 1..N.
-- 0.12 adds, per player p (P0/P1 groups): XP (+0x4940+p*0x50), meter value
-- (f32 +0x4954+p*0x50) and level (+0x4978+p*0x50), current/max health
-- (actor +0x368/+0x370); plus max health (+0x94) and the area's health level
-- (+0x90), and the fatality counters: discovered [0x4DFC1C], performed
-- [0x4DF5D8] (does the discovered list survive a reload?).
-- 0.12.3: instead of the shop's own slots, the whole 28-byte level row
-- (+0x1C4+p*0x1C+slot) as hex, one byte per slot 0-27. The shop keeps EX in
-- 23-26 and its levels in 27; 13-22 are the game's own (Purchase_combo calls
-- Upgrade(player, 13 + row)), so the row shows what the game writes there and
-- proves 23-26 stay untouched.
-- 0.12.6: `rifttrace=` records map-110 preload, trigger, callspawn,
-- group-start and spawn-entry activity for the Time Rifts work.
-- 0.12.7: keep these categories separately and aggregate repeats, so frequent
-- exit triggers cannot evict the arena setup or spawn evidence.
local GAME_MANAGER = 0x005ACEBC
local FRAME        = 0x005CE878
local MAP          = 0x00505970
local FIRE_EVENTS  = 0x0016ED90
local LOADMAP      = 0x00012883
local TRIG_MGR_PTR = 0x00682020
local TRIG_STRIDE  = 0xD8
local CHAR_TABLE   = 0x005D1AB8    -- player entities, 0x3238 apart; actor at +0x200
local FAT_FOUND    = 0x004DFC1C
local FAT_DONE     = 0x004DF5D8
local MAX_LOADMAP_LOGS = 8
local CALLSPAWN    = 0x001D2710
local CALLSPAWN_RC = 0x001D2740
local CALLSPAWN_MERGE = 0x001D2780
local LOAD_GROUPS  = 0x00014D2C
local PRELOAD      = 0x00015DEE
local START_GROUP  = 0x001D2600
local SPAWN_ENTRY  = 0x001D1D40
local ARENA_MAP    = 110
local ARENA_DESC   = 0x004FF2E8
local GROUP_MANAGER = 0x006DBFB0
local GROUP_STRIDE = 0xA6C
local ENTRY_BASE   = 0x18
local ENTRY_STRIDE = 0x74
local GROUP_COUNT  = 0xA68
local GROUP_ENABLED = 0xA6A
local GROUP_LIMIT  = 50
local ENTRY_LIMIT  = 22
local MAX_RIFT_TRIGGERS = 16
local MAX_RIFT_SAMPLES = 12
local ARENA_TARGET = ARENA_MAP + 1

local function hex(v) return string.format("%X", v) end
local function ok(p)
    return p >= 0x10000 and p % 4 == 0 and (p < 0x7FFE0000 or (p >= 0x80000000 and p < 0x84000000)
        or (p >= 0xD0000000 and p < 0xE0000000))
end

local done = false
local last_trigger = nil
local loadmap_count = 0
local loadmap_logs = {}
local trigger_stack = {}
local rift_preloads = {}
local rift_spawn_files = {}
local rift_group_files = {}
local rift_triggers = {}
local rift_trigger_order = {}
local rift_trigger_defs = {}
local rift_callspawns = {}
local rift_groups = {}
local rift_spawns = {}
local spawn_trace_stack = {}
local arena_load_pending = false

local function rift_sample(list, key, cap)
    for _, sample in ipairs(list) do
        if sample.key == key then
            sample.count = sample.count + 1
            sample.last = hex(game.read_u32(FRAME))
            return sample
        end
    end
    if #list >= cap then return nil end
    local frame = hex(game.read_u32(FRAME))
    local sample = { key = key, count = 1, first = frame, last = frame }
    list[#list + 1] = sample
    return sample
end

local function rift_samples_text(list)
    local out = {}
    for i, sample in ipairs(list) do
        out[i] = sample.key .. "x" .. sample.count .. "@" .. sample.first .. "-" .. sample.last
            .. (sample.result and "r" .. sample.result or "")
    end
    return #out > 0 and table.concat(out, "/") or "-"
end

local function rift_trace_text()
    local triggers = {}
    for i, id in ipairs(rift_trigger_order) do
        local sample = rift_triggers[id]
        triggers[i] = id .. "x" .. sample.count .. "@" .. sample.first .. "-" .. sample.last
            .. "{" .. rift_trigger_defs[id] .. "}"
    end
    return "P[" .. rift_samples_text(rift_preloads) .. "]"
        .. ",D[" .. rift_samples_text(rift_spawn_files) .. "]"
        .. ",LG[" .. rift_samples_text(rift_group_files) .. "]"
        .. ",T[" .. (#triggers > 0 and table.concat(triggers, "/") or "-") .. "]"
        .. ",C[" .. rift_samples_text(rift_callspawns) .. "]"
        .. ",G[" .. rift_samples_text(rift_groups) .. "]"
        .. ",S[" .. rift_samples_text(rift_spawns) .. "]"
end

local TRIGGER_NAMES = {
    [0x110CD]="musicenable", [0x114EC]="minimapobj", [0x115F5]="onvsroundend",
    [0x117EE]="isvs", [0x1183E]="onbreak", [0x118D4]="exitgame",
    [0x11938]="addstonepower", [0x11C1C]="MapLocked", [0x11D7A]="spawntutorial",
    [0x11E51]="Fatalityused", [0x12883]="loadmap", [0x13134]="gameevent",
    [0x14BCE]="eventnotcomplete", [0x146A1]="actionButton", [0x156CD]="isoneplayer",
    [0x15BDC]="friendlyfire", [0x16A4B]="eventcomplete", [0x16C1C]="finishhim",
    [0x170290]="firetrigger", [0x170330]="activatetrigger",
}

local function trigger_definition(index, rec, mgr)
    local count = game.read_u32(rec + 0x58)
    local slots = game.read_u32(rec + 0x5C)
    local args = game.read_u32(rec + 0x60)
    local conditions = {}
    if count <= 12 and (count == 0 or (ok(slots) and ok(args))) then
        for i = 0, count - 1 do
            local slot = game.read_u32(slots + i * 4)
            local name = "?" .. slot
            if slot <= game.read_u32(mgr + 0x1254C) then
                local obj = game.read_u32(mgr + slot * 24 + 0x11C00)
                if ok(obj) then
                    local vt = game.read_u32(obj)
                    if ok(vt) then
                        local execute = game.read_u32(vt)
                        name = TRIGGER_NAMES[execute] or hex(execute)
                    end
                end
            end
            conditions[#conditions + 1] = name .. ":" .. hex(game.read_u32(args + i * 4))
        end
    else
        conditions[1] = "conditions?"
    end
    local def = game.read_u32(rec + 0xC)
    local flags = ok(def) and game.read_u32(def + 0x70) or 0
    local need = ok(def) and game.read_u8(def + 0x79) or 0
    return "f" .. hex(flags) .. "n" .. need .. "c" .. game.read_u32(rec + 0xCC)
        .. "d" .. (ok(def) and hex(def) or "?")
        .. "e" .. hex(game.read_u32(rec + 0x64)) .. ":" .. table.concat(conditions, "/")
end

local function rift_trigger(index, rec, mgr)
    local sample = rift_triggers[index]
    if sample then
        sample.count = sample.count + 1
        sample.last = hex(game.read_u32(FRAME))
    elseif #rift_trigger_order < MAX_RIFT_TRIGGERS then
        local frame = hex(game.read_u32(FRAME))
        rift_triggers[index] = { count = 1, first = frame, last = frame }
        rift_trigger_defs[index] = trigger_definition(index, rec, mgr)
        rift_trigger_order[#rift_trigger_order + 1] = index
    end
end

local function active_rift_trigger()
    if game.read_u32(MAP) ~= ARENA_MAP then return nil end
    local active = trigger_stack[#trigger_stack]
    return active and active.index or nil
end

local function fired_trigger(ctx)
    local mgr = game.read_u32(TRIG_MGR_PTR)
    if not ok(mgr) or not ctx.ecx or ctx.ecx < 0x68 then return nil end
    local rec = ctx.ecx - 0x68
    if rec < mgr or (rec - mgr) % TRIG_STRIDE ~= 0 then return nil end
    local idx = (rec - mgr) // TRIG_STRIDE
    local count = game.read_u32(mgr + 0xA8C0)
    if idx < 0 or idx >= count or idx >= 1000 then return nil end
    return idx
end

local function log_loadmap(ctx)
    loadmap_count = loadmap_count + 1
    local active = trigger_stack[#trigger_stack]
    local trigger = active and active.index
    local frame = hex(game.read_u32(FRAME))
    local cur = game.read_u32(MAP)
    local def, args
    if ok(ctx.esp) then def = game.read_u32(ctx.esp + 4) end
    if def and ok(def) then args = game.read_u32(def + 8) end
    local to, entry
    if args and ok(args) then
        to, entry = game.read_u32(args), game.read_u32(args + 4)
    end
    arena_load_pending = to == ARENA_TARGET
    if to == ARENA_TARGET then
        local cap = game.read_u32(ARENA_DESC + 0x20)
        local items = {}
        if cap <= 8 then
            for i = 0, cap - 1 do
                local kind = game.read_u32(ARENA_DESC + 0x24 + i * 4)
                items[#items + 1] = kind == 0xFFFFFFFF and "-" or hex(kind)
            end
        end
        rift_sample(rift_spawn_files, hex(game.read_u32(ARENA_DESC + 0x7C)), 4)
        rift_sample(rift_preloads, cap .. "[" .. table.concat(items, "/") .. "]", 4)
    end
    local key = table.concat({ cur, def and hex(def) or "?", args and hex(args) or "?",
        to and to or "?", entry and entry or "?" }, ":")
    local last = loadmap_logs[#loadmap_logs]
    if last and last.key == key then
        -- The game can call the same loader request every frame while an area
        -- transition is in progress. Compress that run so it cannot evict the
        -- preceding portal request from this short history.
        last.last = frame
        last.count = last.count + 1
        if trigger then last.trigger = trigger end
    else
        loadmap_logs[#loadmap_logs + 1] = { key = key, first = frame, last = frame,
            count = 1, trigger = trigger, cur = cur, def = def, args = args,
            to = to, entry = entry }
        if #loadmap_logs > MAX_LOADMAP_LOGS then table.remove(loadmap_logs, 1) end
    end
end

local function group_text(group)
    local base = GROUP_MANAGER + group * GROUP_STRIDE
    local count = game.read_u16(base + GROUP_COUNT)
    local enabled = game.read_u8(base + GROUP_ENABLED)
    local kinds = {}
    if count <= ENTRY_LIMIT then
        for i = 0, math.min(count, 3) - 1 do
            kinds[#kinds + 1] = hex(game.read_u32(base + ENTRY_BASE + i * ENTRY_STRIDE))
        end
    end
    return "G" .. group .. ":" .. count .. "/" .. enabled .. "[" .. table.concat(kinds, "/") .. "]"
end

local function callspawn_group(ctx)
    if not ok(ctx.esp) then return nil end
    local def = game.read_u32(ctx.esp + 4)
    if not ok(def) then return nil end
    local args = game.read_u32(def + 8)
    if not ok(args) then return nil end
    return game.read_u32(args)
end

local function spawn_entry_info(ctx)
    if not ok(ctx.esp) then return nil end
    local entry = game.read_u32(ctx.esp + 4)
    if not ok(entry) or entry < GROUP_MANAGER + ENTRY_BASE then return nil end
    local rel = entry - GROUP_MANAGER
    local group = rel // GROUP_STRIDE
    local offset = rel % GROUP_STRIDE
    if group >= GROUP_LIMIT or offset < ENTRY_BASE or (offset - ENTRY_BASE) % ENTRY_STRIDE ~= 0 then return nil end
    local slot = (offset - ENTRY_BASE) // ENTRY_STRIDE
    if slot >= ENTRY_LIMIT then return nil end
    local delay = game.read_u16(entry + 0x5A)
    return { group = group, slot = slot, kind = game.read_u32(entry), delay = delay }
end

local function coord(value)
    if value ~= value or value < -1000000 or value > 1000000 then return "?" end
    return string.format("%.0f", value)
end

local function loadmap_text(load)
    return "F" .. load.first .. "-" .. load.last .. "x" .. load.count
        .. ":T" .. (load.trigger and load.trigger or "-") .. ":cur" .. load.cur
        .. (load.def and (":def" .. hex(load.def)) or "")
        .. (load.args and (":data" .. hex(load.args)) or "")
        .. (load.to and (":to" .. load.to) or "")
        .. (load.entry and (":entry" .. load.entry) or "")
end

local function player(gm, p)
    local slots = gm + 0x1C4 + p * 0x1C
    local row = {}
    for s = 0, 27 do row[#row + 1] = string.format("%02X", game.read_u8(slots + s)) end
    local actor = game.read_u32(CHAR_TABLE + p * 0x3238 + 0x200)
    local hp = ok(actor) and (game.read_u32(actor + 0x368) .. "/" .. game.read_u32(actor + 0x370)) or "-"
    return " P" .. p .. "[xp=" .. game.read_u32(gm + 0x4940 + p * 0x50)
        .. " mv=" .. math.floor(game.read_f32(gm + 0x4954 + p * 0x50))
        .. " ml=" .. game.read_u32(gm + 0x4978 + p * 0x50)
        .. " row=" .. table.concat(row, "") .. " hp=" .. hp .. "]"
end

local function report(ctx)
    done = true
    local gm = game.read_u32(GAME_MANAGER)
    local fields = "gm=" .. hex(gm)
    if ok(gm) then
        fields = fields .. " playtime=" .. hex(game.read_u32(gm)) .. " xp=" .. game.read_u32(gm + 0x4940)
            .. " chars=" .. hex(game.read_u32(gm + 0xCC)) .. "," .. hex(game.read_u32(gm + 0xD0))
            .. " +DC=" .. hex(game.read_u32(gm + 0xDC)) .. " +E0=" .. hex(game.read_u32(gm + 0xE0)) .. " +1C4=" .. hex(game.read_u32(gm + 0x1C4))
            .. " +1D0=" .. hex(game.read_u32(gm + 0x1D0))
            .. player(gm, 0) .. player(gm, 1)
            .. " maxhp=" .. game.read_u32(gm + 0x94) .. " hplvl=" .. game.read_u32(gm + 0x90)
            .. " fat=" .. game.read_u32(FAT_FOUND) .. "/" .. game.read_u32(FAT_DONE)
    end
    local args = {}
    if ok(ctx.esp) then
        for i = 1, 4 do args[#args + 1] = hex(game.read_u32(ctx.esp + i * 4)) end
    end
    local load_text = {}
    for i, load in ipairs(loadmap_logs) do load_text[i] = loadmap_text(load) end
    local loads = #load_text > 0 and table.concat(load_text, ",") or "-"
    local rift = rift_trace_text()
    error("SAVESTAT " .. save_tag("save") .. " frame=" .. hex(game.read_u32(FRAME))
        .. " map=" .. game.read_u32(MAP) .. " last_trigger=" .. (last_trigger and ("T" .. last_trigger) or "-")
        .. " loadmaps=" .. loadmap_count .. " loadcalls=" .. loads .. " rifttrace=" .. rift .. " " .. fields
        .. " ecx=" .. hex(ctx.ecx or 0) .. " args=" .. table.concat(args, ","), 0)
end

return {
    {   address = FIRE_EVENTS,
        before = function(ctx)
            local idx = fired_trigger(ctx)
            trigger_stack[#trigger_stack + 1] = { index = idx }
            if idx then last_trigger = idx end
            if idx and game.read_u32(MAP) == ARENA_MAP then
                rift_trigger(idx, ctx.ecx - 0x68, game.read_u32(TRIG_MGR_PTR))
            end
        end,
        after = function()
            trigger_stack[#trigger_stack] = nil
        end,
    },
    {   address = LOADMAP,
        before = function(ctx)
            log_loadmap(ctx)
        end },
    {   address = PRELOAD,
        before = function(ctx)
            local desc = ok(ctx.esp) and game.read_u32(ctx.esp + 4) or 0
            if desc ~= ARENA_DESC then return end
            local cap = game.read_u32(desc + 0x20)
            local items = {}
            if cap <= 8 then
                for i = 0, cap - 1 do
                    local kind = game.read_u32(desc + 0x24 + i * 4)
                    items[#items + 1] = kind == 0xFFFFFFFF and "-" or hex(kind)
                end
            end
            rift_sample(rift_spawn_files, hex(game.read_u32(desc + 0x7C)), 4)
            rift_sample(rift_preloads, cap .. "[" .. table.concat(items, "/") .. "]", 4)
            arena_load_pending = false
        end },
    {   address = LOAD_GROUPS,
        before = function()
            if game.read_u32(MAP) == ARENA_MAP or arena_load_pending then
                rift_sample(rift_group_files, hex(game.read_u32(ARENA_DESC + 0x7C)), 4)
            end
        end,
        after = function()
            arena_load_pending = false
        end },
    {   address = CALLSPAWN,
        before = function(ctx)
            if game.read_u32(MAP) ~= ARENA_MAP then return end
            local group = callspawn_group(ctx)
            local trigger = active_rift_trigger()
            rift_sample(rift_callspawns, "T" .. (trigger or "-") .. ":" .. (group and tostring(group) or "?"), MAX_RIFT_SAMPLES)
        end },
    {   address = CALLSPAWN_RC,
        before = function(ctx)
            if game.read_u32(MAP) ~= ARENA_MAP then return end
            local group = callspawn_group(ctx)
            local trigger = active_rift_trigger()
            rift_sample(rift_callspawns, "RC:T" .. (trigger or "-") .. ":" .. (group and tostring(group) or "?"), MAX_RIFT_SAMPLES)
        end },
    {   address = CALLSPAWN_MERGE,
        before = function(ctx)
            if game.read_u32(MAP) ~= ARENA_MAP then return end
            local group = callspawn_group(ctx)
            local trigger = active_rift_trigger()
            rift_sample(rift_callspawns, "M:T" .. (trigger or "-") .. ":" .. (group and tostring(group) or "?"), MAX_RIFT_SAMPLES)
        end },
    {   address = START_GROUP,
        before = function(ctx)
            if ctx.ecx ~= GROUP_MANAGER or game.read_u32(MAP) ~= ARENA_MAP then return end
            local group = game.read_u32(ctx.esp + 4)
            if group < GROUP_LIMIT then
                local trigger = active_rift_trigger()
                rift_sample(rift_groups, "T" .. (trigger or "-") .. ":" .. group_text(group), MAX_RIFT_SAMPLES)
            end
        end },
    {   address = SPAWN_ENTRY,
        before = function(ctx)
            if game.read_u32(MAP) ~= ARENA_MAP then return end
            local entry = spawn_entry_info(ctx)
            if not entry then return end
            local ptr = game.read_u32(ctx.esp + 4)
            local xyz = coord(game.read_f32(ptr + 0x18)) .. "/" .. coord(game.read_f32(ptr + 0x1C))
                .. "/" .. coord(game.read_f32(ptr + 0x20))
            local trigger = active_rift_trigger()
            local key = "T" .. (trigger or "-") .. ":" .. entry.group .. "." .. entry.slot .. ":" .. hex(entry.kind)
                .. "d" .. entry.delay .. "p" .. xyz
            spawn_trace_stack[#spawn_trace_stack + 1] = rift_sample(rift_spawns, key, MAX_RIFT_SAMPLES) or false
        end,
        after = function(ctx)
            local sample = spawn_trace_stack[#spawn_trace_stack]
            spawn_trace_stack[#spawn_trace_stack] = nil
            if sample then sample.result = hex(ctx.eax or 0) end
        end },
    {   address = SAVE_GAME,
        before = function(ctx)
            if not done and save_due() then report(ctx) end
        end },
}
