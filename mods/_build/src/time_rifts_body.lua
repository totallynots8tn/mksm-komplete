-- Time Rifts 0.6.0 QA: the rift loop without a portal model. Step into the
-- big hollow tree in Wu Shi's arena (map 110) and the arena reloads (the load
-- request the game's loadmap command makes); when it is back, one Orochi
-- drops in mid-arena in front of the tree and waits there. Both spots were
-- read live from P1 on 2026-10-31. When the Orochi is beaten (or something
-- fails) the script writes one TIMERIFT line to the log by failing with
-- error(), which also switches it off. One rift per session.
--
-- Time Rifts is extra content, not part of the randomizer: it never touches
-- a map's preload list (Shaolin Shuffle's) or any authored spawn entry. Map
-- 110 has no spawn-group file, so the rift switches off whatever groups the
-- manager still holds and builds group 1 as a one-entry boss group that only
-- the rift starts.
--
-- Loading the boss: a type the level hasn't loaded only streams in on the spot
-- into one of the first <count> memory slots (0x17B030 scans [0x6322F8+0x10]
-- of them: 3 in the arena, all still holding the Wu Shi entrance's types), so
-- the rift loads it the way cutscenes swap characters: the modelstream command
-- (0x17BA00) queues (slot, type) for 0x17BA40, which unloads that slot and
-- loads the type there. Live-tested 2026-10-31: slot 2's type 77 became the
-- Oni, which could spawn about 1 s later. The rift picks a slot whose type has
-- no living actor.
--
-- The reload: loadmap (0xD0E00) only requests a load when a player has bit
-- 0x40 at +0x3204, which the exit and portal triggers provide; out in the
-- arena it quietly does nothing (0.5.6, QA 2026-10-31 16:0x: reload=never).
-- What it writes when it does is all a load request is: both players'
-- +0x3217 = 1, 0x5ACEE0 = 0, the target map 0x4FC160 and entry 0x4FC164,
-- and the request flag 0x5ACEDC = 1. The rift writes the same.
--
-- 0.6.0: the rift's boss is the Orochi (type 0x1E, the one normal rooms
-- author; the Hellbeast boss is 28). The Oni Warlord spawned on its spot but
-- leapt out over the bamboo fence (QA 2026-10-31 16:25 and 16:3x), and moving
-- it back didn't stick: an entity keeps its position at +0x80, +0xE0,
-- +0x2C60 and +0x3164. The report notes where the boss first stands.
--
-- History: the QA crashes of 2026-10-31 14:06 and 14:12 were Shaolin Shuffle
-- 0.11.2 loading the Wu Shi entrance, not the rift. 0.5.5 spawned the Oni
-- (QA 15:31) but inside the tree, at the spot read from Liu standing in its
-- hollow, and its alive check read the wrong entities, so it reported
-- oni=never while the Oni was up.
local GAMEPLAY      = 0x00154F60    -- gameplay update; skipped while paused
local LOAD_REQUEST  = 0x005ACEDC    -- u8: a map load is wanted
local LOAD_ARG3     = 0x005ACEE0
local LOAD_MAP      = 0x004FC160
local LOAD_ENTRY    = 0x004FC164
local PLAYER_LOADING = 0x3217       -- u8 on each player entity, set by loadmap
local START_GROUP   = 0x001D2600    -- spawn manager thiscall (group, entity index or -1, 0); ret 0xC
local MODELSTREAM   = 0x0017BA00    -- modelstream command: [[arg1+8]] = slot, type
local PRELOAD       = 0x00015DEE

local CURRENT_MAP   = 0x00505970
local ARENA_MAP     = 110
local ARENA_ENTRY   = 1             -- where the Wu Shi entrance's door lands
local ARENA_DESC    = 0x004FF2E8
local NONE          = 0xFFFFFFFF
local MANAGER       = 0x006DBFB0
local GROUP_STRIDE  = 0xA6C
local GROUP_LIMIT   = 50
local ENTRY_BASE    = 0x18
local COUNT_OFFSET  = 0xA68
local ENABLED_OFFSET = 0xA6A
local RIFT_GROUP    = 1
local RIFT_BOSS     = 30            -- Orochi (0x1E); the Oni Warlord was 36

local PLAYER        = 0x005D1AB8    -- entity of in-use flag 0 (P1); position floats at +0x80
local ENTITY_STRIDE = 0x3238
local ENTITY_TYPE   = 0x1DFE        -- u16 character ID (kept after death)
local ENTITY_FLAGS  = 0x0051004C    -- -> u16 per entity, non-zero while in use
local ENTITY_COUNT  = 12
local SLOTS         = 0x006322F8    -- memory slots: +0x10 count, +0x24 -> 20-byte rows
local SLOT_ROW      = 20            -- +0x04 type
local LOADED_TYPES  = 0x006CA69C    -- 6 words: the types that can spawn right now
local LOADED_COUNT  = 6
local PORTAL_X, PORTAL_Y, PORTAL_Z = -7337.944, -1076.305, 841.819   -- in the hollow tree
local BOSS_X, BOSS_Y, BOSS_Z = -4049.003, -1088.373, -258.222              -- mid-arena, facing the tree
local ENTER_RADIUS  = 150           -- step this close to open the rift
local ARM_RADIUS    = 400           -- and come from at least this far away
local SETTLE        = 60            -- frames after the reload before the boss loads
local WAIT_LOAD     = 1800          -- frames to wait for the reload, the load, the spawn

-- The rift's spawn entry: a plain map-104 entry read live (group 4, 2026-10-31)
-- with the Oni's type. Spawning it (0x1D1D40) reads +0x18..+0x20 as integer
-- coordinates: world coordinates when the group was started with entity
-- index -1 (as the callspawn command 0x1D2710 does), an offset from that
-- entity otherwise when +0x58 is 1.
local ENTRY_TEMPLATE = {
    RIFT_BOSS, NONE, NONE, 0x0B, NONE, NONE, 0, 0, 0xFFFFFC18, NONE,
    0, NONE, 0, 0, 0, 0, 4, 2, 0, 0, 0, 0, 1, NONE, NONE, NONE, NONE, 0x3E8, 0,
}

callgate.target(MODELSTREAM)
callgate.target(START_GROUP)

local state = "idle"     -- idle, armed, reloading, arrived, streaming, dropping, fighting
local frames, mark = 0, 0
local notes = {}

local function note(text)
    notes[#notes + 1] = text
end

local function report(verdict)
    error("TIMERIFT 0.6.0 " .. verdict .. " | " .. table.concat(notes, " "), 0)
end

local function enter(next_state)
    state = next_state
    mark = frames
end

local function distance_to_portal()
    local dx = game.read_f32(PLAYER + 0x80) - PORTAL_X
    local dy = game.read_f32(PLAYER + 0x84) - PORTAL_Y
    local dz = game.read_f32(PLAYER + 0x88) - PORTAL_Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- The in-use entity of character `kind`, or nil.
local function entity_of(kind)
    local flags = game.read_u32(ENTITY_FLAGS)
    for i = 0, ENTITY_COUNT - 1 do
        local entity = PLAYER + i * ENTITY_STRIDE
        if game.read_u16(flags + i * 2) ~= 0 and game.read_u16(entity + ENTITY_TYPE) == kind then
            return entity
        end
    end
    return nil
end

local function alive_of(kind)
    return entity_of(kind) ~= nil
end

-- Whether `kind` can spawn. After modelstream the slot row shows the type
-- within 0.2 s, but the type only joins this list once its files have
-- loaded, about 1 s later.
local function is_loaded(kind)
    for i = 0, LOADED_COUNT - 1 do
        if game.read_u32(LOADED_TYPES + i * 4) == kind then
            return true
        end
    end
    return false
end

-- A slot the Oni may take: the last one whose type has no living actor.
local function free_slot()
    local rows = game.read_u32(SLOTS + 0x24)
    for i = game.read_u32(SLOTS + 0x10) - 1, 0, -1 do
        local kind = game.read_u32(rows + i * SLOT_ROW + 4)
        if kind == NONE or not alive_of(kind) then
            return i
        end
    end
    return nil
end

local function group_base(group)
    return MANAGER + group * GROUP_STRIDE
end

local function failed(name)
    return function(eax)
        if eax == nil then
            note(name .. "=BAD")
            report("CHECK")
        end
    end
end

local function open_rift()
    enter("reloading")
    note(string.format("open@%d(d=%.0f)", frames, distance_to_portal()))
    game.write_u8(PLAYER + PLAYER_LOADING, 1)
    game.write_u8(PLAYER + ENTITY_STRIDE + PLAYER_LOADING, 1)
    game.write_u32(LOAD_ARG3, 0)
    game.write_u32(LOAD_MAP, ARENA_MAP)
    game.write_u32(LOAD_ENTRY, ARENA_ENTRY)
    game.write_u8(LOAD_REQUEST, 1)
end

local function stream_oni()
    enter("streaming")
    if is_loaded(RIFT_BOSS) then
        return
    end
    local slot = free_slot()
    if slot == nil then
        note("slot=none")
        report("CHECK")
    end
    note(string.format("slot%d(was%X)", slot, game.read_u32(game.read_u32(SLOTS + 0x24) + slot * SLOT_ROW + 4)))
    callgate.call(MODELSTREAM, {
        args = { callgate.block{ 0, 2, callgate.block{ slot, RIFT_BOSS } }, 0, 0 },
        done = failed("stream") })
end

-- Switch off what the manager still holds (the last map's groups), make
-- group 1 the rift's one Oni at its spot, and start it.
local function drop_oni()
    enter("dropping")
    for group = 0, GROUP_LIMIT - 1 do
        game.write_u8(group_base(group) + ENABLED_OFFSET, 0)
    end
    local base = group_base(RIFT_GROUP)
    local entry = base + ENTRY_BASE
    for i, word in ipairs(ENTRY_TEMPLATE) do
        game.write_u32(entry + (i - 1) * 4, word)
    end
    game.write_u32(entry + 0x18, math.floor(BOSS_X + 0.5) & 0xFFFFFFFF)
    game.write_u32(entry + 0x1C, math.floor(BOSS_Y + 0.5) & 0xFFFFFFFF)
    game.write_u32(entry + 0x20, math.floor(BOSS_Z + 0.5) & 0xFFFFFFFF)
    game.write_u16(base + COUNT_OFFSET, 1)
    game.write_u8(base + ENABLED_OFFSET, 1)
    callgate.call(START_GROUP, {
        ecx = MANAGER,
        args = { RIFT_GROUP, NONE, 0 },        -- as callspawn: no reference entity
        done = failed("start") })
end

local function timed_out(what)
    if frames - mark > WAIT_LOAD then
        note(what .. "=never")
        report("CHECK")
    end
end

local hooks = {
    {
        address = GAMEPLAY,
        before = function(ctx)
            frames = frames + 1
            if callgate.pending() > 0 then
                return
            end
            local map = game.read_u32(CURRENT_MAP)
            if state == "idle" or state == "armed" then
                if map ~= ARENA_MAP then
                    state = "idle"
                    return
                end
                local d = distance_to_portal()
                if state == "idle" and d > ARM_RADIUS then
                    state = "armed"
                elseif state == "armed" and d < ENTER_RADIUS then
                    open_rift()
                end
            elseif state == "reloading" then
                timed_out("reload")
            elseif state == "arrived" then
                if map ~= ARENA_MAP then
                    note("map=" .. map)
                    report("CHECK")
                elseif frames - mark >= SETTLE then
                    stream_oni()
                end
            elseif state == "streaming" then
                if is_loaded(RIFT_BOSS) then
                    note("loaded@+" .. (frames - mark))
                    drop_oni()
                else
                    timed_out("stream")
                end
            elseif state == "dropping" then
                local boss = entity_of(RIFT_BOSS)
                if boss then
                    note(string.format("boss@+%d(%.0f,%.0f,%.0f)", frames - mark, game.read_f32(boss + 0x80),
                        game.read_f32(boss + 0x84), game.read_f32(boss + 0x88)))
                    enter("fighting")
                else
                    timed_out("boss")
                end
            elseif state == "fighting" then
                if map ~= ARENA_MAP then
                    note("left")
                    report("CHECK")
                elseif not alive_of(RIFT_BOSS) then
                    note("boss gone@+" .. (frames - mark))
                    report("OK")
                end
            end
        end,
    },
    {
        address = PRELOAD,
        before = function(ctx)
            if state ~= "reloading" or game.read_u32(ctx.esp + 4) ~= ARENA_DESC then
                return
            end
            -- the arena's preload: the reload is under way (nothing is changed)
            note("reload=ok")
            enter("arrived")
        end,
    },
}

return callgate.hooks(hooks)
