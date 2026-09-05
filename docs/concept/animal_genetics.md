# Animal Genetics

The data model behind every animal born in this world: what an individual's
genes are, where they are stored, how two parents combine into a child, and how
a player selects on all of that deliberately instead of watching it happen.

[evolution.md](evolution.md)'s "Bloodlines" section already argues for this
system in prose and says outright that an animal birth today "produces an
offspring with **no genome at all**". That is still true. This doc is the data
model that section calls for and never wrote.

**Nothing in this doc is implemented.** Every mechanism below is ⬜ in the
status list at the bottom, including the ones specified here down to the
function signature. Three of the modules it composes (`dna_crossover.gd`,
`animal_fitness.gd`, `crop_breeding.gd`) are real, complete and unit-tested —
and have **zero production callers**, verified by grep across `src/` and
`scenes/` (the only hit outside their own files and tests is a doc comment in
`npc_genome.gd`). The work here is almost entirely wiring, not invention — but
see §0 for the one thing about that wiring that is easy to get wrong and that
an earlier draft of this doc got wrong.

## Design pillars

1. **The player breeds; the world does not breed for them.** Every mechanism
   below has to survive one question: *what does the player press, and what
   does the world do back?* A gene that only ever moves because a timer fired
   is a stat readout, not a mechanic. So: the player picks the two parents, the
   player sees the predicted range before committing, the player pays the feed
   that shortens the interval, and the player eats the consequence when the
   line inbreeds. The wild population still breeds on its own — but the wild
   population is a *baseline to beat*, and the player's herd diverges from it
   because of choices the player made.

2. **A trait nobody can see is dead weight.** Every gene in `GENE_NAMES` must
   have a named production reader that changes something observable: a number
   on a panel the game already draws, a speed the player feels under a saddle,
   a colour, a silhouette size, or an interval they are waiting on. This is
   enforced structurally, not by discipline — see
   `test_every_gene_has_a_named_production_reader` below. Five genes with real
   readers beat twelve with a spreadsheet.

3. **Reuse the crossover that already exists, verbatim.**
   `src/gameplay/dna_crossover.gd` is a correct two-parent per-trait crossover
   with bounded mutation, eleven unit tests, and nobody calling it. It is not
   modified by this doc, not wrapped in a variant, not duplicated for animals,
   and — this is the part that matters in practice — **not converted to static
   functions either**. Same for `src/world/animal_fitness.gd` and
   `src/gameplay/crop_breeding.gd`. "Verbatim" means the file is not touched at
   all, which constrains how the call sites are written; §0 spells that out.
   [synthesis.md](synthesis.md)'s north star — "One evolutionary system governs
   all life — beasts, crops, and people" — is currently true of zero kingdoms;
   the cheapest honest way to make it true of one is to call the function that
   is already sitting there.

4. **Genotype underneath, one visible phenotype on top.** The same split
   `TreeGenome`, `HeroDna` and `NpcGenome` already use: continuous 0..1 genes
   stored (or derived), and a small set of expressed, legible consequences.
   `NpcGenome`'s own header records this as the house shape.

5. **Selective breeding is a distribution you are choosing, not an outcome you
   are buying.** The predicted-child readout shows a *range*, because the
   crossover really does roll. A breeding program that always produced the
   midpoint of its parents would be an upgrade shop with animals in it.

6. **Improvement must have a real enemy.** A monotone stat climb is not a
   mechanic. Inbreeding depression is the enemy, it is grounded in actual
   genetics, and its counter-play sends the player back out to the wild with a
   lasso — which is the loop [taming.md](taming.md) already built and which is
   the best-feeling thing in the game. §9 states plainly what that counter-play
   depends on, because [animal_husbandry.md](animal_husbandry.md) has since
   established that getting near a wild animal is not currently a solved
   problem.

## Real-world grounding

**Blending inheritance with mutation.** `DnaCrossover.crossover` coin-flips
each trait toward one parent independently and then nudges it, rather than
averaging the pair. That is the right model: real quantitative traits are
polygenic and segregate independently, which is exactly why a foal can take its
sire's build and its dam's temperament rather than being the mean of both. The
existing `test_across_many_seeds_child_sometimes_leans_toward_each_parent`
already pins that property.

**Estimated breeding value.** Real selective breeding is not a black-box
"breeding chance" roll — it is arithmetic on measurable parent traits. The
predicted-child readout in §6 is the game's version of an EBV, and it is
computed by running the *actual* crossover over a spread of child seeds, so the
prediction and the outcome can never diverge.

**Nutritional flushing.** Ewes and sows genuinely do return to oestrus sooner
on a rising plane of nutrition; putting breeding stock on better feed before
the season is standard husbandry, not a game convenience. That is the real
mechanism behind §5's "the player's carrots shorten the interval".

**Inbreeding depression.** Mating relatives raises homozygosity and exposes
deleterious recessives. The damage falls disproportionately on *fitness*
traits — fertility, neonatal survival, growth rate — rather than on conformation
or colour, which is precisely why real closed herds lose their breeding
performance before they lose their looks. §9 models that asymmetry directly.
Wright's coefficient of relationship gives the textbook values the kinship
tests assert against: full siblings 0.5, half siblings 0.25, parent–offspring
0.5, first cousins 0.125.

**Domestication syndrome and the neural-crest hypothesis.** Belyaev's farm-fox
experiment selected on tameability *alone*, generation after generation, and got
piebald coats, floppy ears, shortened muzzles and earlier, more frequent oestrus
as unselected side effects. Wilkins, Wrangham & Fitch (2014) explain the package
as mild neural-crest deficit: the same cell population builds pigment cells,
craniofacial cartilage and the adrenal stress axis, so selecting on the stress
response drags pigmentation and fertility along with it. §10 makes that a
*modelled correlation* between the docility, coat and fertility genes rather
than an arbitrary domestication bonus — and it delivers the sting too: a
tame animal is a worse animal at not being eaten.

**Kleiber's law.** Metabolic rate scales roughly as mass^0.75, so a bigger
animal eats more in absolute terms. That is why the size gene costs feed (§1),
which is what stops "breed everything bigger" from being free.

## Mechanism spec

### 0. How the three reused modules are actually called

This section exists because getting it wrong produces code that does not
compile, and because the shape of the mistake is invisible in prose — a
class-level call reads exactly like a static one.

`dna_crossover.gd`, `animal_fitness.gd` and `crop_breeding.gd` all begin
`extends RefCounted` and declare **plain `func`, not `static func`**:

```
# src/gameplay/dna_crossover.gd
func crossover(parent_a_traits: Dictionary, parent_b_traits: Dictionary, child_seed: int) -> Dictionary
# src/world/animal_fitness.gd
func phenotype_for(seed_value: int) -> Dictionary
func fitness_score(phenotype: Dictionary) -> float
func mate_attractiveness(a_phenotype: Dictionary, b_phenotype: Dictionary) -> float
# src/gameplay/crop_breeding.gd
func cross_pollinate(parent_a_seed: int, parent_b_seed: int, child_roll: int) -> int
```

None of the three declares `class_name` either, so the bare identifiers
`DnaCrossover`, `AnimalFitness` and `CropBreeding` are **not globally
resolvable**. `DnaCrossover.crossover(a, b, seed)` therefore fails twice over:
the name is not in scope, and the function is not static.

**The decision: instantiate and hold. Do not do a `static` pass first.** Two
reasons, and the second is the load-bearing one.

- It is the house pattern, and the precedent is inside the very file this doc
  edits: `CreatureMarker` already carries
  `const DiseaseModel = preload("res://src/gameplay/disease_model.gd")` beside
  `var _disease_model := DiseaseModel.new()`, and calls
  `_disease_model.herd_transmission_chance(...)` on the instance while reading
  `DiseaseModel.State.INFECTED` off the class. `EarthChunkManager` does the same
  with `var _room_detector := RoomDetector.new()`. `DiseaseModel`,
  `RoomDetector`, `HoverTargetFinder`, `ProceduralAnimalSprite`,
  `WorldBossFitness` and `ConsoleCommandParser` are all instance-method modules
  held this way.
- A `static` pass would edit three files pillar 3 promises not to touch, and it
  would make eleven existing green tests call a static function through an
  instance (`crossover = DnaCrossover.new()` in
  `tests/unit/test_dna_crossover.gd`, `fitness = AnimalFitness.new()` in
  `tests/unit/test_animal_fitness.gd`), which GDScript permits but warns on.
  Changing three files and warning-flagging two test suites in order to save
  one `var` per call site is a bad trade.

So the real cost at each seam is **two lines, not zero**: a `const … = preload(…)`
header line, and a held instance field. Written out, §3's four-line child build
is actually:

```gdscript
# scenes/world.gd, beside its other preloads
const CropBreeding  = preload("res://src/gameplay/crop_breeding.gd")
const DnaCrossover  = preload("res://src/gameplay/dna_crossover.gd")
const AnimalGenome  = preload("res://src/gameplay/animal_genome.gd")
var _crop_breeding := CropBreeding.new()
var _dna_crossover := DnaCrossover.new()
…
var child_seed   := _crop_breeding.cross_pollinate(sire.wander_seed, dam.wander_seed, roll)
var child_genome := AnimalGenome.from_parents(sire, dam, child_seed, _dna_crossover)
```

**Note what that last line does *not* do.** It does not call
`_dna_crossover.crossover(...)` directly, even though the held instance is
right there. §3 makes `AnimalGenome.from_parents` the single entry point
precisely so the [0,1] clamp — which `DnaCrossover._nudge` does not apply — can
never be forgotten at one call site out of three. The crossover instance is
passed *in* rather than reached for, so the seam still owns its dependency and
the test can inject a stub. Any snippet anywhere in this doc that calls
`crossover` directly is a bug in the doc.

Every call example below is written in this form. Where a name *is* called at
class level in this doc — `Courtship`, `LifeCycle`, `AnimalReproduction`,
`Taming`, `KeptAnimals` — that is deliberate and verified: those **five**
modules really do declare `static func` throughout. `AnimalGenome` is new and
is specified static to match them, which is the sixth name and the reason the
list reads as six.

One thing static-ness does *not* buy: **none of those modules declares
`class_name` either.** Every one of them is reached today through a
`const X = preload("res://…")` at the top of the calling file (grep any caller
of `Taming` or `KeptAnimals` to see the pattern). Static resolves *how* the
function is called; the preload resolves whether the bare identifier exists in
scope at all. A seam needs both.

- ⬜ `test_every_reused_module_is_reachable_the_way_the_seam_calls_it` — for
  each of the three, instantiates it via its `res://` path and invokes the
  named method with dummy arguments. Measures: nothing numeric. It is the
  cheapest possible guard against this exact class of error recurring the next
  time a doc says "just call X".

### 1. The genome

```
src/gameplay/animal_genome.gd     ⬜ does not exist
```

A plain `String -> float` Dictionary with values in [0,1], because that is
exactly the shape `DnaCrossover.crossover` consumes and `NpcGenome` already
produces ("`traits` is a plain String -> float Dictionary specifically so it
slots directly into the existing dna_crossover.gd utility with no adaptation").
No new container class for the genes themselves; `AnimalGenome` is a namespace
of `static func`s over that Dictionary, in the style of `AnimalReproduction`
and `LifeCycle` — both verified static.

The [0,1] bound is a **contract this doc enforces, not one the crossover
provides.** `DnaCrossover._nudge` returns `value + direction * MUTATION_AMOUNT *
spread` with no clamp of any kind, so a parent pair of 0.0 and 1.0 has
`spread == 1.0` and can produce a child gene of up to 1.15 or as low as -0.15.
Because pillar 3 forbids editing that file, the clamp lives in this doc's
post-pass — see §3, where `AnimalGenome.from_parents` is the single function
that owns crossing, correlating, penalising and finally normalising.

Seven genes. Three of them — `strength`, `agility`, `coat_vibrancy` — are
`AnimalFitness.phenotype_for`'s existing keys, **unchanged and unrenamed**, so
`AnimalFitness.fitness_score` and `AnimalFitness.mate_attractiveness` operate on
an `AnimalGenome` with no modification at all: both read only those three keys
(`_average_trait_difference` hard-codes that key list), so the four extra genes
are invisible to them by construction. That is deliberate, and it is the
sexual-selection story: mate choice acts on *displayed* traits. The hidden four
are the breeder's edge over the wild population.

| gene | what reads it | what the player sees | why it is not dead weight |
|---|---|---|---|
| `strength` | `CreatureInfo`'s level/`max_health` derivation; `CreatureMarker.ATTACK_DAMAGE` (a flat `6.0` today) | the "Lv.4 / HP 31/31" line `CreaturePanel` **already draws** | picking a weak individual to lasso is already a [taming.md](taming.md) pillar; this is the number that tells you which one is weak |
| `agility` | movement speed; `Taming.MOUNTED_SPEED` (flat `150.0`) | gait cadence — `CreatureMarker.GAIT_STRIDE_PER_FRAME` paces the walk cycle off ground actually covered (`_gait_distance / GAIT_STRIDE_PER_FRAME`), so a fast animal *looks* fast for free | [pets.md](pets.md) promises "a high-fitness horse is faster or"…; today every horse rides at the same 150 |
| `coat_vibrancy` | `ProceduralAnimalSprite.generate_image`'s existing coat jitter (`JITTER_RANGE := 0.08`), **through `ProceduralAnimalAnimation.textures_for`'s look-variant bucket** — see §7, which is where this gets complicated | coat lightness, in `LOOK_VARIANTS` discrete steps | the shiny-hunt. [evolution.md](evolution.md)'s "ooh, a shiny boar", and the only trait readable with no UI whatsoever |
| `size` | multiplies the scale computed in **`CreatureMarker._apply_action_scale`** (both branches) and in `CreatureRenderer._build_marker` (both branches, for the spawn frame) | silhouette size, at a glance across a pasture | second free visual readout, and it *costs*: see the hunger multiplier below |
| `fertility` | `AnimalReproduction.cooldown_for` (§5) | the interval you are waiting on | the breeder's first target in any real program — fertility is what buys you generations to select in |
| `hardiness` | `DiseaseModel`'s **five** transmission-chance functions (`herd_transmission_chance`, `predator_bite_transmission_chance`, `carcass_contamination_chance`, `decomposer_carry_chance`, `carrion_graze_transmission_chance`) | the sick pip `CreatureMarker._sick_pip` **already draws** ([disease.md](disease.md)) | a herd that survives an outbreak; the actual reason real breeders select for resistance |
| `docility` | `Taming.trust_after_feeding` and `Taming.break_free_chance`, both of which gain a docility parameter; and the flee response (§10) | carrots-to-tame, and how close you can walk | the domestication gene (§10), and the one the player selects on by *playing the taming loop* rather than by reading a number |

Two notes on that table that a reader will otherwise get wrong.

**`hardiness` is a new key, not an inherited one.** `AnimalFitness.phenotype_for`
returns exactly `strength`, `agility`, `coat_vibrancy` and nothing else, and
[evolution.md](evolution.md)'s own list names the concept `disease_resistance`.
So of this doc's seven names: `agility` and `coat_vibrancy` are renames of
evolution.md's `speed` and `coat_saturation` **onto keys that already exist and
are already tested**; `hardiness` is a fresh coinage replacing
`disease_resistance` with no existing counterpart to match; `strength` is an
existing tested key that evolution.md's list never mentioned; and `size` and
`fertility` carry over unchanged. Only the first pair is "no adapter needed"
because the key was already there. The rest is ordinary naming, and
evolution.md gets corrected to match under CLAUDE.md's cross-alignment rule.

**`docility` cannot simply scale `TRUST_PER_FEED` or the break-free endpoints.**
Both are constants, and `taming.gd`'s own header is explicit that the endpoints
are chosen to produce a *compounded* outcome: "The quantity a player actually
experiences is `hold_chance()` below — the odds across the whole struggle — so
that is what is pinned by tests, and these two numbers are chosen to produce
it. Change them by checking what `hold_chance` does, never by eye." So docility
enters as a parameter on the two *functions*, and its effect is pinned against
`hold_chance` and against the existing
`test_it_takes_several_hungry_feeds_to_tame_an_animal`, never against the
constants.

`GENE_NAMES` is an ordered constant `Array[String]` — ordered because the V2
save format writes the floats positionally (§11).

**The anti-dead-weight guard.** `AnimalGenome` also declares
`GENE_READERS: Dictionary` mapping each gene name to the `res://` path of the
module that consumes it.

- ⬜ `test_every_gene_has_a_named_production_reader` — asserts `GENE_READERS`
  is total over `GENE_NAMES`. Measures: nothing numeric; it fails the moment
  someone adds an eighth gene with no consumer.
- ⬜ `test_every_named_reader_module_exists` — `ResourceLoader.exists()` over
  every path in `GENE_READERS`. Measures: that the registry names real files,
  so it cannot rot into a wishlist.

Seven is a judgement call and [evolution.md](evolution.md)'s open question
("How many phenotype dimensions (color, size, pattern, …) are worth
simulating") asks for one. The answer this doc gives: **as many as have
readers, and not one more** — the count is an output of the two tests above,
not a target.

**What the player does with the genome directly:** nothing. It is data. Every
section below is what they do *through* it.

### 2. Where it lives: `wander_seed`, and what happens to existing saves

The genome **wraps** `wander_seed`. It does not replace it and it does not sit
beside it as a second source of truth.

`wander_seed` stays exactly what it is: the individual's deterministic identity
key. Everything currently derived from it keeps deriving from it, untouched —
`CreatureNeeds`' per-individual hunger stagger, the three disease roll salts
(`"%d_%d_disease_progress"`, `"%d_%d_herd_disease"`, `"%d_%d_carrion_graze"`,
all salted with `_disease_roll_count`), the struggle rolls in `_step_restraint`,
the wander phase, and the animation look-variant bucket in
`ProceduralAnimalAnimation.textures_for`.

On top of that:

```
static func for_seed(seed_value: int) -> Dictionary
```

derives a full genome from a seed with the same salted-hash `_trait_fraction`
pattern `AnimalFitness._trait_fraction` and `NpcGenome._trait_fraction` already
use. **So every animal that has ever existed in this world already has a
genome, retroactively, with zero storage and zero migration.** A wild deer that
was spawned before this system landed gets exactly the genome it would have got
had the system always existed.

A *bred* animal is the exception, because a crossover result is not a function
of any one seed. So `CreatureMarker` gains one field and one accessor:

```gdscript
var genome: Dictionary = {}          # empty means "derive from wander_seed"

func genome_or_derived() -> Dictionary:
    return genome if not genome.is_empty() else AnimalGenome.for_seed(wander_seed)
```

Two constructors, one field, one branch. **Every consumer in this doc calls
`genome_or_derived()`, never `AnimalFitness.phenotype_for(seed)`** — that
function takes a `seed_value: int` and knows nothing about a stored genome, so
routing a bred animal through it would silently return the wrong traits. The
same rule binds [animal_husbandry.md](animal_husbandry.md): anywhere husbandry
wants "this candidate's phenotype", the call is `genome_or_derived()`.
`phenotype_for` remains the correct call for a *wild* individual and is what
`for_seed` is modelled on, but it is not the general accessor.

The child still needs a `wander_seed` of its own — for needs stagger, wander
phase, look variant and disease rolls, all of which must differ between
siblings. It gets one from `_crop_breeding.cross_pollinate(sire_seed, dam_seed,
child_roll)`, which is *precisely* this function (two parent seeds plus a roll →
one child seed), already written, already tested, and currently called by
nothing. Reuse it verbatim rather than writing a second integer mixer. It
returns `absi(hash(key))`, which fits an int32, so the save format can store
seeds with `store_32` (§11).

**`CreatureInfo` must stop rolling level from the raw seed.** Today
`creature_info.gd` computes `level = 1 + (absi(seed_value) % LEVEL_RANGE)`. If
that stays, a foal from two exceptional parents shows the level of a fresh
random roll and pillar 1 is dead on arrival. Change: `_init` takes an optional
`genome: Dictionary = {}` third parameter defaulting to `for_seed(seed_value)`,
and level comes from a tested function `level_for_strength(strength)` reusing
`LEVEL_RANGE` (5) and `LEVEL_HEALTH_SCALE` (0.25) unchanged.

- ⬜ `test_the_level_distribution_is_unchanged_from_the_seed_modulo_roll` —
  builds the level histogram over a large seed sample under both the old `%`
  roll and `level_for_strength(for_seed(s)["strength"])`, and asserts the two
  histograms agree within tolerance. Measures: the *distribution*, not the
  per-individual value. This is the guard that wild animals do not quietly get
  tougher or weaker the day this lands.
- ⬜ `test_a_child_of_two_strong_parents_reads_a_higher_level_than_average` —
  measures the mean level of N children of top-decile parents against the
  population mean.

**Migration, stated honestly.** Individual animals' levels *will* change on the
pass that lands this, because level now draws from a different hash channel.
That is acceptable, and here is why it is in fact an improvement:

- **Wild animals** are re-derived from chunk seeds on every load and persist no
  level at all. Nothing is lost.
- **Kept animals** already re-roll *completely* on every single chunk load
  today. `EarthChunkManager._restore_kept_animals` rebuilds the saved animal
  with `_creature_renderer.spawn_single(...)`, and `spawn_single` calls
  `randi()`. The horse you spent an evening taming is a statistically fresh
  animal with a trust number pasted on it every time the chunk reloads. §11 is
  what actually fixes that; the level change is a rounding error next to it.
- **Version 1 save records** carry no genome. §11 specifies deriving one
  deterministically from what a V1 record *does* hold, so a legacy animal
  stops re-rolling from the first load after the upgrade onward.

### 3. Inheritance: one crossover call, two seams

The change at the code seam is genuinely small. Two call sites.

**Seam A — `CreatureRenderer.spawn_single`.** Its own doc comment justifies
`randi()`: it is the on-demand `/spawn` path, and "a debug-spawned individual
isn't expected to look the same across sessions". That reasoning is correct and
must not be broken. **So do not change `spawn_single`.** Add a sibling:

```
func spawn_offspring(parent, species_name, position, wander_seed: int,
                     genome: Dictionary, world, tile_size) -> CreatureMarker
```

a thin wrapper over the existing private `_build_marker`, which *already* takes
an explicit `wander_seed` — it sets `marker.genome` and returns. `/spawn` keeps
its documented non-determinism; births get determinism.

`_restore_kept_animals` calls the same function, because a restored animal needs
exactly the same thing a newborn does: an explicit seed and an explicit genome.
The name is chosen for its primary caller and is a mild lie about the restore
path; the alternative is two near-identical entry points, which is worse.

- ⬜ `test_spawn_single_still_produces_unrelated_individuals` — the regression
  guard on `/spawn`'s documented behaviour. It exists precisely because the
  obvious "fix" is to make `spawn_single` deterministic, and that would break a
  documented contract.
- ⬜ `test_spawn_offspring_reproduces_the_same_animal_from_the_same_seed` —
  measures that two calls with one seed produce equal level, max_health and
  genome.

**Seam B — `World._step_reproduction`.** Today: any single creature passing
`can_reproduce()` spawns a same-species offspring beside itself via
`spawn_single`, calls `on_reproduced()`, and reports the birth to the aggregate
with `record_birth_at`. Asexual budding with a `randi()` child.

After: the same density gates stay exactly as they are — `MAX_LIVE_CREATURES`
60, `MAX_SAME_SPECIES_NEARBY` 4 within `NEIGHBOUR_RADIUS_PX` 160, and
`_chunk_manager.can_support_another_herbivore` — because those encode real
density dependence and were added in response to a real reported bug ("the
fruit caused dozens of deer to spawn???"). What changes is that a birth now
requires a *partner* (§4), and the child is built from both, through **one**
function that owns the whole pipeline:

```gdscript
static func from_parents(sire_genome: Dictionary, dam_genome: Dictionary,
                         child_seed: int, f: float, crossover) -> Dictionary
```

which internally: calls `crossover.crossover(sire_genome, dam_genome,
child_seed)`; applies `apply_domestication_correlation` (§10); applies
`apply_inbreeding_penalty(…, f)` (§9); and **finally clamps every gene to
[0,1]**. One entry point, so the clamp cannot be forgotten at one of three call
sites, and `DnaCrossover` is still not touched — which is what keeps pillar 3
literally true rather than approximately true. The crossover instance is passed
in rather than constructed here, so `AnimalGenome` stays a pure static
namespace with no held state.

`on_reproduced()` is then called on **both** parents, so both pay
`BIRTH_ENERGY_COST` (0.45) and both restart their interval.

The failing tests that drive this, red first:

- ⬜ `test_a_creature_with_no_partner_in_range_does_not_give_birth` — the red
  test that kills budding. It fails against today's code immediately.
- ⬜ `test_an_offspring_gene_lands_within_mutation_range_of_one_parent` — for
  every gene, `|child - sire| <= tol or |child - dam| <= tol` where
  `tol = max(MUTATION_AMOUNT * |sire - dam|, MUTATION_FLOOR)`. That is the
  tolerance the repo's own
  `test_each_child_trait_value_is_reasonably_close_to_one_parent` already
  asserts, taken verbatim rather than re-derived. It is a *bound*, not the
  code's exact deviation — when both parents hold the same value the real
  nudge is at most `MUTATION_AMOUNT * MUTATION_FLOOR` (0.0015) against a
  tolerance of `MUTATION_FLOOR` (0.01), so the bound is deliberately loose at
  that end. Matching the existing test's formula is the point: it makes
  "offspring inherit something" a documented invariant on the animal side under
  exactly the same statement it already has on the generic side.
- ⬜ `test_a_child_gene_never_leaves_the_unit_range` — the clamp test, driven
  by the real failure: sire 0.0, dam 1.0 produces up to 1.15 out of
  `crossover` alone. Red against `crossover`'s raw output, green against
  `from_parents`.
- ⬜ `test_siblings_from_one_pairing_differ_from_each_other` — different
  `child_roll`, different animal. Guards against a pen that produces clones.
- ⬜ `test_two_high_strength_parents_produce_a_stronger_than_average_child` —
  measures the mean `strength` of N children against the wild population mean.
  Pinned as that measured mean, not as a literal.

**What the player does:** they chose which two animals are standing next to
each other in the pen. That is the whole input, and it is the input that
matters.

**What happens in the meadow, said out loud.** `_step_reproduction` iterates
*every* `CreatureMarker` in the scene, not just penned ones, so seam B changes
wild births too. The honest statement of that: a wild birth now also requires a
partner within `NOTICE_RADIUS_PX` and also crosses two real genomes, which
makes wild births strictly *rarer* than today and gives the wild population the
genome §9's counter-play needs it to have. The player's input to a wild birth is
nothing, and that is fine — the wild population is pillar 1's *baseline to
beat*, and a baseline the player cannot touch is exactly what makes divergence
measurable. `test_a_wild_birth_appends_no_event` (§8) is the guard that this
extra fidelity does not leak into the event log.

### 4. From asexual budding to two parents

There is no partner concept in mammal reproduction today at all — `courtship.gd`
exists but `DANCING_SPECIES` gates it to `monarch`/`swallowtail`/`blue_morpho`/
`bee`.

**Do not widen `DANCING_SPECIES`.** Its own header explains why, and the reason
is good: the 9px spiral orbit is a butterfly's courtship flight, and a bird
doing it "reads as a bird glitching in place, which is exactly how it was
reported". A horse doing it would be worse. Mammals get their own approach and
reuse everything in `courtship.gd` that is not the dance geometry. All of these
are `static func`, so they are called at class level as written:

- `Courtship.can_court(a, b)` — same species, unchanged (drop the `dances()`
  clause into a separate `dances_or_pairs()` so the existing pollinator gate is
  untouched).
- `Courtship.can_pair(id_a, id_b)` — not itself.
- `Courtship.leads(own_id, partner_id)` — the id tie-break, so exactly one of
  the pair walks to the other with no message passing between markers.
- `Courtship.pair_seed(id_a, id_b, round_index)` — both sides compute the same
  outcome independently.
- `NOTICE_RADIUS_PX` 40 for "these two noticed each other". Deliberately short,
  for the reason `courtship.gd` already states: courtship should read as two
  animals that happened to meet, not a pairing arranged across the meadow — and
  for the player it means *a pen is the mechanism*: putting two animals in a
  small enclosure is how you make a meeting happen.
- `LifeCycle.can_court_at(age_seconds)` — only adults breed. This function is
  **already live** for ambient flyers; what it has never had is a mammal caller,
  because nothing persists a mammal's age. §11 fixes that.

**Replace the flat coin flip.** `Courtship.mates(pair_seed)` rolls against
`MATING_CHANCE := 0.25` with zero fitness weighting. One call site turns
courtship from decoration into selection:

```
static func mates(pair_seed: int, attractiveness: float = NEUTRAL_ATTRACTIVENESS) -> bool
```

where the chance is `lerpf(MIN_MATING_CHANCE, MAX_MATING_CHANCE, attractiveness)`
and `attractiveness` comes from an `AnimalFitness` instance —
`_animal_fitness.mate_attractiveness(a_genome, b_genome)` — the existing
symmetric scorer, unmodified and called on an instance per §0.

**`NEUTRAL_ATTRACTIVENESS` is solved, not chosen.** Its whole job is that the
four pollinator call sites, which pass no second argument, keep behaving
exactly as they do today. So it is derived, not written down:

```gdscript
const NEUTRAL_ATTRACTIVENESS := inverse_lerp(MIN_MATING_CHANCE, MAX_MATING_CHANCE, MATING_CHANCE)
```

— the attractiveness at which the new lerp reproduces the old constant by
construction. `MATING_CHANCE` stays in the file as the thing that definition
points at, rather than being deleted.

The two endpoint constants are likewise not eyeballed. They are solved by their
tests:

- ⬜ `test_an_unweighted_call_reproduces_the_old_flat_rate` — runs N pair seeds
  through `mates(seed)` with no second argument and **counts births**, asserting
  the count equals what today's `MATING_CHANCE` roll produces over the same N.
  Measures a birth count, so the existing pollinator tuning is provably
  unchanged — and it is the test that pins `NEUTRAL_ATTRACTIVENESS`.
- ⬜ `test_the_measured_mating_rate_over_a_random_population_matches_the_old_flat_rate` —
  the same measurement over N *random phenotype pairs*, so the endpoints are
  pinned to keep the population-level rate where it is even once weighting is
  live. This is the same discipline as
  `test_the_measured_catch_rate_matches_the_model` in
  `tests/unit/test_creature_marker.gd`, which pins the lasso catch rate by
  measuring sixty real captures rather than asserting a formula.
- ⬜ `test_a_top_decile_pairing_breeds_more_often_than_a_bottom_decile_one` —
  measures both counts. This is the assertion that selection now exists.

**The tension this creates for free.** `mate_attractiveness` is 60% combined
fitness and 40% *similarity* ("birds-of-a-feather"). So the simulation actively
pushes animals toward mating with animals like themselves — real assortative
mating — and §9 punishes exactly that. The pressure and its penalty were
already sitting in the codebase in two files that had never met.

**What the player does:** builds or fences a space so two chosen animals are
within 40px of each other; feeds both; and picks *which* two, knowing the pen
rewards similarity and the pedigree punishes relatedness.

### 5. Reachability: a birth a player can actually witness

This is the hardest requirement in the doc, and the current numbers make an
individual mammal birth effectively unobservable. Verified:

- `AnimalReproduction.REPRO_COOLDOWN := 24.0 * 60.0 * 60.0` — 24 real hours.
  Its comment records exactly why (it was 30 seconds and "a clearing filled
  with deer"), and that reasoning is sound for the *wild*.
- `CreatureMarker._seconds_since_birth` advances at
  `_seconds_since_birth += delta` inside `_process`, where `delta` is the
  LOD-stepped **real frame delta**. It is never persisted and dies with the
  marker on chunk unload.
- `/ecotest` **partially** touches this, contrary to a common reading:
  `_step_reproduction(delta)` is called from `World._step_ecology_batch`, which
  receives `simulated` — the sum of `TimeLapse.slices(delta, _ecology_time_scale)`.
  So the *poll* accelerates with `/ecotest`; the *clock it polls* does not. The
  gate is checked thousands of times a second and never opens. That is a worse
  failure than not accelerating at all, because it looks like it should work.

Three fixes, and only the third is a player mechanic.

**(a) Put the breeding clock on the simulated clock.** Move the advance out of
the marker's private `_process` and into the batched step that already polls
it: `World._step_reproduction` calls `creature.advance_breeding_clock(delta)`
for each marker before testing the gate, with the same `simulated` delta every
other ecology system gets. One field moves; nothing new is invented.

- ⬜ `test_the_breeding_clock_advances_with_the_ecology_time_scale` — measures
  simulated seconds accumulated under a scaled step versus an unscaled one.
- ⬜ `test_ecotest_produces_a_birth_within_a_measured_number_of_frames` — the
  test that says `/ecotest` is a real breeding-observation tool. Measures the
  frame count to first birth.

**(b) Persist the clock.** `seconds_since_birth` and `age_seconds` go into the
V2 kept-animal record (§11), so a pen the player walks away from does not reset
every animal's progress to zero. Wild animals do not need this — the aggregate
owns the wild population and always has ([ecosystem_dynamics.md](ecosystem_dynamics.md)'s
two-fidelity rule).

**(c) The interval becomes something the player shortens.** The flat constant
becomes a tested function:

```
static func cooldown_for(fertility: float, mean_parent_energy: float) -> float
```

- `REPRO_COOLDOWN`'s 24 hours stays as the **ceiling** — an unfed, low-fertility
  wild pair breeds exactly as slowly as it does today, so the "clearing filled
  with deer" regression cannot return.
- A well-fed pair (energy near `MAX_ENERGY`, which the player achieves by
  feeding them — a verb that already exists, on animals they already own, with
  carrots that already have a source in [wild_crops.md](wild_crops.md)) with
  bred-up `fertility` reaches the **floor**.
- This is nutritional flushing, and it is why the floor is a husbandry reward
  rather than a global timescale cut.

**The floor is measured against a real clock, not against a guessed session
length.** Because (a) puts the breeding clock on the *simulated* clock,
"observable" is a statement about simulated time, and this world already has a
unit for that:

```gdscript
const OBSERVABLE_SECONDS := SeasonCycle.SECONDS_PER_DAY   # one in-game day
```

`SeasonCycle.SECONDS_PER_DAY` is `4.0 * 60.0 * 60.0` and is already
load-bearing for the entire calendar. One in-game day is a span the player can
*see* pass — the sun goes round once — and it is what "you set this pair up
this morning and there is a lamb by evening" means literally rather than
figuratively. Under `/ecotest` at its default `TimeLapse.DEFAULT_SECONDS_PER_YEAR`
(45 s/year over `SeasonCycle.DAYS_PER_YEAR` 48) one in-game day is under a
second of wall clock, which is why the frame-count test above is the wall-clock
half of the same claim. Naming the constant `SESSION_SECONDS` would have been a
lie: a session is nowhere near four hours.

- ⬜ `test_a_well_fed_high_fertility_pair_reaches_the_gate_within_one_in_game_day` —
  drives a simulated pair through `decay`/`feed`/`cooldown_for` and measures
  the simulated seconds until `can_reproduce()` returns true, asserting it is
  under `OBSERVABLE_SECONDS`. The floor is *that measured duration*.
- ⬜ `test_a_neglected_pair_still_takes_about_a_real_day` — measures the same
  duration at low fertility and decayed energy, asserting it is still on the
  order of `REPRO_COOLDOWN`. The anti-explosion guard.
- ⬜ `test_feeding_a_pair_measurably_shortens_their_interval` — the assertion
  that the player's input does something. Measures the difference in seconds
  between a fed and an unfed pair.

**What the player does:** feeds the pair. The world shortens the wait, visibly,
and the readout in §6 shows the remaining interval so the feeding has feedback
instead of being an act of faith.

### 6. Selection the player drives

Three problems. This doc owns two of them.

**Choosing — owned by [animal_husbandry.md](animal_husbandry.md).** Every animal
verb in the game resolves to *nearest* (`Player._throw_lasso`, `_nearest_tamed`,
`_try_mount`), so you cannot pick between two horses standing side by side,
which makes every multi-animal mechanic in this doc unreachable. The mechanism
is a persistent, click-latched `Player.selected_animal`, drawn with a selection
ring, cleared when the animal dies or leaves range, with hover as the fallback
when nothing is selected — and it is specified in full in
[animal_husbandry.md](animal_husbandry.md)'s "Choosing an animal" section, with
one test name, `test_a_verb_prefers_the_selected_animal_over_a_nearer_one`. This
doc does not restate it and does not name a second test for it. What this doc
needs from it is only the guarantee that `/breed` and the pairing readout can
name *two specific animals*.

**The hover half, which this doc does need.** `CreatureMarker` is already in
`HoverTargetFinder.GROUP_NAME` and already answers `get_display_name()`, but it
does not implement `get_hover_actions()`, which `World._update_hover_tooltip`
calls behind a `has_method` guard. Fifteen scripts join that group; eleven
implement `get_hover_actions()` (`carcass.gd`, `carcass_guts.gd`,
`choppable_tree.gd`, `collapsed_passage.gd`, `diggable_rock.gd`,
`dropped_item.gd`, `liftable_stone.gd`, `lumberjack_marker.gd`,
`minable_ore.gd`, `smashable_stone.gd`, `wild_crop_marker.gd`). **Four do not:
`creature_marker.gd`, `fish_marker.gd`, `piscivore_bird_marker.gd` and
`ambient_flyer_marker.gd`** — so the accurate claim is not "the one hoverable
entity without a verb" but "the only *tameable* one", and the other three are
animals the player also has no verb for, which is the same complaint wearing
three more coats. Implementing it on `CreatureMarker` costs ~10 lines,
self-wires through the existing `has_method` guard, and gives the tooltip a
live keybinding glyph for free.

- ⬜ `test_a_creature_offers_a_pair_action_when_a_partner_is_selected` —
  measures the returned action list, not a rendering.

**Seeing.** `CreaturePanel` already draws a name/level/HP card and the play
session found its real failure: five nearby animals produce an anonymous stack
of near-identical "Sheep Lv.4 / HP 31/31" cards. Add the three *displayed*
genes as bars, built from the same `ColorRect` shape `CreatureMarker._trust_bar`
already uses so no new UI primitive is introduced. The four hidden genes are
**not** shown on the world card — they are shown in the pairing readout, because
discovering what a line is actually carrying is part of the mechanic.

**Predicting.** The readout that makes this a strategy:

```
static func predicted_child(sire_genome, dam_genome, samples: int, crossover) -> Dictionary
```

returning, per gene, `{low, likely, high}` — computed by running **the same
`crossover` instance the birth will use** over a spread of child seeds and
reducing, through the same `from_parents` pipeline so the clamp and both
post-passes are included. The preview is therefore the same code path that will
produce the child, so it is honest by construction and cannot drift from the
outcome. It costs one crossover per sample, which is a handful of hashes.

- ⬜ `test_the_predicted_range_contains_every_child_the_crossover_produces` —
  samples N real child seeds and asserts every gene value falls inside the
  predicted `[low, high]`. Measures containment over N samples; the sample
  count is pinned as the smallest N at which containment holds across a
  parent-pair sweep, not chosen by eye.
- ⬜ `test_the_prediction_widens_as_the_parents_diverge` — measures the
  predicted range width for a similar pair against a divergent one. This is
  what teaches the player that a wide outcross is a gamble and a tight pairing
  is a safe, small step.

Two places show it, and only one of them belongs to this doc:

- **`/breed <a> <b>`** — a dev-console command printing the predicted table
  plus both parents' kinship and the resulting `f`. Cheap (one arm in
  `World._on_console_command`'s `match` and one handler), testable, and it
  dodges the window plumbing tax entirely. It is also the only way to iterate
  on any of this at a tolerable speed: the current route to two tamed animals is
  two real 72px lasso throws — and `test_the_measured_catch_rate_matches_the_model`
  pins the hold rate for a healthy horse between 0.2 and 0.55 over sixty
  measured captures — plus five hunger-gated feeds each, on top of an approach
  [animal_husbandry.md](animal_husbandry.md) shows can fail outright. Note
  `ConsoleCommandParser.parse` splits on whitespace with no quoting, so
  arguments cannot contain spaces.
- **The pen's pairing window** — owned by
  [animal_husbandry.md](animal_husbandry.md), not by this doc.

### 7. Making traits visible

Selective breeding has to be legible without a stat sheet, or the player is
back to reading numbers about a simulation instead of looking at it.

**Coat, and the cache that stands in the way.** `ProceduralAnimalSprite.generate_image`
already computes `jitter := PixelNoise.unit(seed_value, key.length(), 0) - 0.5`
and lightens/darkens the species base colour by `JITTER_RANGE := 0.08`.
Replacing that independent noise draw with the genome's `coat_vibrancy` is a
one-line change to a signature — but it is **not** sufficient, and this is the
part an implementer will otherwise discover the hard way.

`CreatureMarker._animation_step` does not call `generate_texture` per
individual. It calls `ProceduralAnimalAnimation.textures_for(species, action,
wander_seed)`, which quantises the seed to `absi(seed_value) % LOOK_VARIANTS`
and caches the frame set on `(species, action, variant)` in a **static** cache
shared by every marker. `LOOK_VARIANTS` is 8, and its own doc comment records
why in measured terms: "drawing a frame set costs ~47ms… a herd of 25 crossing
into 'eat' together spent 1.18 SECONDS generating inside one 5-second window —
the 130-145ms frame spikes reported as lag."

So today, on procedurally-drawn species, an individual's coat is **already**
one of eight looks, not a per-individual value. `_build_marker`'s initial
`generate_texture(species_name, wander_seed)` is the only per-seed draw in the
system, and it is replaced from the very next `_animation_step`.

The consequence for this gene: `coat_vibrancy` **quantises into the existing
`LOOK_VARIANTS` buckets and the cache key gains that bucket**, rather than going
continuous and per-individual. A continuous coat would mean one frame set per
animal per action, which is precisely the 1.18-second stall `LOOK_VARIANTS` was
introduced to stop. Eight steps is what the renderer can afford, and eight steps
is enough for the shiny-hunt: the existing
`test_a_species_still_shows_more_than_one_look` already pins that eight buckets
read as more than one animal.

- ⬜ `test_the_brightest_and_dullest_coat_are_distinguishable` — measures the
  mean per-channel delta between a bucket-0 and a bucket-7 image of one
  species and asserts it exceeds one step of the shared `PixelRamp`. The
  jitter range is pinned as *the value at which that measured delta clears one
  ramp step*, not as `0.08`.
- ⬜ `test_two_animals_in_the_same_vibrancy_bucket_share_one_frame_set` — the
  performance guard, asserted against the cache rather than against a
  stopwatch. This is the test that stops someone "improving" the coat to
  continuous and reintroducing a measured stall.
- ⬜ `test_a_bred_coat_never_leaves_its_species_colour_family` — measures hue
  distance from `SPECIES_BASE_COLORS[species]`, so breeding cannot produce a
  green sheep.

**Size, at the correct seam.** The obvious edit site is wrong.
`CreatureRenderer._build_marker` does set
`marker.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE * species_scale` — but
`CreatureMarker._apply_action_scale` recomputes and **assigns** `scale` from
scratch on every action change, in *both* branches, and syncs
`_shadow_base_scale` from the same value. A factor applied only at
`_build_marker` is wiped by the first walk→idle transition.

The `size` gene therefore multiplies into **four places, which are two formulas
written twice**:

```gdscript
# CreatureMarker._apply_action_scale
new_scale = Vector2.ONE * _illustrated.marker_scale(info.species, action) * size_factor
new_scale = Vector2.ONE * ArtResolution.SPRITE_SCALE * species_scale * size_factor
# CreatureRenderer._build_marker — the same two, for the spawn frame, so the
# on-screen size does not jump when _apply_action_scale first supersedes it
```

Two constraints on that. The factor must **not** go inside
`IllustratedAnimalSprite.marker_scale`, which memoises per `(species, action)`
in a static cache shared by every animal of that species — folding a
per-individual value in would poison it for the whole herd. And
`_shadow_base_scale` needs nothing extra: `_apply_action_scale` assigns it from
`new_scale`, and `_build_marker` passes `marker.scale` into `set_shadow`, so the
silhouette follows for free in both paths.

`LifeCycle.size_scale_at` does **not** establish a precedent at this seam. It is
live, but only in `AmbientFlyerMarker`, which multiplies it into its own
`_adult_scale`; `CreatureMarker` never calls `LifeCycle` at all. So `size` and
juvenile growth do not compose today — they will compose only once §11 gives
`CreatureMarker` a persisted `age_seconds` and the same multiply is added, and
that is a second piece of work, not a free one.

The spread must not be free-form, and the obvious test for it is unwritable as
first stated. **Several species share an identical `world_scale` in
`AnimalAnatomy`** — `venomous_snake` and `nonvenomous_snake` are both 0.7,
`sheep` and `lynx` are both 0.8, `herbivore`/`wolf`/`predator` are all 1.0,
`horse` and `tapir` are both 1.2, `reindeer` and `boar` are both 1.25, `camel`
and `bear` are both 1.5 — so "the smallest gap between any two species" is
**0.0**, and "strictly smaller than 0.0" cannot be satisfied by any spread.

- ⬜ `test_no_individual_reads_as_a_different_species_by_size` — computes the
  smallest **non-zero** gap over a named `BREEDABLE_SPECIES` roster (the
  species a player can actually keep: not world bosses, not the
  `herbivore`/`predator` stand-ins, not predators, which `Taming.can_be_tamed`
  refuses) **from `AnimalAnatomy`'s own table**, and asserts the full
  per-individual spread — the scale at gene 1.0 minus the scale at gene 0.0 —
  is strictly smaller. On today's roster that gap is the sheep-0.8/goat-0.85
  pair's 0.05, but the test reads the table rather than the number, so adding a
  species tightens the bound automatically. Pinned as a relative property
  against the real roster, the same discipline
  `test_kraken_exceeds_the_previous_toughest_species_by_a_clear_margin`
  already uses in `tests/unit/test_creature_info.gd`.
- ⬜ `test_the_size_gene_survives_an_action_change` — spawns a marker, records
  its scale, drives it through a walk→idle→swim sequence and asserts the ratio
  to the species base scale is unchanged. This is the direct regression test on
  the `_build_marker`-only mistake, and it fails against any implementation
  that edits only the spawn path.

**Marking.** `_paint_body_spots` already exists (`SPOT_COUNT := 6`,
`SPOTTED_SPECIES` = jaguar rosettes and venomous-snake bands), reading the
assembled image rather than a source bitmap. A `marking` axis derived from
`coat_vibrancy` and `docility` (§10's piebalding) reuses it directly — this is
listed as a follow-up, not an eighth gene, because pillar 2 forbids adding a
gene before it has a reader. It rides the same look-variant bucket as the coat
and so costs no extra cache entries.

**The honest gap, and it is a big one.** `CreatureRenderer._build_marker`
branches: if `_illustrated.has_species(species_name)` the marker takes
illustrated textures and **never calls `ProceduralAnimalSprite` at all**.
`IllustratedAnimalSprite._SHEETS` covers `horse`, `deer`, `boar`, `wolf`,
`sheep` (plus four world bosses). Those are precisely the species a player most
wants to breed — and `wolf` is a predator, which `Taming.can_be_tamed` refuses
outright, leaving horse/deer/boar/sheep. So **the coat gene is invisible on
every tameable species that has real art**, and only procedurally-drawn species
(goat, camel, reindeer, tapir, mouse…) would show it. Marked ⬜ below. Closing
it means either a per-individual `modulate`/tint pass over the illustrated
texture or a palette-swap pass in the same place the sheep/wolf sheets already
get their `"magenta_keyed"` chroma-key treatment.

The `size` gene **is** unaffected by that split — but not because `scale` is
left alone. It is unaffected because the factor is applied in
`_apply_action_scale`, which both branches pass through on their way to
assigning `scale`. Put it anywhere else and the illustrated species lose it.

### 8. Lineage and pedigree

**What is stored on the animal.** Three fields beyond the genome:

- `sire: int`, `dam: int` — the two parents' `wander_seed`s. 8 bytes.
- `ancestors: PackedInt32Array` — the parents' own ancestor sets, truncated at
  `ANCESTRY_DEPTH` generations. At depth 3 that is 2 + 4 + 8 = 14 ints = 56
  bytes of payload per animal (60 on disk with its length prefix). Seeds fit an
  int32: `CropBreeding.cross_pollinate` returns `absi(hash(key))`, and
  `randi()`'s 32 bits round-trip exactly through `store_32`/`get_32`.
- `inbreeding_coefficient: float` — computed once at birth, never recomputed.

`kept_animals.gd`'s own header already bounds the population this has to
scale to: "Deliberately bounded by how many animals a player can actually tame
and tie up, which is a handful — not by anything that scales with world size."
56 bytes × a handful, per chunk, is not a cost worth optimising — but it is a
cost worth *measuring*, because it is what pins `ANCESTRY_DEPTH` (§11).

**Kinship** is a tested function whose spec is the real textbook values, not
invented ones:

```
static func kinship(a_ancestry: PackedInt32Array, b_ancestry: PackedInt32Array) -> float
```

- ⬜ `test_full_siblings_score_one_half`
- ⬜ `test_half_siblings_score_one_quarter`
- ⬜ `test_parent_and_offspring_score_one_half`
- ⬜ `test_first_cousins_score_one_eighth`
- ⬜ `test_unrelated_founders_score_zero`
- ⬜ `test_a_relationship_deeper_than_the_stored_depth_scores_zero` — the
  honest one. This is a truncation of Wright's coefficient at
  `ANCESTRY_DEPTH`, and the test says so out loud rather than pretending the
  function is exact.

`ANCESTRY_DEPTH` is pinned by which relationships must resolve (first cousins
need three generations) and by the measured per-record byte cost in the V2
round-trip test — not chosen as a round number.

**Depth beyond that lives in the event log, not on the animal.** The emergence
substrate (`src/emergence/`) is event-sourced and persisted
(`event_store.gd`/`event_store_persistence.gd`), and `EntityRef.for_kind`
already mints `"<kind>:<key>"` ids from an entity's existing deterministic key —
for a creature, its `wander_seed`. A birth appends one `Event` with
`actors = [child_ref, sire_ref, dam_ref]`, and `EventStore.link_cause` wires the
child's birth to the parents' own. Arbitrary pedigree depth is then a walk over
`causes`, at zero per-animal storage cost. (`EventStore` is another
instance-method module — `append` and `link_cause` are plain `func` — so §0's
rule applies at this seam too.)

This also gets close to closing a documented gap in the substrate, but not as
cleanly as it first appears. `field_journal.gd` does route the `"creature"`
entity kind, and its own header does record that "No real `src/` call site
produces `creature:` ids yet" — births would be the first. **But the route goes
to `Why.explain_world_boss`**, matching `WorldBossStore.bosses_for`'s
`individual_id`, not to a generic event walk. So `/journal creature:<seed>` on a
bred lamb today would print a world-boss explanation about an animal that is not
one. Reading a pedigree needs either the generic `Why.explain_entity` fallback
(which is real, safe and already the default for unrecognised kinds) or a
composed `creature:` route that tries the boss store and falls through to the
event store. Naming that as a *small extra piece of work* is the honest version;
"the command exists and routes this kind already" is not. `/journal` also
requires a `field_journal` item in the player's inventory.

**But not every birth.** `event.gd`'s header is explicit: "Do not event-source
every low-level movement — event-source meaningful changes only." Wild
populations breed constantly and the log is append-only and persisted, so the
rule is: **a birth is event-sourced when the player had a hand in it** — a pen
birth, or a birth from a pair the player fed. A deer born in a meadow two
chunks over is a number in `EcosystemSimulation`, which is what
[ecosystem_dynamics.md](ecosystem_dynamics.md) says it should be.

- ⬜ `test_a_wild_birth_appends_no_event`
- ⬜ `test_a_kept_birth_appends_exactly_one_event_naming_all_three_animals`
- ⬜ `test_a_pedigree_walk_recovers_a_grandparent_the_animal_does_not_store` —
  the test that justifies splitting storage between the record and the log.
- ⬜ `test_a_creature_id_reads_back_a_pedigree_not_a_boss_explanation` — the
  red test against `FieldJournal.entry_for`'s current `"creature"` route.

**What the player does:** `/journal creature:<seed>` (once the route above is
sorted) or the pen's lineage list reads back the line they built. And crucially,
kinship is shown *before* the pairing, in §6's readout — so relatedness is a
decision input, not a post-mortem.

### 9. Inbreeding and diversity pressure

Without this, breeding is a monotone stat climb and pillar 6 fails.

```
static func apply_inbreeding_penalty(child_genome: Dictionary, f: float) -> Dictionary
```

where `f = 0.5 * kinship(sire.ancestors, dam.ancestors)` and the penalty scales
down **`fertility` and `hardiness` only**. `strength`, `agility`, `size`,
`coat_vibrancy` and `docility` are untouched. That asymmetry is the real
finding, not a balance choice: inbreeding depression hits fitness traits —
reproduction and survival — far harder than it hits conformation or colour,
which is exactly why real closed herds lose their *performance* while still
looking like a good herd. Mechanically it is also the more interesting failure:
the line stops working before it stops looking impressive, so the player is
punished in the currency (generations) they were spending, not by having their
prize animal turn ugly.

- ⬜ `test_a_full_sibling_pairing_produces_a_less_fertile_child_than_an_outcross` —
  a paired comparison, no literal on either side.
- ⬜ `test_inbreeding_does_not_touch_the_visible_conformation_genes` — pins the
  asymmetry so nobody "simplifies" it into a flat penalty later.
- ⬜ `test_repeated_sibling_pairings_collapse_a_line_within_a_measured_number_of_generations` —
  runs generations of sib-mating and measures at which generation mean
  fertility drops below the wild mean. The penalty coefficient is pinned as
  *the value at which that measured generation count* is small enough to be
  felt inside a play span and large enough that one convenient pairing is not
  punished.
- ⬜ `test_an_outcross_to_an_unrelated_animal_restores_fertility_in_one_generation` —
  the counter-play must actually work, or this is just a decay timer.

**The counter-play is the whole point, and it has a dependency this doc must
name.** Fixing a degrading line means bringing in unrelated blood, which means
going out and taming a wild animal — back through the lasso loop that already
exists. That loop is the strongest player-driven mechanic in the game, and it
is also, right now, the one that can silently refuse to start:
[animal_husbandry.md](animal_husbandry.md)'s approach section shows that
`Player.BASE_SPEED` (80) is multiplied by the product of water, weather,
terrain and condition penalties before the player moves, and that
`CreatureMarker.FLEE_SPEED` is a flat 40 — so below a composed multiplier of
0.5 the player is slower than the animal they are chasing and the outcross is
not merely hard, it is unavailable, with nothing on screen saying why. Bait,
crouch and patience are husbandry's answer to that, and this doc's entire
counter-play rests on them landing. Until they do, `/breed` and a wild-caught
founder pair are the only reliable route to fresh blood, which is another
reason the console command in §6 is scoped as a real deliverable rather than a
convenience.

And when it does work, it is [evolution.md](evolution.md)'s own pillar
happening literally: removing high-scoring individuals from the wild breeding
population shifts which phenotypes propagate there.

**A named limit.** Wild `f` is only tracked for individuals the player is
actually breeding. Away from the player a population is a float per chunk in
`EcosystemSimulation`, and a float has no genome by construction. So a wild
valley cannot accumulate real inbreeding, and `EcosystemSimulation`'s
inter-chunk migration cannot relieve pressure that is not modelled. ⬜, stated
rather than papered over.

### 10. Domestication drift

Kept populations must diverge from wild ones over generations, and — this is
the design bar — it must happen *because of a choice the player made*, not
automatically.

It does, and the mechanism is already in the player's hands:

**The selection pressure is the taming loop itself.** `docility` scales
`Taming.trust_after_feeding` (whose `TRUST_PER_FEED` 0.2 means roughly five
feeds to `TAME_TRUST`) and lowers `Taming.break_free_chance` (0.05..0.22 by
condition). So the animals the player successfully catches and tames are, on
average, the more docile ones — and those are the only animals that ever breed
in a pen. The kept gene pool's mean docility rises every generation as a side
effect of the loop the player is already playing, exactly as Belyaev's foxes
did. The player chose which animals to catch; the divergence is the consequence.

**The correlated response is modelled, not bonused.**

```
static func apply_domestication_correlation(child, sire, dam) -> Dictionary
```

nudges `coat_vibrancy` (toward piebald/depigmented) and `fertility` in
proportion to the child's docility gain over its parents — the neural-crest
package. Applied as a post-pass inside `from_parents`, so the crossover stays
verbatim (pillar 3) and the clamp still runs after it.

- ⬜ `test_selecting_only_for_docility_raises_coat_vibrancy_and_fertility` —
  runs N generations selecting purely on docility and measures the drift in the
  other two. **The correlation strength is pinned by direction and ordering
  only**: that both drift *upward*, and that the drift in the directly selected
  gene exceeds the drift in the two correlated ones. No numeric magnitude is
  claimed. Belyaev's result is a qualitative package, not a published effect
  size this project can assert against, and pretending otherwise would put an
  unpinnable number in a test.
- ⬜ `test_a_wild_population_shows_no_such_drift_over_the_same_generations` —
  the control arm. Without it the test proves nothing about *divergence*.

**And it costs something.** Docility scales down the flee response
(`CreatureBehavior`'s threat handling, which today reads `SENSE_RADIUS` 80 and
releases at `FLEE_RELEASE_RADIUS` 120), so a domesticated animal notices a
predator later. That is true of real domestic animals and it makes the pen a
commitment rather than a free upgrade: the herd you bred needs you now. The
composed flight radius itself is [animal_husbandry.md](animal_husbandry.md)'s —
`FlightDistance.radius(species, wariness, trust, crouched)` — and this doc adds
no second one; `docility` reaches it as a species-level shift in the base term,
and husbandry's `test_a_graded_flight_radius_never_dithers` remains the single
owner of the Schmitt-gap invariant.

- ⬜ `test_a_domesticated_animal_flees_later_than_a_wild_one` — measures the
  distance at which each breaks into flee, through husbandry's composed radius
  rather than a private one.

**What the player sees.** `/breed` and the pen readout print the kept-herd mean
and the wild mean side by side, per gene. After enough generations that is two
visibly different animals: brighter and patchier, breeds sooner, tames in fewer
carrots, and dies to a lynx that a wild deer would have outrun.

### 11. Persistence: the complete `KeptAnimals` FORMAT_VERSION 2 record

**This doc owns the V2 record.** [animal_husbandry.md](animal_husbandry.md) and
[taming.md](taming.md) each list only the fields they read and defer the rest
here; there is exactly one binary layout and it is defined below, in write
order. `src/world/kept_animals.gd` is `FORMAT_VERSION := 1` today, its record
holds exactly `{species, position, trust, order, is_tied, tied_to}` written as
positional `store_*` calls, its header says the format is deliberately versioned
so an old save is ignored rather than read as garbage, and
`tests/unit/test_kept_animals.gd` already round-trips it.

**The V2 record, in write order.**

| # | field | encoding | bytes | owner / why |
|---|---|---|---|---|
| 1 | `species` | `store_pascal_string` | 4 + len | V1 |
| 2 | `position` | 2 × `store_float` | 8 | V1 |
| 3 | `trust` | `store_float` | 4 | V1 — [taming.md](taming.md) |
| 4 | `order` | `store_32` | 4 | V1 — `Taming.ORDER_*` |
| 5 | `is_tied` | `store_8` | 1 | V1 |
| 6 | `tied_to` | 2 × `store_float` | 8 | V1 |
| 7 | `wander_seed` | `store_32` | 4 | **the single most important addition.** Without it, `_restore_kept_animals` re-rolls the animal through `spawn_single` → `randi()` on every chunk load, so its level, max_health, needs stagger, look variant and coat all change. The tamed horse is a different animal each time you come back. |
| 8 | `genome` | `store_32` gene count, then that many `store_float` in `GENE_NAMES` order | 4 + 4n (32 at n=7) | §1. Count first so a future gene addition is *detectable* rather than silently misaligned |
| 9 | `sire`, `dam` | 2 × `store_32` | 8 | §8 |
| 10 | `ancestors` | `store_32` count, then that many `store_32` | 4 + 4m (60 at depth 3) | §8, truncated at `ANCESTRY_DEPTH` |
| 11 | `inbreeding_coefficient` | `store_float` | 4 | §8, computed once at birth |
| 12 | `seconds_since_birth` | `store_float` | 4 | §5(b) — the breeding clock survives unload |
| 13 | `age_seconds` | `store_float` | 4 | gives `LifeCycle.size_scale_at`/`can_court_at` a mammal input for the first time (they are already live for ambient flyers), and gives `LifeCycle.stage_at` — the one function in that file with no caller at all — its first. It is also what `WorldBossFitness.fitness_score(level, kills, age_seconds)` needs: nothing tracks a creature's age across sessions today, which is a named reason no world boss can ever emerge. |
| 14 | `energy` | `store_float` | 4 | `CreatureMarker.energy`, the bioenergetic condition `AnimalReproduction` gates on. **Not** `AnimalReproduction.energy` — that module is a static namespace of pure functions and holds no fields. |
| 15 | `hunger`, `thirst` | 2 × `store_float` | 8 | `CreatureNeeds` — [animal_husbandry.md](animal_husbandry.md)'s trough reads these |
| 16 | disease block: `disease_state`, `disease_id`, `disease_severity`, `_disease_state_seconds`, `_disease_roll_count` | `store_32`, `store_pascal_string`, 2 × `store_float`, `store_32` | 28 (worst case) | [disease.md](disease.md). The roll count matters: it is the salt counter, so dropping it would make a reloaded animal re-draw rolls it already made |
| 17 | `pen_id` | `store_32` | 4 | [animal_husbandry.md](animal_husbandry.md) — which enclosure this animal belongs to, 0 for none |
| 18 | `given_name` | `store_pascal_string`, capped at `MAX_NAME_BYTES` | 4 + ≤24 | [animal_husbandry.md](animal_husbandry.md)'s roster. The cap exists so the record has a bound at all |
| 19 | `discovered_foods` | `store_32` registry size, then `store_32` bitmask | 8 | [animal_husbandry.md](animal_husbandry.md)'s bait — which food preferences this player has *found out about* for this animal. Size-then-mask so a grown food registry is detectable the same way a grown `GENE_NAMES` is |
| 20 | `kept_since` | `store_double` | 8 | [animal_husbandry.md](animal_husbandry.md) / [taming.md](taming.md) — world seconds at first capture. `double`, not `float`, because world elapsed seconds outruns float32 precision in a long save |
| 21 | `escape_count`, `last_escape_at` | `store_32`, `store_double` | 12 | [taming.md](taming.md)'s escape memory ("harder to re-catch after it got away"), which is unimplemented today and has nowhere to live without this |

**The byte budget, and what it pins.** At `ANCESTRY_DEPTH` 3, seven genes, a
5-character species and worst-case strings, one record is **about 250 bytes** —
V1's ~34 plus ~216 of additions, of which the ancestor array is 60. Depth 4
would take the ancestor array to 124 and the record past 310.

The budget is not a chosen number. A chunk's kept-animal file is one small
sequential write, and the thing worth staying inside is a single 4 KiB disk
block at the largest roster the pen system can legally produce — which
[animal_husbandry.md](animal_husbandry.md) derives from real `TallGrass`
regrowth in `PenCapacity.max_stock`, not from a round number.

- ⬜ `test_the_v2_record_size_stays_within_the_measured_budget` — writes
  `PenCapacity.max_stock` full V2 records with worst-case strings and a
  fully-populated ancestor array, measures the file's real byte length, and
  asserts it fits one 4 KiB block. `ANCESTRY_DEPTH` is *the largest depth for
  which that holds*, subject to the functional floor of 3 (first cousins must
  resolve, §8). Both ends of that are derived; neither is typed in.

**V1 upgrade path.** `load_all` currently returns `[]` on a version mismatch,
which for V1→V2 would delete every animal the player has tamed. Instead, read
V1 records and derive the missing fields deterministically from what a V1
record *does* hold: `hash("%f_%f_%s_legacy" % [position.x, position.y, species])`.
That is not the animal's original genome — there wasn't one — but it is **stable
from that load onward**, which is strictly better than today's per-load
`randi()`.

- ⬜ `test_a_version_1_record_still_loads` — the red test against today's
  discard-on-mismatch behaviour.
- ⬜ `test_the_same_version_1_record_loads_the_same_genome_twice` — the whole
  point of the legacy derivation.
- ⬜ `test_a_bred_animal_round_trips_its_genome_and_pedigree` — the V2 twin of
  the existing `test_a_kept_animal_survives_being_written_and_read`.
- ⬜ `test_a_restored_animal_keeps_its_level_and_max_health` — the direct
  regression test on the `randi()` re-roll.
- ⬜ `test_an_unknown_future_version_is_still_discarded` — the guard that the
  upgrade path did not turn `FORMAT_VERSION` into a suggestion.

**A dependency this doc does not own, stated correctly.** `KEPT_ANIMALS_DIR` is
absent from `World.backed_up_directories()`, so New Game neither backs up nor
wipes tamed animals and a previous world's horses respawn in the new one. The
fix is **two edits, not one**: `World._wipe_persisted_world` makes exactly four
`wipe_directory` calls matching the four backup entries, and
`test_the_backup_lists_cover_exactly_what_the_wipe_destroys` asserts those two
counts are equal by parsing the wipe's own source — so adding
`KEPT_ANIMALS_DIR` to the backup list *alone* turns that green test red. Red
first here means a **new** test ("a kept animal from a previous world does not
survive New Game"), then adding the directory to both the backup list and the
wipe. That work belongs to [taming.md](taming.md) /
[animal_husbandry.md](animal_husbandry.md), but a bred line is a far bigger
thing to lose than a trust number, so it is worth fixing in the same pass.

## What the player can see

Following [taming.md](taming.md)'s own section of the same name, and
[flora.md](flora.md)'s rule that what is visible must be what is real:

- **The coat**, carrying `coat_vibrancy` in `LOOK_VARIANTS` discrete steps — on
  procedurally-drawn species only, today. ⬜ for illustrated species (§7).
- **The silhouette size**, carrying `size`, on every species, both art paths.
- **The level and HP line** `CreaturePanel` already draws, now carrying
  `strength` instead of a raw seed roll.
- **Three gene bars** on the creature card, in the same `ColorRect` shape the
  trust bar already uses. Only the three displayed genes; the hidden four are
  discovered through breeding.
- **The pairing readout**: both parents' full genomes, their kinship, the
  resulting `f`, and the predicted child as a per-gene range.
- **The remaining interval** on a pen pair, so feeding them has visible
  feedback.
- **Kept-herd mean vs. wild mean**, per gene — the readout that makes
  domestication drift a thing you watch happen rather than a thing a doc claims.

## Which doc owns what

- **[taming.md](taming.md)** — the wild→held loop: lasso, struggle, trust,
  orders, mount. Owns `src/gameplay/taming.gd`, what the `trust` value *means*
  behaviourally (which is the input husbandry's flight radius takes), the
  retirement of `pet_loyalty.gd`, and the neglect outcome for an
  animal that is **free to leave**: it walks off and goes feral rather than
  dying, because killing it is the cheaper implementation and the worse story.
  This doc only *reads* docility into `Taming.trust_after_feeding` and
  `Taming.break_free_chance`.
- **[animal_husbandry.md](animal_husbandry.md)** — the approach (bait, crouch,
  patience, and the speed-multiplier finding that motivates all three), the
  composed `FlightDistance.radius(species, wariness, trust, crouched)` and its
  sole Schmitt-gap test, the shy threshold, target selection
  (`Player.selected_animal` and
  `test_a_verb_prefers_the_selected_animal_over_a_nearer_one`), the pen as a
  placed structure, the roster UI, the pairing window, troughs and feed,
  products, the labour loop — and the neglect outcome for a **penned** animal,
  which *does* starve through `CreatureMarker._die()`, precisely because the
  fence removed the animal's own option to walk away from the problem. The two
  neglect outcomes differ because the situations differ, and each doc states
  its own case.
- **animal_genetics.md (this doc)** — the genome, inheritance, pairing
  genetics, lineage, inbreeding, domestication drift, and **the complete
  `KeptAnimals` FORMAT_VERSION 2 record and its byte budget**. Owns
  `AnimalGenome` (⬜ unwritten) and the changes to
  `AnimalReproduction.cooldown_for`, `Courtship.mates`, `CreatureInfo`'s level
  derivation, and `KeptAnimals` V2.
- **[evolution.md](evolution.md)** — the population-scale story, sexual
  selection, phenotype-target drift and herd dominance. Its "Bloodlines"
  section should now point here for the data model. **It also needs a
  correction:** it names the genes "speed, size, coat_saturation, fertility,
  disease_resistance". This doc renames `speed` → `agility` and
  `coat_saturation` → `coat_vibrancy`, which *are*
  `AnimalFitness.phenotype_for`'s existing tested keys and so need no adapter;
  renames `disease_resistance` → `hardiness`, which is a new key with no
  existing counterpart; and adds `strength`, which is an existing tested key
  evolution.md's list omitted. Per CLAUDE.md's cross-alignment rule,
  evolution.md gets updated to match when this lands.
- **[pets.md](pets.md)** — role by species (dogs guard, cows milk, horses
  carry). Aspirational, carries no status legend, ~5% built; superseded by the
  three docs above where they disagree.
- **[ecosystem_dynamics.md](ecosystem_dynamics.md)** — aggregate populations,
  carrying capacity, the two-fidelity rule, and the density gates in
  `_step_reproduction` that this doc leaves alone.
- **[disease.md](disease.md)** — the SIRS model that `hardiness` scales.
- **[dna.md](dna.md)** / **[players.md](players.md)** — the same crossover for
  people. dna.md already states that animals reuse "this exact inheritance
  shape, not a second one".

## Status / mechanisms

- ✅ `DnaCrossover.crossover` — two-parent per-trait crossover with bounded
  mutation (`MUTATION_AMOUNT` 0.15, `MUTATION_FLOOR` 0.01), 11 unit tests in
  `tests/unit/test_dna_crossover.gd`. **⬜ zero production callers** (verified
  by grep across `src/` and `scenes/`; the only non-test hit is a doc comment
  in `npc_genome.gd`). **Instance methods, not static** — see §0.
- ✅ `AnimalFitness.phenotype_for` / `fitness_score` / `mate_attractiveness` —
  strength/agility/coat_vibrancy, weights summing to 1.0, symmetric mate
  scoring, tested in `tests/unit/test_animal_fitness.gd`. **⬜ zero production
  callers.** **Instance methods.** `phenotype_for` takes a *seed*, not a genome.
- ✅ `CropBreeding.cross_pollinate` — two parent seeds + a roll → a child seed,
  tested. **⬜ zero production callers.** **Instance method.**
- ✅ Condition gating for a birth — `AnimalReproduction.can_reproduce`
  (energy / health / cooldown), live and called from `World._step_reproduction`.
- ✅ `LifeCycle.can_court_at` / `size_scale_at` / `MATURE_SECONDS` — live, but
  **only for ambient flyers** (`ambient_flyer_marker.gd`), plus `MATE_SECONDS`
  in `courtship.gd`. `CreatureMarker` never calls `LifeCycle` at all, so there
  is no existing composition point at the mammal seam §7 edits.
- ⬜ `LifeCycle.stage_at` — the one function in that file with no direct caller
  (it is reached indirectly through `can_court_at`). Nothing persists a mammal
  age to feed it; §11's `age_seconds` is that field.
- 🚧 Individual reproduction — it runs, but it is asexual budding with a
  `randi()` child (`World._step_reproduction` → `CreatureRenderer.spawn_single`),
  and the 24-real-hour `REPRO_COOLDOWN` against a never-persisted, never-scaled
  `_seconds_since_birth` means the gate essentially never opens. Matches
  [ecosystem_dynamics.md](ecosystem_dynamics.md)'s own 🚧 on the same entry.
- ⬜ `AnimalGenome` itself — no such file exists. (`hero_dna.gd`,
  `tree_genome.gd` and `npc_genome.gd` do; there is no animal equivalent.)
- ⬜ Genome derived from `wander_seed` (`for_seed`), the stored-override field
  on `CreatureMarker`, and `genome_or_derived()`.
- ⬜ `AnimalGenome.from_parents` — the one pipeline that crosses, correlates,
  penalises and **clamps to [0,1]**, which `DnaCrossover._nudge` does not do.
- ⬜ `CreatureInfo.level` from `strength` instead of `absi(seed) % LEVEL_RANGE`.
- ⬜ `CreatureRenderer.spawn_offspring` — the explicit-seed, explicit-genome
  spawn path, used by births *and* by `_restore_kept_animals`. `spawn_single`
  is deliberately **not** modified.
- ⬜ Two-parent births at `World._step_reproduction`; partner search; both
  parents paying `on_reproduced()`.
- ⬜ `Courtship.mates` weighted by `AnimalFitness.mate_attractiveness` instead
  of the flat `MATING_CHANCE` 0.25, with `NEUTRAL_ATTRACTIVENESS` derived by
  `inverse_lerp` so the pollinator path is unchanged by construction.
- ⬜ Mammal pairing reusing `can_court`/`can_pair`/`leads`/`pair_seed` without
  widening `DANCING_SPECIES`.
- ⬜ `AnimalReproduction.cooldown_for(fertility, energy)`; the breeding clock
  on the ecology time scale; the clock persisted.
- ⬜ `CreatureMarker.get_hover_actions()` — one of **four** hoverable entities
  that do not implement it (`creature_marker.gd`, `fish_marker.gd`,
  `piscivore_bird_marker.gd`, `ambient_flyer_marker.gd`), and the only tameable
  one. Eleven of the fifteen group members do implement it.
- ⬜ Gene bars on `CreaturePanel`; the predicted-child readout; `/breed`.
- ⬜ `coat_vibrancy` driving `ProceduralAnimalSprite`'s coat jitter **through
  `ProceduralAnimalAnimation`'s `LOOK_VARIANTS` bucket and cache key** — a
  continuous per-individual coat is not viable at the measured ~47 ms per frame
  set the cache exists to amortise.
- ⬜ **`coat_vibrancy` on illustrated species** — `horse`, `deer`, `boar`,
  `wolf`, `sheep` bypass `ProceduralAnimalSprite` entirely
  (`CreatureRenderer._build_marker`), so the coat gene is invisible on almost
  every tameable species that has real art. Named gap, not an oversight.
- ⬜ `size` multiplying the scale at `CreatureMarker._apply_action_scale` (both
  branches) and `CreatureRenderer._build_marker` (both branches) — **not** at
  `IllustratedAnimalSprite.marker_scale`, whose static cache is shared per
  species/action.
- ⬜ `marking` reusing `_paint_body_spots`.
- ⬜ Kinship, `f`, and the inbreeding penalty on fertility/hardiness.
- ⬜ Domestication correlation and the flee-response cost.
- ⬜ Birth events in the `EventStore`; `creature:` entity refs (which would be
  the first real producer of that id kind in the codebase) — plus the
  `FieldJournal` route fix, since `"creature"` currently resolves to
  `Why.explain_world_boss`, not to a pedigree walk.
- ⬜ `KeptAnimals` FORMAT_VERSION 2 (the 21-field record above) and the V1
  upgrade path.
- ⬜ `KEPT_ANIMALS_DIR` in **both** `World.backed_up_directories()` and
  `World._wipe_persisted_world` — pre-existing bug, not introduced here, and it
  takes both edits or `test_world_backup_paths.gd` goes red.
- ⬜ Wild-population inbreeding — the aggregate is a float per chunk and cannot
  carry a genome (§9's named limit).

*Coverage note: every ✅ above is a static read of the test source. Godot is
not on PATH in the environment this doc was written in, so no test in this repo
was executed to confirm it passes. There are also no integration tests at all —
`tests/` contains only `unit/` — while several mechanisms here are cross-node
by nature (pairing → crossover → spawn → persist → restore). Where that matters
the tests above are written against the pure modules and the serialised record
rather than against a live scene, which is a real coverage limit, not a
technique.*

## Open questions

- **How many child-seed samples does `predicted_child` need** before the
  displayed range stops visibly wobbling between two calls on the same parents?
  Cheap to measure; the test named in §6 pins it, but the answer is unknown.
- **Does the wild population need a phenotype target that drifts?**
  [evolution.md](evolution.md) specifies one and asks how fast it should move.
  This doc deliberately does not build it: `mate_attractiveness`'s similarity
  term already produces drift-like behaviour in a local cluster, and adding a
  per-species stored target is a second mechanism that would need its own
  persistence. Worth measuring whether the emergent drift is enough before
  building the explicit one.
- **Which gene supplies `heritable_yield`?** This is a *one-sided* hole, and
  the side that is still open is this doc's.
  [animal_husbandry.md](animal_husbandry.md) has already closed its half: its
  signature is
  `Husbandry.yield_fraction(energy, health_fraction, trust, is_sick, heritable_yield)`,
  pinned by `test_a_bred_ewe_out_yields_a_wild_caught_one_at_equal_condition`,
  and it explicitly hands this doc the question of where that last argument
  comes from. What remains is for this doc's `GENE_READERS` table to name a
  reader for it, which it does not yet do — so as things stand a champion bred
  over six generations would shear exactly like a sheep caught this morning.

  The candidate fix is to make `hardiness` the reader rather than adding an
  eighth gene: it is already the gene that means "this animal thrives", it is
  already read by the disease path, and a second reader costs nothing in
  persistence or byte budget where a new gene costs both. The argument against
  is pillar 3's warning about overloading one gene until it becomes a general
  quality score — which is exactly what `hardiness` would become if it also
  drove combat. Resolve it when the production path is built, not before, and
  record the decision here rather than in husbandry: this doc owns the genes.
- **Should `strength` scale `ATTACK_DAMAGE` for predators?** Predators cannot
  be tamed (`Taming.can_be_tamed` refuses them outright) so the player never
  breeds one — which makes it a pure ecosystem knob with no player input, and
  therefore suspect under pillar 1.
- **Does a bred animal's genome belong on its carcass?**
  [synthesis.md](synthesis.md)'s butcher-vs-breed dilemma — "The best materials
  come only from killing the best specimens" — needs the genome to reach
  `Carcass`/materials for that choice to be real. That is
  [materials.md](materials.md)'s seam, not this doc's, but nothing connects
  them today.
- **What happens to a bred line when the player dies?** [death.md](death.md)
  and [pets.md](pets.md)'s "pets respawn, don't permakill" both bear on whether
  a pedigree is an heirloom or a casualty, and neither says.
- **Is hunting deferred deliberately?** Nothing in this cluster specs tracking
  or traps, and `record_death` does not exist repo-wide, so a hunted valley
  restocks itself. Breeding makes individual animals valuable for the first
  time, which makes the absence of a mortality term more visible, not less.
  Named here as out of scope rather than left unmentioned.
- **Do receptor genes join `GENE_NAMES`?** [ethogram.md](ethogram.md) §4
  expresses `receptor_<channel>` genes (0.5 is the species template, 0 a
  specific anosmia) through the unmodified `DnaCrossover`, with
  `src/gameplay/ethogram.gd` as their reader and a test crossing them — but
  no live animal carries one, because the `AnimalGenome` this doc specifies
  does not exist yet. When it does they are candidates, subject to this doc's
  reader rule and to a question it raises: ten receptor loci cost bytes in
  the V2 record before any of them is visible on a panel. That doc owns the
  expression law; this one owns whether the genes are worth carrying.

## Editor's note

Two places where the audit that drove this pass is itself wrong, and two
findings this pass turned up that the audit did not have.

**The audit is wrong about the crossover tolerance formula.** P0-11's second
half says the doc's stated tolerance `max(MUTATION_AMOUNT * |sire - dam|,
MUTATION_FLOOR)` "is not the code's formula". It is: `test_each_child_trait_value_
is_reasonably_close_to_one_parent` in `tests/unit/test_dna_crossover.gd` uses
exactly that expression, character for character, as its own tolerance. The
audit's underlying observation is correct — when both parents hold the same
value the real deviation is at most `MUTATION_AMOUNT * MUTATION_FLOOR` (0.0015)
against a tolerance of 0.01, so the bound is loose at that end — but that makes
it a conservative bound in the repo's own test, not a wrong one. §3 keeps the
formula and now states the looseness explicitly. **P0-11's first half is
entirely correct** and was the more important half: `_nudge` really does return
an unclamped value, and a 0.0×1.0 parent pair really can produce 1.15.

**The audit's hoverable count is off by two.** P0-4 says "17 scripts join
`HoverTargetFinder.GROUP_NAME`". I count **15** by direct grep for
`add_to_group(HoverTargetFinder.GROUP_NAME)` across `src/` and `scenes/`, with
no other join path (the literal `"hoverable"` appears only in
`hover_target_finder.gd`'s own `GROUP_NAME` declaration). The substantive
finding is unaffected and correct: eleven implement `get_hover_actions()`, and
the four that do not are `creature_marker.gd`, `fish_marker.gd`,
`piscivore_bird_marker.gd` and `ambient_flyer_marker.gd` — so "the one hoverable
entity without a verb" was wrong and "the only tameable one" is right.

**Beyond the audit — the coat gene has a cache problem, not a jitter problem.**
No finding in the audit covers this and it changes the mechanism, not just the
prose. `CreatureMarker._animation_step` does not call
`ProceduralAnimalSprite.generate_texture` per animal; it calls
`ProceduralAnimalAnimation.textures_for`, which quantises the seed to
`absi(seed) % LOOK_VARIANTS` (8) and caches frame sets in a **static** dictionary
shared across every marker in the world. Its doc comment records the measured
reason: ~47 ms per frame set, and a herd of 25 entering "eat" together spent
1.18 seconds generating inside one 5-second window. A continuous per-individual
`coat_vibrancy` would reintroduce exactly that stall. §7 now specifies the gene
as quantised into those eight buckets with the bucket folded into the cache key,
and adds `test_two_animals_in_the_same_vibrancy_bucket_share_one_frame_set` as
the guard.

**Beyond the audit — `/journal creature:<seed>` does not read a pedigree.** The
draft said `field_journal.gd` "already routes the `creature` entity kind", which
is true but misleading: `FieldJournal.entry_for` routes `"creature"` to
`Why.explain_world_boss`, matching `WorldBossStore.bosses_for`'s `individual_id`.
Fed a bred lamb's id it would print a boss explanation about an animal that is
not one. §8 now names the extra work (fall through to `Why.explain_entity`, or
compose the two) and adds a red test for it, rather than implying the read is
free.
