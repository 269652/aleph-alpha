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

## Wired the rest of the way (2026-09-20)

Reported live: *"blackberrys are still not wired and don't grow in forest
biome"*. The sim, the sheet, the drawing and the picking were all there.
Three seams every other ground cover goes through were not, and each of
them reads in play as "it isn't wired":

- **A building's floor did not clear one.** A bramble was absent from the
  block/unblock lists, so a house could be raised with a thicket standing
  through its floor — the one rule [building.md](building.md) states for
  every other cover.
- **A cleared thicket kept drawing.** `_resync_ground_cover_sprites` did
  not reach the brambles, so clearing one left its sprite standing: the
  same lie a grazed tuft left on screen would be.
- **Nothing freed them with the chunk.** The sims and their `Sprite2D`s
  accumulated for every wood a player ever walked through, and hung over
  ground that was no longer loaded.

### The other half did not reproduce, and was measured

On a real Harz chunk: **6 brambles on 242 forest cells** (2.5% against the
3.5% `SEED_CHANCE` asks for) and **all 6 drawn**
(`tools/probe_ferns.gd`, which reports the wood's other cover from the
same run). A render centred on one shows it correctly at the wood's edge
beside the ferns.

What makes them hard to find is not wiring. It is **sparsity** — about
one thicket per 170 tiles — and **the canopy**: a closed wood seen from
above is all crown, and this world has no canopy fade when a player walks
under it, so nothing on a forest floor is visible there at all. Both are
recorded as open questions below rather than quietly tuned away.

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
- ✅ **Cleared, re-drawn and freed like every other cover** (2026-09-20).
  A building's floor takes a thicket and its sprite goes in the same frame;
  both are freed with the chunk. See "Wired the rest of the way" above.
- ⬜ **A cleared bramble never comes back.** There is no `plant` and no
  spread: a chunk is seeded once when it is created and that is the whole
  of it, so a cell cleared by a building carries no thicket for the life of
  that chunk. Every other ground cover can re-colonise. Left as a design
  question rather than answered on the way past.
- ⬜ **Sparse, and under a canopy.** Measured at one thicket per ~170
  tiles, on a forest floor a top-down camera cannot see into. Raising the
  density is a one-line change and would not fix the second half; a canopy
  that fades when the player walks under it would fix both, for ferns,
  mushrooms and everything else down there too. Neither is done.
- ✅ **The player picks them, on the same key as everything else.**
  `EarthChunkManager.pick_blackberries_near` sweeps the tile the player
  stands on and its neighbours, takes the first ripe unpicked patch, and
  drops real `blackberry` through `WorldItemBus` — the same ground-drop path
  `harvest_grass_near` uses, so nothing about carrying, stacking or picking
  the item back up is special-cased. `Player._pick_blackberries_step` fires
  it from `_perform_attack` beside `_harvest_grass_step` and
  `_pull_wild_crop_step`: the same attack key every other harvest-shaped
  verb already uses, rather than a "pick" button of its own.

  Every refusal belongs to the bramble rather than to the swing — out of
  season, already picked this year, or no bramble there at all — so the
  player-facing verb has no rules of its own to drift out of step.

  Unlike `harvest_grass_near`, picking removes NOTHING from the sim and the
  sprite stays exactly where it is. The cane is perennial.
- ⬜ **No animal forages one.** No bird, mammal or villager calls `pick`
  yet; the player is the only forager.
