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


# -- mass_fraction: nutrients scale with how much was actually eaten --------
#
# See docs/concept/metabolism.md's "the two named mushroom gaps": one of
# them is a predator/forager's nutrition not scaling with how much of a
# food item one bite event actually consumed (a partially-bitten mushroom,
# or any future partial-consumption food). Defaults to 1.0 (a whole item)
# so every existing caller above keeps behaving exactly as it always did.

## No `mass_fraction` argument at all -- every call site above this
## section already relies on this -- must behave exactly as before this
## parameter existed.
func test_omitting_mass_fraction_behaves_exactly_as_a_whole_item() -> void:
	var default_call: Dictionary = NutrientRelease.consume("apple")
	var explicit_whole: Dictionary = NutrientRelease.consume("apple", 1.0)
	assert_almost_eq(default_call["water"], explicit_whole["water"], 0.0001)
	assert_almost_eq(default_call["sugar"], explicit_whole["sugar"], 0.0001)
	assert_almost_eq(default_call["vitamins"], explicit_whole["vitamins"], 0.0001)


func test_half_the_mass_yields_half_the_nutrients() -> void:
	var whole: Dictionary = NutrientRelease.consume("parasol", 1.0)
	var half: Dictionary = NutrientRelease.consume("parasol", 0.5)
	assert_true(whole["crushed"])
	assert_true(half["crushed"])
	assert_almost_eq(half["water"], whole["water"] * 0.5, 0.0001)
	assert_almost_eq(half["sugar"], whole["sugar"] * 0.5, 0.0001)
	assert_almost_eq(half["vitamins"], whole["vitamins"] * 0.5, 0.0001)


func test_zero_mass_fraction_yields_zero_nutrients_but_still_crushed() -> void:
	var result: Dictionary = NutrientRelease.consume("parasol", 0.0)
	assert_true(result["crushed"], "the bite itself still lands, it just has nothing left to release")
	assert_almost_eq(result["water"], 0.0, 0.0001)
	assert_almost_eq(result["sugar"], 0.0, 0.0001)
	assert_almost_eq(result["vitamins"], 0.0, 0.0001)


## Defensive: a caller passing an out-of-range fraction (a future bug
## upstream) never grants MORE than a whole item's worth, and never goes
## negative.
func test_mass_fraction_is_clamped_to_a_real_zero_to_one_range() -> void:
	var over: Dictionary = NutrientRelease.consume("apple", 5.0)
	var whole: Dictionary = NutrientRelease.consume("apple", 1.0)
	assert_almost_eq(over["water"], whole["water"], 0.0001)
	var under: Dictionary = NutrientRelease.consume("apple", -5.0)
	assert_almost_eq(under["water"], 0.0, 0.0001)
