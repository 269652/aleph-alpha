extends GutTest

## A departing caravan leaves both villages by their own roads.
##
## Asked for after every other walking marker had a building gate: *"fix
## the caravan and cart markers too"*. A caravan cannot be given that gate
## -- its position is a pure closed-form function of elapsed time, and
## is_arrived, raid_triggered and its PathScarring wear all read the same
## progress, so deflecting the MARKER would only make the marker and the
## trip disagree about where the caravan is (see CaravanTrip.waypoints).
##
## The route bends instead. The geometry is VillageLayout's
## (road_exit_toward) and the polyline is CaravanTrip's, both tested where
## they live; this is the WIRING -- that a real departure actually builds
## the bent route rather than the straight line it used to.
##
## Two settlements a chunk apart, driven through the real
## step_regional_trade the way test_earth_chunk_manager.gd already does.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const VillageLayout = preload("res://src/world/village_layout.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D

var _shortage_coord := Vector2i(0, 0)
var _supplier_coord := Vector2i(-1, 0)
var _shortage_id: String
var _supplier_id: String


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(entities_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	# Seed 11 is a BLACKSMITH, and a blacksmith is what creates the real
	# shortage a caravan is dispatched for (a stone_pickaxe needs 3 rock and
	# 2 stick). Checked rather than copied: test_earth_chunk_manager.gd's
	# own caravan tests still say seed 8 is one, and it generates a nurse
	# now -- so those tests depart no caravan at all and assert against an
	# empty list.
	manager.record_settlement_founded_if_new(_shortage_coord, [NpcIdentity.new(11)])
	manager.record_settlement_founded_if_new(_supplier_coord, [NpcIdentity.new(1)])
	_shortage_id = EntityRef.for_settlement(_shortage_coord)
	_supplier_id = EntityRef.for_settlement(_supplier_coord)
	manager.market_store().market_for(_supplier_id).add_stock("rock", 20)
	manager.market_store().market_for(_supplier_id).add_stock("stick", 20)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _depart() -> Array:
	manager.step_regional_trade(EarthChunkManager.REGIONAL_TRADE_INTERVAL)
	var trips: Array = []
	for entry in manager._active_caravans:
		trips.append(entry["trip"])
	return trips


func _exits_of(coord: Vector2i, toward: Vector2) -> Array:
	return VillageLayout.road_exit_toward(
		VillageLayout.skeleton(
			EarthChunkManager.CHUNK_SIZE, VillageLayout.seed_for(coord),
			manager._is_dry_local(coord)
		),
		coord * EarthChunkManager.CHUNK_SIZE, float(TerrainRenderer.TILE_SIZE), toward
	)


func test_a_real_departure_bends_its_route_round_both_villages():
	var trips := _depart()
	assert_gt(trips.size(), 0, "precondition: a caravan really departed")
	for trip in trips:
		assert_gt(trip.waypoints.size(), 0, "a caravan that walks straight walks through houses")


## Out of the supplier's village by its road, and INTO the shortage
## village by its road -- both ends, because a caravan arrives somewhere
## too. The waypoints are exactly those four points, in that order.
func test_the_route_leaves_by_one_road_and_arrives_by_the_other():
	for trip in _depart():
		var out := _exits_of(_supplier_coord, trip.destination)
		var arrive := _exits_of(_shortage_coord, trip.origin)
		assert_eq(out.size(), 2, "the supplier village has a street")
		assert_eq(arrive.size(), 2, "and so does the one waiting")
		assert_eq(
			trip.waypoints, [out[0], out[1], arrive[1], arrive[0]],
			"out along the road, across country, then in along the other road"
		)


## The first thing the caravan does is walk to its own street, and the last
## is walk in from the other one -- stated as the shape of the route rather
## than as four coordinates, so it still reads if the layout changes.
func test_the_route_still_starts_at_one_well_and_ends_at_the_other():
	for trip in _depart():
		var points: Array = trip.route()
		assert_eq(points[0], trip.origin, "it starts where the goods are")
		assert_eq(points[points.size() - 1], trip.destination, "and ends where they are needed")
		assert_gt(
			trip.route_length(), trip.origin.distance_to(trip.destination),
			"a route round two villages is longer than the line through them"
		)


## ...and it still gets there. The detour must not leave a caravan walking
## for ever, which is what would happen if travel_seconds had kept
## measuring the straight line while position_at walked the longer route.
func test_a_bent_caravan_still_arrives_and_resolves():
	_depart()
	assert_gt(manager._active_caravans.size(), 0)
	for i in 600:
		manager.advance_world_age(1.0)
		manager.step_caravans()
		if manager._active_caravans.is_empty():
			break
	assert_true(manager._active_caravans.is_empty(), "every caravan resolved")
	assert_gt(
		manager.market_store().market_for(_shortage_id).stock_of("rock"), 0,
		"and the goods really arrived"
	)

