-- Extended Upgrades 0.9.1: XP shop, Health, Stamina, weapons, EX moves and fatality inputs.
--
-- Turns pause-menu Moves categories into the XP shop. Nothing new is added
-- to the menu; existing rows get new text, costs and behaviour, and
-- everything sold comes on top of what the game itself gives:
--   * Basic Moves -> Upgrades: Basic Attacks -> Health (+1-4: 1, 2, 4 and 8
--     game health-upgrade steps, above the game's own four) and Air Attacks
--     -> Stamina (+1-4: everything that spends the blue bar costs less, as if
--     it held 125, 150, 200 and 300%). Running Attacks -> Weapons: one row
--     per weapon type lying in the current area; buying one brings that
--     weapon to where you stand, as often as you like.
--   * Fatalities: a row not discovered yet (its input shows as ???) can be
--     bought, which reveals the input. Every fatality works without being
--     discovered; this sells the knowledge, not the move.
--   * Specials: every move row can be bought twice. The first purchase is
--     the game's (the move, on R2); once that is owned, the row is for sale
--     again as its EX ("Special 2 EX"), in any order. L2 + the move's input (no
--     R2) does an EX move as its EX version, for extra stamina (the blue bar;
--     the red orbs stay the fatality meter). L2 + an input without its EX
--     stays vanilla (block), and L2 + R2 + a button stays free.
-- Skill and Team keep their vanilla rows. See analysis/xp_shop/REPORT.md
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
--   * Fatalities: SyncOwned marks a Fatalities row owned (input shown) when
--     its name text index is in the discovered list at 0x4DF5DC (count
--     [0x4DFC1C], 400 slots), which the fatality handler appends to when one
--     is performed. Nothing in gameplay reads it, and it is saved with the
--     game (save offset 0x5C: the entries after the performed counter). After
--     SyncOwned we price the rows it left unowned; buying one appends its
--     name, so the next sync and every later load show it revealed.
--   * Weapons: the weapon manager at 0x5A3AC0 (built at boot by 0xBE070)
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
--   * EX (analysis/ex_specials/REPORT.md): a special's variant is picked by the
--     move system's condition evaluator 0x1CD780(entity, id), which keeps the
--     condition id in ebp and asks GetLevel (thunk 0x111C2) for its slot.
--     Ids 0x3174-0x3182 are slots 0, 1 and 2, five each: level >= 1 to 4 and
--     == 5 (the top), so a button's move j is picked by the condition on
--     level j (the level its row j buys). While L2 (left trigger: the analog
--     byte at pad state +0xC, 0x63ABD4 + p * 0x16; in the joypad object
--     0x63AC20 + p * 0xE4 the analog bytes from +2 are A B X Y Black White LT
--     RT) is held without R2 and an attack button with an EX bought is
--     pressed (flag level slots 19-22: a bit per move, read by nothing else),
--     the pad-to-action translator 0x129480 (eax = joypad object) gets R2
--     instead of L2, and keeps getting it until L2 is let go, so the game does
--     the special and its whole input chain (a tier-4 fireball is R2 + X, X,
--     X; between the presses plain L2 would be block). Pressing it marks an
--     EX: the evaluator, and only it (by return address), then gets level j
--     for the condition on a move j whose EX is bought (and owned on R2) and
--     0 for any other of those ids, so L2 does exactly the EX moves; its
--     stamina extra comes off when the special spends its own (script
--     command 0x1F1 -> wrapper thunk 0x1406B, once per move), scaled like
--     every cost. Slot 3 (^, with its hidden ==6 variant) is left alone.
--   * An EX row is bought through the combo purchase like the shop's other
--     rows: the game's own special purchase would raise the R2 tier, so for
--     a row on sale as its EX we answer IsSpecial (thunk 0x12B71) no.
--   * Text: the strings are a pointer array at [0x5B04A4] (count [0x5AC508]).
--     We write our strings over unused "(PH)" move-list placeholders, only where
--     they fit, and point our rows at them. Every value we change is remembered,
--     and put back if a reloaded text table no longer has room for ours.
local GAME_MANAGER  = 0x005ACEBC
local GAME_MODE     = 0x88          -- 0 single player, 1 co-op, 2 versus
local XP            = 0x4940        -- XP of player p at +0x4940 + p * 0x50
local PLAYER_STRIDE = 0x50
local LEVELS        = 0x1C4         -- level byte of player p, slot s: +0x1C4 + p * 0x1C + s
local HEALTH_UPS    = 0xE0          -- the game's health-upgrade count, 0-4
local METER_LEVEL   = 0x4978        -- meter level of player p at +0x4978 + p * 0x50
local METER_MAX     = 3
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
local METER_LEVELUP = 0x0001116D    -- the setfatalitylevel script command
local STAMINA_TICK  = 0x00016965    -- Tick(record), fastcall: once per record per frame

local BASIC_TEXT    = 402           -- "Basic Moves" category
local FATALITY_TEXT = 400           -- "Fatalities" category: its leaves hang directly off it
local FATALITY_COST = 5000          -- per revealed input (placeholder until the economy pass)
local FATALITY_HINT = 616           -- (PH) text that becomes the Fatalities category's description
local FAT_LIST      = 0x004DF5DC    -- discovered fatalities: name text indices, saved with the game
local FAT_COUNT     = 0x004DFC1C
local FAT_MAX       = 400
local RUNNING_TEXT  = 405           -- "Running Attacks", the third Basic Moves group
local WEAPON_SLOT   = 2             -- its position in Basic Moves
local WEAPON_TEXT   = 617           -- (PH) texts: the Weapons group's name and description,
local WEAPON_DESC   = 683
local WEAPON_ROWS   = { 684, 693, 694, 696 }   -- a row name per weapon type in the area,
local WEAPON_ROW_DESC = 697                    -- and the rows' shared description
local WEAPON_LABEL  = 16            -- names are padded to this many characters, so a
                                    -- placeholder keeps its room after a short name
local WEAPON_COST   = 2000          -- per summon (placeholder until the economy pass)
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
local EX_FLAG       = 19            -- EX moves: level slots 19-22, one per game slot, a bit per move
local EX_PRICES     = { 5000, 10000, 15000, 20000, 25000 }  -- the EX of move 1-5 (placeholders)
local EX_LEAF_SLOT  = { 0, 2, 1 }   -- Specials group * ~ | -> game slot (^, slot 3, waits for its button)
local EX_COST       = 25            -- extra stamina per EX special, before Stamina upgrades
local GET_LEVEL     = 0x000111C2    -- GetLevel(player, slot), cdecl -> eax
local EVAL_FROM     = 0x001CD780    -- the move system's condition evaluator: GetLevel
local EVAL_TO       = 0x001CE400    -- calls returning in here pick a special's variant
local EX_COND       = 0x3174        -- move conditions: c = id - EX_COND in 0-14 is slot c // 5,
local EX_CONDS      = 15            -- level c % 5 + 1
local SPEND         = 0x0001406B    -- a scripted move spends stamina: (player, cost level), cdecl
local PAD_MAP       = 0x00129480    -- one port's pad -> action bits; eax = its joypad object
local PADS          = 0x0063AC20    -- joypad object of port p at + p * 0xE4
local PAD_OBJ       = 0xE4
local J_LT, J_RT    = 8, 9          -- analog bytes in it: A B X Y Black White LT RT from +2
local LT_MIN        = 0xC0          -- trigger byte that counts as held
-- Attack button (its analog byte) -> the special's game slot. ^ (throw) has
-- no button here until it is confirmed which one it is.
local EX_BUTTONS    = { { 4, 0 }, { 5, 2 }, { 3, 1 } }   -- X -> *, Y -> ~, B -> |
local DEMO          = 0x005143A5    -- 1 in the attract demo: GetLevel reports 1 there
local FRAME         = 0x005CE878    -- frame counter
local EX_WINDOW     = 60            -- frames between the variant pick and its stamina spend

local WEAPON_POPUP  = 698           -- (PH) text that takes our popup message
local POSITION      = 0x80          -- entity position: x, y, z floats
local WEAPON_SIDE   = 150.0         -- the weapon lands this far beside the buyer,
local WEAPON_FLOOR  = 57.0          -- this far below his position (on the floor)
local UPGRADE_TEXT  = 455           -- "Upgrade" in the loaded language tells us which it is

-- Text in the game's code page (cp1252). The "(PH)" placeholders we overwrite
-- are 45-62 bytes in the five built-in languages (English is the shortest).
-- health[3] takes the bonus health and stamina[3] the bar size in percent;
-- fatality is the Fatalities category's description, weapon the Weapons
-- group (name, description, row description, the row when the area has
-- none, the popup message) and weapons the names by weapon object (45 bytes
-- at most, names 16).
local LANGUAGES = {
    { tag = "Upgr", category = { "Upgrades", "Spend EXP on health and stamina." },
      health = { "Health", "Health +%d", "Max health +%d,\non top of the game's.",
                 "Extra health on top of the game's." },
      stamina = { "Stamina", "Stamina +%d", "Stamina %d%%.\nBlocks and specials\ncost less.",
                  "Blocks and specials cost less stamina." },
      fatality = "Buy a ??? fatality's\ninput with EXP.",
      weapon = { "Weapons", "Summon this area's weapons.", "Appears where you buy it.\nThrown, it returns.", "None here",
                 "Weapons for sale here:\nUpgrades > Weapons." },
      weapons = { kama01 = "Kamas", sword = "Sword", broadsword = "Broadsword", axe = "Axe",
                  hooksword01 = "Hook swords", shard = "Shard", shard1h = "Shard" } },
    { tag = "Mejo", category = { "Mejoras", "Gasta EXP en salud y energ\237a." },
      health = { "Salud", "Salud +%d", "Vida m\225xima +%d,\nadem\225s de la del juego.",
                 "Salud extra, adem\225s de la del juego." },
      stamina = { "Energ\237a", "Energ\237a +%d", "Energ\237a %d%%.\nBloquear y especiales\ncuestan menos.",
                  "Bloquear y especiales gastan menos." },
      fatality = "Compra la secuencia de\nun ??? con EXP.",
      weapon = { "Armas", "Invoca las armas de esta zona.", "Aparece donde la compras;\nlanzada, vuelve.", "Ninguna aqu\237",
                 "Armas a la venta aqu\237:\nMejoras > Armas." },
      weapons = { kama01 = "Kamas", sword = "Espada", broadsword = "Mandoble", axe = "Hacha",
                  hooksword01 = "Espadas gancho", shard = "Fragmento", shard1h = "Fragmento" } },
    { tag = "Verb", category = { "Verbesserungen", "EXP f\252r Leben und Ausdauer ausgeben." },
      health = { "Leben", "Leben +%d", "Max. Leben +%d,\nzus\228tzlich zum Spiel.",
                 "Mehr Leben, zus\228tzlich zum Spiel." },
      stamina = { "Ausdauer", "Ausdauer +%d", "Ausdauer %d%%.\nBlock, Spezial\nkosten weniger.",
                  "Blocken und Spezial kosten weniger." },
      fatality = "Kaufe die Eingabe\neines ??? mit EXP.",
      weapon = { "Waffen", "Waffen dieses Gebiets rufen.", "Erscheint am Kaufort,\nkehrt geworfen zur\252ck.", "Keine hier",
                 "Hier gibt es Waffen:\nVerbesserungen > Waffen." },
      weapons = { kama01 = "Kamas", sword = "Schwert", broadsword = "Breitschwert", axe = "Axt",
                  hooksword01 = "Hakenschwerter", shard = "Splitter", shard1h = "Splitter" } },
    { tag = "Pote", category = { "Potenziamenti", "Spendi EXP per salute ed energia." },
      health = { "Salute", "Salute +%d", "Salute max +%d,\noltre a quella del gioco.",
                 "Salute extra oltre a quella del gioco." },
      stamina = { "Energia", "Energia +%d", "Energia %d%%.\nParate e speciali\ncostano meno.",
                  "Parate e speciali costano meno." },
      fatality = "Compra la sequenza\ndi un ??? con EXP.",
      weapon = { "Armi", "Evoca le armi di questa zona.", "Appare dove la compri;\nlanciata, torna l\236.", "Nessuna qui",
                 "Armi in vendita qui:\nPotenziamenti > Armi." },
      weapons = { kama01 = "Kama", sword = "Spada", broadsword = "Spadone", axe = "Ascia",
                  hooksword01 = "Spade uncinate", shard = "Frammento", shard1h = "Frammento" } },
    { tag = "Am\233l", category = { "Am\233liorations", "D\233pensez l'EXP en sant\233 et endurance." },
      health = { "Sant\233", "Sant\233 +%d", "Sant\233 max +%d,\nen plus de celle du jeu.",
                 "Sant\233 en plus de celle du jeu." },
      stamina = { "Endurance", "Endurance +%d", "Endurance %d%%.\nGarde, sp\233ciaux\nmoins chers.",
                  "Garde et sp\233ciaux co\251tent moins." },
      fatality = "Ach\232te la saisie\nd'un ??? avec l'EXP.",
      weapon = { "Armes", "Invoque les armes de la zone.", "Appara\238t o\249 tu l'ach\232tes;\nlanc\233e, revient.", "Aucune ici",
                 "Armes \224 vendre ici :\nAm\233liorations > Armes." },
      weapons = { kama01 = "Kamas", sword = "\201p\233e", broadsword = "Claymore", axe = "Hache",
                  hooksword01 = "\201p\233es crochets", shard = "\201clat", shard1h = "\201clat" } },
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
local area = {}                 -- the weapon objects the Weapons rows sell, row k -> area[k]
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

-- What row k's description shows: the health it adds in total, or the size
-- the stamina bar now plays as.
local function row_figure(kind, k)
    if kind == "health" then return HP_STEPS[k] * HP_TEXT_STEP end
    return BAR[k]
end

-- Whether a weapon object is in the current area: placed at a node or lying
-- as a physics body (only those get the update that respawns them).
local function in_area(w)
    return game.read_u32(w + W_NODE) ~= 0xFFFFFFFF or game.read_u32(w + W_BODY) ~= 0
end

-- The weapon types in the current area: first halves with a model, at most
-- one per row.
local function area_weapons()
    local list = {}
    local n = game.read_u32(WEAPONS + W_COUNT)
    if n > 35 then return list end
    for i = 0, n - 1 do
        local w = WEAPONS + 8 + i * W_STRIDE
        if game.read_u8(w + W_HALF) == 0 and game.read_u32(w + W_MODEL) ~= 0xFFFFFFFF and in_area(w) then
            list[#list + 1] = w
            if #list == #WEAPON_ROWS then break end
        end
    end
    return list
end

-- A weapon's row label in the loaded language (the object's own name if we
-- have none for it), padded to WEAPON_LABEL.
local function weapon_label(lang, w)
    local name = {}
    for i = 0, WEAPON_LABEL - 1 do
        local b = game.read_u8(w + W_NAME + i)
        if b == 0 then break end
        name[#name + 1] = string.char(b)
    end
    local label = lang.weapons[table.concat(name)] or table.concat(name)
    label = label:sub(1, WEAPON_LABEL)
    return label .. string.rep(" ", WEAPON_LABEL - #label)
end

-- Our strings, in the loaded language: true, false if any of them can't
-- fit, nil when the budget ran out first. Checked on every menu open, so a
-- reloaded text table is caught. The order is fixed, so a resumed sync picks
-- up where the last one stopped.
local function place_text()
    local lang = language()
    local all = { { SHOP.category.text, lang.category[1] }, { SHOP.category.desc, lang.category[2] } }
    for _, group in ipairs(SHOP.groups) do
        local words = lang[group.kind]
        all[#all + 1] = { group.text, words[1] }
        all[#all + 1] = { group.desc, words[4] }
        for k, row in ipairs(group.rows) do
            all[#all + 1] = { row.name, string.format(words[2], k) }
            all[#all + 1] = { row.desc, string.format(words[3], row_figure(group.kind, k)) }
        end
    end
    all[#all + 1] = { FATALITY_HINT, lang.fatality }
    local w = lang.weapon
    all[#all + 1] = { WEAPON_TEXT, w[1] }
    all[#all + 1] = { WEAPON_DESC, w[2] }
    all[#all + 1] = { WEAPON_ROW_DESC, w[3] }
    all[#all + 1] = { WEAPON_POPUP, w[5] }
    for k = 1, #area > 0 and #area or 1 do
        local label = area[k] and weapon_label(lang, area[k]) or w[4] .. string.rep(" ", WEAPON_LABEL - #w[4])
        all[#all + 1] = { WEAPON_ROWS[k], label }
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

-- The shop byte a level lives in: Health is shared (player 0's byte), Stamina
-- is per player.
local function shop_addr(m, player, kind)
    return m + LEVELS + (kind == "health" and 0 or player) * 0x1C + SHOP_SLOT
end

local function shop_level(m, player, kind)
    local b = game.read_u8(shop_addr(m, player, kind))
    if b & SHOP_MARK == 0 then return 0 end
    local level = kind == "health" and b & 7 or (b >> 3) & 7
    return level < SHOP_ROWS and level or SHOP_ROWS
end

local function set_shop_level(m, player, kind, v)
    local addr = shop_addr(m, player, kind)
    local b = game.read_u8(addr)
    if b & SHOP_MARK == 0 then b = SHOP_MARK end
    if kind == "health" then b = (b & ~7) | v else b = (b & ~0x38) | v << 3 end
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

-- The Weapons group in a Basic Moves category: Running Attacks, or ours
-- (whose row count follows the area).
local function weapon_group(c)
    local count, list = game.read_u32(c + 0x0C), game.read_u32(c + 0x14)
    local g = WEAPON_SLOT < count and game.read_u32(list + WEAPON_SLOT * 4) or 0
    if not plausible(g) or game.read_u32(g + 4) ~= 1 then return nil end
    local gname, rows = game.read_u32(g + 0x18), game.read_u32(g + 0x0C)
    if (gname == RUNNING_TEXT and rows == #WEAPON_ROWS)
            or (gname == WEAPON_TEXT and rows >= 1 and rows <= #WEAPON_ROWS) then
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
    for _, group in ipairs(SHOP.groups) do
        if gname == group.text then
            for k = 1, #group.rows do
                if game.read_u32(kids + (k - 1) * 4) == node then return "basic", group, k end
            end
        end
    end
    if gname == WEAPON_TEXT and game.read_u32(node + 0x28) == WEAPON_COST then
        for k = 1, #WEAPON_ROWS do
            if game.read_u32(kids + (k - 1) * 4) == node then return "weapon", nil, k end
        end
    end
    if gname == FATALITY_TEXT and game.read_u32(node + 0x28) == FATALITY_COST then
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

-- The Fatalities category under a character root: its leaves hang directly
-- off it, like Skill's (nil when absent or not shaped like that).
local function fatality_node(root)
    local n, kids = game.read_u32(root + 0x0C), game.read_u32(root + 0x14)
    if n > 16 or not plausible(kids) then return nil end
    for i = 0, n - 1 do
        local c = game.read_u32(kids + i * 4)
        if plausible(c) and game.read_u32(c + 0x18) == FATALITY_TEXT then
            local count, list = game.read_u32(c + 0x0C), game.read_u32(c + 0x14)
            if count >= 1 and count <= 16 and plausible(list) then return c end
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

-- A flag byte's EX moves, a bit per move (bit 0 = Special 1). Up to 0.9.0
-- the byte counted them, in order; bit 7 marks the bit form.
local function ex_bits(b)
    if b & 0x80 ~= 0 then return b & 0x1F end
    return (1 << (b < 5 and b or 5)) - 1
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
        -- Weapons: a row per weapon type in the area (one "none here" row
        -- when there is none), always buyable again.
        local g = weapon_group(c)
        if g then
            local rows = #area > 0 and #area or 1
            if not (patch(g + 0x18, WEAPON_TEXT) and patch(g + 0x1C, WEAPON_DESC) and patch(g + 0x0C, rows)) then
                return false
            end
            local kids = game.read_u32(g + 0x14)
            for k = 1, rows do
                local node = game.read_u32(kids + (k - 1) * 4)
                if plausible(node) and not (patch(node + 0x18, WEAPON_ROWS[k]) and patch(node + 0x1C, WEAPON_ROW_DESC)
                        and patch(node + 0x28, #area > 0 and WEAPON_COST or 0) and patch(node + 0x2C, 0)) then
                    return false
                end
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
    local fat = fatality_node(root)
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
    area = area_weapons()                                  -- the menu is paused: stable while it syncs
    local placed = place_text()
    if placed == false then ready = false; unpatch() return end
    if placed == nil then resume = true return end
    ready = true
    local root = menu_root(m, blob)
    if root and not patch_root(m, root) then resume = true end
end

-- Row k's weapon is still in the area and nobody holds it.
local function weapon_free(k)
    local w = area[k]
    return w ~= nil and in_area(w) and game.read_u32(w + W_HOLDER) == 0
end

-- The row is the next to buy in its store (a fatality: not discovered yet,
-- with room in the list), affordable, and its cost really is ours.
local function can_buy(node, kind, store, k)
    local m = manager()
    if m == nil then return false end
    local cost = (kind == "fatality" and FATALITY_COST) or (kind == "weapon" and WEAPON_COST)
        or (kind == "ex" and EX_PRICES[k]) or store.rows[k].cost
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
        local player, w = menu_player(), area[k]
        if player == nil or w == nil or not in_area(w) then return end
        local at = ENTITY + player * ENTITY_STRIDE + POSITION
        local x, y, z = f32_to(game.read_u32(at)), f32_to(game.read_u32(at + 4)), f32_to(game.read_u32(at + 8))
        if x == nil or y == nil or z == nil then return end
        local home = { f32_from(x + WEAPON_SIDE), f32_from(y - WEAPON_FLOOR), f32_from(z) }
        local parts = { w }
        local half = game.read_u32(w + W_NEXT)
        if plausible(half) then parts[2] = half end
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
    if shop_level(m, player, store.kind) ~= k - 1 then return end
    set_shop_level(m, player, store.kind, k)
    if store.kind == "health" then
        ensure_health(m)
    else
        ensure_stamina(m, STAMINA + player * STAMINA_STRIDE)
    end
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
    for k = 1, #area do
        if weapon_free(k) and xp >= WEAPON_COST then afford = true end
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

local ex_player, ex_from = nil, nil  -- GetLevel's player and caller
local ex_due = {}               -- [player + 1] = frame an EX was pressed; stamina due
local ex_held = {}              -- [player + 1] = the attack byte of the EX press still held
local ex_chain = {}             -- [player + 1] = true while an EX chain keeps L2 as R2
local spender = nil             -- player passed to the stamina-spend wrapper

-- After GetLevel: the move system asks whether a special's move may be
-- picked (its condition id in ebp). During an EX chain, a move of buttons
-- * ~ | passes only if its EX is bought (and it is owned on R2): it gets
-- exactly its level, any other gets 0. The stamina comes off when the move
-- spends its own.
local function boost_level(ctx)
    local player, from = ex_player, ex_from
    ex_player = nil
    if player == nil or from < EVAL_FROM or from >= EVAL_TO or player > 1 then return end
    if not ex_chain[player + 1] then return end      -- the whole EX chain, follow-ups too
    local c = ctx.ebp - EX_COND
    if c < 0 or c >= EX_CONDS then return end
    local m = manager()
    if m == nil or game.read_u8(DEMO) == 1 then return end
    local slot, level = c // 5, c % 5 + 1
    local bits = ex_bits(game.read_u8(m + LEVELS + player * 0x1C + EX_FLAG + slot))
    local pass = bits & (1 << (level - 1)) ~= 0 and ctx.eax & 0xFF >= level
    ctx.eax = (ctx.eax & 0xFFFFFF00) | (pass and level or 0)
end

-- Before a port's pad becomes action bits: L2 (without R2) + an attack
-- button with an EX bought becomes R2 + that button, so the game does
-- the special, and L2 stays R2 until it is let go, so the special's input
-- chain (X, X, X) goes through; each press marks an EX when the stamina
-- covers the extra. Anything else passes untouched.
local function ex_remap(obj)
    local off = obj - PADS
    if off < 0 or off % PAD_OBJ ~= 0 or off // PAD_OBJ > 1 then return end
    local player = off // PAD_OBJ
    local m = manager()
    if m == nil or game.read_u8(DEMO) == 1 or player >= game.read_u32(STAMINA_COUNT) then return end
    if game.read_u8(obj + J_LT) < LT_MIN then              -- L2 let go: the chain is over
        ex_chain[player + 1], ex_held[player + 1] = nil, nil
        return
    end
    if game.read_u8(obj + J_RT) ~= 0 then return end        -- L2 + R2 stays the game's
    local held = ex_held[player + 1]
    if held and game.read_u8(obj + held) == 0 then ex_held[player + 1] = nil; held = nil end
    for _, b in ipairs(EX_BUTTONS) do
        if game.read_u8(obj + b[1]) ~= 0 and game.read_u8(m + LEVELS + player * 0x1C + EX_FLAG + b[2]) ~= 0 then
            if held == nil then                     -- a new press: EX if the stamina covers it
                local have = f32_to(game.read_u32(STAMINA + player * STAMINA_STRIDE + STAMINA_NOW))
                local paid = have ~= nil and have >= ex_cost(m, player)
                if not paid and not ex_chain[player + 1] then return end   -- not even a chain: block
                ex_held[player + 1] = b[1]
                if paid then ex_due[player + 1] = game.read_u32(FRAME) end
            end
            ex_chain[player + 1] = true
            break
        end
    end
    if ex_chain[player + 1] then
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

local function set_al(ctx, v)
    ctx.eax = (ctx.eax & 0xFFFFFF00) | v
end

return {
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
            -- category's "anything to buy" search hear it.
            if kind == "fatality" and from ~= ASKED_TO_BUY and from ~= ASKED_FOR_ANY then return end
            if kind == "weapon" and from == ASKED_FOR_VIDEO then return end
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
        address = METER_LEVELUP,
        after = function(ctx)
            local m = manager()
            if m == nil then return end
            for player = 0, 1 do
                local addr = m + METER_LEVEL + player * PLAYER_STRIDE
                if game.read_u32(addr) > METER_MAX then game.write_u32(addr, METER_MAX) end
            end
        end,
    },
    { address = RESPAWN, before = function(ctx) respawning(ctx.ecx) end },
    { address = PAD_MAP, before = function(ctx) ex_remap(ctx.eax) end },
    {
        address = GET_LEVEL,
        before = function(ctx)
            ex_player, ex_from = game.read_u32(ctx.esp + 4), game.read_u32(ctx.esp)
        end,
        after = function(ctx) boost_level(ctx) end,
    },
    {
        address = SPEND,
        before = function(ctx) spender = game.read_u32(ctx.esp + 4) end,
        after = function(ctx) charge_ex() end,
    },
    { address = MOVES_OPEN, before = function(ctx) arm_popup() end, after = function(ctx) disarm_popup() end },
    {
        -- Once per stamina record per frame: keep that player's costs scaled,
        -- (on player 0's record) the shop's health on top, and afterwards
        -- scale what the sustained drain took.
        address = STAMINA_TICK,
        before = function(ctx)
            ticked = nil
            local m = manager()
            if m == nil then return end
            local rec = ctx.ecx
            ensure_stamina(m, rec)
            if rec == STAMINA then ensure_health(m) end
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
