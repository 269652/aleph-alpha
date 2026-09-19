extends GutTest

## VillageLabor: docs/concept/village_estates.md mechanism 4 -- a building
## is not production; a STAFFED building is.
##
## This is the honest answer to village_growth.md's own standing gap ("the
## ladder's rungs are buildings, not yet production"): a village raises a
## forge and gets nothing out of it until it has a craftsman to stand in
## it. And it is the squeeze that makes the estate ladder cost something --
## an estate supplies exactly one class of labour, so promoting a cottager
## removes a pair of hands and creates a farmer.

const VillageLabor = preload("res://src/emergence/village_labor.gd")
const VillageEstates = preload("res://src/emergence/village_estates.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")


# -- supply ---------------------------------------------------------------

func test_an_empty_village_supplies_no_labour():
	assert_eq(VillageLabor.supply_for({}), {})


func test_each_household_supplies_one_head_of_its_own_estates_class():
	var supply: Dictionary = VillageLabor.supply_for({"kossaet": 4})
	assert_eq(int(supply[VillageEstates.labour_class_for("kossaet")]), 4)


func test_a_mixed_village_supplies_every_class_its_estates_hold():
	var supply: Dictionary = VillageLabor.supply_for({"kossaet": 3, "handwerker": 2})
	assert_eq(int(supply["hand"]), 3)
	assert_eq(int(supply["craft"]), 2)
	assert_false(supply.has("field"), "a village with no husbandmen supplies field labour")


func test_an_unknown_estate_supplies_nothing_rather_than_crashing():
	assert_eq(VillageLabor.supply_for({"emperor": 9}), {})


## Pillar 4, stated as an invariant rather than as a comment: promoting one
## household moves exactly one head from one class to another -- the
## village is never richer in total labour for having promoted anybody.
func test_promotion_moves_a_head_rather_than_creating_one():
	var before: Dictionary = VillageLabor.supply_for({"kossaet": 5})
	var after: Dictionary = VillageLabor.supply_for({"kossaet": 4, "bauer": 1})
	assert_eq(VillageLabor.total_heads(before), VillageLabor.total_heads(after))
	assert_eq(int(after["hand"]), int(before["hand"]) - 1, "the rung below kept its hand")
	assert_eq(int(after["field"]), 1)


# -- demand ---------------------------------------------------------------

func test_a_village_with_nothing_standing_demands_no_labour():
	assert_eq(VillageLabor.demand_for([]), {})


func test_a_farmhouse_demands_field_labour():
	assert_true(int(VillageLabor.demand_for(["farmhouse"]).get("field", 0)) > 0)


## A saw pit is two men on a saw, not a guild trade -- which is what lets
## a village of cottagers cut its own firewood. It is also the deadlock
## VillageAssembly's tests found: craftsmen only exist downstream of a
## mill, so a mill that needed one could never be the first works a
## village raised.
func test_a_saw_pit_is_worked_by_hands_and_needs_no_guild_trade():
	var demand: Dictionary = VillageLabor.demand_for(["sawmill"])
	assert_true(int(demand.get("hand", 0)) > 0)
	assert_eq(int(demand.get("craft", 0)), 0, "a saw pit wants a guild trade")


## The brewery is the one rung staffed from two classes: a brewer over
## somebody else's back. Either post empty and the mash floor stands.
func test_a_brewery_demands_both_a_brewer_and_a_pair_of_hands():
	var demand: Dictionary = VillageLabor.demand_for(["brewery"])
	assert_true(int(demand.get("hand", 0)) > 0)
	assert_true(int(demand.get("craft", 0)) > 0)


func test_two_of_a_building_demand_twice_the_labour():
	var one: Dictionary = VillageLabor.demand_for(["blacksmith"])
	var two: Dictionary = VillageLabor.demand_for(["blacksmith", "blacksmith"])
	assert_eq(int(two["craft"]), int(one["craft"]) * 2)


func test_a_house_demands_no_labour_because_nobody_works_in_one():
	for house_id in BuildingCatalog.BUILDING_IDS:
		assert_eq(VillageLabor.demand_for([house_id]), {}, "%s demands a workforce" % house_id)


## Every class a building can demand is a class some estate really
## supplies, or it is a post no villager could ever fill.
func test_every_demanded_class_is_one_some_estate_actually_supplies():
	for building_id in VillageLabor.LABOUR_BY_BUILDING:
		for labour_class in VillageLabor.LABOUR_BY_BUILDING[building_id]:
			assert_true(
				VillageEstates.LABOUR_CLASSES.has(labour_class),
				"%s wants %s, which no estate supplies" % [building_id, labour_class]
			)


## Every building with a workforce is a real catalog building -- a table
## entry for a building that cannot be raised is a post in a place that
## does not exist.
func test_every_staffed_building_is_a_real_catalog_building():
	for building_id in VillageLabor.LABOUR_BY_BUILDING:
		assert_true(
			BuildingCatalog.has_building(building_id),
			"%s takes a workforce and is not a building" % building_id
		)


# -- fulfilment and the output scale --------------------------------------

func test_a_village_with_every_post_filled_runs_at_full_output():
	var supply := {"hand": 4, "craft": 4}
	var demand: Dictionary = VillageLabor.demand_for(["sawmill"])
	assert_almost_eq(VillageLabor.output_scale_for("sawmill", supply, demand), 1.0, 0.0001)


## A building whose class the village holds NONE of does not run. That is
## what makes raising a forge before there are craftsmen a real mistake
## rather than a free head start.
func test_a_forge_with_no_craftsman_in_the_village_does_not_run():
	assert_almost_eq(
		VillageLabor.output_scale_for("blacksmith", {"hand": 20}, VillageLabor.demand_for(["blacksmith"])),
		0.0,
		0.0001
	)


func test_half_the_workforce_is_half_the_output():
	var demand: Dictionary = VillageLabor.demand_for(["blacksmith"])
	var half: int = int(demand["craft"]) / 2
	assert_almost_eq(
		VillageLabor.output_scale_for("blacksmith", {"craft": half}, demand), 0.5, 0.0001
	)


## The MINIMUM across the classes a building needs, never the mean: a
## brewery with its brewer and nobody to rake the mash runs at the hand's
## rate. One missing post is a real bottleneck, which is the same reason an
## estate's satisfaction is a minimum too.
func test_a_building_runs_at_the_rate_of_its_worst_staffed_post():
	var demand: Dictionary = VillageLabor.demand_for(["brewery"])
	var scale: float = VillageLabor.output_scale_for("brewery", {"craft": 9, "hand": 0}, demand)
	assert_almost_eq(scale, 0.0, 0.0001)


## Surplus labour does not push a building past full -- a village of forty
## craftsmen does not get a forge that runs at four hundred percent.
func test_a_surplus_of_labour_never_pushes_a_building_past_full():
	var demand: Dictionary = VillageLabor.demand_for(["brewery"])
	assert_almost_eq(
		VillageLabor.output_scale_for("brewery", {"craft": 400, "hand": 400}, demand), 1.0, 0.0001
	)


## Labour is POOLED: two forges in one village share its craftsmen, so
## raising a second one without raising more craftsmen halves them both.
## This is the whole reason demand is read village-wide rather than per
## building.
func test_a_second_forge_with_no_more_craftsmen_halves_them_both():
	var supply := {"craft": 2}
	var one: float = VillageLabor.output_scale_for(
		"blacksmith", supply, VillageLabor.demand_for(["blacksmith"])
	)
	var two: float = VillageLabor.output_scale_for(
		"blacksmith", supply, VillageLabor.demand_for(["blacksmith", "blacksmith"])
	)
	assert_almost_eq(two, one * 0.5, 0.0001)


func test_a_building_that_takes_no_workforce_always_runs():
	assert_almost_eq(VillageLabor.output_scale_for("house_small", {}, {}), 1.0, 0.0001)


## The assembly's own gate (mechanism 5): a village does not vote to build
## what it could not put a single body in.
func test_a_village_can_staff_only_what_it_holds_some_of_every_class_for():
	assert_false(VillageLabor.can_staff("blacksmith", {"hand": 20, "field": 20}))
	assert_true(VillageLabor.can_staff("blacksmith", {"craft": 1}))
	assert_false(VillageLabor.can_staff("sawmill", {"craft": 9}), "a mill with no hands is unstaffable")
	assert_true(VillageLabor.can_staff("sawmill", {"hand": 1}))


func test_anything_that_needs_no_workforce_can_always_be_staffed():
	assert_true(VillageLabor.can_staff("house_small", {}))


## The whole point of the pyramid: promote every cottager and the village
## can no longer work its own mill.
func test_promoting_every_cottager_leaves_the_mill_unstaffable():
	var before: Dictionary = VillageLabor.supply_for({"kossaet": 6})
	var after: Dictionary = VillageLabor.supply_for({"bauer": 6})
	assert_true(VillageLabor.can_staff("warehouse", before))
	assert_false(VillageLabor.can_staff("warehouse", after), "a village of farmers still has hands")


# -- employment: the dual of fulfilment ----------------------------------

## `fulfilment` asks what share of the POSTS are filled; `employment` asks
## what share of the PEOPLE have one. A village reads both off the same two
## numbers, and they are not the same question -- a village with one forge
## and forty craftsmen has every post filled and thirty-eight idle men.
func test_a_class_with_a_post_for_everyone_is_fully_employed():
	assert_almost_eq(float(VillageLabor.employment_for({"hand": 2}, {"hand": 2})["hand"]), 1.0, 0.0001)


func test_a_class_with_posts_for_half_of_it_is_half_employed():
	assert_almost_eq(float(VillageLabor.employment_for({"hand": 4}, {"hand": 2})["hand"]), 0.5, 0.0001)


## Surplus posts do not employ people twice: a village with ten forges and
## two craftsmen has two employed craftsmen, not five each.
func test_more_posts_than_people_never_employs_anyone_twice():
	assert_almost_eq(float(VillageLabor.employment_for({"craft": 2}, {"craft": 20})["craft"]), 1.0, 0.0001)


func test_a_class_nothing_demands_is_wholly_idle():
	assert_almost_eq(float(VillageLabor.employment_for({"field": 5}, {})["field"]), 0.0, 0.0001)


## A class NOBODY holds is not unemployed -- there is nobody to be idle.
## Reported as fully employed rather than as zero, which is the only
## reading that does not invent a crowd of idle people who do not exist.
func test_a_class_nobody_holds_is_not_reported_as_idle():
	assert_almost_eq(float(VillageLabor.employment_for({}, {"craft": 3})["craft"], ), 1.0, 0.0001)


func test_every_class_named_on_either_side_gets_an_answer():
	var employment: Dictionary = VillageLabor.employment_for({"hand": 3}, {"craft": 1})
	assert_true(employment.has("hand"))
	assert_true(employment.has("craft"))


func test_an_empty_village_employs_nobody_and_reports_nothing():
	assert_eq(VillageLabor.employment_for({}, {}), {})


## What one household actually reads: the employment of its OWN estate's
## labour class.
func test_a_household_reads_the_employment_of_its_own_estates_class():
	var census := {"kossaet": 4, "bauer": 2}
	var present := ["warehouse"]  # one `hand` post, nothing for a husbandman
	var employment: Dictionary = VillageLabor.employment_for(
		VillageLabor.supply_for(census), VillageLabor.demand_for(present)
	)
	assert_almost_eq(float(employment["hand"]), 0.25, 0.0001)
	assert_almost_eq(float(employment["field"]), 0.0, 0.0001)


func test_employment_for_estate_reads_the_right_class_and_is_safe_for_an_unknown_one():
	var employment := {"hand": 0.25, "field": 0.0}
	assert_almost_eq(VillageLabor.employment_for_estate("kossaet", employment), 0.25, 0.0001)
	assert_almost_eq(VillageLabor.employment_for_estate("bauer", employment), 0.0, 0.0001)
	assert_almost_eq(
		VillageLabor.employment_for_estate("emperor", employment), 1.0, 0.0001,
		"an estate with no labour class of its own cannot be idle"
	)


## The squeeze, from the PEOPLE'S side rather than the buildings': promote
## every cottager and the village's works have nobody to run them AND the
## risen households have nothing to do.
func test_promoting_everyone_leaves_the_risen_households_idle():
	var present := ["warehouse", "sawmill"]
	var demand: Dictionary = VillageLabor.demand_for(present)
	var before: Dictionary = VillageLabor.employment_for(VillageLabor.supply_for({"kossaet": 3}), demand)
	var after: Dictionary = VillageLabor.employment_for(VillageLabor.supply_for({"bauer": 3}), demand)
	assert_almost_eq(float(before["hand"]), 1.0, 0.0001)
	assert_almost_eq(float(after["field"]), 0.0, 0.0001, "husbandmen with no farm found work anyway")
