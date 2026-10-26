# Extended Upgrades: XP Shop 0.8.4 (preview, experimental)

The XP shop spends XP in the game's own upgrade menu, on the game's own menu
entries. Nothing new is added to the menu, and everything it sells comes **on
top of** what the game gives you.

## What it does

Pause > Moves > **Basic Moves** becomes **Upgrades**, **Skill** becomes **EX
Moves**, and the **Fatalities** you haven't discovered can be bought. Every
other category, Team included, is unchanged.

| Category | Row | Cost | Effect |
| --- | --- | --- | --- |
| Upgrades > Health | Health +1 to +4 | 5,000 / 10,000 / 15,000 / 20,000 XP | 1 / 2 / 4 / 8 health-upgrade steps (+100 / +200 / +400 / +800 max health in solo), above the game's own 4 |
| Upgrades > Stamina | Stamina +1 to +4 | 5,000 / 10,000 / 15,000 / 20,000 XP | everything that spends the blue bar costs less: it plays as 125 / 150 / 200 / 300% |
| Upgrades > Weapons | one row per weapon lying in the current area | 2,000 XP per summon | the weapon appears beside you at full durability |
| EX Moves | EX * / ~ / \| / ^, one move at a time (Special 1, 2, ...) | 5,000 / 10,000 / 15,000 / 20,000 / 25,000 XP per move | L2 + that move's input (no R2): the move as an EX, for extra stamina |
| Fatalities | any row still showing ??? | 5,000 XP each | reveals that fatality's input and video |

- **Buying:** pick the next row and confirm in the usual Upgrade dialog. Health
  and Stamina rows are bought in order. Rows
  only unlock when you have the XP, and as with Combos the description stays
  hidden until you can buy a row.
- **Weapons** sells the weapons of the area you are in: the kamas where kamas
  lie, a sword where a sword lies. Buying one brings it to where you stand,
  at full durability, the moment you unpause. If you throw it, it flies back
  to that spot. If it breaks, it goes back to where the level keeps it, as
  usual; buy it again to bring it to you. You can buy a weapon as often as
  you like, but not while you are holding it. The first time you open Moves
  in an area whose weapons you can afford, the game's "new abilities" popup
  tells you they are for sale. An area without weapons shows "None
  here". The game's own respawn does the moving, so a weapon the area never
  had can't be summoned (yet).
- **EX Moves** (experimental): with a button's EX bought, **L2 + that attack
  button** (X, Y or B; no R2) does the special as an EX. Each of a button's
  moves (Special 1, 2, ...) gets its EX separately, in order, once you own
  that move on R2; the row shows how many are EX ("EX * 2/4") and the next
  move's own input, name and video. L2 only does moves you own both ways.
  Keep L2 held for the whole input: L2 + X, X, X does what R2 + X, X, X does
  (while L2 stays held after an EX press it counts as R2, not block). It costs extra stamina (a
  quarter of the blue bar, less with Stamina upgrades), once per move;
  without enough stamina L2 + the button stays a block. L2 + a button whose
  EX you haven't bought is unchanged, and L2 + R2 + a button is left free.
  The red orbs stay the fatality meter. Each co-op player buys their own.
- **Fatalities** all work without being discovered; the game only hides
  their inputs until you perform one. A ??? row stays hidden while you browse
  (no input, no video); press A on it to buy. Buying reveals its input the same
  way performing it would, and it is saved like a discovery (it also counts
  in the stats' discovered fatalities).
- **Health** applies at once and heals you by what your max health gained.
  It stacks on the game's own health upgrades: pick those up in the world as
  usual, and the shop's steps stay on top. In co-op the shop's Health is shared,
  like the game's.
- **Stamina** (the blue bar under health) applies at once. The game caps the
  bar at 100 everywhere, so instead of a longer bar every block and special
  costs less: at Stamina +4 everything costs a third, as if the bar held 300%. The bar refills as fast as before.
  Each co-op player buys their own.
- **Save:** the shop's levels are kept in unused progress counters, so they
  are saved like any other progress. Uninstalling keeps the counters but the
  effects stop: health and stamina go back to the game's own values on the
  next area.
- **From 0.3.0:** the Energy rows that raised the meter's level and the Weapons
  store are gone. Weapons bought in 0.3.0 are not refunded and read as
  nothing bought here.

## Languages

The labels follow the game's language: English, Spanish, German, Italian or
French. No content files are replaced, so the mod installs alongside a
language pack, which gets the English labels. The labels are written over
unused placeholder text in memory. If a pack's placeholders are too short, the
shop turns itself off and the menu goes back to vanilla.

## Coming next

Combo extenders, in a menu entry that already exists. The reverse-engineering is in
`analysis/xp_shop/REPORT.md` in the project repository.

## Changelog

- **0.8.4:** EX is bought per move: each purchase makes the next of that
  button's moves EX, once you own it on R2, and the row shows that move.
  L2 never does a move you don't own on R2.
- **0.8.3:** L2 keeps counting as R2 until you let go, so EX input chains
  (X, X, X) go through instead of turning into a block between presses.
- **0.8.2:** EX moves come in tiers like the specials themselves (EX * has
  4 for Liu Kang, mirroring his fireball's); earlier EX purchases count as
  tier 1.
- **0.8.1:** EX is L2 + the attack button, without R2 (holding L2 blocks, so
  L2 + R2 + a button did nothing).
- **0.8.0:** Skill becomes **EX Moves**: hold L2 with a bought special for
  its strongest version, for extra stamina once per move.
- **0.7.2:** the "new abilities" popup announces an area's weapons, once per
  area per session, when you open Moves and can afford one; the purchase jingle plays
  for weapons too (the row stays bought until the menu opens again).
- **0.7.1:** a summoned weapon that breaks goes back to its own spot in the
  level instead of where you bought it, so it doesn't come back for free.
- **0.7.0:** Running Attacks becomes **Weapons**: summon the current area's
  weapons to where you stand (2,000 XP each time, placeholder price).

- **0.6.1:** hovering a ??? fatality no longer shows its input and video
  (0.6.0 told the menu's description and video panels the row was buyable,
  and they treat buyable as unlocked); the Fatalities category says the rows
  are for sale instead.
- **0.6.0:** buy the inputs of fatalities you haven't discovered yet
  (5,000 XP each, in the Fatalities menu).
- **0.5.3:** steeper top tiers. Stamina plays as 125 / 150 / 200 / 300%
  (+3 and +4 were 175 / 200%), and Health adds 1 / 2 / 4 / 8 steps (+3 and +4
  were 3 / 4), so Health +4 is +800 max health in solo.
- **0.5.2:** Stamina also discounts the bar's direct drain (1 every 5th frame
  while you hold something), which skips the cost table. The thicker stamina bar is gone: the HUD frame has
  a fixed window, so the extra height only showed as a second bar below it.
- **0.5.1:** fractional costs (3 x 0.67 and so on) alternate between their
  floor and ceiling instead of rounding, so they average exact.
- **0.5.0:** Health and Stamina only. The EX store is out for now (Skill is
  vanilla again) and comes back as its own update, so a problem in one part
  can't switch off the rest of the shop.
- **0.4.1:** fixes 0.4.0 turning itself off on the first purchase. The game's
  Lua has no `math.frexp`, so the purchase errored, the game kept the XP, and
  the shop stopped for the session. Health no longer touches the manager's
  health float (`+0x8C`), which tracks current health, not max.
- **0.4.0:** Health and Stamina stack on top of the game's own upgrades;
  Stamina makes blocks and specials cheaper and the bar thicker; EX costs extra
  stamina instead of meter orbs; the weapon store is parked.
