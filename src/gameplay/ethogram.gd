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
## by an individual's receptor genes. Modulation (drives as gains) is the
## kernel's job, per tick; the DRIVE PROFILES -- how fast hunger rises for a
## mammal, a villager, a songbird, a kingfisher -- are data here too
## (drive_profile), run by one clock (Drives). Pure, static, no engine
## dependency, no RNG.

const SeasonCycle = preload("res://src/world/season_cycle.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

# -- the basis ---------------------------------------------------------------

## The smell channels, unchanged from Olfaction: what fruit, carrion, foliage,
## animals and fire emit. Olfaction re-exports these under its own names.
const SUGAR := "sugar"  # ripe fruit, nectar
const DECAY := "decay"  # rotting fruit, carrion
const GREEN := "green"  # leaves, cut grass, foliage
const MUSK := "musk"  # animals themselves
const SMOKE := "smoke"  # fire

## What another creature IS, as the marker's scan reports it. Not what it
## means: a sheep and a wolf are handed the same `predator` feature for the
## same lynx, and their own valence decides that one flees it and the other
## ignores it (ethogram.md §1, "danger stops being a verdict").
const PREDATOR := "predator"  # a hunting species, by CreatureInfo
const PLAYER := "player"  # a person
const FLESH := "flesh"  # an animal that is not a hunter: something a hunter eats
## The two directions CreaturePerception senses, as the tile it found.
const FORAGE := "forage"  # plant food there
const WATER := "water"  # drinkable water there
const MATE := "mate"  # my courtship partner

const SMELL_CHANNELS: Array[String] = [SUGAR, DECAY, GREEN, MUSK, SMOKE]
const CHANNELS: Array[String] = [
	SUGAR, DECAY, GREEN, MUSK, SMOKE, PREDATOR, PLAYER, FLESH, FORAGE, WATER, MATE
]

# -- drives ------------------------------------------------------------------

## The named gains a wiring can be gated by. A drive's level in [0, 1]
## multiplies the pull of every wiring it gates; zero switches them off.
const DRIVE_FEAR := "fear"
const DRIVE_THIRST := "thirst"
const DRIVE_HUNGER := "hunger"
const DRIVE_COURTSHIP := "courtship"

## Below this score an animal is not interested enough in a smell to cross a
## field for it (ScentForaging's MIN_INTEREST, now the smell wiring's floor).
## Without a floor, a creature would trail after the faintest trace of
## something it barely likes instead of getting on with its life.
const SMELL_INTEREST_FLOOR := 0.02

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
	# A bird with its own appetite (PiscivoreAppetite): a couple of fish
	# across an in-game day, and a whole inter-meal interval before it is
	# interested again -- "1 or 2 fish per in-game day based on hunger", as
	# asked, pinned by the resulting count over a simulated day. Starts
	# wanting a meal. No nose: it hunts by sight.
	"kingfisher": {
		"body_plan": "bird",
		"drives": {
			DRIVE_HUNGER: {
				"rise_seconds": SeasonCycle.SECONDS_PER_DAY / 2.0, "threshold": 1.0, "meal": 1.0, "start": 1.0,
			},
		},
	},
}

# -- body plans --------------------------------------------------------------

## What is shared by everything built the same way: receptor defaults for the
## non-smell channels, and the ordered wirings the kernel walks top to bottom.
##
## The mammal ladder is CreatureBehavior's priority order, for the reasons
## its own doc comment gives: an animal does not court while hunted, dying of
## thirst, starving or mid-hunt. A predator and a person both default to
## "leave" (valence -1); the mammal adapter flips both to +1 for an animal
## that will stand and fight, zeroes `predator` for a hunter (a predator is
## not threatened by other creatures, only by people), and sets `flesh` to +1
## for a hunter -- diet and temperament facts that today reach decide() only
## as context flags (ethogram.md §3, §7).
##
## The smell wiring is the same ranking CreatureMarker's forage program runs
## through ScentForaging when it chooses what to smell its way to; in the
## ladder it is reached by the adapter's `smells` context key (ethogram.md
## §7) and, once the other body plans exist, by anything that hunts by nose
## without a grazing bout. It sits between hunting and biome forage so a
## nose finds a windfall before an animal treks toward greener tiles.
##
## Only the mammal plan has wirings. `bird`, `insect`, `fish` and `villager`
## are named on the records that will need them and wirings_for() returns
## nothing for them rather than pretending.
##
## Every plan's `drives` block is its clock (see Drives for the fields). The
## numbers are the ones the four needs modules always ran, moved here so
## they are species data rather than module constants:
##   mammal    CreatureNeeds' 0.02/s hunger and 0.03/s thirst, urgent from
##             half way, a meal resets, a herd staggered up to 0.45 of the
##             cycle so it does not cross into hunger on one tick
##   villager  the same pace, hunger only (docs/concept/npc.md: thirst has
##             no villager-side consumer, so it is not simulated)
##   bird      BirdDigestion's songbird crop, as hunger: empties in an
##             eighth of the world day, urgent below 0.35 full, a meal fills
##             it by 0.7, starts empty -- a bird that starts fed does nothing
##             until it is not
const BODY_PLANS := {
	"mammal": {
		"receptors": {
			"sensitivity": {PREDATOR: 1.0, PLAYER: 1.0, FLESH: 1.0, FORAGE: 1.0, WATER: 1.0, MATE: 1.0},
			"valence": {PREDATOR: -1.0, PLAYER: -1.0, FLESH: 0.0, FORAGE: 1.0, WATER: 1.0, MATE: 1.0},
		},
		"drives": {
			DRIVE_HUNGER: {"rise_seconds": 1.0 / 0.02, "threshold": 0.5, "meal": 1.0, "stagger": 0.45},
			DRIVE_THIRST: {"rise_seconds": 1.0 / 0.03, "threshold": 0.5, "meal": 1.0, "stagger": 0.45},
		},
		"wirings": [
			{"gate": DRIVE_FEAR, "channels": [PREDATOR, PLAYER], "approach": "attack", "avoid": "flee"},
			{"gate": DRIVE_THIRST, "channels": [WATER], "approach": "seek_water", "search": "search_water"},
			{"gate": DRIVE_HUNGER, "channels": [FLESH], "approach": "hunt"},
			{
				"gate": DRIVE_HUNGER, "channels": SMELL_CHANNELS, "approach": "seek_food",
				"floor": SMELL_INTEREST_FLOOR,
			},
			{"gate": DRIVE_HUNGER, "channels": [FORAGE], "approach": "seek_food", "search": "search_food"},
			{"gate": DRIVE_COURTSHIP, "channels": [MATE], "approach": "court"},
		],
	},
	"villager": {
		"drives": {
			DRIVE_HUNGER: {"rise_seconds": 1.0 / 0.02, "threshold": 0.5, "meal": 1.0, "stagger": 0.45},
		},
	},
	"bird": {
		"drives": {
			DRIVE_HUNGER: {
				"rise_seconds": SeasonCycle.SECONDS_PER_DAY / 8.0, "threshold": 1.0 - 0.35, "meal": 0.7, "start": 1.0,
			},
		},
	},
}

# -- expression: genotype to receptors --------------------------------------

## A genome entry `receptor_<channel>` in [0, 1] scales that channel's
## sensitivity. The same String -> float shape NpcGenome and FlyerPersonality
## use, so DnaCrossover.crossover inherits it unchanged. AnimalGenome.for_seed
## derives a set for every land mammal from its wander_seed.
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
## (the mammal adapter flips valences) without editing the species.
##
## `body_plan` overrides the record's own plan -- the land-mammal adapter
## runs every CreatureMarker species on the mammal ladder, most of which have
## no record yet, so the override expresses that plan's defaults for ANY
## species and layers the species' nose on top when it has one. Without an
## override, an unknown species expresses nothing.
static func express(species: String, genome: Dictionary = {}, body_plan: String = "") -> Dictionary:
	var record: Dictionary = SPECIES.get(species, {})
	var plan_name := body_plan if body_plan != "" else String(record.get("body_plan", ""))
	if record.is_empty() and plan_name == "":
		return {}
	var sensitivity := {}
	var valence := {}
	var plan: Dictionary = BODY_PLANS.get(plan_name, {})
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

# -- personality: boldness (docs/concept/ethogram.md §9) --------------------

## A personality gene, not a receptor: how readily an individual's OWN fear
## wiring fires at all, independent of what it can smell or see. Same
## String -> float shape as the receptor genes, so DnaCrossover inherits it
## unchanged; a different namespace because it isn't one.
const BOLDNESS := "boldness"

## 0.5 is the population median BY DEFINITION, same convention as
## NEUTRAL_RECEPTOR_GENE: a gene absent from a genome (every context built
## before this existed) reads as exactly this, which is why fear_floor(this)
## is zero -- the only floor the mammal ladder's fear wiring has ever had.
const NEUTRAL_BOLDNESS_GENE := 0.5

## The boldest individual's fear wiring only fires once a threat is within
## about one tile (TerrainRenderer.TILE_SIZE) -- the same "right here" scale
## CreatureBehavior already uses to place a sensed direction as a stimulus
## (DIRECTION_STIMULUS_DISTANCE). Deliberately NOT Affinity.proximity(0.0)
## (literally touching): that ceiling sits beyond any distance a running
## simulation actually produces, making the boldest individual's fear wiring
## unreachable rather than merely hard to reach.
##
## Inlined rather than calling Affinity.proximity (a const initializer must
## be constant-foldable); test_the_boldest_gene_caps_the_floor_at_one_tile_away
## pins the two formulas identical.
const BOLDEST_FEAR_FLOOR := 1.0 / (1.0 + float(TerrainRenderer.TILE_SIZE))


## The fear wiring's floor for an individual with this boldness gene: zero
## at or below the population median (today's only floor, unchanged for
## every animal at or below typical), rising linearly past it to
## BOLDEST_FEAR_FLOOR at gene 1.0. There is nowhere to go MORE fearful than
## zero, so only boldness ever moves this, and only upward.
static func fear_floor(boldness_gene: float) -> float:
	var gene := clampf(boldness_gene, 0.0, 1.0)
	if gene <= NEUTRAL_BOLDNESS_GENE:
		return 0.0
	var t := (gene - NEUTRAL_BOLDNESS_GENE) / (1.0 - NEUTRAL_BOLDNESS_GENE)
	return t * BOLDEST_FEAR_FLOOR


## This species' drive profile (the fields Drives reads): its body plan's
## clock, with the species' own overrides on top -- a kingfisher is a bird
## with a different appetite. `body_plan` overrides the record's plan, as in
## express(). A deep copy; empty for a species and plan that have none.
static func drive_profile(species: String, body_plan: String = "") -> Dictionary:
	var record: Dictionary = SPECIES.get(species, {})
	var plan_name := body_plan if body_plan != "" else String(record.get("body_plan", ""))
	var plan: Dictionary = BODY_PLANS.get(plan_name, {})
	var profile := {}
	for drive in plan.get("drives", {}):
		profile[drive] = (plan["drives"][drive] as Dictionary).duplicate(true)
	for drive in record.get("drives", {}):
		profile[drive] = (record["drives"][drive] as Dictionary).duplicate(true)
	return profile


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
