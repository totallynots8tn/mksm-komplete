# Pause Save 0.9 (soft-lock recovery)

Save anywhere, so a soft-lock doesn't cost you everything since the last
save statue.

## How to use

1. Pause the game (Start, or Enter on the keyboard).
2. Press **Back**: Backspace on the keyboard, View on an Xbox pad, Share on a
   PlayStation pad.
3. The save statue's save menu opens. Pick a slot and save as usual.
4. The game resumes when the save menu closes.

If you're stuck and have to quit, save this way first, then Alt+F4 and load
the save.

Tips:

- Save to a **spare slot** when you're stuck, not over your main save. A
  save made mid-fight can't fix whatever trapped you; it just keeps your
  progress.
- Back only works on the main pause page, not inside sub-menus such as
  Options.
- Back has to be pressed after the pause menu opens. Holding it while you
  pause does nothing.

## How it works

The pause menu has an unused path to the save menu: when it closes, it
checks a flag and, if the flag is set, calls the same routine a save statue
calls. No pause menu item sets that flag, which suggests the save option was
cut. Pause Save sets the flag and closes the pause menu when you press Back.
The save itself is the game's own statue save, with the same menu, slots and
file.

## Compatibility

Works alongside every other MKSMK mod. It only reads the controller state and
two bytes of the in-game menu manager.
