You are working in C:\Users\Arcade Machine 1\Documents\MKSMK (Windows, Python 3). It's a pack of Lua mods for Mortal Kombat: Shaolin Monks on ShaolinMonksRecomp 0.2.0. Claude writes the mods. Your job is to analyse the QA data from today's long playthrough and turn it into findings Claude can act on.

RULES
- Write ONLY inside analysis/qa_analysis/ (create it).
- Everything else is READ-ONLY. Never edit qa/, mods/, tools/, release/, analysis/ outside your folder, any .xbe/.iso, or %LOCALAPPDATA%. Don't launch the game, install anything or use git.
- Python standard library only.
- Mark anything inferred as GUESS. Quote offsets and values as hex. Never invent a format: print unknown tokens raw.

INPUTS (read-only)
- qa/run-*/saves/*.dat and qa/run-*/index.csv. Every save.dat the game wrote today, with time and slot labels. save.dat is 193,088 bytes, mostly zeros, and holds several slots. Each slot has an ASCII label like "LIU KANG.128.00:41:35" (character.map.playtime).
- qa/run-*/logs/*.log. Game logs; the same file name can appear in several run folders, so dedupe by name and keep the largest copy. Probe reports are single lines: "Mod routine: mksmk_probe: <TAG> save#N ... | <body>". Tags: EVENTS, SAVEDIFF, UPGRADE, SHUFFLE, PLATE.
- tools/logread/logread.py, an existing parser (import it or call it). tools/logread/README.md documents the EVENTS tokens: G<group>n<count>p<poolfree>[type=free/total,...]L<loaded types>, S<type>:<bytes>, F (failed spawn), D/K (deaths). Types are hex.
- qa/softlock-*/ and qa/crash-kitana/: soft-lock and crash snapshots (peek.txt, logs, a minidump).
- analysis/xbox_roster/characters.json (type id -> name and slots) and maps.json (map -> preloaded types).

TASKS

1. Upgrade unlocks in the save. In qa/run-20261024-2243/, the player bought move upgrades right after launching, then saved (save #2, 22:44:28). Save #1 (22:43:37) is the state before. Byte-diff save #1 against save #2. Group the changed bytes into runs and report each run's offset, length, old and new hex. Attribute each run to a slot by the nearest preceding slot label, and explain what the label offsets tell you about slot size. Then do the same for every other consecutive pair of saves in all runs, and list the offsets that change in every diff (playtime, XP) separately from the rare ones (upgrades, unlocks). GUESS which field is XP: the player had 6650 EXP (0x19FA) at one point, 2890 (0xB4A) at another. Search for those values as u16, u32 and f32.

2. Brutality and dismember data. From every UPGRADE report, merge the "ANIM histogram" tokens and the "sampled commands" (mutilate, reaction, startanim, with callers). List the animation event types that only appear with [F] (fatality/brutality mode). Highlight the consecutive player block p[F]1D..p[F]3D, which all have the same count and are probably the brutality combo. Tabulate the mutilate calls: victim pointers, args and callers.

3. Soft-lock and crash timeline. For every log, give the session start, every save (time), probe reports present, script errors ("Mod routine" lines that aren't probe reports), crashes ("exception C0000005") and the last map. Cross-reference qa/softlock-*/peek.txt and qa/crash-kitana. One table, ordered by time.

4. Spawn health per area. From all EVENTS reports, list per session:
   - group starts whose L list shows a new area;
   - spawns per type, with average cost;
   - failed spawns (F), counted per area;
   - the lowest free heap per type.
   Flag areas with many F tokens; those are where enemies went missing.

5. Demon Orochi question (GUESS). The player saw two "Demon Orochi" in one fight, one out of bounds. Claude suspects type 0x4D (77): its heap dropped by about two instances with no S4D spawn token, which suggests a script spawn, not the wave spawner. Find every session where 0x4D or 0x1A is loaded, show the heap free values around it, and say whether the drops look like 1 or 2 instances (an instance costs about 0x24000-0x26000).

ACCEPTANCE
Write analysis/qa_analysis/build_report.py, which rebuilds analysis/qa_analysis/REPORT.md from the inputs. Run it twice; the two REPORT.md files must be byte-identical. Paste the md5 of both runs.

REPORT.md must have one section per task. Each section starts with a 3-line summary and then the evidence tables. Keep tables to 40 rows or fewer, and put any overflow in analysis/qa_analysis/*.csv.

DELIVERABLE
A chat summary of 15 lines or fewer: the top findings (especially the upgrade-unlock offsets and the XP field), the md5 check, and anything you couldn't do.
