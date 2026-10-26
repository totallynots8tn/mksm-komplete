# Legendary Dark Knight Mode 3.10.0 (x2 / x3 / x4, with Boss Invasion)

Doubles every multi-enemy spawn group (up to 12 per group). The extra enemies
arrive as reinforcements. Sometimes the last one is one of the level's bosses
or elites. **Boss Invasion is now part of this mod.** Remove the separate
"Boss Invasion" mod.



## 3.10: the v1 memory fixes, in the dev line

Two fixes from the v1 patches are now in this build too:

- **Memory reuse counted per heap (v1 patch 2).** When an enemy type stays
  loaded from one map to the next (Goro's Lair keeps its type across maps
  98-100), its dead enemies' memory is reused, and the spawn guard now counts
  that across the maps. Before, the count started over on each map. The guard
  then cancelled the fatality room's respawning wave, which emptied the room,
  so the gate never opened. In the Goro's Lair simulation every enemy now
  spawns, 180 of 180, where the previous build spawned 60.
- **Reptile counts as a boss (v1 patch 4).** The story Reptile (map 144) is
  authored across three waves, so he was being cloned like a common enemy.

## 3.2: works in memory-tight areas

The 3.1 rule required an exact match of every behaviour field before an
enemy's type could change. In practice each enemy type carries its own patrol
and navmesh values, so every type ended up in its own class. A reinforcement whose own type had no spare memory (most of Wu Shi Academy) was cancelled, even when another enemy type had plenty. 3.2 fills it with that type. Now only
entries with a special entrance (spawn-near-player flag `+0x58`, initial AI
state `+0x5C` such as climbing in, mover data `+0x10`) keep the strict match.
Plain entries can take any regular enemy that the area also spawns from plain
entries. Climb-in and other special slots stay with the type they were made for.

## 3.1: softlock fix

A reinforcement could be turned into a boss or a different enemy type for a
spawn slot that type can't use. That's how an Oni ended up hanging outside the
Wu Shi rooftops, unkillable, blocking progress. Spawn entries carry per-slot
behaviour: entrance flag `+0x58`, initial AI state `+0x5C` (for example
climbing in from outside the arena), patrol `+0x60`, navmesh `+0x70`, mover
data `+0x10` and anchor `+0x24`. 3.1 only changes a reinforcement's type when
the area places that type in an entry with exactly the same behaviour.

The level census is now built a few groups per callback, so a full level
never hits the script instruction limit. The first group of an area spawns as
authored while the census finishes.

## 3.0: why 2.1 still crashed

A diagnostic run showed that **enemy model memory is never given back when an
enemy dies**. Each loaded enemy type has its own 2.2 MB pool, and every spawn
takes about 150 KB from it until the area reloads. The game sizes those pools
for the enemies the area itself spawns. So every extra enemy permanently ate
memory that a later, normal spawn needed. 2.1 only checked "is there room
right now", which is the wrong question.

3.0 does budget accounting instead:

- When a group starts, it counts every authored spawn still to come in the
  area, per type.
- An extra enemy only spawns if its type's pool still has room for all of
  those, plus one spare.
- If its own type is out of budget, the reinforcement becomes another loaded
  enemy type that has spare memory, or it is cancelled cleanly. Its type is
  hidden from the allowed list (`0x6CA69C`) for one call, so the game's own
  check (`0x1C1580`) refuses it before allocating anything.
- A last-resort guard cancels any spawn that would not fit at all.

So some areas get lots of reinforcements and memory-tight areas get few. The
area's own enemies are never touched.

## Boss Invasion

In about half the doubled groups, the last reinforcement tries to be a boss
or elite (a type the level places only once). It must be loaded in the
current area and fit the same memory budget. Up to six per area.

## Other details

- Clones wait for a free slot in the 12-character pool (2 slots stay reserved).
- Area reloads are detected two ways: the level-load hook, and pool memory
  going back up.
- Group actor capacity (`0x5142B8`) is raised from 7 to 12 before the first
  controller is created.

Requires Shaolin Monks Recomp 0.2.0 or later.

## 3.3: Legendary bosses (off by default since 3.4)

With `BOSS_HP_MULT = 2`, boss and elite characters get **2x health**:

- Orochi
- Oni Warlord
- Goro
- Kintaro
- Baraka
- Reptile
- Shang Tsung
- Shao Kahn
- Kitana
- Mileena
- Jade
- Ermac
- Scorpion
- Noob Saibot
- Sub-Zero
- Smoke
- Kano

Allies like Raiden and Johnny Cage are left alone.

How it works: the actor's health is at `+0x368` and its maximum at `+0x370`.
`setHealth` (`0x153CD0`) clamps to the maximum and updates the HUD. The first
time a boss's health changes, its maximum and current health are doubled, and
the incoming value is moved by the same amount, so that hit still does its
normal damage. Later hits are normal. A boss that respawns is doubled again.

Set `BOSS_HP_MULT` in `src/ldk_body.lua` (1 turns it off). Players and regular
enemies are never touched.

## 3.4: boss clones

Boss fights are cloned the way regular groups are. Each boss entry gets
`BOSS_MULTIPLIER - 1` extra copies (default 1, so two bosses), even when the
boss is alone in its group, its arena. The clones follow the same rules as
every other clone:

- They spawn a moment after the boss.
- They wait while the 12-slot character pool is full.
- They need memory left over after every authored spawn still to come. A clone that doesn't fit becomes a regular enemy with the same entrance behaviour, or is cancelled.

**Super bosses** are only ever cloned inside their own group, and are no
longer picked as Boss Invasion invaders:

- Orochi
- Oni Warlord
- Goro
- Kintaro
- Reptile (giant)
- Shang Tsung
- Shao Kahn
- the two-slot boss

**Mortal Kombat characters** are cloned in their own fights and can still
invade other groups:

- Scorpion
- Noob Saibot
- Kano
- Baraka
- Kitana
- Mileena
- Jade
- Ermac
- Sub-Zero
- Smoke

The double health from 3.3 is now **off by default**. Two bosses at double
health was too much. Set `BOSS_HP_MULT = 2` in `src/ldk_body.lua` to bring it
back.

Experimental: some boss arenas are scripted around one boss (health bar,
"Finish Him", cutscenes). If a fight breaks with two bosses, set
`BOSS_MULTIPLIER = 1` and send the log.

## 3.4.1

In playtesting, a cloned Oni Warlord spawned out of bounds and died. Its
arena entrance is scripted (mover data, an initial AI state, or the
spawn-near-player flag), and a clone can't take those over. Now only bosses
with a plain entrance are cloned, the same rule Shaolin Shuffle uses for
plain entries. Bosses with a scripted entrance fight alone.

## 3.5: x2, x3 and x4 variants

LDK now ships as three packages. Install all three and enable one; the
launcher refuses to enable two at once (`conflicts`):

| Package | Name | Regular groups | Boss fights |
| --- | --- | --- | --- |
| `ldk` | Legendary Dark Knight Mode | x2 | 2 bosses |
| `ldk_x3` | Legendary Dark Knight Mode (x3 Hard) | x3 | 3 bosses |
| `ldk_x4` | Legendary Dark Knight Mode (x4 Legendary) | x4 | 4 bosses |

The same caps apply to all of them:

- **12 entries per group.**
- **About 8 enemies alive at once.** That's the 12-slot character pool,
  minus the two players, minus 2 slots kept for scripted spawns. Extra
  clones wait for a free slot.
- **Each extra enemy has to fit in its type's memory.** x3 and x4 mostly
  mean bigger waves in rooms with spare memory.

v1 ships x3 only (2026-10-25); the reinstall bats enable it. The dev build
still makes x2 and x4 (`MKSMK.bat` > Pick levels).

The Oni Warlord boss is type 36, not 34 (the club-wielding warlord). 3.4
didn't know that, so Boss Invasion put the Oni into regular spawn entries
outside its arena. It's now a super boss: it never invades and only appears
in its own fight.

## 3.5.1: boss fights stay safe

The Oni Warlord was still spawning outside its arena. Its area authors it
**twice**, and LDK and Shaolin Shuffle treated any type authored twice as a
regular enemy. So the Oni could be re-typed into, or shuffled into, a
grunt's spawn entry outside the arena.

Fixes:

- **Bosses are never regular enemies** now, however many times an area
  authors them. The boss lists live in the shared `core.lua`.
- **Super bosses stay vanilla in v1.** That covers the Oni Warlord, the club
  warlord, Orochi, Goro, Kintaro, giant Reptile, Shang Tsung and Shao Kahn.
  They are never cloned, shuffled, re-typed or used as invaders. They're on
  the critical path, and a broken one can soft-lock a run. Set
  `SUPER_CLONES = true` in `src/ldk_body.lua` to try cloning them in their
  own arena.
- **MK character fights still get clones**, and can still invade other
  groups: Baraka, Kitana, Mileena, Jade, Ermac, Scorpion, Noob, Sub-Zero,
  Smoke and Kano.

## 3.6: single-enemy waves

Early levels such as Goro's Lair are mostly single-enemy waves (groups of 1),
which LDK used to leave alone. A single-enemy group of a regular type is now
multiplied too: x2 gives 1 extra, x3 gives 2, x4 gives 3. That only happens
when the entry has a plain entrance (no scripted mover, initial AI state or
spawn-near-player flag), the same safety rule boss clones use. The area's
first group still spawns as authored while LDK counts the area.

## 3.7: the memory rule follows recycling

In the 2026-10-24 playthrough log, LDK x2 planned reinforcements in Goro's
Lair but cancelled almost all of them (22 failed spawns). Its memory rule
reserved room for **every** authored spawn still to come. Goro's Lair
authors 24 of one enemy type, which came to about 3.6 MB of reservation
against roughly 590 KB free.

The same log shows the game **recycles** a dead enemy's model instance. That
type's memory stopped shrinking after 5 instances, while 18 more spawned and
died. Memory follows how many are alive at once, not how many spawn.

The new rule reserves room for three things:

- the largest authored wave of the type still to come,
- minus the instances the area has already allocated that no live enemy is
  holding;
- plus the extra itself;
- plus one spare.

The last-resort spawn guard that prevents crashes is unchanged.

In the spawn simulation, which now recycles instances like the game, extras
went from 9 to 39 (x2), 60 (x3) and 81 (x4). Every authored enemy still
spawned, with no crashes and no stuck groups.

## 3.8: MK roster reinforcements

LDK now brings in Mortal Kombat characters as regular enemies, not only
through Boss Invasion. Any reinforcement has a 30% chance to come in as an MK
character the area already has loaded. The story streams some of them into
areas, such as Johnny Cage and Raiden in Goro's Lair. The characters:

- Baraka
- Kitana
- Mileena
- Jade
- Ermac
- Scorpion
- Noob Saibot
- Sub-Zero
- Smoke
- Kano
- Johnny Cage
- Raiden

Rules:

- **Plain spawn entries only**, so nobody appears inside a wall or out of
  bounds.
- **Memory:** the character's memory must have room under the
  recycling-aware rule.
- **Per-area cap:** 6 on x2, 12 on x3, 18 on x4.
- **Super bosses** (Oni Warlord, Orochi, Goro, Kintaro, Shang Tsung, Shao
  Kahn, giant Reptile) are never used.

Bringing in MK characters an area doesn't load at all is the UMK roster
phase. It needs free character slots, and those are reserved for bosses that
stream in.

## 3.9: boss AI stays out, first groups count

**MK characters are benched.** They keep their boss AI when cloned or used
as reinforcements. A second Kitana ran her damage-triggered scripted throw,
which carried the player out of bounds, and she couldn't be killed: a
soft-lock. So for now:

- MK roster reinforcements are off (`ROSTER_CHANCE = 0`).
- MK boss clones are off (`MK_CLONES = false`).
- Boss Invasion no longer uses any boss-AI character.

Plain elites authored once in an area, such as Johnny Cage in Goro's Lair,
can still invade. Every boss fight is vanilla. MK characters come back in
the UMK phase, with versus-style behaviour.

**First groups.** LDK counts each area's spawn groups over a few frames, and
a group that started before the count finished used to stay as authored, so
LDK seemed off in some areas. Now that group is expanded the moment the
count completes, as long as it's still spawning.

## 3.9.1: respawning waves soft-lock fix (shared spawn guard)

In the Goro's Lair fatality tutorial, one wave of enemies restarts every time
you clear it, until you perform a fatality. With LDK x3, earlier waves had
used up the enemy type's fresh memory. The last-resort spawn guard that LDK
and Shuffle share then cancelled every spawn: it only counted fresh memory
and ignored the dead enemies' memory the game reuses. The wave restarted
empty. The game never recorded it as cleared, so the gates never opened.

The guard now lets a spawn through when a dead enemy of that type has memory
free to reuse. Shuffle also resets its count of those instances when a map
loads, as LDK already did. In the simulation of that room, the old guard
spawned 9 of 180 enemies and the new one spawns all 180, with no crashes.

## 3.9.2: fatality rooms stay vanilla

The game has three fatality tutorial rooms. Goro's Lair has one: "You need
to perform a Fatality to open the gates." Their exit waits on their own
respawning wave, and changed waves soft-locked it twice. Any area whose map
triggers test the fatality meter or a finished fatality is now left exactly as
authored: no extra enemies, no shuffle, no outsiders.

