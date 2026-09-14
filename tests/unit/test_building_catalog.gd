extends GutTest

## BuildingCatalog: the catalog of whole-building entities (docs/concept/
## building.md "Buildings are entities; interiors are scenes") -- pure data,
## the same "what is this, never may it go here" framing BuildingPiece keeps.
## A building is one id with a rectangular footprint, a door on its south
## edge and a doorstep just outside it; every sheet follows the one asset
## contract (8 columns x 5 lifecycle rows) blacksmith.png already does.

const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const NpcGenome = preload("res://src/world/npc_genome.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")

const _TRAIT_NAMES := ["friendly", "gruff", "curious", "stoic", "greedy", "kind", "cautious", "bold"]


func test_every_building_id_resolves_to_a_definition():
	assert_false(BuildingCatalog.BUILDING_IDS.is_empty())
	for building_id in BuildingCatalog.BUILDING_IDS:
		assert_true(BuildingCatalog.has_building(building_id), building_id)


func test_an_unknown_id_is_not_a_building_and_answers_safely():
	assert_false(BuildingCatalog.has_building("not_a_building"))
	assert_eq(BuildingCatalog.footprint_of("not_a_building"), Vector2i.ZERO)
	assert_eq(BuildingCatalog.sheet_of("not_a_building"), "")
	assert_eq(BuildingCatalog.cost_of("not_a_building"), {})
	assert_eq(BuildingCatalog.footprint_cells("not_a_building", Vector2i(3, 3)), [])


func test_the_first_three_houses_have_the_footprints_the_spec_names():
	assert_eq(BuildingCatalog.footprint_of("house_small"), Vector2i(2, 2))
	assert_eq(BuildingCatalog.footprint_of("house_medium"), Vector2i(3, 2))
	assert_eq(BuildingCatalog.footprint_of("house_large"), Vector2i(4, 3))


## The door sits on the footprint's bottom (south) row, at x = width / 2;
## the doorstep is the cell just outside it -- the ONE cell of the world a
## house is entered from, and never part of the footprint itself.
func test_every_door_is_on_the_south_edge_and_the_doorstep_just_outside():
	for building_id in BuildingCatalog.BUILDING_IDS:
		var footprint := BuildingCatalog.footprint_of(building_id)
		var door := BuildingCatalog.door_of(building_id)
		assert_eq(door.y, footprint.y - 1, "%s: door on the bottom row" % building_id)
		assert_eq(door.x, footprint.x / 2, "%s: door at the middle of the front" % building_id)
		assert_eq(BuildingCatalog.doorstep_of(building_id), door + Vector2i(0, 1), building_id)
		var cells := BuildingCatalog.footprint_cells(building_id, Vector2i.ZERO)
		assert_true(cells.has(door), "%s: the door is a footprint cell" % building_id)
		assert_false(cells.has(BuildingCatalog.doorstep_of(building_id)), "%s: the doorstep is outside" % building_id)


func test_footprint_cells_cover_exactly_the_rectangle_from_the_origin():
	var origin := Vector2i(10, 20)
	var cells := BuildingCatalog.footprint_cells("house_medium", origin)
	assert_eq(cells.size(), 6)
	for x in 3:
		for y in 2:
			assert_true(cells.has(origin + Vector2i(x, y)), str(Vector2i(x, y)))


## The sheet contract every building shares (docs/concept/building.md
## "Asset contract"): 8 columns, 5 rows in a fixed order, and a path under
## assets/sprites/buildings named after the id.
func test_the_sheet_contract_is_eight_columns_by_five_lifecycle_rows():
	assert_eq(BuildingCatalog.SHEET_COLUMNS, 8)
	assert_eq(BuildingCatalog.SHEET_ROWS, 5)
	assert_eq(BuildingCatalog.CONSTRUCTION_STAGES, BuildingCatalog.SHEET_COLUMNS)
	var rows := [
		BuildingCatalog.ROW_CONSTRUCTION, BuildingCatalog.ROW_ACTIVE, BuildingCatalog.ROW_IDLE,
		BuildingCatalog.ROW_BURNING, BuildingCatalog.ROW_RUINED,
	]
	assert_eq(rows, [0, 1, 2, 3, 4])


func test_every_house_declares_its_sheet_path_by_id():
	for building_id in BuildingCatalog.BUILDING_IDS:
		assert_eq(BuildingCatalog.sheet_of(building_id), "res://assets/sprites/buildings/%s.png" % building_id)


func test_every_house_has_an_interior_family_capacity_labor_and_cost():
	for building_id in BuildingCatalog.BUILDING_IDS:
		assert_ne(BuildingCatalog.interior_family_of(building_id), "", building_id)
		assert_gt(BuildingCatalog.capacity_of(building_id), 0, building_id)
		assert_gt(BuildingCatalog.labor_hours_of(building_id), 0.0, building_id)
		var cost := BuildingCatalog.cost_of(building_id)
		assert_false(cost.is_empty(), building_id)
		for item_id in cost:
			assert_gt(int(cost[item_id]), 0, "%s cost for %s" % [building_id, item_id])


func test_a_bigger_house_costs_and_takes_more_than_a_smaller_one():
	assert_gt(BuildingCatalog.labor_hours_of("house_medium"), BuildingCatalog.labor_hours_of("house_small"))
	assert_gt(BuildingCatalog.labor_hours_of("house_large"), BuildingCatalog.labor_hours_of("house_medium"))
	assert_gt(BuildingCatalog.capacity_of("house_large"), BuildingCatalog.capacity_of("house_small"))


# -- occupancy: the one predicate every seam reads -------------------------

func test_occupies_is_true_for_a_building_id_and_the_footprint_marker_only():
	for building_id in BuildingCatalog.BUILDING_IDS:
		assert_true(BuildingCatalog.occupies(building_id), building_id)
	assert_true(BuildingCatalog.occupies(BuildingCatalog.FOOTPRINT_TILE_ID))
	assert_false(BuildingCatalog.occupies(""))
	assert_false(BuildingCatalog.occupies("wood_wall"), "a legacy piece is not a building")
	assert_false(BuildingCatalog.occupies("campfire"), "a single-tile placeable is not a building")


func test_the_footprint_marker_is_not_itself_a_building():
	assert_false(BuildingCatalog.has_building(BuildingCatalog.FOOTPRINT_TILE_ID))
	assert_false(BuildingCatalog.BUILDING_IDS.has(BuildingCatalog.FOOTPRINT_TILE_ID))


# -- choose_house_id: HouseBlueprint.choose_blueprint_id's own rule over --
# -- the new ids (occupation pool, personality nudge, seeded) --------------

func test_choose_house_id_always_returns_a_real_building():
	for seed_value in range(30):
		var genome := NpcGenome.new(seed_value, _TRAIT_NAMES)
		var chosen := BuildingCatalog.choose_house_id("farmer", genome, seed_value)
		assert_true(BuildingCatalog.BUILDING_IDS.has(chosen), "seed %d: %s" % [seed_value, chosen])


func test_choose_house_id_is_deterministic():
	var genome := NpcGenome.new(7, _TRAIT_NAMES)
	assert_eq(
		BuildingCatalog.choose_house_id("merchant", genome, 7),
		BuildingCatalog.choose_house_id("merchant", genome, 7)
	)


func test_unknown_occupations_fall_back_to_the_whole_catalog():
	var genome := NpcGenome.new(1, _TRAIT_NAMES)
	assert_true(BuildingCatalog.BUILDING_IDS.has(BuildingCatalog.choose_house_id("not_a_real_occupation", genome, 1)))


func test_every_occupation_has_a_pool_and_can_choose_more_than_one_house():
	for occupation in NpcIdentity.OCCUPATIONS:
		assert_true(BuildingCatalog.HOUSE_POOL_BY_OCCUPATION.has(occupation), occupation)
		var seen := {}
		for seed_value in range(60):
			var genome := NpcGenome.new(seed_value, _TRAIT_NAMES)
			seen[BuildingCatalog.choose_house_id(occupation, genome, seed_value)] = true
		assert_gt(seen.size(), 1, "%s never varies its house" % occupation)


## A merchant's pool leans large, a farmer's small -- the same "occupation
## decides what a villager plausibly builds" pillar the blueprint catalog
## kept, measured as an average footprint over many seeds.
func test_a_merchant_tends_to_a_bigger_house_than_a_farmer():
	var merchant_area := 0
	var farmer_area := 0
	for seed_value in range(80):
		var genome := NpcGenome.new(seed_value, _TRAIT_NAMES)
		var m := BuildingCatalog.footprint_of(BuildingCatalog.choose_house_id("merchant", genome, seed_value))
		var f := BuildingCatalog.footprint_of(BuildingCatalog.choose_house_id("farmer", genome, seed_value))
		merchant_area += m.x * m.y
		farmer_area += f.x * f.y
	assert_gt(merchant_area, farmer_area)
