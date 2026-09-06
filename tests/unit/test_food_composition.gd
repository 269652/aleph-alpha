extends GutTest

## See docs/concept/material_dsl.md -- the actual "Material DSL" data: a
## plain, flat composition table, mirroring ethogram.gd's own
## data-not-program convention (no control flow to a composition record, so
## it gets no parser).

var FoodComposition: GDScript = preload("res://src/gameplay/food_composition.gd")

var fc: RefCounted


func before_each() -> void:
	fc = FoodComposition.new()


func test_apple_has_a_real_composition() -> void:
	var composition: Dictionary = fc.composition_for("apple")
	assert_almost_eq(composition["water"], 0.86, 0.0001)
	assert_almost_eq(composition["sugar"], 0.10, 0.0001)
	assert_almost_eq(composition["vitamins"], 0.02, 0.0001)


func test_cherry_has_a_real_composition() -> void:
	var composition: Dictionary = fc.composition_for("cherry")
	assert_almost_eq(composition["water"], 0.82, 0.0001)
	assert_almost_eq(composition["sugar"], 0.13, 0.0001)
	assert_almost_eq(composition["vitamins"], 0.025, 0.0001)


func test_an_unmodeled_food_returns_an_empty_composition() -> void:
	assert_eq(fc.composition_for("cooked_meat"), {})


## See docs/concept/mushrooms.md "Animals can find and eat wild
## mushrooms" -- one shared, real composition vector for every
## MushroomSpecies id, rather than 6 duplicated literal entries (real
## fungi don't differ enough in gross macro composition, at this level of
## abstraction, to warrant per-species numbers).
func test_every_mushroom_species_has_a_real_shared_composition() -> void:
	var MushroomSpecies := preload("res://src/world/mushroom_species.gd")
	for species_id in MushroomSpecies.IDS:
		var composition: Dictionary = fc.composition_for(species_id)
		assert_false(composition.is_empty(), "%s should have a real composition" % species_id)
		assert_almost_eq(composition["water"], 0.90, 0.0001)
		assert_almost_eq(composition["sugar"], 0.02, 0.0001)
		assert_almost_eq(composition["vitamins"], 0.03, 0.0001)


## A toxic species (MushroomSpecies.is_toxic) still gets the same real
## composition -- toxicity is deliberately not consulted here at all (see
## the concept doc: a boar eats a toxic mushroom exactly like any other).
func test_a_toxic_mushroom_species_still_has_a_real_composition() -> void:
	assert_false(fc.composition_for("fly_agaric").is_empty())


func test_the_explicit_apple_and_cherry_entries_are_unaffected_by_the_mushroom_fallback() -> void:
	assert_almost_eq(fc.composition_for("apple")["water"], 0.86, 0.0001)
	assert_almost_eq(fc.composition_for("cherry")["water"], 0.82, 0.0001)


## Every real entry's fractions must sum to comfortably under 1.0 -- the
## remainder is fiber/protein/fat/structure this pass doesn't model. A real,
## test-pinned invariant (CLAUDE.md: tuned values are tested, never
## eyeballed), not just a hope about the numbers above.
func test_every_composition_sums_to_no_more_than_one() -> void:
	for food_id in FoodComposition.COMPOSITION:
		var composition: Dictionary = FoodComposition.COMPOSITION[food_id]
		var total := 0.0
		for fraction in composition.values():
			total += float(fraction)
		assert_true(total <= 1.0, "%s's composition sums to %f, over 100%%" % [food_id, total])
