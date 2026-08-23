extends RefCounted

## The flowering plants a meadow can grow (see docs/concept/flora.md#
## flowering-plants-scent-and-pollinators).
##
## Grassland previously got a few flat flower pixels baked into its tile art
## (ProceduralTerrainSprite._paint_flowers) -- decoration with no species, no
## season, and nothing in the world that reacted to it. These are real
## species: each blooms in its own window, and advertises itself with its own
## scent strength (see ScentField).
##
## Colour and scent are deliberately INDEPENDENT axes. A tulip is visually
## loud but faint to smell; a rose is the strongest scent in the roster. That
## keeps "the prettiest meadow" and "the meadow bees actually want" from
## being the same trivial thing.
##
## Pure data + lookups, no RandomNumberGenerator and no node access, so the
## whole roster is testable offline.

## Bloom seasons use the same names SeasonCycle reports, so a caller can pass
## its current season straight through without translating.
const SPECIES := {
	# Earliest bloomer -- the first pollinator food of the year, low and
	# modest, but the only thing on offer when it flowers.
	"crocus": {
		"bloom": ["winter", "spring"],
		"color": Color(0.62, 0.44, 0.85),
		"tints": [
			Color(0.62, 0.44, 0.85),
			Color(0.96, 0.95, 0.98),
			Color(0.96, 0.79, 0.24),
			Color(0.78, 0.68, 0.92),
			Color(0.45, 0.28, 0.72),
		],
		"scent": 0.5,
		"height_cm": 10.0,
	},
	# Showy colour, comparatively weak scent -- true to life: tulips
	# advertise visually rather than aromatically.
	"tulip": {
		"bloom": ["spring"],
		"color": Color(0.9, 0.24, 0.3),
		"tints": [
			Color(0.9, 0.24, 0.3),
			Color(0.97, 0.82, 0.22),
			Color(0.95, 0.55, 0.72),
			Color(0.97, 0.96, 0.94),
			Color(0.95, 0.5, 0.16),
			Color(0.53, 0.17, 0.45),
		],
		"scent": 0.35,
		"height_cm": 40.0,
	},
	# The strongest scent in the roster and the anchor of a mature summer
	# meadow.
	"rose": {
		"bloom": ["summer"],
		"color": Color(0.86, 0.16, 0.32),
		"tints": [
			Color(0.86, 0.16, 0.32),
			Color(0.95, 0.6, 0.72),
			Color(0.97, 0.96, 0.93),
			Color(0.97, 0.85, 0.4),
			Color(0.96, 0.55, 0.45),
		],
		"scent": 1.0,
		"height_cm": 55.0,
	},
	# Long mid-season bloom: the workhorse nectar source that keeps
	# pollinators resident between the showier species.
	"lavender": {
		"bloom": ["summer", "autumn"],
		"color": Color(0.55, 0.42, 0.82),
		"tints": [
			Color(0.55, 0.42, 0.82),
			Color(0.72, 0.63, 0.9),
			Color(0.42, 0.3, 0.68),
			Color(0.93, 0.92, 0.96),
		],
		"scent": 0.85,
		"height_cm": 50.0,
		"stems": 5,
	},
	# The lawn daisy: low, white, yellow-eyed, and in flower for most of the
	# year -- which makes it the reliable fallback forage when the showier
	# species are out of season.
	"daisy": {
		"bloom": ["spring", "summer", "autumn"],
		"color": Color(0.97, 0.97, 0.93),
		"tints": [
			Color(0.97, 0.97, 0.93),
			Color(0.97, 0.88, 0.92),
			Color(0.96, 0.9, 0.62),
		],
		"scent": 0.35,
		"height_cm": 12.0,
	},
	# The tall one. Stands eye to eye with the player, which is what makes it
	# worth having: every other species is an accent underfoot, and a stand of
	# these is something you walk INTO rather than over. Faint scent for its
	# size -- sunflowers trade on being seen, not smelled.
	"sunflower": {
		"bloom": ["summer", "autumn"],
		"color": Color(0.97, 0.76, 0.15),
		"tints": [
			Color(0.97, 0.76, 0.15),
			Color(0.95, 0.62, 0.12),
			Color(0.98, 0.88, 0.35),
			Color(0.76, 0.42, 0.14),
		],
		"scent": 0.3,
		"height_cm": 200.0,
	},
	"clover": {
		"bloom": ["spring", "summer", "autumn"],
		"color": Color(0.95, 0.95, 0.9),
		"tints": [
			Color(0.95, 0.95, 0.9),
			Color(0.9, 0.6, 0.72),
			Color(0.85, 0.42, 0.55),
		],
		"scent": 0.6,
		"height_cm": 15.0,
		"stems": 3,
	},
}

## ## On stature
##
## `height_cm` is what the plant really is: a crocus is ankle-high at 10cm, a
## lavender spike stands at 50. Real measurements rather than invented units,
## so adding a species is a question about the plant and not about the
## renderer -- a sunflower is simply 200 and needs nothing else.
##
## ProceduralFlowerSprite turns these into world sizes against the PLAYER's
## height, which is the yardstick everything else in this world is read
## against. They were previously expressed as fractions of a tile and sized
## against grass alone, which let a tulip drift to 72% of the player's height
## and stand chest-high on the hero.

## ## On variety
##
## A species is not one colour. Crocuses come up purple, white, yellow and
## lilac from the same bed, and a tulip is the classic case of a species bred
## into a whole shelf of colours -- a meadow where every crocus is the
## identical purple reads as copy-paste rather than as planting.
##
## `tints` lists what a species can come up as, and each plant picks one from
## its OWN seed, so a flower keeps its colour for life rather than flickering
## between varieties per frame. The canonical `color` stays first in the list:
## it remains the species' identity for anything that wants "the colour of a
## rose" without caring which rose.
##
## Variety is colour and nothing else. A white tulip is exactly as tall and
## exactly as fragrant as a red one -- scent and stature are the species'
## business, and letting a tint change them would make "which colour did this
## one roll" a hidden gameplay variable.

const IDS: Array[String] = [
	"crocus", "tulip", "rose", "lavender", "clover", "daisy", "sunflower"
]

## Fail-safe for an unknown id, matching this codebase's `.get(x, default)`
## convention elsewhere -- an odd id yields a plain, faintly-scented bloom
## rather than crashing the field.
const _FALLBACK := {
	"bloom": ["spring", "summer"],
	"color": Color(0.85, 0.85, 0.8),
	"tints": [Color(0.85, 0.85, 0.8)],
	"scent": 0.4,
	"height_cm": 25.0,
}


func _init() -> void:
	pass


static func profile_for(species_id: String) -> Dictionary:
	return SPECIES.get(species_id, _FALLBACK)


static func is_in_bloom(species_id: String, season: String) -> bool:
	var bloom: Array = profile_for(species_id)["bloom"]
	return bloom.has(season)


## How strongly this species advertises itself right now -- its scent while
## in bloom, and exactly zero otherwise. Out-of-season plants are still
## present in the world; they just stop calling to pollinators, so a meadow's
## pull rises and falls across the year instead of being constant.
static func scent_strength(species_id: String, season: String) -> float:
	if not is_in_bloom(species_id, season):
		return 0.0
	return float(profile_for(species_id)["scent"])


static func color_for(species_id: String) -> Color:
	return profile_for(species_id)["color"]


## Every colour this species can come up in. Falls back to the canonical
## colour alone, so a species added later without a variety list still
## renders rather than coming up empty.
static func tints_for(species_id: String) -> Array:
	var profile := profile_for(species_id)
	var tints: Array = profile.get("tints", [])
	if tints.is_empty():
		return [profile["color"]]
	return tints


## The colour of ONE plant. Derived from the plant's own seed, so it is fixed
## for that plant's life -- a flower does not change colour while you watch
## it -- while a bed of them comes up mixed.
## How many separate stems this plant puts up.
##
## Lavender does not grow as a single stem -- it is a bush of many spikes, and
## drawing one lone spike per plant made a lavender bed read as scattered
## twigs. Clover likewise grows as a low mat of heads rather than one flower.
## Everything else is a single stem, which is the default.
static func stems_for(species_id: String) -> int:
	return int(profile_for(species_id).get("stems", 1))


## Whether this species grows as a bush rather than on one stem.
static func is_bush(species_id: String) -> bool:
	return stems_for(species_id) > 1


## This species' real height in centimetres.
static func height_cm_for(species_id: String) -> float:
	return float(profile_for(species_id)["height_cm"])


## The tallest species in the roster, which the renderer scales everything
## else against. Computed rather than written down, so adding a taller species
## cannot leave a stale constant behind.
static func tallest_height_cm() -> float:
	var tallest := 0.0
	for species_id in IDS:
		tallest = maxf(tallest, height_cm_for(species_id))
	return tallest


static func tint_for(species_id: String, seed_value: int) -> Color:
	var tints := tints_for(species_id)
	return tints[absi(hash(seed_value * 31 + 17)) % tints.size()]
