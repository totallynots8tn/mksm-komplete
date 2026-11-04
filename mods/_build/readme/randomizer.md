# Shaolin Shuffle 0.13.0

Changes which enemy types a room spawns, three ways:

- **Room mixing (0.10).** A room that authors one regular enemy type trades
  plain spawn slots with a room of another type, so it spawns several types.
  Each trade moves one slot each way, so every type's area total — and with it
  its character-memory use — stays exactly as authored.
- **Outsiders from other areas (0.11: most areas).** The shuffle appends an
  enemy type from another level to the map's preload list and turns plain
  slots into it. An area with one or two loaded enemy types gets one as an
  extra type, and so does an area with three when nothing in it needs the
  fourth memory slot. **0.13:** fourteen areas whose memory is full trade
  one of their own enemy types for the outsider instead (see below).
- **Mortal Kombat warriors (0.12).** About one outsider area in three gets
  a Mortal Kombat character instead. Two of the area's rooms each get one
  warrior: Scorpion, Hell Scorpion, Kano, Baraka, Reptile, Kitana, Mileena,
  Jade, Ermac or Sub-Zero. They fight to the death: the mod lifts the "can't
  die" flag their story fights give them.

Slots with scripted entrances, bosses and elites keep their exact type: only
plain slots (no entrance flags, no mover data) ever change type.

## Settings

0.11 is one mod. The Normal, Wild and Chaos variants are gone; what was Wild
is now the only setting:

| Slot trades per one-type room | Outsiders per room | Extra outsiders | Max per room | Max per area | Outsider types |
| --- | --- | --- | --- | --- | --- |
| 1 | 1 | 50% of the other plain spawns | 5 | 45 | 11 |

A "room" is one spawn group, one wave of a fight. The shuffle never changes
how many enemies spawn, so it costs no more performance than vanilla; only
Legendary Dark Knight adds enemies.

**Outsider types:** the 8 enemy types v1 shipped with, plus 3 more that the
QA logs saw as ordinary enemies in 7 or more areas. Bosses, elites and
two-slot characters are never outsiders.

If you had Shaolin Shuffle (Wild) or (Chaos) installed, remove them; this
mod replaces both.

## 0.13.0: outsiders in full areas

Areas that already fill their enemy memory used to get room mixing only.
Now fourteen of them trade one of their own enemy types for the outsider:
the type leaves the area's load list, the outsider takes its memory slot,
and every spawn of that type becomes the outsider. That's the Foundry's
archers (map 64), the captains of maps 69, 194 and 197 and the Pit II, the
Evil Monastery's priests (192), the Oni of map 101, the Living Forest's clay
soldiers, scythe enemies and corpses (129, 130, 135, 136, 137), and maps 45
and 48.

Shuffle 0.11.2 tried this everywhere and crashed in the Wu Shi entrance:
some levels place characters of their own types straight in the scene, and
those need their type loaded. So each of the fourteen was load-tested live
with its type swapped out (2026-11-03). Wu Shi's start (map 103) crashed
like the entrance, and in map 128 the game loaded its corpses straight back,
so those stay as they were; the other Wu Shi areas with Tarkatans weren't
tested and keep their roster too. The swap only happens when every spawn of
the type is a plain one (no scripted entrance), and a cutscene that pushes
the outsider out puts the area's own type back.

## 0.12.1: no trees

The Living Forest's tree mouth and tree arms are no longer outsiders: they
are hazards a room's wave doesn't count, hard to kill, and they stayed in the
room after its wave was over.

## 0.12.0: Mortal Kombat warriors

Most Mortal Kombat characters are bosses whose story fights end in a
cutscene, so the game makes them unkillable: their health stops at 1 and the
fight's script takes over. Out of that fight, such a warrior would never
fall, so its room would never end. Shuffle turns the flag off on the warriors
it brings, the frame they appear.

A Mortal Kombat character's memory slot holds two copies of it, so an area
gets at most two warrior spawns, one per room. If a third copy would come up
at once, that spawn goes back to the room's own enemy. Warriors never come
to a boss arena or to an area that already has that character (its own
fight), and Legendary Dark Knight never clones them.

## 0.11.5: Mortal Kombat characters stay put

The shared boss list (also LDK's) had its character numbers two off (see
`analysis/mk_roster/`). Every type that was protected still is, and the real
Kintaro, Sub-Zero, Smoke, Raiden, Jax, Johnny Cage and the versus models are
now protected too: Shuffle never moves them into another spawn slot.

## 0.11.4: script safety

When a cutscene evicted the outsider in the same spawn tick as a re-shuffle,
the restore and the new shuffle together could exceed the 256 memory writes a
script may make in one callback, which switches the script off for the
session. The restore now gets its own tick. A Time Rifts boss group is never
shuffled. The outsider pool is shared with LDK, which can now use the outsider
for its reinforcements.

## 0.11.3: crash fix

0.11.2 had the outsider replace one of a three-type area's own enemy types.
That crashed while loading the Wu Shi entrance: the level places some
enemies of its own types directly in the scene, outside the spawn groups, and
they need their type loaded. Shuffle now only ever adds a type, never
replaces one, as in 0.11.1.

## 0.11.1: the fourth slot

An area that loads three types can use the fourth memory slot for the
outsider when its spawn groups author no type outside the roster (nothing
in the level then needs the slot), checked when the area loads.

## 0.11: outsiders in most areas

Up to 0.10, only areas whose whole map roster was a single regular enemy
type (like Goro's Lair) got an outsider. Now any area whose roster has a
regular enemy type gets one, as long as the roster plus the outsider use at
most three of the game's four enemy memory slots. Each listed character
counts its own slots (one, or two for the two-slot bosses), bosses and MK
characters included. Three is the most the game itself ever had loaded in
the QA logs, and the fourth slot stays free for cutscenes and for enemies a
level loads on the spot. Every slot has the same fixed memory, so the
outsider never takes memory an authored enemy needs.

By the game's map rosters, that is about 54 of the 73 maps with enemies: the
19 one-type maps as before, plus about 35 two-type maps. Maps that already
load three types keep their authored enemies and get room mixing only.

## 0.10: rooms actually mix

0.9's shuffle permuted types inside one behaviour signature, which leaves a
room that authors a single type looking untouched, and its outsiders only
reach single-type map rosters. Wild and Chaos looked inert in most areas.
0.10 adds the slot trade above (Wild: one per one-type room, Chaos: two),
tested in the spawn simulation: every one-type room ends up spawning two
types, per-type totals byte-identical to vanilla, 0 stuck groups and 0 heap
crashes across the scenario matrix.

## 0.9: the v1 memory fixes, and more outsider types

The two fixes from the v1 patches are now in this build too, plus a wider
outsider pool:

- **Memory reuse counted per heap (v1 patch 2).** When an enemy type stays
  loaded from one map to the next (Goro's Lair keeps its type across maps
  98-100), its dead enemies' memory is reused, and the spawn guard now counts
  that across the maps. Before, the count started over on each map. The guard
  then cancelled the fatality room's respawning wave, which emptied the room,
  so the gate never opened. In the Goro's Lair simulation every enemy now
  spawns, 180 of 180, where the previous build spawned 60.
- **More outsider types on Wild and Chaos** (0.11 keeps the Wild pool; see Settings). Normal is
  unchanged.
- **Reptile counts as a boss (v1 patch 4).** The story Reptile (map 144) is
  authored across three waves, so he was being cloned like a common enemy.

## 0.8: an outsider in every room

0.7 converted each plain spawn slot with a 35% chance, so some rooms got none.
Now every room with a plain slot gets its guaranteed outsiders first, then the
chance applies to the rest. That includes the area's first room, which is
already spawning when Shuffle plans the area: its slots that haven't spawned
yet can still take an outsider. In the Goro's Lair spawn simulation, every
variant put an outsider in all 18 rooms across three visits, alone and with
LDK x3/x4. Every authored enemy still spawned, with no crashes and no stuck
groups.

## 0.7: outsiders

Before 0.7, an area that loads a single regular enemy type had nothing to swap
with. Goro's Lair authors 24 enemies of one type, so it looked unshuffled.

**What happens now:** each map lists the enemy types it loads up front. When
that list holds exactly one regular type, Shuffle adds one more, picked at
random on every visit from types that are common enemies elsewhere (ids 10-15,
26, 27). The game loads it like any other enemy. Shuffle then turns about a
share of the area's plain spawn slots into it. How many depends on the
variant (see above). Slots with a special entrance, such as climbing in, are
never used.

**Memory:** the game has 4 enemy memory slots. In 164 logged group starts,
vanilla never had more than 3 enemy types loaded, so the outsider takes the
slot that's normally spare. Every spawn is still checked against its type's
real memory.

**Cutscenes:** a cutscene that streams in a character goes through the game's
own replace queue, which unloads whatever holds that slot. That can evict the
outsider. If it does, its remaining spawns go back to their original type and
the area keeps its own roster until it reloads.

**Not affected:** versus mode, boss arenas (the single type is a boss), and
areas with two or more regular types. Those last ones already shuffle.

**Checking it:** in Goro's Lair you should see a different enemy type mixed in
with the usual ones. With the MKSMK Probe installed, the SHUFFLE report's
`loaded=[...]` list shows the outsider as an extra type.



## 0.6: works in memory-tight areas

The 0.5 rule required an exact match of every behaviour field before an
enemy's type could change. In practice each enemy type carries its own patrol
and navmesh values, so every type ended up in its own class. The shuffle had nothing to swap with, so rooms looked unchanged. Now only
entries with a special entrance (spawn-near-player flag `+0x58`, initial AI
state `+0x5C` such as climbing in, mover data `+0x10`) keep the strict match.
Plain entries can take any regular enemy that the area also spawns from plain
entries. Climb-in and other special slots stay with the type they were made for.

## 0.5: softlock fix

0.4 could move an enemy into a spawn slot built for another type's entrance,
like a wall-climber's slot outside the arena. That left it stuck out of bounds,
unkillable, so the area never cleared. 0.5 only swaps types between entries
with identical behaviour (entrance flag, initial AI state, patrol, navmesh,
mover data). The shuffle now runs in the next spawn tick, its own callback.

## Why it changed

Enemy model memory is never freed when an enemy dies. Each type's pool is
sized for how many of that type the area spawns in total. 0.3 picked random
new types, which used up some types' memory and could crash later. It also
had to skip most re-rolls, which is why some rooms looked normal.

0.4 permutes the types the area already has. If an area has 10 spear guys
and 10 monks, it still has 10 of each, just in different places. Totals never
change, so memory never runs out, however much moves around.

- Each area is shuffled once, in a single pass, the first time a group starts.
- Entries are swapped so as few as possible keep their own type.
- Bosses and once-per-area elites stay where they are. Players and allies
  are never included.
- Groups that already ran (and the first group of the area) aren't changed.
- A reload is detected and reshuffled.

An area that only has one common enemy type can't change. There's nothing to
swap with. Bringing in characters from other levels is still on the list.

Compatible with Legendary Dark Knight Mode 3.0.
Requires Shaolin Monks Recomp 0.2.0 or later.

## 0.6.1: bosses stay put

The Oni Warlord is authored twice in its area, so 0.6 counted it as a
regular enemy and could shuffle it into a grunt's spawn entry outside the
arena. Bosses (super bosses and MK characters, listed in `core.lua`) are now
never part of the shuffle.

## 0.6.2

Shares LDK 3.7's memory code (`core.lua`); Shuffle's own behaviour is
unchanged. Areas with only one regular enemy type, like Goro's Lair (24 of
one type), still look unshuffled: there's nothing to swap with. Bringing in
enemies from other levels is the next Shuffle feature.

## 0.8.1: respawning waves soft-lock fix (shared spawn guard)

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

## 0.8.2: fatality rooms stay vanilla

The game has three fatality tutorial rooms. Goro's Lair has one: "You need
to perform a Fatality to open the gates." Their exit waits on their own
respawning wave, and changed waves soft-locked it twice. Any area whose map
triggers test the fatality meter or a finished fatality is now left exactly as
authored: no extra enemies, no shuffle, no outsiders.

