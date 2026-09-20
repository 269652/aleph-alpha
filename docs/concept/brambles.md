# Brambles: the forest edge, and what it gives back

Asked for with the art dropped in — *"And I added blackberry.png"* — and then
directly, choosing how real it should be: *"Forageable, bearing with the
seasons"*.

The sheet is a 5×5 grid of twenty-five bramble clumps, and it draws the whole
year on its face: green fruit, reddening fruit, black fruit, and white
flowers. Art that specific is a specification. A bramble that carried the
same berries all year would be throwing most of that sheet away.

Sibling to [ferns.md](ferns.md), which gave the forest floor its bracken.
Bracken is what a wood's floor IS; a bramble is what it GIVES.

## Design pillars

1. **Bearing follows the calendar, not a private clock.** A bramble flowers
   in spring, swells its fruit through summer, ripens toward autumn and is
   **bare by winter** — exactly the phenology
   [flora.md](flora.md)'s "Fruit comes and goes with the seasons" already
   specifies for trees, and for exactly the reason recorded there: a crop
   ripening on its own unaligned clock is what put apples under snow. The
   bramble asks `SeasonCycle` what time of year it is and derives ripeness
   from that. There is no accumulator to drift.
2. **Ripeness is a number, not a flag.** The art draws green, red and black
   fruit, so the model has to be able to say "half ripe". A boolean would
   make twenty of the twenty-five drawn clumps unreachable.
3. **Only ripe fruit can be picked.** Green fruit is not food. Reaching into
   a bramble in June and coming out with a handful of blackberries is the
   kind of small lie that makes a whole world feel unserious.
4. **A picked patch stays picked until the next bearing year.** Foraging
   that refills the moment you walk away is the "permanent larder"
   [flora.md](flora.md)'s fruit section already refuses. The CANE survives —
   a bramble is not an annual — so the same patch bears again next autumn.
5. **It is a plant, on the same terms as every other.** Same per-chunk
   simulation shape as `TallGrass`, `DesertScrub`, `TundraLichen` and
   `ForestFern`: seeded deterministically from the chunk seed, blocked by
   what is built on it, reproducible across a reload. Deliberately
   duplicated from them rather than abstracted over them, per this project's
   "three similar things beats a premature abstraction" convention.

## Real-world grounding

Bramble (*Rubus fruticosus*) is a woodland-edge plant, not a deep-shade one:
it wants the light of a clearing, a ride or a wood's margin. It flowers
May–July and fruits August–September, and the fruit ripens through green and
red to black — which is why an unripe blackberry is red, and why "the red
ones are green" is a real saying. Canes are biennial but the stand is
perennial: picking a patch does not kill it, and the same bramble is there
the following year.

## Mechanism

### Where it grows

Seeded on `forest` cells from the chunk seed, at a chance well BELOW
bracken's. Bracken carpets a wood's floor; brambles are scattered through
it. The ordering is what a test pins, not the literal — the same discipline
`ForestFern`'s own flavour constants are held to.

`_is_growth_blocked_at` is the identical mask `ForestFern` takes, and for the
identical reason its doc records: a river never changes the biome array and
neither does a building already standing on a reloaded chunk, so without it
a fresh sim seeds brambles into water and through floors on every load.

### What time of year it is

`ripeness_at(year_fraction)` is a pure function of the calendar, with no
state at all. It returns 0 through winter and spring, climbs through summer,
reaches 1 in autumn, and falls back to 0 at the turn into winter. Being
pure, it is directly testable at any point of any year without stepping a
simulation to get there.

`MIN_PICKABLE_RIPENESS` is where "ripe enough to eat" sits on that curve.

### Picking

`pick(cell)` yields a count of `blackberry` when the patch is ripe and has
not already been picked this bearing year, and 0 otherwise. A picked patch
records the YEAR it was picked, so:

- picking twice in one autumn yields nothing the second time;
- the same patch bears again the next autumn, with no regrowth timer to
  tune — the calendar is the timer.

## Status

- ✅ **`BlackberryBramble`, the thicket's own sim.** Seeds on forest cells
  from the chunk seed, well below bracken's density (the ordering is pinned
  by a test, not the literal), takes the identical growth-blocked mask
  `ForestFern` does, and is cleared by anything built on it. `MAX_PATCHES`
  is derived from that density against a real 32×32 chunk, the trap
  `TallGrass.MAX_PATCHES` records paying for once.
- ✅ **Bearing is a pure function of the calendar.** `ripeness_at` takes a
  year fraction and returns 0 through winter and spring, climbing through
  summer to 1 across autumn and back to 0 at the turn into winter. No
  accumulator, so nothing can drift out of step with the season the HUD
  shows — and being pure it is testable at any point of any year without
  stepping a simulation to reach it.
- ✅ **Only ripe fruit can be picked**, and a patch picked this autumn gives
  nothing more until the next one. The CANE always survives: `pick` never
  removes the patch, so the same bramble bears again next year with no
  regrowth timer to tune. The calendar is the timer.
- ✅ **`blackberry` is a real `ItemCatalog` food**, declared beside the other
  wild fruit and stacking like them, so everything that already knows what
  to do with a cherry knows what to do with it.
- ✅ **Drawn, and wired into the world.** Every loaded chunk gets a bramble
  sim beside its fern one, handed the identical growth-blocked mask, and one
  ordinary `Sprite2D` per thicket. Deliberately NOT the fern's banded
  MultiMesh: that exists to bend a chunk's worth of blades as one mesh, and
  brambles are sparse (36 against a fern's 123) and woody — they do not
  sway. Which of the twenty-five clumps a thicket wears is hash-derived from
  its own global cell, so a wood is not one bramble stamped over and over
  and it looks the same across a reload. `blackberry.png` carries real alpha,
  so unlike `fern.png` nothing is keyed.
- ⬜ **Nothing picks them but the player would.** `pick` exists and is
  tested; no forager, bird or villager calls it yet.
