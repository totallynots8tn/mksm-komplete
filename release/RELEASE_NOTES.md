# MKSM Komplete+ Release Notes

Mod pack for **Mortal Kombat: Shaolin Monks** on **Shaolin Monks Recomp 0.2.0+**.
All mods are free, original Lua + metadata; no game assets are redistributed.

Status key: **Works** (playable, validated) - **Experimental** (functional but
incomplete / under investigation) - **Prototype** (scaffold, effects not wired)
- **Diagnostic** (changes nothing in-game; logging only).

## v1.2 test build (2026-10-27, `release/v1.2/`, not published as a release)

v1.1's frozen packages (Shuffle 0.6.6, Env Kill XP 2.0.0, Unlock All 1.1.0,
Solo Co-op 0.6.2) plus:

| Mod | Package | Version | Status | Note |
| --- | --- | --- | --- | --- |
| Legendary Dark Knight Mode (x3) | `ldk_x3` | 3.11.0 | Works (QA run 2026-10-26 through Goro's Lair) | Goro's Lair groups fill to 9-11 Onis; the fatality room stays vanilla. |
| Extended Upgrades: XP Shop | `mk_upgrade` | 0.11.1 | Experimental | Health, Stamina, weapons, fatality reveal and EX moves (L2 + special: 10x damage, fast recovery, half a bar; no hitstop). |
| Time Rifts | `time_rifts` | 0.2.0 | Experimental (not yet seen live) | The co-op rift portals in Wu Shi and Goro's Lair reload their area for another fight. Needs Solo Co-op Paths. |
| MKSMK Probe | `mksmk_probe` | 0.12.0 | Diagnostic | 42 of the 64 routine scripts; the whole set uses 49. |

Offline checks 2026-10-27: XP shop, Time Rifts, env kill, co-op and probe suites
pass; the LDK x3 spawn simulator is clean (0 crashes, 0 stuck groups, max 225
writes per hook call) in every mode, alone and with Shuffle 0.6.6.

## v1 (published)

| Mod | Package | Version | Status | Known issue (one line) |
| --- | --- | --- | --- | --- |
| Legendary Dark Knight Mode (x3) | `ldk_x3` | 3.9.6 | Works (confirmed in a new-game run) | Crowded rooms can lag on slower PCs. v1 ships x3 only to keep QA to one variant; the x2/x4 packages are kept in `release/v1-retired`. |
| Shaolin Shuffle (Enemy Randomizer) | `randomizer` | 0.6.6 | Works | Swaps types between spawn slots; areas with one regular enemy type stay as they are. Outsiders and intensity levels come in v1.1. |
| Unlock All | `unlock_all` | 1.1.0 | Works | None reported; memory-only, so disabling restores the profile's real unlock state. |
| Environmental Kill XP | `env_kill_xp` | 2.0.0 | Works | Enemies the game flags as no-XP still give none; versus mode has no XP. |
| Solo Co-op Paths | `coop_solo` | 0.6.2 | Works | Confirmed in Wu Shi and the portals; other co-op spots are untested. |
| Extended Upgrades | `mk_upgrade` | 0.1.0 | Prototype | Prototype spine only - every gameplay effect is inert (zero memory writes), so nothing changes in-game yet. |
| MKSMK Probe | `mksmk_probe` | 0.11.0 | Diagnostic | Reports at your first three saves, logs XP and playtime at every save, and writes a heartbeat about every 7.5 minutes of play, so a soft-lock between saves still leaves data. |

## Compatibility

- LDK and `randomizer` are compatible and can be enabled together.
- v1 has one LDK variant (x3). Boss Invasion is built in; the old
  `ldk_bosses` mod is retired.
- The three Shuffle variants work the same way: install all three, enable one.
  LDK works with any Shuffle variant.
- Mods change game memory only where stated; disabling a mod returns original
  behavior. No mod edits save files.

## Install

Recomp launcher - **Mods** - **Install from file...** - select the `.tar.xz`
from `mods/<mod>/dist/`, enable it, and start the game.

## Validation status (v1 release candidate 2, 2026-10-24, not published)

- **Packages:** the v1 set in `release/v1/` (LDK 3.9.0, Shuffle 0.6.2, Env Kill XP, Unlock All, Solo Co-op, Probe) passes manifest and
  file SHA-256 checks.
- **Runtime:** Shaolin Monks Recomp 0.2.0 booted with every mod enabled
  and reported no script errors. LDK x3 then held up through a new-game
  playthrough (2026-10-24).
- **Offline tests:** the spawn simulation (normal, big level, Wu Shi, boss
  levels) passes for LDK x2/x3/x4 and Shuffle with no crashes, stuck groups
  or script errors. So does Shuffle 0.8's Goro's Lair outsider mode for all
  three variants, alone, with LDK x3/x4, and with a cutscene evicting the
  outsider. Every room got an outsider, and every authored enemy spawned. The co-op plate and environmental XP tests also pass.
- **Memory-write cap:** LDK x4's worst case is 254 memory writes per
  callback, under the runtime's limit of 256. The 12-entry group cap bounds
  it.
- **Shelved:** Pause Save (a save-anywhere mod) didn't trigger in game, so
  it isn't in the release.
- `analysis/final_validate.py` still has stale runtime fixtures from LDK 1.3.0.
  They fail; the packages themselves don't.

## Source of the v1 packages

The LDK x3 and Shuffle packages in v1 were built from the memory-guard patch 4
snapshot that passed QA (`release/snapshots/mksmk-source-v1-patch4.zip`,
attached to the v1.0.0 release). The probe 0.11.0, the installer and
`modtool.py` come from this repository. `mods/_build` on the main branch is the
v1.1 development line and may differ from the v1 packages.

## Legal

Unofficial fan mods. Not affiliated with or endorsed by Midway / Warner Bros. /
NetherRealm. Requires a legally obtained copy of the game and Shaolin Monks
Recomp 0.2.0+. The UMKSM roster idea is credited to RelaxDirk's UMKSM; no files
from it are included and no affiliation is implied.
