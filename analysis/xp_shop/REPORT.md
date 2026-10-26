# v1.1 plan + XP shop RE (upgrade-menu table)

Static RE of `default.xbe` (capstone, `analysis/xbe_lib.py`) and GAMEDATA.WAD (`analysis/xbox_roster/tools/pwf.py`). Nothing was run against the live game. To reproduce the tree, run `python analysis/xp_shop/tools/dump_mpd.py`, which writes `out/mpd_tree.csv` (199 leaves). Every address below is an XBE VA, and "hookable" means the address is listed in `analysis/routine_targets.txt`.

## 1. v1.1 plan

| # | piece | state | first step | blocker |
|---|---|---|---|---|
| A | **XP shop** (Extended Upgrades 0.2) | menu table, purchase path and hooks mapped below | slice 1: re-cost, retitle, Health I–IV, buy fatalities | U1, U3, U4, U5 (each a small live check) |
| B | **Shuffle+** (outsiders, Normal/Wild/Chaos, reuse guard, fatality-room exemption) | built in `release/v1.1-dev`, soft-locks the Goro's Lair fatality room | diff the v1.1-dev room exemption against v1 0.6.6, which passes the room | user QA run through Goro's Lair |
| C | **EX specials** (hold L2 + special) | design only | find the enhanced-move switch (probe_upgrade ANIM/STATE data) | the brutality-mode switch is unfound, so this is the highest risk |

**Recommended order: A → B → C.** A is all Lua, with no content mod and no language-pack conflict, and its state lives in fields the game already saves. B is a bug hunt that needs the user's QA time, so it can run alongside A as its own session. C needs A's shop as its unlock surface (an "EX ×" item) and needs RE that has not landed yet.

## 2. The upgrade-menu table is data: "M&PD", WAD record 713

- The pause menu (`PauseMenu.cpp`) loads three records through `Async_AddToLoadList`, in function `0x9DA20`:
  - load id `0x2DD` goes to the callback `0x130D0`, which leads to `0x9EE50`, which calls `MPDatabase::ImportData 0x9E8F0` with `this` = `0x4EFA88`;
  - load id `0x2DE` goes to `0x9BCA0`, which stores the text-CRC table at `[0x59E3E0]` with its count at `[0x59E3E4]`;
  - load id `8` goes to `0x9BC70`, which stores the WAD-CRC table at `[0x59E3D8]`.
- **WAD record 713** (`.bin`, 13,396 B) starts with the magic `4D 26 50 44` ("M&PD"). It holds `+8` count = `0x101` (257 nodes) and `+0xC` roots = 4, and it parses to exactly `0x3454` bytes, which is the record length. **WAD 714** is 7,004 B = 1,751 × u32 CRCs, one per entry of text table record 156. The load-id-to-WAD mapping (733→713, 734→714) is inferred from that fit, not traced.
- Node = 0x30-byte header, then its child ids:

| off | field | evidence |
|---|---|---|
| +0x00 | id (CRC) | the parent/child id→pointer fix-up loops in `0x9E9B0..0x9EAB1` |
| +0x04 | type: 3 root, 2 category, 1 button group, 0 **leaf (shop entry)** | `cmp [edi+4],3` at `0x9EAC1`; purchase needs type 0 (`0x9E5BD`) |
| +0x0C / +0x30 | child count / child ids | `lea esi,[esi+ecx*4+0x30]` at `0x9E98C` |
| +0x10 | parent | walked by `0x9B760` |
| +0x18 | **name**: text CRC, converted to a text index at import | lookup in `[0x59E3E0]`, stored back at `0x9EB03`. Root: character id (0 LK, 1 KL, 0x58 Sub-Zero, 0x52 Scorpion), matched against `char+0x1DFE` at `0x9EBDD` |
| +0x1C | **description** text index (same conversion) | `0x9EB33` |
| +0x20/+0x24 | WAD CRC / level | `0x9EB2D..0x9EB94` |
| +0x28 | **XP cost** | `mov ecx,[eax+0x28]` `8B 48 28` @`0x9C43F` |
| +0x2C | **owned** flag | `mov [eax+0x2C],1` `C7 40 2C 01 00 00 00` @`0x9C442`; `0x9BB15` |

Per character (from `out/mpd_tree.csv`), only **Specials** and **Combos** can be bought:

| char | Specials (default / buyable / XP) | Combos (XP) | display-only leaves |
|---|---|---|---|
| Liu Kang | 5 / 11 / 68,000 | 5 (25,000) | Basic 12, Platform 7, Skill 4, Fatalities 10, Team 2 |
| Kung Lao | 5 / 11 / 66,000 | 5 (25,000) | Basic 12, Platform 7, Skill 4, Fatalities 11, Team 2 |
| Sub-Zero | 5 / 7 / 38,500 | 2 (10,000) | Basic 12, Platform 7, Skill 4, Fatalities 5 |
| Scorpion | 5 / 9 / 51,500 | 3 (15,000) | Basic 12, Platform 7, Skill 4, Fatalities 4 |

Special costs are 3,000, 6,500 and 10,000, plus 8,000 for Kung Lao's Hat Toss 4. Each combo costs 5,000.

**Cross-check with QA:** the save-#1→#2 diff (`analysis/qa_analysis/REPORT.md`) shows XP 23,330 → 1,830, a drop of **21,500**. That equals ~ Special 4 (10,000) + | Special 3 (6,500) + Combo 3 (5,000), which are exactly the three counters that moved: +0x1C5, +0x1C6 and +0x1D3.

## 3. Code map: the purchase and where its state lives

| VA | bytes | instr | meaning |
|---|---|---|---|
| 0x9E580 | | jump table on menu action | **dispatcher** (thunk `0x116DB`): leaf → `CanPurchase` → IsSpecial / IsCombo → purchase |
| 0x9E5CE | `50` | `push eax` → `call 0x116CC` | `CanPurchase 0x9BB10`: not owned, the previous level is owned (Specials only), and `XP >= cost` (`3B E9` `cmp ebp,ecx` @`0x9BB8C`) |
| 0x9E60D | `e8 04 37 f7 ff` | `call 0x11D16` | **Purchase_special `0x9C3F0`**, arg = index of the button group inside Specials |
| 0x9E63D | `e8 12 53 f7 ff` | `call 0x13954` | **Purchase_combo `0x9C4C0`**, arg = index of the combo |
| 0x9C405 | `e8 b3 61 f7 ff` | `call 0x125BD` | GetXP(player+1) |
| 0x9C40F | `e8 7c 66 f7 ff` | `call 0x12A90` | "Upgrade" yes/no dialog `0x9BF90` (title = text 455) |
| 0x9C427 | `e8 52 a0 f7 ff` | `call 0x1647E` | **Upgrade(player, slot, 0.0) `0xB08D0`**: level+1, capped by `0x4F3390[slot]` |
| 0x9C449 | `2b f1` | `sub esi,ecx` | XP −= node cost |
| 0x9C454 | `e8 78 98 f7 ff` | `call 0x15CD1` | SetXP(player+1, XP) |
| 0x9C4F5 | `83 c2 0d` | `add edx,0xD` | combo slot = 13 + index |
| 0x7BB0F | `8b 84 01 f0 48 00 00` | `mov eax,[ecx+eax+0x48F0]` | XP = `mgr + n*0x50 + 0x48F0`, with n **1-based**, so P1 = **mgr+0x4940** |
| 0xC48A0 | `a1 bc ce 5a 00` | `mov eax,[0x5ACEBC]` / `add eax,0xE4` | ability base B = mgr+0xE4 |
| 0xB036C | `83 c1 08` | `(p+8)*0x1C` | **level byte = mgr + 0x1C4 + p*0x1C + slot** (28 slots per player) |
| 0xB0714 | `88 14 01` | `mov [ecx+eax],dl` | SetLevel `0xB06F0` writes the level byte (also clears timed record `B+0x118+(p*0x1C+slot)*0x24`) |
| 0xCAECF | `03 81 e0 00 00 00` | `add eax,[ecx+0xE0]` | `healthupgrade` command `0xCAEC0`: **mgr+0xE0 = health-upgrade count**, clamped at 4 (`83 f8 05` @`0xCAED5`), then max HP is recomputed |
| 0xD2BBE | `8b 0d a4 04 5b 00` | `mov ecx,[0x5B04A4]` | GetText: **string pointer array `[0x5B04A4]`**, count `[0x5AC508]` |

- The **slot map** is 0–3 for the special buttons and 13–17 for Combo 1–5. Max levels (`0x4F3390`) are `5 5 5 5`, then 1 × 23, then `5` for slot 27.
- Purchase and default-grant disagree on ~ and |. Purchase uses group position (~ = 1, | = 2), but the default grant `0x9B410` maps ~ → 2 and | → 1. The game does not notice because both groups start at level 1.
- `0x9BB10` checks the RAM node's +0x2C, so something must re-mark bought levels as owned each time the menu opens. That site is not found yet (U3).
- **Bug in the prototype:** `upgrade.lua` and `probe_upgrade.lua` use `0x48F0 + p*0x50` with p counted from 0, which is the slot *below* player 1. Player p's XP is at `0x4940 + p*0x50`.

**Hookability:** the function bodies are not hookable, except SetLevel `0xB06F0`. **Every jump thunk is hookable:** `0x150C9` ImportData, `0x116DB` dispatcher, `0x116CC` CanPurchase, `0x12B71` IsSpecial, `0x15EDE` IsCombo, `0x11D16` / `0x13954` purchases, `0x1647E` Upgrade, `0x111C2` GetLevel, `0x125BD` / `0x15CD1` Get/SetXP, `0x12A90` dialog, `0x16992` GetText, `0x119A1` DisplayDescription, `0x131FC` ApplyNode.

## 4. Shop proposal: reuse the existing leaves at runtime

**Mechanism.** It is all Lua, so there is no record-156/713 content mod and no language-pack conflict.
1. **`after` 0x150C9 (ImportData).** Walk the RAM tree at `[0x4EFA88]` (blob copy), using the node-pointer array at `[0x4EFA8C]` and the count at `blob+8`. For each shop leaf, write +0x28 (cost), +0x2C (owned, derived from the item's saved effect field) and +0x18/+0x1C (text indices). That is about 3 writes per leaf, under the 256-write budget.
2. **Text.** Write the new strings over the unreachable `(PH)` entries' bytes (197 entries, 25–70 B each, `analysis/upgrade_design/out/repurpose_shortlist.csv`), then point the leaf's +0x18/+0x1C at those indices. A pointer at `[0x5B04A4]+i*4` can also be redirected. The writes are spread over a few callbacks.
3. **Make a display-only leaf buyable.** Put `after` hooks on IsCombo `0x15EDE` and CanPurchase `0x116CC` that return 1 for shop leaves, with the mod's own affordability check. The vanilla Purchase_combo then shows the dialog, deducts +0x28 and sets +0x2C. **`replace` on Upgrade `0x1647E`** (cdecl, caller cleans, so `stack_pop` 0) runs while a shop leaf is pending. It skips the combo-slot bump and applies the shop effect instead.
4. **Persistence.** Each item's effect field is its saved state (the manager is laid out like a save slot), so the mod keeps no side store.

**Entry mapping** (per character; Platform stays vanilla so progression cannot be sequence-broken):

| shop item (user scope) | reused entries | effect target | status |
|---|---|---|---|
| Specials (vanilla) | Specials, 7–11 buyable | slots 0–3 | works today; re-cost only |
| New combos | Combos, 2–5 | slots 13–17 | works today; re-cost only |
| Health Upgrade I–IV | Skill group (4 leaves, display-only) | mgr+0xE0 (+ max-HP recompute) | **U4** |
| New fatalities | Fatalities (4–11 leaves) | the fatality-learned flag | **U5** |
| EX ×/~/\|/^ | Basic Moves › Running Attacks (4 leaves) | a free level slot, read by piece C | **U1** + piece C |
| Weapons available so far | Basic Moves › Basic Attacks (4) | weapon-give path | **U6** |
| Combo extenders | Basic Moves › Air Attacks (4) | air-hit / dive-kick counters | **U7** (RE) |
| Stamina | none | no stamina meter found yet | **U8**, may drop |
| no potions or refills | none | none | per scope |

**Slice 1 is built** as `mk_upgrade` 0.2.0 (`mods/_build/src/upgrade.lua`, test `tests/upgrade.lua`). The Skill group becomes Health with Health Up 1–4 at 5,000/10,000/15,000/20,000 XP, and the effect is `mgr+0xE0`. It differs from the plan above in three ways:
- It patches the tree after **SyncOwned** (thunk `0x13A12`, which runs on every menu open) rather than after ImportData.
- Upgrade is not replaced. A Recomp `replace` cannot decline: `routines.cpp` runs the original only if the replace call failed, and a failed call disables the script. So the shop lets Purchase_combo's Upgrade(p, 13+row) run, then restores that slot's level byte, timer and record count.
- The routine limit counts **scripts**, not hooks: 1 script, so 59 → 60 of 64.

Not verified in the running game yet.

## 5. Unknowns (each is a short live check with `tools/livemem/peek.py`, read-only)

- **U1 (answered statically)** Slots 4–10 are Platform, in menu order (`0x9D85F` `lea edx,[esi+4]`). Slots 11–12 hold the timed records (`0x177E30`), 13–17 the Combos, and 23–26 are read by `0x1DA00`. Slot 18 appears only in the completion sum `0x98840`. **Slots 19–22 and 27 have no fixed-slot readers**, so they are the EX-move candidates. The move code (`0x1CD780`) also reads slots by variable, so check live.
- **U2** Which slot the move code reads for ~ and | (1 or 2). SyncOwned `0x9D620` uses group position (~ = 1), the same as purchase. Only the default grant `0x9B410` uses ~ = 2.
- **U3 (answered)** SyncOwned `0x9D620` (called from menu open `0x9DE20`) rebuilds +0x2C:
  - Specials from levels by group position;
  - Combos from slots 13+i;
  - Platform from slots 4+i;
  - Fatalities from the list below.
  
  It never touches Skill or Team.
- **U4 (answered)** Base HP = table `0x50B544[min(mgr+0xE0,4)*5 + mode]`: 200/300/400/500/600 in single player, 400–1200 in co-op. `0xD4760` and `0xD4790` apply it on every map load (`0xD7A60` ← `SetCurrentGameMap`). It cannot exceed 4 upgrades (clamps at `0xC958C` and `0xCAED5`).
- **U5 (partly)** The Fatalities menu marks a row owned when its name text index is in the array at `0x4DF5DC` (count `[0x4DFC1C]`, 400 slots). `0x3E890` appends to it when a fatality is **performed** (`0x3EAF0`); `0x4DF5D8` is a performed counter. No save/load code references the array. Still open: whether it persists, and whether it gates the fatality itself or only reveals its input in the menu.
- **U6** Weapon give / pickup path. **U7** Combo-extender counters. **U8** Whether a stamina meter exists at all (`0xC9710` may be the brutality meter).
- **U9** Whether the text pointer array survives map loads and language changes. Re-apply it on every ImportData.

## 6. Slice 1 QA (mk_upgrade 0.2.0 + Probe 0.11.1)

To install, drag `mods\mk_upgrade` and then `mods\mksmk_probe` onto `MKSMK.bat`. That makes 60 of the 64 routine scripts. Then play:

1. Pause > Moves: **Health** replaces Skill, with rows Health Up 1–4.
2. With at least 5,000 XP, Health Up 1 shows its description. Buy it through the Upgrade dialog: XP drops by 5,000 and the row reads owned. Rows 2–4 stay hidden.
3. Combos: Combo 1 must still be locked, unless it was already bought. This checks the slot restore.
4. Enter the next area: the health bar is longer and your health is not refilled.
5. Save at a statue. The SAVESTAT report shows `+E0=1`, and `+1D0` is unchanged for the combo slots. Alt+F4, reload, and check that the row is still owned.

If something goes wrong, read-only checks: `peek.py` for `mgr+0xE0` (count), `mgr+0x1D1..0x1D5` (Combo 1–5 levels), `mgr+0x4940` (XP).

**Live smoke test, 2026-10-25.** Recomp 0.2.0, Spanish, on a scratch copy of the saves (`--no-launcher --save-dir`), with mk_upgrade 0.2.0 installed and 60 routine scripts active. No script errors in the log.
- **Before any pause:** the tree is at `0x81A18480` (257 nodes, 4 roots) and each Skill group's rows are 1410–1413. The text table at `[0x5B04A4]` holds Spanish and keeps the `(PH)` entries.
- **On pause:** the labels are written in Spanish (Salud, Salud +1…+4, with the accents rendering correctly). All 4 roots are retitled and priced, and owned follows `+0xE0`.
- **In the menu:** Salud shows green in the category list, the game's "new abilities" notice fires, and rows that are out of order show red locks.
- **Slot 5** (202,965 XP, 3 upgrades): buying Salud +4 opened the game's "Mejorar Sí/No" dialog at 20000. XP went to 182,965 and `+0xE0` 3 → 4. `+0x94` = 500, the table value for 3 upgrades, and max HP = 500.
- **Slot 1** (5,900 XP, 0 upgrades, no combos): after loading, `+0x94` = 200 and max HP = 200, which confirms the recompute on map load. Buying Salud +1 took XP to 900 and `+0xE0` to 1. **Combo slot 13 stayed 0**, with its timer and record count unchanged, so the restore works.
- **Not seen yet:** max HP rising after the next area load.

## 7. Slice 1, revised: the shop lives in Basic Moves (user decision, 2026-10-25)

The user asked to leave Skill (Habilidad) alone and to sell health **and stamina**.

**Layout.** Basic Moves (category 402, type 2) becomes **Upgrades / Mejoras**.

| Group | Takes over | Rows | Effect |
|---|---|---|---|
| Health | Basic Attacks (403) | Health Up 1–4 (5,000 / 10,000 / 15,000 / 20,000) | `+0xE0` |
| Energy | Air Attacks (404) | Energy +1/+2 (8,000 / 16,000) | the meter's levels 2 and 3 |

- Running Attacks (405) stays vanilla, reserved for EX moves.
- Unused rows are hidden by lowering the group's child count in RAM (`+0x0C`, 4 → 2). Live test: only 2 rows draw.
- All changed fields are stored with their vanilla values and restored if a reloaded text table has no room.
- Only the menu player's character root is patched: `mgr+0xCC + p*4` holds the character id, matched the way SyncOwned matches it.
- A 200-write budget per callback applies. Any overflow resumes in the next CanPurchase call (tested).

**"Stamina" is the meter level.** The table is laid out as handlers then name: `setfatalitylevel` → `0x3F2F0` (level += a0; meter += a1), `setfatalityAmount` → `0x3F480`, `healthupgrade` → `0xCAEC0`.
- **Fields:** meter value = f32 `mgr + 0x4954 + p*0x50` (get/set `0xC9710` / `0xC9740`); level = u32 `mgr + 0x4978 + p*0x50` (get/set `0xC9770` / `0xC97A0`).
- **Capacity:** AddMeter `0x84980` caps the value at level × bar size (char stats `+0x2B6C → +0x54 → +4` × `[0x49F0F4]`). The HUD's per-level layout table `0x4E69C0` (via `0x81FE0`) has entries for levels 1–3.
- **Saves:** level 1 early, 3 late (save slots: 1,1,1,0,3,3); one bar = 400.
- **Naming:** the HUD shows only two gauges, the health bar and a red orb (this meter). The game's tips call the meter blocking drains the "Energy meter" (text 1335/1375), and the tutorial calls the meter for fatalities the "fatality meter" (text 11). So the shop labels it Energy. Holding block with no enemy near did not drain it, which proves nothing either way.
- **Overflow guard:** the story's `setfatalitylevel` adds without a cap, so an `after` hook on thunk `0x1116D` clamps both players at 3.

**Live, slot 1, Spanish** (scratch saves; XP set to 30,000 with peek):
- The category list shows **MEJORAS** first, with "Mejora disponible a la venta". **HABILIDAD is unchanged.**
- Mejoras shows SALUD, ENERGÍA and Ataques en carrera. Energía has 2 rows; the list shows a cost of 8000 and row 2 with a red lock.
- **The purchase worked:** XP 30,000 → 22,000, level 1 → 2, meter value unchanged at 400 (no refill), combo slots untouched, Energía +2 then buyable.
- With the meter at 800 (set with peek) the HUD draws a second small red orb.
- No script errors. The category and group descriptions were added after this run and are covered offline only.

## 8. Next slices: what the static RE settled (2026-10-25)

**Fatalities: the list is a record of discoveries, not a gate.**
- `0x3E890` appends a fatality to the array at `0x4DF5DC` (count `[0x4DFC1C]`, 400 slots) and bumps the performed counter `[0x4DF5D8]` (the pause stats' "FATALITIES"). It is called from `0x3EAF0`, the fatality handler.
- Readers:
  - SyncOwned `0x9D620`, which marks a menu row owned and so reveals its input instead of `???`;
  - the count getter `0x9BE50` (completion stats `0xC95E0`);
  - the stats screen `0x98F5B`.
- The lookup `0x9BE20` (thunk `0x15D5D`) has **no callers**. Nothing in gameplay checks the list, so a fatality works without being discovered.
- **Shop design:** sell the input. Buying a Fatalities row appends its name index to the list (CanPurchase/IsCombo/Purchase_combo path, as for Health).
- **Open:** whether the list survives save/load, since no code references it from the save path. Check live: load a late save and read `[0x4DFC1C]`.

**The meter level gates only capacity and HUD.** Its readers are AddMeter `0x84980` (the cap), HUD `0x81FE0`, `0x83910` and `0x83B30`, and the two script commands. No fatality-tier check was found.

**EX specials: a design built on the game's own code, not tested yet.**
- **How a variant is chosen:** the move system `0x1CD780` asks `GetLevel(player, slot)` through thunk `0x111C2` (hookable) for slots 0–3 to pick a special's variant.
- **Pad:** XInput state for port p is at `0x63ABC8 + p*0x16` (XINPUT_STATE). Left trigger = byte `0x63ABD4`, right trigger = `0x63ABD5` for port 0 (`0x13A563..0x13A58F` copies it into the joypad driver).
- **EX = while the EX button is held**, an `after` hook on `0x111C2` reports an unlocked slot at its top tier. A bar (400) comes off the meter float `mgr+0x4954+p*0x50` when the move starts.
- **Unlock state** goes in a free level slot: 19–22 have no fixed-slot readers (one per special button). The shop sells it from the Running Attacks group.
- **Unknowns, needing a controller test:**
  - what a top-tier variant looks like through the normal special input;
  - whether L2+R2 already means fatality mode on the user's mapping (if it does, EX needs another button);
  - whether the move code reads slots 19–22 by variable.
  
  The live attempt failed: computer use can't hold RT and Square together.

**Weapons.** The pickup class tables (7 handlers, then the name) are:
- weapons: `broadsword` → `0xAFF40`, `kama01` → `0xB0020`, `staff` → `0xB0100`, `sword` → `0xB01E0`;
- `mkapowerup` → `0xB28D0`, the ability-slot setter for both players;
- `fistofruin` → `0xB29F0`.

The weapon classes share their other handlers (`0xAFDF0`, `0xAFDB0`, `0xAFDE0`, `0xAC6D0`). That's the trail to follow for "buy weapons" (`PmeWeapon.cpp` code is around `0xBA300`).

## 9. Slice 2 design: EX store (Skill) and weapon store (Team) (2026-10-25)

User scope: **Skill (Habilidad, 464) becomes the EX store with 4 leaves; Team (Equipo, 465) becomes the weapon store with 2 leaves, for Liu Kang and Kung Lao only** (SZ/Scorpion roots have no Team category at all, so Equipo is simply absent there — accepted).

### 9.1 Menu shape

Both categories are type **1** (button groups), not type 2 like Basic Moves/Specials — the patcher must accept either. Their leaves are *direct children of the category*, so Purchase_combo's index is the position inside the category: EX idx 0..3 → `Upgrade(p, 13..16)`, Equipo idx 0..1 → `Upgrade(p, 13..14)`. Both are covered by the existing Upgrade save/restore hook. Skill leaves are 1410–1413 for every character; Team leaves are 1022/1023 (LK) and 1024/1025 (KL).

### 9.2 EX store

- **Ownership:** level byte slots 19–22 (`mgr+0x1C4+p*0x1C+slot`, cap 1 in `0x4F3390`… slots 19–22 have no fixed-slot readers). Leaf → slot: `19 + game slot`, game slot per the default-grant convention (*→0, ~→2, |→1, ^→3). Each leaf is **independent** (not a ladder): buyable whenever its flag is 0 and XP suffices.
- **Effect (experimental, gated behind the flag):** `after` hook on GetLevel thunk `0x111C2`. When the player holds LT (byte `0x63ABD4 + p*0x16` ≥ ~0xC0), the slot's flag is 1 and the meter float (`mgr+0x4954+p*0x50`) ≥ 400, report the slot's **exact top tier** instead of the real level. The variant checkers (`0x1CDB1C–0x1CDC3F`, condition ids 0x3178+, jump table `0x1CE208`) compare with **equality**, so an inflated-but-wrong value would select nothing.
- **Top tiers per character per game slot** (from the Specials group child counts, menu order * ~ | ^ mapped through APPLY_SLOT):

| char | slot 0 (*) | slot 1 (\|) | slot 2 (~) | slot 3 (^) |
|---|---|---|---|---|
| Liu Kang | 4 | 3 | 4 | 5 |
| Kung Lao | 3 | 5 | 3 | 5 |
| Sub-Zero | 1 | 3 | 3 | 5 |
| Scorpion | 3 | 3 | 3 | 5 |

- **Cost:** one bar (400.0) per **L2 press** — a rising-edge latch per player, deducted by writing the f32 back (manual IEEE-754 encode; the Lua API is integer-only). Crude but observable; documented as experimental.
- **User-verified:** L2+buttons has no native conflict ("L2 plus buttons does not trigger exs").

### 9.3 Weapon store (Equipo)

- **Give path (fully mapped):** pickup entity (vtable `0x4A2588`, handlers thunk `0x11DDE`→`0xBE4C0` / thunk `0x14CDC`→`0xBE4D0`) → `0xBD900` (reads the entity name `[edi+0xC]` into a stack buffer, port `[+0x68]` 1-based, position `[+0x80..0x88]`) → `0x148B3` (`0xC4F20`, PmeWeapons) → thunk `0x1153C` (`0xABE40` **FindAndRemove(name, ctx)**: scans the 35-slot pool, count `+0x50`, name at `[entry+0x20]`, calls `entry vtable[+4](ctx)`, unlinks) → thunk `0x1238D` (`0xBC500` PmeWeapon::Attach) → `0x76810` character bind (`char = 0x5D1AB8 + idx*0x3238`, weapon ptr `char+0x2794`, plus model/event calls `0x1439A`, `0x1973D0`, …).
- **Verdict:** a pure field-write give is impossible (pool unlink, vtable calls, model attach are engine code), and spawning is impossible (factory `0xB9FC0` not hookable; Lua can't call functions). **Chosen mechanism: name redirect.** `before` hook on FindAndRemove thunk `0x1153C`: when the redirect is armed, overwrite the name-buffer argument (`[esp+4]`, a stack local in `0xBD900`) with the owned weapon's **type name**, so the game's own give path delivers it. The replacement must fit within the original name's length (type names: `broadsword` `0x4A07A8`, `kama01` `0x4A07E0`, `staff` `0x4A0810`, `sword` `0x4A0840`; instance names seen: `hooksword0d2`, `axeaskama02`, `shard1d`). `0x1153C` has exactly one caller (the give path), so the hook fires only on pickups.
- **Ownership:** ladder in level byte slot **27** (cap 5, no fixed-slot readers): value = rows bought (0–2). Weapon 2 requires weapon 1.
- **Mapping (guesses pending QA):** LK → `kama01` then `staff`; KL → `broadsword` then `sword`. Verify by watching which type name a pickup carries.
- **Limitation:** the redirect fizzles if the current map's pool has no weapon of the replacement type — FindAndRemove finds nothing. Documented for QA. Single-player mode only for v0.

### 9.4 Text (all five languages must fit or the whole shop stays vanilla)

`(PH)` index allocations (capacities 45–52 B): EX category 616/617; EX leaves 683/684, 693/694, 696/697, 698/699; Equipo category 716/717; Equipo leaves 718/719 + 783/784 (LK), 793/794 + 796/797 (KL). place_text grows by ~18 strings, which exceeds one callback's 200-write budget — the existing resume mechanism (CanPurchase re-entry) covers it.

## 10. Stamina hunt (QA Console diff, run qa/run-20261025-2121)

The user says Energía should be the stamina that blocking and specials use. Diff steps watched the manager (0x5200 bytes), both player entities, actors and stats blocks.
- **special ×2:** no meter-like value changed; only position, animation and HUD fields moved. The meter value `mgr+0x4954` was already **0**, so a drain couldn't have shown.
- **blocked hit:** `mgr+0x4954` went **0 → 20.** Blocking a hit fills this meter; it doesn't drain it.
- **HUD code (Ghidra):** the gauge is drawn from `[[entity+0x2B6C]+0x54]` (p0: `0x59D350`; `+4` bar size, `+8` value in bars; `0x81F30`, `0x82EA0`). That's the same meter AddMeter `0x84980` caps at level × bar. Nothing else in the HUD path reads a separate energy value.
- **So far:** the red orb looks like the game's only energy/stamina meter. Its level (`mgr+0x4978+p*0x50`) is what Energía raises.
- **Open:** whether specials or blocking spend it once it isn't empty. Next session: build the meter with combos first, then special → Step, blocked hit → Step, L2+special → Step.

**Correction (user, with HUD screenshot):** the **blue bar under health is stamina**; the red orb is the **fatality meter**. So `mgr+0x4954` is the fatality meter value and `mgr+0x4978` its level (the small orbs). Energía rows 0.2/0.3 raised fatality orbs, not stamina, which is wrong.
- **Where it isn't:** the stamina value isn't in the manager, player entity, actor or stats block (two specials changed nothing there, and the screenshot shows the bar at about 40% after a special).
- **Candidates:** the per-player meter objects `[stats+0x50]` (`0x59CA68`/`0x59CDC0`, from `0x7EF70`) and `[stats+0x54]` (`0x59D350`/`0x59D8C8`). The latter's init `0x80260` sets `+0x28 = 300.0` and `+0x2C = 30.0`, and actor `+0x38E` (u16) is also 300. `diff.py` now watches both objects, so the next session should pin it.


**Session 2 (qa/run-20261025-2147), special then refill:** the console did watch both meter objects (it started after the change), and nothing in any region dipped and recovered. The likely reason is method, not location: stamina refills within seconds, so the snapshot taken at Step comes after the refill. `diff.py trace` (console **Trace** button) now samples at 10 Hz and ranks values that drop and climb back.
- Ruled out along the way: `entity+0x30FC` (an angle that wraps at 360, `0x1C0070`); actor `+0x38E`/`+0x390` (init constants, from `0x153450`); and the HUD element functions `0x8CE00`/`0x8D400` (enemy health bars) and `0x81160` (fatality-mode overlay).

## 11. Stamina found (paused snapshots + Ghidra, 2026-10-25)

Method: two paused snapshots, bar low then bar full (`pausesnap.py`: all of .data/.bss plus the 64 MB RAM window), keeping values that are higher when full. Two hits: f32 `0x4E65A8` 40 → 100 (the field) and `0x59E244` (its HUD copy).

**Record:** a `util_sarray` of 0x24-byte records at `0x4E6598`, count at `+0x48` (`0x4E65E0` = 2), init flag at `+0x4C`. Record i is player i (`+0x20` = entity `0x5D1AB8 + i*0x3238`).

| off | live | meaning |
|---|---|---|
| +0x00..+0x0C | 10, 20, 100, 3 | cost table, indexed by cost level 1..4 |
| +0x10 | f32 100.0 | current stamina |
| +0x14 | 120 | regen delay in frames (`SetDelay 0x761A0`, thunk `0x157C7`) |
| +0x18 | 0/1/2 | last affordability check (1 = could pay, 2 = couldn't) |
| +0x1C | counter | frames since the last spend (Consume zeroes it) |
| +0x20 | ptr | player entity |

**Code (all thunks whitelisted unless noted):**
- `Get 0x760F0` (thunk `0x150FB`) reads +0x10.
- `Add 0x76130` (`0x11CC6`) adds an int amount and clamps to `[0x49778C]` = 100.0. Its only caller is `0xAEF50`, a script command.
- `Consume 0x761F0` (`0x1453E`) subtracts `cost[level-1]` and floors at 0. Mode 2 with entity `+0x1E04` 0x2D or 3 makes it free. Its only route is `0x765E0` (`0x1406B`), called from script command `0xA5FB0` (case `0x1F1`). **Correction (2026-10-26):** not every spend goes through the cost table. Tick calls `0x75F20` first: while `0x15E620(entity)` is set (a sustained state such as the long jump) and entity `+0x1E04` isn't `0xA8`, it takes `[0x496454]` = 1.0 off +0x10 every 5th frame (frame `0x5CE878 % 5`), skips regen, and calls `0x15E580(entity)` when the bar hits 0. mk_upgrade 0.5.2 refunds that drain by the bigger bar's share in an after-hook on the Tick thunk.
- `CanAfford 0x76280` (`0x1146F`) compares the same cost to +0x10.
- `Tick 0x76300` (`0x16965`), once per frame per record, skipped while `[0x59998F]` is set:
  - counts +0x1C;
  - once the count reaches the delay, adds `[0x496454]` = 1.0 per frame (`[0x49EFF0]` = 0.05 in mode 2) and clamps to 100.
  - So, after 2 s, empty to full takes about 1.7 s.
- `Reset 0x76390` (thunk `0x15FD3`, not whitelisted; its caller `0x765D0` → `0x114B0` is) sets +0x10 = 100, +0x1C = 0, +0x14 = 120.
- `Init 0x76690` (`0x16870`) copies all 9 dwords from a per-character template (`0x76610`, keyed by `0x144350(player)`), so it rewrites the cost table.
- `HUD 0x8DF60` (whitelisted as a function): `0x59E248 = 100.0` (immediate), `0x59E244 = Get(p)`, fill width = cur / max × W with a minimum of 1 px. Health uses the f32 pair `0x59E208`/`0x59E210` (600/600) in `0x8A5A0`, and its bar length is set separately (`0x8A450`/`0x8A500`).

**What this means for Energía:**
- The 100 cap is hard-coded in three places: the Add clamp, the Tick clamp, and the HUD immediate. So "more max stamina" can't be one field write the way health is.
- The cheap, exact equivalent is to **scale the cost table**. At Energía level L the bar holds `100 + 25L`, so `cost = max(1, round(base × 100 / (100 + 25L)))`. L1 = 8/16/80/2; L4 = 5/10/50/2, i.e. twice as many blocks and specials per bar.
- Write it after `Init` (thunk `0x16870`, one after-hook) and again at purchase. The bar still looks the same and refills in the same time per bar.
- A truly longer on-screen bar would need replace/after hooks on Add, Tick, Reset and the HUD, plus the widget width W. That's cosmetic and can come later.

**Built (mk_upgrade 0.4.0, user OK 2026-10-25):** this session took the file over. Everything the shop sells stacks on top of what the game gives (user requirement).
- **Health +1..+4:** each level adds one table step (the 3 → 4 difference), above the game's own count.
- **Stamina +1..+4:** scales the cost table as above.
- **Bar thickness:** +2 px per Stamina level, via an after-hook on `0x8DF60` that rewrites the sprite's size dword, which holds width (low half) and height (high half, 10).
- **Storage:** both levels live in level slot 27 with marker bit 0x80. Health uses player 0's byte, bits 0–2 (shared, like `mgr+0xE0`); Stamina uses each player's own byte, bits 3–5. The 0.3.0 weapon count left there reads as 0.
- **Re-apply:** a before-hook on the Tick thunk `0x16965` (ecx = record) re-applies both whenever the game has rewritten vanilla values. Health matches `base + l·step` (× area level, halved in co-op) on `mgr+0x94`/`+0x8C` and on actor `+0x370`, and heals by what max gained (never revives).
- **Removed:** 0.3.0's Weapons and meter Energy are gone. The meter-level clamp stays for saves that bought it.
- **Not yet live-verified:**
  - whether the on-screen health bar follows actor `+0x370` / `mgr+0x94`;
  - whether the thicker stamina sprite looks right.
- **Correction:** `mgr+0x1C` is not the character pointer (it reads 0; `0x16B210` is `[ecx+0x1C]` on another object).
- **EX cost (user rule):** EX specials cost extra **stamina**, never red orbs; the orbs are the fatality meter (fatalities, multalities, brutalities).
  - 0.4.0 charges `scaled(25, Stamina level)` from record `+0x10` on the first boosted GetLevel of a press, and zeroes `+0x1C` so regen waits.
  - The rest of that press stays boosted.
  - With too little stamina, you get the plain special.
- **0.4.0 live failure → 0.4.1:** `f32_from` used `math.frexp`, which the runtime Lua 5.4 lacks. The first purchase errored, the callback's writes were dropped and the game kept the XP. Probe SAVEDIFF also showed `mgr+0x8C` going 600.0 → 580.0 under damage, so it is **current** health as a float, not max; 0.4.1 no longer writes it.

## 12. Weapon store, rung 3: static RE (2026-10-26)

User design: buying a weapon makes it appear in front of the player, as many times as they like, one weapon at a time. The user's idea is a stash: let the game's own code make the weapons and keep them out of sight, then bring one out on purchase. Section 9.3's notes were partly wrong; this replaces them.

**Every weapon already exists.** The weapon manager at `0x5A3AC0` (vtable `0x4A2588`, the "pickup entity vtable" in 9.3) is built once at boot by `0xBE070`. Its table of weapon objects sits at `+8`, `0x27C` bytes each, count at `+0x56FC` (at most 35, `util_sarray`). The constructor creates one object per weapon type with `0xBD830(class, name, half, model, model, durability, text)` and adds it with `0xBDCF0`:

| class | names (in order) |
|---|---|
| 0x54 | sword, shard (half), one more sword-class blade with durability 2000 (name at `0x4A2564`) |
| 0x55 | broadsword, shard1h (half) |
| 0x57 | `0x4A2174` (durability 1, no models) |
| 0x58 | kama01 + kama02, hooksword01 + hooksword02 (pairs; the second half has `+0x178` = 1 and hangs off the first's `+0x17C`) |

So a map doesn't create a weapon; it places one of these.

**Weapon object** (vtable `0x4A24D4`):
- `+0x04` class;
- `+0x0C` name;
- `+0x10C` holder: the character carrying it, 0 when free;
- `+0x124` physics body or attach parent;
- `+0x12C` / `+0x130` model ids;
- `+0x174` the scene node it is placed at (an index into the instance table at `0x5CE880`), −1 when not placed;
- `+0x178` / `+0x17C` pair links;
- `+0x264` name text;
- `+0x268` / `+0x26C` durability, max and current.

**Placing, picking up, dropping:**
- **Place** `0xBAA90`: when the weapon has no body, `+0x174 = 0x1A6EC0(node)` looks up a named node in the level.
- **Pick up** `0xBD900`, a manager method reached through its vtable: thunks `0x11DDE` / `0x14CDC` → `0xBE4C0` / `0xBE4D0`. `0xBC080` finds the nearest weapon that is placed or has a body, has no holder and is not a second half, measured to the player's position (entity `+0x80..+0x88`). The pickup marker with the same name is then deleted from the list at `[0x5ACEAC]` (FindAndRemove `0xABE40`; it calls the marker's vtable `+4`, then its destructor). Attach `0xBC500` sets `+0x10C` and refills durability (`+0x26C = +0x268`). `0x76810` binds the weapon to the character (entity `+0x2794`).
- **Throw or drop** `0xBB470`: computes a trajectory from the holder, clears `+0x10C`, and the weapon becomes a physics object (`+0x124` set at `0xBA184` / `0xBA244`) that can be picked up again.
- **Markers** are the map's weapon pickup objects. Their classes are `broadsword` / `kama01` / `staff` / `sword`, with vtables `0x4A0784` / `0x4A07BC` / `0x4A07EC` / `0x4A081C` and shared methods `0xAFDF0` (collected), `0xAFDB0`, `0xAFDE0`, `0xAC6D0`, `0xA8A60`, `0xA8A70`. Each marker is `[vtable][x][y][z][w]…`, with its name at `+0x20`.
- **Types per map:** `0xB9FC0` keeps a list of weapon types (id + 256-byte descriptor; it skips `weapon_pickup`). It is probably the map's model load list. Not traced.

**Summon plan, field writes only.** For the bought type's object:
1. clear `+0x10C` and `+0x124`;
2. refill `+0x26C`;
3. set `+0x174` to a scene node at the player.

The game's own pickup (`0xBC080` → `0xBD900`) then finds it at distance 0 and attaches it. FindAndRemove finds no marker by that name, so it does nothing.

**Open, needs a live session** (`tools/livemem/weapons.py watch`):
1. what a placed weapon's fields look like, and what pickup, drop and break do to them;
2. which scene node index the player has, or another node that sits where the player stands;
3. whether a type the map didn't place has its model loaded. If not, summoning it would draw or attach a missing model, the same class of crash as the Kitana NULL model. The first write test therefore uses a type the map has.

**Live results (2026-10-26, Liu Kang, a mine area with the kama pair on the floor; `tools/livemem/weapons.py`):**
- Kama01/02 lie in the world as physics bodies (`+0x124`), node −1. Pickup sets `+0x10C` to the player entity and leaves the body. Each hit costs 15–40 durability (`+0x26C`). At −10 the holder is cleared. The player entity's `+0x2794` is the held weapon's **class** (0x58), not a pointer.
- A thrown or broken weapon returns to its spawn point. `+0x110` is its **current** position, rewritten every frame. `+0x1F0` is refreshed at pickup.
- **Respawn** `0xBECC0` (thunk `0x12BEE`) places the weapon at its home matrix `+0x1F0`, using the position at **`+0x234..+0x23C`** when byte **`+0x244`** is set (it is, for the kamas).
- The per-weapon update `0xBD620` (thunk `0x15DD5` → `0xBEF10`) runs only for weapons in the world (node or body). While a weapon is free, it counts **`+0x230`** down and respawns the weapon at 0, with the sparkle effect `0xBA7F0` at the spawn point. It is skipped while the game is paused.
- **Proven:** writing `+0x234` = player position and `+0x230 = 1` on both halves made the kama appear beside the player on the next frame, with no throw. The same `+0x234` write also made a thrown kama fly back to the player.
- **Limit:** weapons the area never placed (no node, no body) get no update, and placing them (`0xBAAF0`) does nothing. This route can only summon types present in the current area. Those are also the only ones with a loaded model, so it cannot crash on a missing model.
- The table has no `staff` weapon object, although `staff` is a pickup marker class. The weapon objects are sword, shard, broadsword, shard1h, kama01/02, axe and hooksword01/02, plus 21 `weapon_pickup` slots with no models.
