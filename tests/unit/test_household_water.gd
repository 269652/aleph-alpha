extends GutTest

## HouseholdWater: docs/concept/village_water.md mechanism 1 -- water is a
## level on the house, drunk by the people in it, refilled a bucket at a
## time.
##
## The number that matters most here is not the capacity but the STARTING
## level: two houses raised on the same day must not run dry on the same
## day, or the village re-synchronises and the crowd at the well comes
## back. That is pillar 1, and it is tested as a distribution rather than
## as a constant.

const HouseholdWater = preload("res://src/emergence/household_water.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")


func _seeds(count: int) -> Array:
	var seeds: Array = []
	for i in count:
		seeds.append(hash("house_%d" % i))
	return seeds


# -- the tank ---------------------------------------------------------------

func test_a_house_holds_a_real_amount_of_water():
	assert_gt(HouseholdWater.TANK_LITRES, 0.0)


func test_one_villager_drinks_a_real_amount_a_day():
	assert_gt(HouseholdWater.DRAW_PER_HEAD_PER_DAY, 0.0)


func test_more_people_drink_more():
	assert_gt(HouseholdWater.draw_for(3, 1.0), HouseholdWater.draw_for(1, 1.0))


func test_longer_draws_more():
	assert_gt(HouseholdWater.draw_for(2, 3.0), HouseholdWater.draw_for(2, 1.0))


func test_nobody_home_drinks_nothing():
	assert_eq(HouseholdWater.draw_for(0, 5.0), 0.0)


func test_no_time_passing_draws_nothing():
	assert_eq(HouseholdWater.draw_for(4, 0.0), 0.0)


func test_a_nonsense_household_or_span_draws_nothing_rather_than_refunding_water():
	assert_eq(HouseholdWater.draw_for(-3, 1.0), 0.0)
	assert_eq(HouseholdWater.draw_for(2, -1.0), 0.0)


func test_drinking_lowers_the_level():
	var after := HouseholdWater.level_after(HouseholdWater.TANK_LITRES, 2, 1.0)
	assert_lt(after, HouseholdWater.TANK_LITRES)


func test_a_tank_never_goes_below_empty():
	assert_eq(HouseholdWater.level_after(1.0, 8, 100.0), 0.0)


func test_a_tank_never_holds_more_than_it_holds():
	assert_eq(HouseholdWater.poured_into(HouseholdWater.TANK_LITRES, 999.0), HouseholdWater.TANK_LITRES)


func test_pouring_a_bucket_in_raises_the_level_by_the_bucket():
	var half := HouseholdWater.TANK_LITRES * 0.5
	assert_almost_eq(
		HouseholdWater.poured_into(half, HouseholdWater.BUCKET_LITRES),
		half + HouseholdWater.BUCKET_LITRES, 0.0001
	)


func test_a_bucket_is_less_than_a_tank_or_one_trip_would_do_forever():
	assert_lt(HouseholdWater.BUCKET_LITRES, HouseholdWater.TANK_LITRES)


# -- when somebody has to go ------------------------------------------------

func test_a_full_tank_sends_nobody():
	assert_false(HouseholdWater.trip_is_due(HouseholdWater.TANK_LITRES))


func test_an_empty_tank_sends_somebody():
	assert_true(HouseholdWater.trip_is_due(0.0))


func test_the_trip_comes_before_the_tank_is_dry():
	# A household that waits until it is empty has a thirsty day while
	# somebody walks.
	assert_true(HouseholdWater.trip_is_due(HouseholdWater.TANK_LITRES * 0.05))
	assert_gt(HouseholdWater.TRIP_THRESHOLD_SHARE, 0.0)


func test_a_tank_just_above_the_threshold_sends_nobody():
	assert_false(HouseholdWater.trip_is_due(
		HouseholdWater.TANK_LITRES * (HouseholdWater.TRIP_THRESHOLD_SHARE + 0.01)
	))


# -- the anti-crowd mechanism -----------------------------------------------

func test_a_new_house_starts_with_water_in_it():
	for seed_value in _seeds(50):
		assert_gt(HouseholdWater.starting_level(seed_value), 0.0)


func test_a_new_house_never_starts_already_needing_a_trip():
	# A village founded today would otherwise send every household to the
	# well on day one -- the exact crowd this feature exists to break up.
	for seed_value in _seeds(200):
		assert_false(
			HouseholdWater.trip_is_due(HouseholdWater.starting_level(seed_value)),
			"seed %d starts dry" % seed_value
		)


func test_a_new_house_never_starts_overfull():
	for seed_value in _seeds(200):
		assert_lte(HouseholdWater.starting_level(seed_value), HouseholdWater.TANK_LITRES)


func test_two_houses_do_not_start_at_the_same_level():
	var levels := {}
	for seed_value in _seeds(40):
		levels[HouseholdWater.starting_level(seed_value)] = true
	assert_gt(levels.size(), 20, "houses are starting from a handful of levels, so they will run dry together")


func test_the_same_house_always_starts_the_same():
	assert_eq(HouseholdWater.starting_level(1234), HouseholdWater.starting_level(1234))


## The claim the whole stagger rests on: run a village forward and the
## households cross the threshold on DIFFERENT days.
func test_houses_founded_together_run_dry_on_different_days():
	var due_on := {}
	for seed_value in _seeds(30):
		var level := HouseholdWater.starting_level(seed_value)
		var day := 0
		while not HouseholdWater.trip_is_due(level) and day < 400:
			level = HouseholdWater.level_after(level, 2, 1.0)
			day += 1
		due_on[day] = int(due_on.get(day, 0)) + 1
	assert_gt(due_on.size(), 3, "every house in the village ran dry on the same few days")
	var biggest := 0
	for day in due_on:
		biggest = maxi(biggest, int(due_on[day]))
	assert_lt(biggest, 20, "%d of 30 households went to the well on one day" % biggest)


# -- how often a household really has to go ---------------------------------
#
# What pins the capacity and the draw: not the numbers, but the errand they
# produce. A household must go often enough that the well is a real part of
# life, and rarely enough that a villager is not living at it.

func test_a_small_household_goes_at_least_once_a_season_and_not_every_day():
	var days := _days_between_trips(2)
	assert_gt(days, 1, "a two-person household is at the well every single day")
	assert_lt(days, SeasonCycle.DAYS_PER_YEAR / 4.0, "a household goes less than once a season")


func test_a_bigger_household_goes_more_often():
	assert_lt(_days_between_trips(4), _days_between_trips(1))


## Days from a full tank to the trip threshold, for a household of `heads`.
func _days_between_trips(heads: int) -> int:
	var level := HouseholdWater.TANK_LITRES
	var day := 0
	while not HouseholdWater.trip_is_due(level) and day < 1000:
		level = HouseholdWater.level_after(level, heads, 1.0)
		day += 1
	return day


# -- the farm drinks last ---------------------------------------------------

func test_a_farm_waters_crops_only_with_what_is_above_the_drinking_reserve():
	var full := HouseholdWater.TANK_LITRES
	assert_gt(HouseholdWater.spare_for_crops(full), 0.0)
	assert_lt(HouseholdWater.spare_for_crops(full), full, "a farm poured its drinking water on the field")


func test_a_low_tank_has_nothing_to_spare_for_crops():
	assert_eq(HouseholdWater.spare_for_crops(HouseholdWater.DRINKING_RESERVE_LITRES), 0.0)
	assert_eq(HouseholdWater.spare_for_crops(0.0), 0.0)


func test_the_drinking_reserve_is_real_water_not_the_whole_tank():
	assert_gt(HouseholdWater.DRINKING_RESERVE_LITRES, 0.0)
	assert_lt(HouseholdWater.DRINKING_RESERVE_LITRES, HouseholdWater.TANK_LITRES)


## People before plants: the reserve must outlast a trip to the well, or a
## farm waters itself into a household drought.
func test_the_reserve_outlasts_the_walk_to_the_well():
	var days_of_reserve := HouseholdWater.DRINKING_RESERVE_LITRES / HouseholdWater.draw_for(2, 1.0)
	assert_gte(days_of_reserve, 1.0, "a farm household could go thirsty while somebody fetches water")


# -- the bucket is a real thing (2026-09-20) --------------------------------
#
# Asked for directly: *"each NPC should have a bucket in its house
# inventory"*. A bucket is a vessel, never the place water lives -- the
# water itself is a level on the house (pillar 3), so the bucket is an
# ordinary carryable item and nothing more.

const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")


func test_a_bucket_is_a_real_catalog_item():
	var catalog := ItemCatalog.new()
	assert_true(catalog.known_ids().has(HouseholdWater.BUCKET_ITEM_ID))


func test_a_bucket_is_a_tool_rather_than_food_or_a_weapon():
	var catalog := ItemCatalog.new()
	assert_eq(catalog.kind_of(HouseholdWater.BUCKET_ITEM_ID), "tool")


func test_a_bucket_has_a_name_somebody_could_read():
	var catalog := ItemCatalog.new()
	var bucket = catalog.make(HouseholdWater.BUCKET_ITEM_ID)
	assert_not_null(bucket)
	assert_ne(bucket.display_name, "")


## Water is never an item. It is a level on the house, and a bucket is how
## it moves -- if water became a catalog item too there would be two places
## a household's water could live and they would drift.
func test_water_itself_is_not_an_item_anybody_can_carry():
	var catalog := ItemCatalog.new()
	assert_false(catalog.known_ids().has("water"))
