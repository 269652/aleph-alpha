extends GutTest

## ConstructionLabor: derives a real labor-hours requirement for a
## ConstructionProject's own blueprint_id from its real CraftingRecipeBook
## recipe (see docs/concept/timber_construction.md's "Unloaded / offscreen
## fidelity" subsection) -- there is no HouseBlueprint.total_labor_hours
## field anywhere real today, so this sums the recipe's own real input
## material counts and scales by a named, test-pinned
## HOURS_PER_UNIT_MATERIAL constant instead.

const ConstructionLabor = preload("res://src/emergence/construction_labor.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")

var book: CraftingRecipeBook


func before_each():
	book = CraftingRecipeBook.new()


## storage: 12 wood + 4 plank = 16 real input units.
func test_labor_hours_for_storage_matches_the_pinned_per_unit_rate():
	var required := ConstructionLabor.labor_hours_required("storage", book)
	assert_almost_eq(required, 16.0 * ConstructionLabor.HOURS_PER_UNIT_MATERIAL, 0.001)


## sagewerk: 8 log + 4 wood = 12 real input units.
func test_labor_hours_for_sagewerk_matches_the_pinned_per_unit_rate():
	var required := ConstructionLabor.labor_hours_required("sagewerk", book)
	assert_almost_eq(required, 12.0 * ConstructionLabor.HOURS_PER_UNIT_MATERIAL, 0.001)


## The core grounding this module exists for: a structure needing more raw
## material to assemble genuinely takes more labor to put together.
func test_a_recipe_with_more_input_material_requires_more_labor_than_a_smaller_one():
	var storage_hours := ConstructionLabor.labor_hours_required("storage", book)  # 16 units
	var club_hours := ConstructionLabor.labor_hours_required("wooden_club", book)  # 3 units
	assert_gt(storage_hours, club_hours)


func test_labor_hours_scale_linearly_with_total_input_count():
	# torch: 1 wood + 1 hide = 2 units. crude_blade: 1 stick + 1 shard + 2
	# fibre = 4 units -- exactly double torch's own input count.
	var torch_hours := ConstructionLabor.labor_hours_required("torch", book)
	var blade_hours := ConstructionLabor.labor_hours_required("crude_blade", book)
	assert_almost_eq(blade_hours, torch_hours * 2.0, 0.001)


func test_unknown_blueprint_requires_zero_labor():
	var required := ConstructionLabor.labor_hours_required("not_a_real_recipe", book)
	assert_eq(required, 0.0)


func test_is_pure_and_deterministic():
	var a := ConstructionLabor.labor_hours_required("storage", book)
	var b := ConstructionLabor.labor_hours_required("storage", book)
	assert_eq(a, b)


# -- labor_hours_for_piece / labor_hours_required_for_pieces (the Builder's --
# -- own per-piece completion signal -- see docs/concept/timber_construction --
# -- .md's NPC construction section) ------------------------------------------
#
# A Builder's own target is a real piece layout (local_cell -> piece_id), not
# necessarily a CraftingRecipeBook recipe -- these reuse the EXACT SAME
# HOURS_PER_UNIT_MATERIAL rate labor_hours_required already uses ("one truth",
# not a second parallel model), applied per-piece via BuildingPiece.cost_of
# instead of a whole recipe's summed inputs.

func test_labor_hours_for_a_piece_matches_its_own_real_cost_of_material():
	# timber_wall costs beam: 2 -> 2 real units.
	var hours := ConstructionLabor.labor_hours_for_piece("timber_wall")
	assert_almost_eq(hours, 2.0 * ConstructionLabor.HOURS_PER_UNIT_MATERIAL, 0.001)


func test_labor_hours_for_a_piece_with_a_larger_cost_is_larger():
	var wall_hours := ConstructionLabor.labor_hours_for_piece("timber_wall")  # beam: 2 -> 2 units
	var door_hours := ConstructionLabor.labor_hours_for_piece("stone_door")   # stone: 3 + wood: 2 -> 5 units
	assert_gt(door_hours, wall_hours)


func test_labor_hours_for_an_unknown_piece_is_zero():
	assert_eq(ConstructionLabor.labor_hours_for_piece("not_a_real_piece"), 0.0)


func test_labor_hours_required_for_pieces_sums_every_real_piece_in_the_dict():
	var pieces := {
		Vector2i(0, 0): "timber_floor",  # plank: 2 -> 3.0 hours
		Vector2i(1, 0): "timber_wall",   # beam: 2 -> 3.0 hours
	}
	var required := ConstructionLabor.labor_hours_required_for_pieces(pieces)
	assert_almost_eq(required, 6.0, 0.001)


func test_labor_hours_required_for_an_empty_piece_dict_is_zero():
	assert_eq(ConstructionLabor.labor_hours_required_for_pieces({}), 0.0)


func test_labor_hours_required_for_pieces_is_pure_and_deterministic():
	var pieces := {Vector2i(0, 0): "timber_wall", Vector2i(1, 0): "timber_floor"}
	var a := ConstructionLabor.labor_hours_required_for_pieces(pieces)
	var b := ConstructionLabor.labor_hours_required_for_pieces(pieces)
	assert_eq(a, b)
