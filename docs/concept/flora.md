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

### Open questions

- Exact trait list and per-species preference/predator-vs-disperser
  tagging — needs a first content pass once implementation starts.
- Does seed-coat toughness (a plausible DNA trait) actually gate which
  species *can* act as a disperser vs. predator for a given tree (a
  toughness threshold a predator's bite can't crack), or is the
  disperser/predator role fixed per species-pair regardless of trait
  values?
- How far does animal-mediated dispersal actually carry a seed — tied to
  the disperser species' migration/home-range behavior
  ([world.md](world.md)'s animal population model), or a flat distance
  roll?
