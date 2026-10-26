# livemem: inspect a running game

`peek.py` reads the running ShaolinMonksRecomp.exe's guest memory (Windows,
Python standard library only).

```
python tools/livemem/peek.py
```

The report shows:

- **loaded types:** the enemy types that are loaded;
- **memory slots:** each slot's heap and fresh memory;
- **spawner:** its state and every enabled wave, with entry types;
- **actors:** which character slots are alive;
- **waves cleared:** the game's records of finished waves.

## Rescue recipe (2026-10-24, Goro's Lair fatality tutorial)

A trigger waits for "wave N cleared" (record in `0x6C0168`, written when a
wave's last enemy dies). If the wave never spawned, the record never comes and
the room stays empty. To restart it:

1. Retype the wave's entries to a loaded type with fresh memory.
2. Append a record `{N, 0, 1}` at index `[0x6C0258] % 20`, then bump the
   index.

Writing changes the live game. Only do it to rescue a soft-locked session, and
don't save if anything looks wrong afterwards.

## diff.py: find which values change when you do something

Read-only. It snapshots the game manager, both player characters and their
actors and stats, then lists every 32-bit value that changed, as hex, integer
and float. Values that change on their own while you stand still are filtered
out as noise.

```
python tools/livemem/diff.py watch
```

1. Start it while you're in game, and leave the pad alone for the first 3
   seconds (it records the idle noise).
2. Do one thing in game: throw a special, block a hit, take damage.
3. Come back to the console, type a short label (for example `special`) and
   press Enter. That step's changes are printed.
4. Repeat. Doing the same thing twice with the same label lets the summary
   show what changed every time. Type `q` to finish.

Everything goes to `qa/diff/watch-<time>.txt`, so Claude can read it after
your session. `snap NAME` and `diff A B [--noise C]` do the same from saved
snapshots, and `--range ADDR:LEN` adds any guest range.

Known noise: the player-0 HUD block `0x5AEE24` (`+0x3C`, `+0x40`) changes
whenever the HUD fades in and out, for example when you press block.
