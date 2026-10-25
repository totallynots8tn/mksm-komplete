# MKSM Komplete+

**Mortal Kombat: Shaolin Monks, Komplete+.** A free, open fan mod pack for
[Shaolin Monks Recomp](https://github.com/OAleex/ShaolinMonksRecomp) (the static recompilation of the Xbox game)
that makes Shaolin Monks bigger, harder and more rewarding. Bigger fights,
XP that pays you for playing with style, co-op routes in single player, and
over time a real postgame.

> **Komplete** = the game you remember, finished the way it deserved.
> **The +** = everything on top: quality-of-life fixes, enhancements,
> improvements and additions, up to a Kingdom Hearts 2-style postgame.

Short name: **MKSMK**. Every mod is original Lua and metadata; no game files or
assets are included.

---

## What's in v1

| Mod | Version | What it does |
| --- | --- | --- |
| **Legendary Dark Knight Mode** (`ldk_x3`) | 3.9.6 | Three times the enemies in every spawn group, as reinforcements. Boss fights stay vanilla. Every extra enemy must fit in the memory the area has spare, so the game doesn't crash. |
| **Environmental Kill XP** (`env_kill_xp`) | 2.0.0 | Pits, spikes, saws, fire and throws off the map pay XP like normal kills, with combo multiplier and popup. In vanilla a hazard kill could cost you your combo's XP. |
| **Solo Co-op Paths** (`coop_solo`) | 0.6.2 | Opens co-op-only routes and secret areas in single player. Co-op plates work solo. |
| **Shaolin Shuffle** (`randomizer`) | 0.6.6 | Enemy randomizer: swaps enemy types between the spawn slots of each area, using exactly the vanilla enemy memory. |
| **Unlock All** (`unlock_all`) | 1.1.0 | Unlocks the full roster and extras with the game's own full-unlock mask. |

v1 was QA'd with a full campaign run through Shao Kahn and the credits on
LDK x3 + Shuffle + Env Kill XP + Solo Co-op: no crashes, no failed spawns,
no stuck waves.

## Install

1. Set up **[Shaolin Monks Recomp](https://github.com/OAleex/ShaolinMonksRecomp)
   0.2.0+** with your own legally obtained copy of the game, start it once,
   then close it.
2. Download **`MKSM-Komplete-v1.zip`** from the [latest release](https://github.com/totallynots8tn/mksm-komplete/releases/latest)
   and unzip it.
3. Double-click **MKSM Komplete Installer**, press **Install**, then **Play**.
   (Windows may warn about an unknown publisher the first time: *More info >
   Run anyway*. The installer isn't code-signed.)

No Python needed. By hand instead: in the Recomp launcher choose **Mods >
Install from file...** and pick each `.tar.xz` from the zip's `packages`
folder. Disabling a mod restores the original behavior; no mod edits your
save file.

**Testers and contributors:** `MKSM-Komplete-v1-contributor-tools.zip` on the
same release has the MKSMK Probe (diagnostics, changes nothing), the QA
recorder and the live-memory peek tool. See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## The vision

Shaolin Monks is a great beat 'em up that ends too soon and plays the same
every time. MKSM Komplete+ keeps what made it great and adds the depth it
never got: harder fights, rewards for creative kills, more ways through each
level, and a reason to keep playing after Shao Kahn.

### Roadmap

**v1: Komplete (released).** The five mods above.

**v1.1: Extended Upgrades (in progress)**
- **XP shop.** Spend XP in the existing upgrade menu on any weapon available
  at that point, health and stamina upgrades, combo extenders, new combos,
  EX moves and new fatalities. No refills or potions: upgrades only. It reuses
  the game's own upgrade entries with new text and behavior, not a new menu.
- **EX specials.** Hold L2 with a special-move input for an unlockable
  enhanced version, built from the brutality-mode move set.
- **Shuffle+.** Outsider enemies from other levels in rooms that normally
  have one enemy type, with Normal / Wild / Chaos intensity.
- Fatality-room safety and the reuse-aware memory guard from the v1.1 dev line.

**v2: the + (planned)**
- **New Game+ alternate realities.** The game's portals placed in co-op-only
  areas reload the area as an alternate reality. The story reason: the
  timeline meddling of the later Mortal Kombat games reaching back into
  Shaolin Monks. They lead to super boss fights, boss rushes and enemy rushes.
- **Kingdom Hearts 2-style postgame.** Mortal Kombat characters as real
  bosses in the existing secret fights and in new co-op secret areas, ending
  in a boss rush.
- More QoL as the reverse-engineering uncovers it.

Plans change as we learn the engine. The order follows what the
reverse-engineering makes possible.

### How it works

- **Recomp routine mods.** Shaolin Monks Recomp runs Lua scripts that hook
  addresses of the original Xbox code (before/after a function runs) and
  read or write guest memory. Each mod is a package of those scripts and a
  manifest the launcher verifies.
- **Memory-safe by design.** The game gives each enemy type a fixed model
  heap. LDK and Shuffle check every spawn against the memory actually left, so
  extra enemies never starve authored ones or crash the game.
- **Evidence first.** Every hook address and struct offset is backed by a
  disassembly or a memory capture. The probe and the QA recorder (save-file
  archive + session logs) turn each playtest into data: spawns, heap use, XP,
  save-file diffs, a heartbeat every few minutes.
- **Offline tests.** A small Lua harness emulates the Recomp runtime (its
  memory, write and instruction budgets) so scripts are tested before the
  game ever loads them.

## Contributing

Help is welcome: playtesting, reverse-engineering, Lua, docs. Start with
[CONTRIBUTING.md](CONTRIBUTING.md). It explains the project layout, how a
routine mod works, the runtime's limits, how to build and test, and how a QA
report turns into a fix.

## Support the project

**Continue? 9... 8... 7...**

I played Shaolin Monks so much I knew every fight by heart, and I always
wished for a mod that made it feel new. Nobody made one, so I'm building it:
one function, one memory address, one full playthrough at a time.

Everything here is free and stays free: no paywalls, no locked features, no
early access. What keeps it moving is time, and that's what a coffee buys:

- **A coffee**: a late night of reverse-engineering, the kind that turned
  hazard kills into XP.
- **A few coffees**: a full QA playthrough, so an update ships without
  crashing your run.
- **Next unlock**: v1.1, the XP shop. Spend your XP on weapons, combos, EX
  moves and fatalities.

### [Insert coin: buy me a coffee](https://buymeacoffee.com/S8tn)

Can't chip in? That's fine. Star the repo, share a clip of a 3x fight, or
send a bug report. It all keeps the project alive.

---

## Credits

- **[Shaolin Monks Recomp](https://github.com/OAleex/ShaolinMonksRecomp) by
  OAleex**: the PC port this pack runs on, and its routine-mod support. None
  of this exists without it.
- **Roster idea:** the future-roster ideas are inspired by **RelaxDirk's
  UMKSM**. Nothing from UMKSM is implemented or included: v1 is only our own
  mods on top of the Recomp. No affiliation is implied.

## Legal

- **Unofficial fan mods.** Not affiliated with, endorsed by, or sponsored by
  Midway, Warner Bros. or NetherRealm Studios. *Mortal Kombat* and *Shaolin
  Monks* are trademarks of their respective owners.
- Requires a **legally obtained** copy of Mortal Kombat: Shaolin Monks and
  **Shaolin Monks Recomp 0.2.0+**. This package ships no game files, no
  emulator and no copyrighted assets, only original Lua scripts and metadata.
- License: [MIT](LICENSE).
