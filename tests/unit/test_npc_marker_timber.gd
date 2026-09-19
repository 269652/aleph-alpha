extends GutTest

## A villager who actually works the sawmill (docs/concept/village_timber.md).
##
## Reported in play: "The sawmill also never produces any beams and doesn't
## even have a dedicated worker". The village raised a sawmill at its own
## timber and nothing ever worked it -- there was not even a trade for it.
##
## Same three-part split the hunter and the farmer already use: VillageSawmill
## decides WHAT, LumberjackBehavior decides WHEN, and NpcMarker owns the world
## effect -- real trees felled with the same ChoppableTree.take_damage loop a
## player's own axe uses.

const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const NpcPlanner = preload("res://src/world/npc_planner.gd")
const VillageMarket = preload("res://src/world/village_market.gd")
const VillageSawmill = preload("res://src/gameplay/village_sawmill.gd")
const SagewerkProduction = preload("res://src/world/sagewerk_production.gd")
const FelledTree = preload("res://src/rendering/felled_tree.gd")

const TILE_SIZE := 16
const MILL_CELL := Vector2i(10, 10)
const MILL_POSITION := Vector2(10 * 16 + 8, 10 * 16 + 8)


## Stands in for a real ChoppableTree: the same group, the same is_felled /
## take_damage / growth_scale surface the marker actually touches.
class FakeTree:
	extends Node2D
	var growth_scale := 1.0
	var hits := 0
	var _felled := false
	var _canopy_removed := false
	var _cuts_left: int = FelledTree.CUTS_TO_CLEAR
	## Logs this stub would have dropped ON THE GROUND, the way the real
	## ChoppableTree._cut_up does. A worker must never make the ground grow a
	## pile of the same timber it is carrying home (see buck_for_worker).
	var ground_logs := 0
	var worker_logs := 0

	func _ready() -> void:
		add_to_group("tree")

	func is_felled() -> bool:
		return _felled

	func canopy_removed() -> bool:
		return _canopy_removed

	func cuts_left() -> int:
		return _cuts_left

	func take_damage(_amount: float) -> void:
		hits += 1
		if not _felled:
			_felled = true
			return
		if not _canopy_removed:
			_canopy_removed = true
			return
		_cuts_left -= 1
		ground_logs += FelledTree.logs_per_cut(growth_scale)
		if _cuts_left <= 0:
			queue_free()

	func buck_for_worker() -> int:
		if not _felled or not _canopy_removed or _cuts_left <= 0:
			return 0
		_cuts_left -= 1
		var logs := FelledTree.logs_per_cut(growth_scale)
		worker_logs += logs
		if _cuts_left <= 0:
			queue_free()
		return logs

	## The state a trunk somebody ELSE already felled and limbed is in.
	func fell_and_limb() -> void:
		_felled = true
		_canopy_removed = true


## A world that answers the structure-stock questions the real
## EarthChunkManager does, so a mill has somewhere to keep its logs.
class StubTimberWorld:
	var biome := "forest"
	var stock: Dictionary = {}

	func biome_at_global(_x: int, _y: int) -> String:
		return biome

	func vegetation_density_near(_pos: Vector2) -> float:
		return 0.6

	func herbivore_population_near(_pos: Vector2) -> float:
		return 0.0

	func fish_population_near(_pos: Vector2) -> float:
		return 0.0

	func deposit_to_structure_at(_x: int, _y: int, item_id: String, count: int) -> void:
		stock[item_id] = int(stock.get(item_id, 0)) + count

	func withdraw_from_structure_at(_x: int, _y: int, item_id: String, count: int) -> bool:
		if int(stock.get(item_id, 0)) < count:
			return false
		stock[item_id] = int(stock[item_id]) - count
		return true

	func structure_stock_at(_x: int, _y: int, item_id: String) -> int:
		return int(stock.get(item_id, 0))


class AllWorkPlanner:
	extends NpcPlanner.Planner
	func plan_day(_identity: NpcIdentity, _day_index: int) -> Array:
		var out: Array = []
		for block in ["morning", "midday", "evening", "night"]:
			out.append({"time_block": block, "location_tag": "sawmill", "activity": "work"})
		return out


var marker: NpcMarker
var world: StubTimberWorld
var market: VillageMarket
var _extra: Array = []


func before_each():
	world = StubTimberWorld.new()
	market = VillageMarket.new()
	marker = NpcMarker.new()
	marker.identity = NpcIdentity.new(1)
	marker.identity.occupation = VillageSawmill.OCCUPATION
	marker.home_position = MILL_POSITION
	marker.workspot_position = MILL_POSITION
	marker.landmarks = {"sawmill": MILL_POSITION, "well": MILL_POSITION}
	marker.position = MILL_POSITION
	marker.set_planner(AllWorkPlanner.new())
	marker.setup(world, TILE_SIZE)
	marker.setup_economy(market)
	marker.sawmill_cell = MILL_CELL
	add_child(marker)


func after_each():
	remove_child(marker)
	marker.free()
	for node in _extra:
		if is_instance_valid(node):
			node.free()
	_extra.clear()


func _tree_at(at: Vector2) -> FakeTree:
	var tree := FakeTree.new()
	tree.position = at
	add_child(tree)
	_extra.append(tree)
	return tree


func _run(seconds: float, slice := 0.1) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		marker._process(slice)
		elapsed += slice


# -- the sawyer goes out to real timber ------------------------------------


func test_a_lumberjack_walks_out_to_a_real_tree():
	var tree := _tree_at(MILL_POSITION + Vector2(100, 0))
	var before := marker.position
	_run(2.0)
	assert_lt(
		marker.position.distance_to(tree.position), before.distance_to(tree.position),
		"a sawyer with no logs goes to the wood"
	)


func test_a_lumberjack_really_fells_the_tree_they_reach():
	var tree := _tree_at(MILL_POSITION + Vector2(40, 0))
	_run(30.0)
	assert_gt(tree.hits, 0, "the same axe as the player's, swung by a villager")
	assert_true(tree.is_felled())


## Timber beyond the mill's own range is somebody else's wood: a village
## fells its own rather than stripping the map.
func test_a_tree_out_of_the_mills_range_is_left_standing():
	var reach := float(VillageSawmill.TIMBER_REACH_TILES) * float(TILE_SIZE)
	var tree := _tree_at(MILL_POSITION + Vector2(reach + 200.0, 0))
	_run(20.0)
	assert_eq(tree.hits, 0, "a sawyer does not cross the map for one trunk")


# -- and the logs reach the mill -------------------------------------------


## The mill really receives what the sawyer cut. Asserted the moment the
## logs land rather than at the end of the run: a mill that is working
## SQUARES them (3 logs to a beam, see _shape_a_beam), so a stock read long
## afterwards is measuring how much has not been milled yet, not how much
## arrived. This test used to pass only because the shaping never kept up.
func test_felling_puts_real_logs_into_the_mill():
	_tree_at(MILL_POSITION + Vector2(40, 0))
	var peak := 0
	for i in 600:
		marker._process(0.1)
		peak = maxi(peak, world.structure_stock_at(0, 0, "log"))
	assert_gt(peak, 0, "the wood a sawyer cut is at the mill")


## And the mill squares it. Reported live: "it only produced 6xLogs but no
## beams" -- the other half of the same chain, and the whole reason a
## village's sawmill exists.
func test_the_mill_squares_the_logs_its_sawyer_brought_in():
	_tree_at(MILL_POSITION + Vector2(40, 0))
	for i in 600:
		marker._process(0.1)
		if world.structure_stock_at(0, 0, "beam") > 0:
			break
	assert_gt(world.structure_stock_at(0, 0, "beam"), 0, "a mill with logs in it squares beams")


# -- and the mill squares them into beams ----------------------------------


func test_a_mill_with_enough_logs_produces_a_real_beam():
	world.stock["log"] = VillageSawmill.LOGS_PER_BEAM * 2
	_run(SagewerkProduction.SHAPE_SECONDS_PER_BEAM + 5.0)
	assert_gt(world.structure_stock_at(0, 0, "beam"), 0, "the sawmill produces beams")


func test_squaring_a_beam_really_consumes_the_logs_it_costs():
	world.stock["log"] = VillageSawmill.LOGS_PER_BEAM
	_run(SagewerkProduction.SHAPE_SECONDS_PER_BEAM + 5.0)
	assert_eq(
		world.structure_stock_at(0, 0, "log"), 0,
		"three logs went into the beam, exactly as the mill's own cost says"
	)
	assert_eq(world.structure_stock_at(0, 0, "beam"), 1)


## Shaping takes real time -- a mill that turned logs into beams the instant
## they arrived would be a number going up, not a trade.
func test_a_beam_is_not_squared_instantly():
	world.stock["log"] = VillageSawmill.LOGS_PER_BEAM
	_run(SagewerkProduction.SHAPE_SECONDS_PER_BEAM * 0.4)
	assert_eq(world.structure_stock_at(0, 0, "beam"), 0, "squaring a beam is slow, skilled work")


# -- and nobody else does any of this --------------------------------------


func test_a_villager_who_is_not_a_lumberjack_fells_nothing():
	marker.identity.occupation = "nurse"
	marker.sawmill_cell = NpcMarker.NO_SAWMILL
	var tree := _tree_at(MILL_POSITION + Vector2(40, 0))
	_run(20.0)
	assert_eq(tree.hits, 0, "a nurse does not fell trees")


func test_a_lumberjack_with_no_mill_of_their_own_fells_nothing():
	marker.sawmill_cell = NpcMarker.NO_SAWMILL
	var tree := _tree_at(MILL_POSITION + Vector2(40, 0))
	_run(20.0)
	assert_eq(tree.hits, 0, "a village with no sawmill has no sawmill work")


# -- and the beams reach the village ---------------------------------------
#
# The same store-then-haul chain the farmhouse already runs
# (docs/concept/building_storage.md): grown/cut at the worksite, held there,
# carried to the village at the end of the work block.


class OffDutyPlanner:
	extends NpcPlanner.Planner
	func plan_day(_identity: NpcIdentity, _day_index: int) -> Array:
		var out: Array = []
		for block in ["morning", "midday", "evening", "night"]:
			out.append({"time_block": block, "location_tag": "home", "activity": "idle"})
		return out


func test_the_mills_beams_are_carried_to_the_village():
	world.stock["beam"] = 4
	marker.haul_sawmill_stock_to_village()
	assert_eq(world.structure_stock_at(0, 0, "beam"), 0, "the mill handed over what it had")
	assert_gt(float(market.stock.get("beam", 0.0)), 0.0, "and the village has it now")


## Enough beams that a whole COIN certainly lands, whatever the levy is.
##
## A wallet holds whole coins only; a take-home under one is carried
## (NpcEconomy._take_home_carry) rather than lost, so a small haul can pay
## a villager and move no coin at all. This used to haul three beams, which
## cleared exactly 1.0 at the levy of the day -- and adding one occupation
## to NpcIdentity.OCCUPATIONS moved the levy (it is derived from the
## non-producer share of the census, see VillageWages.wage_share) and with
## it the take-home, to 0.9. The test was measuring the rounding boundary,
## not the payment.
func test_hauling_pays_the_sawyer_for_what_they_carried_in():
	world.stock["beam"] = 10
	var before := marker.economy.wallet.balance
	marker.haul_sawmill_stock_to_village()
	assert_gt(marker.economy.wallet.balance, before, "paid on arrival, like a farmer's crop")


func test_an_empty_mill_carries_nothing_and_changes_nothing():
	var before := marker.economy.wallet.balance
	marker.haul_sawmill_stock_to_village()
	assert_eq(marker.economy.wallet.balance, before)
	assert_eq(float(market.stock.get("beam", 0.0)), 0.0)


func test_a_villager_with_no_mill_hauls_nothing():
	marker.sawmill_cell = NpcMarker.NO_SAWMILL
	world.stock["beam"] = 4
	marker.haul_sawmill_stock_to_village()
	assert_eq(world.structure_stock_at(0, 0, "beam"), 4, "not their mill to empty")


## Logs are the mill's own raw material and stay there -- carrying them to
## the village would be carrying away the thing the sawmill exists to work.
func test_the_logs_a_mill_is_working_are_not_carried_off():
	world.stock["log"] = 5
	marker.haul_sawmill_stock_to_village()
	assert_eq(world.structure_stock_at(0, 0, "log"), 5, "a mill keeps its own timber")


## The haul happens on its own, at the end of the work block -- the same
## point the farmhouse's does, and the one moment reached every day.
func test_the_beams_go_in_on_their_own_when_the_day_ends():
	world.stock["beam"] = 2
	marker.set_planner(OffDutyPlanner.new())
	marker.schedule = []
	_run(1.0)
	assert_eq(world.structure_stock_at(0, 0, "beam"), 0, "clocking off carries the day's beams in")


# -- the trunks lying around the mill ----------------------------------------
# Reported live: "there are lying two felled trees around the sawmill and the
# worker doesn't bring them in". The sawyer looked only for STANDING trees,
# so a trunk left lying -- by the player, by weather, or by this villager
# before they went off the clock and dropped it (_abandon_timber) -- stayed
# there for ever while they walked past it to fell another.

func test_a_trunk_already_lying_by_the_mill_is_worked_up():
	var trunk := _tree_at(MILL_POSITION + Vector2(TILE_SIZE, 0))
	trunk.fell_and_limb()
	for i in 4000:
		marker._process(0.25)
		if not is_instance_valid(trunk) or trunk.is_queued_for_deletion():
			break
	assert_true(trunk.is_queued_for_deletion(), "a sawyer finishes what is already down")


## And the logs it bucks reach the MILL, not the ground beside it. Every
## swing used to create the timber twice: the take_damage drop AND the
## villager's own carried count.
func test_the_logs_the_sawyer_bucks_are_not_also_dropped_on_the_ground():
	var trunk := _tree_at(MILL_POSITION + Vector2(TILE_SIZE, 0))
	trunk.fell_and_limb()
	for i in 4000:
		marker._process(0.25)
		if not is_instance_valid(trunk) or trunk.is_queued_for_deletion():
			break
	assert_eq(trunk.ground_logs, 0, "the sawyer carries the logs home; they are not also on the ground")
	assert_gt(trunk.worker_logs, 0, "and they really were bucked")


# -- the mill's shelf is the carter's to empty (Mechanism 7) ----------------
#
# Reported in play with the mill's own panel in shot, reading "Stored: 0 / 60,
# Beam x0, Log x0": *"The sawmill also doesn't produce beams or plangs or
# logs"*. It produced them all along -- and then, at the end of every work
# block, the sawyer carried every beam off the shelf into the abstract
# village ledger, exactly as the farmer used to do with their farmhouse. So
# the mill you clicked was always empty, and the carter arrived at a shelf
# somebody had already emptied.


func test_a_sawyer_in_a_village_with_a_store_leaves_the_beams_on_the_shelf():
	marker.warehouse_position = Vector2(400.0, 400.0)  # this village has a store
	world.stock["beam"] = 5

	marker.haul_sawmill_stock_to_village()

	assert_eq(world.structure_stock_at(0, 0, "beam"), 5, "the mill is still holding them")


## And a village with no store keeps the old behaviour exactly: the sawyer
## carries them in, because there is nowhere else for them to go.
func test_a_sawyer_with_no_store_still_carries_the_beams_in():
	marker.warehouse_position = null
	world.stock["beam"] = 5

	marker.haul_sawmill_stock_to_village()

	assert_eq(world.structure_stock_at(0, 0, "beam"), 0, "carried in, as before")


## Off the clock is where it happened: the whole shelf went at the end of
## every single work block.
func test_going_off_the_clock_no_longer_empties_a_mill_in_a_village_with_a_store():
	marker.warehouse_position = Vector2(400.0, 400.0)
	world.stock["beam"] = 5

	marker._step_timber(0.1, false)

	assert_eq(world.structure_stock_at(0, 0, "beam"), 5, "the beams are still at the mill")
