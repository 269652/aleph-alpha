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

⬜ Nothing implemented yet. This doc is the spec; the entries below are
filled in as each part lands.
