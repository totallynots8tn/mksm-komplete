# Time Rifts 0.7.4 (QA)

Rifts without a portal model. Step into a rift and its arena reloads; when
you are back in control, a boss drops in mid-arena and waits for you.

- **Wu Shi's co-op arena (map 110):** step into the big hollow tree. An
  Orochi drops in front of it.
- **Mileena's secret arena (map 132):** step up to the purple wall portal.
  No reload here (the map's only entry is far from the arena): Mileena
  drops in mid-arena right away; if she leaves, Johnny Cage, then the
  Orochi.

Walk away from the rift first, then step in. Beat the boss, save at a statue,
quit. The mod writes one `TIMERIFT 0.7.4` line to the log (as a script error,
which also switches it off for the session): `OK`, or `CHECK` with the step
that failed. One rift per session.

Time Rifts is extra content and Shaolin Shuffle is the randomizer: the rift
never edits a map's preload list or any authored enemy. The boss gets its own
empty spawn group, and it is loaded the way cutscenes swap characters, in
place of a leftover enemy type that has nobody alive in the arena.

## History

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
