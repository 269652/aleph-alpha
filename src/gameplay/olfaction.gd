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
## Since docs/concept/ethogram.md the receptors live in the species record
## (Ethogram.SPECIES) rather than here, so a species is data in one place;
## what this file used to call `response` is the ethogram's `valence`. This
## file keeps the PHYSICS of smell -- what things emit, and how a smell thins
## with range -- and reads an animal's expressed receptors through
## Ethogram.express, which is also how an individual's receptor genes reach
## the verdict: pass a genome and the answer is that individual's. The
## molecule names are the ethogram's smell channels, re-exported so no caller
## of this API changes.
##
## Pure and engine-free: this says what a thing emits and what an animal makes
## of it. Walking toward it is the caller's job.

const Ethogram = preload("res://src/gameplay/ethogram.gd")
const Affinity = preload("res://src/gameplay/affinity.gd")

## The molecules worth modelling: the ones that decide foraging.
const SUGAR := Ethogram.SUGAR  # ripe fruit, nectar
const DECAY := Ethogram.DECAY  # rotting fruit, carrion
const GREEN := Ethogram.GREEN  # leaves, cut grass, foliage
const MUSK := Ethogram.MUSK  # animals themselves
const SMOKE := Ethogram.SMOKE  # fire

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
## Ethogram.SPECIES, expressed per individual by Ethogram.express: a species'
## `sensitivity` is how well it DETECTS a molecule at all, its `valence` what
## it makes of detecting it, negative being driven off. They are separate on
## purpose: an animal can be keenly aware of something it wants nothing to do
## with, which is what makes a repellent work rather than merely being
## invisible. A receptor gene (`receptor_<molecule>` in the genome) scales
## that individual's sensitivity; valence is the species' innate wiring.
##
## The species template is expressed once and cached, since every sniff of
## every source asks for it; an individual genome is expressed on demand.
static var _template_cache: Dictionary = {}


## How faint a smell is at this range, 1 at the source and 0 beyond reach.
static func dilution(distance_tiles: float) -> float:
	var distance := maxf(distance_tiles, 0.0)
	if distance >= MAX_RANGE_TILES:
		return 0.0
	return pow(1.0 - distance / MAX_RANGE_TILES, DILUTION_POWER)


## How LOUD this mixture is to this animal -- how much it notices, regardless
## of whether it likes it.
static func perceived_strength(
	species: String, mixture: Dictionary, distance_tiles: float, genome: Dictionary = {}
) -> float:
	var expressed := _expressed(species, genome)
	if expressed.is_empty():
		return 0.0
	return Affinity.loudness(mixture, expressed["sensitivity"]) * dilution(distance_tiles)


## What this animal makes of the mixture: positive draws it in, negative drives
## it off, near zero is noise.
##
## The same sum as perceived_strength but weighted by VALENCE too, so a
## rotting fruit can be extremely loud to a deer and still repel it.
static func attraction_to(
	species: String, mixture: Dictionary, distance_tiles: float, genome: Dictionary = {}
) -> float:
	var expressed := _expressed(species, genome)
	if expressed.is_empty():
		return 0.0
	return (
		Affinity.pull(mixture, expressed["sensitivity"], expressed["valence"])
		* dilution(distance_tiles)
	)


static func _expressed(species: String, genome: Dictionary) -> Dictionary:
	if not genome.is_empty():
		return Ethogram.express(species, genome)
	if not _template_cache.has(species):
		_template_cache[species] = Ethogram.express(species)
	return _template_cache[species]
