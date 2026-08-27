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
as snow. Two things make it true now. A thin cover is TRANSLUCENT
(`SnowLayer.BAND_ALPHA`), so the ground tints through it instead of being
knocked out in specks; that is the only way this layer can tint toward the
ground at all, since one tile set is baked for every biome and so the layer has
no ground colour of its own to blend with. And the coverage roll happens in
blocks of `SnowLayer.GRAIN_BLOCK` art pixels rather than per art pixel: one art
pixel is half a WORLD pixel, a shade nudge may legitimately be that fine but
coverage is a hard present/absent mask, and a hard mask rolled below the world
pixel grid is a dither, i.e. static.

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
smooth form instead: `MAX_NEIGHBOUR_ONSET_STEP` holds two touching tiles to a
quarter of a band, so a band boundary takes at least four tiles to cross and
the snow LINE meanders through the field. The field still spans the full
variance -- a test pins that too, so nobody "fixes" a neighbour-step failure by
flattening the drift to a constant and putting the whole chunk back on one
shared threshold.

**The repaint itself has to happen often enough to show that mix changing.**
Onset variance alone was not sufficient: the whole-field repaint that
actually pushes new pixels to the tile layer only fired when the tracked
depth crossed one of the four texture-band boundaries, so within a single
band's depth range -- comfortably a third of a whole snowfall -- nothing
repainted at all no matter how far coverage kept climbing underneath. A real
probe caught it: coverage sat flat at the same percentage from depth 0.02
through 0.25, then jumped straight to full at 0.5 -- the instant-reveal bug
again, just relocated to a coarser timescale. `EarthChunkManager._repaint_snow`
now also repaints whenever depth has moved by `SNOW_REPAINT_DEPTH_STEP`
(0.05, well under the onset variance so several checkpoints land across the
spread) since the last repaint, not only on a band crossing -- still on the
order of dozens of repaints across a whole snowfall, not one every frame.

### Status

- ✅ Snow instead of rain below freezing, falling white, slow, and as FLECKS
  rather than rain's streaks — `RainOverlay.FLAKE_LENGTH`/`drop_length_scale`
  plus the `drop_length_scale` shader uniform, tested; wired in `set_snowing`.
- ✅ Accumulation and thaw, whitening the ground
- ✅ Footprint displacement and snow filling tracks back in
- ✅ Tracks rendered: snow is a per-tile overlay, so footprints carve it
- ✅ A dusting reads as frost, not as white static — a thin cover is
  translucent so the ground tints through it, and the coverage mask is never
  rolled finer than one world pixel (`SnowLayer.BAND_ALPHA`/`GRAIN_BLOCK`,
  both pinned by tests).
- ✅ Per-tile onset variance, so a field fills in as a visible spread rather
  than snapping everywhere at once — `SnowLayer.ONSET_VARIANCE`/
  `onset_offset_for`/`band_for`, tested; wired in
  `EarthChunkManager._paint_snow_tile`.
- ✅ That onset is a low-frequency DRIFT field, not per-tile static, so the
  snow line meanders instead of rendering as hard-edged tile squares —
  `SnowLayer.ONSET_DRIFT_TILES`/`MAX_NEIGHBOUR_ONSET_STEP`, tested from both
  sides (coarse enough, and not flattened to a constant).
- ⬜ Sideways DRIFT on falling flakes — a wobble across the fall. Flakes
  currently come down near-vertically (`Snowfall.FLAKE_SLANT` 0.05). Needs its
  own uniform and its own tested constant.
- ⬜ Water freezing over. Snow deliberately never lies on water
  (`EarthChunkManager._paint_snow_tile` erases the cell over `"ocean"`):
  ice is a separate mechanic that does not exist yet, so this is a boundary
  rather than an omission.
- ✅ The repaint that reveals that spread runs often enough to show it moving
  — `EarthChunkManager.SNOW_REPAINT_DEPTH_STEP`, tested; wired in
  `_repaint_snow`.
- ✅ A chunk streamed in mid-snowfall shows its own correct snow immediately
  (`_load_chunk` calls `_paint_snow_chunk` for just that chunk) rather than
  staying bare until the next field-wide repaint happens to reach it; an
  unloaded chunk's painted snow cells are erased along with the rest of its
  overlays (`_unload_chunk`), not left floating over nothing.

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
