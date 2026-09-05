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
exists yet for this fruit/nut case to create the disperser-vs-predator
tension [flora.md](flora.md)'s DNA loop describes — both remain open
extensions here.

A seed predator DOES now exist for the other half of bird granivory: a
sparrow eating bare ground seed (flower/grass, not fruit) destroys the large
majority of what it eats rather than always dispersing it (see
[flora.md](flora.md#bird-endozoochory-flowers-spread-where-birds-go) and
`SeedEndozoochory.GRANIVORY_CONSUMED_CHANCE`) — real predation, closing that
gap for ground seed specifically while leaving it open for fruit/nut seed.

## Animal bioenergetics and reproduction

Real animals only reproduce when their body condition supports it — starving
animals don't breed. Each creature carries an **energy/condition** value that:

- **rises** when it eats (fallen fruit, grazing, or — for predators — prey),
- **decays** slowly over time (basal metabolism),
- and **gates reproduction**: a creature reproduces only when it is both
  **healthy** (high health fraction) and **well-fed** (energy above a threshold),
  and then only after a **refractory cooldown** (real inter-birth interval).

That gate (`AnimalReproduction.can_reproduce`) is a **precondition**, not the
whole story: an eligible creature does not spawn young by itself. It has to
find a mate — see "Land-mammal courtship" below, the walking counterpart to
the pollinator dance a few sections down. Only once a real, two-partner
courtship completes does an offspring actually appear (individual-scale
birth), paying an energy cost on both sides. Away from the player the same
effect is captured by the aggregate logistic growth term.

### Land-mammal courtship: a walk, not a solo spawn

The first version of this let a single eligible creature spawn a copy of
itself, gated only by crowding and carrying capacity — there was no mate, no
pairing, no courtship of any kind, for anything walking on legs. Pollinators
got a real courtship dance (see "Courtship, and where births come from"
below) from early on; land mammals didn't, because a tight synchronized orbit
built for a flying insect looks wrong for a walking quadruped — the same
problem that keeps that dance off birds (`Courtship.dances()`).

`MammalCourtship` (`src/gameplay/mammal_courtship.gd`) is the grounded
equivalent: two matched individuals **walk toward each other, then stand
together for a real duration**, before the pairing resolves. It deliberately
reuses `Courtship`'s pairing *primitives* — `can_pair`, `pair_seed`, `mates`,
`leads` are already id-based and species-agnostic, so "which two
individuals, who leads, did it take" resolves the same way regardless of
body plan — while replacing only the pollinator-specific parts (the orbiting
`dance_offset` motion, and the `DANCING_SPECIES` gate) with a land-appropriate
shape:

- **Pairing still requires AnimalReproduction's own gate, PLUS a nearby
  partner.** `World._pair_up_courtships` only pairs two creatures that are
  each individually eligible (energy/health/cooldown) AND stand within
  `NEIGHBOUR_RADIUS_PX` of each other — the same "right here" locality the
  crowding check below already uses. No eligible same-species neighbour in
  range means no courtship and no offspring; there is no solo fallback.
- **Among the neighbours actually in range, the creature prefers the more
  attractive one, not just the closest one.** `MammalCourtship.
  most_attractive_partner_index` still applies `NEIGHBOUR_RADIUS_PX` FIRST —
  a highly attractive mate three chunks away is not reachable, so distance
  gates the candidate pool exactly like the plain-nearest selection it
  replaces — and only THEN ranks whoever survives that filter by
  `AnimalFitness.mate_attractiveness` scored against the creature's own
  phenotype. Both phenotypes come from `AnimalFitness.phenotype_for`, keyed
  off each individual's own `wander_seed` (already on `CreatureMarker`, so
  nothing new has to be stored per-creature) — this is `AnimalFitness`'s
  first real caller anywhere in the game. This is a bounded nudge to
  candidate selection, not a redesign of it: the tuned "who's even in range"
  baseline (`NEIGHBOUR_RADIUS_PX`) is untouched, only the tie-break rule
  among whoever already qualifies changes.
- **The pair is a real behaviour STATE, not a background timer.**
  `CreatureBehavior`'s decision tree gets a `court` intent, ranked just above
  ordinary wandering and below every survival need (flee/attack, thirst,
  hunt, hunger) — a starving or thirsty animal does not stop to court, but an
  otherwise-idle paired one does. While courting, a creature visibly walks
  toward its partner (`MammalCourtship.should_approach`) and then simply
  stands near it once close enough (`LINGER_RADIUS_PX`) — the two read as an
  interacting pair, the same design goal the pollinator dance has, just
  expressed as a walk-and-linger instead of an orbit.
- **The duration has to actually elapse, together.** `World._advance_
  courtships` ticks both partners' shared timer once per
  `REPRODUCTION_INTERVAL`; only once `MammalCourtship.courtship_complete`
  is true for a pair does `_resolve_courtship` run — mirroring
  `Courtship.leads` so exactly one side of the pair resolves it, never both.
- **Viability is re-checked at the end, not just the start.** Crowding and
  carrying capacity can change during the linger window — a clearing that
  filled up *while* a pair was courting must not still produce young just
  because they started before it was full (`World.courtship_still_viable`,
  the same "dozens of deer" bug the crowding check below was already built
  to prevent, re-applied at resolution time). The pair must also still be
  near each other; either partner may have wandered off, died, or been eaten
  during the wait.
- **A meeting is still not a pregnancy.** The mating roll itself is
  `Courtship.mates` — the same 25%-of-meetings chance pollinators use,
  reused directly rather than inventing a second number for mammals.

### Mammal offspring grow up, live-born

A mammal offspring used to appear at full adult size the instant courtship
resolved. `MammalGrowth` (`src/gameplay/mammal_growth.gd`) is the mammal
counterpart to `LifeCycle`'s pollinator growth stage — deliberately NOT
`LifeCycle` reused wholesale, the same call `MammalCourtship` itself already
made for not reusing a pollinator-shaped module when the underlying biology
genuinely differs. A mammal is born **live**: there is no egg stage and no
separate hatch event, so the shape is simpler than `LifeCycle`'s — just a
starting size and a growth curve to full size:

- **A newborn starts at `NEWBORN_SCALE` (0.4× adult), never zero.** Grounded
  on a precocial ungulate newborn — a fawn or foal, the majority of this
  game's breeding-eligible land mammals, stands and moves within hours of
  birth already a real, substantial fraction of adult size. This knowingly
  overstates an altricial newborn (e.g. a lynx kitten, born blind and
  comparatively tiny) — a deliberate simplification, not a second
  predator-only constant.
- **Full size takes `mature_seconds_for(species)` — a per-species SIZE TIER,
  not one flat duration.** A mouse matures in real weeks; a bear takes real
  years — reproducing that gap literally would put a bear's whole "watch it
  grow up" arc outside any plausible player return visit, but flattening it
  to one number (this module's own earlier design) erased a real, visible
  difference the game already has the data for. Duration is now a function
  of `CreatureInfo.MAX_HEALTH_BY_SPECIES` — the SAME size/toughness signal
  every other per-species stat in this codebase already keys off — split
  into three tiers rather than one duration per exact species, so the
  boundaries stay a small, testable set of numbers instead of 21 individually
  eyeballed ones:
  - **Small** (`max_health < 15.0`: mouse, squirrel, both snakes) — grounded
    on a real mouse reaching sexual maturity in about 6–8 weeks. 30 real
    days (~4.3 weeks) — exactly the OLD flat constant's value, which in
    hindsight was really only calibrated for the roster's smallest/fastest
    species.
  - **Medium** (`15.0 ≤ max_health < 40.0`: deer, horse, boar, wolf, lynx,
    and most of the roster) — grounded on real mid-size herbivores/mid
    predators: wild boar ~8–10 months, deer ~1.5 years, horses and wolves
    ~2 years. 90 real days, 3× the small tier, a proportionally-compressed
    stand-in for that whole "many months to ~2 years" real band. Lynx lands
    here rather than with the apex predators below — a real lynx is built
    more like a large dog than a lion, and matures faster (~1–3 years,
    commonly ~21 months) than a real apex predator does, so keying off
    size/toughness rather than predator-vs-herbivore role gets this one
    right.
  - **Large** (`max_health ≥ 40.0`: lion, bear) — grounded on real apex
    predators commonly needing 3+ years (up to 4–8 for some brown bear
    populations) to reach full sexual maturity, the slowest real category on
    the roster. 180 real days, 2× the medium tier, 6× the small tier —
    preserving the real small < medium < large ordering while staying inside
    a timeframe a returning player can still see progress in, the same
    "compressed but liveable" trade the flat constant always made, now
    honoring the real relative gap between tiers instead of collapsing it.
- **Wired at three points**, `size_scale_at`/`is_mature` now taking the
  individual's `species` alongside its age. `CreatureMarker.begin_life()` —
  called from `World._resolve_courtship` on the newly spawned offspring,
  mirroring `AmbientFlyerMarker.begin_life` exactly — tags the offspring
  with `age_seconds = 0.0` and immediately shrinks its rendered scale.
  `CreatureMarker._apply_action_scale` multiplies the species' own normal
  scale for the current action by `MammalGrowth.size_scale_at(age_seconds,
  species)` every frame while immature, converging back to the ordinary
  scale once grown — the same "species scale × growth fraction" shape
  `AmbientFlyerMarker._step_growing` already uses for pollinators.
  `CreatureMarker.can_reproduce()` additionally requires `MammalGrowth.
  is_mature(age_seconds, species)`, alongside (not instead of) the existing
  energy/health/cooldown gate, so a newborn cannot pair off the moment it is
  born.

**A growing juvenile now has two real behavioural differences from an adult
of its species**, on top of the can't-court gate above:

- **Stays near home.** `CreatureWander.direction_at`/`step_position` take an
  optional `radius` parameter (default `WANDER_RADIUS`, so every adult caller
  is unaffected). `CreatureMarker._wander_radius()` scales it down by
  `MammalGrowth.size_scale_at(age_seconds, species)` — the same already-
  computed 0.4→1.0 growth fraction used for the rendered scale, reused here
  rather than inventing a second tunable — so a newborn wanders within
  roughly `NEWBORN_SCALE × WANDER_RADIUS` of its `home` (its actual birth
  site, for a courtship-born individual — `home` needed no new tracking) and
  the range widens smoothly as it grows, reaching the ordinary adult
  `WANDER_RADIUS` exactly at maturity.
- **More skittish, never fights.** `CreatureBehavior.decide`'s context now
  carries an `is_mature` key (`CreatureMarker` supplies it every frame from
  `MammalGrowth.is_mature`, the same way `is_courting`/`partner_position`
  were added). `_will_fight` returns `false` outright whenever `is_mature` is
  false, regardless of temperament or health — a real juvenile of even an
  aggressive-tempered species (boar, bear, lion) flees a threat rather than
  standing its ground; missing the key at all (every context built before
  this change) still defaults to mature, so behaviour is unchanged wherever
  it isn't explicitly set.

Left out of this pass on purpose: no reduced perception/sense range (a
juvenile senses threats/food/water exactly as far as an adult), no
parent-following behaviour — just the tighter home-anchored wander range and
the never-fights gate above.

**A juvenile's `age_seconds` now DOES persist across a chunk unload
(2026-08-26)** — `src/world/growing_juveniles.gd` (`GrowingJuveniles`),
wired into `EarthChunkManager._save_growing_juveniles`/
`_restore_growing_juveniles` right alongside `KeptAnimals`' own
`_save_kept_animals`/`_restore_kept_animals`. This used to be left out under
this doc's own two-fidelities boundary (see the note just below) on the
theory that no individual-fidelity creature state persists across an
unload — but with mammal maturity now a real 30–180-real-day window (see
`mature_seconds_for` above), almost certainly longer than most chunks stay
loaded, that boundary meant a juvenile would essentially never be seen
actually reaching adulthood in one sitting. See the fidelity-boundary note
below for exactly what is now the one deliberate exception to that rule,
and what still isn't persisted (an in-progress courtship PAIRING specifically,
a smaller and separate piece of this same gap).

**Pollinator eggs are now a distinct rendered entity.** This used to be a
named gap: from the moment a courting pair's offspring spawned until
`LifeCycle.HATCH_SECONDS`, the rendered sprite was simply the ADULT insect's
own procedural silhouette scaled down to `HATCHLING_SCALE` — a tiny adult,
not anything egg-shaped, for the entire COURTING/MATED/EGG span (the
JUVENILE-onward "growing tiny adult" look, from `HATCH_SECONDS` to
`MATURE_SECONDS`, was already correct and is unchanged). `ProceduralEggSprite`
(`src/rendering/procedural_egg_sprite.gd`) draws a small, pale, plain oval —
not an insect silhouette at all — using the same house shading technique as
every other procedural sprite here (`PixelForm`'s lit-spheroid shading
through `PixelRamp`, `PixelPalette`'s shared outline). `AmbientFlyerMarker.
_animate_wings` shows it (via a renderer-assigned `egg_frame`, built for
every marker in `AmbientFlyerRenderer._build_marker`) for as long as
`LifeCycle.stage_at(age_seconds) < LifeCycle.STAGE_JUVENILE`, then falls
straight back to the existing scaled-adult sprite with no other change.
**One shared egg shape/color for every pollinator species**, deliberately,
not a species-specific egg: a real butterfly/bee egg is not identifiable by
species to the naked eye either, and the point of this sprite is legibility
("this is an egg, not a bug yet") rather than species identification — that
job is already done once the animal hatches into its recognizable tiny-adult
juvenile. Left unchanged on purpose: the offspring's *behaviour* during this
span (it still flies/forages/wanders exactly as it did before this pass) —
only what it looks like changed, since the wall-clock stage timing this
section describes was never meant to gate movement, only rendering and the
can't-court-yet rule above.

**Revisited (2026-08-26), now that mammal maturity is a real 30–180-real-day
window**: a juvenile's `age_seconds` is exactly the kind of individual-
fidelity creature state this doc used to say never survives an unload — but
it is now the ONE deliberate exception, via `GrowingJuveniles`
(`src/world/growing_juveniles.gd`). That module's own doc comment explains
at length why this does not reopen the "two fidelities" pillar above: it
only ever covers markers that are ALREADY individually rendered at the
moment of unload — a set already bounded globally (`World.
MAX_LIVE_CREATURES`) and per-species-per-chunk (`CreatureRenderer.
MAX_MARKERS_PER_SPECIES`) — narrowed further still to whichever of those are
not yet mature (`GrowingJuveniles.is_worth_persisting`). That is a strict
SUBSET of an already-bounded population, not the unbounded per-animal save
this pillar rules out for an ordinary wild herd; a mature individual drops
back out of the file on its very next save and is exactly as interchangeable
as any other wild adult again.

Everything else stands exactly as before: hunger, thirst, energy, an
in-progress hunt, and a courting pair's in-progress linger timer (the
PAIRING specifically — which two individuals, how long they have already
stood together) still do not persist across an unload; only aggregate
populations do, by the same "two fidelities" design. A courting pair's link
is a LIVE node-instance reference (`CreatureMarker._courting_partner_id`,
read back via `instance_from_id`), which cannot itself be written to disk —
reconstructing it after both individuals independently respawn would need a
new stable cross-reload identity nothing in this codebase has yet, so
pairing quietly ends on unload exactly as it always did. This is a real,
named simplification, not a silently-dropped one: once both individuals
reload — now at their real preserved age, via `GrowingJuveniles` — each is
free to re-pair with a new eligible partner once mature again, same as
before, just no longer forced to restart its own growth clock too.

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
- **A bout is slower while snow is actively falling.** See
  [weather.md](weather.md#weather-feeds-creature-behaviour) --
  `GrazerForaging.snowing` scales the head-down duration
  (`GRAZE_SECONDS`) only, not the walk between bites or the give-up
  timeout: a grazer is not just cropping a tuft any more, it is working
  through what is landing on top of it to keep its muzzle in the grass.

## Biome-specific species composition

Pillar 1 ("boars live where boars thrive") extends beyond population *size* to
population *composition*: which species show up at all should depend on the
biome, not just how many individuals do. A promoted individual's species is
chosen from a **per-biome species pool** (grassland/forest/desert/tundra/
rainforest/mountain each have their own herbivore+predator pair; unmapped
biomes fall back to a generic pool), keyed off the chunk's **dominant
biome** — the most frequent biome among its cells, since a chunk can straddle
more than one.

Those pools no longer contain the anonymous `"herbivore"`/`"predator"` ids.
Those were never species: they were this project's own unnamed stand-ins —
`ProceduralAnimalSprite.SPECIES_SHAPE_FAMILY` maps `"herbivore"` to
`deer_shape` and `"predator"` to `wolf_shape` — from before deer and wolf
existed as real named species with real illustrated art. Naming those two did
not remove the stand-ins from the pools, so a promoted individual could still
reach the creature panel as a nameless "Herbivore Lv.5" standing beside a
"Boar Lv.1" (`CreatureInfo.display_name` is just the species id capitalized).
They are now retired from **spawning**: grassland's dominant grazer slot goes
to deer (what `"herbivore"` was always drawn as), grassland's dominant
predator slot to jackal, and every other biome simply drops its single
placeholder entry, each already having a dominant named specialist plus named
fillers. The generic fall-back pool for an unmapped biome is likewise named
now (`deer`/`boar`, `lynx`/`jackal`). The two ids **remain as data keys** and
must not be deleted: `AnimalAnatomy.profile_for` falls back to
`_PROFILES["herbivore"]` and `ProceduralAnimalSprite` resolves any unknown
species to `"herbivore"`, so they are the never-crash-on-an-odd-id default.
The dev console's `/spawn` still defaults to `"herbivore"` — an explicitly
debug path, deliberately left spawnable on demand. Every species reuses one of 4 hand-drawn silhouette shapes
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

### Squirrel: a genuine 22nd species, and the fruit/nut seed-predator flora.md was missing

Squirrel is a real roster species, not a reskin of mouse or anything else —
its own `AnimalAnatomy` body plan, its own `ProceduralAnimalSprite` colour,
its own `CreatureInfo` stats, and its own small ecological mechanism
(`SquirrelNutCaching`). It closes [flora.md](flora.md)'s last open
disperser-vs-predator gap: a real seed predator for fallen tree NUTS,
mirroring the ground-seed predator (sparrow) pass this same session already
built for grass/flower seed.

- **Real-world grounding**: a real tree squirrel is a forest/woodland
  specialist (unlike mouse's near-ubiquitous generalism) whose food is fallen
  hard-shelled nuts, not fleshy fruit — and it is famous for two things: real
  scatter-hoarding (gathering more than it eats on the spot, burying the
  surplus, and only recovering a fraction of what it buried — which is
  exactly how a lot of real wild nut trees actually get planted) and
  speed/acrobatics (leaping tree to tree, outrunning ground predators).
- **Roster**: herbivore-role (`is_predator = false`, calm temperament, flees
  rather than fights — same category as mouse), `Forager` diet (matching
  mouse's own label), joins the forest biome's herbivore pool ONLY (not
  every biome the way mouse does) — see `CreatureRenderer.
  HERBIVORE_SPECIES_POOL_BY_BIOME`.
- **Stats**: health sits between mouse (6.0, the roster's smallest/frailest)
  and the generic herbivore baseline (20.0) — small, but notably bigger and
  more robust than a mouse. Stamina is deliberately HIGH (35.0, above even
  mouse's own already-high 20.0), a real-world-grounded agility stat for a
  species famous for speed and acrobatics.
- **Body plan**: `AnimalAnatomy`'s `"squirrel"` profile is small and
  short-legged like mouse's, but bigger (`world_scale` 0.45 vs mouse's
  0.35), and defined above all by a large `TAIL_BUSHY` tail that is
  proportionally LONGER relative to its own body than any other profile in
  the roster, including mouse's own already-long (but thin, cord-like)
  tail — a squirrel's tail is one of its most distinctive real-world
  features. Reuses mouse's own `"mouse_shape"` silhouette family in
  `ProceduralAnimalSprite` rather than a 6th hand-authored bitmap (its own
  base coat colour keeps it visually distinct) — unlike mouse, which needed
  a new family because nothing else read as a small round-bodied rodent at
  any scale, a squirrel genuinely IS that same body plan, just bigger; what
  reads as distinctly "squirrel" is the tail override, painted procedurally
  on top of the shared bitmap, not a different silhouette.
- **Mechanism — nut scatter-hoarding, the fruit/nut seed-predator gap
  flora.md was still missing**: a squirrel that passes near a fallen tree
  NUT (`TreeSpecies.is_nut` — pine/acorn/hazelnut/walnut, not cherry/apple)
  picks it up and carries it a short ground distance while going about its
  business, exactly the same find→carry→resolve shape `SeedCaching` already
  established for a mouse's grass seed (`EarthChunkManager.
  _step_squirrel_nut_caching`, gated to `species == "squirrel"` specifically,
  wired to the SAME `fruit_near`/`take_fruit_at` world API any other land
  forager already eats fallen fruit through). Once it has carried the nut
  far enough, the outcome resolves: mostly it just eats the nut outright
  (`SquirrelNutCaching.NUT_CONSUMED_CHANCE` — 0.7, real-world-grounded on
  scatter-hoarding studies where caching is the minority outcome for a
  handled nut, and deliberately its own constant rather than a reuse of the
  sparrow's `GRANIVORY_CONSUMED_CHANCE` — 0.8 — since deliberate hoarding
  effort is a stronger dispersal force than a bird's incidental gut-passage
  survival of a tiny bare seed), but sometimes caches it into a brand-new
  sapling via the SAME tree-seed sink robin's own fruit dispersal already
  uses (`try_plant_seed_at`, gated to forest/rainforest). Fleshy fruit
  (cherry/apple) is deliberately untouched by this mechanism — a squirrel
  finding one just eats it like any other fruit-eating forager via the
  ordinary, ungated `GrazerForaging` `FOOD_FRUIT` path, nutritionally a
  disperser-or-nothing exactly as before this pass.
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

Naming the wolf did not by itself finish the job: the `"predator"` placeholder
stayed in every biome's pool for a long time afterwards and kept spawning
alongside the named species. It is retired now (see "Biome-specific species
composition" above). Grassland's freed dominant-predator slot went to
**jackal**, not to wolf — real golden jackals are an open grassland/steppe
canid across Eurasia and Africa, and wolves stay **forest-exclusive** here by
design, as this section specifies and `test_forest_promotes_wolves_alongside_
their_sheep_and_deer_prey` asserts. Moving wolves onto grassland would be a
deliberate reversal of that design, not a placeholder cleanup.

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

- **Butterflies** are pure ambient wildlife: real pollinators, but their
  visits do not feed back into flower seed-set or tree fruit-set (see
  [flora.md](flora.md)'s pollination feedback, which bees alone now do —
  real fruit trees' primary pollinator). Movement is a fluttering,
  low-speed, frequently-changing-heading drift (visually distinct from a
  bird's straighter glide), confined to no particular target — just "make
  a meadow feel alive." Biome-gated to grassland/forest/rainforest (real
  butterflies are a warm/flowering-habitat presence; excluded from desert/
  tundra/mountain/ocean as implausible) — but that tier-wide gate is no
  longer the whole story; see "Where a flyer actually lives" below.
- **Songbirds** are the same ambient tier, biome-gated tier-wide to forest/
  grassland/rainforest and then range-gated per species (see "Where a flyer
  actually lives" below), with their own glide-and-perch movement pattern (straighter
  runs between heading changes than a butterfly's flutter). Real songbirds
  are largely insectivore/granivore. The **insectivore half has a real
  feeding model** — see [soil_fauna.md](soil_fauna.md): a per-chunk earthworm
  population that surfaces with soil moisture and warmth, a per-species diet
  table, and a robin that descends onto a worm, sits down, pecks it, and
  actually removes it from the chunk. The robin's diet also includes a
  **frugivore half** — fallen tree fruit
  ([flora.md](flora.md#bird-endozoochory-swallowing-the-seed-not-just-carrying-it)),
  eaten through the same land/sit/peck cycle as a worm, with a real
  consequence beyond feeding: a swallowed seed gets carried and planted
  elsewhere, a genuinely new disperser mechanism. Sparrows have their own
  **granivore half**, the same shape as the robin's worm hunt but against
  ground seed cells instead of burrows.
  **Update — robin/sparrow now have a real aggregate population, not just
  feeding behaviour:** `RobinPopulationModel`/`SparrowPopulationModel`
  (thin `PopulationModel` wrappers, the same generic logistic-growth-plus-
  migration shape `HerbivorePopulationModel`/`PredatorPopulationModel`/
  `AquaticPopulationModel` already share) give `EcosystemSimulation` a real
  per-chunk `robin_population`/`sparrow_population`, with carrying capacity
  derived from each bird's own real food-density signal — robin from
  `EarthwormPatch.worm_cells().size()`, sparrow from the combined
  `FlowerPatch`/`TallGrass` `ground_seed_cells().size()` — reported in via
  `EcosystemSimulation.update_worm_density`/`update_seed_density` since that
  density lives in `EarthChunkManager`'s own patch instances, not in the
  static `Chunk` data the aggregate model otherwise derives everything from.
  `AmbientFlyerRenderer.spawn_ambient_flyers` now promotes robin/sparrow from
  that real population (one marker per rounded unit, capped for perf —
  `MAX_ROBINS_PER_CHUNK`/`MAX_SPARROWS_PER_CHUNK` — mirroring
  `CreatureRenderer.marker_count_for`'s exact shape) instead of a flat
  `MIN..MAX` roll: a worm-rich chunk now genuinely hatches more robins, the
  way a flower-rich chunk hatches more pollinators. **Deliberately still
  missing**: an explicit death-on-eat term. Eating one specific worm/seed
  does not instantly remove one specific bird — population responds to food
  *density* through carrying capacity only, the same fidelity gap
  herbivore/predator/fish lived with until their own `record_death`/
  `record_catch` were added. See Open questions below.
- **Fish-eating birds** (heron/osprey-type piscivores) reach into the
  aquatic population model
  ([fishing.md](fishing.md#aquatic-population-model)) the same way a
  player's rod does. Spawn is gated to chunks with water (not a land biome
  pool). Behavior is a small, pure, testable state machine — **cruise**
  (ordinary ambient flight over open water) → **target** (a nearby chunk's
  fish population is above zero, so the bird commits to a dive point) →
  **dive** (a fast, visibly different descent toward the water) →
  **grab-or-miss** (a probability roll, not a guaranteed catch — real
  herons/ospreys miss most strikes) → on a **grab**, the exact same
  `EcosystemSimulation.record_catch` the player's fishing hook now calls
  (see [fishing.md](fishing.md#aquatic-population-model)) fires for this
  bird's catch too, so a heavily-birded cove is measurably fished down over
  time just like a heavily-angled one → **ascend** back to cruise altitude →
  **cooldown** (real birds don't dive continuously; a real digestion/
  re-hunt interval) before it can target again. This closes the loop the
  aquatic model spec already asked for: fishing pressure was previously
  only ever the player; a bird population that's always present on a
  coastline is now a second, always-on mortality source on the same
  aggregate number — exactly the kind of multi-source pressure a real
  fishery actually has.
  **Update — the kingfisher's own presence is now aggregate too:**
  `KingfisherPopulationModel` (same `PopulationModel`-wrapper shape as
  above, structurally identical to `PredatorPopulationModel`) gives
  `EcosystemSimulation` a real per-chunk `kingfisher_population`, with
  carrying capacity derived from the EXISTING `fish_population` — no new
  food-density signal needed on this side, since a kingfisher's prey already
  has an aggregate number. `PiscivoreBirdRenderer.spawn_piscivore_birds` now
  promotes from that population (still capped at `MAX_PER_CHUNK` — a special
  sight, not filling the sky) instead of the flat `SPAWN_CHANCE` die roll it
  used to run regardless of whether the water it hunts actually held any
  fish.

#### Where a flyer actually lives

The aerial tier shipped as a decorative layer and, alone among the creature
categories, never got the per-species range treatment the ground roster got in
"Biome-specific species composition" above: one fixed global pool per group,
gated only by biome name. The visible result was a **Blue Morpho — a
Neotropical rainforest butterfly — fluttering over a German meadow at 52.5°N**,
next to a Monarch, a Nearctic one.

Flyers are now range-gated per species (`AmbientFlyerRenderer.FLYER_RANGE`,
filtered by `_in_range_pool`, the aerial mirror of
`CreatureRenderer._allowed_pool`) on **two** axes rather than one, because
biome alone cannot tell a German meadow from a Kansas one:

- **Biome** — the same biome-name gate as before, now per species. The
  tier-wide `BUTTERFLY_BIOMES`/`BIRD_BIOMES` constants stay (other files refer
  to them by name) and are pinned consistent with the per-species table by
  test, so the two cannot drift apart.
- **Absolute latitude band** — degrees from the equator, so one band covers
  both hemispheres. The chunk's real latitude is derived from the global tile
  row the renderer already receives, through the same
  `GeoCoordinates.latitude_for_tile` / `EarthChunkGenerator.WORLD_HEIGHT_TILES`
  pair the generator itself uses for temperature and biome — so a flyer's range
  is measured against exactly the geography that produced the biome it is
  flying over. Measured at the chunk's middle row, not its corner.

The ranges are real, not invented:

| Species | Biomes | Abs. latitude | Why |
| --- | --- | --- | --- |
| monarch (*Danaus plexippus*) | grassland, forest | 15–50° | Nearctic butterfly of open country; absent from Europe — the reported bug |
| swallowtail (*Papilio machaon*) | grassland, forest | 25–70° | The **Old World** swallowtail: Palearctic, Mediterranean into the subarctic. The swallowtail a German meadow really has |
| blue_morpho (*Morpho* spp.) | rainforest | 0–25° | Neotropical rainforest, inside the tropics |
| bee (*Apis mellifera*) | grassland, forest, rainforest | 0–70° | Near-cosmopolitan |
| sparrow (*Passer domesticus*) | grassland, forest, rainforest | 0–70° | Near-cosmopolitan |
| robin (*Erithacus rubecula* / *Turdus migratorius*) | grassland, forest | 20–70° | Temperate woodland and garden bird in both the Old and New World; not a rainforest species |

Two consequences worth stating plainly rather than discovering later:

- A filtered pool can legitimately come out **empty** (nothing at all can live
  in a 52.5°N rainforest), so the spawn path returns nothing instead of
  dividing by zero on the modulo that picks a species.
- **A German meadow now shows one butterfly species (swallowtail) plus bees,
  where it used to show three.** That is the honest state of the roster, not a
  loosening candidate: the butterfly roster is Americas-heavy. The fix for the
  thinness is a roster *addition* — one genuinely Palearctic species such as a
  peacock butterfly, which is procedural art plus an entry each in the sprite
  tables, `FLYER_WORLD_SCALE`, `FlyerDiet` and `FLYER_RANGE` — not a widening
  of the bands.


### Open questions

- Pollination (butterflies/songbirds feeding vegetation or
  [flora.md](flora.md)'s fruit set) is real and grounded, but has no model
  to hook into yet on either side (no flower/pollen state, no per-species
  feeding need); tracked here rather than invented wholesale in this pass.
  Partly overtaken since: flowers now carry real nectar state that
  pollinators deplete (see [flora.md](flora.md)), and birds now have a real
  per-species diet (see [soil_fauna.md](soil_fauna.md)).
  **Resolved for birds**: eaten worms/seeds now DO affect bird numbers, via
  carrying capacity (see below).
  **Resolved for tree fruit set**: a bee visiting a blossoming apple/cherry
  tree now measurably nudges that tree's yield (`FruitingModel.
  pollination_factor`, `EarthChunkManager.blossoms_near`/
  `record_pollination_visit_at` — see [flora.md](flora.md)'s pollination
  feedback). Still open: the reverse direction, a region light on flowers
  hatching fewer butterflies/bees (pollinator numbers are still purely
  decorative, not fed by what they visit).
- ~~Should ambient flyers eventually graduate to their own lightweight
  aggregate population...~~ **Resolved for songbirds, still open for
  pollinators.** Robin and sparrow now have a real per-chunk aggregate
  population (`RobinPopulationModel`/`SparrowPopulationModel`), carrying
  capacity derived from worm burrow count and combined ground-seed-cell
  count respectively — see the Species roster section above for the full
  wiring. Butterflies/bees remain purely decorative: there is still no
  predation pressure on pollinators to make an aggregate number mean
  anything, unlike birds (which now have a real food-density ceiling) or
  fish (angler + bird harvest).
  **Explicit non-goal kept for this pass**: no death-on-eat term. A robin
  eating one specific worm, a sparrow eating one specific seed, or a
  kingfisher catching one specific fish does not directly remove one
  specific bird from any of these three aggregates — only the region's
  overall food DENSITY, sampled fresh each simulated day, moves the
  carrying capacity these populations grow or decline toward. This is the
  same fidelity gap herbivore/predator/fish briefly had before
  `record_death`/`record_catch`/`record_birth` closed it for them; doing
  the same for birds (an eaten worm/seed/fish instantly culling a
  particular bird near the player, the way a wolf kill already does for
  herbivores) is a real, separate follow-up, not done here.
- ~~Fish-eating-bird population itself is decorative/capped, not
  aggregate...~~ **Resolved.** `KingfisherPopulationModel` gives
  `EcosystemSimulation` a real per-chunk `kingfisher_population`, carrying
  capacity derived directly from the EXISTING `fish_population` (mirroring
  how predator capacity already derives from herbivore population) —
  `PiscivoreBirdRenderer` now promotes a kingfisher from that number instead
  of an unconditional `SPAWN_CHANCE` roll. The death-on-eat non-goal above
  applies here too: a kingfisher's own successful catch already calls
  `EcosystemSimulation.record_catch` against the FISH population (unchanged,
  pre-existing behaviour), but does not itself remove a kingfisher from the
  kingfisher population, nor does a fished-out chunk instantly banish the
  kingfisher standing in it — only the next carrying-capacity recompute does.
- ~~**Persistence/catch-up gap, robin/sparrow/kingfisher**: unlike
  herbivore/predator/fish, these three aggregate populations are NOT wired
  into `EarthChunkManager`'s unloaded-chunk catch-up or disk persistence.~~
  **Resolved.** `ChunkEcologyCatchup.advance` now takes three more state keys
  (`robins`, `sparrows`, `kingfishers`) and two more capacity inputs
  (`robin_capacity`, `sparrow_capacity`) — robin/sparrow step against their
  own independently-supplied capacity, the same shape fish already used
  (their food-density signal lives outside this pure function); kingfisher
  instead mirrors predator, its capacity derived INSIDE `advance()` from the
  freshly-advanced fish population, the same "post-step prey level" ordering
  predator capacity already used for herbivores. `ChunkSerializer.save_ecology`/
  `load_ecology` append `robins`/`sparrows`/`kingfishers` as three more floats
  AFTER `land_health` (old saves default all three to 0.0 via the same
  file-position check `land_health` itself uses). `EcosystemSimulation`
  gained `seed_robin_population`/`seed_sparrow_population`/
  `seed_kingfisher_population`, mirroring `seed_populations`/
  `seed_fish_population`'s exact "install a caught-up value" role.
  `EarthChunkManager._unload_chunk` snapshots all three into
  `_unloaded_ecology`'s in-session record and into the on-disk ecology file
  alongside herbivores/predators/vegetation/land_health;
  `_apply_ecology_catchup` (in-session revisit) and `_apply_persisted_ecology`
  (cross-session revisit) both advance and re-install them the same way they
  already did for herbivores/predators/fish/land_health. A chunk that
  unloads and reloads now resumes the exact robin/sparrow/kingfisher count it
  had when the player left (evolved by however long they were away), and a
  full game-session restart no longer resets these three to a fresh
  bootstrap the way it never did for fish.
- ~~**Fish never actually caught up across a session gap**: `_apply_persisted_ecology`
  fed fish into the same `ChunkEcologyCatchup.advance()` call every other
  population uses, and `advance()` genuinely stepped it forward for the
  elapsed away-time — but the result was never written back via
  `seed_fish_population`, unlike its six siblings just above. A fish
  population left well under capacity across a real multi-day session gap
  therefore came back frozen at exactly its pre-gap value, never having
  caught up at all — the exact opposite of what the "it never did for fish"
  line above meant to say (fish's raw LAST-KNOWN count did survive, via its
  own separate `save_fish_population`/`load_fish_population` file; it just
  never grew or declined for the time spent away).~~ **Resolved**: one
  missing `_ecosystem.seed_fish_population(chunk_coord, float(caught_up.get("fish", 0.0)))`
  call, mirroring the six calls it already sat alongside.
- **Marker top-up is reload-only, not continuous, for these three (new,
  this pass)**: `EarthChunkManager._refresh_creatures` tops up/thins land
  creature and fish MARKERS every periodic ecosystem step so a chunk's
  visible count tracks its aggregate population continuously while loaded.
  Robin/sparrow/kingfisher markers are not part of that pass yet — their
  visible count is set from the aggregate population at chunk load (and
  stays there until the chunk unloads and reloads), even though the
  aggregate numbers themselves keep growing/declining underneath every
  simulated day via `_refresh_bird_food_density`/`EcosystemSimulation.step`.
  A robin population that has genuinely doubled since load will not spawn a
  second visible robin until the player leaves the chunk and comes back.
- **No biogeographic realm axis exists anywhere in the project**, and a
  latitude band cannot substitute for one: a band cannot separate Nearctic
  from Palearctic, so a monarch can still appear on a 40°N Eurasian steppe,
  and the same gap already lets `CreatureRenderer` put camels in American
  deserts and jaguars in African rainforest. Both tiers have the identical
  omission, so closing it once serves both. What it would take: bundling a
  biogeographic-realm/ecoregion raster and sampling it the way
  `EarthElevationSource` samples `assets/data/world_elevation.png` — the only
  real geographic raster shipped today. That is feature-scale work, not a
  filter tweak, which is why the range tables stop at biome + latitude.

### Real illustrated art for songbirds and the kingfisher (2026-09-05)

Four hand-illustrated sheets (`assets/sprites/birds/{sparrow,robin,
blackbird,kingfisher}.png`) replace `ProceduralBirdSprite`'s primitive-shape
generation, the same "real art where it exists, procedural everywhere else"
move `IllustratedAnimalSprite` already made for horse/deer/boar/sheep/wolf.
`IllustratedBirdSprite` is a sibling of that class rather than an extension
of it — birds run through `AmbientFlyerMarker`/`PiscivoreBirdMarker`, not
`CreatureMarker`, so there is nothing to share beyond `SpriteSheetSlicer`
itself (already generic). `AmbientFlyerRenderer._bird_sprite_generator_for`/
`PiscivoreBirdRenderer._sprite_generator` pick it over the procedural
generator whenever `has_species` says yes, at every spawn path (chunk spawn,
courtship offspring, the diorama's `build_bird`) — a chick born in front of
the player gets the exact same real art as every other bird of its species.

**Phase 1 scope only** (see the bird-behavior-overhaul plan): idle,
perched (the same pose as idle in this art — there is no separate
folded-wing rest row the way the procedural generator draws one), flap
(the sheets' takeoff and glide rows concatenate into one 16-frame cycle,
a drop-in match for `generate_flap_textures`' existing contract), and
pecking. Still procedural/unwired: a ground walk/hop row, the kingfisher's
own dive pose (its `PiscivoreBirdBehavior.Phase.DIVING` already exists
behaviorally, just with no dedicated art yet), a display/mating-dance row,
and a singing/tweeting row — none of the sheets' seven-or-eight rows are
wasted, they just don't have a real trigger to attach to until later
phases (walk/dive land with new animation states, court/sing with real
bird courtship). **Blackbird is not yet a spawnable species** — it has a
real `IllustratedBirdSprite` entry (so the slicer is proven against all
four sheets together) but no diet/range/population/pool wiring; that is
its own follow-up.

**The four sheets are not row-for-row identical** — confirmed by looking
at the actual pixels, not assumed from a shared template. Sparrow's sheet
has a dedicated head-down, seed-crumb pecking row. Robin's and
blackbird's sheets do not: the row a shared template would put "peck" at
is their tail-fanned DISPLAY pose instead, and real divider lines bound
every row on both sheets with no gap left over for a missing one.
`generate_pecking_texture` falls back to idle for a species with no
dedicated peck band, the same never-return-nothing shape
`IllustratedAnimalSprite.has_action`'s own fallback chain already uses.
Bands were hand-measured (a throwaway tool: chroma-key the magenta ground
transparent, then scan for real horizontal divider lines — not an even
height/N split, which does not hold on any of the four sheets) and stored
as data in `IllustratedBirdSprite._SHEETS`, never auto-detected at
runtime, matching every existing illustrated sheet's own house rule.

Pinned by `test_illustrated_bird_sprite.gd` (9 tests: species coverage,
real non-blank content, the flap concatenation, the canvas/baseline
invariant, frame caching, and the sparrow-vs-robin/blackbird peck
distinction specifically). `test_ambient_flyer_marker.gd`,
`test_ambient_flyer_renderer.gd`, `test_piscivore_bird_marker.gd`,
`test_piscivore_bird_renderer.gd` and `test_procedural_bird_sprite.gd` all
stay green (255 tests total across the six files) — the art swap changes
no behavioral assertion, only which pixels a bird is drawn with.

**Follow-up, same day: "robins and sparrows are now gigantic".** The
renderers apply ONE flat `marker.scale`
(`ArtResolution.SPRITE_SCALE * FishRenderer.FISH_WORLD_SCALE *
FLYER_WORLD_SCALE[species]`) tuned for `ProceduralBirdSprite`'s tiny 32x20
art canvas, regardless of which generator actually produced the texture —
and `IllustratedBirdSprite`'s real-art canvas measures roughly 6-9x wider
in actual content, so the same flat scale drew a bird 6-9x too big
(measured: a sparrow that should read ~6.6 world px wide rendered at
~58). Fixed with `IllustratedBirdSprite.marker_scale(species)`, the bird
analog of `IllustratedAnimalSprite.marker_scale`: normalizes the MEASURED
content width back down to a real target world width
(`BASE_WORLD_WIDTH := 6.6`, calibrated to reproduce the procedural
sparrow's own pre-existing on-screen size, times a per-species multiplier
matching `FLYER_WORLD_SCALE`'s intended proportions). `AmbientFlyer
Renderer._build_marker`/`PiscivoreBirdRenderer.spawn_piscivore_birds` now
branch on `sprite_generator.has_method("marker_scale")` and use it instead
of the flat chain whenever the illustrated generator is the one in use —
mirroring `CreatureMarker._apply_action_scale`'s own illustrated/
procedural branch exactly. `FLYER_WORLD_SCALE` gained a `"blackbird"`
entry (`1.7`, alongside kingfisher — a real blackbird is one of the larger
common garden birds) so `IllustratedBirdSprite`'s own target widths have
something real to stay consistent with even before blackbird is
spawnable. Pinned by two new tests in `test_illustrated_bird_sprite.gd`
(a bounded, sane world-width range; relative ordering across species) and
two in `test_ambient_flyer_renderer.gd` (the real `build_bird` spawn path
uses `marker_scale`, not the flat chain; `FLYER_WORLD_SCALE` and
`IllustratedBirdSprite`'s target widths agree on which species is
bigger) — 259 tests green across the six files.

**Follow-up, same day: halved again, plus real flight height and the
Phase 3 rows.** Live playtest after the first size fix: "the robin should
be half as big and all others halved as well" — `BASE_WORLD_WIDTH` halved
again (6.6 → 3.3) directly on that report, no re-derivation attempted.

**Flight height**, requested directly: "give birds a z height in their
flight and scale size based on distance from ground / distance to
camera". On a top-down camera, distance-from-ground and distance-from-
camera are the same quantity, so `AmbientFlyerMarker._flight_height` (one
value, birds only — gated on `IllustratedBirdSprite.has_species`, since
`perched` means something different for a nectaring pollinator and a
first pass broke its own settle/alight tests) eases toward
`FLIGHT_CRUISE_HEIGHT_PX` (derived from `BASE_WORLD_WIDTH`) while airborne
and back to 0 once `perched`, driving both a lift (`offset`, never
`position`) and a scale shrink. `_animate_wings` is now a thin
`_animate_wings_body` + `_apply_flight_height` wrapper so every existing
call site gets it for free. 264 tests green.

**Phase 3**, requested the same session alongside flight height ("no
foraging, no pecking, no dancing, no tweeting... wire this all up"): the
ground walk/hop row (the three songbirds), the kingfisher's own dive pose,
and singing (every species) all get real art and real triggers.
`IllustratedBirdSprite` gains `generate_walk_textures`/
`generate_dive_textures`/`generate_sing_textures`, each confirmed by eye
before wiring in. The singing row's radiating sound-lines sit far enough
from the body that the default frame-column detector over-split it (13-16
pieces instead of 8) on all three songbird sheets — `_MIN_DIVIDER_WIDTH`
raised from 1 to 8, verified against every other row first so it narrows
without merging anything real. New pure `BirdSong.should_sing(seed,
elapsed)` (a periodic duty-cycle roll, per-bird offset by seed) drives
singing — no new phase machine, since singing has no world-state
consequence. `PiscivoreBirdMarker` shows `dive_frames` (indexed by the
existing `dive_progress()` clock) only while `Phase.DIVING`, ascend/hover/
carry still flap. `AmbientFlyerMarker` shows `walk_frames` during
`GroundForageBehavior.Phase.RESUMING` (the one grounded moment that is not
mid-strike) and `sing_frames` whenever `BirdSong.should_sing` says so,
both alongside the existing `peck_frame` check in the one `perched`
branch — no new state machine there either. 301 tests green across eight
files (the six bird/flyer suites, new `test_bird_song.gd`, and
`test_ground_forage_behavior.gd` reconfirmed untouched).

**Phase 4, same session: real bird courtship, display, and visible
reproduction.** New `src/gameplay/bird_courtship.gd` (`BirdCourtship`)
reuses `Courtship`'s species-agnostic pairing primitives (`can_pair`/
`pair_seed`/`mates`/`leads`) exactly as `MammalCourtship` already does for
land mammals — only the motion and the species gate are bird-specific, per
the explicit design note in `animal_genetics.md`'s "do not widen
DANCING_SPECIES" section (quoted above): a bird pairing does not
spiral-orbit the way a butterfly's courtship flight does, because the
display itself is a HELD pose (the tail-fanned `court` art), not a flight
figure — so `BirdCourtship.hold_offset` is simpler than either existing
courtship: a straight LINEAR close (deliberately not eased —
`FlightTransition.crossing_seconds`, not `settling_seconds`, so the
bird's speed during the approach is always exactly its own airspeed, never
over it) to a fixed point opposite the partner's own, then a genuine hold
with no further motion at all.

`BirdCourtship.DANCING_SPECIES` is the three `AmbientFlyerMarker`
songbirds (sparrow/robin/blackbird) — deliberately **not** kingfisher,
even though it has the same real `court` art: a kingfisher is a
`PiscivoreBirdMarker`, an entirely separate class that never runs
`AmbientFlyerMarker._step_pair_interactions`, so this mechanism cannot
structurally reach it (kingfisher courtship, if ever built, is that
class's own follow-up).

Wired into `AmbientFlyerMarker._step_pair_interactions` as a genuine THIRD
interaction path alongside the existing pollinator courtship and the
spiral whirl — own fields (`_bird_courting_*`, not reusing `_courting_*`:
two different motions/geometries sharing mutable state is exactly the
kind of thing that produces a sparrow orbiting a point meant for a
butterfly), `_scan_for_partners` extended to answer a third question
("who would bird-court me") in the same one group-walk, and `_begin_bird_
court`/`_continue_bird_court`/`_finish_bird_court`/`_end_bird_court`
mirroring the pollinator four one-for-one. `_animate_wings_body` shows
`court_frames` for the whole held display (checked before the `perched`
branch, since a bird-court hold overrides `position` directly and never
sets that flag, exactly like the pollinator dance).

**Reproduction is now genuinely visible for birds**, not just an
aggregate number climbing: on a successful pairing (`BirdCourtship.
mates`, personality crossed via the same shipped `FlyerPersonality.
inherit` pollinators use — a player is a selection pressure on birds too,
not just butterflies), `courtship_world.spawn_flyer_offspring` spawns the
visible chick exactly like a pollinator's, AND a new `record_bird_birth_
at` → `EcosystemSimulation.record_bird_birth` (species-routed, unlike the
single hardcoded `record_birth` mammals use) reconciles the AGGREGATE
population — `RobinPopulationModel`/`SparrowPopulationModel`, the number
`AmbientFlyerRenderer.marker_count_for` actually promotes markers from on
chunk reload — with the individual chick just spawned. Without this
second half a courtship-born chick would simply vanish the next time its
chunk unloaded and reloaded, since the aggregate never knew it existed;
this is the same "individual half reports to the aggregate half" role
`CreatureMarker`'s own mammal-courtship birth already plays via
`EarthChunkManager.record_birth_at`. A no-op for blackbird (no aggregate
population model yet — see above) and for an unknown region, the same
"unrecognized input does nothing" contract this file already uses
throughout.

Verified with the SAME class of test that once caught the pollinator
dance's own one-sided-pairing bug: two real robin markers, real frames,
confirmed to actually pair (`_bird_courting_with` pointing at each other
on both sides, not one orbiting nothing), hold a genuinely fixed point
(position stops changing once closed, unlike the butterfly orbit), and
— walking positions until a pair's own seed happens to mate, the same
technique `test_a_courting_pairs_child_inherits_from_both_parents` already
uses — spawn a chick AND reconcile the population exactly once. Confirmed
`test_birds_do_not_perform_the_butterfly_dance` still passes unchanged:
this is a separate mechanism, not a widened gate. 399 tests green across
eleven files.

**Still not done**: kingfisher's own remaining two unmapped rows (a calm
rest pose closer to `PiscivoreAppetite.ACTIVITY_PERCH` than anything
wired, and one still-unresolved variant), and kingfisher courtship
itself (a `PiscivoreBirdMarker`-side follow-up, structurally out of
this mechanism's reach — see above). Named follow-ups, not oversights.

**Follow-up, reported live a third time after Phases 3 and 4 had both
already shipped: "robins just fly from random point to point and don't
switch between diverse actions / behaviour".** Peck/walk/sing all worked
and were all tested — the bug was one level up. Every one of them is
gated on `perched`, and the ONLY thing that had ever set `perched` true
was `GroundForageBehavior` actually committing to real, nearby food (see
`_step_ground_forage`). A bird with nothing edible within
`GroundForageBehavior.SEARCH_TILES` — an ordinary condition, since an
`EarthwormPatch` needs real soil moisture/warmth to surface anything at
all — simply never perches, and so never does anything but fly, exactly
as reported, regardless of how correct the animation wiring underneath
is. A pre-existing test had actually pinned this as the intended
contract (`test_a_robin_with_nothing_to_hunt_just_keeps_flying`,
asserting `perched` stays false for a full 20-second run with nothing to
hunt) — i.e. the bug had a regression test guarding it.

The fix is a second, independent way to perch: `AmbientFlyerMarker._step_
idle_rest`, a periodic clock (`IDLE_REST_INTERVAL_SECONDS` = 12s of
flight, `IDLE_REST_DURATION_SECONDS` = 5s resting) with no food involved
at all — the same way a real bird spends much of its day sitting on a
branch or the ground between meals, not only right after one. Bird-only
(`IllustratedBirdSprite.has_species`, the same gate flight height uses),
and structurally unable to pre-empt an actual pursuit or a pair
interaction: both already claim the frame with their own `return` in
`_process` before `_step_idle_rest` is ever reached, so there is nothing
for it to interrupt — verified directly (a bird held in `DESCENDING` all
the way through a full idle-rest interval never perches). The old test
above was rewritten to check what was actually always meant to be true —
`ground_forage.phase` never commits to food that isn't there — rather
than the accidental "never perches either" it had also been asserting.
332 tests green across all seven bird/flyer suites (`test_ambient_flyer_
marker.gd` itself, plus `test_piscivore_bird_marker.gd`/`test_ambient_
flyer_renderer.gd`/`test_bird_song.gd`/`test_bird_courtship.gd`/
`test_illustrated_bird_sprite.gd`/`test_ecosystem_simulation.gd` re-run
as siblings with no direct relation to the fix).

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
  uncomfortable to encode as content regardless of intent. This is
  specifically about *danger* claims at *country/city* granularity — it
  doesn't extend to [worldbosses.md](worldbosses.md)'s regional-folklore
  brainstorm, which maps a bounded set of cultural/mythological
  macro-regions (not thousands of places) onto a *flavor* identity for an
  already-emergent boss, not a claim about real-world danger.

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

**Standing still still lives.** Idle used to hold one frozen frame forever —
tolerable while standing still was rare, wrong once grazing pauses and a
boxed-in animal with nowhere to go (above) made it a common state. A second
idle frame (a small whole-body settle, read as a breath) gives a standing
animal somewhere to go, and which of the two shows is picked the same way
grazing pauses are: a deterministic hash of the animal's own seed
(`ProceduralAnimalAnimation.idle_frame_index`), not wall-clock time alone —
so a herd standing together breathes out of step with itself instead of
reading as one frozen tableau.

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
- ✅ Condition-gated individual reproduction — `animal_reproduction.gd`, wired
  end to end via `CreatureMarker.can_reproduce`/`on_reproduced` and
  `World._step_reproduction` (energy/health/birth-cooldown gate plus local
  crowding and vegetation-capacity vetoes; see progress.md's own "Condition-
  gated reproduction (bioenergetics)" entry for the full breakdown). This
  entry was stale (still marked 🚧) after the code had landed fully wired.
- ✅ Unloaded-chunk catch-up integration — `chunk_ecology_catchup.gd`, wired
  into `EarthChunkManager`'s load/unload path (`_apply_ecology_catchup`/
  `_unloaded_ecology`), tested (`test_chunk_ecology_catchup.gd`). This entry
  was stale (still marked 🚧) after the code landed.
- ✅ Aquatic sibling of this whole doc (fish population as a water-area-
  derived carrying capacity, with an explicit fishing-harvest mortality
  term, `record_catch`) — `aquatic_population_model.gd`,
  `water_area_survey.gd`, wired into `EcosystemSimulation`/
  `ChunkEcologyCatchup`/`EarthChunkManager`, persisted across restarts
  (`ChunkSerializer.save_fish_population`). See
  [fishing.md](fishing.md#aquatic-population-model).
- ✅ Land herbivore/predator mortality term — `EcosystemSimulation.record_death`
  is `record_catch`'s land counterpart (subtracts from `_herbivore_population`
  or `_predator_population` per `is_predator`, floored at 0.0, silent no-op on
  an unknown region), wired through `EarthChunkManager.record_death_at` from
  `CreatureMarker.take_damage`'s death branch — the one place a kill is
  finalized for both a predator's own hunt and the player's weapon. Closes
  the gap this section used to describe explicitly: killing a land animal
  used to never touch `EcosystemSimulation` at all. See the "two fidelities
  are one population" section above. **A working NPC `hunter` now calls the
  same hook too** (`NpcEconomy._gather`, `is_predator=false` — see
  [npc.md](npc.md#needs-and-the-local-production-economy) and
  `docs/progress.md`'s NPC Needs / Local Production Economy entry), so
  sustained village hunting, not just a predator's own hunt or the player's
  weapon, is a real herbivore-population depletion driver.
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
  `EarthChunkManager.fish_population_near`/`record_fish_catch_near`. **A
  working NPC `fisher` now calls the same `record_fish_catch_near` hook too**
  (`NpcEconomy._deplete_discrete_unit` — see
  [npc.md](npc.md#needs-and-the-local-production-economy) and
  `docs/progress.md`'s NPC Needs / Local Production Economy entry), visibly
  thinning the shoal exactly like the player's own catch or a kingfisher's
  dive. Unlike the hunter/farmer hooks above (pure aggregate-population
  arithmetic, safe every frame), `record_fish_catch_near` also
  find-and-`queue_free`s one real on-screen fish per call — built for a
  piscivore bird's one-call-per-real-catch contract, not a per-frame drip —
  so the fisher only calls it once per whole `FOOD_UNIT` actually gathered
  (the same accumulation gate `NpcEconomy._gather` already uses for the
  market stock/wallet gold update), not every frame like the hunter/farmer
  arms. An earlier version of this fix called it unconditionally every
  frame, which stripped every fish within catch radius of the dock almost
  instantly; caught during verification before merge.
  **Follow-up (wings):** `PiscivoreBirdMarker` was built with only a static
  resting-pose texture and never touched it again — cruising, hovering over
  its target, diving, and carrying a catch home all played on one frozen
  frame, including the hover this doc calls out as the signature kingfisher
  beat, which is sustained by rapid wingbeats in life (reported: "fix the
  kingfisher's wings"). `ProceduralBirdSprite` already painted flap/perched
  frames for `"kingfisher"` and `FlapGlide`/`WingbeatBounce` already carried
  its wingbeat frequency — this was a wiring gap, not a missing painter.
  `PiscivoreBirdRenderer.spawn_piscivore_birds` now sets `flap_frames`/
  `perched_frame` at spawn (mirroring `AmbientFlyerRenderer._build_marker`'s
  sparrow/robin wiring exactly), and `PiscivoreBirdMarker` gained its own
  `_animate_wings` step: `perched_frame` only during the genuinely
  motionless `ACTIVITY_PERCH`, `flap_frames` cycling everywhere else —
  patrol, nest trips, hunting flight, and every strike phase (hover/dive/
  ascend/carry) all keep flapping, since none of them are actually still.

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


## Two butterflies meeting

Two butterflies passing close do the most recognisable thing butterflies do:
they fly at each other and **corkscrew rapidly upward** for a second or two
before breaking off. Real lepidopterists call it a **spiral flight**, and it
happens between males, between different species, and between individuals that
have already mated. It is investigative and territorial — not courtship.

That distinction is the whole design. There are **two** interactions, and they
are deliberately nothing alike:

| | Spiral flight (`SpiralFlight`) | Courtship dance (`Courtship`) |
|---|---|---|
| Who | any two true butterflies, **cross-species** | **same species** only, plus bees |
| Noticed from | 4 m | 3.2 m |
| Lasts | 2 s | 4.5 s |
| Shape | tight fast whirl, up **and away** along a 1.5 m ascent | wide slow orbit, stays put |
| Again in | 18 s | a **real day** |
| Produces | nothing, ever | sometimes an egg |

### Neither of them is a circle, and neither is flown at a speed it cannot fly

Reported: *"the dance is overly dramatic and only a circle"*. Both halves were
real, and both were the same mistake — a turn rate written down without
checking the speed and the acceleration it implies.

**The drama was a physics error.** The whirl's rate came from a monarch's
5 m/s **burst** speed applied to the whole orbit. At a 35 cm radius that is
`v²/r = 71 m/s²` — over **seven g**. Nothing with wings pulls seven g. The
turn, not the wing, is what limits this, and the ceiling is one this project
had already derived somewhere else: `WingbeatBounce` argues that a wing cannot
pull the body *down* through its stroke, so lift swings about weight with
depth `e ≤ 1` and peak lift is at most **twice** weight — a load factor of
two. `ORBIT_SPEED_MPS = sqrt(2g·r)` follows, and the whirl rate roughly
**halves**. The courtship dance had the same problem in reverse: 0.85 turns a
second on a 9-pixel (≈70 cm) radius is 3.8 m/s, three quarters of an absolute
burst, for a manoeuvre the module itself calls a slow wide orbit. It is now
derived from a monarch's ordinary **cruise** (2 m/s), because a display flight
is flown at a cruise.

The whirl also **covers ground** now. A real ascending flight goes up *and
away*; spinning on one spot is a large part of why a fast turn reads as
frantic. The 1.5 m ascent is decomposed at 45° into a climb and a ground
track, so the excursion — and the territory budget it was already capped
against — is unchanged. The orbit, the climb and the ground track are three
components of **one** velocity and their sum has to fit inside a real burst;
the old model spent the entire burst on the orbit and then added the climb on
top of it.

**The circle was a shape error.** Real spiral flights are chaotic ascending
chases — irregular, jagged, never a clean ellipse — and the pair's separation
is observed as a *range* ("about half a metre to a metre"), not a number.
Both orbits now breathe across their real band, per-pair and deterministic,
using the **same** irregularity a butterfly's ordinary flight already had
(`FlightIrregularity`, factored out of `PollinatorForaging`'s flutter rather
than invented a second time). The courtship dance's fixed 0.7 ellipse is gone:
an ellipse is still a closed figure traced identically every time round, which
is what "only a circle" meant. The departure from a circle is kept at exactly
the magnitude the ellipse asserted — it is the same observation — but made
irregular.

The radius is written `r₀/(1 + k·w)` rather than `r₀·(1 + k·w)`, which is not
cosmetic: a flyer holds an **airspeed**, so on a varying radius it comes round
faster where it is tighter, `ω = v/r`. With the reciprocal form the angular
rate is exactly `(v/r₀)(1 + k·w)`, whose integral is closed-form — so the
swept angle is the true integral of a real varying turn rate rather than an
accumulation per frame. That matters: accumulating it would make the figure
depend on frame rate and on `SimulationLod`'s step size, which is precisely
the class of bug this system has already produced three separate ways.

One projection compromise, stated rather than hidden: the ground track is
drawn over the **upper** half-circle only. This world is top-down and draws
height as screen-up, so climb and ground track land on the same two axes, and
a track pointing down the screen cancels the climb exactly — measured at
0.07 px of total shared translation over a whole whirl when it first did,
which is a pair spinning on one spot, the very thing the ground track exists
to stop.

The spiral flight is allowed to be common precisely **because it is inert**.
Everything that bounds the population lives in courtship and the life cycle; a
behaviour with no outcome needs no bound, so it can happen as often as the
real thing does. There is no `mates`, no `pair_seed` and no `leads` anywhere in
it, and a test pins their absence.

Every distance and duration in it is a real figure converted through this
project's one yardstick (world pixels per real metre, itself derived from the
player's real height): territorial butterflies react to an intruder from 2–6 m;
a spiral flight carries the pair 1–3 m up; the whirl rate is a real burst
flight speed (5 m/s, a monarch at full exertion) divided by the circumference
of the circle the flyer is actually flying, not a number that looked right.
The gap between bouts is derived from a **time budget** — field studies put
roughly 5–15% of a territorial butterfly's active time into aerial
interactions, and one that spent more than that whirling would not feed enough.

### Why the player never saw any of this

The report was blunt: *"I never see butterfly dance and play with each other
when they fly by close or mate"*. Three separate causes, all of them measured
rather than guessed.

**The spiral flight did not exist.** Courtship did, and it is deliberately
rare, same-species and on a day-long cooldown — it was never going to satisfy
"when they fly by close".

**Courtship was one-sided, and always had been.** Flyers are processed one
after another, so the first of a pair always commits first; the partner search
then rejected any flyer already courting — including the one courting the
searcher. What was actually on screen was **one** butterfly orbiting an empty
midpoint while the other flew obliviously off to a flower, never two. It
survived because courtship's own tests covered its *rules* and nothing
anywhere drove two real flyers through real frames. That test exists now.

**Courtship was geometrically starved.** A chunk's 2–4 butterflies were
scattered over its whole 32×32 tiles, while two of them can only notice each
other within a few metres and each stays tethered near its own spawn point.
Measured through the real spawn geometry over 300 real chunks at the reported
coordinate (52.5°N, Brandenburg):

| | chunks where a same-species pair could **ever** meet | …close enough to meet **routinely** | any pair inside spiral-flight range |
|---|---|---|---|
| scattered (before) | 4.4% | 0.0% | 0.0% |
| aggregated (after) | 100% | 100% | 100% |

At 40°N, where two of the pool's species really overlap and so the *species*
half of the problem is live as well as the geometric half: 2.2% → 89.0%, a
40-fold change. It is not 100% on purpose — a quarter of a meadow's
butterflies are a stray of another kind, and in a chunk holding only two of
them one stray means no courtable pair. A meadow that could only ever hold one
species would be a duller thing than the real one, and those meadows are
lively anyway, because the spiral flight does not care about species.

### Butterflies club up

The fix for the geometry is not a wider notice radius — that number is a claim
about a butterfly's eyesight, and inflating it to paper over a spawn problem
would make every other distance in the system lie too. It is that **real
butterflies congregate**: at a stand of nectar flowers, at a damp patch
(mud-puddling clubs, where dozens crowd onto a square metre of wet ground), at
a landmark (hilltopping and lekking). A meadow with its butterflies spread
evenly across it is the unrealistic picture.

So a chunk's true butterflies are now **one loose aggregation**, about 3 m
across — sized so that any two members are already within noticing distance of
one another standing still — and **mostly one species**, because a species is
present where its larval host plant grows, one female lays dozens of eggs on
one stand, and what emerges is a local cohort.

Bees and songbirds keep the old scatter, deliberately: a honeybee commutes
from a hive and works a whole meadow, and songbirds hold territories rather
than clubs. Only the butterflies club up.

A club is **not choreographed**. Every butterfly in a chunk comes into
existence on the same frame, so each starts part-way through its own
spiral-flight cooldown — uniformly, which is the stationary distribution of
"this one last whirled at some point in the past cycle" and therefore the
truth about an animal that did not begin existing when the chunk loaded.
Without it a whole club would whirl on one frame, go silent together, and
whirl together again.


## The butterfly that knows you

*"Can make butterflies dance around a players head or fly away based on
personality (dna derived)?"*

Every true butterfly now carries a **personality**: one heritable trait,
**boldness**, on a continuum from 0 to 1. It decides one thing — what this
individual does about the player — and that one thing is enough to turn a
meadow from scenery into something that responds to how you behave in it.

### The two ends, and the middle

| Boldness | Flight initiation distance | What you see |
|---|---|---|
| 0.00 (shyest) | 3 m | bolts as you walk up |
| 0.50 (typical) | 1.5 m | nothing much, unless you walk into it |
| 0.88+ (bold) | 0 m | comes and orbits your head |

**Flight initiation distance (FID)** is a real, measured quantity — how close
a threat gets before an animal breaks and flies — and it is the standard field
measure of boldness across taxa precisely because bolder individuals reliably
have shorter ones. Butterfly FIDs sit in the low metres; the shyest individual
takes the top of that band, and the bold endpoint is **zero**, because bold
individuals of many species show no flight response to a human at all.

The **dance** is not a third dance shape. It is the existing spiral flight
aimed at a different object, at the same orbit radius and the same turn rate —
which is exactly what the real behaviour is, since a territorial butterfly
launches at conspecifics, passing birds, falling leaves and thrown pebbles
alike, and a person walking through a meadow is one more such object. It is
centred on the player's **head**, a measured place: the character's origin is
at its feet and its height is a real 175 cm through the same yardstick every
other distance uses.

Boldness is a **continuum, not two buckets**, and the threshold between "will
dance" and "will not" is *derived* rather than chosen: a butterfly may only be
counted bold enough to orbit once its own FID has dropped below the radius it
would be orbiting at. Anything shyer would be fleeing from inside its own
dance. That lands near 0.88.

The distribution is the **average of two independent halves** — the triangular
distribution: bounded to [0,1] by construction, peaked in the middle, thin at
both ends. So roughly 3% of a meadow will dance at you, roughly 3% will bolt
dramatically, and the other 94% carry on as before. Both alternatives were
rejected for measurable reasons: a single uniform roll makes the extremes as
common as the middle, and a Gaussian has to be clamped into [0,1], which piles
probability up on the two endpoints and makes the extremes *commoner* than the
middle. In a meadow of 266 butterflies that is about seven of each — uncommon,
and present.

### Fleeing is a burst

An escape is maximum exertion, not a cruise. The multiplier is the **ratio**
between the two real speeds (a monarch bursts at ~5 m/s against a ~2 m/s
cruise), never an absolute: this world's butterfly cruise is its own stylised
number, and dropping a literal 5 m/s on top of it would read as a teleport. A
fleeing butterfly does not stop on the line it flushed at either — in the
escape-distance literature an animal puts about its own FID again between
itself and the threat before settling.

### The precedence order

Five things can move a butterfly, and they must not fight. Highest first:

1. **flee the player** — escape outranks everything, in every animal. A
   butterfly that keeps courting while something big closes on it is a dead
   butterfly, so a flush ends a courtship or a whirl mid-way (and charges no
   cooldown, because the interaction did not happen — otherwise a player
   walking through a meadow would sterilise it for a real day). The partner is
   told directly: this is the one place one flyer reaches into another, and it
   has to be, because "my partner bolted" is not something the other side can
   derive, and leaving it underived is the *one butterfly orbiting an empty
   midpoint* bug all over again.
2. **finish a pair interaction already running** — commitment. An interaction
   that can be interrupted by a passer-by is an interaction that flickers.
3. **start a courtship** — the rarest and the only one with an outcome.
4. **dance at the player**.
5. **start a spiral flight** with another butterfly.
6. **forage** — ground prey, a bloom, drinking.
7. **wander**.

The dance is leashed: it is centred on the player's head, so a player who
keeps walking would otherwise tow a butterfly across the world. It lets go
once the player has carried it more than a notice radius from the butterfly's
own home — as far as it spotted the intruder from in the first place, which is
about as far as a real territorial butterfly pursues one before returning to
its perch. The leash is checked against the **orbit's centre**, not against
the butterfly, so a player who moves a long way in one step never drags it
there even for a frame.

### The player is a selection pressure

Boldness is **inherited**, through the same `DnaCrossover` that crosses
players' children and bred livestock — see [dna.md](dna.md)'s "Wild animals
have DNA too". That is the whole reason it is genes and not a hash of the
flyer's seed. Who the player catches is decided by the same number the
survivors' offspring inherit, so a player who nets what comes close leaves the
shy ones to breed and **the meadow learns to avoid them** — with nothing
anywhere saying so.

Measured over ten generations of a 266-butterfly meadow: mean boldness falls
from 0.496 to 0.377 under a netting player, against 0.019 of drift in the
identical untouched control. Run the same pressure the other way round (which
no player behaviour can do — it is there to prove the drop is selection and
not a bias hiding in the crossover) and the meadow reaches 0.849.

Two honest limits, repeated here because they decide what the player can
actually see today: **nothing nets an ambient flyer in the live game yet**
(the net is craftable, `CaptureTool` knows what it is for, but no interaction
removes one from the world), and **ambient flyers are not persisted** — a
chunk's flyers are re-derived from their cells' seeds on load, so an evolved
meadow reverts when that chunk unloads. Boldness drifts within a session, not
across one.

### Songbirds notice you too

The boldness/FID continuum above is deliberately butterfly-only —
`FlyerPersonality.reacts_to_player` gates on `SpiralFlight.spirals`, and that
module's own doc comment is explicit: "a bee, a fly and a sparrow have no
personality steering at all". A real sparrow's flight response has nothing to
do with a corkscrewing insect's, and giving every species one shared
personality trait would blur a distinction this project already draws
carefully. But a real ground-foraging songbird still does the one plain thing
every other sensed creature in this project already does when something
looms: it notices and gets away.

Real house sparrows and robins have a measured flight initiation distance in
the low-single-digit-to-several-metres band — commonly further out than a
shy butterfly's own 3 m endpoint (`FlyerPersonality.SHYEST_FLUSH_DISTANCE_M`),
which fits: a bird's predator-vigilance is sharper than an insect's.

Rather than a second boldness system, `AmbientFlyerMarker.
_step_songbird_flight_response` reuses the SAME two pure modules the ground
creature roster (`CreatureMarker`/`CreatureBehavior`) already senses/avoids
threats through — `CreaturePerception.nearby` (is the player within notice
range) and `ThreatAvoidantWander.away_biased_step` (bias the flight heading
away from whatever was sensed, keeping the sideways component) — rather than
inventing a second perception/avoidance system. Both existed, tested, and
had no production caller anywhere in the game until this.

- **One shared flush distance** (`AmbientFlyerMarker.
  SONGBIRD_FLUSH_DISTANCE_M`), not an inherited trait — that individuality is
  deliberately left where it already lives, on the butterflies.
- **Gated on `FlyerDiet.forages_on_the_ground`** (currently robin and
  sparrow) rather than a third species list, so a future ground-feeding
  species inherits the reaction automatically instead of needing to be added
  to yet another roster.
- **A threat outranks a meal here too.** A bird flushed mid-peck abandons the
  strike (`GroundForageBehavior.abort`) — the same rule "Grazing is an act,
  not an aura" above already states for ground grazers — and a bird already
  mid-courtship breaks it off, exactly as a fleeing butterfly does.
- **Released further out than it was noticed at** — the same hysteresis
  shape as the butterflies' own `FLEE_RELEASE_FACTOR` (reused directly, not a
  second "how much further" number), so a player parked right at the flush
  distance does not make the bird dither in and out of scattering.


## A shoal finds its shape

*"Make fish interact with each other (approach, follow, avoid, play) and
also make them swim away from player and animals who wade near them."*

Fish were deliberately the lightest tier in this project —
[fishing.md](fishing.md#aquatic-population-model) scopes them out of
`CreatureMarker`'s full sense/perceive/act stack on purpose, since an
aggregate population model, not individual cognition, is what makes a
fishery feel real. That scoping still holds for *population* — a fish's
movement gains no needs, no hunger, no courtship. What it gains is the one
thing every real shoaling fish actually does with its neighbours: react to
how far away they are.

### The three zones

Real shoaling fish don't coordinate — no fish in a shoal has ever seen the
whole shoal's shape from outside it, and none needs to. The classic account
of how a shoal nonetheless holds together is the **zonal model** (Aoki 1982;
Huth & Wissel 1992): each fish reacts to its nearest neighbour through three
concentric zones, purely by distance.

| Zone | Distance (body lengths) | Response |
|---|---|---|
| Repulsion | < 1 | swim directly away — **avoid** |
| Orientation | 1 – 4 | match the neighbour's heading — **follow** |
| Attraction | 4 – 10 | swim toward it — **approach** |
| (beyond) | > 10 | not noticed at all |

`FishSchooling.steering_for_neighbor` (`src/gameplay/fish_schooling.gd`,
pure and engine-free like `CreatureBehavior`/`ThreatAvoidantWander`) is
exactly this table as a function of one neighbour's position and heading.
Every distance is stated as a **multiple of body length**, the same unit
the real literature itself uses, rather than an independently chosen pixel
count — `FishMarker.CLEARANCE_PX` (already documented there as "roughly the
sprite's half-extent") doubled gives the body length the zones are measured
in (cross-checked directly by test, not just by comment, since the two
scripts deliberately don't import each other — see below).

No flocking/steering system was built to make a shoal look like a shoal.
Each fish independently finds its own single nearest schoolmate (mirroring
`AmbientFlyerMarker._scan_for_partners`'s own "both sides compute the same
answer, no messaging" shape) and reacts to *only* that one — the same "give
every individual the same independent reaction and the group behaviour
emerges for free" principle [animal_husbandry.md](animal_husbandry.md)
already states for herding. A crowded pool full of fish all avoiding their
nearest neighbour and drifting toward the next-nearest one, with nobody
coordinating anything, is what a shoal actually is.

### Play: an occasional, harmless chase

Real shoaling fish are also observed bursting into a brief chase of a
schoolmate that is neither feeding, fleeing, nor courting — investigatory or
purely social behaviour, distinct from all three. Modeled as a low, per-fish,
per-interval chance (`FishSchooling.rolls_for_play`, the same deterministic
hash-roll shape as `CreatureWander.is_pausing`) that a fish with a nearby
schoolmate briefly abandons the zoned steering above for a direct pursuit —
reusing the *existing* fast-tail-flap speed boost
(`FishMarker.FLAP_SPEED_MULTIPLIER`) rather than inventing a second burst
mechanic, the same "not a new dance, the existing one aimed at a different
object" economy this doc's own butterfly-dance section already practices.
Deliberately **one-sided**: the chased fish does not itself react specially,
it just carries on schooling/wandering as normal, and a real "catch and peel
off" look falls naturally out of the chaser eventually entering the target's
own repulsion zone. A fully mutual, alternating-roles chase would read a
little richer but was judged not worth a second fish reaching into another's
state for it — the population-model precedent for staying lightweight here
(fishing.md's original scoping) still applies to how elaborate this gets,
not just to whether it exists at all.

### Fish scatter when the water gets crowded

The other half of the ask — fish fleeing a wading player or animal — turns
out to need no new fear mechanism at all. `FishMarker.bolt_from`/
`is_bolting` already exist, built for a kingfisher's missed strike (see "A
kingfisher hunts" below): a hard, fast, shore-respecting dash directly away
from a threat point, for a fixed duration. The only new question was ever
*what else should be allowed to call it*.

The answer was already sitting in `EarthChunkManager.river_wader_positions`
— the exact "is this position genuinely standing in water" filter the
world's own river-flow-ripple shader already runs, every frame, on the
player plus every creature (`scenes/world.gd`'s wader-candidate gathering),
tile-memoized since rivers never move. A player wading in, or an animal that
has waded in near them, *is* a wader by that same definition.
`EarthChunkManager.startle_fish_near_waders` reacts to whichever of those
positions are within `FISH_WADER_FLUSH_DISTANCE_PX` of a given fish, the
same way `startle_fish_near` already reacts to one kingfisher's position —
a real alarm/flush response, the same kind every other sensed creature in
this project already has to an approaching threat
(`FlyerPersonality.SHYEST_FLUSH_DISTANCE_M`, `AmbientFlyerMarker.
SONGBIRD_FLUSH_DISTANCE_M`), at roughly the same few-metre order of
magnitude real shallow-water fish show toward a wading disturbance. One
shared threshold, not an inherited trait — deliberately following the
songbird's own precedent ("that individuality is deliberately left where it
already lives, on the butterflies") rather than building fish their own
boldness system.

### The precedence order

Bolting (fear, whether from a kingfisher or a wader) always wins — the same
"escape outranks everything" rule stated for butterflies, songbirds and
every land creature in this project. Below that:

1. **flee** (`bolt_from` — kingfisher strike or a nearby wader)
2. **an active lure** (a player's cast fishing line, pre-existing — unchanged)
3. **a rolled play chase already under way**
4. **ordinary zoned schooling** (avoid / follow / approach the nearest schoolmate)
5. **wander**

Schooling is also **leashed to home**, the same shape as the butterfly
dance's own leash: past `SCHOOL_LEASH_RADIUS_FACTOR` times this fish's own
wander radius from home, schooling is ignored in favour of wander (which
already pulls a fish home) — so a fish cannot in principle keep closing on a
schoolmate that itself keeps drifting, indefinitely, away from where either
of them actually lives.


## Butterflies do not fly in straight lines

*"butterflies generaly should have more random / dancy motions rather then fly
in a straight line"*

Erratic, unpredictable flight is a genuine anti-predator adaptation —
**protean** behaviour: a flight path a bird cannot extrapolate is a flight
path a bird cannot intercept, and it is a large part of *why* butterflies fly
the way they do rather than an aesthetic quirk.

The tumble already existed and was already grounded — it was simply only ever
reached on the last stretch to a bloom. Ordinary wander picked **one heading
and held it for 0.7 s**, which is a straight line at a time, and that is what
the player was watching. The same tumble now applies to ordinary flight at
full strength, because out there is no bloom to settle onto.

Songbirds are deliberately excluded. They share the same movement module, and
a sparrow tumbling like a monarch reads as a bird glitching — the same failure
that already got birds out of the courtship dance.

This corner of the code has produced a *"flyers stall and jitter on a fixed
spot"* bug three separate ways, every one of them from building a heading out
of vector components that can cancel. Nothing can cancel here: the tumble
keeps a full-length component along the heading and adds a strictly
perpendicular veer of at most 0.8 of it, so the result always has a positive
forward component. A test measures **every single step as a whole step**.


## The wingbeat bounce

*"maybe also make them bounce slightly with each wing flap"*

Lift is not delivered smoothly. It arrives in **pulses**, essentially all of
it on the downstroke, so over one beat the force holding the animal up swings
above and below its weight and the body genuinely rises and falls once per
wingbeat. In a butterfly — slow beat, light body — that undulation is most of
what its flight *looks* like.

The amplitude is derived, not chosen. Model the lift as swinging sinusoidally
about body weight at the wingbeat frequency and the body's displacement has
amplitude `e·g/ω²`. `e` is not a knob: a wing cannot pull the body *down*
through its stroke, so lift can dip to zero and no further, `e ≤ 1`, and
taking `e = 1` makes this the physical **ceiling** on the bob. For a monarch —
~10 beats a second, ~25 mm of body — that is about 2.5 mm, or a fifth of its
own body from the bottom of the cycle to the top. Which is what a monarch in
the air actually looks like.

It is expressed as a **fraction of the body** rather than a distance, and that
divergence is deliberate: this world draws its small flyers well above life
size, so a physically exact 2.5 mm bob would be three hundredths of a world
pixel and would not exist on screen. The ratio is what transfers into a
stylised world.

There is **no species gate**, and none is needed. The bob goes as
`1/(frequency² × body length)`, so a bee at ~230 Hz and a sparrow carrying
14 cm of body fall out of it at an amplitude nothing could draw — structurally,
without a list that would go stale the next time a species is added.

The **period** comes from the wing animation and the **amplitude** from the
physics, and the two are different on purpose: the sprite's four-frame beat is
under three a second where a real monarch does ten, and locking the bob to the
real frequency would give a body oscillating four times faster than the wings
driving it — two motions at once instead of one animal.

**It is a draw offset and never `position`.** That is load-bearing rather than
stylistic: `position` feeds containment, the courtship orbit, the spiral
flight, every partner-distance check, and the whole tree's Y-sorting. A
per-frame bob folded into it would put a wobble through all five at once. A
test pins that `position` is untouched while the drawn offset moves.

### Butterflies flap-glide, so the beat is a gait and not a metronome

*"can you add more random bounces and flaps?"*

A clean sinusoid at a fixed frequency, and wing frames stepped at a fixed
seconds-per-frame, are metronomic — which is exactly what reads as mechanical.
The real animal does not do that. Butterflies **flap-glide**: monarchs
especially alternate bursts of flapping with gliding and soaring phases, and
their wingbeat is genuinely irregular, unlike a bee's near-constant hum. Small
passerines do the related thing, **flap-bounding**.

`FlapGlide` holds that gait, and almost all of it is derived:

- **Who alternates at all** is read off the wingbeat frequency, not a roster.
  Above ~100 Hz an insect has **asynchronous** flight muscle — the thing that
  lets a bee do a couple of hundred beats a second where a butterfly does ten
  — and an animal beating that fast is not alternating with anything. A
  species added to `WingbeatBounce.FLIGHT` gets the right answer for free,
  the same way it already gets the right bob.
- **How much of the time** comes out of level flight. Mean lift across a gait
  must equal weight; the wings supply none of it while gliding, so the
  flapping phase supplies all of it, and the most a wing can make is the same
  `1 + e ≤ 2` ceiling the bob amplitude stands on. `(1 − f)·2W = W`, so
  **f = ½**.
- **How fast the beat varies inside a bout** comes out of aerodynamics.
  Quasi-steady lift goes as the square of flapping speed, so a lift that can
  swing by `e` corresponds to a rate that swings by `√(1+e) − 1`.

The one figure *not* derived is the bout length: **two** visible beats, on the
grounds that one beat followed by a pause is a stutter rather than a gait. The
tests pin the properties (the flapping half is at least two visible beats; the
whole gait repeats inside a couple of seconds so a player watching sees it)
rather than the digit.

The body follows what the wings are actually **doing**. Both the frame index
and the bob are driven off one **wing clock** that pauses through a glide, so
they can never disagree. Through a glide the bob stops — there is no pulse to
rise and fall on — and the body **sinks**; through the next bout it climbs
back while bobbing on the beat. Over a whole gait those cancel exactly: a
sawtooth with no net drift, which is what level flap-gliding *is*, and the
sink needs no size of its own because the height a bout gains is the height
the glide gives back.

`WingbeatBounce` is untouched by all of this and still owns how big the bob is
and why; `FlapGlide` composes on top of it and owns only *when* the wings are
driving. And it is still a **draw offset** — the same `position` invariant,
the same test.


### Butterflies perch to feed, so a drink is not a hover

*"butterflies get stuck in front of a single flower"* — reported twice.

The forage **rule** was measured exhaustively and cleared: a butterfly visits
20–29 distinct blooms per 600 simulated seconds, longest loiter 6.8–11.5 s,
and after this change 30 distinct blooms of 30 available over 600 s with 134
landings. The plan was fine. What was wrong was the **picture**. Three things
compounded across the 2.4 s of `PollinatorForaging.DRINK_SECONDS`:

1. arrival snapped `position` onto an exact pixel, with no landing;
2. `position` was then never touched again for the whole drink;
3. the wings kept running the **flight flap** — `perched_frame` is generated
   by `ProceduralBirdSprite` alone (the only `generate_perched_texture` in
   `src/rendering`), so a butterfly had no settled frame at all and fell
   straight through to `flap_frames`.

Net: a butterfly hovering, wings beating, motionless on one pixel, repeatedly.
Which is exactly what *in front of* a flower describes.

Real butterflies do none of that. Monarchs, swallowtails and blue morphos
**perch** to feed; hovering while nectaring is a hawkmoth trait, not a
butterfly one. The feeding wing posture is nothing like flight — wings held
**closed over the back**, opened only slowly and occasionally to bask. And
they **shuffle around the flower head** constantly, working different florets
with the proboscis; a feeding butterfly is never motionless for 2.4 seconds.

`NectaringPosture` holds that, beside `FlapGlide` and `WingbeatBounce`, and
takes the same shape: real seconds and real proportions, no free digits.

- **The wings.** `ProceduralButterflySprite.generate_settled_textures` is the
  nectaring counterpart of the bird's perched frame — the same one painter
  re-run at a different wing phase, except that basking is a *movement*, so it
  is a short sequence rather than a single pose. Shut is the real ratio: a
  monarch spans ~100 mm open and ~6 mm across the appressed wings and thorax,
  the wings being edge-on. That is sub-pixel on this canvas, so it is floored
  at the one pixel of half-extent that is guaranteed to rasterise — the same
  legibility floor the body spindle already carries. A butterfly that
  *vanished* on landing would be a worse picture than the hovering one.
- **How often.** One shut→open→shut cycle every **4 s**, the swing itself
  **0.6 s** each way — so the shut duty (70 %) is derived rather than a second
  free number. The cycle is deliberately longer than a whole drink, which is
  what makes it read as *occasional basking* rather than as a slow flap: at
  most one opening per stop, an order of magnitude slower than the 0.36 s
  flight beat.
- **The feet.** The excursion is the size of the **flower head**, not of the
  meadow: a composite head (aster, clover, thistle) is ~20 mm across, ~10 mm
  of reach, against a monarch's ~27 mm body. Read as that ratio against the
  *drawn* body rather than through `GroundSlide.PX_PER_METER`, because ambient
  flyers are drawn far larger than life — in metres the shuffle would be
  sub-pixel. The wobble is `FlightIrregularity`'s, read as a bearing and a
  radius so it walks *around* the head and is bounded exactly, and it is an
  **offset from a fixed anchor**, never an accumulating step. That is the only
  reason micro-motion is safe to add to something the forage rule measures
  arrival against, and it is why the measurement above came back unchanged.
- **Landing.** The snap is gone. The last gap is flown at the flyer's own
  airspeed — so a bee sets down quicker than a monarch with no second number
  existing — and smoothstepped, so it eases onto the bloom instead of arriving
  at full speed and stopping dead. The duration is
  `FlightTransition.settling_seconds`, which stretches the crossing by the
  ease's own peak-to-mean ratio: sizing an eased settle as `gap / airspeed`
  sizes its *average* rate, and a smoothstep runs half again that fast halfway
  through. See "Nothing outflies itself" below.

The bob is zeroed throughout, for the same reason the perched branch zeroes
it: nothing is beating, so there is no lift pulse to rise and fall on. And
flushing still outranks all of it — a butterfly the player walks up to leaves
the flower mid-drink and is beating its wings again on the next frame, which
is the classic flight-initiation-distance measurement and stays intact.


## Nothing outflies itself

Asked as a question, which is the same thing: *"can you interpolate the state
transitions?"*

Every state entry a flyer had was a bare `position = <wherever the new state
wants me>`, and a state entry is exactly the frame a player is most likely to
be looking at the animal. Measured against the shipped constants on 1/60 s
frames, where a butterfly flies **0.267 px per frame**:

| entry | jump | |
|---|---|---|
| courtship dance | **14.9 px** | snapped onto a fixed 9 px orbit |
| spiral flight | **3.27 px** | wide start radius swung at a 4.4 px orbit's turn rate |
| dance at the player's head | **6.31 px** | the same, round a head |
| worm / fruit / seed / grass-seed arrival | **3.5 px** each | `position = <the food>` |
| nectaring settle | **0.47 px** | eased — but sized by its *mean* rate, not its peak |

So there is one statement, made everywhere, and it needs **no tuned number at
all**: *nothing may move further in one step than the airspeed it is flying at
carries it.* The time to cross a gap is that gap over the animal's own
airspeed. `AmbientFlyerMarker.airspeed_px_per_second` is what "the airspeed it
is flying at" means — its wander cruise ordinarily, that cruise ×
`FlyerPersonality.ESCAPE_SPEED_MULTIPLIER` while bolting, and
`SpiralFlight.BURST_SPEED_PX_PER_SECOND` while flying one of the three aerial
figures, whose geometry is derived in metres per second from a real monarch
rather than from the wander speed.

`FlightTransition` holds the shared duration model, beside `NectaringPosture`,
`FlapGlide` and `WingbeatBounce` — the nectaring landing derived it first, for
one fixed gap, and every other entry needed the same idea with the distance
left as a parameter.

**A flyer holds an airspeed, not a turn rate.** The orbits already said so
about their *breathing* radius and not about their *convergence*, so a pair
meeting 50 px apart was swept round a 25 px circle at the rate derived for a
4.4 px one — 164 px/s, eleven times what the animal flies at.
`SpiralFlight.orbit_clock` applies the same `v/r` law to the approach, as a
closed form (a stretched clock, whose integral is a logarithm because the
nominal radius closes linearly) rather than a per-frame accumulator — which
would make the figure depend on frame rate and on `SimulationLod`'s step size,
a bug this system has produced three separate ways. The courtship dance now
flies that same primitive with its own radius, turn rate and breathing band,
so there is one implementation of the geometry and not two.

**Both partners of a pair still agree without messaging.** A pair derives its
whole dance from the two instance ids and each partner's own offset from the
shared midpoint. The midpoint *is* the midpoint, so the two start offsets are
exactly opposite by construction — which is also what made `is_leader`
unnecessary rather than merely redundant. Two partners easing in over different
durations would converge onto different radii and stop reading as a pair; that
is the subtlest risk in the whole change, and it is closed by construction
rather than by a tolerance.

**The ninth entry, which hid behind the other eight: the late join.** Markers
are processed one after another, and a flyer that scanned and came up empty
waits `PARTNER_SEARCH_INTERVAL` before scanning again — so the *second* of a
pair routinely joins a figure its partner began up to half a second ago, having
flown ordinary wander the whole time. It adopted the partner's clock and the
mirror of its start offset, which threw it onto the far side of an orbit it had
never been on: **17.3× its own airspeed on one frame**, measured at the full
delay, on top of every entry easing above. Both figures now **re-base** on
where the two actually are at that moment — at elapsed 0 a converging orbit is
exactly its own start offset, so *neither* flyer moves, and the midpoint is the
midpoint, so the two offsets stay opposite to the float. The clock restarting is
the price, and it is the right one: a whirl properly begins when both
butterflies are in it. This is the second of the two places one flyer writes
into another (the first is a flush telling its partner it bolted), and for the
same reason: "my partner has drifted since you committed" is not derivable, and
a pair holding two different centres is the one-butterfly-orbiting-an-empty-
midpoint failure all over again.

**The exit is the half that is easy to miss.** Position was always continuous
when a figure *ended*; velocity was not. On the frame a whirl ended the flyer
stopped orbiting at ~37 px/s and started wandering at 16 px/s along a heading
picked from its own seed — measured across eight whirls, a mean turn of **108°
on one frame, worst 168°**: a butterfly reversing instantaneously. The wander
heading now starts from the figure's own tangent and turns off it as hard as
the animal can turn and no harder, which is *derived*: a turn is flown by
banking, the hardest bank is `SpiralFlight.MAX_LOAD_FACTOR` times body weight,
and at speed `v` that is a turn rate of `a/v` (`SpiralFlight.turn_seconds`).
Measured after: mean **8.3°**, worst **12.0°**, against a physical single-frame
budget of 14.8°. The turn is a **slerp**, never a componentwise blend — two
nearly-opposed headings blended componentwise give a near-zero vector, which is
the "flyers stall and jitter on a fixed spot" bug this system has produced
three times. The *speed* is left to drop on its own: coming off a burst and
settling to a cruise is a deceleration, which an animal does abruptly in a way
that reversing direction is not.

Ending a courtship now also charges the whirl cooldown, which
`_end_player_dance` already did and this did not. `SPIRAL_DUTY_CYCLE` is
derived from a real *time budget* — roughly 5–15 % of a territorial
butterfly's active time goes into aerial interactions — and a 4.5 s dance is
aerial-interaction time by any reading, so falling straight out of a dance into
a whirl spent that budget twice. It was also the one figure-to-figure handover
this system could produce, and the velocity turned 57° across it however
carefully each figure eased its own entry.

**The wings swap on one frame too.** Two cheap, exact fixes, and no crossfade:

- **Landing.** A butterfly alights with its wings **spread** and folds them
  afterwards. The settled cycle was read off wall time, so an insect that had
  just been beating its wings was usually drawn fully shut on the very next
  frame. It now starts at the top of the basking swing
  (`NectaringPosture.seconds_to_open`) and closes from there, over the
  `OPENING_SECONDS` that already existed.
- **Take-off.** A real butterfly opens its wings and beats. The wing clock
  free-runs, so the stroke resumed at whatever frame wall time was on — folded
  over the back to mid-downstroke in one frame. Flap frame 0 is the fully-open
  pose *by construction* (`ProceduralButterflySprite.generate_flap_images` has
  openness 1.0 at `i = 0`), so the clock is re-based there on take-off. Scoped
  to flyers that have a settled pose, because frame 0's meaning is a property
  of the butterfly generator and a bird's sequence makes no such promise.

A frame-level **crossfade** was considered and rejected: blending two pixel-art
sprites produces semi-transparent ghosting that reads as a rendering artefact
rather than as motion, and it would want a second `Sprite2D` or a shader per
flyer across hundreds of them, in a project that has just been through a
performance pass.

**Left alone, deliberately: the flee onset.** `ESCAPE_SPEED_MULTIPLIER` applies
instantly — 16 → 40 px/s on one frame, measured, alongside a 151° turn away
from the player. The turn *is* the behaviour rather than an artefact: that is
what a flush is, and it is the whole flight-initiation-distance model. The
speed step is a fifth of a second's worth of real acceleration compressed into
17 ms, against a simultaneous 151° turn that nobody could see past; and easing
it would need an acceleration constant this game has no grounding for, which is
exactly the eyeballed number the process forbids.


## Courtship, and where births come from

Reproduction used to be a number going up. Animals of the same kind now
**notice each other, dance, and sometimes mate** — so a population growing is
something the player can watch happen rather than something they infer from
there being more deer than yesterday.

This section covers **pollinators** specifically — the tight synchronized
orbit below (`Courtship.dance_offset`) is a butterfly's courtship flight, and
reads as a bird (or a horse) glitching in place on anything that doesn't fly
that way (`Courtship.dances()` gates it to `DANCING_SPECIES` for exactly this
reason). Land mammals get their own walking equivalent — see "Land-mammal
courtship: a walk, not a solo spawn" above — which reuses this section's
pairing/leader/mating *primitives* directly rather than duplicating them.

- **Same kind only, and only nearby.** Two animals of one species within a
  short radius may pair off. A monarch and a swallowtail share a meadow, not a
  lineage. (They do chase each other, though — see "Two butterflies meeting"
  above, which is the common interaction and this the rare one.)
- **They circle each other.** Leader and follower orbit a shared midpoint on
  opposite sides, so a pair reads as two animals interacting rather than two
  sprites overlapping. Neither sends the other a message: both compute who
  leads, and whether they mated, from the same two instance ids, which is also
  why a partner vanishing mid-dance is harmless.
- **Both of them dance.** The second of a pair joins the dance the first
  started, adopting its clock, its midpoint and its round — which is what makes
  them end together and agree on whether they mated. This was broken for as
  long as courtship existed; see "Why the player never saw any of this".
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
- **How many "so many" is, for a flyer, is the meadow's own answer**
  (`AmbientFlyerRenderer.max_flyers_per_chunk`). The pollinator half of that
  ceiling is scaled by the same `ScentField.pollinator_spawn_multiplier` the
  spawn pass is handed on load, through the one shared `scented_budget`
  formula both read. Summing the raw per-species constants instead made the
  ceiling a stale number the moment pollinator spawning became scent-driven:
  a bloom-rich chunk legitimately spawned *past* it on load (measured: 24
  flyers against a ceiling reporting 14), so the guard then refused every
  courtship birth in precisely the meadows most worth breeding in. The fix
  scales the ceiling rather than clamping the spawn pass, because the
  multiplier **is** the carrying-capacity signal — a meadow supports what it
  supports, and the scent field is how this world measures that. Boundedness
  costs nothing here: `pollinator_spawn_multiplier` already saturates at
  `MAX_SPAWN_MULTIPLIER`, so no second flat cap is needed on top. Birds are
  deliberately not scaled on either side — a robin is not a pollinator, and
  its numbers come from its own aggregate population.
- An individual death in front of the player **lowers the region's aggregate**
  the same way a birth raises it (`EcosystemSimulation.record_death`,
  `is_predator` selecting which population it subtracts from) — the mortality
  counterpart of the birth rule above, and of fishing's own `record_catch`
  (see [fishing.md](fishing.md#harvest-fishing-as-the-mortality-term)). This
  used to be a genuine, explicitly-named gap: a predator eating a herbivore,
  or the player's own weapon, despawned the individual marker but never told
  the aggregate, so a hunted valley only ever emptied out cosmetically —
  the very next chunk reload re-seeded it at fresh carrying-capacity
  equilibrium regardless of how thoroughly it had just been hunted. The fix
  sits at `CreatureMarker.take_damage`'s death branch, since that is the one
  place a kill is actually finalized for both causes: a predator's own
  hunting AI and the player's weapon both route through it.


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
