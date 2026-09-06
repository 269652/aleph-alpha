extends GutTest

## EarthChunkManager.crush_walnut_near -- "crack open" (see docs/concept/
## soil_fauna.md "Crushed underfoot", CrushMechanic). Reported live: "Same
## for walnuts (crack open)."
##
## Unlike a worm/caterpillar/mushroom, a fallen walnut is a plain
## DroppedItem with no per-chunk sim of its own (see docs/concept/
## soil_fauna.md's own investigation: "There is no standing/growing
## walnut marker distinct from the dropped item"). Detection here scans
## DroppedItem.GROUP_NAME directly, filtered to real walnut item stacks,
## matched by exact tile -- the same tile-exact-match crush_caterpillars_
## near already uses for a real Node2D rather than per-cell sim state.
## Cracking one destroys it outright, the same "gone, not transformed
## into a different item" outcome a crushed worm/caterpillar already
## gets -- nothing in this project models a separate cracked-kernel item.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const DroppedItem = preload("res://src/rendering/dropped_item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const CrushMechanic = preload("res://src/world/crush_mechanic.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _item_catalog := ItemCatalog.new()


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	add_child(entities_parent)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _drop(item_id: String, position: Vector2) -> DroppedItem:
	var item := DroppedItem.new()
	item.item_stack = ItemStack.new(_item_catalog.make(item_id), 1)
	item.position = position
	entities_parent.add_child(item)
	return item


func test_crush_walnut_near_removes_a_walnut_underfoot():
	var walnut := _drop("walnut", Vector2(100.0, 100.0))

	assert_true(
		manager.crush_walnut_near(Vector2(100.0, 100.0), CrushMechanic.CRUSH_MOMENTUM_THRESHOLD_KG_M_S * 10.0)
	)

	assert_true(walnut.is_queued_for_deletion())


func test_crush_walnut_near_does_nothing_below_threshold():
	var walnut := _drop("walnut", Vector2(100.0, 100.0))

	assert_false(manager.crush_walnut_near(Vector2(100.0, 100.0), 0.01))

	assert_false(walnut.is_queued_for_deletion())


## Only a real walnut is cracked -- an ordinary food item standing on the
## exact same tile (e.g. a dropped mushroom or a windfall apple) must be
## left alone.
func test_crush_walnut_near_ignores_a_different_item_on_the_same_tile():
	var apple := _drop("apple", Vector2(100.0, 100.0))

	assert_false(
		manager.crush_walnut_near(Vector2(100.0, 100.0), CrushMechanic.CRUSH_MOMENTUM_THRESHOLD_KG_M_S * 10.0)
	)

	assert_false(apple.is_queued_for_deletion())


## Tile-exact match, the same precision crush_caterpillars_near already
## uses -- a walnut one whole tile away must not be crushed by a step
## here.
func test_crush_walnut_near_ignores_a_walnut_on_a_different_tile():
	var walnut := _drop("walnut", Vector2(100.0 + TerrainRenderer.TILE_SIZE, 100.0))

	assert_false(
		manager.crush_walnut_near(Vector2(100.0, 100.0), CrushMechanic.CRUSH_MOMENTUM_THRESHOLD_KG_M_S * 10.0)
	)

	assert_false(walnut.is_queued_for_deletion())


func test_crush_walnut_near_returns_false_when_nothing_is_there():
	assert_false(
		manager.crush_walnut_near(Vector2(100.0, 100.0), CrushMechanic.CRUSH_MOMENTUM_THRESHOLD_KG_M_S * 10.0)
	)
