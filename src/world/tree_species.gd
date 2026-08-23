extends RefCounted

## Named fruit/nut tree species (see docs/concept/flora.md#named-fruit-and-nut-tree-species).
##
## Before this, a tree's "species" was nothing more than TreeGenome.species_bias
## -- a single continuous 0 (nut) .. 1 (fruit) float, bucketed into 4 anonymous
## canopy-colour buckets in tree_renderer.gd with no name a player could ever
## point at. This gives that same spectrum three real, named species: Walnut
## anchors the nut end, Cherry and Apple the fruit end (species_bias already
## treats fruit-vs-nut as one axis -- see tree_genome.gd -- so a walnut is
## simply "nut-leaning" rather than needing its own trait dimension).
##
## Deliberately still a PURE function of species_bias, not stored per-tree
## state -- matching the "no stored genome, position derives everything"
## idiom TreeGenome/ForageScheduler/TreeRenderer already use throughout this
## codebase: the same tree at the same position always names the same
## species, with nothing new to persist or desync.
##
## Real-world grounding for the two per-species multipliers FruitingModel
## consumes (see fruiting_model.gd):
## - Cherries ripen fast (bloom to ripe fruit in as little as 2 months) and
##   bear prolifically -- lots of small, fast fruit.
## - Walnuts ripen slow (a long single-season husk-to-kernel process,
##   typically into autumn) and bear a comparatively small, high-value crop.
## - Apples sit in between -- a solid, moderately fast, heavy-bearing
##   orchard fruit -- and keep the values the original undifferentiated
##   "fruit-leaning tree" already had, so the fruit-anchor bucket's baseline
##   behaviour is unchanged.

## Pure data + lookups, no RandomNumberGenerator and no node access, matching
## flower_species.gd's shape.

## species_bias below this is Walnut (the nut anchor); at/above it and below
## CHERRY_MAX_BIAS is Cherry; at/above CHERRY_MAX_BIAS is Apple. An even
## three-way split of the 0..1 spectrum -- there's no real-world reason to
## weight one species' band wider than another's.
##
## IDS is ordered along that spectrum, NUT first and fruit last, and the bias
## range is split evenly between them. It was three hardcoded thresholds; with
## six species that would have been five, each needing renaming whenever the
## roster changed, so the bands are computed from the list instead. Adding a
## species now means adding it to IDS in its right place on the spectrum.
const IDS: Array[String] = ["pine", "acorn", "hazelnut", "walnut", "cherry", "apple"]

## Kept for callers that still speak in terms of the old thresholds.
const WALNUT_MAX_BIAS := 4.0 / 6.0
const CHERRY_MAX_BIAS := 5.0 / 6.0

const SPECIES := {
	# Evergreen, and the only conifer in the roster: its canopy never goes
	# bare, and its crop is a cone rather than a fruit.
	"pine": {
		"display_name": "Pine Nut",
		"canopy_color": Color(0.09, 0.32, 0.18),
		"fruit_color": Color(0.42, 0.28, 0.14),
		# A poor crop for the work, which is what pine nuts are.
		"yield_multiplier": 0.55,
		"ripening_multiplier": 1.8,
	},
	# Oak. Named for its crop like every other entry here -- the species id
	# doubles as the item id its tree drops.
	"acorn": {
		"display_name": "Acorn",
		"canopy_color": Color(0.16, 0.40, 0.14),
		"fruit_color": Color(0.55, 0.35, 0.15),
		"yield_multiplier": 1.5,
		"ripening_multiplier": 1.5,
	},
	# Hazel. The quickest of the nut trees to come into crop.
	"hazelnut": {
		"display_name": "Hazelnut",
		"canopy_color": Color(0.24, 0.52, 0.18),
		"fruit_color": Color(0.52, 0.30, 0.13),
		"yield_multiplier": 1.0,
		"ripening_multiplier": 1.1,
	},
	"walnut": {
		"display_name": "Walnut",
		# A deeper, duller green than the other two -- real walnut canopies
		# read darker than an orchard fruit tree's.
		"canopy_color": Color(0.12, 0.42, 0.12),
		# The husk, not the kernel -- a dropped walnut on the ground is still
		# in its green-brown hull.
		"fruit_color": Color(0.42, 0.34, 0.16),
		"yield_multiplier": 0.75,
		"ripening_multiplier": 1.4,
	},
	"cherry": {
		"display_name": "Cherry",
		"canopy_color": Color(0.22, 0.58, 0.2),
		"fruit_color": Color(0.75, 0.08, 0.18),
		"yield_multiplier": 1.3,
		"ripening_multiplier": 0.65,
	},
	"apple": {
		"display_name": "Apple",
		"canopy_color": Color(0.32, 0.62, 0.18),
		"fruit_color": Color(0.85, 0.15, 0.1),
		"yield_multiplier": 1.1,
		"ripening_multiplier": 1.0,
	},
}

## Fail-safe for an unrecognized id, matching flower_species.gd's `.get(x,
## default)` convention -- an odd id yields a plain, green, baseline-yielding
## tree rather than crashing.
const _FALLBACK := {
	"display_name": "Tree",
	"canopy_color": Color(0.2, 0.55, 0.2),
	"fruit_color": Color(0.8, 0.2, 0.15),
	"yield_multiplier": 1.0,
	"ripening_multiplier": 1.0,
}


func _init() -> void:
	pass


## The named species a tree at this species_bias (TreeGenome.species_bias,
## 0=nut..1=fruit) resolves to. Pure and total: every bias in [0, 1] maps to
## exactly one of IDS.
static func species_for_bias(bias: float) -> String:
	var index := int(clampf(bias, 0.0, 0.9999) * float(IDS.size()))
	return IDS[clampi(index, 0, IDS.size() - 1)]


static func profile_for(species_id: String) -> Dictionary:
	return SPECIES.get(species_id, _FALLBACK)


static func display_name_for(species_id: String) -> String:
	return String(profile_for(species_id)["display_name"])


static func canopy_color_for(species_id: String) -> Color:
	return profile_for(species_id)["canopy_color"]


static func fruit_color_for(species_id: String) -> Color:
	return profile_for(species_id)["fruit_color"]


## Scales FruitingModel.crop_potential -- how large a crop this species bears
## relative to the genome's raw fruit_yield trait.
static func yield_multiplier_for(species_id: String) -> float:
	return float(profile_for(species_id)["yield_multiplier"])


## Scales FruitingModel's bearing-cycle length -- below 1 ripens faster than
## the genome's raw maturity_time alone would suggest, above 1 slower.
static func ripening_multiplier_for(species_id: String) -> float:
	return float(profile_for(species_id)["ripening_multiplier"])
