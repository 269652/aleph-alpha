extends GutTest

## The carter's own decision (see VillageCart, docs/concept/
## village_warehouse.md Mechanism 4): whose shelf to empty next.
##
## Pure -- shelves are passed in as {cell, waiting} records, so nothing here
## needs a villager, a store or a world.

const VillageCart = preload("res://src/gameplay/village_cart.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")


func test_a_carter_walks_the_round_and_nobody_else_does():
	assert_true(VillageCart.walks_the_round(VillageCart.OCCUPATION))
	assert_false(VillageCart.walks_the_round("farmer"))
	assert_false(VillageCart.walks_the_round(""))


## The trade is a real one a villager can be born to, not a role invented
## beside the list.
func test_the_carter_is_a_real_trade():
	assert_true(NpcIdentity.OCCUPATIONS.has(VillageCart.OCCUPATION))
	assert_true(
		NpcIdentity.WORK_LOCATION_BY_OCCUPATION.has(VillageCart.OCCUPATION),
		"and works somewhere their schedule can name"
	)


# -- whose shelf to empty next ----------------------------------------------

func test_the_fullest_shelf_is_the_one_worth_walking_to():
	var chosen: Dictionary = VillageCart.fullest_shelf([
		{"cell": Vector2i(1, 1), "waiting": 2},
		{"cell": Vector2i(9, 9), "waiting": 7},
	])
	assert_eq(chosen.get("cell"), Vector2i(9, 9))


func test_a_village_with_nothing_waiting_sends_nobody():
	assert_true(VillageCart.fullest_shelf([]).is_empty())
	assert_true(VillageCart.fullest_shelf([{"cell": Vector2i(1, 1), "waiting": 0}]).is_empty())


## Deterministic when two shelves hold the same: the same village sends its
## carter the same way every visit rather than picking by Dictionary order.
func test_two_equal_shelves_are_broken_the_same_way_every_time():
	var shelves: Array = [
		{"cell": Vector2i(9, 9), "waiting": 4},
		{"cell": Vector2i(1, 1), "waiting": 4},
	]
	assert_eq(VillageCart.fullest_shelf(shelves).get("cell"), Vector2i(1, 1))
	assert_eq(
		VillageCart.fullest_shelf(shelves).get("cell"),
		VillageCart.fullest_shelf([shelves[1], shelves[0]]).get("cell"),
		"and the order they were offered in does not decide it"
	)
