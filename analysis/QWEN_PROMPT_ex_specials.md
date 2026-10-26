# Qwen task: EX specials RE (rung 5 of the v1.x ladder)

Paste everything below the line into Qwen.

---

You are helping reverse-engineer **Mortal Kombat: Shaolin Monks (Xbox, USA/Europe)** as run by Shaolin Monks Recomp 0.2.0, for the MKSM Komplete+ mod project. The workspace is `C:\Users\Arcade Machine 1\Documents\MKSMK`. XBE SHA-256: `48240902bf4a04eb89376217c529531032d3370749bcce91a194878cc49db74a` (`default.xbe` in the workspace root).

## Goal

The XP shop mod will sell **EX specials**. With an EX unlocked, holding **L2 (left trigger) while doing a special** makes that special come out as its strongest variant, for extra **stamina** (the blue bar). The red orbs are the fatality meter and must never be spent. Your job is the static RE this needs. You don't write the mod.

## Rules

- **Write only inside `analysis/ex_specials/`** (create it). Put your report in `analysis/ex_specials/REPORT.md` and any scripts in `analysis/ex_specials/tools/`.
- **Do not modify anything else**, in particular:
  - `mods/` (all of it, including `mods/_build/src/*.lua` and `mods/_build/tests/`)
  - `release/`, `tools/`, `MKSMK.bat`, `analysis/xp_shop/`, `analysis/routine_targets.txt`
- Don't run the game and don't install mods.
- Every claim needs **evidence: the address plus the instruction bytes or the decompiled line**. Mark anything unproven as a guess.
- Lua hooks can only attach to addresses listed in `analysis/routine_targets.txt` (mostly jump thunks in 0x10000–0x17000). A hook can read and write memory, read and change registers and arguments, and change a return value (`eax`). **It cannot call game functions.** So for every mechanism you propose, name the hookable address it would use.

## Tools

- Decompiler: `powershell -File tools/ghidra/decompile.ps1 0xADDR [0xADDR ...]` prints the C of the function containing each address (thunks are followed).
- Disassembly and scanning: `analysis/xbe_lib.py` (`Xbe().print_dis(va, n)`, `Xbe().read(va, n)`). To find calls, scan `.text` for `E8`/`E9` rel32 targets, as shown in `analysis/xp_shop/REPORT.md`.
- Background reading:
  - `analysis/xp_shop/REPORT.md` sections 3, 5 (U1, U2) and 8 ("EX specials"); section 11 for stamina; section 12 for the weapon store, which is the style of work wanted here.
  - An earlier prototype of this feature, untested: `mods/mk_upgrade/dist/mk_upgrade-0.4.1.tar.xz`. Inside it, `scripts/upgrade.lua`, functions `boost_level` and the `GET_LEVEL` hook. It is reference only; don't edit it.

## What is known (verify, don't assume)

- `GetLevel(player, slot)` (thunk `0x111C2`, cdecl, returns in `eax`) is asked by the move system `0x1CD780` for slots 0–3 (the four special buttons) to pick a special's variant. The variant pickers `0x1CDB1C`–`0x1CDC3F` (condition ids 0x3178+, jump table `0x1CE208`) compare with **equality**.
- Level bytes are at `mgr + 0x1C4 + p*0x1C + slot` (`mgr = [0x5ACEBC]`), max levels at `0x4F3390`. Slots 19–22 have no fixed readers (candidate EX unlock flags).
- Pad state for port p is at `0x63ABC8 + p*0x16` (XINPUT_STATE); left trigger is byte `0x63ABD4 + p*0x16`, right trigger `0x63ABD5`.
- Stamina: one record per player at `0x4E6598 + p*0x24`; Consume `0x761F0` (thunk `0x1453E`) via `0x765E0` (thunk `0x1406B`), called by script command `0xA5FB0` case 0x1F1 with a cost level; the current value is f32 `+0x10`.
- The prototype's top tier per character (id: slots 0,1,2,3): Liu Kang (0) 4,3,4,5; Kung Lao (1) 3,5,3,5; Sub-Zero (0x58) 1,3,3,5; Scorpion (0x52) 3,3,3,5. Unverified.

## Questions to answer (in this order of importance)

1. **Variant selection.** Exactly how does `0x1CD780` choose a special's variant from `GetLevel`? Confirm the equality compare, and confirm the true top tier per character and slot, with evidence from the data or the code. Does the move code read slots 0–3 only, or anything else (for example 19–22) by variable?
2. **The ~ / | slot question (U2).** Which slot does the move code read for the ~ and | buttons: group position (~ = 1) or the default grant's mapping (~ = 2)?
3. **L2 + R2.** Does holding the left trigger while pressing the special modifier (R2) already mean something in vanilla (block, fatality mode, dodge with A)? Find the readers of the trigger bytes or the joypad driver's button mapping (`0x13A563..0x13A58F` copies the pad), and list what L2 does in each state. If L2 is taken during specials, propose another modifier.
4. **Charge once per move.** Find a hookable point that runs **once when a special starts**: the move start, the special's animation start, or where the special's own stamina cost is consumed (which `Consume` level does a special use?). That way the EX cost is charged once per EX special, not per L2 press.
5. **Safety.** Can a variant the player hasn't unlocked (a level above their current one) be selected safely, or does it need assets that only load once unlocked? Look at what the top-tier variants reference.

## Deliverable

`analysis/ex_specials/REPORT.md`:
- one section per question, each with the answer, the evidence (addresses plus bytes or decompiled lines) and a confidence rating;
- then a short **"Recommended hooks"** list: address, before/after, what to read and write;
- then **"Open questions for a live test"**: what only a controller test can settle.

Keep it factual and compact. Write in plain English, short sentences.
