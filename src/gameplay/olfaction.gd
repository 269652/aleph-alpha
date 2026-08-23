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

## The molecules worth modelling: the ones that decide foraging.
const SUGAR := "sugar"  # ripe fruit, nectar
const DECAY := "decay"  # rotting fruit, carrion
const GREEN := "green"  # leaves, cut grass, foliage
const MUSK := "musk"  # animals themselves
const SMOKE := "smoke"  # fire

const MOLECULES: Array[String] = [SUGAR, DECAY, GREEN, MUSK, SMOKE]

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
		"sensitivity": {SUGAR: 1.0, DECAY: 0.9, GREEN: 0.5, MUSK: 0.6, SMOKE: 0.8},
		"response": {SUGAR: 1.0, DECAY: 0.3, GREEN: 0.2, MUSK: -0.1, SMOKE: -1.0},
	},
	# Browser: wants fruit and foliage, avoids anything dead.
	"deer": {
		"sensitivity": {SUGAR: 0.8, DECAY: 0.7, GREEN: 1.0, MUSK: 0.9, SMOKE: 0.9},
		"response": {SUGAR: 0.8, DECAY: -0.6, GREEN: 0.9, MUSK: -0.5, SMOKE: -1.0},
	},
	# Grazer: it is the grass it is after.
	"horse": {
		"sensitivity": {SUGAR: 0.7, DECAY: 0.6, GREEN: 1.0, MUSK: 0.7, SMOKE: 0.9},
		"response": {SUGAR: 0.6, DECAY: -0.5, GREEN: 1.0, MUSK: -0.2, SMOKE: -1.0},
	},
	# Fruit-eating bird: takes ripe fruit, ignores what has gone over.
	"robin": {
		"sensitivity": {SUGAR: 0.9, DECAY: 0.4, GREEN: 0.3, MUSK: 0.5, SMOKE: 0.7},
		"response": {SUGAR: 1.0, DECAY: -0.2, GREEN: 0.1, MUSK: -0.3, SMOKE: -0.8},
	},
	# The one that wants what everything else avoids.
	"fly": {
		"sensitivity": {SUGAR: 0.5, DECAY: 1.0, GREEN: 0.1, MUSK: 0.6, SMOKE: 0.2},
		"response": {SUGAR: 0.3, DECAY: 1.0, GREEN: 0.0, MUSK: 0.2, SMOKE: -0.4},
	},
}


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
	if not RECEPTORS.has(species):
		return 0.0
	var sensitivity: Dictionary = RECEPTORS[species]["sensitivity"]
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
	if not RECEPTORS.has(species):
		return 0.0
	var sensitivity: Dictionary = RECEPTORS[species]["sensitivity"]
	var response: Dictionary = RECEPTORS[species]["response"]
	var total := 0.0
	for molecule in mixture:
		total += (
			float(mixture[molecule])
			* float(sensitivity.get(molecule, 0.0))
			* float(response.get(molecule, 0.0))
		)
	return total * dilution(distance_tiles)
