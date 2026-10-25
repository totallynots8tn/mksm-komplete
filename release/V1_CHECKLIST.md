# v1 publish checklist

## Before calling it v1

- [x] **Full v1 run** on the `release/v1` set (LDK 3.9.6 x3 + Shuffle 0.6.6),
      through every fatality room. This pair passed them all on 2026-10-24;
      the campaign was finished through Shao Kahn and the credits on
      2026-10-25 (qa/run-20261025-1118: no crashes, no script errors, no
      failed spawns, no stuck waves). The newer builds (Shuffle+, guard and
      fatality changes) are v1.1 and live in `release/v1.1-dev`.
- [x] **v1 is x3 only** (decided 2026-10-25): `ldk`/`ldk_x4` 3.9.6 moved to
      `release/v1-retired`. Probe 0.11.0 (heartbeat, per-save stats) and the
      modtool x3 default were built from `mods/_build` after the patch4
      snapshot: noted in RELEASE_NOTES ("Source of the v1 packages"); attach
      the patch4 snapshot zip to the release.
- [x] **Name.** MKSM Komplete+ (short: MKSMK), decided 2026-10-25. It drops
      the UMKSM-derived "UMKSMK", so no permission is needed for the name.
      Repo name: `mksm-komplete` (no "+": repo names and some file systems
      reject it).
- [ ] Release assets are `release/v1/` (packages + `SHA256SUMS.txt`). Its
      source is `release/snapshots/mksmk-source-v1-patch4.zip` (checkpoint + memory-guard patch 2 + Reptile boss fixes).
      The repo's `mods/_build` holds the v1.1 work, so tag v1 from that
      snapshot or note it in the release.

## Publishing

- [ ] **Stay anonymous.** Make a separate GitHub account, `totallynots8tn`,
      signed up with totallynots8tn@gmail.com, and turn on "Keep my email
      addresses private" in its settings. Your usual git setup is signed in as
      your personal account, so set the identity inside this repo only, right
      after `git init` (local config, not `--global`):
      `git config user.name "totallynots8tn"` and
      `git config user.email "<id>+totallynots8tn@users.noreply.github.com"`
      (the exact noreply address is shown in the new account's email
      settings). Sign Git Credential Manager in as `totallynots8tn` when you
      first push. Check with `git log --format="%an <%ae>"` before pushing.
- [ ] Create the repository `totallynots8tn/mksm-komplete`. Make it private
      first if you want a look before it goes public.
- [ ] From the project folder: `git init`, `git add .`, then check
      `git status`. Expect about 94 files: scripts, tests, tools, docs. No ISO,
      no `default.xbe`, no UMKSM files, no Recomp binaries, no `qa/`. The
      `.gitignore` keeps those out.
- [ ] First commit and push.
- [ ] Run `python tools/installer/build_release.py` (needs `pip install
      pyinstaller`), then create GitHub Release `v1.0.0` and attach
      `release/dist/MKSM-Komplete-v1.zip` (installer .exe + packages, no
      probe) and `MKSM-Komplete-v1-contributor-tools.zip` (probe + QA tools).
- [ ] Optional: list the mods in the Recomp launcher's Krypt catalog
      (`docs/MODS.md`, "Publish and update") so players can install them from
      the launcher.
- [ ] Optional: host `release/site/index.html` (GitHub Pages) and link it from
      the README.

## Already done

- Donation link: buymeacoffee.com/S8tn, in `donate.html`, the landing page
  and the README.
- License: MIT (`LICENSE`).
- Credits and legal notes: in `release/RELEASE_NOTES.md` and on the landing
  page. No game assets are included.
