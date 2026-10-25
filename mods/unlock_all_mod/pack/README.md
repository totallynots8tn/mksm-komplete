# Unlock All

Unlocks the game's full roster and bonus content while the mod is enabled:
all characters, arenas, modes and extras that the game itself grants through
its complete-unlock mask.

## How it works

Progress lives in a 13-dword bitset at `0x005A375C` in the running game. This
mod does not guess which bits matter. It reproduces the game's own
full-unlock routine:

- Sets the same bit ranges as that routine: 101-164, 166-341 and 343-358
  (the game intentionally skips bits 165 and 342).
- ORs in the same extra masks the game uses for dword 2, dword 3 and dword 11.
- Sets the three exact-value flag bytes at `0x5A378D`, `0x5A378E` and
  `0x5A378F` to `1` while preserving the rest of the final dword.

The mask is applied:

- after the profile-load thunk at `0x00014D36` copies the profile bitset into
  memory,
- before the character-list builder at `0x000127BB` reads it, and
- as a cheap check on the game/mode getter at `0x000138F0`.

Because the check is idempotent and runs after profile loads, loading a save
or creating a new profile cannot silently re-lock the roster.

## Install

1. Open the Recomp launcher's Mods tab.
2. Choose "Install from file..." and select `unlock_all-1.1.0.tar.xz`.
3. Enable **Unlock All** in the mod list.
4. Start the game.

Requires Shaolin Monks Recomp 0.2.0 or later.

## Notes

- The mod changes game memory only. It does not edit save files, so disabling
  it returns the profile to its real unlock state.
- The unlock is active for every profile load while the mod is enabled.
- Local mod only. Do not redistribute extracted game resources or assets
  without distribution rights.
