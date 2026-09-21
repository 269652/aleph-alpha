extends GutTest

## docs/concept/monsters.md, entry 5: the Curupira, the roster's Tier A
## hostile fauna -- a rainforest guardian whose aggro table is the ecosystem
## simulation itself.
##
## Its behaviour rule is pinned by test_ecological_grudge.gd. What is
## asserted here is that it exists as a REAL SPECIES: every table a species
## needs, a real niche in a real biome's pool, and its own bite -- so that
## nothing about it is a special case bolted onto the side of the roster.

const CreatureInfo = preload("res://src/world/creature_info.gd")
const CreatureRenderer = preload("res://src/rendering/creature_renderer.gd")
const AnimalAnatomy = preload("res://src/rendering/animal_anatomy.gd")
const ProceduralAnimalSprite = preload("res://src/rendering/procedural_animal_sprite.gd")
const ConsoleSpecies = preload("res://src/gameplay/console_species.gd")
const SpeciesBite = preload("res://src/gameplay/species_bite.gd")
const EcologicalGrudge = preload("res://src/gameplay/ecological_grudge.gd")

const CURUPIRA := "curupira"
## An ordinary rainforest predator, to hold the newcomer against.
const REFERENCE := "jaguar"


# -- it is a real species, not a special case -----------------------------

## Every table the reference species appears in, the newcomer appears in
## too. Two-way rather than a hand-listed set, so a table added later cannot
## silently leave this species half-defined.
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
		assert_true(table.has(CURUPIRA), "%s has no entry for the curupira" % name)


func test_it_hunts():
	assert_true(CreatureInfo.PREDATOR_SPECIES.has(CURUPIRA))
	assert_true(bool(CreatureInfo.PREDATOR_SPECIES[CURUPIRA]))
	assert_eq(CreatureInfo.TEMPERAMENT_BY_SPECIES[CURUPIRA], "aggressive")


## A guardian, not an apex predator: it must be a real threat without
## outclassing the biome's own top carnivore.
func test_it_is_a_real_threat_without_outclassing_the_biome():
	var health: float = CreatureInfo.MAX_HEALTH_BY_SPECIES[CURUPIRA]
	assert_gt(health, 0.0)
	assert_lt(
		health, CreatureInfo.MAX_HEALTH_BY_SPECIES[REFERENCE] * 2.0,
		"a folklore guardian is not a world boss"
	)


## It is a spirit of the forest, so it is the one predator with a real mana
## pool -- the roster's "not just a wolf with more health".
func test_it_carries_more_than_an_ordinary_animal():
	assert_gt(
		float(CreatureInfo.MAX_MANA_BY_SPECIES[CURUPIRA]),
		float(CreatureInfo.MAX_MANA_BY_SPECIES[REFERENCE]),
		"a forest spirit is not an ordinary carnivore"
	)


# -- it can actually be drawn and spawned ---------------------------------

func test_it_has_a_body_the_renderer_can_draw():
	assert_true(AnimalAnatomy.has_profile(CURUPIRA), "no anatomy profile")
	assert_true(
		ProceduralAnimalSprite.SPECIES_SHAPE_FAMILY.has(CURUPIRA), "no shape family"
	)
	assert_true(ProceduralAnimalSprite.SPECIES_BASE_COLORS.has(CURUPIRA), "no colour")


func test_it_can_be_summoned_by_name():
	assert_eq(ConsoleSpecies.resolve(CURUPIRA), CURUPIRA, "/spawn and /arena must find it")


# -- and it lives somewhere real ------------------------------------------

## The roster places it in rainforest, and its whole behaviour is about the
## herd of a forest. It belongs in that pool and in no other.
func test_it_lives_in_the_rainforest_and_nowhere_else():
	for biome in CreatureRenderer.PREDATOR_SPECIES_POOL_BY_BIOME:
		var pool: Array = CreatureRenderer.PREDATOR_SPECIES_POOL_BY_BIOME[biome]
		if biome == "rainforest":
			assert_true(pool.has(CURUPIRA), "the rainforest must be able to produce it")
		else:
			assert_false(pool.has(CURUPIRA), "%s is not its forest" % biome)


## Rare: a guardian that turns up as often as a jaguar is a jaguar. It takes
## the smallest possible share of its pool.
func test_it_is_rarer_than_the_biomes_ordinary_predator():
	var pool: Array = CreatureRenderer.PREDATOR_SPECIES_POOL_BY_BIOME["rainforest"]
	var mine := 0
	var reference := 0
	for entry in pool:
		if String(entry) == CURUPIRA:
			mine += 1
		elif String(entry) == REFERENCE:
			reference += 1
	assert_gt(reference, mine, "the ordinary predator must still dominate its own biome")


# -- and it bites like itself ---------------------------------------------

func test_it_has_its_own_bite_rather_than_the_fallback():
	assert_true(SpeciesBite.has_profile(CURUPIRA), "a named monster with a generic bite is a reskin")


## The roster's line about it: not a wolf with more health. Its reach is
## what makes it different -- a guardian that has already decided about you
## does not need to stumble across you.
func test_it_senses_further_than_the_biomes_ordinary_predator():
	assert_gt(
		float(SpeciesBite.profile_for(CURUPIRA)["sense_radius_tiles"]),
		float(SpeciesBite.profile_for(REFERENCE)["sense_radius_tiles"]),
		"a guardian knows where you are before an animal would"
	)


## And it does not give up, because a grievance is not hunger.
func test_it_does_not_break_off_the_way_a_hungry_animal_does():
	assert_lt(
		float(SpeciesBite.profile_for(CURUPIRA)["tenacity"]),
		float(SpeciesBite.profile_for(REFERENCE)["tenacity"]),
		"it must hold on past the health a hunting animal would quit at"
	)


# -- the grudge is really its own -----------------------------------------

func test_the_grudge_rule_exists_and_is_this_creatures():
	assert_false(EcologicalGrudge.is_provoked(100.0, 100.0), "an untouched forest is quiet")
	assert_true(EcologicalGrudge.is_provoked(10.0, 100.0), "a stripped one is not")


# -- it is peaceful until your footprint provokes it ----------------------
#
# The roster's whole point: it IGNORES a player who hunts sustainably. An
# ordinary predator perceives every threat always (CreatureBehavior.
# _perceives_threats returns true for anything that is not a world boss), so
# without this the Curupira would be a jaguar that happens to be red.

const CreatureBehavior = preload("res://src/gameplay/creature_behavior.gd")


func _context(overrides: Dictionary) -> Dictionary:
	var context := {
		"position": Vector2.ZERO,
		"species": CURUPIRA,
		"temperament": "aggressive",
		"is_predator": true,
		"health_fraction": 1.0,
		"bears_a_grudge": true,
		"is_aggroed": false,
		"stimuli": [],
	}
	for key in overrides:
		context[key] = overrides[key]
	return context


func test_it_ignores_you_while_the_forest_is_whole():
	assert_false(
		CreatureBehavior.new()._perceives_threats(_context({})),
		"an unprovoked guardian does not hunt a sustainable hunter"
	)


func test_it_comes_for_you_once_provoked():
	assert_true(
		CreatureBehavior.new()._perceives_threats(_context({"is_aggroed": true}))
	)


## And nothing else in the game changes: an ordinary animal still perceives
## threats whether or not anyone has been over-hunting.
func test_an_ordinary_animal_is_unaffected():
	assert_true(
		CreatureBehavior.new()._perceives_threats(
			_context({"species": REFERENCE, "bears_a_grudge": false})
		)
	)
	assert_true(
		CreatureBehavior.new()._perceives_threats({"stimuli": []}),
		"a context built before this existed behaves exactly as it always did"
	)


## The marker really reads the live ecology rather than a flag somebody set.
func test_the_marker_really_reads_the_live_ecology():
	var source := FileAccess.get_file_as_string("res://src/rendering/creature_marker.gd")
	assert_true(source.contains("EcologicalGrudge.is_provoked"), "through the shared rule")
	assert_true(source.contains("herbivore_population_at_chunk"), "the real herd")
	assert_true(source.contains("herbivore_capacity_at_chunk"), "against the real ground")
