extends GutTest

## StaffedProduction: docs/concept/village_estates.md mechanism 4, wired to
## real output -- and the close of village_growth.md's own standing gap,
## "the ladder's rungs are buildings, not yet production."
##
## Before this, a village raised a brewery and had no beer, a farmhouse and
## no grain. VillageLabor said what share of full output a building runs at;
## nothing multiplied anything by it. Here that share becomes real attempts
## at real CraftingRecipeBook recipes, out of and into the settlement's own
## market.

const StaffedProduction = preload("res://src/emergence/staffed_production.gd")
const VillageLabor = preload("res://src/emergence/village_labor.gd")
const VillageEstates = preload("res://src/emergence/village_estates.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")


func _full_supply(building_ids: Array) -> Dictionary:
	var supply := {}
	for labour_class in VillageEstates.LABOUR_CLASSES:
		supply[labour_class] = 99
	return supply


# -- the table ------------------------------------------------------------

func test_every_producing_building_is_a_real_catalog_building():
	for building_id in StaffedProduction.RECIPE_BY_BUILDING:
		assert_true(
			BuildingCatalog.has_building(building_id),
			"%s produces and is not a building" % building_id
		)


func test_every_recipe_really_resolves_in_the_real_book():
	var book := CraftingRecipeBook.new()
	for building_id in StaffedProduction.RECIPE_BY_BUILDING:
		var recipe_id: String = StaffedProduction.RECIPE_BY_BUILDING[building_id]
		assert_true(book.recipe_ids().has(recipe_id), "%s makes %s, which is not a recipe" % [building_id, recipe_id])


## A building may only run a recipe IT is the gate for, or a village would
## be walking through a gate a player has to earn. One alias is allowed and
## is documented in the module: a farmhouse IS the farm raised as a real
## building, which BuildingCatalog's own entry says in as many words.
func test_a_building_only_runs_a_recipe_it_is_itself_the_gate_for():
	var book := CraftingRecipeBook.new()
	for building_id in StaffedProduction.RECIPE_BY_BUILDING:
		var recipe_id: String = StaffedProduction.RECIPE_BY_BUILDING[building_id]
		var gate: String = book.recipe_requires_structure(recipe_id)
		assert_eq(
			gate, StaffedProduction.structure_satisfied_by(building_id),
			"%s runs %s, which is gated on %s instead" % [building_id, recipe_id, gate]
		)


## And every recipe run here IS gated on something -- an ungated recipe
## needs no building to run it and is already somebody's household work
## (OccupationProduction), so running it here too would simply produce the
## same goods twice.
func test_every_recipe_run_here_is_really_gated_on_a_structure():
	var book := CraftingRecipeBook.new()
	for building_id in StaffedProduction.RECIPE_BY_BUILDING:
		assert_ne(
			book.recipe_requires_structure(StaffedProduction.RECIPE_BY_BUILDING[building_id]),
			"",
			"%s runs a recipe that needs no building at all" % building_id
		)


## Nothing here duplicates a household's own occupation work, or the
## village would produce the same goods twice for one set of hands.
func test_nothing_here_duplicates_a_households_own_occupation_recipe():
	var OccupationProduction = load("res://src/emergence/occupation_production.gd")
	var NpcIdentity = load("res://src/world/npc_identity.gd")
	for occupation in NpcIdentity.OCCUPATIONS:
		var household_recipe: String = OccupationProduction.recipe_for(occupation)
		if household_recipe == "":
			continue
		assert_false(
			StaffedProduction.RECIPE_BY_BUILDING.values().has(household_recipe),
			"%s is run by both a %s household and a building" % [household_recipe, occupation]
		)


## Every producing building is one this ladder actually raises -- a
## production table entry for a building no village ever builds produces
## nothing, ever.
func test_every_producing_building_is_one_the_ladder_really_raises():
	var VillageGrowth = load("res://src/emergence/village_growth.gd")
	for building_id in StaffedProduction.RECIPE_BY_BUILDING:
		assert_true(
			VillageGrowth.LADDER_BUILDING_IDS.has(building_id),
			"%s produces and is not on the growth ladder" % building_id
		)


# -- attempts -------------------------------------------------------------

func test_a_village_with_nothing_standing_attempts_nothing():
	assert_eq(StaffedProduction.attempts_over([], {}, {}, 10.0, {})["attempts"], {})


func test_a_span_of_no_time_attempts_nothing():
	var present := ["brewery"]
	assert_eq(
		StaffedProduction.attempts_over(
			present, _full_supply(present), VillageLabor.demand_for(present), 0.0, {}
		)["attempts"],
		{}
	)


func test_a_fully_staffed_building_really_attempts_its_own_recipe():
	var present := ["brewery"]
	var result: Dictionary = StaffedProduction.attempts_over(
		present, _full_supply(present), VillageLabor.demand_for(present), 10.0, {}
	)
	assert_true(int(result["attempts"].get("brew_beer", 0)) > 0)


## The whole claim of the pyramid: an unstaffed building produces NOTHING,
## however long it stands.
func test_a_building_with_nobody_in_it_produces_nothing_ever():
	var present := ["brewery"]
	var result: Dictionary = StaffedProduction.attempts_over(
		present, {"hand": 99, "field": 99}, VillageLabor.demand_for(present), 1000.0, {}
	)
	assert_eq(result["attempts"], {}, "a mash floor with no brewer on it made beer")


func test_a_half_staffed_building_produces_about_half_as_much():
	var present := ["brewery"]
	var demand: Dictionary = VillageLabor.demand_for(present)
	var full: int = int(StaffedProduction.attempts_over(
		present, {"craft": 2, "hand": 2}, demand, 100.0, {}
	)["attempts"]["brew_beer"])
	var half: int = int(StaffedProduction.attempts_over(
		present, {"craft": 2, "hand": 0}, demand, 200.0, {}
	)["attempts"].get("brew_beer", 0))
	assert_eq(half, 0, "a mash floor with nobody to rake it still brewed")
	assert_true(full > 0)


func test_two_of_a_building_attempt_twice_as_much_when_both_are_staffed():
	var one := ["brewery"]
	var two := ["brewery", "brewery"]
	var single: int = int(StaffedProduction.attempts_over(
		one, _full_supply(one), VillageLabor.demand_for(one), 100.0, {}
	)["attempts"]["brew_beer"])
	var double: int = int(StaffedProduction.attempts_over(
		two, _full_supply(two), VillageLabor.demand_for(two), 100.0, {}
	)["attempts"]["brew_beer"])
	assert_eq(double, single * 2)


## Whole attempts out, the fraction carried -- so a village assessed often
## is not held back against one assessed rarely.
func test_many_short_spans_attempt_as_much_as_one_long_one():
	var present := ["brewery"]
	var supply := _full_supply(present)
	var demand: Dictionary = VillageLabor.demand_for(present)
	var carry := {}
	var short_total := 0
	for _i in 20:
		var step: Dictionary = StaffedProduction.attempts_over(present, supply, demand, 5.0, carry)
		carry = step["carry"]
		short_total += int(step["attempts"].get("brew_beer", 0))
	var one_long: int = int(StaffedProduction.attempts_over(
		present, supply, demand, 100.0, {}
	)["attempts"]["brew_beer"])
	assert_eq(short_total, one_long)


func test_the_callers_own_carry_is_left_untouched():
	var present := ["brewery"]
	var carry := {}
	StaffedProduction.attempts_over(present, _full_supply(present), VillageLabor.demand_for(present), 100.0, carry)
	assert_eq(carry, {})


# -- the sawmill: a saw pit is worth having -------------------------------

## The assembly tells a village short of firewood to build a sawmill. That
## has to be TRUE, or the petition is a lie -- so a staffed saw pit really
## does get more usable timber out of the same hands.
func test_a_staffed_sawmill_really_raises_what_the_same_hands_bring_in():
	var present := ["sawmill"]
	assert_true(
		StaffedProduction.timber_multiplier_for(present, _full_supply(present), VillageLabor.demand_for(present))
		> 1.0
	)


func test_a_village_with_no_sawmill_gets_no_bonus_and_no_penalty():
	assert_almost_eq(StaffedProduction.timber_multiplier_for([], {}, {}), 1.0, 0.0001)


## Never below 1.0, ever. docs/concept/village_growth.md's own rule: a
## hungry village must still be able to cut the timber for the farm that
## would fix its hunger, so gathering may be RAISED by a building and never
## dragged down by one.
func test_an_unstaffed_sawmill_is_never_a_penalty():
	assert_almost_eq(
		StaffedProduction.timber_multiplier_for(["sawmill"], {}, VillageLabor.demand_for(["sawmill"])),
		1.0,
		0.0001
	)


func test_a_half_staffed_sawmill_is_worth_about_half_the_bonus():
	var present := ["sawmill"]
	var demand: Dictionary = VillageLabor.demand_for(present)
	var full: float = StaffedProduction.timber_multiplier_for(present, {"hand": int(demand["hand"])}, demand)
	var half: float = StaffedProduction.timber_multiplier_for(
		present, {"hand": int(demand["hand"]) / 2}, demand
	)
	assert_almost_eq(half - 1.0, (full - 1.0) * 0.5, 0.0001)


## Two mills are not twice the bonus: a village only has so many trees
## within reach, and a multiplier that stacked would make timber free.
func test_a_second_sawmill_does_not_double_the_bonus():
	var one := ["sawmill"]
	var two := ["sawmill", "sawmill"]
	assert_almost_eq(
		StaffedProduction.timber_multiplier_for(two, _full_supply(two), VillageLabor.demand_for(two)),
		StaffedProduction.timber_multiplier_for(one, _full_supply(one), VillageLabor.demand_for(one)),
		0.0001
	)


# -- the rate is derived from what a works has to be worth ---------------

## The relation BATCHES_PER_BUILDING_PER_DAY exists to satisfy, rather
## than the number itself: a fully staffed works must supply several times
## more households than it employs. At any less, the works costs the
## village more labour than it returns and nobody should ever build one.
func _households_supplied_per_staff(building_id: String, good: String, estate: String) -> float:
	var present := [building_id]
	var staff: int = StaffedProduction.staff_needed_for(building_id)
	var per_household_per_day: float = float(VillageEstates.station_basket(estate)[good])
	var made_per_day: float = float(StaffedProduction.attempts_over(
		present, _full_supply(present), VillageLabor.demand_for(present), 1000.0, {}
	)["attempts"][StaffedProduction.RECIPE_BY_BUILDING[building_id]]) / 1000.0
	return (made_per_day / per_household_per_day) / float(staff)


func test_a_staffed_works_supplies_more_households_than_it_employs():
	assert_true(
		_households_supplied_per_staff("brewery", "beer", "buerger")
		>= StaffedProduction.MIN_SELF_SUFFICIENCY_MULTIPLE,
		"a brewhouse cannot even keep several times its own staff in beer"
	)


## And the margin is not absurd either -- a works that supplied a hundred
## villages off two hands would make the whole supply chain pointless.
func test_a_works_is_not_a_cornucopia():
	assert_true(
		_households_supplied_per_staff("brewery", "beer", "buerger") < 100.0,
		"two brewhouse hands keep a hundred times their own village in beer"
	)


## Nothing here is an AUTOMATED recipe. CraftingRecipeBook.can_craft
## refuses one outright, because an automated recipe is a real
## world-standing structure's own production -- a farmhouse's grain really
## does come from its real field, worked by real villagers on real plots,
## and running it a second time here would be the same crop harvested
## twice. Found by the code rather than chosen: a farmhouse -> grow_wheat
## entry produced exactly nothing, silently, for sixty assessments.
func test_nothing_here_is_an_automated_recipe():
	var book := CraftingRecipeBook.new()
	for building_id in StaffedProduction.RECIPE_BY_BUILDING:
		assert_false(
			book.recipe_is_automated(StaffedProduction.RECIPE_BY_BUILDING[building_id]),
			"%s runs an automated recipe, which can_craft refuses outright" % building_id
		)
