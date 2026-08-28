## Weather & disasters

[world.md](world.md) already implies weather matters ("a drought or
overhunting measurably changes where you find [boars]") without ever
defining an actual system. This formalizes it: dynamic, simulated weather
that has real mechanical teeth, not just atmosphere.

- **Dynamic weather** (rain, storms, snow, fog) is driven by the existing
  climate/season/day-night clock ([world.md](world.md)) rather than being
  an independent random layer — a tropical biome and a tundra biome should
  weather differently by construction, RDR2/BOTW-style regional variety.
  **Divergence note**: today's `weather_model.gd` is exactly the
  independent-random-layer this bullet says NOT to build (a flat
  per-region hash roll, identical odds anywhere on the planet).
  [climate_dynamics.md](climate_dynamics.md) is what actually makes this
  bullet true — real pressure/wind/water-cycle simulation, with
  `weather_model.gd`'s four-state vocabulary and gameplay hooks
  (`movement_speed_modifier`/`warmth_factor`/etc.) surviving as the
  presentation layer reading its output rather than an independent roll.
- **Occasional disaster events** — droughts, floods, wildfires, blizzards —
  are larger, rarer perturbations on top of normal weather that visibly
  stress [world.md](world.md)'s vegetation/population sim: a drought
  measurably drops carrying capacity in affected cells, a flood can
  reshape terrain temporarily, a wildfire (which can also be
  player-triggered — see below) clears vegetation and forces herbivore
  migration. For fruit/nut-bearing trees specifically, see
  [flora.md](flora.md#climate-and-water-abiotic-selection-alongside-animal-selection)
  — drought doesn't just lower density, it genetically selects for
  hardier trees, a good rain year triggers mast fruiting, and sustained
  climate trends make forests visibly migrate over time.
- **Mechanical, not just visual**, on two fronts:
  - **Survival** ([survival.md](survival.md)): exposure (cold/wet) feeds
    the same debuff-stacking model as hunger/exhaustion.
  - **Combat** ([combat.md](combat.md)): rain douses fire/oil effects,
    fog reduces line-of-sight independent of vegetation concealment, snow/
    mud could slow movement — weather becomes another environmental lever
    in the same family as knockback-into-hazards and spreadable fire.
- **Feeds [farming.md](farming.md)**: seasonal crop viability and
  disaster risk (a flood or drought threatening a farm plot) give farming
  actual stakes beyond a static grow-timer.

### Open questions

- Disaster frequency/scale — rare-and-memorable (a once-a-season regional
  event) vs. frequent-and-ambient; needs pacing design once other systems
  it stresses (farming, ecosystem) are further along.
- Do players get any warning/forecast, or is unpredictability part of the
  challenge (closer to real weather)?
- Can disasters ever be player-triggered deliberately (a Mage setting a
  controlled wildfire via [magic.md](magic.md)'s Ignite atom interacting
  with dry vegetation) as a tool, not just a threat?


## What rain costs

Rain is drawn as **geometry, not as a screen-wide effect**: one small quad per
drop in flight, animated by a vertex shader off `TIME`, all in a single
MultiMesh.

The obvious implementation -- a full-screen rect whose fragment shader decides
which pixels are streaks -- was tried first and is the wrong shape for this
game's target hardware. On an integrated GPU that one extra screen-covering
blended pass cost about 6ms, which does not sound like much until vsync turns
it into a dropped frame and halves the frame rate. Measured: 42 fps with the
rect, 57.7 without it, and the difference survived replacing the shader with a
constant, dropping the material entirely, and discarding the 99% of pixels
between streaks. It only went away when the rect got smaller.

The rule that falls out of it, and that applies to any full-screen effect
added later (fog, heat haze, snow): **a screen-space overlay costs what it
rasterises.** If the effect is sparse, draw the sparse thing.

**A second, unrelated cost hid in the water surface itself, not the falling
drops** (reported live: "it takes it from 30fps to 6fps" for rain OR snow).
`WaterShader.raindrop_ripples()` (the GPU term that makes standing water
splash while it rains, see `water_shader.gd`) samples a 3x3 grid of
neighboring cells per fragment so a splash crossing a cell boundary still
renders -- but it was doing the expensive half of each cell's work (a
second and third hash to find the drop's exact position, then the full
`exp`+`sin` ripple-packet math) *before* checking whether that cell's
splash was even in its active window right now, wasting it on every cell
that wasn't. Since `rain_ripple_lifetime` is shorter than the spawn
interval, most of the 9 cells are between splashes at any instant --
reordering the cheap bounds check ahead of the expensive part (a `continue`
mirroring `movement_ripples()`'s own early-out) cuts the wasted majority of
that work with a mathematically identical result, not a visual change.
This scales with on-screen WATER area, not falling-drop count, which is why
it hit regardless of how sparse the rain/snow overlay itself looked.

**The same shader cost was firing during snow too, for no reason.**
`world.gd` derived `raining` from the raw weather string (`"rain"` /
`"storm"`) alone, with no check for whether it was cold enough to actually
be snowing instead -- so a snowy day still drove `rain_intensity` to 1.0
and paid the full ripple cost above, even though `RainOverlay` had already
switched the falling-precipitation visual to flakes. `raining` now excludes
`snowing` explicitly.


## Snow

**It snows when it is cold, not when the calendar says winter.** Temperature
decides: a cold snap in autumn snows and a mild winter rains. That is what
makes weather feel like weather rather than a label on the season.

Snow falling is the same drop field as rain -- one mesh, one draw call -- with
the colour, speed, slant and drop SHAPE swapped. White, far slower, drifting
rather than slanting, and coming down as flecks rather than streaks; reusing
rain unchanged would give WHITE RAIN, which reads as a recolour rather than as
weather.

Shape was the property this first missed, and it is the one that most says
"rain": a streak IS motion blur, so an eleven-pixel white streak is a raindrop
however pale you paint it, and a flake drifting at `FLAKE_FALL_SPEED` (90 px/s
against rain's 620) has no blur to draw. Reported as rain still falling during
a snowstorm. The drop field is one MultiMesh built once, so the shape cannot be
swapped by swapping the mesh -- the weather has to be expressible as uniforms.
`RainOverlay.drop_length_scale` squashes the same quad down its length
(`FLAKE_LENGTH` over `STREAK_LENGTH`, derived rather than restated so the CPU
constant and the GPU value cannot drift apart), and because the quad is
anchored at its head only the tail shortens. Real sideways DRIFT -- a wobble
across the fall -- is still not built; flakes come down near-vertically.

**It accumulates and it thaws.** The ground whitens over a snowfall and clears
over a thaw, both slowly enough to watch: ground that went from bare to white
between two frames would read as a bug, and so would a thaw that did. It
whitens the GROUND rather than the whole scene -- snow lies on the land, and
tinting everything would put a wash over the trees and the player too. The
grass keeps its shape and its blades under it: it is covered, not replaced.

"Covered, not replaced" is a claim about the ART as much as about the layering,
and the first version only made it true at the deep end. A shallow band was
written FULLY OPAQUE at 45% coverage, so a dusting was 45% of the tile switched
hard to near-white and 55% punched out -- a 50/50 dither of near-white at the
finest grain the atlas can express, reported as texture corruption rather than
as snow. Two things made it true for that procedural art: a thin cover was
TRANSLUCENT so the ground tinted through it instead of being knocked out in
specks (the only way that art could tint toward the ground at all, since one
tile set is baked for every biome and so the layer has no ground colour of its
own to blend with), and the coverage roll happened in blocks of art pixels
rather than per pixel, since a hard present/absent mask rolled below the world
pixel grid is a dither, i.e. static.

**Each tile's own cover is now real illustrated art, not a procedural mask, so
those two rules are inherited from the source pixels rather than enforced by
this layer.** `SnowLayer.build_band_image` slices a real cell out of an
illustrated contact sheet (`assets/sprites/terrain/snowoverlay.png`) instead
of painting a synthetic mask -- the real art's own alpha and colour already
carry translucency at the shallow end and grain throughout, so
`BAND_ALPHA`/`BAND_COVERAGE`/`BAND_WHITENESS`/`GRAIN_BLOCK` are gone, not
merely superseded.

**The sheet itself has since been replaced a second time, and the two sheets'
own grids meant two different things.** The first illustrated sheet was a 5x5
contact sheet where all 25 cells were distinct coverage stages, so
`SnowLayer.DEPTH_BANDS` was `OVERLAY_COLUMNS * OVERLAY_ROWS`, and reading it
needed a measured, non-row-major `OVERLAY_BAND_CELLS` map (that sheet's real
coverage climbed along BOTH axes diagonally, not left-to-right-then-wrap) plus
measured `OVERLAY_ROW_BANDS`/`OVERLAY_COLUMN_BANDS` crop rectangles to dodge
real near-opaque divider lines baked into the contact sheet as a generation
artifact. The current sheet is a clean 10x10 grid with no divider artifacts at
all (confirmed by the same min-alpha sweep that found the old dividers, this
time finding nothing), and its two axes are NOT interchangeable the way the
old sheet's were: ROW is coverage/depth (mean alpha climbs substantially and
monotonically row 0 -> row 9), while COLUMN is a genuinely separate
hand/AI-illustrated shape VARIANT at roughly that same depth -- real spread
exists within a row, but it does not trend column to column the way rows do,
it is shape variety rather than a second gradient. `SnowLayer.DEPTH_BANDS` is
therefore `OVERLAY_ROWS` alone (10), not the product of both axes -- a real,
deliberate drop from 25 depth bands to 10, since a variant is a different
PICTURE of the same depth rung rather than a finer one. `OVERLAY_BAND_CELLS`,
`OVERLAY_ROW_BANDS`, and `OVERLAY_COLUMN_BANDS` are gone along with it: the
new sheet's cells are an exact grid, so `_cropped_cell` just partitions the
sheet by column and row directly. (Corrected in the seventh follow-up below:
"already-square 125.4x125.4" described the sheet AT THE TIME this paragraph
was written; the sheet has since been replaced again and its cells are not
square.)

**The ten-way coarsening trades DEPTH granularity for real per-tile VARIETY,
which the coarsening does not cost.** `SnowLayer.variant_for(global_x,
global_y)` picks which of the ten shapes a given tile draws, independently of
which depth band it is in, so two neighbouring tiles at the same coverage no
longer always show the identical blob -- something the 25-single-picture-per-
band sheet could never do regardless of its finer depth ladder. Deliberately
NOT built like `onset_offset_for`'s smooth drift field: onset has to be
low-frequency because it feeds a THRESHOLD decision (two neighbours on
opposite sides of a boundary is the checkerboard bug, see below), while
variant drives no threshold at all -- it is a cosmetic shape choice at a fixed
depth, so neighbouring tiles SHOULD often disagree, which is the entire point
of having ten pictures. It samples `PixelNoise.range_index` (built on `unit`,
the genuinely per-cell-independent form the codebase already has, as opposed
to `smooth`'s deliberately correlated one) rather than reusing onset's
machinery. `EarthChunkManager._paint_snow_tile` caches each tile's own variant
the same way and for the same reason it already caches onset
(`_snow_variant_by_tile`, alongside `_snow_onset_by_tile`), and paints it into
the second half of the tile's atlas coordinate: `set_cell(tile, 0,
Vector2i(band, variant))`, against a real 2D `DEPTH_BANDS * OVERLAY_COLUMNS`
(100-tile) atlas from `build_tile_set` rather than the old 1D strip.

The two onset noise layers below and the new variant axis solve genuinely
different problems and both stay: onset decides WHICH DEPTH BAND a tile shows
relative to the field's shared coverage number (so a snowfall spreads tile by
tile rather than everyone crossing together), while variant decides WHICH
PICTURE draws that band once chosen -- turning off either one reintroduces a
different flatness (a synchronized field, or every tile at a given depth
looking identical), not the same bug twice.

**It fills in tile by tile, not the whole field at once.** A single lying-snow
DEPTH still drives the whole snowfall -- one clock, one number, exactly as
above -- but each tile answers that number differently: real snow does not
accumulate evenly, it drifts and shelters unevenly (a hollow, a lee side, the
shade under a tree line all hold snow at a different rate than open, exposed
ground), so different tiles cross into a deeper band at different points along
the SAME snowfall. The whole field still starts bare and still ends fully
covered together -- only the middle of the fall differs tile to tile -- so a
snowfall reads as spreading, patchy cover arriving across the ground rather
than the entire loaded field flashing to the next shade of white in lockstep.
Reported directly: "snow still covers a percentage of a whole chunk instantly
instead of gradually filling individual tiles."

**Walking displaces it.** Footprints are the same shape as the dirt paths worn
into grass (see `PathScarring`): walking marks a tile and the world slowly
undoes it. What undoes it is the difference -- a path grows back on its own,
while footprints sit there until it snows again. So a trail across a field
lasts through a clear cold day and is gone after a fall.

**A field fills in tile by tile -- it does not flip all at once.** Coverage
(`Snowfall.accumulate`) is one aggregate number, 0 bare to 1 fully covered,
because that is the right shape for the pure model. But every PAINTED tile
used to read that exact same number: the instant it ticked past a depth-band
boundary, the whole loaded chunk snapped to the new band together, which reads
as "the ground turned white in one frame" rather than as a snowfall settling
(reported: "snow covers a whole chunk instantly instead of spreading
progressively"). Each tile now carries its own small lead or lag on the shared
depth, sampled from a LOW-FREQUENCY DRIFT FIELD spanning
`SnowLayer.ONSET_DRIFT_TILES` tiles per lift (`SnowLayer.onset_offset_for`,
keyed off the tile's GLOBAL coordinates so the pattern doesn't repeat or seam
at a chunk boundary) -- the same seeded-jitter idea `TallGrass`/`FlowerPatch`
already use so a uniform process doesn't read as synchronized (this project
has hit that "same value everywhere" clustering bug five times before; see
`PixelNoise`'s own doc comment), applied to WHEN a tile catches on rather than
WHERE something is placed. A partial snowfall now paints a genuine MIX of bare
and covered land -- some tiles catch the first flakes, others hold out a little
longer -- rather than the whole chunk changing together.

**Why a drift FIELD rather than a per-tile roll.** The lead/lag was first
rolled per tile as white noise, which is what those two placement systems use
-- and it was the wrong tool here, because a tile is the smallest thing a snow
band can speak about. Measured over an 800x80 tile sweep, two EDGE-ADJACENT
tiles could land 0.358 apart while one whole depth band is only 0.25, so
neighbours routinely sat a band apart and sometimes two, and the field rendered
as a checkerboard of bare / dusted / covered SQUARES with a razor edge on the
tile grid. Noise driving a per-tile decision has to be much COARSER than a
tile, not finer. Real snow drifts and shelters in patches many metres across, a
low-frequency shape by nature, so `onset_offset_for` samples `PixelNoise`'s
smooth form instead: `MAX_NEIGHBOUR_ONSET_STEP` holds two edge-adjacent tiles'
onsets close together (re-measured and re-pinned as the field itself changed --
see the fine-grain paragraph below for the current, real number), so a band
boundary takes several tiles to cross and the snow LINE meanders through the
field. The field still spans the full variance -- a test pins that too, so
nobody "fixes" a neighbour-step failure by flattening the drift to a constant
and putting the whole chunk back on one shared threshold.

**One drift layer alone reads as large flat PLATEAUS, not texture.** Reported
live after `DEPTH_BANDS` went 4 -> 25: *"it's not using accumulation per tile
and sth like perlin noise or so instead whole areas increment to next sprite
without variations"*. This is not the checkerboard bug above (neighbours
differing too much) -- closer to the opposite. `onset_offset_for`'s single
broad layer is exactly as low-frequency as the checkerboard fix demands (a
lift every `ONSET_DRIFT_TILES` = 12 tiles), which means a realistic ~20-30
tile on-screen view often sits inside one near-flat lobe of that field, where
almost every tile rounds to the same band. Measured directly: sweeping every
24x24 window across a real 400x120-tile swath, the worst window found held
only 3 distinct depth bands at a mid snowfall (depth 0.5) -- a whole
neighbourhood stepping together. A second, much shorter-period smooth layer
(`ONSET_FINE_DRIFT_TILES` = 2 tiles) now adds real tile-to-tile texture inside
whatever broad-scale patch the first layer already chose, carrying a
deliberately small slice of the shared `ONSET_VARIANCE` budget
(`ONSET_FINE_VARIANCE`, with the broad share derived as the remainder so the
two can't drift out of sync) so the broad layer still governs which general
area -- a hollow, a lee side, a tree line's shade -- catches on first. Re-
measured on the combined field: that same worst-case window rose from 3 to 5
distinct bands, while the worst neighbour step rose from a measured 0.0357 to
0.0612 -- roughly 1.53 of the new fine bands (0.04 each), nowhere near the
old checkerboard's whole-range jump -- so `MAX_NEIGHBOUR_ONSET_STEP` is
re-pinned to 0.07, a real if narrower-than-first-estimated margin over that
fresh measurement. (An initially-reported 0.0581 for this figure did not
reproduce on independent re-verification the same day; 0.0612 is the real,
deterministically-reproducible number, confirmed three times over.)

**Re-checked, not re-tuned, when `DEPTH_BANDS` dropped 25 -> 10.**
`onset_offset_for` reads neither `DEPTH_BANDS` nor either `OVERLAY_*`
constant, so the field this whole section describes is byte-for-byte
unchanged by the sheet replacement above -- re-running the exact same
neighbour-step sweep still measures the identical 0.0612 worst case, and
`MAX_NEIGHBOUR_ONSET_STEP` stays `0.07`. What DID change is how many bands
that unchanged field's spread now falls across: a 24x24 window's worst-case
distinct-band count dropped from 5 to 2 (same sweep, same swath, same origin
`(-42, -48)`), simply because there are fewer bands total to land in, not
because the onset field lost any texture. The local-window test's own
threshold moved from "more than 3 distinct bands" to "more than 1" for
exactly that reason -- see `SnowLayer`'s own doc comments on
`MAX_NEIGHBOUR_ONSET_STEP` and the test's own comment in
`test_snow_layer.gd` for the full reasoning.

**The repaint itself has to happen often enough to show that mix changing.**
Onset variance alone was not sufficient: the whole-field repaint that
actually pushes new pixels to the tile layer only fired when the tracked
depth crossed one of the four texture-band boundaries, so within a single
band's depth range -- comfortably a third of a whole snowfall -- nothing
repainted at all no matter how far coverage kept climbing underneath. A real
probe caught it: coverage sat flat at the same percentage from depth 0.02
through 0.25, then jumped straight to full at 0.5 -- the instant-reveal bug
again, just relocated to a coarser timescale. A first fix gated the repaint on
`SNOW_REPAINT_DEPTH_STEP` (a smaller depth-moved-by-0.05 threshold) instead of
only a band crossing, which closed that particular gap but kept the same
shape underneath: still one aggregate gate deciding when to unconditionally
repaint EVERY loaded tile.

**That shape has its own failure mode: a batch pop.** Even with the tighter
gate, the trigger still only fired roughly once every 18 real seconds
(`SNOW_REPAINT_DEPTH_STEP` 0.05 of depth against `Snowfall.SECONDS_TO_COVER`
360s), and between two such firings NOTHING repainted at all -- not because
the math was wrong (individual tiles' own onset-adjusted bands kept crossing
their thresholds continuously the whole time, per the onset section above),
but because nothing was WATCHING for it. Then, the instant the gate did fire,
every tile that had crossed sometime in that whole 18-second window all
repainted TOGETHER, in the same frame. Reported a third time, in the user's
own words: *"doesn't correctly fall and accumulate gradually on individual
tiles instead after a time a whole chunk get's every tile covered"* -- which
is exactly this: long silence, then a visible batch of tiles change at once.
An investigation this round confirmed the underlying per-tile spread math was
never the problem (a real probe drove `step_snow` in small real-world-age
steps and found multiple bands genuinely present in the field throughout) --
the gate's own cadence was.

The fix restores the shape a since-lost architecture
(`_snow_painted_band_by_tile`/`_sweep_chunk`, dropped in a hand-resolved merge
conflict without anyone noticing) already had: track every loaded tile's own
last-PAINTED band in `EarthChunkManager._snow_painted_band_by_tile`, and on a
real, tested cadence (`SNOW_SWEEP_INTERVAL_SECONDS`, see below) SWEEP every
loaded tile, calling `_paint_snow_tile` for each -- but `_paint_snow_tile`
itself now only actually touches the `TileMapLayer` (a real
`set_cell`/`erase_cell`) for a tile whose freshly-computed band differs from
what is tracked, not unconditionally for every tile the sweep visits. The
sweep can therefore run far more often than the old whole-field repaint did,
because most of its cost is no longer "thousands of set_cell calls" -- it is
"thousands of cheap comparisons, a few dozen real paints."

**Even that cheap comparison was not cheap enough at first.** Measured live
against the real field a `LOAD_RADIUS=2` chunk radius loads (~22,700 land
tiles): recomputing each tile's onset offset (a `PixelNoise.smooth` call --
several hashed lookups) on every single sweep cost ~200ms per pass on its own,
before touching the tile layer at all -- far too expensive to run on any
cadence tighter than the old ~18s gate, which would have defeated the whole
point. But onset is a PURE function of a tile's global coordinates: it never
changes for that tile's entire loaded lifetime. Caching it once, the first
time a tile is ever painted (`EarthChunkManager._snow_onset_by_tile`), cut
the same sweep to ~40-50ms -- about 5x cheaper, and the difference between a
tight cadence being affordable or not. The cache is dropped per-tile when its
chunk unloads, so it does not grow without bound as a player roams.

With that cache, `EarthChunkManager.SNOW_SWEEP_INTERVAL_SECONDS` (2.0 real
seconds) throttles how often the sweep itself runs from `step_snow`'s
per-frame call -- still a real, bounded cost (an O(loaded tiles) scan, just a
cheap one now), not something to pay unconditionally every frame. 2.0s keeps
the new mechanism's average CPU cost roughly the SAME order as the old one's
(~45ms every 2s vs. the old ~426ms every 18s -- an unconditional repaint of
every tile, measured -- is ~2.1% vs. ~2.4% of wall-clock time) while making it
9x more frequent, so a real crossing shows up within ~2 seconds of happening
rather than sitting invisible for up to 18 and then jumping. `set_snow_depth`
(a rare, deliberate call -- `/weather`, or code setting depth outright) still
sweeps immediately and unthrottled, since it is not a per-frame call and
should reflect its own change right away.

**Seventh follow-up: the slicer itself had real artefacts, separate from
everything above, and a second complaint about accumulation "not staying
coherent" turned out to be the same bug wearing a different name.** The sheet
had been replaced a third time by now -- 1536x1024, 153.6x102.4 cells, NOT
the square 125.4x125.4 the sixth follow-up above measured -- and that
asymmetry is not incidental: a cell 102px tall is a tight fit for a "puff"
shape drawn to roughly fill it, tight enough that some of the largest,
highest-row shapes press across their own ROW boundary at real, sometimes
near-opaque alpha, something a 125px-square cell had much more room to avoid.
`_cropped_cell`'s partition math was confirmed exact (gap-free, overlap-free)
-- the bug was always the ILLUSTRATED CONTENT pressing past its own nominal
cell, in two distinct ways. First, a near-invisible one: a real, consistent
colour persists under alpha as low as 0.004-0.02 at ordinary cell boundaries
(measured: ~0.57/0.65/0.78 RGB at row 6's column 2/3 crossing), which
`Image.resize`'s straight-alpha Lanczos blends into its kernel at FULL
weight regardless of how invisible that colour actually is -- a halo/fringe
around real edges after the shrink, 61,204 such pixels found across all 100
built tiles in one sheet-wide scan. Second, a substantial one: `band=5,
variant=2` rendered a disconnected ghost blob at the very top of its own
crop (a fragment of the row-4 cell above, bleeding down); `band=9,variant=7`
rendered a flat, un-tapered high-alpha plateau starting immediately at its
own top edge, because that variant's real content presses UP into row 8 and
a fixed-grid crop cannot recover pixels that live on the far side of a
boundary.

Fixed with two techniques together -- confirmed neither alone was enough,
by rendering the same two known-bad tiles through each in isolation.
`SnowLayer.build_band_image` now premultiplies alpha before the Lanczos
resize and un-premultiplies after, so near-invisible colour contributes to
the resize kernel in proportion to how invisible it actually is rather than
at full weight; guarded (`_UNPREMULTIPLY_MIN_ALPHA = 0.02`) against dividing
by an alpha too close to zero, which measurably amplifies ordinary 8-bit
quantization noise into an arbitrary colour rather than fixing anything.
Premultiply alone left both known-bad tiles visually unchanged, since their
defects are near-OPAQUE overflow, not the near-invisible colour premultiply
targets. The crop's own outer border is now also feathered toward
transparent before that resize (`_feather_crop_edges`, `CROP_EDGE_
FEATHER_PX = 8`, a smoothstep rather than linear ramp specifically because a
linear ramp's kinked derivative measurably rang under the Lanczos resize
that follows it) -- this discounts whatever of a neighbour's overflow lands
within a cell's own nominal boundary, and turns a hard, un-tapered clip like
`band=9,variant=7`'s into a genuine, if synthetic, taper instead. The width
was swept from both sides: wide enough to matter, narrow enough that row 9
-- "one large puff nearly filling the cell," whose real content already
touches its own nominal edge on every one of its ten variants (measured 0px
margin on at least one side, all ten) -- keeps real, if modest, margin over
`FULL_COVER_MIN_MEAN_ALPHA` (worst variant measures 0.339 against the 0.32
floor) rather than being amputated by the same fix meant to help it. Both
known-bad tiles' own top-row mean alpha dropped roughly 87% (0.449 -> 0.028,
0.915 -> 0.059).

The SEPARATE "keep the initial variant so accumulation stays coherent"
complaint was investigated on its own terms, not assumed fixed by the above.
`EarthChunkManager._snow_variant_by_tile` already looked, by its own
existing design, like it should hold one tile's variant fixed for its whole
loaded lifetime -- has()-then-compute-once against a pure function of the
tile's own global coordinates, erased only on unload and recomputed
identically if reloaded. A new test drives one real manager through several
depths spanning multiple bands and confirms directly that a tile's own
painted variant never moves while its band does -- green on the first run,
no production change needed. The user-visible complaint was therefore very
likely the slicer bug above wearing a different name: a contaminated crop at
one band reading as a different SHAPE from the crop at the next band, even
though the underlying variant index never moved -- confirmed by re-rendering
the same variant across several bands after the slicer fix landed, which now
reads as one blob thickening rather than a sequence of unrelated pictures.

Two pre-existing test failures were found while establishing this pass's
baseline and are confirmed unrelated to, and unmoved by, either fix above:
row 9 measures LESS white on average than row 8 in the current sheet's real
content (`test_deeper_snow_is_whiter`), and row 0's variant 7 sits fractionally
over `DUSTING_MAX_MEAN_ALPHA` (0.0659 against 0.06). Both are about the
sheet's real per-row content, not about cross-cell bleed or slicing, and both
measured identically before and after this pass's fix -- left open rather
than silently tuned away, since fixing either is a different piece of work
(re-checking the sheet's actual row order, or re-deriving the dusting
ceiling against real new-sheet content) than the slicer this follow-up was
about.

### Status

- ✅ Snow instead of rain below freezing, falling white, slow, and as FLECKS
  rather than rain's streaks — `RainOverlay.FLAKE_LENGTH`/`drop_length_scale`
  plus the `drop_length_scale` shader uniform, tested; wired in `set_snowing`.
- ✅ Accumulation and thaw, whitening the ground
- ✅ Footprint displacement and snow filling tracks back in
- ✅ Tracks rendered: snow is a per-tile overlay, so footprints carve it
- ✅ A dusting reads as frost, not as white static — real illustrated coverage
  art (`assets/sprites/terrain/snowoverlay.png`, sliced by
  `SnowLayer.build_band_image`) whose own translucency and grain replace the
  old procedural mask entirely, pinned against the real sheet's measured mean
  alpha (`DUSTING_MAX_MEAN_ALPHA`/`FULL_COVER_MIN_MEAN_ALPHA`).
- ✅ A tile's own transition fades through real illustrated depth steps
  instead of hard-cutting between hand-picked procedural bands —
  `SnowLayer.DEPTH_BANDS` is the illustrated sheet's own real ROW count
  (`OVERLAY_ROWS`, currently 10, after a second asset replacement dropped it
  from an interim 25 — see the narrative above for why row-count, not
  row*column, is the right number for the current sheet's two independent
  axes); tested.
- ✅ Real per-tile shape VARIETY at a fixed depth, not just one picture per
  band — `SnowLayer.variant_for` picks one of `OVERLAY_COLUMNS` (10)
  illustrated shapes per tile, seeded off its global coordinates and
  deliberately NOT smoothed (unlike onset, a shape choice has no coherence
  requirement — see `variant_for`'s own doc comment), tested for bounds,
  determinism, and real per-tile disagreement; wired in
  `EarthChunkManager._paint_snow_tile` via `Vector2i(band, variant)` atlas
  coordinates and cached per tile (`_snow_variant_by_tile`) the same way
  onset already is.
- ✅ Per-tile onset variance, so a field fills in as a visible spread rather
  than snapping everywhere at once — `SnowLayer.ONSET_VARIANCE`/
  `onset_offset_for`/`band_for`, tested; wired in
  `EarthChunkManager._paint_snow_tile`.
- ✅ That onset is a low-frequency DRIFT field, not per-tile static, so the
  snow line meanders instead of rendering as hard-edged tile squares —
  `SnowLayer.ONSET_DRIFT_TILES`/`MAX_NEIGHBOUR_ONSET_STEP`, tested from both
  sides (coarse enough, and not flattened to a constant).
- ✅ A second, fine-grained drift layer adds real per-tile texture within a
  realistic local view, so a snowfall doesn't read as a few large uniform
  plateaus stepping band by band — `SnowLayer.ONSET_FINE_DRIFT_TILES`/
  `ONSET_FINE_VARIANCE`, tested (`test_a_local_window_shows_real_per_tile_
  variation_not_a_uniform_plateau`); `MAX_NEIGHBOUR_ONSET_STEP` re-measured
  and re-pinned for the combined field.
- ⬜ Sideways DRIFT on falling flakes — a wobble across the fall. Flakes
  currently come down near-vertically (`Snowfall.FLAKE_SLANT` 0.05). Needs its
  own uniform and its own tested constant.
- ⬜ Water freezing over. Snow deliberately never lies on water
  (`EarthChunkManager._paint_snow_tile` erases the cell over `"ocean"`):
  ice is a separate mechanic that does not exist yet, so this is a boundary
  rather than an omission.
- ✅ The repaint that reveals that spread trickles in continuously rather
  than batching into periodic pops — a per-tile diff sweep
  (`EarthChunkManager._snow_painted_band_by_tile`/`_sweep_snow_field`) only
  touches the TileMapLayer for a tile whose band actually changed, run on a
  real, measured cadence (`SNOW_SWEEP_INTERVAL_SECONDS`, 2.0s, backed by a
  per-tile onset cache — `_snow_onset_by_tile` — that keeps a full sweep
  affordable); tested (`test_step_snow_driven_coverage_changes_trickle_in_
  rather_than_batching_every_18_seconds`), wired in `step_snow`.
- ✅ A chunk streamed in mid-snowfall shows its own correct snow immediately
  (`_load_chunk` calls `_paint_snow_chunk` for just that chunk) rather than
  staying bare until the next field-wide repaint happens to reach it; an
  unloaded chunk's painted snow cells are erased along with the rest of its
  overlays (`_unload_chunk`), not left floating over nothing.
- ✅ A built tile's own crop no longer reproduces a neighbouring cell's bleed
  as a visible artefact — `SnowLayer.build_band_image` premultiplies alpha
  around its Lanczos resize (`_premultiply_alpha`/`_unpremultiply_alpha`) and
  feathers the crop's own outer border toward transparent first
  (`_feather_crop_edges`, `CROP_EDGE_FEATHER_PX`); tested against a
  sheet-wide near-invisible-colour guard and the two specific worst tiles
  found by direct render, plus a guard that the fix did not amputate row 9's
  own real coverage. The separately-reported "keep the initial variant so
  accumulation stays coherent" complaint was confirmed, by a dedicated test,
  to have never been a caching bug — `_snow_variant_by_tile` already held a
  tile's variant fixed for its loaded lifetime by construction; the visible
  symptom was this same slicer bug read as a shape change. See the seventh
  follow-up in `docs/progress.md` for the full measurement trail.

## Pinning the weather (`/weather`)

**The override lives on the model, not at the call sites.** Weather is a
deterministic roll on the day and the region, which is right for the world and
useless for inspection: to watch snow settle you would otherwise wait for a
rainy day to come round in winter. Every reader — the rain overlay, soil
moisture, wind strength, snowfall — reaches weather through the same call, so
pinning it there means they all agree. An override that only reached the
overlay would give a downpour that never wet the ground.

**There is no "snow" to ask for.** Snow is what rain IS when it falls cold, so
the states stay clear/cloudy/rain/storm and winter does the rest. `/weather
rain` with `/season winter` is how you get a snowfall on demand.

## Snow keeps the world's clock

**Lying snow advances on world time, not on frame time.** It used to melt
against the real frame delta while the season ran on the world clock, which is
two clocks that have to agree and were never made to. Jumping to summer leaps
the world clock up to a year forward; the snow saw one frame — about sixteen
milliseconds — and went on lying there in the sunshine. The same mismatch left
a fast-forwarded winter thawing at real-time speed while the seasons flew past.

The fix is structural rather than numeric: the snow step takes no delta at all
and reads the world clock itself, so there is one clock rather than two kept in
step by hand. The thaw and cover durations are unchanged — measured in weather
spells, they were already right for ordinary play, where a season is long
enough to watch a thaw happen properly.
