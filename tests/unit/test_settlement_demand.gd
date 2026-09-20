extends GutTest

## City Hall's own real "compute demands" step (see docs/concept/
## npc_role_consensus.md's "City Hall" section): reuses ConstructionPriority/
## NeedResolver's existing recipe-graph walk -- no new needs computation.
## Uses the REAL CraftingRecipeBook throughout (mirrors test_construction_
## priority.gd's own convention), not a fixture book, since this is
## specifically about what the real recipe book's real requires_structure
## gates surface today.

const SettlementDemand = preload("res://src/emergence/settlement_demand.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")

var book: CraftingRecipeBook


func before_each():
	book = CraftingRecipeBook.new()


func _demand_for(demands: Array, recipe_id: String) -> Dictionary:
	for demand in demands:
		if demand["recipe_id"] == recipe_id:
			return demand
	return {}


## With every real structure-gated recipe's own structure present, there is
## nothing to demand -- the settlement is fully producer-equipped. The list
## grew with the bread chain (docs/concept/milling_and_baking.md): farm/
## mill/bakery gate grow_wheat/mill_flour/bake_bread; and again with
## brewing (docs/concept/village_estates.md mechanism 1), where the brewery
## gates brew_beer.
func test_no_demands_when_every_gated_structure_is_present():
	var demands := SettlementDemand.demands_for(
		{}, ["sagewerk", "campfire", "farm", "mill", "bakery", "brewery"], book
	)
	assert_eq(demands, [])


## The bread chain surfaces as real City Hall demands the moment any of its
## links is missing -- "wheat needs a farm, flour needs a mill, bread needs
## a bakery" -- with no chain-specific code here: the chain is resolver
## data (docs/concept/milling_and_baking.md), and this step already walks
## every structure-gated recipe.
## A fourth demand rides along with them now and it is not noise: brewing
## (docs/concept/village_estates.md mechanism 1) draws on the SAME wheat
## grow_wheat grows, so a village with a brewery and no farm is blocked on
## the farm -- which is what the walk reports, naming the farm rather than
## the brewery it already has. Beer and bread competing for one crop is
## the intended shape, not an accident of adding a recipe.
func test_a_missing_bread_chain_surfaces_as_three_demands():
	var demands := SettlementDemand.demands_for({}, ["sagewerk", "campfire", "brewery"], book)
	assert_eq(_demand_for(demands, "grow_wheat").get("missing_structure_id"), "farm")
	assert_eq(_demand_for(demands, "mill_flour").get("missing_structure_id"), "mill")
	assert_eq(_demand_for(demands, "bake_bread").get("missing_structure_id"), "bakery")
	assert_eq(
		_demand_for(demands, "brew_beer").get("missing_structure_id"),
		"farm",
		"a brewery with no grain to brew is blocked on the farm, not on itself"
	)
	assert_eq(demands.size(), 4, "the three chain links and the grain the brewery wants")


## The brewery surfaces the same way and for the same reason: a village
## whose burghers want beer and whose brewery is not standing has a real,
## nameable demand for one (docs/concept/village_estates.md mechanism 1).
## No brewing-specific code here either -- this step already walks every
## structure-gated recipe, which is precisely why adding one showed up.
func test_a_missing_brewery_surfaces_as_a_real_demand():
	var demands := SettlementDemand.demands_for({}, ["sagewerk", "campfire", "farm", "mill", "bakery"], book)
	var brew := _demand_for(demands, "brew_beer")
	assert_eq(brew.get("missing_structure_id"), "brewery")
	assert_eq(brew.get("output_item_id"), "beer")
	assert_eq(demands.size(), 1, "exactly the brewery, nothing else")


## With NO structures present, the two real sagewerk-gated recipes (see
## docs/concept/npc_role_consensus.md's own worked example) surface as
## real demands -- this is the "wood" case the whole feature was reported
## for.
func test_a_missing_sagewerk_surfaces_beam_and_plank_demands():
	var demands := SettlementDemand.demands_for({}, [], book)
	var beam := _demand_for(demands, "log_to_balken")
	var plank := _demand_for(demands, "log_to_planke")
	assert_eq(beam.get("missing_structure_id"), "sagewerk")
	assert_eq(plank.get("missing_structure_id"), "sagewerk")


func test_demand_entries_name_their_own_real_output_item():
	var demands := SettlementDemand.demands_for({}, [], book)
	var beam := _demand_for(demands, "log_to_balken")
	assert_eq(beam.get("output_item_id"), "beam")


## A recipe with real stock and its structure present is satisfied, not
## demanded -- only a genuinely BLOCKED structure gate is a demand, matching
## ConstructionPriority's own READY/SHORTFALL/BUILD_PRODUCER_FIRST split
## (a pure material shortfall stays the existing shortfall path's own job).
func test_a_recipe_with_its_structure_present_is_not_a_demand():
	var demands := SettlementDemand.demands_for({}, ["sagewerk"], book)
	assert_eq(_demand_for(demands, "log_to_balken"), {})
	assert_eq(_demand_for(demands, "log_to_planke"), {})


## An ungated recipe (no requires_structure at all) never appears, even
## with zero stock -- that's a pure material shortfall, not a structure
## demand.
func test_an_ungated_recipe_never_appears_even_with_no_stock():
	var demands := SettlementDemand.demands_for({}, [], book)
	assert_eq(_demand_for(demands, "torch"), {})
	assert_eq(_demand_for(demands, "wooden_club"), {})


## The heat_source gate (iron_ingot/copper_ingot) is a real, already-
## documented ABSTRACT multi-structure category, not one concrete
## buildable id -- this wrapper reports that same abstract name honestly
## rather than resolving or hiding the limitation (see
## ConstructionPriority.missing_structure_id's own doc comment).
func test_an_abstract_heat_source_gate_reports_the_abstract_category_name():
	var demands := SettlementDemand.demands_for({}, [], book)
	var iron_ingot := _demand_for(demands, "iron_ingot")
	assert_eq(iron_ingot.get("missing_structure_id"), "heat_source")


## Either a campfire OR a furnace resolves the heat_source demand -- the
## same "either counts" translation ConstructionPriority already does
## internally.
func test_a_campfire_alone_resolves_the_heat_source_demand():
	var demands := SettlementDemand.demands_for({}, ["campfire"], book)
	assert_eq(_demand_for(demands, "iron_ingot"), {})
