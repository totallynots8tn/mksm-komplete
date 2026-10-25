# Contributing to MKSM Komplete+

Thanks for helping. This guide covers how the mods work, where things live,
the runtime rules every script must follow, and how to build, test and QA a
change. Read the [vision and roadmap](README.md#the-vision) first so you know
where the project is going.

## Ways to help

- **Playtest and send logs.** The most useful help there is. See
  [QA: playtests become data](#qa-playtests-become-data).
- **Reverse-engineering.** Map functions and structs the roadmap needs:
  - the upgrade-menu entry table (XP shop);
  - move and special-input handling (EX specials);
  - portal and area loading (New Game+ realities);
  - how the secret boss fights spawn and arm their boss (postgame).
- **Lua.** New mods, fixes, tests.
- **Docs.** Clearer install steps, translations, screenshots.

Open an issue before a big change so we can agree on the approach.

## Project layout

| Path | What it is |
| --- | --- |
| `mods/_build/src/` | Mod sources. `core.lua` is shared by LDK and Shuffle; `*_body.lua` are the mod-specific parts; `probe_*.lua` are diagnostics. |
| `mods/_build/build.py` | Assembles the sources into each mod's `pack/` folder and `dist/*.tar.xz` package. `python build.py <folder>` rebuilds just one mod. |
| `mods/_build/tests/` | Offline tests and `harness.lua`, an emulation of the Recomp routine runtime. |
| `mods/_build/modtool.py` | Bulk install/uninstall into the launcher's mods folder (used by the `.bat` files and the installer). |
| `mods/<mod>/pack/`, `mods/<mod>/dist/` | Built output: the unpacked package and the `.tar.xz`. |
| `release/v1/` | The v1 release packages and `SHA256SUMS.txt`. `release/v1.1-dev/` holds v1.1 builds. |
| `tools/qa_recorder/` | Archives every `save.dat` version and session log while you play. |
| `tools/livemem/peek.py` | Reads the running game's memory (spawner, enemy heaps, waves) to diagnose soft-locks live. |
| `tools/installer/` | The small install window. |
| `analysis/` | Reverse-engineering notes, roster/map tables and QA reports. |

The `mods/_build` sources are the development line (v1.1). The v1 release was
built from `release/snapshots/` so it matches exactly what was QA'd.

## How a routine mod works

Shaolin Monks Recomp runs Lua 5.4 scripts that hook addresses of the original
Xbox code. A script returns a list of hooks:

```lua
return {
    {   address = 0x001272A0,           -- the statue-save write
        before = function(ctx)          -- runs before the original code
            local xp = game.read_u32(game.read_u32(0x005ACEBC) + 0x4940)
        end },
}
```

- `ctx` holds the guest registers (`ctx.eax`, `ctx.ecx`, `ctx.esp`, ...);
  stack arguments are read from `ctx.esp + 4`, `+ 8`, ...
- `game.read_u8/u16/u32(address)` and `game.write_u8/u16/u32(address, value)`
  access guest memory. Addresses are Xbox virtual addresses.
- A manifest (`mod.json`) lists the routine scripts and every file's SHA-256;
  the launcher verifies it on install. `build.py` writes it for you.

### Runtime rules (the launcher enforces these)

- **At most 64 routine scripts** may be active across all enabled mods, or the
  game refuses to boot. The v1 set uses 59 (the probe alone uses 54), so keep
  new mods to one or two scripts. `build.py` rejects a mod that leaves fewer
  than 8 free.
- **Instruction budget** per hook call (about 100,000 Lua instructions) and a
  **write budget** of 256 memory writes per call. Spread big scans across
  frames (see `probe_savediff.lua`, which reads 1 KB per frame).
- **Reads and writes must hit committed memory.** Validate every pointer you
  follow (`ok(p)` in the existing scripts).
- **An error disables the script for the session.** The only way a script can
  write to the log is by failing with `error()`. So diagnostics collect quietly
  and report once, at a statue save (`0x1272A0`). Mods meant to keep running
  must never error.
- Hooks run in the game's thread: keep them fast and side-effect free unless
  changing the game is the point.

### Conventions

- **Evidence first.** Every address or offset in a script needs evidence: a
  disassembly (address + bytes) or a captured log or memory dump. Note it in a
  comment or in `analysis/`. Guesses are labeled as guesses.
- **Memory safety.** Never spawn or allocate beyond what the game's own heap
  has left. LDK and Shuffle share the guard in `core.lua`; reuse it.
- **Vanilla where it matters.** Boss fights and the three fatality tutorial
  rooms stay vanilla (other mods and progression detect them by their triggers).
- **Match the surrounding code**: comment density, naming, plain Lua.

## Build and test

```bash
cd mods/_build
python build.py               # every mod
python build.py mksmk_probe   # just one
```

Tests need any Lua 5.3+/5.4 interpreter (`lua54`, `texlua`, or `lupa` for
Python). Run them from `mods/_build`:

```bash
lua tests/sim.lua ../ldk_x3/pack/scripts/ldk.lua
lua tests/env.lua
lua tests/probe_heartbeat.lua ../mksmk_probe/pack/scripts/probe_heartbeat.lua ../mksmk_probe/pack/scripts/probe_heartbeat_2.lua
```

`tests/harness.lua` emulates the runtime: committed memory regions, the write
and instruction budgets, and `error()` disabling a script. A change isn't done
until its test passes and it has been played in the real game.

Install your build with `python modtool.py refresh <folder> --with-probe`
(close the game first; removed mods are moved to `mods\.mksmk-backup\`).

## QA: playtests become data

1. Install the mods with the probe (`Mods - reinstall latest + probe.bat`).
2. Start `QA - start recorder.bat` before the game. It archives every save
   and the session logs into `qa/run-<date>-<time>/`.
3. Play normally. Save at a statue now and then: each save writes the probe
   reports (spawns and heap use, XP, save-data changes, upgrade commands). A
   heartbeat report is also written every few minutes of play.
4. If something soft-locks, keep the game running and capture its state with
   `python tools/livemem/peek.py`.
5. Quit, stop the recorder with Ctrl+C, and attach the run folder's `logs/`
   (and `saves/` if relevant) to an issue with a line on what happened and
   where.

## AI-assisted work

This project is built with AI tools (see [Credits](README.md#credits)), and
AI-assisted contributions are welcome. The bar is the same as for any change:
evidence for every address, passing tests, a real-game check, and a PR that
says which parts were AI-generated.

## Pull requests

- One change per PR, with what it does, the evidence behind any new address,
  and how you tested it (test output and/or a QA run).
- Never commit game files, disc images, `default.xbe`, Recomp binaries, UMKSM
  files, crash dumps or `qa/` runs. `.gitignore` keeps them out; check
  `git status` anyway.
- By contributing you agree your work is released under the [MIT license](LICENSE).
