extends GutTest

## The builder on a construction site (docs/concept/building.md, "Somebody
## is working on it" and "And he carries the material"). Asked for
## directly: *"the construction site should show a builder working on it"*,
## and then *"the builders should carry materials to the site"*.
##
## A small purpose-built walker, like the Farmer and the Lumberjack and for
## the same reason -- so what it owes is small and exact: he works his own
## plot, he moves about it rather than standing like a prop, and the only
## thing that ever takes him off the site is fetching the material the
## project really reserved from the store that really holds it.

const ConstructionWorkerMarker = preload("res://src/rendering/construction_worker_marker.gd")
const ConstructionHaul = preload("res://src/gameplay/construction_haul.gd")
const LogisticsMarker = preload("res://src/rendering/logistics_marker.gd")
const ProceduralBuilderSprite = preload("res://src/rendering/procedural_builder_sprite.gd")
const NpcMarker = preload("res://src/rendering/npc_marker.gd")

const PLOT := Rect2(Vector2(100.0, 200.0), Vector2(32.0, 32.0))
const STORE := Vector2(400.0, 200.0)
const RESERVED := {"wood": 12.0}
const FRAME := 1.0 / 60.0

var worker: ConstructionWorkerMarker


func before_each():
	worker = ConstructionWorkerMarker.new()
	worker.plot = PLOT
	worker.seed_value = 4242
	worker.position = PLOT.position + PLOT.size * 0.5
	add_child(worker)


func after_each():
	remove_child(worker)
	worker.free()


func _work(seconds: float) -> Array:
	var seen: Array = []
	for i in int(seconds / FRAME):
		worker._process(FRAME)
		seen.append(worker.position)
	return seen


# -- the plot: a man working, when there is nothing to fetch ---------------


## Nothing reserved and no store: exactly the builder that existed before
## the haul, working the plot he stands on.
func test_a_builder_with_nothing_to_fetch_never_leaves_the_site():
	for point in _work(60.0):
		assert_true(
			PLOT.has_point(point as Vector2),
			"%s is off the plot %s -- with nothing to fetch, the site is the job" % [point, PLOT]
		)


## And a village whose site is too cramped for a store (village_warehouse.md's
## own pillar-1 caveat) has nowhere to fetch FROM -- so its builder works,
## rather than walking off toward a store that does not exist.
func test_a_builder_with_no_store_in_reach_just_works():
	worker.reserved_material = RESERVED.duplicate()
	for point in _work(60.0):
		assert_true(PLOT.has_point(point as Vector2), "%s is off the plot with no store to go to" % point)


func test_a_builder_moves_about_the_site_rather_than_standing_like_a_prop():
	var seen := _work(30.0)
	var furthest := 0.0
	for point in seen:
		furthest = maxf(furthest, (point as Vector2).distance_to(seen[0] as Vector2))
	assert_gt(furthest, 4.0, "a builder who never moves is a statue on a plot")


## And he stops to work: a figure gliding continuously about a building
## site is a patrol, not a workman.
func test_a_builder_stops_to_work_between_moves():
	var seen := _work(30.0)
	var still := 0
	for i in range(1, seen.size()):
		if (seen[i] as Vector2).is_equal_approx(seen[i - 1] as Vector2):
			still += 1
	assert_gt(still, seen.size() / 10, "a builder spends real time working, not only walking")


func test_two_builders_with_the_same_seed_work_the_same_way():
	var twin := ConstructionWorkerMarker.new()
	twin.plot = PLOT
	twin.seed_value = worker.seed_value
	twin.position = worker.position
	add_child(twin)
	for i in 600:
		worker._process(FRAME)
		twin._process(FRAME)
	assert_almost_eq(worker.position.x, twin.position.x, 0.001)
	assert_almost_eq(worker.position.y, twin.position.y, 0.001)
	remove_child(twin)
	twin.free()


## A worker with no site given to him stays exactly where he was put,
## rather than walking off toward the world's origin.
func test_a_builder_with_no_plot_stays_put():
	var stray := ConstructionWorkerMarker.new()
	stray.position = Vector2(10.0, 20.0)
	add_child(stray)
	for i in 120:
		stray._process(FRAME)
	assert_eq(stray.position, Vector2(10.0, 20.0))
	remove_child(stray)
	stray.free()


# -- the round: store, load, site, work (docs/concept/building.md) ---------


func _stock_the_round() -> void:
	worker.reserved_material = RESERVED.duplicate()
	worker.depot = STORE


func test_he_walks_to_the_store_for_the_material():
	_stock_the_round()
	var closest := INF
	for point in _work(60.0):
		closest = minf(closest, (point as Vector2).distance_to(STORE))
	assert_lte(closest, ConstructionWorkerMarker.ARRIVE_DISTANCE_PX, "he got %.1f px from the store" % closest)


func test_what_he_picks_up_is_what_the_project_reserved():
	_stock_the_round()
	var carried := ""
	for i in int(60.0 / FRAME):
		worker._process(FRAME)
		if worker.carried_count > 0.0:
			carried = worker.carried_item_id
			break
	assert_eq(carried, "wood", "he carries the timber the cottage is really made of")


func test_he_carries_it_back_and_sets_it_down_on_the_site():
	_stock_the_round()
	var delivered_on_the_plot := false
	var was_carrying := false
	for i in int(120.0 / FRAME):
		worker._process(FRAME)
		if worker.carried_count > 0.0:
			was_carrying = true
		elif was_carrying:
			delivered_on_the_plot = PLOT.has_point(worker.position)
			break
	assert_true(was_carrying, "precondition: he picked something up")
	assert_true(delivered_on_the_plot, "the load is set down ON the site, not dropped on the way")
	assert_gt(float(worker.delivered.get("wood", 0.0)), 0.0, "and the site's pile really grew")


func test_he_works_the_plot_between_loads_rather_than_only_hauling():
	_stock_the_round()
	var still_on_the_plot := 0
	var seen := _work(240.0)
	for i in range(1, seen.size()):
		if (seen[i] as Vector2).is_equal_approx(seen[i - 1] as Vector2) and PLOT.has_point(seen[i] as Vector2):
			still_on_the_plot += 1
	assert_gt(
		float(worker.delivered.get("wood", 0.0)), float(ConstructionHaul.CARRY_LOAD),
		"precondition: more than one load came in"
	)
	assert_gt(still_on_the_plot, 60, "a builder who only hauls never builds anything")


## The round ends: once the whole reservation is standing on the site there
## is nothing left to fetch, and he is a man working his plot again.
func test_when_the_pile_is_all_on_site_he_only_works():
	_stock_the_round()
	_work(600.0)
	assert_almost_eq(
		float(worker.delivered.get("wood", 0.0)), float(RESERVED["wood"]), 0.001,
		"precondition: the whole reservation was carried in"
	)
	for point in _work(60.0):
		assert_true(PLOT.has_point(point as Vector2), "%s -- nothing left to fetch, so nothing to leave for" % point)


## He walks the round and nothing else: a builder found somewhere that is
## neither his plot nor the road to the store has wandered off the job.
##
## Measured as an ellipse with the site and the store for foci, slack a
## whole plot diagonal wide -- a spot he legitimately works is up to that
## far off the straight line between the two, and nothing else he could do
## is.
func test_he_never_wanders_off_the_round_between_the_two():
	_stock_the_round()
	var leg := PLOT.get_center().distance_to(STORE)
	var slack := PLOT.size.length()
	for point in _work(240.0):
		var p := point as Vector2
		assert_lte(
			p.distance_to(PLOT.get_center()) + p.distance_to(STORE), leg + slack,
			"%s is neither on the site nor on the way to the store" % p
		)


## Two men carrying goods across the same square at visibly different
## speeds is something the eye catches at once, so a loaded builder's road
## pace is the village porter's, pinned to it rather than restated beside
## it -- and both are faster than the pace he picks about a footprint at,
## because crossing a village and stepping between two corners of one plot
## are not the same walk.
func test_a_builder_on_the_road_walks_at_the_porters_pace():
	assert_eq(ConstructionWorkerMarker.HAUL_SPEED, LogisticsMarker.WALK_SPEED)
	assert_gt(ConstructionWorkerMarker.HAUL_SPEED, ConstructionWorkerMarker.WALK_SPEED)


## And you can see which leg of the round he is on: the mallet up on the
## way out to the store, a load on his shoulder on the way back, put down
## again when it reaches the site.
func test_he_is_drawn_loaded_exactly_while_he_carries():
	_stock_the_round()
	assert_true(_drawn_as(false), "he sets out empty-handed")
	for i in int(120.0 / FRAME):
		worker._process(FRAME)
		if worker.carried_count > 0.0:
			break
	assert_gt(worker.carried_count, 0.0, "precondition: he picked a load up")
	assert_true(_drawn_as(true), "and is visibly carrying it")
	for i in int(120.0 / FRAME):
		worker._process(FRAME)
		if worker.carried_count <= 0.0:
			break
	assert_eq(worker.carried_count, 0.0, "precondition: he set it down")
	assert_true(_drawn_as(false), "and has his hands free again")


## Whether the sprite he is really wearing is the loaded drawing or the
## empty-handed one. A bool rather than the two images, so a failure reads
## as one line instead of eight hundred bytes of pixels.
func _drawn_as(carrying: bool) -> bool:
	var sprite := worker.get_child(0) as Sprite2D
	var drawn := (sprite.texture as ImageTexture).get_image().get_data()
	return drawn == ProceduralBuilderSprite.new().generate_image(carrying).get_data()


# -- a wall between him and the store (docs/concept/navigation.md) ---------
#
# Measured on a real village (tools/probe_construction_haul.gd): given a
# straight line and the wall slide alone, a builder walked 68 px toward
# the store's door, pressed into the corner of a building 25 px short of
# it, and stood there for the remaining 230 simulated seconds -- nothing
# delivered, never once back on his own plot. Sliding is a reflex for a
# wall you brush; a detour needs a plan, which is what TileRouter is and
# what every villager already walks on.


## A world that answers the one question AgentPassability asks about
## buildings, with a wall standing between the site and the store and a
## way round its south end.
class WalledVillage:
	extends RefCounted

	const WALL_COLUMN := 20
	const GAP_BELOW_ROW := 21

	func has_building_at_global(x: int, y: int) -> bool:
		return x == WALL_COLUMN and y <= GAP_BELOW_ROW


func test_he_walks_round_a_building_standing_between_him_and_the_store():
	_stock_the_round()
	var village := WalledVillage.new()
	worker.earth = village
	var reached_the_store := false
	var stood_in_a_wall := false
	for i in int(240.0 / FRAME):
		worker._process(FRAME)
		if worker.position.distance_to(STORE) <= ConstructionWorkerMarker.ARRIVE_DISTANCE_PX:
			reached_the_store = true
		var tile := Vector2i(
			floori(worker.position.x / 16.0), floori(worker.position.y / 16.0)
		)
		if village.has_building_at_global(tile.x, tile.y):
			stood_in_a_wall = true
	assert_true(reached_the_store, "he never got round the wall to the store")
	assert_false(stood_in_a_wall, "and he did not walk through it either")
	assert_gt(
		float(worker.delivered.get("wood", 0.0)), 0.0,
		"a builder who cannot reach the store delivers nothing, however long you watch"
	)


## The same budget and the same throttle every villager routes on, read off
## NpcMarker rather than restated beside it: two walkers searching the same
## village to different depths is a difference nobody can justify.
func test_a_builder_routes_on_the_same_terms_a_villager_does():
	assert_eq(ConstructionWorkerMarker.ROUTE_NODE_BUDGET, NpcMarker.ROUTE_NODE_BUDGET)
	assert_eq(ConstructionWorkerMarker.ROUTE_RECOMPUTE_SECONDS, NpcMarker.ROUTE_RECOMPUTE_SECONDS)
