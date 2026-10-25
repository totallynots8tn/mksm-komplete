# Solo Co-op Paths 0.6.2

Opens co-op-only routes and secret areas in single player.

Level scripts choose between their solo and co-op layouts with two commands:

| Command | Handler | Game answers |
| --- | --- | --- |
| `istwoplayer` | `0x740F0` (thunk `0x12E55`) | game mode == 1 (co-op) |
| `isoneplayer` | `0x740B0` (thunk `0x156CD`) | game mode == 0 (single player) |

0.1 only flipped `istwoplayer`. In single player both commands then said
yes, and scripts kept the solo layout, which is why plate unlocks didn't
change. 0.2 makes single player answer `istwoplayer` = yes and
`isoneplayer` = no. Co-op and versus are untouched.

Cameras, respawn, tether and everything else the engine decides from the
real game mode stay single player.

**Experimental.** A co-op plate may still need two bodies on two plates, or
co-op "stone power" (`addstonepower` / `stonepowatleast`). If a plate still
won't open, run the **MKSMK Probe** while standing on it and send the log.
Its script tracer shows which of those commands the plate uses. If you get
stuck, disable the mod and reload the checkpoint.

Requires Shaolin Monks Recomp 0.2.0 or later.

## 0.3

The probe's script tracer showed levels poll `istwoplayer` every frame with
more than one kind of argument. 0.2 only answered calls that passed a
character reference, so half the checks still said "no". 0.3 answers every
call in single player.

## 0.4

The 0.5 probe's plate tracer showed a problem with 0.3. Map triggers walk
their condition commands at `0x16F4B0`, and the pressure plate's gate
triggers (`T102`/`T103`) use `isoneplayer` as a **condition**. 0.3 forced
`isoneplayer` to "no" for every caller, so those conditions never passed and
the plate sequence looped (`F24c1…c5`, a repeating objective countdown)
without opening.

0.4 splits the answer by caller:

- `isoneplayer` asked **inside the trigger-condition walk** (a live return
  address into `0x16F4B0` is on the stack) now answers honestly — single
  player — so solo-progression triggers like `T102`/`T103` can pass.
- `isoneplayer` asked by anything else (the layout scripts) still answers
  "no", so co-op layouts and secret routes stay open.
- `istwoplayer` still answers "yes" everywhere in single player.

This is a new combination 0.1 and 0.3 never tried. It is still a hypothesis:
if the plate genuinely needs two bodies on two plates, no player-count answer
will open it. Test the same plate with 0.4; if it still won't open, keep the
**MKSMK Probe** installed, stand on the plate, press action a few times, wait
about 10 seconds, and send the newest log — the `PLATE` line shows whether
`T102`/`T103` now pass.

## 0.5

0.4 made the plate's co-op gate triggers (`istwoplayer` / `isoneplayer`) fire
in solo, but the plate still would not open. The probe's `PLATE` line showed
why: the co-op gates pass (`F86`/`F127`/`F128`/`F129`), but the plate's
**action-button gate** reads `actionButton(0)=0` — player 1's action press
never registers when the trigger samples it (`stone=0`, `mask=0`).

0.5 adds two things.

**Plate condition rewrite (functional).** Map triggers (manager `[0x682020]`,
records `0xD8` apart) fire when every condition in their list passes: `0x16F4B0`
walks `[rec+0x58]` conditions, command indices at `[rec+0x5C]`, args at
`[rec+0x60]`. Within any trigger whose list contains `actionButton` (the plate
gate), 0.5 rewrites a **player-2 condition in place into a copy of the
player-1 condition** (command index + arg), so player 1 alone can satisfy a
gate authored for two players. The rewrite is cached per record and re-armed
when the trigger manager changes (area reload). Set `REWRITE_PLATE = false` in
`coop_solo.lua` to keep 0.4 behaviour only.

*RE caveat:* `actionButton` (`0x146A1`→`0x2AE20`), `buttonthrough` and
`OtherPlayerInvisible` pick the player from the **activator** (char index at
`[ref+0x10]`, passed by `CHECK`), not from the condition arg; `eventnotcomplete`'s
arg is an event id and `stonepowatleast`'s arg is a threshold. So for a plate
whose only gate is `actionButton` this rewrite is a **no-op** — the real blocker
is *why* `actionButton` returns 0, not a player-2 condition.

**Plate diagnostic (optional, read-only).** `coop_solo_debug.lua` ships with the
mod and writes ONE report to the session log, then disables only itself
(coop_solo keeps running). Set `DEBUG = false` at the top of the script to ship
it inert. It is listed before `coop_solo.lua` in the routines so it snapshots
the original condition list before the rewrite runs.

## 0.5.1

The 0.5 diagnostic kept only the first 10 `actionButton` calls from any
trigger. Standing on a plate fills that in a fraction of a second, before you
press anything. 0.5.1 counts every call per trigger instead and reports which
step of `actionButton` (`0x2AE20`) refuses the press:

1. **busy**: the fatality manager says the player is busy. `[0x58D6A8]`
   slot `+0x310 + [entity+0x68]*8`, entity field `+0x23C` matches one of two
   per-character values at `0x5999FC + charID*0x6C`.
2. **press**: the player's controller must hold bit `0x2`. Port
   `[0x50FFEC + idx*8]`, buttons `u16 [0x67C658 + port*0x98 + 0x26]`. The
   report ORs together every button word it sees (`btn`), so it shows which
   bits your action button really sets.
3. **gate**: byte `0x4E67C4` must be 0.
4. **state**: char state `[entity+0x1E04]` must be 0, 1, 0x76, 0xC7, 0xC6
   or 0x69.

`CHECK` stops at the first failing condition. So `T39`
`{eventnotcomplete:17, actionButton}` never asks `actionButton` once event 17
is complete, which the earlier captures showed. `T24` `{actionButton}` is the
plate to test.

## 0.5.2

0.5.1's report showed 5011 checks of `T24`, all from player 1, never busy,
gate and state always fine, and **not one button bit** in the word
`actionButton` reads. The Recomp log shows A pressed 14 times in the same
window.

Recomp feeds an original Xbox pad: a digital word (d-pad in bits 0-3,
start/back/stick clicks in bits 4-7) plus 8 analog bytes for A, B, X, Y,
black, white and the triggers. Bit `0x2` of that digital word is
**d-pad down**, so the plate may want d-pad down rather than a face button.

0.5.2 logs, whenever a button changes during a plate check, the raw XInput
bytes the game polls (`0x63ABC8 + port*0x16`) next to the pad manager's
block (`0x67C658 + port*0x98 + 0x20..0x3F`). The report is now written
**when you save the game**, so it no longer fires early or times out.

## 0.5.3

0.5.2 hooked `0xA2260` for the save, but a statue save never runs it, so no
report was written. 0.5.3 hooks `0x1272A0`, the HardDisk write that every save
ends in: it creates the save container and opens `save.dat` for writing.

**To test the plate:**

1. Stand on the plate.
2. Press d-pad down a few times, then each other d-pad direction, then A,
   B, X and Y.
3. Save at a statue, then quit.

The `PLATE052` line in the log has everything.

## 0.5.4

The 0.5.3 report (all five reports arrived at the statue save) settled the
controller question:

- The word `actionButton` reads is the game's own button mapping. A sets
  `0x40` and X sets `0x80`.
- Bit `0x2` is **d-pad down**. Pressing it in the save menu made
  `actionButton` pass (char state `0x76`).
- The help text agrees: "Ko-op Switches: There are colored plates in some
  levels that you will need an ally to use."

So a colored plate fires when the player standing on it presses d-pad down
in an allowed state (0, 1, 0x76, 0xC7, 0xC6 or 0x69). On the plaques you
pressed X/B/Y, which are not checked, and sometimes your state was 6, which
is not allowed.

0.5.4 answers whether a plate fires in solo:

- Triggers are counted per map (`m<map>T<index>`).
- Every d-pad-down press on a plate is detailed: state, busy, gate and
  result.
- The trigger's fires (`0x16F560` returning 1) and event runs (`0x16ED90`)
  are counted.
- Raw pad bytes are logged when the game-button word changes on a plate.

**To test:**

1. Stand still on a colored plate. Press d-pad down once, then wait 2
   seconds. Do this three times.
2. If there's a second plate, step onto it and repeat.
3. Watch whether anything lights up or opens.
4. Save at a statue, then quit.

## 0.6: colored plates work in single player

The co-op plates don't use a button: you stand on them. The game's help text
says: "Ko-op Switches: There are colored plates in some levels that you will
need an ally to use." `actionButton` was the wrong lead. Those triggers were
other things, like the save statue, whose action input is d-pad down.

How a colored plate works:

- **The plate** is a map trigger with the condition `stonecolor:C`
  (`0x15574` → `0x20B90`). It passes only when the activating player's
  color, `[[entity+0x2B6C]+4]` (set by `setspawncolor`), equals `C`.
- **When it fires**, it runs events such as `addstonepower` (adds its amount
  to the stone power at `0x581B48`, which only resets when a level resets) and
  `gameevent` (sets event flag `[[0x5ACEBC]+0x4874+id]`).
- **The door** checks `stonepowatleast:N` (power ≥ N) or `eventcomplete`.

In single player the second player's color never stands on its plate, so the
door never opens. 0.6 lets a player (activator index 0 or 1) pass
`stonecolor` of any color in single player. Stand on each colored plate in
turn and the stone power adds up. Enemies, co-op and versus keep the real
check. Set `SOLO_STONES = false` in `coop_solo.lua` to turn this off.

The diagnostic (`PLATE060`, written when you save) shows:

- every co-op trigger per map with its checks, passes and fires;
- each `stonecolor` check (plate color, your color, result);
- each `addstonepower` and `gameevent` with the trigger that ran it;
- each `stonepowatleast` check against the power;
- every event-flag change, frame by frame.

**To test:**

1. Find a set of colored plates.
2. Stand on one until something happens, then on the other.
3. Check whether the door or secret opens.
4. Save at a statue, then quit.

## 0.6.1: plate latch

The Wu Shi plates are event flags, not colored stones. Standing on a plate
sets flag 28 or 29 (`[[0x5ACEBC]+0x4874+id]`, through `gameevent`).
Stepping off clears it 0.3 to 0.7 seconds later, and the secret wants both
flags at the same time.

In single player, a flag cleared within 10 seconds of being set is now held
for about 15 seconds more. That gives you time to step from one plate to
the other. Flags that stay set longer, co-op and versus are untouched. Set
`SOLO_LATCH = false` in `coop_solo.lua` to turn it off.

## 0.6.2: release build

Confirmed in Wu Shi and the portals. The plate diagnostic
(`coop_solo_debug.lua`) is no longer shipped. It stays in `mods/_build/src`
for future investigations.
