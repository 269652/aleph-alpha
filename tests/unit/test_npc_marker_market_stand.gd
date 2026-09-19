extends GutTest

## A market stand is up only while its trader is behind it.
##
## Reported live with a stand in shot, pitched in long grass well off the
## paving: "the market stands should only be put up when an NPC stands
## behind them to sell goods ... also the stand should clear long grass
## around it and be placed on the plaza anyways".
##
## A trestle and a board are not architecture. A real market stand is
## carried out in the morning, stood up for as long as there is somebody
## behind it, and taken in again -- an empty square at night has no stalls
## on it, which is exactly what makes a market read as a market rather than
## as scenery.

const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const NpcPlanner = preload("res://src/world/npc_planner.gd")

const TILE_SIZE := 16


class FixedPlanner:
	extends NpcPlanner.Planner
	var _schedule: Array

	func _init(fixed_schedule: Array) -> void:
		_schedule = fixed_schedule

	func plan_day(_identity: NpcIdentity, _day_index: int) -> Array:
		return _schedule


var marker: NpcMarker
var stand: Node2D


func before_each():
	marker = NpcMarker.new()
	marker.identity = NpcIdentity.new(1, "merchant")
	marker.home_position = Vector2(1000, 1000)
	marker.position = marker.home_position
	marker.workspot_position = Vector2(1000, 1064)
	stand = Node2D.new()
	stand.position = Vector2(1200, 1000)
	marker.landmarks = {"stall": stand.position}
	marker.market_stand = stand
	add_child_autofree(stand)
	add_child_autofree(marker)


## The pure rule, so the threshold is a tested function rather than a
## comment: a stand is up while its trader is working AND within reach of
## it. Both halves matter -- a merchant passing their own stand on the way
## home at night is not selling.
func test_a_stand_is_up_only_when_its_trader_is_working_and_within_reach():
	assert_true(NpcMarker.stand_is_up(true, 0.0, 16.0))
	assert_true(NpcMarker.stand_is_up(true, 16.0, 16.0))
	assert_false(NpcMarker.stand_is_up(true, 16.1, 16.0), "nobody is behind it")
	assert_false(NpcMarker.stand_is_up(false, 0.0, 16.0), "off the clock, the boards come in")


## Reach is a tile: a trader standing on the square beside their own trestle
## is behind it. Derived from the world's own tile size rather than chosen,
## so a stand's reach cannot drift away from the grid it stands on.
func test_a_traders_reach_over_their_own_stand_is_one_tile():
	marker.setup(null, TILE_SIZE)
	assert_almost_eq(marker.market_stand_reach(), float(TILE_SIZE), 0.001)


func test_a_stand_starts_taken_in():
	assert_false(stand.visible, "nobody has carried it out yet")


func test_the_stand_goes_up_once_its_trader_is_working_at_it():
	_work_all_day()
	marker.position = stand.position
	marker._process(0.1)
	assert_true(stand.visible, "a trader standing at their own stand is selling")


func test_the_stand_stays_down_while_its_trader_is_still_walking_to_it():
	_work_all_day()
	marker.position = stand.position + Vector2(400, 0)
	marker._process(0.1)
	assert_false(stand.visible, "a stand with nobody behind it is not up")


func test_the_stand_comes_down_when_its_trader_goes_home():
	_work_all_day()
	marker.position = stand.position
	marker._process(0.1)
	assert_true(stand.visible)
	_sleep_all_day()
	marker._process(0.1)
	assert_false(stand.visible, "an empty square at night has no stalls on it")


## A villager who keeps no stand must not crash the frame, and must not have
## one appear out of nowhere -- every other world hook on this marker fails
## open the same way.
func test_a_villager_with_no_stand_is_left_alone():
	marker.market_stand = null
	_work_all_day()
	marker._process(0.1)
	pass_test("a villager with no stand simply has none")


func _work_all_day() -> void:
	var schedule := [
		{"time_block": "morning", "location_tag": "stall", "activity": "work"},
		{"time_block": "midday", "location_tag": "stall", "activity": "work"},
		{"time_block": "evening", "location_tag": "stall", "activity": "work"},
		{"time_block": "night", "location_tag": "stall", "activity": "work"},
	]
	marker.schedule = schedule
	marker.set_planner(FixedPlanner.new(schedule))


func _sleep_all_day() -> void:
	var schedule := [
		{"time_block": "morning", "location_tag": "home", "activity": "sleep"},
		{"time_block": "midday", "location_tag": "home", "activity": "sleep"},
		{"time_block": "evening", "location_tag": "home", "activity": "sleep"},
		{"time_block": "night", "location_tag": "home", "activity": "sleep"},
	]
	marker.schedule = schedule
	marker.set_planner(FixedPlanner.new(schedule))


# -- a stand nobody can reach because its trader is queueing at an empty ---
# -- well ------------------------------------------------------------------
#
# MEASURED on a real village once the stands were on the square
# (tools/probe_village_market.gd, the whole settlement ticked): the stand was
# up for 5 of 1801 ticks. Not because the siting was wrong -- the merchant
# got within 6.1px of it, well inside the 16px reach -- but because they were
# HUNGRY for 1589 of those ticks with an empty purse, and NpcMarker's hunger
# interrupt overrode all 825 of their scheduled "work at the stall" ticks and
# sent them to the well, which had nothing they could pay for.
#
# That is the same deadlock this file's own neighbour already records for a
# hunter; the guards written for it (a producer who feeds itself, a villager
# with a field) cover neither a merchant nor any other non-producer. See
# NpcEconomy.can_obtain_a_meal.

const VillageMarket = preload("res://src/world/village_market.gd")
const NpcEconomy = preload("res://src/world/npc_economy.gd")


func test_a_hungry_trader_who_cannot_buy_anything_keeps_working():
	var market := VillageMarket.new()  # nothing on the stall, no purse
	marker.setup_economy(market)
	marker.economy.needs.hunger = 1.0
	assert_true(marker.economy.needs.is_hungry(), "precondition: hungry")
	assert_false(marker.economy.can_obtain_a_meal(), "precondition: nothing to be had")
	_work_all_day()
	marker.position = stand.position
	marker._process(0.1)
	assert_true(
		stand.visible,
		"a villager who cannot buy must keep working -- work is the only thing that can change that"
	)


## ...and the interrupt still does its job when there really is a meal to be
## had: a hungry villager who can pay leaves their stand and goes to eat.
func test_a_hungry_trader_who_can_buy_still_goes_to_eat():
	var market := VillageMarket.new()
	market.add_stock("fish", 5.0)
	marker.setup_economy(market)
	marker.economy.wallet.add(100)
	marker.economy.needs.hunger = 1.0
	assert_true(marker.economy.can_obtain_a_meal(), "precondition: a meal is really there")
	_work_all_day()
	marker.position = stand.position
	marker._process(0.1)
	assert_false(stand.visible, "they have left the stand to eat")
