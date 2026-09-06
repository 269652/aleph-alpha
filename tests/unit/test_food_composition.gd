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
