extends GutTest

## The Farm's Farmer -- a small, purpose-built walker Node2D (mirrors
## LumberjackMarker's own doc comment on why this is NOT the full
## NpcMarker stack). Owns a fixed set of real FarmPlotMarker children (the
## SAME plant/water/harvest logic and art a player's own hand-tilled plot
## already uses) and cycles: harvest a ready plot, else plant an empty one,
## else water a growing one at real risk of withering -- crediting the
## Farm's own real StructureStock on harvest (see docs/concept/
## npc_farm_production.md). Instantiates a real EarthChunkManager the same
## way test_lumberjack_marker.gd does, since harvested wheat credits its
## real StructureStock via a late-bound `earth` reference.

const FarmerMarker = preload("res://src/rendering/farmer_marker.gd")
const FarmerBehavior = preload("res://src/gameplay/farmer_behavior.gd")
const FarmPlotMarker = preload("res://src/rendering/farm_plot_marker.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var marker: FarmerMarker
var manager: EarthChunkManager
var _tile_map_layer: TileMapLayer
var _entities_parent: Node2D
var _creatures_parent: Node2D
var _berlin_tile: Vector2i
var _geo_coordinates := GeoCoordinates.new()


func before_each():
	_tile_map_layer = TileMapLayer.new()
	_entities_parent = Node2D.new()
	_creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(_tile_map_layer, _entities_parent, _creatures_parent)
	_berlin_tile = Vector2i(
		_geo_coordinates.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		_geo_coordinates.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	manager.update(_berlin_tile)

	marker = FarmerMarker.new()
	marker.earth = manager
	var home := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	marker.home = home
	marker.position = home
	add_child_autofree(marker)


func after_each():
	_tile_map_layer.free()
	_entities_parent.free()
	_creatures_parent.free()


func test_joins_the_farmer_group():
	assert_true(marker.is_in_group(FarmerMarker.GROUP_NAME))


func test_owns_the_real_plot_count():
	assert_eq(marker._plots.size(), FarmerMarker.PLOT_COUNT)
	for plot_marker in marker._plots:
		assert_true(plot_marker is FarmPlotMarker)


## Every owned plot starts empty and gets planted with wheat almost
## immediately -- the Farmer's very first priority once there is nothing
## else to do.
func test_plants_an_empty_plot_soon_after_starting():
	for i in 40:
		marker._process(0.5)
	var any_planted := false
	for plot_marker in marker._plots:
		if plot_marker.plot.state != "empty":
			any_planted = true
	assert_true(any_planted, "at least one plot should be planted after 20 simulated seconds")


func _has_wheat_stock() -> bool:
	return manager.structure_stock_at(_berlin_tile.x, _berlin_tile.y, "wheat") > 0


## The full loop, end to end: plant, tend (water before withering), harvest
## once ready, credit the Farm's own real StructureStock -- repeatable
## since a harvested plot gets re-planted.
func test_the_full_loop_eventually_yields_wheat_at_home():
	for i in 4000:
		marker._process(0.25)
		if _has_wheat_stock():
			break
	assert_true(_has_wheat_stock(), "a full plant/tend/harvest loop should eventually yield real wheat")


## Plots must not be left to wither for lack of tending -- given the
## Farmer's own real priority order (harvest, then plant, then water), no
## owned plot should ever actually reach "withered" over a long run.
func test_no_owned_plot_withers_over_a_long_run():
	for i in 4000:
		marker._process(0.25)
	for plot_marker in marker._plots:
		assert_ne(plot_marker.plot.state, "withered", "a tended plot should never be left to wither")


func test_get_display_name_reports_farmer():
	assert_eq(marker.get_display_name(), "Farmer")


func test_get_hover_actions_is_empty():
	assert_eq(marker.get_hover_actions(), [])


# -- a bed is ground, and ground does not follow a person -------------------
#
# Reported live: *"There's now some weird moving char thing + soil tiles??"*,
# then *"The soil tiles are also moving with the character..."*. The plots
# were `add_child`ed to the Farmer, so their positions were offsets from HIM
# rather than places in the world -- three tilled beds, wheat and all, walked
# around the field with the farmer every time he took a step.


func test_a_bed_stays_where_it_is_when_the_farmer_walks_away():
	var before: Array[Vector2] = []
	for plot_marker in marker._plots:
		before.append(plot_marker.global_position)

	marker.position += Vector2(96.0, 64.0)

	for i in marker._plots.size():
		assert_eq(
			marker._plots[i].global_position, before[i],
			"bed %d walked off with the farmer" % i
		)


## ...because it is not attached to him at all. A bed belongs to the world
## the farmer walks around in, which is the node he is in himself.
func test_a_bed_is_not_a_child_of_the_farmer():
	for plot_marker in marker._plots:
		assert_ne(plot_marker.get_parent(), marker, "a bed hanging off the farmer moves with him")
		assert_eq(
			plot_marker.get_parent(), marker.get_parent(),
			"a bed stands in the same world the farmer does"
		)


## And they stand at the FARM, which is what `home` means -- not wherever
## the farmer happened to be standing when his beds were first built.
func test_the_beds_stand_at_the_farm_not_wherever_the_farmer_started():
	marker.position = marker.home + Vector2(200.0, 200.0)
	for plot_marker in marker._plots:
		assert_lt(
			plot_marker.global_position.distance_to(marker.home),
			FarmerMarker.PLOT_SPACING_PX * float(FarmerMarker.PLOT_COUNT),
			"a bed should be laid out around the farm, not around the farmer"
		)


## The beds used to be freed along with the farmer for free, by being his
## children. They are siblings now, so he has to take them with him
## deliberately -- otherwise a demolished Farm leaves three tilled beds
## and their wheat standing in an empty field forever.
func test_freeing_the_farmer_takes_his_beds_with_him():
	var parent := marker.get_parent()
	var standing := FarmerMarker.PLOT_COUNT
	assert_eq(_beds_under(parent), standing, "the premise: his beds are in the world")

	marker.free()
	await get_tree().process_frame

	assert_eq(_beds_under(parent), 0, "a demolished farm left its beds behind")


func _beds_under(parent: Node) -> int:
	var found := 0
	for child in parent.get_children():
		if child is FarmPlotMarker:
			found += 1
	return found


## The invariant the bug actually broke. _step_approaching has ALWAYS walked
## the farmer to `home + _plot_offset(index)` -- a fixed spot in the world --
## while the bed itself was drawn at `farmer + _plot_offset(index)`. So the
## further he wandered, the further his beds drifted from the ground he was
## standing on to tend them. Both are the same expression now, and this is
## what keeps them that way.
func test_the_bed_he_walks_to_is_the_bed_that_is_standing_there():
	for i in marker._plots.size():
		assert_eq(
			marker._plots[i].global_position, marker.home + marker._plot_offset(i),
			"bed %d is not where the farmer walks to tend it" % i
		)


# -- the farmer asks before it walks, like every other worker ---------------
#
# Reported live: "Creatures and NPCs also walk through houses", then "the
# farmer too". The farmer was the one walker deliberately left ungated in the
# first pass, because its rails are the one fence a villager is SUPPOSED to
# cross: a field's rails stand on its inner edge, so the person they would
# otherwise shut out is the farmer whose beds they enclose. Gating it without
# that exemption would have re-broken "a farmer's own rail shut them IN",
# which a separate pass had just fixed for NpcMarker.
#
# WalkGate already takes the exemption as a parameter. What was missing was
# the farmer knowing which cells are its own.


class FenceStubWorld:
	var walls: Dictionary = {}
	var rails: Dictionary = {}  # "fx,fy>tx,ty" -> true
	func piece_blocks_movement_at_global(x: int, y: int) -> bool:
		return walls.has(Vector2i(x, y))
	func fence_blocks_step_global(fx: int, fy: int, tx: int, ty: int) -> bool:
		return rails.has("%d,%d>%d,%d" % [fx, fy, tx, ty])


func _tile_of(point: Vector2) -> Vector2i:
	return Vector2i(
		floori(point.x / TerrainRenderer.TILE_SIZE), floori(point.y / TerrainRenderer.TILE_SIZE)
	)


## Puts the farmer at its farmhouse with the middle bed as its target, on a
## stub world that answers only the two questions the gate asks.
func _farmer_walking_to_its_bed() -> FenceStubWorld:
	var world := FenceStubWorld.new()
	marker.earth = world
	marker.home = Vector2(8.0, 8.0)
	marker.position = marker.home
	marker._target_index = 1
	return world


func test_a_farmer_knows_which_beds_are_its_own():
	_farmer_walking_to_its_bed()
	var cells: Dictionary = marker.own_field_cells()
	for i in FarmerMarker.PLOT_COUNT:
		assert_true(
			cells.has(_tile_of(marker.home + marker._plot_offset(i))),
			"bed %d must be one of its own" % i
		)


## A wall is a wall, even for the farmer, and even on the way to its own soil
## -- the exemption is about rails and only rails.
func test_a_wall_between_the_farmer_and_its_bed_stops_it():
	var world := _farmer_walking_to_its_bed()
	var bed := marker.home + marker._plot_offset(1)
	world.walls[_tile_of(bed)] = true
	var before := marker.position
	marker._step_approaching(0.5)
	assert_eq(marker.position, before, "a farmer may not walk into a house either")


## ...but its OWN rail is the one fence it crosses, or it stands nine pixels
## from its own soil forever (measured, reported, and fixed once already for
## the other villager class).
func test_the_farmer_crosses_the_rail_around_its_own_field():
	var world := _farmer_walking_to_its_bed()
	var bed := marker.home + marker._plot_offset(1)
	world.rails["%d,%d>%d,%d" % [
		_tile_of(marker.home).x, _tile_of(marker.home).y, _tile_of(bed).x, _tile_of(bed).y
	]] = true
	var before := marker.position
	marker._step_approaching(0.5)
	assert_ne(marker.position, before, "its own rail must not shut it out of its beds")


## And the exemption is its OWN field, not fences in general: a neighbour's
## rail still stops it.
func test_a_neighbours_rail_still_stops_the_farmer():
	var world := _farmer_walking_to_its_bed()
	# A rail crossing on the way OUT of the farm, nowhere near its own beds.
	marker._target_index = 1
	marker.position = Vector2(200.0, 200.0)
	marker.home = Vector2(200.0, 200.0)
	var bed := marker.home + marker._plot_offset(1)
	world.rails["%d,%d>%d,%d" % [
		_tile_of(marker.position).x, _tile_of(marker.position).y,
		_tile_of(bed).x, _tile_of(bed).y
	]] = true
	# ...but tell the farmer its beds are somewhere else entirely, so this
	# rail is a stranger's.
	marker.home = Vector2(1000.0, 1000.0)
	var before := marker.position
	marker._step_approaching(0.5)
	assert_eq(marker.position, before, "somebody else's fence is still a fence")


## The exemption's cache is keyed on `home`, so a farmer whose farmhouse
## moves cannot keep answering with the old field's cells.
func test_moving_the_farmhouse_moves_which_beds_count_as_its_own():
	_farmer_walking_to_its_bed()
	var first: Dictionary = marker.own_field_cells().duplicate()
	marker.home = Vector2(600.0, 600.0)
	var second: Dictionary = marker.own_field_cells()
	assert_ne(first.keys(), second.keys(), "the cache may not outlive the home it was built for")
