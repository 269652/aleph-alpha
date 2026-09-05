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
##
## Roster revised (see mushrooms.md's own merge note) to match the real
## illustrated art actually delivered -- Fly Agaric, Psilocybe, Black
## Trumpet, Champignon, Chanterelle, Parasol -- replacing the originally
## designed Death Cap/Porcini/Puffball, which no art exists for.

## Two real psychoactive species (Fly Agaric, Psilocybe -- neither
## typically lethal) and four real, commonly foraged edibles (Black
## Trumpet, Champignon, Chanterelle, Parasol) -- see docs/concept/
## mushrooms.md's real-world grounding.
const IDS: Array[String] = [
	"fly_agaric", "psylo", "black_trumpet", "champignon", "chanterelle", "parasol"
]

const SPECIES := {
	"fly_agaric": {
		"display_name": "Fly Agaric",
		# The iconic vivid red cap.
		"cap_color": Color(0.78, 0.14, 0.1),
	},
	"psylo": {
		"display_name": "Psilocybe",
		# A real Psilocybe cap is a plain, unremarkable tan/buff -- the
		# understated colour is part of why it's so easily overlooked in a
		# real pasture.
		"cap_color": Color(0.62, 0.5, 0.34),
	},
	"black_trumpet": {
		"display_name": "Black Trumpet",
		# A real Black Trumpet reads as dark blackish-brown/grey -- among
		# the few genuinely dark-capped species foraged for food.
		"cap_color": Color(0.22, 0.19, 0.17),
	},
	"champignon": {
		"display_name": "Champignon",
		# The common cultivated/meadow mushroom -- a plain pale cream.
		"cap_color": Color(0.88, 0.84, 0.74),
	},
	"chanterelle": {
		"display_name": "Chanterelle",
		# A real chanterelle is a vivid egg-yolk gold.
		"cap_color": Color(0.92, 0.68, 0.12),
	},
	"parasol": {
		"display_name": "Parasol",
		# A real Parasol's cap is a warm tan scattered with darker scales.
		"cap_color": Color(0.72, 0.58, 0.4),
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


## Whether `species_id` is genuinely toxic/psychoactive (see docs/concept/
## mushrooms.md -- Fly Agaric and Psilocybe are real, psychoactive species,
## neither typically lethal in a modern medical context, unlike the
## originally-designed roster's Death Cap). The rest of the roster is real,
## commonly foraged edibles. An unlisted/unknown id defaults to false,
## matching this file's existing fallback convention.
const _TOXIC_SPECIES := {"fly_agaric": true, "psylo": true}

static func is_toxic(species_id: String) -> bool:
	return _TOXIC_SPECIES.has(species_id)


## The real tree species (a tree_species.gd id) this mushroom is
## mycorrhizal with -- it fruits only where that host actually grows. An
## unlisted id returns "", meaning a real saprotroph: it decomposes litter
## directly and needs no living host tree at all.
const _HOST_TREE_BY_SPECIES := {
	"fly_agaric": "pine",
	"black_trumpet": "acorn",
	"chanterelle": "acorn",
}
# psylo/champignon/parasol deliberately absent -- see is_saprotroph below:
# all three are real grassland/pasture/forest-edge saprotrophs, not
# mycorrhizal with any tree.

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
const MUSHROOMS_TO_LEARN_IDENTIFICATION := 6
