-- Solo Co-op Paths 0.6.1 (experimental).
-- 0.4 made co-op layout scripts see istwoplayer=yes / isoneplayer=no in solo,
-- while map-trigger conditions still saw the honest player count so
-- solo-progression plates could fire. The co-op plate itself still would not
-- unlock: the probe showed its co-op gate triggers (istwoplayer/isoneplayer)
-- fire in solo, but the action-button gate reads actionButton(0)=0.
--
-- 0.5 adds a plate condition rewrite. Map triggers (manager [0x682020], records
-- 0xD8 apart, count +0xA8C0) fire when every condition in their list passes:
-- 0x16F4B0 walks [rec+0x58] conditions, command indices at [rec+0x5C], args at
-- [rec+0x60]; command object = mgr + index*24 + 0x11C00, execute = [[obj]].
-- Within any trigger whose list contains actionButton (the plate gate), a
-- player-2 condition is rewritten IN PLACE into a copy of the player-1
-- condition (command index + arg), so player 1 alone can satisfy a gate authored
-- for two players. The rewrite is cached per record and re-armed when the
-- trigger manager pointer changes (area reload).
--
-- RE CAVEAT: actionButton (0x146A1->0x2AE20), buttonthrough and
-- OtherPlayerInvisible select the player from the ACTIVATOR (char index at
-- [ref+0x10], passed by CHECK), not from the condition arg; eventnotcomplete's
-- arg is an event id and stonepowatleast's arg is a threshold. So for a plate
-- whose only gate is actionButton this rewrite is a no-op, and the real blocker
-- is why actionButton returns 0. coop_solo_debug.lua (0.5.1) counts each step
-- actionButton can refuse on (fatality-manager busy check, controller bit 0x2,
-- gate 0x4E67C4, char state) to answer that.
-- 0.6: colored co-op plates. Help text [1354]: "colored plates in some levels
-- that you will need an ally to use". A plate is a map trigger whose
-- condition stonecolor:C (0x15574 -> 0x20B90) passes only when the activating
-- player's color, [[entity+0x2B6C]+4] (set by setspawncolor), equals C. Each
-- plate that fires runs addstonepower, adding to the stone power at 0x581B48
-- (reset only when a level resets), and the door checks stonepowatleast:N. In
-- single player the second color never stands on its plate, so the door
-- never opens. 0.6 lets a player (activator index 0 or 1) pass stonecolor of
-- any color in single player, so one player can stand on each plate in turn.
-- Set SOLO_STONES=false to turn this off.
local SOLO_STONES    = true
local STONE_COLOR    = 0x00015574

-- 0.6.1: plate latch. Some co-op plates (Wu Shi) are event flags instead:
-- standing on a plate sets [[0x5ACEBC]+0x4874+id] through gameevent
-- (0x13134 -> 0xA4A80) and stepping off clears it a moment later; the secret
-- wants both plates' flags at once. In single player a flag cleared within
-- PLATE_WINDOW frames of being set is held for LATCH_FRAMES more (~15 s), so
-- one player can step from one plate to the other. Set SOLO_LATCH=false to
-- turn this off.
local SOLO_LATCH     = true
local GAME_EVENT     = 0x00013134
local FRAME          = 0x005CE878
local EVENT_FLAGS    = 0x4874
local EVENT_LIMIT    = 200
local PLATE_WINDOW   = 600
local LATCH_FRAMES   = 900
local IS_TWO_PLAYER  = 0x00012E55
local IS_ONE_PLAYER  = 0x000156CD
local GAME_MANAGER   = 0x005ACEBC
local TRIG_CHECK     = 0x0016F4B0   -- walks a trigger's condition commands
local TRIG_CHECK_END = 0x0016F560   -- next function; CHECK body is [start, end)
local TRIG_MGR_PTR   = 0x00682020
local TRIG_STRIDE    = 0xD8

-- Plate rewrite. Set REWRITE_PLATE=false to keep 0.4 behaviour only.
local REWRITE_PLATE  = true
local ACTION_BUTTON  = 0x000146A1   -- execute address (thunk) of actionButton
-- Conditions treated as "player 2": OtherPlayerInvisible is inherently about the
-- other player; actionButton/buttonthrough with arg==1 would be a player-2 gate
-- if the author encoded the player in the arg (the RE says they do not, but the
-- rewrite stays correct and harmless either way).
local PLAYER2_CMDS = {
    [0x0001420A] = "always",   -- OtherPlayerInvisible
    [0x000146A1] = "arg1",     -- actionButton
    [0x00014606] = "arg1",     -- buttonthrough
}

local function ok(p)
    return p >= 0x10000 and (p < 0x7FFE0000 or (p >= 0x80000000 and p < 0x84000000)
        or (p >= 0xB0000000 and p < 0xC0000000) or (p >= 0xD0000000 and p < 0xE0000000)
        or (p >= 0xF0000000 and p < 0xF4000000))
end

local function single_player()
    local manager = game.read_u32(GAME_MANAGER)
    if not ok(manager) then
        return false
    end
    return game.read_u32(manager + 0x88) == 0
end

-- True when the current call sits inside the trigger-condition walk, i.e.
-- isoneplayer is being asked as a trigger's pass/fail condition rather than by
-- a layout script. The condition command is called directly from CHECK, so a
-- live return address into CHECK's body sits near the top of the stack.
local function in_trigger_check(esp)
    for offset = 0, 0x1C, 4 do
        local ret = game.read_u32(esp + offset)
        if ret >= TRIG_CHECK and ret < TRIG_CHECK_END then
            return true
        end
    end
    return false
end

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

local scanned = {}
local cur_mgr = nil

-- Rewrite player-2 conditions of a plate trigger into copies of its player-1
-- actionButton condition. Returns the number of conditions written.
local function rewrite_plate(mgr, rec)
    local count = game.read_u32(rec + 0x58)
    if count <= 0 or count > 12 then return 0 end
    local slots = game.read_u32(rec + 0x5C)
    local args  = game.read_u32(rec + 0x60)
    if not ok(slots) or not ok(args) then return 0 end

    -- Pass 1: resolve every condition and locate the player-1 actionButton.
    local is_plate, p1_slot, p1_arg = false, nil, 0
    local execute_of = {}
    for j = 0, count - 1 do
        local slot = game.read_u32(slots + j * 4)
        local execute = resolve_execute(mgr, slot)
        execute_of[j] = execute
        if execute == ACTION_BUTTON then
            is_plate = true
            local arg = game.read_u32(args + j * 4)
            if arg == 0 and p1_slot == nil then
                p1_slot, p1_arg = slot, arg
            end
        end
    end
    if not is_plate then return 0 end

    -- Pass 2: copy the player-1 condition over each player-2 condition.
    local wrote = 0
    for j = 0, count - 1 do
        local kind = execute_of[j] and PLAYER2_CMDS[execute_of[j]]
        if kind then
            local arg = game.read_u32(args + j * 4)
            if kind == "always" or (kind == "arg1" and arg == 1) then
                if p1_slot ~= nil then
                    game.write_u32(slots + j * 4, p1_slot)
                end
                game.write_u32(args + j * 4, p1_arg)
                wrote = wrote + 1
            end
        end
    end
    return wrote
end

local two, one, stone = false, false, false
local last_set, latched, latch_frame, pending_event = {}, {}, nil, nil

local function set_flag(id, value)
    local manager = game.read_u32(GAME_MANAGER)
    if ok(manager) then game.write_u8(manager + EVENT_FLAGS + id, value) end
end

-- Release latches whose time is up (once per frame).
local function expire_latches()
    if next(latched) == nil then return end
    local frame = game.read_u32(FRAME)
    if frame == latch_frame then return end
    latch_frame = frame
    for id, until_frame in pairs(latched) do
        if frame >= until_frame then
            set_flag(id, 0)
            latched[id] = nil
            last_set[id] = nil
        end
    end
end

return {
    {
        address = IS_TWO_PLAYER,
        before = function(ctx)
            two = single_player()
        end,
        after = function(ctx)
            if two then
                ctx.eax = (ctx.eax & 0xFFFFFF00) | 1
                two = false
            end
        end,
    },
    {
        address = IS_ONE_PLAYER,
        before = function(ctx)
            one = single_player() and not in_trigger_check(ctx.esp)
        end,
        after = function(ctx)
            if one then
                ctx.eax = ctx.eax & 0xFFFFFF00
                one = false
            end
        end,
    },
    {
        address = STONE_COLOR,
        before = function(ctx)
            stone = false
            if not SOLO_STONES or not single_player() then return end
            local ref = game.read_u32(ctx.esp + 4)
            if ok(ref) and game.read_u32(ref + 0x10) <= 1 then stone = true end
        end,
        after = function(ctx)
            if stone then
                ctx.eax = (ctx.eax & 0xFFFFFF00) | 1
                stone = false
            end
        end,
    },
    {
        address = TRIG_CHECK,
        before = function(ctx)
            expire_latches()
            if not REWRITE_PLATE then return end
            local rec = ctx.ecx
            local mgr = game.read_u32(TRIG_MGR_PTR)
            if not ok(mgr) then return end
            if mgr ~= cur_mgr then
                cur_mgr = mgr
                scanned = {}
            end
            if scanned[rec] then return end
            scanned[rec] = true
            rewrite_plate(mgr, rec)
        end,
    },
    {
        address = GAME_EVENT,
        before = function(ctx)
            pending_event = nil
            if not SOLO_LATCH or not single_player() then return end
            local def = game.read_u32(ctx.esp + 4)
            local args = ok(def) and game.read_u32(def + 8) or 0
            if not ok(args) then return end
            local id = game.read_u32(args)
            if id >= EVENT_LIMIT then return end
            pending_event = { id = id, value = game.read_u32(args + 4) }
        end,
        after = function(ctx)
            local e = pending_event
            pending_event = nil
            if e == nil then return end
            local frame = game.read_u32(FRAME)
            if e.value ~= 0 then
                last_set[e.id] = frame
                latched[e.id] = nil
            elseif last_set[e.id] and frame - last_set[e.id] <= PLATE_WINDOW then
                set_flag(e.id, 1)
                latched[e.id] = frame + LATCH_FRAMES
            end
        end,
    },
}
