extends GutTest

## The dependency-chain priority decision from docs/concept/timber_
## construction.md's "Storage, logistics, and the autonomous dependency
## chain" section: given a target recipe and what a settlement has on hand
## right now, decide whether the real priority is "build the missing
## producer first" or "the existing shortfall/regional-trade path already
## covers this".
##
## Honesty note: the task brief this was implemented from named a
## NeedResolver module to call here -- no such module exists in this
## codebase (see this doc section's own gap note). This instead composes two
## already-real mechanisms directly: CraftingRecipeBook's real recipe data,
## and Smelting.can_smelt's already-proven "is this recipe gated on a
## present structure" check (Player.craft already heat-gates smelting
## recipes the same way, see scenes/player.gd).

const ConstructionPriority = preload("res://src/gameplay/construction_priority.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")

var priority: ConstructionPriority
var book: CraftingRecipeBook


func before_each():
	priority = ConstructionPriority.new()
	book = CraftingRecipeBook.new()


func test_unknown_recipe_is_ready_with_nothing_to_block_on():
	assert_eq(priority.decide("not_a_real_recipe", {}, [], book), ConstructionPriority.Priority.READY)


func test_a_non_structure_gated_recipe_with_enough_stock_is_ready():
	var stock := {"wood": 3}
	assert_eq(priority.decide("wooden_club", stock, [], book), ConstructionPriority.Priority.READY)


func test_a_non_structure_gated_recipe_short_on_material_is_a_shortfall():
	var stock := {"wood": 1}
	assert_eq(priority.decide("wooden_club", stock, [], book), ConstructionPriority.Priority.SHORTFALL)


## iron_ingot is a real smelting recipe (Smelting.is_smelting_recipe) --
## gated on a heat source (campfire/furnace) actually being present, the
## same gate Player.craft already enforces for the player.
func test_a_structure_gated_recipe_with_no_structure_present_is_build_producer_first():
	var stock := {"iron_ore": 5, "coal": 5}
	assert_eq(
		priority.decide("iron_ingot", stock, [], book), ConstructionPriority.Priority.BUILD_PRODUCER_FIRST
	)


func test_a_structure_gated_recipe_with_the_structure_present_and_enough_stock_is_ready():
	var stock := {"iron_ore": 5, "coal": 5}
	assert_eq(
		priority.decide("iron_ingot", stock, ["furnace"], book), ConstructionPriority.Priority.READY
	)


## The structure being present resolves the PRODUCER gate; a real material
## shortfall on TOP of that is still reported as a shortfall, not READY --
## having a furnace doesn't conjure ore.
func test_a_structure_gated_recipe_with_the_structure_present_but_short_on_material_is_a_shortfall():
	var stock := {"iron_ore": 1}
	assert_eq(
		priority.decide("iron_ingot", stock, ["furnace"], book), ConstructionPriority.Priority.SHORTFALL
	)


## A campfire is a real heat source too (Player._has_heat_source checks
## both) -- not just furnace.
func test_campfire_also_satisfies_the_heat_source_gate():
	var stock := {"iron_ore": 5, "coal": 5}
	assert_eq(
		priority.decide("iron_ingot", stock, ["campfire"], book), ConstructionPriority.Priority.READY
	)
