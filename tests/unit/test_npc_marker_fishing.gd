extends GutTest

## A villager who actually fishes (docs/concept/npc.md, "Work against the
## real world, not against a number").
##
## The other half of the hunter's change, and the easier half: the hook for
## taking a real fish already existed for the player's own rod
## (EarthChunkManager.catch_nearest_fish, which frees the fish AND records
## the harvest against its chunk's aggregate population), and so did the
## one for finding one (nearest_fish_position, written for a diving bird).
## What was missing was a villager who walked to the water and used them --
## the fisher's whole catch came from fish_population_near, a number, and
## _deplete_discrete_unit deleted a fish somewhere nearby afterwards to
## keep the books straight.
##
## Both hooks are read duck-typed, like every other world read on this
## marker: a world that cannot answer them leaves the fisher on the
## regional fallback rather than crashing.

const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const NpcPlanner = preload("res://src/world/npc_planner.gd")
const NpcEconomy = preload("res://src/world/npc_economy.gd")
const ForagerBehavior = preload("res://src/gameplay/forager_behavior.gd")
const HuntableQuarry = preload("res://src/gameplay/huntable_quarry.gd")
const VillageMarket = preload("res://src/world/village_market.gd")
const Player = preload("res://scenes/player.gd")

const TILE_SIZE := 16
const HOME := Vector2.ZERO
const WORKSPOT := Vector2(120.0, 0.0)
## Far enough that reaching it is a real walk, close enough to be inside
## HuntableQuarry.SEARCH_RADIUS_PX from anywhere the schedule takes them.
const POND := Vector2(-100.0, 0.0)


class AllWorkPlanner:
	extends NpcPlanner.Planner
	var activity := "work"

	func plan_day(_identity: NpcIdentity, _day_index: int) -> Array:
		return [
			{"time_block": "morning", "location_tag": "dock", "activity": activity},
			{"time_block": "midday", "location_tag": "dock", "activity": activity},
			{"time_block": "evening", "location_tag": "dock", "activity": activity},
			{"time_block": "night", "location_tag": "dock", "activity": activity},
		]


## A stand-in for a real FishMarker: a node in the water with a species and
## a mass, which is all either world hook reads off it.
class FishStub:
	extends Node2D
	var species := "goldfish"
	var mass_kg := 1.2


## The two real EarthChunkManager hooks, with the same contracts: find
## returns the live marker (or null), and take FREES it and books its own
## depletion against the region.
class StubWorld:
	var fish: Array = []
	var cast_count := 0
	var extra_depletion_count := 0
	var casts_land := true

	func biome_at_global(_x: int, _y: int) -> String:
		return "grassland"

	func vegetation_density_near(_pos: Vector2) -> float:
		return 0.6

	func herbivore_population_near(_pos: Vector2) -> float:
		return 10.0

	func fish_population_near(_pos: Vector2) -> float:
		return 8.0

	func nearest_fish_position(pixel_position: Vector2, max_distance: float):
		var nearest = null
		var nearest_distance := max_distance
		for f in fish:
			if not is_instance_valid(f):
				continue
			var distance: float = pixel_position.distance_to(f.position)
			if distance <= nearest_distance:
				nearest = f
				nearest_distance = distance
		return nearest

	func catch_nearest_fish(pixel_position: Vector2, max_distance: float) -> Dictionary:
		cast_count += 1
		var target = nearest_fish_position(pixel_position, max_distance)
		if target == null or not casts_land:
			return {"species": "", "mass_kg": 0.0}
		var caught := {"species": target.species, "mass_kg": target.mass_kg}
		fish.erase(target)
		target.free()
		return caught

	func record_fish_catch_near(_pos: Vector2, _count: float) -> bool:
		extra_depletion_count += 1
		return true


var marker: NpcMarker
var market: VillageMarket
var world: StubWorld
var planner: AllWorkPlanner


func before_each():
	market = VillageMarket.new()
	world = StubWorld.new()
	planner = AllWorkPlanner.new()
	marker = NpcMarker.new()
	marker.identity = NpcIdentity.new(1)
	marker.identity.occupation = "fisher"
	marker.home_position = HOME
	marker.workspot_position = WORKSPOT
	marker.landmarks = {"well": WORKSPOT, "stall": WORKSPOT, "gate": WORKSPOT}
	marker.position = HOME
	marker.set_planner(planner)
	marker.setup(world, TILE_SIZE)
	marker.setup_economy(market)
	add_child(marker)


func after_each():
	remove_child(marker)
	marker.free()
	for f in world.fish:
		if is_instance_valid(f):
			f.free()
	world.fish = []


func _fish_at(at: Vector2) -> FishStub:
	var f := FishStub.new()
	f.position = at
	add_child(f)
	world.fish.append(f)
	return f


func _run(seconds: float, slice := 0.1) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		marker._process(slice)
		elapsed += slice


func _fish_until_caught(limit := 60.0, slice := 0.1) -> void:
	var elapsed := 0.0
	while elapsed < limit:
		marker._process(slice)
		elapsed += slice
		if market.stock.get("fish", 0.0) > 0.0:
			return
	fail_test("the fisher never landed a fish within %s seconds" % limit)


# -- going to the water -----------------------------------------------------


func test_a_fisher_walks_to_water_that_has_fish_in_it():
	_fish_at(POND)
	_run(ForagerBehavior.REHUNT_SECONDS + 3.0)
	assert_lt(marker.position.x, 0.0, "a fisher goes to the fish, not to a prop called a dock")


func test_a_fisher_with_no_fish_anywhere_keeps_to_their_schedule():
	_run(10.0)
	assert_gt(marker.position.x, 0.0)


func test_a_fisher_stops_at_the_bank_rather_than_wading_onto_the_fish():
	# A rod reaches out over the water; a villager standing on top of the
	# shoal would be a villager standing in the river.
	_fish_at(POND)
	_run(30.0)
	assert_gt(
		marker.position.distance_to(POND),
		NpcMarker.CAST_DISTANCE_PX - NpcMarker.WALK_SPEED,
		"the fisher must hold at casting range, not swim out to the fish"
	)


func test_a_fisher_off_the_clock_does_not_fish():
	planner.activity = "sleep"
	_fish_at(POND)
	_run(30.0)
	assert_eq(world.cast_count, 0)


# -- the cast ---------------------------------------------------------------


func test_a_fisher_in_range_casts():
	_fish_at(POND)
	_run(30.0)
	assert_gt(world.cast_count, 0)


func test_a_fisher_does_not_cast_from_across_the_valley():
	_fish_at(POND)
	_run(ForagerBehavior.REHUNT_SECONDS + 0.5)
	assert_eq(world.cast_count, 0, "still walking; a rod is not that long")


func test_a_landed_fish_goes_into_the_village_market():
	_fish_at(POND)
	_fish_until_caught()
	assert_almost_eq(market.stock.get("fish", 0.0), 1.0, 0.0001, "one real fish is one food unit")
	assert_almost_eq(market.total_stock(), 1.0, 0.0001, "and nothing conjured alongside it")


func test_a_landed_fish_pays_the_fisher():
	_fish_at(POND)
	_fish_until_caught()
	assert_gt(NpcEconomy.purse_of(market), 0.0)


func test_a_cast_that_lands_nothing_credits_nothing():
	world.casts_land = false
	_fish_at(POND)
	_run(30.0)
	assert_gt(world.cast_count, 0, "precondition: the fisher really did cast")
	assert_almost_eq(market.stock.get("fish", 0.0), 0.0, 0.0001)


func test_the_take_books_no_second_depletion():
	# catch_nearest_fish already records the catch against its chunk's
	# aggregate. record_fish_catch_near on top of it would thin the same
	# shoal twice for one fish -- the exact double-booking
	# CreatureMarker._die's own doc comment records happening once before.
	_fish_at(POND)
	_fish_until_caught()
	assert_eq(world.extra_depletion_count, 0)


# -- the fallback, and losing the fish --------------------------------------


func test_a_fisher_working_real_fish_does_not_also_conjure_regional_yield():
	_fish_at(POND)
	_run(ForagerBehavior.REHUNT_SECONDS + 1.0)
	assert_almost_eq(market.total_stock(), 0.0, 0.0001, "no fish appears out of a walk")


func test_a_fisher_with_no_fish_in_reach_still_earns_from_the_region():
	# npc.md's named limitation: an unloaded village keeps the aggregate.
	_run(30.0)
	assert_gt(market.total_stock(), 0.0)


func test_a_fish_that_is_gone_mid_approach_is_given_up():
	var fish := _fish_at(POND)
	_run(ForagerBehavior.REHUNT_SECONDS + 3.0)
	assert_lt(marker.position.x, 0.0, "precondition: really committed and walking")
	world.fish.erase(fish)
	fish.free()
	_run(30.0)
	assert_gt(marker.position.x, 0.0, "with nothing left in the water, the schedule resumes")


func test_a_world_that_cannot_answer_leaves_the_fisher_on_the_regional_fallback():
	marker.setup(null, TILE_SIZE)
	_fish_at(POND)
	_run(30.0)
	assert_eq(world.cast_count, 0)
	assert_gt(marker.position.x, 0.0, "the ordinary schedule still runs")


# -- how far a rod reaches --------------------------------------------------


func test_cast_distance_matches_the_players_own_rod():
	# A villager's rod is the player's rod. Player.FISH_CATCH_RADIUS's own
	# doc comment already says what this number is for: "generous enough to
	# cover a pond fish a few tiles out while standing at the shore".
	assert_eq(NpcMarker.CAST_DISTANCE_PX, Player.FISH_CATCH_RADIUS)
