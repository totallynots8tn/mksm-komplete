You are working in C:\Users\Arcade Machine 1\Documents\MKSMK (Windows, Python 3). The project is a pack of Lua routine mods for Mortal Kombat: Shaolin Monks on ShaolinMonksRecomp 0.2.0. Claude does the reverse-engineering and the mod code. You build data tables that speed up design.

ONE task, with a hard acceptance check. You're not done until it passes and you've pasted its output.

RULES
- Write ONLY inside analysis/roster_table/ (create it if missing).
- READ-ONLY everywhere else. Never edit mods/, tools/, release/, analysis/xbox_roster/, analysis/routine_targets.txt, any .xbe/.iso, or the game's data folder.
- Never touch %LOCALAPPDATA%\Shaolin Monks Recomp except to READ its logs\ folder. No game launch, no installs, no git.
- Python standard library only.
- Label anything inferred GUESS. Don't invent formats.

======================================================================
TASK: area roster table for Shaolin Shuffle 0.7  (analysis/roster_table/)
======================================================================
Why: Shuffle only swaps enemy types that an area already loads. Goro's Lair
loads one regular type, so nothing changes there. Shuffle 0.7 will add
"outsiders": regular enemy types from other levels, loaded through the map's
preload list. This table tells Claude which outsiders fit each map.

Inputs (read-only):
- analysis/xbox_roster/maps.json: every map descriptor. "map" is the id,
  "preload" is the list of enemy types the area loads up front, and
  "preload_cap" is how many types it may preload.
- analysis/xbox_roster/characters.json: 91 character types. "name" is filled
  in where known; "slots" is how many memory slots it needs (1 or 2).
- analysis/upgrade_design/out/text_game.csv: the game text dump, for area or
  level names.
- SHUFFLE reports in real logs: ground truth for a few areas. Run
  `python tools/logread/logread.py --last 5` (already built) to see them, or
  read the raw "Mod routine: mksmk_probe: SHUFFLE ..." lines in the logs.

Facts (verified by Claude; use them as given):
- An area can have at most 4 enemy types loaded at once. The types it
  preloads use slots. The rest of the 4 are free for types that stream in on
  demand (elites and bosses).
- Regular enemy types are ids 2-49. Ids 50 and up are MK characters and
  bosses: never list those as outsiders.
- Two-slot types (characters.json "slots" = 2) need two free slots.

Produce:
1. analysis/roster_table/roster.csv, one row per map, with these columns:
   - `map`
   - `preload`: type ids and names
   - `preload_cap`
   - `free_slots`: 4 minus the slots the preload list uses
   - `area_name`: mark it GUESS if inferred, leave it blank if unknown
   - `candidate_outsiders`: regular types (ids 2-49, 1 slot) that some OTHER
     map preloads but this map doesn't, ordered by how many maps use them
2. analysis/roster_table/ROSTER.md, with these sections:
   - the table for the 20 maps with the most free slots;
   - the regular enemy types used by only one map (good "rare" outsiders);
   - how you mapped map ids to area names, and how confident you are (GUESS
     unless proven);
   - a cross-check: for every area in a real SHUFFLE report, the map whose
     preload list matches its `loaded=[...]` enemy types.

ACCEPTANCE: a script, analysis/roster_table/build_roster.py, that rebuilds
both files from the inputs. Run it twice; the outputs must be
byte-identical. Paste:
- its summary line;
- the md5 of roster.csv from both runs;
- the SHUFFLE cross-check results.

DELIVERABLE: a chat summary of 12 lines or fewer: files written, acceptance
outputs, and anything you couldn't do.
