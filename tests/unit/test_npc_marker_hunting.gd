extends GutTest

## A villager who actually hunts (docs/concept/npc.md, "Work against the
## real world, not against a number").
##
## Reported in play: "the hunter doesn't hunt". Before this, a hunter
## walked to a decorative prop, stood on it, and food appeared in the
## village market -- no animal was approached and none died. Now the same
## three-part split the Sägewerk's Lumberjack already uses applies to the
## other verb: ForagerBehavior decides WHEN, HuntableQuarry decides WHAT,
## and NpcMarker owns the world effect -- scanning the real "creature"
## group, walking to a real animal, and striking it with the same
## take_damage() a wolf's own bite calls.
##
## The regional-aggregate path stays underneath as the fallback for a
## village whose chunks hold no loaded animals -- npc.md's own named
## limitation -- so these tests check BOTH: that a hunter with quarry in
## reach takes it and is paid for it, and that a hunter with none still
## earns from the region exactly as before.

const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const NpcPlanner = preload("res://src/world/npc_planner.gd")
const NpcEconomy = preload("res://src/world/npc_economy.gd")
const HuntableQuarry = preload("res://src/gameplay/huntable_quarry.gd")
const ForagerBehavior = preload("res://src/gameplay/forager_behavior.gd")
const VillageMarket = preload("res://src/world/village_market.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const CreatureMass = preload("res://src/world/creature_mass.gd")
const Carcass = preload("res://src/rendering/carcass.gd")

const TILE_SIZE := 16

## Home is the origin and every scheduled destination is at +x, so "walked
## toward the animal" is unambiguous: quarry sits at -x, and only a hunter
## who genuinely abandoned their schedule ends up there.
const HOME := Vector2.ZERO
const WORKSPOT := Vector2(120.0, 0.0)


class AllWorkPlanner:
	extends NpcPlanner.Planner
	var activity := "work"

	func plan_day(_identity: NpcIdentity, _day_index: int) -> Array:
		return [
			{"time_block": "morning", "location_tag": "field", "activity": activity},
			{"time_block": "midday", "location_tag": "field", "activity": activity},
			{"time_block": "evening", "location_tag": "field", "activity": activity},
			{"time_block": "night", "location_tag": "field", "activity": activity},
		]


class StubWorld:
	var biome := "grassland"
	func biome_at_global(_x: int, _y: int) -> String:
		return biome
	func vegetation_density_near(_pos: Vector2) -> float:
		return 0.6
	func herbivore_population_near(_pos: Vector2) -> float:
		return 10.0
	func fish_population_near(_pos: Vector2) -> float:
		return 8.0
	func record_death_at(_pos: Vector2, _is_predator: bool, _count: float = 1.0) -> void:
		pass


## A stand-in for a real CreatureMarker, exposing exactly the contract the
## hunt reads: the species record, taming, live mass, and the same
## take_damage -> die -> queue_free -> leave a carcass sequence
## CreatureMarker itself runs.
class StubCreature:
	extends Node2D
	var info: CreatureInfo
	var damage_taken := 0.0
	var tame := false
	var leaves_carcass := false
	var mass_ratio := 1.0

	func _init(species := "deer") -> void:
		info = CreatureInfo.new(species, 0)

	func _ready() -> void:
		add_to_group(HuntableQuarry.QUARRY_GROUP_NAME)

	func is_tame() -> bool:
		return tame

	func current_mass_kg() -> float:
		return CreatureMass.mass_kg_for(info.species) * mass_ratio

	func take_damage(amount: float) -> void:
		damage_taken += amount
		info.health = maxf(0.0, info.health - amount)
		if info.health > 0.0:
			return
		if leaves_carcass:
			var carcass := Carcass.new()
			carcass.species = info.species
			carcass.position = position
			carcass.mass_ratio = mass_ratio
			get_parent().add_child(carcass)
		queue_free()


var marker: NpcMarker
var market: VillageMarket
var world: StubWorld
var planner: AllWorkPlanner
var _extra: Array = []


func before_each():
	market = VillageMarket.new()
	world = StubWorld.new()
	planner = AllWorkPlanner.new()
	marker = NpcMarker.new()
	marker.identity = NpcIdentity.new(1)
	marker.identity.occupation = "hunter"
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
	# Carcasses are spawned by the stub creature itself, not by the test, so
	# they are cleaned up by group rather than by a list. Anything already
	# queued is the SceneTree's to free -- freeing it twice is an error.
	for node in get_tree().get_nodes_in_group(Carcass.GROUP_NAME) + _extra:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			node.free()
	_extra = []


func _creature_at(at: Vector2, species := "deer") -> StubCreature:
	var c := StubCreature.new(species)
	c.position = at
	add_child(c)
	_extra.append(c)
	return c


## Real seconds of simulation, in frame-sized slices so walking, the
## look-around interval and the strike cadence all advance the way they do
## in play.
func _run(seconds: float, slice := 0.1) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		marker._process(slice)
		elapsed += slice


## Carcasses still really lying in the world. These tests drive _process
## by hand rather than yielding frames, so a queue_free()'d node is still
## listed in its group until the SceneTree next gets a turn -- "still
## standing" is the question being asked, not "still allocated".
## Runs until `creature` is dead, then stops. The stopping matters: once
## the last animal in reach is gone the region has none, so the aggregate
## fallback legitimately starts running again (npc.md's named limitation)
## and would pile conjured food on top of the kill being measured.
func _hunt_until_dead(creature, limit := 60.0, slice := 0.1) -> void:
	var elapsed := 0.0
	while elapsed < limit:
		marker._process(slice)
		elapsed += slice
		if not is_instance_valid(creature) or creature.is_queued_for_deletion():
			return
	fail_test("the hunter never brought the animal down within %s seconds" % limit)


func _carcasses() -> Array:
	var standing: Array = []
	for node in get_tree().get_nodes_in_group(Carcass.GROUP_NAME):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			standing.append(node)
	return standing


# -- leaving the schedule for a real animal ---------------------------------


func test_a_hunter_leaves_their_workspot_for_a_real_animal():
	_creature_at(Vector2(-100.0, 0.0))
	_run(ForagerBehavior.REHUNT_SECONDS + 3.0)
	assert_lt(marker.position.x, 0.0, "a hunter with a deer behind them does not stand at the workspot")


func test_a_hunter_with_nothing_in_reach_keeps_to_their_schedule():
	_run(10.0)
	assert_gt(marker.position.x, 0.0, "with no animal anywhere, the ordinary schedule still runs")


func test_a_hunter_does_not_commit_before_the_look_around_interval():
	_creature_at(Vector2(-100.0, 0.0))
	_run(ForagerBehavior.REHUNT_SECONDS - 0.5)
	assert_gt(marker.position.x, 0.0, "the first beat of the day is still spent walking to work")


func test_a_hunter_ignores_a_predator_underfoot():
	var wolf := _creature_at(Vector2(-20.0, 0.0), "wolf")
	_run(10.0)
	assert_eq(wolf.damage_taken, 0.0, "a hunter is paid by the herbivore count, and takes herbivores")
	assert_gt(marker.position.x, 0.0)


func test_a_hunter_ignores_a_tamed_animal_underfoot():
	var pet := _creature_at(Vector2(-20.0, 0.0))
	pet.tame = true
	_run(10.0)
	assert_eq(pet.damage_taken, 0.0, "a tamed animal belongs to somebody")
	assert_gt(marker.position.x, 0.0)


func test_a_villager_who_is_not_a_producer_never_hunts():
	marker.identity.occupation = "blacksmith"
	marker.setup_economy(market)
	var deer := _creature_at(Vector2(-20.0, 0.0))
	_run(10.0)
	assert_eq(deer.damage_taken, 0.0)


func test_a_hunter_off_the_clock_does_not_hunt():
	planner.activity = "sleep"
	var deer := _creature_at(Vector2(-20.0, 0.0))
	_run(10.0)
	assert_eq(deer.damage_taken, 0.0, "hunting is work, not what a villager does at night")


# -- the strike -------------------------------------------------------------


func test_a_hunter_strikes_an_animal_they_have_reached():
	var deer := _creature_at(Vector2(-20.0, 0.0))
	_run(10.0)
	assert_gt(deer.damage_taken, 0.0)


func test_a_hunter_does_not_swing_while_still_walking():
	var deer := _creature_at(Vector2(-100.0, 0.0))
	_run(ForagerBehavior.REHUNT_SECONDS + 1.0)
	assert_eq(deer.damage_taken, 0.0, "no swinging at thin air from across the meadow")


func test_a_strike_lands_the_same_blow_a_predators_bite_does():
	var deer := _creature_at(Vector2(-20.0, 0.0))
	_run(ForagerBehavior.REHUNT_SECONDS + 4.0)
	assert_almost_eq(
		fmod(deer.damage_taken, HuntableQuarry.STRIKE_DAMAGE), 0.0, 0.0001,
		"every blow is one whole STRIKE_DAMAGE"
	)


# -- what the kill is worth -------------------------------------------------


func test_a_kill_puts_that_animals_own_real_meat_in_the_village_market():
	var deer := _creature_at(Vector2(-20.0, 0.0))
	var expected := HuntableQuarry.meat_yield_of(deer)
	assert_gt(expected, 0, "precondition: this animal really carries meat")
	_hunt_until_dead(deer)
	assert_almost_eq(market.stock.get("meat", 0.0), float(expected), 0.0001)
	assert_almost_eq(
		market.total_stock(), float(expected), 0.0001,
		"and nothing else: a hunter with an animal in reach is paid by the animal"
	)


func test_a_leaner_animal_feeds_the_village_less():
	var deer := _creature_at(Vector2(-20.0, 0.0))
	deer.mass_ratio = 0.4
	var expected := HuntableQuarry.meat_yield_of(deer)
	var plump := HuntableQuarry.meat_yield_of(_creature_at(Vector2(9999.0, 9999.0)))
	assert_lt(expected, plump, "precondition: a lean deer really does carry less")
	_hunt_until_dead(deer)
	assert_almost_eq(market.stock.get("meat", 0.0), float(expected), 0.0001)


func test_a_kill_pays_the_hunter_real_gold():
	var deer := _creature_at(Vector2(-20.0, 0.0))
	_hunt_until_dead(deer)
	assert_gt(NpcEconomy.purse_of(market), 0.0, "the village takes its levy on a real kill")


func test_a_hunter_working_real_quarry_does_not_also_conjure_regional_yield():
	# Far enough that the whole run is spent approaching -- nothing has been
	# killed yet, so nothing has been earned yet either.
	_creature_at(Vector2(-100.0, 0.0))
	_run(ForagerBehavior.REHUNT_SECONDS + 2.0)
	assert_almost_eq(market.total_stock(), 0.0, 0.0001, "no food appears out of a walk")


func test_a_hunter_with_no_animal_in_reach_still_earns_from_the_region():
	# npc.md's named limitation: a village whose chunks hold no loaded
	# animals keeps the aggregate fallback rather than starving.
	_run(30.0)
	assert_gt(market.total_stock(), 0.0)


# -- the carcass ------------------------------------------------------------


func test_a_hunter_carries_home_the_animal_it_killed():
	var deer := _creature_at(Vector2(-20.0, 0.0))
	deer.leaves_carcass = true
	_hunt_until_dead(deer)
	assert_eq(_carcasses().size(), 0, "the meat is in the market; a carcass too would be it counted twice")


func test_a_hunter_leaves_a_carcass_it_did_not_kill():
	var stray := Carcass.new()
	stray.species = "herbivore"
	stray.position = Vector2(-HuntableQuarry.SEARCH_RADIUS_PX, 0.0)
	add_child(stray)
	_extra.append(stray)
	var deer := _creature_at(Vector2(-20.0, 0.0))
	deer.leaves_carcass = true
	_hunt_until_dead(deer)
	assert_eq(_carcasses().size(), 1, "somebody else's kill is not a hunter's to pick up")


# -- losing the quarry ------------------------------------------------------


func test_quarry_that_vanishes_mid_approach_is_given_up():
	var deer := _creature_at(Vector2(-100.0, 0.0))
	_run(ForagerBehavior.REHUNT_SECONDS + 3.0)
	assert_lt(marker.position.x, 0.0, "precondition: really committed and walking")
	deer.queue_free()
	_run(30.0)
	assert_gt(marker.position.x, 0.0, "with nothing left to chase, the schedule resumes")
