## Flora: DNA, seed dispersal, and plant-animal coevolution

[world.md](world.md)'s vegetation model tracks density per cell as an
aggregate (sunlight + moisture → growth toward local carrying capacity).
Fruit/seed-bearing flora goes one level deeper: individual trees carry
their own DNA, and animal foraging becomes a real selective force on that
DNA over time — the same "promote to individually-simulated agent near a
player" pattern [world.md](world.md) already uses for animals, applied to
fruiting trees instead of leaving them purely in the density field.

### The loop

1. **Trees have DNA-driven fruit/nut traits** — size, sugar/nutrition
   content, "tastiness," color/visibility, seed-coat toughness — same
   common → rare → legendary tier vocabulary as everything else
   ([dna.md](dna.md)).
2. **Animals forage preferentially.** Foraging is simple and
   one-directional: a species has a fixed preference profile (e.g. birds
   favor color/visibility, bears favor size/sugar) and, given a choice,
   deterministically favors the higher-scoring fruit available. Animal
   *preference itself* doesn't evolve — only the trees respond to it. This
   keeps the simulation tractable while still producing the interesting
   loop: the tree side is where the emergent depth actually lives.
3. **Disperser vs. predator roles, per species-plant pair.** Some species
   are **dispersers** (swallow fruit whole, the seed survives digestion and
   gets deposited elsewhere — birds, large herbivores); others are **seed
   predators** (crack/destroy the seed itself for the kernel — squirrels
   and other nut-crackers). This creates real tension in what a tree
   evolves toward: a trait that attracts more foragers overall (bigger,
   more visible fruit) can also attract more seed-predators, not just more
   dispersers. A species isn't free to just maximize "attractive," it has
   to navigate who it's attracting.
4. **Seeds establish two ways, with very different odds:**
   - **Local self-seeding** (fallen/uneaten fruit rotting near the parent)
     is the *default, ordinary* way forests spread and reproduce — this
     is baseline, not a fallback. Success rate is real but suppressed by
     proximity to the parent (crowding, shared pests/pathogens — the
     real-world "Janzen-Connell effect").
   - **Animal dispersal is a bonus on top**, not a requirement: a
     disperser-eaten seed lands away from the parent, escaping that local
     competition, and establishes considerably more reliably as a result.
   - This is the actual mechanism of selection: a tastier/more visible
     fruit doesn't just get eaten more, its seeds land somewhere better —
     so over generations, populations under real foraging pressure trend
     toward traits that win disperser attention over predator attention,
     without a species with mediocre fruit ever being at risk of total
     extinction the way "dispersal-only" reproduction would risk.
5. **DNA inheritance follows the same model as animals**: offspring DNA is
   the parent's genetics plus mutation chance, same as
   [evolution.md](evolution.md)'s animal reproduction — a local seedling
   and a disperser-planted seedling both inherit and vary from the parent
   the same way, they just have different odds of surviving to maturity.

### One shared DNA model with farmed crops

[farming.md](farming.md)'s crop-breeding system and this wild-flora system
are **the same underlying plant-DNA machinery**, not two parallel systems.
This closes farming.md's own open question: a selectively-bred farm seed
that escapes cultivation (blown or carried off a farm plot, or a fruit a
tamed/wild animal steals and disperses) can establish as a wild plant
carrying cultivated traits, and conversely a wild plant with an unusually
good trait roll is legitimate starting stock for domestication. Player
farming and wild-forest evolution are two access points into one
population, exactly like taming interacts with the wild animal population
in [evolution.md](evolution.md) and [pets.md](pets.md).

### Climate and water: abiotic selection alongside animal selection

Foraging isn't the only pressure shaping tree DNA — climate/water
([world.md](world.md)'s existing sunlight+moisture model,
[weather.md](weather.md)'s droughts) selects too, and does it the same
way: by killing less-suited individuals rather than by uniformly scaling a
density number.

- **Drought/climate tolerance is itself a DNA trait**, same rarity
  vocabulary as fruit traits. When a sustained drought
  ([weather.md](weather.md)) hits a region, it doesn't reduce every tree's
  local density equally — it kills low-tolerance individuals
  preferentially. Surviving, reproducing trees skew hardier, so the
  population's *average* tolerance genuinely drifts after a bad drought,
  the same way a phenotype target drifts under foraging pressure
  ([evolution.md](evolution.md)). Two independent selection pressures —
  animal-mediated (fruit traits) and climate-mediated (tolerance traits) —
  act on the same DNA at once.
- **Mast fruiting**: fruiting isn't constant year-round output — a good
  rain year triggers a synchronized, region-wide heavy-fruiting pulse
  ("masting," a real phenomenon). A mast year floods the area with far
  more fruit than seed-predators can consume, which shifts the
  disperser-vs-predator ratio (see the loop above) sharply toward
  successful dispersal in that specific year — predators hit a ceiling on
  how much they can eat/destroy, dispersers don't. This makes masting both
  a real evolutionary lever (good-rain-year reproduction matters
  disproportionately) and a visible player event: a mast year is when you
  go fruit-hunting, and it's driven by the same rain/season clock as
  everything else in [weather.md](weather.md), not a separate calendar.
- **Forests visibly migrate over long timescales.** Same "no fixed spawn
  zone, exists wherever conditions make it viable" philosophy
  [world.md](world.md) already applies to boars, applied to trees: a
  persistent local drying trend means fewer seedlings survive to maturity
  at a forest's dry edge while more succeed at its wetter edge, so the
  forest's actual footprint creeps across the map over many in-game
  seasons. Slow and background, but a real, observable long-term
  consequence of [weather.md](weather.md)'s climate trends rather than
  forests being permanently fixed at their worldgen placement.

### Ancient trees: emergent legendary flora

The same fitness-threshold emergence [worldbosses.md](worldbosses.md)
defines for apex predators applies to flora: an individual tree that has,
through the ordinary DNA/selection loop above, survived enough droughts,
disease, and competition to reach extreme age and trait quality crosses a
threshold and becomes a named, unique, legendary landmark — an ancient
oak that's outlived every drought in the region's simulated history. Like
a world boss, it's emergent (a real outcome of that world's actual
climate/foraging history, unique per world) rather than hand-placed, and
becomes an [exploration.md](exploration.md) point of interest: an
exceptional seed source, rare crafting material
([crafting.md](crafting.md)), and a legitimate destination to seek out —
"find the oldest tree in the forest" as a real, simulation-grounded goal
rather than a flavor label on a hand-authored unique.

### Player-facing payoff

Same dual payoff pattern as animal rarity: a grove that's evolved
exceptional fruit (through generations of real disperser pressure, or
through isolation from predators) is a discoverable, desirable resource —
better [cooking.md](cooking.md) and [crafting.md](crafting.md) inputs, and
a legitimate rare-seed-hunting activity parallel to rare-animal-taming.
Overharvesting or clearing a good grove has the same population-level
consequence removing rare animals from the wild does.

### Named species: Cherry, Apple, Walnut

The fruit/nut DNA loop above was, until this pass, entirely anonymous:
`TreeGenome.species_bias` (0 = nut .. 1 = fruit) picked a canopy tint, but
there was nothing a player could actually point at and call "a cherry
tree." Three named species anchor that same spectrum — Walnut at the nut
end, Cherry and Apple at the fruit end — without inventing a second trait
axis: `species_bias` still IS the fruit-vs-nut lean, it now just resolves
to a name instead of a raw float.

- **Walnut** (`species_bias` in the bottom third) — a real walnut is a
  slow, long-season bearer: a comparatively small, high-value crop that
  ripens late (the husk-to-kernel process runs well into autumn). Modeled
  as a below-1 yield multiplier and an above-1 ripening-time multiplier on
  top of the genome's own raw traits (see `FruitingModel`).
- **Cherry** (middle third) — real cherries ripen fast (as little as two
  months from bloom) and bear prolifically in small fruit. Modeled as an
  above-1 yield multiplier and a below-1 (faster) ripening multiplier —
  the opposite lean from Walnut.
- **Apple** (top third) — a solid, moderately fast, heavy-bearing orchard
  fruit that sits between the two; kept at the original undifferentiated
  fruit-leaning tree's baseline multipliers (1.0/1.0), so the fruit-anchor
  end of the spectrum's behavior is unchanged from before named species
  existed.

Canopy colour, ripe-fruit-dot colour, and the item a fallen fruit drops as
are all keyed off the SAME named species — a walnut canopy reads as a
deeper, duller green than a cherry or apple's, and its fallen "fruit" is a
green-brown husk colour, not the bright warm red an apple/cherry drops. A
tree's species is still a pure function of its own position (via its
genome's `species_bias`), never stored per-tree state — the same "no
stored DNA, position derives everything" model this whole system already
runs on for spread saplings (see `TreeSpread`).

### Bird endozoochory: swallowing the seed, not just carrying it

The disperser-vs-predator loop above describes two very different
mechanisms by name; this pass builds the disperser half for trees
specifically — a bird that eats a fallen fruit and later deposits its
seed elsewhere, distinct from the flower epizoochory
([below](#spread-by-animal-seed-dispersal)) already in the game, where
seed merely rides on a grazer's coat.

- **Who disperses**: the robin — already a ground-foraging insectivore
  (see [soil_fauna.md](soil_fauna.md)) — gains fallen fruit as a second
  diet entry. Real robins genuinely are omnivores that switch onto soft
  fruit/berries once available, especially outside the breeding season, so
  this is a grounded second food for an existing species rather than a new
  one invented just for this mechanism.
- **Eating is landing, not proximity**: fallen fruit sits on the ground
  exactly like an earthworm does, so a fruit-eating bird goes through the
  same seek → descend → peck → resume cycle soil_fauna.md already
  specifies for worm-hunting, just aimed at a different target.
- **Carry is a real DISTANCE, flown in an actual heading** — resolving the
  "how far" open question below: a swallowed seed is sized a target
  distance (`SeedEndozoochory.carry_distance_tiles`, 10–40 tiles, grounded
  in a real small-bird gut-passage estimate of roughly 15–60 real minutes)
  and a random heading to fly off in (`carry_direction`), and the carry
  resolves only once the bird has actually flown that far from where it
  ate — the same carried-tiles-since-origin idiom the mammal epizoochory
  case below already uses. This deliberately carries a seed FURTHER than a
  grazer's epizoochory range (flower spread's 3–14 tiles) — a bird is
  airborne and takes longer to pass a seed than a grazer takes to shed one
  off its coat, so real endozoochory routinely disperses seed well beyond
  a ground animal's epizoochory range.
  - **This used to be a fixed TIME budget instead** (distance converted to
    elapsed flight time at the bird's own speed, then simply waited out) —
    changed after being measured, not merely suspected: a bird's ordinary
    wander is anchored to a home point within a fairly tight radius
    (`AmbientFlyerMovement.direction_at`), so a bird whose home never moved
    could never actually get further than roughly that radius from wherever
    it started carrying, however long the timer ran. Measured directly at a
    hard ~2.5-tile ceiling for a sparrow, for every one of 30 sampled
    wander_seeds, against the 10–40 tile range intended above — the
    dispersal mechanism was firing on schedule but depositing seed only a
    couple of tiles from the parent plant almost every time. Giving the
    carry an actual heading to lean into (blended with ordinary wander, not
    replacing it — a carrying bird should still read as wandering, just
    wandering with somewhere to get to) and resolving on real distance
    travelled rather than elapsed time closes the gap without inventing a
    new movement system: resolving on real distance is the exact shape
    ground carriers already used (see below) — but it turned out ground
    wander (`CreatureWander`) is home-tethered the SAME way flying wander
    is, not exempt from this bug the way this section used to claim. Ground
    carriers needed (and got) the identical heading-to-lean-into fix; see
    "Spread by animal seed dispersal" below for the measurement.
- **Where it can land**: forest/rainforest only — the same biomes trees
  themselves grow in, not grassland (unlike flower seed, which is a
  meadow plant). A seed digested over open grassland or ocean is simply
  lost, the same honest "not every drop succeeds" flower dispersal already
  models.
- **Only one seed at a time**: a bird carries at most one swallowed seed;
  eating a second fruit while still digesting the first doesn't reset or
  overwrite the timer. A real bird's crop holds roughly one meal's worth
  in flight before the next matters, and this keeps "which species gets
  planted" unambiguous.
- **Species inheritance is the same as ground spread, not stronger**: a
  bird-planted sapling reuses the exact planting sink `TreeSpread`'s own
  ground-planted saplings use, which means its actual rendered species is
  whatever its LANDING position's own genome resolves to — not
  force-inherited from the exact fruit the bird swallowed. This matches
  (rather than fixes) an existing property of this codebase's tree
  genetics: `TreeGenome.mutate()`'s child genome is computed by
  `TreeSpread.propose_saplings` but never actually threaded through to the
  planted record, so even an ordinary ground-spread sapling's species is
  position-derived, not inherited from its parent tree either (see
  [ecosystem_dynamics.md](ecosystem_dynamics.md)'s status list). Fixing
  that inheritance gap for BOTH spread mechanisms at once is a reasonable
  follow-up; making bird dispersal alone force-inherit species would have
  made the two mechanisms behave inconsistently instead.

### Open questions

- Exact trait list and per-species preference/predator-vs-disperser
  tagging — needs a first content pass once implementation starts.
- Does seed-coat toughness (a plausible DNA trait) actually gate which
  species *can* act as a disperser vs. predator for a given tree (a
  toughness threshold a predator's bite can't crack), or is the
  disperser/predator role fixed per species-pair regardless of trait
  values?
- ~~How far does animal-mediated dispersal actually carry a seed~~ —
  answered for bird endozoochory above (a real target distance grounded in
  gut-passage time, resolved on actual distance travelled in an actual
  heading, further than ground epizoochory); still open for whether other
  future dispersers (large herbivores) should use the same distance-based
  model or one tied to their own migration/home-range behavior instead.
- ~~No seed PREDATORS exist yet~~ — partially answered: a sparrow eating
  bare GROUND seed (flower/grass, see [Bird endozoochory: flowers spread
  where birds go](#bird-endozoochory-flowers-spread-where-birds-go)) now
  destroys the large majority of what it eats rather than always
  dispersing it (`SeedEndozoochory.GRANIVORY_CONSUMED_CHANCE`), and that
  chance is now trait-driven per individual: each bird's own `AnimalFitness.
  fitness_score` (its `wander_seed`-derived phenotype) nudges ITS personal
  consumption chance a few percentage points around the flat base
  (`SeedEndozoochory.consumption_chance_for`/`FITNESS_CHANCE_SWING`), rather
  than every sparrow rolling against the exact same number — bounded so the
  large-majority band holds for every individual, not just on average.
  ~~Still open for FRUIT/nut seed specifically~~ — answered: a real squirrel
  species (`CreatureInfo`/`AnimalAnatomy`/`ProceduralAnimalSprite`, herbivore-
  role, forest-only) now scatter-hoards fallen tree NUTS specifically
  (`TreeSpecies.is_nut` — pine/acorn/hazelnut/walnut, not cherry/apple)
  exactly the way a real scatter-hoarding rodent does: it picks one up,
  carries it a short ground distance (`SquirrelNutCaching`, the same
  find-carry-resolve shape `SeedCaching` already established for a mouse's
  grass seed, wired to `fruit_near`/`take_fruit_at` instead), and mostly eats
  it outright (`SquirrelNutCaching.NUT_CONSUMED_CHANCE`, real predation) but
  sometimes caches it into a brand-new sapling via the same tree-seed sink
  robin's own fruit dispersal already uses (`try_plant_seed_at`). Fleshy
  fruit is untouched by this — a squirrel finding a fallen cherry/apple just
  eats it like any other fruit-eating forager, nutritionally a
  disperser-or-nothing exactly as before. The disperser-vs-predator TENSION
  this doc's "The loop" section describes is now a real selective force for
  BOTH ground seed and fruit/nut seed. Now trait-driven per individual too,
  exactly mirroring the sparrow's own treatment: each squirrel's own
  `AnimalFitness.fitness_score` (its `wander_seed`-derived phenotype) nudges
  ITS personal consumption chance a few percentage points around the flat
  base (`SquirrelNutCaching.nut_consumption_chance_for`/
  `NUT_FITNESS_CHANCE_SWING` — 0.06, same magnitude as the sparrow's own
  swing), rather than every squirrel rolling against the exact same
  `NUT_CONSUMED_CHANCE` — bounded so the majority-but-not-certainty band
  holds for every individual, not just on average.
- True DNA inheritance for spread saplings (ground- or bird-planted) — see
  the species-inheritance note above.

### Status

- ✅ Named species catalog (`TreeSpecies`: Walnut/Cherry/Apple, each with
  canopy colour, fruit colour, and yield/ripening multipliers layered on
  `FruitingModel`).
- ✅ Fallen fruit renders as a real, visible, per-species-coloured ground
  entity (`DroppedItem`, via the existing `WorldItemBus` pipeline) that
  herbivores/omnivores already eat (`FoodConsumption`).
- ✅ Bird endozoochory (`SeedEndozoochory` + `AmbientFlyerMarker.fruit_world`/
  `_carried_seed_species` + `EarthChunkManager.fruit_near`/`take_fruit_at`/
  `try_plant_seed_at`): a robin eats fallen fruit, carries the seed for a
  gut-passage-timed interval, and plants a sapling of whatever species its
  landing position resolves to.
- ✅ Seed predators for GROUND seed (flower/grass) — see the "flowers spread
  where birds go" section's own status entry above.
- ✅ Seed predators for FRUIT/nut seed (`SquirrelNutCaching` + a real
  `squirrel` species): crack-or-cache tension for real tree NUTS
  specifically (`TreeSpecies.is_nut`), mirroring the mouse's grass-seed
  scatter-hoarding shape — see Open questions. Fleshy fruit (cherry/apple)
  is still pure dispersal-or-nothing, untouched by this.
- ⬜ True DNA inheritance for spread saplings (both ground- and
  bird-planted) — see Open questions.
- ⬜ Mast fruiting, drought/climate tolerance trait, ancient-tree emergence
  — unchanged from before this pass, still not started (see
  [ecosystem_dynamics.md](ecosystem_dynamics.md) and `progress.md`).

## Flowering plants, scent, and pollinators

## Seed: the other half of a flower's year

A meadow feeds two different guilds at two different times, from the same
plants:

- **In bloom** a flower offers **nectar**, which pollinators drink (see
  PollinatorForaging). Nectar refills over about a minute.
- **Out of bloom** the same flower **sheds seed**, which falls to the ground
  nearby and lies there as **its own entity** — not a state of the plant.
  Granivores (sparrows) eat it off the ground.

Seed being a real object rather than a property of a flower is the point: it
accumulates *around* the parent plant, so a meadow visibly reads as a seed
source; a patch birds have picked clean looks different from an untouched
one; and — decisively — there is something on the ground for a bird to fly
down to. Seed attached to the plant was invisible, and a sparrow pecking at
bare grass is the world lying about what is there (see
[What is visible must be what is real](#what-is-visible-must-be-what-is-real)).
Seed falls only a cell or two from its parent. Carrying it further is what
*animals* do, and that distinction is the whole reason animals matter for
spread.

That falls straight out of the bloom table already in `FlowerSpecies`: a
species advertising nectar in spring is setting seed in summer, and its
neighbour does the reverse. Nothing new has to be placed in the world, and
the seasons acquire a real consequence beyond which blooms are drawn: which
*guild* a given meadow supports rotates through the year. A sparrow that
finds nothing in a spring meadow full of crocus finds plenty in the same
meadow in autumn.

Seed regrows more slowly than nectar. A plant refills a drained nectary in
minutes; it sets seed once, and a picked-over patch stays picked over for a
good while.

### Bird endozoochory: flowers spread where birds go

A sparrow that eats seed carries it, and — most of the time — destroys it.
A real granivorous songbird is a seed PREDATOR first: its gizzard grinds up
the large majority of what it swallows, and only a minority survives gut
passage to actually be planted (`SeedEndozoochory.GRANIVORY_CONSUMED_CHANCE`,
closing the "no seed predator exists" gap named below and in
[ecosystem_dynamics.md](ecosystem_dynamics.md)). Not every bird is an
identical predator, either: each individual's own `AnimalFitness.
fitness_score` (derived from its `wander_seed`, the same per-individual seed
`AmbientFlyerMarker` already carries) nudges its personal chance a few
points around that base (`SeedEndozoochory.consumption_chance_for`), a
fitter forager being a slightly more efficient one — bounded so it is
always still a large majority, for every bird, never a coin flip or a
certainty. When a seed does survive,
it plants where it later drops — the same carry-then-drop shape as the
mammal epizoochory above
([Spread by animal seed dispersal](#spread-by-animal-seed-dispersal)) and
the robin's tree dispersal (`SeedEndozoochory`), and for the same design
reason: flower spread follows the ecosystem's real movement corridors
rather than a tile-adjacency rule. The difference is range. A mammal brushes
a bloom and carries seed a few tiles; a bird eats it, flies, and drops it
much further, so a surviving seed still travels further than a grazer could
carry one, and granivorous birds remain how meadows colonise ground no
grazer walks — just less often than every seed eaten. A seed dropped where
flowers cannot root (ocean, rock, forest floor) is simply lost — the same
honest check on spread every other dispersal path uses.

This predation gate is deliberately GROUND seed only (flower and grass seed
picked bare off the ground) — it does not apply to the tree-fruit case
above ([Bird endozoochory: swallowing the seed, not just carrying
it](#bird-endozoochory-swallowing-the-seed-not-just-carrying-it)): a fleshy
fruit exists specifically so the seed riding inside it is swallowed whole
and passed unharmed, a real mutualism between the tree and its disperser,
whereas a bare seed IS the meal for a true granivore. That is also why this
doesn't fold into that section's own status list — it is a different
mechanism on a different food source, even though the carry-then-drop
machinery (`SeedEndozoochory`) is shared.

## What is visible must be what is real

A flower drawn on the ground is a promise that a pollinator will visit it.
Only species actually **in bloom this season** are rendered; a planted flower
out of its bloom window is still there and still simulated, it simply isn't
showing a blossom — which is also what a real meadow looks like.

The rule extends one step further than it currently reaches: a bloom that has
**gone over** should be drawn as gone over. `FlowerBloom.is_withered`
(`WITHER_PHASE`, the last quarter of a species' own window) is read LIVE
every tick when a pollinator picks a target — a bee already refuses a flower
past its phase — but the withered look is chosen once, at the instant the
sprite is generated, and never refreshed. A daisy drawn early in spring
therefore keeps fresh-bloom art right through autumn and then simply
vanishes, while the bees have long since stopped visiting it. That is the sim
and the picture openly disagreeing, which is exactly what this section
forbids. Recorded as an open item below rather than silently tolerated.

This is a specific instance of a general rule this project learned twice the
hard way: **the rendered world must not advertise something the simulation
will not honour.** Flowers were drawn year-round while `ScentField` correctly
gave out-of-bloom species exactly zero scent, so pollinators ignored perfectly
good-looking blooms and the whole foraging feature read as broken. The
simulation was right; the world was lying. Bloom is therefore filtered at the
single point every consumer reads — rendering, scent-steering, and
target-choice all agree about what is on offer, rather than each deciding
separately.

Grassland currently gets a few flat flower pixels baked into its tile art
(see `ProceduralTerrainSprite._paint_flowers`) -- decoration with no species,
no life cycle, and nothing that reacts to it. This makes flowers a real part
of the ecosystem, and gives butterflies and bees a reason to be where they
are instead of wandering uniformly.

### Illustrated head art: one kit per archetype, not per species

Procedural pixel art hit a real quality ceiling here, the same one animal art
hit before it (see `IllustratedAnimalSprite`'s own doc comment: "the
procedural generated sprites are too bad... let's switch to illustrated
ones"). The fix follows the same shape, but at a finer grain than "one
species, one sheet": a flower BLOOM HEAD's shape (see
`ProceduralFlowerSprite.HEAD_SHAPE_BY_SPECIES` -- cup/layered/spike/puff) is
what differs structurally between species; colour (`FlowerSpecies.
color_for`) and world size (`height_tiles`) are already separate, data-driven
axes applied at runtime. A real crocus and a real tulip share the same
shallow-open-cup shape and differ only in colour and size -- so one
illustrated sheet per ARCHETYPE covers every species that maps to it, and a
new species costs zero new art (a data entry, not a commission). See
`docs/art/ai_sprite_prompts.md` for the actual generation prompts and
`IllustratedFlowerHead` for the loader (mirrors `IllustratedAnimalSprite`'s
"hand-drawn sheet -> `SpriteSheetSlicer` -> cached frames" shape exactly).

Each archetype sheet is a 4-stage bloom progression -- bud, opening, full
bloom, spent -- authored in a pale/neutral base tone specifically so it can
be colour-tinted per species at runtime (a multiply blend, preserving the
art's own shading rather than flattening it). `ProceduralFlowerSprite`
composites the illustrated head onto its own procedural stem/leaves, and
falls back to the original procedural painter entirely for any archetype
with no sheet yet -- the same has-art-or-doesn't fallback
`IllustratedAnimalSprite` documents. Only "cup" (crocus, tulip) has a sheet
so far; layered/spike/puff still draw procedurally, unaffected.

This also closes a real "what is visible must be what is real" gap: nectar
depletion (`FlowerPatch.nectar_at`) previously had zero visual effect --  a
bloom at 1% nectar rendered identically to a full one, so a pollinator
correctly skipping a near-empty flower looked to the player like it was
ignoring a good one. An illustrated head now shows its "spent" frame below
`ProceduralFlowerSprite.SPENT_NECTAR_THRESHOLD`, so a foraged-out bloom
visibly reads that way. The stage is picked once, at sprite-creation time
(nectar's already-established default is 1.0 -- a fresh bloom, see
`FlowerPatch.plant` -- so this reads correctly in the common case); it does
not yet update live as an already-rendered bloom is foraged down, which
would need `_sync_flower_sprites` to revisit existing sprites, not just add
newly-blooming ones (see its own "unlike grass tufts there is no growth
animation" comment) -- a separate, tracked follow-up, not attempted here.

The bud/opening frames are sliced and cached by `IllustratedFlowerHead` but
not yet drawn by anything: a currently-rendered flower is always already in
bloom (`FlowerPatch.blooming_cells` only surfaces blooming cells at all), so
there is no live "still opening toward its first bloom" state to show them
for today. They stay fully built and tested rather than half-shipped, ready
for whenever growth-stage rendering is added.

### Species

Distinct flowering species rather than one generic "flower", each with its
own bloom season, colour, and how strongly it advertises itself:

- **Crocus** — earliest bloomer (late winter/early spring), low-growing,
  modest scent. The first pollinator food of the year.
- **Tulip** — spring, showy colour but comparatively weak scent (true to
  life: tulips are visually advertised, not strongly aromatic).
- **Rose** — summer, the strongest scent in the roster and the anchor of a
  mature meadow.
- **Lavender / clover** — long mid-season bloom, moderate scent, the
  workhorse nectar source that keeps pollinators resident between the
  showier species.

Colour and scent are deliberately *independent* axes, so a visually loud
meadow is not automatically the most attractive one to a bee.

### Scent as a diffusing field

Each blooming flower emits scent. Concentration at a point is the **sum** of
every nearby flower's contribution, falling off with distance -- so a dense
patch is not merely "more flowers", it is a genuinely stronger signal than
the same flowers scattered thinly. That superposition is the whole point:
it makes clumping mechanically meaningful.

Grounding: real floral scent is a volatile-organic-compound plume that
disperses with distance and wind. This models the steady-state concentration
rather than simulating individual molecules -- the right fidelity for a
top-down tile game, and honest about being an approximation (the same
stance `water.md`'s wave model takes).

Scent only counts while a species is actually **in bloom**, so a meadow's
pull rises and falls across the season rather than being a constant.

### Pollinators follow the gradient

Butterflies and bees (see `AmbientFlyerRenderer`) use the field two ways:

- **Spawn rate** scales with local concentration, so heavily flowered
  meadows are visibly busier than bare grass.
- **Movement** biases up the concentration gradient, so flyers drift toward
  and linger around dense patches instead of wandering uniformly.

The result is emergent rather than scripted: nothing places butterflies at
flowers: they accumulate there because that is where the signal is strongest.

### Foraging is a cycle, not a stable attractor

Steering alone has a stable attractor at the strongest bloom -- arriving
there and continuing to steer toward it just oscillates forever. Real
foraging cycles: land, drink, and move on to a flower you haven't just
emptied.

Two pieces of memory make that work, in different places on purpose (see
`PollinatorForaging`):

- the **flower** remembers it was drained (nectar 0..1, refilling slowly
  over time via `NECTAR_REGEN_PER_SECOND`), so a bloom is a depleting
  resource rather than an infinite one;
- the **pollinator** remembers which flowers it personally visited, so it
  moves on even while a flower is still refilling, and two insects don't
  lock onto the same bloom. This is **time-based** (`VISIT_MEMORY_SECONDS`,
  ~10 minutes), not count-bounded: a pollinator with only one or two flowers
  in range would otherwise exhaust a small fixed memory on them and have
  nowhere left to go until something aged out by count, which never happens
  if nothing new is ever visited. A ceiling (`MAX_REMEMBERED_VISITS`) bounds
  it in the other direction, since a continuously-foraging pollinator banks
  a visit every few seconds and every entry is distance-checked on every
  sniff; the newest entries are the ones kept.

That memory **ranks candidate flowers, it does not blacklist them.** As a
veto it produced the opposite of foraging: a pollinator worked the flowers
in its reach dry in about a minute and then did nothing whatsoever for the
next nine, resuming only as the memory expired — even though every one of
those flowers was back to full nectar within ~20 seconds. The memory is
meant to be long enough not to re-land on a bloom that has not refilled
yet, but at ~30x the actual refill time it was refusing a meadow that had
already recovered. A bloom that was just drained is excluded by its nectar
level anyway, so preferring-but-not-refusing keeps the "work across the
meadow rather than re-drink one flower" behaviour without the idle spell.

### Ranging further when a neighbourhood is worked out

Scent is how a pollinator picks its way around a patch it can already
smell. It is *not* how it finds the next patch: a flower's scent carries
only `ScentField.RADIUS_TILES`, so a flyer that had emptied everything
within that radius had nothing left to steer by and fell through to
undirected drift permanently (reported: "when all nearby are empty
butterflies and bees stop foraging completely and just drift around
meaninglessly", "they are not attracted by the scent anymore it seems").

Two things fix that, both grounded in how real bees forage well beyond the
range any single bloom advertises over:

- the forage search runs at `FORAGE_SEARCH_TILES`, well past scent range,
  so a worked-out neighbourhood is a reason to look further rather than to
  give up. The wider flower list does not distort the steering — scent
  falloff is exactly zero past its own radius, so the extra flowers affect
  only which bloom is chosen.
- committing to a distant flower **moves the flyer's wander anchor** to it.
  Ambient flight is tethered to a home point, and without this the flyer
  was dragged straight back the moment it arrived, so it could never take
  up residence in a new patch. With nothing forageable anywhere in range it
  instead relocates that anchor by `RELOCATION_STEP_TILES` — a discrete hop
  onto new ground, taken only once it has arrived at the last one, so the
  motion still reads as wandering rather than a straight-line chase.

Those hops are **leashed** (`MAX_RELOCATION_TILES`), and that leash is what
keeps searching from becoming a one-way trip. Unleashed, relocation is a
random walk with nothing pulling back: a flyer that found nothing kept
going, and once it was outside the chunks that hold flowers at all it could
no longer see anything, which triggered another relocation, which carried it
further still. Drift became an *absorbing state* — measured at 93 tiles from
spawn after ten simulated minutes, at which point a full meadow appearing
right where it started was invisible to it (reported: "don't resume foraging
when they encounter new flowers" — they never encounter any). The leash is
anchored to wherever the flyer last actually drank, not to a fixed spawn
point, so a pollinator's territory follows the food rather than pinning it
to ground that has since gone barren.

### Trap-lining: a forager works a circuit, not a flower

Real pollinators — bumblebees, butterflies, hummingbirds — forage a
repeatable **circuit** of blooms rather than re-working one. It has a name
(trap-lining) and a reason: a flower you have just emptied is the worst bet
in the patch, and the circuit exists so that the first stop has refilled by
the time you come back round to it.

Two rules make that happen, and both are strictly *tie-breaks inside the
distance band* above — neither can make a pollinator fly past a bloom it has
not checked:

- **Don't turn back.** `PollinatorForaging.moved_on_from` drops whichever
  tied candidate lies closest to the bloom this flyer has just worked, so it
  carries on round instead of shuttling between two neighbours. It has no
  distance constant of its own — "closest to the one just worked" is decided
  by the same ordering the band already uses — and it never empties the
  pool, because chaining beats idling.
- **The territory is the circuit.** The leash above is anchored on
  `PollinatorForaging.patch_centre`: the mean of the stops the flyer has
  made that have *not yet refilled*. That window is not a choice — the round
  a forager is currently on is exactly the set of blooms it has drained and
  which are still empty, so it is `NECTAR_REFILL_SECONDS`, itself derived
  from the regen rate rather than restated. Anchoring on the single **last**
  bloom instead (which is what shipped) followed the food but collapsed the
  circuit to a point: the whole search leash re-centred on one flower on
  every feed, so however many blooms the flyer was really working, its world
  was that one flower's neighbourhood. Reported as "butterflies still get
  stuck infront of a signle flower".

Visit memory also has to **outlast** the refill (90 s against 60 s), and
that relation is now pinned rather than incidental: if the two clocks agreed,
a bloom would become both legal and full on the same second, and the flyer
would go straight back to the flower it had just drained.

**Honest measurement.** The single-flower lock did *not* reproduce in a
headless sim of the shipped code — see `docs/progress.md` for the numbers.
What the sim did show is a revisit interval pinned exactly to the memory
window in every sparse layout tried. These two rules are the trap-line made
explicit; they are not a fix for a stall that could be measured offline.

### Pollinators scatter rather than queueing

Picking the single nearest bloom is the obvious rule and the wrong one:
every pollinator in an area computes the identical answer, so they follow
one another along one route and only the leader finds nectar — the rest
arrive at a flower that was drained seconds earlier (reported: "flyers
should randomly select the next flowers from the nearest so that not all
bees and butterflies fly the same route following each other and only the
first gets nectar").

Each pollinator therefore chooses among the nearest forageable blooms rather
than always the closest — but the pool is defined by **distance, not by
rank**. Only blooms within `SCATTER_BAND_TILES` of the nearest one count as
tied with it (`NEAREST_CANDIDATE_POOL` caps how many of those are kept).

Ranking alone was not enough, and the difference only showed up in a real
world. A fixed count of "the three nearest" is fine where blooms are evenly
spaced, but in an actual meadow the third-nearest is routinely two or three
times further than the first, so roughly two commits in three went to a
visibly further flower. Measured in a live Berlin world: mean chosen
distance 5.83 tiles against a mean nearest-available of 4.26, worst commit
14.40 tiles, and 9 of 24 commits more than 2 tiles worse than what was on
offer — "chose 8.5 (nearest 3.2)". To a player that reads as flying straight
past flowers without even checking them. With the band, the same measurement
over 400 commits gives mean chosen 2.74 against nearest 2.13, and 5 of 400
commits more than 2 tiles worse.

The band is absolute rather than proportional on purpose: a percentage
tolerance would license ever-sloppier choices the further out the nearest
bloom happens to be, which is the same failure again at longer range. The choice is seeded from the
flyer's own stable seed mixed with how many blooms it has picked so far, so
two pollinators in the same spot disagree, one pollinator's successive picks
vary, and everything stays deterministic and reproducible rather than
depending on global RNG state.

**Distance is decided before anything else, and that ordering is
load-bearing.** Selecting on unvisited-versus-remembered across the whole
flower list *before* considering distance let any unvisited bloom at any
range outrank every remembered one however close. Measured with a
pollinator's three nearest blooms in memory, its targets were the ones 20,
50 and 100 tiles away — it flew past a refilled flower a single tile from
its nose to cross the meadow (reported: "they ignore most flowers and target
some much further away than the nearest"). Because a continuously-foraging
flyer remembers precisely its own local patch, memory-first selection drove
it away from exactly the flowers it should have been working. So the near
pool is taken first, and visit memory only breaks ties *within* it: prefer a
bloom you haven't just drained, never at the cost of leaving the patch.

### Pollinators know what their neighbours are heading for

Seeded scatter turned out not to be enough on its own, and the reason is
structural: it can only decorrelate flyers when the distance band actually
holds more than one candidate. Measured in a real world, **the band holds
exactly one candidate 86.5% of the time** — so the seed usually has nothing
to choose between, every co-located flyer reaches the same answer, and
**62.1% of pollinator pairs within four tiles of each other were flying to
the same bloom**. The leader drains it and the followers arrive at an empty
flower: mean nectar found on arrival was **0.182**.

Widening the band to manufacture choice would just reintroduce skipping. So
pollinators share what they have committed to (`ForageClaims`, one claim per
flyer, keyed by flyer so the table can never outgrow the live population).

A claim is **intent, not ownership**, and is applied by demotion:

- it only ever reorders blooms *within* the distance band, so a claim can
  never send a flyer past a closer flower;
- if every candidate is spoken for, the flyer still takes one — chaining
  beats stalling with nothing to do;
- peers outrank visit memory, because heading for a neighbour's bloom means
  arriving at an empty one, whereas re-visiting a flower this flyer drained a
  while ago is merely second-best (it has had time to refill).

The scent gradient itself only knows which species are in bloom this
season, not any individual flower's current nectar level -- draining a
bloom doesn't reduce its scent. Left unfiltered, that meant a fully-drained
local patch kept pulling a pollinator's steering toward its exact position
just as strongly as a full one, even though it correctly refused to *land*
there -- which read as orbiting the one spent bloom instead of moving on to
a new patch. The flyer's own foraging step filters out drained flowers
before computing which way to steer at all, so an all-drained patch reads
as nothing to smell and ordinary wander actually carries it elsewhere.

### Spread by animal seed dispersal

Flowers spread when animals carry seed, not by teleporting into neighbouring
cells. An animal moving through a blooming patch picks seed up, carries it
while it wanders, and drops it somewhere along its path -- so flower spread
follows the actual movement corridors of the ecosystem's herbivores, and a
region that loses its grazers slowly stops spreading flowers. This reuses the
same "ecology has consequences" thread as tree spread (see
[ecosystem_dynamics.md](ecosystem_dynamics.md)).

**"Carries it while it wanders" needed a real heading, the same fix the bird
endozoochory section above got, and for the identical reason.**
`CreatureMarker`'s ordinary wander (`CreatureWander`) is home-tethered within
a fairly tight radius -- the SAME containment shape `AmbientFlyerMovement`
uses for birds (same 40px/2.5-tile radius, same pull-fully-home factor) --
so an animal whose home never moves cannot reach this carrier's own 3-14
tile range by wander alone, and the bird section's own claim that ground
wander was exempt from this was never actually checked. Measured directly:
30 sampled `wander_seed`s driving a bare marker (pure wander, no AI) all
plateaued at a hard ~2.6-tile net displacement from the pickup point,
regardless of what `carry_distance_tiles` intended -- 0 of 30 ever reached
the real range. A REAL grazer's other movement (hunger, foraging) helps but
does not close the gap on its own: across a 15-simulated-minute window in a
real `EarthChunkManager`, only 2 of those 30 seeds' carries actually
resolved. Fixed identically to the bird case: `SeedDispersal.carry_direction`
(a seeded heading, independent of `carry_distance_tiles`) is picked at
pickup and leaned into by ordinary wander (`CreatureMarker._wander_step`,
`CARRY_STEER_WEIGHT = 0.9`, same value and reasoning as the bird's own). The
mouse (`SeedCaching`, see [long_grass.md](long_grass.md#reproduction-seed-and-how-a-field-colonises-ground-it-never-touches))
and squirrel (`SquirrelNutCaching`, above) ground carriers share the exact
same `CreatureWander` movement and got the same fix --
see `docs/progress.md` for the full measurement and all three real-range
regression tests.

### Status

- ✅ Species catalog with per-species bloom season, colour, and scent strength
- ✅ Scent field: superposed per-flower contributions with distance falloff
- ✅ Pollinator spawn multiplier and gradient-following direction from the field
- ✅ Seed dispersal carried by animals — `SeedDispersal` + `FlowerPatch.plant`,
  driven from the same throttled herbivore walk as grazing. (This entry, and
  the two below, were stale: all three had landed while the list still read
  ⬜.)
- ✅ Seed PREDATION for ground seed (flower/grass) — `SeedEndozoochory.
  seed_is_consumed`/`GRANIVORY_CONSUMED_CHANCE`, rolled once per seed in
  `AmbientFlyerMarker._step_seed_carrying`: a sparrow now destroys the large
  majority of what it eats instead of always planting it, only ever
  dispersing a minority. Scoped to bare ground seed only — the tree-fruit
  disperser above is deliberately untouched (see that section's own doc
  text) — so the disperser-vs-predator tension the top-level "The loop"
  section describes is now real for this one carrier. Fruit/nut predation
  (a real squirrel species) is now also real — see the "Named species:
  Cherry, Apple, Walnut" section's Open questions/Status entries above
  (`SquirrelNutCaching`). Trait-driven per individual now too: `SeedEndozoochory.
  consumption_chance_for` nudges each bird's chance by its own
  `AnimalFitness.fitness_score`, bounded to keep the large-majority band for
  every individual.
- ✅ Flower sprites and their placement in the world — `ProceduralFlowerSprite`,
  one foot-anchored sprite per live `FlowerPatch` cell, synced with the chunk
  lifecycle.
- ✅ Wiring the field into ambient flyer spawning/steering — `scent_world`
  duck-typed onto `EarthChunkManager`, sniffed on a throttled interval.
- ✅ Nectar as a depleting/refilling resource plus per-pollinator visit memory
  — `PollinatorForaging`, `FlowerPatch.drink`/`advance`.
- ✅ Claim-sharing so pollinators stop chaining onto one bloom — `ForageClaims`
  (see above), wired through `EarthChunkManager`'s
  `claim_flower`/`release_flower_claim`/`claims_near` and released for every
  flyer on chunk unload so the table cannot leak.
- ✅ Re-evaluating targets en route, with hysteresis — a committed flyer used
  to refuse to look at anything until it arrived, so it flew straight past
  live blooms right beside it ("butterfly is still ignoring unvisited
  flowers"). It now sniffs every interval but only switches for a bloom
  closer by more than `AmbientFlyerMarker.RETARGET_IMPROVEMENT_TILES`, which
  is what keeps it from thrashing between near-ties instead of arriving.
- ✅ Pollination feedback, both halves. **Seed viability** (flowers) was
  already done — `Pollination` (dioecious male/female flowers, species-
  specific pollen, seed only set when a carrier's pollen matches), wired
  through `FlowerPatch`.
  **Fixed (2026-08-26): "wired through `FlowerPatch`" was not actually
  true.** `Pollination` and `FlowerPatch.pollinate` were a complete,
  fully-tested pure module — but `pollinate`'s only caller anywhere in the
  live game was its own test file. Nothing a bee or butterfly did ever
  called it, so `FlowerPatch._pollinated` stayed permanently empty and
  `shed_seed` (which only sheds for a cell that is both past bloom AND in
  `_pollinated`) never fired through pollination: a real meadow's flowers
  never actually went to seed, silently, no matter how many pollinators
  visited it. `EarthChunkManager.pollinate_flower_at` — the flower-side
  counterpart of `record_pollination_visit_at` below — is the fix: a
  landing bee/butterfly now actually delivers whatever pollen it is
  carrying to the flower (`FlowerPatch.pollinate`) and picks up new pollen
  in return (`Pollination.pollen_after_visit`), exactly the way the tree
  side already worked. Wired from `AmbientFlyerMarker`'s existing flower
  landing branch (alongside `drink_nectar_at`, not gated on whether it fed
  — nectar and pollen are separate resources) via a new `_carried_pollen`
  field that persists across visits, for every flower-foraging species
  (bees and butterflies alike, unlike the bee-only tree-blossom branch).
  Six tests in `test_earth_chunk_manager.gd` (`test_seeds_near_reports_seed_
  lying_on_the_ground` and five siblings) had been failing on exactly this
  cause the whole time, unnoticed because that file is one of two this
  project always excludes from a full-suite check as "known-slow" — see
  `docs/progress.md`'s "Pollinator visits now feed back into flower seed set
  too" entry for the correction and the fix.
  **Fruit set** (apple/cherry trees) is the half
  this closed: bees now recognize a blossoming, insect-pollinated tree
  (`TreeSpecies.needs_pollinators_for`) as a real food source alongside
  flowers — `EarthChunkManager.blossoms_near` hands a bee's existing
  targeting machinery (`PollinatorForaging.choose_target`) a tree exactly
  shaped like a flower it already knows how to work — and a landed visit
  (`record_pollination_visit_at`) is banked on the tree
  (`ChoppableTree.pollination_visits_in_cycle`, scoped to one bearing
  cycle) and composed into `FruitingModel.crop_potential`'s yield
  multiplier via `FruitingModel.pollination_factor`: an isolated tree still
  sets a reduced-but-real crop from self-/incidental pollination (real
  apples/cherries are not self-sterile), rising toward the species' usual
  ceiling as bee visits accumulate. Wind-pollinated species (pine/acorn/
  hazelnut/walnut — real catkins/cones) are unaffected either way, by
  design. Scoped to bees, not every nectar-feeder, since bees are fruit
  trees' primary real-world pollinator. Known simplification: a tree's
  visit count lives on its own node and does not persist across a chunk
  unload/reload or a save — the same tier its other per-tree state
  (growth, ripe count) already lives at, and not yet promoted further.
  Individual bees are no longer interchangeable for this: each visit is now
  weighted by the visiting bee's own `AnimalFitness.fitness_score` (its
  `wander_seed`-derived phenotype) via `FruitingModel.
  visit_weight_for_fitness`, a bounded 0.85..1.15 multiplier around the flat
  1.0 an average bee still banks — a fitter bee is a modestly more effective
  pollinator, grounded in real (modest, not order-of-magnitude) individual
  variation in pollinator foraging efficiency, and nowhere near enough on
  its own to meaningfully dent `POLLINATION_SATURATION_VISITS`.
- ⬜ **A bloom that has gone over is not redrawn as withered.**
  `FlowerBloom.is_withered` is evaluated once, at sprite creation, inside
  `EarthChunkManager._sync_flower_sprites`, and baked into the generated
  texture; the per-tick loop just below it already re-reads live sim state
  for every existing sprite but only ever touches `scale`. Meanwhile the
  pollinator path reads `is_withered` live every tick, so a bee refuses a
  flower the world still draws as fresh (see "What is visible must be what
  is real"). The fix is small and the refresh cadence to hang it on is
  already paid for: remember the flag each sprite was BUILT with and
  regenerate only when it flips — at most once per plant per year, the same
  only-on-change guard `_sync_tree_season` uses for canopies.
- ✅ Seasonal bloom windows themselves are correct and already live
  (`FlowerSpecies.SPECIES[*].bloom`, `FlowerPatch.blooming_cells`,
  re-synced on every season change) — exactly one of the eight species
  (crocus) blooms in winter, so a winter meadow is genuinely ~7/8 empty.
  Noted explicitly because "flowers keep blooming in winter" has been
  reported and is not what the code does.
- 🚧 Illustrated head art per archetype — `IllustratedFlowerHead` +
  `ProceduralFlowerSprite._paint_illustrated_head`, tinted per species,
  nectar-driven full/spent staging. Only "cup" (crocus, tulip) has a sheet
  so far; layered/spike/puff still draw procedurally. Staging is picked once
  at sprite creation, not live-updated as an already-visible bloom depletes.
  Bud/opening frames are sliced and tested but unconsumed — no live
  "not yet in bloom" render state exists to use them for.
- ✅ **Nectar economy is not over-subscribed any more.** A pre-claims
  measurement found the population's drink demand 2.05x its flowers' regen
  capacity (64.24 drinks/s against 31.30 nectar/s across 626 reachable
  flowers) — the arithmetic behind why arrivals found a mean 0.182 nectar.
  Re-measured now that claim-sharing (above) is wired up
  (`tests/unit/test_nectar_economy.gd`): a real simulation of 150
  pollinators over a 616-flower summer meadow, run to steady state, now
  measures **0.86x** — demand 8.44 drinks/s against supply 9.87 nectar/s
  across 592 flowers actually reached. Peer-claim demotion alone closed the
  gap; `PollinatorForaging.NECTAR_REGEN_PER_SECOND` needed no change (see
  its own doc comment for the same numbers).


## How a pollinator flies

Two rules, both learned the hard way.

**What a flyer may not land on, it must not be steered toward.** Visit memory
stops a pollinator re-targeting a bloom it has just drained, but the scent
gradient is a separate system, and it carried more weight in the steering blend
than the wander did. So a butterfly that had just worked a flower was pulled
straight back to it while being forbidden to land — and hung in front of it
indefinitely, which read as a butterfly staring at a flower rather than
foraging. The two systems now share one answer: a bloom inside this flyer's
visit memory neither attracts it nor can be targeted by it. It goes on
advertising to every *other* flyer, and starts advertising to this one again
once the memory ages out — which is roughly when it has refilled.

**A butterfly does not fly in a straight line.** Erratic, tumbling flight is a
real anti-predator adaptation, not decoration, and an approach that tracked
dead-straight at a bloom read as a moth homing on a lamp. The approach now
veers side to side as it goes, on two different frequencies so the path never
repeats the same arc, with a per-individual phase so two butterflies in one
meadow don't flutter in unison. The veer eases off as it closes in, so it
settles onto the blossom rather than fluttering around it — and it always keeps
a forward component, because a tumble that could point backwards is a flyer
that never arrives.

## Where a forest comes from

A tree drops fruit; the fruit is eaten or rots; some of the seed in it ends up
far enough from the parent to become a tree of its own. That loop is what makes
a wood spread, and every step of it has to actually reach the ground somewhere
NEW or the wood stays exactly where it was planted.

**Seed lands on the neighbours, not on the parent.** Fruit falls uniformly
across the parent's own tile and the eight around it -- the three-by-three
block a real canopy overhangs. A fruit that always lands on the trunk is a
fruit that can never found a tree, because the trunk's tile is already taken.

This was the single reason woods did not spread: `spread_radius` is documented
as "tiles a seed can land within" and ranges 2 to 8, but the spread code added
it to a position measured in PIXELS. Seeds landed two to eight pixels from the
parent -- a fraction of one tile -- and the minimum-spacing rule was then tuned
*below* that wrong number to stop it rejecting everything, which hid it. An
assumption written in a comment and enforced nowhere, again.

**A tile holds three trees at most.** Nothing stopped a stack before: the
spacing rule was a pixel and a half on a sixteen-pixel tile, so a tile could in
principle carry a hundred trunks. Three is a thicket you can walk into; more is
a wall of overlapping sprites that reads as a rendering fault.

**Fruit comes and goes with the seasons.** A tree flowers in spring, swells its
crop through summer, ripens it toward autumn, and is BARE BY WINTER. Anything
still hanging at the end of autumn falls then -- a canopy carrying apples under
snow is the clearest possible sign the phenology is not wired to the calendar.

The bearing cycle used to run on its own clock, unaligned to the seasons, so
abscission began at four-fifths of the year -- which is midwinter -- and fruit
hung on bare branches through the cold.

**Fruit on the ground does not last.** It is eaten -- by the player, by
mammals, by birds who carry the seed on -- or it rots. Fruit that lies
untouched forever turns the ground under every tree into a permanent larder and
removes the reason to come back in season.


## Illustrated trees

A tree is composited from three separate pieces of art rather than drawn as
one image: a **trunk**, a **canopy** that changes with the season, and a
**fruit** that hangs in the canopy. They are separate because they change on
different clocks -- the trunk never changes, the canopy changes four times a
year, and the fruit changes as a crop ripens -- and drawing them as one image
would mean an entire tree's worth of art for every combination.

**The canopy carries the season.** Four frames per species: bare, blossom,
in leaf, and turning. This is new -- trees previously wore one canopy all year
while the flowers beneath them bloomed and died on schedule, which made the
seasons something that happened to the ground cover and not to the world. A
bare orchard in winter is the clearest signal the game has that time is
passing.

That fix then had an exact inverse defect, and it is worth naming here
because this paragraph is where someone will come looking: the canopies
turned and the GROUND under them did not. Bare winter trees stood on a
bright high-summer lawn, in still-lush tall grass, over still-green crop
tops. The ground cover now carries the season too, on the same
`SeasonTransition` clock these canopies turn on — see
[seasons.md](seasons.md)'s "The ground carries the season too" and
`src/rendering/seasonal_foliage.gd`.

The frames map to seasons by MEANING, not by their order in the sheet: bare is
winter, blossom is spring, leaf is summer, turning is autumn. Written down
because it is exactly the kind of thing that silently works until a sheet is
authored in a different order.

**But WHEN a tree wears each frame is phenology, not the calendar.** Reported
from a world that started in winter: pink blossom and green crowns standing in
the snow. The mapping above was not at fault — `SeasonTransition` spends the
last third of every season turning into the next, so a third of winter was
already reporting "turning into spring", and blossom is 2.5x as dense a picture
as bare branches, so a sixth of a turn already reads as pink. `TreePhenology`
(`src/world/tree_phenology.gd`) now owns the canopy's own schedule: **winter is
bare end to end** (its pre-turn is suppressed outright — a canopy's spring
arrival state IS bare, so there is nothing to blend toward), **blossom is a
brief early-spring event** derived from real bloom records (opening + full
bloom = 12 of a 92-day spring, so 13% of an in-game spring against the 34% an
ordinary turn takes), and **leaf-out follows it gradually** on the same six
quantised steps. Summer and autumn are untouched. Full spec, with the measured
frame densities that explain the report, in [seasons.md](seasons.md)'s "Winter
stays bare: the canopy has its own phenology".

Two consequences of that worth having here, where the sheets are described.
The blossom slot is only a *flowering* frame for cherry: the nut and orchard
sheets draw it as the yellow-green flush of a bursting bud, which reads
correctly as new leaf in early spring and read oddly across a whole spring.
And **pine is an evergreen in its art as well as in its data** — its bare-slot
frame keeps 84% of its leaf-frame foliage in a grey-green rather than showing
branches — so it walks the same four stages as four tones of conifer and is
unaffected by any of this. Both are pinned by tests, because both are claims
about pixels somebody could repaint.

**Fruit is two frames, unripe and ripe**, so a crop coming in is visible on the
tree before it can be picked -- the same information the fruiting model already
tracks (see `FruitingModel`) but shown rather than hidden. Fruit is scattered
across the canopy from the tree's own seed, so a heavy crop reads as heavy
without needing a frame drawn for every count.

**One sheet or three.** Art arrives either as three separate files or as a
single composite holding canopy strip, trunk and fruit together. The composite
is how the art is actually generated -- one image is one prompt and one file --
so it wins where it exists.

A composite is cut up by FINDING the drawings on it rather than by a declared
grid, because the drawings are different sizes and there are different numbers
of them per species. The obvious approach, cutting on empty rows and columns,
does not survive the art: the autumn canopies have leaves drawn falling away
beneath them, and those strays bridge every gap. Each drawing is found as a
connected blob instead, and strays are dropped for being far too small to be a
drawing.

The pieces are then read by position: the top band is the canopy strip, the
largest drawing below it is the trunk, and the rest are fruit.

**A fruit frame's row says what it means.** The first row of the fruit block is
the crop AS IT HANGS ON THE TREE -- drawn on a branch, with leaves or needles.
The rows below are what you get once you have picked it: shelled, cracked open,
the kernel. Only the first row is ever drawn on a tree.

Species differ in how many stages they have. Walnut, acorn and hazelnut each
draw two on-tree stages; pine draws three, its extra one a bare needle sprig
carrying no cone at all. So ripe is the LAST on-tree stage and unripe the one
before it, counted from the END. Counted from the start, pine's bare sprig
would be its unripe crop and its green cone the ripe one -- a tree bearing
needles instead of cones.

**Trunk and canopy are proportioned, and vary together.** A trunk is tall and
narrow. Scaled to preserve the source art's aspect it came out squat and wide,
because the trunk drawings are nearly square -- they include the flare of the
roots -- and a tree read as a canopy sitting on a stump. The art is stretched
to real proportions instead, deliberately and only so far: bark grain runs
vertically, which is what lets it take a vertical stretch without looking
wrong.

Trunk height and canopy size vary per tree from its own seed, the canopy less
than the trunk, so a wood does not read as one tree stamped out repeatedly.
They vary TOGETHER: the canopy is placed against the trunk's actual top, so a
taller trunk lifts its crown with it rather than leaving a gap.

The two overlap by a lot, because these canopies are notched along the bottom
exactly where the trunk is -- the artist leaves room for one. At a small
overlap the trunk stops in that notch and the crown visibly floats above it.

**A trunk is one piece of wood, not two either side of a gap.** Squeezing the
root flare sideways into the narrow trunk box can land a real gap between two
separate root "toes" of the source art on the box's own centre column -- the
walnut sheet's flare happens to split exactly there, so every walnut trunk
sampled at its centre came out fully transparent, while every other species'
equivalent gap sits off to one side. Any transparent run flanked by opaque
trunk pixels on both sides of the same row is enclosed by the trunk rather
than open to the background, so it is filled -- the same "petals are not
windows" reasoning below, applied row-wise rather than as a full flood fill,
because a trunk's gaps run sideways between root legs rather than sitting as
enclosed pockets.

**Art is per species, and optional.** A species with sheets is drawn from them;
one without falls back to the procedural painter unchanged. This is the same
species-first-then-generic lookup the flowers and the animals use, so adding a
species costs its three sheets and one line of registration, and never touches
anything already working.


## Recolouring illustrated blooms

An illustrated head sheet is shared by every species of its archetype (a real
crocus and a real tulip are the same shallow cup), so the species' own colour
has to be applied to the art at composite time.

That recolour takes the source's **shading only, never its hue**: the sheet is
read as luminance and the petal colour painted at that brightness.

It was a plain multiply, which is correct only if the source art is pale and
neutral. The cup sheet is not -- it carries real green in its sepals and
outlines -- and multiply preserves hue, so crocus and tulip came out as green
cages: invisible against grass, and not a colour petals come in. Depending on a
promise about how the art was drawn is a promise that will eventually be broken
by the next sheet; discarding hue outright makes the recolour robust to
whatever the art happens to be tinted.

A floor under the darkest shading stops the sheet's linework multiplying down
to near-black, which at this size reads as a hole in the flower rather than as
shading.

**Petals are not windows.** The cup sheet is line art -- petals drawn as
outlines with nothing inside them -- so composited as-is the grass showed
straight through every petal and a flower read as a wireframe cage. Recolouring
the outlines correctly did not help, because the green being complained about
was the background. Any transparent area that cannot be reached from the edge
of the canvas is *inside* the drawing, so it is filled before compositing. That
holds for any line-art sheet rather than for this one specifically.

**Flowers are measured against the player, and pinned to two reference
points.** A tulip comes up to the player's HIP; a sunflower stands as tall as
the player. Everything else follows from its real height in centimetres, and
the curve between those two anchors is computed rather than chosen by eye.

Sizes are deliberately a little taller than life. At true scale a tulip reaches
a quarter of a person and a crocus about a sixteenth -- correct, and dull:
flowers you can barely see are not worth walking through. These are plants as
they feel rather than as they measure.

The curve is anchored to centimetres rather than to whichever species happens
to be tallest. That matters for exactly the reason the sunflower exposed:
under the old relative scheme, introducing one tall species would silently
have shrunk every other flower in the world. A new entry now decides only its
own size.

The sunflower is the one deliberate exception to flowers being accents among
grass. Everything up to hip height grows between the blades and must not tower
over them; the sunflower is meant to stand above the meadow, and is measured
against the player instead. It is what makes the rest read as small -- a stand
of them is something you walk into rather than over.

**Flowers are measured against the player.** They were sized against grass
alone, which let a tulip reach 72% of the player's height and stand chest-high
on the hero; grass is a poor yardstick because grass is itself waist-high in
places. Species now carry their real heights in centimetres -- a crocus is 10,
a lavender spike 50 -- and the tallest renders at knee height on the player,
with everything else falling below it. Adding a species is a question about
the plant, not about the renderer: a sunflower is simply 200.

Real heights are exaggerated toward legibility, small ones most: at true scale
a crocus is 6% of a person, about one world pixel, a speck rather than a
flower. The exaggeration never reorders the species -- a lavender still reads
as clearly taller than a crocus, it is simply not seventeen times taller as it
would be in life.

**No two plants are quite the same size.** A bed where every bloom is
pixel-identical reads as stamped-out copies rather than as things that grew,
so each plant is nudged from its species' norm by its own seed -- fixed for
that plant's life, like its colour. It stays a nudge: a runt and a giant of the
same species still read as that species.

**Some plants are bushes.** Lavender does not grow on a single stem; it is a
bush of many spikes, and one lone spike per plant made a lavender bed read as
scattered twigs. A species says how many stems it puts up, and a bush is drawn
as several of its own with their own heights and lean, close enough to overlap
into one mass. The centre spike stands full height so the bush has a crown
rather than a flat top. Clover grows the same way, as a low mat of heads.

**Masks: recolour the petals, keep what is deliberately another colour.** The
recolour discards the sheet's hue entirely -- which is what fixed blooms
rendering as green cages -- but it discarded the gold eye along with it, so an
illustrated daisy came out uniformly grey. A flower's centre is not its petals.

Which hue is "petal" cannot be derived from the sheet: measured, the shared cup
sheet's *petals* sit at 30 degrees, exactly where the daisy sheet's *eye* sits,
so a "biggest cluster wins" rule gets one of the two backwards. Each sheet
declares where its own petals are instead. That is the mask, expressed as data
rather than as a companion image -- a new sheet costs one number, not a second
drawing.

Being far from the petals in hue is not sufficient on its own, because these
sheets also draw green sepals that are equally far. On a bloom a few pixels
tall a preserved sepal does not read as botanical detail, it reads as a green
flower -- the exact complaint that started this. So an accent must also be
gold: the window closes at 70 degrees, before the green begins.

**A species is not one colour.** Crocuses come up purple, white, yellow and
lilac from the same bed, and a tulip is the classic case of a species bred
into a whole shelf of colours; a meadow where every crocus is the identical
purple reads as copy-paste rather than as planting. Each species declares the
colours it can come up in, and each plant picks one from its own seed, so a
flower keeps its colour for life rather than flickering between varieties.
The canonical colour stays the species' identity for anything that wants "the
colour of a rose" without caring which rose.

Variety is colour and nothing else. A white tulip is exactly as tall and
exactly as fragrant as a red one -- scent and stature are the species'
business, and letting a tint change them would make "which colour did this one
roll" a hidden gameplay variable.

**Stature is a real spread.** A crocus is an ankle-high early bloom and a
lavender spike stands nearly twice it, roughly their relation in a real
meadow. An earlier pass had flattened every species to about one size while
fixing roses that rendered as towering shrubs; what actually mattered in that
complaint is kept as its own rule -- no species may dwarf the meadow it stands
in -- rather than by making them all the same. A much larger species (a
sunflower) needs nothing but its own entry, with its height chosen against the
grass line deliberately rather than by eye.

**Shape families are named for shapes.** The fallback family was called
"daisy", which was a category error: a daisy is a species, and naming a shape
family after one of its members meant that species could never be given art of
its own without colliding with the fallback everything else uses. It is
"radial" now, alongside cup, layered, spike and puff.

**A brown centre needs no special case.** A sunflower's dark eye sits in the
same hue bucket as its petals -- brown is simply dark gold -- so it recolours
along with them and comes out dark in whatever colour the plant came up as,
russet on a russet flower. The mask only has to separate hues, not values.

**A species may bring its own art.** One sheet per archetype is the default
because it costs no new art per species, and for most it is right. Where a
species deserves its own drawing, its sheet is registered against the species
and wins over the archetype's; every other species of that archetype is
unaffected, and a species with neither falls back to the procedural painter.
The same species-first-then-generic lookup the animal art already uses.

**A young tree has fewer branches, not a smaller picture.** Growth used to be a
single node scale, so a sapling was a full-grown tree drawn in miniature —
crown, boughs and every twig, only small — which reads as a toy rather than a
young tree. A real one is a short trunk carrying a few leaves, then a small
crown, then boughs spreading; the far tips of the branches are the last thing
it puts out. So growth prunes the CANOPY as well as scaling the node: the crown
is traced and only the part the tree has actually grown into is drawn.

**Growth traces from the trunk outward; the season turn traces from the rim
inward.** Both walk the same crown art by geodesic distance through its painted
pixels, and the seeding is the whole difference between them. The turn starts
from the crown's entire bottom edge, because a season arrives everywhere along
the outside of a tree at once. Growth starts from the ONE point where the trunk
meets the crown, because that is where a tree grows from. Seeding growth the
turn's way — which is the obvious reuse, and was the first attempt — draws a
young spreading tree as an arch hanging in the air with a gap beneath it, since
for a spreading crown the "bottom edge" is the drooping outer rim.

**Growth is traced; the turn is dissolved.** The turn mixes its trace half and
half with per-clump noise, because leaves really do colour individually all over
a tree and a clean advancing front looks mechanical. Growth cannot afford that
mix: at an even split a sapling comes out as confetti, leaf specks strewn across
the whole mature crown box with nothing joining them. Growth weights the trace
far higher (`GROWTH_BRANCH_WEIGHT`) and keeps only a little noise — enough that
two saplings of the same species are visibly different trees, not enough to
break the crown apart.

**Both are quantised, for the same reason.** Every distinct growth fraction is a
whole tree picture to composite and cache, so growth is drawn in a fixed number
of stages (`GROWTH_LEVELS`) exactly as the turn is. A continuous fraction would
mean a new texture per frame per sapling in a wood full of them.

**A tree bears once a year, and the species decides WHEN, not how often.** The
bearing cycle is one year for every species, always. It used to be scaled by the
species' ripening character, which meant a cherry ran a cycle two thirds of a
year long and a pine one nearly two years long — and since the ripening phases
are fractions *of a year*, the fruit landed somewhere new every year. Measured:
a cherry shed 24 fruit a year in two windows, the second in mid-**winter**,
while a pine shed nothing in a year at all. How fast a species ripens is *when*
in the year it bears, which the phases already say; it is not how often. An
apple and a pine both fruit once a year, in different months.

**Falling fruit is counted cumulatively, not per step.** How many fruit have
fallen by now is a continuous quantity; how many *hit the ground* is a whole
number. Differencing the whole count between two moments is what makes the two
agree, and it is the only formulation where stepping the world in seconds and
stepping it in years give the same answer. Rounding each step's own increment
instead is why nothing ever fell: fruiting steps once a second, and one second
of a crop of twelve spread over a fall window a tenth of a year long is about
two ten-thousandths of a fruit, which rounds to zero — every step, forever. A
year-long call returned the whole crop, so tests asking in one big span all
passed while the running game shed nothing.

## Fruit are individuals, not a number

**The cherry that falls is the cherry that was hanging there.** A tree's crop
was two unrelated things wearing the same name: a decorative count baked into
the canopy texture (quantised into four levels, so what you saw was a
*representative* crop rather than the real one), and a separate abscission
count that spawned brand-new item stacks on the ground. Nothing tied them
together, so fruit could hit the ground while the tree above was drawn bare,
and the tree could be heavy with cherries that had already fallen (reported).

**One curve, read two ways.** How many of a crop are still hanging at a given
moment is the single source of truth. What the canopy draws is that number.
What falls between two moments is the *decrease* in that number. Defining the
drop as a difference of the hanging count — rather than as its own integral
over its own window — is what makes the two agree by construction: a fruit
cannot fall without leaving the tree, because falling IS leaving the tree.

The previous arrangement computed the two windows separately and they disagreed
about warmth: the displayed window was shifted earlier by `_earliness` and the
falling window was not, so the tree ripened up to four days before its fruit
was willing to drop.

**Fruit fall one at a time, in the tree's own order.** Each fruit in a crop has
an index; its position in the canopy comes from that index and never moves, so
a growing crop lights up more fruit rather than rearranging what is there. Fruit
leave from the top of that order, so a crop empties one fruit at a time from
scattered positions rather than thinning uniformly. The fruit that leaves index
*k* lands under where index *k* hung — which is what makes it the same cherry.
