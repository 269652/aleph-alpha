extends RefCounted

## The ethogram: behaviour as data (see docs/concept/ethogram.md).
##
## Ethology's ethogram is the catalogue of what a species does and what
## releases each behaviour. This one is the game's behaviour DSL. Three
## things live here, and nothing executable:
##
##   * the CHANNELS -- one small feature basis every stimulus and every
##     receptor is expressed in, so a fruit, a carcass, a wolf and a puddle
##     are all points in the same space and one kernel can compare them;
##   * the SPECIES records -- receptor sensitivity (what an animal can
##     detect) and valence (what detecting it does: positive draws, negative
##     repels) per channel, plus which body plan the species is built on;
##   * the BODY_PLANS -- receptor defaults shared by everything built the
##     same way, and the ordered WIRINGS the behaviour kernel evaluates.
##
## The pillar this exists for: "all animals search for food and eat when
## they are hungry" is written once, as a wiring, and a species gets it by
## being data. The five smell records here are Olfaction.RECEPTORS moved
## verbatim (olfaction's `response` is this file's `valence`); the mammal
## ladder is CreatureBehavior's priority ladder written down.
##
## express() is the genotype-to-phenotype step: a species template, adjusted
## by an individual's receptor genes. modulation (drives as gains) is the
## kernel's job, per tick. Pure, static, no engine dependency, no RNG.

# -- the basis ---------------------------------------------------------------

## The smell channels, unchanged from Olfaction: what fruit, carrion, foliage,
## animals and fire emit. Olfaction re-exports these under its own names.
const SUGAR := "sugar"  # ripe fruit, nectar
const DECAY := "decay"  # rotting fruit, carrion
const GREEN := "green"  # leaves, cut grass, foliage
const MUSK := "musk"  # animals themselves
const SMOKE := "smoke"  # fire

## The non-smell channels the land-mammal ladder listens on. `danger` is,
## for now, the marker's own threat classification handed over as a feature
## (ethogram.md §1 says so plainly); the roadmap replaces it with predator/
## player/conspecific features and lets valence decide.
const DANGER := "danger"  # something that can hurt me
const FLESH := "flesh"  # an animal I could eat
const FORAGE := "forage"  # plant food in that direction
const WATER := "water"  # drinkable water in that direction
const MATE := "mate"  # my courtship partner

const SMELL_CHANNELS: Array[String] = [SUGAR, DECAY, GREEN, MUSK, SMOKE]
const CHANNELS: Array[String] = [
	SUGAR, DECAY, GREEN, MUSK, SMOKE, DANGER, FLESH, FORAGE, WATER, MATE
]

# -- drives ------------------------------------------------------------------

## The named gains a wiring can be gated by. A drive's level in [0, 1]
## multiplies the pull of every wiring it gates; zero switches them off.
const DRIVE_FEAR := "fear"
const DRIVE_THIRST := "thirst"
const DRIVE_HUNGER := "hunger"
const DRIVE_COURTSHIP := "courtship"

# -- species records ---------------------------------------------------------

## `smell` blocks are Olfaction's receptor sets, verbatim. `sensitivity` is
## how well the animal DETECTS a molecule; `valence` is what it makes of it.
## They are separate on purpose: an animal can be keenly aware of something
## it wants nothing to do with, which is what makes a repellent work rather
## than merely being invisible.
const SPECIES := {
	# Rooting omnivore: excellent nose, eats fruit and is untroubled by a
	# little rot -- which is most of what a boar's nose is for.
	"boar": {
		"body_plan": "mammal",
		"smell": {
			"sensitivity": {SUGAR: 1.0, DECAY: 0.9, GREEN: 0.5, MUSK: 0.6, SMOKE: 0.8},
			"valence": {SUGAR: 1.0, DECAY: 0.3, GREEN: 0.2, MUSK: -0.1, SMOKE: -1.0},
		},
	},
	# Browser: wants fruit and foliage, avoids anything dead.
	"deer": {
		"body_plan": "mammal",
		"smell": {
			"sensitivity": {SUGAR: 0.8, DECAY: 0.7, GREEN: 1.0, MUSK: 0.9, SMOKE: 0.9},
			"valence": {SUGAR: 0.8, DECAY: -0.6, GREEN: 0.9, MUSK: -0.5, SMOKE: -1.0},
		},
	},
	# Grazer: it is the grass it is after.
	"horse": {
		"body_plan": "mammal",
		"smell": {
			"sensitivity": {SUGAR: 0.7, DECAY: 0.6, GREEN: 1.0, MUSK: 0.7, SMOKE: 0.9},
			"valence": {SUGAR: 0.6, DECAY: -0.5, GREEN: 1.0, MUSK: -0.2, SMOKE: -1.0},
		},
	},
	# Fruit-eating bird: takes ripe fruit, ignores what has gone over.
	"robin": {
		"body_plan": "bird",
		"smell": {
			"sensitivity": {SUGAR: 0.9, DECAY: 0.4, GREEN: 0.3, MUSK: 0.5, SMOKE: 0.7},
			"valence": {SUGAR: 1.0, DECAY: -0.2, GREEN: 0.1, MUSK: -0.3, SMOKE: -0.8},
		},
	},
	# The one that wants what everything else avoids.
	"fly": {
		"body_plan": "insect",
		"smell": {
			"sensitivity": {SUGAR: 0.5, DECAY: 1.0, GREEN: 0.1, MUSK: 0.6, SMOKE: 0.2},
			"valence": {SUGAR: 0.3, DECAY: 1.0, GREEN: 0.0, MUSK: 0.2, SMOKE: -0.4},
		},
	},
}

# -- body plans --------------------------------------------------------------

## What is shared by everything built the same way: receptor defaults for the
## non-smell channels, and the ordered wirings the kernel walks top to bottom.
##
## The mammal ladder is CreatureBehavior's priority order, for the reasons
## its own doc comment gives: an animal does not court while hunted, dying of
## thirst, starving or mid-hunt. `danger` defaults to "leave" (valence -1);
## the mammal adapter flips it to +1 for an animal that will stand and fight,
## and sets `flesh` to +1 for a predator -- both are species facts that today
## only reach decide() as context flags (ethogram.md §3, §7).
##
## The smell wiring is new and inert for the live game until CreatureMarker
## publishes smells as stimuli (slice 2): ScentForaging keeps doing that job
## in the marker meanwhile. It sits between hunting and biome forage so a
## nose finds a windfall before an animal treks toward greener tiles.
##
## Only the mammal plan has wirings. `bird`, `insect`, `fish` and `villager`
## are named on the records that will need them and wirings_for() returns
## nothing for them rather than pretending.
const BODY_PLANS := {
	"mammal": {
		"receptors": {
			"sensitivity": {DANGER: 1.0, FLESH: 1.0, FORAGE: 1.0, WATER: 1.0, MATE: 1.0},
			"valence": {DANGER: -1.0, FLESH: 0.0, FORAGE: 1.0, WATER: 1.0, MATE: 1.0},
		},
		"wirings": [
			{"gate": DRIVE_FEAR, "channels": [DANGER], "approach": "attack", "avoid": "flee"},
			{"gate": DRIVE_THIRST, "channels": [WATER], "approach": "seek_water", "search": "search_water"},
			{"gate": DRIVE_HUNGER, "channels": [FLESH], "approach": "hunt"},
			{"gate": DRIVE_HUNGER, "channels": SMELL_CHANNELS, "approach": "seek_food"},
			{"gate": DRIVE_HUNGER, "channels": [FORAGE], "approach": "seek_food", "search": "search_food"},
			{"gate": DRIVE_COURTSHIP, "channels": [MATE], "approach": "court"},
		],
	},
}

# -- expression: genotype to receptors --------------------------------------

## A genome entry `receptor_<channel>` in [0, 1] scales that channel's
## sensitivity. The same String -> float shape NpcGenome and FlyerPersonality
## use, so DnaCrossover.crossover inherits it unchanged.
const RECEPTOR_GENE_PREFIX := "receptor_"

## 0.5 is the species template BY DEFINITION: a gene is a deviation from the
## species, and the population mean deviates nowhere. Under the linear law
## below 0.0 is a specific anosmia (the receptor is not expressed) and 1.0 a
## receptor at twice the species' sensitivity -- the factor of two is what a
## linear law with these two fixed points produces, not a tuned number; the
## tests pin the endpoints and monotonicity, not the slope.
const NEUTRAL_RECEPTOR_GENE := 0.5


## Whether this species smells at all -- the only thing ScentForaging asks.
static func has_nose(species: String) -> bool:
	if not SPECIES.has(species):
		return false
	return not SPECIES[species].get("smell", {}).is_empty()


## This individual's expressed receptors: the species' smell block merged
## over its body plan's defaults, with receptor genes applied to sensitivity.
## Valence is the species' innate wiring and no gene touches it (ethogram.md
## §4). Returns fresh Dictionaries so a caller may adjust what it was handed
## (the mammal adapter flips valences) without editing the species. An
## unknown species expresses nothing.
static func express(species: String, genome: Dictionary = {}) -> Dictionary:
	if not SPECIES.has(species):
		return {}
	var record: Dictionary = SPECIES[species]
	var sensitivity := {}
	var valence := {}
	var plan: Dictionary = BODY_PLANS.get(record.get("body_plan", ""), {})
	_merge_receptors(plan.get("receptors", {}), sensitivity, valence)
	_merge_receptors(record.get("smell", {}), sensitivity, valence)
	for channel in sensitivity:
		var gene_name: String = RECEPTOR_GENE_PREFIX + channel
		if genome.has(gene_name):
			sensitivity[channel] = float(sensitivity[channel]) * receptor_gene_factor(float(genome[gene_name]))
	return {"sensitivity": sensitivity, "valence": valence}


## How a receptor gene scales the species' sensitivity for its channel.
static func receptor_gene_factor(gene: float) -> float:
	return clampf(gene, 0.0, 1.0) / NEUTRAL_RECEPTOR_GENE


## The ordered wirings of a body plan, as a deep copy the caller may reorder
## or override for itself. Empty for a plan that has none yet.
static func wirings_for(body_plan: String) -> Array:
	var plan: Dictionary = BODY_PLANS.get(body_plan, {})
	var copy: Array = []
	for wiring in plan.get("wirings", []):
		copy.append((wiring as Dictionary).duplicate(true))
	return copy


static func _merge_receptors(block: Dictionary, sensitivity: Dictionary, valence: Dictionary) -> void:
	for channel in block.get("sensitivity", {}):
		sensitivity[channel] = float(block["sensitivity"][channel])
	for channel in block.get("valence", {}):
		valence[channel] = float(block["valence"][channel])
