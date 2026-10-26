# MKSM Komplete+ roadmap: v1.5 and v2 (working notes, 2026-10-25)

This was planned as v1.1, and its scope grew. Nothing here is committed; all of it is local work in `mods/_build`. "Live" means it was checked in the running game, on a scratch copy of the saves. "Sim" means the offline simulator in `mods/_build/tests`.

## v1.5: what is done, and what each piece still needs

| Piece | Build | State | Evidence | Still needs |
|---|---|---|---|---|
| **XP shop: Health + Energy** | `mk_upgrade` 0.2.0 | done | live (ES): buys work, XP deducted, no refill, combo slot restored, HUD shows the extra bar; offline test of 13 cases; strings fit all 5 languages | your QA run: max HP after the next area; co-op |
| **Shuffle+ / LDK: v1 memory fixes in the dev line** | LDK 3.10.0, Shuffle 0.9.0 | done | sim: Goro's Lair CARRY case 180/180 spawns, the old dev build 60/180 (the soft-lock); full scenario matrix 0 stuck / 0 crashes | your QA run through the Goro's Lair fatality room |
| **Fatality-room exemption** | LDK 3.10.0, Shuffle 0.9.0 | in the build (from 0.8.2) | its three handler addresses re-verified against the script table (`isfatalityfull`, `fatalityover`, `fatalitytutor`) | same QA run |
| **Wider outsider pool ("true random" among regular enemies)** | Shuffle 0.9.0 Wild/Chaos | done | sims: an outsider in 18 of 18 rooms per variant, 0 stuck | QA on Wild or Chaos |
| **Reptile as boss (v1 patch 4)** | LDK 3.10.0, Shuffle 0.9.0 | ported | table entry only | none |
| Shop: buy fatalities (reveal the input) | not built | design ready | REPORT §8: the list gates nothing | live: does the list survive a save/load? |
| Shop: EX specials | `mk_upgrade` 0.3.0 | built (experimental effect) | REPORT §9.2: GetLevel boost on LT hold, flag slots 19–22, one bar per press; offline suite passes | controller test: top-tier variant via L2 + special; ~ vs | slot convention |
| Shop: weapons | `mk_upgrade` 0.3.0 | built (experimental) | REPORT §9.3: FindAndRemove name redirect, gear ladder slot 27, LK/KL only | QA: confirm type-name mapping (LK kama01/staff, KL broadsword/sword) and fizzle when the map lacks the type |
| Shop: combo extenders | not started | none | none | RE |

**Suggested v1.5 release set:**
- LDK 3.10.0, Shuffle 0.9.0 (Normal/Wild/Chaos), XP Shop 0.3.0, plus the v1 mods;
- the probe 0.11.1 for QA.

That makes 60 of the 64 routine scripts with the probe.

**One QA session covers it all:**
1. Play through Goro's Lair, including the fatality room.
2. Buy Health and Energy in Mejoras, an EX unlock in Habilidad and a weapon tier in Equipo (LK/KL).
3. Hold L2 and throw a special (EX, one bar per press); pick up a weapon and watch what it becomes.
4. Enter a new area.
5. Save at a statue.

## v2: groundwork found today

- **MK characters as enemies without boss AI.** The game already has multi-instance, MK-styled common enemies: rows whose instance pool (`+0x08`) is above 2. The loaders `0xC1DB0`/`0xC1B10` take it next to the model:
  - 80 "Scorpion (enemy)" (pool 14), preloaded with ordinary enemies in maps 1, 5, 7, 8, 25 and 30;
  - 77 (pool 8), in maps 15, 24, 103, 104 and 107;
  - 87 Kitana alt (pool 10) and 77, in maps 234–235;
  - 76 Johnny Cage, already safe as an LDK invader.
  
  The boss rows (63 Kitana etc., pool 2) carry the scripted boss AI that soft-locked LDK 3.9. **First step:** add 80/77/87 to the outsider and invader pools behind a test, then check live that they fight like grunts.
- **VS fighters** (rows 81–84, 88–90, pool 1, with alternate costumes) are the second route if a VS-style CPU AI is needed.
- **Playable MK characters, later:** see `analysis/xbox_roster/REPORT.md` ("Playable UMKSM characters").
- **Postgame and alternate realities:** no RE yet. The ability slots 23–26 read by `0x1DA00` and slot 27 (max level 5) are still unexplained, and are worth a look as unlock state.

## Where things are

- Shop RE and design: `analysis/xp_shop/REPORT.md`. Tree dump: `analysis/xp_shop/out/mpd_tree.csv` (`tools/dump_mpd.py`).
- Sources: `mods/_build/src/upgrade.lua`, `core.lua`, `ldk_body.lua`, `randomizer_body.lua`; tests in `mods/_build/tests/`.
- Built packages are in `mods/*/dist/` (gitignored): `mk_upgrade-0.3.0`, `ldk*-3.10.0`, `randomizer*-0.9.0`, `mksmk_probe-0.11.1`.
