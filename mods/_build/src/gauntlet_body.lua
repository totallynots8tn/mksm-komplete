-- Time Rifts 0.12.0: the Survival gauntlet. The game's own "Survival N"
-- stages (maps 161-191) were cut, but most of them work: each loads its Mortal
-- Kombat line-up with the memory laid out for it and makes them killable
-- (their cankill_boss trigger). Once the vanilla survival is done (the Pit
-- II beaten, MK2 unlocked), Smoke's portal becomes a rift: Smoke says so, the
-- A prompt in front of the portal pulls P1 in, and the gauntlet runs the
-- working stages in their designers' order. Each stage's own way out (its
-- loadmap command when it is won) is pointed at the next stage, at an entry
-- known to work (the stages' links crash at entry 0); after the last one
-- P1 is sent back to Smoke, who pays the reward in XP (the addexperience
-- command his quests use). Smoke's lines go in the slot Time Rifts writes
-- Raiden's line in. Stages were toured live on 2026-11-03.
--
-- A stage that never sends P1 on is left once nobody is up and no wave runs
-- for STAGE_IDLE frames (or nobody came for STAGE_EMPTY); another map than
-- the next one ends the run (LEFT). Smoke's own portal, if it still loads
-- the Pit II once the survival is done, leads into the gauntlet too. A QA
-- build reports one GAUNTLET line per run (BEATEN, LEFT or CHECK).

local QA            = true          -- write the GAUNTLET line (and stop) after each run
local GAMEPLAY      = 0x00154F60    -- gameplay update; skipped while paused
local LOADMAP       = 0x00012883    -- loadmap command's exec: (event, a1, a2); event +8 -> { map + 1, entry, 1 }
local MESSAGETEXT   = 0x00012847    -- messagetext command's exec: (event, a1, a2), stdcall
local REACTION      = 0x00016A00    -- reaction command's exec: (event, target, from), stdcall
local ADDEXPERIENCE = 0x00013A53    -- addexperience command's exec: (event, target, a2): args[0] XP to a "char"
local PAD_MAP       = 0x00129480    -- one port's pad -> action bits; eax = its joypad object
local PADS          = 0x0063AC20    -- port 0's joypad object
local PAD_A         = 2             -- its analog A byte
local CURRENT_MAP   = 0x00505970
local LOAD_REQUEST  = 0x005ACEDC    -- u8: a map load is wanted
local LOAD_PORTAL   = 0x005ACEE0    -- loadmap's third argument: 1 for the portals and the stages' links
local LOAD_MAP      = 0x004FC160
local LOAD_ENTRY    = 0x004FC164
local PLAYER        = 0x005D1AB8    -- entity of in-use flag 0 (P1); position floats at +0x80
local ENTITY_STRIDE = 0x3238
local PLAYER_LOADING = 0x3217       -- u8 on each player entity, set by loadmap
local ENTITY_FLAGS  = 0x0051004C    -- -> u16 per entity, non-zero while in use
local ENTITY_TYPE   = 0x1DFE        -- u16 character ID
local ENTITY_COUNT  = 12
local MANAGER       = 0x006DBFB0    -- spawn manager
local ST_ACTIVE     = 0x2092A       -- u8: a group runs (0 once it is cleared)
local STATE         = 0x1E04        -- entity: u32 state, 0 standing
local REACTING      = 0xC           -- the state a reaction plays in
local PULL_ANIM     = 0x26          -- the portals' pull-in reaction, as it resolves for P1
local CHAR_TARGET   = 0x72616863    -- "char": a command's target kind, its index at +0x10
local MESSAGES      = 0x004E6E20    -- the message manager
local MESSAGE_TYPE  = 0x6D4         -- the type it shows (-1: none)
local MESSAGE_TIMER = 0x6F0         -- a repeat call of that type sets it back to 10
local PROMPT_TEXT   = 391           -- "=": the A button icon alone
local PROMPT_TYPE   = 4
local TEXT_PTRS     = 0x005B04A4    -- -> the game's text pointers (count at 0x5AC508)
local TEXT_COUNT    = 0x005AC508
local LINE_TEXT     = 34            -- "Raiden:\nTutorial Message 13.", never shown: Time Rifts' lines go in its slot
local LINE_TYPE     = 5             -- the game's speaker lines, up for 300 frames
local GAME_MANAGER  = 0x005ACEBC
local GAME_EVENTS   = 0x4874        -- game manager: a byte per game event
local PIT_BEATEN    = 115           -- the Pit II's way out sets it (map 74: gevent_115_on, then loadmap_75to147)
local MK2_UNLOCKED  = 0x005A378C    -- u8 the unlockmk2 command sets (0xB7290), Smoke's last reward; Unlock All leaves it
local CLEARED_SLOT  = 0x1C4 + 22    -- player 1's level slot 22: beaten rifts
local CLEARED_MARK  = 0xA0          -- bits 5-7 of that byte; bits 0-4: one per rift
local GAUNTLET_BIT  = 4             -- the rifts use bits 0-3
local NONE          = 0xFFFFFFFF
local SMOKE_AREA    = 146           -- Smoke's secret area (Forest - Map 19)
local PIT_LINK      = 75            -- his portal's loadmap_147to75 (designer numbers, map + 1): the Pit II, map 74
local RETURN_ENTRY  = 2             -- where the Pit II sends P1 back (loadmap_75to147: 147, 2, 1)
local PORTAL        = { 105810.266, -1427.247, 63.655 }  -- the portal's trigger (_d_portal) in map 146's trigger file
local PROMPT_RADIUS = 500           -- the trigger's centre, not a spot read from P1: wider than a rift's 250
local ARM_RADIUS    = 650           -- the prompt waits until P1 has been this far from the portal
local PROMPT_EVERY  = 30            -- frames between messagetext calls while it doesn't show
local PULL_MAX      = 120           -- frames the pull-in may take before the load
local SETTLE        = 60            -- frames after an arrival before anything happens
local QUIET         = 120           -- frames with no message up before one of Smoke's lines
local SMOKE_QUIET   = 180           -- in his area: his quest messages come in a run
local WAIT_LOAD     = 1800          -- frames to wait for a load
local STAGE_IDLE    = 1800          -- a stage that never sends P1 on: nobody up and no wave this long,
local STAGE_EMPTY   = 3600          -- or nobody came this long
local REWARD_FIRST  = 10000         -- XP for the first run beaten on a save
local REWARD_AGAIN  = 2500          -- and for every one after
local HAZARDS       = { [42] = true, [43] = true }  -- the tree mouth and arms: no wave waits on them

-- The Survival stages in their designers' order (Survival 2, 3, 4, 6, 7, 28,
-- 32, 31, 10), each at the entry the stage tour loaded it at. Survival 5
-- (map 164) is left out: its scene has no cameras, P1 lands in the void.
local STAGES = {
    { map = 161, entry = 1 },   -- Survival 2: Baraka, Tarkatans, mask guards
    { map = 162, entry = 1 },   -- Survival 3: Kahn's captains, generals, archers, handlers
    { map = 163, entry = 1 },   -- Survival 4: Oni and two Oni Warlords
    { map = 165, entry = 1 },   -- Survival 6: Orochi and the burned Scorpion
    { map = 166, entry = 1 },   -- Survival 7: clay soldiers, tree mouths
    { map = 187, entry = 1 },   -- Survival 28: Kano
    { map = 191, entry = 1 },   -- Survival 32: Goro and Kintaro
    { map = 190, entry = 0 },   -- Survival 31: Reptile, Ermac, Sub-Zero, Scorpion (the one stage with entry 0's camera)
    { map = 169, entry = 1 },   -- Survival 10: Shang Tsung and his priests
}

-- Smoke's lines: cp1252, under 128 bytes (the slot)
local LINES = {
    rift = {
        es = "Smoke:\nAlgo ha rasgado el tiempo.\nMi portal se ha vuelto una grieta.\nEntra, si te atreves.",
        en = "Smoke:\nSomething has torn through time.\nMy portal has become a rift.\nEnter it, if you dare.",
    },
    first = {
        es = "Smoke:\nEsta es la verdadera Supervivencia:\n%d batallas en la grieta.\n\xA1Sobrevive a todas!",
        en = "Smoke:\nThis is the true Survival:\n%d battles in the rift.\nSurvive them all!",
    },
    next = { es = "Smoke:\nBatalla %d de %d.\n\xA1Sigue luchando!", en = "Smoke:\nBattle %d of %d.\nKeep fighting!" },
    last = { es = "Smoke:\nLa \xFAltima batalla.\nShang Tsung te espera.", en = "Smoke:\nThe last battle.\nShang Tsung awaits." },
    reward = {
        es = "Smoke:\nHas sobrevivido a la grieta.\nRecompensa: %s de experiencia.",
        en = "Smoke:\nYou survived the rift.\nReward: %s experience.",
    },
}

callgate.target(MESSAGETEXT)
callgate.target(REACTION)
callgate.target(ADDEXPERIENCE)

-- off, smoke (in his area), pulling, loading, stage, back (in his area after the last stage)
local state = "off"
local run = nil          -- the run: { index, going = { map, entry } while a load is wanted, seen, idle_since, told, paid, amount }
local at_map = nil       -- the map the frames are in
local told = false       -- Smoke's rift line was shown on this visit
local armed = false      -- P1 has been ARM_RADIUS from the portal on this visit
local prompting = false  -- P1 is in front of the portal: A opens the rift
local prompted = nil     -- frame of the last messagetext call there
local pressed = false    -- A was pressed fresh while prompting
local a_down = false     -- port 0's A as last seen
local swallow = false    -- A is held since it was swallowed: keep it from the game
local pulled = false     -- the pull-in reaction is seen playing
local quiet_since = nil  -- frame since which no message is up
local frames, mark = 0, 0
local notes = {}
local report_text = nil  -- the GAUNTLET line, written on the next frame

local function note(text)
    notes[#notes + 1] = text
end

local function enter(next_state)
    state = next_state
    mark = frames
end

local function plausible(p)
    return p >= 0x10000 and p % 4 == 0 and (p < 0x7FFE0000
        or (p >= 0x80000000 and p < 0x84000000)
        or (p >= 0xB0000000 and p < 0xC0000000)
        or (p >= 0xD0000000 and p < 0xE0000000)
        or (p >= 0xF0000000 and p < 0xF4000000))
end

local function distance_to(spot)
    local dx = game.read_f32(PLAYER + 0x80) - spot[1]
    local dy = game.read_f32(PLAYER + 0x84) - spot[2]
    local dz = game.read_f32(PLAYER + 0x88) - spot[3]
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- A float's 32-bit pattern, for a call's argument block (the game's Lua 5.4
-- has no math.frexp; coordinates are normal floats)
local function f32_bits(x)
    if x == 0 then
        return 0
    end
    local sign = 0
    if x < 0 then
        sign, x = 0x80000000, -x
    end
    local e = 0
    while x >= 2.0 do x, e = x / 2.0, e + 1 end
    while x < 1.0 do x, e = x * 2.0, e - 1 end
    local frac = math.floor((x - 1.0) * 0x800000 + 0.5)
    if frac == 0x800000 then
        frac, e = 0, e + 1
    end
    return sign | (e + 127) << 23 | frac
end

local function cleared_addr()
    local m = game.read_u32(GAME_MANAGER)
    if m < 0x10000 or m % 4 ~= 0 then
        return nil
    end
    return m + CLEARED_SLOT
end

local function beaten_once()
    local addr = cleared_addr()
    if not addr then
        return false
    end
    local b = game.read_u8(addr)
    return b & 0xE0 == CLEARED_MARK and b & (1 << GAUNTLET_BIT) ~= 0
end

-- The rift is open once the vanilla survival is done on this save: the Pit
-- II's way out was taken and Smoke gave MK2.
local function opened()
    local m = game.read_u32(GAME_MANAGER)
    if m < 0x10000 or m % 4 ~= 0 then
        return false
    end
    return game.read_u8(m + GAME_EVENTS + PIT_BEATEN) ~= 0 and game.read_u8(MK2_UNLOCKED) ~= 0
end

local function spanish()
    local p = game.read_u32(game.read_u32(TEXT_PTRS))       -- text 0: "= Salir" in Spanish
    local tag = "= Salir"
    for k = 1, #tag do
        if game.read_u8(p + k - 1) ~= tag:byte(k) then
            return false
        end
    end
    return true
end

local function line(name)
    return spanish() and LINES[name].es or LINES[name].en
end

-- 10,000 (10.000 in Spanish); the runtime has no string patterns
local function thousands(n)
    local sep, text = spanish() and "." or ",", ""
    while n >= 1000 do
        text = string.format("%s%03d", sep, n % 1000) .. text
        n = n // 1000
    end
    return tostring(n) .. text
end

-- One of Smoke's lines, written over the unused "Raiden: Tutorial Message
-- 13." (text 34) as Raiden's is, only where that string's slot has the room
-- (the strings sit in 128-byte slots: the rest of it must be zeros up to the
-- next string), then shown as one of the game's speaker lines. The line
-- before it is zeroed past the new one, so the slot stays one string and
-- zeros. Without the room nothing shows and the run goes on.
local function tell(text)
    local list = game.read_u32(TEXT_PTRS)
    if list < 0x10000 or game.read_u32(TEXT_COUNT) <= LINE_TEXT + 1 then
        note("line=none")
        return
    end
    local p, after = game.read_u32(list + LINE_TEXT * 4), game.read_u32(list + (LINE_TEXT + 1) * 4)
    local bytes = text .. "\0"
    local room, words = after - p, (#bytes + 3) // 4
    if p % 4 ~= 0 or room % 4 ~= 0 or room < words * 4 or room > 0x200 then
        note("line=noroom")
        return
    end
    local len = 0
    while len < room and game.read_u8(p + len) ~= 0 do
        len = len + 1
    end
    for k = len, room - 1 do
        if game.read_u8(p + k) ~= 0 then
            note("line=noroom")
            return
        end
    end
    for k = 0, math.max(len + 1, #bytes) - 1, 4 do
        local word = 0
        for j = 0, 3 do
            word = word | (k + j < #bytes and bytes:byte(k + j + 1) or 0) << (8 * j)
        end
        game.write_u32(p + k, word)
    end
    callgate.call(MESSAGETEXT, {
        args = { callgate.block{ 0, 11, callgate.block{ LINE_TEXT, LINE_TYPE, 0, 0, 0, 0, 0, 0, 0, 0, 0 } }, 0, 0 } })
end

-- No message up for n frames in a row (the game's own lines come first).
local function quiet(n)
    if game.read_u32(MESSAGES + MESSAGE_TYPE) ~= NONE then
        quiet_since = nil
        return false
    end
    quiet_since = quiet_since or frames
    return frames - quiet_since >= n
end

-- In front of the portal: the game's own portal prompt. One messagetext
-- call shows it; while a type-4 message shows, a repeat call only sets its
-- timer back to 10, so the gauntlet does just that.
local function show_prompt()
    if game.read_u32(MESSAGES + MESSAGE_TYPE) == PROMPT_TYPE then
        game.write_u32(MESSAGES + MESSAGE_TIMER, 10)
    elseif prompted == nil or frames - prompted >= PROMPT_EVERY then
        prompted = frames
        callgate.call(MESSAGETEXT, {
            args = { callgate.block{ 0, 11, callgate.block{ PROMPT_TEXT, PROMPT_TYPE, 0, 0, 0, 0, 0, 0, 0, 0, 0 } }, 0, 0 } })
    end
end

-- The pull-in the game's portals play before their load: the reaction
-- command on P1 with the Portals' rec_portal arguments, from the portal.
local function pull()
    enter("pulling")
    pulled = false
    callgate.call(REACTION, {
        args = { callgate.block{ 0, 16, callgate.block{ PULL_ANIM, 0, PULL_ANIM, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } },
                 callgate.block{ CHAR_TARGET, 0, 0, 0, 0 },     -- "char" 0: P1
                 callgate.block{ 0, f32_bits(PORTAL[1]), f32_bits(PORTAL[2]), f32_bits(PORTAL[3]) } },
        done = function(eax)
            if eax == nil then
                note("pull=BAD")                 -- only the look: the load comes anyway
            end
        end })
end

-- The load request the game's loadmap command makes.
local function request(target)
    game.write_u8(PLAYER + PLAYER_LOADING, 1)
    game.write_u8(PLAYER + ENTITY_STRIDE + PLAYER_LOADING, 1)
    game.write_u32(LOAD_PORTAL, 1)
    game.write_u32(LOAD_MAP, target.map)
    game.write_u32(LOAD_ENTRY, target.entry)
    game.write_u8(LOAD_REQUEST, 1)
end

local function begin()
    run = { index = 1, seen = false, told = false }
    prompting = false
end

-- On to the next stage, or back to Smoke after the last.
local function advance()
    run.index = run.index + 1
    run.going = STAGES[run.index] or { map = SMOKE_AREA, entry = RETURN_ENTRY }
    enter("loading")
end

local function finish(verdict)
    if QA then
        report_text = "GAUNTLET 0.12.0 " .. verdict .. " | " .. table.concat(notes, " ")
    end
    notes = {}
    run, prompting, armed = nil, false, false
    enter(at_map == SMOKE_AREA and "smoke" or "off")
end

local function enemies_up()
    local flags = game.read_u32(ENTITY_FLAGS)
    for i = 2, ENTITY_COUNT - 1 do
        if game.read_u16(flags + i * 2) ~= 0 and not HAZARDS[game.read_u16(PLAYER + i * ENTITY_STRIDE + ENTITY_TYPE)] then
            return true
        end
    end
    return false
end

-- The frames are in another map: where the run sent P1, or the run is over.
local function arrive(map)
    at_map, told, armed, prompting, quiet_since = map, false, false, false, nil
    if run then
        if run.going and map == run.going.map then
            note(string.format("s%d@%d", run.index, frames))
            run.going, run.seen, run.idle_since, run.told = nil, false, nil, false
            enter(map == SMOKE_AREA and "back" or "stage")
        else
            note("left@" .. map)
            finish("LEFT")
        end
    else
        enter(map == SMOKE_AREA and "smoke" or "off")
    end
end

-- Smoke's area: his line once the rift is open (each visit until it is
-- first beaten), then the A prompt in front of the portal while no other
-- message is up.
local function smoke_step()
    if not opened() or frames - mark < SETTLE then
        return
    end
    if not told and not beaten_once() then
        if quiet(SMOKE_QUIET) then
            told = true
            tell(line("rift"))
        end
        return
    end
    local d = distance_to(PORTAL)
    if d > ARM_RADIUS then
        armed = true
    end
    local up = game.read_u32(MESSAGES + MESSAGE_TYPE)
    prompting = armed and d < PROMPT_RADIUS and (up == NONE or up == PROMPT_TYPE)
    if prompting and pressed then
        begin()
        note(string.format("open@%d(d=%.0f)", frames, d))
        pull()
    elseif prompting then
        show_prompt()
    else
        prompted = nil
    end
    pressed = false
end

-- In a stage: Smoke's line, and the stage's end if its own load never comes.
local function stage_step()
    if frames - mark < SETTLE then
        return
    end
    if not run.told and quiet(QUIET) then
        run.told = true
        if run.index == 1 then
            tell(string.format(line("first"), #STAGES))
        elseif run.index == #STAGES then
            tell(line("last"))
        else
            tell(string.format(line("next"), run.index, #STAGES))
        end
    end
    if enemies_up() then
        run.seen, run.idle_since = true, nil
    elseif game.read_u8(MANAGER + ST_ACTIVE) ~= 0 then
        run.idle_since = nil
    else
        run.idle_since = run.idle_since or frames
        if (run.seen and frames - run.idle_since >= STAGE_IDLE) or (not run.seen and frames - mark >= STAGE_EMPTY) then
            note(string.format("s%d=%s@+%d", run.index, run.seen and "idle" or "empty", frames - mark))
            advance()
            request(run.going)
        end
    end
end

-- Back with Smoke: his line, then the XP (one call per frame), and the run
-- is remembered in the save.
local function back_step()
    if frames - mark < SETTLE then
        return
    end
    if not run.amount then
        if quiet(QUIET) then
            run.amount = beaten_once() and REWARD_AGAIN or REWARD_FIRST
            tell(string.format(line("reward"), thousands(run.amount)))
        end
    elseif not run.paid then
        run.paid = true
        local amount = run.amount
        callgate.call(ADDEXPERIENCE, {
            args = { callgate.block{ 0, 1, callgate.block{ amount } }, callgate.block{ CHAR_TARGET, 0, 0, 0, 0 }, 0 },
            done = function(eax)
                note(eax == nil and "xp=BAD" or ("xp+" .. amount))
                local addr = cleared_addr()
                if addr then
                    local b = game.read_u8(addr)
                    if b & 0xE0 ~= CLEARED_MARK then b = CLEARED_MARK end
                    game.write_u8(addr, b | (1 << GAUNTLET_BIT))
                end
                finish("BEATEN")
            end })
    end
end

local hooks = {
    {
        address = GAMEPLAY,
        before = function(ctx)
            frames = frames + 1
            if report_text then
                local text = report_text
                report_text = nil
                error(text, 0)
            end
            if callgate.pending() > 0 then
                return
            end
            local map = game.read_u32(CURRENT_MAP)
            if map ~= at_map then
                arrive(map)
            end
            if state == "smoke" then
                smoke_step()
            elseif state == "pulling" then
                -- load once the pull-in is over (or never started)
                local s = game.read_u32(PLAYER + STATE)
                if s == REACTING then
                    pulled = true
                end
                if (pulled and s ~= REACTING) or (not pulled and frames - mark > 2) or frames - mark >= PULL_MAX then
                    note(string.format("pull@+%d(%s)", frames - mark, pulled and "seen" or "none"))
                    run.going = STAGES[1]
                    request(run.going)
                    enter("loading")
                end
            elseif state == "loading" then
                if frames - mark > WAIT_LOAD then
                    note("load" .. run.going.map .. "=never")
                    finish("CHECK")
                end
            elseif state == "stage" then
                stage_step()
            elseif state == "back" then
                back_step()
            end
        end,
    },
    {
        -- a loadmap command: in a stage, its way out goes to the next stage
        -- instead (its own reload stays); in Smoke's area, once the rift is
        -- open, his portal goes into the gauntlet instead of the Pit II
        address = LOADMAP,
        before = function(ctx)
            if not plausible(ctx.esp) then
                return
            end
            local def = game.read_u32(ctx.esp + 4)
            local args = plausible(def) and game.read_u32(def + 8)
            if not args or not plausible(args) then
                return
            end
            local map, to = game.read_u32(CURRENT_MAP), game.read_u32(args)
            if run == nil then
                if map ~= SMOKE_AREA or to ~= PIT_LINK or not opened() then
                    return
                end
                begin()
                note("portal@" .. frames)
                run.going = STAGES[1]
                enter("loading")
            elseif state == "stage" then
                local stage = STAGES[run.index]
                if map ~= stage.map or to == stage.map + 1 then
                    return
                end
                note(string.format("s%d=link%d@+%d", run.index, to - 1, frames - mark))
                advance()
            elseif state ~= "loading" or map == run.going.map then
                return
            end
            game.write_u32(args, run.going.map + 1)
            game.write_u32(args + 4, run.going.entry)
            game.write_u32(args + 8, 1)
        end,
    },
    {
        -- port 0's pad, before the game reads it: in front of the portal A
        -- opens the rift instead of jumping, and stays swallowed until it is
        -- let go
        address = PAD_MAP,
        before = function(ctx)
            if ctx.eax ~= PADS then
                return
            end
            local down = game.read_u8(PADS + PAD_A) ~= 0
            if down and (prompting or swallow) then
                if prompting and not a_down then
                    pressed = true
                end
                game.write_u8(PADS + PAD_A, 0)
                swallow = true
            else
                swallow = false
            end
            a_down = down
        end,
    },
}

return callgate.hooks(hooks)
