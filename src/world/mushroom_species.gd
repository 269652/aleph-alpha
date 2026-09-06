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
## typically lethal), four real, commonly foraged edibles (Black Trumpet,
## Champignon, Chanterelle, Parasol), and -- added once real art surfaced
## for them -- one genuinely, often-fatally toxic species (Death Cap) plus
## its real, non-toxic lookalike (False Death Cap) -- see docs/concept/
## mushrooms.md's real-world grounding.
const IDS: Array[String] = [
	"fly_agaric", "psylo", "black_trumpet", "champignon", "chanterelle", "parasol",
	"death_cap", "false_death_cap",
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
	"death_cap": {
		"display_name": "Death Cap",
		# A real Amanita phalloides cap is an eerie, muted olive-yellow-
		# green -- distinct from every other cap colour in the roster, the
		# same way its real toxicity is distinct from everything else here.
		"cap_color": Color(0.66, 0.68, 0.42),
	},
	"false_death_cap": {
		"display_name": "False Death Cap",
		# A real Amanita citrina cap reads as a paler, more uniform lemon-
		# yellow than Death Cap's more olive tone -- close enough to explain
		# the real confusion between them, distinct enough to still be its
		# own colour in this roster.
		"cap_color": Color(0.85, 0.82, 0.55),
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
## neither typically lethal in a modern medical context. Death Cap is the
## one exception: real amatoxin poisoning, often fatal without treatment --
## see MushroomToxin.severity_for's own doc comment for how much more
## severe it is rated than the other two). False Death Cap is deliberately
## NOT listed here despite its name and its real visual similarity to
## Death Cap: modern mycological consensus is that it is not itself
## seriously toxic (its real danger is being mistaken for something that
## is). The rest of the roster is real, commonly foraged edibles. An
## unlisted/unknown id defaults to false, matching this file's existing
## fallback convention.
const _TOXIC_SPECIES := {"fly_agaric": true, "psylo": true, "death_cap": true}

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
	# Both real Amanita, both genuinely mycorrhizal (never saprotrophic --
	# see is_saprotroph below). Death Cap classically oak-associated in its
	# native range (the same real partnership Black Trumpet/Chanterelle
	# already use "acorn" for); False Death Cap classically conifer-
	# associated (the same real partnership Fly Agaric -- also Amanita --
	# already uses "pine" for).
	"death_cap": "acorn",
	"false_death_cap": "pine",
}
# psylo/champignon/parasol deliberately absent -- see is_saprotroph below:
# all three are real grassland/pasture/forest-edge saprotrophs, not
# mycorrhizal with any tree.

static func host_tree_for(species_id: String) -> String:
	return String(_HOST_TREE_BY_SPECIES.get(species_id, ""))


static func is_saprotroph(species_id: String) -> bool:
	return host_tree_for(species_id).is_empty()


## Real biome eligibility per species (see docs/concept/mushrooms.md).
## Mycorrhizal species (a non-empty host_tree_for) only ever grow where
## their real host tree does -- forest/rainforest. Saprotrophs vary by
## real species rather than sharing one blanket rule: Champignon (Agaricus
## campestris, the real "field mushroom") is specifically a pasture/
## grassland species, genuinely uncommon in deep forest -- unlike
## Psilocybe/Parasol, both real mixed-habitat species (grassland AND
## forest-edge/leaf-litter), kept eligible in both. An unlisted id falls
## back to forest/rainforest only, matching a mycorrhizal default.
const _BIOMES_BY_SPECIES := {
	"fly_agaric": ["forest", "rainforest"],
	"black_trumpet": ["forest", "rainforest"],
	"chanterelle": ["forest", "rainforest"],
	"champignon": ["grassland"],
	"psylo": ["forest", "rainforest", "grassland"],
	"parasol": ["forest", "rainforest", "grassland"],
	# Both real mycorrhizal Amanita, same as fly_agaric/black_trumpet/
	# chanterelle above -- forest/rainforest only, matching their real host
	# trees (see _HOST_TREE_BY_SPECIES).
	"death_cap": ["forest", "rainforest"],
	"false_death_cap": ["forest", "rainforest"],
}
const _FALLBACK_BIOMES := ["forest", "rainforest"]


static func allows_biome(species_id: String, biome: String) -> bool:
	var biomes: Array = _BIOMES_BY_SPECIES.get(species_id, _FALLBACK_BIOMES)
	return biomes.has(biome)


