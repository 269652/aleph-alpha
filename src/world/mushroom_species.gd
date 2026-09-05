extends RefCounted

## Named wild mushroom species (see docs/concept/mushrooms.md's Species
## roster).
##
## Mirrors tree_species.gd's exact shape: an ordered IDS array, a SPECIES
## profile dict for real per-species data (display name, cap colour), and
## small per-trait lookup dicts for booleans (is_toxic) and per-species
## strings (host_tree_for) rather than fields folded into the profile --
## matching TreeSpecies.is_nut/needs_pollinators_for's own "one small dict
## per trait, an unlisted id falls back cleanly" convention, so a trait
## split can never silently drift out of sync with an index cutoff into
## IDS.
##
## Pure data + lookups, no RandomNumberGenerator and no node access, same
## as tree_species.gd/flower_species.gd.

## Two real toxic species (Fly Agaric, Death Cap) and three real, commonly
## foraged edibles (Chanterelle, Porcini, Puffball) -- see
## docs/concept/mushrooms.md's real-world grounding.
const IDS: Array[String] = ["fly_agaric", "death_cap", "chanterelle", "porcini", "puffball"]

const SPECIES := {
	"fly_agaric": {
		"display_name": "Fly Agaric",
		# The iconic vivid red cap.
		"cap_color": Color(0.78, 0.14, 0.1),
	},
	"death_cap": {
		"display_name": "Death Cap",
		# Real Death Caps are understated -- a pale, dull greenish-yellow,
		# not an obviously dangerous colour. That understatement is the
		# real reason it kills people who mistake it for something safe.
		"cap_color": Color(0.72, 0.76, 0.52),
	},
	"chanterelle": {
		"display_name": "Chanterelle",
		# A real chanterelle is a vivid egg-yolk gold.
		"cap_color": Color(0.92, 0.68, 0.12),
	},
	"porcini": {
		"display_name": "Porcini",
		"cap_color": Color(0.55, 0.38, 0.2),
	},
	"puffball": {
		"display_name": "Puffball",
		# A real puffball is a plain, near-white ball.
		"cap_color": Color(0.92, 0.9, 0.82),
	},
}

## Fail-safe for an unrecognized id, matching tree_species.gd's `.get(x,
## default)` convention -- a plain, nondescript, non-toxic mushroom rather
## than a crash.
const _FALLBACK := {
	"display_name": "Mushroom",
	"cap_color": Color(0.55, 0.45, 0.35),
}


func _init() -> void:
	pass


static func profile_for(species_id: String) -> Dictionary:
	return SPECIES.get(species_id, _FALLBACK)


static func display_name_for(species_id: String) -> String:
	return String(profile_for(species_id)["display_name"])


static func cap_color_for(species_id: String) -> Color:
	return profile_for(species_id)["cap_color"]


## Whether `species_id` is genuinely toxic (see docs/concept/mushrooms.md --
## Fly Agaric and Death Cap are real, distinctly dangerous species; the rest
## of the roster is real, commonly foraged edibles). An unlisted/unknown id
## defaults to false, matching this file's existing fallback convention.
const _TOXIC_SPECIES := {"fly_agaric": true, "death_cap": true}

static func is_toxic(species_id: String) -> bool:
	return _TOXIC_SPECIES.has(species_id)


## The real tree species (a tree_species.gd id) this mushroom is
## mycorrhizal with -- it fruits only where that host actually grows. An
## unlisted id (puffball) returns "", meaning a real saprotroph: it
## decomposes litter directly and needs no living host tree at all.
const _HOST_TREE_BY_SPECIES := {
	"fly_agaric": "pine",
	"death_cap": "acorn",
	"chanterelle": "acorn",
	"porcini": "pine",
}
# puffball deliberately absent -- see is_saprotroph below.

static func host_tree_for(species_id: String) -> String:
	return String(_HOST_TREE_BY_SPECIES.get(species_id, ""))


static func is_saprotroph(species_id: String) -> bool:
	return host_tree_for(species_id).is_empty()


## How many real mushrooms (any species, edible or toxic) a player must eat
## before they've learned to identify them on sight (see Player.
## knows_mushrooms) -- real foraging knowledge comes from direct field
## experience, not a purchased skill point. Equal to the roster's own size
## (one real encounter per species) rather than an unrelated eyeballed
## number -- pinned by test_identification_threshold_matches_the_roster_
## size, since GDScript's cross-script constant resolution can't fold
## `IDS.size()` directly into a const here.
const MUSHROOMS_TO_LEARN_IDENTIFICATION := 5
