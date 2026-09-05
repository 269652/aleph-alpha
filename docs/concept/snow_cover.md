# Snow Cover

How lying snow is *drawn*. The physics of when it falls, how fast it piles
up and how fast it thaws belong to [weather.md](weather.md#snow) and
`Snowfall`; how walking displaces it belongs to `SnowTrail`. This document
covers only the rendering: what the player actually sees on the ground when
`Snowfall.accumulate` says the field is 37% covered.

## Design pillars

1. **Snow is a continuum, not a ladder.** Real snow does not arrive in
   discrete steps. Any mechanism whose smallest expressible unit is
   perceptible — a tile, a band — will eventually be reported as popping,
   snapping or checkerboarding, because it genuinely does. This layer has
   been reported for exactly that six times in a row (see
   [progress.md](../progress.md)'s snow entries). The fix is not a finer
   ladder; it is to stop having rungs the player can see.

2. **The ground is covered, not replaced.** Snow lies *over* grass, stones
   and flowers, and a thin cover lets them through. The layer draws above
   terrain and below anything standing on it.

3. **A trail through a field must be expressible.** Whatever the mechanism,
   it has to be able to say "this patch is trodden and that one is not" —
   the original reason snow stopped being a whole-world tint.

4. **The cost of drawing snow must not scale with how much ground is
   loaded.** Snow covers everything in view by definition, so any
   per-ground-unit CPU work is per-*everything* work. It belongs on the GPU.

5. **The art is illustrated, and must survive being drawn.** The snow
   shapes are hand/AI-illustrated puffs. They must not be stretched,
   aliased, or laid down on a grid frequency the eye can lock onto.

## Real-world grounding

Snow does not accumulate evenly. It drifts and shelters at the scale of
metres to tens of metres — a hollow, a lee slope, the shade of a tree line
catch and hold it while exposed ground beside them stays bare far longer.
So the field deciding *which ground catches first* is genuinely
low-frequency, and two points a metre apart are nearly identical while two
points twenty metres apart can differ completely.

Within any such patch, though, cover is built out of discrete lumps —
individual drifts and clumps at the scale of tens of centimetres. That
two-scale structure (broad drift field, discrete lumps within it) is what
the mechanism below reproduces: the drift field says how much snow this
ground has caught, and the lumps are real illustrated stamps.

## The art: leveled snow sheets

`assets/sprites/terrain/snow_<level>.png`, one sheet per coverage level,
each a **5 column x 2 row grid of ten shape variants** at that level.
Three levels exist today, and their file names carry the level:

| Sheet | Size | Mean alpha | What it draws |
|---|---|---|---|
| `snow_1.png` | 1983x793 | 0.058 | A sparse dusting — a few tiny scattered clumps |
| `snow_5.png` | 1983x793 | 0.277 | A large lumpy patch with real holes in it |
| `snow_6.png` | 1774x887 | 0.469 | Near-solid cover, ragged at the edges |

All three carry clean alpha — fully transparent backgrounds, no divider
lines, no dark matte fringe (measured: transparent-pixel fraction 0.94 /
0.71 / 0.52, dark-opaque fraction 0.0000 in all three). Each sheet's ten
cells partition an even 5x2 grid with real empty gutters between them
(measured occupancy runs, `SnowStampAtlas`), so cells crop cleanly.

The set is **deliberately open**: the level ladder is read from whichever
`snow_<level>.png` files exist, so dropping in `snow_2/3/4.png` later
extends the ladder with no code change. Levels 1, 5 and 6 are what the
artist has drawn so far, and three levels are already enough — see
"Density, not steps" below for why the number of levels is not the number
of visible states.

## Mechanism

### Texture bombing, not tiles

The layer is **one fragment shader over world space**, not a grid of
painted tiles. For each screen pixel it asks: *which illustrated snow
stamps overlap this point, and how opaque are they here?*

Stamp sites sit on a virtual world-space lattice of
`STAMP_LATTICE_WORLD` units. Each site draws one stamp of about
`STAMP_WORLD_SIZE` units, with everything about it — position jitter,
which of the ten shape variants, which level, orientation, size — derived
from a hash of that site's own lattice coordinates. Nothing is stored;
every stamp is recomputed from its coordinates every frame, identically
and for free.

Because a stamp is larger than its lattice cell, stamps overlap, and a
fragment must consider its neighbours' stamps too. The search is a fixed
**3x3 neighbourhood**, which is only correct if no stamp can reach further
than 1.5 lattice cells from its own site. That is a real geometric
constraint on the tuning, not a hope, and it is pinned from both sides:

```
STAMP_WORLD_SIZE / 2  +  STAMP_JITTER_WORLD  <=  1.5 * STAMP_LATTICE_WORLD
```

Stamps accumulate by **maximum alpha**, taking the colour of whichever
stamp is most opaque at that point — "the topmost puff wins". Summing
would saturate to flat white mush and lose the illustrated shading;
alpha-compositing would need an ordering the loop does not have.

### Density, not steps

The three real art levels are **not** three visible states. What the depth
field controls is:

- **Whether a site has a stamp at all.** Each site holds its own hashed
  onset threshold, so sites pop in one at a time as the field deepens.
  This is the same idea as the old per-tile onset, at a much finer grain
  than a tile — the reason the mechanism no longer has rungs the player
  can see.
- **How big its stamp is.** A dusting draws small specks; deep snow draws
  large overlapping puffs.
- **Which level it draws**, with a per-site jitter so that neighbouring
  sites near a level boundary disagree about which side they are on. That
  dithers every level transition away instead of drawing it as a contour.

Three levels plus continuous density, size and dithering is a genuinely
continuous ramp from bare ground to solid cover. Adding `snow_2/3/4.png`
would refine the middle of it, not unlock it.

### The drift field

`lying = clamp(depth + onset(world_pos), 0, 1)`, where `depth` is the one
number `Snowfall` maintains for the whole field and `onset` is the
two-octave smooth drift field carried over unchanged from the tile-based
implementation: a **broad** layer at `ONSET_DRIFT_TILES` tiles per lift
deciding which general area catches first, plus a **fine** layer at
`ONSET_FINE_DRIFT_TILES` adding texture within it. That two-layer design
was measured and tuned across three separate reported bugs; it is correct
and it is kept. What changes is only that it is now evaluated per *pixel*
on the GPU rather than per *tile* on the CPU.

Two guards survive from `band_for` and matter for the same reasons: a
genuinely bare field (`depth <= 0`) stays bare for even the most-leading
point, and a genuinely full field (`depth >= 1`) reaches full cover for
even the most-lagging one — onset is a lead/lag on the *climb*, and has
nothing left to lead or lag at either end.

### The hash must be trig-free

The lattice hash is a fract-first Hoskins-style hash, **never**
sine-times-a-large-constant. This world's coordinates reach the hundreds
of thousands of world units; a sine-based hash there feeds `sin()` millions
of radians, float32 range reduction collapses, and the field goes
regionally near-constant — snow would simply not render across whole
regions, while every float64 CPU-mirror statistic passed. That exact
failure was found live in this codebase's river shader and is the reason
this constraint is a *pin*, not a preference:

- a structural test greps the shader source and requires no `sin(`;
- a real-GPU render test renders the material at far-world coordinates,
  reads the frame back, and requires snow to actually appear there, with a
  control at the origin separating a broken harness from broken
  coordinates.

### Footprints

Walking packs snow down rather than clearing it, so a trail reads as tracks
through a field rather than a trench dug to soil. `SnowTrail` still owns
that per-tile bookkeeping on the CPU — it is driven by footstep events, so
its cost is per *footstep*, not per tile of loaded ground.

It reaches the GPU as a **world-space trail mask texture**: a small R8
window that follows the player, sampled by world position. Points outside
the window read as untrodden rather than clamping to the window's edge
value, which would smear the last row of footprints across the rest of the
world.

**Tracks are not player-only.** Every individually-simulated `CreatureMarker`
treads the same way, once per frame, right beside the player's own call in
`World`'s per-frame loop — packing down the exact same `SnowTrail`
dictionary and reaching the exact same trail mask, not a second, parallel
trail system (the caravan/`PathScarring` precedent this deliberately does
*not* repeat — that one forked into its own instance because merging it
into the player's rendered pass was real, separate work; `SnowTrail` had no
such obstacle, since it was already one shared instance on
`EarthChunkManager` rather than one scoped inside the player-tracking
`World` node). The one thing a creature's own tread does *not* do is move
the window above: the window has to keep following the player, so
`EarthChunkManager.tread_snow_at` takes a `move_trail_window` argument —
true (its default) for the player's own call, false for every creature's.
Leaving that false out would let the window snap to wherever the
last-processed creature of the frame happens to be standing, potentially
carrying the player's own nearby tracks right out of view.

Tread reduces both the coverage and the level a site draws — packed snow
is thinner snow, and only where cover was thin to begin with does a boot
reach the ground.

### What the CPU still does

Per frame: push one float (`depth`), and the trail mask only when a
footstep actually landed.

Per chunk load: paint a plain presence cell for every non-ocean tile, once
— **including river and lake tiles** (see "Snow under a river reads as a
staircase" below). Ocean does not take snow — freezing is a different
mechanic and not this one — and this whole-tile ocean check is the only
reason the layer is a `TileMapLayer` at all rather than one screen-sized
quad: the tile grid is what carries "this ground is land", which the
shader cannot know.

Per depth change: **nothing.** This is the whole point. The tile-based
implementation swept every loaded tile every 2 seconds, recomputing bands
and diffing them against a per-tile dictionary — measured at ~40-50 ms per
sweep over the real ~22,700-tile loaded field, after an onset cache had
already cut it from ~200 ms. That sweep, its three per-tile dictionaries,
its 100-image baked atlas and its whole diff-tracking architecture are
deleted, not optimized.

### Snow under a river reads as a staircase

Reported from a screenshot: near a river, the snow/water boundary was a
visible jagged staircase instead of following the river's own smoothly
curved bank.

`_paint_snow_presence` used to also exclude every tile where
`Chunk.blocks_ground_cover` was true (river OR lake — see
[hydrology.md](hydrology.md)), the same exclusion tree/tall-grass/tree-
rooting placement already use to keep themselves out of the water (see
`tall_grass.gd`, `tree_renderer.gd`, `EarthChunkManager._can_root_at`).
For THOSE systems that exclusion is load-bearing: their sprites are parented
under `GroundDecor`, drawn as a *later* sibling than `RiverFlowFx` (see
"Rendering: overlay, not a new biome" in [rivers.md](rivers.md)), so nothing
else would hide a tree standing in the river.

Snow is the opposite case, and this is the fact the bug turned on:
`SnowFx` is an *earlier* sibling than `RiverFlowFx` at the same z_index
(pinned by `test_world_ground_layer_order.gd`), so the river overlay
already draws on top of it every frame. Excluding river/lake tiles from
snow was therefore never load-bearing the way it is for grass/trees — it
just meant a whole tile's snow vanished at the coarse, binary,
`RIVER_HALF_WIDTH_TILES`-distance granularity `Chunk.is_river` is baked at
(see [rivers.md](rivers.md)'s `river_catalog.gd`), while the river's own
visible edge is a smooth, continuous, sub-tile curve (`|across| == 1`,
feathered — see `river_flow_shader.gd`). Those two boundaries don't
coincide except by accident, especially on a diagonal or curved reach, and
the mismatch between a square tile-grid cutoff and a smoothly curved real
edge is exactly what reads as a staircase.

The fix removes the river/lake half of the exclusion and keeps only the
ocean check: a river or lake tile now gets a snow presence cell like any
other land tile, and the river-flow overlay's own already-on-top, already
sub-tile-accurate edge is what makes the boundary read as seamless — no
new curve for snow to compute, the same one the river already draws itself
with. **Ocean is deliberately left excluded and not fixed here**: `WaterFx`
(the ocean shore overlay) is a simpler shore-distance tile approach, not
the continuous `|across|` field `RiverFlowFx` reconstructs, so this same
fix does not extend to it — a coastline under snow may show an analogous,
un-addressed artifact.

## The CPU mirror

A fragment shader cannot be asserted headless, so the tuned parts of the
GLSL are mirrored by `static func`s in GDScript, kept in sync by hand —
the same relationship `water_shader.gd`'s `ripple_amplitude` and
`hillshade_shader.gd`'s `shadow_alpha` have to their own shaders, and for
the same reason.

The mirror covers the hash, the noise, the drift field and the full
bombing accumulate, so the properties that actually matter are real
assertions over real numbers rather than eyeballed screenshots:

- coverage rises monotonically with depth;
- a bare field draws nothing and a full field draws solid cover;
- coverage is continuous across a tile boundary (no seams — the mechanism's
  central claim);
- no lattice-period artifact: coverage sampled on the lattice period is no
  more self-similar than coverage sampled off it;
- neighbouring stamps really do draw different variants and levels.

The mirror runs in float64 and the GPU in float32, so it cannot catch
precision failures. That is exactly what the far-world GPU render test is
for, and why both exist.

## Status

- ✅ **Three leveled snow sheets measured and cropped** — `SnowStampAtlas`
  builds one padded stamp atlas (levels down, variants across) from
  whichever `snow_<level>.png` sheets exist, content-bbox cropped and
  aspect-preserved so illustrated shapes are neither stretched nor clipped.
- ✅ **GPU texture bombing** — `SnowBombShader`, a real `canvas_item`
  fragment shader: 3x3 lattice search, per-site hashed variant / level /
  orientation / size / onset, max-alpha accumulation, trig-free hash, a
  structural tread-can-only-remove-snow clamp, a level-crossfade (no hard
  pop between two independently-illustrated images), and an edge fade
  closing the stamp's-own-footprint-boundary case. `test_snow_bomb_shader.gd`
  26/26.
- ✅ **Wired into the game, the old tile-based path deleted.** `SnowLayer`,
  `_sweep_snow_field`, `_paint_snow_tile` and every per-tile band/onset/
  variant cache are gone (`snow_layer.gd`/`test_snow_layer.gd` deleted
  outright, not deprecated). `EarthChunkManager.set_snow_layer` assigns
  `SnowBombShader.shared_material()` to the same `SnowFx` `TileMapLayer`
  the old system used (unchanged scene wiring — `scenes/world.tscn`/
  `world.gd` needed no edits), whose cells now carry only a one-tile
  `build_presence_tile_set()` land/ocean bit, painted once at chunk load
  (`_paint_snow_presence`) and never revisited: `fragment()` never reads
  `TEXTURE`, so a painted cell means nothing but "may render here" — an
  erased ocean cell keeps snow off water without the shader needing to
  know what a biome is. `step_snow` is now a continuous, unthrottled
  per-frame push (`snow_depth` + a rebuilt trail mask) — the old
  diff-aware sweep and its 2-second throttle are gone along with the cost
  they existed to bound. **Confirmed rendering in a real running
  instance**, not just green tests.
- ✅ **Footprints reach the GPU.** `SnowTrail.build_mask_texture` bridges
  its own tile->float dictionary to a real R8 window texture in world
  pixels, rebuilt once per `step_snow` call and pushed via
  `SnowBombShader.set_trail_mask` — bounded by tracked footprints, not
  window size, so cheap enough to do unconditionally.
- ✅ **Tracks are not player-only.** Every individually-simulated
  `CreatureMarker` treads the same `SnowTrail` and reaches the same mask
  the player's own footsteps do — `EarthChunkManager.tread_snow_at` grew a
  `move_trail_window` argument (true for the player, false for every
  creature) so a creature's own tread cannot relocate the mask window away
  from the player. See this section's own "Tracks are not player-only"
  paragraph above.
- ✅ **Snow now covers river and lake tiles too** — see "Snow under a river
  reads as a staircase" above. `_paint_snow_presence` no longer excludes
  `Chunk.blocks_ground_cover` tiles, only ocean; the river-flow overlay's
  own already-on-top, sub-tile-accurate edge is what keeps the boundary
  looking seamless. Ocean coastlines are unchanged and may still show an
  analogous artifact — not fixed here.
- ⬜ **Far-world precision** — the no-`sin(` structural pin exists
  (`SHADER_CODE` greps clean), but there is no real-GPU readback test yet at
  far-world coordinates; add one, since that is exactly where the old river
  shader's float32 failure hid from every CPU-mirror assertion.
- ⬜ **Snow on top of things, not just under them** — snow lies on the
  ground plane only. Caps on stones, logs and roofs are a separate feature
  and not attempted here.
- ⬜ **`snow_2/3/4.png`** — the middle of the level ladder is not drawn yet;
  the atlas reads whatever exists, so adding them needs no code change.
