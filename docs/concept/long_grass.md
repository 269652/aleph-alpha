# Long Grass

## Design pillars

1. **A patch is a small field, not one oversized tuft.** Every mature
   `TallGrass` simulation cell renders several (`CARD_COUNT`) illustrated
   blade cards from `assets/sprites/grass_blades.png`, with deterministic
   variation, their roots spread across most of the cell's own footprint
   (`card_specs_for_seed`) rather than clustered in one small sub-region --
   a dense field filling the tile, not one clump sitting somewhere on it.
2. **Depth is readable in a top-down world, at the granularity performance
   allows.** Cards render GPU-instanced (see Mechanism) rather than as
   individual nodes, so exact per-blade Y-sorting against the player isn't
   available; instead, a chunk's grass splits into horizontal bands, and
   each band Y-sorts as a unit against the player/creatures. Coarser than
   per-blade, but a walker still reads as correctly in front of or behind
   the grass around them as they move through a field.
3. **Motion is cheap, physical, and path-traced per blade.** Wind and nearby
   walkers bend blade tops on the GPU by displacing the *sampled texture UV*
   per pixel row, not by shearing the card's geometry, so each card's drawn
   blades bend along a curved path that follows their own silhouette instead
   of leaning as one rigid parallelogram. Roots never translate, and a
   walker leaves a short-lived wake. Ambient wind sway scales with the same
   live wind strength driving the water's shimmer and every other swaying
   plant (`WeatherModel.wind_strength_for` via
   `EarthChunkManager.set_wind_strength`) — calmer on a clear day, harder in
   a storm. The walker's own push is deliberately exempt from this scaling:
   parting is the walker's reaction, not the weather's.
4. **Draw-call cost must not scale with card density -- fill-rate cost
   still does.** One draw call per band, not one per card, so `CARD_COUNT`
   is never constrained by how many individual nodes the scene can afford.
   It is still constrained by overdraw: every card is a translucent,
   alpha-blended, shaded quad the GPU must rasterize and blend regardless of
   batching, and a fill-rate-limited integrated GPU measurably felt a
   12-deep field -- `CARD_COUNT` trades a little volumetric density for
   headroom there (pinned by test, see Mechanism/History).

## Mechanism

`IllustratedGrassPatch` selects a tile from the delivered 10×10 illustrated
blade atlas (about 128 pixels per source cell) by stable cell seed; each
selected card is rooted at its own deterministic sub-tile offset
(`card_specs_for_seed`). Growth scales a card uniformly without moving its
root (`instances_for_cells`, pinned by test): the mesh's local origin sits
at its bottom edge (`QuadMesh.center_offset`), so scaling never drifts a
root away from its ground position (`origin * scale == origin`, for any
scale).

**Rendering is GPU-instanced, one `MultiMeshInstance2D` draw call per
(chunk, Y-band), not one `Sprite2D` per card.** `BAND_COUNT` is now 64 (half
a tile row of a `CHUNK_SIZE=32` chunk, 8 world units tall each) -- see the
constant's own doc comment for the fix history. A band's
`MultiMeshInstance2D.position` is anchored to its own BOTTOM edge, not its
vertical center (`band_anchor_world_y`), so an entity standing anywhere
within or above a band always Y-sorts behind the whole band rather than
sometimes reading as "behind" grass its own feet have already passed --
see that function's own doc comment for the full reasoning. This replaced
an earlier one-`Sprite2D`-per-card design: at the chunk/decoration-radius
density this system actually runs at (up to several thousand simultaneous
cards), that many individually Y-sorted, alpha-blended draw calls measured
as visibly laggy, reported live as "super laggy" once bug fixes made the
system actually render at its intended density for the first time.

**Banding is per-CARD, not per-cell** (2026-08-27, following a live report
after the BAND_COUNT 8->32 fix: "y sorting works for some [tufts] but not
all... it parts and bends but y ordering is correct only for some").
`IllustratedGrassPatch.cards_for_cell` expands a `TallGrass` cell into its
own `CARD_COUNT` real, offset-adjusted per-card positions (each card's own
random offset from the cell's nominal ground position -- see
`card_specs_for_seed`); `EarthChunkManager._sync_grass_sprites` buckets
each of THOSE cards into a Y-sort band via its own real world Y
(`IllustratedGrassPatch.local_row_for_world_y` converts a card's real
world Y back into the same chunk-local-row space a cell's raw row already
lived in), not the cell's own un-offset row. `IllustratedGrassPatch.
instances_for_cards` (renamed from `instances_for_cells`) takes these
pre-expanded per-card specs directly rather than expanding a cell itself,
so a cell whose own cards land in two different bands can be split across
two separate `fill_band` calls without any card drawn twice or dropped --
one seam (`cards_for_cell`) computes a card's real position for both
banding and final placement, so the two can never drift apart. This landed
in two stages: at `BAND_COUNT=32` (one band == one full tile row == 16
world units) a card's real max offset (6.8 world units, well under half a
band's height) was mathematically incapable of crossing a band boundary --
a genuine architectural correctness improvement (a single seam that cannot
drift) but provably a no-op at that ratio, confirmed by every existing
`EarthChunkManager` grass test passing completely unmodified. Raising
`BAND_COUNT` to 64 (see the constant's own doc comment) shrank a band to 8
world units -- now smaller than a card's own 6.8-unit max offset -- so
per-card banding genuinely diverges from cell-level banding on real
production data, not just at a synthetic finer test-only ratio. Directly
demonstrated by test (`test_illustrated_grass_patch.gd`'s
`test_per_card_banding_diverges_from_cell_level_banding_at_the_real_
production_ratio`, sweeping every chunk-local row and many real cell
seeds: at least one real divergence exists, and every divergence lands in
the immediately-next band, never further -- proven directly by
`test_per_card_banding_splits_a_single_cells_cards_across_two_real_bands`,
same mechanism, real seed 7: 6 of its 8 cards, whose real offset.y is
+6.8, land in the next band over, while the other 2, whose real offset.y
is -6.8, stay in the cell's own nominal band).

The shader's `fragment()` stage computes a bend curve
`bend_curve(top_t) = pow(top_t, BEND_CURVE_EXPONENT)`, where `top_t` runs
from 0 at the root to 1 at the tip - `UV.y` directly (a shared `QuadMesh`'s
own UV is local `[0, 1]` per instance, verified empirically; this is
*unlike* a region-mapped `Sprite2D`'s UV, which is atlas-relative, the
source of an earlier bug - see History). Because the exponent is above 1,
the curve eases in: the root stays essentially pinned and displacement
concentrates near the tip, unlike a per-vertex shear (which can only ever
interpolate linearly between a quad's 4 corners). Wind phase and amplitude
both vary with `UV.x` (`blade_phase`, `blade_amplitude_scale`), so blades
drawn side by side within one card sway with different timing instead of
moving as a single rigid shape - approximating independent blades without
needing per-blade geometry. The same curve gates a radial, directionally-
away push around the player's world position, so a walker's "parting"
reaction reads as clearly stronger than ambient wind sway
(`WALKER_PUSH_UV_AMPLITUDE > WIND_UV_AMPLITUDE`, tested). `EarthChunkManager`
updates the one shared player-position uniform once per frame.

`IllustratedGrassPatch`'s ambient wind term also carries a `wind_strength`
uniform (default `1.0`, calibrated to `WeatherModel.wind_strength_for
("clear")`, itself the majority weather state — see `CLEAR_THRESHOLD`), fed
by `EarthChunkManager.set_wind_strength` from the SAME live value that
already drives the water's wind-driven shimmer (`WaterShader.
set_wind_strength`) and `WindSway`'s tree/tuft/bloom sway (see below) — one
shared wind concept, not a parallel one invented per system.
`WIND_UV_AMPLITUDE` is the BASE amplitude at that baseline; the live uniform
scales it multiplicatively, so today's tuned look is exactly reproduced on
a clear day and visibly stronger in worse weather. `WALKER_PUSH_UV_AMPLITUDE`
is deliberately NOT scaled by it — parting is the walker's own reaction to
being nearby, not a function of ambient wind.

Every card in a band shares one atlas texture and one `ShaderMaterial`, so
each instance's own atlas sub-rect (which ~125×125px cell of the 10×10
sheet) has to arrive as per-instance data, not a plain shader `uniform`.
It's packed into `MultiMesh`'s dedicated custom-data channel
(`use_custom_data`/`set_instance_custom_data`), read via the `INSTANCE_CUSTOM`
built-in *in `vertex()`* and carried to `fragment()` by a `varying` - not
`instance uniform` (a global, hardware-capped buffer shared by the whole
scene, see History) and not plain per-instance `COLOR` read directly in
`fragment()` (produces a dithered mix of neighboring instances' data under
this project's `gl_compatibility` renderer, also History).

Tall grass initially covers roughly one fifth of eligible grassland cells
(`128`-patch hard chunk cap, so this stays bounded even in an all-grass
chunk), but NOT as an independent per-cell roll -- `TallGrass.
_seed_initial_patches` thresholds `PixelNoise.smooth` (`FIELD_NOISE_SCALE`/
`FIELD_NOISE_THRESHOLD`, tuned to land near the same ~20% coverage) instead.
Reported live: "remove the percentage of overall grass blades instead make
them stick more together forming fields using perlin noise / voronoi" -- an
independent roll gave the right overall coverage but painted scattered
individual dots, since each cell's outcome was uncorrelated with its
neighbours'; smooth noise keeps neighbouring samples close together, so
thresholding it carves out contiguous blobs -- real fields a player can
walk into -- instead of salt-and-pepper. `SEED_CHANCE` (`0.20`) stays
defined at the same value and is still the reference commonality several
OTHER ecological scatter systems (`DesertScrub`, `EarthwormPatch`,
`WildCropPatch`, `TundraLichen`) pin their own rarity below, in their own
tests -- it just isn't read as a literal per-cell chance by this class
anymore. Sampled in each chunk's own local cell coordinates against its own
per-chunk seed (the same per-chunk-deterministic inputs every other roll in
this file already uses), so a field is NOT guaranteed to continue
seamlessly across a chunk boundary -- a deliberate scope cut, not asked for
and not attempted; a seamless version would need a shared noise seed
sampled in global tile coordinates instead.

## Seasonal art: growth-stage rows and a staggered per-blade turn

The single `grass_blades.png` atlas above is superseded by four sheets, one
per season (`grass_blades_spring.png`/`_summer.png`/`_autumn.png`/
`_winter.png`, same 10×10 grid and 1254×1254 delivered size) -- spring in
flower, summer as the original shipped art, autumn senescing toward orange/
red, winter frosted. Two changes follow from this, one about what a single
sheet's grid MEANS and one about having four of them at all.

**A sheet's row is now a growth stage, not a second variant axis.** Before
this, `atlas_region_for_seed`'s 100 cells were one flat, undifferentiated
pool -- a "young shoot" was just a mature clump's own art scaled down
(`instances_for_cards`' `maxf(0.3, growth)`), because no cell was actually
drawn as a shoot. The delivered sheets changed that: row 0 is a bare single
blade, row 9 a full flowering/fruiting-head clump, with a real, drawn
progression between. Reusing that means splitting the seed's old dual job
(pick a row AND a column) into two separate, independently-driven axes:
`growth` (0..1, from `TallGrass.get_growth`) selects the ROW
(`clampi(int(growth * ATLAS_ROWS), 0, ATLAS_ROWS - 1)`), and the existing
per-card seed hash keeps selecting the COLUMN -- so two cards at the same
growth still look different (variant), and one card's own look now actually
changes as it grows, rather than just shrinking and growing back. This
retires the growth-as-scale trick entirely (`instances_for_cards` always
places cards at their full, undamped size now) -- double-damping an
already-smaller-drawn sprout by ALSO shrinking it read as wrong once row 0
existed to draw instead. `atlas_region_for_seed` (seed-only) is superseded by
`atlas_region_for` (seed AND growth); the row-bleed correction
(`ROW_TOP_BLEED_PX`) is unaffected by which axis picked the row -- it is
about the sheet's own pixels, not about how a caller chose to address them.

**Which of the four sheets a card samples is a staggered, per-card decision,
not a field-wide swap -- the same idea trees use, at the granularity grass
actually has.** `TreePhenology`/`ProceduralTreeSprite` turn a canopy by
sweeping individual PIXELS across a shared `turn_progress`, baking and
caching the result per (species, season-pair, progress) combination -- cheap
because there are only ever a few hundred trees and a handful of distinct
combinations in view at once (see `docs/concept/seasons.md`). Grass has no
such headroom: several thousand simultaneous cards, recomputed from a hash
every sync rather than persisted (see Mechanism above) -- baking a unique
image per card is the wrong shape for this system entirely. So the sweep
happens per CARD instead of per pixel, and the "which side of the sweep is
this unit on" decision is pushed onto the GPU's existing per-instance data
rather than costing a second CPU image per card: each card's own atlas seed
already produces a stable pseudo-random value (`card_specs_for_seed`); a
second hash of that same identity (`turn_threshold_for_seed`) gives a stable
`[0, 1)` threshold, and a card samples the OLD season's sheet while
`SeasonTransition`'s shared, quantised `progress` is still below its own
threshold and the NEW season's sheet once progress reaches it -- so a turn
spreads across many individually-timed cards exactly the way it spreads
across many individually-timed branches on one tree, using the identical
"one shared clock, many independently-thresholded units" shape, just with
the unit resized from a pixel to a whole card.

A card's decision is a hard swap between two fully-rendered sheets, not a
cross-fade -- there is no meaningful halfway image between "row 6, spring
sheet" and "row 6, autumn sheet" the way there is between two aligned tree-
canopy pixels, so blending them would not read as a real intermediate season,
only as a double-exposure. `EarthChunkManager` realizes the split by
building up to two `MultiMeshInstance2D`s per band instead of one whenever a
turn is actually in progress (`0 < progress < 1`) -- one bound to the "from"
season's texture holding every card still below its own threshold, one bound
to "to" holding the rest -- collapsing back to the day's single MMI the
instant `progress` reaches `0` or `1` (matching every prior season, and
today's behaviour, exactly). The doubled draw call is real but brief and
bounded the same way the tree cache's rebuild cost is: `SeasonTransition`
only advances in `TURN_STEPS=6` steps, a handful of times per in-game year,
so the extra MMI exists for a small fraction of a chunk's decorated lifetime,
never per-frame.

## View-distance culling: grass only draws what the camera can see

Reported live: "optimize the grass blade rendering so it only draws what
the player currently sees +2 tiles of buffer in every direction and blades
get loaded/unloaded as the player walks to improve framerate." The
chunk-level decoration gate above (`DecorationLod.keeps_decoration`) only
ever scopes drawing to whole `CHUNK_SIZE`=32-tile chunks -- several times
what the camera can actually show (see `decoration_lod.gd`'s own doc
comment) -- so a decorating chunk drew every one of its grass cells
regardless of whether they were actually on-screen.

`DecorationLod.keeps_decoration_tile` adds a tighter, rectangular,
tile-precise cutoff layered ON TOP of (never instead of) that coarser gate:
half the camera's own visible span (`EarthChunkManager.
_visible_half_span_tiles`, rounded up) plus a `GRASS_VIEW_BUFFER_TILES=2`
buffer in every direction, independent per axis -- rectangular, matching
the camera's own rectangular view, not a circular radius (the same
philosophy the chunk-level gate's own Chebyshev-not-Euclidean check
already uses). `_sync_grass_sprites` filters each cell against it before
grouping into bands, so a band's real instance count can be smaller than
its full cell count once some cells fall outside the window.

This cutoff is re-evaluated only when `_sync_grass_sprites` actually runs
-- throttled to `GRASS_REFRESH_INTERVAL=5.0`s, or forced immediately on
crossing into a new CHUNK (see `EarthChunkManager.update`). That was fine
for the old chunk-level-only gate, but tight enough here that a player can
walk many tiles -- up to a whole `CHUNK_SIZE`=32 without ever crossing a
chunk boundary -- bringing new ground into view that stayed bare until the
next coarse trigger, then popped in as one late batch. Reported live right
after the culling landed: "the blades load way too late and the player
walks into a new area without any blades which then suddenly appear."
Fixed by tracking the tile the grass view was last resynced against
(`_grass_view_synced_tile`) and marking the resync due on ANY tile change
-- the same "mark due, picked up by the next `step_tall_grass` call"
mechanism the chunk-boundary trigger already used, just at tile instead of
chunk granularity. This also primes `sim.advance`/`shed_seed` to run early
(gated behind the same accumulator) -- harmless, not just cheap: growth is
linear in delta and spread carries its own accumulator, so more frequent
smaller steps land in exactly the same state (see the "growth in one
throttled batch" tests). Triggering per TILE rather than per frame is what
keeps the cost down: tile crossings happen at a walking pace (a few a
second), far below the 60/sec rate the original throttle exists to avoid.

## Reproduction: seed, and how a field colonises ground it never touches

`_step_spread` (above) is CONTIGUOUS growth: a mature patch only ever seeds
the four cells touching it, so a field creeps outward but can never found a
second, disconnected field somewhere else in the chunk, let alone in another
chunk entirely. Real grass reproduces both ways at once -- it tillers into
the ground right next to it, AND it sets seed that something else carries
off -- so a second mechanism sits alongside `_step_spread` rather than
replacing it, the same "local self-seeding is the default, animal dispersal
is a bonus on top" split [flora.md](flora.md) already uses for trees.

### Seed is its own entity, the same shape flowers already use

`TallGrass.shed_seed` mirrors `FlowerPatch.shed_seed`/`ground_seed_cells`/
`take_ground_seed` exactly: a mature patch periodically drops a seed onto a
nearby cell (`SEED_FALL_RADIUS`), which then sits there as its own tracked
entity, capped per chunk (`MAX_GROUND_SEEDS`), until something eats it. Two
differences from the flower version, both because grass has no bloom cycle:

- **No pollination gate.** A flower only sets seed once something has
  actually pollinated it; grass has nothing analogous (wind-pollinated
  grasses in reality, and this game already treats a mature TallGrass patch
  as reproductively active the instant it grows in -- the same "map-seeded
  grass starts mature" rule the base patches already follow). Every mature
  patch is eligible to shed, not a pollinated subset.
- **No species.** `FlowerPatch` tracks which of several species a ground
  seed is so a bird replants the right bloom. `TallGrass` has exactly one
  "species", so its ground seed carries no species field at all -- `take_
  ground_seed` returns whether a seed was taken, not a name.
- **Slower per-patch, because there are more patches shedding at once.**
  Every mature cell counts (up to `MAX_PATCHES` = 128), where a flower
  meadow's shedding population is the much smaller "past bloom and
  pollinated" subset of `MAX_FLOWERS` = 40. `SECONDS_PER_SEED_FALL` is
  tuned longer than `FlowerPatch`'s so the aggregate accumulation rate
  stays the same order of magnitude rather than flooding the ground the
  moment a chunk loads.

### Two carriers, two different mechanisms, and that difference is deliberate

Three animal-seed shapes already existed before this pass, each in its own
module: `SeedDispersal` (a grazer brushes a bloom, seed rides its coat until
it wanders off -- epizoochory), `SeedEndozoochory` (a bird swallows fallen
fruit, seed survives a real gut-passage-timed digestion, dropped once the
timer elapses -- endozoochory), and `FlowerPatch`'s own ground-seed granivory
(a sparrow eats a shed flower seed off the ground and carries it the same
gut-passage way `SeedEndozoochory` does). Grass seed dispersal reuses the
CLOSEST fit for each of its two carriers rather than inventing a fourth shape
or forcing both animals through one:

- **Birds (sparrow) eat it exactly like flower seed, because it is the same
  organ doing the same thing.** A sparrow already forages flower ground seed
  through `seed_world` (`seeds_near`/`take_seed_at`/`plant_flower_at`), the
  granivory half of [flora.md](flora.md#seed-the-other-half-of-a-flowers-year).
  Grass seed adds a second ground-food source through the SAME duck-typed
  `seed_world` port (`grass_seeds_near`/`take_grass_seed_at`/
  `plant_grass_at`) and reuses `SeedEndozoochory.carry_distance_tiles`
  unchanged for the carry -- a sparrow's crop does not care whether what it
  swallowed came from a flower head or a grass seed head, so there is no
  reason to model the digestion differently.
- **Mice do NOT get the bird treatment, on purpose.** A real scatter-hoarding
  rodent does not fly and does not digest a seed in transit -- it finds a
  seed, carries a whole one in its cheek pouch on foot for a short distance
  while it goes on about its business, and caches it, often forgetting a
  fraction of what it buried (which is, in reality, how a lot of wild seed
  dispersal by rodents actually establishes new plants). That is a
  meaningfully different mechanism from "swallow and digest over flight
  time," not just a shorter version of it, so it gets its own small module
  (`SeedCaching`) rather than reusing `SeedEndozoochory`'s carry model with
  smaller numbers: a GROUND carry distance (`SeedCaching.CARRY_MIN_TILES`/
  `CARRY_MAX_TILES`, a small fraction of a bird's or even a grazer's own
  epizoochory range) converted from tiles the same way every other carrier
  here converts a distance to a timer, gated to the mouse specifically
  (`EarthChunkManager._step_grass_seed_caching`, species == "mouse") rather
  than to the whole "Forager" diet label -- this is a real mouse behaviour,
  not a generic dietary fact that should attach to anything sharing mice's
  diet table entry.
  - **A mouse's own ordinary wander could not actually cover this range on
    its own, the identical bug `flora.md`'s bird-endozoochory section had.**
    `CreatureMarker`'s wander (`CreatureWander`) is home-tethered within a
    fairly tight radius, the SAME containment shape `AmbientFlyerMovement`
    uses for birds -- measured directly at a hard ~2.6-tile ceiling across
    30 sampled `wander_seed`s regardless of what `carry_distance_tiles`
    intended, only reaching this module's own short end (targets under
    ~2.7 of the 1-6 tile range) 11 times out of 30. Fixed the same shape
    the bird case was: `SeedCaching.carry_direction`, a seeded heading
    picked at pickup and leaned into by ordinary wander
    (`CreatureMarker._wander_step`). See `docs/progress.md` for the full
    measurement.
- **Both carriers use the SAME sink.** Whatever gets a grass seed to a new
  position -- a sparrow's digestion timer or a mouse's cache -- calls
  `EarthChunkManager.plant_grass_at`, which establishes a brand-new,
  immature `TallGrass` patch there (`TallGrass.plant`, the grass-seed
  counterpart of `FlowerPatch.plant`) if the ground is grassland and the
  chunk is under its own `MAX_PATCHES` cap. This is the actual "genuinely
  new field appears somewhere else" mechanism `_step_spread` cannot produce
  on its own: a seed carried across a chunk boundary, or merely across a
  patch of non-grassland the parent field could never creep through, can
  found a second field the local spread alone would never have reached.

### Grazing was already the counter-pressure this needed

Before any of the above existed, `EarthChunkManager._graze_by_herbivores`
(driven from the same throttled `step_tall_grass` tick as growth/spread) was
already eating a mature patch under any non-predator creature standing on
it, every refresh interval, for every loaded chunk -- horses and sheep
(role `Grazer`) included, since the check is "not a predator," not a
narrower role match. Two new spread vectors (local creep, now animal-carried
long-distance seeding) landing on top of that existing, already-live grazing
pressure is what keeps total coverage bounded rather than one-directional --
see `docs/progress.md`'s Long Grass entry for the actual measured
with-grazers-vs-without numbers.

## History (bugs found building this, in order)

Each of these was reported live, after the previous fix looked correct in
isolated testing - the common thread is that this codebase's headless test
runner uses a null renderer (validates GLSL compilation, produces no real
framebuffer), so several of these needed a real, non-headless, off-screen
`SubViewport` capture to actually see, not just reason about.

1. **Whole-card sideways slide instead of a curve; bigger bushes didn't
   bend at all.** Root cause: a region-mapped `Sprite2D`'s canvas_item
   shader `UV` is atlas-relative (a card whose seed rolled atlas row 9 of
   10 saw `UV.y` in roughly `[0.9, 1.0]` for its *entire* card), compressing
   the bend curve into a near-flat sliver per card. Fixed at the time by
   giving each card its own atlas sub-rect as `instance uniform` parameters
   and renormalizing UV against them - superseded by the MultiMesh rewrite
   below, which doesn't have atlas-relative UV to begin with (a shared
   `QuadMesh`'s UV is already local `[0,1]`).
2. **"Bushes don't part at all... don't sway anymore."** Not a direction
   bug (verified via a color-visualizing diagnostic shader: `bend ≈ 0` at a
   card's root, `≈ 1` at its tip). A rendered-pixel diff showed a dense,
   busy bush card barely *looks* different even when its sampled pixels
   genuinely shift - a small positional shift of repetitive texture still
   looks like the same texture, unlike a sparse blade where the same shift
   moves a high-contrast silhouette edge. Fixed by resizing
   `WIND_UV_AMPLITUDE`/`WALKER_PUSH_UV_AMPLITUDE` for the busier case,
   re-confirmed visually (the bush's wheat-head visibly displaces under
   push, not just diffs numerically).
3. **"Super laggy" + "should be multiple entities per tile."** Root cause:
   individual `Sprite2D` cards, once actually rendering at real density
   (up to ~4,600 simultaneous cards across a typical decoration radius),
   meant that many separate alpha-blended draw calls (Y-sorting forces
   per-node paint order, defeating batching). Fixed by the banded
   `MultiMeshInstance2D` rewrite (see Mechanism) - one draw call per
   (chunk, band) instead of one per card, which also made a higher
   `CARD_COUNT` (4 → 7) affordable for a more volumetric field.
4. **Scattered pixel noise instead of coherent card art, discovered while
   verifying the MultiMesh rewrite.** Two compounding causes, found via a
   real `SubViewport` render (not headless):
   - `instance uniform` draws from one *global* buffer shared by the whole
     scene, hardware-capped (measured: 4096 total) - a single test grid of
     576 cards already overflowed it ("Too many instances using shader
     instance variables"), silently falling back to each instance's
     *default* uniform value past the cap.
   - Switching to `MultiMesh`'s `use_colors`/per-instance `COLOR`, read
     directly in `fragment()`, rendered as a dithered/checkerboard mix of
     neighboring instances' data - even a bare-minimum shader with zero
     bend math, visualizing `COLOR.rg` alone (no texture sampling at all),
     showed the same noise instead of a solid uniform patch. This appears
     specific to this project's `gl_compatibility` (GLES3) renderer, which
     (unlike Forward+/Mobile) has no true per-instance buffer and packs
     `MultiMesh` instance data into a texture internally. Fixed by reading
     `INSTANCE_CUSTOM` in `vertex()` (not `COLOR` in `fragment()`) and
     carrying it to `fragment()` via a `varying` - confirmed clean via the
     same real-render technique.

5. **"Grass doesn't part when the player walks through it" (reported live,
   after the above fixes already looked correct in single-player).** Root
   cause: `World._process` called `EarthChunkManager.
   set_grass_walker_position` from inside the `_owns_ecosystem_simulation()`
   gate — correct for the real simulation steps beside it, but this is a
   purely cosmetic, per-client effect, not shared world state (the same
   reasoning `step_water_disturbances` right above it was already exempted
   for). In single-player the gate happens to evaluate true, so the report
   was really about multiplayer: every CONNECTED client except whichever
   peer hosts never calls this at all, so a joining client's own local grass
   never parts for them, only the host's does. Fixed by moving the call
   out of the gate, unconditional every frame for every client, matching
   `step_water_disturbances`. Investigated but REFUTED as contributing
   causes (each confirmed with a real, non-headless render, not just code
   reading): a coordinate-space mismatch between `Player.position` and the
   grass `MultiMeshInstance2D`'s `MODEL_MATRIX`-derived root (both are
   direct children of the same, un-transformed `$Entities` node — same
   space); and the uniform/distance/`wake` math itself not reaching the
   shader (a temporary diagnostic that painted any card with `wake > 0.01`
   solid magenta confirmed it fires exactly where expected — right at the
   walker's own position, correctly falling off by `walker_radius` — at the
   real, tuned constants, not just an artificially cranked one).
6. **"Swaying was really good now player doesn't influence sprite" / "now
   the barely bend" (reported across several later live sessions).** Two
   compounding causes. First, a literal `const WALKER_PUSH_UV_AMPLITUDE :=
   5.0 # TEMP DIAGNOSTIC CRANK` had shipped from an earlier debugging pass,
   self-labelled but never reverted, alongside a `COLOR = vec4(1,0,1,1)`
   magenta override gated on `wake > 0.01` — both debug scaffolding, not a
   regression in the mechanism itself. `bend_offset` at `5.0` overshoots the
   shader's own UV clamp, so the curve collapses into a static-looking
   clamped sliver instead of a visible sway — reset to the real tuned value
   and the override removed, both now caught by test so this class of bug
   fails loudly instead of shipping again. Second: a parallel editing
   session repeatedly touched this same constant concurrently across the
   same stretch, so several later "broken again" reports traced to it
   having been reverted back to `5.0` (or another stale value) between
   visual checks rather than a new bug — re-diagnosed each time by
   re-reading the file fresh. Once genuinely stable, live "still not
   enough" feedback across several more rounds climbed the tuned value
   further: 0.45 → 0.6 → 0.7 → 1.5 (the last a deliberately large jump, the
   smaller steps still having read as weak in practice).
7. **"Only one sprite per tile" / clumped in one corner, and later "super
   laggy" again once fixed (reported live, in that order).** `card_specs_
   for_seed`'s offset formula spread cards across only ±3.3×±1.4 world
   units, a small sub-region hugging the tile's own center — visually one
   clump rather than grass filling the tile. Widened to ±6.8 on both axes
   (21×17 hash buckets), `CARD_COUNT` raised 7→12 alongside it (spreading
   the same small count over a bigger area reads as *sparser*, not denser).
   Once actually rendering at the new count, a fill-rate-limited integrated
   GPU measurably felt the extra overdraw — draw-call count didn't change
   (still one per band, pillar 4), but every extra card is still a
   translucent quad the GPU rasterizes and blends. Settled at `CARD_COUNT
   = 8`, keeping the spread fix (which is what actually answered "clumped
   in one corner") while trading back some of the peak density.
8. **"The blades load way too late... walks into a new area without any
   blades which then suddenly appear" (reported live, immediately after
   view-distance culling landed).** The new tile-precise cutoff (see its
   own section above) is only re-evaluated when `_sync_grass_sprites`
   actually runs — throttled to `GRASS_REFRESH_INTERVAL`, or forced on a
   CHUNK-boundary crossing. A player can walk many tiles within one
   `CHUNK_SIZE`=32 chunk without tripping that trigger, so newly-visible
   ground stayed bare for a stretch of walking and then popped in as one
   late batch once the coarse trigger finally fired. Fixed by tracking the
   tile the grass view was last resynced against and marking the resync
   due on any tile change, extending the existing "mark due, chunk
   crossing" mechanism to tile granularity (see its own section above for
   the cost reasoning).
9. **"y sorting works for some [tufts] but not all... it parts and bends
   but y ordering is correct only for some" (reported live, after the
   BAND_COUNT 8→32 fix).** Root cause: `EarthChunkManager._sync_grass_
   sprites` bucketed a whole cell's `CARD_COUNT=8` cards into a Y-sort band
   from the cell's own raw, un-offset tile row (`band_index_for_local_y
   (cell.y, CHUNK_SIZE)`), even though each individual card carries its own
   random offset from that nominal position (up to a real, verified
   ±6.8 world units — see `card_specs_for_seed`), computed and applied only
   AFTER the cell-level band decision was already made. Fixed by making
   banding per-CARD (see "Banding is per-CARD, not per-cell" above for the
   mechanism). Verified, honest scope AT THE TIME: at `BAND_COUNT=32`/
   `CHUNK_SIZE=32`, this was provably a no-op on every existing chunk — a
   card's real offset (6.8) was mathematically incapable of crossing a
   16-world-unit band boundary from a cell center that starts 8 world units
   from either edge. The user-visible "only some tufts sort correctly"
   symptom itself was not independently reproduced or explained by this
   investigation beyond this one real, verified mechanism — see #10, which
   found and fixed the actual remaining cause the same day.
10. **Same live report as #9, still visible after the per-card fix landed
    (same day).** A second Explore investigation, on the corrected premise
    that the report was about the atlas's existing dense "bush" rows (not a
    separate round-shaped rendering system, an earlier wrong premise the
    user directly corrected: "There's no round shape it's long grass like
    the others"), found the real residual cause: even with per-card banding
    in place, a whole `BAND_COUNT=32` band (one full tile) still draws in
    front of the player for as long as they stand anywhere within it
    (`band_anchor_world_y`'s own bottom-edge anchoring, see Mechanism —
    "normal, expected concealment" by design). That grace window is barely
    perceptible on sparse, mostly-transparent blade art but reads as
    glaringly broken on the atlas's dense, near-opaque "bush" cards — the
    literal "some tufts... not others" split. Fixed by raising `BAND_COUNT`
    32→64 (halves the grace window to 8 world units), which as a direct
    side effect also finally made #9's per-card fix start doing something
    real: at the finer 8-unit band height, a card's own 6.8-unit max offset
    can now genuinely cross a boundary (see "Banding is per-CARD" above).
    New worst-case reach under the player: 8 (band_height) + 6.8 (max card
    offset) + 16 (`WORLD_SIZE`) = 30.8, an 11.2-unit margin under the
    player's real 42-unit max reach (`character_view.tscn`'s `HeadSlot`) —
    comfortable again, versus a thin 3.2 at the old ratio.
11. **"The grass now has floating artefacts above it"** — a real property of
    `assets/sprites/grass_blades.png` itself, unrelated to any rendering
    math (Y-sort, growth-scale, and the wind/walker-push shader were each
    independently ruled out with real, non-headless renders before landing
    on this). The sheet's taller "bush"/wheat-ear variants (denser rows)
    draw their own plant art past their own nominal cell's bottom edge,
    bleeding into the TOP of the next row down — measured directly against
    the real shipped sheet: growing from a few px at the row1/2 boundary up
    to 25px at row7/8, present on the large majority of non-row-0 cells.
    `IllustratedGrassPatch.atlas_region_for_seed` sliced the sheet with no
    padding, content-blind, so a recipient card's own region carried a
    fragment of the DONOR row's plant right at its own top edge — and
    because the shader flips root-at-bottom/tip-at-top, that fragment
    rendered at the card's TIP, genuinely detached from its own body by a
    real transparent gap. Only newly visible once real snow (see
    `concept/weather.md`) gave the white ground enough contrast to show it
    clearly — reproduced identically over both white and green backgrounds,
    so the bleed itself predates and is independent of any snow work.
    Fixed by inseting each row's own region from the top by its own
    MEASURED bleed depth (`ROW_TOP_BLEED_PX`, one entry per row, expressed
    as a fraction of a cell so it scales correctly for any `atlas_size`),
    rather than a single global worst-case margin that would over-crop rows
    with little or no real bleed. Pinned directly against the real shipped
    PNG (`test_atlas_region_for_seed_never_includes_the_previous_rows_
    bled_over_content`), not just the measured table by eye.

## Status

- ✅ Atlas-backed, GPU-instanced (banded `MultiMeshInstance2D`), per-blade
  curved bending, wind sway, and player wake are wired and verified with
  real (non-headless) renders at real card counts.
- ✅ Y-sort banding is per-CARD (`IllustratedGrassPatch.cards_for_cell`/
  `local_row_for_world_y`), not per-cell — see History #9. At `BAND_COUNT
  =64` (History #10) this genuinely diverges from cell-level banding on
  real production data, not just a synthetic finer test ratio. The
  player's own safety margin against a band's worst-case blade, honestly
  including each card's own real ±6.8-world-unit offset, is 11.2 world
  units — see `test_illustrated_grass_patch.gd`'s
  `test_band_height_leaves_a_real_safety_margin_under_the_players_own_
  max_reach`.
- ✅ The walker-position uniform updates every frame for every client
  (host and connected), not just whichever peer owns the ecosystem
  simulation — see History #5.
- ✅ `IllustratedGrassPatch.atlas_region_for_seed` insets past every row's
  own measured content-bleed from the row above it, so no card's region
  carries a donor fragment at its own tip — see History #11.
- ✅ Ambient wind sway (not the walker push) scales with the live
  `WeatherModel.wind_strength_for` value, the same one driving the water's
  shimmer and every other swaying plant.
- ✅ A field carries the season two ways now. The blade shader still takes
  the `SeasonalFoliage` tint the ground under it wears
  (`IllustratedGrassPatch.set_season_tint`, greenness-gated with the shared
  `GREENNESS_GAIN`) for the same-sheet colour shift `World._client_process`
  already pushed every frame off the world clock (`set_wind_strength`'s own
  pattern), pinned by `tests/unit/test_world_season_fanout.gd`. On top of
  that, which of the four delivered sheets (`grass_blades_spring/summer/
  autumn/winter.png`) a card actually samples now turns too, staggered per
  card rather than snapping the whole field at once — see "Seasonal art"
  above. `TallGrass.GROWTH_RATE` is still season-independent (only
  appearance turns, not growth speed) — see [seasons.md](seasons.md).
- ✅ Growth stage is a real drawn row, not a scaled-down copy of the mature
  art — `IllustratedGrassPatch.atlas_region_for` maps `TallGrass.get_growth`
  (0..1) to one of the sheet's 10 rows, the per-card seed keeps choosing the
  column/variant independently, and `instances_for_cards` no longer damps a
  young card's scale on top of that (see "Seasonal art" above for why
  double-damping was wrong once a real shoot row existed to draw instead).
- ⬜ Creature wake uses the same shader input but is not yet wired.
- ✅ Cards spread across most of a cell's own footprint (`card_specs_for_
  seed`, `CARD_COUNT = 8`) rather than clustering in one small sub-region —
  see History #7 for the density/overdraw tuning trail.
- ✅ Grass draws only what the camera can currently see (`DecorationLod.
  keeps_decoration_tile`, `GRASS_VIEW_BUFFER_TILES = 2`), layered on top of
  the coarser chunk-level gate — see the View-distance culling section
  above. Resyncs promptly on tile-level movement, not just a chunk crossing
  or the refresh timer — see History #8.
- ✅ Initial seeding clusters into noise-shaped fields (`PixelNoise.smooth`
  thresholded by `FIELD_NOISE_SCALE`/`FIELD_NOISE_THRESHOLD`) instead of
  scattering independently per cell — see the Mechanism section's seeding
  paragraph. Not seamless across chunk boundaries (deliberate scope cut,
  noted there).
- ✅ Seed production (`TallGrass.shed_seed`/`ground_seed_cells`/
  `take_ground_seed`) and the sink it plants into (`TallGrass.plant`), backed
  by `EarthChunkManager.grass_seeds_near`/`take_grass_seed_at`/
  `plant_grass_at` -- see "Reproduction" above. Verified with a real,
  non-headless-independent probe against real Berlin chunk data (deleted
  after use, per this project's convention -- see `docs/progress.md`'s Long
  Grass entry for the numbers).
- ✅ Bird dispersal (sparrow eats shed grass seed, carries it exactly like
  flower seed via the shared `seed_world` port and `SeedEndozoochory`'s carry
  model, plants a new patch elsewhere) -- `AmbientFlyerMarker`'s fourth
  parallel ground-forage track, mechanically proven correct in isolation
  (dedicated tests, a stub world offering ONLY grass seed). 🚧 In a real,
  mixed meadow it is a BACKUP path today, not an equal one: the four
  ground-forage searches try in a fixed order (worm, fruit, flower-seed,
  grass-seed -- unchanged, grass-seed simply appended last), so with real
  flower seed abundant nearby a sparrow commits to it first every time and
  grass-seed foraging never gets a turn -- measured in a real-world probe
  (see `docs/progress.md`): 11 seeds eaten over a real run, 0 by sparrows.
  Not fixed here (reordering priority risks the already-tested flower path
  and wasn't asked for) -- flagged as a judgment call for a future pass.
- ✅ Rodent dispersal (mouse picks up nearby shed seed, carries a short
  ground distance, caches/plants a new patch) -- its own module
  (`src/gameplay/seed_caching.gd`), a deliberately different mechanism from
  the bird's, gated to species == "mouse" specifically. In the same
  real-world probe this was the ONLY carrier that actually established a new
  patch (11 of 11 eaten seeds, 1 new patch) -- today's real-world workhorse
  of the two dispersal paths, for the priority-order reason above.
- ✅ Grazing counter-pressure -- was already live before this pass
  (`EarthChunkManager._graze_by_herbivores` already ate a mature patch under
  any non-predator creature standing on it, horses/sheep included); this
  pass confirmed it with a causally-isolated real probe (a creature pinned
  onto a real, currently-mature patch every tick): 121 real `graze()` calls,
  coverage fell 3101→3072 (−29) versus 3101→3200 (+99) with no grazer at
  all -- a strong, real effect. Caveat, also found by probing: a freely
  wandering herd's `CreatureWander.WANDER_RADIUS` (40px, ~2.5 tiles) means
  how quickly a real herd finds grass to crop depends on how close its home
  point already is to some -- worth knowing when reading "grazers keep
  growth in check" as a promise about every herd everywhere, not just one
  planted directly on grass.
