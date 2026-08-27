extends GutTest

## The Sägewerk's Lumberjack -- a small, purpose-built walker Node2D
## (mirrors DecomposerMarker's own doc comment on why this is NOT the full
## NpcMarker stack). SEEKING (find the nearest real standing ChoppableTree)
## -> APPROACHING -> FELLING (the SAME ChoppableTree.take_damage loop a
## player's axe uses) -> CARRYING -> DEPOSIT (credits the Sägewerk's own log
## stock, which separately shapes into beam/plank -- see
## docs/concept/timber_construction.md).
##
## Shaped beam/plank output now credits the Sägewerk's own StructureStock
## (via EarthChunkManager.deposit_to_structure_at, through a late-bound
## `earth` reference -- see LogisticsMarker's identical pattern) instead of
## the old WorldItemBus ground-drop, so these tests instantiate a real
## EarthChunkManager the same way test_logistics_marker.gd does, rather than
## a bare Node2D marker with no world to credit.

const LumberjackMarker = preload("res://src/rendering/lumberjack_marker.gd")
const LumberjackBehavior = preload("res://src/gameplay/lumberjack_behavior.gd")
const ChoppableTree = preload("res://src/rendering/choppable_tree.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var marker: LumberjackMarker
var tree: ChoppableTree
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

	marker = LumberjackMarker.new()
	marker.earth = manager
	var home := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	marker.home = home
	marker.position = home
	add_child_autofree(marker)


func after_each():
	if is_instance_valid(tree):
		tree.free()
	_tile_map_layer.free()
	_entities_parent.free()
	_creatures_parent.free()


func _standing_tree_at(at: Vector2) -> ChoppableTree:
	var t := ChoppableTree.new()
	t.position = at
	add_child_autofree(t)
	return t


func test_joins_the_lumberjack_group():
	assert_true(marker.is_in_group(LumberjackMarker.GROUP_NAME))


func test_joins_the_hoverable_group():
	assert_true(marker.is_in_group(HoverTargetFinder.GROUP_NAME))


func test_stays_near_home_while_no_tree_is_in_reach():
	for i in 30:
		marker._process(0.5)
	assert_lt(marker.position.distance_to(marker.home), LumberjackMarker.WANDER_RADIUS_PX * 2.0)


## The full loop, end to end: a nearby standing tree is found, walked to,
## felled, bucked into logs, and the Lumberjack carries the haul home --
## eventually shaping real beam or plank output, now credited to the
## Sägewerk's own real StructureStock (see SagewerkProduction).
func _has_shaped_output() -> bool:
	return (
		manager.structure_stock_at(_berlin_tile.x, _berlin_tile.y, "beam") > 0
		or manager.structure_stock_at(_berlin_tile.x, _berlin_tile.y, "plank") > 0
	)


func test_the_full_loop_eventually_yields_beam_or_plank_at_home():
	tree = _standing_tree_at(marker.home + Vector2(10, 0))
	for i in 4000:
		marker._process(0.25)
		if _has_shaped_output():
			break
	assert_true(_has_shaped_output(), "a full seek/fell/carry/deposit loop should eventually shape real output")


## The old ground-drop is really gone -- shaped output must NOT also emit a
## WorldItemBus pickup, or a Storage-fed Logistics worker and a player
## ground-pickup would both be crediting the same beam/plank twice over.
func test_shaped_output_no_longer_emits_a_worlditembus_drop():
	var drops: Array = []
	var record := func(stack, _position): drops.append(stack)
	WorldItemBus.item_dropped.connect(record)
	tree = _standing_tree_at(marker.home + Vector2(10, 0))
	for i in 4000:
		marker._process(0.25)
		if _has_shaped_output():
			break
	WorldItemBus.item_dropped.disconnect(record)
	for stack in drops:
		assert_ne(stack.item.id, "beam", "beam should credit StructureStock, not the ground")
		assert_ne(stack.item.id, "plank", "plank should credit StructureStock, not the ground")


## Felling really does fell the SAME tree a player's axe would -- no
## separate mechanic, just a different caller (see
## docs/concept/timber_construction.md's own framing).
func test_felling_actually_fells_and_clears_the_real_tree():
	tree = _standing_tree_at(marker.home + Vector2(2, 0))
	for i in 4000:
		marker._process(0.25)
		if is_instance_valid(tree) and tree.is_queued_for_deletion():
			break
	assert_true(tree.is_queued_for_deletion(), "the Lumberjack should have fully worked up the tree")


## Once carrying a load home, the Lumberjack goes back to seeking rather
## than getting stuck.
func test_returns_to_seeking_after_a_full_deposit():
	tree = _standing_tree_at(marker.home + Vector2(2, 0))
	for i in 4000:
		marker._process(0.25)
		if _has_shaped_output():
			break
	marker._process(1.0)
	assert_eq(marker._behavior.phase, LumberjackBehavior.Phase.SEEKING)


func test_get_display_name_reports_lumberjack():
	assert_eq(marker.get_display_name(), "Lumberjack")
