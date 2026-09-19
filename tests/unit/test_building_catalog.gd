extends GutTest

## BuildingCatalog: the catalog of whole-building entities (docs/concept/
## building.md "Buildings are entities; interiors are scenes") -- pure data,
## the same "what is this, never may it go here" framing BuildingPiece keeps.
## A building is one id with a rectangular footprint, a door on its south
## edge and a doorstep just outside it; every sheet follows the one asset
## contract (8 columns x 5 lifecycle rows) blacksmith.png already does.

const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const BuildingLifecycleSheet = preload("res://src/rendering/building_lifecycle_sheet.gd")
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


## Asked directly, alongside the art for each: *"cottage 2x2; house 3x2;
## manor 3x3"*. The manor was 4x3 -- wider than it was deep, and wider than
## the hall -- which is what the real manor illustration then had to be
## squeezed into; it is a square building now, and the hall keeps the 4x3
## the town hall was always drawn at.
func test_the_first_three_houses_have_the_footprints_the_spec_names():
	assert_eq(BuildingCatalog.footprint_of("house_small"), Vector2i(2, 2), "cottage")
	assert_eq(BuildingCatalog.footprint_of("house_medium"), Vector2i(3, 2), "house")
	assert_eq(BuildingCatalog.footprint_of("house_large"), Vector2i(3, 3), "manor")


## And they still grow: each tier covers more ground than the one below it,
## which is what makes the ladder a ladder rather than three sizes of one
## thing.
func test_each_house_tier_still_covers_more_ground_than_the_one_below():
	var small := BuildingCatalog.footprint_of("house_small")
	var medium := BuildingCatalog.footprint_of("house_medium")
	var large := BuildingCatalog.footprint_of("house_large")
	assert_gt(medium.x * medium.y, small.x * small.y)
	assert_gt(large.x * large.y, medium.x * medium.y)


## A manor draws a manor and a cottage draws a cottage -- never the flat
## 25-cottage sheet, which is where "villages use scaled houses" came from.
func test_no_house_tier_falls_back_to_a_cottage_that_is_not_one():
	assert_eq(
		BuildingCatalog.variant_sheet_of("house_large"), "",
		"a manor with a missing sheet must not fall back to a page of cottages"
	)


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


## A readable name per building, for a readout that has to title itself.
## Kept in the catalog because it IS catalog data -- a house has no
## ItemCatalog entry to borrow a display name from (and must not get one,
## see test_no_house_is_ever_offered_at_a_crafting_bench).
func test_every_building_has_a_readable_display_name():
	var seen := {}
	for building_id in BuildingCatalog.BUILDING_IDS + BuildingCatalog.CIVIC_BUILDING_IDS + BuildingCatalog.PRODUCTION_BUILDING_IDS:
		var name: String = BuildingCatalog.display_name_of(building_id)
		assert_ne(name, "", "%s needs a name" % building_id)
		assert_ne(name, building_id, "%s must read as a name, not an id" % building_id)
		assert_false(seen.has(name), "two buildings must not share the name %s" % name)
		seen[name] = true


func test_an_unknown_id_still_gets_something_printable():
	assert_ne(BuildingCatalog.display_name_of("moon_base"), "")


# -- variant sheets: many real cottages, one building id -------------------
#
# A supplied 5x5 sheet of hand-drawn cottage variants (black background, no
# dividers, one whole house per cell) is what a finished first-tier village
# house is actually drawn from, picked per building seed -- so a street of
# cottages reads as a street of different cottages rather than one house
# repeated. The LIFECYCLE sheet contract (8 columns x 5 rows) is untouched
# and still what a RISING building's construction row comes from; a variant
# sheet has no construction/burning/ruined rows and never claims to.

## house_1.png is a page of 25 COTTAGES, and the two smaller tiers fall back
## to it. The manor does NOT, and that is the change of 2026-09-19: it has
## manor art of its own now, and one whose sheet is missing must fall
## through to the honest procedural placeholder rather than to a picture of
## a cottage. "Grander art for those tiers lands, at which point they get
## their own entries" is exactly what this test used to promise.
func test_the_two_smaller_house_tiers_fall_back_to_the_cottage_sheet():
	for building_id in ["house_small", "house_medium"]:
		assert_eq(
			BuildingCatalog.variant_sheet_of(building_id),
			"res://assets/sprites/buildings/house_1.png",
			"%s should fall back to the village cottage sheet" % building_id
		)


func test_a_building_with_no_variant_sheet_says_so_rather_than_guessing_a_path():
	for building_id in ["city_hall", "warehouse", "sawmill", "farmhouse", "blacksmith", "brewery", "moon_base"]:
		assert_eq(BuildingCatalog.variant_sheet_of(building_id), "", "%s has no variant sheet" % building_id)


## Two houses of the same tier standing side by side must not be the same
## cottage -- the whole point of a variant sheet.
func test_two_houses_with_different_seeds_usually_draw_different_cottages():
	var distinct := {}
	for seed_value in range(0, 40):
		distinct[BuildingCatalog.variant_cell_for("house_small", seed_value)] = true
	assert_gt(distinct.size(), 5, "forty houses drew only %d distinct cottages" % distinct.size())


func test_the_variant_grid_matches_the_supplied_sheets_own_shape():
	assert_eq(BuildingCatalog.VARIANT_SHEET_COLUMNS, 5)
	assert_eq(BuildingCatalog.VARIANT_SHEET_ROWS, 5)


func test_a_buildings_variant_is_deterministic_from_its_own_seed():
	for seed_value in [0, 1, 7, -3, 991, 123456789]:
		assert_eq(
			BuildingCatalog.variant_cell_for("house_small", seed_value),
			BuildingCatalog.variant_cell_for("house_small", seed_value),
			"the same house must always draw as the same cottage"
		)


func test_every_variant_cell_lands_inside_the_grid():
	for seed_value in range(-50, 200):
		var cell: Vector2i = BuildingCatalog.variant_cell_for("house_small", seed_value)
		assert_between(cell.x, 0, BuildingCatalog.VARIANT_SHEET_COLUMNS - 1, "column out of grid for %d" % seed_value)
		assert_between(cell.y, 0, BuildingCatalog.VARIANT_SHEET_ROWS - 1, "row out of grid for %d" % seed_value)


## All twenty-five are actually reachable -- a sheet whose corner variants
## never turn up is art nobody ever sees.
func test_every_one_of_the_twenty_five_variants_is_really_reachable():
	var seen := {}
	for seed_value in range(0, 4000):
		seen[BuildingCatalog.variant_cell_for("house_small", seed_value)] = true
	assert_eq(
		seen.size(), BuildingCatalog.VARIANT_SHEET_COLUMNS * BuildingCatalog.VARIANT_SHEET_ROWS,
		"only %d of the 25 variants ever appear" % seen.size()
	)


# -- which sheet a FINISHED building is drawn from -------------------------

## Superseded 2026-09-17: a finished house now prefers its own LIFECYCLE
## variation sheet (house_1_1.png .. house_1_5.png), which carries the same
## house it was while it was rising. The flat house_1.png variant sheet
## stays as the fallback below it.
func test_a_finished_first_tier_house_is_drawn_from_its_lifecycle_variation():
	var sheet: Dictionary = BuildingCatalog.finished_sheet_for("house_small", 42)
	var grid := BuildingLifecycleSheet.grid_for("house_small")
	assert_eq(sheet["path"], BuildingLifecycleSheet.sheet_for("house_small", 42))
	# Each tier's own art carries the grid it is drawn on now -- the cottage
	# and manor sheets are the 8x5 contract, house_1_* the 8x10 one.
	assert_eq(sheet["columns"], int(grid["columns"]))
	assert_eq(sheet["rows"], int(grid["rows"]))
	var cell: Vector2i = BuildingLifecycleSheet.idle_cell_for("house_small", 42)
	assert_eq(sheet["row"], cell.y)
	assert_eq(sheet["column"], cell.x)
	assert_eq(sheet["grid"], "dividers", "these sheets divide their cells with magenta lines")


func test_the_flat_variant_sheet_is_still_there_under_the_lifecycle_one():
	var chain: Array = BuildingCatalog.finished_sheet_chain("house_small", 42)
	assert_gte(chain.size(), 3, "lifecycle variation, then the flat variant sheet, then the 8x5 sheet")
	assert_eq(chain[0]["path"], BuildingLifecycleSheet.sheet_for("house_small", 42))
	assert_eq(chain[1]["path"], BuildingCatalog.variant_sheet_of("house_small"))
	assert_eq(chain[1]["grid"], "gutters", "house_1.png separates its cells with dark gutters")
	assert_eq(chain[2]["path"], BuildingCatalog.sheet_of("house_small"))
	assert_eq(chain[2]["grid"], "even")


func test_a_rising_house_walks_its_own_variations_build_frames():
	for progress in [0.0, 0.3, 0.7, 1.0]:
		var sheet: Dictionary = BuildingCatalog.construction_sheet_for("house_small", 42, progress)
		assert_eq(
			sheet["path"], BuildingLifecycleSheet.sheet_for("house_small", 42),
			"a house must rise as the house it is going to be, not as a different one"
		)
		var cell: Vector2i = BuildingLifecycleSheet.build_cell_for("house_small", progress)
		assert_eq(sheet["row"], cell.y)
		assert_eq(sheet["column"], cell.x)
		assert_true(BuildingLifecycleSheet.grid_for("house_small")["build_rows"].has(sheet["row"]))


func test_a_rising_building_with_no_variations_keeps_the_old_construction_row():
	var sheet: Dictionary = BuildingCatalog.construction_sheet_for("city_hall", 7, 0.5)
	assert_eq(sheet["path"], BuildingCatalog.sheet_of("city_hall"))
	assert_eq(sheet["row"], BuildingCatalog.ROW_CONSTRUCTION)
	assert_eq(sheet["column"], BuildingCatalog.construction_stage_for(0.5))
	assert_eq(sheet["grid"], "even")


func test_a_rising_house_falls_back_to_the_old_construction_row_too():
	var chain: Array = BuildingCatalog.construction_sheet_chain("house_small", 42, 0.5)
	assert_gte(chain.size(), 2)
	assert_eq(chain[chain.size() - 1]["path"], BuildingCatalog.sheet_of("house_small"))
	assert_eq(chain[chain.size() - 1]["row"], BuildingCatalog.ROW_CONSTRUCTION)


func test_every_sheet_choice_names_how_its_grid_is_read():
	for building_id in ["house_small", "city_hall", "sawmill"]:
		for entry in (
			BuildingCatalog.finished_sheet_chain(building_id, 5)
			+ BuildingCatalog.construction_sheet_chain(building_id, 5, 0.4)
		):
			assert_true(
				["even", "gutters", "dividers"].has(entry["grid"]),
				"%s names its grid as %s, which nothing knows how to read" % [building_id, entry["grid"]]
			)


## Everything without a variant sheet keeps the lifecycle sheet's idle row,
## exactly as before -- this is additive art, not a change of contract.
func test_every_other_building_still_comes_from_its_lifecycle_sheets_idle_row():
	for building_id in ["city_hall", "warehouse", "sawmill", "brewery"]:
		var sheet: Dictionary = BuildingCatalog.finished_sheet_for(building_id, 7)
		assert_eq(sheet["path"], BuildingCatalog.sheet_of(building_id))
		assert_eq(sheet["columns"], BuildingCatalog.SHEET_COLUMNS)
		assert_eq(sheet["rows"], BuildingCatalog.SHEET_ROWS)
		assert_eq(sheet["row"], BuildingCatalog.ROW_IDLE)
		assert_eq(sheet["column"], 0)


## A RISING building still comes from the lifecycle sheet's construction
## row: a variant sheet has no scaffold stages and must never be asked for
## one.
## Still true of the FLAT variant sheet, which has no scaffold stages at
## all. The lifecycle variation sheets are a different thing entirely --
## they carry their own build rows, which is the whole point of them.
func test_a_rising_building_is_never_drawn_from_the_flat_variant_sheet():
	for progress in [0.0, 0.5, 1.0]:
		for entry in BuildingCatalog.construction_sheet_chain("house_small", 3, progress):
			assert_ne(
				entry["path"], BuildingCatalog.variant_sheet_of("house_small"),
				"the flat variant sheet draws 25 FINISHED cottages and no scaffold"
			)


# -- every building holds its own goods -------------------------------------
#
# Asked for directly: "Farmhouses, Sawmills, Houses should have their own
# small storage where e.g. a villager keeps his acquired goods; the farmhouse
# stockpiles wheat until the storage is full". See
# docs/concept/building_storage.md.


func test_a_house_holds_a_households_own_goods():
	for house_id in BuildingCatalog.BUILDING_IDS:
		assert_gt(
			BuildingCatalog.storage_capacity_of(house_id), 0,
			"%s is a home with things in it, not a sleeping box" % house_id
		)


func test_every_production_building_holds_what_it_produces():
	for building_id in BuildingCatalog.PRODUCTION_BUILDING_IDS:
		assert_gt(
			BuildingCatalog.storage_capacity_of(building_id), 0,
			"%s produces goods that have to sit somewhere" % building_id
		)


## A workplace holds more than a home: a farmhouse has to keep working
## between collections, a house only keeps what one household owns.
func test_a_workplace_holds_more_than_a_home():
	assert_gt(
		BuildingCatalog.storage_capacity_of("farmhouse"),
		BuildingCatalog.storage_capacity_of("house_small")
	)


## The warehouse is the village's granary -- that is the whole point of the
## building, so it holds more than anything that feeds it.
func test_the_warehouse_holds_more_than_anything_that_feeds_it():
	var warehouse := BuildingCatalog.storage_capacity_of("warehouse")
	for building_id in BuildingCatalog.PRODUCTION_BUILDING_IDS + BuildingCatalog.BUILDING_IDS:
		assert_gt(
			warehouse, BuildingCatalog.storage_capacity_of(building_id),
			"a granary smaller than a %s would never be worth hauling to" % building_id
		)


## Somewhere goods are NOT kept: a hall is where a village decides things.
func test_a_building_that_keeps_no_goods_says_so():
	assert_eq(BuildingCatalog.storage_capacity_of("city_hall"), 0)
	assert_eq(BuildingCatalog.storage_capacity_of("not_a_building"), 0)


## Every building the catalog knows answers the question, so no caller ever
## has to special-case an id.
func test_every_building_in_the_catalog_answers_at_all():
	var every: Array = (
		BuildingCatalog.BUILDING_IDS + BuildingCatalog.CIVIC_BUILDING_IDS
		+ BuildingCatalog.PRODUCTION_BUILDING_IDS
	)
	for building_id in every:
		assert_gte(BuildingCatalog.storage_capacity_of(building_id), 0, building_id)


# -- a house no grander than its household's standing -----------------------
#
# Asked directly: *"The village should not produce Manors from the beginning
# only cottages and once all villagers needs are stable in the green they can
# upgrade to houses"*.
#
# The estate layer (docs/concept/village_estates.md) already says which house
# an estate lives in, and every household is founded a kossaet -- but
# choose_house_id never asked. It draws from the OCCUPATION's pool, so a
# founding merchant (whose pool is medium/large/large/large) raised a manor
# on day one, before the village had fed anybody.
#
# So the pool is CAPPED by what the household is entitled to. Occupation and
# personality still choose within that cap -- a showy merchant cottager gets
# the grandest cottage there is, which is still a cottage.


func test_a_household_entitled_to_a_cottage_never_builds_a_manor():
	var genome := NpcGenome.new(3, _TRAIT_NAMES)
	for occupation in BuildingCatalog.HOUSE_POOL_BY_OCCUPATION:
		for seed_value in range(40):
			assert_eq(
				BuildingCatalog.choose_house_id(occupation, genome, seed_value, "house_small"),
				"house_small",
				"%s built above their standing" % occupation
			)


## The cap is a ceiling, not a fixed answer: a household entitled to a house
## may still live in a cottage if that is what their trade and character
## would have built.
##
## Asked of a FARMER, whose pool really spans the cap (cottage, cottage,
## house). A merchant's does not -- theirs is house/manor/manor/manor, so
## capped at a house there is exactly one thing left for them to build, and
## that is the cap doing its job rather than an assignment.
func test_the_cap_is_a_ceiling_rather_than_an_assignment():
	var seen := {}
	for seed_value in range(120):
		var genome := NpcGenome.new(seed_value, _TRAIT_NAMES)
		var id: String = BuildingCatalog.choose_house_id("farmer", genome, seed_value, "house_medium")
		assert_ne(id, "house_large", "above the cap")
		seen[id] = true
	assert_gt(seen.size(), 1, "a ceiling that only ever answers one thing is an assignment")


## And a pool with nothing at or below the cap still answers with a real
## house: a merchant entitled only to a cottage lives in a cottage, rather
## than in nothing at all.
func test_a_pool_with_nothing_under_the_cap_still_houses_the_household():
	var genome := NpcGenome.new(11, _TRAIT_NAMES)
	assert_eq(
		BuildingCatalog.choose_house_id("merchant", genome, 11, "house_small"), "house_small"
	)


## No cap named is exactly today's behaviour, so every caller that has not
## been taught about standing yet is untouched.
func test_naming_no_cap_leaves_the_choice_exactly_as_it_was():
	for occupation in BuildingCatalog.HOUSE_POOL_BY_OCCUPATION:
		for seed_value in range(30):
			var genome := NpcGenome.new(seed_value, _TRAIT_NAMES)
			assert_eq(
				BuildingCatalog.choose_house_id(occupation, genome, seed_value, ""),
				BuildingCatalog.choose_house_id(occupation, genome, seed_value)
			)


## And an unknown cap is no cap, never an empty answer -- a caller that
## passes something this catalog has never heard of still gets a real house.
func test_an_unknown_cap_still_answers_with_a_real_house():
	var genome := NpcGenome.new(5, _TRAIT_NAMES)
	assert_true(
		BuildingCatalog.BUILDING_IDS.has(
			BuildingCatalog.choose_house_id("farmer", genome, 5, "not_a_house")
		)
	)


# -- a building stands IN its plot, not across it -------------------------

## Reported live with a screenshot of three cottages in a row: "make the
## cottages a bit smaller and add a padding so they have a gap between them
## and the top doesn't get clipped".
##
## The cause was not the slicer. Measured on the real sheets, every
## finished cottage frame has ZERO transparent pixels on all four edges --
## the cell bands are cut tight to the art by construction -- and that
## tight crop was then scaled to exactly the plot width. So neighbouring
## houses touched at the pixel, and a roof that reaches well above its own
## plot ran straight into whatever stood north of it.
##
## A building is drawn INSIDE its plot now, leaving PLOT_MARGIN_SHARE of
## the plot free on each side.
func test_a_building_is_drawn_narrower_than_the_plot_it_stands_on():
	for footprint_width in [1, 2, 3, 4]:
		assert_lt(
			BuildingCatalog.drawn_plot_width_tiles(footprint_width),
			float(footprint_width),
			"a %d-tile building fills its whole plot" % footprint_width
		)


## But it still reads as a building on that plot rather than a model of
## one: most of the ground it claims is covered.
func test_a_building_still_covers_most_of_its_own_plot():
	for footprint_width in [1, 2, 3, 4]:
		assert_gt(
			BuildingCatalog.drawn_plot_width_tiles(footprint_width) / float(footprint_width),
			0.75,
			"a %d-tile building shrank into its own plot" % footprint_width
		)


## The claim the report was actually about: two houses on ADJACENT plots
## stand a visible distance apart. A quarter of a tile is the floor,
## because anything under that is a seam rather than a gap at the size a
## tile is really drawn.
func test_two_houses_on_neighbouring_plots_really_stand_apart():
	for building_id in BuildingCatalog.BUILDING_IDS:
		var plot_width: int = BuildingCatalog.footprint_of(building_id).x
		var gap: float = float(plot_width) - BuildingCatalog.drawn_plot_width_tiles(plot_width)
		assert_gt(gap, 0.25, "two %s side by side are %f tiles apart" % [building_id, gap])


## The margin is the SAME on both sides, so a building stands in the middle
## of its plot rather than shouldered against one edge.
func test_the_margin_is_centred_so_a_building_is_not_shouldered_to_one_side():
	var plot := 3
	var margin: float = (float(plot) - BuildingCatalog.drawn_plot_width_tiles(plot)) * 0.5
	assert_almost_eq(
		BuildingCatalog.drawn_plot_width_tiles(plot) + margin * 2.0, float(plot), 0.0001
	)


## A nonsense plot is treated as the smallest real one rather than
## returning zero or a negative width -- a building drawn at no width at
## all is a building nobody can see.
func test_a_nonsense_plot_still_draws_something():
	for plot in [0, -3]:
		assert_gt(BuildingCatalog.drawn_plot_width_tiles(plot), 0.0)
