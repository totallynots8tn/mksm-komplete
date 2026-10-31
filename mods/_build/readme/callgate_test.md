# Call Gate Test (diagnostics)

Tests the callgate library (`mods/_build/src/callgate_lib.lua`), which lets
a routine script make the game call one of its own functions. Routine
scripts can only read and write memory; the library points one virtual call
the game makes every frame at another function for a single frame, then puts
it back.

About 15 seconds of unpaused gameplay after loading, it makes three calls,
one per frame:

- **reset**: sets co-op stone power to 1234, then has the game call its own
  stone-power reset (no arguments).
- **add**: has the game run the `addstonepower` command with an amount of
  25. The arguments are a pointer to a block that holds another pointer, so
  this tests the frame the library builds on the stack.
- **get**: calls the singleton getter and checks its return value.

Two seconds later it writes one line to the game log
(`%LOCALAPPDATA%\Shaolin Monks Recomp\logs\shaolin-recomp_*.log`):

    Mod routine: callgate_test: CALLGATE v0.2 OK | reset=ok(...) add=ok(...) get=ok(...)

`CHECK`, a `BAD` entry, or a crash is a result too: keep the log.

Only co-op stone power changes. Remove the mod after the test.
