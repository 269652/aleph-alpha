extends GutTest

## FoodComposition (see docs/concept/material_dsl.md): per-food real
## nutrient composition, the data NutrientRelease.consume resolves a real
## bite against.

const FoodComposition = preload("res://src/gameplay/food_composition.gd")
const MushroomBiting = preload("res://src/gameplay/mushroom_biting.gd")

var composition := FoodComposition.new()


func test_apple_has_its_own_explicit_composition():
	assert_eq(composition.composition_for("apple"), FoodComposition.COMPOSITION["apple"])


func test_an_unmodeled_food_returns_an_empty_composition():
	assert_true(composition.composition_for("cooked_meat").is_empty())


func test_a_base_mushroom_species_uses_the_shared_mushroom_composition():
	assert_false(composition.composition_for("parasol").is_empty())


## The real gap this closes: eating a bitten mushroom (docs/concept/
## metabolism.md's "the two named mushroom gaps") used to fall through to
## an empty composition -- "_bitten" is not itself a MushroomSpecies id --
## which silently skipped the whole real nutrient pipeline for every
## partially-eaten mushroom a player picked up, regardless of mass.
func test_a_bitten_mushroom_id_uses_its_base_species_composition():
	var bitten := composition.composition_for("parasol_bitten")
	var base := composition.composition_for("parasol")
	assert_false(bitten.is_empty())
	assert_eq(bitten, base)


func test_every_bitten_mushroom_id_resolves_a_real_composition():
	const MushroomSpecies = preload("res://src/world/mushroom_species.gd")
	for species_id in MushroomSpecies.IDS:
		var bitten_id := MushroomBiting.bitten_item_id_for(species_id)
		assert_false(composition.composition_for(bitten_id).is_empty(), bitten_id)
