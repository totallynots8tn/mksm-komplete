# Shaolin Monks roster: what we know about every character

Everything the mods need to use Mortal Kombat characters: as extra enemies
(LDK, Shaolin Shuffle), as rift bosses (Time Rifts), and later as playable or
versus fighters the way UMKSM does on PS2. Gathered on 2026-11-01 from the
earlier roster work, the UMKSM analysis, the XP Shop and Time Rifts research,
QA runs, and new disassembly.

- `roster.csv`: one row per character type (0-90), the full table.
- `roster.json`: the same, plus every map's preload list and the dev menu's
  boss battles.
- `roster.lua`: `type -> { name, role, slots, instances }`, ready for a mod.
- `build_roster.py`: rebuilds all three from `default.xbe`, the ISO's
  GAMEDATA.WAD and the mod sources. Run `python analysis/mk_roster/build_roster.py`;
  the output is identical every run.

Each fact is marked **live** (seen in a QA run), **static** (disassembly or game
data) or **guess**.

## 1. Correction: the old character names were two types off

The type numbers our mods use were always right. The **names** were not. The
character table stores WAD file ids, and the game's file id `F` is record
`F - 0x14` in `pwf.py` (20 records = two characters' file groups). The old
dump (`analysis/xbox_roster/characters.json`, `REPORT.md`) read record `F`, so
every name it gives belongs to the type two numbers up. **Static**, five
independent checks:

1. **Liu Kang's and Kung Lao's files.** Type 0's model id `0x17A1` minus
   0x14 is the group that ends in `liukang_sf.dat`; type 1's ends in
   `kunglao_sf.dat`. Unshifted, both point at empty records.
2. **Boss arenas preload their boss.** The dev menu's battles (§3.8):
   - Goro battle: map 47 preloads 57;
   - Baraka battle: map 15 preloads 56;
   - Kitana/Mileena/Jade battle: map 195 preloads 65, 66 and 67;
   - Mileena's secret arena: map 132 preloads 66.

   With the shift these are exactly Goro, Baraka, Kitana, Mileena and Jade.
   With the old names they were Reptile, Kintaro, Jade/Ermac/Sub-Zero and Ermac.
3. **Size.** The only two 2-slot types, 47 and 57, are both Goro.
4. **Move menu.** The XP Shop's menu roots for Scorpion (0x52) and Sub-Zero
   (0x58) are types 82 and 88. Those are Scorpion and Sub-Zero models with full
   player animation sets (1.6 MB and 1.2 MB). The old names said Reptile and
   nothing.
5. **Sound banks.** The per-character sound table (§3.2) agrees with every
   model, shifted the same way.

What was wrong because of it, all fixed on this branch:

- **Time Rifts 0.7.x "Mileena" (64) was Shao Kahn**, and its "Johnny Cage"
  (76) is a generic humanoid grunt (the Goro's Lair screenshot that was taken
  for Johnny Cage showed a monk). 0.8.1 drops Mileena (66), then Johnny Cage
  (78).
- The boss lists in `core.lua` (shared by LDK and Shuffle) had wrong labels,
  and real Mortal Kombat characters were missing. The lists only grew:
  - LDK 3.11.2 and Shuffle 0.11.5 add Kintaro, Sub-Zero, Smoke, Raiden, Jax,
    Johnny Cage and the versus models.
  - Two old entries were listed under wrong names: 28 is a bladed humanoid
    (with the 2-instance limit bosses have) and 34 an archer. LDK and Shuffle
    still never touch them; review that later.
- "Ermac 66 in map 132's preload" (an earlier QA note) is Mileena.

## 2. Quick reference: the Mortal Kombat characters

Mortal Kombat characters all take 1 memory slot, except Goro (2). NPC and
boss rows have `instances` = 2; player and versus rows have 1 (§3.1).

| Character | NPC / boss type | Playable / versus type | Vanilla fight or appearance (maps that preload it) | UMKSM tier |
| --- | --- | --- | --- | --- |
| Liu Kang | | **0** (player) | | 0 |
| Kung Lao | | **1** (player) | | 0 |
| Scorpion | **52**, 55 (burned) | **82** (playable) | Scorpion battle 160 (both NPC types); 52 also 190; 55 also 165 | 0 |
| Sub-Zero | **69** | **88** (playable) | final battle 73; maps 44-46, 190 | 0 |
| Baraka | **56** | 83 (versus) | Baraka battle 15; 161 | 1 |
| Reptile | **59** | 84 (versus) | Reptile battle 144; 164, 190 | 1 |
| Kitana | **65** | 89 (versus) | Kitana/Mileena/Jade battle 195; 194 | 1 |
| Johnny Cage | **78**; 71 (story); 86 (stone) | 90 (versus) | 86 in the Ermac battle 108; 71 in 47, 104, 106; 78 nowhere | 1 |
| Ermac | **68** | 85 (versus) | Ermac battle 108; 190 | 1 |
| Mileena | **66** | | secret arena 132; battle 195 | 2 |
| Jade | **67** | | battle 195 | 2 |
| Noob Saibot | **53** | | not preloaded anywhere (scripted spawns) | 2 |
| Smoke | **70** | | 146, 147 | 2 |
| Kano | **54** | | 72, 187 | 2 |
| Raiden | **72** | | 41, 96 | 2 |
| Jax | **74** | | 72 | (UMKSM story extra) |
| Shang Tsung | **62** young, 63 old | | final battle 73 (young); 169 (old) | 2 |
| Shao Kahn | **64** | | final battle 73 | 2 |
| Goro | **57**, 47 (mace) | | Goro battle 47 (57); 191 (57); 176 (47) | |
| Kintaro | **58**, 81 (morning star) | | not preloaded | 2 |

Other bosses: Orochi **30** (Time Rifts' Wu Shi boss, **live**), Oni
Warlord **36** (**live**: Time Rifts 0.5.7 dropped it, and it leapt the fence).

Being authored once in an area doesn't mean a character appears there. The
probe's censuses (**live**) show the same one-entry groups in unrelated areas
(types 2, 20, 27, 30, 36, 46, 48, 51, 57, 63). A rough parse of the spawn
files (**guess**-level) finds most of them in every map's file, so they look
like a shared block. An older note read them as "Kitana, Noob, Reptile" with
the old names.

## 3. Data structures

### 3.1 Character table `0x4FA9F0`: 91 rows × 0x30 (writable .data)

| Offset | Field |
| --- | --- |
| `+0x00` | `0x20004 + type` |
| `+0x04` | memory slots (1; 2 for Goro 47 and 57) |
| `+0x08` | **instances**: 1 for player and versus rows, 2 for Mortal Kombat characters, 2-20 for grunts, 34 and 66 for swarms (tentacles, skulls) |
| `+0x0C` / `+0x10` | model / textures (file ids) |
| `+0x14` / `+0x18` | alternate model / textures (player and versus rows) |
| `+0x1C` | effects file |
| `+0x20`-`+0x2C` | costume 2 and 3 pairs (read by the versus loader) |

Readers (**static**):
- `SetCharacterFiles 0xC26B0` (thunk `0x140D4`, hookable) loads a player:
  - alternate costume when `0x5AC4FD` / `0x5AC4FE` is set;
  - for P1 only, also the 3 sound files from §3.2.
- `0xC3250(slot, type)` loads an enemy slot: VRAM `0x5062AC + slot*4`, sound
  bank `0xA + slot`.
- The versus loader `0x22C70(slot, type, costume)` reads `+0x20`-`+0x2C`.

`+0x08` goes to `0xC1DB0`, which queues the load (request record
`0x5AB308 + n*0x20`, field `+0x1C`, callback thunk `0x1256D`). **Guess:** it is
how many model instances the slot is built for. If so, spawning more live
copies of a type than this fails. That would explain LDK's soft-locks when it
cloned Mortal Kombat bosses (`instances` = 2) into waves: the wave waits for
spawns that never come. Worth one test before any mod spawns several copies
of a Mortal Kombat character.

### 3.2 Sound table `0x4F9EA0`: 91 rows × 0x20

`{ bank header, sound font (*_sf.dat), voice archive (AFS), flag }`, as file
ids. Read at `0xC2796` for P1. The sound font's name identifies the character
(`roster.csv` column `sound_bank`). Noob Saibot, Smoke, Raiden and Johnny
Cage 78 have none of their own.

### 3.3 Files in GAMEDATA.WAD

Each type owns a run of 10 records (12 for the players), in this order:
1. effects;
2. two empty records;
3. textures;
4. model (EWDF, "PS2.bin");
5. "DT2" and "DAT" data;
6. animations (`nim.rtt`);
7. sound bank header, then sound font.

Record index = file id − 0x14. Animation sizes show which rows can be played
(**static**):
- player and versus rows: 0.8-1.6 MB of animations;
- NPC rows: 0.2-0.8 MB;
- Noob 53 and Johnny Cage 78: no animation record in their run. Where they
  get theirs is an open question.

### 3.4 Players

- **Character ids:** P1 `[0x5ACEBC]+0xCC`, P2 `+0xD0` (getter `0xC4850`, thunk
  `0x15358`).
- **Readers:** the player loader `0xC2AA5` compares them with what's loaded,
  then calls `SetCharacterFiles`.
- **Writers:**
  - the dev menu handler `0x52A30` (writes the selected item's value; items are
    8 bytes at `[menu+0x54]`, value at `+4`, selection `[menu+0x6C]`, -3 =
    special);
  - map setup `0x44530`;
  - front-end code `0x45811`, `0x50F8B` and `0x5140C`.
- **Character select:** in this game it is menu data, a type per menu item,
  not a list in the code. The versus select menu's record isn't decoded yet.

### 3.5 Entities and health

- **Entities:** 12 at `0x5D1AB8`, stride `0x3238`; in-use u16 flags at
  `[0x51004C]`.
- **Fields:**
  - `+0x1DFE` type (kept after death);
  - `+0x68` player index;
  - `+0x80/+0x84/+0x88` position (y grows downward; writing it doesn't stick);
  - `+0x200` actor.
- **Health:** actor `+0x368`, maximum `+0x370`. `setHealth 0x153CD0` (thiscall,
  actor in ecx, the new health at `[esp+4]`) is how Time Rifts 0.8 sees a boss
  beaten.

### 3.6 Loading a character during play (**live**)

- **Memory:** 4 character slots (`0x6322F8`: `+0x10` count, `+0x24` rows of 20
  bytes `{heap, type, firstBlock, nBlocks, flags}`). `LOADED_TYPES 0x6CA69C[6]`
  holds P1, P2 and the 4 slots.
- **Preload list:** map descriptor `+0x24` (cap `+0x20`); a before-hook on
  `0x15DEE` can change it. Never remove a listed type: scenes place listed
  characters outside the spawn groups (Shuffle 0.11.2 crashed on that).
- **Spawning a type that isn't loaded:** the game streams it in on the spot,
  only into a free slot (`0x16C550` → make-resident `0x17B460`, hookable).
- **Swapping a type into a slot:** the `modelstream` command `0x17BA00` queues
  `(slot, type)` for `0x17BA40`, which evicts the slot and loads the type.
  Time Rifts loads its bosses this way (through callgate).

### 3.7 Boss events: why a Mortal Kombat boss can't die (**static**)

Every actor starts killable. Actor init (`0x153450`) sets `+0xD4 = 1` (and a
placeholder 666 health at `+0x368`). `TakeDamage` (`0x153E20`, thiscall, actor
in ecx) does this:
- **Hit:** it saves the old health at `+0x36C`, calls `setHealth(old -
  damage)`, and tells the actor's AI (`+0xCC`).
- **Health would reach 0:** if `+0xD4` is 0, or the AI overlord's no-kill flag
  is set (`[0x1836C0(0)] + 0x32C`, for scripted moments), health is set back
  to **1** and the AI gets event `0x400000` ("near death", `0x195F50`).
- **Otherwise:** the actor dies (`0x153700`).

**The per-character AI setup** is a switch on the type: `0xE2F11`, jump
table `0xE8CE8`, types 2-86. It sets each character's health, AI tuning and
flags. For these types it writes `+0xD4 = 0`:
- Goro 47 and 57;
- Scorpion 52 and 55;
- Kano 54, Baraka 56, Kintaro 58, Reptile 59;
- Shang Tsung 62, Shao Kahn 64;
- Mileena 66, Jade 67, Ermac 68, Sub-Zero 69;
- Johnny Cage 71, Jax 74;
- plus 19 and 29.

Their story fights end by script. `roster.csv` column `killable` is rebuilt
from this switch.

These start killable: Noob 53, Kitana 65, Smoke 70, Raiden 72, Johnny Cage 78,
Orochi 30, Oni Warlord 36 and the versus rows. (Orochi's and the Warlord's
cases write a different object's `+0xD4`: their AI's.)

**The map scripts' AI commands** are registered by name (`0x16F970`; events
through `0x16D710`, conditions through `0x16D700`):
- **Events:**
  - `cankill` (exec `0x1DE520`: its target is entity `0x5D1AB8 +
    [a1+0x10] * 0x3238`, a2's value goes to the actor's `+0xD4`);
  - `aionoff`, `setaito`, `setdefense`, `setaidiff`;
  - `startneardeath` / `stopneardeath`, `changephase`;
  - `despawnai`, `despwntrigai`, `changebehavior`;
  - `aisetattribute` / `airemoveattribute`, `aisetinterdist`,
    `aisetloopdist`.
- **Conditions:** `characterdead`, `bossentersphase`, `charactertype`,
  `squaddeath`.

A boss fight is a map's triggers using these. The boss can't die, a phase
condition fires, then a cutscene plays and the boss is despawned. Mileena
leaving with Kitana in map 132 is one.

**Using a Mortal Kombat boss outside its fight** means setting `+0xD4` back
to 1 on the actor you spawned, every frame it's up (the AI setup and map
scripts may write it again). Leave vanilla fights alone, or their endings
may never play:
- Time Rifts 0.8.2 does this for its boss;
- Shaolin Shuffle 0.12 does it for its warriors.

### 3.8 Spawning and maps

- **Spawn entries:** 0x74 bytes in memory (0x60 in the map's spawn file);
  `+0x00` is the type.
- **Spawn path:** `0x1D1D40` hands the entry's type straight to actor creation
  (`0x16C550`, character pool `0x510040`).
- **Starting a group:** manager `0x6DBFB0`, thiscall `0x1D2600(group, -1, 0)`
  (callspawn style: integer world coordinates at `+0x18..+0x20`).
- **Behaviour fields:**
  - `+0x10`, `+0x24`, `+0x58`, `+0x5C` (initial AI state), `+0x60`, `+0x70`
    (see `signature()` in `core.lua`);
  - `+0x6C` (1000) is copied to AI `+0x1EC` when it isn't 1000.
- **Maps:** descriptor table `0x5020E8` (lookup `0x172F60`).
  - `+0x20` preload cap, `+0x24` preload list, `+0x44` map number, `+0x7C`
    spawn file.
- **Dev menu `0x4E6050`:** label and map pairs:

| Battle | Map |
| --- | --- |
| Ermac | 108 |
| Reptile | 144 |
| KMJ (Kitana, Mileena, Jade) | 195 |
| Baraka | 15 |
| Goro | 47 |
| Scorpion | 160 |
| Final (Shao Kahn) | 73 |

  The level starts are Wu Shi 103, Evil Monastery 192, Tombs 30 and Forest 128.

## 4. Recipes for the mods

### 4.1 A Mortal Kombat character as an extra enemy (LDK, Shuffle, Boss Invasion)

**Built:** Shaolin Shuffle 0.12's Mortal Kombat warriors (offline sims pass,
not played yet):
- about one in three outsider areas gets a warrior, two per area, one per
  room;
- each warrior is made killable;
- a spawn that would exceed the slot's two copies goes back to the room's
  own enemy.

What the warriors are built on:

- **What already works (live):**
  - type 76 (a monk-like grunt) fought and died in Goro's Lair;
  - Shuffle's outsiders stream into other areas.
- **One-slot types only.** Never Goro 47 or 57.
- **Rows `role = mk` are bosses** to `core.lua`: never cloned or shuffled.
  Keep it that way until the instance limit (§3.1) is understood.
- **Load:** stream with `modelstream` into a slot nobody alive uses (Time
  Rifts' `free_slot()`), or append the type to the preload list before
  `0x15DEE` reads it.
- **Spawn:** give it its own group and mark it `RIFT` (group `+0xA10`) so LDK
  and Shuffle leave it alone.

### 4.2 A Mortal Kombat character as a rift boss (Time Rifts)

- **The recipe (live, map 110):**
  1. stream the type in;
  2. write a one-entry group at the boss spot (y lifted 64);
  3. mark it `RIFT` and start it like callspawn;
  4. judge by `setHealth`.
- **Spawn near the player:** the game removes enemies spawned far away (62,000
  units was too far, **live**). The limit is unknown; 0.8.1 drops Mileena only
  within 1,500 units and logs the distance.
- **Make it killable:** set `+0xD4` back to 1 every frame it's up (§3.7).
  Mileena is unkillable by default; Time Rifts 0.8.2 does this.
- **Unknown:** the boss health bar and scripted phases. A probe capture of a
  vanilla boss fight (Mileena's in map 132 is the obvious one) is the next
  research step.

### 4.3 Playable and versus Mortal Kombat characters (UMKSM-style)

UMKSM (PS2, V2.6) puts Noob Saibot, Mileena, Raiden and others in story and
versus mode. What its files show (analysis in the main checkout,
`analysis/umksm_port/REPORT.md`):
- **No code in the cheat file:** the movesets are in a rebuilt game ELF.
- **Character table remaps:** the cheat file rewrites the character table.
  Versus mode fills enemy costume slots; story mode rewrites rows 68, 84 and
  88 for the chosen character. Those are PS2 row numbers; check them against
  this table before reusing anything.
- **Three tiers:**
  - tier 0: the base four;
  - tier 1: the versus characters, with fatalities;
  - tier 2: "extra NPC" characters that "can't do much but just Kombat".
- **Rain and Kajin** are skins on Noob's model.

On Xbox, three levels, cheapest first:
1. **Model swap onto a playable row.**
   - **How:** write the NPC's model and texture ids (and the alternate pair)
     into a player or versus row before `SetCharacterFiles` runs. A
     before-hook on thunk `0x140D4` sees the type.
   - **Example:** Noob 53 is model `0x19B7` / textures `0x19B6`. Scorpion's
     playable row 82 is model `0x1AD9` / textures `0x1AD8` (alternate
     `0x1B3C` / `0x1B3B`).
   - **Result:** that row's moves and animations with the new look, if the
     skeletons match. The ninjas share `sc_01`..`sc_05`; most humanoids share
     the `l_`/`r_` bone names. **Static**, untested.
2. **The NPC row as the player.** Write P1's id `[0x5ACEBC]+0xCC` before the
   player loader runs, or rewrite the type argument in the `0x140D4` hook. The
   player gets the NPC's own animations, but the move menu only has roots for
   0, 1, 82 and 88, so expect tier 2 at best. One live test (it needs a memory
   write, so ask first).
3. **Versus roster.**
   - `VSModeManager` (`0x21EE0`-`0x23080`) loads fighters through `0x22C70`;
     the select values are menu data.
   - **Next step:** find the versus select menu's record and add items whose
     value is an NPC type.
   - **Combine with 1** to show the NPC on a row that has full moves.

Names on screen (rift boss names, a lore prompt) can use the text-bank rewrite
the XP Shop already uses.

## 5. Open questions, cheapest test first

1. **Instance limit:** does `+0x08` cap live copies of a type? It goes to
   `tgtProcessObjectModel` (`0x113B50`) as the model copy count (**static**).
   Shuffle 0.12 guards it either way; a live count would settle it.
2. **Spawn distance:** how far from P1 may an enemy spawn before the game
   removes it? Time Rifts 0.8.1's `near@` and `gone@` notes give the first
   numbers.
3. **Boss health bar and phases:** what shows them in a vanilla boss fight?
   Capture Mileena's vanilla fight in map 132 with the probe.
4. **Versus select menu data:** item values are types; find the record.
5. **Type 66 as P1:** load it as P1 once (live write, ask first).
6. **Animations:** where do Noob 53, Johnny Cage 78 and Smoke 70 (33 KB) get
   theirs?
7. **Unnamed types:** 2, 3, 5, 6, 21-24, 29, 32, 33, 37-39, 51, 60, 61, 73, 75
   and 79. A probe line naming the type of each enemy on screen, plus a
   screenshot, settles them; then add them to `CURATED` in the build script.

## 6. Sources

- `analysis/xbox_roster/REPORT.md`: character loading, the stream gate, the
  preload hook (its character names are two off; see §1).
- `analysis/xp_shop/REPORT.md`: the move menu and its character roots.
- `analysis/time_rifts/INVESTIGATION.md` and
  `mods/_build/src/time_rifts_body.lua`: the boss drop, verdicts and live
  results.
- `mods/_build/src/core.lua`: boss and outsider lists, spawn signatures and
  memory rules.
- Main checkout `analysis/umksm_port/REPORT.md` and
  `UMKSM VERSION II 2.6/readme - UMKSM V.2.txt`: what UMKSM changes.
