# Qwen task: EX power, recovery and the brutality fireball (rung 5, part 2)

Paste everything below the line into Qwen.

---

You are continuing the reverse-engineering of **Mortal Kombat: Shaolin Monks (Xbox, USA/Europe)** as run by Shaolin Monks Recomp 0.2.0, for the MKSM Komplete+ mod project. The workspace is `C:\Users\Arcade Machine 1\Documents\MKSMK`, with `default.xbe` in the root. Your previous report, `analysis/ex_specials/REPORT.md`, is the starting point. Read it first. If `analysis/ex_power/REPORT.md` already exists from an earlier version of this brief, extend it rather than starting over.

## Where EX stands (built, XP Shop 0.9.0)

- **Buying.** EX is bought **per move**, in the game's own Pause > Moves > Specials menu. Each button's group (X, Y, B, then ^) lists that button's moves as separate rows ("Special 1", "Special 2", ...), and the vanilla tiers are separate moves with their own input chains: Liu Kang's Special 1 is R2 + X (fireball), Special 2 is R2 + X, X (high/low fireball), Special 4 is R2 + X, X, X (fireburst). Every row can now be bought twice. The first purchase is the vanilla move on R2. Once that is owned, the row is for sale again as "<move> EX". A button's EX moves are bought in order. The EX count per button is kept in level slots 19–22 (mgr+0x1C4+p*0x1C+19+slot; the menu's group order X, Y, B maps to game slots 0, 2, 1).
- **Input.** L2 + an attack button (X, Y, B), without R2, becomes R2 + that button. A before-hook on the pad translator `0x129480` does it (eax = joypad object `0x63AC20 + p*0xE4`; analog bytes from +2 are A B X Y Black White **LT RT**). Live data proved LT is the analog byte at pad state +0xC (`0x63ABD4`), the **Xbox** XINPUT layout. Your 3.1/3.2 table used the PC layout and was wrong there; everything else in your report held. L2 stays latched as R2 while it is held, so EX input chains (X, X, X) go through. L2 + R2 + a button is left free for later.
- **Variant.** While L2 is held after an EX press, GetLevel (`0x111C2`) answers the condition evaluator (return address in `0x1CD780..0x1CE400`) with the lower of the player's EX count for that button and their own R2 level. So L2 does exactly the moves whose EX is bought, as the same moves the game picks for R2.
- **Cost.** EX costs 25 extra stamina, taken in an after-hook on the spend wrapper `0x1406B`.

So an EX move is today **the same move, picked by the same input, with nothing stronger yet.** This task is about making it stronger, per move.

The owner wants each EX move to be **the same move, but stronger** (the EX of Special 2 is a stronger Special 2): more damage, faster recovery (fewer frames before you can act again) and, ideally, **flashier**. The game's **brutality** fireball is "faster, flashier", so the owner would like EX to reuse brutality behaviour or animations if possible. Live tests showed that level slots 23–26 (power-up states, conditions `0x318E`–`0x3191`) change nothing visible for Liu Kang's specials, so they aren't it.

## Rules (same as before)

- **Write only inside `analysis/ex_power/`** (create it): `REPORT.md`, plus scripts in `analysis/ex_power/tools/`.
- **Do not modify anything else.** In particular, leave `mods/`, `release/`, `tools/`, `MKSMK.bat`, `analysis/xp_shop/`, `analysis/ex_specials/` and `analysis/routine_targets.txt` alone.
- Don't run the game or install mods.
- Every claim needs evidence: the address plus bytes or a decompiled line. Mark guesses.
- A Lua hook can only attach to addresses in `analysis/routine_targets.txt`. It can read and write memory, read and change registers and arguments, and change `eax` on return. **It cannot call game functions.** Name the hookable address for every mechanism you propose. Also say what identifies "this hit or this move belongs to player p's EX move": the shop can raise a per-player flag at the EX press (the pad translator) and keep it until the move ends, so name where a move ends, and say whether one of these identifies it instead: the attacker entity (`0x5D1AB8 + p*0x3238`, port at +0x68), the move id, or the variant node.

## Tools

- `powershell -ExecutionPolicy Bypass -File tools/ghidra/decompile.ps1 0xADDR ...` (C of the function containing each address).
- `analysis/xbe_lib.py` (`Xbe().print_dis(va, n)`, `.read(va, n)`; scan `.text` for E8/E9 rel32 targets to find callers).
- Your earlier tools in `analysis/ex_specials/tools/`.

## Questions, most important first

1. **Damage.** Where is a hit's damage computed and applied to the target? This includes projectile hits, since the fireball is a projectile. Find the function that subtracts health (actor health is int at `actor+0x368`, actor = `[entity+0x200]`), the damage value's source (move or projectile data, multipliers for difficulty or power-ups), and a hookable point where the damage of a hit **from a given attacker** can be scaled. Is the attacker (or the projectile's owner) known there? The platform ability "Double Damage" (text 1613) may already be a multiplier: find which level slot or state it uses (the constant-slot predicates `0x752B9`→slot 5, `0x1C81C5`→slot 6, `0x1E9339`→slot 4 are candidates) and whether switching it on briefly is a clean way to double one move's damage.
2. **Recovery.** What decides when the player can act again after a special: the animation's length or speed, a recovery or cancel window in the move node (`entity+0x1E24` variant nodes, `*node` = animation id), or the move queue (`DAT_005C5BF0`)? Find a hookable point where the current move's animation could play faster, or its recovery end sooner, **for one entity**, without touching other moves.
3. **The fireball itself.** How does Liu Kang's fireball special spawn its projectile, and what sets its speed, damage and effects? How do his four X moves (fireball, high/low fireball, fireburst) differ in data? Is there a **brutality** version: how does the game enter brutality mode (find the state or flag and where it's tested), and does it change the fireball (another projectile type, another animation, other parameters)? If so, what would it take to give one EX special the brutality fireball's projectile or parameters, using hookable points only?
4. **Flash.** Is there a cheap visual cue the game already supports for a single move: a glow, colour tint, trail, particle effect or the fatality-mode screen effect? (`probe_upgrade` once logged fatality mode at `0x58E068+0x1A0`.)
5. **The ^ group.** The fourth Specials group (^, the throw button in the move list) has no confirmed game slot or pad button yet. Which game slot (0–3) do its moves test in the condition evaluator, and which pad bit or analog byte is its button?

## Deliverable

`analysis/ex_power/REPORT.md`:
- one section per question: the answer, the evidence (addresses plus bytes or decompiled lines), and a confidence rating;
- a **"Recommended hooks"** table: address, before/after, what to read and write, and how it limits the effect to player p's EX move. Note that the mod is close to the recomp's limit of 64 routine scripts and 256 writes per callback, so fewer hooks are better;
- **"Open questions for a live test"**.

Keep it factual and compact. Write in plain English, short sentences.
