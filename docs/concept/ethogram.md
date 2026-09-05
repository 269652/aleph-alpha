# Ethogram: behaviour as expressed receptors, not per-species code

An *ethogram* is ethology's word for the catalogue of what a species does and
what releases each behaviour. This doc makes that catalogue the game's actual
behaviour DSL: every animal reacts to the world by scoring stimulus *feature
vectors* against its own *receptor* and *valence* vectors, gated by *drives*,
and the same short list of wirings then serves every species. "All animals
search for food and eat when they are hungry" is written once, and a species
gets it by being data, not by getting a tenth copy of the loop.

The prompt for this doc was a plain observation about the codebase: hunger
alone is implemented separately for land mammals (`creature_needs.gd`),
villagers (`npc_needs.gd`, which describes itself as a copy of the mammal
version's shape), the kingfisher (`piscivore_appetite.gd`), songbirds
(`bird_digestion.gd`) and the player (`survival_meters.gd`); finding food has
eight separate brains; fear has four; mate choice has three. Each copy was
reasonable on its own. Together they are the thing this doc replaces.

What is *not* being invented here is the trick that makes it work. The
codebase already runs it for one sense: [olfaction.md](olfaction.md) models a
smell as a molecule vector and a species as two receptor vectors, and lets the
verdict fall out of their product. A fly goes to rot because its decay
sensitivity and decay valence are both high, and nothing in the fly's code
mentions a rotten apple. This doc generalises that mechanism to every stimulus,
puts the receptor vectors under the genome, and puts the drives on top as
gains.

## Design pillars

1. **One kernel, many species; a species is data.** The behaviour loop is a
   short, ordered list of *wirings* per body plan (mammal, bird, insect, fish,
   villager), evaluated by one pure kernel. A species record holds receptors,
   valence and gains, nothing executable. Adding a species means adding a
   record; changing what "hungry" does for every mammal means editing one
   wiring. The test for this pillar is literal: three species run the same
   hunger wiring with zero species-specific code
   (`test_three_species_share_one_hunger_wiring`).

2. **The verdict lives in the animal.** [olfaction.md](olfaction.md)'s pillar,
   generalised: nothing in the world is a threat, a food or a mate. A thing
   *emits features*; an animal *carries valence*. A carcass has decay; the fly
   wants it and the deer does not; the wolf and the sheep meet the same
   `danger` feature with opposite valence. This is what lets one stimulus mean
   different things to different creatures without a lookup table of
   verdicts, and it is what "niche" is.

3. **Genes express receptors; state modulates gains.** Two time scales,
   kept apart on purpose because biology keeps them apart. *Expression* is
   slow: a genome sets how sensitive each receptor is, once per individual,
   and is inherited through the existing `dna_crossover.gd` unchanged.
   *Modulation* is fast: a drive (hunger, thirst, fear, courtship) is a gain
   that scales whole channel groups tick by tick. Personality is a point in
   gain space, so the same vector that drives behaviour is the one that gets
   inherited.

4. **The kernel ranks; the caller commits.** [ecosystem_dynamics.md](ecosystem_dynamics.md)'s
   rule that thresholds are ramps or hysteresis, never hard switches, is not
   the kernel's to enforce and it deliberately does not try. It is stateless:
   given this tick's stimuli it says what is most worth doing and which way
   that is. The Schmitt trigger on fleeing (`CreatureMarker`'s sense/release
   radii), a grazer's approach commitment (`GrazerForaging`), a bird's
   descend/peck cycle (`GroundForageBehavior`) stay exactly where they are.
   Those are motor programs; this doc chooses between them.

5. **Pure core, thin glue.** [npc_instructions.md](npc_instructions.md)'s
   pillar 6. `affinity.gd`, `ethogram.gd` and `behavior_kernel.gd` are
   `RefCounted` modules over plain Dictionaries with no engine dependency and
   no RNG, unit-tested headlessly. Only the adapters that already exist
   (`creature_behavior.gd`, `olfaction.gd`) touch anything that knows about a
   world.

6. **Real in the model must be named as such until it is real in the game.**
   Every mechanism below says which it is. The receptor genes of §4 are
   expressed and inherited in tests and carried by no live animal yet, and the
   status list says so, the same way [dna.md](dna.md) names the butterfly net
   nobody can swing.

7. **A valence table is an eyeballed table unless behaviour is pinned.** The
   five smell records this doc inherits are already fifty guessed numbers.
   Nothing here changes a number; everything here pins what the numbers
   *do*: the fly picks the rotten apple over the ripe one, the deer walks past
   it, the nearer of two equal threats is the one fled from. Any future
   retune has to keep those true.

## Real-world grounding

**Sign stimuli and releasing mechanisms.** Tinbergen's male stickleback
attacks a crude red-bellied model and ignores a lifelike fish with no red. The
behaviour is released by a *feature*, not by recognising an object, and
Lorenz and Tinbergen's "innate releasing mechanism" is exactly a weighting of
features that fires a fixed action pattern when the weighted sum is high
enough. A stimulus feature vector scored by a valence vector against a
threshold is that mechanism written down.

**Receptor repertoires and individual variation.** A nose is a repertoire of
receptor types, each tuned to some molecules more than others, and the
repertoire is genetic. Two species smell different worlds from the same air
(olfaction.md already models this). So do two *individuals*: a single
receptor-gene variant (OR7D4) decides whether a person finds androstenone
foul, sweet or odourless, and specific anosmias run in families. That is the
justification for §4's per-channel receptor genes rather than one "good nose"
scalar.

**Hunger sharpens the nose, and fear shuts the mouth.** In *Drosophila*,
starvation raises neuropeptide signalling on the olfactory receptor neurons
themselves, making a hungry fly measurably more sensitive to food odours than
a fed one (Root et al. 2011). Hunger does not add a "look for food" routine;
it turns up the gain on the receptors that were already there. In vertebrates
the arousal response suppresses feeding and courtship while a threat is
present. Both are the same operation, a drive scaling a channel group, and
that is what §5's gains are. The priority ladder every game AI hand-codes
(threat over thirst over hunger over mating) is what those gains produce
when fear's gain is large; slice 1 keeps the ladder explicit and the roadmap
lets it fall out of the numbers.

**Boldness, docility and flight distance.** `flyer_personality.gd` already
grounds a heritable boldness in the flight-initiation-distance literature, and
[animal_genetics.md](animal_genetics.md) §10 grounds docility's cost in
Belyaev's foxes: a domesticated animal notices a predator later. Both are a
gain on the same fear channel. This doc gives them one place to live.

**Needs and advertisements.** The nearest game-design precedent is *The
Sims*' motive engine: objects *advertise* what needs they satisfy, an agent
scores advertisements against its current need levels, and the best score
wins. Its authors' lesson was that the scoring weights, not the scripts, are
where the design lives. What this doc adds is that the weights are not
authored per object but *expressed* per animal from a genome and a species
record, so they can differ between individuals and be inherited.

## Mechanism spec

### 0. Files

```
src/gameplay/affinity.gd          ✅ pure vector arithmetic: pull, loudness, proximity, toward/away
src/gameplay/ethogram.gd          ✅ channels, species records, body plans, expression
src/gameplay/behavior_kernel.gd   ✅ ordered wirings + receptors + drives + stimuli -> {intent, direction}
src/gameplay/olfaction.gd         ✅ now a view over the ethogram's smell channels
src/gameplay/scent_foraging.gd    ✅ asks the ethogram who has a nose
src/gameplay/creature_behavior.gd ✅ now the land-mammal adapter onto the kernel
```

All three new modules are pure `static func` namespaces over plain
Dictionaries, in the style of `olfaction.gd` and `scent_foraging.gd`. The two
adapters keep their public signatures exactly, which is what lets their
existing tests stand as the regression bar for slice 1 (33 in
`test_creature_behavior.gd`, 12 in `test_olfaction.gd`, 11 in
`test_scent_foraging.gd`).

### 1. Channels: the shared semantic basis

A *channel* is one dimension of the feature space every stimulus and every
receptor is expressed in. The basis is deliberately small and deliberately
shared: a fruit, a carcass, a wolf and a puddle are all points in the same
space, which is what lets one kernel compare them.

| channel | what emits it | slice 1 source |
|---|---|---|
| `sugar` | ripe fruit, nectar | `Olfaction.fruit_mixture` (✅) |
| `decay` | rotting fruit, carrion | `Olfaction.fruit_mixture` (✅) |
| `green` | leaves, cut grass, foliage | `Olfaction.fruit_mixture` (✅) |
| `musk` | animals themselves | reserved, nothing emits it yet |
| `smoke` | fire | reserved, nothing emits it yet |
| `danger` | something that can hurt me | `CreatureMarker`'s existing threat scan, via the adapter |
| `flesh` | something I could eat that is an animal | the existing prey scan, via the adapter |
| `forage` | plant food in that direction | `CreaturePerception`'s biome food direction, via the adapter |
| `water` | drinkable water in that direction | `CreaturePerception`'s water direction, via the adapter |
| `mate` | my courtship partner | `MammalCourtship` pairing, via the adapter |

`Ethogram.CHANNELS` is the ordered list; `Ethogram.SMELL_CHANNELS` is the
first five and is what `Olfaction.MOLECULES` now aliases. The molecule
constants (`Olfaction.SUGAR` and friends) keep their names and their values;
they are re-exported from the ethogram so that no caller of the smell API
changes.

**`danger` is a verdict wearing a feature's clothes, and this doc says so.**
Today `CreatureMarker` decides who counts as a threat (players and predator
creatures within `SENSE_RADIUS`) before `CreatureBehavior.decide` ever runs,
so slice 1 can only hand the kernel that classification as a feature. The
honest version, on the roadmap (§8, slice 2), has the scan publish
`predator`, `player` and `conspecific` features and lets the *species'
valence* decide that a sheep flees a wolf and a wolf does not flee a sheep.
Until then the adapter is where that verdict lives, exactly as it does today.

### 2. Stimuli

A stimulus is `{"position": Vector2, "features": {channel: float}}`. It is
what a sense hands the kernel. There is no stimulus *type*: a rotten apple is
`{decay: 1.0, sugar: 0.15, green: 0.05}` and a wolf is `{danger: 1.0}`, and
the only thing that distinguishes them is where they sit in the basis.

Who builds them, by slice:

- ✅ `Olfaction.fruit_mixture(item_id, freshness)` already is a feature
  vector over the smell channels; `EarthChunkManager.smells_near` already
  returns `{position, mixture}` lists. `mixture` and `features` are the same
  thing under two names, and the kernel accepts either key.
- slice 1: `CreatureBehavior.decide` synthesises stimuli from the context it
  already receives (§7). Nothing above it changes.
- ⬜ slice 2: `CreatureMarker` publishes real stimuli (its threat/prey scans,
  `smells_near`, `GrazerForaging`'s bite candidates) and the adapter's
  synthesis retires.

### 3. Species records and body plans

```gdscript
Ethogram.SPECIES = {
    "boar":  {"body_plan": "mammal", "smell": {"sensitivity": {...}, "valence": {...}}},
    "deer":  {"body_plan": "mammal", ...},
    "horse": {"body_plan": "mammal", ...},
    "robin": {"body_plan": "bird",   ...},
    "fly":   {"body_plan": "insect", ...},
}
Ethogram.BODY_PLANS = {
    "mammal": {"receptors": {"sensitivity": {...}, "valence": {...}}, "wirings": [...]},
}
```

The five `smell` blocks are `Olfaction.RECEPTORS` moved verbatim, with
olfaction's `response` renamed `valence` (the affective-science term for the
same signed number: positive draws, negative repels, near zero is noise).
`Olfaction.RECEPTORS` itself is deleted; the one production reader
(`ScentForaging.forages_by_smell`) asks `Ethogram.has_nose(species)` instead.

A **body plan** carries what is shared by everything built the same way: the
receptor *defaults* for the non-smell channels, and the wirings (§6). Slice 1
ships exactly one, `mammal`, because that is the one whose behaviour loop
already runs through a pure decision module that can be swapped underneath.
`bird`, `insect`, `fish` and `villager` are named on the records that will
need them and have no wirings yet; `Ethogram.wirings_for("bird")` returns an
empty list rather than pretending.

The mammal defaults, and why each is what it is:

| channel | sensitivity | valence | why |
|---|---|---|---|
| `danger` | 1.0 | −1.0 | every mammal notices a threat, and the default answer is to leave; the adapter flips valence to +1.0 for an animal that will stand and fight (§7) |
| `flesh` | 1.0 | 0.0 | a herbivore sees prey and wants nothing from it; the adapter sets +1.0 for a predator |
| `forage` | 1.0 | +1.0 | plant food is food |
| `water` | 1.0 | +1.0 | |
| `mate` | 1.0 | +1.0 | |

The two adapter overrides are state and species facts that today reach
`decide()` only as context flags (`temperament`, `health_fraction`,
`is_mature`, `is_predator`). The species record is where they belong
(`flesh` valence is a diet fact; fight valence is temperament) and the
roadmap moves them there when `decide()` learns which species it is deciding
for (§8). Slice 1 does not pretend otherwise.

### 4. Expression: genotype to receptors

```gdscript
static func express(species: String, genome: Dictionary = {}) -> Dictionary
    # -> {"sensitivity": {channel: float}, "valence": {channel: float}}
```

Expression starts from the species' smell block merged over its body plan's
defaults, then applies the individual's **receptor genes**. A receptor gene is
a genome entry named `receptor_<channel>` with a value in [0, 1], the same
`String -> float` shape `NpcGenome.traits` and `FlyerPersonality` already use
and `DnaCrossover.crossover` already consumes, so a child's receptor
expression is inherited by the one crossover this project has, with no
adaptation and no second implementation.

The expression law is linear and has one fixed point:

```
expressed_sensitivity[c] = template_sensitivity[c] * gene / NEUTRAL_RECEPTOR_GENE
NEUTRAL_RECEPTOR_GENE = 0.5
```

`0.5` is the species template *by definition*: a gene here is a deviation
from the species, and the population mean deviates nowhere. `0.0` is a
specific anosmia for that channel (the receptor is not expressed at all);
`1.0` is a receptor at twice the species' sensitivity. The factor of two is
not a tuned number, it is what a linear law with a neutral point of 0.5 and an
anosmic point of 0 produces; the tests pin the two endpoints and monotonicity
between them, not the slope. A genome with no `receptor_*` entries expresses
the species template exactly, so every existing caller of the species-keyed
smell API is unchanged by construction.

Only *sensitivity* is heritable in slice 1. Valence is the species' innate
wiring: real innate odour valences (a fly's aversion to geosmin, say) are
circuit-level and species-typical, and this project has no reader that would
make an individual valence visible. Under animal_genetics.md's rule that a
gene with no reader is dead weight, valence genes wait for one.

**Reader, and honest status.** `Olfaction.perceived_strength` and
`Olfaction.attraction_to` gain an optional trailing `genome` argument and read
`Ethogram.express(species, genome)`. That is the production reader; it makes
"a boar with a poor decay receptor is drawn less by rot" a real, tested fact
of the model. No live animal carries a receptor gene yet: `AnimalGenome`
(animal_genetics.md §1) does not exist, `CreatureMarker` derives nothing from
`wander_seed` but a stagger, and the markers call the species-keyed API. When
`AnimalGenome` lands, `receptor_*` are candidates for its `GENE_NAMES` with
`res://src/gameplay/ethogram.gd` as their `GENE_READERS` entry, which is
exactly the guard that doc specifies.

### 5. Modulation: drives as gains

A **drive** is a named level in [0, 1]: `hunger`, `thirst`, `fear`,
`courtship`. Every wiring names the drive that *gates* it, and the kernel
multiplies a wiring's pull by that drive's level. A level of zero switches the
wiring off entirely; a hungry animal at level one finds food exactly as loud
as the receptors make it. That single multiplication is the whole of
"neuromodulation" in this model, and it is enough for hunger to sharpen the
nose (Root et al.) and for a sated animal to walk past a windfall.

In slice 1 the levels are the booleans the adapter already has:
`CreatureNeeds.is_hungry()` becomes `hunger: 1.0` or `0.0`, and likewise
thirst; `fear` is always `1.0` (an un-aggroed world boss is handled by
*sensitivity*, §7, because it genuinely does not perceive the player as a
threat rather than merely not caring); `courtship` is `1.0` while paired.
Continuous levels, drive rates per body plan, and the unification of the five
hunger clocks into one drive vector are slice 3 (§8). Personality as a
baseline on these gains (boldness lowering `fear`, temperament raising a
`fight` gain), and the spell `FEAR`/`CALM` statuses as a temporary push on the
same gain rather than today's temperament-string swap in
`CreatureMarker._temperament_for_decision`, are slice 4.

### 6. Wirings and the kernel

A **wiring** is one line of the ethogram:

```gdscript
{"gate": "hunger", "channels": ["flesh"], "approach": "hunt"}
{"gate": "thirst", "channels": ["water"], "approach": "seek_water", "search": "search_water"}
{"gate": "fear",   "channels": ["danger"], "approach": "attack", "avoid": "flee"}
```

- `gate`: the drive whose level scales this wiring; level zero skips it.
- `channels`: the subset of the basis this wiring listens on.
- `approach`: the intent when the best stimulus *draws* (pull > 0), heading
  toward it.
- `avoid` (optional): the intent when the best stimulus *repels* (pull < 0),
  heading away. A wiring with no `avoid` ignores a repellent stimulus rather
  than fleeing it; a deer that smells a carcass walks on, it does not bolt.
- `search` (optional): the intent when the gate is open but nothing on these
  channels is sensed at all, with a zero direction for the caller to fill in,
  exactly today's `search_food`/`search_water` contract.

The kernel:

```gdscript
static func decide(wirings: Array, receptors: Dictionary, drives: Dictionary,
                   position: Vector2, stimuli: Array) -> Dictionary
    # -> {"intent": String, "direction": Vector2}
```

evaluates wirings top to bottom, the same first-match discipline
`npc_instruction_evaluator.gd` uses for the player's instruction rules. For
each wiring with an open gate it scores every stimulus:

```
pull  = Σ_{c ∈ channels} features[c] · sensitivity[c] · valence[c]
score = |pull| · level · Affinity.proximity(distance)
```

and takes the highest score. `Affinity.proximity(d) = 1 / (1 + d)` is a
*ranking* function, not physics: strictly decreasing and never zero, so that
between two stimuli with equal pull the nearer one wins, which is precisely
today's `_nearest` behaviour and is pinned by the existing
`test_flees_from_the_nearest_of_several_threats`. Range is the sense's job,
not the kernel's: `Olfaction.dilution` still says how far a smell carries and
`SENSE_RADIUS` still says how far a threat is noticed, and the kernel never
drops a stimulus a sense chose to report. The sign of the winning pull picks
`approach` or `avoid`; an open gate with no scoring stimulus yields `search`
when the wiring has one; and when every wiring has passed, the answer is
`wander` with a zero direction. `Affinity.toward`/`away_from` carry
`CreatureBehavior`'s existing `OVERLAP_FALLBACK` so a creature standing on its
threat still flees somewhere.

**The land-mammal ethogram**, `Ethogram.BODY_PLANS["mammal"]["wirings"]`, is
today's `CreatureBehavior` priority ladder written as data, in the same order
for the same reasons its doc comment gives (an animal does not court while
hunted, dying of thirst, starving or mid-hunt):

```gdscript
[
    {"gate": "fear",      "channels": ["danger"],     "approach": "attack",    "avoid": "flee"},
    {"gate": "thirst",    "channels": ["water"],      "approach": "seek_water", "search": "search_water"},
    {"gate": "hunger",    "channels": ["flesh"],      "approach": "hunt"},
    {"gate": "hunger",    "channels": SMELL_CHANNELS, "approach": "seek_food"},
    {"gate": "hunger",    "channels": ["forage"],     "approach": "seek_food", "search": "search_food"},
    {"gate": "courtship", "channels": ["mate"],       "approach": "court"},
]
```

Two things in that list are new, and both are inert for the live game until
slice 2. The smell wiring lets the kernel choose a windfall by nose through
the same ladder (`test_a_fly_and_a_boar_choose_different_fruit_through_the_kernel`
proves it against the real fruit mixtures), but `CreatureBehavior`'s context
carries no smells today, so the wiring never sees a stimulus from a live
marker; `ScentForaging.best_source` keeps doing that job in `CreatureMarker`
until the marker publishes smells as stimuli. And the ladder being *data*
means its order is a property a test can read
(`test_the_mammal_ladder_puts_fear_before_thirst_before_hunger_before_courtship`)
rather than an accident of `if` nesting.

Order is priority in slice 1. The roadmap's version (§8, slice 4) scores
across wirings with fear's gain large enough that the ladder falls out of the
numbers, and that ordering test is what will keep it honest when it does.

### 7. What sits on the kernel in slice 1

**`Olfaction` becomes a view.** `perceived_strength(species, mixture,
distance_tiles, genome := {})` is
`Affinity.loudness(mixture, expressed.sensitivity) * dilution(distance)`, and
`attraction_to` is `Affinity.pull(mixture, expressed.sensitivity,
expressed.valence) * dilution(distance)`, with `expressed =
Ethogram.express(species, genome)`. Emission (`fruit_mixture`, the ripe and
rotten mixtures) and dilution (`MAX_RANGE_TILES`, `DILUTION_POWER`) stay in
`olfaction.gd`: they are the physics of smell, not of animals. The roster
test moves from iterating `Olfaction.RECEPTORS` to iterating
`Ethogram.SPECIES` and asserting every nose covers every smell channel, which
is the same guarantee against a silently invisible molecule.

**`CreatureBehavior.decide` becomes the mammal adapter.** Same signature,
same context keys, same return shape. It maps:

| context | becomes |
|---|---|
| `threats: [Vector2]` | one stimulus each, `{danger: 1.0}` |
| `prey: [Vector2]` | one stimulus each, `{flesh: 1.0}` |
| `water_direction != ZERO` | one stimulus at `position + direction`, `{water: 1.0}` |
| `food_direction != ZERO` | one stimulus at `position + direction`, `{forage: 1.0}` |
| `is_courting` + `partner_position` | one stimulus, `{mate: 1.0}` |
| `hungry`, `thirsty`, `is_courting` | drives `hunger`, `thirst`, `courtship` at 1.0 or 0.0; `fear` at 1.0 |
| `is_world_boss and not is_aggroed` | `danger` *sensitivity* 0.0: an un-aggroed boss perceives no threat, so it neither attacks nor flees, and still drinks and eats (worldbosses.md) |
| `temperament == "aggressive" and health_fraction >= STRONG_HEALTH_FRACTION and is_mature` | `danger` *valence* +1.0 (stand and fight); otherwise −1.0 (flee) |
| `is_predator` | `flesh` valence +1.0; otherwise 0.0 |

Everything the existing 33 tests pin (the ladder order, nearest-threat flight,
the overlap fallback, the world-boss gate, the juvenile rule, the skittish
temperament, the search fallbacks) is preserved by that mapping and is
re-run unchanged as the regression bar. `_will_fight`, `_perceives_threats`,
`_nearest`, `_toward` and `_away_from` cease to exist as separate logic: the
first two are the two receptor overrides, the last three are the kernel.

**`CreatureMarker` does not change.** It builds the same context and consumes
the same intents. That is the point of doing slice 1 behind the decision
seam: a 2,700-line marker with behaviour tangled into rendering is not
rewritten, it is strangled.

### 8. Roadmap: the slices after this one

Each is its own red-first pass with its own status entries here; none is
started by slice 1.

- ⬜ **Slice 2, real stimuli.** `CreatureMarker` publishes its threat scan
  as `predator`/`player`/`conspecific` features, its `smells_near` results
  and `GrazerForaging`'s bite candidates as stimuli, and passes its species
  and genome. `ScentForaging.best_source` and `CreaturePerception`'s food
  direction retire into the kernel; `danger` stops being a verdict; the
  `flesh` and fight overrides move into the species record. Also the natural
  point to give a horse or a mouse its own smell block.
- ⬜ **Slice 3, one drive vector.** `CreatureNeeds`, `NpcNeeds`,
  `PiscivoreAppetite` and `BirdDigestion` become one `Drives` module with
  per-body-plan rates (the player's `SurvivalMeters` stays the player's);
  levels become ramps rather than 0/1, so a slightly hungry animal is
  slightly interested; the `START_STAGGER` idiom is kept.
- ⬜ **Slice 4, gains as personality.** Baseline gains per individual from the
  genome: `boldness` on `fear` (re-deriving `FlyerPersonality`'s flight
  initiation distance and `animal_husbandry.md`'s composed flight radius from
  the same number), temperament and `docility` on a `fight` gain, the spell
  `FEAR`/`CALM` statuses as a temporary push. With fear's gain large the
  ladder falls out of cross-wiring scoring, and the ordering test keeps it
  honest.
- ⬜ **Slice 5, the other body plans.** `bird`, `insect`, `fish`, `villager`
  ethograms whose wirings select the existing motor programs
  (`GroundForageBehavior`, `PiscivoreBirdBehavior`, `PollinatorForaging`,
  `CarrionForageBehavior`, `AntForageBehavior`, `NpcEconomy`) by body plan.
  The NPC instruction DSL becomes the player-facing dialect: a rule such as
  `if need_above(hunger, 0.7): gather(berries)` is a wiring override on the
  villager ethogram, evaluated by the same first-match kernel.
- ⬜ **Slice 6, mate choice.** An individual's displayed phenotype
  (`AnimalFitness.phenotype_for`) is a stimulus on display channels; a
  species' preference vector is [evolution.md](evolution.md)'s drifting
  "attractive phenotype target"; `Courtship.mates` weights by
  `AnimalFitness.mate_attractiveness` instead of the flat `MATING_CHANCE`,
  with animal_genetics.md §6's `NEUTRAL_ATTRACTIVENESS` discipline.
- ⬜ **Pathogens, immunity and pharmacology** reuse `affinity.gd` (a pathogen's
  tropism vector against a host's expressed receptors; an antigen signature
  against immune memory; a drug's binding vector against a pathogen). That is
  a separate doc extending [disease.md](disease.md), and the only reason
  `affinity.gd` is its own file rather than a corner of the kernel.

## Which doc owns what

- [olfaction.md](olfaction.md): what things emit and how smell thins with
  range. Its receptor table now lives in `Ethogram.SPECIES`; its status list
  says so.
- [animal_genetics.md](animal_genetics.md): the genome container, the
  crossover-verbatim discipline, `GENE_NAMES`/`GENE_READERS`. Receptor genes
  are proposed there, not declared there, until an `AnimalGenome` exists to
  hold them.
- [evolution.md](evolution.md): mate choice and the phenotype target (slice 6).
- [ecosystem_dynamics.md](ecosystem_dynamics.md): the ramps/hysteresis rule
  and every commitment mechanism the kernel deliberately leaves in place.
- [npc_instructions.md](npc_instructions.md): the player-facing rule grammar
  that slice 5 makes a dialect of this.
- [flies.md](flies.md), [carrion.md](carrion.md), [seed_dispersal.md](seed_dispersal.md):
  emitters, unchanged.

## What the player can see

After slice 1: nothing different, by design. Every animal decides exactly
what it decided yesterday, because the slice is a behaviour-preserving
re-expression of the decision it already made, pinned by the tests that
already existed. What the player gets is indirect and arrives with the later
slices: a species added as a record rather than a marker branch, individuals
whose noses differ and whose children inherit that, and personalities that
are numbers a breeder can select on.

## Status / mechanisms

- ✅ `affinity.gd`: `pull`, `loudness`, `proximity`, `toward`, `away_from`,
  `OVERLAP_FALLBACK` (`test_affinity.gd`, 9 tests).
- ✅ `ethogram.gd`: `CHANNELS`, `SMELL_CHANNELS`, `SPECIES` (the five smell
  records moved from `Olfaction.RECEPTORS`), `BODY_PLANS["mammal"]`,
  `has_nose`, `express` with `receptor_<channel>` genes,
  `NEUTRAL_RECEPTOR_GENE` and the body-plan override, `wirings_for`
  (`test_ethogram.gd`, 23 tests).
- ✅ `behavior_kernel.gd`: `decide` over ordered wirings; gate skip; approach
  by positive pull, avoid by negative, search on an open gate with nothing
  sensed; proximity ranking; the drive level scaling the score; overlap
  fallback; wander default; a stimulus under Olfaction's `mixture` key
  (`test_behavior_kernel.gd`, 20 tests).
- ✅ `Olfaction` reading `Ethogram.express`; `RECEPTORS` deleted; optional
  `genome` on `perceived_strength`/`attraction_to`; the species template
  cached per sniff; roster test moved to the ethogram.
- ✅ `ScentForaging.forages_by_smell` reading `Ethogram.has_nose`.
- ✅ `CreatureBehavior.decide` as the mammal adapter; all 33 existing tests
  green unchanged, plus six pinning the target and score in a decision, the
  optional `species`/`genome`/`smells` context keys, a record-less species
  on the ladder, and an individual's receptor genes reaching its decision.
- ✅ Receptor genes inherited through the unmodified `DnaCrossover.crossover`
  (`test_a_child_expresses_a_nose_between_its_parents`).
- ✅ Regression after the rewire: the olfaction, scent-foraging, flies,
  fly-life-cycle, creature-marker, creature-info, ambient-flyer-marker and
  piscivore-bird-marker suites all green.
- ⬜ Anything visible. The smell wiring and the `smells`/`species`/`genome`
  context keys are fed by nothing live; no animal carries a receptor gene.
- ⬜ Slices 2 to 6 above, each untouched.

*Coverage note: every mechanism in this list is a pure module with a headless
unit test. Nothing here is exercised by an integration test against a live
scene, which is the same limit animal_genetics.md records; `CreatureMarker`'s
own tests run against the unchanged `decide()` contract and are the closest
thing to one.*

## Open questions

- **When does `danger` stop being a verdict?** Slice 2 as planned, but the
  split between "the sense classifies" and "the valence decides" has a real
  cost question attached: a per-tick valence check over every nearby creature
  is more work than the marker's current group scan under `SimulationLod`.
- **One proximity law or one per sense?** Smell has its own dilution and the
  kernel ranks by a unit-free proximity. When vision and hearing get ranges,
  are those the sense's (as now) or does the kernel take a per-channel
  falloff?
- **Where does commitment live once scoring is continuous?** Today the caller
  commits (grazing approach, flee hysteresis). If slice 4's cross-wiring
  scoring can flip intents tick to tick, the kernel may need a small
  hysteresis of its own, which pillar 4 currently forbids it.
- **Receptor genes: one per channel, or fewer loci with pleiotropy?** One per
  channel is honest to receptor biology and cheap; it also means ten genes
  before any of them is visible in a panel. animal_genetics.md's reader rule
  applies.
- **Cost.** Scoring every stimulus against every open wiring per creature per
  tick is bounded by what the senses report, which is already culled by
  radius and by `SimulationLod`. Measured against the fish water-check
  regression this project has already paid for, not assumed.
