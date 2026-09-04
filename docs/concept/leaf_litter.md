# Leaf Litter: What Falls, What Rots, What Eats It

[soil_fauna.md](soil_fauna.md) names this exact gap in its own Scope choices:
*"A real detritivore population model (litter input β†’ worm biomass β†’ bird
carrying capacity) is the natural follow-up and is deferred."* This doc closes
the **litter input** half of that chain: trees shed leaves and blossom onto the
ground, season-weighted (little in spring and summer, most in autumn), the
litter persists and rots down over time whether anything eats it or not, and
ants and carrion bugs -- [carrion.md](carrion.md)'s `DecomposerMarker`, which
already models exactly these two species -- can find and eat it.

## Design pillars

1. **Real accumulation, not a spawned decoration.** Litter is on the ground
   because leaves actually fell, driven by the same world clock every other
   seasonal quantity already reads (canopy turn, fruiting, snowfall) -- not a
   timer that spawns a decal.
2. **A real, depletable resource.** A decomposer eating litter actually
   reduces how much is there, the same contract `Carcass.take_bite` already
   has. A visual that doesn't feed back into the number lying under it is a
   decoration, not the mechanic this was asked for.
3. **Persisted, not re-derived.** Canopy snow depth is deliberately NOT saved
   (see `docs/progress.md`'s snow-frame entries) because it is never consumed
   -- it can always be recomputed from the weather clock on reload. Litter is
   different: something eats it, so its value at any moment depends on a real
   history the clock alone cannot reconstruct. It has to be saved.
4. **Reuse before invention.** Every piece below already has a precedent
   elsewhere in this codebase, and uses it rather than a new mechanism:
   stateless elapsed-time rate functions (`FruitingModel`), a small persisted
   scalar per chunk (`ChunkSerializer.save_ecology`), depletion by amount
   (`Carcass.take_bite`), and a consumer that already searches for and walks
   to a food source (`DecomposerMarker`).

## Real-world grounding

- **Leaf fall is seasonal and cued by day length and temperature (abscission),
  not a single event.** A few leaves come down from wind or petal-drop
  through spring and summer; the bulk falls in autumn as deciduous trees shut
  down chlorophyll production and cut their leaves loose before winter --
  exactly the "few in spring/summer, more in autumn" shape asked for.
- **Fallen leaves are the base of the litter layer, and litter is what feeds
  the detritivores underneath everything else.** Earthworms (`soil_fauna.md`)
  and carrion-feeders (`carrion.md`) are downstream consumers of two
  DIFFERENT organic inputs (soil organic matter, and carcasses); leaf litter
  is a third, distinct input its own consumers -- ants and ground/carrion
  beetles foraging the leaf layer itself, not only carcasses -- already exist
  in-game to eat.
- **Litter decomposes whether or not anything eats it.** Fungi and bacteria
  break it down continuously; a pile of leaves left untouched thins on its
  own over the following weeks, the same real process `Carcass.ROT_SECONDS`
  already stands in for on a carcass.

## Mechanism spec

### Per-chunk litter accumulation

A single persisted float per chunk, `leaf_litter` -- the same shape as every
other small aggregate `ChunkSerializer.save_ecology`/`load_ecology` already
carries (`herbivores`, `land_health`, ...), appended as one more
forward-compatible field rather than a new file format.

Driven by a **stateless function of elapsed time**, evaluated as the
difference between two timestamps -- `FruitingModel.fallen_between`'s own
pattern, adopted deliberately: an earlier version of that file tried
incrementing a running counter every step and lost real fruit to floating-
point rounding at typical per-step deltas, documented at length in its own
history. `LeafLitter.fallen_between(t0, t1, season_weight)` must not repeat
that mistake.

Seasonal weight is a small table, not a continuous curve fitted from nothing:
autumn heaviest, spring and summer a light trickle, winter negligible (an
already-bare canopy has nothing left to shed) -- mirroring
`FruitingModel.RIPENING_BY_SPECIES`'s own precedent for "a small, named,
tested table beats an invented formula."

### Decay

Litter thins on its own over time, whether or not anything eats it -- a
decay rate applied the same closed-form way accumulation is (a function of
elapsed time, not a per-frame subtraction), so a chunk that unloads for a
long time comes back having rotted down realistically in one step, the same
way `ChunkEcologyCatchup.advance` already catches up fruit stock and land
health across an unload without re-simulating every missed tick.

### Litter as food: ants and bugs

`DecomposerMarker` already models exactly the two species asked for --
`"ant"` and `"bug"` -- and already knows how to search for, path to, and eat
from something with a `take_bite`-shaped contract (see `Carcass`). Extending
its search to also consider a chunk with real standing litter, and depleting
`leaf_litter` the same way a bite depletes `_decompose_health`, reuses that
whole loop rather than building a second one beside it.

### Rendering: deferred, not designed away

The visual side -- individual leaves drifting down and piling visibly near a
tree -- is real scope, not yet built in this pass. The right SOURCE ART is
already settled: `IllustratedTree`'s new per-species litter closeups (single
leaf/blossom drawings, found the same way `CANOPY_SNOW` is -- optional, by
what a sheet actually contains, not a roster) rather than anything drawn
fresh. The right RENDERING approach is not yet settled and deserves its own
pass rather than a guess: this project has hit real, measured performance
collapses from the "obvious" per-object approach twice already (character
compositing at 160ms/tree, and the original tile-painted `SnowLayer` at
40-50ms/sweep, both replaced by shader/hash-driven approaches instead) -- see
`SnowBombShader`'s own doc comment for the second one. A litter-density
overlay in the same spirit (driven by the persisted `leaf_litter` scalar,
not a spawned node per leaf) is the likely shape, but is a separate,
dedicated design pass, not assumed here.

### Scope choices (explicit)

- **No individual falling-leaf animation or ground decal this pass.** See
  "Rendering" above -- real scope, deliberately deferred rather than shipped
  as a per-object system likely to repeat a cost this project has already
  paid down twice.
- **Chunk-level, not per-tile or per-tree.** Matches every other persisted
  chunk aggregate (`herbivores`, `land_health`, `fish_population`); a
  per-tree number would need new persistence machinery individual trees do
  not otherwise have (trees are regenerated from the chunk seed, not saved
  as individual objects, except for the modifications `chunk_modifications`
  already tracks).
- **Only species with a real litter closeup on their sheet gain this.**
  Confirmed on cherry's sheet today; other species' equivalent frames, if
  any, are picked up automatically the same way `has_snow_frame_for` needed
  no roster when a second sheet grew its own snow column -- no per-species
  code required either way.

## Status

βœ… **Litter closeup frames found on cherry's sheet**
(`IllustratedTree.litter_frames_for`) -- the single leaf/blossom drawings
below the trunk row and the twig-detail row, found by position the same way
every other role on the sheet already is.

🚧 **Accumulation, decay, persistence, and decomposer feeding** -- being
built this pass (`src/world/leaf_litter.gd`,
`EarthChunkManager.step_leaf_litter`/`leaf_litter`,
`ChunkSerializer.save_leaf_litter`/`load_leaf_litter`, `DecomposerMarker`
extended to search litter alongside carrion).

⬜ **Rendering** -- deferred, see "Rendering: deferred, not designed away"
above.
