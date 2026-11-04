# Rift scouting: Smoke's secret area and the survival maps

Scouted 2026-11-03 from the running game (P1 in Smoke's secret area) and the
game files. No rift goes in this room; this records what the room and its
neighbours give the mods. Map numbers are the game's own (the map table index,
what `CURRENT_MAP` 0x505970 and `loadmap` use).

## How the maps are named

A map descriptor (map table 0x5020E8 + map × 4) holds two name pointers:
`+0x18` is the designers' name ("Forest - Map 19") and `+0x1C` reads "This is
map N + 1". The designers counted from 1, and so does the **`loadmap` trigger
command**: its first argument is the designers' number, one more than the map
table index that `CURRENT_MAP` and the load request (0x4FC160, which Time
Rifts writes) hold. Confirmed live: Smoke's `loadmap_147to75` (75) put the
user in map 74. So a trigger's `mapA_to_B` reads in designer numbers.

## Smoke's secret area (maps 146 and 147, "Forest - Map 19/20")

| What | Detail |
| --- | --- |
| Where | P1 stood at (84651, 39, -4227) on map 146, facing 1184 |
| Memory | 3 slots, all used by the map's preloads: Smoke 70, tree mouth 42, type 17 |
| Smoke | Type 70, spawned by spawn group 15 at (83837, 32, -1476). He keeps the placeholder health 666 an actor starts with: an NPC that is never meant to be fought. |
| Tree mouth | Group 16 at (97769, 7, -1244): the area's own, not a Shuffle outsider |
| Type 17 | Groups 17-19 author it at three spots (82806/92021/100061). Not up while we looked; still unidentified. |
| Map 147 | The same area without a spawn file, with its own triggers |

**Smoke's quests are trigger commands.** The area's trigger file (record 0xF0C)
runs the whole chain:
- `smokeknown N` and `smokecomplete N` (N = 0-4) track the five quests.
- `messagetext` shows the lines. Quest intros use type 5 (a speaker line), and
  descriptions and rewards use type 0. The texts are:
  - 0x12: the intro, "Only through completing these tasks...";
  - quest 1: 0x13-0x15;
  - quest 2: 0x45-0x47;
  - quest 3: 0x5E-0x60;
  - quest 4: 0x94-0x96;
  - quest 5: 0xB0-0xB2;
  - all done: 0x61, "You have unlocked MK2".
- `addexperience 500` / `700` pays the quest rewards. Its exec is thunk
  0x13A53 (body 0x74AC0): with the target a "char" object (index at +0x10), it
  adds `args[0]` XP to that player through the XP getter and setter (thunks
  for 0x7BB00 and 0x7BB20, 1-based player). In single player it also credits
  the other player entity.
- `unlockmk2` (exec thunk 0x16339) gives the final reward.
- `freezetime 300` (exec 0x1A2530) only writes the frame count to 0x6C0400
  and 1 to 0x6C0404, so a mod can start it with two writes. Its effect isn't
  seen yet.
- `gameevent` 54, 98, 105 and 114 on; `animstreaminit` / `animstreamplay`
  for a cinematic; `spawnexperience` (exec thunk 0x134F9) drops XP.
- Its `loadmap`s (designer numbers): `loadmap_147to75` is quest 5's portal
  to the Pit II (map 74); `map147_to_131` goes to map 130; `map05_to_01` to
  map 0.

## The Pit II (map 74, "Foundry - Map 11")

Quest 5's survival, read live with the user in it: 4 memory slots, all with
memory (captain 10, general 11, handler 13, type 39), and ten waves (groups
15-24) of captains, handlers and generals. Entries are 20 frames apart within
a wave, with stragglers up to 980 frames late. Its exit is
`loadmap_75to147` back to Smoke's area (map 146, entry 2), and it sets game
event 115.

## The survival maps (161-191)

Descriptors named "Survival N" preload Mortal Kombat bosses together, with
spawn files that drop them. Their memory slots are laid out for those
characters, so nothing has to be swapped:

| Map | Name | Preload | Spawns (type: count) |
| --- | --- | --- | --- |
| 161 | Survival 2 | 56, 14, 26 | Baraka 1, Tarkatan 6, mask guard 2 |
| 162 | Survival 3 | 10, 11, 12, 13 | captain 6, general 3, archer 6, handler 3 |
| 163 | Survival 4 | 15, 36 | Oni 12, Oni Warlord 2 |
| 164 | Survival 5 | 59, 8 | Reptile 1, corpse 6 |
| 165 | Survival 6 | 30, 55 | Orochi 3, burned Scorpion 1 |
| 166 | Survival 7 | 17, 4, 42 | clay soldier 12, type 17 6, tree mouth 1 |
| 169 | Survival 10 | 63, 27 | Shang Tsung 1, priest 8 |
| 187 | Survival 28 | 54, 9 | Kano 1, type 9 6 |
| 190 | Survival 31 | 59, 68, 69, 52 | Reptile, Ermac, Sub-Zero, Scorpion: one each, one group |
| 191 | Survival 32 | 57, 58 | Goro and Kintaro, one group |

They form one gauntlet, in designer-numbered `loadmap`s from stage to stage:

**Survival 2 → 3 → 4 → 5 → 6 → 7 → 28 → 32 → 31 → 10**, then out (map 0 or
map 3).

Its door is `map65_to_162` in Foundry - Map 1 (map 64). Map 193 (Evil
Monastery - Map 2) also has `map194_to_161`, a load into map 160, the Scorpion
battle.

Every stage with a Mortal Kombat boss runs its own **`cankill_boss`**
(`cankill 1`): Survival 2, 5, 6, 28, 31, 32 and 10. So the game itself makes
those bosses killable there, unlike in any other map. Survival 28 also sets
game event 119, and Survival 10 sets 37.

The versus arenas sit among them (170-185: The
Wastelands, The Kombat Crag, The Pit 172, The Dead Pool, Kombat Tomb, The
Portal, Goro's Lair 176 with the mace Goro 47, The Tower, The Living Forest,
Warrior Shrine, Rooftops, The Ice Falls, Kahn's Arena 182 with Shao Kahn,
Wu-shi Arena, Shokan Shrine, The Armory). Most carry the same placeholder
spawn file as Smoke's area (Smoke 1, tree mouth 1, type 17 ×3).

**Live test, 2026-11-03:** a load request written from the Pit II (map 190, entry 0, portal flag 1, as the stages' own links) put P1 in Survival 31 within 6 s. Its one group spawned Reptile (850), Ermac (800), Sub-Zero (850) and Scorpion (900) around P1, all with +0xD4 = 1, and they attacked at once. Its 4 memory slots hold exactly those four. When it is won, its own trigger loads Survival 10.

**Live tour, 2026-11-03 (user playing):**
- **Survival 31:** loaded from the Pit II (entry 0). Won, its own exit dropped the user in the Foundry (map 64, the Fundición), not in Survival 10.
- **Survival 2:** loaded from the Foundry (entry 1, as its door): Baraka, Tarkatans and mask guards, all killable.
- **Survival 3:** won, Survival 2's own link (designer 163, entry 0) **crashed during the load**, a null read at +0x7EC in the camera manager (GameMapSetup 0xD25B0 -> GameCameraManager 0x59E9F/0x58685 -> pxCameraManager). The camera that entry needs doesn't exist. Either the stage is unfinished or entry 0 has no camera there; entry 1 is untried.

**Stage tour, 2026-11-03** (load requests from the running game, user playing):

| Stage | Map | Entry | Result |
| --- | --- | --- | --- |
| Survival 2 | 161 | 1 | OK: Baraka, Tarkatans, mask guards |
| Survival 3 | 162 | 1 | OK: captains, archers, handlers (generals loaded), 12 waves. Entry 0 crashed in the camera setup |
| Survival 4 | 163 | 1 | OK: 2 Oni Warlords, 6 Oni |
| Survival 5 | 164 | 1 | **broken**: P1 lands at a fallback (0, 0, 5000), Reptile far below; its scene has no camera tags at all |
| Survival 6 | 165 | 1 | OK: burned Scorpion, an Orochi. Entry 0 crashed in the camera setup |
| Survival 7 | 166 | 1 | OK: clay soldiers, tree mouths, type 17, 13 waves |
| Survival 28 | 187 | 1 | OK: Kano (1000), five type 9 |
| Survival 32 | 191 | 1 | OK: Goro (950) and Kintaro (1050) together |
| Survival 31 | 190 | 0 | OK: Reptile, Ermac, Sub-Zero, Scorpion (entry 1 untried) |
| Survival 10 | 169 | 1 | OK: Shang Tsung, 4 priests. His health read 666, the actor's placeholder, so check it in a fight |

Every loaded enemy had +0xD4 = 1 (killable), and each stage loaded in about 2 s. Entry 1 is the one to use; entry 0 works only in Survival 31, the stage with a +0x6C camera record. The scenes (descriptor +0x4C) carry the camera tags (CAMERAID, CAMERATARGETID, CAMBOXID...).

So the gauntlet is cut content in places. A revival should drive the run itself, loading each stage with an entry known to work and skipping broken ones, rather than trusting the stages' own links.

## The survival revival (user's design, 2026-11-03)

**Played 2026-11-03, full run BEATEN** (`GAUNTLET 0.12.0 BEATEN | portal@3985 s1=link162 s2=link163 s3=link164 s4=idle s5=idle s6=link191 s7=link190 s8=link64 s9=idle ... xp+10000`). The run started through Smoke's own portal, which still loads after the survival. Survival 6, 7 and 10 have no way out when won and needed the 30 s idle fallback. Survival 31's way out is the Foundry (map 64). Shang Tsung can be beaten.

**Built in Time Rifts 0.12.0** (`mods/_build/src/gauntlet_body.lua`): the rift opens once the save has game event 115 and the MK2 unlock byte 0x5A378C (set by `unlockmk2` at 0xB7290; Unlock All leaves it). The A prompt sits at the portal trigger `_d_portal` (105810, -1427, 64; radius 1303 in the trigger file), and Smoke's own portal load (designer 75) is redirected into the gauntlet too. Each stage's `loadmap` (exec 0x12883, args `{map + 1, entry, 1}`) is rewritten to the next stage; the Pit II's way back is `{147, 2, 1}`.

- **The entrance:** the portal in Smoke's room, once the vanilla survival is done (the user, 2026-11-03: do Smoke's quests, beat the Pit II, get MK2; then Smoke says a rift appeared). Smoke prompts them (a speaker line) to jump in.
- **The gauntlet:** the survival mode, finished: Time Rifts loads the working stages in turn, with its own lines and rewards (addexperience), and brings the player back at the end.
- **The versus arenas:** the survival stages look built on the versus arenas, and the arenas themselves (maps 170-185) work in versus mode, so they can be Time Rift destinations too.
- **After the gauntlet:** the KH2-style super boss postgame. Once the gauntlet is beaten, each survival room gets its own entrance somewhere in the world, and its stage runs with enhanced enemy settings. Not designed yet.

Not checked yet: whether a player can reach Foundry - Map 1's door in a
normal game, and what the stages look like. A load request into one of them
from the running game shows that; don't save there.

## Also seen

- **Every spawn file starts with the same 14 groups:** one relative entry
  each of 14, 46, 71, 15, 48, 2, 27, 48, 51, 30, 20, 26, 57, 36 (maps 132,
  146, 199 alike). They look like a debug template; they are never started
  in play.
- **Game events in the save** (bytes at [0x5ACEBC] + 0x4874 + N) set on the
  user's save: 1-23, 26, 31, 34, 37, 39, 40, 51, 52, 55, 57, 59, 60, 62,
  63, 65, 68, 72, 75, 78, 81-86, 92-94, 96-103, 105-108, 112-131 and 133.
  Map 199's triggers toggle 57 and 58: after its rush was beaten and saved,
  57 is set and 58 is not. So 57 is the likely saved "rush done" switch that
  Time Rifts' map-199 prompt could use after a reload. Check it on a save
  from before that rush.

## Ideas this gives the mods

- **Rift rewards:** call `addexperience` (or the XP setter) when a rift is
  beaten, with a Smoke-style line ("Excellent! Reward: ...") in the Raiden
  text slot.
- **Rift openings:** `freezetime` as the "time is torn" moment when a rift
  opens. Try it live first.
- **Boss-rush rifts:** a rift that loads Survival 31 or 32 would put four Mortal
  Kombat warriors, or Goro and Kintaro, in an arena whose memory fits them,
  with no streaming at all.
