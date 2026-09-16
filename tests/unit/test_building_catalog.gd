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
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")

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


# -- touches_building: the tree-apron rule, generalized ---------------------

func test_touches_building_is_true_for_the_cell_itself_and_every_neighbour():
	var modifications := {Vector2i(5, 5): "house_small"}
	assert_true(BuildingCatalog.touches_building(modifications, Vector2i(5, 5)), "the cell itself")
	assert_true(BuildingCatalog.touches_building(modifications, Vector2i(6, 6)), "diagonal neighbour")
	assert_true(BuildingCatalog.touches_building(modifications, Vector2i(5, 4)), "cardinal neighbour")
	assert_false(BuildingCatalog.touches_building(modifications, Vector2i(7, 5)), "two cells away")


func test_touches_building_is_true_for_a_footprint_marker_cell_too_not_just_the_anchor():
	var modifications := {Vector2i(5, 5): "house_small", Vector2i(6, 5): BuildingCatalog.FOOTPRINT_TILE_ID}
	assert_true(BuildingCatalog.touches_building(modifications, Vector2i(6, 4)), "neighbour of the footprint marker cell")


func test_touches_building_is_false_for_a_non_building_modification():
	var modifications := {Vector2i(5, 5): "campfire"}
	assert_false(BuildingCatalog.touches_building(modifications, Vector2i(5, 5)), "a single-tile placeable is not a building")


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


# -- civic buildings (docs/concept/civic_construction.md): the City Hall -----
#
# A real catalog entity a village raises on its own plaza over time (see
# VillageLayout.skeleton's civic plot and EarthChunkManager's civic build
# decision), drawn from the city_hall.png sheet that already follows the
# asset contract -- and NEVER a house: choose_house_id must not hand a
# villager a town hall to live in.

func test_the_city_hall_is_a_real_civic_building_and_not_a_house():
	assert_true(BuildingCatalog.has_building("city_hall"))
	assert_true(BuildingCatalog.CIVIC_BUILDING_IDS.has("city_hall"))
	assert_false(BuildingCatalog.BUILDING_IDS.has("city_hall"), "never in the house pool")
	assert_eq(BuildingCatalog.footprint_of("city_hall"), Vector2i(4, 3))
	assert_eq(BuildingCatalog.capacity_of("city_hall"), 0, "nobody lives in the town hall")
	assert_eq(BuildingCatalog.sheet_of("city_hall"), "res://assets/sprites/buildings/city_hall.png")
	assert_eq(BuildingCatalog.doorstep_of("city_hall"), Vector2i(2, 3), "door on the south edge, doorstep just outside")


## Its price is the SAME wood 20 + stone 10 the legacy city_hall placeable
## recipe already charges (CraftingRecipeBook) -- one number, not two.
func test_the_city_halls_cost_matches_the_legacy_recipes_inputs():
	var inputs: Array = CraftingRecipeBook.new().recipe_inputs("city_hall")
	assert_false(inputs.is_empty(), "precondition: the legacy recipe exists")
	var expected := {}
	for input in inputs:
		expected[input["item_id"]] = input["count"]
	assert_eq(BuildingCatalog.cost_of("city_hall"), expected)
	assert_gt(BuildingCatalog.labor_hours_of("city_hall"), BuildingCatalog.labor_hours_of("house_large"), "a hall is more work than any house")


# -- the construction row: which stage a rising building shows ------------

func test_construction_stage_walks_the_eight_columns_from_scaffold_to_roof():
	assert_eq(BuildingCatalog.construction_stage_for(0.0), 0)
	assert_eq(BuildingCatalog.construction_stage_for(0.124), 0)
	assert_eq(BuildingCatalog.construction_stage_for(0.125), 1)
	assert_eq(BuildingCatalog.construction_stage_for(0.5), 4)
	assert_eq(BuildingCatalog.construction_stage_for(0.99), 7)
	assert_eq(BuildingCatalog.construction_stage_for(1.0), 7, "complete never overruns the row")
	assert_eq(BuildingCatalog.construction_stage_for(-0.5), 0)
	assert_eq(BuildingCatalog.construction_stage_for(3.0), 7)


func test_the_hall_labour_matches_its_recipe_derived_hours():
	# ConstructionLabor derives a project's hours from its recipe's material
	# (HOURS_PER_UNIT_MATERIAL per unit); the catalog's own figure for the
	# hall must be that same number, or the site sprite and the ledger
	# would disagree on how far along the hall is.
	var ConstructionLabor = load("res://src/emergence/construction_labor.gd")
	var book = load("res://src/gameplay/crafting_recipe_book.gd").new()
	assert_almost_eq(
		BuildingCatalog.labor_hours_of("city_hall"), ConstructionLabor.labor_hours_required("city_hall", book), 0.001
	)


# -- the growth ladder's production and civic buildings --------------------
#
# docs/concept/village_growth.md's own ladder: a village raises a sawmill,
# a warehouse, a farmhouse, a blacksmith and a brewery as its population
# grows, alongside the city hall it already raises. Every one is a real
# catalog entity with a real sheet on disk, nobody lives in any of them,
# and every one costs ONLY material a settlement can actually gather for
# itself (SettlementGathering stocks wood, stone and plant_fibre -- a rung
# priced in anything else could never be raised autonomously).

const _LADDER_BUILDING_IDS := ["sawmill", "warehouse", "farmhouse", "blacksmith", "brewery"]


func test_every_ladder_building_is_a_real_catalog_entity_nobody_lives_in():
	for building_id in _LADDER_BUILDING_IDS:
		assert_true(BuildingCatalog.has_building(building_id), "%s must be a real building" % building_id)
		assert_false(BuildingCatalog.BUILDING_IDS.has(building_id), "%s must never be a home" % building_id)
		assert_eq(BuildingCatalog.capacity_of(building_id), 0, "nobody lives in the %s" % building_id)
		assert_ne(BuildingCatalog.interior_family_of(building_id), "", "%s needs an interior family" % building_id)


func test_the_production_building_ids_list_is_exactly_the_non_civic_ladder():
	assert_eq(BuildingCatalog.PRODUCTION_BUILDING_IDS, ["sawmill", "farmhouse", "blacksmith", "brewery"] as Array[String])
	assert_true(BuildingCatalog.CIVIC_BUILDING_IDS.has("warehouse"), "a warehouse is a commons, not a trade")
	assert_true(BuildingCatalog.CIVIC_BUILDING_IDS.has("city_hall"))


## The sheets already exist in the repo -- this is what makes the ladder
## art-complete rather than a row of procedural placeholders.
func test_every_ladder_building_has_a_real_sheet_file_on_disk():
	for building_id in _LADDER_BUILDING_IDS:
		var path: String = BuildingCatalog.sheet_of(building_id)
		assert_eq(path, "res://assets/sprites/buildings/%s.png" % building_id)
		assert_true(FileAccess.file_exists(path), "%s has no real sheet at %s" % [building_id, path])


## Every rung must be payable out of what SettlementGathering actually
## gathers, or the village can never raise it on its own.
func test_every_ladder_building_costs_only_material_a_village_can_gather():
	var SettlementGathering = load("res://src/emergence/settlement_gathering.gd")
	var gatherable := {}
	for item_id in ["wood", "stone", "plant_fibre"]:
		gatherable[item_id] = true
		assert_gt(
			float(SettlementGathering.material_delta(1, 86400.0, {})["stock_delta"].get(item_id, 0)), 0.0,
			"precondition: a village really gathers %s" % item_id
		)
	for building_id in _LADDER_BUILDING_IDS + ["city_hall"]:
		var cost: Dictionary = BuildingCatalog.cost_of(building_id)
		assert_false(cost.is_empty(), "%s must cost something" % building_id)
		for item_id in cost:
			assert_true(gatherable.has(item_id), "%s costs un-gatherable %s" % [building_id, item_id])


## Ladder order is also price order: a village pays more for each rung it
## grows into. Pinned against the ORDER, not any one "correct" price.
func test_each_ladder_rung_costs_more_material_than_the_one_before_it():
	var ladder := ["sawmill", "farmhouse", "warehouse", "city_hall", "blacksmith", "brewery"]
	var previous := 0
	for building_id in ladder:
		var total := 0
		for item_id in BuildingCatalog.cost_of(building_id):
			total += int(BuildingCatalog.cost_of(building_id)[item_id])
		assert_gt(total, previous, "%s must cost more material than the rung before it" % building_id)
		previous = total


## Same contract the hall already keeps: the catalog's labour figure and
## ConstructionLabor's recipe-derived one must agree, or a rising
## building's sprite and the ledger disagree on how far along it is.
func test_every_ladder_buildings_cost_and_labour_match_its_recipe():
	var ConstructionLabor = load("res://src/emergence/construction_labor.gd")
	var book = CraftingRecipeBook.new()
	for building_id in _LADDER_BUILDING_IDS:
		var inputs: Array = book.recipe_inputs(building_id)
		assert_false(inputs.is_empty(), "%s needs a real recipe" % building_id)
		var expected := {}
		for input in inputs:
			expected[input["item_id"]] = input["count"]
		assert_eq(BuildingCatalog.cost_of(building_id), expected, "%s cost must be its recipe" % building_id)
		assert_almost_eq(
			BuildingCatalog.labor_hours_of(building_id),
			ConstructionLabor.labor_hours_required(building_id, book), 0.001,
			"%s labour must be its recipe-derived hours" % building_id
		)


## Every street-placed building must fit the street pitch VillageLayout
## reserves between one row and the next -- the pitch is derived from the
## catalog's own deepest footprint, so a deeper entry can never silently
## make two streets overlap.
func test_no_catalog_building_is_deeper_than_the_street_pitch_reserves():
	var VillageLayout = load("res://src/world/village_layout.gd")
	var deepest := 0
	for building_id in BuildingCatalog.BUILDING_IDS + BuildingCatalog.CIVIC_BUILDING_IDS + BuildingCatalog.PRODUCTION_BUILDING_IDS:
		deepest = maxi(deepest, BuildingCatalog.footprint_of(building_id).y)
	assert_eq(
		VillageLayout.STREET_PITCH_TILES, deepest + VillageLayout.STREET_GAP_TILES,
		"the street pitch must reserve the deepest real footprint plus the gap"
	)


# -- houses are buildings, not items ---------------------------------------
#
# A house the village raises for an arriving household goes up through the
# SAME ConstructionProject ledger every other building does, so it needs a
# real recipe: without one, recipe_inputs is empty, try_start finds nothing
# to wait on, ConstructionLabor derives zero hours, and the house completes
# instantly and for free on the tick it is queued.

func test_every_house_has_a_real_recipe_at_exactly_its_catalog_price():
	var ConstructionLabor = load("res://src/emergence/construction_labor.gd")
	var book = CraftingRecipeBook.new()
	for building_id in BuildingCatalog.BUILDING_IDS:
		var inputs: Array = book.recipe_inputs(building_id)
		assert_false(inputs.is_empty(), "%s needs a real recipe to be raised over time" % building_id)
		var expected := {}
		for input in inputs:
			expected[input["item_id"]] = input["count"]
		assert_eq(BuildingCatalog.cost_of(building_id), expected, "%s: one price, not two" % building_id)
		assert_gt(ConstructionLabor.labor_hours_required(building_id, book), 0.0, "%s must take real work" % building_id)


## A house is a building, not something a player carries home from a
## workbench. It has no ItemCatalog entry, which is exactly what keeps it
## off every bench surface -- no extra gate needed.
func test_no_house_is_ever_offered_at_a_crafting_bench():
	var book = CraftingRecipeBook.new()
	var catalog = load("res://src/gameplay/item_catalog.gd").new()
	var bench: Array = book.bench_recipe_ids(catalog)
	for building_id in BuildingCatalog.BUILDING_IDS:
		assert_false(catalog.has(building_id), "%s must not be a carryable item" % building_id)
		assert_false(bench.has(building_id), "%s must never appear at a bench" % building_id)
