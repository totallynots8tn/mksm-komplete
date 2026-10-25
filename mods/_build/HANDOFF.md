# MKSMK Handoff — Tasks 1–4 (for Claude)

Workspace: `C:\Users\Arcade Machine 1\Documents\MKSMK`. Game: Mortal Kombat:
Shaolin Monks (USA/Europe, Xbox), ShaolinMonksRecomp 0.2.0. XBE SHA-256
`48240902bf4a04eb89376217c529531032d3370749bcce91a194878cc49db74a`.

This round split work: Claude owns the heavy RE + probe 0.8 (`probe_*.lua`,
`randomizer_body.lua`, `core.lua` — untouched here). This file is the result of
the four quick tasks. Everything below was verified against the Xbox
`default.xbe` and the Recomp 0.2.0 source, not assumed.

---

## Task 1 — Address check + minterface.c platform

`analysis/routine_targets.txt` is the authoritative whitelist of hookable x86
function-entry addresses in the Xbox `default.xbe`. `analysis/final_validate.py`
fails any mod hook whose address is not in it (`hook {a:#x} not in
routine_targets`). `analysis/xbe_lib.py` reads `default.xbe` and disassembles
with capstone `CS_ARCH_X86, CS_MODE_32` — i.e. this is the **Xbox x86** image.

| Address | In routine_targets? | What it is | Xbox x86 disassembly |
| --- | --- | --- | --- |
| `0x1CEE00` | **NO** | minterface `SetCharacterFiles` | garbage: `add byte ptr [ebx-0x76b4fb3c],al` (bytes `00 83 c4 04 4b …`) |
| `0x2F6BA0` | **NO** | minterface `SetLoadedType` | garbage: `lodsb; cwde` (bytes `ac 98 df ff …`) |
| `0x283B50` | **NO** | minterface `GetObjectPointer` | garbage: `mov edx,0x40a10000` (bytes `ba 00 00 a1 40 …`) |
| `0x67C590` | **NO** | minterface `gModelInterface` | lands in `.data` (a pointer variable, not code) |
| `0xCFC80`  | **NO** | (only `0x3CFC80` exists) | real code, but reached via thunk `0x14D2C` (`jmp 0xcfc80`); not itself a routine target |
| `0x17B460` | **YES** | internal combat fn | clean prologue `51 53 56 57` = push ecx/ebx/esi/edi |
| `0x1D2600` | **YES** | `START_GROUP` | `push ebp; mov ebp,[esp+8]; …` |
| `0x14D2C`  | **YES** | `LOAD_GROUPS` (thunk) | `jmp 0xcfc80; jmp 0xa9120; jmp 0xa03c0` |
| `0x1D1D40` | **YES** | `SPAWN_ENTRY` | `sub esp,0x50; push ebx; push ebp` |
| `0x1D23F0` | **YES** | `SPAWN_TICK` | `push esi; mov esi,ecx; …` |

### minterface.c is the **PS2 build** — its addresses are unusable on Xbox

`analysis/MKSMHook/MKSMHook/` is a **PS2 (EE/MIPS)** project, not Xbox:

- `makefile`: `EE_BIN = ../scripts/MKSMHook.elf`, `EE_OBJS = … mips.o ps2mem.o …
  mksm\minterface.o …`, `PS2SDK = ../external/ps2sdk/ps2sdk`, includes
  `Makefile.eeglobal` / `eemakefile.eeglobal`. Both `PS2_BUILD` branches compile
  with the EE (MIPS) toolchain into an ELF; the "PC" branch
  (`BASE_ADDRESS = 0x02020000`) is a misnomer — still MIPS/ELF.
- `ps2mem.c` emits **MIPS opcodes**: `makeJal` → `0x0C000000 | (addr>>2)` (JAL),
  `makeJmp` → `0x08000000 | (addr>>2)` (J). `mips.c`/`mips.h` is a MIPS
  assembler/register model.
- `build_config.h`: `// build for ps2 plugin injector …` with `//#define
  PS2_BUILD` commented out; `mksm.h`: `#ifndef PS2_BUILD → "0.2" #else →
  "0.2ps2"`.
- The addresses appear **only** in `mksm/minterface.c` / `.h`, with no PS2 guard,
  and decode as garbage x86 in `default.xbe`.

**Conclusion:** `0x1CEE00` / `0x2F6BA0` / `0x283B50` / `0x67C590` (and
`PLAYER1_VRAM 0x4E5094`) are **PS2 EE addresses**. They are NOT valid Xbox
routine targets and cannot be hooked or called on the Xbox XBE. The whole
MKSMHook model-load pipeline (`SetCharacterFiles` / `SetLoadedType` /
`GetObjectPointer` / `gModelInterface`) is PS2-only reference material. For
Xbox character/model work (e.g. UMKSM characters) the equivalent functions must
be located in `default.xbe` independently. Note `mksm/actor.c`, `actorManager.c`,
`object.c` are 4–6 line stubs — MKSMHook contains **no** spawn/streaming RE.

---

## Task 2 — How language packs / file overrides reach the game

**Answer: YES, mods override game files — but NOT by writing to `d:\` or
rewriting the disc/ISO.** There is no `d:\` drop folder. The override happens in
Recomp's **virtual file layer**, in memory, at startup.

Mechanism (verified in `ShaolinMonksRecomp-0.2.0/ShaolinMonksRecomp-0.2.0/src`):

- Installed packs live under the **data folder**, not the disc:
  `runtime_paths.cpp:95` → `fs::path Mods() { return root / "mods"; }` where
  `root` is the data folder (Windows `%LOCALAPPDATA%\Shaolin Monks Recomp`, or an
  isolated `runtime-data`, or a `paths.toml`-selected folder).
  `game_files.cpp:56` → `const auto pack = paths::Mods() / files::FromUtf8(row.mod.install_dir);`
  `install_dir` is `packages/<id>` (content mods) or `languages/<id>` (language
  packs). `mods/installed.toml` records installed versions + enabled states
  (`mods/state.cpp:9-10,27`) — do not hand-edit it.
- The **original** game is read from the mounted disc / extracted folder:
  `game_files.cpp` `MountLanguage` → `const auto* disc = kernel::MountedDisc();`
  with `SourceRead`/`SourceSize` lambdas calling `disc->Find(name)` /
  `disc->Read(...)` (or `OriginalPath(source.path, name)` for an extracted
  folder). This emulated disc is the guest `d:\`.
- The **override** is an in-memory splice: `language_archive.h` →
  `PlanArchivesForPacks(packs, read, size, ArchiveView& files, …)` builds
  `ArchiveView = std::array<std::shared_ptr<const VirtualFile>, 8>` (8 virtual
  WAD + 4 virtual SFD archives). `virtual_file.h` → `VirtualFile` is a list of
  `Segment{at,size,source_offset,ReadAt}`; "Immutable after Seal. **Gaps read as
  zeroes; sources remain owned by their readers.**" `PackFileReader(path)` reads
  replacement bytes from the installed pack. Original bytes come from the disc
  reader; pack bytes are spliced over them.

Docs confirm (`docs/MODS.md`, `docs/LANGUAGE_PACKS.md`):

- Pack replacement paths: `gamedata/recordNNNNN.bin` / `.ewdf` (replace a PWF /
  EWDF archive record by original record number), `files/<game path>` (replace a
  directly read game file), `fonts/small.xpr` / `large.xpr`, `audio/voices/*.adx`,
  `audio/movies/*.adx|*.aix`, `scripts/*.lua` (routine callbacks).
- "The archive planner combines compatible resources from active mods. **It
  preserves original disc files. Direct replacements apply only to game-disc
  reads.** They do not replace saves, settings or host files."
- "It applies fonts and resource tables **in memory without rewriting game
  archives or creating a language cache.**" "**Original game files remain
  unchanged.**"
- Conflict rules: "Mods cannot replace the same file, archive record, voice or
  embedded font." "Replacing a whole archive conflicts with mods that replace
  its individual resources."

**Implication for UMKSM characters:** you cannot drop files on `d:\`. You build a
mod package with `gamedata/recordNNNNN.bin/.ewdf` (model/texture PWF/EWDF
records) and/or `files/<game path>` replacements, plus `sources` mappings for
xdelta, and install it through the Mods tab. Routine scripts (`scripts/*.lua`)
are the only code path; DLL/raw-XBE mods are unsupported.

---

## Task 3 — Solo Co-op Paths 0.5 (plate condition rewrite + diagnostic)

Built, tested, packaged: `mods/coop_solo/dist/coop_solo-0.5.0.tar.xz`
(`mods/coop_solo/pack/`). Routines order is **`coop_solo_debug.lua` then
`coop_solo.lua`** so the diagnostic snapshots the original condition list before
the functional rewrite runs. All hook addresses validate against
routine_targets (`0x12E55`, `0x156CD`, `0x16F4B0`, `0x146A1`); `0x16F4B0` is
shared by both scripts via before-hooks (allowed: "Before and after hooks can
share a target").

### What was implemented

- `src/coop_solo.lua` (functional, v0.5): keeps the 0.4 `istwoplayer`/`isoneplayer`
  caller-split, and adds a **plate condition rewrite**. On `CHECK` (`0x16F4B0`)
  before, for any trigger whose condition list contains `actionButton`, a
  player-2 condition is rewritten **in place** into a copy of the player-1
  condition (writes `+0x5C` command index and `+0x60` arg). Player-2 detection:
  `OtherPlayerInvisible` (always), or `actionButton`/`buttonthrough` with arg==1.
  Cached per record; re-armed when the trigger manager pointer changes (area
  reload). Toggle `REWRITE_PLATE`. No `error()` (the mod must stay alive).
- `src/coop_solo_debug.lua` (read-only diagnostic, the "debug toggle" `DEBUG`):
  dumps ONE `PLATE05` report via `error()` (disables only itself), then stops.
  Logs every `actionButton` trigger's full condition list (before + simulated
  after), and for each `actionButton` call: frame, activator char index, press
  latches `0x582130`/`0x582134` **before and after**, action mask `0x582140`,
  gate byte `0x4E67C4`, per-char state `0x5D38BC + idx*0x3238`, and the return.
- Tests (cwd `mods/_build`, run via lupa): `tests/coop.lua` (0.4 behaviour),
  `tests/coop_plate.lua` (rewrite: T0 arg 1→0, T1 OtherPlayerInvisible slot+arg
  copied, T2 non-plate untouched, 0 errors, max_writes 2), `tests/coop_debug.lua`
  (read-only: max_writes 0, one `PLATE05` report). All pass against the built
  pack.

### RE finding — the literal "player-2 condition" hypothesis is unsupported for the captured plate

Disassembly of the co-op gate commands (thunk → real fn) shows **none of them
take a player-index arg**; they key off the **activator** that `CHECK` passes:

- `CHECK` (`0x16F4B0`, real code): walks `count=[rec+0x58]`, `slots=[rec+0x5C]`,
  `args=[rec+0x60]`; command object `= mgr + slot*24 + 0x11C00`, `execute =
  [[obj]]`, slot bound `mgr+0x1254C`; stores `cmd_obj+8 = rec`, `cmd_obj+4 =
  args[j]`, then `execute(this=cmd_obj, activator, def)` where `def = rec+0xC`
  and the activator is CHECK's own first arg.
- `actionButton` (`0x146A1`→`0x2AE20`): `idx = [[esp+4]+0x10]` (activator char
  index), entity `= 0x5D1AB8 + idx*0x3238`. **Always** sets `ACTION_MASK
  0x582140 |= 1<<idx`. Returns 1 only if `call 0x113A2(0x58D6A8, entity)` gives
  `al&2`, AND gate byte `[0x4E67C4]==0`, AND per-char state
  `[0x5D38BC + idx*0x3238] ∈ {0,1,0x76,0xC7,0xC6,0x69}`. On success it **clears**
  press latches `0x582130` and `0x582134`. It ignores its condition arg.
- `buttonthrough` (`0x14606`→`0x36560`), `OtherPlayerInvisible`
  (`0x1420A`→`0x71AE0`), `enabletether` (`0x14EDA`→`0x21040`): all read the
  activator (`[esp+4]`/`[eax+8]`), not a player arg.
- `istwoplayer` (`0x12E55`→`0x740F0`) / `isoneplayer` (`0x156CD`→`0x740B0`):
  compare the **def** (`[esp+8]`) against the 5-byte string `"char"` at
  `0x496C80`, then read game mode at `[manager+0x88]` (via `call 0x15358`).
- `eventnotcomplete` (`0x14BCE`→`0xA4AF0`): arg = **event id** (`this+4`), reads
  completion flag `[manager + 0x4874 + id]`, valid for id < 0xC8.
- `stonepowatleast` (`0x13F94`→`0x20CB0`): arg = threshold (`this+4`).

**Captured plate (probe logs 067/068, byte-identical):** the co-op gates already
fire in solo — `T86{istwoplayer:1}`, `T127{isoneplayer}`, `T128{istwoplayer}`,
`T129` all reach `F…c1`. The plate itself is gated by **`T24{f5000,n0,c0}
actionButton`** and **`T39{f5000,n0,c0} eventnotcomplete:17, actionButton`**, and
`actionButton(0)=0` (stone=0, mask=0). T24 is **not** multi-pass (`f5000`, bit17
`0x20000` clear; `need=0`), and its only condition is `actionButton` with arg 0 —
**there is no player-2 condition to rewrite.** So the 0.5 rewrite is a safe no-op
for this plate; the real blocker is *why `actionButton` returns 0*.

**Next step (the diagnostic answers it):** run coop_solo 0.5.0, stand on the
plate, press action a few times, wait ~10 s, send the `PLATE05` line. It shows
whether the press latch `0x582130`/`0x582134` was set when sampled (a
consumed-press / timing problem — a "hold the latch" fix), or whether gate
`0x4E67C4` / per-char state forces 0, or whether `call 0x113A2` is the gate.
That decides between a latch-hold fix and a genuine "needs a second body" wall.
Because the puzzle uses persistent **event flags** (`eventnotcomplete` reads
`manager+0x4874+id`), a "latch plate A → walk to plate B" sequence is plausible
without a p2 if the gate is flag-based rather than two-simultaneous-bodies.

### Addresses worth keeping (all Xbox x86, in routine_targets unless noted)

- Trigger system: `TRIG_MGR_PTR 0x682020` (data), stride `0xD8`, count `mgr+0xA8C0`,
  slot bound `mgr+0x1254C`, cmd objects `mgr+slot*24+0x11C00`; `CHECK 0x16F4B0`,
  `TRY_FIRE 0x16F560`, `FIRE_EVENTS 0x16ED90` (rec = `ecx-0x68`); record: def
  `+0xC`, conditions `+0x58`/`+0x5C`/`+0x60`, passes `+0xCC`; def flags `+0x70`
  (bit17 `0x20000` = multipass), need `+0x79`.
- actionButton: thunk `0x146A1`, real `0x2AE20`; latches `0x582130`/`0x582134`,
  mask `0x582140`, gate `0x4E67C4`, char state `0x5D38BC + idx*0x3238`, helper
  `call 0x113A2` with `0x58D6A8`. CHAR_TABLE `0x5D1AB8`, stride `0x3238`.
- Game manager `0x5ACEBC`, mode `+0x88` (0 solo / 1 coop / 2 versus), frame
  counter `0x5CE878`, `"char"` string `0x496C80`, manager getter `call 0x15358`.

---

## Status / not done

- coop_solo 0.5.0 is built and tested offline; **not installed** (install through
  the launcher Mods tab → Install from file → `mods/coop_solo/dist/coop_solo-0.5.0.tar.xz`).
  No git/publish actions taken.
- `probe_*.lua`, `randomizer_body.lua`, `core.lua` were **not** edited (Claude
  owns them this round). probe is at 0.7.1.
- Open: randomizer barrier Path A (offline ISO/level-data patcher) vs Path B
  (runtime early-rewrite) — task #19; streaming probe 0.8 (Claude).

---

## Round 2 (Claude): Xbox roster RE

See `analysis/xbox_roster/REPORT.md` (data: `characters.json`, `maps.json`; tools in `tools/`).

- Xbox equivalents of the PS2 model pipeline exist. `SetCharacterFiles` ≈ `0xC26B0`
  (thunk `0x140D4`), `gModelInterface` = `0x64D218`, and the player charIDs sit at
  `[0x5ACEBC]+0xCC/+0xD0`.
- The character file table is at `0x4FA9F0`: 91 rows × 0x30, GAMEDATA.WAD record ids,
  plus a charID→name map.
- The stream gate is 2 players + 4 fixed enemy slots. Map rosters are static, writable
  preload lists at `desc+0x24` (cap `desc+0x20`), and they are read after the spawn
  census exists. Adding a roster ID in a before-hook on `0x15DEE` makes the game load
  that character itself. This changes the randomizer barrier question: Path B works
  for adding characters without an offline patcher.
- **Correction to Task 3's actionButton description:**
  - `call 0x113A2(0x58D6A8, entity)` is a block. When it returns true
    (fatality manager busy), actionButton returns 0.
  - The `al & 2` test is on the controller word (`0x15ABF0(0x67C658, port)`, button bit `0x2`).
  - The latches `0x582130`/`0x582134` are only cleared on success; they aren't inputs.
  - `0x582140` is cleared every frame (`0x286D0`).
  - CHECK stops at the first failing condition, so T39 never reaches actionButton while event 17 is complete.

  coop_solo 0.5.1's debug script counts each step.

---

## Round 4 (Claude): save menu, game flow, Pause Save

**Save path.** A save statue is a trigger event. The trigger event dispatcher
`0xA54D0` (a big switch on event ids) has a case that stores the save-point
index in `[0x4EFA60]` and calls OpenSaveMenu, `0xA2300`. That function sets
`ecx = 0x4EF3C8` (the in-game menu manager) and jumps to `0xA21B0`.

- `0xA21B0` is a blocking menu loop. It calls `0xA1980` to read the saves
  (`0xA1320`, then `0x127420`) and build the page from the descriptor at
  `0x4F0210` ("Save Menu", with the "Save Array" widget at `0x4F00C8`). It
  then runs `0x93D40` (thunk `0x142EB`) every frame until `[mgr+0x64]` is set.
- The Save Array's handler, `0xA1C50`, moves the slot cursor 0-8 and, on
  confirm, writes the save through `0xA1A80` → `0xA13C0` → `0x1272A0`.
- The `0x5982C8` frontend and its `0xA2260` write path belong to the
  title-screen frontend (game-flow state 8). The statue doesn't use them.

**Pause menu.** The pause menu is `0xA4810` (thunk `0x12BA8`, page
descriptor `0x4F1EA8`, page handle in `[0x59E364]`); `0xA4670` (thunk
`0x15722`) is its twin. On entry it clears `[mgr+0x692/0x693/0x694]`. After
the loop closes it checks them in order:

- `+0x693` calls OpenSaveMenu.
- `+0x692` calls `0xA4480`, a debug menu.
- `+0x694` calls `0xA4370`.

No shipped item sets `+0x693`, so the pause save option was cut. Pause Save
0.9 sets it, plus `+0x64`, on a fresh Back press while the pause page is
current. **Shelved:** in game, Back reached the input buffer, but nothing
happened and no script error was raised, so the hooks never matched. To
revisit, first check which pause routine actually runs.

**Pads.** XInputGetState fills `0x63ABC8 + port*0x16`: the packet dword
first, then `wButtons` at +4 and the analog buttons at +6..+13. The poll is
`0x13A540`, which isn't hookable; read the buffer from any hook.

**Game flow (cGameState at `0x5ADF18`, ctor `0xCC230`, main loop `0xCA4F0`).**

- **State table:** at `+0x48`, 24-byte rows. 0x1CF910 registers a row as
  (index, flag, enter, ?, update, exit).
- **Fields:** current state `+0x688`, previous `+0x68C`, program `+0x690`,
  pc `+0x694`, call stack `+0x250`.
- **Programs:** registered with 0x1CFDC0 at `+0x658`, as (op, arg) pairs.
  The ops:
  - 1: run state arg
  - 2: goto pc
  - 3: next
  - 4: skip
  - 5: call program arg
  - 6: flag `+0x699`
  - 7: return
- **Queue:** the message queue at `+0x00` (8 × (op, arg), posted by
  0x1CFA40) uses the same ops. It's processed in 0x1CFF70 after a state's
  update returns 0.
- **States:** state 8 (update `0x51A00`) is the title frontend; state 0xB
  is a fade.
- **Programs seen:**
  - program 1 = (0xB, 8)
  - program 3 = (4, 0xC, 9, 0xA)
  - program 8 = (0x13, 0x14); 0x14's exit, `0xC5D90`, autosaves through
    `0xA1DE0`.

**LDK write cap.** One callback can stage at most 256 writes. `copy_entry`
stages 28 per clone, and `MAX_ENTRIES = 12` bounds x4 at 9 clones in one
group: 252 + count + capacity = 254. Don't raise `MAX_ENTRIES` or add writes
to the START_GROUP or SPAWN_TICK expansion path without splitting the copy
across frames.

**Shuffle 0.7 outsiders (Round 4).**

- **Preload:** a before-hook on `0x15DEE` (`0xCFAB0(desc)`, stdcall, desc
  at `[esp+4]`) appends one regular type when the authored list is exactly
  one non-boss type 2-49. It raises `desc+0x20` to 2: `0xCF9F0` counts the
  missing listed types (missing from LOADED_TYPES or the sound table), and
  the preload is skipped when cap < missing.
- **Restore:** descriptors are static, so the authored list is cached per
  desc and restored on every preload. `0xD1910` re-preloads the current map
  when something is missing (after cutscenes); the outsider is kept while
  converted entries exist.
- **Memory slots:** make-resident `0x17B460` only uses slots whose charID is
  -1. `0x17AF70` marks every occupied slot in use, so there's no LRU
  eviction.
- **modelstream:** the script command `modelstream` (`0x17BA00`) queues
  (slot, charID) in the ring at `0x6964E8`. `0x17BA40` then unloads that slot
  (`0x17B280`: `0x17B220` destroys live actors of the type, and `0x17B190`
  frees bank, VRAM and heap) and loads the new character there. Shuffle
  reverts its converted entries when the outsider leaves LOADED_TYPES.
- **Empirical:** in 164 logged group starts, vanilla never had more than 3
  enemy types loaded at once.
- **Guard quirk, real (fixed in LDK 3.9.1 / Shuffle 0.8.1):** `guard_spawn`
  cancelled a spawn when the type's largest free block was smaller than its
  cost, even if a dead instance was free to recycle. See "Round 5" below. The "skipped enemies after an
  eviction" the 0.7 sim showed was a sim bug instead: in OUTSIDER mode the
  heap IDs `10+i+t` collided (type 15 in slot 1 and type 14 in slot 2 both
  got 26). Fixed in 0.8's sim (`40+t`). After the fix, every authored spawn
  lands in every mode.
- **Shuffle 0.8:** `OUTSIDER_MIN` is guaranteed per group with a plain entry,
  and the active group's unspawned entries (index ≥ `ST_SPAWNED`) are
  candidates too. build.py makes the variants randomizer (1/25%/3/30),
  randomizer_wild (1/50%/5/45) and randomizer_chaos (2/80%/8/60). Worst-case
  writes per callback: 150 permutation + 60 conversions = 210, under 256.

---

## Round 5 (Claude): Goro's Lair fatality soft-lock, waves and triggers

Diagnosed live with `tools/livemem/peek.py`, which reads guest memory at
host 0x100000000.

**Wave-cleared records.** These live at `0x6C0168`: 20 × `{s16 group, u32
alive, u8 cleared}`, with the next free slot at `0x6C0258`. They're cleared
at map load (`0xD20F0` → `0x1836B0` → `0x19C250`).

- **Written:** when an actor dies, `0x19CC70` (controller) writes `{group,
  alive}`, then `{group, 0, 1}` when alive reaches 0 (unless `ctrl+0xA6`,
  which is set only during actor transfers). The controller's wave id is
  `ctrl+0xA8`; the spawn tick writes ST_GROUP there after each spawn.
- **Never written:** when the spawner finishes a wave with alive == 0
  (`0x1D25D2`; every spawn failed, or everyone died before the last spawn),
  it frees the controller without a record.
- **Removed:** START_GROUP `0x19C270(group)` removes that group's record.

**Wave-cleared condition.** Command `0x1DED00` (class vtable `0x4B26B0`)
calls `0x19C390(arg)`, which is true when a record `{arg, 0}` exists.
Triggers are records `0xD8` apart from `[0x682020]`, count at `+0xA8C0`:
conditions at `+0x58/+0x5C/+0x60`, fired frame at `+0x10`, pass count at
`+0xCC`, definition at `+0xC`. The definition's `+0x84` is the script event
the trigger runs (`0x16ED90`).

**Fatality tutorial (map 99).** T13 is "wave 15 cleared → event 10", which
restarts wave 15. T55 is `isfatalityfull`, T05 `fatalityover`; Raiden says
"You need to perform a Fatality to open the gates."

**Bug.** LDK x3's extras had used up type 0xF's fresh heap (0x21E80 free,
0x24D00 per instance). The shared guard cancelled every spawn of the
respawned wave, so the wave ended with alive 0 and no record. T13 never
fired again, and the room had no enemies.

**Fix.** The guard allows a spawn when a free instance exists (`allocs -
alive > 0`), but only after this session has seen a spawn succeed without a
heap drop (`recycling_seen`). Shuffle now resets `allocs` on a new map or a
memory reload. Sim mode `RESPAWN=1` reproduces it: the old builds spawn 66 of
180, the new ones 180, and `NORECYCLE=1` still has 0 crashes. The sim now
returns the actor in eax from 0x1D1D40.

**Live rescue used.**

1. Retype waves 15, 18 and 19 to 0x16, the other loaded type, which had
   0x17DE80 of fresh memory.
2. Set wave 15's count back to 3.
3. Append the record `{15, 0, 1}`.

T13 fired at once, and the wave respawned with 3 type-0x16 enemies.

**Debug menu.** `0xA4480` (pause flag `+0x692`) builds a list from the
cGameState map table (`[obj+0x88]`, 16-byte entries, `[0x4FC168]` count) and
runs `0xA3FB0`. That has toggles (`0x599934`, `0x5AB031`), a 0-2 cycle
(`0x4FC108`), and a map load (`0x505968` → `0xCCB00`): a level select.
Untested in game, and it's unknown whether retail draws its text.

