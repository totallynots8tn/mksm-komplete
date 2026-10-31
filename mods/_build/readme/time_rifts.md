# Time Rifts 0.6.0 (QA)

Tests the rift loop without the portal model or its pull-in animation yet.

1. Go to Wu Shi's co-op arena (map 110).
2. Walk away from the big hollow tree, then step into its hollow, where the
   portal will be.
3. The arena reloads. About a second after you are back in control, one Orochi
   drops in mid-arena, in front of the tree, and waits there.
4. Beat it, save at a statue, quit.

The mod writes one `TIMERIFT 0.6.0` line to the log (as a script error, which
also switches it off for the session): `OK` when the Orochi appeared and was
beaten, `CHECK` with the step that failed otherwise. One rift per session.

Time Rifts is extra content and Shaolin Shuffle is the randomizer: the rift
never edits a map's preload list or any authored enemy. The arena has no
spawn groups of its own, so the rift builds one for the boss, and it loads the
boss the way cutscenes swap characters, replacing a leftover enemy type that
has nobody alive in the arena.

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
