# Ecosystem Dynamics

This doc specifies the living-ecosystem simulation: how plants fruit, how that
fruit feeds animals, how animal populations grow and prey on one another, and
how all of this is computed at two fidelities — **individual agents** on-screen
near the player, and a cheaper **aggregate catch-up** for chunks the player
isn't looking at. Every rule below is deliberately grounded in a real-world
ecological mechanism so the world behaves plausibly rather than arbitrarily.

## Design pillars

1. **Real mechanisms, not scripted spawns.** Fruit appears because trees are in
   their fruiting phase, not because a timer drops loot. Boars are where boars
   thrive. Populations rise and fall from births, deaths, predation, and food —
   the same feedback loops that govern real ecosystems.
2. **Two fidelities, one truth.** What the player can see runs at individual-agent
   fidelity (each ripe fruit is a pixel, each animal a node making its own
   decisions). What the player can't see runs as an aggregate per-chunk integration
   that is *catch-up integrated* the moment the player returns, so a region the
   player left evolves believably instead of freezing or resetting.
3. **Determinism.** Both fidelities are seeded/deterministic so a region looks
   the same on revisit given the same elapsed time — no divergence between the
   two representations beyond intended stochastic variation.

## Plant phenology (fruiting)

Real fruit trees move through phenological stages: flowering → fruit set →
green (immature) fruit → **ripening** → **abscission** (ripe fruit detaches and
falls) → decomposition. We model a simplified version per tree, driven by the
tree's own DNA (`TreeGenome.fruit_yield` sets its potential crop; `species_bias`
sets fruit-vs-nut lean) and its local climate (warmer/wetter → faster ripening,
matching growing-degree-day phenology).

Per-tree state over elapsed time yields three counts:

- **Growing** — immature fruits still developing on the tree (not yet edible).
- **Ripe** — mature fruits still hanging (edible; **rendered as individual
  pixel dots on the canopy**). Capped by the tree's `fruit_yield` crop potential.
- **Fallen** — ripe fruits that have abscised and dropped to the ground this
  step (become ground-item `fruit`/`nut` drops that animals and the player can eat).

Ripening rate and the fall (abscission) threshold are tuned constants pinned by
tests, not eyeballed. A tree that has just dropped its crop re-enters the growing
phase (a new fruiting cycle), so trees fruit repeatedly over time — like a real
seasonal bearing cycle compressed to the game's timescale.

## Frugivory and seed dispersal

Fallen fruit is food. Herbivores (and omnivores like boars) that pass within
eating range of a fallen fruit consume it, gaining body condition (energy). This
is the frugivory half of a real seed-dispersal mutualism: the plant trades food
energy for having its seeds carried and its offspring fed.

The disperser half now exists for one species: a robin that eats fallen fruit
(a second diet entry alongside the earthworms it already hunts, see
[soil_fauna.md](soil_fauna.md)) carries the seed for a real gut-passage-timed
interval before planting a sapling elsewhere — see
[flora.md](flora.md#bird-endozoochory-swallowing-the-seed-not-just-carrying-it)
for the full mechanism. Ground herbivores/omnivores still only ever get the
food-energy half (no seed dispersal from them yet), and no seed PREDATOR
exists to create the disperser-vs-predator tension [flora.md](flora.md)'s
DNA loop describes — both remain open extensions.

## Animal bioenergetics and reproduction

Real animals only reproduce when their body condition supports it — starving
animals don't breed. Each creature carries an **energy/condition** value that:

- **rises** when it eats (fallen fruit, grazing, or — for predators — prey),
- **decays** slowly over time (basal metabolism),
- and **gates reproduction**: a creature reproduces only when it is both
  **healthy** (high health fraction) and **well-fed** (energy above a threshold),
  and then only after a **refractory cooldown** (real inter-birth interval).

When those conditions are met near the player, the individual creature spawns an
offspring beside it (individual-scale birth), paying an energy cost. Away from
the player the same effect is captured by the aggregate logistic growth term.

### Births are slow, and crowding stops them

Two limits keep individual-scale birth from turning a clearing into a herd:

- **The refractory cooldown is a full real-world day.** A single animal can give
  birth at most once per 24 real hours, so growing a population is a background
  change a returning player notices, never something they watch happen. This is
  wall-clock time, not world time -- inter-birth interval is a property of the
  animal's body, and the player's felt experience of "the herd got bigger while
  I was away" is what the number is chosen for.
- **Local crowding vetoes birth.** Before an animal breeds we count its own
  species within a short radius; past a small cap it doesn't, regardless of
  condition. The same count is passed to the vegetation-derived herbivore
  capacity for the animal's chunk, so a thin biome supports fewer births than a
  lush one. Density dependence therefore acts *where the animal stands*, not
  only against the global creature cap.

## Grazing is an act, not an aura

A herbivore used to feed by standing still. Hunger crossed its threshold, the
tile under it happened to be a food biome, and hunger went back to zero on that
frame -- so a horse on grassland was never hungry for longer than one frame, had
no reason to go anywhere, and nothing about eating was ever visible. The tall
grass a herd "ate" was whatever its aimless wander happened to cross.

Land herbivores now forage the way the pollinators and the ground-feeding birds
already do (see `GrazerForaging`, and `GroundForageBehavior` for the robin it is
modelled on): **see a specific thing, walk to it, put your head down, move on.**

- **What an animal will walk to is its diet.** The default comes from the diet
  label `CreatureInfo` already assigns -- a Grazer crops grass, an Omnivore works
  mast, seed and the soil fauna under it, a Forager takes seed and fruit -- with
  per-species overrides where the label is too coarse. A deer carries one: it is
  a mixed feeder rather than a strict grazer, so it takes windfall fruit that a
  horse walks straight past. Only the rooters take worms.
- **Blooms are deliberately not edible.** They are the pollinators' resource and
  the seed loop's source; letting grazers crop them would quietly eat the
  butterflies' food supply to feed the horses. Grazers take the grass between
  the flowers, which is what they mostly do anyway.
- **A bout is long and the walk between bouts is short.** Real grazers spend the
  bulk of their active day feeding and only step between mouthfuls, so the
  head-down fraction is pinned as a ratio rather than eyeballed.
- **What is visible is what is real.** Only mature tufts are offered as targets,
  because a mature tuft is what the animal can actually crop on arrival; a bite
  disappears from the world on the frame the muzzle is in it, not at the next
  throttled sprite refresh.
- **Nothing to walk to is not starvation.** An animal that can see no bite but
  stands on living ground crops what is under it -- the old biome grazing, except
  it now costs a full head-down bout like any other bite.
- **A threat outranks a meal.** An animal that senses something lifts its head
  and goes; it does not finish the mouthful.

## Biome-specific species composition

Pillar 1 ("boars live where boars thrive") extends beyond population *size* to
population *composition*: which species show up at all should depend on the
biome, not just how many individuals do. A promoted individual's species is
chosen from a **per-biome species pool** (grassland/forest/desert/tundra/
rainforest/mountain each have their own herbivore+predator pair; unmapped
biomes fall back to a generic pool), keyed off the chunk's **dominant
biome** — the most frequent biome among its cells, since a chunk can straddle
more than one. Every species reuses one of 4 hand-drawn silhouette shapes
(deer-shaped, boar-shaped, wolf-shaped, lynx-shaped) in its own color rather
than needing bespoke pixel art per species, since the ecological point is
biome-appropriate *variety*, not bespoke art for its own sake. Temperament/
role stay independent of shape: a species can reuse a shape family and still
have its own diet/temperament (e.g. tapir reuses boar's silhouette but is
calm, not aggressive).

Mountain's vegetation carrying capacity, previously a hard `0.0` (making
mountain permanently uninhabitable regardless of species pool), is now a
small nonzero placeholder reflecting real sparse alpine grazing above the
tree line — see `vegetation_growth_model.gd`'s `CARRYING_CAPACITY_BY_BIOME`.

## Species roster: mice, horses, and a new aerial tier

The biome-specific pools above stayed within one shape: ground quadrupeds
occupying exactly two roles, herbivore and predator. Rounding out a "basic
ecosystem" means two different kinds of addition — more variety *within*
that existing two-role, aggregate-simulated tier, and an entirely new
**aerial tier** that sits outside it by design.

### More variety within the existing tier: mice and horses

Mice and horses are new herbivore-role species, nothing more — they slot
directly into `HERBIVORE_SPECIES_POOL_BY_BIOME` exactly like camel/
reindeer/tapir/goat did, with no new mechanism required:

- **Mice** are the small-forager end of the herbivore role: real mice are
  near-ubiquitous generalists (any biome with vegetation supports them), so
  mice join *every* non-ocean biome's pool rather than being biome-
  exclusive like the desert/tundra/rainforest/mountain specialists. New
  shape family (see `ProceduralAnimalSprite`): mice don't read as any
  existing silhouette at any scale (short legs, round body, long tail), so
  they get a small hand-authored `mouse_shape` bitmap — deliberately the
  simplest of the five families, since mice render small on screen.
- **Horses** are the large grassland/steppe grazer end — real wild/feral
  horses are a genuine grassland and dry-steppe herbivore, so horses join
  grassland's and desert's pools (steppe and semi-arid range both fit).
  Horses reuse `deer_shape` rather than needing new art: both are
  slender-legged ungulates, and the project's existing convention is
  explicitly "every species reuses one of 4 hand-drawn silhouette shapes…
  the ecological point is biome-appropriate variety, not bespoke art for
  its own sake" — horse is exactly the deer/camel/reindeer/goat situation
  again, just a new color/species entry on an existing shape.
- Both are ordinary `CreatureInfo` entries (own stats/diet/temperament,
  `is_predator = false`) and run the *exact* same `CreatureBehavior`
  flee/graze/drink AI and the *exact* same aggregate
  `EcosystemSimulation`/`HerbivorePopulationModel` logistic growth as every
  other herbivore — no new population mechanism, only roster variety. Both
  are herd/calm-temperament grazers.
- **Update, grass seed dispersal pass:** mice DO now carry one small,
  genuinely new mechanism on top of the above — real scatter-hoarding
  rodents cache seed, and that behaviour has nothing to do with the generic
  "Forager" diet label mice happen to share the table with (see
  `concept/long_grass.md`'s "Reproduction" section and
  `EarthChunkManager._step_grass_seed_caching`, gated to `species ==
  "mouse"` specifically). This narrows, rather than contradicts, "no new
  mechanism required" above: population growth/reproduction is still the
  exact same aggregate machinery every herbivore uses; only this one
  ecological side-behaviour (which plant species end up where) is
  mouse-specific.

### Forest gets its own named predator: wolves, and their sheep prey

The biome-specific pools above (desert/jackal, tundra/arctic_fox, rainforest/
jaguar, mountain/mountain_lion) each pair a biome with one dominant NAMED
predator of its own — except forest, which drew its dominant predator slot
from the plain `"predator"` placeholder (wolf-shaped, gray-coated) that every
other biome falls back to when nothing more specific applies. That
placeholder was always this project's own anonymous stand-in for a wolf —
see `ProceduralAnimalSprite.SPECIES_SHAPE_FAMILY`'s `"predator": "wolf_shape"`
and this doc's own "wolf-dominant predators" phrasing above — so giving it a
real name, real stats, and real illustrated art closes the one gap left in
that per-biome pattern rather than adding a new role.

- **Wolves** are forest-exclusive (real wolves are the classic temperate/
  boreal forest apex predator), added to forest's predator pool alongside —
  not in place of — its existing lynx dominance, generic `predator` filler,
  and HARD-gated bear. An ordinary `CreatureInfo` predator-role entry
  (`is_predator = true`, aggressive temperament, "Hunter" diet), no minimum
  difficulty tier (like every other pre-existing roster member).
- **Sheep** are wolves' (and deer's) real forest prey. Predation itself needs
  no new mechanism: `is_predator` already means "hunts herbivore-role
  creatures generically" (see CreatureInfo's own doc comment), not a
  per-species prey list, so a wolf sharing forest with sheep and deer already
  hunts both by construction — the roster addition alone is what makes it
  real rather than just a name. Sheep are an ordinary calm, non-predator
  herbivore-role entry, joining forest only (not every biome, unlike mice) —
  they exist here specifically as wolf/deer-adjacent prey, not as a
  general-purpose grazer.
- Both get real illustrated art (`assets/sprites/animals/wolf.png`,
  `sheep.png`) via `IllustratedAnimalSprite`, rather than falling back to
  the shared procedural silhouettes deer/boar/horse used before their own
  art existed. Their source sheets are the first illustrated-animal sheets
  supplied on a solid **chroma-keyed magenta** ground (with a real alpha
  channel and near-white cell dividers) instead of the plain white/
  transparent convention deer/boar/horse use — the same "transparent
  background was ignored by the AI image generator" situation
  `IllustratedStoneSprite` already solved for pebbles/boulders/cobbles (see
  that class's own doc comment). `IllustratedAnimalSprite` gained its own
  copy of that despill-before-slice, scrub-after-normalize chroma-key logic,
  gated per sheet behind a `"magenta_keyed"` flag so the existing white-
  background sheets are entirely unaffected (skipped outright, not merely a
  no-op on non-magenta pixels). Each sheet is a 2-row (walk, then eat) x
  8-column grid; neither has a dedicated idle row, so idle synthesizes from
  the eat cycle's own frame 0, same as deer/boar.

### A new aerial tier: ambient flyers and one predator

Birds and butterflies don't fit the ground-quadruped mold at all —
different silhouette, different movement (unconstrained 2D flight, not
terrain-relative wandering), and for most of them, no real trophic role
worth simulating. Rather than force them into the aggregate
herbivore/predator population machinery, they get their own lighter tier,
matching how this project already treats "present but not
population-simulated" wildlife (the original static tree-placement layer,
grass tufts, lichen): a deterministic, capped, per-chunk decorative spawn
with its own lightweight movement, no reproduction/death/migration model.
This is an honest scope choice, not an oversight — see Open questions below
for what a real bird/insect population model would need and why it's
deferred.

- **Butterflies** are pure ambient wildlife: real pollinators, but
  pollination → flower/fruit-set feedback is a genuine future mechanism
  (see Open questions), not modeled here. Movement is a fluttering,
  low-speed, frequently-changing-heading drift (visually distinct from a
  bird's straighter glide), confined to no particular target — just "make
  a meadow feel alive." Biome-gated to grassland/forest/rainforest (real
  butterflies are a warm/flowering-habitat presence; excluded from desert/
  tundra/mountain/ocean as implausible).
- **Songbirds** are the same ambient tier, biome-gated to forest/grassland/
  rainforest, with their own glide-and-perch movement pattern (straighter
  runs between heading changes than a butterfly's flutter). Real songbirds
  are largely insectivore/granivore. The **insectivore half now has a real
  feeding model** — see [soil_fauna.md](soil_fauna.md): a per-chunk earthworm
  population that surfaces with soil moisture and warmth, a per-species diet
  table, and a robin that descends onto a worm, sits down, pecks it, and
  actually removes it from the chunk. Songbird *numbers* are still decorative
  and capped — this is feeding behaviour, not population dynamics, and a
  worm-rich chunk does not yet hatch more robins the way a flower-rich chunk
  hatches more pollinators. The robin's diet now also includes a
  **frugivore half** — fallen tree fruit
  ([flora.md](flora.md#bird-endozoochory-swallowing-the-seed-not-just-carrying-it)),
  eaten through the same land/sit/peck cycle as a worm, with a real
  consequence beyond feeding: a swallowed seed gets carried and planted
  elsewhere, the one genuinely new disperser mechanism this pass adds. The
  **granivore half is still open**: sparrows are specified as seed eaters
  but no seed model exists yet, so a sparrow still only drifts.
- **Fish-eating birds** (heron/osprey-type piscivores) are the one
  genuinely new *mechanism*, not just roster variety: a real behavioral
  role that reaches into the aquatic population model
  ([fishing.md](fishing.md#aquatic-population-model)) the same way a
  player's rod does. Spawn is gated to chunks with water (not a land biome
  pool) and capped like every other decorative tier. Behavior is a small,
  pure, testable state machine — **cruise** (ordinary ambient flight over
  open water) → **target** (a nearby chunk's fish population is above
  zero, so the bird commits to a dive point) → **dive** (a fast, visibly
  different descent toward the water) → **grab-or-miss** (a probability
  roll, not a guaranteed catch — real herons/ospreys miss most strikes) →
  on a **grab**, the exact same `EcosystemSimulation.record_catch` the
  player's fishing hook now calls (see
  [fishing.md](fishing.md#aquatic-population-model)) fires for this bird's
  catch too, so a heavily-birded cove is measurably fished down over time
  just like a heavily-angled one → **ascend** back to cruise altitude →
  **cooldown** (real birds don't dive continuously; a real digestion/
  re-hunt interval) before it can target again. This closes the loop the
  aquatic model spec already asked for: fishing pressure was previously
  only ever the player; a bird population that's always present on a
  coastline is now a second, always-on mortality source on the same
  aggregate number — exactly the kind of multi-source pressure a real
  fishery actually has.

### Open questions

- Pollination (butterflies/songbirds feeding vegetation or
  [flora.md](flora.md)'s fruit set) is real and grounded, but has no model
  to hook into yet on either side (no flower/pollen state, no per-species
  feeding need); tracked here rather than invented wholesale in this pass.
  Partly overtaken since: flowers now carry real nectar state that
  pollinators deplete (see [flora.md](flora.md)), and birds now have a real
  per-species diet (see [soil_fauna.md](soil_fauna.md)). What is still
  missing is the FEEDBACK — pollinator visits do not yet affect fruit set,
  and eaten worms do not yet affect bird numbers.
- Should ambient flyers eventually graduate to their own lightweight
  aggregate population (so, e.g., a region genuinely overhunted of insects
  has visibly fewer songbirds), the way fish now will? Deferred — there's
  no predation pressure on butterflies/songbirds yet to make that number
  mean anything, unlike fish (angler + bird harvest) or land herbivores
  (predator hunting).
- Fish-eating-bird population itself is decorative/capped, not aggregate —
  a real "more fish support more birds" feedback (bird carrying capacity
  derived from local fish population, mirroring how predator capacity
  derives from herbivore population) is a natural, grounded follow-up once
  the aquatic model above is live and provably working with a fixed bird
  count.

## Region difficulty (gating the roster by player readiness)

Rounding out the roster with real predators (bear, lion) and a real hazard
(venomous snake) raises a design question the earlier roster additions
didn't: those are meaningfully more dangerous than anything currently in
the game, so they shouldn't just appear next to a fresh player's spawn
point the way mice and songbirds do. This section specs how a region's
difficulty is derived and how it gates which of the roster's more
dangerous members can spawn there.

### Why not real-world danger statistics, and why not manual region curation

Two tempting approaches, both worth naming and rejecting:

- **Real-world wildlife-danger statistics** (attack/incident rates by
  country or region) sound like the most "grounded" option, but don't
  actually hold up: rigorous, consistent, global data at this granularity
  barely exists, and even where it does, turning "N incidents/year" into a
  game-balance number is itself an arbitrary judgment call — the
  real-world data wouldn't remove the arbitrariness, just hide it behind a
  citation.
- **Manually mapping countries/cities/regions to a difficulty tier** doesn't
  scale to a real, full-size Earth (thousands of distinct places, no
  natural stopping point for "did we cover enough of them"), and more
  importantly means directly asserting that specific real countries or
  cities are "dangerous" — a real-world value claim about actual places
  that has nothing to do with this game's own simulated ecology and is
  uncomfortable to encode as content regardless of intent.

### What we do instead: two signals the game already computes from real data

- **Biome/climate plausibility** (already real-world-grounded, via
  `BiomeClassifier`'s existing real-elevation/climate-derived biomes) —
  extends the exact pattern the original 12-species roster already uses
  (`HERBIVORE_SPECIES_POOL_BY_BIOME`/`PREDATOR_SPECIES_POOL_BY_BIOME`):
  bears fit temperate/boreal forest and tundra, lions fit hot grassland
  (savanna-equivalent), venomous snakes fit warm arid (desert) and tropical
  (rainforest) biomes — the same real-world habitat logic already
  grounding every other species placement in this doc. This determines
  *which* dangerous species are even ecologically plausible in a region,
  independent of difficulty.
- **Remoteness from the world's spawn point** — a simple, transparent,
  standard game-design gradient (concentric difficulty bands expanding
  outward from where a fresh character starts, the same shape Terraria's
  layers/Diablo's acts/Valheim's biome rings already use), *not* a claim
  about the real world. This is what actually answers "regions for
  different player levels": a region's raw chunk-distance from the fixed
  spawn tile (the same Berlin-area point `world.gd`/the test suite already
  use) maps to a difficulty tier — EASY near spawn, then MEDIUM, then HARD
  farther out. Deliberately not tied to the player's own traveled distance
  or save data — the region itself has a fixed difficulty independent of
  who's visiting it, the same "no fixed spawn zone, the *conditions* make a
  species viable" philosophy already governing biome-based placement, just
  applied to one more condition (remoteness) instead of vegetation/water.

A dangerous species spawns only where BOTH conditions hold: the region's
biome is one it's ecologically plausible in, AND the region's difficulty
tier is at or above that species' own minimum tier. Everything already in
the roster (the original 12 species, mice, horses, deer, non-venomous
snake) has no minimum tier (available everywhere its biome already allows,
unchanged) — only the three new dangerous additions (bear, lion, venomous
snake) are tier-gated, so this is additive to the existing roster, not a
retrofit/rebalance of it.

### Player level

Kept advisory, not a hard travel gate: nothing stops a strong player from
walking into a HARD region early (or a fresh player from wandering too far
and meeting a bear) — the open, no-invisible-walls world this project
already commits to. A region's difficulty tier is meant to *inform* (a
HUD/warning signal is a natural, separate follow-up), not police, where a
player of a given level should be.

### Status / mechanisms

- ✅ `region_difficulty.gd` (chunk-distance-from-spawn → tier), wired into
  `CreatureRenderer`'s species-pool selection (`MIN_DIFFICULTY_TIER_BY_SPECIES`)
  and `EarthChunkManager.set_spawn_tile`/`_difficulty_tier_at`.
- ✅ Bear, lion, venomous snake as difficulty-gated roster additions.
- ✅ Deer, non-venomous snake as ordinary (ungated) roster additions.
- ✅ Venom (venomous_snake's bite) — `venom_model.gd` + the existing
  `debuff_stack.gd`, `Player.apply_venom`/`_venom_step`.
- ⬜ HUD difficulty warning (open question, not blocking the gating itself).

## Locomotion: look before you step

An animal decides **where it is allowed to go before it goes there**, rather
than moving and reacting to the consequences afterwards.

This is a design rule, not an optimisation. Every reactive mechanism in the
movement stack — reshape a heading that points at a threat, notice after the
fact that the creature didn't actually advance — behaves well *while somewhere
open remains*, and degrades into visible thrashing when nothing does. A
creature wedged between the player and a tree has nowhere to go, so a reactive
system picks a new direction every single frame, and the animal reads as
vibrating rather than as cornered. Real animals do the opposite: when there is
no way out, they stop and watch.

**The rule.** Before committing to a step, an animal checks the destination
against:

- **Solid props** — tree trunks, stones, ore. Only the trunk of a tree is
  solid; canopies are walked under, not around.
- **Its own flee radius** — a non-fleeing animal will not take a step that
  closes the distance to something it is keeping away from. This is what stops
  an animal wandering into its own panic range and bouncing straight back out.

If the preferred heading fails, progressively wider turns are tried, smallest
first — an animal walks *around* an obstacle rather than veering wildly off a
good heading, and among clear detours the side that **keeps its current
facing** wins: turning around is the most visible thing an animal can do, so
it is a last resort, not a tiebreak. If nothing is clear, it **stands idle**:
no movement, no walk cycle, no turning. Standing still is a legitimate
outcome, not a failure to find a move — and once declared stuck, the animal
holds that stand until its senses refresh rather than re-deciding every frame.

**Turning around is committed.** A facing change holds for a beat
(`FACING_COMMIT_SECONDS`); a reversal requested inside that window is refused
and the animal stands for the frame instead. Movement never contradicts
facing — an animal that cannot yet turn does not walk backward; it waits.
Real animals stop, then turn.

**Wandering rests.** A deterministic share of wander intervals
(`PAUSE_FRACTION`) are standing pauses — grazing, looking around — because
continuous, never-resting drift reads as mechanical. Searching for a needed
resource, seeking, and fleeing never pause.

**Two escape hatches**, both necessary. The checks are "don't make it worse",
never "must not be close": an animal the player has walked up to is *already*
inside its flee radius, and one that has somehow ended up overlapping a trunk
is *already* inside that. Refusing every step in those states would pin the
animal exactly when it most needs to leave, so a step that doesn't decrease
the offending distance always stays available. A fleeing animal is likewise
gated on obstacles but **not** on threats — it still goes around a tree, but
must not be talked out of running by the very thing it is running from.

**Thresholds are ramps or hysteresis, never hard switches.** Repeatedly, a
hard on/off boundary at some distance has produced a frame-rate limit cycle:
cross the line, the behaviour changes, the change carries the animal back
across the line, repeat. Flee acquisition uses a Schmitt trigger (entered at
the sense radius, released further out); caution avoidance ramps its strength
with proximity instead of switching on at a radius; home-anchoring contains
outward motion rather than pulling against it. Opposing influences must also
never be blended and then renormalised — a near-cancelled step scaled back up
to full speed is ill-conditioned and reverses on sub-pixel noise. Where forces
would oppose, the animal slows and stops instead.

## Population dynamics (aggregate)

At the aggregate (per-chunk) level we use the classic ecological equations:

- **Logistic growth** for herbivores toward a vegetation/water-derived carrying
  capacity `K`: `dN/dt = r·N·(1 − N/K)`. Growth is fastest at intermediate
  density and stalls as the region fills up — real density dependence.
- **Lotka–Volterra-style predator–prey coupling**: predator carrying capacity is
  derived from prey abundance (a trophic-pyramid ratio), so predators lag and
  track their prey; over-predation depresses prey, which then depresses predators,
  which lets prey recover — the canonical oscillation.
- **Fruit stock** accumulates on the region's trees over elapsed time (aggregate
  of the per-tree phenology) and is drawn down by herbivore consumption, coupling
  the plant and animal layers.

These already exist for *loaded* chunks (`ecosystem_simulation.gd`,
`herbivore_population_model.gd`, `predator_population_model.gd`). This doc adds
the *unloaded* case.

## Variable-fidelity simulation (LOD)

The world is far too large to simulate every chunk every frame. So:

- **Loaded chunks (near the player)** run at **individual fidelity**: real tree
  nodes with per-tree fruiting and visible pixel-dot fruit, real creature nodes
  making per-agent decisions (flee/hunt/graze/eat/drink/reproduce). This is the
  "happens right on the scene" layer.
- **Unloaded chunks (away from the player)** are *not* ticked continuously.
  Instead each chunk records the world-time at which it was unloaded, and on
  reload a **catch-up integration** advances its aggregate state (vegetation
  regrowth, accumulated fruit stock, herbivore logistic growth, predator–prey
  coupling) by the elapsed unloaded duration in one step. The region the player
  returns to therefore reflects everything that "would have happened" while they
  were away — trees have fruited, herds have grown or been thinned by predators —
  without paying per-frame cost for unwatched chunks.

This catch-up is the honest, bounded version of a full always-on planetary
simulation: correct in aggregate, deterministic, and O(chunks-revisited) rather
than O(all-chunks-per-frame).

## Status / mechanisms

- ✅ Look-before-you-step locomotion — `creature_movement_gate.gd` (pure:
  candidate headings vs. blockers/threats, returns "stand still" when
  nothing is clear), wired into every movement intent in `creature_marker.gd`
  (`_advance_gated`; obstacles gathered from the `tree`/`stone` groups and
  sized from their own collision shapes). Flee is obstacle-gated but not
  threat-gated, by design.
- ✅ Ramped/hysteretic thresholds throughout creature movement —
  `FLEE_RELEASE_RADIUS` (Schmitt trigger), ramped caution avoidance,
  `CreatureWander`'s containment-based home anchoring, and the same
  containment in `AmbientFlyerMovement` (birds/butterflies had kept the old
  hard home-radius switch), each replacing a hard distance switch that had
  produced a frame-rate limit cycle. The movement gate's detour is sticky
  (kept while clear, dropped the moment the desired heading clears) for the
  same reason.
- ✅ Obstacle lookup is O(nearby), not O(world) —
  `EarthChunkManager.solid_obstacles_near`, from per-chunk tree/stone
  bookkeeping; creatures duck-type onto it.
- ✅ Gait cadence ∝ ground covered — `CreatureMarker.GAIT_STRIDE_PER_FRAME`
  (derived constant): stride frequency scales with real speed, legs freeze
  when no ground is covered.
- ✅ Logistic herbivore growth, predator–prey capacity coupling, per-loaded-chunk
  ecosystem step (pre-existing).
- ✅ Biome-specific species composition (per-biome herbivore/predator species
  pools keyed off a chunk's dominant biome) — `creature_renderer.gd`'s
  `HERBIVORE_SPECIES_POOL_BY_BIOME`/`PREDATOR_SPECIES_POOL_BY_BIOME`,
  `biome_classifier.gd`'s `dominant_biome`, wired in `EarthChunkManager`.
- ✅ Per-tree fruit phenology (growing/ripe/fallen) — `fruiting_model.gd`,
  now scaled per NAMED species (Walnut/Cherry/Apple, see
  [flora.md](flora.md#named-species-cherry-apple-walnut)) via a
  yield/ripening multiplier pair layered on top of the genome's own raw
  traits. This entry and the one below were stale (still marked 🚧) after
  the underlying phenology/rendering had already landed fully wired and
  tested; named species is what's new this pass, not the phenology itself.
- ✅ Ripe fruit rendered as canopy pixel dots on near trees, in the tree's
  own named-species colour (`ProceduralTreeSprite`/`TreeRenderer`).
- 🚧 Condition-gated individual reproduction — `animal_reproduction.gd`.
- ✅ Unloaded-chunk catch-up integration — `chunk_ecology_catchup.gd`, wired
  into `EarthChunkManager`'s load/unload path (`_apply_ecology_catchup`/
  `_unloaded_ecology`), tested (`test_chunk_ecology_catchup.gd`). This entry
  was stale (still marked 🚧) after the code landed.
- ✅ Aquatic sibling of this whole doc (fish population as a water-area-
  derived carrying capacity, with an explicit fishing-harvest mortality
  term the land model still lacks) — `aquatic_population_model.gd`,
  `water_area_survey.gd`, wired into `EcosystemSimulation`/
  `ChunkEcologyCatchup`/`EarthChunkManager`, persisted across restarts
  (`ChunkSerializer.save_fish_population`) — land ecology still isn't. See
  [fishing.md](fishing.md#aquatic-population-model).
- 🚧 Animal-mediated seed dispersal (moved seeds germinating elsewhere) —
  ✅ for bird endozoochory specifically (`SeedEndozoochory`, a robin eating
  fallen fruit and later planting a sapling elsewhere, see
  [flora.md](flora.md#bird-endozoochory-swallowing-the-seed-not-just-carrying-it));
  ⬜ for ground herbivores/omnivores, which still only get the food-energy
  half of frugivory, not a dispersal role.
- ✅ Seasonal forcing of phenology by a real calendar/season variable —
  `season_cycle.gd` scales fruiting warmth (see [seasons.md](seasons.md)).
- ✅ Mice/horses added to the herbivore species roster — new `mouse_shape`
  silhouette family plus `horse`'s reuse of `deer_shape`
  (`procedural_animal_sprite.gd`), stats/diet in `creature_info.gd`, wired
  into `creature_renderer.gd`'s `HERBIVORE_SPECIES_POOL_BY_BIOME` (mouse in
  every non-ocean biome, horse in grassland/desert).
- ✅ Wolf/sheep added to forest's roster — forest's own named predator
  (joining lynx/predator/bear, not replacing them) and its real prey (see
  this doc's own "Forest gets its own named predator" section above): stats/
  diet in `creature_info.gd`, `AnimalAnatomy` profiles (wolf's pre-existed;
  sheep's is new), procedural color/shape fallback in
  `procedural_animal_sprite.gd`, wired into `creature_renderer.gd`'s
  `PREDATOR_SPECIES_POOL_BY_BIOME`/`HERBIVORE_SPECIES_POOL_BY_BIOME` forest
  entries, and real illustrated art in `illustrated_animal_sprite.gd` via a
  new per-sheet `"magenta_keyed"` chroma-key pass (own copy of
  `IllustratedStoneSprite`'s despill logic) for their chroma-keyed-magenta
  source sheets.
- ✅ Ambient-flyer tier (butterflies, songbirds) — `ambient_flyer_movement.gd`
  (configurable flutter/glide), `procedural_butterfly_sprite.gd`/
  `procedural_bird_sprite.gd`, `ambient_flyer_renderer.gd` (biome-gated,
  decorative/capped, no population sim), wired into
  `EarthChunkManager`'s load/unload lifecycle.
- ✅ Soil-fauna tier and the first songbird feeding behaviour — a per-chunk
  earthworm population driven by live weather moisture and soil temperature
  (`earthworm_patch.gd`, `WeatherModel.soil_moisture`), a per-species flyer
  diet table (`flyer_diet.gd` — robins eat worms, sparrows do not), a pure
  seek/descend/peck/resume state machine (`ground_forage_behavior.gd`), worm
  and head-dipped-bird art (`procedural_worm_sprite.gd`,
  `ProceduralBirdSprite.generate_pecking_image`), wired live through
  `EarthChunkManager` (`worms_near`/`take_worm_at`/`step_worms`) and
  `World._process`. Closes the insectivore half of the songbird gap noted
  above. See [soil_fauna.md](soil_fauna.md).
- ✅ Fish-eating-bird piscivore mechanic, hooked into the aquatic model's
  harvest term — `piscivore_bird_behavior.gd` (pure cruise/dive/grab-or-
  miss/ascend/cooldown state machine), `piscivore_bird_marker.gd`/
  `piscivore_bird_renderer.gd` (water-gated kingfisher spawn), calling the
  same `EcosystemSimulation.record_catch` the player's rod uses via
  `EarthChunkManager.fish_population_near`/`record_fish_catch_near`.

## Simulation runs at the rate the player can perceive

The world holds far more living things than the screen shows: 484 ambient
flyers and 25 animals were counted around one player, spread across the 3x3
chunks (96x96 tiles) kept loaded, while the camera frames about 20x11 tiles.
Running every one of them sixty times a second is most of a frame's CPU spent
on things nobody is looking at.

Creatures inside a radius that comfortably covers the screen update every
frame — anything visibly moving must move smoothly. Beyond it the rate eases
off with distance to a floor of a couple of updates a second. Eased rather
than stepped, so an animal walking toward the player speeds up smoothly
instead of changing gear at a threshold, the same reason the flee and caution
radii are ramps.

This changes the RATE, never the behaviour: each update is handed the time
accumulated since the last one, so a distant butterfly ages, forages and
travels exactly as far as a near one. It simply does so in fewer, larger
steps, at a distance where nobody can see the difference. The same principle
as drawing decoration only where it can be seen, applied to simulation.


## Courtship, and where births come from

Reproduction used to be a number going up. Animals of the same kind now
**notice each other, dance, and sometimes mate** — so a population growing is
something the player can watch happen rather than something they infer from
there being more deer than yesterday.

- **Same kind only, and only nearby.** Two animals of one species within a
  short radius may pair off. A monarch and a swallowtail share a meadow, not a
  lineage.
- **They circle each other.** Leader and follower orbit a shared midpoint on
  opposite sides, so a pair reads as two animals interacting rather than two
  sprites overlapping. Neither sends the other a message: both compute who
  leads, and whether they mated, from the same two instance ids, which is also
  why a partner vanishing mid-dance is harmless.
- **A meeting is not a pregnancy.** Most dances are just a dance.

### On real time, and why it is so slow

The whole cycle runs on **wall-clock** time, at the scale the design asks for:
about a day before a pair will mate, two before there are eggs, three before
they hatch, and a week before the young are grown.

These are far longer than any play session, and that is the point. A player who
parks in a meadow for an afternoon does not get to farm butterflies — they see
courtship, and if they come back tomorrow they might see the result. The
population work happens where it belongs: in the aggregate model that runs
across whole regions whether anyone is watching or not.

The first version ran courtship on a forty-second cooldown and produced a
flying adult immediately. Measured, that added a butterfly every few seconds —
a population explosion wearing a nature documentary's clothes.

### The two fidelities are one population

This is the part that makes the whole thing honest rather than decorative.
Away from the player, a region's population is a **number that grows
logistically**. Near the player, **actual animals** court, mate and produce
actual offspring. Those are the same population seen at two resolutions, not
two separate worlds, so:

- An individual birth in front of the player **raises the region's aggregate**
  (`EcosystemSimulation.record_birth`), or a herd the player watched grow would
  evaporate the moment the chunk unloaded, while the off-screen model went on
  breeding a range that was already full.
- A birth **cannot push a region past its carrying capacity**. The land decides
  the ceiling, not how long somebody stood and watched.
- Only **grown** animals court, and a chunk holds only so many. A population
  with births and no bound only ever goes one way — which is exactly how the
  deer explosion started.


## A region remembers, and animals cross between regions

Two properties make the aggregate model a simulation rather than a
decoration: what happens to a region **lasts**, and regions are **connected**.

### Persistence

A chunk's land ecology — herbivores, predators, vegetation — is written to
disk when it unloads and restored when the player comes back, in a later
session as much as a later minute.

Before this only *fish* survived a restart. Everything on land lived in an
in-memory record, so quitting reset every region to a freshly-seeded
population at full carrying capacity: a valley the player hunted out was full
again next launch, and a herd they had spent an evening watching grow was
simply gone. On a life cycle measured in real days (see the courtship section
above, where a newborn takes a week to mature) that made the whole timescale
meaningless — nothing could ever live long enough to reach the next stage.

The saved stamp is **wall-clock** time, so being away actually means
something: a real hour away advances the region by an ecological day, through
the same catch-up model an in-session unload uses, capped at a season's worth
because logistic growth converges anyway and integrating a decade of it is
arithmetic nobody can see.

"Never saved" and "saved as empty" are deliberately different: a region really
can be hunted down to nothing, and re-seeding it would quietly undo the
player's effect on the world.

### Migration

Regions are not sealed jars. Each step, animals flow between orthogonally
adjacent regions down the gradient of **surplus over carrying capacity** — a
crowded range spills into an emptier neighbour, at a rate that makes migration
the slow term that reshapes a map over seasons rather than one that flattens
every region to the same density overnight.

This is what lets a hunted-out valley repopulate from the hills rather than
from nowhere, and it is capped from both ends: a region can never export more
animals than it has, and the logistic step that follows holds every region to
what its own land supports.

## A kingfisher hunts

The fish-eating bird used to cruise on the ordinary ambient wander and dive
only when that wander happened to carry it over water with fish in it. A bird
whose territory was inland essentially never fished at all, and after a dive it
held its horizontal position through the ascent and an eight-second cooldown,
which read as a bird stuck in place.

It hunts now, in the shape a real kingfisher does:

1. **Look for a fish** within its hunting range and fly to it, rather than
   waiting for one to drift underneath.
2. **Hover** over it — the signature kingfisher beat, and mechanically the
   thing that makes the strike readable. Without it the dive is over before the
   player registers that anything is happening.
3. **Strike**, which mostly misses. A kingfisher is not a guaranteed predator.

Both outcomes are things the player can see, which is the whole point:

- **Caught**: the bird rises above its cruise line with the fish visibly in its
  beak, carries it for a couple of seconds, and swallows it. The fish is really
  taken from the world and the region's aquatic population really goes down —
  the same `record_catch` the player's own fishing rod calls.
- **Missed**: the fish that got away actually gets away, bolting in a fast
  dash quite unlike its usual meander -- but still *through* the same
  shore-clearance logic every fish moves by. The first version moved a
  startled fish directly and skipped that logic, so it shot out of the water
  and flopped across the grass, with the bird then calmly following it onto
  land to eat it. A panicking fish still cannot leave the water.

The bird holds onto the **specific fish it aimed at** from the moment it starts
hovering, and hovers over that fish rather than over a fixed point. Resolving
the strike against "whatever is nearest now" instead meant the target had swum
on during the hover and the dive -- a second or two of swimming -- so the grab
found nothing, no fish appeared in the beak, and the bird went off to strike at
some other fish later.

## Flying things draw above the ground

Flowers, grass, flyers and the player all sort by Y in one tree, and a flower is
anchored at its stem **foot** so it can sort against the player the way a tree
does. A butterfly hovering at the blossom is higher on screen — a *smaller* y —
than the flower it is visiting, so it sorted behind the bloom and disappeared
into it.

Y-sorting cannot resolve that, because the two are answering different
questions: the flower's sort position is where it is **rooted**, and the flyer's
is where it is **flying**. Being airborne is the answer, so flyers carry a
raised z-index and draw over ground clutter regardless of Y.

## How long a day is

**Four real hours**, defined once in `SeasonCycle.SECONDS_PER_DAY`, with the
year derived from it: 48 days, so eight real days to a year and two to a
season. It was 25 seconds, implied by a 20-minute year.

This is the clock the world's slow biology is measured against -- how often a
kingfisher eats, how long a tree takes to come round to fruit -- and it puts
those on a scale a player experiences *across* sessions rather than within one,
alongside the life cycle's own real-day timings.

**Weather deliberately does not follow it.** Weather used to roll once per day,
which at 25 seconds a day meant constant change; at four hours it would lock a
whole session into one sky, so a player who logged in during rain would see
nothing but rain. It has its own, much shorter period. Real weather turns over
within a day anyway.

## A kingfisher gets full

The bird hunted continuously: strike, wait out a cooldown, strike again,
forever. Nothing about it was ever full, so it would work a pond until there
was nothing left in it -- and the fish it takes are real, out of the same
population the player fishes from.

Two rules hold it back, and both are needed:

- **Appetite.** A couple of fish across an in-game day, and simply not
  interested in between.
- **Giving up on a poor patch.** Even a *hungry* bird leaves water that has
  been worked below a quarter of what it could support, the way a real predator
  abandons a patch that has stopped paying. Appetite alone only slows the
  stripping down; this is what actually stops a pond being emptied, because it
  lifts the pressure exactly when the population can least afford it.

A bird that is not hungry is not an idle bird. It patrols its territory, perches
and digests, or carries material to a nest site -- picked per bird, so a river
does not look choreographed.
