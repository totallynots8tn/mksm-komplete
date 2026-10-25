You are working in C:\Users\Arcade Machine 1\Documents\MKSMK (Windows, Python 3). The project is a pack of Lua routine mods for Mortal Kombat: Shaolin Monks on ShaolinMonksRecomp 0.2.0. It will be published as its own repo under the working title "UMKSMK". Claude is doing the reverse-engineering and the mod code this round. Your job is release prep, documentation and one front-end page.

Read first:
- README.md (root)
- donate.html
- every file in mods/_build/readme/ (one readme per mod; they are the source of truth for each mod's state)
- analysis/upgrade_design/DESIGN.md (your earlier work)
- mods/_build/HANDOFF.md (bottom sections)

TASKS

1. RELEASE HYGIENE (prepare, don't publish)
   a. Write a root .gitignore for the future repo. It must exclude everything that is game content or third-party:
      - *.iso, *.xbe, *.xiso
      - "Mortal Kombat - Shaolin Monks*/"
      - "UMKSM VERSION II 2.6/" (RelaxDirk's mod: never redistribute it)
      - "ShaolinMonksRecomp-0.2.0*/" (upstream project; link to it instead)
      - analysis/umksm_port/out/*.elf
      - analysis/luaenv/
      - __pycache__/
      - mods/.mksmk-backup/
      - *.dmp
      Do NOT run git init, git add or any git command.
   b. Update the package list in analysis/final_validate.py (the `pkgs` list near the top) to the newest dist/*.tar.xz of each mod that actually exists today. The current list points at old versions and a retired mod (ldk_bosses, now built into ldk). Change nothing else in that file. Then run `python analysis/final_validate.py` and report its output. If it fails, report the failure; don't "fix" mod code.
   c. Fix stale text in the root README.md:
      - `ldk` and `ldk_bosses` no longer conflict; Boss Invasion is built into LDK 3.2.
      - List every current mod with its current version: read each mods/<mod>/pack/mod.json.
      - Keep the Legal section and its meaning; you may improve the wording.
   d. Write release/RELEASE_NOTES.md: a table of every mod with version, status (Works / Experimental / Prototype / Diagnostic) and a one-line known-issue, taken from its readme. Mark Solo Co-op Paths and Extended Upgrades experimental.

2. LANDING PAGE (front end)
   Make release/site/index.html: a single self-contained page (inline CSS, no external scripts or fonts) for the UMKSMK mod pack.
   - Hero, a mod list with version and status badges, install steps (Recomp launcher → Mods → Install from file), a requirements block (legally obtained game + Shaolin Monks Recomp 0.2.0+), FAQ, credits, and a donation section that links to donate.html.
   - Make it look good on a phone and support dark mode.
   - Put the pack name in ONE place (a CSS/JS constant or a single heading) so it can be renamed easily.
   - Do NOT use Midway/WB/NetherRealm logos or trademark styling, and do NOT use game screenshots or assets.
   - Credits must say: unofficial fan mods, not affiliated with Midway/WB; built on Shaolin Monks Recomp; the UMKSM roster idea is credited to RelaxDirk's UMKSM, with no files from it included and no affiliation implied.

3. UPGRADE DESIGN UPDATE (analysis/upgrade_design/DESIGN.md only)
   - Correction: your doc ranks dismemberment "most feasible" because enemy_detach_bone/enemy_detach_group/mutilate_collision are hookable. Probe logs show weapon kills never call them: they are level-script commands. Combat damage runs `0x17877F → 0x175037 → 0xBFB81 → apply damage 0x153DC0 / 0x153E9C`. Re-rank dismemberment as "needs combat-path RE" and say why.
   - Add an AIR COMBAT perk group, from your own text dump:
     - [492] "Air Juggle"
     - [973] "Combo: More Air Combo Hits" (Square ×5)
     - [981] "Combo: More Dive Kicks"
     - [992] "Combo: Air Throw Ender"
     - [1415] air-reaction recovery
     Propose 4–6 perks (e.g. more air hits, longer juggle, air dash/recover). Each one names the game value Claude would need to find; label those GUESS.
   - Keep everything else; mark your edits with "(rev 2)".

RULES
- Write ONLY: .gitignore (root), README.md (root), analysis/final_validate.py (pkgs list only), and new files under release/ and analysis/upgrade_design/.
- Do NOT edit anything under mods/ (Claude is changing mods/_build/src, tests, build.py and the packages right now), analysis/xbox_roster/, analysis/umksm_port/, analysis/routine_targets.txt, HANDOFF.md, donate.html, or any game/ISO/XBE file.
- No game launch, no mod installs, no %LOCALAPPDATA% changes, no git.
- Label anything uncertain as GUESS.

DELIVERABLE
A chat summary of 12 lines or fewer: files written or changed, final_validate.py output (pass/fail plus first error), and anything you couldn't do.
