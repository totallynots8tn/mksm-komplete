# Extended Upgrades — perk & options design

**Goal:** decide how "Extended Upgrades" hands players perks and choices, given that the extra XP from **Legendary Dark Knight (LDK)** mode should buy more than the vanilla move upgrades. This is a design document + mockups, **not** the mod. Perks in scope: blade dismemberment, "EX" moves reusing brutality-mode enhanced moves, a stamina meter, and anything else that fits a "more XP → more moves" economy.

**Read first (done):** `mods/_build/readme/upgrade.md`, `mods/_build/src/upgrade.lua`, `analysis/xbox_roster/REPORT.md` (§"Brutality / enhanced moves leads"), `ShaolinMonksRecomp-0.2.0/docs/MODS.md`, `mods/_build/readme/env_kill_xp.md`, `ShaolinMonksRecomp-0.2.0/tools/prepare_language_pack.py`.

**Evidence base:** the game's own text tables, dumped read-only from the Xbox ISO this round → `out/text_game.csv` (1,751 entries), `out/text_system.csv` (12), `out/repurpose_shortlist.csv` (371 candidates). Every text claim below cites a **table index** and is reproducible from those CSVs. Tooling in `tools/`.

**Rev 2 (this edit):** (1) dismemberment re-ranked from "most feasible" to **needs combat-path RE** — probe logs show weapon kills never call the detach functions (they are level-script commands); combat damage runs `0x17877F → 0x175037 → 0xBFB81 → applydamage 0x153DC0 / 0x153E9C`. (2) Added the **Air Combat perk group** (perks 19–23) from text indices [492]/[973]/[981]/[992]/[1415]. Every rev-2 passage is tagged "(rev 2)". Everything else is unchanged.

---

## The two hard facts that shape every option

**(F1) Routine mods can read/write ANY guest memory, but can only *hook* whitelisted addresses.** `MODS.md` ("Routine scripts") gives `game.read_*/write_*` on any valid committed address; the `routine_targets.txt` whitelist (27,716 addresses) only constrains where a `before/after/replace` callback may attach. Verified this round:
- **Writable-but-not-hookable** (effect *fields* — fine, we write them directly): fatality-mode manager `0x58E068` (+0x1A0 active / +0x1A4 over), per-player manager `0x58D6A8` (brutality-off flag `+0x318+(idx-1)*8+4`, count `+0x388`), meter get/set/level/max `0xC9710/0xC9740/0xC9770/0x82EA0`. *(Addresses cited from `analysis/xbox_roster/REPORT.md`; none are in `routine_targets.txt`.)*
- **Hookable** (we can intercept the game doing the thing): dismemberment `enemy_detach_bone 0x1A33E0`, `enemy_detach_group 0x1A34A0`, `mutilate_collision 0x1A3450`, hazard `bodydamage 0x180CA0`, `applydamage 0x153DC0`, animation `startanim 0x18AAC0`, XP award `addexperience 0x13A53`, poll ticks `0x1D23F0`/`0x1D2600`, menu text path `cLIST::CopyTextEntry 0x1B5880` and `swfBaseMenu::InitTextList 0x1B0F70`.
- **Not hookable** (so we cannot *call* them): the XP/combo popup path `RegisterKill 0x7E750` / combo-end `0x7EA94`, and in-game text draw `ProcessIngameTextData 0xC38D0` / `ProcessMCTextData 0xC3A20`. *(From `env_kill_xp.md` + `fnnames.json`; confirmed absent from `routine_targets.txt`.)*

→ **Consequence:** a routine mod can *force* an effect by writing a field, and can *ride* an event by hooking it, but it can **never pop up a message on demand**. Any in-game feedback must either (a) ride an event the game already fires, or (b) intercept the menu-text path (`0x1B5880`, hookable) and substitute a string.

**(F2) A content mod that replaces text record 156 conflicts with every language pack.** `MODS.md` ("Compatibility"): "Mods cannot replace the same file, archive record, voice or embedded font." The main text table is **GAMEDATA.WAD record 156** (EWDF stamp `b3f9f220`, internal name `h.bin`, 1,751 entries — found this round via `tools/find_text_tables.py`); the system table is **record 158** (12 entries). A language pack also replaces record 156. So any option that rewrites game text **cannot co-exist with an installed language pack**, and turns the mod `type: mixed`. This is a real cost, not a detail.

---

## (A) Text-table findings

### A.1 The tables
| table | record | entries | bytes | keyed (hash) | key==0 | CSV |
|---|---|---|---|---|---|---|
| game text | 156 (EWDF `b3f9f220` "h.bin") | **1,751** | 65,477 | 139 | 1,612 | `out/text_game.csv` |
| system text | 158 (raw, count=12) | 12 | 844 | 0 | 12 | `out/text_system.csv` |

Format (verified by round-trip in `prepare_language_pack.decode_text_table`, copied verbatim into `tools/`): `u32 count`, then per entry `u32 key, u32 len, len bytes` (cp1252, NUL-terminated). "keyed" entries carry a non-zero 32-bit hash — these are looked up **by string hash** at runtime (story subtitles, ability-gained toasts, combo-rank words). `key==0` entries are looked up **by index** (menus, move lists, labels).

### A.2 Button-glyph legend (proven from the table itself)
The font renders certain cp1252 bytes as button icons. Proven by the pairing of index 466–469 with 470–477:
| glyph | button | proof |
|---|---|---|
| `*` | **Square** | [466] `* Special` ↔ [470] `%s\n\nSquare Special %d Max` |
| `~` | **Triangle** | [467] `~ Special` ↔ [472] `Triangle Special` |
| `\|` | **Circle** | [468] `\| Special` ↔ [474] `Circle Special` |
| `^` | fourth attack / **throw / up** | [469] `^ Special` ↔ [476] `^ Special`; [24] `^ throws`; [30] `^ to pickup weapon` |
| `$` | special-move **modifier** (GUESS: R1) | [26] `Special Moves\nHold $ + any attack` |
| `#` | **Block / Lock-On** (GUESS: L1) | [9] `Lock-On and Block\nHold #` |
| `` ` `` | change target (GUESS: right-stick) | [9] `` ` changes target `` |
| `=` | **Accept / Start / Jump** | system[11] `{}  Move    =  Accept`; [10] `Press = to jump` |
| `@` | on-screen prompt marker (GUESS) | [105] `... fatality stunner.       @` |

Mockups must reuse these glyphs; a replacement string that says "Square" where the original used `*` will render wrong.

### A.3 The pause-menu upgrade/moves structure (key==0, index order)
- Tabs / chrome: [396] `Main`, [397] `Moves`, [398] `Info`, [399] `Purchase`, [400] `Fatalities`, [411] `Select Moves Type`.
- Move categories: [461] `Specials`, [462] `Platform`, [463] `Combos`, [464] `Skill`, [465] `Team`; basic groups [402] `Basic Moves`, [403] `Basic Attacks`, [404] `Air Attacks`, [405] `Running Attacks`.
- **Purchase descriptions are format strings**: [470]–[481], e.g. [471] `%s\n\nSquare Special %d level Up %d`, [479] `%s\n\nCombo moves %d level Up %d`. The `%s` is the move name, `%d` the level/cost. These are the strings shown when you buy a vanilla upgrade.
- Purchase **state** strings: [446] `???`, [447] `Not Upgraded yet`, [451] `Not Available`, [455] `Upgrade`, [458] `Purchased`, [459] `Empty`, [460] `Upgraded to Max`, [406] `Upgrade Available for Purchase`.
- Move-name slots: [520]–[569] etc. are `Special 1..5` / `NA` per character (32× `Special 1`, 172× `NA` — see A.5).
- Move-description entries: real ones look like [570] `Fireball.\nLiu Kang fires a single, firey projectile.\n$ + *` (format `Name.\nDescription\nInput`).

The exact strings the task named — **"Moves List Menu", "How To Do Move", "Move Description" — do not exist verbatim** (searched: 0 hits). The real menu uses [397] `Moves` → [411] `Select Moves Type` → categories [461]–[465]; the move-detail panes are the per-move description entries ([570]+). GUESS: the task's names were paraphrases.

### A.4 Fatality Level menu (a real, native 4-level selector)
[1632] `P1 Fatality Level`, [1633] `P2 Fatality Level`, [1634] `Fatality Level 0`, [1635] `Fatality Level 1`, [1636] `Fatality Level 2`, [1637] `Fatality Level 3`. This is an existing VS-mode selector with 4 discrete levels and per-player headers — the closest thing the game already has to a "pick a tier" UI. (Reachability in story/LDK is GUESS/needs-RE; it reads as a VS options row.)

### A.5 Unused / duplicate re-purpose candidates (`out/repurpose_shortlist.csv`, 371 rows)
| category | count | indices | why re-purposable |
|---|---|---|---|
| **`(PH)` move placeholders** | **197** | 574–1301 | Cut/unused move-list entries, e.g. [574] `(PH) Liu Kang Fireball 5 \nDescription\nKey Sequence`, [578] `Teleport 4.\nTBD\n$+*+*+*+*`. Already in the table with stable indices; text is placeholder. GUESS: most are unreachable in normal play (the Moves list shows only moves a character has), so rewriting them is *safe* but may never display — needs RE to confirm which indices map to a visible pane. |
| `NA` filler | 172 | scattered | Padding move slots; same caveat as (PH). |
| Debug/internal menu labels | 37 | 1603–1639 (+363,364,395,412–423) | [1603] `Main Menu`, [1610–1612] `Camera: Close/Normal/Panoramic`, [1613–1620] ability names, [1638] `God Mode On`, [1639] `God Mode Off`, [414] `Debug Stuff`, [417] `Free Cam`, [422] `Warp Player`. GUESS: retail-inaccessible debug strings — free to repurpose, but again only useful if something displays them. |
| Combo-rank popup words | 20 | 1640–1659 | **keyed** toasts the combo system fires: [1640] `Excellent`, [1641] `Superb`, [1642] `Outstanding`, [1643] `Impressive`, [1644] `Exceptional`, [1645] `Superior`, [1646] `Phenomenal`, [1647] `Flawless`, [1648] `Destructive`, [1649] `Savage`, [1650] `Chaotic`, [1651] `Catastrophic`, [1652] `Lethal`, [1653] `Fatal`, [1654] `Unbelievable`, [1655] `Outrageous`, [1656] `Ludicrous`, [1657–1659] `Impossible`×3. These **are** shown in-game (combo feedback). |
| Duplicate key | 2 | 1658, 1659 | `Impossible` repeats with the **same hash key `3d85cdbc`** as 1657 → two of the three are redundant. Cleanest single re-purpose target in the table. |
| Ability-gained toasts | 12 | 50,74,84,88,91,98,100,108,109,138,352,407 | **keyed** "you got a thing" popups: [98] `Fatality Obtained!...`, [91] `Brutality Obtained!...`, [88] `Multality Obtained!...`, [100] `You have obtained the Fist of Ruin!...`, [108] `Double Jump ability has been gained!...`, [407] `Congratulations! ...gained enough experience to acquire new abilities.` These are the natural template/wording for a perk-unlock toast — but they fire on game events, not on demand (F1). |
| Upgrade fmt strings | 12 | 470–481 | The `%s\n\n... level Up %d` purchase lines (A.3). |
| Platform ability names | 8 | 1613–1620 | `Double Damage`, `Double Jump`, `Fist Of Ruin`, `Long Jump`, `Monkey Swing`, `Shield`, `Wall Climb`, `Wall Run` — the game's existing "platform ability" vocabulary; good naming precedent for perks. |

**Reachability caveat (applies to B/C/E):** which index is drawn in which pane is determined by game code we have not reversed. The `(PH)`/`NA`/debug entries are *textually* free to reuse, but a replacement only becomes **visible** if some menu actually renders that index. Confirming index→location is RE work (Section E). The **combo-rank words [1640–1659] and the keyed toasts are the only entries we can be confident are displayed**, because the combo/ability systems fire them by hash during normal play.

---

## (B) Option surfaces, ranked

Scoring axes: player choice, discoverability, RE burden, risk, language-pack co-install. Effort S/M/L.

### ⭐ Rank 1 — **A+D hybrid: passive XP-threshold unlocks, shipped as named package variants** *(RECOMMENDED)*
- **How it works under the constraints:** the existing spine (`upgrade.lua`) already watches per-player XP (`manager+0x48F0+player*0x50`), keeps a monotonic lifetime total, and flips `owned[player][id]` at each threshold. Perks apply by **writing the effect field / riding the hookable event** (F1) — no UI. Player *choice* comes at **install time**: ship 2–3 packages (`Extended Upgrades: Brutal`, `: Classic`, `: Hardcore`) whose `UPGRADES` tables enable different perk sets / curves; declare `conflicts` so only one is enabled (`MODS.md`).
- **Text/menu entries re-purposed:** **none** (no record-156 replacement). Discoverability is out-of-game: Krypt catalog `name`/`summary` + `README.txt`.
- **What Claude must RE:** only the **per-perk effect targets** (Section E) — the same probe work already scoped for `probe_upgrade`. No menu/purchase/input RE.
- **Player UX:** zero friction; perks "just happen" as you play LDK and bank XP. No way to see/toggle them in-game (mitigated by README + variant names). Feels like the game getting bloodier the deeper you go.
- **Risk:** **lowest.** No content mod → no language-pack conflict, no save/upgrade-state interaction, no desync. Purely additive memory writes gated on a monotonic counter.
- **Effort:** **S** (spine exists; add effect writes once RE lands) + **S** packaging per variant.
- **Depends on:** Lua-only + RE(effect targets). Packaging for the variants.

### Rank 2 — **C: in-game toggle combos + menu-text readout via `cLIST::CopyTextEntry`**
- **How:** read pad state from guest memory at the poll tick (`0x1D23F0`, hookable) to detect a button combo (e.g. hold `#`(L1)+`$`(R1)+D-pad) that cycles a perk on/off; persist to a mod-owned memory scratch. **Feedback:** hook `cLIST::CopyTextEntry 0x1B5880` (hookable) so that when the player opens **Moves/Info**, the mod substitutes a re-purposed string index carrying live status (e.g. an `(PH)` slot rewritten to `Decapitate  ON`). Optionally also force a **combo-rank word** [1640–1659] on the next combo as a transient toast (needs the rank variable — RE).
- **Entries re-purposed:** status lines from the `(PH)`/debug pool (A.5) for the menu readout; combo words [1640–1659] for the transient toast. A **content mod** is needed for clear wording (→ language-pack conflict, F2); a **no-content-mod** fallback maps each perk to an existing combo word (cryptic but zero-conflict).
- **What Claude must RE:** pad-state address + layout; `cLIST::CopyTextEntry` args (which text index, which list slot) and whether substituting the index is stable; the combo-rank variable behind [1640–1659]; which text index renders in a visible pane.
- **UX:** real runtime choice + a native-looking readout in the pause menu. Discoverable once you know the combo (README).
- **Risk:** medium — touches the menu-text path and (optionally) the combo popup; a bad index substitution could garble a menu. No save writes.
- **Effort:** **M** (toggle logic) + **M** (menu-text hook) + RE.
- **Depends on:** Lua + RE(pad state, text path, rank var); content mod optional (conflicts with language packs if used).

### Rank 3 — **B: re-purpose the upgrade shop (content mod rewrites purchase text + Lua remaps the effect)**
- **How:** a content mod rewrites the purchase **format strings** [470]–[481] and specific move-name/description slots to present perks as buyable items; Lua detects the purchase (a vanilla "upgrade bought" flag flipping in memory) and applies the perk effect instead of / in addition to the vanilla one.
- **Entries re-purposed:** [470]–[481] (purchase descriptions), [446/447/458/460] (state), move-name slots [520]–[569], or `(PH)` descriptions.
- **What Claude must RE:** the purchase routine + the per-slot "purchased/level" flags; whether writing a flag without the real effect desyncs the save; index→pane mapping.
- **UX:** best native feel — perks appear as real shop items bought with XP (true "more XP → more moves" economy), fully discoverable in the existing menu.
- **Risk:** **highest.** Interacts with save/upgrade state (corruption risk), **record-156 content mod conflicts with all language packs** (F2), and remapping a real move's slot can break that move. `MODS.md` also warns replacing a whole archive conflicts with per-record mods.
- **Effort:** **L.**
- **Depends on:** content mod (record 156) + heavy RE.

### Rank 4 — **D alone: package variants with no passive layer**
Same as the hybrid's choice mechanism, but perks are fixed per variant with no XP gating. Simpler, but loses the "LDK XP buys progression" feel. Effort S. (Subsumed by Rank 1.)

### Rank 5 — **A alone: pure passive thresholds (today's prototype)**
Safe and nearly free, but no player choice and no discoverability. Effort S. (Subsumed by Rank 1, which adds variants for choice at ~no extra risk.)

### Better idea considered — **E: "Fatality-Level dial" + combo-word readout**
- **E1 — Fatality-Level selector as a perk tier dial:** the native [1632]–[1637] menu already offers 4 discrete levels with P1/P2 headers. If its selected level is stored in a readable memory field, a routine mod can **read it as a perk-tier dial** (Level 0 = off … Level 3 = all perks) with **zero content mod and zero new UI** — the player uses a menu that already exists. Elegant, but GUESS/needs-RE: it reads as a **VS-mode** row, so it may not be reachable in story/LDK, and we must find the stored selection. If reachable, this beats C for effort.
- **E2 — combo-rank-word readout:** bind each perk to one of [1640]–[1659] and force the combo popup to show it when the perk state changes. The duplicate `Impossible` keys [1658/1659] are free real estate. Cryptic without a content mod; a transient, non-blocking toast with it. This is the feedback half of C, usable standalone.

**Recommendation:** ship **Rank 1 (A+D hybrid)** first — lowest risk, no language-pack conflict, reuses the existing spine, and gives coarse choice via variants. Then add **E1 (Fatality-Level dial)** *if* RE shows the selector is reachable and its value readable, because it adds in-game choice with no content mod. Hold **C** as the "deluxe in-game UI" and **B** as a last resort (save-corruption + language-conflict risk).

---

## (C) Perk catalogue & XP curve

**Economy anchor (from the tables + `env_kill_xp.md`):** a normal kill ≈ **50 XP** (elites more); quest rewards are **500–700 XP** ([21]/[71]/[96]); the combo multiplier scales payout and "increases every 10 combo hits or enemy kill" ([1316]/[1356]). LDK spawns more enemies → more kills → more XP, so the curve is **back-loaded** to make capstone perks land late in an LDK run. **Calibration is a GUESS until a real LDK playthrough logs a lifetime-XP total** (Open Question F.1); thresholds below are relative and tunable in `UPGRADES`.

Curve shape: Tier 1 ≈ 1.5k–3k, Tier 2 ≈ 4k–8k, Tier 3 ≈ 9k–15k, Tier 4 ≈ 16k–25k.

Dependency key: **RE** = needs a memory target found (what); **CM** = needs a content mod (text); **Lua** = routine-mod-only once the target is known. *Brutality/EX perks are marked ⚠ and kept separate — they depend on the enhanced-move switch, which is not found yet.*

### Tier 1 — opening (1,500–3,000 XP)
| # | perk | XP | effect | dependency |
|---|---|---|---|---|
| 1 | **Endurance** | 1,500 | larger stamina/guard meter | **RE**(stamina max field behind `0xC9710/0xC9740/0x82EA0`) + Lua |
| 2 | **Bloodlust** | 2,500 | small health on kill | **RE**(per-player health offset; ride `RegisterKill`-adjacent state) + Lua |
| 3 | **Decapitate** | 2,000 | blade finishing hits behead | **RE**(combat-path dismember trigger; the detach fns are level-script, not combat — rev 2) + Lua |
| 4 | ⚠ **EX Finisher** | 3,000 | a brutality anim as an enhanced special | **RE**(enhanced-move switch: `[0x58E068]+0x1A0`, brutality-off `[0x58D6A8]+0x318+…`, `startanim 0x18AAC0` anim-ids) + Lua |

### Tier 2 — core (4,000–8,000 XP)
| # | perk | XP | effect | dependency |
|---|---|---|---|---|
| 5 | **Recuperate** | 4,000 | faster stamina regen | **RE**(regen field) + Lua |
| 6 | **Sever Limbs** | 5,000 | blade hits sever arms/legs | **RE**(combat-path dismember trigger — rev 2) + Lua |
| 7 | **Combo Master** | 6,000 | slower combo-meter decay | **RE**(combo-timer var near `0x7EA94` path) + Lua |
| 8 | ⚠ **EX Combo Breaker** | 7,000 | brutality anim as a combo-ending EX | **RE**(same enhanced-move switch) + Lua |
| 9 | **XP Boost** | 8,000 | +XP multiplier on kills | **Lua-mostly**: before-hook `addexperience 0x13A53` (hookable) and scale the awarded amount; confirm player index |

### Tier 3 — powerful (9,000–15,000 XP)
| # | perk | XP | effect | dependency |
|---|---|---|---|---|
| 10 | **Cleaver** | 9,000 | higher dismember chance on blades | **RE**(combat-path dismember chance — rev 2) + Lua |
| 11 | ⚠ **EX Launcher** | 11,000 | enhanced launcher from brutality set | **RE**(enhanced-move switch) + Lua |
| 12 | **Iron Lungs** | 12,000 | longer sprint & dodge | **RE**(stamina drain field) + Lua |
| 13 | **Bone Breaker** | 13,000 | power attacks can dismember too (GUESS) | **RE**(`bodydamage 0x180CA0`/`applydamage 0x153DC0` flags) + Lua hook |
| 14 | **Warrior's Fortune** | 14,000 | bonus XP from fatalities ([1333] confirms fatalities already give bonus EXP) | **RE**(fatality-XP path) + Lua |

### Tier 4 — capstone (16,000–25,000 XP)
| # | perk | XP | effect | dependency |
|---|---|---|---|---|
| 15 | ⚠ **Berserk** | 16,000 | longer brutality-mode window | **RE**(write `[0x58E068]+0x1A0` timer / hold ≥10) + Lua |
| 16 | **Second Wind** | 18,000 | burst stamina/health when nearly dead (GUESS) | **RE**(health+stamina fields) + Lua |
| 17 | **Air Juggle+** | 20,000 | extra air-combo hits (cf. [973] `More Air Combo Hits`) | **RE**(air-hit counter) + Lua |
| 18 | **Quick Recovery** | 25,000 | faster wake-up after knockdown | **RE**(getup-timer var) + Lua |

### Air Combat group (rev 2) — 19,000–24,000 XP

Sourced from the game's own air-move strings, which prove the engine already
models each concept: [492] `Air Juggle`, [973] `Combo: More Air Combo Hits`
(Square ×5), [981] `Combo: More Dive Kicks`, [992] `Combo: Air Throw Ender`, and
[1415] `Allows the player to flip out and recover from an air reaction.`
Tier-4 perk **#17 Air Juggle+** (more air hits, cf. [973]) is this group's
"more air hits" member; the five below join it, making the group six.

| # | perk | XP | effect | dependency |
|---|---|---|---|---|
| 19 | **Extended Juggle** | 19,000 | a launched enemy stays juggle-able longer before it falls (cf. [492]) | **RE**(the juggle / "unrecoverable" timer on a launched enemy — GUESS) + Lua |
| 20 | **Dive Kick+** | 20,000 | more dive kicks allowed per air sequence (cf. [981]) | **RE**(the once-per-air dive-kick flag / use counter — GUESS) + Lua |
| 21 | **Air Throw Ender** | 21,000 | unlock an air throw that slams and ends the combo (cf. [992]) | **RE**(the move-unlock bit / `startanim` id for the air-throw ender — GUESS) + Lua |
| 22 | **Sky Recovery** | 22,000 | faster flip-out / recovery from an air reaction (cf. [1415]) | **RE**(the air-reaction recovery timer / getup-state duration — GUESS) + Lua |
| 23 | **Air Dash** | 24,000 | a short horizontal air dash / mid-air recover to extend or escape a juggle | **RE**(an air-mobility state or impulse applied on jump/dodge — GUESS) + Lua |

Every value in this group is a **GUESS** until Claude locates the field; the
strings prove the *concept* exists in the engine, not the offset. The group is
deliberately late-curve: air mastery is a capstone, not an opener.

**18 core perks + 5 air-combat perks (rev 2).** 4 are ⚠ brutality/EX (all gated on the *same* unfound enhanced-move switch — if RE finds it, all four unlock together; if not, none ship). **(rev 2) The dismemberment cluster (3,6,10) is NOT the easy win it first looked:** probe logs show **weapon/blade kills never call** `enemy_detach_bone` / `enemy_detach_group` / `mutilate_collision` — those are **level-script commands**, not part of combat. Real combat damage runs `0x17877F → 0x175037 → 0xBFB81 → applydamage 0x153DC0 / 0x153E9C`. So dismemberment **needs combat-path RE** (find where on that chain a dismember decision is made, or how combat reaches the detach commands), not merely a hook on the detach functions. `bodydamage 0x180CA0` / `applydamage 0x153DC0` (perk 13) *are* on the damage path and remain the viable hooks. Stamina (1,5,12) and the XP/economy perks (9,14) are field writes / one hook. **No perk requires a content mod for its *effect*** — CM is only ever for *naming/feedback* (surfaces B/C/E2).

**Variant loadouts (surface D):**
- **Classic** — Tiers 1–2 only, curve ×1.0 (≈ vanilla+ a little blood).
- **Brutal** *(default)* — all 18, curve as tabled.
- **Hardcore** — dismemberment + EX only, curve ×0.7 (fast, lethal, no stamina/QoL).

---

## (D) Mockups

Two self-contained mockups for the top-2 surfaces (Rank 1 hybrid, Rank 2 toggles). Exact replacement strings included; original-length budgets noted where a content mod rewrites a fixed-width slot.

- **Rank 1 (A+D hybrid):** `mock/surface1_passive_variants.txt` — the Krypt catalog variant picker, the README perk card, and the in-game moment (passive: the vanilla XP popup is unchanged; perks apply silently). No text-table edits, so **no length constraints apply**.
- **Rank 2 (C toggles + readout):** `mock/surface2_toggle_readout.html` — a single self-contained HTML file (no external scripts): the pause-menu **Moves/Info** readout showing live perk on/off states via re-purposed `(PH)` indices, the toggle-combo card, and the combo-word toast — with the **exact replacement strings and their original lengths** (e.g. [1658] `Impossible` = 10 chars → replacement must be ≤10 to keep the popup layout; [574] `(PH) Liu Kang Fireball 5 ` = 25 chars).

---

## (E) What Claude must RE for the top choice (Rank 1 hybrid)

The hybrid needs **only per-perk effect targets** (no menu/purchase/input RE). In priority order:

1. **(rev 2) Dismemberment (perks 3,6,10) — needs combat-path RE, not just hooks.** Probe logs show **weapon/blade kills never call** `enemy_detach_bone 0x1A33E0`, `enemy_detach_group 0x1A34A0` or `mutilate_collision 0x1A3450` — those are **level-script commands** (fatality/finisher scripting), not the combat damage path. Real combat damage instead runs `0x17877F → 0x175037 → 0xBFB81 → applydamage 0x153DC0 / 0x153E9C`. So a before-hook on the detach functions will **not** fire on blade kills and cannot deliver the perk; the earlier "hooks exist, most feasible" reading was wrong. **New deliverable:** locate, on the combat damage chain, the decision/flag that produces dismemberment (or the route by which combat invokes the detach commands), and confirm which arg is bone/group id vs. the attacker/ownership entity and whether a "blade" damage-type flag is visible. `bodydamage 0x180CA0` / `applydamage 0x153DC0` remain the hookable on-path functions (perk 13). (`probe_upgrade` already samples these per `upgrade.md`.)
2. **XP slot + player index (all perks).** Confirm `manager+0x48F0+player*0x50` is the live XP and the **single-player player index** (0 or 1) — `upgrade.md` flags this as unconfirmed. Also confirm the `addexperience 0x13A53` argument so perk 9 can scale it.
3. **Stamina (perks 1,5,12,16).** Find the meter **value / max / regen / drain** fields behind get `0xC9710`, set `0xC9740`, level `0xC9770`, per-level max `0x82EA0`. If the game has **no** stamina meter, scope a mod-maintained meter (larger job — `upgrade.md` anticipates this).
4. **Health field (perks 2,16).** Per-player current/max health offset (manager-relative), for Bloodlust/Second Wind.
5. **⚠ Enhanced-move switch (perks 4,8,11,15) — the blocker for all EX/brutality perks.** Determine what makes a special play its *brutality/enhanced* version: the semantics of fatality-mode `[0x58E068]+0x1A0` (≥10 active) / `+0x1A4`, the brutality-off flag `[0x58D6A8]+0x318+(idx-1)*8+4` and count `+0x388`, and which `startanim 0x18AAC0` animation-ids correspond to enhanced moves. Key question: **does writing the mode field make normal specials enhanced, or does it desync animation state?** (This is the "`probe_upgrade` samples these fields + `startanim` while entering brutality mode" step from `REPORT.md`.)
6. **Combo/XP popup vars (feedback for Rank 2 / E2, optional for Rank 1).** The combo-rank variable that selects among [1640]–[1659], and the combo-timer behind decay (perk 7). Only needed if we add in-game feedback.

For **Rank 2 (C)** additionally: pad-state address/layout at the poll tick, and `cLIST::CopyTextEntry 0x1B5880` argument semantics (text index in, list slot out) + whether substituting the index is safe. For **E1**: the memory field holding the Fatality-Level [1632–1637] selection and whether that menu is reachable outside VS.

---

## (F) Open questions

1. **LDK lifetime-XP total?** The whole curve is relative until a real LDK playthrough logs total XP gained (probe already logs `XP+<amount>c<combo>`). Needed to place Tier 4 so it lands near end-of-run, not mid-game.
2. **Enhanced-move switch (the ⚠ blocker).** Does forcing brutality-mode via memory make specials enhanced without desync? If no, the 4 EX perks are cut and the catalogue is 14.
3. **Is there a stamina meter at all?** If not, "stamina" perks become a mod-maintained meter (much larger; may drop from v1).
4. **Text-index → screen mapping.** Which `(PH)`/debug/Info indices are actually rendered, and where? Without this, surface B/C/E readouts are guesswork. (RE.)
5. **Language-pack policy.** Do we accept that any text-rewriting variant (B, or C/E2 with a content mod) **cannot co-install with a language pack** (F2)? The recommended Rank-1 hybrid avoids this entirely by shipping no content mod — confirm we're OK with out-of-game-only discoverability.
6. **Save persistence.** Thresholds currently use *session* XP (a continued save re-unlocks as you play). Do perks need to persist to the save? That means writing save-backed state — higher risk, likely out of v1.
7. **Co-op parity.** Perks are per-player (`owned[player]`); in co-op do both players unlock independently, and does a toggle combo (surface C) need per-pad detection? `env_kill_xp.md` notes co-op credits the longer-combo player — perk attribution may need the same rule.
8. **`God Mode On/Off` [1638/1639] and `Double Damage` [1613]** exist as strings — are the underlying cheats reachable/writable? If so they're free perk candidates (GUESS).
