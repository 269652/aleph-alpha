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
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const Butchering = preload("res://src/gameplay/butchering.gd")
const MerchantVisit = preload("res://src/emergence/merchant_visit.gd")
const SurvivalMeters = preload("res://src/gameplay/survival_meters.gd")
const NpcCondition = preload("res://src/world/npc_condition.gd")

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
		market.total_stock(), float(expected + Butchering.HIDE_COUNT), 0.0001,
		"and nothing conjured: just the animal's own meat and its hide"
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
	#
	# Long enough to cross a whole FOOD_UNIT, derived from the real rate
	# rather than written as a round 30 seconds: the regional drip is each
	# resource's own renewal now, scaled by that trade's own reach (see
	# docs/concept/settlement_food_calibration.md), so a fixed second count
	# silently stops gathering anything the moment that is retuned.
	var NpcProduction = load("res://src/world/npc_production.gd")
	var per_second: float = NpcProduction.new().yield_per_second("hunter", world, marker.position)
	assert_gt(per_second, 0.0, "precondition: this region really does drip")
	_run(ceil(2.0 * NpcProduction.FOOD_UNIT / per_second))
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


# -- looking around costs something -----------------------------------------
#
# Finding quarry means walking the whole creature group, which
# CreatureMarker's own _scan_nearby_creatures doc comment already calls out
# as O(n^2) across a loaded population. That marker answers it with
# SENSE_INTERVAL -- "the expensive part of the AI ... runs at most this
# often, cached in between" -- and a villager looking for a deer is the
# same expensive part of the same AI.


func test_the_quarry_scan_is_throttled_the_way_every_other_sense_is():
	_creature_at(Vector2(-100.0, 0.0))
	var seconds := 1.0
	var slice := 0.1
	_run(seconds, slice)
	assert_gt(marker._quarry_scan_count, 0, "precondition: it really does look around")
	assert_lte(
		marker._quarry_scan_count,
		ceili(seconds / NpcMarker.QUARRY_SCAN_INTERVAL) + 1,
		"a villager must not walk the whole creature group every single frame"
	)


func test_a_villager_looks_around_as_often_as_a_creature_senses():
	assert_eq(NpcMarker.QUARRY_SCAN_INTERVAL, CreatureMarker.SENSE_INTERVAL)


func test_the_very_first_working_frame_already_knows_whether_quarry_is_there():
	# Otherwise a hunter draws the conjured drip for the first interval of
	# every working day, standing next to a deer.
	_creature_at(Vector2(-100.0, 0.0))
	_run(0.1, 0.1)
	assert_almost_eq(market.total_stock(), 0.0, 0.0001)


func test_the_frame_after_a_kill_already_knows_the_next_deer_is_there():
	# Otherwise every kill is followed by a scan interval of conjured drip
	# with the rest of the herd standing right there. Asserted on the gate
	# itself rather than on market stock, because the drip accumulates
	# sub-unit and a fraction of a food unit never reaches the market to
	# be seen (NpcEconomy._gather's FOOD_UNIT accumulation loop) -- it is
	# a real leak that a stock assertion simply cannot observe.
	var first := _creature_at(Vector2(-20.0, 0.0))
	_creature_at(Vector2(-40.0, 0.0))
	_hunt_until_dead(first)
	_run(0.1, 0.1)
	assert_true(marker._on_real_quarry, "the herd is still there; the drip must stay off")


# -- the hide ---------------------------------------------------------------


func test_a_kill_puts_a_real_hide_in_the_village_market():
	# MerchantVisit.buy_list() has bought hides since it was written; until
	# now no hide ever reached a village market for a cart to buy.
	var deer := _creature_at(Vector2(-20.0, 0.0))
	_hunt_until_dead(deer)
	assert_almost_eq(
		market.stock.get(HuntableQuarry.HIDE_ITEM_ID, 0.0), float(Butchering.HIDE_COUNT), 0.0001
	)


func test_a_travelling_cart_is_willing_to_buy_that_hide():
	assert_true(MerchantVisit.buy_list().has(HuntableQuarry.HIDE_ITEM_ID))


func test_a_marker_outside_the_tree_hunts_nothing_rather_than_crashing():
	# The engine only runs _process on a node in the tree, but tools and
	# probes drive markers by hand (see tools/probe_village_hunting.gd),
	# and a detached marker's get_tree() is null. Fail open, the same
	# convention every other world read on this marker follows.
	_creature_at(Vector2(-20.0, 0.0))
	remove_child(marker)
	marker._process(1.0)
	marker._process(1.0)
	marker._process(1.0)
	assert_false(marker._on_real_quarry, "no tree means nothing to find, not a crash")
	add_child(marker)


# -- a hunter runs, and the run is paid for in stamina ----------------------
#
# Asked for directly: "Hunters should run and running costs stamina which
# slowly recovers based on fitness." See docs/concept/npc.md, "A hunter runs,
# and the run is paid for in stamina": a deer that has seen you leaves at
# CreatureMarker.FLEE_SPEED, twice a villager's walk, so a hunter who only
# ever walked could take nothing that had noticed them.


## Far enough that the measured frames are all spent closing the gap, and
## inside HuntableQuarry.SEARCH_RADIUS_PX so it is really found.
const CHASE_DISTANCE_PX := 200.0

## One frame, the same slice _run walks in. Paces are measured over a single
## one on purpose: stepping a loop of 0.1s slices accumulates float error and
## lands an extra frame in, which is exactly enough to make a pace check read
## 22px where the walk is 20.
const _FRAME := 0.1


func test_a_hunter_closing_on_a_real_animal_runs():
	_creature_at(Vector2(-CHASE_DISTANCE_PX, 0.0))
	_run(ForagerBehavior.REHUNT_SECONDS + 0.2)  # long enough to commit, no longer
	# ONE frame, so this measures a pace exactly rather than accumulating
	# float error over a loop of them.
	var before := marker.position
	marker._process(_FRAME)
	assert_almost_eq(
		before.distance_to(marker.position), NpcMarker.RUN_SPEED * _FRAME, 0.001,
		"a committed hunter closes the gap at a run, not at a stroll"
	)


func test_a_villager_walking_their_own_schedule_never_runs():
	_run(ForagerBehavior.REHUNT_SECONDS + 0.2)
	var before := marker.position
	marker._process(_FRAME)
	assert_almost_eq(
		before.distance_to(marker.position), NpcMarker.WALK_SPEED * _FRAME, 0.001,
		"with no animal anywhere, the walk to work is still a walk"
	)


func test_running_at_an_animal_spends_the_hunters_wind():
	_creature_at(Vector2(-CHASE_DISTANCE_PX, 0.0))
	_run(ForagerBehavior.REHUNT_SECONDS + 1.2)
	assert_lt(marker.condition.stamina, 1.0, "the chase has to cost something")


func test_a_blown_hunter_drops_back_to_a_walk():
	_creature_at(Vector2(-CHASE_DISTANCE_PX, 0.0))
	_run(ForagerBehavior.REHUNT_SECONDS + 0.2)
	# Blown, by the meter's own rule rather than by poking a flag.
	while marker.condition.can_run():
		marker.condition.advance(0.1, 0.0, true)
	var before := marker.position
	marker._process(_FRAME)
	assert_almost_eq(
		before.distance_to(marker.position), NpcMarker.WALK_SPEED * _FRAME, 0.001,
		"out of wind, a hunter keeps following at a walk rather than stopping dead"
	)


## Not a new eyeballed number: a hunter's run is the same doubling of their
## own pace that the player's sprint already is of theirs.
func test_a_hunters_run_is_the_same_doubling_the_players_own_sprint_is():
	assert_almost_eq(
		NpcMarker.RUN_SPEED / NpcMarker.WALK_SPEED,
		Player.SPRINT_SPEED / Player.BASE_SPEED,
		0.0001,
		"one idea of what running means, not two"
	)


## And it lands exactly on a fleeing deer's own speed, which is the honest
## outcome rather than a limitation: a human does not out-sprint a deer, so a
## kill comes from the animal's fear running out before the hunter's legs do.
func test_a_running_hunter_keeps_pace_with_a_fleeing_animal_rather_than_out_running_it():
	assert_almost_eq(NpcMarker.RUN_SPEED, CreatureMarker.FLEE_SPEED, 0.0001)


## The scale sanity check the cost constant's own doc comment claims: one
## full bar of wind is about one full-radius approach, so a hunter who spots
## something at the edge of their range can actually reach it.
func test_a_full_bar_of_wind_covers_most_of_a_hunters_own_search_radius():
	var run_seconds: float = (
		(1.0 - SurvivalMeters.EXHAUSTED_THRESHOLD) / NpcCondition.RUN_STAMINA_PER_SECOND
	)
	var reach_px: float = run_seconds * NpcMarker.RUN_SPEED
	assert_gt(
		reach_px, HuntableQuarry.SEARCH_RADIUS_PX * 0.8,
		"a bar that could not cross the hunter's own search radius would make running pointless"
	)
	assert_lt(
		reach_px, HuntableQuarry.SEARCH_RADIUS_PX * 1.5,
		"...and one that crossed it several times over would make stamina pointless"
	)
