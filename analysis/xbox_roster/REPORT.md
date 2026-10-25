# Xbox roster RE: character loading, the stream gate, brutality leads

All addresses are Xbox `default.xbe` (x86, SHA-256 `48240902…db74a`), verified by
disassembly in this round. "Hookable" means the address is in
`analysis/routine_targets.txt`. Data dumps: `characters.json`, `maps.json`.
Tools: `tools/` (see the end of this file).

## TL;DR for shipping

- The PS2 `minterface.c` pipeline has direct Xbox equivalents (table below).
- Every character, players, enemies and bosses alike, is one row in a static
  91-entry **character file table** at `0x4FA9F0` (IDs 0–90, same ID space as
  spawn-entry `+0x00` "enemy type" and `LOADED_TYPES`).
- The "6-slot gate" is **2 player entities + 4 enemy entities**, backed by 4
  enemy memory slots configured once at startup. It's the same for every map.
- Each map's enemy roster is a **static, writable preload list** in its map
  descriptor (`desc+0x24`, −1 terminated, cap at `desc+0x20`). 48 of 110 maps
  preload fewer types than their cap.
- Spawning a type that isn't loaded makes the game try to **stream it in on
  the spot** (`0x16C550` → `0x17B460`). It only succeeds if a memory slot is
  free. Occupied slots get marked in-use, so in practice that means one of the
  area's unused slots.
- So **UMKSM characters as enemies in LDK / Shuffle need no asset work**.
  Their files are already in GAMEDATA.WAD and listed in the table. A mod
  appends a roster ID to an area's preload list before the game reads it
  (before-hook `0x15DEE`). The game then loads it into a free slot itself,
  and it shows up in `LOADED_TYPES` with its own heap.

## PS2 → Xbox equivalents

| PS2 (`minterface.c`) | Xbox | Notes |
|---|---|---|
| `gModelInterface 0x67C590` | `0x64D218` | `ecx` for every `cModelInterface` call |
| `GetObjectPointer 0x283B50` | `0x144350` (also `0x144620`) | `GetObjectPointer(id)`, id 1-based; `id=1` → P1 entity `0x5D1AB8`, entities stride `0x3238` |
| `SetCharacterFiles 0x1CEE00` `(id, objectID, 0, 1, VRAM, 0x21)` | `0xC26B0` (thunk `0x140D4`, hookable) `(entity+0x68, charID, 0, player, [VRAM var], memblock)` | Same argument shape. Reads the char table row |
| `SetLoadedType 0x2F6BA0` | `byte [entity+0x2429]` = 3 (P1) / 4 (P2) | Written right after the files are queued |
| `PLAYER1_VRAM 0x4E5094` / `PLAYER2_VRAM 0x4E5098` | `0x5062A4` / `0x5062A8` | Enemy slots: `0x5062AC + slot*4` |
| `save_data +204 characterID / characterIDp2` | `[0x5ACEBC]+0xCC` / `+0xD0` | Same offsets. Manager getter `0xC4850` (thunk `0x15358`) |
| `SwapCharacterModel` (unfinished on PS2) | `0xC2E70` (thunk `0x111D1`, hookable, **no callers**) | Leftover "load charID into player slot" routine |

Other named functions (from the game's own assert strings): `tgtProcessObjectModel
0x113B50`, `Process_Character 0x1130D0`, `Associate_CharacterModel 0x113790`,
`AssignModelInstance 0x113EF0`, `Async_AddToLoadList 0x17A840`
`(file, …, callback, …)` (file −1 = `FILE_NULL`), `Async_InitLoad 0x17A9D0`,
`cGameMemInterface::GetGameCharacterMemoryBlockID 0x106980`.

## Character file table `0x4FA9F0` (91 rows × 0x30)

| Offset | Meaning |
|---|---|
| `+0x00` | `0x20004 + id` |
| `+0x04` | memory slots needed (1, or 2 for IDs 47 and 57) |
| `+0x08` | unknown small count (1–0x42) |
| `+0x0C` / `+0x10` | model / texture-WAD record |
| `+0x14` / `+0x18` | alt costume model / texture (players & VS fighters; used when P2 picks the same character or flag `0x5AC4FD`) |
| `+0x1C` | effects record |
| `+0x20`–`+0x2C` | further costume pairs |

File ids are **GAMEDATA.WAD PWF record indexes** (7281 records). Model records
are EWDF (raw deflate after the header). The decompressed models contain bone
names and usually an author name, which gave this map (full list in
`characters.json`):

| ID | Character | ID | Character |
|---|---|---|---|
| 0 / 1 | players (Liu Kang / Kung Lao) | 62 | Shao Kahn |
| 2–49 | regular enemy types | 63 | Kitana |
| 50 | Scorpion | 64 | Mileena? (`ninjagirl`) |
| 51 | Noob Saibot | 65 | Jade |
| 52 | Kano | 66 | Ermac |
| 54 | Baraka | 67 | Sub-Zero |
| 55 | Goro | 68 | Smoke |
| 56 | Kintaro | 70 | Raiden |
| 57 | Reptile (2 slots) | 76 | Johnny Cage |
| 60 / 61 | Shang Tsung young / old | 81–84, 88–90 | VS fighters with alt costumes |

## The stream gate, mechanically

- **Memory**: `InitialiseGameMemoryBlocks` is called once (`0xD2800` →
  `0x106D50` on `cGameMemInterface 0x6322F8`) from static templates at
  `0x5066E8`–`0x506778`. It sets 4 character blocks (`[+0x08]`) and 4 logical
  slots (`[+0x10]`). Block table `[+0x1C]` and slot table `[+0x24]` are both 20
  bytes per entry: `{heap, charID, firstBlock, nBlocks, flags}`.
- **Free test** `0x106B40(block)`: true when heap ≠ −1, flag bit 4
  (streamable) is set and bit 2 (in use) is clear. `0x17AF70` (find resident)
  sets bit 2 on every occupied slot it passes.
- **Make resident** `0x17B460(slotHint, charID, flag)` (hookable): reuse if
  loaded → else `0x17B060` (find `+0x04` consecutive free blocks) →
  `0x17AD60` (evict) → `0x17B360` → **`0x17AE20(slot, charID, …)`**
  (hookable) → `0xC3250` loads the files into entity `slot+2`, VRAM
  `0x5062AC+slot*4`, sound bank `0xA+slot`.
- **Callers of make-resident**: actor creation `0x16C550` (`(-1, type, 0)`,
  synchronous: it waits for the load), a deferred replace queue `0x17BA40`
  (ring at `0x6964E8`), and `0xC74A0` (thunk `0x111D6`, no callers).
- **`LOADED_TYPES 0x6CA69C[6]`** is written by `0x1C1620(charID, entity)`, which
  also writes `entity+0x1DFE` (the entity's charID) and the mirror `0x6CA664`.
  Probe log 064–068: `loaded=[0,1,E,1A,4D,-]` = P1, P2, three preloaded enemy
  types, one empty enemy entity.

## Map rosters `0x5020E8` (static descriptor pointers, indexed by map id)

The map table object is `0x505968` (`[+8]` current map, `[+0xC]` → `0x5020E8`).
Lookup is `0x172F60`. In each descriptor:

- `+0x20`: preload cap. `0xCFAB0` skips the preload entirely when more listed
  types are missing than the cap allows.
- `+0x24`: −1-terminated list of charIDs.
- `+0x44`: map number.
- `+0x48`–`+0x5C`: map files.
- `+0x7C`: spawn-group file (its load callback is `LOAD_GROUPS 0x14D2C`).

Examples: map 1 = cap 4 `[14,80,46,27]`; map 2 = cap 3 `[14]`; maps 103/107 =
cap 3 `[14,26,77]`. Some maps have empty lists, which means those areas stream
everything on demand.

**Load order** (`0xD20F0`): `0xD1E50` queues the map files incl. the spawn
groups and waits (`0x17ACE0`), *then* `0xD1F70` loads the players and runs
`0xCFAB0` → `0x17B6E0(list, 0)`. So **the spawn census already exists when the
preload list is read.** A before-hook on `0x15DEE` (desc at `[esp+4]`) can
decide what to add with full knowledge of the area's authored types.

## Proposed shipping design (needs one in-game test)

**"Outsiders" for Shaolin Shuffle 0.7 and LDK Boss Invasion**

1. In a before-hook on `0x15DEE`, take the area's census. Let *reserved* be the
   authored types that aren't in the preload list (elites and bosses that
   stream on demand), and *free* be `4 − preloaded − reserved`.
2. If `free ≥ 1`, append one roster ID with `+0x04 == 1` (Raiden 70, Mileena
   64, Jade 65, Kitana 63, Smoke 68, Ermac 66, Noob 51, Kano 52, Baraka 54,
   Scorpion 50, Sub-Zero 67, Shang Tsung 60, Johnny Cage 76). Raise `+0x20` to
   the new list length if needed. The list has room for 7 IDs plus the −1
   terminator before `+0x44`. Vanilla lists hold at most 4.
3. Shuffle converts a few common entries to the outsider (not a pure
   permutation). The outsider has its own fresh heap, so per-type memory
   rules still hold, and `can_afford` covers instance costs after the first
   spawn.
4. Boss Invasion treats loaded types with census 0 as invaders too.

Risks to verify in-game:
- Whether a slot freed this way is still enough for an on-demand boss that
  the census missed (scripted spawns outside the spawn manager).
- Whether boss AI stays sane outside its arena. Boss Invasion already says it
  does.
- The extra load time at area start.

Never add 2-slot characters (47, 57).

**Playable UMKSM characters (later, separate mod).** Writing `[0x5ACEBC]+0xCC`
before `0xC2F70` runs, or rewriting the charID argument in a before-hook on
`0x140D4`, makes P1 load another character's files. Expect UMKSM "tier 2"
results: non-player characters probably lack the player move/upgrade data.

## Brutality / enhanced moves leads (for Extended Upgrades)

- Fatality-mode manager singleton `0x58E068` (getter `0x3D7F0`): `+0x1A0` ≥
  10 = fatality mode active (`fatality` command, `0x3B810`); `+0x1A4` ≥ 10 =
  over (`0x3B840`).
- Per-player manager: pointer at `0x58D6A8`. The per-player info is at
  `[0x58D6A8]+0x310+idx*8`, where idx = `entity+0x68`. The brutality-off flag
  is at `[0x58D6A8]+0x318+(idx-1)*8+4` (`brutalityoff` → `0x3BF90`), with the
  count at `+0x388`.
- Meter: get `0xC9710`, set `0xC9740`, level `0xC9770`, per-level max `0x82EA0`.
- Next step: a probe that samples these fields plus `startanim` while the
  player enters brutality mode. That shows which field the enhanced moves key
  off, so the upgrade can force it for chosen moves.

## coop_solo lead

`actionButton`'s hidden gate `call 0x113A2(0x58D6A8, entity)` resolves to
`0x3BAA0` → `0x3B1B0`. It returns true only when `entity+0x23C` (non-zero)
equals one of two per-character values at `0x5999FC` / `0x599A00` +
`charID*0x6C` (a runtime table in bss). The PLATE05 report doesn't log
`entity+0x23C` yet. If `ret=0` with gate/state OK, this is the condition to
check next.

## Cross-check with Qwen's PS2 analysis (`analysis/umksm_port/`)

- **The PS2 character table is the same structure** at `0x4D6988` in
  `SLUS_286.88`: 91 rows × 0x30, `+0x00 = 0x20004+id`. It ends at `0x4D7A18`,
  which matches the end of Qwen's changed span. Qwen's "9-word runs" are fields
  `+0x0C`–`+0x2C`: model, tex, altM, altT, fx, c2M, c2T, c3M, c3T. The 6-word
  runs at `0x4D602C`–`0x4D68EC` belong to a separate table just before this
  one, not decoded yet.
- **Record mapping:** in the character range, PS2 record + `0x84` = Xbox
  record. This holds for every row except PS2 row 38, which the UMKSM ELF
  already points at `0x1933`. That suggests the shipped ELF isn't fully retail,
  so some "old" values are UMKSM's own.
- **UMKSM's roster edits are data, mostly portable.** All 1063 edits, with
  Xbox record numbers and gates, are in `umksm_table_edits.csv`:
  - `[0x5CA2AC]==2` (likely VS): fills enemy costume slots with each row's
    own model/tex, so enemy rows can be picked without empty-record loads.
  - Unconditional: permanent model swaps (e.g. row 2 → row 64's model,
    row 24 → `0x1933`) and costume fills for rows 70 and 72–75.
  - `[0x5CA2AC]==1` & selection vars `0xC2974C`/`0xC45648`: rewrites rows 68,
    84 and 88 per chosen character/costume. That fits story-mode play as an
    NPC by swapping the model onto a row that already has a full move set.
    This is a hypothesis, to be confirmed on Xbox by loading P1 as row 84 with
    a swapped model.
- Qwen's conclusion that all behavior is in the rebuilt ELF is probably
  overstated for the roster. The visible mechanism is table remapping, which
  an Xbox Lua mod can reproduce by writing `0x4FA9F0` (writable `.data`)
  before a load.

## Round 3 findings (shipped in Co-op 0.6, LDK 3.3, Probe 0.9)

- **Colored co-op plates** are triggers with `stonecolor:C` (`0x15574` → `0x20B90`).
  - The condition passes only if the activator's color `[[entity+0x2B6C]+4]` equals `C`. `setspawncolor` (`0x152C7` → `0x20A70`) assigns the colors.
  - Plates that fire run `addstonepower` (`0x11938` → `0x20C30`, adding to `0x581B48`). That value is reset only by the level reset at `0xD1280` → `0x20BF0`.
  - Doors check `stonepowatleast:N` (`0x13F94` → `0x20CB0`).
  - No button is involved. The `actionButton` triggers were other interactables; their action input is d-pad down, the game-button word bit `0x2`. A = `0x40`, X = `0x80`.
- **Event flags:** 200 bytes at `[0x5ACEBC] + 0x4874 + id`.
  - Read by `eventcomplete` (`0x16A4B` → `0xA4B70`) and `eventnotcomplete` (`0x14BCE` → `0xA4AF0`).
  - Written by the `gameevent(id, value)` event (`0x13134` → `0xA4A80`).
  - Cleared in bulk by `0xA4A00` / `0xA4A20`.
- **Save write:** `0x1272A0` (HardDisk: XCreateSaveGame, then CreateFile GENERIC_WRITE). `0x127420` is the read. `0xA2260` is a save path the statue doesn't use.
- **Combat dismemberment:** engine functions `0x10C3B0` (detach bone), `0x10C600` (detach group) and `0x10BD70` (mutilate). They're reached from the animation-event dispatcher `0x180D30(entity, a2, type, ...)` (a ~560-way switch) and from the script commands `0x1A33E0` / `0x1A34A0` / `0x1A3350`.
- **Health:** actor `+0x368` current, `+0x370` max; `setHealth` = `0x153CD0` (ecx = actor). `+0x134` is a lock flag. The actor's entity is `[actor+0x31C]`, and its player index is `entity+0x68`.
- **Combat kill chain** (probe): `0x17877F → 0x175037 → 0xBFB81 → 0x153E9C` (inside apply damage `0x153DC0`).

## Tools (`tools/`)

- `xt.py`: XBE helpers on top of `analysis/xbe_lib.py`:
  - `xref_imm`: immediate-value xrefs.
  - `callers` / `callers2`: callers including thunks.
  - `fn`: containing function, from call targets plus int3 padding.
    `routine_targets.txt` isn't a full function list.
  - `dis` / `disfn`: disassembly with string and thunk annotations.
  - `nm`: assert-derived function names.
- `names.py`: harvests function names from assert/debug call sites into `fnnames.json` (891 functions). `q.py <regex>` searches them.
- `xiso.py`: read-only XDVDFS reader for the redump ISO (partition at `0x18300000`).
- `pwf.py`: GAMEDATA.WAD directory, record reader, EWDF inflate (`decoded(record)`), string scan.
