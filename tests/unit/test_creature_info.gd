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
