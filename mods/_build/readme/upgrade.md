# Extended Upgrades 0.1.0 (PROTOTYPE — experimental)

A scaffold for a bigger upgrade system: the extra XP from **Legendary Dark
Knight Mode** unlocks passive perks, so more enemies means more to spend on.
Planned perk groups:

- **Blade dismemberment** — behead and sever limbs with blades, as move
  attributes (`Decapitate`, `Sever Limbs`, `Cleaver`).
- **EX / new moves** — reuse the game's brutality animations as enhanced
  specials (`EX Finisher`, `EX Combo Breaker`).
- **Stamina** — a stamina/guard meter and upgrades for it (`Endurance`,
  `Recuperate`, `Iron Lungs`).

## What actually runs in 0.1.0

Only the **spine**: it watches each player's XP, keeps a running lifetime
total (unaffected by spending), and *unlocks* the perks in `src/upgrade.lua`
as that total crosses each threshold. The perk list and costs live in that
file's `UPGRADES` table — that is the design surface to edit.

**Every gameplay effect is inert.** This mod performs **zero writes to game
memory**, so it is completely safe to have installed — but you will not see
any change in game yet. That is expected for a prototype.

## Why the effects are not wired up

A Recomp routine mod can only **read/write memory and hook addresses**. It can
never **call** the game's functions — so it cannot directly play a brutality
animation, detach a bone, or run an upgrade routine. Each effect therefore
needs a verified *memory target*: a flag or field that, when written, makes the
game do the thing itself (the way `mkapowerup` / `healthupgrade` flip internal
state). Finding those targets is reverse-engineering, and it is what
**MKSMK Probe 0.7** (`probe_upgrade`) is for: it logs the arguments and effects
of the upgrade, mutilation (`enemy_detach_bone`, `enemy_detach_group`,
`mutilate_collision`) and brutality/animation commands, and dumps the player
state region to locate the stamina meter and confirm the XP slot.

Once a target is known, `apply()` in `src/upgrade.lua` writes it, and a small
hook (for dismemberment, on the detach/`bodydamage` path) reads the ownership
flag. The framework is already shaped for that.

## Design notes / open questions

- **No menu.** Adding entries to the game's upgrade menu means editing menu
  assets/data, which a routine mod cannot do. So perks unlock **passively at XP
  thresholds** instead of being bought — this is the "loose fun" the extra XP
  buys, with no UI work.
- **XP slot.** `manager+0x48F0+player*0x50` is the per-player XP value the probe
  already watches; the exact player index in single player is to be confirmed
  from the `probe_upgrade` dump.
- **Lifetime total.** Thresholds compare against XP *gained this session*, not a
  save's stored balance, so a continued save starts at 0 and perks re-unlock as
  you play. Cross-session persistence (tying unlocks to the save) is a later
  step.
- **Stamina.** The game may not expose a stamina meter at all; if not, this
  becomes a new meter the mod maintains, which is a larger job.

Requires Shaolin Monks Recomp 0.2.0 or later.
