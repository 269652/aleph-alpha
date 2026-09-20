# The village market square

*Reported live with a stand in shot, pitched in long grass well off the
paving:*

> the market stands should only be put up when an NPC stands behind them to
> sell goods ... also the stand should clear long grass around it and be
> placed on the plaza anyways

Both halves of that were one bug, and the bug was that a market stand was
never a market at all. A merchant's stand was pitched two tiles south of
that merchant's own front door, out in the meadow — and *nobody ever stood
behind one*, because `NpcMarker._resolve_location` sends every merchant to
`landmarks["stall"]`, the square's single stall. A stand a player walked
past was decoration by construction.

## Design pillars

- **A market is where the market is.** A stand is a cell OF the village
  square ([village_growth.md](village_growth.md)'s street-village
  grounding: *"a widened square at the middle carrying the well, the market
  stall and the civic building"*), not a prop beside somebody's house. The
  square already exists, is already paved, and is already where a villager's
  schedule sends them to trade.
- **A stand is furniture, not architecture.** A trestle and a board are
  carried out in the morning, stood up for as long as there is somebody
  behind them, and taken in again. An empty square at night has no stalls on
  it — which is exactly what makes a market read as a market rather than as
  scenery.
- **One trader, one stand.** Several merchants in one village are several
  villagers who each trade, not one shop — the same reason the personal
  stand existed in the first place. What changes is *where*: side by side on
  the square, the way a real market row works.
- **No second mechanism for the grass.** The square is paved, paving is a
  built surface, and every ground-cover sim in the chunk already clears and
  keeps clearing a built surface. Siting a stand on the square IS clearing
  the long grass around it.

## Real-world grounding

A medieval market is a *place* before it is a building: a widened street or
a square, held on market days, with traders' trestles set up in rows across
paving that exists precisely so the ground does not turn to mud. The stalls
themselves are demountable — that is what a "stall" was — and the square is
empty between markets. Permanent market *halls* are a later and much richer
settlement's answer; a village of five households has boards and trestles.

## Mechanism

### Where the stands are

`VillageLayout.market_stand_cells(skeleton, count)` walks **west from the
square's own stall** along the plaza's southern row, `MARKET_STAND_PITCH_
TILES` (2) apart so a shopper can walk between two stalls and two stands
never read as one long counter.

- The square's own `stall` landmark is always the **first** stand, so the
  one canonical trading spot a schedule, a quest or a dialogue can name by
  tag is a real stand somebody works, rather than a fourth thing standing
  beside three others.
- The well is skipped: it is on the square too, and a stall pitched in it
  would be a stall in the water.
- It returns **what fits**. A village with more merchants than its square
  has room for leaves the rest trading at the square's own spot — the same
  honest shortfall [village_farms.md](village_farms.md) already accepts for
  a village with more farmers than farmhouse plots.
- Pure and seedless. The square already IS a seeded function of the chunk,
  so nothing about a market needs persisting to come back identically.

`VillageRenderer._market_stand_positions` then filters those cells against
what is **really paved** (`modification_at_global` → `is_road_tile`), rather
than against the plan: a village whose square never got laid (nowhere dry
for one, see `VillageLayout.plaza_x0_for`) has no market to pitch, and a
stand on bare ground is the thing this replaced.

### The square is for the stands; the well stands beside it

Reported in play with the square in shot: *"The well should not be placed on
the plaza also the stand is too big and it's placed ontop of a house.. should
be on the plaza instead"*.

Three separate things, measured (`SIZES` against the real art pipeline, and
the plaza's own rows):

- **A prop stands ON its cell, not over the one below it.** A landmark
  sprite is centre-anchored, so half its height hangs SOUTH of the cell it
  was placed on. The stall's art is ~1.7 tiles tall and its cell is the
  plaza's southernmost row, so ~0.85 of a tile of awning lands on the row
  where the cottages front the street — which is exactly "placed ontop of a
  house". Every prop is anchored at its **foot** instead, the same rule
  `CartMarker` already follows and the same one
  `VillageRenderer._solid_body_for` already states for a prop's collision
  box ("a prop stands ON its own base").
- **A stall is narrower than the cottage it sells in front of.** That was
  the rule the last size cut was made against — *"It was 52 — 3.25 tiles on
  a 16-pixel grid, wider than the cottages it sells in front of"* — but 32
  made it exactly 2 tiles, and the smallest house in the catalog
  (`house_small`) is exactly 2 tiles wide. Equal is not narrower. The size
  is derived from `BuildingCatalog`'s own smallest house footprint and
  pinned by test, so a new, smaller cottage would make this fail loudly
  rather than quietly leaving a stall the wider of the two.
- **The well stands beside the square, not on it.** A square is an open
  place to trade in; the well was taking a cell of it, and since the well
  became solid (`landmark_is_solid`) it was taking a cell nobody could even
  walk through. It moves one column west of the plaza, on the row south of
  the street — off the paving, off the street, still at the square's edge,
  and still the first thing you see walking in. `_grounded_position` nudges
  it to the nearest free cell if a house claimed that one, as it already
  does for every other landmark.
- **And nothing fences it in.** A landmark is a NODE, not a persisted tile,
  so nothing reading `modification_at_global` can see one — and a farmstead's
  rails are laid AFTER the landmarks are grounded. Off the square's own
  paving the well was on ordinary ground, and the first village measured
  drove a rail straight through it. The shared landmarks' cells are reserved
  for the whole farm pass now, beds and rails alike: neither a crop nor a
  fence belongs in the village well.

`market_stand_cells` keeps its "skip the well" guard even though the well no
longer starts on the square: grounding can nudge it back onto the paving, and
a stall pitched in the well would still be a stall in the water.

### When a stand is up

`NpcMarker.stand_is_up(is_working, distance, reach)` — its trader is on the
clock **and** within `STAND_REACH_TILES` (one tile) of it. Both halves
matter: a merchant passing their own stand on the way home at night is not
selling from it.

The marker drives it, because the marker is the only thing that knows where
its trader is standing this frame — no per-frame group scan, no polling, one
distance check per merchant. A stand is taken in the moment it is handed
over (`market_stand`'s own setter), so a village loading at night never
flashes its whole market up for the frame before the first `_process`.

### Who trades at which

`VillageRenderer` hands merchant *i* the *i*-th stand and gives that marker
a **copy** of the settlement's landmark dictionary with `stall` pointing at
their own stand — overriding the shared dictionary in place would send every
villager in the village to one merchant's trestle.

## Status

- ✅ **Every stand is a cell of the square**, filtered against real paving.
  `test_every_market_stand_stands_on_the_village_square`,
  `test_a_market_stand_stands_on_the_villages_own_paving`.
- ✅ **A stand is up only while its trader is behind it**, and starts taken
  in. `test_npc_marker_market_stand.gd` 7/7,
  `test_a_freshly_spawned_market_stand_is_taken_in`.
- ✅ **One stand per merchant, each trading at their own.**
  `test_each_merchant_trades_at_a_stand_of_their_own`,
  `test_a_village_pitches_one_stand_per_merchant_and_no_more`.
- ✅ **A village nobody trades in has no market.**
  `test_a_village_with_no_merchant_pitches_no_market_stand` — which is the
  point of the whole change: a stand with nobody behind it should not be
  standing.
- ✅ **The long grass is gone because the square is paved**, not because a
  stand carries a clearing rule of its own. `EarthChunkManager.
  _is_built_surface` covers road tiles and `_block_ground_cover_on_cells` is
  what clears and keeps clearing them, for tall grass, flowers, scrub and
  lichen alike.
- ✅ **A stall is 2 tiles wide**, not 3.25 — reported separately ("the
  stands are way too big") and pinned by
  `test_a_stall_is_two_tiles_wide_not_wider_than_a_cottage`.

- ✅ **A trader who cannot eat still works.** Putting the stands on the
  square exposed a deadlock that the permanent, unattended stall had been
  hiding. **Measured** (`tools/probe_village_market.gd`, a real village with
  the whole settlement ticked): the stand was up for **5 of 1801 ticks** —
  not because the siting was wrong (the merchant got within 6.1px of it,
  well inside the 16px reach) but because they were HUNGRY for 1589 of those
  ticks with an empty purse, so `NpcMarker`'s hunger interrupt overrode all
  825 of their scheduled "work at the stall" ticks and sent them to a well
  with nothing on it. They never worked, never earned, and stayed hungry for
  ever.

  That is the same deadlock `npc_marker.gd` already records for a hunter
  ("went hungry about twelve seconds in ... and then never worked again for
  the remaining 227 simulated seconds"); the guards written for it cover
  only producers and villagers with a field, and a merchant, a blacksmith, a
  guard and a nurse are none of those. `NpcEconomy.can_obtain_a_meal` is the
  honest general form of the rule that comment already states — *the
  interrupt is for villagers who must BUY* — and now gates it. **Measured
  again on the same village: 0% → 30% of the day-night cycle with the stand
  up.**

  The famine chain is untouched: this village is genuinely poor (2 fish, an
  empty purse) and its merchant is still hungry 1589/1801. What changed is
  that they are hungry AT WORK, where something might yet come of it.

Honest gaps, each real:

- ✅ **The square is laid AROUND what stands in it** (2026-09-20) — reported
  a further time: *"There are still villages without plaza."* Measured
  (`tools/probe_village_supply.gd`): of the two genuine villages in a
  14-chunk sweep, one had 8 of its 48 square cells paved — exactly the
  single street row crossing it — with a farm rail and a warehouse standing
  inside the square. Two faults, each fatal alone. The paving pass
  **returned on the first cell it could not take**, so one rail cancelled
  the whole square; it steps over such a cell now. And it **skipped the
  pass whenever the civic doorstep already carried a road tile** — which
  the street crossing the square paves — so a village that lost its square
  once could never gain it back on any later visit; that short-circuit is
  gone, and the walk being idempotent means every visit now heals it.
  A floor remains, because scattered cells are stray paving rather than a
  square: `VillageLayout.plaza_is_worth_laying`, a **share** rather than a
  count so it does not change meaning if `PLAZA_WIDTH_TILES` does, pinned
  at both ends. Paving *through* a building is still forbidden — that half
  of the old rule was right and is kept.
- 🚧 **A stand is up or down, never being set up.** There is no carrying-out
  animation and no goods on the boards: the sprite appears when its trader
  arrives and vanishes when they leave. What a stand is *selling* is the
  village market's stock (`VillageMarket`), which nothing draws on the
  trestle.
- 🚧 **Stands are a single row.** `market_stand_cells` only ever walks the
  plaza's southern row, so a village with more merchants than that row holds
  runs out of stands while the square still has empty rows. A second row would
  need a rule for which side of it a trader stands on.
- 🚧 **A player cannot buy at a stand.** Trading with a village is
  `Player.sell_food_to_village` and the dialogue/market path; standing in
  front of a merchant's trestle is not yet a way in.

## The well stands on a free 2x2 (2026-09-19)

Asked for directly: *"The well should be placed on a free 2x2 place; not
over streets or plaza"*. Measured across four real villages before the
fix: in one the well stood **directly on a road cell**, in the others its
footprint took road cells beside it.

**Two rules had been disagreeing.** The well was moved off the square on
an earlier report ("The well should not be placed on the plaza"), but
shared landmarks are grounded with `allow_road` true — which explicitly
lets the search settle one straight back onto the paving. The stall and
the gate genuinely do belong on their own stonework, so this is now
per-landmark: the well alone refuses a road.

**And a cell is the wrong unit for it.** The well is the one SOLID
landmark, so the ground it takes is ground nobody can walk through, and it
is drawn wider and taller than the single cell that was being checked for
clearance. `LANDMARK_FOOTPRINT_TILES` gives it 2×2, and the grounding
search needs the whole block clear.

**Which 2×2 matters more than it looks.** A block fixed to one quadrant is
wrong for exactly the place the well belongs: it stands one row south of
the street, so a block that always ran north bit into the road, and the
search shoved the well five tiles away hunting for somewhere it fitted —
which is not "beside the square" any more. It may lie in whichever
quadrant is actually free, chosen in a fixed order (`_BLOCK_TOP_LEFT_
OFFSETS`) so that placement and reservation always name the same four
cells.

That agreement is the third part. The farm pass reserves landmark cells so
it never rails through one, but it reserved the well's ANCHOR while the
well takes four — so a fence was dutifully laid through the other three.
Both paths go through `_clear_block` now.

Pinned by `test_the_well_stands_on_a_free_2x2_clear_of_street_and_plaza`,
which asserts the contract as asked: the well stands on free ground, and
that ground is part of a free 2×2. Which quadrant is the renderer's
business; that there is one is the rule.
