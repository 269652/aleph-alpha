# The sward: what grows between the tussocks

Reported live, looking at a real grassland chunk at noon: *"the bare grass
parts feel empty."* They were. `TallGrass` covers about 20% of grassland,
clustered into fields; `FlowerPatch` seeds 3.5% of cells. The remaining ~76%
of a meadow had **nothing on it at all** — a flat tiled blade texture whose
seams you can count, one cobble every few tiles, and no other living thing.

This doc owns the layer that goes there.

## Design pillars

**A meadow is not grass-or-nothing.** Real grassland has two distinct plant
layers, and this game had only the top one. Above is the tussock — the tall
grass a grazer takes in mouthfuls. Below and between is the **sward**: a low
carpet of rosette-forming herbs, mostly leaves, ankle-high. A field with the
tussocks removed is not bare earth; it is clover and plantain.

**The sward is a readout, not decoration.** This is the pillar the whole doc
rests on, and it is what separates this from the "few flat flower pixels baked
into its tile art" that [flora.md](flora.md) rightly criticises. How much sward
a cell carries is a *consequence* — of how much tall grass shades it, and of
how hard it has been grazed. A player who keeps animals on a meadow will watch
it change under them, without anything telling them it happened.

**Foliage, not blooms.** [flora.md](flora.md)'s rule is that *what is visible
must be what is real*: a bloom drawn on the ground is a promise that a
pollinator will visit it. The sward makes no such promise, because it is drawn
as **leaves** — a clover trefoil, a plantain rosette, a yarrow frond. Blooms
stay `FlowerPatch`'s job, and the two layers can coexist on the same cell
without either lying about the other. It is also simply what these plants look
like for most of the year.

**It must be nearly free to draw.** The sward is the majority of the ground, so
it cannot be a `Sprite2D` per plant — `DecorationLod` exists because ~2,900
decorative sprites measurably decayed the frame rate (55.7 → 49.1 fps). Four
`MultiMeshInstance2D` **in total**, one per species, flat on the ground under
everything else.

Per-chunk nodes are the shape every other decoration layer here uses, and they
are the wrong shape for this one: the sward is already scoped to the
tile-precise camera window rather than to whole chunks, and once the visible set
is the unit of work, splitting it by chunk only multiplies draw calls.

## Real-world grounding

**The grazing lawn.** Every species in the sward shares one trait: its growing
point sits at or below ground level. A grass blade grows from a meristem near
its tip, so a bite that takes the top of a tussock takes its growing point with
it. A clover or a plantain grows from a crown pressed flat against the soil,
and a bite merely trims leaves it will replace.

That single anatomical difference is why grazing *selects for* the sward.
Graze a meadow hard and it converts to clover, plantain and daisy — the classic
"grazing lawn". Stop grazing and the tussocks close over and shade the rosettes
out. A sheep pasture and a hay meadow, on the same soil, in the same climate,
look nothing alike, and that is the whole reason.

**Species**, a plausible Central European sward (the game's Berlin default):

| species | what it is | why it is here |
|---|---|---|
| **white clover** (*Trifolium repens*) | creeping trefoil | the classic grazing-lawn legume; spreads by stolon, not seed |
| **ribwort plantain** (*Plantago lanceolata*) | flat rosette of ribbed lance leaves | the most grazing-tolerant plant in a pasture |
| **daisy** (*Bellis perennis*) | tight ground rosette | survives being trodden on, which is why it is on every lawn |
| **yarrow** (*Achillea millefolium*) | fine feathery frond | deep-rooted, drought-tolerant, holds the sward through a dry spell |

## Mechanism spec

### Cover is a pure function, not a stored number

The one piece of ecology in this system is a single pure function:

```gdscript
GroundCover.cover_for(base: float, tall_grass_growth: float, grazing: float) -> float
```

- `base` — the cell's own inherent richness, deterministic `PixelNoise` from
  the chunk seed. Soil varies; a meadow is not uniform.
- `tall_grass_growth` — 0 where no tussock stands, 1 under a mature one.
  **Shade suppresses.**
- `grazing` — how hard this cell has been bitten lately. **Grazing releases.**

Everything else in the module is bookkeeping around that function. Keeping the
ecology in one pure, tested function rather than spread across an `advance()`
is what lets the renderer ask for a live answer with the *current* tall-grass
growth, instead of the sim having to be told about grass every tick.

The orderings that matter, and the tests that pin them, are properties rather
than numbers — the multipliers stay retunable:

- `test_shade_suppresses_the_sward` — more tall grass, less sward.
- `test_grazing_releases_the_sward` — a grazed cell carries more than an
  ungrazed one at the same shade.
- `test_a_grazed_tussock_beats_an_ungrazed_gap` — the composition that makes
  the readout legible: hard grazing under a tussock still beats an untouched
  bare cell, because that is what a grazing lawn *is*.
- `test_cover_never_leaves_its_range` over the whole input cube.

### Grazing memory decays

`record_graze(cell)` steps a per-cell grazing memory up; `advance(delta)` decays
it. The decay half-life is expressed against `TallGrass.SPREAD_INTERVAL` — the
clock on which the tussocks actually come back — rather than as an eyeballed
number of seconds, so retuning grass regrowth keeps the two in step.

The input is already live: `EarthChunkManager.graze_grass_at` is what a
herbivore calls through `CreatureMarker._take_forage_bite`. One line there
feeds this.

### What is drawn

Cover drives **how many** rosettes a cell shows, not how big they are — a
richer patch of sward is more plants, not larger ones.

```gdscript
GroundCover.plant_count_for(cover: float) -> int   # 0 .. MAX_PLANTS_PER_CELL
```

Each plant's species, offset within the cell, and art variant are derived from
`PixelNoise` on its own cell and index, so a meadow shows real variety and a
reloaded chunk redraws exactly the same one.

Rendering is four `MultiMeshInstance2D`, one per species, each bound to that
species' own procedurally generated texture (`ProceduralSwardSprite`) — one
draw call per species for every rosette on screen. Per-species nodes rather
than one node against an atlas because selecting an atlas cell per instance
needs a shader and custom data (the way `IllustratedGrassPatch` does it), and
four draw calls is cheaper than that machinery for art this simple; per-plant
variety comes from the instance transform, not from a texture each.

Parented to `_ground_decor_parent`, so it draws flat and under everything, with
no wind shader and no Y-sort bands: a rosette is ankle-high and lies beneath
whatever is standing on it, which is exactly why it needs none of what
`IllustratedGrassPatch` needs.

The visible set is rebuilt whole on the same `GRASS_REFRESH_INTERVAL` throttle
and the same tile window (`DecorationLod.keeps_decoration_tile` with
`GRASS_VIEW_BUFFER_TILES`) the tussocks use, so the two plant layers appear and
disappear together instead of the sward popping in a beat behind.

A five-second throttle is fine while standing still and visibly wrong while
walking, because the window moves with the player. So the sward also rides
grass's own "make the next refresh due immediately" trigger in
`_sync_decoration_and_grass_tracking` — fired on a tile crossing and on a chunk
crossing — without which the ground at the leading edge of the screen stays
bare for up to five seconds after it comes into view. Pinned by
`test_walking_a_tile_makes_the_sward_refresh_due_immediately` and
`test_the_sward_and_the_tussocks_come_due_together`, the second of which exists
so the shared trigger cannot quietly become two copies that drift.

Per-instance MultiMesh transforms do not round-trip under `--headless` (the
dummy renderer), so the tests cover the **placement math** and the atlas
painting; the `MultiMesh` fill itself is thin glue, the same split
`IllustratedGrassPatch.instances_for_cards` / `fill_band` already uses.

### Scope choices (explicit)

- **Grassland only.** A forest herb layer is real and is the obvious next
  biome, but the reported problem is the meadow and the species table above is
  a pasture sward.
- **Not food.** Grazers do not eat the sward yet. They plainly should — it is
  what a real grazing lawn is *for* — but `FOOD_GRASS` currently means the
  tussock, and giving herbivores a second, denser food source is an ecology
  balance change that deserves its own pass rather than riding in on a
  rendering fix.
- **No spread, no species competition.** Cover is a function of shade and
  grazing, not a population that colonises. Clover really does spread by
  stolon and really does out-compete plantain on fertile soil; neither is
  modelled.
- **Not persisted.** A reloaded chunk re-derives its base cover from the same
  seed, and grazing memory is short-lived by construction — the same reasoning
  `EarthwormPatch` and `AntColony` give for theirs.

## Status

- ✅ `GroundCover` — the sim: deterministic `PixelNoise` base richness on
  grassland cells, `cover_for` as the one piece of ecology, `plant_count_for`,
  `plants_for_cell`'s unit-space layout, and the grazing memory with its
  decay expressed against `TallGrass.SPREAD_INTERVAL`.
- ✅ Grazing is a live input: `EarthChunkManager.graze_grass_at` — the call a
  herbivore already makes through `CreatureMarker._take_forage_bite` — now also
  releases the sward on that cell.
- ✅ `ProceduralSwardSprite` — four species, four silhouettes, cached per
  species and seed.
- ✅ Rendering: four `MultiMeshInstance2D` in total (not per chunk), rebuilt on
  the same tile-precise camera window and the same `GRASS_REFRESH_INTERVAL`
  throttle the tussocks use, parented to `_ground_decor_parent` so it draws
  flat and under everything.
- 🐛 **Fixed in the same pass, reported from a real screenshot: the first
  version read as pale white STARS scattered over the meadow**, not as plants
  growing in it. Two causes, both now pinned by tests rather than by eye.
  (1) The plantain and yarrow leaf colours were *less saturated* than the
  grassland tile — and a washed-out green against a vivid one reads as grey
  however dark it is. Luminance alone did not catch it (they were already
  darker than the grass), which is why the test that guards this is about
  saturation: `test_no_sward_species_is_washed_out_against_the_grass`, against
  `ProceduralTerrainSprite.BASE_COLORS["grassland"]`. (2) Leaves radiated at
  evenly-spaced angles with a bright midrib, which is a snowflake. The angular
  jitter is now wide enough that leaves genuinely crowd and gap, and
  `HIGHLIGHT_LIGHTEN` is a shading rather than a flash.
- ⬜ Not food (see Scope choices). Grazers do not eat the sward.
- ⬜ Grassland only; no forest herb layer.
- ⬜ No spread, no species competition, not persisted.
- ⬜ **No seasonal response.** A real sward browns off in a drought and stays
  green under snow longer than the tussocks do; `SeasonCycle.growth_modifier`
  is right there and this does not read it. The most obviously missing next
  thing.
