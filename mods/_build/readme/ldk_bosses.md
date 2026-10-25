# Legendary Dark Knight: Boss Invasion 0.3

Everything in **Legendary Dark Knight Mode 2.1**, plus: in about 60% of the
doubled groups, the last reinforcement can come in as one of the level's
bosses or elites (up to six per level).

## Rules for an invader

- Its type must be loaded in the current level (`0x6CA69C`). Bosses from
  other levels can't appear: their models aren't in memory.
- Its own heap must have measured room. Costs are learned from real spawns,
  so invaders start showing up **after the level's own boss or elite has
  appeared once** and memory frees up. If there's no room, that reinforcement
  stays a regular enemy.

0.2.1 put the invader in place when the group started, and then the memory
check cancelled it, so you'd only ever see the level's normal one (your
single Oni Warlord). 0.3 picks the invader at spawn time, from elites that
fit.

Includes all LDK 2.1 crash fixes. Conflicts with `ldk`.
Experimental: bosses use their normal AI outside their arenas.
Requires Shaolin Monks Recomp 0.2.0 or later.
