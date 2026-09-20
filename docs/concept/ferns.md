# Ferns

*Asked for directly: "I added fern sprite.. can you wire it and make it
grow in forest biome; also please add the same leaf tracing and bending
mechanism which the long grass already has".*

Grassland has long grass. Forest floor had nothing — a wooded chunk drew
its trees and then bare ground between them, because every ground-cover sim
this world has is gated to a biome that is not forest: `TallGrass` seeds on
grassland, `DesertScrub` on desert, `TundraLichen` on tundra. A fern is the
missing fourth, and it is the one plant a temperate wood is actually
carpeted in.

## Design pillars

- **The same mechanism, not a similar one.** The ask is explicit: *the same
  leaf tracing and bending mechanism which the long grass already has*. So
  a fern card is bent by `IllustratedGrassPatch`'s OWN shader code and
  subdivided by its OWN mesh constants, reached through the class rather
  than copied out of it. A second bend shader that drifted from the first
  would be two wind systems in one world, and the first thing anybody would
  notice is ferns swaying out of time with the grass beside them.
- **A fern clump is one plant, where a grass tuft is a field.** Grass draws
  `CARD_COUNT` 8 blade cards per cell because a cell of meadow IS many
  blades. Each delivered fern cell is already a whole clump with its own
  rocks, logs and mushrooms drawn in, so stacking eight of them per tile
  would read as a hedge and cost eight times the overdraw for it. Ferns
  draw fewer, larger cards.
- **Shade, not sun.** Real ferns are an understorey plant: they want the
  damp, low-light floor a closed canopy gives them. In this world the
  closest honest reading of that is the forest biome itself, which is where
  a fern seeds and the only place one spreads into.
- **A delivered sheet is keyed, not re-drawn.** The art arrives as opaque
  RGB with a checkerboard painted where transparency belongs — the same
  way three of the four grass sheets and every building yard sheet arrived.
  That is a loading problem with an answer already in this codebase, and
  the answer is reused rather than written twice.

## Real-world grounding

Bracken and its relatives are the classic temperate woodland understorey:
they thrive in the damp shade under a closed canopy, spread clonally by
rhizome rather than by seed, and colonise slowly — a bracken stand creeps
outward by tens of centimetres a year, not metres. They are also tough:
a fern frond is far slower to grow back than a grass blade once cropped,
which is why grazing animals suppress grass first and ferns last. A sim
that seeds ferns in woods, spreads them slowly into neighbouring wood, and
grows them back slowly after they are cropped is a fair miniature of that.

## Mechanism

### The sim

`ForestFern` is the fourth of this world's ground-cover simulations, and is
deliberately shaped like the three that already exist rather than sharing
code with them (see `TallGrass`'s own doc comment and this project's "three
similar things beats a premature abstraction" convention): patches seed
deterministically on **forest** cells when a chunk's simulation is created,
grow toward maturity over time, spread into adjacent forest cells on a
throttled tick, and can be grazed or blocked.

Its flavour is its own, and every ordering that says so is pinned by a test
rather than asserted in a comment:

- **Sparser than grass**, because a wood's floor is shaded and broken by
  trunks, where a meadow is wall-to-wall.
- **Slower-growing than grass**, because a frond takes a season where a
  blade takes days.
- **Slower to spread than grass**, because a fern creeps by rhizome rather
  than casting seed.

### The look, and the bend

`IllustratedFernPatch` renders a chunk's fern cells the way
`IllustratedGrassPatch` renders its grass cells, and reaches into that
class for everything about the MOTION:

- the bend shader itself (`IllustratedGrassPatch.SHADER_CODE`), so wind
  phase, walker push, the eased bend curve, the per-blade phase spread and
  the amplitude variation across a card's width are one implementation;
- the mesh subdivision (`BEND_MESH_SUBDIVIDE_WIDTH`/`_DEPTH`), so a bent
  frond has the same vertex budget to travel along that a bent blade does;
- the band maths (`band_index_for_local_y`, `band_anchor_world_y`,
  `local_row_for_world_y`), so a fern Y-sorts against the player on exactly
  the same rule a blade does, and a walker cannot read as behind the ferns
  and in front of the grass in the same step.

What is the fern's own is the SHEET and the geometry it implies: a 5x5
atlas rather than 10x10, its own card count and world size, and its own
per-card offsets.

### Growth picks the row, the seed picks the column

The same two independent axes long grass already uses: growth selects the
row (a young clump through a full one), the per-card seed selects the
column. Clamped, not wrapped — a mature fern stays mature rather than
cycling back to a shoot.

### The checkerboard

The sheet is opaque RGB with a checkerboard drawn where transparency
belongs. `SpriteSheetSlicer.checkerboard_keyed` floods it off: inward from
the cell's own edges, and outward from the checker's DARKER square anywhere
in the cell, which no part of the art shares — that second seed is what
clears checker showing through a gap in the foliage, which art encloses and
an edge flood can never reach. It is the routine
`IllustratedStructureSprite` already used for the building yard sheets,
moved to the module that owns keying so there is one of it rather than two.

## Status

- ✅ **`ForestFern`, the wood's own sim.** Seeds on forest cells, grows,
  creeps by rhizome, is cropped by `graze` and blocked by a building's
  floor through the same seam every other ground cover uses. Every flavour
  ordering against the grass it is modelled on is pinned by a test rather
  than asserted in a comment: sparser, slower-growing, slower to spread.
  `MAX_PATCHES` is derived from the seed chance against a real 32x32 chunk
  and recomputed by its own test — the trap `TallGrass.MAX_PATCHES`'
  comment records paying for once, where a cap under the density reached by
  seeding ALONE leaves planting and spreading permanently unable to
  succeed.
- ✅ **Ground nothing grows on, handed in at construction.** The same mask
  `TallGrass` takes as `is_river`, and for the same reason: a river never
  changes the biome array, and neither does a building already standing on
  a reloaded chunk, so without it a fresh sim seeds ferns into water and
  through floors on every chunk load. Optional and empty by default, the
  same optional-trailing-parameter shape that addition used.
- ✅ **`IllustratedFernPatch`, bent by the grass's own mechanism.** The
  shader, the mesh subdivision and the band maths are all reached through
  `IllustratedGrassPatch` rather than restated. Those are forwarders, and
  the tests assert the equality directly; it is trivially true by
  construction, which is the point.
- ✅ **Fewer, larger cards, on a fill-rate budget.** 3 cards at 22 world
  units against grass's 8 at 16. The budget that keeps it honest is AREA
  rather than count — every card is a translucent blended quad regardless
  of batching — and a test pins that a fern tile blends no more pixels
  than a grass tile (3 x 22² = 1452 against 8 x 16² = 2048). Root offsets
  are bounded by the TILE rather than by the card, a distinction grass does
  not have to make because its card IS a tile.
- ✅ **The checkerboard, keyed by one routine.** Moved to
  `SpriteSheetSlicer` beside `chroma_keyed`, with every threshold and every
  measurement behind it; `IllustratedStructureSprite` delegates, so nothing
  about the yard sheets changed.
- ✅ **Wired into the world.** Every loaded chunk gets a sim beside its
  grass one, handed the identical blocker mask. `step_ferns` runs on the
  world's own ecology tick beside `step_tall_grass`, sharing its refresh
  interval but not its accumulator. The live wind, the season tint and the
  walker's push all reach them, because a wood and the meadow beside it
  have to sway in one wind.
- ✅ **Rendered and measured, not just tested.** `tools/probe_ferns.gd`,
  under xvfb + Mesa software GL on the Harz chunk: 30 ferns on 242 forest
  cells with none in water (**12.4%** against the 12.0% asked for), the
  checkerboard down to **0.00%** of drawn pixels, 13 bands holding 66
  instances, and **16.0%** of the frame moving when a walker steps in —
  which is the only evidence that the bend is really live rather than
  merely wired.

### Bracken is cover

Asked for directly, choosing between a fern that is only decoration, one
that is ground cover, and one that also shelters: *"Ground cover + shelter
for wildlife"*.

This is the half that makes bracken worth simulating rather than drawing. A
prey animal crossing open forest floor is exposed; the same animal in a full
stand is not. `ForestFern.is_shelter(cell)` is the single question the
creature code asks, so nothing in the ethogram needs to know what a fern is
— only that a cell shelters or does not.

Two decisions inside that one question:

- **Only a MATURE clump shelters.** A frond that has not unrolled hides
  nothing, and tying cover to growth is what makes the understorey a layer
  that establishes over time rather than a flag set at worldgen — the same
  reason the spread step starts a new clump at `0.0` rather than at `1.0`.
- **It reads straight off the growth map**, so everything that already takes
  a fern away — `graze`, `block_cells` — takes its cover with it for free.
  A second structure tracking "which cells are cover" would be one more
  thing that could drift out of step with what is actually growing there.

`SHELTER_GROWTH` is maturity itself rather than a second number kept beside
it, for the same reason.

### Honest gaps

- **A closed wood is all crown.** Measured in the same render: the frame a
  player actually sees is almost entirely canopy, and the ferns under it
  are barely visible. The probe keeps a second frame with the trees hidden
  purely so the floor can be checked at all. That is a fact about a
  top-down camera in a forest rather than a fault in the ferns, and
  nothing here tries to work around it — but it does mean the feature
  reads best at a wood's EDGE and in its clearings, which is also where a
  player walks.
- **No seasonal sheets.** Grass has four; ferns have one. The shared
  season tint still reaches them, so a November wood is not summer-bright,
  but there is no drawn autumn frond. Stated so nobody reads the single
  sheet as an oversight.
- ~~**Nothing eats them.**~~ **Closed** (2026-09-20), asked for directly:
  *"make ferns grazeable by herbivores"*. A grazer that takes no grass from
  the cell it stands on crops the fern instead — the standing-on-it path
  [ecosystem_dynamics.md](ecosystem_dynamics.md) already describes (*"an
  animal that can see no bite but stands on living ground crops what is
  under it"*), and deliberately NOT a new `GrazerForaging` food kind, since
  those are things an animal sees and walks to and nothing walks across a
  wood to reach a fern. Mature only, the same rule grass has.

  It is also what a real grazer does: bracken is toxic to livestock and
  most leave it standing while there is grass to be had, while deer browse
  fronds mainly when the grazing is poor.

  **The `elif` that puts grass first is a rail, not a contest.** Grass is
  gated to grassland and a fern to forest, so no cell can ever carry both
  and the preference can never be observed. A test pins exactly that, after
  an earlier version of it tried to stand mature grass on a fern's own cell
  and failed at its own precondition.
- **No seed fall.** Grass sheds seed onto nearby ground (`shed_seed`);
  ferns only creep from a mature clump. That matches how bracken actually
  spreads, so it is deliberate — but it means a fern can never cross a
  gap in the wood, however narrow.
