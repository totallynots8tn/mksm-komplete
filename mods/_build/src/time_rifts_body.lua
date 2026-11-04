-- Time Rifts 0.12.0 QA: rifts without a portal model. Each rift is a spot in
-- an arena: step into it and a boss drops in at the rift's boss spot and
-- waits there. Wu Shi's arena (map 110): walk into the big hollow tree, the
-- arena reloads (the load request the game's loadmap command makes), then an
-- Orochi drops in with burning monks. Mileena's arena (map 132, the secret
-- area): its purple wall portal shows the A prompt, A pulls P1 in and sends
-- them back to the shrine deck (no reload), and Mileena waits in her arena
-- with Tarkatans: she drops when P1 comes back within APPROACH of her spot
-- (else Johnny Cage, else the Orochi). Goro's Lair (map 102, past the bell
-- door): the A prompt, the pull-in, the arena reloads and P1 is put back,
-- Raiden warns of the rifts, a rush comes, then Goro. Spots were read live
-- from P1 on 2026-10-31 and 2026-11-01.
--
-- 0.10.0: company and a third rift. A boss's extras (rift.extras) share its
-- group, EXTRA_GAP frames apart (entry +0x5A delays) around its spot; their
-- type streams in after the boss's, into a slot holding neither (left out
-- without one). Groups are written over frames (BUILD_EVERY entries: 29
-- writes each, 256 per callback). Goro's Lair: Raiden's line is written over
-- the unused "Raiden: Tutorial Message 13." (text 34) where its 128-byte
-- slot has room, in Spanish or English, and shown as a speaker line (type 5,
-- like "Sub-Zero: ..."). The rush is 3 enemies of the types the map has
-- loaded (its two slots hold Oni and Tarkatan; a third type would need the
-- preload list, which is Shaolin Shuffle's) with 2 clones each; it is over
-- when the spawn manager no longer runs its group and none of its types is
-- left. Then Goro (see finale_start).
--
-- 0.10.1 (QA 2026-11-01: Raiden's line and the warp worked): the rush takes
-- regular fighters only (RUSH_KINDS; Shuffle had loaded tree mouths), and
-- Goro's Lair's pull-in turns P1 the other way (it carried P1 into the arena).
--
-- 0.12.0: the Survival gauntlet in Smoke's secret area runs in its own
-- script (gauntlet.lua, with its own callgate); nothing here changed but the
-- version.
--
-- 0.11.4 (QA 2026-11-03, the user: "I fought and killed him"): 0.11.2's
-- "fell" was Kintaro's leap or the floor below the dais, not a fall out of
-- the map. A boss only counts as fallen once it has been FALL_DEPTH (now
-- 1,500) below where it dropped for FALL_FRAMES in a row; only then is it
-- put back (or gone).
--
-- 0.11.3 (QA 2026-11-03: no crash; Kintaro dropped in front of the chair,
-- fell out of the world within 4 s at full health, 12,568 from P1, and the
-- rift called him gone): a boss that falls FALL_DEPTH below where it dropped
-- is put back on the rift's spot with the game's set-position (0x15DC30, as
-- P1's warp) and its momentum cleared, up to MAX_LIFTS times; then it is gone
-- and the next boss comes. Map 199's next boss is the Orochi, which held the
-- chair's dais before; a stream may take back a slot the rift itself filled
-- (borrow).
--
-- 0.11.2 (QA 2026-11-01: map 199 crashed again, on the main thread, in the
-- heap free of the stream that unloads the Tarkatan for Kano, a second after
-- the Orochi had been streamed over the area's priests; the first crash also
-- followed that swap, and the Orochi alone is fine in map 110): map 199's
-- rift is Kintaro alone, streamed over the Tarkatans only (rift.borrow: the
-- slots a rift may take), with three of the area's own priests; the
-- priests' slot is never unloaded.
--
-- 0.11.1 (QA 2026-11-01: map 199 crashed in the game's zlib worker, thread
-- 30, mid-fight; entered before its rush, the rift found no free slot): a
-- prompt rift with after_waves opens only once enough of those vanilla waves
-- are cleared (the wave records at 0x6C0168) with no group running and no
-- enemy up; a rift with drop_back drops its enemies on the last floor P1
-- crossed that far from the portal (its trail), not where P1 stood; streams
-- rest STREAM_REST frames after each load (the game streams one character at
-- a time; two back to back were new in 0.11.0); the can't-die flag is only
-- cleared on living actors.
--
-- 0.11.0: a fourth rift and more company. The co-op area (map 199, past its
-- vanilla rush, which LDK already doubles): the A prompt, the pull-in (P1
-- turned the way the spot was read, pull_facing), the warp back, then a pack
-- (rift.pack): the Orochi and Kano drop together, fought like a rush (over
-- when neither type is left), each made killable; then Kintaro (one memory
-- block: streamed in like any boss). Wu Shi's Orochi brings 5 burning monks
-- and 3 priests (extras are a list now). Every slot a stream takes from a
-- type the map's own groups author is streamed back once the rift is over
-- (remember/restore_step), never under a living or dying actor: map 199's
-- two slots hold its Tarkatans and priests.
--
-- 0.10.2: the rift's enemies attack. Their group now gets the header a
-- vanilla wave has (GROUP_HEADER); with the zeros of an unused group they
-- only struck back with their counter.
--
-- 0.9.1: the pull-in. A plays the reaction the game's own portals play
-- before their load (the Portals' rec_portal: reaction animation 0x26 with
-- every other argument 0, which resolves to 0x26 for P1), through the
-- reaction command's exec (0x16A00) on "char" 0, turned by a point in the
-- portal's wall. P1's state (+0x1E04) is 0xC while it plays; the warp waits
-- for it to end (at most PULL_MAX frames). Mileena's spot moved back into her
-- arena (QA 2026-11-01: on the deck she dropped right beside P1).
--
-- 0.9.0: the purple wall portal works like a real one. In front of it the
-- game's own portal prompt shows: the messagetext command (exec 0x12847)
-- with text 391, the A button icon alone, and type 4, the type portals and
-- exits use. One call shows it; while a type-4 message shows, a repeat call
-- only sets its timer (+0x6F0) back to 10, so the rift does just that. A
-- there opens the rift and is swallowed (port 0's analog A byte, zeroed
-- before the pad is read, until it is let go), so Liu doesn't jump. P1 then
-- moves to the deck with the game's set-position routine (0x15DC30, what
-- versus respawns use, 0x1F390): besides +0x80 and +0xE0 it drops the cached
-- floor (+0x1DF6) and resets the physics, which is why writing the position
-- never stuck. As that respawn does, the momentum is cleared and the camera
-- told to cut; P1 faces the way the deck spot was read. The boss drops on
-- the deck's own enemy spawn point (map 132 group 17), and the TIMERIFT line
-- notes where P1 landed.
--
-- 0.8.2: the boss can die. The per-character AI setup (the switch on the
-- type at 0xE2F11) makes most Mortal Kombat bosses unkillable, Mileena
-- included: actor +0xD4 = 0, and TakeDamage (0x153E20) then stops their
-- health at 1 so their scripted fight can play its ending. Out of that fight
-- the rift sets it back to 1 every frame the boss is up (noted once as
-- "killable@").
--
-- 0.8.1: the secret area is big and the portal is about 4,900 units from
-- mid-arena, so the arena may not be solid (or near enough for the game to
-- keep an enemy) when the rift opens: map 132's boss now waits for P1 to come
-- near the arena. The TIMERIFT line notes P1's distance when it drops. The
-- boss types were also two off (the names came from WAD records read 0x14
-- too high, analysis/mk_roster): 64 is Shao Kahn, Mileena is 66 (map 132
-- preloads her for her own fight), Johnny Cage is 78, and 76 (0.7.x's "Johnny
-- Cage") is a generic humanoid grunt.
--
-- 0.8.0: the verdict is the boss's health: BEATEN when the game sets it to
-- 0 (setHealth 0x153CD0 on its actor, or actor +0x368 seen at 0). A boss
-- that disappears with health left, or falls out of the map, is noted with
-- its health and distance from P1, and the next boss drops (after the last:
-- VANISHED). FAILED when P1's health reaches 0, LEFT when the map changes
-- first (no spawn group is built on the new map). A beaten rift is remembered in
-- the save (level slot 22 of player 1, which no game code reads: a bit per
-- rift under the mark 0xA0) and never opens again on that save. The boss's
-- group carries the RIFT mark that LDK and Shaolin Shuffle leave alone
-- (core.lua), and is emptied again when the rift is over. QA builds still
-- write one TIMERIFT line to the log (by failing with error() one frame after
-- the verdict, so the cleanup is kept), which also switches the script off:
-- one rift per session.
--
-- 0.7.4: map 132's only entry (1) is the map's start, about 62,000 units
-- from the secret arena, and the game removes enemies spawned that far from
-- the player (QA 2026-10-31 18:0x; writing P1's position doesn't stick), so
-- that rift drops its boss without a reload. 0.7.2: y grows downward, so the
-- boss spawns SPAWN_LIFT above its spot (vanilla relative entries use y
-- -128). 0.6.0: the Orochi (type 0x1E: model "orochi", sound bank
-- "hellbeast") replaced the Oni Warlord (36), which leapt out over the
-- bamboo fence (an entity keeps its position at +0x80, +0xE0, +0x2C60 and
-- +0x3164; moving it doesn't stick).
--
-- Time Rifts is extra content, not part of the randomizer: it never touches
-- a map's preload list (Shaolin Shuffle's) or any authored spawn entry. The
-- boss gets the highest empty spawn group as a one-entry group that only the
-- rift starts. Map 110 has no spawn-group file, so there the rift first
-- switches off whatever groups the manager still holds (the last map's); map
-- 132's own groups (1-19) are left alone.
--
-- Loading the boss: a type the level hasn't loaded only streams in on the spot
-- into one of the first <count> memory slots (0x17B030 scans [0x6322F8+0x10]
-- of them), so the rift loads it the way cutscenes swap characters: the
-- modelstream command (0x17BA00) queues (slot, type) for 0x17BA40, which
-- unloads that slot and loads the type there (live-tested 2026-10-31). The
-- rift takes a slot whose type has no living actor, preferring one no enabled
-- spawn group authors.
--
-- The reload: loadmap (0xD0E00) only requests a load when a player has bit
-- 0x40 at +0x3204, which the exit and portal triggers provide; out in the
-- arena it quietly does nothing. What it writes when it does is all a load
-- request is: +0x3217 = 1 on both player entities (the game does that in
-- single player too), 0x5ACEE0 = 0, the target map 0x4FC160 and entry
-- 0x4FC164, and the request flag 0x5ACEDC = 1. The rift writes the same.
local QA            = true          -- write the TIMERIFT line (and stop) after each rift
local ONCE_PER_SAVE = true          -- a beaten rift never opens again on that save
local GAMEPLAY      = 0x00154F60    -- gameplay update; skipped while paused
local LOAD_REQUEST  = 0x005ACEDC    -- u8: a map load is wanted
local LOAD_ARG3     = 0x005ACEE0
local LOAD_MAP      = 0x004FC160
local LOAD_ENTRY    = 0x004FC164
local PLAYER_LOADING = 0x3217       -- u8 on each player entity, set by loadmap
local START_GROUP   = 0x001D2600    -- spawn manager thiscall (group, entity index or -1, 0); ret 0xC
local MODELSTREAM   = 0x0017BA00    -- modelstream command: [[arg1+8]] = slot, type
local PRELOAD       = 0x00015DEE
local SET_HEALTH    = 0x00153CD0    -- thiscall: actor in ecx, the new health at [esp+4]
local SET_POSITION  = 0x0015DC30    -- thiscall: entity in ecx, -> x, y, z, w at [esp+4]
local MESSAGETEXT   = 0x00012847    -- messagetext command's exec: (event, a1, a2), stdcall
local REACTION      = 0x00016A00    -- reaction command's exec: (event, target, from), stdcall
local PAD_MAP       = 0x00129480    -- one port's pad -> action bits; eax = its joypad object

local CURRENT_MAP   = 0x00505970
local DESC_SPAWN_FILE = 0x7C        -- map descriptor: spawn-group file, -1 for none
local NONE          = 0xFFFFFFFF
local MANAGER       = 0x006DBFB0
local GROUP_STRIDE  = 0xA6C
local GROUP_LIMIT   = 50
local ENTRY_BASE    = 0x18
local ENTRY_STRIDE  = 0x74
local ENTRY_SLOTS   = 22
local COUNT_OFFSET  = 0xA68
local ENABLED_OFFSET = 0xA6A
local RIFT_MARK_OFFSET = 0xA10      -- as core.lua: LDK and Shuffle leave a marked group alone
local RIFT_MARK     = 0x54464952    -- "RIFT"
local OROCHI        = 30            -- 0x1E, the Orochi normal rooms author
local MILEENA       = 66            -- map 132 preloads her (types: analysis/mk_roster)
local JOHNNY_CAGE   = 78            -- never spawned as an enemy yet
local TARKATAN      = 14
local BURNING_MONK  = 77            -- voice bank CHAR_BURNINGMONK_1 (76 is the other one)
local PRIEST        = 27
local KANO          = 54            -- a Mortal Kombat boss: his AI setup makes him unkillable
local KINTARO       = 58            -- one memory block, unlike Goro
local GORO          = 57            -- Goro of his battle (47 carries the mace): two memory blocks
-- the rush's types: regular fighters only. Shaolin Shuffle's outsiders also
-- bring the Living Forest's tree mouth (42) and tree arms (43): hazards a
-- wave doesn't count, hard to kill (QA 2026-11-01: three tree mouths held
-- the rush open)
local RUSH_KINDS    = { [4] = true, [8] = true, [10] = true, [11] = true, [12] = true, [13] = true, [14] = true,
                        [15] = true, [18] = true, [19] = true, [26] = true, [27] = true, [76] = true, [77] = true }
local UNLOAD        = 0x0017B280    -- unloads a memory slot's type, as a stream does first: (slot)
local CHAR_TABLE    = 0x004FA9F0    -- character rows of 0x30: +0x04 the memory blocks a type needs
local CHAR_ROW      = 0x30
local DELAY_OFFSET  = 0x5A          -- entry: u16 spawn delay in frames after the group start
local ST_GROUP      = 0x20920       -- spawn manager: the running group (u16),
local ST_SPAWNED    = 0x20922       -- how many of its entries spawned (u16),
local ST_ACTIVE     = 0x2092A       -- and whether one runs (u8: 0 once it is cleared)

local PLAYER        = 0x005D1AB8    -- entity of in-use flag 0 (P1); position floats at +0x80
local ENTITY_STRIDE = 0x3238
local ENTITY_TYPE   = 0x1DFE        -- u16 character ID (kept after death)
local ENTITY_FLAGS  = 0x0051004C    -- -> u16 per entity, non-zero while in use
local ENTITY_COUNT  = 12
local ACTOR         = 0x200         -- entity: its actor; health at +0x368, max at +0x370
local ACTOR_HP      = 0x368
local ACTOR_MAX_HP  = 0x370
local CAN_KILL      = 0xD4          -- actor: 0 = its health stops at 1 (MK bosses' AI setup)
local FACING        = 0x94          -- entity: facing angle (float)
local STATE         = 0x1E04        -- entity: u32 state, 0 standing
local REACTING      = 0xC           -- the state a reaction plays in
local PULL_ANIM     = 0x26          -- the portals' pull-in reaction, as it resolves for P1
local CHAR_TARGET   = 0x72616863    -- "char": a reaction's target kind, its index at +0x10
local MOMENTUM      = { 0x3184, 0x3188, 0x318C, 0xD0, 0xD4, 0xD8, 0x3144, 0x3148, 0x314C, 0x3130 }  -- 0x15DDD0 zeroes these
local PADS          = 0x0063AC20    -- port 0's joypad object
local PAD_A         = 2             -- its analog A byte
local MESSAGES      = 0x004E6E20    -- the message manager
local MESSAGE_TYPE  = 0x6D4         -- the type it shows (-1: none)
local MESSAGE_TIMER = 0x6F0         -- a repeat call of that type sets it back to 10
local PROMPT_TEXT   = 391           -- "=": the A button icon alone (140 is "= The Portal")
local PROMPT_TYPE   = 4
local TEXT_PTRS     = 0x005B04A4    -- -> the game's text pointers (count at 0x5AC508)
local TEXT_COUNT    = 0x005AC508
local RAIDEN_TEXT   = 34            -- "Raiden:\nTutorial Message 13.", never shown: the rift's line goes in its slot
local RAIDEN_TYPE   = 5             -- the game's speaker lines ("Sub-Zero:\n..."), up for 300 frames
local RAIDEN_LINES  = {             -- cp1252, under 128 bytes (the slot)
    es = "Raiden:\nLa hechicer\xEDa de Shang Tsung\nrasga el tiempo. Se abren grietas.\n\xA1Prep\xE1rate para lo que venga!",
    en = "Raiden:\nShang Tsung's sorcery is tearing\nat time itself. Rifts are opening.\nBe ready for what comes through!",
}
local CAMERA_HOLD   = 0x00599534    -- u8, P1's: the respawn teleport clears it,
local CAMERA_CUT    = 0x004E640C    -- u8, P1's: sets this,
local CAMERA_BLEND  = 0x004E641C    -- f32, P1's: and raises this to 1/6
local GAME_MANAGER  = 0x005ACEBC
local CLEARED_SLOT  = 0x1C4 + 22    -- player 1's level slot 22: beaten rifts
local CLEARED_MARK  = 0xA0          -- bits 5-7 of that byte; bits 0-4: one per rift
local SLOTS         = 0x006322F8    -- memory slots: +0x10 count, +0x24 -> 20-byte rows; +0x08 blocks,
local SLOT_ROW      = 20            -- +0x1C -> block rows. Rows: +0x04 type; a slot's +0x08 first block;
local BLOCK_MEMORY  = 4             -- a block's +0x10 flags: 4 it has memory, 2 it is in use
local LOADED_TYPES  = 0x006CA69C    -- 6 words: the types that can spawn right now
local LOADED_COUNT  = 6
local ENTER_RADIUS  = 150           -- step this close to open the rift
local ARM_RADIUS    = 400           -- and come from at least this far away
local SETTLE        = 60            -- frames after the reload before the boss loads
local WAIT_LOAD     = 1800          -- frames to wait for the reload or a load
local WAIT_BOSS     = 300           -- frames for a started boss to appear, then the next boss
local SPAWN_LIFT    = 64            -- spawn this far above the spot (y grows downward)
local FALL_DEPTH    = 1500          -- a boss this far below its drop point, for FALL_FRAMES in a row,
local FALL_FRAMES   = 180           -- fell out of the map (a leap or a lower floor is shorter, or nearer)
local MAX_LIFTS     = 5             -- times a fallen boss is put back on the rift's spot
local APPROACH      = 1500          -- map 132: the boss drops once P1 is this close to its spot (a guess to tune)
local PROMPT_RADIUS = 250           -- the A prompt shows this close to a prompt rift's portal
local PROMPT_EVERY  = 30            -- frames between messagetext calls while it doesn't show
local ARRIVE_LIFT   = 16            -- P1 lands from this far above the arrival spot
local PULL_MAX      = 120           -- frames the pull-in may take before the warp (the Portals load ~95 after)
local STREAM_REST   = 90            -- frames after a load before the next stream or the drop
local TRAIL_EVERY   = 10            -- frames between P1 positions kept while a rift is armed
local TRAIL_SIZE    = 48
local WAVES_CLEARED = 0x006C0168    -- 20 records of 12 bytes: u16 group, u32 alive, u8 cleared at +8
local WAVE_RECORDS  = 20
local RAIDEN_FRAMES = 240           -- the rush comes this long after Raiden's line
local EXTRA_GAP     = 45            -- frames between a boss's extras (after the boss)
local RUSH_GAP      = 20            -- frames between the rush's spawns
local BUILD_EVERY   = 6             -- entries written per frame (29 writes each; 256 per callback)
-- A group record's header (+0x00..+0x17), as the spawn-file loader (0xCFC80)
-- writes it and the group start (0x1D1B80) hands it to the wave's controller:
-- +0x04 s16 (controller +0xB8) 16, +0x08 (controller +0xBE) 4, +0x0C flags 0,
-- +0x10/+0x12/+0x14 -1 (unset), the values 1,082 of the game's groups use.
-- An unused group is all zeros, which leaves its enemies passive: they only
-- strike back with their counter (QA 2026-11-01, every rift spawn).
local GROUP_HEADER  = { 0, 0x10, 4, 0, 0xFFFFFFFF, 0xFFFF }
-- where a group's entries drop around the rift's spot (x, z)
local RING          = { { 0, 0 }, { 150, 0 }, { -150, 0 }, { 0, 150 }, { 0, -150 }, { 110, 110 },
                        { -110, -110 }, { 110, -110 }, { -110, 110 }, { 220, 0 }, { -220, 0 }, { 0, 220 } }

-- map, its descriptor, the entry the reload uses, the rift's spot, the boss's
-- spot, and the bosses to try in order; bit = its bit in the save's byte;
-- approach = how close P1 must come to the boss's spot before it drops;
-- prompt = the text of the A prompt that opens it (instead of stepping in);
-- wall = a point in the portal's wall, which the pull-in turns P1 by;
-- arrive = where P1 is moved when it opens (after the reload if there is
-- one), facing = P1's facing there; pull_facing = P1's facing while pulled
-- in; extras = the boss's company ({ kind, count }s); raiden = Raiden's line
-- first; rush = a wave instead of a boss: that many enemies of the types the
-- map has loaded, each with copies - 1 clones; pack = bosses that drop
-- together (over when all are down); finale = the boss after the rush or
-- the pack; borrow = the only map types whose slots a stream may take;
-- drop_back = drop on P1's trail that far from the portal;
-- after_waves/after_need = the prompt waits for that many of those vanilla
-- waves to be cleared
local RIFTS = {
    { map = 110, desc = 0x004FF2E8, entry = 1, bit = 0,  -- Wu Shi's co-op arena
      portal = { -7337.944, -1076.305, 841.819 },   -- in the hollow tree
      spot = { -4049.003, -1088.373, -258.222 },    -- mid-arena, facing the tree
      bosses = { OROCHI }, extras = { { kind = BURNING_MONK, count = 5 }, { kind = PRIEST, count = 3 } } },
    { map = 132, desc = 0x004FF5C8, reload = false, bit = 1, approach = APPROACH, prompt = PROMPT_TEXT,
      portal = { 92509.586, -1139.231, -19890.369 }, -- at the purple wall portal (Mileena's arena)
      wall = { 92909.586, -1139.231, -19890.369 },   -- the arena's east wall, behind the portal
      arrive = { 63824.207, -1200.248, -20076.363 }, facing = -800.937,  -- the shrine deck
      spot = { 87946.750, -1139.231, -19956.053 },   -- in her arena, 4,560 from the portal
      bosses = { MILEENA, JOHNNY_CAGE, OROCHI }, extras = { { kind = TARKATAN, count = 4 } } },
    { map = 102, desc = 0x004FEE98, entry = 1, bit = 2, prompt = PROMPT_TEXT,  -- Goro's Lair, the bell arena
      portal = { 6666.973, -190.785, -5098.718 },   -- past the bells (read live 2026-11-01)
      wall = { 6666.973, -190.785, -5498.718 },     -- no portal there: a point to turn by (0.10.0's +z side pulled P1 into the arena)
      arrive = { 6666.973, -190.785, -5098.718 }, facing = -585.0,  -- back to the spot after the reload
      spot = { 6666.973, -190.785, -5098.718 },
      raiden = true, rush = 3, copies = 3, finale = GORO },  -- Goro's Lair, and no Goro? not on our watch
    { map = 199, desc = 0x00501790, reload = false, bit = 3, prompt = PROMPT_TEXT,  -- the co-op area (map 199)
      portal = { -15246.421, -1466.247, -872.126 },  -- past its vanilla rush (read live 2026-11-01)
      wall = { -15246.421, -1466.247, -1272.126 }, pull_facing = 935.0,  -- pulled in facing as read
      arrive = { -15246.421, -1466.247, -872.126 }, facing = 935.0,
      spot = { -15246.421, -1466.247, -872.126 }, drop_back = 450,  -- he drops in front of the chair
      after_waves = { 15, 16, 17, 18, 19, 20, 21, 22 }, after_need = 5,  -- its rush (18, 20 never came solo)
      bosses = { KINTARO, OROCHI }, extras = { { kind = PRIEST, count = 3 } },   -- the priests are the area's own
      borrow = { [TARKATAN] = true } },             -- never the priests' slot (both crashes followed its swap)
}

-- The rift's spawn entry: a plain map-104 entry read live (group 4, 2026-10-31)
-- with the boss's type. Spawning it (0x1D1D40) reads +0x18..+0x20 as integer
-- coordinates: world coordinates when the group was started with entity
-- index -1 (as the callspawn command 0x1D2710 does), an offset from that
-- entity otherwise when +0x58 is 1.
local ENTRY_TEMPLATE = {
    OROCHI, NONE, NONE, 0x0B, NONE, NONE, 0, 0, 0xFFFFFC18, NONE,
    0, NONE, 0, 0, 0, 0, 4, 2, 0, 0, 0, 0, 1, NONE, NONE, NONE, NONE, 0x3E8, 0,
}

callgate.target(MODELSTREAM)
callgate.target(START_GROUP)
callgate.target(SET_POSITION)
callgate.target(MESSAGETEXT)
callgate.target(REACTION)
callgate.target(UNLOAD)

-- idle, armed, reloading, pulling, warping, arrived, streaming, dropping, fighting, done
local state = "idle"
local rift = nil         -- the RIFTS row in use
local boss_index = 1     -- which of rift.bosses is being tried
local boss_entity = nil  -- the boss's entity while it is up
local boss_actor = nil   -- and its actor
local boss_down = false  -- the game set the boss's health to 0
local made_killable = false  -- the rift cleared the boss's "can't die" flag
local prompting = false  -- P1 is in front of a prompt rift's portal: A opens it
local prompted = nil     -- frame of the last messagetext call there
local pressed = false    -- A was pressed fresh while prompting
local a_down = false     -- port 0's A as last seen
local swallow = false    -- A is held since it was swallowed: keep it from the game
local pulled = false     -- the pull-in reaction is seen playing
local placed = false     -- P1 is at the rift's arrival spot
local want = {}          -- the types the drop needs loaded: the boss first, then the extras
local streaming = nil    -- the type being streamed in
local build = nil        -- the group being written: { group, kinds, next }
local rush = nil         -- the rush once dropped: { kinds, count, spawned, seen }
local forced_slot = nil  -- the slot the next stream must use (the finale's)
local restore = {}       -- the finale's unloaded slots: { slot, kind } to stream back
local verdict_after = nil  -- the finale's verdict, given once the map's types are back
local finale_on = false  -- the finale's boss is the one being fought
local streamed_in = {}   -- the types the rift streamed in (a pack's are made killable)
local rest_until = nil   -- frame the next stream (or the drop) may come
local lifts = 0          -- times the boss was put back after a fall
local below_since = nil  -- frame the boss went FALL_DEPTH below its drop point
local trail, trail_next = {}, 1  -- P1's recent positions while a rift is armed
local seen = nil         -- the boss as last seen: { hp, max, d }
local frames, mark = 0, 0
local notes = {}
local report_text = nil  -- the TIMERIFT line, written on the next frame

local function note(text)
    notes[#notes + 1] = text
end

local function enter(next_state)
    state = next_state
    mark = frames
end

local function boss()
    return rift.bosses[boss_index]
end

local function distance(x, y, z, spot)
    local dx, dy, dz = x - spot[1], y - spot[2], z - spot[3]
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function distance_to(spot)
    return distance(game.read_f32(PLAYER + 0x80), game.read_f32(PLAYER + 0x84), game.read_f32(PLAYER + 0x88), spot)
end

local function rift_of(map)
    for _, r in ipairs(RIFTS) do
        if r.map == map then
            return r
        end
    end
    return nil
end

local function signed(v)
    return v >= 0x80000000 and v - 0x100000000 or v
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

local function in_use(entity)
    local flags = game.read_u32(ENTITY_FLAGS)
    return game.read_u16(flags + (entity - PLAYER) // ENTITY_STRIDE * 2) ~= 0
end

-- An entity's health and maximum (nil when it has no actor).
local function health(entity)
    local actor = game.read_u32(entity + ACTOR)
    if actor < 0x10000 or actor % 4 ~= 0 then
        return nil
    end
    return signed(game.read_u32(actor + ACTOR_HP)), signed(game.read_u32(actor + ACTOR_MAX_HP))
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

local function group_base(group)
    return MANAGER + group * GROUP_STRIDE
end

-- The types the map's enabled spawn groups author (the rift's own excluded).
local function authored()
    local kinds = {}
    for group = 0, GROUP_LIMIT - 1 do
        local base = group_base(group)
        local count = game.read_u16(base + COUNT_OFFSET)
        if game.read_u8(base + ENABLED_OFFSET) ~= 0 and count <= ENTRY_SLOTS
                and game.read_u32(base + RIFT_MARK_OFFSET) ~= RIFT_MARK then
            for slot = 0, count - 1 do
                kinds[game.read_u32(base + ENTRY_BASE + slot * ENTRY_STRIDE)] = true
            end
        end
    end
    return kinds
end

-- A slot a type may take: the last one whose type has no living actor and
-- isn't one the rift needs (`keep`), preferring one that no enabled spawn
-- group still authors.
local function free_slot(keep)
    local rows, wanted = game.read_u32(SLOTS + 0x24), authored()
    local fallback = nil
    for i = game.read_u32(SLOTS + 0x10) - 1, 0, -1 do
        local kind = game.read_u32(rows + i * SLOT_ROW + 4)
        if not keep[kind] and (kind == NONE or not alive_of(kind))
                and (rift.borrow == nil or kind == NONE or rift.borrow[kind] or streamed_in[kind]) then
            if kind == NONE or not wanted[kind] then
                return i
            end
            fallback = fallback or i
        end
    end
    return fallback
end

-- The regular fighters the map has loaded right now, in order.
local function loaded_enemies()
    local kinds = {}
    for i = 0, LOADED_COUNT - 1 do
        local kind = game.read_u32(LOADED_TYPES + i * 4)
        if RUSH_KINDS[kind] then
            kinds[#kinds + 1] = kind
        end
    end
    return kinds
end

-- The highest spawn group the map doesn't author.
local function empty_group()
    for group = GROUP_LIMIT - 1, 0, -1 do
        if game.read_u16(group_base(group) + COUNT_OFFSET) == 0 then
            return group
        end
    end
    return nil
end

-- Empties the rift's group if it is still marked as the rift's.
local function release_group(group)
    local base = group_base(group)
    if game.read_u32(base + RIFT_MARK_OFFSET) == RIFT_MARK then
        game.write_u32(base + RIFT_MARK_OFFSET, 0)
        game.write_u8(base + ENABLED_OFFSET, 0)
        game.write_u16(base + COUNT_OFFSET, 0)
    end
end

local function cleared_addr()
    local m = game.read_u32(GAME_MANAGER)
    if m < 0x10000 or m % 4 ~= 0 then
        return nil
    end
    return m + CLEARED_SLOT
end

local function cleared(r)
    local addr = cleared_addr()
    if addr == nil then
        return false
    end
    local b = game.read_u8(addr)
    return b & 0xE0 == CLEARED_MARK and b & (1 << r.bit) ~= 0
end

-- The rift is over: its group is emptied (only while it still carries the
-- mark, so a new map that loaded its own group there keeps it), a beaten rift
-- is remembered in the save, and a QA build reports on the next frame.
local function finish(verdict, map)
    if rift.group then
        release_group(rift.group)
        rift.group = nil
    end
    if verdict == "BEATEN" and ONCE_PER_SAVE then
        local addr = cleared_addr()
        if addr then
            local b = game.read_u8(addr)
            if b & 0xE0 ~= CLEARED_MARK then b = CLEARED_MARK end
            game.write_u8(addr, b | (1 << rift.bit))
        end
    end
    if QA then
        report_text = "TIMERIFT 0.12.0 " .. verdict .. " | " .. table.concat(notes, " ")
    end
    notes = {}
    boss_index, boss_entity, boss_actor, boss_down, seen = 1, nil, nil, false, nil
    made_killable, placed, want, streaming, build, rush = false, false, {}, nil, nil, nil
    forced_slot, restore, verdict_after, finale_on, streamed_in = nil, {}, nil, false, {}
    rest_until, trail, trail_next, rift.drop, lifts, below_since = nil, {}, 1, nil, 0, nil
    if rift.finale then
        rift.bosses = nil                    -- the finale's boss list was set for the fight only
    end
    enter("done")
end

-- A slot whose type the rift replaces, to stream back when the rift is
-- over: only on a map with its own spawn groups and only a type one of them
-- still authors (a map without them holds the last map's groups, switched
-- off). run = part of the finale's run of blocks (the unload step's).
local function remember(slot, kind, run)
    for _, r in ipairs(restore) do
        if r.slot == slot then
            r.run = r.run or run
            return
        end
    end
    if kind ~= NONE and (run or (game.read_u32(rift.desc + DESC_SPAWN_FILE) ~= NONE and authored()[kind])) then
        restore[#restore + 1] = { slot = slot, kind = kind, run = run }
    end
end

-- A verdict that waits for the restore, if there is one.
local function conclude(verdict, map)
    if #restore > 0 then
        verdict_after = verdict
        enter("restoring")
    else
        finish(verdict, map)
    end
end

local function failed(name)
    return function(eax)
        if eax == nil then
            note(name .. "=BAD")
            finish("CHECK", game.read_u32(CURRENT_MAP))
        end
    end
end

local function timed_out(what, limit, map)
    if frames - mark > (limit or WAIT_LOAD) then
        note(what .. "=never")
        finish("CHECK", map)
        return true
    end
    return false
end

-- Whether a prompt rift may open: its vanilla waves cleared (enough of
-- them), no group running and nobody but the players up.
local function waves_done()
    local need, done = rift.after_need or #rift.after_waves, 0
    for i = 0, WAVE_RECORDS - 1 do
        local record = WAVES_CLEARED + i * 12
        local group = game.read_u16(record)
        for _, wave in ipairs(rift.after_waves) do
            if group == wave and game.read_u8(record + 8) ~= 0 then
                done = done + 1
            end
        end
    end
    if done < need or game.read_u8(MANAGER + ST_ACTIVE) ~= 0 then
        return false
    end
    local flags = game.read_u32(ENTITY_FLAGS)
    for i = 2, ENTITY_COUNT - 1 do
        if game.read_u16(flags + i * 2) ~= 0 then
            return false
        end
    end
    return true
end

-- P1's trail while the rift is armed: a position every TRAIL_EVERY frames.
local function track()
    if frames % TRAIL_EVERY == 0 then
        trail[trail_next] = { game.read_f32(PLAYER + 0x80), game.read_f32(PLAYER + 0x84), game.read_f32(PLAYER + 0x88) }
        trail_next = trail_next % TRAIL_SIZE + 1
    end
end

-- The last trail point at least drop_back from the portal: floor P1 just
-- crossed on the way in (nil: none, the rift's spot is used).
local function trail_drop()
    for k = 1, TRAIL_SIZE do
        local point = trail[(trail_next - 1 - k) % TRAIL_SIZE + 1]
        if point and distance(point[1], point[2], point[3], rift.portal) >= rift.drop_back then
            return point
        end
    end
    return nil
end

-- In front of a prompt rift's portal: the game's own portal prompt. One
-- messagetext call shows it; while a type-4 message shows, a repeat call
-- only sets its timer back to 10, so the rift does just that.
local function show_prompt()
    if game.read_u32(MESSAGES + MESSAGE_TYPE) == PROMPT_TYPE then
        game.write_u32(MESSAGES + MESSAGE_TIMER, 10)
    elseif prompted == nil or frames - prompted >= PROMPT_EVERY then
        prompted = frames
        callgate.call(MESSAGETEXT, {
            args = { callgate.block{ 0, 11, callgate.block{ rift.prompt, PROMPT_TYPE, 0, 0, 0, 0, 0, 0, 0, 0, 0 } }, 0, 0 } })
    end
end

-- Move P1 to the rift's arrival spot as the game's respawn teleport does
-- (0x1F390): set-position, no momentum, a camera cut, and a facing.
local function warp()
    enter("warping")
    local a = rift.arrive
    callgate.call(SET_POSITION, {
        ecx = PLAYER,
        args = { callgate.block{ f32_bits(a[1]), f32_bits(a[2] - ARRIVE_LIFT), f32_bits(a[3]), 0 } },
        done = function(eax)
            if eax == nil then
                note("warp=BAD")
                finish("CHECK", rift.map)
                return
            end
            for _, off in ipairs(MOMENTUM) do
                game.write_u32(PLAYER + off, 0)
            end
            game.write_f32(PLAYER + 0x3190, 1.0)
            game.write_f32(PLAYER + 0x3150, 1.0)
            game.write_f32(PLAYER + FACING, rift.facing)
            game.write_u8(CAMERA_HOLD, 0)
            game.write_u8(CAMERA_CUT, 1)
            if game.read_f32(CAMERA_BLEND) < 1 / 6 then
                game.write_f32(CAMERA_BLEND, 1 / 6)
            end
            note(string.format("warp@+%d(d=%.0f)", frames - mark, distance_to(a)))
            placed = true
            enter("arrived")
        end })
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

-- Raiden's line about the rifts: written over the unused "Raiden: Tutorial
-- Message 13." in the game's language (Spanish, else English), only where
-- that string's slot has the room (the strings sit in 128-byte slots: the
-- rest of it must be zeros up to the next string), then shown as one of the
-- game's speaker lines. Without the room the rush just comes.
local function tell()
    enter("telling")
    local list = game.read_u32(TEXT_PTRS)
    if list < 0x10000 or game.read_u32(TEXT_COUNT) <= RAIDEN_TEXT + 1 then
        note("raiden=none")
        return
    end
    local p, after = game.read_u32(list + RAIDEN_TEXT * 4), game.read_u32(list + (RAIDEN_TEXT + 1) * 4)
    local bytes = (spanish() and RAIDEN_LINES.es or RAIDEN_LINES.en) .. "\0"
    local room, words = after - p, (#bytes + 3) // 4
    if p % 4 ~= 0 or room < words * 4 or room > 0x200 then
        note("raiden=noroom")
        return
    end
    local len = 0
    while len < room and game.read_u8(p + len) ~= 0 do
        len = len + 1
    end
    for k = len, room - 1 do
        if game.read_u8(p + k) ~= 0 then
            note("raiden=noroom")
            return
        end
    end
    for k = 0, words * 4 - 1, 4 do
        local word = 0
        for j = 0, 3 do
            word = word | (k + j < #bytes and bytes:byte(k + j + 1) or 0) << (8 * j)
        end
        game.write_u32(p + k, word)
    end
    callgate.call(MESSAGETEXT, {
        args = { callgate.block{ 0, 11, callgate.block{ RAIDEN_TEXT, RAIDEN_TYPE, 0, 0, 0, 0, 0, 0, 0, 0, 0 } }, 0, 0 } })
    note("raiden@+0")
end

-- The pull-in the game's portals play before their load: the reaction
-- command on P1 with the Portals' rec_portal arguments, turned by the wall.
local function pull()
    enter("pulling")
    pulled = false
    local w = rift.wall
    callgate.call(REACTION, {
        args = { callgate.block{ 0, 16, callgate.block{ PULL_ANIM, 0, PULL_ANIM, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } },
                 callgate.block{ CHAR_TARGET, 0, 0, 0, 0 },     -- "char" 0: P1
                 callgate.block{ 0, f32_bits(w[1]), f32_bits(w[2]), f32_bits(w[3]) } },
        done = function(eax)
            if eax == nil then
                note("pull=BAD")
                finish("CHECK", rift.map)
            elseif rift.pull_facing then
                game.write_f32(PLAYER + FACING, rift.pull_facing)   -- pulled in the way P1 faced when the spot was read
            end
        end })
end

local function reload()
    enter("reloading")
    game.write_u8(PLAYER + PLAYER_LOADING, 1)
    game.write_u8(PLAYER + ENTITY_STRIDE + PLAYER_LOADING, 1)
    game.write_u32(LOAD_ARG3, 0)
    game.write_u32(LOAD_MAP, rift.map)
    game.write_u32(LOAD_ENTRY, rift.entry)
    game.write_u8(LOAD_REQUEST, 1)
end

local function open_rift()
    note(string.format("map%d open@%d(d=%.0f)", rift.map, frames, distance_to(rift.portal)))
    prompting = false
    if rift.drop_back then
        rift.drop = trail_drop()
        if rift.drop then
            note(string.format("drop(%.0f,%.0f,%.0f)", rift.drop[1], rift.drop[2], rift.drop[3]))
        end
    end
    if rift.wall then
        pull()                                   -- the portal pulls P1 in, then sends them on
    elseif rift.reload == false then
        enter("arrived")                         -- the boss drops without a reload
    else
        reload()
    end
end

-- The types the drop needs loaded: the boss being tried (or the pack), then
-- its extras' types (a rush uses what the map has loaded; the finale comes
-- alone). stream_step brings in the ones missing, one at a time.
local function load_types()
    enter("streaming")
    want, streaming = {}, nil
    if rift.bosses then
        want[1] = boss()
    end
    if not finale_on then
        for _, kind in ipairs(rift.pack or {}) do
            want[#want + 1] = kind
        end
        for _, e in ipairs(rift.extras or {}) do
            want[#want + 1] = e.kind
        end
    end
end

-- Make the highest empty group the rift's: the boss and its extras, or the
-- rush, around the rift's spot. On a map without its own spawn file the
-- manager still holds the last map's groups: switch those off first. The
-- entries are written over the next frames (build_step).
local function drop(map)
    enter("building")
    if game.read_u32(rift.desc + DESC_SPAWN_FILE) == NONE then
        for group = 0, GROUP_LIMIT - 1 do
            game.write_u8(group_base(group) + ENABLED_OFFSET, 0)
        end
    end
    local group = rift.group or empty_group()
    if group == nil then
        note("group=none")
        finish("CHECK", map)
        return
    end
    rift.group = group
    local kinds = {}
    if rift.bosses or rift.pack then
        if rift.bosses then
            kinds[1] = boss()
        else
            for _, kind in ipairs(rift.pack) do
                if is_loaded(kind) then
                    kinds[#kinds + 1] = kind
                end
            end
        end
        for _, e in ipairs(not finale_on and rift.extras or {}) do
            if is_loaded(e.kind) then
                for _ = 1, e.count do
                    kinds[#kinds + 1] = e.kind
                end
            end
        end
        if not rift.bosses then
            -- the pack: fought like a rush, over when none of its types is left
            local seen_kind, pack = {}, {}
            for _, kind in ipairs(kinds) do
                if not seen_kind[kind] then
                    seen_kind[kind], pack[#pack + 1] = true, kind
                end
            end
            rush = { kinds = pack, count = #kinds, spawned = 0, seen = false, pack = true }
        end
    else
        -- the rush: rift.rush enemies of the loaded types in turn, then
        -- their clones in the same order
        local loaded = loaded_enemies()
        if #loaded == 0 then
            note("rush=none")
            finish("CHECK", map)
            return
        end
        for i = 1, rift.rush * rift.copies do
            kinds[i] = loaded[((i - 1) % rift.rush) % #loaded + 1]
        end
        rush = { kinds = loaded, count = #kinds, spawned = 0, seen = false }
    end
    build = { group = group, kinds = kinds, next = 1 }
end

-- Writes up to BUILD_EVERY of the group's entries, then marks the group as
-- the rift's and starts it.
local function build_step(map)
    local base = group_base(build.group)
    local last = math.min(#build.kinds, build.next + BUILD_EVERY - 1)
    for i = build.next, last do
        local entry = base + ENTRY_BASE + (i - 1) * ENTRY_STRIDE
        local ring = RING[(i - 1) % #RING + 1]
        local spot = rift.drop or rift.spot
        local delay = (i - 1) * (rift.bosses and EXTRA_GAP or RUSH_GAP)
        for k, word in ipairs(ENTRY_TEMPLATE) do
            if k == 1 then
                word = build.kinds[i]
            elseif k == 7 then
                word = math.floor(spot[1] + ring[1] + 0.5) & 0xFFFFFFFF             -- +0x18
            elseif k == 8 then
                word = math.floor(spot[2] - SPAWN_LIFT) & 0xFFFFFFFF                -- +0x1C
            elseif k == 9 then
                word = math.floor(spot[3] + ring[2] + 0.5) & 0xFFFFFFFF             -- +0x20
            elseif k == 23 then
                word = word & 0xFFFF | delay << 16                                  -- +0x5A
            end
            game.write_u32(entry + (k - 1) * 4, word)
        end
    end
    build.next = last + 1
    if build.next <= #build.kinds then
        return
    end
    note(string.format("group%d:%d", build.group, #build.kinds))
    for k, word in ipairs(GROUP_HEADER) do
        game.write_u32(base + (k - 1) * 4, word)
    end
    game.write_u32(base + RIFT_MARK_OFFSET, RIFT_MARK)
    game.write_u16(base + COUNT_OFFSET, #build.kinds)
    game.write_u8(base + ENABLED_OFFSET, 1)
    build = nil
    enter("dropping")
    callgate.call(START_GROUP, {
        ecx = MANAGER,
        args = { rift.group, NONE, 0 },        -- as callspawn: no reference entity
        done = failed("start") })
end

-- Streams in the next type the drop needs, into a slot holding none of them;
-- drops once they are all loaded. No slot: the boss can't come (CHECK), an
-- extra is left out.
local function stream_step(map)
    if streaming then
        if not is_loaded(streaming) then
            timed_out("stream", nil, map)
            return
        end
        note("loaded@+" .. (frames - mark))
        streaming, rest_until = nil, frames + STREAM_REST
    end
    if rest_until and frames < rest_until then
        return                                   -- the game streams one character at a time
    end
    rest_until = nil
    for i, kind in ipairs(want) do
        if not is_loaded(kind) then
            local keep = {}
            for _, k in ipairs(want) do
                keep[k] = true
            end
            local slot = forced_slot or free_slot(keep)
            forced_slot = nil
            if slot == nil and i == 1 then
                note("slot=none")
                finish("CHECK", map)
            elseif slot == nil then
                note(kind .. ":noslot")
                table.remove(want, i)
            else
                local was = game.read_u32(game.read_u32(SLOTS + 0x24) + slot * SLOT_ROW + 4)
                note(string.format("%d:slot%d(was%X)", kind, slot, was))
                remember(slot, was)
                streaming, streamed_in[kind] = kind, true
                mark = frames
                callgate.call(MODELSTREAM, {
                    args = { callgate.block{ 0, 2, callgate.block{ slot, kind } }, 0, 0 },
                    done = failed("stream") })
            end
            return
        end
    end
    drop(map)
end

-- In the fight: BEATEN once the boss's health reaches 0, FAILED once P1's
-- does. A boss that disappears with health left, or falls out of the map,
-- is noted and the next boss drops (the last one ends the rift as VANISHED).
local function fight(map)
    local hp = health(PLAYER)
    if hp and hp <= 0 then
        note("p1 down@+" .. (frames - mark))
        conclude("FAILED", map)
        return
    end
    local entity = boss_entity
    local up = in_use(entity) and game.read_u16(entity + ENTITY_TYPE) == boss()
    local bhp, bmax = nil, nil
    if up then
        bhp, bmax = health(entity)
        if boss_actor and boss_actor >= 0x80000000 and boss_actor < 0x84000000 and bhp and bhp > 0
                and game.read_u8(boss_actor + CAN_KILL) == 0 then
            game.write_u8(boss_actor + CAN_KILL, 1)   -- out of its scripted fight, the boss can die
            if not made_killable then
                note("killable@+" .. (frames - mark))
                made_killable = true
            end
        end
    end
    if boss_down or (bhp and bhp <= 0) then
        note(string.format("%d beaten@+%d", boss(), frames - mark))
        conclude("BEATEN", map)
        return
    end
    if up then
        local x, y, z = game.read_f32(entity + 0x80), game.read_f32(entity + 0x84), game.read_f32(entity + 0x88)
        seen = { hp = bhp, max = bmax, d = distance_to({ x, y, z }) }
        if y <= (rift.drop or rift.spot)[2] + FALL_DEPTH then
            below_since = nil
            return
        end
        below_since = below_since or frames
        if frames - below_since < FALL_FRAMES then
            return                               -- a leap, a knock-down, a lower floor: not yet a fall
        end
        below_since = nil
        if lifts < MAX_LIFTS then
            -- fell out of the map: back on the rift's spot, as P1's warp
            lifts = lifts + 1
            note(string.format("%d lift%d@+%d(y=%.0f)", boss(), lifts, frames - mark, y))
            local s = rift.spot
            callgate.call(SET_POSITION, {
                ecx = entity,
                args = { callgate.block{ f32_bits(s[1]), f32_bits(s[2] - SPAWN_LIFT), f32_bits(s[3]), 0 } },
                done = function(eax)
                    if eax ~= nil then
                        for _, off in ipairs(MOMENTUM) do
                            game.write_u32(entity + off, 0)
                        end
                    end
                end })
            return
        end
        note(boss() .. " fell")
    end
    local s = seen or {}
    note(string.format("%d gone@+%d(hp=%s/%s d=%.0f)", boss(), frames - mark,
        tostring(s.hp), tostring(s.max), s.d or -1))
    if boss_index < #rift.bosses then
        boss_index, boss_entity, boss_actor, seen, lifts, below_since = boss_index + 1, nil, nil, nil, 0, nil
        load_types()                         -- the next boss
    else
        conclude("VANISHED", map)
    end
end

-- The finale's run of memory blocks 0..need-1: each has memory, and is free
-- or held by a type the rift unloads (`held`).
local function finale_room(need, held)
    local blocks = game.read_u32(SLOTS + 0x1C)
    if game.read_u32(SLOTS + 0x08) < need then
        return false
    end
    for b = 0, need - 1 do
        local flags = game.read_u32(blocks + b * SLOT_ROW + 0x10)
        if flags & BLOCK_MEMORY == 0 or (flags & 2 ~= 0 and not held[game.read_u32(blocks + b * SLOT_ROW + 4)]) then
            return false
        end
    end
    return true
end

-- Goro after the rush (rift.finale). He needs two memory blocks in a row,
-- and Goro's Lair gives memory to just two, each holding one of its enemy
-- types. With nobody of the rush's types left, the rift unloads the slots
-- holding blocks 1 and on (0x17B280, what a stream does before it loads)
-- and streams him into slot 0: that stream unloads slot 0 and takes the run
-- of free blocks from block 0. A stream into a named slot never checks that
-- run, so the rift does, before and after the unloads; without the room he
-- doesn't come. When his fight is over and his body gone, the map's own
-- types are streamed back into their slots (restore).
local function finale_start(map)
    local kind = rift.finale
    local need = game.read_u32(CHAR_TABLE + kind * CHAR_ROW + 4)
    rift.bosses, boss_index, rush, finale_on = { kind }, 1, nil, true
    streamed_in[kind] = true
    if need <= 1 then
        load_types()                             -- one block: streamed in like any boss
        return
    end
    local rows, held, first = game.read_u32(SLOTS + 0x24), {}, nil
    for s = 0, game.read_u32(SLOTS + 0x10) - 1 do
        local t = game.read_u32(rows + s * SLOT_ROW + 4)
        if t ~= NONE and game.read_u32(rows + s * SLOT_ROW + 8) < need then
            remember(s, t, true)
            held[t] = true
            first = first or s
        end
    end
    if first ~= 0 or not finale_room(need, held) then
        note(kind .. "=noroom")
        conclude("BEATEN", map)                  -- the rush or the pack was beaten
        return
    end
    enter("unloading")
end

-- Unloads the finale's slots past slot 0, one a frame, then streams the
-- boss into slot 0 once the run of blocks is still there.
local function unload_step(map)
    local rows, held = game.read_u32(SLOTS + 0x24), {}
    for _, r in ipairs(restore) do
        held[r.kind] = r.run or held[r.kind]
        if r.run and r.slot > 0 and game.read_u32(rows + r.slot * SLOT_ROW + 4) == r.kind then
            note(string.format("unload%d(%d)", r.slot, r.kind))
            callgate.call(UNLOAD, { args = { r.slot }, done = failed("unload") })
            return
        end
    end
    if not finale_room(game.read_u32(CHAR_TABLE + rift.finale * CHAR_ROW + 4), held) then
        note(rift.finale .. "=noroom")
        conclude("BEATEN", map)                  -- the rush was beaten; put the map's types back
        return
    end
    load_types()
    forced_slot = 0
end

-- After the finale: once the boss's body is gone (a model can't go while
-- it is used), the unloaded types stream back into their slots, one at a
-- time, then the verdict.
local function restore_step(map)
    if streaming then
        if not is_loaded(streaming) then
            timed_out("restore", nil, map)
            return
        end
        streaming, rest_until = nil, frames + STREAM_REST
    end
    if rest_until and frames < rest_until then
        return
    end
    rest_until = nil
    local r = restore[1]
    if r == nil then
        note("restored@+" .. (frames - mark))
        finish(verdict_after, map)
        return
    end
    -- never under a living (or dying) actor: wait for its type to be gone,
    -- else leave that slot as it is
    local current = game.read_u32(game.read_u32(SLOTS + 0x24) + r.slot * SLOT_ROW + 4)
    if current ~= NONE and entity_of(current) then
        if frames - mark >= WAIT_LOAD then
            note(string.format("kept%d(%d)", r.slot, current))
            table.remove(restore, 1)
        end
        return
    end
    table.remove(restore, 1)
    if not is_loaded(r.kind) then
        streaming = r.kind
        callgate.call(MODELSTREAM, {
            args = { callgate.block{ 0, 2, callgate.block{ r.slot, r.kind } }, 0, 0 },
            done = failed("restore") })
    end
end

-- The rush: BEATEN once its wave has run (the manager clears a group when
-- all its enemies spawned and died, or another group takes over) and no
-- enemy of its types is left; FAILED once P1 goes down.
local function rush_fight(map)
    local hp = health(PLAYER)
    if hp and hp <= 0 then
        note("p1 down@+" .. (frames - mark))
        conclude("FAILED", map)
        return
    end
    if rush.pack then
        -- out of their scripted fights, the pack's bosses can die
        local flags = game.read_u32(ENTITY_FLAGS)
        for i = 2, ENTITY_COUNT - 1 do
            local entity = PLAYER + i * ENTITY_STRIDE
            local actor = game.read_u32(entity + ACTOR)
            if game.read_u16(flags + i * 2) ~= 0 and actor >= 0x80000000 and actor < 0x84000000 and actor % 4 == 0
                    and streamed_in[game.read_u16(entity + ENTITY_TYPE)] and signed(game.read_u32(actor + ACTOR_HP)) > 0
                    and game.read_u8(actor + CAN_KILL) == 0 then
                game.write_u8(actor + CAN_KILL, 1)
                if not made_killable then
                    note("killable@+" .. (frames - mark))
                    made_killable = true
                end
            end
        end
    end
    if game.read_u8(MANAGER + ST_ACTIVE) ~= 0 and game.read_u16(MANAGER + ST_GROUP) == rift.group then
        rush.seen = true
        rush.spawned = math.max(rush.spawned, game.read_u16(MANAGER + ST_SPAWNED))
        return
    end
    if not rush.seen then
        timed_out("rush", WAIT_BOSS, map)
        return
    end
    for _, kind in ipairs(rush.kinds) do
        if alive_of(kind) then
            return
        end
    end
    note(string.format("%s%d/%d@+%d", rush.pack and "pack" or "rush", rush.spawned, rush.count, frames - mark))
    if rift.finale then
        finale_start(map)                        -- and now the finale's boss
    else
        conclude("BEATEN", map)
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
            if state == "idle" or state == "armed" or state == "done" then
                local r = rift_of(map)
                if r ~= rift then
                    rift, state = r, "idle"
                end
                prompting = false
                if rift == nil or state == "done" or (ONCE_PER_SAVE and cleared(rift)) then
                    return
                end
                local d = distance_to(rift.portal)
                if state == "idle" and d > ARM_RADIUS then
                    state = "armed"
                elseif state == "armed" and rift.prompt then
                    if rift.drop_back then
                        track()
                    end
                    prompting = d < PROMPT_RADIUS and (rift.after_waves == nil or waves_done())
                    if prompting and pressed then
                        open_rift()
                    elseif prompting then
                        show_prompt()
                    else
                        prompted = nil
                    end
                    pressed = false
                elseif state == "armed" and d < ENTER_RADIUS then
                    open_rift()
                end
            elseif state == "reloading" then
                timed_out("reload", nil, map)
            elseif map ~= rift.map then
                note("left@" .. state)
                finish("LEFT", map)
            elseif state == "pulling" then
                -- warp once the pull-in is over (or never started)
                local s = game.read_u32(PLAYER + STATE)
                if s == REACTING then
                    pulled = true
                end
                if (pulled and s ~= REACTING) or (not pulled and frames - mark > 2) or frames - mark >= PULL_MAX then
                    note(string.format("pull@+%d(%s,s=%X)", frames - mark, pulled and "seen" or "none", s))
                    if rift.reload == false then
                        warp()
                    else
                        reload()                         -- the arena reloads, then P1 is put back
                    end
                end
            elseif state == "arrived" then
                local d = distance_to(rift.spot)
                if frames - mark < SETTLE then
                    return
                elseif rift.arrive and not placed then
                    warp()                               -- after the reload: back to the rift's spot
                elseif d <= (rift.approach or math.huge) then
                    if rift.arrive then
                        note(string.format("near@+%d(d=%.0f,a=%.0f)", frames - mark, d, distance_to(rift.arrive)))
                    elseif rift.approach then
                        note(string.format("near@+%d(d=%.0f)", frames - mark, d))
                    end
                    if rift.raiden then
                        tell()
                    else
                        load_types()
                    end
                end
            elseif state == "telling" then
                if frames - mark >= RAIDEN_FRAMES then
                    load_types()
                end
            elseif state == "streaming" then
                stream_step(map)
            elseif state == "building" then
                build_step(map)
            elseif state == "dropping" then
                local entity = rift.bosses and entity_of(boss())
                if not rift.bosses then
                    enter("fighting")
                elseif entity then
                    note(string.format("boss%d@+%d(%.0f,%.0f,%.0f)", boss(), frames - mark,
                        game.read_f32(entity + 0x80), game.read_f32(entity + 0x84), game.read_f32(entity + 0x88)))
                    boss_entity, boss_actor, boss_down = entity, game.read_u32(entity + ACTOR), false
                    enter("fighting")
                elseif frames - mark > WAIT_BOSS and boss_index < #rift.bosses then
                    note(boss() .. "=never")
                    boss_index = boss_index + 1          -- fall back to the next boss
                    load_types()
                else
                    timed_out("boss", WAIT_BOSS, map)
                end
            elseif state == "fighting" and rush then
                rush_fight(map)
            elseif state == "fighting" then
                fight(map)
            elseif state == "unloading" then
                unload_step(map)
            elseif state == "restoring" then
                restore_step(map)
            end
        end,
    },
    {
        -- the game sets the boss's health: to 0 when it is beaten
        address = SET_HEALTH,
        before = function(ctx)
            if boss_actor and ctx.ecx == boss_actor and signed(game.read_u32(ctx.esp + 4)) <= 0 then
                boss_down = true
            end
        end,
    },
    {
        -- port 0's pad, before the game reads it: in front of a prompt rift's
        -- portal A opens the rift instead of jumping, and stays swallowed
        -- until it is let go
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
    {
        address = PRELOAD,
        before = function(ctx)
            if state ~= "reloading" or game.read_u32(ctx.esp + 4) ~= rift.desc then
                return
            end
            -- the arena's preload: the reload is under way (nothing is changed)
            note("reload=ok")
            enter("arrived")
        end,
    },
}

return callgate.hooks(hooks)
