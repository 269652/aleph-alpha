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

| channel | what emits it | who publishes it |
|---|---|---|
| `sugar` | ripe fruit, nectar | `Olfaction.fruit_mixture` (✅) |
| `decay` | rotting fruit, carrion | `Olfaction.fruit_mixture` (✅) |
| `green` | leaves, cut grass, foliage | `Olfaction.fruit_mixture` (✅) |
| `musk` | animals themselves | reserved, nothing emits it yet |
| `smoke` | fire | reserved, nothing emits it yet |
| `predator` | a creature of a hunting species, by `CreatureInfo` | `CreatureMarker`'s creature scan (✅ slice 2) |
| `player` | a person | `CreatureMarker`'s player scan (✅ slice 2) |
| `flesh` | a creature that is not a hunter | `CreatureMarker`'s creature scan (✅ slice 2) |
| `forage` | plant food at that tile, or the bite the grazer has committed to | `CreaturePerception.nearest_tile_offset` / `GrazerForaging` (✅ slice 2) |
| `water` | drinkable water at that tile | `CreaturePerception.nearest_tile_offset` (✅ slice 2) |
| `mate` | my courtship partner | `MammalCourtship` pairing (✅ slice 2) |

`Ethogram.CHANNELS` is the ordered list; `Ethogram.SMELL_CHANNELS` is the
first five and is what `Olfaction.MOLECULES` now aliases. The molecule
constants (`Olfaction.SUGAR` and friends) keep their names and their values;
they are re-exported from the ethogram so that no caller of the smell API
changes.

**Danger is not a feature, and there is no `danger` channel.** Slice 1 had
one, because `CreatureMarker` then decided who counted as a threat (players
and predator creatures within `SENSE_RADIUS`) before `CreatureBehavior.decide`
ever ran, and the kernel could only be handed that classification. Slice 2
made the scan report what the other thing *is* -- `predator`, `player`,
`flesh` -- and left the verdict to the species valence: a sheep flees a wolf,
a wolf ignores a wolf and eats a sheep, a tamed horse no longer perceives a
person at all. `test_the_basis_also_carries_the_non_smell_channels_the_mammal_ladder_needs`
pins that `danger` never comes back. A `conspecific` feature waits for a
wiring that reads it (herd alarm, evolution.md); under pillar 7 a channel
nothing reads is not published.

### 2. Stimuli

A stimulus is `{"position": Vector2, "features": {channel: float}}` plus
whatever the sense wants back: `CreatureMarker` tags each creature stimulus
with its `node`, and the kernel returns the winning stimulus whole, which is
how the marker gets its prey or attack target back. It is what a sense hands
the kernel. There is no stimulus *type*: a rotten apple is `{decay: 1.0,
sugar: 0.15, green: 0.05}` and a wolf is `{predator: 1.0}`, and the only
thing that distinguishes them is where they sit in the basis.

A stimulus may also carry a `strength`: how loud it is at this range, when
the sense that reported it knows (smell, with `Olfaction.dilution`). The
kernel then ranks by that instead of by its unit-free distance ranking
(§6), and a wiring's `floor` is stated in those units. Anything on the smell
channels therefore arrives through `ScentForaging.stimuli_from`, which is
what attaches it.

Who builds them:

- ✅ `Olfaction.fruit_mixture(item_id, freshness)` is a feature vector over
  the smell channels; `EarthChunkManager.smells_near` returns `{position,
  mixture}` lists; `ScentForaging.stimuli_from` turns those into stimuli with
  their dilution as `strength`. `mixture` and `features` are the same thing
  under two names, and the kernel accepts either key.
- ✅ slice 2: `CreatureMarker` publishes its senses on every sensing tick
  (`_cached_stimuli`): every other creature as `{predator: 1}` or
  `{flesh: 1}` by *its* role, every person as `{player: 1}`, the nearest
  water and plant-food tiles at their real positions, and, per frame, its
  courtship partner as `{mate: 1}`. The adapter's own synthesis from position
  lists and headings survives only for callers that still speak the older
  context shape (§7).
- 🚧 Grazing bites are *not* stimuli. `GrazerForaging` still picks a visible
  grass/fruit/seed/worm bite in diet order (`choose_bite`) and commits to it;
  what slice 2 changed is that its smell step ranks through the kernel with
  the individual's genome (`ScentForaging.best_source`). Diet order is
  lexicographic (a boar prefers mast over grass at any distance), which a
  weighted sum does not express; publishing bites as stimuli needs per-kind
  wirings per species and is left for the body-plan slice.

### 3. Species records and body plans

```gdscript
Ethogram.SPECIES = {
    "boar":       {"body_plan": "mammal", "smell": {"sensitivity": {...}, "valence": {...}}},
    "deer":       {"body_plan": "mammal", ...},
    "horse":      {"body_plan": "mammal", ...},
    "robin":      {"body_plan": "bird",   ...},
    "fly":        {"body_plan": "insect", ...},
    "kingfisher": {"body_plan": "bird",   "drives": {"hunger": {...}}},   # a clock, no nose
}
Ethogram.BODY_PLANS = {
    "mammal":   {"receptors": {...}, "drives": {"hunger": {...}, "thirst": {...}}, "wirings": [...]},
    "villager": {"drives": {"hunger": {...}}},
    "bird":     {"drives": {"hunger": {...}}},
}
```

A record may carry any of three blocks: `smell` (receptors, §4), `drives`
(its clock, §5) and, on a body plan, `receptors` defaults and `wirings`
(§6). A species overrides its plan block by block.

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
| `predator` | 1.0 | −1.0 | every mammal notices a hunter, and the default answer is to leave; the adapter flips valence to +1.0 for an animal that will stand and fight, and to 0.0 for a hunter, which is not threatened by other creatures (§7) |
| `player` | 1.0 | −1.0 | likewise for a person; the adapter zeroes *sensitivity* for a tamed animal, which has stopped perceiving people as anything at all |
| `flesh` | 1.0 | 0.0 | a herbivore sees prey and wants nothing from it; the adapter sets +1.0 for a predator |
| `forage` | 1.0 | +1.0 | plant food is food |
| `water` | 1.0 | +1.0 | |
| `mate` | 1.0 | +1.0 | |

The adapter overrides are species and state facts that reach `decide()` as
context flags (`temperament`, `health_fraction`, `is_mature`, `is_predator`,
`fears_players`, the world-boss aggro pair). The species record is where the
species half belongs (`flesh` valence and "ignores other hunters" are diet
facts; the fight valence is temperament) and `CreatureInfo`'s
`PREDATOR_SPECIES`/`TEMPERAMENT_BY_SPECIES` tables are their source today for
all thirty species, five of which have an ethogram record. Moving them
means moving those tables, which is the body-plan slice's job (§8); the
state half (health, maturity, taming, aggro) stays an override by nature.

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

**Reader, and where the genes come from.** `Olfaction.perceived_strength`
and `Olfaction.attraction_to` take an optional trailing `genome` argument and
read `Ethogram.express(species, genome)`; `ScentForaging.best_source` takes
the same and ranks through the kernel. Those are the production readers.
Since slice 2 every live land mammal has a genome to hand them:
`src/gameplay/animal_genome.gd` exists with exactly the receptor genes
(`GENE_NAMES`, one per smell channel) and `GENE_READERS` naming
`ethogram.gd` for each, under animal_genetics.md's own anti-dead-weight
guard (`test_every_gene_has_a_named_production_reader`,
`test_every_named_reader_module_exists`). `AnimalGenome.for_seed` derives it
from the marker's `wander_seed` -- bell-shaped around the species template,
the same shape `FlyerPersonality` gives boldness, so most individuals are
close to their species and a freak nose is rare -- and
`CreatureMarker.genome_or_derived()` hands it to every decision and every
sniff, preferring a stored `genome` when a bred or restored animal has one.
Nothing new is persisted: the seed already is. What is still that doc's:
the seven genes it specifies, two-parent births (`from_parents`), and the
V2 record.

### 5. Modulation: drives as gains

A **drive** is a named level in [0, 1]: `hunger`, `thirst`, `fear`,
`courtship`. Every wiring names the drive that *gates* it, and the kernel
multiplies a wiring's pull by that drive's **gain**. A gain of zero switches
the wiring off entirely; a hungry animal at gain one finds food exactly as
loud as the receptors make it. That single multiplication is the whole of
"neuromodulation" in this model, and it is enough for hunger to sharpen the
nose (Root et al.) and for a sated animal to walk past a windfall.

**One clock (slice 3).** `src/gameplay/drives.gd` is the single
implementation of "rises over time, crosses a threshold, a meal takes it
back down", and the numbers are a **drive profile** in the species record or
its body plan (`Ethogram.drive_profile(species, body_plan)`), with these
fields per drive:

| field | meaning |
|---|---|
| `rise_seconds` | how long the drive takes from 0 (satisfied) to 1 (desperate), in the world's own seconds |
| `threshold` | the level from which the drive is *urgent* (the old `is_hungry`) and its gain is fully open |
| `meal` | how much one meal takes off; 1.0 or more resets |
| `start` | (optional) where a fresh individual begins: a bird starts empty, a mammal fed |
| `stagger` | (optional) how far into its cycle a fresh *seeded* individual may start, so a herd is not on one clock; the same hash `CreatureNeeds` always used |
| `onset` | (optional) the level at which the gain begins to open; below the threshold it makes the gain a **ramp**, so a slightly hungry animal is slightly interested. Defaults to the threshold: a step |

The profiles are the numbers the four animal clocks always ran, moved into
the ethogram: `mammal` (CreatureNeeds' 0.02/s hunger and 0.03/s thirst,
urgent from half way, staggered up to 0.45), `villager` (the same pace,
hunger only, per npc.md), `bird` (BirdDigestion's songbird crop, as hunger:
empties in an eighth of the world day, urgent below 0.35 full, a meal fills
0.7, starts empty), and a `kingfisher` species record overriding the bird
appetite (PiscivoreAppetite's two meals a day, a whole inter-meal interval
before it is interested again). `CreatureNeeds`, `NpcNeeds`,
`PiscivoreAppetite` and `BirdDigestion` survive as **facades** over `Drives`
with their APIs and their re-exported numbers unchanged, so their markers,
consumers and tests did not move; the player's `SurvivalMeters` stays the
player's (it has stamina and fitness, and a player is not a species record).
`Drives.gains()` is what the mammal adapter now receives as `drives`, and a
partial gain opens its gate.

Every profile keeps the **step** its own tests pin -- no profile sets an
`onset` -- because under first-match arbitration any nonzero gain fires its
wiring, so a ramp today would only make animals forage below the threshold
they were tuned to. A ramp becomes meaningful with cross-wiring scoring
(slice 4), which is where the first `onset` goes in. `fear` is always `1.0`
(an un-aggroed world boss is handled by *sensitivity*, §7, because it
genuinely does not perceive the player as a threat rather than merely not
caring); `courtship` is `1.0` while paired. Personality as a baseline on
these gains (boldness lowering `fear`, temperament raising a `fight` gain),
and the spell `FEAR`/`CALM` statuses as a temporary push on the same gain
rather than today's temperament-string swap in
`CreatureMarker._temperament_for_decision`, are slice 4.

### 6. Wirings and the kernel

A **wiring** is one line of the ethogram:

```gdscript
{"gate": "hunger", "channels": ["flesh"], "approach": "hunt"}
{"gate": "thirst", "channels": ["water"], "approach": "seek_water", "search": "search_water"}
{"gate": "fear",   "channels": ["predator", "player"], "approach": "attack", "avoid": "flee"}
```

- `gate`: the drive whose level scales this wiring; level zero skips it.
- `channels`: the subset of the basis this wiring listens on.
- `approach`: the intent when the best stimulus *draws* (pull > 0), heading
  toward it.
- `avoid` (optional): the intent when the best stimulus *repels* (pull < 0),
  heading away. A wiring with no `avoid` listens only for what draws it: a
  deer that smells a carcass neither bolts from it nor lets it shadow the
  ripe apple beyond.
- `search` (optional): the intent when the gate is open but nothing on these
  channels is sensed at all, with a zero direction for the caller to fill in,
  exactly today's `search_food`/`search_water` contract.
- `floor` (optional): the score a stimulus must exceed to fire the wiring at
  all. The smell wiring carries `Ethogram.SMELL_INTEREST_FLOOR`, which is
  what `ScentForaging.MIN_INTEREST` now aliases.

The kernel:

```gdscript
static func decide(wirings: Array, receptors: Dictionary, drives: Dictionary,
                   position: Vector2, stimuli: Array) -> Dictionary
    # -> {"intent", "direction", "score", "target", "stimulus"}
static func best_stimulus(receptors, channels, position, stimuli,
                          level := 1.0, floor := 0.0, attract_only := false) -> Dictionary
    # -> {"stimulus", "pull", "score"} or {}
static func perceived(receptors, channels, stimuli) -> Array
    # every stimulus with a nonzero pull on those channels, fight or flee alike
```

`decide` evaluates wirings top to bottom, the same first-match discipline
`npc_instruction_evaluator.gd` uses for the player's instruction rules. For
each wiring with an open gate it scores every stimulus:

```
pull  = Σ_{c ∈ channels} features[c] · sensitivity[c] · valence[c]
score = |pull| · level · weight
weight = stimulus.strength if the sense supplied one, else Affinity.proximity(distance)
```

and takes the highest score. `Affinity.proximity(d) = 1 / (1 + d)` is a
*ranking* function, not physics: strictly decreasing and never zero, so that
between two stimuli with equal pull the nearer one wins, which is precisely
the old `_nearest` behaviour and is pinned by
`test_flees_from_the_nearest_of_several_threats`. Range is the sense's job,
not the kernel's: `Olfaction.dilution` says how far a smell carries and hands
it over as `strength`, `SENSE_RADIUS` says how far a threat is noticed, and
the kernel never drops a stimulus a sense chose to report (a strength of zero
is how a sense says "out of range"). The sign of the winning pull picks
`approach` or `avoid`; an open gate with no scoring stimulus yields `search`
when the wiring has one; and when every wiring has passed, the answer is
`wander` with a zero direction. `Affinity.toward`/`away_from` carry
`CreatureBehavior`'s old `OVERLAP_FALLBACK` so a creature standing on its
threat still flees somewhere. `best_stimulus` is the same ranking on its own,
for a motor program that picks a target and commits to it itself (the grazer
choosing what to smell its way to); `perceived` is what the marker keeps as
its threat list (§7).

**The land-mammal ethogram**, `Ethogram.BODY_PLANS["mammal"]["wirings"]`, is
today's `CreatureBehavior` priority ladder written as data, in the same order
for the same reasons its doc comment gives (an animal does not court while
hunted, dying of thirst, starving or mid-hunt):

```gdscript
[
    {"gate": "fear",      "channels": ["predator", "player"], "approach": "attack", "avoid": "flee"},
    {"gate": "thirst",    "channels": ["water"],      "approach": "seek_water", "search": "search_water"},
    {"gate": "hunger",    "channels": ["flesh"],      "approach": "hunt"},
    {"gate": "hunger",    "channels": SMELL_CHANNELS, "approach": "seek_food", "floor": SMELL_INTEREST_FLOOR},
    {"gate": "hunger",    "channels": ["forage"],     "approach": "seek_food", "search": "search_food"},
    {"gate": "courtship", "channels": ["mate"],       "approach": "court"},
]
```

The ladder being *data* means its order is a property a test can read
(`test_the_mammal_ladder_puts_fear_before_thirst_before_hunger_before_courtship`)
rather than an accident of `if` nesting. The smell wiring lets the kernel
choose a windfall by nose through the same ladder
(`test_a_fly_and_a_boar_choose_different_fruit_through_the_kernel` proves it
against the real fruit mixtures); the adapter reaches it through its `smells`
context key. The live mammal marker does not: its grazing bout owns the
commitment to a bite, so it ranks smells with the same kernel
(`ScentForaging.best_source`, with the individual's genome) *inside* that
motor program and hands the winner to `GrazerForaging` -- pillar 4, the
caller commits. The wiring's live readers are the body plans that hunt by
nose without a grazing bout (§8, slice 5).

Order is priority in slice 1. The roadmap's version (§8, slice 4) scores
across wirings with fear's gain large enough that the ladder falls out of the
numbers, and that ordering test is what will keep it honest when it does.

### 7. What sits on the kernel

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

**`CreatureBehavior.decide` is the mammal adapter.** Same signature, same
intents. A caller that publishes `stimuli` is taken at its word; the older
position-list shape is turned into stimuli for callers that still speak it.
The overrides on the individual's expressed receptors:

| context | becomes |
|---|---|
| `stimuli` | used as published (`{predator}`, `{player}`, `{flesh}`, `{forage}`, `{water}`, `{mate}`, smells) |
| `threats: [Vector2]` (older shape) | one stimulus each, `{player: 1.0}` -- the one feature every species answers |
| `prey: [Vector2]`, `water_direction`, `food_direction`, `partner_position`, `smells` (older shape) | stimuli as before; smells through `ScentForaging.stimuli_from` |
| `hungry`, `thirsty`, `is_courting` | drives `hunger`, `thirst`, `courtship` at 1.0 or 0.0; `fear` at 1.0 |
| `is_world_boss and not is_aggroed` | `predator` and `player` *sensitivity* 0.0: an un-aggroed boss perceives no threat, so it neither attacks nor flees, and still drinks and eats (worldbosses.md) |
| `fears_players == false` (tamed) | `player` *sensitivity* 0.0: people are not a thing it reacts to any more |
| `temperament == "aggressive" and health_fraction >= STRONG_HEALTH_FRACTION and is_mature` | `player` *valence* +1.0 (stand and fight), and `predator` valence likewise for a non-hunter; otherwise −1.0 (flee) |
| `is_predator` | `predator` valence 0.0 (a hunter is not threatened by other creatures, only by people); `flesh` valence +1.0; otherwise 0.0 |

Everything the original 33 tests pin (the ladder order, nearest-threat flight,
the overlap fallback, the world-boss gate, the juvenile rule, the skittish
temperament, the search fallbacks) is preserved and re-run unchanged as the
regression bar; the slice-2 tests add the stimulus path, the predator and
tamed verdicts, and `threats()`. `_will_fight` and `_perceives_threats`
survive as the receptor overrides; `_nearest`, `_toward` and `_away_from`
are the kernel. The adapter caches its expression and the wirings per
instance, since it runs every frame for every creature.

**`CreatureBehavior.threats(context)`** is `BehaviorKernel.perceived` on the
fear channels: everything this individual *notices* as dangerous, whether it
would fight or flee it. That is what the marker keeps as its threat list.

**`CreatureMarker` (slice 2).** On each sensing tick it publishes
`_cached_stimuli` (§2) and asks `threats()` for what it notices; that list
feeds the grazing abort ("a threat outranks a meal"), and the flee-release
widening of the scan radius runs off `_is_fleeing` as before. `decide()`
gets the stimuli plus the frame-fresh courtship partner; `attack` and `hunt`
act on the node the winning stimulus carries instead of re-scanning for the
nearest. The old prey cache and the two direction caches are gone. The
caution radius for wander avoidance (players within `CAUTION_RADIUS`) and
the flee Schmitt trigger are untouched: they are commitment, not verdict.
The genome reaches both `decide()` and the grazing bout's smell step through
`genome_or_derived()` (§4).

### 9. Personality: a boldness gene

A first, deliberately narrow slice of "gains as personality." The original
plan for this slice named three things: boldness on `fear`, `docility` on a
new `fight` gain, and the spell `FEAR`/`CALM` statuses pushing on a gain
instead of overriding the temperament string. Building it turned up that two
of those three don't hold up on inspection, and this doc says so rather than
building past what the inspection found:

- **`docility` does not exist.** It is one of animal_genetics.md's seven
  specified genes, none of which are in `AnimalGenome` yet, and that doc — not
  this one — owns when a gene is introduced (§1's own reader rule). Inventing
  it here, ahead of that doc's own domestication mechanism (§10, the thing
  that would actually make docility *move* over generations), would be this
  doc reaching into a neighbour's job for a gene with nothing to select it.
- **The spell mechanism was never broken.** `CreatureMarker._temperament_for_decision`
  already overrides `context["temperament"]` correctly for the duration of a
  `FEAR`/`CALM` debuff, and three passing tests already prove it. "Push a
  gain instead of swapping a string" was a cleanliness preference, not a
  fix for wrong behaviour, and TDD only licenses touching working, tested code
  when a failing test demands it — there wasn't one.

What remains, and what actually shipped: a **boldness gene**, land-mammal
specific, that raises the *floor* the fear wiring's score must clear before
it fires at all. Boldness is not a `fear` gate multiplier — a multiplier
scales the *score*, and under first-match arbitration any nonzero score still
wins outright regardless of magnitude, so a multiplier alone would be exactly
the dead-weight gene animal_genetics.md's pillar 2 forbids. A *floor*, the
same mechanism the smell wiring already uses for its interest threshold (§6),
genuinely gates whether the wiring fires:

```gdscript
Ethogram.NEUTRAL_BOLDNESS_GENE := 0.5
Ethogram.BOLDEST_FEAR_FLOOR := 1.0 / (1.0 + TerrainRenderer.TILE_SIZE)  # = Affinity.proximity(one tile)

static func fear_floor(gene: float) -> float:
    if gene <= NEUTRAL_BOLDNESS_GENE: return 0.0
    return (gene - NEUTRAL_BOLDNESS_GENE) / (1.0 - NEUTRAL_BOLDNESS_GENE) * BOLDEST_FEAR_FLOOR
```

Two things about this are load-bearing, not incidental. **Zero at or below
the median.** The mammal ladder's fear wiring has always had a floor of zero
— every sensed predator or player registers, which is already the *most*
fearful state a floor can express; there is nowhere to go more shy. So the
gene only ever raises the floor, and only past 0.5, which means every
individual at or below the population median behaves *exactly* as every land
mammal always has — the regression bar (all pre-existing `CreatureBehavior`
and `CreatureMarker` tests) holds by construction, not by exemption.
**The ceiling is one tile, not zero distance.** `Affinity.proximity(0.0) =
1.0` looks like the natural cap — the kernel's own theoretical maximum score
for a stimulus of this pull magnitude — but capping there makes the boldest
individual's floor *unreachable at any distance a running simulation actually
produces* (a marker's own position is never exactly zero pixels from
another's), which is a difference between "rare" and "impossible" that
matters. `TerrainRenderer.TILE_SIZE` — the same "right here" reference
`CreatureBehavior.DIRECTION_STIMULUS_DISTANCE` already uses to place a sensed
direction as a stimulus — gives a real, reachable, still-demanding ceiling:
the boldest individual's own fear wiring requires a predator within about a
tile before it fires at all.

This is deliberately **not** a re-derivation of `FlyerPersonality`'s flight
initiation distance, despite that earlier being the plan. Butterflies and
land mammals are different body plans with no shared infrastructure yet
(slice 5's job), and `FlyerPersonality`'s metre constants (3.0m shyest, 0m
boldest) are butterfly-specific measurements with no grounding for a boar or
a deer — reusing them verbatim would have been dishonest, not unifying.
What *is* shared is the shape: most individuals near the population median,
rare bold outliers, the same "mean of two independent halves" distribution
`AnimalGenome` already gives every gene — a real analogy to
`FlyerPersonality`'s own reasoning, named as an analogy rather than claimed
as the same number.

**The reader.** `CreatureBehavior._apply_boldness_floor` patches the cached
fear wiring's `floor` field on genome change, the same per-instance mutation
`Ethogram.wirings_for`'s deep copy makes safe (§6). Wiring it up surfaced a
real, independent bug worth recording here because it will bite the next
gain-based gate too: `CreatureMarker` calls `CreatureBehavior.threats()`
every sensing tick *before* `decide()` ever runs for a fresh instance, and
`threats()` shares `decide()`'s genome-change cache without itself ensuring
the wirings array exists — so the floor patched an empty array on that first
call, and with the genome now marked "seen," the cache never gave it a
second chance. Fixed by having both entry points share one
`_ensure_wirings()` guard; pinned directly
(`test_threats_called_before_the_first_decide_still_lets_the_floor_apply`),
not just by the boldness tests that happened to expose it.

### 8. Roadmap: the slices after this one

Each is its own red-first pass with its own status entries here.

- ✅ **Slice 2, real stimuli** (2026-09-05). `CreatureMarker` publishes its
  creature and player scans as `predator`/`player`/`flesh` features and the
  nearest water/food tiles at real positions, passes its species and genome,
  and reads its threat list back from the valence (`threats()`); `danger`
  is gone from the basis. `ScentForaging.best_source` ranks through the
  kernel with the individual genome; `CreaturePerception` reports the tile
  itself. `AnimalGenome.for_seed` gives every land mammal receptor genes
  from its `wander_seed`, so individual noses are live. Deliberately not
  done, and recorded in §2 and §3: grazing bites stay `GrazerForaging`'s
  (diet order is lexicographic), the `flesh`/fight/"ignores other hunters"
  facts stay adapter overrides sourced from `CreatureInfo`'s tables, and no
  `conspecific` feature is published until a wiring reads one.
- ✅ **Slice 3, one drive vector** (2026-09-05). `Drives` is the one clock;
  the four animal needs modules are facades over it with their numbers as
  ethogram drive profiles (§5); the mammal adapter takes published gains.
  Deliberately not done: no profile sets an `onset`, so every gain is still
  the step its tests pin -- a ramp only makes sense once wirings are scored
  against each other (slice 4).
- ✅ **Slice 4, a boldness gene** (2026-09-05), narrower than originally
  planned — see §9 for the full account and why. A land-mammal `boldness`
  gene raises the fear wiring's *floor* (not its gain — a gain alone is
  dead weight under first-match arbitration), zero at or below the
  population median, capped at one tile away for the boldest possible
  individual. Deliberately not done, and why: `docility` on a fight gain
  (no docility gene exists; that gene is animal_genetics.md's to introduce);
  the spell `FEAR`/`CALM` mechanism (already correct, no failing test
  motivated touching it); cross-wiring scoring (turned out unnecessary — a
  floor works entirely within first-match ordering). A real ordering bug
  surfaced and got fixed along the way: `threats()` must ensure the cached
  wirings exist before touching the genome-change cache, same as `decide()`.
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

After slice 1: nothing different, by design. Every animal decided exactly
what it decided the day before, because the slice was a behaviour-preserving
re-expression of the decision it already made, pinned by the tests that
already existed.

After slice 2: individuals. Every wild land mammal derives receptor genes
from its own seed, so two boars at the same windfall can disagree about it,
and one born without a decay receptor walks past carrion the other takes.
Nothing else looks different, because the verdicts moved without changing:
a sheep still flees a wolf, a wolf still ignores a wolf, a tamed horse still
ignores its owner. What is still to come: a species added as a record rather
than a marker branch, children who inherit their parents' noses, and
personalities that are numbers a breeder can select on.

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
- ✅ Slice 2: `predator`/`player`/`flesh` replace `danger` in the basis; the
  kernel returns the winning stimulus whole, ranks by a sense-supplied
  `strength`, honours a wiring `floor`, and exposes `best_stimulus` and
  `perceived`; `ScentForaging.stimuli_from`/`best_source` rank through the
  kernel with a genome; `CreaturePerception.nearest_tile_offset`;
  `AnimalGenome.for_seed` with `GENE_NAMES`/`GENE_READERS` and the two guard
  tests; `CreatureBehavior` takes published `stimuli` and `fears_players`,
  exposes `threats()`, caches its expression; `CreatureMarker` publishes
  `_cached_stimuli`, derives `genome_or_derived()` from `wander_seed`, and
  acts on the winning stimulus's node. Marker, adapter, creature-info,
  ambient-flyer, piscivore, taming, reproduction and courtship suites green.
- ✅ Visible now: every wild land mammal has its own nose. A boar born
  without a decay receptor walks past carrion the next boar takes
  (`test_an_individuals_nose_reaches_the_live_forage_choice`).
- ✅ Slice 3: `drives.gd` (levels, urgency, meals, seeded stagger with the
  old hash, gains as step-or-ramp, the stateless helpers; `test_drives.gd`,
  21 tests); `Ethogram.drive_profile` with the `mammal`, `villager` and
  `bird` plan clocks and the `kingfisher` record; `CreatureNeeds`,
  `NpcNeeds`, `PiscivoreAppetite` and `BirdDigestion` as facades with their
  numbers re-exported from the profiles and every existing test green;
  `CreatureBehavior` taking published `drives`; `CreatureMarker` publishing
  `CreatureNeeds.gains()`.
- ⬜ A drive with an `onset` (a live ramp); the player's meters.
- ⬜ Grazing bites as stimuli; the species half of the adapter overrides in
  the species record; a `conspecific` feature (§2, §3).
- ✅ Slice 4 (§9): `Ethogram.BOLDNESS`/`NEUTRAL_BOLDNESS_GENE`/
  `BOLDEST_FEAR_FLOOR`/`fear_floor`; `AnimalGenome.GENE_NAMES` gains
  `boldness`, bell-shaped like every other gene; `CreatureBehavior.
  _apply_boldness_floor` patching the cached fear wiring per individual;
  `_ensure_wirings()` shared by `decide()` and `threats()`, fixing a real
  ordering bug threats-before-first-decide exposed. 8 new/changed tests
  (`test_ethogram.gd` +4, `test_animal_genome.gd` +1 changed +1 new,
  `test_creature_behavior.gd` +3, `test_creature_marker.gd` +2); full
  affected regression (534 tests across every touched suite) green.
- ⬜ Docility on a fight gain (no gene yet — animal_genetics.md's to
  introduce); the spell `FEAR`/`CALM` mechanism as a gain push (reconsidered
  — already correct, no failing test); cross-wiring scoring (turned out
  unnecessary for slice 4 — a floor works entirely within first-match
  ordering; still open for slice 5+ if a later gain genuinely needs it).
- ⬜ Slices 5 and 6 above, each untouched.

*Coverage note: every mechanism in this list is a pure module with a headless
unit test. Nothing here is exercised by an integration test against a live
scene, which is the same limit animal_genetics.md records; `CreatureMarker`'s
own tests run against the unchanged `decide()` contract and are the closest
thing to one.*

## Open questions

- **Resolved: `danger` stopped being a verdict in slice 2.** The cost
  question it carried turned out small: the scan still classifies each
  creature by its own role in the same one pass, and the valence check is
  one dot product per stimulus per sensing tick (`threats()`), not per
  frame. What is still open is the *species* half of the overrides (§3).
- **One proximity law or one per sense?** Smell has its own dilution and the
  kernel ranks by a unit-free proximity. When vision and hearing get ranges,
  are those the sense's (as now) or does the kernel take a per-channel
  falloff?
- **Where does commitment live if cross-wiring scoring is ever built?** Still
  open, and now genuinely deferred rather than merely unscheduled: slice 4
  found a floor sufficient for boldness and never needed to replace
  first-match ordering. If a later gain genuinely can't be expressed as a
  floor and cross-wiring scoring is finally built, the caller still commits
  today (grazing approach, flee hysteresis) — continuous scoring flipping
  intents tick to tick would need a small hysteresis of its own, which
  pillar 4 currently forbids the kernel.
- **Receptor genes: one per channel, or fewer loci with pleiotropy?** One per
  channel is honest to receptor biology and cheap; it also means ten genes
  before any of them is visible in a panel. animal_genetics.md's reader rule
  applies.
- **Cost.** Scoring every stimulus against every open wiring per creature per
  tick is bounded by what the senses report, which is already culled by
  radius and by `SimulationLod`. Measured against the fish water-check
  regression this project has already paid for, not assumed.
