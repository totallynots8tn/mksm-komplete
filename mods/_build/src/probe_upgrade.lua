-- MKSMK Probe: upgrade / dismember / brutality command signatures (diagnostics
-- only, changes nothing). The mk_upgrade prototype can unlock effects but a
-- routine cannot CALL game functions, so every effect must be wired by hooking
-- the game's own call and biasing its arguments. To do that we first need to
-- know, for each relevant command, which stack argument is the victim, which is
-- the bone/group/anim id, and which combat code path calls it. This script
-- samples those commands while you play, annotates any argument that points at
-- a character, records the caller return addresses, and writes ONE report to
-- the session log when the game saves (probe_save.lua).
--
-- Sampling starts immediately and each command is capped, so a normal session
-- with a few blade kills captures everything before the save. 0.9 adds the
-- engine dismember functions, an animation-event histogram (normal vs
-- fatality mode) and fatality/brutality state changes.
local WATCH = {
    [0x001A33E0] = { name = "enemy_detach_bone",  cap = 8, args = 3, rare = true  },
    [0x001A34A0] = { name = "enemy_detach_group", cap = 8, args = 3, rare = true  },
    [0x001A3350] = { name = "enemy_mutilate",     cap = 8, args = 3, rare = true  },
    [0x001A3450] = { name = "mutilate_collision", cap = 8, args = 4, rare = true  },
    [0x001A33A0] = { name = "enemy_resurrect",    cap = 3, args = 2, rare = true  },
    [0x0013A17]  = { name = "fatality",           cap = 4, args = 3, rare = true  },
    [0x0016C1C]  = { name = "finishhim",          cap = 4, args = 3, rare = true  },
    [0x00128B0]  = { name = "healthupgrade",      cap = 4, args = 3, rare = true  },
    [0x001286F]  = { name = "mkapowerup",         cap = 4, args = 3, rare = true  },
    [0x0018AAC0] = { name = "startanim",          cap = 6, args = 3, rare = false },
    [0x0016A00]  = { name = "reaction",           cap = 4, args = 3, rare = false },
    [0x0013A53]  = { name = "addexperience",      cap = 6, args = 3, rare = false },
    [0x00134F9]  = { name = "spawnexperience",    cap = 5, args = 3, rare = false },
    -- 0.9: the engine-level dismember functions the script commands above
    -- call. Combat reaches them from the animation-event dispatcher 0x180D30
    -- (bodydamage path), so blade kills show up here, not in the commands.
    [0x0010C3B0] = { name = "detach_bone",        cap = 10, args = 4, rare = true },
    [0x0010C600] = { name = "detach_group",       cap = 10, args = 4, rare = true },
    [0x0010BD70] = { name = "mutilate",           cap = 10, args = 4, rare = true },
}

-- 0.9: animation events. 0x180D30(entity, a2, type, a4, ...) dispatches one of
-- about 560 event types an animation fires on its frames (hits, detaches,
-- effects). Counted per type, split by player-owned vs other entities and by
-- whether fatality mode is active (0x58E068 +0x1A0 >= 10), so the types that
-- only appear in fatality/brutality mode point at the enhanced moves.
-- Fatality-mode state (+0x1A0, +0x1A4) and each player's brutality-off flag
-- ([0x58D6A8] + 0x318 + i*8 + 4) are logged when they change.
local ANIM_EVENT    = 0x00180D30
local FATAL_MODE    = 0x0058E068
local FATAL_MGR     = 0x0058D6A8
local TOP_TYPES     = 30
local STATE_CAP     = 40

local REPORT_AT     = 120
local FRAME         = 0x005CE878
local GAME_MANAGER  = 0x005ACEBC
local GAME_MODE     = 0x88
local XP_BASE       = 0x4940        -- player 0 (0.12: was 0x48F0, the slot below player 0)
local CHAR_TABLE    = 0x005D1AB8
local CHAR_STRIDE   = 0x3238
local CHAR_LIMIT    = 12
local ACTOR_OFFSET  = 0x200
local HEALTH        = 0x368
local STATS_LINK    = 0x2B6C
local STATS_HITS    = 0xC4
local CODE_LOW, CODE_HIGH = 0x11000, 0x3C6240

local function ok(p)
    return p >= 0x10000 and p % 4 == 0 and (p < 0x7FFE0000
        or (p >= 0x80000000 and p < 0x84000000)
        or (p >= 0xB0000000 and p < 0xC0000000)
        or (p >= 0xD0000000 and p < 0xE0000000)
        or (p >= 0xF0000000 and p < 0xF4000000))
end
local function hex(v) return string.format("%X", v) end
local function signed(v) if v >= 0x80000000 then return v - 0x100000000 end return v end

local entries = {}
local samples = {}
local anim_counts = {}            -- "p"/"o" .. ("F" in fatality mode) .. type -> count
local state_log, state_prev, state_frame = {}, nil, nil
local armed_at = nil
local first_sample_at = nil
local done = false

local function player_state()
    local manager = game.read_u32(GAME_MANAGER)
    if not ok(manager) then return "noplayer" end
    local mode = game.read_u32(manager + GAME_MODE)
    local xp = game.read_u32(manager + XP_BASE)
    local entity = CHAR_TABLE
    local actor = game.read_u32(entity + ACTOR_OFFSET)
    local hp = ok(actor) and signed(game.read_u32(actor + HEALTH)) or -999
    local link = game.read_u32(entity + STATS_LINK)
    local stats = ok(link) and game.read_u32(link + 0x50) or 0
    local hits = ok(stats) and game.read_u32(stats + STATS_HITS) or -1
    return "mode=" .. mode .. " hp=" .. hp .. " xp=" .. xp .. " combo=" .. hits
end

-- Reported when the game saves (probe_save.lua). Recording stops once
-- REPORT_AT entries are kept; each command is also capped (spec.cap).
local function anim_summary()
    local list = {}
    for key, n in pairs(anim_counts) do list[#list + 1] = { key = key, n = n } end
    table.sort(list, function(a, b) return a.n > b.n end)
    local out = {}
    for i = 1, math.min(#list, TOP_TYPES) do out[#out + 1] = list[i].key .. "=" .. list[i].n end
    -- every fatality-mode type, even rare ones
    for i = TOP_TYPES + 1, #list do
        if list[i].key:sub(2, 2) == "F" then out[#out + 1] = list[i].key .. "=" .. list[i].n end
    end
    return table.concat(out, " ")
end

local function report(reason)
    done = true
    error("UPGRADE " .. reason .. (#entries >= REPORT_AT and " full" or "") .. " frame=" .. game.read_u32(FRAME)
        .. " " .. player_state() .. " | " .. table.concat(entries, " ")
        .. " | ANIM " .. anim_summary()
        .. (#state_log > 0 and (" | STATE " .. table.concat(state_log, " ")) or ""), 0)
end

-- Fatality-mode / brutality state, once per frame; returns true in fatality mode.
local function fatality_state()
    local frame = game.read_u32(FRAME)
    local mode = signed(game.read_u32(FATAL_MODE + 0x1A0))
    if frame == state_frame then return mode >= 10 end
    state_frame = frame
    local over = signed(game.read_u32(FATAL_MODE + 0x1A4))
    local fm = game.read_u32(FATAL_MGR)
    local b0, b1 = -1, -1
    if ok(fm) then
        b0 = game.read_u32(fm + 0x318 + 4)
        b1 = game.read_u32(fm + 0x318 + 8 + 4)
    end
    local now = mode .. "/" .. over .. "/" .. b0 .. "/" .. b1
    if now ~= state_prev and #state_log < STATE_CAP then
        state_log[#state_log + 1] = "f" .. frame .. ":" .. now
    end
    state_prev = now
    return mode >= 10
end

local function record(text)
    if #entries < REPORT_AT then
        entries[#entries + 1] = text
    end
end

-- Annotate an argument that points at a character: "eN" for a char-table entity
-- slot, "cN" for a "char" script reference resolving to index N.
local function annotate(v)
    if v >= CHAR_TABLE and (v - CHAR_TABLE) % CHAR_STRIDE == 0 then
        local index = (v - CHAR_TABLE) // CHAR_STRIDE
        if index < CHAR_LIMIT then return "e" .. index end
    end
    if ok(v) and game.read_u8(v) == 0x63 then
        local index = game.read_u32(v + 0x10)
        if index < CHAR_LIMIT then return "c" .. index end
    end
    return nil
end

local function callers(esp)
    local found = {}
    for offset = 0, 0x40, 4 do
        local value = game.read_u32(esp + offset)
        if value >= CODE_LOW and value < CODE_HIGH then
            found[#found + 1] = hex(value)
            if #found >= 3 then break end
        end
    end
    return table.concat(found, "/")
end

local function sample(ctx, spec)
    if first_sample_at == nil then
        first_sample_at = game.read_u32(FRAME)
    end
    local parts = { "ecx=" .. hex(ctx.ecx) }
    local a = annotate(ctx.ecx)
    if a then parts[1] = parts[1] .. "(" .. a .. ")" end
    for i = 1, spec.args do
        local v = game.read_u32(ctx.esp + i * 4)
        local note = annotate(v)
        parts[#parts + 1] = hex(v) .. (note and ("(" .. note .. ")") or "")
    end
    record(spec.name .. "[" .. table.concat(parts, " ") .. "]@" .. callers(ctx.esp))
    if spec.rare and armed_at == nil then
        armed_at = game.read_u32(FRAME)
        record("ARM")
    end
end

local hooks = {}
for address, spec in pairs(WATCH) do
    hooks[#hooks + 1] = {
        address = address,
        before = function(ctx)
            if done then return end
            local n = samples[address] or 0
            if n >= spec.cap then return end
            samples[address] = n + 1
            sample(ctx, spec)
        end,
    }
end
hooks[#hooks + 1] = {
    address = ANIM_EVENT,
    before = function(ctx)
        if done then return end
        local entity = game.read_u32(ctx.esp + 4)
        local kind = game.read_u32(ctx.esp + 0xC)
        if kind > 0x400 then return end
        local owner = "o"
        if entity >= CHAR_TABLE and (entity - CHAR_TABLE) % CHAR_STRIDE == 0
            and (entity - CHAR_TABLE) // CHAR_STRIDE < 2 then owner = "p" end
        local key = owner .. (fatality_state() and "F" or "") .. hex(kind)
        anim_counts[key] = (anim_counts[key] or 0) + 1
    end,
}
hooks[#hooks + 1] = {
    address = SAVE_GAME,
    before = function(ctx)
        if save_due() and not done and (#entries > 0 or next(anim_counts) ~= nil) then report(save_tag("save")) end
    end,
}
return hooks
