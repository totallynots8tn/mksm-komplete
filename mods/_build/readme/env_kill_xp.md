# Environmental Kill XP 2.0

Hazard kills now count **exactly like normal kills**. Each one adds its XP
(50 for most enemies, more for elites) to your running combo, gets your combo
multiplier, and shows up in the normal XP popup when the combo pays out.

## How the game pays kill XP

Every player has a combo stats object (`[[entity+0x2B6C]+0x50]`). A normal
kill goes through RegisterKill (`0x7E750`), which adds one to
`kills[enemy type]` in that object (`+0x118`, type = victim `+0x1DFE`). When
the combo ends (`0x7EA94`), the game multiplies those kills by the per-type
XP table at `0x508238`, applies your multiplier, shows the popup and pays.
Hazards kill through paths that never call RegisterKill, so those kills were
lost.

1.x added XP straight to your total. You got no popup and no multiplier, and
before 1.2.2 single player got nothing at all. 2.0 does what RegisterKill
does instead, and the game handles everything else.

| Path | Address | Typical hazard |
| --- | --- | --- |
| instant kill | `0x1F2500` | thrown off the map / over walls, kill zones |
| `killandhidecharacter` | `0x1F25B0` | pits, drops |
| `applydamage` | `0x153DC0` | spikes, saws, fire |
| `bodydamage` | `0x180CA0` | hazard dismemberment |

- Single player credits player 1. In co-op, the player with the longer
  combo gets the kill. Versus has no XP.
- Enemies the game marks as giving no XP still give none.
- One death counts once, even if several paths fire for it.

Requires Shaolin Monks Recomp 0.2.0 or later.
