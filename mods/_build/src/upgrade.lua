-- Extended Upgrades 0.15.0: XP shop, Health, Stamina, fatality meter, weapons, EX moves and fatality inputs.
--
-- Turns pause-menu Moves categories into the XP shop. Nothing new is added
-- to the menu; existing rows get new text, costs and behaviour, and
-- everything sold comes on top of what the game itself gives:
--   * Basic Moves -> Upgrades: Basic Attacks -> Health (+1-4: 1, 2, 4 and 8
--     game health-upgrade steps, above the game's own four) and Air Attacks
--     -> Stamina (+1-4: everything that spends the blue bar costs less, as if
--     it held 125, 150, 200 and 300%). Running Attacks -> Items: refill the
--     fatality meter by 1, 2 or 3 levels at once, as often as there is room.
--   * Skill -> Fatality meter (+1-4): every meter gain is 125, 150, 200 or
--     300% of the game's, and in fatality mode a full meter lasts like 3.5,
--     4, 4.5 or 5 orbs (shared, like Health).
--   * Platform -> Weapons: a row per weapon type (seven), in every area,
--     each its own price; buying one brings it to where you stand, as often
--     as you like. One the area never placed is spawned by the game's own
--     weaponspawn command (experimental; see Weapon spawns below).
--     The abilities behind Skill's and Platform's vanilla rows are untouched.
--   * Fatalities: a row not discovered yet (its input shows as ???) can be
--     bought, which reveals the input. Every fatality works without being
--     discovered; this sells the knowledge, not the move.
--   * Specials: every move row can be bought twice. The first purchase is
--     the game's (the move, on R2); once that is owned, the row is for sale
--     again as its EX ("Special 2 EX"), in any order. L2 + the move's input (no
--     R2) does an EX move as its EX version, for extra stamina (the blue bar;
--     the red orbs stay the fatality meter). L2 + an input without its EX
--     stays vanilla (block), and L2 + R2 + a button stays free.
-- Team keeps its vanilla rows. See analysis/xp_shop/REPORT.md
-- (menu, weapons) and analysis/ex_specials/REPORT.md (EX).
-- Analysis: analysis/xp_shop/REPORT.md (sections 7, 9 and 11).
--
-- How the menu works (default.xbe):
--   * The menu is data: the "M&PD" tree (GAMEDATA.WAD record 713), copied into
--     memory by MPDatabase::ImportData. [0x4EFA88] holds the copy; roots at
--     [blob+0x10] (count blob+0x0C). Node: +0x04 type (2 category, 1 group,
--     0 row), +0x0C child count, +0x10 parent, +0x14 children, +0x18 name and
--     +0x1C description (text indices), +0x28 XP cost, +0x2C owned.
--     Skill (464) is a type-1 category whose leaves hang directly off it, so
--     a bought leaf's index is its category position.
--   * Opening the menu runs SyncOwned (thunk 0x13A12), which recomputes +0x2C
--     for Specials, Combos, Platform and Fatalities. Our categories are never
--     synced, so after it runs we set their text, costs and owned flags
--     ourselves.
--   * Only Specials and Combos can be bought. The purchase dispatcher asks
--     CanPurchase (thunk 0x116CC) and IsCombo (thunk 0x15EDE); we answer yes for
--     our rows, so the game's Purchase_combo (thunk 0x13954) runs its own yes/no
--     dialog, deducts the row's cost from XP and marks it owned.
--   * Purchase_combo also calls Upgrade(player, 13 + row) (thunk 0x1647E), which
--     would unlock a combo for free. We save that level byte and restore it.
--   * Shop levels live in level slot 27 (no fixed-slot readers): player 0's
--     byte holds Health (bits 0-2, shared like the game's own count), each
--     player's byte holds their Stamina (bits 3-5). Bit 7 marks the byte as
--     ours; 0.3.0 kept a weapon count there, which reads as nothing bought.
--   * Health: the game's max health is the table at 0x50B544, read as
--     [min(ups, 4) * 5 + mode] (ups = manager +0xE0, mode +0x88: 0 solo,
--     1 co-op) into manager +0x94 (int; +0x8C is current health as a float,
--     not a max: it follows damage, so we leave it alone), then each
--     player actor (+0x200 of entity 0x5D1AB8 + p * 0x3238) gets +0x370 =
--     +0x94 times the area's level +0x90 (1-15), halved per character in co-op,
--     and is healed to it (0xD4760, 0xD4790 on map load and after the
--     healthupgrade command). We add table steps (the 3 -> 4 difference) on
--     top: HP_STEPS by shop level. Whenever the game has rewritten those values
--     (it only ever writes vanilla ones), the stamina tick adds ours back and
--     heals by what max health gained.
--   * Stamina: one 0x24-byte record per player at 0x4E6598 (count 0x4E65E0).
--     It drains two ways. Consume(level) subtracts the record's cost[level - 1]
--     (+0x00..+0x0C: 10, 20, 100, 3); CanAfford compares the same cost. And
--     while the player is in a sustained state (the long jump, for one), the
--     Tick (0x76300, through 0x75F20) takes 1.0 off the bar every 5th frame
--     without a cost. The 100 cap is an immediate in Add, Tick and the HUD, so
--     a bigger bar is cheaper costs: cost * 100 / BAR[level], and the
--     sustained drain gets the same share refunded after each Tick. Init
--     (0x76690) copies the record from a per-character template, so the tick
--     re-scales whenever the costs are no longer the ones we wrote. (0.4/0.5
--     also drew the bar taller; the HUD frame over it has a fixed window, so
--     the extra height only showed below the frame.)
--   * Meter (0.2/0.3 sold its levels early): the story's setfatalitylevel
--     (thunk 0x1116D) adds without a cap, and the HUD has layouts for levels
--     1-3 only, so we still clamp it at 3 for saves that bought a level.
--   * Meter fills (0.13.0): the meter is the f32 at manager +0x4954 + p *
--     0x50 (get/set 0xC9710 / 0xC9740), fed by AddMeter (0x84980), which
--     keeps it within levels * level size: the levels at +0x4978 (0-3, the
--     story raises them), the size a third of the HUD meter's +4 (entity
--     +0x2B6C -> +0x54 -> +4: 1200.0, so 400 a level). A level is full at
--     value >= size (0x82F00 counts them; 0x3D030 lets fatality mode start),
--     compared with the unrounded size. Fill row j adds j levels, clamped to
--     the levels held, and is for sale only while j more can light up. In
--     fatality mode (0x3BAA0) the HUD (0x84A50) rewrites the meter from the
--     mode's timer every frame, so nothing is sold then.
--   * Fatality meter upgrades (0.14.0, longer lasting since 0.15.0): every gain goes through AddMeter
--     (0x84980, thunk 0x16AC8; thiscall on the HUD meter, entity and f32
--     amount on the stack), from the hit code (0x177E30 via 0x84BE0: a
--     per-move byte, +0x66 of the move's info) and blocks; spends (0x84CE0,
--     fatalities, team attacks) pass a negative amount. A before hook grows a
--     player's positive amounts. Fatality mode's time is the record of
--     the player at [0x58D6A8] + 0x318 + p * 8 (+0 entity, +4 left: 1000 is a
--     full meter, the HUD shows the meter as left * 1.2 in the mode); the
--     drain 0x3B1F0 (thunk 0x126E4, once a frame per record from the
--     manager's update 0x3D9D0) takes one off while the entity is in the
--     mode and ends it at 0. An after hook gives back 1 - LAST of each step,
--     carried as a fraction. Skill's four leaves hang off the category
--     like Fatalities'; the level is shared, in the bits Health leaves free
--     in player 1's shop byte (0-2; that byte's 3-5 are player 1's Stamina).
--   * Fatalities: SyncOwned marks a Fatalities row owned (input shown) when
--     its name text index is in the discovered list at 0x4DF5DC (count
--     [0x4DFC1C], 400 slots), which the fatality handler appends to when one
--     is performed. Nothing in gameplay reads it, and it is saved with the
--     game (save offset 0x5C: the entries after the performed counter). After
--     SyncOwned we price the rows it left unowned; buying one appends its
--     name, so the next sync and every later load show it revealed.
--   * Weapons (Platform's seven leaves since 0.14.0; 0.7-0.13 sold only the
--     area's own in Running Attacks): the weapon manager at 0x5A3AC0 (built at boot by 0xBE070)
--     holds one object per weapon type in a table at +8 (0x27C each, count
--     +0x56FC). A map does not create weapons, it places these: a weapon is
--     in the area when it has a scene node (+0x174 != -1) or a physics body
--     (+0x124). While nobody holds it (+0x10C), the per-weapon update
--     (0xBD620 -> 0xBEF10) counts +0x230 down and at 0 respawns it (0xBECC0)
--     at its home: the position at +0x234 when +0x244 is set. That is where a
--     thrown or broken weapon flies back to. A purchase sets home to the
--     buyer's feet, refills durability (+0x26C = +0x268) and sets the
--     countdown to 1, for the weapon and the pair half at +0x17C: on the next
--     unpaused frame the game itself brings it over, with its sparkle. Types
--     the area never placed get no update, so only those in the area are
--     sold (they are also the only ones whose models are loaded). Thrown, a
--     summoned weapon flies back to where it was bought; broken, it goes
--     back to where the level put it: every respawn passes the thunk
--     0x12BEE (ecx = the weapon), where we put its original home back
--     first when its durability is spent (a pair's first half decides).
--     New weapons in an area are announced with the game's "you can acquire
--     new abilities" popup: opening the Moves list (0x9C590, thunk 0x1425F)
--     shows it modally (0x9BE60) while byte 0x4EE890 is set and something
--     can be bought; any purchase clears that byte. Around that call we set
--     it and point the popup's text (407) at ours, once per area (map
--     [0x505970]) per session, when one of its weapons can be afforded,
--     then put both back.
--   * Weapon spawns (0.14.0, experimental, needs a live test): a type the
--     area never placed has no node or body, so no update and no respawn.
--     The level scripts' weaponspawn command (exec 0xBED40, thunk 0x11C8F,
--     stdcall (args, 0, spot), its object 0x4F34FC in ecx) places one: it
--     looks the weapon up by its name hash (+8, 0xBE7E0), copies a matrix from
--     [object + 4] + 0x18 to the home matrix +0x1F0, sets the home +0x234,
--     assigns a PmeWeapons slot (0x5A38CC, 0xBA550: a free one or one it may
--     release; the slot loads the PME model and textures, load ids 0x113-
--     0x122 and 0x258-0x25B, into its memory group), respawns it and wakes
--     its body. We call it through the call gate (callgate_lib.lua) with
--     [object + 4] pointing at the weapon's own matrix (written upright at
--     the spot), then put the pointer back; a pair's second half is spawned
--     after the first. A spawn that hasn't shown up ARMS.WAIT frames after its
--     call gives its XP back and isn't sold again in that area this session.
--   * EX (analysis/ex_specials/REPORT.md): a special's variant is picked by the
--     move system's condition evaluator 0x1CD780(entity, id), which keeps the
--     condition id in ebp and asks GetLevel (thunk 0x111C2) for its slot.
--     Ids 0x3174-0x3182 are slots 0, 1 and 2, five each: level >= 1 to 4 and
--     == 5 (the top), so a button's move j is picked by the condition on
--     level j (the level its row j buys). While L2 (left trigger: the analog
--     byte at pad state +0xC, 0x63ABD4 + p * 0x16; in the joypad object
--     0x63AC20 + p * 0xE4 the analog bytes from +2 are A B X Y Black White LT
--     RT) is held without R2 and an attack button with an EX bought is
--     pressed (flag level slots 19-21: a bit per move, marked with bit 7; no
--     menu row buys 18-22, combos are 13-17. 0.11.3 kept them in 23-25,
--     which the game reads: 0x1DA00 lets a co-op player start a team attack
--     when any of 23-26 is non-zero, and move conditions 0x318E-0x3191 test
--     them; those bytes are moved back to 19-21 and cleared),
--     the pad-to-action translator 0x129480 (eax = joypad object) gets R2
--     instead of L2, and keeps getting it until L2 is let go, so the game does
--     the special and its whole input chain (a tier-4 fireball is R2 + X, X,
--     X; between the presses plain L2 would be block). Pressing it marks an
--     EX: the evaluator, and only it (by return address), then gets level j
--     for the condition on a move j whose EX is bought (and owned on R2) and
--     0 for any other of those ids. The move filter 0x77810 (registration and
--     each move start) asks too, through SlotLevel (thunk 0x12FD1: player and
--     the move's slot flag 0x10000000 << slot, levels read straight from the
--     manager, not through GetLevel), one call site per tier (>= 1 to 4, ==
--     5); it gets the same answers. So L2 does exactly the EX moves; its
--     stamina extra comes off when the special spends its own (script
--     command 0x1F1 -> wrapper thunk 0x1406B, once per move), scaled like
--     every cost. Slot 3 (^, with its hidden ==6 variant) is left alone.
--   * EX cancels: the game drops a special pressed while another plays, so
--     during an EX move a fresh L2 press of another EX button is held back
--     (the game sees it released) until the move's last event (its last hit,
--     or the fireball leaving the hand) has played. Then the move is ended on
--     the spot (anim frame 0x7FFF: the anim tick ends it and runs its end
--     handlers) and the press is played back as R2 + the button, so the next
--     EX starts on the next frame. The same button again is the move's own
--     input chain (X, X, X) and is left to the game.
--   * EX power (analysis/ex_power/REPORT.md). Damage: every hit reaches its
--     victim as entity message 164 (dispatcher 0x180D30(entity, msg, arg1):
--     TakeDamage(entity's actor, -arg1)), with no attacker; a hit on anyone
--     but the players while a player's EX move plays, or shortly after its
--     press (a fireball lands late), gets EXP.DAMAGE / 2 times the final damage
--     in TakeDamage (0x153E20). In single player any damage to an enemy while
--     the EX move plays counts too; in co-op only message-164 hits do. No
--     impact pause (0.11.3 had one again; the user wants none).
--     Recovery: the anim tick 0x1C4A60 advances an entity
--     by 2 frames a tick while its speed byte +0x263A is 32 (reset at every
--     anim start), but the move's events (hits, spawns) fire only on their
--     exact frame (0x1CEBE0), so the EX move speeds up only after its last
--     event: the recovery. Events: anim bank 0x6C03E0, list by anim at
--     [[+0xC] + anim * 4], 16 bytes each (frame s16, type s16; type 0 ends;
--     frame -2: at the end).
--   * An EX row is bought through the combo purchase like the shop's other
--     rows: the game's own special purchase would raise the R2 tier, so for
--     a row on sale as its EX we answer IsSpecial (thunk 0x12B71) no.
--   * Text: the strings are a pointer array at [0x5B04A4] (count [0x5AC508]).
--     We write our strings over unused "(PH)" move-list placeholders, only where
--     they fit, and point our rows at them. Every value we change is remembered,
--     and put back if a reloaded text table no longer has room for ours.
--   * Two scripts (0.12.0): build.py makes upgrade.lua (PART "shop": the menu,
--     Health, Stamina, the fatality meter, weapons, fatalities) and upgrade_ex.lua (PART "ex": the
--     L2 remap, the move answers, EX stamina, damage, recovery and cancels)
--     from this file, each with callgate_lib.lua in front (only the shop
--     script returns the gate's hooks). A script that fails is switched off
--     whole, so an EX error can no longer take Health and Stamina with it.
--     They share nothing but game memory (the flag and shop bytes in the level row).
local GAME_MANAGER  = 0x005ACEBC
local GAME_MODE     = 0x88          -- 0 single player, 1 co-op, 2 versus
local XP            = 0x4940        -- XP of player p at +0x4940 + p * 0x50
local PLAYER_STRIDE = 0x50
local LEVELS        = 0x1C4         -- level byte of player p, slot s: +0x1C4 + p * 0x1C + s
local HEALTH_UPS    = 0xE0          -- the game's health-upgrade count, 0-4
local METER = {                     -- the fatality meter (one table: the game's Lua allows 200 locals)
    VALUE = 0x4954,                 -- player p's meter, f32 at +0x4954 + p * 0x50 (0xC9710 / 0xC9740)
    LEVEL = 0x4978,                 -- the levels it holds (the story's 0-3), u32 at +0x4978 + p * 0x50
    MAX = 3,
    LEVELUP = 0x0001116D,           -- the setfatalitylevel script command
    STATS = 0x2B6C, HUD = 0x54,     -- entity -> stats -> its HUD meter, whose +4 is the size of
    BAR = 4,                        -- all three levels (1200.0); a level is a third of it, as
    THIRD = 0.3333333432674408,     -- the game multiplies it (the f32 1/3 at 0x49F0F4)
    MODES = 0x0058D6A8,             -- fatality mode, as the HUD asks it (0x3BAA0): the record at
    MODE_REC = 0x310,               -- [0x58D6A8] + 0x310 + (p + 1) * 8 names an entity whose
    MODE_STATE = 0x23C,             -- state +0x23C is one of its character's two mode states
    CHAR_ID = 0x1DFE,               -- (0x5999FC / 0x599A00 + id * 0x6C, id = the s16 at +0x1DFE)
    MODE_IDS = 0x005999FC,
    MODE_STRIDE = 0x6C,
    TEXT = { 816, 817, 818 },       -- (PH) texts: refill row j's name and description
    DESC = { 618, 619, 819 },
    PRICES = { 3000, 5500, 7500 },  -- +1, +2, +3 levels (placeholders until the economy pass)
    ADD = 0x00016AC8,               -- AddMeter (0x84980), thiscall: ecx = the HUD meter, (entity, f32)
    GAIN = { [0] = 100, 125, 150, 200, 300 },   -- the meter fills at this % by Fatality level
    DRAIN = 0x000126E4,             -- fatality mode's drain (0x3B1F0), fastcall: ecx = a record
    RECORDS = 0x318,                -- [0x58D6A8] + 0x318 + i * 8 = { entity, left } (players first;
                                    -- left 1000 = a full meter), one off left per call in the mode
    LAST = { [0] = 1, 6 / 7, 3 / 4, 2 / 3, 3 / 5 },  -- the drain by level: a full meter lasts like
    LONGER = { [0] = 0, 17, 33, 50, 67 },            -- 3, 3.5, 4, 4.5 or 5 orbs (% longer, as shown)
    carry = {},                     -- [player + 1] = the drain's share still to give back
    drained = nil,                  -- { record, left, player } around one drain call
}
local MAX_HP        = 0x94          -- base max health (int)
local HP_LEVEL      = 0x90          -- the area's level multiplier, 1-15
local HP_TABLE      = 0x0050B544    -- base max health, [min(ups, 4) * 5 + mode]
local HP_MAX_UPS    = 4
local HP_LEVEL_MAX  = 15
local HP_TEXT_STEP  = 100           -- the solo table step, as the row text shows it
local ENTITY        = 0x005D1AB8    -- player entity p at + p * 0x3238
local ENTITY_STRIDE = 0x3238
local ACTOR         = 0x200         -- the entity's actor
local ACTOR_HP      = 0x368         -- current health (int)
local ACTOR_MAX_HP  = 0x370         -- max health (int)
local STAMINA       = 0x004E6598    -- stamina record of player p at + p * 0x24
local STAMINA_STRIDE = 0x24
local STAMINA_COUNT = 0x004E65E0
local COSTS         = 4             -- cost by cost level 1-4 at +0x00..+0x0C
local STAMINA_NOW   = 0x10          -- current stamina (f32, 0-100)
local SHOP_SLOT     = 27            -- shop levels (see above)
local SHOP_MARK     = 0x80
local SHOP_ROWS     = 4
local HP_STEPS      = { [0] = 0, 1, 2, 4, 8 }           -- health table steps by shop level
local BAR           = { [0] = 100, 125, 150, 200, 300 } -- the bar each Stamina level plays as (%)
local ABILITY_BASE  = 0xE4          -- per-ability timers (float) and records hang off here
local MPD           = 0x004EFA88    -- MPDatabase: [+0] tree copy
local MENU_PLAYER   = 0x004EFA60    -- player (0 or 1) whose pause menu is open
local SELECTED      = 0x004EFB38    -- the highlighted menu node
local TEXT_PTRS     = 0x005B04A4
local TEXT_COUNT    = 0x005AC508

local SYNC_OWNED    = 0x00013A12
local CAN_PURCHASE  = 0x000116CC
-- CanPurchase's callers, by return address. Two more ask it about the
-- highlighted row while you hover it: the description panel (0x9CE58) and
-- the preview video (0x9D3A0) show the row's text and video on a yes.
local ASKED_TO_BUY  = 0x0009E5D9    -- the purchase dispatcher (A on a row)
local ASKED_FOR_ANY = 0x0009BC0E    -- "anything to buy under here?" (colours the category)
local ASKED_FOR_VIDEO = 0x0009D3A0  -- the preview video: a weapon row has none of its own
local IS_COMBO      = 0x00015EDE
local BUY_COMBO     = 0x00013954
local UPGRADE       = 0x0001647E
local STAMINA_TICK  = 0x00016965    -- Tick(record), fastcall: once per record per frame

local BASIC_TEXT    = 402           -- "Basic Moves" category
local FATALITY_TEXT = 400           -- "Fatalities" category: its leaves hang directly off it
local FATALITY_COST = 5000          -- per revealed input (placeholder until the economy pass)
local FATALITY_HINT = 616           -- (PH) text that becomes the Fatalities category's description
local FAT_LIST      = 0x004DF5DC    -- discovered fatalities: name text indices, saved with the game
local FAT_COUNT     = 0x004DFC1C
local FAT_MAX       = 400
local RUNNING_TEXT  = 405           -- "Running Attacks", the third Basic Moves group
local ITEMS_SLOT    = 2             -- its position in Basic Moves
local ITEMS_TEXT    = 617           -- (PH) texts: the Items group's name and description
local ITEMS_DESC    = 683
local ARMS = {                      -- Platform becomes Weapons: a row per weapon type, in every area
    TEXT = 462,                     -- "Platform": its seven leaves hang directly off it
    NAME = 1047, DESC = 1051,       -- (PH) texts: the category's new name and description,
    ROWS = { 684, 693, 694, 696, 701, 702, 703 },   -- the rows' names (by TYPES)
    ROW_DESC = 697,                 -- and their shared description
    TYPES = { "shard", "shard1h", "sword", "kama01", "broadsword", "hooksword01", "axe" },
    PRICES = { 1500, 1750, 2000, 2250, 2500, 2750, 3000 },  -- per summon (placeholders until the economy pass)
    SPAWN = 0x00011C8F,             -- weaponspawn's exec (0xBED40), stdcall (args, 0, spot), ecx = the
    CMD = 0x004F34FC,               -- command object: the exec copies its [+4] + 0x18 matrix to the weapon
    MATRIX = 0x1F0,                 -- weapon: home matrix (three rotation rows, then the spot)
    WAIT = 300,                     -- frames a spawned weapon has to appear, or its XP comes back
    objects = {},                   -- [row] = its weapon object (the table is built once, at boot)
    failed = {},                    -- [map * 8 + row] = true: a spawn there never appeared
    pending = nil,                  -- { w, k, player, cost, at, map } until a spawn has appeared
}
local WEAPONS       = 0x005A3AC0    -- weapon manager: objects at +8, count at +0x56FC
local W_STRIDE      = 0x27C
local W_COUNT       = 0x56FC
local W_NAME        = 0x0C
local W_HOLDER      = 0x10C         -- character carrying it, 0 when free
local W_BODY        = 0x124         -- physics body, 0 when none
local W_MODEL       = 0x12C         -- -1 for the model-less pickup slots
local W_NODE        = 0x174         -- scene node it is placed at, -1 when none
local W_HALF        = 0x178         -- the second half of a pair
local W_NEXT        = 0x17C         -- a pair's second half
local W_COUNTDOWN   = 0x230         -- respawn countdown: at 0 the weapon goes home
local W_HOME        = 0x234         -- home position, used while W_HOME_ON is set
local W_HOME_ON     = 0x244
local W_DUR_MAX     = 0x268
local W_DUR         = 0x26C
local W_SEEN        = 0x220         -- position of the home matrix +0x1F0 (the last pickup spot)
local RESPAWN       = 0x00012BEE    -- thunk to the respawn 0xBECC0, fastcall: ecx = weapon
local MOVES_OPEN    = 0x0001425F    -- the Moves list opens (0x9C590), the popup inside it
local POPUP_FLAG    = 0x004EE890    -- byte: show the "new abilities" popup (purchases clear it)
local POPUP_TEXT    = 407           -- that popup's text
local MAP           = 0x00505970    -- the current map (area) number
local SPECIALS_TEXT = 461           -- "Specials": a group per button (menu order), a row per move
local IS_SPECIAL    = 0x00012B71    -- IsSpecial(node): the dispatcher's "buy as a special?"
local EX_NAMES      = { 713, 714, 716, 717, 793 }   -- (PH) texts: "<move j's name> EX"
local EX_FLAG       = 19            -- EX moves: level slots 19-21, one per game slot, a bit per move
local EX_PRICES     = { 5000, 10000, 15000, 20000, 25000 }  -- the EX of move 1-5 (placeholders)
local EX_LEAF_SLOT  = { 0, 1, 2 }   -- Specials group X Y B -> game slot (live: Y's moves test slot 1)
local EX_COST       = 50            -- extra stamina per EX special, before Stamina upgrades
local GET_LEVEL     = 0x000111C2    -- GetLevel(player, slot), cdecl -> eax
local EVAL_FROM     = 0x001CD780    -- the move system's condition evaluator: GetLevel
local EVAL_TO       = 0x001CE400    -- calls returning in here pick a special's variant
local EX_COND       = 0x3174        -- move conditions: c = id - EX_COND in 0-14 is slot c // 5,
local EX_CONDS      = 15            -- level c % 5 + 1
local SLOT_LEVEL    = 0x00012FD1    -- SlotLevel(player, flags): the level of a move's special, cdecl
local MOVE_TIER     = {             -- its calls in the move filter 0x77810: the tier each
    [0x00077B0C] = 0,               -- requires (0: the special at all, when entity
    [0x00077B3A] = 1,               -- +0x3215 is 1; 5: exactly, the top tier)
    [0x00077B69] = 2,
    [0x00077B98] = 3,
    [0x00077BC7] = 4,
    [0x00077BF6] = 5,
}
local SPEND         = 0x0001406B    -- a scripted move spends stamina: (player, cost level), cdecl
local PAD_MAP       = 0x00129480    -- one port's pad -> action bits; eax = its joypad object
local PADS          = 0x0063AC20    -- joypad object of port p at + p * 0xE4
local PAD_OBJ       = 0xE4
local J_LT, J_RT    = 8, 9          -- analog bytes in it: A B X Y Black White LT RT from +2
local LT_MIN        = 0xC0          -- trigger byte that counts as held
-- Attack button (its analog byte) -> the special's game slot. ^ (throw) is
-- left out: nobody uses it.
local EX_BUTTONS    = { { 4, 0 }, { 5, 1 }, { 3, 2 } }   -- X -> slot 0, Y -> 1, B -> 2
local DEMO          = 0x005143A5    -- 1 in the attract demo: GetLevel reports 1 there
local FRAME         = 0x005CE878    -- frame counter
local EX_WINDOW     = 60            -- frames between the variant pick and its stamina spend
local EXP = {                       -- EX power (one table: the game's Lua allows 200 locals)
    MSG = 0x00180D30,               -- an entity's message dispatcher (entity, msg, arg1, arg2), cdecl
    TAKE_DAMAGE = 0x00153E20,       -- thiscall: actor in ecx, final positive damage at esp+4
    HIT = 0xA4,                     -- msg 164: the entity takes -arg1 damage
    TICK = 0x001C4A60,              -- advances every entity's animation, once a frame
    FRAME = 0x1C, ANIM = 0x24,      -- entity: animation frame, anim id, state (6: in a move,
    STATE = 0x1E04, SPEED = 0x263A, -- recovery included), speed byte (0 normal, > 15: frames a tick * 16)
    BANK = 0x006C03E0,              -- anims: count; +4 lengths (16 bytes per [LENGTH_IX + anim * 4],
    LENGTH_IX = 0x006CA6C0,         -- length at +8); +8 anim data, +0xC event lists, by anim
    DAMAGE = 10,                    -- an EX hit does DAMAGE / 2 times the damage
    HIT_FRAMES = 90,                -- a press's hits count as EX this long (a fireball lands late)
    RECOVERY = 48,                  -- an EX move's recovery: 3 frames a tick
    CANCEL_WAIT = 45,               -- frames a cancel press is held back at most
    FORCE = 2,                      -- frames a played-back cancel press is held
    OLD_FLAG = 23,                  -- where 0.11.3 kept the EX flags (the game's slots)
}

local WEAPON_POPUP  = 698           -- (PH) text that takes our popup message
local POSITION      = 0x80          -- entity position: x, y, z floats
local WEAPON_SIDE   = 150.0         -- the weapon lands this far beside the buyer,
local WEAPON_FLOOR  = 57.0          -- this far below his position (on the floor)
local UPGRADE_TEXT  = 455           -- "Upgrade" in the loaded language tells us which it is
local PART          = "all"         -- "shop" or "ex" in the built scripts (build.py)

-- Text in the game's code page (cp1252). The "(PH)" placeholders we overwrite
-- are 45-62 bytes in the five built-in languages (English is the shortest).
-- health[3] takes the bonus health, stamina[3] the bar size and fatal[3]
-- the meter's fill rate, in percent; fatality is the Fatalities category's
-- description, items the Items group (name, description), meter its refill
-- rows (name, description for one level, for more; the game's own word for
-- the meter), fatal the Fatality meter category made of Skill (name, row,
-- row description, description), weapon the Weapons category made of
-- Platform (name, description, the rows' description, the popup message)
-- and weapons the row names by weapon object (45 bytes at most).
local LANGUAGES = {
    { tag = "Upgr", category = { "Upgrades", "Spend EXP on health and stamina." },
      health = { "Health", "Health +%d", "Max health +%d,\non top of the game's.",
                 "Extra health on top of the game's." },
      stamina = { "Stamina", "Stamina +%d", "Stamina %d%%.\nBlocks and specials\ncost less.",
                  "Blocks and specials cost less stamina." },
      fatality = "Buy a ??? fatality's\ninput with EXP.",
      items = { "Items", "Fatality meter refills." },
      meter = { "Meter refill +%d", "Fills %d more level of\nthe fatality meter.",
                "Fills %d more levels of\nthe fatality meter." },
      fatal = { "Fatality meter", "Meter +%d", "Fills at %d%% and\nlasts %d%% longer.",
                "The meter fills faster, lasts longer." },
      weapon = { "Weapons", "Summon a weapon to your side.", "Appears where you buy it.\nThrown, it returns.",
                 "Weapons for sale in\nthe Weapons menu." },
      weapons = { kama01 = "Kamas", sword = "Sword", broadsword = "Broadsword", axe = "Axe",
                  hooksword01 = "Hook swords", shard = "Shard", shard1h = "Short shard" } },
    { tag = "Mejo", category = { "Mejoras", "Gasta EXP en salud y energ\237a." },
      health = { "Salud", "Salud +%d", "Vida m\225xima +%d,\nadem\225s de la del juego.",
                 "Salud extra, adem\225s de la del juego." },
      stamina = { "Energ\237a", "Energ\237a +%d", "Energ\237a %d%%.\nBloquear y especiales\ncuestan menos.",
                  "Bloquear y especiales gastan menos." },
      fatality = "Compra la secuencia de\nun ??? con EXP.",
      items = { "Objetos", "Recargas del medidor de Fatality." },
      meter = { "Recarga de medidor +%d", "Llena %d nivel m\225s del\nmedidor de Fatality.",
                "Llena %d niveles m\225s del\nmedidor de Fatality." },
      fatal = { "Medidor de Fatality", "Medidor +%d", "Se llena al %d%% y\ndura un %d%% m\225s.",
                "El medidor se llena antes y dura m\225s." },
      weapon = { "Armas", "Invoca un arma a tu lado.", "Aparece donde la compras;\nlanzada, vuelve.",
                 "Armas a la venta en\nel men\250 Armas." },
      weapons = { kama01 = "Kamas", sword = "Espada", broadsword = "Mandoble", axe = "Hacha",
                  hooksword01 = "Espadas gancho", shard = "Fragmento", shard1h = "Fragmento corto" } },
    { tag = "Verb", category = { "Verbesserungen", "EXP f\252r Leben und Ausdauer ausgeben." },
      health = { "Leben", "Leben +%d", "Max. Leben +%d,\nzus\228tzlich zum Spiel.",
                 "Mehr Leben, zus\228tzlich zum Spiel." },
      stamina = { "Ausdauer", "Ausdauer +%d", "Ausdauer %d%%.\nBlock, Spezial\nkosten weniger.",
                  "Blocken und Spezial kosten weniger." },
      fatality = "Kaufe die Eingabe\neines ??? mit EXP.",
      items = { "Gegenst\228nde", "Fatality-Anzeige auff\252llen." },
      meter = { "Anzeige auff\252llen +%d", "F\252llt %d weitere Stufe\nder Fatality-Anzeige.",
                "F\252llt %d weitere Stufen\nder Fatality-Anzeige." },
      fatal = { "Fatality-Anzeige", "Anzeige +%d", "F\252llt sich zu %d%%,\nh\228lt %d%% l\228nger.",
                "Die Anzeige f\252llt sich schneller, h\228lt l\228nger." },
      weapon = { "Waffen", "Ruf eine Waffe zu dir.", "Erscheint am Kaufort,\nkehrt geworfen zur\252ck.",
                 "Waffen zu kaufen\nim Men\252 Waffen." },
      weapons = { kama01 = "Kamas", sword = "Schwert", broadsword = "Breitschwert", axe = "Axt",
                  hooksword01 = "Hakenschwerter", shard = "Splitter", shard1h = "Kurzer Splitter" } },
    { tag = "Pote", category = { "Potenziamenti", "Spendi EXP per salute ed energia." },
      health = { "Salute", "Salute +%d", "Salute max +%d,\noltre a quella del gioco.",
                 "Salute extra oltre a quella del gioco." },
      stamina = { "Energia", "Energia +%d", "Energia %d%%.\nParate e speciali\ncostano meno.",
                  "Parate e speciali costano meno." },
      fatality = "Compra la sequenza\ndi un ??? con EXP.",
      items = { "Oggetti", "Ricariche della barra fatality." },
      meter = { "Ricarica barra +%d", "Riempie %d livello in pi\249\ndella barra fatality.",
                "Riempie %d livelli in pi\249\ndella barra fatality." },
      fatal = { "Barra fatality", "Barra +%d", "Si riempie al %d%% e\ndura il %d%% in pi\249.",
                "La barra si riempie prima e dura di pi\249." },
      weapon = { "Armi", "Evoca un'arma accanto a te.", "Appare dove la compri;\nlanciata, torna l\236.",
                 "Armi in vendita\nnel men\249 Armi." },
      weapons = { kama01 = "Kama", sword = "Spada", broadsword = "Spadone", axe = "Ascia",
                  hooksword01 = "Spade uncinate", shard = "Frammento", shard1h = "Frammento corto" } },
    { tag = "Am\233l", category = { "Am\233liorations", "D\233pensez l'EXP en sant\233 et endurance." },
      health = { "Sant\233", "Sant\233 +%d", "Sant\233 max +%d,\nen plus de celle du jeu.",
                 "Sant\233 en plus de celle du jeu." },
      stamina = { "Endurance", "Endurance +%d", "Endurance %d%%.\nGarde, sp\233ciaux\nmoins chers.",
                  "Garde et sp\233ciaux co\251tent moins." },
      fatality = "Ach\232te la saisie\nd'un ??? avec l'EXP.",
      items = { "Objets", "Recharges de la jauge de fatality." },
      meter = { "Recharge de jauge +%d", "Remplit %d niveau de plus\nde la jauge de fatality.",
                "Remplit %d niveaux de plus\nde la jauge de fatality." },
      fatal = { "Jauge de fatality", "Jauge +%d", "Se remplit \224 %d%% et\ndure %d%% de plus.",
                "La jauge se remplit vite et dure plus." },
      weapon = { "Armes", "Invoque une arme pr\232s de toi.", "Appara\238t o\249 tu l'ach\232tes;\nlanc\233e, revient.",
                 "Armes \224 vendre dans\nle menu Armes." },
      weapons = { kama01 = "Kamas", sword = "\201p\233e", broadsword = "Claymore", axe = "Hache",
                  hooksword01 = "\201p\233es crochets", shard = "\201clat", shard1h = "\201clat court" } },
}

-- Each shop group takes over one Basic Moves group (source = its vanilla
-- name, slot = its position). Row k is owned once the shop level has reached
-- k and can be bought when it is k - 1; buying sets it to k.
local SHOP = {
    category = { text = 598, desc = 611 },
    groups = {
        { kind = "health", source = 403, slot = 0, text = 574, desc = 612,
          rows = { { cost = 5000,  name = 581, desc = 582 }, { cost = 10000, name = 583, desc = 584 },
                   { cost = 15000, name = 593, desc = 594 }, { cost = 20000, name = 596, desc = 597 } } },
        { kind = "stamina", source = 404, slot = 1, text = 599, desc = 613,
          rows = { { cost = 5000,  name = 601, desc = 602 }, { cost = 10000, name = 603, desc = 604 },
                   { cost = 15000, name = 718, desc = 719 }, { cost = 20000, name = 783, desc = 784 } } },
    },
    -- Skill becomes the Fatality meter's upgrades: its four leaves hang
    -- directly off the category, bought in order like the groups' rows
    fatal = { kind = "fatal", source = 464, text = 1020, desc = 1021,
              rows = { { cost = 5000,  name = 704, desc = 985 }, { cost = 10000, name = 711, desc = 986 },
                       { cost = 15000, name = 712, desc = 996 }, { cost = 20000, name = 794, desc = 801 } } },
}

local function plausible(p)
    if p < 0x10000 or p % 4 ~= 0 then
        return false
    end
    return p < 0x7FFE0000
        or (p >= 0x80000000 and p < 0x84000000)
        or (p >= 0xB0000000 and p < 0xC0000000)
        or (p >= 0xD0000000 and p < 0xE0000000)
        or (p >= 0xF0000000 and p < 0xF4000000)
end

local function manager()
    local m = game.read_u32(GAME_MANAGER)
    if not plausible(m) then return nil end
    if game.read_u32(m + GAME_MODE) == 2 then return nil end
    return m
end

local CHARACTER     = 0xCC          -- character id of player p at +0xCC + p * 4
local BUDGET        = 200           -- writes per callback (the runtime allows 256)

local ready = false             -- our strings are in place and rows retitled
local writes = 0                -- writes staged in this callback
local resume = false            -- a sync ran out of budget; finish it next callback
local pending = nil             -- { kind, store, k } while the game runs our purchase
local saved = nil               -- the level slot Upgrade is about to change
local asked = nil               -- node passed to CanPurchase / IsCombo
local asked_from = nil          -- CanPurchase's return address: which menu code asks
local tree = nil                -- the tree copy our changes were made to
local changed = {}              -- [address] = { was = vanilla value, now = ours }
local costs = {}                -- per player: { base = vanilla costs, now = ours, level }
local ticked = nil              -- { record, stamina before } around one Tick
local area = {}                 -- the weapon objects lying in the current area (for the popup)
local ex_rows = {}              -- [Specials row] = { k = button, j = move, sale = on sale as its EX }
local announced = {}            -- [map] = true once the popup announced its weapons (this session)
local popup = nil               -- { at, was, ours, flag } while our message is in the popup
local summoned = {}             -- [weapon] = { first, spot, home, on, seen }: its home before
                                -- we moved it to the purchase spot (spot), as raw words

-- Exact powers of two, so f32 <-> Lua number conversions don't drift.
local POW2 = {}
do
    local v = 1.0 for e = 0, 127 do POW2[e] = v v = v * 2.0 end
    v = 1.0 for e = 0, 150 do POW2[-e] = v v = v / 2.0 end
end

local function f32_to(u)
    local exp = (u >> 23) & 0xFF
    if exp == 0xFF then return nil end          -- inf/nan: never a stamina value
    local frac = u & 0x7FFFFF
    local x = exp == 0 and frac * POW2[-149] or (frac + 0x800000) * POW2[exp - 150]
    return u >> 31 ~= 0 and -x or x
end

-- (The game's Lua 5.4 has no math.frexp, so the exponent is found by hand.)
local function f32_from(x)
    if x ~= x then return 0x7FC00000 end        -- nan
    local sign = x < 0 and 1 or 0
    x = x < 0 and -x or x
    if x == 0 then return sign << 31 end
    if x >= POW2[127] * 2.0 then return sign << 31 | 0x7F800000 end
    local e = 0                                 -- 2^e <= x < 2^(e+1)
    while e < 127 and x >= POW2[e + 1] do e = e + 1 end
    while e > -149 and x < POW2[e] do e = e - 1 end
    if e < -126 then return sign << 31 | math.floor(x / POW2[-149] + 0.5) end
    local frac = math.floor((x / POW2[e] - 1.0) * 0x800000 + 0.5)
    if frac == 0x800000 then frac, e = 0, e + 1 end
    if e > 127 then return sign << 31 | 0x7F800000 end
    return sign << 31 | (e + 127) << 23 | frac
end

-- String at text index i, as an address (strings need not be aligned).
local function text_at(i)
    if i >= game.read_u32(TEXT_COUNT) then return nil end
    local list = game.read_u32(TEXT_PTRS)
    if not plausible(list) then return nil end
    local p = game.read_u32(list + i * 4)
    if not plausible(p - p % 4) then return nil end
    return p
end

-- The built-in language whose "Upgrade" word is loaded; English otherwise.
local function language()
    local p = text_at(UPGRADE_TEXT)
    if p ~= nil then
        for _, lang in ipairs(LANGUAGES) do
            local hit = true
            for k = 1, #lang.tag do
                if game.read_u8(p + k - 1) ~= lang.tag:byte(k) then hit = false break end
            end
            if hit then return lang end
        end
    end
    return LANGUAGES[1]
end

-- Puts s at text index i if it fits in the bytes already there: true when it
-- is in place, false when it can't fit, nil when this callback's budget is
-- spent. Written in whole words; the last word keeps the bytes after our NUL.
local function put_text(i, s)
    local p = text_at(i)
    if p == nil then return false end
    local same = game.read_u8(p + #s) == 0
    for k = 1, #s do
        local b = game.read_u8(p + k - 1)
        if b == 0 then return false end         -- too short for our string
        if b ~= s:byte(k) then same = false end
    end
    if same then return true end
    local bytes = s .. "\0"
    if writes + (#bytes + 3) // 4 > BUDGET then return nil end
    for k = 0, #bytes - 1, 4 do
        local word = 0
        for j = 0, 3 do
            local b = k + j < #bytes and bytes:byte(k + j + 1) or game.read_u8(p + k + j)
            word = word | b << (8 * j)
        end
        game.write_u32(p + k, word)
        writes = writes + 1
    end
    return true
end

-- What row k's description shows: the health it adds in total, the size
-- the stamina bar now plays as, or how fast the fatality meter fills.
local function row_figure(kind, k)
    if kind == "health" then return HP_STEPS[k] * HP_TEXT_STEP end
    if kind == "fatal" then return METER.GAIN[k] end
    return BAR[k]
end

-- Whether a weapon object is in the current area: placed at a node or lying
-- as a physics body (only those get the update that respawns them).
local function in_area(w)
    return game.read_u32(w + W_NODE) ~= 0xFFFFFFFF or game.read_u32(w + W_BODY) ~= 0
end

-- One pass over the weapon table: the weapon types in the current area
-- (first halves with a model), and each Weapons row's object by name.
local function scan_weapons()
    local list = {}
    local n = game.read_u32(WEAPONS + W_COUNT)
    if n > 35 then return list end
    for i = 0, n - 1 do
        local w = WEAPONS + 8 + i * W_STRIDE
        if game.read_u8(w + W_HALF) == 0 and game.read_u32(w + W_MODEL) ~= 0xFFFFFFFF then
            local name = {}
            for c = 0, 15 do
                local b = game.read_u8(w + W_NAME + c)
                if b == 0 then break end
                name[#name + 1] = string.char(b)
            end
            name = table.concat(name)
            for k, t in ipairs(ARMS.TYPES) do
                if t == name then ARMS.objects[k] = w end
            end
            if in_area(w) then list[#list + 1] = w end
        end
    end
    return list
end

-- Our strings, in the loaded language: true, false if any of them can't
-- fit, nil when the budget ran out first. Checked on every menu open, so a
-- reloaded text table is caught. The order is fixed, so a resumed sync picks
-- up where the last one stopped.
local function place_text()
    local lang = language()
    local all = { { SHOP.category.text, lang.category[1] }, { SHOP.category.desc, lang.category[2] } }
    for _, group in ipairs({ SHOP.groups[1], SHOP.groups[2], SHOP.fatal }) do
        local words = lang[group.kind]
        all[#all + 1] = { group.text, words[1] }
        all[#all + 1] = { group.desc, words[4] }
        for k, row in ipairs(group.rows) do
            all[#all + 1] = { row.name, string.format(words[2], k) }
            all[#all + 1] = { row.desc, string.format(words[3], row_figure(group.kind, k), METER.LONGER[k]) }
        end
    end
    all[#all + 1] = { FATALITY_HINT, lang.fatality }
    all[#all + 1] = { ITEMS_TEXT, lang.items[1] }
    all[#all + 1] = { ITEMS_DESC, lang.items[2] }
    for j = 1, #METER.PRICES do
        all[#all + 1] = { METER.TEXT[j], string.format(lang.meter[1], j) }
        all[#all + 1] = { METER.DESC[j], string.format(j == 1 and lang.meter[2] or lang.meter[3], j) }
    end
    local w = lang.weapon
    all[#all + 1] = { ARMS.NAME, w[1] }
    all[#all + 1] = { ARMS.DESC, w[2] }
    all[#all + 1] = { ARMS.ROW_DESC, w[3] }
    all[#all + 1] = { WEAPON_POPUP, w[4] }
    for k, t in ipairs(ARMS.TYPES) do
        all[#all + 1] = { ARMS.ROWS[k], lang.weapons[t] }
    end
    local result = true
    for _, t in ipairs(all) do
        local placed = put_text(t[1], t[2])
        if placed == false then return false end
        if placed == nil then result = nil end
    end
    return result
end

-- A tree field we change, remembering the vanilla value the first time.
-- False when this callback's budget is spent.
local function patch(addr, value)
    local now = game.read_u32(addr)
    if now ~= value and writes >= BUDGET then return false end
    if changed[addr] == nil then changed[addr] = { was = now } end
    changed[addr].now = value
    if now ~= value then
        game.write_u32(addr, value)
        writes = writes + 1
    end
    return true
end

-- A field's own (game) value: what it held before we patched it, unless the
-- game has written it since.
local function vanilla(addr)
    local c, now = changed[addr], game.read_u32(addr)
    if c and now == c.now then return c.was end
    return now
end

-- Puts every changed field back where it still holds our value.
local function unpatch()
    for addr, c in pairs(changed) do
        if game.read_u32(addr) == c.now then game.write_u32(addr, c.was) end
    end
    changed = {}
end

-- The shop byte a level lives in: Health is shared (player 0's byte, bits
-- 0-2), Stamina is per player (bits 3-5) and the Fatality meter is shared in
-- the bits Health leaves free in player 1's byte.
local function shop_addr(m, player, kind)
    local p = (kind == "health" and 0) or (kind == "fatal" and 1) or player
    return m + LEVELS + p * 0x1C + SHOP_SLOT
end

local function shop_level(m, player, kind)
    local b = game.read_u8(shop_addr(m, player, kind))
    if b & SHOP_MARK == 0 then return 0 end
    local level = kind == "stamina" and (b >> 3) & 7 or b & 7
    return level < SHOP_ROWS and level or SHOP_ROWS
end

local function set_shop_level(m, player, kind, v)
    local addr = shop_addr(m, player, kind)
    local b = game.read_u8(addr)
    if b & SHOP_MARK == 0 then b = SHOP_MARK end
    if kind == "stamina" then b = (b & ~0x38) | v << 3 else b = (b & ~7) | v end
    game.write_u8(addr, b)
end

-- The menu player, or nil.
local function menu_player()
    local player = game.read_u32(MENU_PLAYER)
    if player > 1 then return nil end
    return player
end

-- Max health with the shop's steps on top. The game only ever writes vanilla
-- values (base plus nothing), so any value of the form base + l steps is one
-- we may raise to base + level steps; anything else isn't ours to touch.
local function ensure_health(m)
    local mode = game.read_u32(m + GAME_MODE)
    if mode > 1 then return end
    local function table_hp(ups) return game.read_u32(HP_TABLE + (ups * 5 + mode) * 4) end
    local ups = game.read_u32(m + HEALTH_UPS)
    local base = table_hp(ups < HP_MAX_UPS and ups or HP_MAX_UPS)
    local step = table_hp(HP_MAX_UPS) - table_hp(HP_MAX_UPS - 1)
    if base < 1 or base > 100000 or step < 1 or step > 100000 then return end
    local want = base + HP_STEPS[shop_level(m, 0, "health")] * step
    local function known(v, scale, div)
        for l = 0, HP_STEPS[SHOP_ROWS] do
            if v == (base + l * step) * scale // div then return true end
        end
        return false
    end
    local now = game.read_u32(m + MAX_HP)
    if now ~= want and known(now, 1, 1) then
        game.write_u32(m + MAX_HP, want)
    end
    local area = game.read_u32(m + HP_LEVEL)
    if area < 1 or area > HP_LEVEL_MAX then return end
    local div = mode == 1 and 2 or 1
    for player = 0, mode do
        local actor = game.read_u32(ENTITY + player * ENTITY_STRIDE + ACTOR)
        if plausible(actor) then
            local max, new = game.read_u32(actor + ACTOR_MAX_HP), want * area // div
            if max ~= new and known(max, area, div) then
                game.write_u32(actor + ACTOR_MAX_HP, new)
                local hp = game.read_u32(actor + ACTOR_HP)
                if hp > 0 and hp < 0x80000000 then       -- heal by what max gained, never revive
                    if new > max then hp = hp + new - max end
                    game.write_u32(actor + ACTOR_HP, hp < new and hp or new)
                end
            end
        end
    end
end

-- A stamina cost as the bigger bar sees it: cost * 100 / BAR[level],
-- exact (it may have a fraction; see ensure_stamina).
local function scaled(c, level)
    if c < 1 or c > 100000 then return c end
    return c * 100 / BAR[level]
end

-- Player p's stamina costs, scaled to their Stamina level. Costs that are no
-- longer the ones we wrote were just copied from the character's template.
-- The costs are integers, and the smallest (3, drained every frame by moves
-- like the long jump) would round 1.5 up to 2 at Stamina +4. So a fractional
-- cost alternates between its floor and ceiling from frame to frame, carrying
-- the remainder, and averages out exact.
local function ensure_stamina(m, rec)
    local off = rec - STAMINA
    if off < 0 or off % STAMINA_STRIDE ~= 0 then return end
    local player = off // STAMINA_STRIDE
    if player > 1 or player >= game.read_u32(STAMINA_COUNT) then return end
    local level = shop_level(m, player, "stamina")
    local cur = {}
    for i = 1, COSTS do cur[i] = game.read_u32(rec + (i - 1) * 4) end
    local s = costs[player + 1]
    local fresh = s == nil
    if s then
        for i = 1, COSTS do if cur[i] ~= s.now[i] then fresh = true end end
        if not fresh and s.level == level and not s.dither then return end
    end
    local base = fresh and cur or s.base
    local carry = (not fresh and s.level == level) and s.carry or { 0.5, 0.5, 0.5, 0.5 }
    local now, dither = {}, false
    for i = 1, COSTS do
        local exact = scaled(base[i], level)
        if exact == math.floor(exact) then
            now[i] = math.tointeger(exact)
        else
            dither = true
            local due = carry[i] + exact
            now[i] = math.floor(due)
            if now[i] < 1 then now[i] = 1 end
            carry[i] = due - now[i]
        end
        if now[i] ~= cur[i] then game.write_u32(rec + (i - 1) * 4, now[i]) end
    end
    costs[player + 1] = { base = base, now = now, level = level, carry = carry, dither = dither }
end

-- After a Tick: whatever it took off the bar was the sustained drain (regen
-- only adds, and is skipped while draining). Give back the share a bigger
-- bar wouldn't have spent, unless the drain emptied the bar and ended the
-- state.
local function refund_drain(m, t)
    local rec, before = t[1], t[2]
    local player = (rec - STAMINA) // STAMINA_STRIDE
    local level = shop_level(m, player, "stamina")
    if level == 0 then return end
    local after = f32_to(game.read_u32(rec + STAMINA_NOW))
    if after == nil or after <= 0 or after >= before then return end
    local back = (before - after) * (BAR[level] - 100) / BAR[level]
    game.write_u32(rec + STAMINA_NOW, f32_from(after + back))
end

-- The Basic Moves category under a character root, and the vanilla group
-- each shop group takes over (nil where it doesn't look as expected).
local function shop_nodes(root)
    local n, kids = game.read_u32(root + 0x0C), game.read_u32(root + 0x14)
    if n > 16 or not plausible(kids) then return nil end
    for i = 0, n - 1 do
        local c = game.read_u32(kids + i * 4)
        if plausible(c) and game.read_u32(c + 4) == 2 then
            local name = game.read_u32(c + 0x18)
            local count, list = game.read_u32(c + 0x0C), game.read_u32(c + 0x14)
            if (name == BASIC_TEXT or name == SHOP.category.text) and plausible(list) then
                local groups = {}
                for j, group in ipairs(SHOP.groups) do
                    local g = group.slot < count and game.read_u32(list + group.slot * 4) or 0
                    if plausible(g) and game.read_u32(g + 4) == 1 then
                        local gname, rows = game.read_u32(g + 0x18), game.read_u32(g + 0x0C)
                        if (gname == group.source or gname == group.text) and rows == #group.rows then
                            groups[j] = g
                        end
                    end
                end
                return c, groups
            end
        end
    end
    return nil
end

-- The Items group in a Basic Moves category: Running Attacks, or ours
-- (the meter's refills).
local function items_group(c)
    local count, list = game.read_u32(c + 0x0C), game.read_u32(c + 0x14)
    local g = ITEMS_SLOT < count and game.read_u32(list + ITEMS_SLOT * 4) or 0
    if not plausible(g) or game.read_u32(g + 4) ~= 1 then return nil end
    local gname, rows = game.read_u32(g + 0x18), game.read_u32(g + 0x0C)
    if (gname == RUNNING_TEXT and rows == 4) or (gname == ITEMS_TEXT and rows == #METER.PRICES) then
        return g
    end
    return nil
end

-- The shop kind, store and row index (1-n) when node is one of our shop rows.
local function shop_row(node)
    if not ready or not plausible(node) or game.read_u32(node + 4) ~= 0 then return nil end
    local ex = ex_rows[node]
    if ex and ex.sale then return "ex", ex, ex.j end
    local g = game.read_u32(node + 0x10)
    if not plausible(g) then return nil end
    local gname = game.read_u32(g + 0x18)
    local kids = game.read_u32(g + 0x14)
    for _, group in ipairs({ SHOP.groups[1], SHOP.groups[2], SHOP.fatal }) do
        if gname == group.text then
            for k = 1, #group.rows do
                if game.read_u32(kids + (k - 1) * 4) == node then return "basic", group, k end
            end
        end
    end
    local cost = game.read_u32(node + 0x28)
    if gname == ITEMS_TEXT or gname == ARMS.NAME then      -- the meter's refills, or a weapon type
        local prices = gname == ITEMS_TEXT and METER.PRICES or ARMS.PRICES
        for k = 1, #prices do
            if game.read_u32(kids + (k - 1) * 4) == node and cost == prices[k] then
                return gname == ITEMS_TEXT and "meter" or "weapon", nil, k
            end
        end
    end
    if gname == FATALITY_TEXT and cost == FATALITY_COST then
        return "fatality", nil, nil
    end
    return nil
end

-- Whether a name text index is in the game's discovered-fatality list (nil
-- when the count is not one we understand).
local function discovered(name)
    local count = game.read_u32(FAT_COUNT)
    if count > FAT_MAX then return nil end
    for i = 0, count - 1 do
        if game.read_u32(FAT_LIST + i * 4) == name then return true end
    end
    return false
end

-- A category under a character root whose leaves hang directly off it
-- (Fatalities, Skill, Platform), by its vanilla name or ours, with at least
-- n leaves (nil when absent or not shaped like that).
local function leaf_category(root, name, ours, n)
    local count, kids = game.read_u32(root + 0x0C), game.read_u32(root + 0x14)
    if count > 16 or not plausible(kids) then return nil end
    for i = 0, count - 1 do
        local c = game.read_u32(kids + i * 4)
        local cname = plausible(c) and game.read_u32(c + 0x18)
        if cname == name or cname == ours then
            local leaves, list = game.read_u32(c + 0x0C), game.read_u32(c + 0x14)
            if leaves >= n and leaves <= 16 and plausible(list) then return c end
        end
    end
    return nil
end

-- The EX flag byte of the menu player for Specials group k (menu order).
local function flag_addr(m, k)
    local player = menu_player()
    if player == nil then return nil end
    return m + LEVELS + player * 0x1C + EX_FLAG + EX_LEAF_SLOT[k]
end

-- A flag byte's EX moves, a bit per move (bit 0 = Special 1). Only a byte we
-- marked ourselves (bit 7) counts: the game writes its own values into the
-- level row, and one of those is not a purchase.
local function ex_bits(b)
    if b & 0x80 == 0 then return 0 end
    return b & 0x1F
end

-- The EX moves of Specials group k for the menu player, and their byte.
local function ex_mask(m, k)
    local addr = flag_addr(m, k)
    if addr == nil then return 0, nil end
    return ex_bits(game.read_u8(addr)), addr
end

-- The Specials category under a character root: a group per button.
local function specials_node(root)
    local n, kids = game.read_u32(root + 0x0C), game.read_u32(root + 0x14)
    if n > 16 or not plausible(kids) then return nil end
    for i = 0, n - 1 do
        local c = game.read_u32(kids + i * 4)
        if plausible(c) and game.read_u32(c + 4) == 2 and game.read_u32(c + 0x18) == SPECIALS_TEXT then
            local groups, list = game.read_u32(c + 0x0C), game.read_u32(c + 0x14)
            if groups >= 1 and groups <= 8 and plausible(list) then return c end
        end
    end
    return nil
end

-- A text as a Lua string (at most n bytes), or nil.
local function read_text(i, n)
    local p = text_at(i)
    if p == nil then return nil end
    local out = {}
    for k = 0, n - 1 do
        local b = game.read_u8(p + k)
        if b == 0 then return table.concat(out) end
        out[#out + 1] = string.char(b)
    end
    return nil
end

local function char_of(m, player)
    local id = game.read_u32(m + CHARACTER + player * 4)
    if id ~= 0 and id ~= 1 and id ~= 0x58 and id ~= 0x52 then id = 0 end
    return id
end

-- The menu player's character root, matched the way SyncOwned matches it
-- (ids other than the four playable characters fall back to Liu Kang).
local function menu_root(m, blob)
    local player = menu_player()
    if player == nil then return nil end
    local id = char_of(m, player)
    local roots, list = game.read_u32(blob + 0x0C), game.read_u32(blob + 0x10)
    if roots > 8 or not plausible(list) then return nil end
    for r = 0, roots - 1 do
        local root = game.read_u32(list + r * 4)
        if plausible(root) and game.read_u32(root + 0x18) == id then return root end
    end
    return nil
end

-- Our rows under one character root; false when the budget ran out.
local function patch_root(m, root)
    local player = menu_player()
    local c, groups = shop_nodes(root)
    if c and player ~= nil then
        if not (patch(c + 0x18, SHOP.category.text) and patch(c + 0x1C, SHOP.category.desc)) then
            return false
        end
        for j, group in ipairs(SHOP.groups) do
            local g, value = groups[j], shop_level(m, player, group.kind)
            if g then
                if not (patch(g + 0x18, group.text) and patch(g + 0x1C, group.desc)) then return false end
                local kids = game.read_u32(g + 0x14)
                for k, row in ipairs(group.rows) do
                    local node = game.read_u32(kids + (k - 1) * 4)
                    if plausible(node) and not (patch(node + 0x18, row.name) and patch(node + 0x1C, row.desc)
                            and patch(node + 0x28, row.cost)
                            and patch(node + 0x2C, value >= k and 1 or 0)) then
                        return false
                    end
                end
            end
        end
        -- Items: the fatality meter's refills (+1 to +3), bought again and again
        local g = items_group(c)
        if g then
            if not (patch(g + 0x18, ITEMS_TEXT) and patch(g + 0x1C, ITEMS_DESC)
                    and patch(g + 0x0C, #METER.PRICES)) then
                return false
            end
            local kids = game.read_u32(g + 0x14)
            for k = 1, #METER.PRICES do
                local node = game.read_u32(kids + (k - 1) * 4)
                if plausible(node) and not (patch(node + 0x18, METER.TEXT[k]) and patch(node + 0x1C, METER.DESC[k])
                        and patch(node + 0x28, METER.PRICES[k]) and patch(node + 0x2C, 0)) then
                    return false
                end
            end
        end
    end
    -- Skill becomes the Fatality meter's upgrades (shared, like Health) and
    -- Platform the Weapons, a row per type, always for sale again. The
    -- abilities behind the vanilla rows are untouched: the rows only show them.
    local skill = player ~= nil and leaf_category(root, SHOP.fatal.source, SHOP.fatal.text, #SHOP.fatal.rows)
    if skill then
        local value = shop_level(m, player, "fatal")
        if not (patch(skill + 0x18, SHOP.fatal.text) and patch(skill + 0x1C, SHOP.fatal.desc)) then return false end
        local kids = game.read_u32(skill + 0x14)
        for k, row in ipairs(SHOP.fatal.rows) do
            local node = game.read_u32(kids + (k - 1) * 4)
            if plausible(node) and not (patch(node + 0x18, row.name) and patch(node + 0x1C, row.desc)
                    and patch(node + 0x28, row.cost) and patch(node + 0x2C, value >= k and 1 or 0)) then
                return false
            end
        end
    end
    local arms = player ~= nil and leaf_category(root, ARMS.TEXT, ARMS.NAME, #ARMS.TYPES)
    if arms then
        if not (patch(arms + 0x18, ARMS.NAME) and patch(arms + 0x1C, ARMS.DESC)) then return false end
        local kids = game.read_u32(arms + 0x14)
        for k = 1, #ARMS.TYPES do
            local node = game.read_u32(kids + (k - 1) * 4)
            if plausible(node) and not (patch(node + 0x18, ARMS.ROWS[k]) and patch(node + 0x1C, ARMS.ROW_DESC)
                    and patch(node + 0x28, ARMS.PRICES[k]) and patch(node + 0x2C, 0)) then
                return false
            end
        end
    end
    -- Specials: SyncOwned has just marked the moves owned on R2. A move whose
    -- EX is bought is named "<move> EX" and owned; any other owned on R2 is
    -- for sale again as its EX.
    ex_rows = {}
    local sc = specials_node(root)
    if sc and player ~= nil then
        local groups, list = game.read_u32(sc + 0x0C), game.read_u32(sc + 0x14)
        for k = 1, groups < #EX_LEAF_SLOT and groups or #EX_LEAF_SLOT do
            local g, bits = game.read_u32(list + (k - 1) * 4), ex_mask(m, k)
            local rows, leaves = 0, 0
            if plausible(g) then rows, leaves = game.read_u32(g + 0x0C), game.read_u32(g + 0x14) end
            for j = 1, rows <= #EX_NAMES and rows or #EX_NAMES do
                local leaf = plausible(leaves) and game.read_u32(leaves + (j - 1) * 4) or 0
                local ex = bits & (1 << (j - 1)) ~= 0
                local sale = not ex and plausible(leaf) and vanilla(leaf + 0x2C) ~= 0
                if plausible(leaf) and game.read_u32(leaf + 4) == 0 and (ex or sale) then
                    ex_rows[leaf] = { k = k, j = j, sale = sale }
                    local name = read_text(vanilla(leaf + 0x18), 40)
                    local placed = name and put_text(EX_NAMES[j], name .. " EX")
                    if placed == nil and name then return false end
                    if placed and not patch(leaf + 0x18, EX_NAMES[j]) then return false end
                    if not patch(leaf + 0x2C, sale and 0 or 1) then return false end
                    if sale and not patch(leaf + 0x28, EX_PRICES[j]) then return false end
                end
            end
        end
    end
    -- Fatalities: SyncOwned has just marked the discovered ones owned; the
    -- rest get a price. Hovering a ??? row shows nothing (see CanPurchase), so
    -- the category's own description says they are for sale.
    local fat = leaf_category(root, FATALITY_TEXT, nil, 1)
    if fat then
        if not patch(fat + 0x1C, FATALITY_HINT) then return false end
        local kids = game.read_u32(fat + 0x14)
        for k = 0, game.read_u32(fat + 0x0C) - 1 do
            local node = game.read_u32(kids + k * 4)
            if plausible(node) and game.read_u32(node + 4) == 0 and game.read_u32(node + 0x2C) == 0
                    and not patch(node + 0x28, FATALITY_COST) then
                return false
            end
        end
    end
    return true
end

-- After the game syncs the menu: our text, costs and owned flags on the
-- menu player's character, or the vanilla rows back when our text has no
-- room. If the write budget runs out, the next CanPurchase call (the menu
-- asks it every frame while it draws) finishes the job.
local function sync()
    writes, resume = 0, false
    local m = manager()
    local blob = game.read_u32(MPD)
    if m == nil or not plausible(blob) then return end
    if blob ~= tree then changed = {}; tree = blob end     -- a fresh copy is vanilla
    area = scan_weapons()                                  -- the menu is paused: stable while it syncs
    local placed = place_text()
    if placed == false then ready = false; unpatch() return end
    if placed == nil then resume = true return end
    ready = true
    local root = menu_root(m, blob)
    if root and not patch_root(m, root) then resume = true end
end

-- Weapons row k can be bought: nobody holds its weapon, and it lies in the
-- area (bought, it comes over) or can be spawned here: no spawn is still
-- under way and none of this type failed in this area.
local function weapon_free(k)
    local w = ARMS.objects[k]
    if w == nil or game.read_u32(w + W_HOLDER) ~= 0 then return false end
    if in_area(w) then return true end
    return ARMS.pending == nil and callgate.pending() == 0 and not ARMS.failed[game.read_u32(MAP) * 8 + k]
end

-- Spawn part i of a weapon the area never placed, with the game's own
-- weaponspawn command, as a level script does: a PME slot with its model,
-- the home, the respawn and the physics body. The command copies its
-- orientation from [+4] + 0x18 of its command object, which points at the
-- part's own home matrix (set upright at the spot first) for the call. A
-- pair's second half follows the first. The wait for the weapon to show
-- starts once the calls have run (the gate runs on unpaused frames).
function ARMS.spawn(i)
    local p = ARMS.pending
    local part = p.parts[i]
    local up = { 0x3F800000, 0, 0, 0, 0, 0x3F800000, 0, 0, 0, 0, 0x3F800000, 0, p.home[1], p.home[2], p.home[3],
                 0x3F800000 }
    for j = 1, 16 do game.write_u32(part + ARMS.MATRIX + (j - 1) * 4, up[j]) end
    local ctx, was = part + ARMS.MATRIX - 0x18, game.read_u32(ARMS.CMD + 4)
    game.write_u32(ARMS.CMD + 4, ctx)
    callgate.call(ARMS.SPAWN, {
        ecx = ARMS.CMD,
        args = { callgate.block{ 0, 1, callgate.block{ game.read_u32(part + 8) } }, 0,
                 callgate.block{ 0, p.home[1], p.home[2], p.home[3] } },
        done = function(eax)
            if game.read_u32(ARMS.CMD + 4) == ctx then game.write_u32(ARMS.CMD + 4, was) end
            if ARMS.pending ~= p then return end
            if eax == nil then ARMS.check(true) return end          -- the call never ran
            if p.parts[i + 1] then ARMS.spawn(i + 1) else p.at = game.read_u32(FRAME) end
        end })
end

-- Once a frame: a spawned weapon that has appeared is done; one that
-- hasn't, ARMS.WAIT frames after its calls (or at once when told), gives
-- its XP back, and its type isn't sold again in that area this session.
function ARMS.check(now)
    local p = ARMS.pending
    if p == nil or (not now and p.at == nil) then return end
    if not now and in_area(p.parts[1]) then ARMS.pending = nil return end
    if not now and game.read_u32(FRAME) - p.at < ARMS.WAIT and game.read_u32(MAP) == p.map then return end
    ARMS.pending = nil
    ARMS.failed[p.map * 8 + p.k] = true
    local m = manager()
    if m == nil then return end
    local at = m + XP + p.player * PLAYER_STRIDE
    game.write_u32(at, game.read_u32(at) + p.cost)
end

-- Player p's fatality meter: its value, the size of a level, the levels it
-- holds and how many more of them can light up (a value within 1e-4 levels
-- of a level counts as there). Nil when it can't be read, or in fatality
-- mode, where the HUD sets the meter from the mode's timer and a fill
-- would be lost.
local function meter_state(m, player)
    local stats = game.read_u32(ENTITY + player * ENTITY_STRIDE + METER.STATS)
    local hud = plausible(stats) and game.read_u32(stats + METER.HUD) or 0
    if not plausible(hud) then return nil end
    local bar = f32_to(game.read_u32(hud + METER.BAR))
    local value = f32_to(game.read_u32(m + METER.VALUE + player * PLAYER_STRIDE))
    local levels = game.read_u32(m + METER.LEVEL + player * PLAYER_STRIDE)
    if bar == nil or bar < 3 or bar > 100000 or value == nil or value < 0 or levels > METER.MAX then return nil end
    local modes = game.read_u32(METER.MODES)
    local who = plausible(modes) and game.read_u32(modes + METER.MODE_REC + (player + 1) * 8) or 0
    if plausible(who) then
        local state, id = game.read_u32(who + METER.MODE_STATE), game.read_u16(who + METER.CHAR_ID)
        local ids = METER.MODE_IDS + id * METER.MODE_STRIDE
        if state ~= 0 and id < 0x100 and (state == game.read_u32(ids) or state == game.read_u32(ids + 4)) then
            return nil
        end
    end
    local size = bar * METER.THIRD
    return value, size, levels, levels - math.floor(value / size + 1e-4)
end

-- The row is the next to buy in its store (a fatality: not discovered yet,
-- with room in the list; a meter fill: room for its levels), affordable,
-- and its cost really is ours.
local function can_buy(node, kind, store, k)
    local m = manager()
    if m == nil then return false end
    local cost = (kind == "fatality" and FATALITY_COST) or (kind == "weapon" and ARMS.PRICES[k])
        or (kind == "meter" and METER.PRICES[k]) or (kind == "ex" and EX_PRICES[k]) or store.rows[k].cost
    if game.read_u32(node + 0x28) ~= cost then return false end
    local player = menu_player()
    if player == nil then return false end
    if kind == "fatality" then
        if game.read_u32(node + 0x2C) ~= 0 or game.read_u32(FAT_COUNT) >= FAT_MAX
                or discovered(game.read_u32(node + 0x18)) ~= false then
            return false
        end
    elseif kind == "weapon" then
        if not weapon_free(k) then return false end
    elseif kind == "meter" then
        local value, _, _, room = meter_state(m, player)
        if value == nil or room < k then return false end
    elseif kind == "ex" then
        if not store.sale or ex_mask(m, store.k) & (1 << (k - 1)) ~= 0 then return false end
    elseif shop_level(m, player, store.kind) ~= k - 1 then
        return false
    end
    return game.read_u32(m + XP + player * PLAYER_STRIDE) >= cost
end

-- Record the bought row and apply it at once (the pause menu shows the new
-- max health straight away). A fatality goes into the discovered list, which
-- the game saves, so its input stays revealed like one the player performed.
local function apply_purchase(m, kind, store, k, node)
    if kind == "ex" then
        local bits, addr = ex_mask(m, store.k)
        if addr then game.write_u8(addr, 0x80 | bits | (1 << (k - 1))) end
        store.sale = false
        return
    end
    if kind == "weapon" then
        local player, w = menu_player(), ARMS.objects[k]
        if player == nil or w == nil then return end
        local at = ENTITY + player * ENTITY_STRIDE + POSITION
        local x, y, z = f32_to(game.read_u32(at)), f32_to(game.read_u32(at + 4)), f32_to(game.read_u32(at + 8))
        if x == nil or y == nil or z == nil then return end
        local home = { f32_from(x + WEAPON_SIDE), f32_from(y - WEAPON_FLOOR), f32_from(z) }
        local parts = { w }
        local half = game.read_u32(w + W_NEXT)
        if plausible(half) then parts[2] = half end
        if not in_area(w) then
            -- the area never placed it: the game spawns it (experimental; see ARMS.spawn)
            ARMS.pending = { parts = parts, home = home, k = k, player = player, cost = ARMS.PRICES[k],
                             map = game.read_u32(MAP) }
            ARMS.spawn(1)
            return
        end
        for _, part in ipairs(parts) do
            -- remember where the level keeps it, unless that is our own last spot
            local now = { game.read_u32(part + W_HOME), game.read_u32(part + W_HOME + 4),
                          game.read_u32(part + W_HOME + 8) }
            local s = summoned[part]
            if not (s and s.spot[1] == now[1] and s.spot[2] == now[2] and s.spot[3] == now[3]) then
                s = { first = w, home = now, on = game.read_u8(part + W_HOME_ON),
                      seen = { game.read_u32(part + W_SEEN), game.read_u32(part + W_SEEN + 4),
                               game.read_u32(part + W_SEEN + 8) } }
            end
            s.spot = home
            summoned[part] = s
            for i = 1, 3 do game.write_u32(part + W_HOME + (i - 1) * 4, home[i]) end
            game.write_u8(part + W_HOME_ON, 1)
            game.write_u32(part + W_DUR, game.read_u32(part + W_DUR_MAX))
            game.write_u32(part + W_COUNTDOWN, 1)
        end
        -- the row stays bought (the menu plays its purchase jingle for that)
        -- until the next menu open, whose sync puts it up for sale again
        return
    end
    if kind == "fatality" then
        local name, count = game.read_u32(node + 0x18), game.read_u32(FAT_COUNT)
        if count < FAT_MAX and discovered(name) == false then
            game.write_u32(FAT_LIST + count * 4, name)
            game.write_u32(FAT_COUNT, count + 1)
        end
        return
    end
    local player = menu_player()
    if player == nil then return end
    if kind == "meter" then
        -- k levels on top of what the meter holds, kept within its levels,
        -- rounded up to the next f32: the game compares the meter with an
        -- unrounded level (400.00001), and a full level must not land below it.
        -- The HUD follows the value by itself; the row stays bought until
        -- the next menu open, like a weapon's.
        local value, size, levels, room = meter_state(m, player)
        if value == nil or room < k then return end
        local want = math.min(value + k * size, levels * size)
        local bits = f32_from(want)
        if f32_to(bits) < want then bits = bits + 1 end
        game.write_u32(m + METER.VALUE + player * PLAYER_STRIDE, bits)
        return
    end
    if shop_level(m, player, store.kind) ~= k - 1 then return end
    set_shop_level(m, player, store.kind, k)
    if store.kind == "health" then
        ensure_health(m)
    elseif store.kind == "stamina" then
        ensure_stamina(m, STAMINA + player * STAMINA_STRIDE)
    end                                     -- (the Fatality meter's: every gain from now on)
end

-- Before the Moves list opens: in an area (map) not announced yet this
-- session whose weapons one can afford, the abilities popup will show our
-- message (the game shows it when the flag is set and anything is for sale).
local function arm_popup()
    popup = nil
    local m, player = manager(), menu_player()
    if not ready or m == nil or player == nil or #area == 0 then return end
    local key = game.read_u32(MAP)
    if announced[key] then return end
    local xp = game.read_u32(m + XP + player * PLAYER_STRIDE)
    local afford = false
    for k, w in pairs(ARMS.objects) do
        if in_area(w) and weapon_free(k) and xp >= ARMS.PRICES[k] then afford = true end
    end
    local list, ours = game.read_u32(TEXT_PTRS), text_at(WEAPON_POPUP)
    if not afford or not plausible(list) or ours == nil then return end
    popup = { at = list + POPUP_TEXT * 4, was = game.read_u32(list + POPUP_TEXT * 4), ours = ours,
              flag = game.read_u8(POPUP_FLAG) }
    game.write_u32(popup.at, ours)
    game.write_u8(POPUP_FLAG, 1)
    announced[key] = true
end

-- After the Moves list opened (the popup, modal, has closed): the game's text
-- and flag back.
local function disarm_popup()
    local p = popup
    popup = nil
    if p == nil then return end
    if game.read_u32(p.at) == p.ours then game.write_u32(p.at, p.was) end
    game.write_u8(POPUP_FLAG, p.flag)
end

-- Before a respawn: a summoned weapon whose durability is spent goes back to
-- the home the level gave it, not to its purchase spot. A record whose home
-- is no longer our spot is stale (the level placed the weapon again).
local function respawning(w)
    local s = summoned[w]
    if s == nil then return end
    if game.read_u32(w + W_HOME) ~= s.spot[1] or game.read_u32(w + W_HOME + 4) ~= s.spot[2]
            or game.read_u32(w + W_HOME + 8) ~= s.spot[3] then
        summoned[w] = nil
        return
    end
    local dur = game.read_u32(s.first + W_DUR)
    if dur ~= 0 and dur < 0x80000000 then return end       -- thrown, not broken
    for i = 1, 3 do
        game.write_u32(w + W_HOME + (i - 1) * 4, s.home[i])
        game.write_u32(w + W_SEEN + (i - 1) * 4, s.seen[i])
    end
    game.write_u8(w + W_HOME_ON, s.on)
    summoned[w] = nil
end

-- EX stamina, scaled like every cost by the player's Stamina level.
local function ex_cost(m, player)
    return scaled(EX_COST, shop_level(m, player, "stamina"))
end

-- EX flags 0.11.3 wrote into the game's level slots 23-25 (marked with bit
-- 7, which no game value there carries) join the ones in 19-21, and the
-- game's byte goes back to 0. Once per save: afterwards nothing matches.
local function ex_migrate(m)
    for player = 0, 1 do
        local row = m + LEVELS + player * 0x1C
        for k = 0, 2 do
            local old = game.read_u8(row + EXP.OLD_FLAG + k)
            if old & 0xE0 == 0x80 then
                game.write_u8(row + EX_FLAG + k, 0x80 | ex_bits(game.read_u8(row + EX_FLAG + k)) | (old & 0x1F))
                game.write_u8(row + EXP.OLD_FLAG + k, 0)
            end
        end
    end
end

local ex_due = {}               -- [player + 1] = frame an EX was pressed; stamina due
local ex_held = {}              -- [player + 1] = the attack byte of the EX press still held
local ex_chain = {}             -- [player + 1] = true while an EX chain keeps L2 as R2
local spender = nil             -- player passed to the stamina-spend wrapper
local exs = {                       -- EX power state
    press = {},                     -- [player + 1] = frame of their last paid EX press
    move = {},                      -- [player + 1] = anim id of the EX move they are in
    button = {},                    -- [player + 1] = the button (analog byte) of their last paid press
    down = {},                      -- [player + 1] = { [button] = held last frame }, the EX buttons
    cancel = {},                    -- [player + 1] = { button, at, go }: a cancel press held back
    force = {},                     -- [player + 1] = { button, till }: a cancel press played back
    events = {}, map = nil,         -- [anim] = its last event frame (false: unknown), per map
    -- GetLevel's player and caller, SlotLevel's arguments and caller
    ex_player = nil, ex_from = nil, lv_player = nil, lv_flags = nil, lv_from = nil,
}

-- During player's EX chain, the level to report for move `level` of game
-- slot `slot` (0: the special at all), given the real one: exactly its level
-- if its EX is bought (and it is owned on R2), else 0, so only EX moves pass.
-- nil: leave it (no chain, the demo, no manager).
local function ex_answer(player, slot, level, real)
    if not ex_chain[player + 1] then return nil end  -- the whole EX chain, follow-ups too
    local m = manager()
    if m == nil or game.read_u8(DEMO) == 1 then return nil end
    local bits = ex_bits(game.read_u8(m + LEVELS + player * 0x1C + EX_FLAG + slot))
    if level == 0 then return bits ~= 0 and real or 0 end
    return (bits & (1 << (level - 1)) ~= 0 and real >= level) and level or 0
end

-- After GetLevel: the move system asks whether a special's move may be
-- picked (its condition id in ebp). The stamina comes off when the move
-- spends its own.
local function boost_level(ctx)
    local player, from = exs.ex_player, exs.ex_from
    exs.ex_player = nil
    if player == nil or from < EVAL_FROM or from >= EVAL_TO or player > 1 then return end
    local c = ctx.ebp - EX_COND
    if c < 0 or c >= EX_CONDS then return end
    local level = ex_answer(player, c // 5, c % 5 + 1, ctx.eax & 0xFF)
    if level then ctx.eax = (ctx.eax & 0xFFFFFF00) | level end
end

-- After SlotLevel: the move filter asks whether a move's special is owned up
-- to the move's tier (the call site says which). Same answers.
local function gate_move(ctx)
    local player, flags, tier = exs.lv_player, exs.lv_flags, MOVE_TIER[exs.lv_from]
    exs.lv_player = nil
    if player == nil or tier == nil or player > 1 then return end
    local slot = (flags & 0x10000000 ~= 0 and 0) or (flags & 0x20000000 ~= 0 and 1)
        or (flags & 0x40000000 ~= 0 and 2)
    if not slot then return end                     -- (^, slot 3: left alone)
    local level = ex_answer(player, slot, tier, ctx.eax & 0xFF)
    if level then ctx.eax = level end
end

-- The last frame of anim `anim` with an event on it, or nil when it can't be
-- told. Cached per map (the banks are the level's).
local function last_event(anim)
    local map = game.read_u32(MAP)
    if map ~= exs.map then exs.events, exs.map = {}, map end
    local known = exs.events[anim]
    if known ~= nil then return known or nil end
    local last = false
    local count, lists, data = game.read_u32(EXP.BANK), game.read_u32(EXP.BANK + 0xC), game.read_u32(EXP.BANK + 8)
    local i = anim < count and anim or 0
    local list = plausible(lists) and game.read_u32(lists + i * 4) or 0
    local lengths = game.read_u32(EXP.BANK + 4)
    if plausible(list) and plausible(data) and plausible(lengths) then
        local length = game.read_u32(lengths + game.read_u32(EXP.LENGTH_IX + anim * 4) * 16 + 8)
        local info = game.read_u32(data + i * 4)
        last = -1
        for k = 0, 63 do
            local e = list + k * 16
            local frame, kind = game.read_u16(e), game.read_u16(e + 2)
            if frame >= 0x8000 then frame = frame - 0x10000 end
            if frame == -2 then                      -- at the end: the anim's own end frame
                local at = plausible(info) and game.read_u16(info + 0x16) or 0
                frame = (at ~= 0 and at - 1 <= length - 1) and at - 1 or length - 1
            end
            if frame < -2 or k == 63 or length > 0x4000 then last = false break end
            if frame > last then last = frame end
            if kind == 0 then break end
        end
    end
    exs.events[anim] = last
    return last or nil
end

-- Before a port's pad becomes action bits: L2 (without R2) + an attack
-- button with an EX bought becomes R2 + that button, so the game does
-- the special, and L2 stays R2 until it is let go, so the special's input
-- chain (X, X, X) goes through; each press marks an EX when the stamina
-- covers the extra. During an EX move a fresh L2 press of another EX button
-- is a cancel: the game sees that button released until ex_tick has ended
-- the move after its last event, then the press is played back here as R2
-- + the button for EXP.FORCE frames (a tap works too). Anything else passes
-- untouched. Only the trigger bytes count as L2 and R2: they are all the
-- pad translator reads.
local function ex_remap(obj)
    local off = obj - PADS
    if off < 0 or off % PAD_OBJ ~= 0 or off // PAD_OBJ > 1 then return end
    local player = off // PAD_OBJ
    local i = player + 1
    local m = manager()
    if m == nil or game.read_u8(DEMO) == 1 or player >= game.read_u32(STAMINA_COUNT) then return end
    local row, frame = m + LEVELS + player * 0x1C, game.read_u32(FRAME)
    local down, fresh = exs.down[i] or {}, nil      -- fresh presses of EX buttons, as the pad has them
    exs.down[i] = down
    for _, b in ipairs(EX_BUTTONS) do
        local now = game.read_u8(obj + b[1]) ~= 0
        if now and not down[b[1]] and ex_bits(game.read_u8(row + EX_FLAG + b[2])) ~= 0 then fresh = b[1] end
        down[b[1]] = now
    end
    local lt_held = game.read_u8(obj + J_LT) >= LT_MIN
    local rt_held = game.read_u8(obj + J_RT) ~= 0
    local cancel = exs.cancel[i]
    if cancel and cancel.go then                    -- ex_tick ended the move: play the press back
        exs.cancel[i] = nil
        exs.force[i] = { button = cancel.button, till = frame + EXP.FORCE - 1 }
        ex_due[i], exs.press[i], exs.button[i] = frame, frame, cancel.button
        ex_chain[i], ex_held[i] = true, cancel.button
        cancel = nil
    end
    local force = exs.force[i]
    if force then
        if frame >= force.till then exs.force[i] = nil end
        game.write_u8(obj + force.button, 0xFF)
        game.write_u8(obj + J_LT, 0)
        game.write_u8(obj + J_RT, 0xFF)
        return
    end
    -- a fresh press of another EX button in an EX move whose last event can
    -- be told, with the stamina for it: a cancel (the latest one wins)
    if fresh and fresh ~= exs.button[i] and exs.move[i] and lt_held and not rt_held
            and last_event(exs.move[i]) then
        local have = f32_to(game.read_u32(STAMINA + player * STAMINA_STRIDE + STAMINA_NOW))
        if have ~= nil and have >= ex_cost(m, player) then
            cancel = { button = fresh, at = frame }
            exs.cancel[i] = cancel
        end
    end
    if cancel then game.write_u8(obj + cancel.button, 0) end   -- held back until it plays
    if not lt_held then              -- L2 let go: the chain is over
        ex_chain[i], ex_held[i] = nil, nil
        return
    end
    if rt_held then return end        -- L2 + R2 stays the game's
    local held = ex_held[i]
    if held and game.read_u8(obj + held) == 0 then ex_held[i] = nil; held = nil end
    for _, b in ipairs(EX_BUTTONS) do
        if (cancel == nil or b[1] ~= cancel.button) and game.read_u8(obj + b[1]) ~= 0
                and ex_bits(game.read_u8(row + EX_FLAG + b[2])) ~= 0 then
            if held == nil then                     -- a new press: EX if the stamina covers it
                local have = f32_to(game.read_u32(STAMINA + player * STAMINA_STRIDE + STAMINA_NOW))
                local paid = have ~= nil and have >= ex_cost(m, player)
                if not paid and not ex_chain[i] then return end   -- not even a chain: block
                ex_held[i] = b[1]
                if paid then ex_due[i], exs.press[i], exs.button[i] = frame, frame, b[1] end
            end
            ex_chain[i] = true
            break
        end
    end
    if ex_chain[i] then
        game.write_u8(obj + J_LT, 0)
        game.write_u8(obj + J_RT, 0xFF)
    end
end

-- After a scripted move spent stamina: an EX variant picked moments ago
-- pays its extra now, once. A pick whose move spent nothing expires.
local function charge_ex()
    local player = spender
    spender = nil
    if player == nil or player > 1 then return end
    local due = ex_due[player + 1]
    if due == nil then return end
    ex_due[player + 1] = nil
    local frame = game.read_u32(FRAME)
    if frame < due or frame - due > EX_WINDOW then return end
    local m = manager()
    if m == nil then return end
    local rec = STAMINA + player * STAMINA_STRIDE
    local have = f32_to(game.read_u32(rec + STAMINA_NOW))
    if have == nil then return end
    local left = have - ex_cost(m, player)
    game.write_u32(rec + STAMINA_NOW, f32_from(left > 0 and left or 0))
end

-- Once a frame, before the animations advance: a player in an EX move
-- (latched from a paid press) speeds up once its last event has played, or,
-- with a cancel held back, the move ends right there and the press plays
-- back on the next frame (see ex_remap). A cancel whose move ended first
-- plays at once; one whose move never reached its last event is let go.
local function ex_tick()
    local frame = game.read_u32(FRAME)
    for p = 0, 1 do
        local i = p + 1
        local e = ENTITY + p * ENTITY_STRIDE
        local anim, press = game.read_u32(e + EXP.ANIM), exs.press[i]
        if game.read_u32(e + EXP.STATE) ~= 6 or anim >= 0x10000 then
            exs.move[i] = nil
        elseif anim ~= exs.move[i] then           -- a new move: EX if just pressed
            exs.move[i] = (press and frame - press <= EX_WINDOW) and anim or nil
        end
        local cancel = exs.cancel[i]
        if cancel and cancel.go then cancel = nil end
        if cancel and frame - cancel.at > EXP.CANCEL_WAIT then
            exs.cancel[i], cancel = nil, nil
        end
        if exs.move[i] then
            local last = last_event(anim)
            local at = game.read_u32(e + EXP.FRAME)
            if last and at < 0x10000 and at > last then
                if cancel then
                    game.write_u32(e + EXP.FRAME, 0x7FFF)   -- the anim tick ends the move now
                    cancel.go = true
                elseif game.read_u8(e + EXP.SPEED) == 0 then
                    game.write_u8(e + EXP.SPEED, EXP.RECOVERY)
                end
            end
        elseif cancel then
            cancel.go = true
        end
    end
end

-- Msg 164 identifies a combat hit (arg1 is minus the damage); its nested
-- TakeDamage applies the boost to the final positive damage rather than
-- only changing the event argument.
local function ex_hit(ctx)
    if game.read_u32(ctx.esp + 8) ~= EXP.HIT then return end
    local victim = game.read_u32(ctx.esp + 4)
    if victim == ENTITY or victim == ENTITY + ENTITY_STRIDE then return end
    local frame = game.read_u32(FRAME)
    local live = false
    for p = 1, 2 do
        local press = exs.press[p]
        if exs.move[p] or (press and frame >= press and frame - press <= EXP.HIT_FRAMES) then live = true end
    end
    if live and game.read_u32(ctx.esp + 0xC) >= 0x80000000 then exs.hit = victim end
end

-- TakeDamage: an EX hit (see ex_hit) does EXP.DAMAGE / 2 times the damage.
-- In single player any damage to an enemy while the player's EX move plays
-- is the move's (some of its hits reach TakeDamage without message 164); in
-- co-op only message-164 hits count, so the other player's own hits stay
-- as they are.
local function ex_take_damage(ctx)
    local victim = game.read_u32(ctx.ecx + 0xBC)
    if victim == ENTITY or victim == ENTITY + ENTITY_STRIDE then return end
    local boost = exs.hit ~= nil and victim == exs.hit
    if not boost and exs.move[1] then
        local m = manager()
        boost = m ~= nil and game.read_u32(m + GAME_MODE) == 0
    end
    if not boost then return end
    local damage = game.read_u32(ctx.esp + 4)
    if damage == 0 or damage >= 0x01000000 then return end    -- not a hit's damage
    game.write_u32(ctx.esp + 4, damage * EXP.DAMAGE // 2)
end

local function set_al(ctx, v)
    ctx.eax = (ctx.eax & 0xFFFFFF00) | v
end

local shop_hooks = {
    { address = SYNC_OWNED, after = function(ctx) sync() end },
    {
        address = CAN_PURCHASE,
        before = function(ctx)
            if resume then sync() end
            asked = game.read_u32(ctx.esp + 4)
            asked_from = game.read_u32(ctx.esp)
        end,
        after = function(ctx)
            local node, from = asked, asked_from
            asked, asked_from = nil, nil
            local kind, store, k
            if node then kind, store, k = shop_row(node) end
            -- A yes makes the description and the preview video show, and for a
            -- fatality those are the input: only the purchase itself and the
            -- category's "anything to buy" search hear it. (The row's own
            -- look stays vanilla: lifting the game's skip for Fatalities
            -- showed the names, so ??? rows stay white.)
            if kind == "fatality" and from ~= ASKED_TO_BUY and from ~= ASKED_FOR_ANY then return end
            if (kind == "weapon" or kind == "meter") and from == ASKED_FOR_VIDEO then return end
            if kind then set_al(ctx, can_buy(node, kind, store, k) and 1 or 0) end
        end,
    },
    {
        -- A row on sale as its EX is not bought as a special (that would raise
        -- the R2 tier) but through the combo purchase, like the shop's rows.
        address = IS_SPECIAL,
        before = function(ctx) asked = game.read_u32(ctx.esp + 4) end,
        after = function(ctx)
            local ex = ex_rows[asked]
            asked = nil
            if ready and ex and ex.sale then set_al(ctx, 0) end
        end,
    },
    {
        address = IS_COMBO,
        before = function(ctx) asked = game.read_u32(ctx.esp + 4) end,
        after = function(ctx)
            local node = asked
            asked = nil
            if node and shop_row(node) then set_al(ctx, 1) end
        end,
    },
    {
        address = BUY_COMBO,
        before = function(ctx)
            local node = game.read_u32(SELECTED)
            local kind, store, k = shop_row(node)
            pending = kind and can_buy(node, kind, store, k) and { kind, store, k, node } or nil
        end,
        after = function(ctx)
            local p = pending
            pending = nil
            local m = manager()
            if p == nil or m == nil or ctx.eax & 0xFF ~= 1 then return end
            apply_purchase(m, p[1], p[2], p[3], p[4])
        end,
    },
    {
        -- Upgrade(player, slot, timer), cdecl. During our purchase it is called
        -- with a combo slot; put that slot back the way it was.
        address = UPGRADE,
        before = function(ctx)
            saved = nil
            local m = manager()
            if pending == nil or m == nil then return end
            local player, slot = game.read_u32(ctx.esp + 4), game.read_u32(ctx.esp + 8)
            if player > 1 or slot > 27 then return end
            local i = player * 0x1C + slot
            local timer = m + ABILITY_BASE + i * 4
            local records = m + ABILITY_BASE + 0x118 + i * 0x24 + 0x20
            saved = { level = m + LEVELS + i, l = game.read_u8(m + LEVELS + i),
                      timer = timer, t = game.read_u32(timer),
                      records = records, r = game.read_u32(records) }
        end,
        after = function(ctx)
            local s = saved
            saved = nil
            if s == nil then return end
            if game.read_u8(s.level) ~= s.l then game.write_u8(s.level, s.l) end
            if game.read_u32(s.timer) ~= s.t then game.write_u32(s.timer, s.t) end
            if game.read_u32(s.records) ~= s.r then game.write_u32(s.records, s.r) end
        end,
    },
    {
        -- The story's meter level-up adds without a cap; keep it within the
        -- HUD's three levels for saves where 0.2/0.3 sold a level early.
        address = METER.LEVELUP,
        after = function(ctx)
            local m = manager()
            if m == nil then return end
            for player = 0, 1 do
                local addr = m + METER.LEVEL + player * PLAYER_STRIDE
                if game.read_u32(addr) > METER.MAX then game.write_u32(addr, METER.MAX) end
            end
        end,
    },
    {
        -- AddMeter(entity, amount) on a player's HUD meter: every gain grows
        -- by the Fatality meter's level (a spend comes in negative: left alone)
        address = METER.ADD,
        before = function(ctx)
            local m = manager()
            if m == nil then return end
            local level = shop_level(m, 0, "fatal")
            local e = game.read_u32(ctx.esp + 4)
            if level == 0 or (e ~= ENTITY and e ~= ENTITY + ENTITY_STRIDE) then return end
            local add = f32_to(game.read_u32(ctx.esp + 8))
            if add == nil or add <= 0 or add > 100000 then return end
            game.write_u32(ctx.esp + 8, f32_from(add * METER.GAIN[level] / 100))
        end,
    },
    {
        -- Fatality mode's drain: one off a player's record per call. Give back
        -- the share a longer-lasting meter wouldn't have spent (only a plain
        -- step: the mode's end sets the record to 0, then back to 1000)
        address = METER.DRAIN,
        before = function(ctx)
            METER.drained = nil
            local modes = game.read_u32(METER.MODES)
            local i = ctx.ecx - modes - METER.RECORDS
            if plausible(modes) and i >= 0 and i <= 8 and i % 8 == 0 then
                METER.drained = { ctx.ecx, game.read_u32(ctx.ecx + 4), i // 8 }
            end
        end,
        after = function(ctx)
            local d = METER.drained
            METER.drained = nil
            if d == nil then return end
            local left = game.read_u32(d[1] + 4)
            if left ~= d[2] - 1 or left < 1 or left > 1000 then return end
            local m = manager()
            local level = m and shop_level(m, 0, "fatal") or 0
            if level == 0 then return end
            local carry = (METER.carry[d[3] + 1] or 0) + 1 - METER.LAST[level]
            if carry >= 1 then
                carry = carry - 1
                game.write_u32(d[1] + 4, left + 1)
            end
            METER.carry[d[3] + 1] = carry
        end,
    },
    { address = RESPAWN, before = function(ctx) respawning(ctx.ecx) end },
    { address = MOVES_OPEN, before = function(ctx) arm_popup() end, after = function(ctx) disarm_popup() end },
    {
        -- Once per stamina record per frame: keep that player's costs scaled,
        -- (on player 0's record) the shop's health on top, 0.11.3's EX flags
        -- moved and a weapon spawn checked, and afterwards scale what the
        -- sustained drain took.
        address = STAMINA_TICK,
        before = function(ctx)
            ticked = nil
            local m = manager()
            if m == nil then return end
            local rec = ctx.ecx
            ensure_stamina(m, rec)
            if rec == STAMINA then ensure_health(m); ex_migrate(m); ARMS.check(false) end
            local off = rec - STAMINA
            if off >= 0 and off % STAMINA_STRIDE == 0 and off // STAMINA_STRIDE <= 1 then
                local now = f32_to(game.read_u32(rec + STAMINA_NOW))
                if now then ticked = { rec, now } end
            end
        end,
        after = function(ctx)
            local t = ticked
            ticked = nil
            local m = manager()
            if t and m then refund_drain(m, t) end
        end,
    },
}

local ex_hooks = {
    { address = PAD_MAP, before = function(ctx) ex_remap(ctx.eax) end },
    { address = EXP.TICK, before = function(ctx) ex_tick() end },
    { address = EXP.MSG, before = function(ctx) ex_hit(ctx) end, after = function(ctx) exs.hit = nil end },
    { address = EXP.TAKE_DAMAGE, before = function(ctx) ex_take_damage(ctx) end },
    {
        address = GET_LEVEL,
        before = function(ctx)
            exs.ex_player, exs.ex_from = game.read_u32(ctx.esp + 4), game.read_u32(ctx.esp)
        end,
        after = function(ctx) boost_level(ctx) end,
    },
    {
        address = SLOT_LEVEL,
        before = function(ctx)
            exs.lv_player, exs.lv_flags, exs.lv_from = game.read_u32(ctx.esp + 4), game.read_u32(ctx.esp + 8),
                game.read_u32(ctx.esp)
        end,
        after = function(ctx) gate_move(ctx) end,
    },

    {
        address = SPEND,
        before = function(ctx) spender = game.read_u32(ctx.esp + 4) end,
        after = function(ctx) charge_ex() end,
    },
}

-- (no loop here: the main chunk is near the game's Lua limit of 200 locals)
callgate.target(ARMS.SPAWN)
if PART == "shop" then return callgate.hooks(shop_hooks) end
if PART == "ex" then return ex_hooks end
return callgate.hooks(table.move(ex_hooks, 1, #ex_hooks, #shop_hooks + 1, shop_hooks))
