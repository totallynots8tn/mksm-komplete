# Time Rifts: evidence and next build

Research pass: 2026-10-28. This records what the current files and captures
support, and which attractive conclusions they do not support yet.

## What the evidence confirms

- Cross-area character streaming works. The player's current Goro's Lair
  screenshot shows a portal-area monk as an outsider; earlier QA also saw
  Johnny Cage and a demon captain there. This supports using the game's normal
  character streaming path for a rift enemy. It does not prove that the boss
  AI, encounter controller, or portal prop can be transplanted safely.
- Wu Shi arena is map 110. Its XBE descriptor is `0x4FF2E8`; `+0x7C` is
  `0xFFFFFFFF`, so it has no authored spawn-group file. Its PWF resources
  include record `0xC3C` (`triggers`, 624 bytes), `0xC3D` (`PS2.bin`) and
  record `0x1135` (`_portal_sf.dat`, 186,368 bytes decoded). The game also has
  record `0x11D5` (`_wushi_arena_sf.dat`, 176,128 bytes decoded).
- Map 110's trigger file declares two trigger entries and an event table with
  `map05_to_01` / `loadmap`, two breakable-object events, and `load_text` /
  `gametext`. The file does not identify an authored portal. The two entries
  are not evidence of a portal interaction.
- The loader queues map 110's spawn groups only when `desc+0x7C != -1`
  (`0xD1E50`); group-file parsing starts at `0x14D2C`. The 0.4.1 prototype
  temporarily substitutes the Wu Shi entrance's spawn file, then waits for a
  native `callspawn`. That is an unverified workaround, not a director the
  arena is known to have.
- The full log from `run-20261028-1454` shows repeated map-110 trigger `T0`
  requests to map 105, entry 5, plus `T1` activity. That Probe build did not
  include the later event-action/group correlation, so the absence of a
  `callspawn` summary there cannot be used as proof that none ran.
- Recomp routine Lua can read and write guest memory, but has no guest-call or
  guest-allocation API. Therefore a routine hook cannot simply construct a
  portal scene object. The mod format can replace numbered PWF resources, so
  the visible portal likely needs a content-resource change, with a routine
  mod only for runtime behavior.

## Counter-checks

1. **“Outsiders work, so the boss encounter is solved.”** Only the character
   load path is demonstrated. A fight still needs a reliable trigger, a
   spawn controller, safe memory capacity, and a valid boss AI state.
2. **“The portal asset exists, so loading it adds a portal.”** Existence is
   not instantiation. The asset format and the map's references to it still
   need to be decoded; blindly swapping an empty map slot could feed the
   wrong resource type to the loader.
3. **“Borrow a spawn table and wait for callspawn.”** Map 110 has no native
   spawn-file reference. Borrowing the entrance table can expose it to
   Shuffle's group hooks and can disable or rewrite unrelated groups. The
   prior empty-arena capture used an older Probe build and did not resolve
   whether a director runs.
4. **“Use a trigger already in the arena.”** The trigger file only proves two
   entries and the listed event names; it does not prove their locations,
   conditions, or that either can serve as a portal. The full 0.12.8 capture
   should be used to map runtime trigger IDs to event calls before repurposing
   anything.

## Recommended feature slice

Build a content-backed portal in map 110 first, using the native portal asset
as a reference and the arena scene/trigger resources as the insertion point.
Keep the content patch scoped to map 110. Then add one explicit same-map
portal action and route its alternate load into a dedicated Oni Warlord
encounter. Do not make the encounter depend on an unspecified arena
`callspawn`; provide or adapt a dedicated spawn group, and coordinate its
runtime hooks with Shuffle so the shared engine hooks cannot rewrite it.

The first playable QA target is deliberately small: portal is visible,
activating it uses the game's loading/transition path into map 110, exactly
one Oni appears, it can be killed, and leaving/re-entering resets the rift.
Keep Shaolin Shuffle enabled in the coexistence pass. No release work is
implied.

## Next evidence needed

Use Probe 0.12.8 to capture the complete `rifttrace=` and `rift110=` sections
from one arena visit, including the trigger IDs/actions and any `callspawn`,
group-start, and spawn-entry records. No need to repeat the Wu Shi-to-Portals
route. If the new run is unavailable, decode the map-110 trigger and scene
resource formats offline before writing runtime mutations.
