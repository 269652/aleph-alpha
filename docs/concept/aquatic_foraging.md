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

## What this pass does NOT include

Named rather than silently dropped: **worms are not yet a food source for
fish at all** — a worm thrown into water or fished with becoming an
especially attractive, high-value bait is the direct, explicit follow-up
this pass exists to make meaningful, not attempted in this same commit. No
fish species differentiation in diet (real fish diets vary by species; this
game's own fish are not yet species-differentiated at the individual-marker
level at all, per `fishing.md`'s own "species is a per-tile deterministic
pick... at catch time" scope note — extending diet by species waits on
that). No plankton, no ocean vegetation — freshwater river/lake only, per
the real grounding above. No swaying/current-driven animation on the
vegetation sprite itself (a real but purely cosmetic follow-up, the same
"logic first" scope cut leaf litter's own fall animation once was before
its own follow-up pass).

## Status

- ✅ `AquaticVegetation` — real per-chunk water-gated vegetation patch sim.
- ✅ `ProceduralAquaticVegetationSprite` — real rendered presence.
- ✅ `FishForaging` — pure target-finding, wired into `FishMarker`'s existing
  precedence chain at the wander tier.
- ✅ `EarthChunkManager.aquatic_vegetation_near`/`graze_aquatic_vegetation_at`/
  `step_aquatic_vegetation`.
- ⬜ Worms as fish bait (the direct next pass).
- ⬜ Per-species fish diet, plankton, ocean vegetation, sprite sway animation
  (see scope note above).
