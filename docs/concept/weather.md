## Weather & disasters

[world.md](world.md) already implies weather matters ("a drought or
overhunting measurably changes where you find [boars]") without ever
defining an actual system. This formalizes it: dynamic, simulated weather
that has real mechanical teeth, not just atmosphere.

- **Dynamic weather** (rain, storms, snow, fog) is driven by the existing
  climate/season/day-night clock ([world.md](world.md)) rather than being
  an independent random layer — a tropical biome and a tundra biome should
  weather differently by construction, RDR2/BOTW-style regional variety.
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
the colour, speed and slant swapped. White, far slower, and drifting rather
than slanting; reusing rain unchanged would give WHITE RAIN, which reads as a
recolour rather than as weather.

**It accumulates and it thaws.** The ground whitens over a snowfall and clears
over a thaw, both slowly enough to watch: ground that went from bare to white
between two frames would read as a bug, and so would a thaw that did. It
whitens the GROUND rather than the whole scene -- snow lies on the land, and
tinting everything would put a wash over the trees and the player too. The
grass keeps its shape and its blades under it: it is covered, not replaced.

**Walking displaces it.** Footprints are the same shape as the dirt paths worn
into grass (see `PathScarring`): walking marks a tile and the world slowly
undoes it. What undoes it is the difference -- a path grows back on its own,
while footprints sit there until it snows again. So a trail across a field
lasts through a clear cold day and is gone after a fall.

### Status

- ✅ Snow instead of rain below freezing, falling white and slow
- ✅ Accumulation and thaw, whitening the ground
- ✅ Footprint displacement and snow filling tracks back in
- ✅ Tracks rendered: snow is a per-tile overlay, so footprints carve it

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
