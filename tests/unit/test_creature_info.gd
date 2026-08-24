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

const NEW_HERBIVORE_SPECIES := ["camel", "reindeer", "tapir", "goat", "mouse", "horse", "deer", "nonvenomous_snake", "sheep"]
const NEW_PREDATOR_SPECIES := ["jackal", "arctic_fox", "jaguar", "mountain_lion", "bear", "lion", "venomous_snake", "wolf"]


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


# -- mice and horses (see docs/concept/ecosystem_dynamics.md's Species roster) --

func test_mouse_is_a_calm_herbivore_that_is_not_a_predator():
	var mouse_info := CreatureInfo.new("mouse")
	assert_eq(mouse_info.temperament, "calm")
	assert_false(mouse_info.is_predator)


func test_horse_is_a_calm_herbivore_that_is_not_a_predator():
	var horse_info := CreatureInfo.new("horse")
	assert_eq(horse_info.temperament, "calm")
	assert_false(horse_info.is_predator)


## Mouse is the smallest/frailest creature in the roster -- a real-world-
## grounded distinction (it's a mouse), not an arbitrary stat pick.
func test_mouse_has_less_health_than_every_other_species():
	var mouse_health: float = CreatureInfo.MAX_HEALTH_BY_SPECIES["mouse"]
	for species in CreatureInfo.MAX_HEALTH_BY_SPECIES:
		if species == "mouse":
			continue
		assert_lt(
			mouse_health, CreatureInfo.MAX_HEALTH_BY_SPECIES[species],
			"mouse should be the smallest/frailest species"
		)


## Real horses are known for endurance -- higher stamina than any other
## herbivore-role species, a real-world-grounded distinction.
func test_horse_has_the_highest_stamina_among_herbivore_role_species():
	var horse_stamina: float = CreatureInfo.MAX_STAMINA_BY_SPECIES["horse"]
	for species in ["herbivore", "boar", "camel", "reindeer", "tapir", "goat", "mouse"]:
		assert_gte(
			horse_stamina, CreatureInfo.MAX_STAMINA_BY_SPECIES[species],
			"horse should have real-world-grounded high stamina/endurance"
		)


# -- bear, deer, lion, and both snakes (see docs/concept/ecosystem_dynamics.md's
# Region difficulty section) -------------------------------------------------

func test_deer_is_a_calm_herbivore_that_is_not_a_predator():
	var deer_info := CreatureInfo.new("deer")
	assert_eq(deer_info.temperament, "calm")
	assert_false(deer_info.is_predator)


func test_bear_is_an_aggressive_predator():
	var bear_info := CreatureInfo.new("bear")
	assert_eq(bear_info.temperament, "aggressive")
	assert_true(bear_info.is_predator)


func test_lion_is_an_aggressive_predator():
	var lion_info := CreatureInfo.new("lion")
	assert_eq(lion_info.temperament, "aggressive")
	assert_true(lion_info.is_predator)


## Bear/lion are meant to be the new apex tier -- meaningfully tougher than
## the existing predator roster, matching their HARD region-difficulty gate
## (see region_difficulty.gd).
func test_bear_and_lion_have_more_health_than_every_existing_predator():
	var existing_predators := ["predator", "lynx", "jackal", "arctic_fox", "jaguar", "mountain_lion"]
	for apex in ["bear", "lion"]:
		var apex_health: float = CreatureInfo.MAX_HEALTH_BY_SPECIES[apex]
		for species in existing_predators:
			assert_gt(
				apex_health, CreatureInfo.MAX_HEALTH_BY_SPECIES[species],
				"%s should be tougher than %s" % [apex, species]
			)


func test_nonvenomous_snake_is_a_calm_herbivore_role_that_is_not_a_predator():
	var info := CreatureInfo.new("nonvenomous_snake")
	assert_eq(info.temperament, "calm")
	assert_false(info.is_predator)


func test_venomous_snake_is_an_aggressive_predator():
	var info := CreatureInfo.new("venomous_snake")
	assert_eq(info.temperament, "aggressive")
	assert_true(info.is_predator)


## Venom is the real danger, not raw combat stats -- venomous_snake should
## be fragile in a straight fight, unlike bear/lion.
func test_venomous_snake_is_frailer_than_bear_and_lion():
	var snake_health: float = CreatureInfo.MAX_HEALTH_BY_SPECIES["venomous_snake"]
	assert_lt(snake_health, CreatureInfo.MAX_HEALTH_BY_SPECIES["bear"])
	assert_lt(snake_health, CreatureInfo.MAX_HEALTH_BY_SPECIES["lion"])


## Wolves are forest's own named apex predator (see CreatureRenderer's
## PREDATOR_SPECIES_POOL_BY_BIOME forest entry, and
## docs/concept/ecosystem_dynamics.md's Species roster section) -- real
## wolves are pack-hunting predators, aggressive like every other predator-
## role species.
func test_wolf_is_an_aggressive_predator():
	var wolf_info := CreatureInfo.new("wolf")
	assert_eq(wolf_info.temperament, "aggressive")
	assert_true(wolf_info.is_predator)


## Sheep are wolf's (and deer's) forest prey -- an ordinary calm, non-
## predator herbivore, the same role every other grazer in the roster has.
func test_sheep_is_a_calm_herbivore_that_is_not_a_predator():
	var sheep_info := CreatureInfo.new("sheep")
	assert_eq(sheep_info.temperament, "calm")
	assert_false(sheep_info.is_predator)


func test_every_new_species_has_positive_health_stamina_and_mana_and_a_known_diet():
	for species in NEW_HERBIVORE_SPECIES + NEW_PREDATOR_SPECIES:
		var creature_info := CreatureInfo.new(species)
		assert_gt(creature_info.max_health, 0.0, species)
		assert_gt(creature_info.max_stamina, 0.0, species)
		assert_gt(creature_info.max_mana, 0.0, species)
		assert_ne(creature_info.diet, "Unknown", species)


# -- Germany-region world bosses (docs/concept/worldbosses.md) --------------
#
# Debug/test-spawn stats, not the doc's real design: worldbosses.md specs
# boss stats as *emergent* (world_boss_fitness.gd's fitness-threshold
# promotion), not hand-authored -- that promotion mechanism doesn't exist in
# code yet. These entries exist so `/spawn krampus` produces something
# actually fightable (aggressive, real threat) right now rather than
# silently falling back to CreatureInfo's calm/10hp defaults, the same way
# every other species here is a plain hand-authored stat row (see this
# file's MAX_HEALTH_BY_SPECIES -- bear/lion are hand-authored too, not
# derived) -- not a violation of this project's no-eyeballed-thresholds
# rule, which targets tuned FORMULAS/curves, not per-species flavor stats in
# an already-precedent-setting hand-authored table.
const GERMANY_BOSS_SPECIES := ["lindwurm", "rubezahl", "nyx", "krampus"]


func test_every_germany_boss_is_aggressive_and_a_predator():
	for species in GERMANY_BOSS_SPECIES:
		var info := CreatureInfo.new(species)
		assert_eq(info.temperament, "aggressive", species)
		assert_true(info.is_predator, species)


## Should read as tougher than this roster's current toughest ordinary
## predator (bear, 50 base health) -- boss stakes, not a routine encounter.
func test_every_germany_boss_has_more_base_health_than_a_bear():
	var bear_health: float = CreatureInfo.MAX_HEALTH_BY_SPECIES["bear"]
	for species in GERMANY_BOSS_SPECIES:
		assert_gt(CreatureInfo.MAX_HEALTH_BY_SPECIES[species], bear_health, species)


## is_world_boss gates the aggro-provocation rule (see BossAggro,
## CreatureBehavior._perceives_threats): a boss should not proactively
## attack a low-level player, and shouldn't even flee one, until a real hit
## lands. is_aggroed is the per-individual state that flips that on.
func test_germany_bosses_are_flagged_as_world_bosses():
	for species in GERMANY_BOSS_SPECIES:
		assert_true(CreatureInfo.new(species).is_world_boss, species)


func test_ordinary_species_are_not_world_bosses():
	assert_false(CreatureInfo.new("bear").is_world_boss)
	assert_false(CreatureInfo.new("herbivore").is_world_boss)


func test_a_fresh_creature_always_starts_unaggroed():
	assert_false(CreatureInfo.new("krampus").is_aggroed)
	assert_false(CreatureInfo.new("herbivore").is_aggroed)
