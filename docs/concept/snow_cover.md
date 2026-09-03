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
that bookkeeping on the CPU — it is driven by real footstep *events*, so
its cost is per *footstep*, not per tile of loaded ground.

**A footstep is a place and a facing, not a tile.** The first version keyed
tread by `Vector2i` game tile and stepped it on every call — and the caller
called it *every rendered frame the player stood in snow*, not once per real
stride. `TREAD_PER_STEP` reached `MAX_TREAD` in three frames regardless of
whether the player was walking or merely standing still, so the whole tile
saturated to "as trodden as it will ever be" within a fraction of a second
of first arriving, and — because the tile was the unit — one visit packed
the *entire* tile uniformly: there was no way to tell "walked through the
corner" from "walked wall to wall", and no way to distinguish one crossing
from a hundred. That is the literal mechanism behind two reports that turned
out to share one root cause: "footprints don't look like footprints, just a
soft depression" and "walking back and forth doesn't deepen a path."

The fix is the same discipline pillar 1 already states — stop having rungs
the player can see — applied to the trail the way it was already applied to
coverage itself. A mark is recorded only when the player has moved at least
`STRIDE_PX` since the last one (`SnowTrail.step`, the same distance-gated
shape `BloodTrail.step` already uses for a wounded animal's drops — real
human stride length, not a frame count), and it carries the exact world
position and facing at that moment, not a tile index.

What a point on the ground reads as (`tread_at`) is the SUM of every live
mark whose shape reaches it, clamped to `MAX_TREAD` — not the single
deepest one. This is deliberate, not an approximation: real repeated
treading of one spot has to actually deepen it toward the full depth, which
is the literal original complaint, and a max would have reproduced the same
defect in a new shape — every spot capped at whatever one footstep's own
mark is worth, however many times it was really stepped on. Two marks that
do not overlap still contribute nothing to each other's ground, so this is
real accumulated overlap, not every step ever taken leaking into everywhere
else. Repeated walking over one *line* now deepens it two ways at once:
standing and shuffling packs one exact spot toward full depth by summed
overlap, while walking a rough, never-quite-repeating line lays down many
distinct marks that widen the trodden width as they go — exactly how a real
desire path is worn by many feet landing in slightly different places along
the same rough line. A game tile that used to go uniformly trodden the
instant anyone crossed a corner of it now shows a real footpath's width and
depth through it and stays untouched everywhere else — the "big tile, one
scalar" failure and the "split into finer units" fix are the same change
seen from two sides.

**Orientation and displacement are real, not a texture trick.** Each mark
carries the facing it was placed at (this game's own 4-directional character
model — `Player._facing_string`'s own convention, reused rather than a new
one invented here) and is rasterized as an oriented, elongated mark rather
than a round blob — a footprint, not a puddle — with its own value graded
across its shape rather than flat, so it reads as a compression (deep at the
centre, tapering at the edge) rather than a stencil cutout. This costs
nothing new the shader does not already have: `lying_at`'s `tread * 
tread_depth` subtraction is *already* "how much snow this exact point has
displaced" — the only change is that the value sampled at a point is now
shaped like a boot instead of flat across a whole tile, so the pillar 4
claim ("only where the cover was thin to begin with does a boot reach the
ground") is something the player can actually see the shape of.

It reaches the GPU as a **world-space trail mask texture**: a small R8
window that follows the player, sampled by world position. Points outside
the window read as untrodden rather than clamping to the window's edge
value, which would smear the last row of footprints across the rest of the
world. The window now packs several texels per tile (`MASK_TEXELS_PER_TILE`)
rather than one — a single texel per tile is exactly the granularity that
made a boot-shaped mark impossible to express at all, whatever the CPU-side
math wanted to draw into it.

Tread reduces both the coverage and the level a site draws — packed snow
is thinner snow, and only where cover was thin to begin with does a boot
reach the ground.

### What the CPU still does

Per frame: push one float (`depth`), and the trail mask only when a
footstep actually landed.

Per chunk load: paint a plain presence cell for every non-ocean tile, once.
Water does not take snow — freezing is a different mechanic and not this
one — and this is the only reason the layer is a `TileMapLayer` at all
rather than one screen-sized quad: the tile grid is what carries "this
ground is land", which the shader cannot know.

Per depth change: **nothing.** This is the whole point. The tile-based
implementation swept every loaded tile every 2 seconds, recomputing bands
and diffing them against a per-tile dictionary — measured at ~40-50 ms per
sweep over the real ~22,700-tile loaded field, after an onset cache had
already cut it from ~200 ms. That sweep, its three per-tile dictionaries,
its 100-image baked atlas and its whole diff-tracking architecture are
deleted, not optimized.

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
- 🚧 **Footprints reach the GPU, corrected 2026-09-03.** The first version
  bridged a tile→float dictionary to a real R8 window texture, but the
  caller stepped it every rendered frame rather than once per real stride,
  and the tile was the unit — so a whole tile saturated within three frames
  of first entering it, however far the player then walked, and one crossing
  looked identical to a hundred. `SnowTrail.step` now gates on real distance
  moved (`STRIDE_PX`, mirroring `BloodTrail.step`'s own distance-spaced
  shape) and records a place-and-facing mark rather than a tile, rasterized
  as an oriented, graded footprint at several texels per tile
  (`MASK_TEXELS_PER_TILE`) instead of one flat texel per tile — see
  "Footprints" above for the full mechanism and why both reported failures
  were one root cause. Still bounded by tracked marks, not window size, so
  still cheap enough to rebuild unconditionally.
- ⬜ **Far-world precision** — the no-`sin(` structural pin exists
  (`SHADER_CODE` greps clean), but there is no real-GPU readback test yet at
  far-world coordinates; add one, since that is exactly where the old river
  shader's float32 failure hid from every CPU-mirror assertion.
- ⬜ **Snow on top of things, not just under them** — snow lies on the
  ground plane only. Caps on stones, logs and roofs are a separate feature
  and not attempted here.
- ⬜ **`snow_2/3/4.png`** — the middle of the level ladder is not drawn yet;
  the atlas reads whatever exists, so adding them needs no code change.
