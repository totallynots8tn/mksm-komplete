# Time Rifts 0.2.0 (preview)

Existing co-op portals reload their current area instead of taking you to their original destination. Jump into a rift portal as usual.

- **Wu Shi (map 1):** reloads the area and its authored enemies.
- **Goro's Lair (map 100):** reloads the authored Goro encounter and enemy groups. With the test set's campaign-tested LDK x3 enabled, those enemies provide the rush; Time Rifts itself does not clone enemies or bosses.

The reload uses each portal's own `loadmap` event and the game's full area loader. No boss AI is moved between arenas, no Living Forest gates are touched, and no rewards or progression are changed.

**Experimental:** portal trigger 27 is identified from the Wu Shi trace; Goro's portal resources and arena are confirmed, but its trigger and same-area reload still need live verification. Test the Goro fight, enemy waves, repeated activation, player position, camera, and the route out. Disable the mod and reload a save if the area does not return cleanly.

Requires Shaolin Monks Recomp 0.2.0 and Solo Co-op Paths to reach co-op portals in single player.
