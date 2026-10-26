# MKSMK Probe 0.10 (diagnostics)

Changes nothing in the game. It records kills, XP changes and enemy spawns,
then writes them to the session log
(`%LOCALAPPDATA%\Shaolin Monks Recomp\logs`) as lines starting with
`Mod routine: mksmk_probe: PROBE`. Three copies report after 25, 90 and 300
events. Each switches itself off after reporting; that's expected.

Event codes:
- `D<char>:<hp>@<callers>`: a character's health dropped to 0, and which code did it
- `K`, `A`, `B`: the killandhide, applydamage and bodydamage hazard commands
- `X<player>:+<xp>c<combo>@<callers>`: XP was awarded, and which code did it
- `G<group>n<count>p<free pool>[type=free/total heap,...]L<loaded types>`: a group started
- `S<type>:<bytes>`: model memory one spawn used; `F`: a spawn failed

Play a few minutes: kill enemies normally, throw some off the map, use
spikes or pits. Then send the newest log.

## 0.2: script tracer

`probe_trace` logs calls to the co-op, stone-power, trigger and event script
commands (`istwoplayer`, `isoneplayer`, `stonepowatleast`, `addstonepower`,
`enabletether`, `actionButton`, `buttonthrough`, `movetotrigger`,
`gameevent`, `eventcomplete`, `callspawn`, `spawnunlockable` and others).
Each entry shows the command's result and the current co-op stone power
(`0x581B48`); repeats collapse into `xN`. It reports as a line starting with
`Mod routine: mksmk_probe: TRACE` after 60 different entries.

To diagnose a co-op plate: load near it, step on and off it a few times, try
the action button on it, then send the log.

## 0.3: XP watcher

The XP setter is called directly and can't be hooked, so the probe watches
your XP value instead. Every increase is logged as
`XP+<amount>c<combo hits><<last death>`, which shows exactly what normal
kills, combos and env kills pay.

## 0.4: plate tracer

`probe_plate` replaces the 0.2 script tracer. Map triggers (manager pointer
`0x682020`, records `0xD8` apart) only fire when every condition command in
their list passes (`0x16F4B0`). The tracer:

- dumps each trigger whose conditions use `istwoplayer`, `isoneplayer`,
  `actionButton`, `buttonthrough`, `stonepowatleast` and similar, as
  `T<index>{f<flags>,n<needed passes>,c<passes>}<condition list>`
- logs each condition result when it changes, as `<command>(<character>)=<result>/T<index>`
  and `t<index>@<character>=<all passed>`
- arms (`ARM<index>`) the moment you press action on such a trigger, then
  also logs every script command that runs, trigger passes `F<index>c<count>`
  and trigger events `E<index>@<activator>#<n>`

It reports once, as a line starting with `Mod routine: mksmk_probe: PLATE`:
10 seconds after you disturb a trigger, or after 140 entries. It hooks every
script command, so it may cost a little performance while installed;
uninstall it once the log is sent.

To diagnose a co-op plate: walk onto it, press action a few times, wait
about 10 seconds on or near it (try a second plate if there is one), then
send the newest log.

## 0.5: plate arming + shuffle eligibility

The plate tracer no longer reports on a bare "saw a co-op trigger" timeout,
which used to stop it before you reached the plate. It now arms only when a
trigger's condition or pass counter actually changes under you (`ARMC`,
`ARMB`, `ARMF`, `STEPP`), then reports 10 seconds later. It also reads the
multi-pass flag (`def+0x70` bit 17) for every trigger: a trigger that needs
two or more passes is marked `T<index>{...,M}` and its pass counter is traced
as `P<index>c<passes>/<needed>`. A solo player on a 2-pass plate shows the
count rising to `1/2` and the trigger never firing — that is the co-op gate.

`probe_shuffle` is a one-shot snapshot for the Shaolin Shuffle. Shortly
after the first group of an area starts it walks every authored spawn entry
and reports, as a line starting with `Mod routine: mksmk_probe: SHUFFLE`:

- `slots=<n>` authored entries, `eligible=<n>` entries whose type can move,
  `freegates=<n>` empty slots in the 6-type spawn gate, and `loaded=[...]`
  the types that can spawn right now
- one `<type>=<count><flags>` per authored type, where `once` marks a type
  authored fewer than twice (a boss or one-off elite), `L`/`l` is whether it
  is in the 6-slot spawn gate, and `H`/`h` is whether it owns a
  character-memory heap. A common `lH` type has its model resident but is not
  gated in (a reservation could spawn it); `lh` has neither, so only the
  engine streaming it in would help. This shows the exact constraint that
  keeps a type out of the shuffle.

To diagnose low shuffle variety: load an area, let a fight start, then send
the newest log.

## 0.6: shuffle report detail

`probe_shuffle` now reports the spawn-gate (`L`/`l`) and heap (`H`/`h`) state
of every authored type separately, plus `freegates`, instead of a single
rejection reason — so a type that is merely ungated can be told from one whose
model isn't resident at all.

## 0.7: plate flood fix + upgrade command signatures

**Plate tracer.** The 0.5 arming policy backfired: ambient triggers that fire
every frame (their pass counter rising `1173, 1174, ...`) re-armed the timeout
continuously, so the report window never closed and the 140-entry budget filled
with noise before you reached the real plate. The tracer now:

- caps every repeating key at 5 entries (the last is suffixed `~`), so an
  oscillating condition or a per-frame fire cannot flood the report;
- opens the capture window only on a **player-driven co-op event** — a level-2
  (`istwoplayer`/`isoneplayer`) condition change (`ARMC`) or an action-button
  press (`ARMB`). Plain fires (`ARMF`) and multi-pass steps (`STEPP`) are still
  recorded but no longer arm anything;
- the first arm wins and is never overwritten, plus a hard 60-second fallback
  (`timeout`) guarantees a dump even if nothing arms.

To diagnose a co-op plate: walk onto it, press action a few times, wait ~10 s,
then send the newest `PLATE` line.

**`probe_upgrade`.** Read-only sampler for the Extended Upgrades prototype. A
routine cannot *call* game functions, so every upgrade effect has to be wired by
hooking the game's own call and biasing its arguments — which first needs each
command's argument layout. While you play it samples the dismember, finisher and
upgrade commands (`enemy_detach_bone`, `enemy_detach_group`, `enemy_mutilate`,
`mutilate_collision`, `fatality`, `finishhim`, `healthupgrade`, `mkapowerup`,
`startanim`, `reaction`, `addexperience`, `spawnexperience`), annotates any
argument that points at a character (`eN` = char-table slot, `cN` = "char"
script reference), records the caller return addresses, and writes ONE report as
a line starting with `Mod routine: mksmk_probe: UPGRADE`. Each command is
capped (3–8 samples) so hot commands like `startanim` cannot flood it. It dumps
25 seconds after the first finisher/dismember lands, 40 seconds after the first
sampled command, or at 120 entries — whichever comes first.

To capture upgrade signatures: fight normally, kill a few enemies with blades
(so dismemberment fires), use a special move, then send the newest `UPGRADE`
line.

## 0.7.1: upgrade sampler actually reports

0.7.0's `probe_upgrade` could go silent: once every watched command reached its
sample cap the hook returned early and stopped checking the dump timers, and the
capped entries never reached the 120 budget, so no `UPGRADE` line was ever
written. The timers are now evaluated on **every** command hit (capped or not),
and a hard 40-second fallback guarantees a report. No gameplay change.

## 0.8: reports when you save

A routine script can only write to the log by stopping with an error, and
that switches it off for the rest of the session. Every probe used to guess
when to do that (an event count, a timer after the first interesting event,
a hard timeout). The guess was often wrong: reports fired before the thing
you were testing, or never.

Now every probe collects quietly and writes its report **when you save the
game**. A probe with nothing collected waits for the next save.

- `probe_events` replaces `probe_a`/`b`/`c`. It keeps the first 60 and the
  last 140 events, with a count of the ones dropped in between.
- `probe_shuffle` takes one snapshot per area you visit instead of only the
  first.
- `probe_plate` and `probe_upgrade` stop recording at their caps instead of
  reporting.

**How to use it:** play normally, test what you want, save at a statue, then
quit (Alt+F4 is fine once the save is done). Anything after your last save
isn't reported.

## 0.8.1: the right save hook

0.8.0 hooked `0xA2260`, a save path the statue never uses, so a statue save
wrote nothing. 0.8.1 hooks `0x1272A0`, the HardDisk write every save ends in.
It creates the save container (`SaveMeta.xbx`) and opens `save.dat` with
`GENERIC_WRITE`. `0x127420`, the matching read, isn't hooked: the game reads
saves at startup and right after writing one.

## 0.8.2

`probe_plate` used to stop recording at 140 entries, so a long session cut
off before you reached the plates. It now uses the shared head + tail log:
the first 60 entries and the last 140, with a count of the ones in between.

## 0.9: combat dismemberment, animation events, fatality mode

Blade kills never called the `enemy_detach_*` / `enemy_mutilate` commands
`probe_upgrade` watched. Those are level-script commands. `probe_upgrade` now
also watches the engine functions they call:

- `0x10C3B0` detach bone
- `0x10C600` detach group
- `0x10BD70` mutilate

Combat reaches them from the animation-event dispatcher `0x180D30`, the
`bodydamage` path.

The report also has:

- **ANIM**: a histogram of animation-event types (`0x180D30`'s third
  argument). It is split by player-owned (`p`) and other (`o`) entities, and
  `F` marks events in fatality mode (`0x58E068 + 0x1A0 >= 10`). Types that
  only appear with `F` point at the enhanced moves.
- **STATE**: fatality-mode state (`+0x1A0`, `+0x1A4`) and each player's
  brutality-off flag, logged when they change.

`probe_plate` now also watches `stonecolor`, so colored co-op plates show up
in its trace.

**For a useful run:**

- do some blade kills;
- go into brutality mode and do enhanced moves;
- do some air combos;
- save at a statue.

## 0.10: more reports, bigger logs, save-data watcher

- **Three reports per launch.** A script can still report only once, so the
  build ships copies: `probe_events` and `probe_savediff` report at your 1st,
  2nd and 3rd save (`#1`, `#2`, `#3`), and `probe_upgrade` at the 1st and 2nd.
  Each copy holds everything since the game started.
- **Bigger logs.** The first 100 and the last 400 events are kept (was 60 and
  140).
- **`probe_savediff` (`SAVEDIFF`)** watches the game manager `[0x5ACEBC]`,
  which is also the save data. It snapshots 32 KB of it one slice per frame,
  then keeps comparing. Every dword that changes is listed as
  `+offset:first>last(count)`. Unlock an ability, buy an upgrade or gain XP,
  then save, and the offsets that moved are those fields. Matched against
  archived `save.dat` files (see the QA console in `MKSMK.bat`), it maps the save
  file to live memory, which New Game+ and Extended Upgrades need.


## 0.12: shop, meter and health state

- **`SAVESTAT`** now also reports each player's XP, meter value and level,
  the EX flags (level slots 19-22, as four digits) and slot 27, current and
  max health, plus the max-health value, the area's health level and the
  fatality counters (`fat=discovered/performed`). Compare `fat=` before and
  after a reload to see whether discovered fatalities are kept.
- **`HEARTBEAT`** samples end with player 0's health and meter (`hp450/600 mv380`).
- `probe_upgrade` read player 0's XP from the wrong field; fixed.
- Pairs with the QA Console (`MKSMK.bat` > QA console), which reads the same
  fields live and turns each run's logs into `summary.md`.

## 0.11.1 and 0.11.2

- **0.11.1:** the per-save report (`SAVESTAT`) also shows `+E0=`, the game's
  health-upgrade count, so XP-shop purchases show up in save reports.
- **0.11.2:** the heartbeat reports every 15 minutes instead of 7.5. A script
  can only log once, so each report needs its own copy: 12 copies now cover
  the same 3 hours as 24 did, which leaves 12 more of the Recomp's 64 script
  slots for other mods. A crash now loses at most the last 15 minutes of
  samples.

## 0.11: heartbeat and per-save stats

- **`probe_heartbeat` (`HEARTBEAT#n`)** reports about every 15 minutes of
  gameplay (12 copies, about 3 hours), so a soft-lock or crash between statues
  still leaves data. Each report has a sample every ~40 seconds since the previous
  heartbeat: gameplay frames, game frame, map, XP balance, spawner
  (`sp<active>,<group>,<spawned>`), loaded enemy types and the cleared-waves
  table (`group:alive:cleared`), plus a `save@` sample for each statue save.
  If the game soft-locks, leave it running for 8 minutes before quitting.
- **`probe_savestat` (`SAVESTAT save#n`)** reports at every statue save (20
  copies): playtime, XP balance, characters, the upgrade counters (`+DC`,
  `+1C4`, `+1D0`), map and the save call's raw `ecx`/stack arguments. The
  playtime matches the label of the save.dat slot that was written.
