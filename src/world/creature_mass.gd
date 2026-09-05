extends RefCounted

## Real average adult body mass, kilograms, per creature species -- see
## docs/concept/soil_fauna.md "Crushed underfoot: weight-emergent worm
## mortality". The mass term the worm-crush momentum calculation
## (EarthwormPatch.is_crushed_by) reads: real weight is what actually
## separates "a mouse steps here, nothing happens" from "a horse steps
## here, the worm dies" -- the calibration example this whole mechanic
## exists to satisfy.

const AnimalAnatomy = preload("res://src/rendering/animal_anatomy.gd")
const StoneSize = preload("res://src/world/stone_size.gd")

## The player's own mass reuses StoneSize's already-established human
## reference directly, rather than a second, independent guess.
const PLAYER_MASS_KG := StoneSize.AVERAGE_BODY_MASS_KG

## Real average adult body mass, kilograms, for every REAL (non-mythical)
## AnimalAnatomy species -- a commonly-cited reference figure for that
## real animal, never an invented number. Deliberately does NOT cover the
## purely mythical world bosses (lindwurm/rubezahl/nyx/krampus/squallmaw/
## coilnecca/champ/kraken) -- there is no real animal to cite a mass for,
## so those fall back to _mass_from_world_scale instead (see
## mass_kg_for).
const _REAL_MASS_KG := {
	"mouse": 0.02,
	"squirrel": 0.5,
	"arctic_fox": 3.5,
	"venomous_snake": 5.0,
	"nonvenomous_snake": 5.0,
	"jackal": 10.0,
	"lynx": 18.0,
	"wolf": 40.0,
	"predator": 40.0,  # generic predator build -- wolf-scale reference
	"goat": 60.0,
	"mountain_lion": 60.0,
	"deer": 70.0,
	"herbivore": 70.0,  # generic herbivore build -- deer-scale reference
	"sheep": 80.0,
	"boar": 90.0,
	"jaguar": 90.0,
	"reindeer": 150.0,
	"lion": 180.0,
	"tapir": 250.0,
	"bear": 300.0,
	"horse": 500.0,
	"camel": 500.0,
}

## The real land mammal this table anchors its mythical-species fallback
## against: a species with BOTH a real cited mass above and a real
## AnimalAnatomy world_scale, so the ratio between them is a real number,
## not an assumption.
const _FALLBACK_ANCHOR_SPECIES := "deer"


## `species`'s own real body mass, kilograms. A tabulated real species
## returns its own cited figure directly. Anything else (today: only the
## mythical world bosses, which have no real animal to cite a mass for at
## all, plus any future species this table hasn't caught up with yet)
## falls back to that species' own AnimalAnatomy.world_scale, CUBED
## against the anchor species' real mass/scale ratio -- mass follows
## volume, which follows the cube of a linear dimension, the identical
## reasoning StoneSize.mass_kg_for already uses to turn a stone's own
## diameter into a real mass. Deliberately NOT used for the tabulated
## real species above: world_scale is tuned for on-screen legibility, not
## real mass ratios (verified directly -- cubing alone would put a
## "horse" under 150kg, nothing like its real ~500kg), so only species
## with no real reference at all use this derived approximation.
static func mass_kg_for(species: String) -> float:
	if _REAL_MASS_KG.has(species):
		return _REAL_MASS_KG[species]
	return _mass_from_world_scale(species)


static func _mass_from_world_scale(species: String) -> float:
	var anchor_scale: float = AnimalAnatomy.profile_for(_FALLBACK_ANCHOR_SPECIES).world_scale
	var species_scale: float = AnimalAnatomy.profile_for(species).world_scale
	var anchor_mass: float = _REAL_MASS_KG[_FALLBACK_ANCHOR_SPECIES]
	var reference_mass_at_scale_one := anchor_mass / (anchor_scale * anchor_scale * anchor_scale)
	return reference_mass_at_scale_one * (species_scale * species_scale * species_scale)
