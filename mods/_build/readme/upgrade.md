# Extended Upgrades: XP Shop 0.16.2 (preview, experimental)

The XP shop spends XP in the game's own upgrade menu, on the game's own menu
entries. Nothing new is added to the menu, and everything it sells comes **on
top of** what the game gives you.

## What it does

Pause > Moves > **Basic Moves** becomes **Upgrades**, **Skill** becomes
**Fatality meter**, **Platform** becomes **Weapons**, every **Specials** row
can be bought a second time as its **EX** move, and the **Fatalities** you
haven't discovered can be bought. Skill's and Platform's own rows only
showed what you have: the techniques and platform abilities keep working,
they just aren't listed any more. **Team** becomes **Travel** (see below).
Combos are unchanged.

| Category | Row | Cost | Effect |
| --- | --- | --- | --- |
| Upgrades > Health | Health +1 to +4 | 5,000 / 10,000 / 15,000 / 20,000 XP | 1 / 2 / 4 / 8 health-upgrade steps (+100 / +200 / +400 / +800 max health in solo), above the game's own 4 |
| Upgrades > Stamina | Stamina +1 to +4 | 5,000 / 10,000 / 15,000 / 20,000 XP | everything that spends the blue bar costs less: it plays as 125 / 150 / 200 / 300% |
| Upgrades > Items | Meter refill +1 / +2 / +3 | 3,000 / 5,500 / 7,500 XP per refill | the fatality meter (the red orbs) gains 1 / 2 / 3 full levels at once |
| Fatality meter | Meter +1 to +4 | 5,000 / 10,000 / 15,000 / 20,000 XP | every fatality-meter gain is 125 / 150 / 200 / 300%, and fatality mode lasts 17 / 33 / 50 / 67% longer (a full meter lasts like 3.5 / 4 / 4.5 / 5 orbs) |
| Weapons | Shard, Short shard, Sword, Kamas, Broadsword, Hook swords, Axe | 1,500 / 1,750 / 2,000 / 2,250 / 2,500 / 2,750 / 3,000 XP per summon | the weapon appears beside you at full durability, in any area |
| Specials > X, Y or B | each move you own, again as "<move> EX", in any order | 5,000 / 10,000 / 15,000 / 20,000 / 25,000 XP (Special 1 / 2 / 3 / 4 / 5) | L2 + that move's input (no R2): the move as an EX, for extra stamina |
| Fatalities | any row still showing ??? | 5,000 XP each | reveals that fatality's input and video |

- **Buying:** pick the next row and confirm in the usual Upgrade dialog. Health,
  Stamina and Fatality meter rows are bought in order. Rows
  only unlock when you have the XP, and as with Combos the description stays
  hidden until you can buy a row.
- **Weapons** sells all seven weapon types in every area. Buying one brings
  it to where you stand, at full durability, the moment you unpause. If you
  throw it, it flies back to that spot. If it breaks, it goes back to where
  the level keeps it (a weapon the shop spawned goes back to where you bought
  it); buy it again to bring it to you. You can buy a weapon as often as you
  like, but not while you are holding it. The first time you open Moves in
  an area where weapons lie and you can afford one, the game's "new
  abilities" popup tells you they are for sale.
  **Weapons the area doesn't have (experimental):** the game's own spawn
  command (the one levels use) places it beside you. One at a time: while a
  spawn is under way the other missing types are locked. If the weapon
  doesn't appear within about five seconds of unpausing (the area has no
  room for its model), the XP comes back and that type isn't sold again in
  that area until you restart the game.
- **Meter refills** (Items): each lights that many more levels of the
  fatality meter at once, and what you had built towards the next level is
  kept as long as the meter has room for it. A refill is for sale only while
  the meter has that many levels left to light: the levels are the ones the
  story has given you (one early on, three later), and a full meter sells
  nothing. Buy as often as you like: the row reads as bought until you open
  Moves again. Nothing is sold during fatality mode (the game drains the
  meter from its own timer then). Each co-op player refills their own meter.
- **Fatality meter** (was Skill): every gain of the meter (hits, blocked
  hits) is bigger, 125 / 150 / 200 / 300% at +1 to +4, and once you enter
  fatality mode the meter drains slower, so the mode lasts longer: at +4
  three orbs last as long as five would. The orbs themselves stay the
  story's (up to three); what fatalities and team attacks cost is
  unchanged. In co-op it is shared, like Health, and helps both players.
- **EX moves** (experimental): every row in Specials is bought twice. The
  first purchase is the game's own (the move, on R2); once you own it, the
  row is for sale again as "<move> EX", with the move's own input and video.
  Every move you own is for sale as its EX right away, in any order. With
  it bought, **L2 + the move's input** (no R2) does the move as an EX, and
  L2 does only the moves whose EX you own: a chained move (Special 4 is
  X, X, X) comes out on L2 only if the moves it chains through (Special 1
  and 2) have their EX too. The ^ (throw) moves have no EX.
  Keep L2 held for the whole input: L2 + X, X, X does what R2 + X, X, X does
  (while L2 stays held after an EX press it counts as R2, not block). It costs extra stamina (a
  half of the blue bar, less with Stamina upgrades), once per move;
  without enough stamina L2 + the button stays a block. L2 + a button whose
  EX you haven't bought is unchanged, and L2 + R2 + a button is left free.
  The red orbs stay the fatality meter.
  An EX move is stronger: its hits on enemies do 5x damage, and once its
  last hit or projectile is out it recovers three times as fast. (A fireball
  that lands up to about a second and a half after the press still counts.)
  It looks the part too, with Liu Kang's own flames (the fire his moves
  put on his arms and body, for either monk): an X EX sets your arms on
  fire, a Y EX your whole body, and both keep burning for as long as you
  chain the move (L2 still held); a B EX bursts into flames with an orange
  glow on every press. Its hits set what they hit on fire for a moment.
  Each co-op player buys their own.
  **EX cancels:** during an EX move, L2 + *another* button with an EX (say
  L2 + Y into L2 + X) is held until the first move's last hit or fireball is
  out, and the second EX comes out right then: a press made early is kept, a
  tap works too, and it costs its own stamina. Pressing the *same* button
  again is the move's own chain (X, X, X) and works as before. A press that
  can't happen within about three-quarters of a second is dropped.
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
- **Travel** (was Team; every character has it, Sub-Zero and Scorpion
  too): the first row, **Save game**, opens the save statue's own save menu
  right where you are; pick a slot and save as usual, and the game goes on
  when it closes. Below it, one row per world: Tombs, Wasteland, Foundry,
  Wu Shi, Forest, Evil Monastery (with the Netherealm), the versus arenas
  and the cut Survival stages. A row shows a map, as `< Wu Shi - Map 07 (102) >`
  (the designers' name and the map's number); **D-pad left/right** shows the
  world's previous or next map, and **A** loads it, at the entrance the game's
  own doors use. A row starts at the map you are in.
  - Travel waits until a fight is over (anyone besides the players still
    up), and doesn't work in a fatality room, during a Time Rift, or in a cut
    stage you didn't travel to yourself (the Survival gauntlet). From a stage
    or versus arena Travel sent you to, you can always leave, fight or not.
    Saving works in fights, but only in story areas and never during a Time
    Rift. When either can't happen, its rows say so.
  - The cut stages are unfinished: some have no way out, and the way out of
    others crashes the game (Survival 2's door, for one). Leave them with
    Travel. Survival 5 has no camera.
  - The two team-attack rows that Team showed are gone; the attacks
    themselves are unchanged (the story unlocks them).
  - A save made away from a statue loads at the entrance of the area you
    saved in.
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

- **0.16.2:** one build with both 0.16.x test builds: Travel and the 0.16.1
  flare.

- **0.16.1:** the flames last the whole EX chain (L2 + X, X, X keeps the
  arms burning; each press of the chain flares again), not just its first
  move.

- **0.16.0:** Team becomes **Travel**: save anywhere in the story, and a row
  per world loads any of 98 maps (left and right pick it, A goes). Sub-Zero
  and Scorpion get the page too. The team-attack rows are gone.
  EX flare: an EX move starts with Liu Kang's flames on the
  player, played by the game's own effect command, and its hits burn. The
  look goes by the EX button: X flaming arms, Y the whole body aflame, B a
  fire burst with an orange glow.

- **0.15.0:** the Fatality meter upgrades also make fatality mode last
  longer: its drain runs at 6/7, 3/4, 2/3 and 3/5 speed at +1 to +4 (at +4 a
  full meter lasts like 5 orbs). The rows are now called "Meter +1" to "+4".

- **0.14.0:** Skill becomes **Fatality meter**: Faster meter +1 to +4 (5,000
  to 20,000 XP) make every meter gain 125 / 150 / 200 / 300%. Platform
  becomes **Weapons**: all seven weapon types in every area, each its own
  price (1,500 to 3,000 XP); a type the area doesn't have is spawned by the
  game's own command (experimental, refunded if it doesn't appear). Items
  keeps only the meter refills, now called "Meter refill +1/+2/+3". Skill's
  and Platform's own rows are no longer listed (what they listed still works).

- **0.13.0:** buy fatality meter fills: Weapons becomes **Items**, and the
  rows the area's weapons leave sell Fatality meter +1 / +2 / +3 (3,000 /
  5,500 / 7,500 XP, placeholder prices), filled at once and bought again and
  again, for finishing bosses where the game lets you (the hidden Survival
  stages). The "None here" row is gone: an area without weapons shows the
  three fills. The weapons popup now points to Upgrades > Items.
- **0.12.0:** EX cancels: L2 + another EX button during an EX move is no
  longer eaten (0.11.3 ended the move on any attack press and dropped the
  press, leaving Liu idle); it now comes out as the next EX the moment the
  first move's last hit or fireball is out. The same button is the chain, as
  before. The impact pause 0.11.3 brought back is gone again. EX purchases
  are kept in level slots 19-21 again: 23-26 are the game's own (any of
  them non-zero lets a co-op player start a team attack), so purchases 0.11.3
  saved there move back on the next load, together with any older EX that
  0.11.3 stopped reading. In co-op, only real hits of an EX count as EX
  damage (the other player's hits during your EX don't). L2 and R2 are read
  from the trigger bytes only, like the game reads them. The EX moves run in
  a script of their own (`upgrade_ex.lua`), so an error there can no longer
  switch off Health, Stamina, Weapons and the menu with it.
- **0.11.3:** fixes an EX that was already bought and never fired. The purchase
  flags lived in level slots 19-22, which are the game's own: buying a combo
  calls `Upgrade(player, 13 + row)` and writes 13-22, so a combo row could read
  as "all five EX bought" (the row turned unsellable and L2 did nothing). The
  flags are in slots 23-26 now, and only a byte carrying this shop's bit-7 mark
  counts as owned. **EX bought before 0.11.3 reads as nothing bought: buy it
  again.** Health, Stamina, Weapons and Fatalities are untouched.
- **0.11.0:** EX hits do 10x damage with an eight-frame impact pause. The boost
  now changes the final TakeDamage argument, not only the combat-message argument.
- **0.10.4:** EX hits do 5x damage (was 4x); the extra stamina cost doubles
  from 25 to 50 before Stamina upgrades.
- **0.10.3:** EX moves recover three times as fast (was twice).
- **0.10.2:** EX hits do 4x damage.
- **0.10.1:** EX hits do 2.5x damage (was 1.5x); the slow motion is off.
- **0.10.0:** EX power: EX hits do 1.5x damage with a moment of slow
  motion, and EX moves recover twice as fast after their last hit.
- **0.9.5:** Y and B EX work: the shop had their game slots swapped, so
  an EX bought for Y was checked against B's moves and the other way round.
- **0.9.4:** L2 really does only the moves whose EX you bought: the game
  also checks a move's tier in its move filter, which reads the levels
  directly, and that check now gets the EX answer too (before, L2 did the
  whole R2 moveset). ??? fatality rows are back as in 0.9.1 (0.9.3's green
  look showed their names).
- **0.9.1:** every move you own is for sale as its EX at once, in any order
  (0.9.0 sold them one at a time). The ^ moves are no longer sold as EX
  until their L2 input exists.
- **0.9.0:** EX moves are bought in the game's own Specials menu: each move
  row can be bought a second time as its EX, in order, instead of in a
  Skill -> EX Moves store. Skill is vanilla again. EX bought in 0.8.x carry
  over (the same counters).
- **0.8.5:** fixes one EX move unlocking all of that button's moves on L2: the
  follow-up presses of a chain (X, X) now stay limited to the moves made EX.
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
