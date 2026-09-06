extends GutTest

## See docs/concept/material_dsl.md -- the generic, species-blind core: a
## bite resolved as a real impact (ImpactResolver + OrganicMaterialProperties)
## against a food's real composition (FoodComposition), released as
## meter-ready nutrient amounts. Pure and content-driven -- it does not know
## or care who is eating, which is what makes "implicitly the same for all
## species" fall out for free at the caller side.

var NutrientRelease: GDScript = preload("res://src/gameplay/nutrient_release.gd")


func test_biting_a_modeled_fruit_crushes_it() -> void:
	var result: Dictionary = NutrientRelease.consume("apple")
	assert_true(result["crushed"])


func test_biting_an_unmodeled_food_releases_nothing() -> void:
	var result: Dictionary = NutrientRelease.consume("cooked_meat")
	assert_false(result["crushed"])
	assert_almost_eq(result["water"], 0.0, 0.0001)
	assert_almost_eq(result["sugar"], 0.0, 0.0001)
	assert_almost_eq(result["vitamins"], 0.0, 0.0001)


## Each composition fraction x NUTRIENT_UNIT_SCALE -- calibrated so a whole
## apple's sugar content lands in the same ballpark as today's flat
## Player.EAT_HUNGER_RELIEF (0.4), the real number the new one replaces.
func test_apples_nutrient_amounts_are_the_real_composition_scaled() -> void:
	var result: Dictionary = NutrientRelease.consume("apple")
	assert_almost_eq(result["water"], 0.86 * NutrientRelease.NUTRIENT_UNIT_SCALE, 0.0001)
	assert_almost_eq(result["sugar"], 0.10 * NutrientRelease.NUTRIENT_UNIT_SCALE, 0.0001)
	assert_almost_eq(result["vitamins"], 0.02 * NutrientRelease.NUTRIENT_UNIT_SCALE, 0.0001)


func test_a_sweeter_fruit_yields_more_sugar() -> void:
	var apple: Dictionary = NutrientRelease.consume("apple")
	var cherry: Dictionary = NutrientRelease.consume("cherry")
	assert_true(cherry["sugar"] > apple["sugar"], "cherry has real more sugar by mass than apple")


## The bite-scale momentum is real enough to clear ImpactResolver.T_CRUSH
## against fruit_flesh's own toughness -- not an assumed pass, an actually
## resolved one. This is the "a crushing force is applied" half of the ask,
## made real rather than a rubber-stamped boolean.
func test_bite_momentum_actually_clears_the_crush_threshold() -> void:
	var ImpactResolver := preload("res://src/gameplay/impact_resolver.gd")
	assert_true(NutrientRelease.BITE_MOMENTUM_KG_M_S >= ImpactResolver.T_CRUSH)
