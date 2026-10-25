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
