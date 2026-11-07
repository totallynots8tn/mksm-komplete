-- Time Rifts 0.14.3: the postgame rifts (the user's design, 2026-11-04):
-- once the Survival gauntlet is beaten (bit 4 of the rifts' save byte), a
-- rift opens in each area a Survival stage was built on, and sends P1 to
-- that stage's fight made harder: the stage as the game has it, then a chain
-- of phases, each a set of bosses (clones included) with grunts. The game's
-- own Survival portal look rises on the rift's spot (Survival 2's ground
-- rings, rays and red ring, through the particleoffset command), and the
-- Black button opens it, the Survival portals' button (the other rifts use
-- A). Win the chain and P1 is sent back to the spot with XP; go down and P1
-- is sent back without. A rift can be run again (no save bit is left).
-- * The Soul Tombs (map 4), where Shang Tsung's soul orb is destroyed:
--   Survival 10 (map 169, built on that chamber), then Goro with Red
--   Dragons, Kintaro with Black Dragons, the young Shang Tsung with both.
-- * The Champion Shrine (map 108), Ermac's battle: Survival 31 (map 190),
--   Reptile, Ermac, Sub-Zero and Scorpion together, then each in turn with a
--   clone and grunts, Goro and his clone last.
--
-- Memory: a map gives memory only to the types its preload list names. A
-- rift may add types to its stage's list for its run (Survival 10 names two;
-- only rifts ever load the Survival stages, and Shaolin Shuffle leaves them
-- alone); the list is put back when the run ends. Each phase streams in the
-- types it lacks (modelstream, as cutscenes swap characters), one at a time,
-- into slots holding no type it needs and no one alive, whose first block
-- has memory. Goro needs two blocks in a row: the slots holding blocks 0 and
-- 1 are unloaded (nobody of them up) and he streams into slot 0 (as the
-- Goro's Lair rift does). A slot whose type is still up (a body not yet
-- gone) is waited for, up to SLOT_WAIT. Every boss of the phase is made
-- killable while it is up. Types: 9 is taken for the Black Dragon (Kano's
-- crew in Survival 28), 16 for the Red Dragon, 8 for the zombies (Scorpion's
-- battle), 4 for the skeletons (sword and shield) and 17 for the Living
-- Forest's shadows (scythe).
--
-- 0.13.0 (the Soul Tombs rift alone, soul_rift.lua): QA 2026-11-04 BEATEN,
-- but every boss came alone (the stage had lost both clans by then) and the
-- stage's way out opened during Goro's fight. 0.13.1 streamed missing clans
-- in, took back the stage's loadmap during the chain, and added the rays and
-- red ring. 0.14.0: this script, with the rifts as data and phases of several
-- bosses.
--
-- 0.14.1 (QA 2026-11-04: the Champion Shrine crashed in the zlib worker,
-- thread 30, as map 199 did when the Orochi was streamed over its priests;
-- and the phases dropped on P1): a slot is streamed over only once nobody of
-- its type has been up for TYPE_CLEAR frames (a dismembered fighter's parts
-- and death effects outlive its entity), and each phase drops from the
-- stage's rift: the spot P1 landed on, where the portal rises too.
--
-- 0.14.2 (QA 2026-11-04, with a live recorder: the Scorpions' phase spawned
-- only the burned Scorpion, then the game crashed in the zlib worker two
-- seconds after the two Sub-Zeros of phase 2 spawned. Sub-Zero had been
-- streamed back into another slot than the one the stage first loaded him
-- in; every stream that worked so far put a type into a slot it had never
-- been in, or back into its own, as the Kintaro rift's restore does): a type
-- that held a slot in the stage only ever streams back into that slot (its
-- home), and one already used in the stage (the stage's Scorpion) is
-- streamed again into its home first, so its memory is fresh for the
-- phase's copies. A home wanted by the phase is never given to another type.
--
-- 0.14.3 (the user: the stage's rift stayed up after P1 dropped): in the
-- stage the portal only flashes, for FLASH frames, when P1 lands, when a
-- phase drops and when the chain is won. particleoffset's args[2] is the
-- effect's life in frames; args[6] = 1 makes it 0x1A85 frames instead, as the
-- ambient effects (fog, embers, rain) and the Survival portal have it, which
-- the entrance's portal keeps.

local QA            = true          -- write the POSTGAME line (and stop) after each run
local GAMEPLAY      = 0x00154F60    -- gameplay update; skipped while paused
local PRELOAD       = 0x00015DEE    -- before the loader reads a map's preload list: [esp+4] = descriptor
local START_GROUP   = 0x001D2600    -- spawn manager thiscall (group, entity index or -1, 0); ret 0xC
local MODELSTREAM   = 0x0017BA00    -- modelstream command: [[arg1+8]] = slot, type
local UNLOAD        = 0x0017B280    -- unloads a memory slot's type, as a stream does first: (slot)
local SET_HEALTH    = 0x00153CD0    -- thiscall: actor in ecx, the new health at [esp+4]
local SET_POSITION  = 0x0015DC30    -- thiscall: entity in ecx, -> x, y, z, w at [esp+4]
local MESSAGETEXT   = 0x00012847    -- messagetext command's exec: (event, a1, a2), stdcall
local REACTION      = 0x00016A00    -- reaction command's exec: (event, target, from), stdcall
local ADDEXPERIENCE = 0x00013A53    -- addexperience command's exec: (event, target, a2): args[0] XP to a "char"
local LOADMAP       = 0x00012883    -- loadmap command's exec: a stage's own way out
local PARTICLES     = 0x001582A0    -- particleoffset command's exec: thiscall (event, target, from), the
local PARTICLE_CMD  = 0x0050FFD0    -- effect at from + the integer offsets args[3..5]; ecx = this object
local PAD_MAP       = 0x00129480    -- one port's pad -> action bits; eax = its joypad object
local PADS          = 0x0063AC20    -- port 0's joypad object
local PAD_BLACK     = 6             -- its analog Black byte (A B X Y Black White from +2)
local CURRENT_MAP   = 0x00505970
local LOAD_REQUEST  = 0x005ACEDC
local LOAD_PORTAL   = 0x005ACEE0
local LOAD_MAP      = 0x004FC160
local LOAD_ENTRY    = 0x004FC164
local PLAYER        = 0x005D1AB8    -- entity of in-use flag 0 (P1); position floats at +0x80
local ENTITY_STRIDE = 0x3238
local PLAYER_LOADING = 0x3217       -- u8 on each player entity, set by loadmap
local ENTITY_FLAGS  = 0x0051004C    -- -> u16 per entity, non-zero while in use
local ENTITY_TYPE   = 0x1DFE
local ENTITY_COUNT  = 12
local ACTOR         = 0x200         -- entity: its actor; health at +0x368
local ACTOR_HP      = 0x368
local CAN_KILL      = 0xD4          -- actor: 0 = its health stops at 1 (MK bosses' AI setup)
local FACING        = 0x94
local STATE         = 0x1E04        -- entity: u32 state; REACTING while a reaction plays
local REACTING      = 0xC
local PULL_ANIM     = 0x26          -- the portals' pull-in reaction
local CHAR_TARGET   = 0x72616863    -- "char": a command's target kind, its index at +0x10
local MOMENTUM      = { 0x3184, 0x3188, 0x318C, 0xD0, 0xD4, 0xD8, 0x3144, 0x3148, 0x314C, 0x3130 }
local CAMERA_HOLD   = 0x00599534
local CAMERA_CUT    = 0x004E640C
local CAMERA_BLEND  = 0x004E641C
local MESSAGES      = 0x004E6E20
local MESSAGE_TYPE  = 0x6D4
local MESSAGE_TIMER = 0x6F0
local PROMPT_TEXT   = 60            -- "^ Activar": the Black button's icon (^) and a verb
local PROMPT_TYPE   = 4
local TEXT_PTRS     = 0x005B04A4
local TEXT_COUNT    = 0x005AC508
local LINE_TEXT     = 34            -- the slot Time Rifts' lines use
local LINE_TYPE     = 5
local GAME_MANAGER  = 0x005ACEBC
local CLEARED_SLOT  = 0x1C4 + 22    -- player 1's level slot 22: beaten rifts
local CLEARED_MARK  = 0xA0
local GAUNTLET_BIT  = 4             -- the Survival gauntlet (gauntlet.lua)
local NONE          = 0xFFFFFFFF
local MANAGER       = 0x006DBFB0
local GROUP_STRIDE  = 0xA6C
local GROUP_LIMIT   = 50
local ENTRY_BASE    = 0x18
local ENTRY_STRIDE  = 0x74
local COUNT_OFFSET  = 0xA68
local ENABLED_OFFSET = 0xA6A
local RIFT_MARK_OFFSET = 0xA10      -- as core.lua: LDK and Shuffle leave a marked group alone
local RIFT_MARK     = 0x54464952    -- "RIFT"
local ST_GROUP      = 0x20920
local ST_ACTIVE     = 0x2092A
local SLOTS         = 0x006322F8    -- memory slots: +0x08 blocks, +0x10 slot count, +0x1C block rows, +0x24 slot rows
local SLOT_ROW      = 20            -- rows: +0x04 type; a slot's +0x08 first block; a block's +0x10 flags
local BLOCK_MEMORY  = 4             -- a block's flag: it has memory (2: in use)
local LOADED_TYPES  = 0x006CA69C    -- 6 words: the types that can spawn right now
local LOADED_COUNT  = 6
local CHAR_TABLE    = 0x004FA9F0    -- character rows of 0x30: +0x04 the memory blocks a type needs
local CHAR_ROW      = 0x30

-- (the type names live in this block only: the main chunk is near Lua's 200 locals)
local RIFTS
do
    local GORO, KINTARO, YOUNG_SHANG, OLD_SHANG = 57, 58, 62, 63
    local REPTILE, ERMAC, SUB_ZERO, SCORPION, BURNED_SCORPION, KANO = 59, 68, 69, 52, 55, 54
    local PRIEST, RED_DRAGON, BLACK_DRAGON, ZOMBIE, SKELETON, SHADOW = 27, 16, 9, 8, 4, 17
    -- entrance map, the spot (read live from P1) and P1's facing there, the
    -- entrance's entry to come back by; the stage, its descriptor and entry;
    -- first = the stage's own fighters (its fight is over once one was up and
    -- nobody is); added = types appended to the stage's preload list; phases:
    -- bosses and extras as { type, count }
    RIFTS = {
        { name = "soul", entrance = 4, spot = { -613.910, -47.872, 8419.954 }, facing = 62.0, back = 1,
          stage = 169, desc = 0x005002B8, entry = 1, first = { [OLD_SHANG] = true },
          added = { RED_DRAGON, BLACK_DRAGON }, reward = 15000,
          phases = {
              { bosses = { { GORO, 1 } }, extras = { { RED_DRAGON, 4 } } },
              { bosses = { { KINTARO, 1 } }, extras = { { BLACK_DRAGON, 4 } } },
              { bosses = { { YOUNG_SHANG, 1 } }, extras = { { RED_DRAGON, 2 }, { BLACK_DRAGON, 2 } } },
          } },
        { name = "shrine", entrance = 108, spot = { 1403.788, -1010.621, 32438.879 }, facing = 70.0, back = 1,
          stage = 190, desc = 0x00501118, entry = 0,                 -- Survival 31: entry 0 (its camera record)
          first = { [REPTILE] = true, [ERMAC] = true, [SUB_ZERO] = true, [SCORPION] = true },
          added = {}, reward = 20000,
          phases = {
              { bosses = { { BURNED_SCORPION, 1 }, { SCORPION, 1 } }, extras = { { ZOMBIE, 3 }, { SKELETON, 3 } } },
              { bosses = { { SUB_ZERO, 2 } }, extras = { { BLACK_DRAGON, 4 } } },
              { bosses = { { REPTILE, 2 } }, extras = { { SHADOW, 4 } } },
              { bosses = { { ERMAC, 2 } }, extras = { { PRIEST, 4 } } },
              { bosses = { { KANO, 2 } }, extras = { { RED_DRAGON, 4 } } },
              { bosses = { { GORO, 2 } }, extras = {} },     -- the ex-champion and his clone
          } },
    }
end
-- the Survival portal as Survival 2's triggers play it: the ground rings
-- (bank 0, 109), the rays rising from the ground (bank 3, 105) and the red
-- ring (bank 3, 48), all from the Survival portal's effect pack (args[6] = 1)
local PORTAL_FX     = { { 0, 109 }, { 3, 105 }, { 3, 48 } }
local FLASH         = 150           -- frames the stage's rift shows: P1 lands, a phase drops, the chain is won
local PROMPT_RADIUS = 250
local ARM_RADIUS    = 400           -- the prompt waits until P1 has been this far from the spot
local FX_RADIUS     = 4000          -- the portal rises once P1 is this close
local PROMPT_EVERY  = 30
local PULL_MAX      = 120
local SETTLE        = 60
local QUIET         = 120
local WAIT_LOAD     = 1800
local STAGE_WAIT    = 3600          -- the chain starts anyway if the stage's fighters never show
local STAGE_QUIET   = 150           -- the stage is over: nobody up and no wave this long
local STREAM_REST   = 90
local SLOT_WAIT     = 1500          -- frames to wait for a slot to clear
local TYPE_CLEAR    = 600           -- frames a type must have had nobody up before its slot is streamed over
local WAIT_BOSS     = 300
local BOSS_GONE     = 30            -- frames with no boss of the phase up: its fight is over
local GRUNT_WAIT    = 900           -- after the bosses, frames the phase's grunts may hold it
local FAIL_WAIT     = 180           -- P1 down: frames before the way back
local BUILD_EVERY   = 6
local EXTRA_GAP     = 45
local SPAWN_LIFT    = 64
local LINE_SHOW     = 240           -- the reward line shows this long before the way back
local GROUP_HEADER  = { 0, 0x10, 4, 0, 0xFFFFFFFF, 0xFFFF }
local RING          = { { 0, 0 }, { 300, 0 }, { -300, 0 }, { 0, 300 }, { 0, -300 }, { 220, 220 },
                        { -220, -220 }, { 220, -220 }, { -220, 220 }, { 440, 0 }, { -440, 0 }, { 0, 440 } }
local ENTRY_TEMPLATE = {
    0, NONE, NONE, 0x0B, NONE, NONE, 0, 0, 0xFFFFFC18, NONE,
    0, NONE, 0, 0, 0, 0, 4, 2, 0, 0, 0, 0, 1, NONE, NONE, NONE, NONE, 0x3E8, 0,
}
local LINES = {
    more = { es = "Smoke:\nLa grieta no ha terminado.\n\xA1Vienen m\xE1s!", en = "Smoke:\nThe rift isn't done with you.\nMore are coming!" },
    reward = { es = "Smoke:\nHas vencido a la grieta.\nRecompensa: %s de experiencia.",
               en = "Smoke:\nYou beat the rift.\nReward: %s experience." },
}

callgate.target(START_GROUP)
callgate.target(MODELSTREAM)
callgate.target(UNLOAD)
callgate.target(SET_POSITION)
callgate.target(MESSAGETEXT)
callgate.target(REACTION)
callgate.target(ADDEXPERIENCE)
callgate.target(PARTICLES)

-- off, entrance, pulling, loading, stage, telling, freeing, streaming,
-- building, dropping, fighting, paying, returning, failing
local state = "off"
local at_map = nil
local rift = nil         -- the RIFTS row of the entrance P1 is in, or of the run
local active = false     -- a run is under way (the stage's list may carry its additions)
local phase = 0          -- index into rift.phases (0: the stage's own fight)
local want, wanted, skipped = {}, {}, {}   -- the phase's types in order, as a set, and those left out
local unloads = {}       -- slots to unload before Goro streams into slot 0
local streaming, stream_since, rest_until, wait_since = nil, nil, nil, nil
local build, group = nil, nil
local boss_seen, boss_gone_since, bosses_over = false, nil, nil
local stage_seen, quiet_since = false, nil
local stage_spot = nil   -- where P1 landed in the stage: its rift, where each phase drops
local last_seen = {}     -- type -> the last frame one of it was up in the stage
local home = {}          -- type -> the slot it first held in the stage
local fresh = {}         -- the phase's types streamed again into their home already
local restream = nil     -- a type streamed into the slot it holds: { kind, gone }
local armed, fx_q, fx_done, prompting, prompted, pressed, b_down, swallow = false, nil, false, false, nil, false, false, false
local pulled = false
local verdict, paid = nil, nil
local saved_list = nil   -- the stage's preload words and cap before the rift's change
local exit_held = false
local frames, mark = 0, 0
local notes = {}
local report_text = nil

local function note(text)
    notes[#notes + 1] = text
end

local function enter(next_state)
    state = next_state
    mark = frames
end

local function signed(v)
    return v >= 0x80000000 and v - 0x100000000 or v
end

local function distance_to(spot)
    local dx = game.read_f32(PLAYER + 0x80) - spot[1]
    local dy = game.read_f32(PLAYER + 0x84) - spot[2]
    local dz = game.read_f32(PLAYER + 0x88) - spot[3]
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

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

local function health(entity)
    local actor = game.read_u32(entity + ACTOR)
    if actor < 0x10000 or actor % 4 ~= 0 then
        return nil
    end
    return signed(game.read_u32(actor + ACTOR_HP))
end

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

local function enemies_up()
    local flags = game.read_u32(ENTITY_FLAGS)
    for i = 2, ENTITY_COUNT - 1 do
        if game.read_u16(flags + i * 2) ~= 0 then
            return true
        end
    end
    return false
end

local function is_loaded(kind)
    for i = 0, LOADED_COUNT - 1 do
        if game.read_u32(LOADED_TYPES + i * 4) == kind then
            return true
        end
    end
    return false
end

local function slot_type(slot)
    return game.read_u32(game.read_u32(SLOTS + 0x24) + slot * SLOT_ROW + 4)
end

local function blocks_of(kind)
    return game.read_u32(CHAR_TABLE + kind * CHAR_ROW + 4) == 2 and 2 or 1
end

local function gauntlet_beaten()
    local m = game.read_u32(GAME_MANAGER)
    if m < 0x10000 or m % 4 ~= 0 then
        return false
    end
    local b = game.read_u8(m + CLEARED_SLOT)
    return b & 0xE0 == CLEARED_MARK and b & (1 << GAUNTLET_BIT) ~= 0
end

local function rift_at(map)
    for _, r in ipairs(RIFTS) do
        if r.entrance == map then
            return r
        end
    end
    return nil
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

local function thousands(n)
    local sep, text = spanish() and "." or ",", ""
    while n >= 1000 do
        text = string.format("%s%03d", sep, n % 1000) .. text
        n = n // 1000
    end
    return tostring(n) .. text
end

-- One of Smoke's lines in text 34's slot, as gauntlet.lua writes them.
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

local function quiet(n)
    if game.read_u32(MESSAGES + MESSAGE_TYPE) ~= NONE then
        quiet_since = nil
        return false
    end
    quiet_since = quiet_since or frames
    return frames - quiet_since >= n
end

local function show_prompt()
    if game.read_u32(MESSAGES + MESSAGE_TYPE) == PROMPT_TYPE then
        game.write_u32(MESSAGES + MESSAGE_TIMER, 10)
    elseif prompted == nil or frames - prompted >= PROMPT_EVERY then
        prompted = frames
        callgate.call(MESSAGETEXT, {
            args = { callgate.block{ 0, 11, callgate.block{ PROMPT_TEXT, PROMPT_TYPE, 0, 0, 0, 0, 0, 0, 0, 0, 0 } }, 0, 0 } })
    end
end

-- One of the Survival portal's effects on a spot, as its particleoffset
-- trigger plays it: up for `life` frames, or the long life of the
-- Survival portal (args[6] = 1) without one.
local function raise_effect(fx, s, life)
    callgate.call(PARTICLES, {
        ecx = PARTICLE_CMD,
        args = { callgate.block{ 0, 13, callgate.block{ fx[1], fx[2], life or 0, 0, 0, 0, life and 0 or 1, 0, 0, 0, 0, 0, 0 } },
                 callgate.block{ 0, 0, 0, 0, 0 },
                 callgate.block{ 0, f32_bits(s[1]), f32_bits(s[2]), f32_bits(s[3]) } },
        done = function(eax)
            note(string.format(eax == nil and "fx%d=BAD" or "fx%d", fx[2]))
        end })
end

-- The portal's three effects on a spot, raised one a frame by the frame hook.
local function queue_portal(spot, life)
    fx_q = { spot = spot, life = life, i = 1 }
end

-- The memory slots' types, for the notes: tag[types].
local function slots_note(tag)
    local rows, out = game.read_u32(SLOTS + 0x24), {}
    for s = 0, game.read_u32(SLOTS + 0x10) - 1 do
        out[#out + 1] = tostring(signed(game.read_u32(rows + s * SLOT_ROW + 4)))
    end
    note(tag .. "[" .. table.concat(out, ",") .. "]")
end

local function request(map, entry)
    game.write_u8(PLAYER + PLAYER_LOADING, 1)
    game.write_u8(PLAYER + ENTITY_STRIDE + PLAYER_LOADING, 1)
    game.write_u32(LOAD_PORTAL, 1)
    game.write_u32(LOAD_MAP, map)
    game.write_u32(LOAD_ENTRY, entry)
    game.write_u8(LOAD_REQUEST, 1)
end

-- The stage's preload list back as authored.
local function restore_list()
    if saved_list then
        for i, word in ipairs(saved_list.words) do
            game.write_u32(saved_list.desc + 0x24 + (i - 1) * 4, word)
        end
        game.write_u32(saved_list.desc + 0x20, saved_list.cap)
        saved_list = nil
    end
end

local function release_group()
    if group then
        local base = MANAGER + group * GROUP_STRIDE
        if game.read_u32(base + RIFT_MARK_OFFSET) == RIFT_MARK then
            game.write_u32(base + RIFT_MARK_OFFSET, 0)
            game.write_u8(base + ENABLED_OFFSET, 0)
            game.write_u16(base + COUNT_OFFSET, 0)
        end
        group = nil
    end
end

local function finish(final)
    release_group()
    restore_list()
    if QA then
        report_text = "POSTGAME 0.14.3 " .. (rift and rift.name or "?") .. " " .. final .. " | " .. table.concat(notes, " ")
    end
    notes = {}
    active, phase, want, wanted, skipped, unloads = false, 0, {}, {}, {}, {}
    streaming, stream_since, rest_until, wait_since, build = nil, nil, nil, nil, nil
    boss_seen, boss_gone_since, bosses_over, verdict, paid, exit_held = false, nil, nil, nil, nil, false
    armed, prompting, stage_spot, last_seen, home, fresh, restream, fx_q = false, false, nil, {}, {}, {}, nil, nil
    rift = rift_at(at_map)
    enter(rift and "entrance" or "off")
end

local function warp()
    local s, facing = rift.spot, rift.facing
    callgate.call(SET_POSITION, {
        ecx = PLAYER,
        args = { callgate.block{ f32_bits(s[1]), f32_bits(s[2] - 16), f32_bits(s[3]), 0 } },
        done = function(eax)
            if eax ~= nil then
                for _, off in ipairs(MOMENTUM) do
                    game.write_u32(PLAYER + off, 0)
                end
                game.write_f32(PLAYER + 0x3190, 1.0)
                game.write_f32(PLAYER + 0x3150, 1.0)
                game.write_f32(PLAYER + FACING, facing)
                game.write_u8(CAMERA_HOLD, 0)
                game.write_u8(CAMERA_CUT, 1)
                if game.read_f32(CAMERA_BLEND) < 1 / 6 then
                    game.write_f32(CAMERA_BLEND, 1 / 6)
                end
            end
            finish(verdict or "CHECK")
        end })
end

-- The next phase: the types it needs, bosses first.
local function start_phase()
    phase = phase + 1
    local p = rift.phases[phase]
    if p == nil then
        if stage_spot then
            queue_portal(stage_spot, FLASH)          -- the chain is won: the rift flashes once more
        end
        enter("paying")
        return
    end
    want, wanted, skipped, unloads, fresh = {}, {}, {}, {}, {}
    for _, list in ipairs({ p.bosses, p.extras }) do
        for _, e in ipairs(list) do
            if not wanted[e[1]] then
                wanted[e[1]] = true
                want[#want + 1] = e[1]
            end
        end
    end
    slots_note("p" .. phase)
    wait_since = nil
    enter("freeing")
end

-- Every type up in the stage, seen this frame.
local function track_types()
    local flags = game.read_u32(ENTITY_FLAGS)
    for i = 2, ENTITY_COUNT - 1 do
        if game.read_u16(flags + i * 2) ~= 0 then
            last_seen[game.read_u16(PLAYER + i * ENTITY_STRIDE + ENTITY_TYPE)] = frames
        end
    end
end

-- The slot each type first holds in the stage: its home.
local function track_homes()
    local rows = game.read_u32(SLOTS + 0x24)
    for s = 0, game.read_u32(SLOTS + 0x10) - 1 do
        local kind = game.read_u32(rows + s * SLOT_ROW + 4)
        if kind ~= NONE and home[kind] == nil then
            home[kind] = s
        end
    end
end

-- A slot's type may be streamed over: nobody of it up for TYPE_CLEAR frames.
local function clear(kind)
    return kind == NONE or (not entity_of(kind) and frames - (last_seen[kind] or -TYPE_CLEAR) >= TYPE_CLEAR)
end

-- Goro's run: the slots holding blocks 0 and 1 unloaded (slot 0 is streamed
-- over), all of them with nobody up and nothing else the phase needs, and
-- both blocks with memory. False: not now (a body still up) or never.
local function plan_run()
    local rows, count, blocks = game.read_u32(SLOTS + 0x24), game.read_u32(SLOTS + 0x10), game.read_u32(SLOTS + 0x1C)
    local list = {}
    for s = 0, count - 1 do
        local t, b = game.read_u32(rows + s * SLOT_ROW + 4), game.read_u32(rows + s * SLOT_ROW + 8)
        if t ~= NONE and b < 2 then
            if (wanted[t] and blocks_of(t) == 1) or not clear(t) then
                return false
            end
            if s > 0 then
                list[#list + 1] = s
            end
        end
    end
    for b = 0, 1 do
        if game.read_u32(blocks + b * SLOT_ROW + 0x10) & BLOCK_MEMORY == 0 then
            return false
        end
    end
    unloads = list
    return true
end

-- A slot for one of the phase's one-block types new to the stage: holding no
-- type the phase wants and no one alive, not the home of a type the phase
-- wants, its first block with memory and its own (or no one's), and clear of
-- a two-block boss's run when the phase has one.
local function pick_slot(run)
    local rows, blocks = game.read_u32(SLOTS + 0x24), game.read_u32(SLOTS + 0x1C)
    local nblocks = game.read_u32(SLOTS + 0x08)
    local reserved = {}
    for _, k in ipairs(want) do
        if home[k] then
            reserved[home[k]] = true
        end
    end
    for s = game.read_u32(SLOTS + 0x10) - 1, 0, -1 do
        local t, b = game.read_u32(rows + s * SLOT_ROW + 4), game.read_u32(rows + s * SLOT_ROW + 8)
        if not wanted[t] and not reserved[s] and clear(t) and b < nblocks and not (run and b < 2) then
            local owner = game.read_u32(blocks + b * SLOT_ROW + 4)
            if game.read_u32(blocks + b * SLOT_ROW + 0x10) & BLOCK_MEMORY ~= 0 and (owner == NONE or owner == t) then
                return s
            end
        end
    end
    return nil
end

local function stream(kind, slot)
    note(string.format("%d:slot%d(was%d)", kind, slot, signed(slot_type(slot))))
    if slot_type(slot) == kind then
        restream = { kind = kind, gone = false }     -- the same type again: wait for it to go, then come back
    end
    home[kind] = home[kind] or slot
    streaming, stream_since = kind, frames
    callgate.call(MODELSTREAM, {
        args = { callgate.block{ 0, 2, callgate.block{ slot, kind } }, 0, 0 },
        done = function(eax)
            if eax == nil then
                note("stream=BAD")
                skipped[kind], streaming = true, nil
            end
        end })
end

-- The highest empty group, made the rift's: the phase's bosses (each with
-- its count) first, then its extras, those loaded, EXTRA_GAP frames apart,
-- around P1.
local function drop()
    local p = rift.phases[phase]
    local kinds, bosses = {}, 0
    for _, list in ipairs({ p.bosses, p.extras }) do
        for _, e in ipairs(list) do
            if is_loaded(e[1]) then
                for _ = 1, e[2] do
                    kinds[#kinds + 1] = e[1]
                end
                if list == p.bosses then
                    bosses = bosses + e[2]
                end
            end
        end
    end
    if bosses == 0 then
        note("p" .. phase .. "=noboss")
        start_phase()
        return
    end
    if group == nil then
        for g = GROUP_LIMIT - 1, 0, -1 do
            if game.read_u16(MANAGER + g * GROUP_STRIDE + COUNT_OFFSET) == 0 then
                group = g
                break
            end
        end
    end
    if group == nil then
        note("group=none")
        enter("paying")
        return
    end
    build = { kinds = kinds, next = 1,
              spot = stage_spot or { game.read_f32(PLAYER + 0x80), game.read_f32(PLAYER + 0x84), game.read_f32(PLAYER + 0x88) } }
    enter("building")
end

local function build_step()
    local base = MANAGER + group * GROUP_STRIDE
    local last = math.min(#build.kinds, build.next + BUILD_EVERY - 1)
    for i = build.next, last do
        local entry = base + ENTRY_BASE + (i - 1) * ENTRY_STRIDE
        local ring = RING[(i - 1) % #RING + 1]
        local s = build.spot
        for k, word in ipairs(ENTRY_TEMPLATE) do
            if k == 1 then
                word = build.kinds[i]
            elseif k == 7 then
                word = math.floor(s[1] + ring[1] + 0.5) & 0xFFFFFFFF
            elseif k == 8 then
                word = math.floor(s[2] - SPAWN_LIFT) & 0xFFFFFFFF
            elseif k == 9 then
                word = math.floor(s[3] + ring[2] + 0.5) & 0xFFFFFFFF
            elseif k == 23 then
                word = word & 0xFFFF | ((i - 1) * EXTRA_GAP) << 16
            end
            game.write_u32(entry + (k - 1) * 4, word)
        end
    end
    build.next = last + 1
    if build.next <= #build.kinds then
        return
    end
    note(string.format("group%d:%d", group, #build.kinds))
    for k, word in ipairs(GROUP_HEADER) do
        game.write_u32(base + (k - 1) * 4, word)
    end
    game.write_u32(base + RIFT_MARK_OFFSET, RIFT_MARK)
    game.write_u16(base + COUNT_OFFSET, #build.kinds)
    game.write_u8(base + ENABLED_OFFSET, 1)
    build = nil
    boss_seen, boss_gone_since, bosses_over = false, nil, nil
    enter("dropping")
    callgate.call(START_GROUP, {
        ecx = MANAGER,
        args = { group, NONE, 0 },
        done = function(eax)
            if eax == nil then
                note("start=BAD")
            end
        end })
    if stage_spot then
        queue_portal(stage_spot, FLASH)              -- the phase comes out of the rift
    end
end

local function p1_down()
    local hp = health(PLAYER)
    if hp and hp <= 0 then
        note(string.format("p1 down@%d(phase%d)", frames, phase))
        enter("failing")
        return true
    end
    return false
end

-- The phase's bosses up, each made killable; the count of them up.
local function bosses_up()
    local p, n = rift.phases[phase], 0
    local flags = game.read_u32(ENTITY_FLAGS)
    for i = 2, ENTITY_COUNT - 1 do
        local entity = PLAYER + i * ENTITY_STRIDE
        if game.read_u16(flags + i * 2) ~= 0 then
            local kind = game.read_u16(entity + ENTITY_TYPE)
            for _, b in ipairs(p.bosses) do
                if b[1] == kind then
                    n = n + 1
                    local actor = game.read_u32(entity + ACTOR)
                    if actor >= 0x80000000 and actor < 0x84000000 and actor % 4 == 0
                            and signed(game.read_u32(actor + ACTOR_HP)) > 0 and game.read_u8(actor + CAN_KILL) == 0 then
                        game.write_u8(actor + CAN_KILL, 1)
                    end
                end
            end
        end
    end
    return n
end

-- The frames are in another map: the stage, the entrance, or the run is over.
local function arrive(map)
    at_map, armed, fx_q, fx_done, prompting, quiet_since = map, false, nil, false, false, nil
    if state == "loading" and map == rift.stage then
        note("stage@" .. frames)
        stage_seen = false
        enter("stage")
    elseif state == "returning" and map == rift.entrance then
        enter("returning")
    elseif active then
        note("left@" .. map)
        finish("LEFT")
    else
        rift = rift_at(map)
        enter(rift and "entrance" or "off")
    end
end

local function entrance_step()
    if not gauntlet_beaten() or frames - mark < SETTLE then
        return
    end
    local d = distance_to(rift.spot)
    if not fx_done and d < FX_RADIUS then
        fx_done = true
        queue_portal(rift.spot, nil)                 -- the entrance's portal stays up
        return
    end
    if d > ARM_RADIUS then
        armed = true
    end
    local up = game.read_u32(MESSAGES + MESSAGE_TYPE)
    prompting = armed and d < PROMPT_RADIUS and (up == NONE or up == PROMPT_TYPE)
    if prompting and pressed then
        prompting = false
        active, phase = true, 0
        note(string.format("open@%d(d=%.0f)", frames, d))
        pulled = false
        enter("pulling")
        local s = rift.spot
        callgate.call(REACTION, {
            args = { callgate.block{ 0, 16, callgate.block{ PULL_ANIM, 0, PULL_ANIM, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } },
                     callgate.block{ CHAR_TARGET, 0, 0, 0, 0 },
                     callgate.block{ 0, f32_bits(s[1]), f32_bits(s[2]), f32_bits(s[3] + 400) } },
            done = function(eax)
                if eax == nil then
                    note("pull=BAD")
                end
            end })
    elseif prompting then
        show_prompt()
    else
        prompted = nil
    end
    pressed = false
end

-- The stage's own fight: over once one of its fighters was up and nobody is
-- up and no wave has run for STAGE_QUIET frames.
local function stage_step()
    if p1_down() then
        return
    end
    if frames - mark == SETTLE then
        slots_note("s")
        stage_spot = { game.read_f32(PLAYER + 0x80), game.read_f32(PLAYER + 0x84), game.read_f32(PLAYER + 0x88) }
        note(string.format("rift(%.0f,%.0f,%.0f)", stage_spot[1], stage_spot[2], stage_spot[3]))
        queue_portal(stage_spot, FLASH)              -- the stage's rift flashes where P1 landed
    end
    if not stage_seen then
        local flags = game.read_u32(ENTITY_FLAGS)
        for i = 2, ENTITY_COUNT - 1 do
            if game.read_u16(flags + i * 2) ~= 0 and rift.first[game.read_u16(PLAYER + i * ENTITY_STRIDE + ENTITY_TYPE)] then
                stage_seen = true
            end
        end
        if not stage_seen and frames - mark < STAGE_WAIT then
            return
        end
    end
    if enemies_up() or game.read_u8(MANAGER + ST_ACTIVE) ~= 0 then
        quiet_since = nil
        return
    end
    quiet_since = quiet_since or frames
    if frames - quiet_since < STAGE_QUIET then
        return
    end
    note(string.format("stage%s@+%d", stage_seen and "" or "(none up)", frames - mark))
    quiet_since = nil
    enter("telling")
end

-- Goro's run first when the phase needs one, then every missing type, one
-- stream at a time with a rest after each, then the drop.
local function freeing_step()
    local first = want[1]
    if first == nil or blocks_of(first) ~= 2 or is_loaded(first) or skipped[first] then
        enter("streaming")
        return
    end
    if #unloads == 0 then
        if not plan_run() then
            if frames - mark >= SLOT_WAIT then
                note(first .. "=noroom")
                skipped[first] = true
                enter("streaming")
            end
            return
        end
        if #unloads == 0 then
            stream(first, 0)                 -- the run is clear: into slot 0, which takes blocks 0 and 1
            enter("streaming")
            return
        end
    end
    local s = table.remove(unloads, 1)       -- one a frame; then the run is planned again
    note(string.format("unload%d(%d)", s, signed(slot_type(s))))
    callgate.call(UNLOAD, { args = { s } })
end

-- The phase's next stream: first a type with a home in the stage that is
-- missing, or loaded but used already (a fresh copy of its memory), into its
-- home; then a type new to the stage into a free slot.
local function next_stream()
    for _, k in ipairs(want) do
        if not skipped[k] and blocks_of(k) == 1 and home[k]
                and (not is_loaded(k) or (last_seen[k] and not fresh[k])) then
            return k, home[k]
        end
    end
    for _, k in ipairs(want) do
        if not skipped[k] and not is_loaded(k) then
            return k, nil
        end
    end
    return nil, nil
end

local function streaming_step()
    if streaming then
        if restream and restream.kind == streaming and not restream.gone then
            if not is_loaded(streaming) or frames - stream_since > 120 then
                restream.gone = true                 -- unloaded (or the change was missed): now it loads again
            end
        elseif is_loaded(streaming) then
            note(streaming .. ":loaded")
            fresh[streaming], restream = true, nil
            streaming, rest_until = nil, frames + STREAM_REST
        elseif frames - stream_since > WAIT_LOAD then
            note(streaming .. "=never")
            skipped[streaming], streaming = true, nil
        end
        return
    end
    if rest_until and frames < rest_until then
        return                                       -- the game streams one character at a time
    end
    rest_until = nil
    local kind, slot = next_stream()
    if kind == nil then
        drop()
        return
    end
    if blocks_of(kind) == 2 then
        note(kind .. "=notfirst")                    -- a two-block type only comes as the phase's first
        skipped[kind] = true
        return
    end
    if slot then
        local t = slot_type(slot)                    -- its home: free of anyone up, and of anything else wanted
        if (t ~= kind and wanted[t]) or not clear(t) then
            slot = nil
        end
    else
        slot = pick_slot(want[1] and blocks_of(want[1]) == 2)
    end
    if slot == nil then
        wait_since = wait_since or frames
        if frames - wait_since >= SLOT_WAIT then
            note(kind .. ":noslot")
            skipped[kind], wait_since = true, nil
        end
        return
    end
    wait_since = nil
    stream(kind, slot)
end

-- In a phase's fight: over once none of its bosses has been up for
-- BOSS_GONE frames (after one was), and its group is done or GRUNT_WAIT has
-- passed since.
local function fight_step()
    if p1_down() then
        return
    end
    if bosses_up() > 0 then
        boss_seen, boss_gone_since = true, nil
        return
    end
    if not boss_seen then
        if frames - mark > WAIT_BOSS then
            note("p" .. phase .. "=nodrop")
            start_phase()
        end
        return
    end
    boss_gone_since = boss_gone_since or frames
    if frames - boss_gone_since < BOSS_GONE then
        return
    end
    bosses_over = bosses_over or frames
    local running = game.read_u8(MANAGER + ST_ACTIVE) ~= 0 and game.read_u16(MANAGER + ST_GROUP) == group
    if running and frames - bosses_over < GRUNT_WAIT then
        return
    end
    note(string.format("p%d beaten@+%d", phase, frames - mark))
    start_phase()
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
            if active and at_map == rift.stage then
                track_types()
                track_homes()
            end
            if fx_q then
                raise_effect(PORTAL_FX[fx_q.i], fx_q.spot, fx_q.life)
                fx_q.i = fx_q.i + 1
                if fx_q.i > #PORTAL_FX then
                    fx_q = nil
                end
                return
            end
            if state == "entrance" then
                entrance_step()
            elseif state == "pulling" then
                local s = game.read_u32(PLAYER + STATE)
                if s == REACTING then
                    pulled = true
                end
                if (pulled and s ~= REACTING) or (not pulled and frames - mark > 2) or frames - mark >= PULL_MAX then
                    note(string.format("pull@+%d(%s)", frames - mark, pulled and "seen" or "none"))
                    request(rift.stage, rift.entry)
                    enter("loading")
                end
            elseif state == "loading" then
                if frames - mark > WAIT_LOAD then
                    note("load=never")
                    finish("CHECK")
                end
            elseif state == "stage" then
                stage_step()
            elseif state == "telling" then
                if quiet(QUIET) or frames - mark > QUIET * 4 then
                    tell(line("more"))
                    start_phase()
                end
            elseif state == "freeing" then
                freeing_step()
            elseif state == "streaming" then
                streaming_step()
            elseif state == "building" then
                build_step()
            elseif state == "dropping" then
                if bosses_up() > 0 then
                    note("p" .. phase .. "@+" .. (frames - mark))
                    enter("fighting")
                elseif frames - mark > WAIT_BOSS then
                    note("p" .. phase .. "=nodrop")
                    start_phase()
                end
            elseif state == "fighting" then
                fight_step()
            elseif state == "paying" then
                if not paid then
                    if quiet(QUIET) or frames - mark > QUIET * 4 then
                        paid = frames
                        tell(string.format(line("reward"), thousands(rift.reward)))
                    end
                elseif verdict == nil then
                    verdict = "BEATEN"
                    note("xp+" .. rift.reward)
                    callgate.call(ADDEXPERIENCE, {
                        args = { callgate.block{ 0, 1, callgate.block{ rift.reward } }, callgate.block{ CHAR_TARGET, 0, 0, 0, 0 }, 0 } })
                elseif frames - paid > LINE_SHOW then
                    request(rift.entrance, rift.back)
                    enter("returning")
                end
            elseif state == "failing" then
                if frames - mark > FAIL_WAIT then
                    verdict = "FAILED"
                    request(rift.entrance, rift.back)
                    enter("returning")
                end
            elseif state == "returning" then
                if at_map == rift.entrance and frames - mark > SETTLE then
                    warp()
                    enter("off")
                elseif at_map ~= rift.entrance and frames - mark > WAIT_LOAD then
                    note("return=never")
                    finish("CHECK")
                end
            end
        end,
    },
    {
        -- the stage's preload: the rift's additions for its run
        address = PRELOAD,
        before = function(ctx)
            if not active or #rift.added == 0 or game.read_u32(ctx.esp + 4) ~= rift.desc then
                return
            end
            if saved_list == nil then
                saved_list = { desc = rift.desc, cap = game.read_u32(rift.desc + 0x20), words = {} }
                for i = 0, 5 do
                    saved_list.words[i + 1] = game.read_u32(rift.desc + 0x24 + i * 4)
                end
            end
            local n = 0
            while n < 4 and saved_list.words[n + 1] ~= NONE do
                n = n + 1
            end
            for i, kind in ipairs(rift.added) do
                game.write_u32(rift.desc + 0x24 + (n + i - 1) * 4, kind)
            end
            game.write_u32(rift.desc + 0x24 + (n + #rift.added) * 4, NONE)
            game.write_u32(rift.desc + 0x20, n + #rift.added)
            note("preload+" .. #rift.added)
        end,
    },
    {
        -- a stage's own way out (it opens once its fight is won): while the
        -- chain runs its load request is taken back (the rift sends P1 back
        -- itself, with direct requests)
        address = LOADMAP,
        after = function(ctx)
            if not active or at_map ~= rift.stage or state == "paying" or state == "returning" or state == "failing"
                    or game.read_u8(LOAD_REQUEST) == 0 then
                return
            end
            game.write_u8(LOAD_REQUEST, 0)
            game.write_u8(PLAYER + PLAYER_LOADING, 0)
            game.write_u8(PLAYER + ENTITY_STRIDE + PLAYER_LOADING, 0)
            if not exit_held then
                note("exit=held@" .. frames)
                exit_held = true
            end
        end,
    },
    {
        -- port 0's pad: in front of a rift Black opens it instead of its own
        -- action, and stays swallowed until it is let go
        address = PAD_MAP,
        before = function(ctx)
            if ctx.eax ~= PADS then
                return
            end
            local down = game.read_u8(PADS + PAD_BLACK) ~= 0
            if down and (prompting or swallow) then
                if prompting and not b_down then
                    pressed = true
                end
                game.write_u8(PADS + PAD_BLACK, 0)
                swallow = true
            else
                swallow = false
            end
            b_down = down
        end,
    },
}

return callgate.hooks(hooks)
