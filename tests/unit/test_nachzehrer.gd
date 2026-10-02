extends GutTest

## docs/concept/monsters.md, entry 11: the Nachzehrer -- a German-folklore
## corpse-eating revenant, the roster's second biped and its first
## predator-role addition to grassland/forest's own pools. What is asserted
## here is that it exists as a REAL SPECIES: every table a species needs, a
## real (sparse, like every other named predator) niche in a real biome's
## pool, and its own bite. Its "prefers carrion over a live target"
## behaviour is pinned separately (see test_carrion_preference.gd and the
## CreatureMarker wiring test alongside it).

const CreatureInfo = preload("res://src/world/creature_info.gd")
const CreatureRenderer = preload("res://src/rendering/creature_renderer.gd")
const CreatureMass = preload("res://src/world/creature_mass.gd")
const AnimalAnatomy = preload("res://src/rendering/animal_anatomy.gd")
const ProceduralAnimalSprite = preload("res://src/rendering/procedural_animal_sprite.gd")
const ConsoleSpecies = preload("res://src/gameplay/console_species.gd")
const SpeciesBite = preload("res://src/gameplay/species_bite.gd")

const NACHZEHRER := "nachzehrer"
## An ordinary forest predator, to hold the newcomer against.
const REFERENCE := "wolf"


# -- it is a real species, not a special case -----------------------------

func test_it_is_defined_everywhere_an_ordinary_species_is():
	var tables := {
		"MAX_HEALTH_BY_SPECIES": CreatureInfo.MAX_HEALTH_BY_SPECIES,
		"MAX_STAMINA_BY_SPECIES": CreatureInfo.MAX_STAMINA_BY_SPECIES,
		"MAX_MANA_BY_SPECIES": CreatureInfo.MAX_MANA_BY_SPECIES,
		"DIET_BY_SPECIES": CreatureInfo.DIET_BY_SPECIES,
		"TEMPERAMENT_BY_SPECIES": CreatureInfo.TEMPERAMENT_BY_SPECIES,
	}
	for name in tables:
		var table: Dictionary = tables[name]
		assert_true(table.has(REFERENCE), "precondition: %s knows the reference" % name)
		assert_true(table.has(NACHZEHRER), "%s has no entry for the nachzehrer" % name)


func test_it_hunts():
	assert_true(bool(CreatureInfo.PREDATOR_SPECIES.get(NACHZEHRER, false)))
	assert_eq(CreatureInfo.TEMPERAMENT_BY_SPECIES[NACHZEHRER], CreatureInfo.AGGRESSIVE)


func test_it_has_a_body_the_renderer_can_draw():
	assert_true(AnimalAnatomy.has_profile(NACHZEHRER), "no anatomy profile")
	assert_true(AnimalAnatomy.profile_for(NACHZEHRER).get("biped", false), "should use the biped body plan")
	assert_true(ProceduralAnimalSprite.SPECIES_BASE_COLORS.has(NACHZEHRER), "no colour")
	assert_true(CreatureMass.knows(NACHZEHRER), "no mass -- the loot table would silently drop nothing for it")


func test_it_can_be_summoned_by_name():
	assert_eq(ConsoleSpecies.resolve(NACHZEHRER), NACHZEHRER, "/spawn and /arena must find it")


# -- it lives in the two biomes a real spawn can land in ---------------------

func test_it_lives_in_grassland_and_forest_and_nowhere_else():
	for biome in CreatureRenderer.PREDATOR_SPECIES_POOL_BY_BIOME:
		var pool: Array = CreatureRenderer.PREDATOR_SPECIES_POOL_BY_BIOME[biome]
		if biome in CreatureRenderer.SPAWN_REACHABLE_BIOMES:
			assert_true(
				pool.has(NACHZEHRER), "%s is spawn-reachable and should be able to produce a nachzehrer" % biome
			)
		else:
			assert_false(pool.has(NACHZEHRER), "%s is not spawn-reachable; it could never be met there" % biome)


## Rare, like every other named predator in these two biomes' own pools --
## the dense, common fighter is the herbivore-role pool's own job (boar,
## goblin; see test_goblin.gd), not this one's.
func test_it_is_rarer_than_the_biomes_ordinary_predators():
	for biome in CreatureRenderer.SPAWN_REACHABLE_BIOMES:
		var pool: Array = CreatureRenderer.PREDATOR_SPECIES_POOL_BY_BIOME[biome]
		var mine := 0
		var others := 0
		for entry in pool:
			if String(entry) == NACHZEHRER:
				mine += 1
			else:
				others += 1
		assert_gt(others, mine, "%s's ordinary predators must still dominate the pool" % biome)


func test_it_has_its_own_bite_rather_than_the_fallback():
	assert_true(SpeciesBite.has_profile(NACHZEHRER), "a named monster with a generic bite is a reskin")


# -- it would rather eat than fight (CarrionPreference) ----------------------
#
# Every predator already notices carrion (CreatureMarker._scan_carrion_
# stimuli, docs/concept/carrion.md's opportunistic-scavenging gap) -- a
# Nachzehrer is the first one for which it outranks a live target. Driven
# directly against a bare CreatureMarker's own private filter, the same
# convention test_curupira.gd's _perceives_threats tests already use
# (CreatureBehavior.new()._perceives_threats(context)), rather than
# standing up a full scene + chunk manager for a pure stimulus transform.

const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const Ethogram = preload("res://src/gameplay/ethogram.gd")


func _stimulus(channel: String) -> Dictionary:
	return {"position": Vector2.ZERO, "features": {channel: 1.0}, "node": null}


func test_a_nachzehrer_drops_huntable_stimuli_when_carrion_is_present():
	var marker := CreatureMarker.new()
	add_child_autofree(marker)
	marker.info = CreatureInfo.new(NACHZEHRER, 1)
	var stimuli := [_stimulus(Ethogram.PLAYER), _stimulus(Ethogram.CARRION)]

	var filtered: Array = marker._carrion_preference_filter(stimuli)

	assert_eq(filtered.size(), 1, "only the carrion stimulus should remain")
	assert_true(filtered[0]["features"].has(Ethogram.CARRION))


func test_a_nachzehrer_with_no_carrion_present_is_unaffected():
	var marker := CreatureMarker.new()
	add_child_autofree(marker)
	marker.info = CreatureInfo.new(NACHZEHRER, 1)
	var stimuli := [_stimulus(Ethogram.PLAYER), _stimulus(Ethogram.FLESH)]

	var filtered: Array = marker._carrion_preference_filter(stimuli)

	assert_eq(filtered, stimuli, "nothing to prefer carrion over means nothing changes")


## Nothing about any OTHER species changes -- an ordinary predator still
## hunts right past a corpse, exactly as it always has.
func test_an_ordinary_predator_is_unaffected_even_with_carrion_present():
	var marker := CreatureMarker.new()
	add_child_autofree(marker)
	marker.info = CreatureInfo.new(REFERENCE, 1)
	var stimuli := [_stimulus(Ethogram.PLAYER), _stimulus(Ethogram.CARRION)]

	var filtered: Array = marker._carrion_preference_filter(stimuli)

	assert_eq(filtered, stimuli, "an ordinary predator's stimuli must be untouched")


func test_the_marker_really_uses_the_shared_rule():
	var source := FileAccess.get_file_as_string("res://src/rendering/creature_marker.gd")
	assert_true(
		source.contains("CarrionPreference.prefers_carrion"), "through the shared rule, not a hardcoded species check"
	)
