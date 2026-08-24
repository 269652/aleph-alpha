extends GutTest

## OccupationProduction: which CraftingRecipeBook recipe a settlement
## attempts on behalf of a household whose founder holds a given occupation
## (see src/emergence/occupation_production.gd's own doc comment for why
## only these two occupations are mapped).

const OccupationProduction = preload("res://src/emergence/occupation_production.gd")


func test_hunter_maps_to_cooked_meat():
	assert_eq(OccupationProduction.recipe_for("hunter"), "cooked_meat")


func test_blacksmith_maps_to_stone_pickaxe():
	assert_eq(OccupationProduction.recipe_for("blacksmith"), "stone_pickaxe")


## Every other real occupation (see NpcIdentity.OCCUPATIONS) has no
## comparably obvious recipe analog in CraftingRecipeBook and is
## intentionally left unmapped, rather than forced onto an unrelated recipe.
func test_occupations_with_no_grounded_recipe_return_empty_string():
	for occupation in ["farmer", "merchant", "guard", "fisher", "herbalist", "nurse"]:
		assert_eq(OccupationProduction.recipe_for(occupation), "", occupation)


func test_unknown_occupation_returns_empty_string():
	assert_eq(OccupationProduction.recipe_for("not_a_real_occupation"), "")
