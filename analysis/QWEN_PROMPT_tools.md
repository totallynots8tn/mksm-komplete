You are working in C:\Users\Arcade Machine 1\Documents\MKSMK (Windows, Python 3). The project is a pack of Lua routine mods for Mortal Kombat: Shaolin Monks on ShaolinMonksRecomp 0.2.0. Claude does the reverse-engineering and the mod code. You build tools and data tables that speed up QA and design.

There are TWO tasks. Each one has a hard acceptance check. You're not done until it passes, and you paste its output.

RULES
- Write ONLY inside tools/logread/ (task 1) and analysis/roster_table/ (task 2). Create both folders.
- READ-ONLY everywhere else. Never edit mods/, analysis/xbox_roster/, analysis/routine_targets.txt, any .xbe/.iso, or the game's data folder.
- Never touch %LOCALAPPDATA%\Shaolin Monks Recomp except to READ its logs\ folder. No game launch, no installs, no git.
- Python standard library only.
- Label anything inferred GUESS. Don't invent formats: if a token doesn't match the spec below, print it raw under "unparsed".

======================================================================
TASK 1: QA log reader  (tools/logread/logread.py)
======================================================================
Logs live in %LOCALAPPDATA%\Shaolin Monks Recomp\logs\shaolin-recomp_NNN.log. One file per game launch; NNN increases.

Usage:
  python tools/logread/logread.py            newest log
  python tools/logread/logread.py --last 2   the 2 newest logs
  python tools/logread/logread.py --log 071  one specific log

For each log, print a short human summary (aim for under 60 lines) with these sections:

A. Session: duration (last timestamp), "Mods: N routine scripts active", and every save. A save is a line `open U:\...\save.dat` that comes right after a `SaveMeta.xbx` line; print the timestamps. Also say whether the log ends with "Exit (0)", and list crash dumps in ..\crashes\ whose modified time falls inside the session.

B. Mod errors: every "Mod routine: <mod>: <message>" line whose message does NOT start with one of the known report tags below. These are real script errors. Print them in full.

C. Reports. Each report is one line:
   `Mod routine: <mod>: <TAG> <reason> <fields> | <body> ... Script disabled for this session.`
   Known tags (mod mksmk_probe unless noted): EVENTS, PLATE, SHUFFLE, UPGRADE, and PLATE051 / PLATE052 / PLATE054 / PLATE060 (mod coop_solo, older builds). Parse them like this:

   EVENTS body (space separated tokens):
     D<idx>@<callers>              a character died (idx = char slot; 0/1 = players)
     K<idx>:<hp>@<callers>         instant kill / kill-and-hide
     A<idx>:<old>><new>            damage applied (hp old > new)
     B<idx>:<old>><new>            body damage (hp old > new)
     X<player>:+<n>c<combo>@...    XP set call
     XP+<n>c<combo><<death token>  XP awarded
     G<group>n<count>p<poolfree>[<type>=<free>/<total>,...]L<six loaded types>   group start
     S<type>:<bytes>               a spawn took <bytes> from that type's heap (hex)
     S<type>:<bytes>!fail          ...and the spawn failed
     F                             a spawn failed
     ...(<n> dropped)...           middle of a long session omitted
   Print: kills/deaths per char slot, total XP awarded and the biggest single award, group starts (count and pool free), spawns per type (count, average cost, failures), and the lowest heap free seen per type, as a percentage of total.

   SHUFFLE body: "areas=<n>" then one {...} block per area:
     {mode=.. frame=.. slots=<n> eligible=<n> freegates=<n> loaded=[a,b,...] | <type>=<count><flags> ...}
     flags: "once" = authored once; L/l = loaded or not; H/h = owns a memory heap or not.
   Print one line per area: loaded types, eligible/slots, and the list of types per flag group.

   UPGRADE: print the header fields, every sampled command (name, args, callers) grouped by name with counts, the "| ANIM " histogram as a sorted table (key = owner p|o, optional F = fatality mode, hex event type), and the "| STATE " transitions.

   PLATE (probe) and PLATE0xx (coop_solo): print the header and the body tokens, one per line, first 40.

D. Input: count "input: gamepad port=0 buttons=XXXX A=.. B=.." lines, and the distinct non-zero buttons values with their counts.

ACCEPTANCE (paste the output):
  python tools/logread/logread.py --log 071
  python tools/logread/logread.py --last 3
Both must run without a traceback on the real logs. Also write tools/logread/README.md (usage plus an example of the output).

======================================================================
TASK 2: area roster table for Shaolin Shuffle 0.7  (analysis/roster_table/)
======================================================================
Inputs (read-only):
- analysis/xbox_roster/maps.json: every map descriptor. "map" is the id, "preload" is the enemy types the area loads up front (up to 4 enemy type slots exist in total), "preload_cap" is how many of the 4 it may preload.
- analysis/xbox_roster/characters.json: 91 character types. "name" is filled in where known; "slots" is how many memory slots it needs (1 or 2).
- analysis/upgrade_design/out/text_game.csv: your game text dump, for area or level names.
- SHUFFLE reports in real logs (see task 1): ground truth for a few areas.

Facts (verified by Claude; use them as given):
- An area can have at most 4 enemy types loaded at once. The types it preloads use slots; the rest of the 4 are free for types that stream in on demand (elites and bosses).
- Regular enemy types are ids 2–49. ids 50+ are MK characters and bosses.
- Two-slot types (characters.json "slots" = 2) need two free slots.

Produce:
1. analysis/roster_table/roster.csv, one row per map:
   map, preload types (ids and names), preload_cap, free_slots = 4 − (slots used by the preload list), area_name (GUESS if inferred, blank if unknown), candidate_outsiders = regular types (2–49, 1 slot) that some OTHER map preloads but this map doesn't, ordered by how many maps use them.
2. analysis/roster_table/ROSTER.md:
   - the table for the 20 maps with the most free slots;
   - a list of regular enemy types used by only one map (good "rare" outsiders);
   - how you tried to map map ids to area names, and how confident you are (GUESS unless proven);
   - cross-check: for every area in a real SHUFFLE report, find the map whose preload list matches its `loaded=[...]` enemy types, and say which map it is.

ACCEPTANCE: a script analysis/roster_table/build_roster.py that rebuilds both files from the inputs. Run it twice; the outputs must be byte-identical. Paste its summary line, the md5 of roster.csv from both runs, and the SHUFFLE cross-check results.

DELIVERABLE: a chat summary of 12 lines or fewer: files written, acceptance outputs, anything you couldn't do.
