extends GutTest

const CreatureInfo = preload("res://src/world/creature_info.gd")

var info: CreatureInfo


func before_each():
	info = CreatureInfo.new("herbivore")


func test_display_name_is_the_capitalized_species():
	assert_eq(info.display_name, "Herbivore")


func test_starts_at_full_health():
	assert_eq(info.health, info.max_health)
	assert_gt(info.max_health, 0.0)


func test_diet_flavor_text_differs_by_species():
	var herbivore_info := CreatureInfo.new("herbivore")
	var predator_info := CreatureInfo.new("predator")
	assert_ne(herbivore_info.diet, predator_info.diet)


func test_herbivores_are_calm_and_not_predators():
	var herbivore_info := CreatureInfo.new("herbivore")
	assert_eq(herbivore_info.temperament, "calm")
	assert_false(herbivore_info.is_predator)


func test_predators_are_aggressive_and_are_predators():
	var predator_info := CreatureInfo.new("predator")
	assert_eq(predator_info.temperament, "aggressive")
	assert_true(predator_info.is_predator)


func test_level_is_at_least_one():
	assert_gte(info.level, 1)


func test_level_is_deterministic_for_the_same_seed():
	var a := CreatureInfo.new("herbivore", 42)
	var b := CreatureInfo.new("herbivore", 42)
	assert_eq(a.level, b.level)


func test_level_can_vary_by_seed():
	var levels := {}
	for seed_value in range(10):
		levels[CreatureInfo.new("herbivore", seed_value).level] = true
	assert_gt(levels.size(), 1, "levels should vary across different individuals")


func test_starts_with_full_stamina_and_mana():
	assert_eq(info.stamina, info.max_stamina)
	assert_eq(info.mana, info.max_mana)
	assert_gt(info.max_stamina, 0.0)
	assert_gt(info.max_mana, 0.0)


func test_max_health_scales_up_with_level():
	var level_1 := CreatureInfo.new("herbivore", 0)  # seed 0 -> level 1
	var level_5 := CreatureInfo.new("herbivore", 4)  # seed 4 -> level 5
	assert_eq(level_1.level, 1)
	assert_eq(level_5.level, 5)
	assert_gt(level_5.max_health, level_1.max_health)


func test_max_health_matches_the_level_scaling_formula():
	var info_at_level_5 := CreatureInfo.new("herbivore", 4)
	var base: float = CreatureInfo.MAX_HEALTH_BY_SPECIES["herbivore"]
	var expected := base * (1.0 + (info_at_level_5.level - 1) * CreatureInfo.LEVEL_HEALTH_SCALE)
	assert_almost_eq(info_at_level_5.max_health, expected, 0.01)


func test_a_level_1_creatures_max_health_equals_the_species_base():
	var level_1 := CreatureInfo.new("herbivore", 0)
	assert_almost_eq(level_1.max_health, CreatureInfo.MAX_HEALTH_BY_SPECIES["herbivore"], 0.01)


func test_boar_is_an_aggressive_herbivore_that_is_not_a_predator():
	var boar_info := CreatureInfo.new("boar")
	assert_eq(boar_info.temperament, "aggressive")
	assert_false(boar_info.is_predator)


func test_lynx_is_an_aggressive_predator():
	var lynx_info := CreatureInfo.new("lynx")
	assert_eq(lynx_info.temperament, "aggressive")
	assert_true(lynx_info.is_predator)


# -- biome-specific species (see CreatureRenderer's per-biome species pools) --

const NEW_HERBIVORE_SPECIES := ["camel", "reindeer", "tapir", "goat"]
const NEW_PREDATOR_SPECIES := ["jackal", "arctic_fox", "jaguar", "mountain_lion"]


func test_camel_is_a_calm_herbivore_that_is_not_a_predator():
	var camel_info := CreatureInfo.new("camel")
	assert_eq(camel_info.temperament, "calm")
	assert_false(camel_info.is_predator)


func test_reindeer_is_a_calm_herbivore_that_is_not_a_predator():
	var reindeer_info := CreatureInfo.new("reindeer")
	assert_eq(reindeer_info.temperament, "calm")
	assert_false(reindeer_info.is_predator)


func test_goat_is_a_calm_herbivore_that_is_not_a_predator():
	var goat_info := CreatureInfo.new("goat")
	assert_eq(goat_info.temperament, "calm")
	assert_false(goat_info.is_predator)


## Unlike boar (which shares tapir's shape family but is aggressive), tapir
## should just flee like a plain herbivore -- temperament is independent of
## shape family and set directly per species.
func test_tapir_is_a_calm_herbivore_unlike_the_aggressive_boar_it_shares_a_shape_with():
	var tapir_info := CreatureInfo.new("tapir")
	var boar_info := CreatureInfo.new("boar")
	assert_eq(tapir_info.temperament, "calm")
	assert_false(tapir_info.is_predator)
	assert_eq(boar_info.temperament, "aggressive")


func test_jackal_is_an_aggressive_predator():
	var jackal_info := CreatureInfo.new("jackal")
	assert_eq(jackal_info.temperament, "aggressive")
	assert_true(jackal_info.is_predator)


func test_arctic_fox_is_an_aggressive_predator():
	var arctic_fox_info := CreatureInfo.new("arctic_fox")
	assert_eq(arctic_fox_info.temperament, "aggressive")
	assert_true(arctic_fox_info.is_predator)


func test_jaguar_is_an_aggressive_predator():
	var jaguar_info := CreatureInfo.new("jaguar")
	assert_eq(jaguar_info.temperament, "aggressive")
	assert_true(jaguar_info.is_predator)


func test_mountain_lion_is_an_aggressive_predator():
	var mountain_lion_info := CreatureInfo.new("mountain_lion")
	assert_eq(mountain_lion_info.temperament, "aggressive")
	assert_true(mountain_lion_info.is_predator)


func test_every_new_species_has_positive_health_stamina_and_mana_and_a_known_diet():
	for species in NEW_HERBIVORE_SPECIES + NEW_PREDATOR_SPECIES:
		var creature_info := CreatureInfo.new(species)
		assert_gt(creature_info.max_health, 0.0, species)
		assert_gt(creature_info.max_stamina, 0.0, species)
		assert_gt(creature_info.max_mana, 0.0, species)
		assert_ne(creature_info.diet, "Unknown", species)
