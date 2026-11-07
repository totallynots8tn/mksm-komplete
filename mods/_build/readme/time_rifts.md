# Time Rifts 0.14.3 (preview)

Rifts without a portal model. Step into a rift and its arena reloads; when
you are back in control, a boss drops in mid-arena and waits for you.

- **Wu Shi's co-op arena (map 110):** step into the big hollow tree. An
  Orochi drops in front of it, with five burning monks and three priests.
- **Mileena's secret arena (map 132):** stand in front of the purple wall
  portal and the A prompt shows. Press A (it doesn't jump there): the portal
  pulls you in, as the game's own portals do, and sends you back to the
  shrine deck halfway through the secret area (no reload). Walk back to her
  arena: Mileena drops in once you are within about 1,500 units of her spot,
  with four Tarkatans; if she leaves, Johnny Cage, then the Orochi.
- **Goro's Lair (map 102), past the bell door:** the A prompt shows where the
  portal would be. A pulls you in, the arena reloads and you are put back
  there. Raiden warns you that time is torn, a rush comes (three enemies of
  the lair's own kinds, each with two clones), and once it is beaten, Goro
  himself. He needs both of the lair's enemy memory slots, so the lair's
  enemy types are unloaded for him and loaded back after his fight.
- **The co-op area (map 199), past its enemy rush:** the A prompt shows only
  once that rush is beaten (and nobody is left standing). It pulls you in and
  back, then Kintaro drops in front of the chair (on the floor you crossed on
  your way up) with three of the area's priests (if he is lost, the Orochi
  comes instead). He borrows the Tarkatans'
  memory slot (never the priests'); the Tarkatans are loaded back once his
  body is gone.
- **Smoke's secret area (map 146), the Survival gauntlet:** once you have
  done Smoke's quests the vanilla way (the Pit II beaten, MK2 unlocked), his
  portal becomes a rift. Smoke says so; stand in front of the portal and the
  A prompt shows (walk away from it first if you arrive there). A pulls you
  in and the gauntlet starts: the game's own cut Survival stages, one after
  another, each with its Mortal Kombat line-up (Baraka, Kahn's guards, the
  Oni Warlords, the Orochi and the burned Scorpion, the clay soldiers, Kano,
  Goro and Kintaro, Reptile, Ermac, Sub-Zero and Scorpion together, then
  Shang Tsung). Smoke tells you which battle you are in. Win a stage and the
  next one loads; after the last you are back with Smoke, who pays 10,000 XP
  the first time and 2,500 after. You can run it again.
- **The Soul Tombs (map 4), after the gauntlet:** the first postgame rift.
  In the chamber where Shang Tsung's soul orb is destroyed, the Survival
  portal's ground rings, rays and red ring rise and the Black button (^)
  opens the rift. It
  sends you to Survival 10, the cut stage built on that chamber: Shang Tsung
  and his priests as the stage has them, then Goro with four Red Dragons,
  Kintaro with four Black Dragons, and the young Shang Tsung with two of
  each. Win and you are back in the chamber with 15,000 XP; go down and you
  are sent back without it. You can run it again. To make room, the rift adds
  both dragon clans to that stage's load list for its run (Shuffle leaves the
  Survival stages alone). The stage's own exit stays shut until the last boss
  is down.
- **The Champion Shrine (map 108), Ermac's battle, after the gauntlet:** the
  second postgame rift, the same portal and button. It sends you to
  Survival 31: Reptile, Ermac, Sub-Zero and Scorpion together, then the
  burned and the regular Scorpion with zombies and skeletons, two Sub-Zeros
  with Black Dragons, two Reptiles with the Living Forest's shadows, two
  Ermacs with priests, two Kanos with Red Dragons, and the ex-champion Goro
  with his clone. 20,000 XP. Each phase loads the types it needs into the
  memory the last one leaves.

Both postgame rifts are one script, `postgame.lua`, which writes one
`POSTGAME 0.14.3 <rift> <verdict>` line per run. Each phase comes out of
the stage's rift, the spot you landed on: it flashes for a moment when you
land, when each phase drops and when the chain is won.

Walk away from the rift first, then step in. Beat the boss, save at a statue,
quit. A rift you beat stays closed on that save (it never opens again), so
the arena is yours to move on from.

The mod writes one `TIMERIFT 0.12.0` line to the log a frame after the fight
ends (as a script error, which also switches it off for the session):

| Verdict | Meaning |
| --- | --- |
| `BEATEN` | the game set the boss's health to 0 |
| `VANISHED` | the last boss disappeared (or fell out of the map) with health left; each boss's health and distance from you are noted |
| `FAILED` | your health reached 0 |
| `LEFT` | you left the map first |
| `CHECK` | a step failed (the note names it) |

One rift per session. The gauntlet has its own script and writes one
`GAUNTLET 0.12.0` line per run: `BEATEN` (back with Smoke and paid), `LEFT`
(you ended up somewhere else than the next stage, the stage noted) or
`CHECK` (a load never came). Its notes list each arrival (`s3@` = stage 3),
how each stage was left (`s3=link163` = the stage's own way out to map 163,
redirected; `s3=idle` = nobody up and no wave for 30 seconds), and the XP.

**The gauntlet's stages** (map, entry): Survival 2 (161, 1), 3 (162, 1), 4
(163, 1), 6 (165, 1), 7 (166, 1), 28 (187, 1), 32 (191, 1), 31 (190, 0) and
10 (169, 1), the order of their own links. Survival 5 (164) is left out: its
scene has no cameras and you land in the void. The stages' own links use
entry 0, which crashes in the camera setup of every stage but Survival 31,
so each stage's way out is pointed at the next stage's working entry. A
stage that never sends you on is left once nobody is up and no wave has run
for 30 seconds (or nobody came for a minute).

Time Rifts is extra content and Shaolin Shuffle is the randomizer: the rift
never edits a map's preload list or any authored enemy. The boss gets its own
empty spawn group, marked as the rift's so that LDK doesn't clone the boss
and Shuffle doesn't change it, and emptied again when the fight is over. It
is loaded the way cutscenes swap characters, in place of an enemy type that
has nobody alive in the arena (one the map's own spawn groups don't use, when
there is one).

**Save data:** a beaten rift is a bit in player 1's level slot 22, a byte no
game code reads (the XP Shop uses 19-21 and 27); bit 4 is the gauntlet's.

## History

- 0.14.3 (the user: the stage's rift stayed up after you dropped in): in the
  stage the rift only flashes, for 2.5 seconds, when you land, when a phase
  drops and when the chain is won. The entrance's portal stays up.

- 0.14.2 (QA 2026-11-04 with a live recorder: the Scorpions' phase spawned
  only the burned Scorpion, and the game crashed two seconds after phase 2's
  Sub-Zeros spawned; he had been streamed back into another slot than his
  own): a type that held a slot in the stage only ever comes back into that
  slot, and one already used in the stage is loaded again there first, so
  its memory is fresh for the phase's copies.

- 0.14.1 (QA 2026-11-04: the Champion Shrine crashed in the game's model
  decompression worker, as map 199 did after the Orochi was streamed over
  its priests; and the phases dropped on Liu): a slot is only streamed over
  once nobody of its type has been up for 10 seconds (a dismembered
  fighter's parts outlive it), and each phase drops from the stage's rift.

- 0.14.0: the Champion Shrine rift. The postgame rifts are one script
  (`postgame.lua`, replacing `soul_rift.lua`) with the rifts as data; a phase
  is a set of bosses (clones included) and grunts, and every type it lacks is
  streamed in before the drop, waiting for a slot's last body to go. Types
  taken: 8 for the zombies, 4 for the skeletons, 17 for the shadows.

- 0.13.1 (QA 2026-11-04: the whole chain was BEATEN, but every boss came
  alone and the stage's exit opened during Goro's fight): a dragon clan the
  stage no longer holds when a phase starts is streamed into a free slot
  with memory first; the stage's own loadmap is taken back while the chain
  runs; the portal adds Survival 2's rays (105) and red ring (48) to the
  rings; the notes list the memory slots at the stage and at each phase.

- 0.13.0: the Soul Tombs rift (its own script, `soul_rift.lua`), the first of
  the postgame rifts: the user's chain of Shang Tsung, Goro, Kintaro and the
  young Shang Tsung, with the dragon clans. The rings are the global effect
  109 through the particleoffset command (0x1582A0); Black is pad byte +6
  and the prompt is text 60. Type 9 is taken for the Black Dragon and 16 for
  the Red Dragon.

- 0.12.0: the Survival gauntlet in Smoke's secret area (its own script,
  `gauntlet.lua`). The rift opens once the save has game event 115 (the Pit
  II's way out) and the MK2 unlock (the byte `unlockmk2` sets; Unlock All
  leaves it alone); its first beaten run is bit 4 of the rifts' save byte.
  Smoke's lines go in the slot Raiden's line uses. Smoke's portal, if it
  still loads the Pit II then, leads into the gauntlet too.

- 0.11.4: a boss only counts as fallen out of the map once it has stayed far
  below (1,500 units) for three seconds. Kintaro's leaps (or the floor below
  map 199's dais) ended his fight too early in 0.11.2 though you beat him.

- 0.11.3: a rift boss that falls out of the map is put back on the rift's
  spot (up to five times; Kintaro fell through map 199's floor). Map 199's
  Kintaro now has the Orochi as his fallback.

- 0.11.2: map 199's rift is Kintaro alone with the area's priests. The game
  crashed twice right after the Orochi was loaded over the area's priests,
  so the rift only ever borrows the Tarkatans' memory slot there.

- 0.11.1: map 199's rift waits for its rush to be beaten (before, it opened
  and found no memory for its bosses), its bosses drop in front of the chair,
  and the rifts load one character at a time with a pause between (a crash in
  the game's loader followed two loads back to back).

- 0.11.0: the co-op area's rift (map 199): the Orochi and Kano, then
  Kintaro. Wu Shi's Orochi brings five burning monks and three priests. A
  rift that borrows memory slots the map's own enemies use loads them back
  when it is over.

- 0.10.2: the rifts' enemies attack you. Their spawn group lacked the
  settings every vanilla wave has, so they only struck back with their
  counter.

- 0.10.1: the rush takes regular fighters only (Shaolin Shuffle had loaded
  tree mouths, which held the rush open), and in Goro's Lair the pull-in
  turns you the other way (it carried you into the arena).

- 0.10.0: burning monks with the Orochi, Tarkatans with Mileena, and the
  Goro's Lair rift: Raiden's line (written in your game's language over an
  unused Raiden tutorial text, only where it fits), the rush, then Goro.

- 0.9.1: the pull-in. A plays the reaction the game's own portals play
  before they load the next map (animation 0x26), and you are sent on once
  it ends (`pull@` in the `TIMERIFT` line). Mileena waits in her arena
  again: on the deck she dropped right beside you.

- 0.9.0: the purple wall portal works like a real one. In front of it the
  game's own portal prompt shows (the A button icon), and A takes you to the
  shrine deck with the game's own set-position routine, the one versus
  respawns use. Writing the position never stuck because that routine also
  resets the cached floor and the physics. Your momentum is cleared, the
  camera cuts to you and you face the way the deck spot was read. Mileena
  drops on the deck's own enemy spawn point. The `TIMERIFT` line notes
  where you landed (`warp@`, and `a=` at the drop: your distance from the
  deck spot).

- 0.8.2: the boss can die. The game makes most Mortal Kombat bosses
  unkillable (their health stops at 1 so their story fight's cutscene can
  end it), Mileena included. Out of that fight the rift turns this off; the
  log notes it as `killable@`.
- 0.8.1: Mileena's arena waits for you. The secret area is big and the
  portal is about 4,900 units from mid-arena, so the arena may not be solid
  yet when the rift opens. The boss drops once you are within 1,500 units of
  mid-arena (a first guess; the `near@` note in the log gives your distance).
  The right bosses this time: the character numbers were two off, so 0.7.x
  "Mileena" was Shao Kahn (type 64) and "Johnny Cage" a generic grunt (76).
  Mileena is 66 and Johnny Cage 78 (see `analysis/mk_roster/`).
- 0.8.0: honest verdicts (the boss's health decides: `BEATEN`, `VANISHED`,
  `FAILED`, `LEFT`; 0.7.x called any boss that left after 5 seconds `OK`).
  A beaten rift stays closed on that save. No spawn group is built after the
  map changes. LDK and Shuffle leave the rift's group alone (LDK x3 turned the
  one boss into three in the offline sim). The callgate library checks each
  call when it is queued, so a bad call can't leave the game's vtable
  redirected.
- 0.5.0 and 0.5.1 crashes were Shaolin Shuffle 0.11.2 loading the Wu Shi
  entrance; the rift never ran.
- 0.5.2 to 0.5.4: the Oni's spawn entry and group start were fixed, but the
  Oni never loaded (no free memory slot).
- 0.5.5: the Oni loaded and spawned, inside the tree, and the mod didn't see
  it alive.
- 0.5.6: the reload never happened: the game's loadmap command only requests
  a load from inside an exit or portal trigger. 0.5.7 makes the request
  itself.
- 0.5.7: the whole loop worked (QA 2026-10-31 16:25), but the Oni came in
  outside the bamboo fence; 0.5.8 moves it mid-arena the moment it appears.
- 0.5.8: the Oni Warlord leapt out over the fence right after spawning, and
  moving it back didn't stick; 0.6.0 drops an Orochi instead.
- 0.6.0: the Orochi rift in Wu Shi's arena worked (QA 2026-10-31). 0.7.0
  adds Mileena's arena and a fallback boss.
- 0.7.0: Mileena spawned and removed herself a quarter second later; 0.7.1
  moves on to the next boss when that happens.
- 0.7.1: Mileena and Johnny Cage spawned just under the floor of map 132 and
  fell out of the map; 0.7.2 spawns bosses a little above the floor and
  treats a fall as the boss not staying.
- 0.7.2: Mileena and Johnny Cage landed but removed themselves within
  seconds; 0.7.3 drops the Orochi in Mileena's arena too.
- 0.7.3: the reload put the player at map 132's start, far from the arena,
  and the game removed the far-away boss; 0.7.4 drops it without a reload.
