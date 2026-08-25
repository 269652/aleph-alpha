extends GutTest

## The dependency-chain priority decision from docs/concept/timber_
## construction.md's "Storage, logistics, and the autonomous dependency
## chain" section: given a target recipe and what a settlement has on hand
## right now, decide whether the real priority is "build the missing
## producer first" or "the existing shortfall/regional-trade path already
## covers this".
##
## Now a thin wrapper over the real, general NeedResolver (src/gameplay/
## need_resolver.gd) rather than composing CraftingRecipeBook +
## Smelting.can_smelt directly -- see docs/concept/production_chains.md's
## own mechanism section. A "structure" or "skill" need anywhere in
## NeedResolver's recursive walk means BUILD_PRODUCER_FIRST (something must
## be built/trained before this can happen at all, regardless of materials);
## a plain "material" need with no structure/skill need means SHORTFALL (the
## existing regional-trade/shortfall path already covers a pure materials
## gap). No need at all means READY.

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


## A real behavioral gap the old Smelting-only composition could not see:
## "sagewerk" is not a smelting recipe, so the old code never checked its
## required_skill (Carpentry) at all -- it would have reported READY with
## enough materials and no skill whatsoever. NeedResolver's generic walk
## checks required_skill for every recipe, not just smelts, and a missing
## skill is exactly the same "something must exist before this can happen
## at all, regardless of material stock" situation a missing structure is --
## so it maps to the same BUILD_PRODUCER_FIRST priority.
func test_a_skill_gated_recipe_with_no_skill_present_is_build_producer_first():
	var stock := {"log": 8, "wood": 4}
	assert_eq(
		priority.decide("sagewerk", stock, [], book), ConstructionPriority.Priority.BUILD_PRODUCER_FIRST
	)


## Passing real allocated_nodes that satisfy the skill threshold (the same
## carpentry_1 + carpentry_2 nodes test_player.gd's own sagewerk craft test
## allocates) clears the gate.
func test_a_skill_gated_recipe_with_the_skill_allocated_is_ready():
	var stock := {"log": 8, "wood": 4}
	var allocated_nodes := {"carpentry_1": true, "carpentry_2": true}
	assert_eq(
		priority.decide("sagewerk", stock, [], book, allocated_nodes),
		ConstructionPriority.Priority.READY
	)


## Multi-hop: log_to_balken needs a Sägewerk (structure) AND its own log
## input. With the structure present but the log short, NeedResolver's
## recursive walk still reports the material gap two levels down --
## BUILD_PRODUCER_FIRST wins over SHORTFALL whenever ANY structure/skill
## need exists anywhere in the walk, per this function's own doc comment.
func test_a_multi_hop_recipe_with_structure_present_but_material_short_reports_build_producer_first_only_when_structure_missing():
	var stock := {"log": 0}
	assert_eq(
		priority.decide("log_to_balken", stock, [], book), ConstructionPriority.Priority.BUILD_PRODUCER_FIRST
	)


## Same recipe, structure present: the only remaining need is the material
## shortfall, which now correctly reports SHORTFALL.
func test_a_multi_hop_recipe_with_structure_present_and_material_short_is_a_shortfall():
	var stock := {"log": 0}
	assert_eq(
		priority.decide("log_to_balken", stock, ["sagewerk"], book), ConstructionPriority.Priority.SHORTFALL
	)


## A real, small behavioral widening from rebuilding on NeedResolver (see
## decide's own doc comment): NeedResolver resolves from the recipe's OWN
## output item, so a target that's already fully stocked reports READY
## outright -- even with zero of the recipe's own input on hand -- rather
## than checking inputs regardless the way the old can_craft-only
## composition always did. Nothing more needs to happen if you already have
## enough beam.
func test_an_already_stocked_output_is_ready_even_with_no_input_material():
	var stock := {"beam": 4, "log": 0}
	assert_eq(
		priority.decide("log_to_balken", stock, [], book), ConstructionPriority.Priority.READY
	)
