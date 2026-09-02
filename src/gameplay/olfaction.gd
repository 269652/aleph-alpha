extends RefCounted

## Smell as molecules and receptors (see docs/concept/olfaction.md).
##
## A smell is not a label, it is a MIXTURE. A ripe apple and a rotting one are
## the same fruit emitting different proportions of the same handful of
## molecules, which is what lets a new thing smell like something without
## anyone deciding in advance what it smells OF: a carcass and a rotten fruit
## share their decay molecule and therefore share their audience, without
## either being told about the other.
##
## And nothing is inherently attractive. A boar and a fly meet the same rotting
## apple and disagree, because the verdict lives in the ANIMAL. That is what
## makes an ecosystem out of a set of props -- the same object meaning
## different things to different creatures is what a niche actually is.
##
## Pure and engine-free: this says what a thing emits and what an animal makes
## of it. Walking toward it is the caller's job.

const CreatureInfo = preload("res://src/world/creature_info.gd")

## The molecules worth modelling: the ones that decide foraging.
const SUGAR := "sugar"  # ripe fruit, nectar
const DECAY := "decay"  # rotting fruit, carrion
const GREEN := "green"  # leaves, cut grass, foliage
const MUSK := "musk"  # animals themselves
const SMOKE := "smoke"  # fire
## Nuts, seeds and oily kernels. Real: what a nut smells of is the aldehydes
## its fats throw off (hexanal, nonanal) as they oxidise -- nothing to do with
## sugar or foliage, which is exactly why a squirrel and a horse disagree
## about a walnut. Added when bait became a real verb: without it every food
## on the ground reduced to "sweet or rotten" and a nut had no smell of its
## own to prefer.
const OIL := "oil"

const MOLECULES: Array[String] = [SUGAR, DECAY, GREEN, MUSK, SMOKE, OIL]

## How far a smell carries at all, in tiles.
const MAX_RANGE_TILES := 20.0

## How sharply it thins with range. Smell falls off faster than light: an
## animal has to cast about and close in rather than reading a beacon from
## across the map, and that casting about is the thing the player watches.
const DILUTION_POWER := 1.6


## ## What fruit emits
##
## Interpolated across its life rather than switched at a threshold, so its
## audience changes gradually: as sugar falls and decay rises, the animals that
## come for it change without anything deciding "this is now a rotten apple".
const FRUIT_RIPE_MIXTURE := {SUGAR: 1.0, DECAY: 0.05, GREEN: 0.15}
const FRUIT_ROTTEN_MIXTURE := {SUGAR: 0.15, DECAY: 1.0, GREEN: 0.05}


## What a fruit of this freshness smells of. `freshness` is 1 fresh, 0 rotten
## (see FruitSpoilage.freshness).
static func fruit_mixture(_item_id: String, freshness: float) -> Dictionary:
	var t := clampf(freshness, 0.0, 1.0)
	var mixture := {}
	for molecule in MOLECULES:
		var ripe: float = FRUIT_RIPE_MIXTURE.get(molecule, 0.0)
		var rotten: float = FRUIT_ROTTEN_MIXTURE.get(molecule, 0.0)
		var strength := lerpf(rotten, ripe, t)
		if strength > 0.0:
			mixture[molecule] = strength
	return mixture


## ## Who carries which receptors
##
## `sensitivity` is how well the animal DETECTS a molecule at all; `response`
## is what it makes of detecting it, negative being driven off. They are
## separate on purpose: an animal can be keenly aware of something it wants
## nothing to do with, which is what makes a repellent work rather than merely
## being invisible.
const RECEPTORS := {
	# Rooting omnivore: excellent nose, eats fruit and is untroubled by a
	# little rot -- which is most of what a boar's nose is for.
	"boar": {
		"sensitivity": {SUGAR: 1.0, DECAY: 0.9, GREEN: 0.5, MUSK: 0.6, SMOKE: 0.8, OIL: 1.0},
		"response": {SUGAR: 1.0, DECAY: 0.3, GREEN: 0.2, MUSK: -0.1, SMOKE: -1.0, OIL: 0.8},
	},
	# Browser: wants fruit and foliage, avoids anything dead.
	"deer": {
		"sensitivity": {SUGAR: 0.8, DECAY: 0.7, GREEN: 1.0, MUSK: 0.9, SMOKE: 0.9, OIL: 0.4},
		"response": {SUGAR: 0.8, DECAY: -0.6, GREEN: 0.9, MUSK: -0.5, SMOKE: -1.0, OIL: 0.15},
	},
	# Grazer: it is the grass it is after.
	"horse": {
		"sensitivity": {SUGAR: 0.7, DECAY: 0.6, GREEN: 1.0, MUSK: 0.7, SMOKE: 0.9, OIL: 0.3},
		"response": {SUGAR: 0.6, DECAY: -0.5, GREEN: 1.0, MUSK: -0.2, SMOKE: -1.0, OIL: 0.05},
	},
	# Fruit-eating bird: takes ripe fruit, ignores what has gone over.
	"robin": {
		"sensitivity": {SUGAR: 0.9, DECAY: 0.4, GREEN: 0.3, MUSK: 0.5, SMOKE: 0.7, OIL: 0.6},
		"response": {SUGAR: 1.0, DECAY: -0.2, GREEN: 0.1, MUSK: -0.3, SMOKE: -0.8, OIL: 0.4},
	},
	# The one that wants what everything else avoids.
	"fly": {
		"sensitivity": {SUGAR: 0.5, DECAY: 1.0, GREEN: 0.1, MUSK: 0.6, SMOKE: 0.2, OIL: 0.4},
		"response": {SUGAR: 0.3, DECAY: 1.0, GREEN: 0.0, MUSK: 0.2, SMOKE: -0.4, OIL: 0.1},
	},
}


## ## A nose for everything with a body
##
## The hand-authored table above covers five animals. The husbandry approach
## layer needs every land species to be able to smell, because bait an animal
## cannot detect is not bait -- and hand-authoring thirty more tables would put
## thirty more things in the tree to go stale as the roster grows.
##
## So a species without its own entry inherits the receptors of its DIET
## (`CreatureInfo.DIET_BY_SPECIES`), which is the honest answer anyway: what an
## animal's nose is FOR is what it eats. A grazer added tomorrow is born
## smelling like a grazer rather than born noseless.
const RECEPTORS_BY_DIET := {
	# Eats foliage; keenly aware of anything that eats IT.
	"Grazer": {
		"sensitivity": {SUGAR: 0.7, DECAY: 0.6, GREEN: 1.0, MUSK: 0.9, SMOKE: 0.9, OIL: 0.3},
		"response": {SUGAR: 0.6, DECAY: -0.5, GREEN: 1.0, MUSK: -0.6, SMOKE: -1.0, OIL: 0.05},
	},
	# Nuts, seeds and kernels -- the diet OIL exists for.
	"Forager": {
		"sensitivity": {SUGAR: 0.7, DECAY: 0.5, GREEN: 0.4, MUSK: 0.9, SMOKE: 0.8, OIL: 1.0},
		"response": {SUGAR: 0.5, DECAY: -0.2, GREEN: 0.1, MUSK: -0.7, SMOKE: -0.9, OIL: 1.0},
	},
	# Takes what is going: fruit, mast, carrion, and the odd nest.
	"Omnivore": {
		"sensitivity": {SUGAR: 1.0, DECAY: 0.9, GREEN: 0.5, MUSK: 0.7, SMOKE: 0.8, OIL: 0.8},
		"response": {SUGAR: 0.9, DECAY: 0.3, GREEN: 0.2, MUSK: 0.1, SMOKE: -0.9, OIL: 0.6},
	},
	# Follows other animals, not plants: musk is the signal, and a carcass
	# still counts as a meal.
	"Hunter": {
		"sensitivity": {SUGAR: 0.3, DECAY: 0.9, GREEN: 0.2, MUSK: 1.0, SMOKE: 0.8, OIL: 0.6},
		"response": {SUGAR: 0.05, DECAY: 0.5, GREEN: 0.0, MUSK: 0.9, SMOKE: -0.8, OIL: 0.3},
	},
	# A snake hunting mice: the same musk-led nose, dulled to everything
	# vegetable, and far less troubled by smoke than a mammal is.
	"Small-Prey Hunter": {
		"sensitivity": {SUGAR: 0.15, DECAY: 0.7, GREEN: 0.1, MUSK: 1.0, SMOKE: 0.4, OIL: 0.4},
		"response": {SUGAR: 0.0, DECAY: 0.2, GREEN: 0.0, MUSK: 0.9, SMOKE: -0.5, OIL: 0.1},
	},
	"Venomous Hunter": {
		"sensitivity": {SUGAR: 0.15, DECAY: 0.7, GREEN: 0.1, MUSK: 1.0, SMOKE: 0.4, OIL: 0.4},
		"response": {SUGAR: 0.0, DECAY: 0.2, GREEN: 0.0, MUSK: 0.9, SMOKE: -0.5, OIL: 0.1},
	},
	# Nothing hunts it, so nothing about the world reads as a warning -- not
	# even fire. The one nose with no negative response to SMOKE at all.
	"Apex Hunter": {
		"sensitivity": {SUGAR: 0.2, DECAY: 0.8, GREEN: 0.2, MUSK: 1.0, SMOKE: 0.6, OIL: 0.5},
		"response": {SUGAR: 0.0, DECAY: 0.4, GREEN: 0.0, MUSK: 1.0, SMOKE: 0.0, OIL: 0.2},
	},
	"Abyssal Hunter": {
		"sensitivity": {SUGAR: 0.2, DECAY: 0.9, GREEN: 0.1, MUSK: 1.0, SMOKE: 0.1, OIL: 0.5},
		"response": {SUGAR: 0.0, DECAY: 0.6, GREEN: 0.0, MUSK: 1.0, SMOKE: 0.0, OIL: 0.2},
	},
}


## The receptors `species` actually carries: its own hand-authored entry if it
## has one, otherwise its diet's. Empty for something with no nose at all,
## which callers can treat as "smells nothing" rather than crashing.
##
## The authored entry WINS on purpose: the boar/deer/horse tuning above was
## measured against real foraging behaviour, and a diet default must not
## quietly overwrite it.
static func receptors_for(species: String) -> Dictionary:
	if RECEPTORS.has(species):
		return RECEPTORS[species]
	var diet := String(CreatureInfo.DIET_BY_SPECIES.get(species, ""))
	return RECEPTORS_BY_DIET.get(diet, {})


## Whether this species can smell anything at all.
static func has_nose(species: String) -> bool:
	return not receptors_for(species).is_empty()


## ## What a PARTICULAR food smells of
##
## `fruit_mixture` deliberately ignores its item id -- every fruit is the same
## sugar-to-decay curve, which is right for fruit and wrong for everything
## else. Bait needs the id to matter: a carrot has to be a better lure for a
## horse than a walnut is, or choosing what to put on the ground is not a
## choice (see docs/concept/animal_husbandry.md "The approach").
##
## Anything not listed falls back to the fruit curve, so a food added later is
## drawable but never silently scentless -- and
## test_every_food_item_in_the_catalog_has_a_mixture iterates the real catalog
## so an addition cannot go unnoticed either.
const BAIT_MIXTURES := {
	# Roots: earthy-sweet and leafy, not fruity. This is why the taming treat
	# is a carrot and not an apple -- it is aimed at a grazer's nose.
	"carrot": {SUGAR: 0.75, GREEN: 0.8, DECAY: 0.05},
	"potato": {SUGAR: 0.3, GREEN: 0.35, DECAY: 0.05},
	# Mast. OIL-led, which is what a forager is listening for.
	"walnut": {OIL: 1.0, GREEN: 0.15, SUGAR: 0.1},
	"hazelnut": {OIL: 0.95, GREEN: 0.15, SUGAR: 0.12},
	"acorn": {OIL: 0.8, GREEN: 0.25, SUGAR: 0.08},
	"pine": {OIL: 0.85, GREEN: 0.35, SUGAR: 0.05},
	"nut": {OIL: 0.9, GREEN: 0.2, SUGAR: 0.1},
	# Flesh. Loud to a hunter, repellent to everything it hunts.
	"meat": {MUSK: 0.9, DECAY: 0.4, OIL: 0.3},
	"fish": {MUSK: 0.7, DECAY: 0.45, OIL: 0.5},
	"rare_fish": {MUSK: 0.7, DECAY: 0.45, OIL: 0.5},
	"legendary_fish": {MUSK: 0.7, DECAY: 0.45, OIL: 0.5},
	# Cooking is a real change to what a thing emits, not a label on it: the
	# fire is in the food afterwards. So cooked bait carries SMOKE, which every
	# prey animal in RECEPTORS_BY_DIET reads as fire and avoids -- cooking your
	# bait makes it WORSE bait, and nothing had to be told that.
	"cooked_meat": {MUSK: 0.5, DECAY: 0.1, OIL: 0.5, SMOKE: 0.6},
	"cooked_fish": {MUSK: 0.4, DECAY: 0.1, OIL: 0.55, SMOKE: 0.6},
}

## How much of a food's own signature survives it going over. Not zero: a
## rotten apple still smells faintly of apple, which is why the fly and the
## boar can still tell one windfall from another.
const ROTTEN_RESIDUE := 0.15


## What a food of this freshness emits. `freshness` is 1 fresh, 0 rotten (see
## FruitSpoilage.freshness), interpolated exactly the way fruit_mixture already
## interpolates so a bait's audience changes across its life rather than at a
## threshold.
static func bait_mixture(item_id: String, freshness: float) -> Dictionary:
	var fresh: Dictionary = BAIT_MIXTURES.get(item_id, FRUIT_RIPE_MIXTURE)
	var t := clampf(freshness, 0.0, 1.0)
	var mixture := {}
	for molecule in MOLECULES:
		var fresh_strength: float = fresh.get(molecule, 0.0)
		var rotten_strength := (
			FRUIT_ROTTEN_MIXTURE[DECAY] if molecule == DECAY else fresh_strength * ROTTEN_RESIDUE
		)
		var strength := lerpf(rotten_strength, fresh_strength, t)
		if strength > 0.0:
			mixture[molecule] = strength
	return mixture


## ## The player has a smell too
##
## A human is an animal, and animals smell of MUSK -- the molecule that was
## defined from the start and that nothing ever emitted. Without a player
## emission there is nothing for the wind to carry (see WindScent), and
## therefore no difference between stalking upwind and downwind, which is the
## whole of the stalk.
const PLAYER_MIXTURE := {MUSK: 1.0}


static func player_mixture() -> Dictionary:
	return PLAYER_MIXTURE.duplicate()



## How faint a smell is at this range, 1 at the source and 0 beyond reach.
static func dilution(distance_tiles: float) -> float:
	var distance := maxf(distance_tiles, 0.0)
	if distance >= MAX_RANGE_TILES:
		return 0.0
	return pow(1.0 - distance / MAX_RANGE_TILES, DILUTION_POWER)


## How LOUD this mixture is to this animal -- how much it notices, regardless
## of whether it likes it.
static func perceived_strength(
	species: String, mixture: Dictionary, distance_tiles: float
) -> float:
	var receptors := receptors_for(species)
	if receptors.is_empty():
		return 0.0
	var sensitivity: Dictionary = receptors["sensitivity"]
	var total := 0.0
	for molecule in mixture:
		total += float(mixture[molecule]) * float(sensitivity.get(molecule, 0.0))
	return total * dilution(distance_tiles)


## What this animal makes of the mixture: positive draws it in, negative drives
## it off, near zero is noise.
##
## The same sum as perceived_strength but weighted by RESPONSE, so a rotting
## fruit can be extremely loud to a deer and still repel it.
static func attraction_to(
	species: String, mixture: Dictionary, distance_tiles: float
) -> float:
	var receptors := receptors_for(species)
	if receptors.is_empty():
		return 0.0
	var sensitivity: Dictionary = receptors["sensitivity"]
	var response: Dictionary = receptors["response"]
	var total := 0.0
	for molecule in mixture:
		total += (
			float(mixture[molecule])
			* float(sensitivity.get(molecule, 0.0))
			* float(response.get(molecule, 0.0))
		)
	return total * dilution(distance_tiles)
