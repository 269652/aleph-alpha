# Aquatic Foraging: Real Food, and Fish That Actually Eat It

Requested directly, right after the earthworm crush mechanic shipped: "fish
should have full fledged foraging and also add food into the water somehow...
plankton or whatever or water plants." This doc specifies the **aquatic
producer layer** — the trophic level below every fish the world already
simulates — and the first real consumer wired onto it: a fish that grazes it.

This closes a real, named gap: [ecosystem_dynamics.md](ecosystem_dynamics.md)'s
own "A shoal finds its shape" section gives fish a full, real social-behaviour
precedence order (flee > lure > play > schooling > wander), but every one of
those five states is about *how a fish moves*, never *why it needs to*. A fish
in this game has never once eaten anything. This doc gives it a real reason to
be somewhere other than mid-water: food, sited exactly where real aquatic
vegetation actually grows.

## Design pillars

1. **Real mechanisms, not a hunger bar.** A patch of pondweed is somewhere a
   fish can actually swim to and actually remove by grazing it, the same
   "real, addressable, world-state" standard every other patch sim in this
   project already holds itself to (`TallGrass`, `EarthwormPatch`,
   `FlowerPatch`) — not an invisible number ticking up and down.
2. **Water plants, not plankton.** Both were floated; water plants win because
   they are the one option this project's whole aesthetic already insists on
   — see every prior soil/flora pass — **something the player can actually
   see**. Plankton is real, but it is microscopic: there is nothing to render,
   nowhere for a fish to visibly arrive, and no discrete thing for a mechanic
   to remove. A visible pondweed patch a fish visibly noses down to and clears
   is the same "logic and its own visible form arrive together" standard this
   project has held to for every food source before it (worms, seeds, fruit,
   nectar).
3. **Foraging fits inside the existing precedence order, not above it.**
   `ecosystem_dynamics.md`'s fear-always-wins / lure-predates-schooling /
   schooling-only-displaces-wander ordering is real, tuned, and already
   shipped — this pass does not reopen it. Foraging slots in exactly where
   plain wander already sat: a fish with nothing more urgent to do forages
   instead of drifting aimlessly, but a fleeing, lured, playing, or
   schooling fish is unaffected.
4. **Determinism.** A chunk's water seeds the same vegetation patches every
   time it loads, the same `PixelNoise`-seeded, never-`hash()` guarantee
   every other patch sim in this project already gives.

## Real-world grounding

- **Submerged and floating freshwater vegetation (pondweed, algae mats,
  duckweed) grows in slow-moving or still fresh water** — river shallows and
  lake margins, not fast rapids and not the open ocean (a genuinely different,
  saline, wave-driven environment this game's own fish population model
  already scopes separately — see `fishing.md`'s river/lake-only population).
  `Chunk.blocks_ground_cover` already tracks exactly this water extent
  (`is_river OR is_lake`), the identical mask `TallGrass` already reads to
  KEEP grass OUT of the water — this pass reads the same real mask to grow
  vegetation only INSIDE it.
- **Small, common freshwater fish (minnows, sunfish, and similar) are
  substantially herbivorous/omnivorous grazers**, cropping algae and soft
  vegetation as a real dietary staple, not just chasing other animals for
  food. A fish idly nosing along the bottom or margin of a river is
  real, ordinary behaviour, not a stretch.
- **Aquatic plant growth is seasonal**, slower in cold water and faster in a
  warm growing season — the identical `SeasonCycle.growth_modifier` every
  other plant patch sim in this game already reads, not a new seasonal model.

## Mechanism spec

### `AquaticVegetation` (new, `src/world/aquatic_vegetation.gd`)

Mirrors `TallGrass`'s own patch-sim contract almost exactly (pure
`RefCounted`, `PixelNoise`-seeded smooth-noise field clustering so patches
read as real weed-beds rather than salt-and-pepper noise, a hard per-chunk
cap, `advance(delta, growth_modifier)`, a pure `graze(cell) -> bool`) — the
same "clone the proven shape, change what's genuinely different" convention
`EarthwormPatch` itself already used against the same sibling family. What is
genuinely different: seeding is gated to WATER cells
(`Chunk.blocks_ground_cover`) instead of grassland, and there is no
ground-seed-shedding layer — real aquatic plants spread by fragmentation and
rhizome growth into adjacent water, which the existing throttled `_step_
spread` mechanism already models without needing a second, carried-seed
entity the way `TallGrass`'s own land-animal-carried seed does.

### `FishForaging` (new, `src/gameplay/fish_foraging.gd`)

Pure static functions, mirroring `FishSchooling`'s own shape exactly (that
class is already "a handful of pure static functions `FishMarker` calls into
each frame," not an instantiated behaviour object — the fish system's own
established pattern, followed here rather than importing the land-animal
`XForageBehavior` state-machine convention wholesale into a file that has
never used it) —

- `nearest_target(position, candidates) -> Variant` — the nearest real
  vegetation position within range, or null. Pure geometry, independently
  testable without a real `EarthChunkManager`.
- `FORAGE_DETECTION_RADIUS_TILES` / `GRAZE_ARRIVE_DISTANCE_PX` — real, tested,
  pinned constants (not eyeballed) bounding how far a fish notices food and
  how close counts as "arrived."

### `FishMarker` wiring

Slots a new target-priority tier into the exact chain
`ecosystem_dynamics.md`'s "A shoal finds its shape" already specifies, in the
one place that was still a bare fallback: where the priority chain used to
fall through straight to plain wander, it now first checks for a real nearby
vegetation patch (`EarthChunkManager.aquatic_vegetation_near`) and steers
toward it via the identical heading-toward-a-point math `attract_target`
already uses; arriving grazes it
(`EarthChunkManager.graze_aquatic_vegetation_at`) and the fish falls back to
plain wander until its next food search finds something else. Every state
above this one (bolt, attraction, play, schooling) is completely untouched —
a fleeing, lured, playing, or schooling fish never even reaches the foraging
check.

### `EarthChunkManager` wiring

`aquatic_vegetation_near(pixel_position, radius_tiles) -> Array` /
`graze_aquatic_vegetation_at(pixel_position) -> bool` mirror `worms_near`/
`take_worm_at`'s own exact shape. `step_aquatic_vegetation(delta)` mirrors
`step_worms`'s own per-chunk `advance` loop, called from the same ecology
batch. Per-chunk `AquaticVegetation` instances are created at `_load_chunk`
time, gated to chunks that actually contain water at all (the same
"don't allocate a sim for a chunk with nothing for it to do" discipline
`EarthwormPatch`'s own soil-biome gate already uses) — a chunk with no river
or lake tile gets no vegetation sim, exactly as a desert/tundra/ocean chunk
gets no earthworm patch today.

### Rendered presence

`ProceduralAquaticVegetationSprite` — a small offline-drawn frond/weed
silhouette, the same "hand-drawn procedural style, real illustrated art
later" convention `ProceduralWormSprite`/`ProceduralAntMoundSprite` already
follow. One static, non-swaying sprite per real vegetation cell, spawned/
freed with its chunk exactly like every other per-chunk marker in this
project (worm sprites, ant mounds) — logic and its own visible form arrive
together, per this doc's own second design pillar above.

## Revised (2026-09-07): real per-species diet and forage-coupled mass

Requested directly, brainstormed first: *"what the different fish we have
eat and what we need to add to the ecosystem so every fish can properly
forage and grow mass."* Then, asked to pick between the two open framings
that brainstorm surfaced: **"Forage-coupled mass, and yes to real
per-species items."** This closes the two biggest gaps the section above
named — no per-species diet, no mass of any kind — and answers them
together, because they are the same mechanism: a fish that eats gains
real mass toward its own species' adult size; a fish that cannot eat
(nothing in its diet nearby) does not grow.

### `FishDiet` (new, `src/gameplay/fish_diet.gd`)

Mirrors `FlyerDiet`'s own shape exactly (see that file's own doc comment:
*"the table that makes 'robins eat worms, sparrows eat seeds' a
STRUCTURAL fact rather than an `if species == "robin"` buried in a
marker"*) — a plain `species -> Array[food type]` table, `eats(species,
food)`/`foods_for(species)` lookups, no instance state. `FishMarker`
already carries a real per-instance `species` field (set at spawn for
rendering, per `ProceduralFishSprite.SPECIES_IDS`) — it was simply never
READ for anything but sprite colour. This wires it into behaviour instead
of inventing a second species concept.

Two food types for now, matching what the ecosystem actually offers (see
`AquaticInvertebrates` below):

```
const FOOD_VEGETATION := "vegetation"
const FOOD_INVERTEBRATES := "invertebrates"

const DIET_BY_SPECIES := {
    "bluegill": [FOOD_VEGETATION, FOOD_INVERTEBRATES],
    "koi":      [FOOD_VEGETATION, FOOD_INVERTEBRATES],
    "goldfish": [FOOD_VEGETATION, FOOD_INVERTEBRATES],
    "trout":    [FOOD_INVERTEBRATES],
}
```

Real-world grounding, per the brainstorm: bluegill are genuine
omnivorous sunfish (algae/plant matter AND insects/small invertebrates);
koi are famously indiscriminate omnivores; common goldfish (carp family,
same as koi) graze algae/plant matter and also take small invertebrates.
Trout are the real outlier — overwhelmingly insectivorous/carnivorous
(aquatic insect larvae are the entire basis of fly-fishing); plant matter
barely features in a real trout's diet, so it gets the same narrow,
single-food-type shape `FlyerDiet` already gives the kingfisher
(`[FOOD_FISH]` only) rather than a padded-out list. An unrecognized
species eats nothing, same "missing from the table simply doesn't feed"
contract `FlyerDiet.foods_for` already has, catchable by an equivalent
every-spawnable-species roster test.

### `AquaticInvertebrates` (new, `src/world/aquatic_invertebrates.gd`)

The real gap trout's own diet exposed: vegetation alone cannot be a real
diet for an insectivore. Real streams and ponds host aquatic insect
larvae (mayfly/caddisfly/midge nymphs and similar) in the same water
`AquaticVegetation` already grows in — a second producer-adjacent layer,
not a variant of the first.

Mirrors `AquaticVegetation`'s own contract line for line — same
`PixelNoise`-seeded clustering, same water-cell gate, same
`advance(delta, growth_modifier)`/`graze(cell) -> bool` shape, same
per-chunk cap derivation — the identical "clone the proven shape, change
what's genuinely different" move `AquaticVegetation` itself already made
against `TallGrass`. What's genuinely different: `GROWTH_RATE` is tuned
higher than `AquaticVegetation.GROWTH_RATE` — a real insect-larva
population turns over on the order of days/weeks, far faster than a weed
bed's own rhizome-driven regrowth, so a grazed patch should visibly
recover sooner. Rendered the same way, too:
`ProceduralAquaticInvertebrateSprite` mirrors
`ProceduralAquaticVegetationSprite`'s own shape (a small, distinct
silhouette — a cluster of larvae/nymphs, not a frond) so the two food
layers read as different things at a glance, not two colours of the same
icon.

`EarthChunkManager` wiring mirrors the vegetation wiring exactly:
`aquatic_invertebrates_near`/`graze_aquatic_invertebrates_at`/
`step_aquatic_invertebrates`, a parallel `_aquatic_invertebrates`
dictionary seeded at `_load_chunk` time behind the identical water-cell
gate `AquaticVegetation` already uses (both sims exist together in any
chunk that has water at all — real ponds host both plants and insect
life in the same water, not one or the other).

### `FishMarker` diet-gated foraging

`_step_foraging` no longer unconditionally seeks vegetation. It now
checks `FishDiet.eats(species, FishDiet.FOOD_VEGETATION)` /
`FishDiet.eats(species, FishDiet.FOOD_INVERTEBRATES)` and only queries
(and targets) the food types this species actually eats — a trout never
so much as looks at a vegetation patch, an omnivore checks both and
takes whichever is nearer. Everything above this tier in `ecosystem_
dynamics.md`'s precedence order (flee/lure/play/schooling) is untouched,
exactly as the original pass already established.

### `FishGrowth` (new, `src/gameplay/fish_growth.gd`) and `FishMass` (new, `src/world/fish_mass.gd`)

**Mass is forage-coupled, not a clock.** Unlike `MammalGrowth` (a land
creature grows from a fixed newborn fraction to full size over a fixed
real-time duration, regardless of whether it ever finds food), a fish's
`mass_kg` only advances on a REAL successful graze — a fish with nothing
in reach of its own diet does not grow, the direct mechanical answer to
"can properly forage and grow mass" being one connected fact rather than
two independent ones.

`FishMass.mass_kg_for(species) -> float` is the real ADULT reference
mass table, the exact same shape and convention `CreatureMass._REAL_MASS_KG`
already established for land animals (a real, commonly-cited average
adult weight per species, never invented):

```
const _ADULT_MASS_KG := {
    "bluegill": 0.25,  # real bluegill rarely exceed ~0.5kg
    "goldfish": 0.4,   # a real, well-grown common (non-fancy) goldfish
    "trout":    0.5,   # a representative adult catch weight
    "koi":      3.5,   # real ornamental koi genuinely dwarf the other three
}
```

`FishGrowth.JUVENILE_START_FRACTION` (0.5) is where a freshly-promoted
`FishMarker` starts — half its species' adult mass. Deliberately NOT
`MammalGrowth.NEWBORN_SCALE` territory (a literal fry/fingerling): this
game does not model a hatch event for fish (`FishRenderer.spawn_fish`
promotes population into markers directly, the same as it always has —
see `fishing.md`), so there is no real "just born" moment to anchor a
tiny starting fraction against the way a live mammal birth has one.
Starting already half-grown is the honest reading of "a fish that exists
in the world, not yet fully grown" rather than pretending a birth event
that isn't modeled.

`FishGrowth.feed(current_mass_kg, adult_mass_kg) -> float` is the one
real growth step: `minf(current_mass_kg + adult_mass_kg *
GROWTH_PER_MEAL_FRACTION, adult_mass_kg)`. A FRACTION of the species' own
adult mass per successful meal (`GROWTH_PER_MEAL_FRACTION`, pinned by
test), not a flat kg amount — a bluegill and a koi both take roughly the
same NUMBER of good meals to mature, proportional to their own real size,
the identical species-scaled-by-proportion reasoning `MammalGrowth`
itself already applies to maturation DURATION (a mouse and a bear both
grow up "quickly" relative to their own lifespan, not in the same wall-
clock time). Linear toward the cap and monotonic — no starvation-driven
shrinkage modeled (named explicitly rather than silently absent: no
existing hunger/needs system in this codebase currently drives mass
downward for anything, land creatures included, so this doesn't invent a
first instance of it for fish alone).

Called from `FishMarker._step_foraging` immediately after EITHER
`graze_aquatic_vegetation_at`/`graze_aquatic_invertebrates_at` succeeds —
whichever food type this fish just actually ate from feeds the same
`mass_kg`, real fish are not size-limited by WHICH food source fed them,
only by how much.

**Visual size follows real physics, not an arbitrary lerp.** `FishMarker`
scales its sprite by `cbrt(mass_kg / adult_mass_kg)` — mass scales with
the CUBE of a linear dimension, the identical reasoning
`CreatureMass._mass_from_world_scale` already uses in the other
direction (deriving a mythical species' mass FROM its visual scale); this
reuses that same real relationship to go the other way, deriving a
grown fish's visual scale FROM its real mass, so a half-grown fish
(`cbrt(0.5) ≈ 0.79`) reads as visibly, believably smaller — not half-size
outright (a linear mass-to-scale mapping would make a young fish look
comically flat, the exact "distorted... very large/small" failure shape
this project has already hit and fixed once for `SquashCrushEffect`).

### What this pass does NOT include

Named rather than silently dropped: **worms are still not a food source
for fish at all** — the original pass's own explicit follow-up, now
superseded in intent (aquatic insect larvae answer the real gap worms
were meant to close, and are the more accurate real trout diet besides)
but not itself withdrawn; a worm swept into the water from an eroding
bank remains a plausible, ungrounded-here follow-up. No plankton, no
ocean vegetation — freshwater river/lake only, unchanged from the
original pass. No swaying/current-driven animation on either patch
sprite. No fish-on-fish predation (a real trout eating smaller fish as
it grows) — plausible and grounded, genuinely bigger than this pass (it
needs per-fish vulnerability, not just diet), tracked as its own open
question in `fishing.md`, not attempted here. No starvation-driven mass
loss (see `FishGrowth`'s own doc comment above). Terrestrial insects
falling into water near a bank (a real, well-known trout-stream
phenomenon) — a cheap, plausible future addition once `AquaticInvertebrates`
proves out, not required for a fish to have a complete real diet today.

## Status

- ✅ `AquaticVegetation` — real per-chunk water-gated vegetation patch sim.
- ✅ `ProceduralAquaticVegetationSprite` — real rendered presence.
- ✅ `FishForaging` — pure target-finding, wired into `FishMarker`'s existing
  precedence chain at the wander tier.
- ✅ `EarthChunkManager.aquatic_vegetation_near`/`graze_aquatic_vegetation_at`/
  `step_aquatic_vegetation`.
- ✅ `FishDiet` — real per-species diet table, gating which food types a
  fish's own foraging even looks for.
- ✅ `AquaticInvertebrates`/`ProceduralAquaticInvertebrateSprite` — the
  second real aquatic food layer, closing trout's own diet gap.
- ✅ `FishGrowth`/`FishMass` — forage-coupled mass, growing only on a real
  successful graze, capped at a real per-species adult mass, visually
  expressed through the same cube-law scale relationship `CreatureMass`
  already established for land species.
- ✅ Real per-species catch items — see `fishing.md`'s own "Individual-
  fidelity promotion" section for the catch-side half of this pass.
- ⬜ Worms/terrestrial insects as an additional aquatic food source,
  fish-on-fish predation, plankton, ocean vegetation, sprite sway
  animation, starvation-driven mass loss (see scope note above).
