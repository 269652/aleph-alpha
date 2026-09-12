extends GutTest

## EarthChunkManager's real-illustrated-art overlay Sprite2D for the four
## structures IllustratedStructureSprite knows about (farm/sagewerk/
## storage/wooden_fence -- see docs/concept/npc_farm_production.md).
## Purely visual: the underlying ground tile is unchanged (bare earth, the
## same as any other prop-bearing tile -- a tree or mushroom doesn't
## change its own ground tile either). Mirrors test_earth_chunk_manager_
## bees.gd's own dedicated-file shape -- uses `_load_chunk` directly, never
## the slow real `update()`.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const IllustratedStructureSprite = preload("res://src/rendering/illustrated_structure_sprite.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _berlin_tile: Vector2i
var _berlin_chunk: Vector2i


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	add_child(entities_parent)
	var geo_coordinates := GeoCoordinates.new()
	_berlin_tile = Vector2i(
		geo_coordinates.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo_coordinates.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	_berlin_chunk = Vector2i(
		floori(float(_berlin_tile.x) / EarthChunkManager.CHUNK_SIZE),
		floori(float(_berlin_tile.y) / EarthChunkManager.CHUNK_SIZE)
	)
	manager._load_chunk(_berlin_chunk)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _sprites_in_entities_parent() -> Array:
	var found: Array = []
	for child in entities_parent.get_children():
		if child is Sprite2D:
			found.append(child)
	return found


func test_placing_a_farm_spawns_a_real_art_overlay_sprite():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "farm")
	assert_eq(_sprites_in_entities_parent().size(), 1)


func test_placing_a_sagewerk_spawns_a_real_art_overlay_sprite():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "sagewerk")
	assert_eq(_sprites_in_entities_parent().size(), 1)


func test_placing_storage_spawns_a_real_art_overlay_sprite():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "storage")
	assert_eq(_sprites_in_entities_parent().size(), 1)


func test_placing_a_wooden_fence_spawns_a_real_art_overlay_sprite():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "wooden_fence")
	assert_eq(_sprites_in_entities_parent().size(), 1)


## A structure with no real art wired yet (campfire) must NOT get a
## surprise overlay sprite -- it keeps rendering via its existing
## baked-into-the-tile-atlas ProceduralStructureSprite look, unaffected.
func test_placing_a_campfire_spawns_no_art_overlay_sprite():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "campfire")
	assert_eq(_sprites_in_entities_parent().size(), 0)


func test_destroying_a_farm_removes_its_art_overlay_sprite():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "farm")
	manager.destroy_at_global(_berlin_tile.x, _berlin_tile.y)
	assert_eq(_sprites_in_entities_parent().size(), 0)


## Rebuilding the SAME tile with a different real-art structure must not
## leave the old overlay behind alongside the new one.
func test_replacing_a_farm_with_a_different_structure_swaps_the_overlay_not_stacks_it():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "farm")
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "storage")
	assert_eq(_sprites_in_entities_parent().size(), 1)


## The overlay's own texture width matches the tile footprint (see
## IllustratedStructureSprite.footprint_texture) -- not left at the sheet's
## own raw cell size.
func test_the_overlay_sprites_texture_width_matches_the_tile_size():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "farm")
	var sprite: Sprite2D = _sprites_in_entities_parent()[0]
	assert_eq(sprite.texture.get_width(), TerrainRenderer.TILE_SIZE)


## Re-loading a chunk that already has a persisted farm tile re-spawns its
## overlay -- "an art overlay is there" survives a chunk unload/reload the
## same way the Sagewerk's own Lumberjack re-staffs on reload.
func test_reloading_a_chunk_with_a_persisted_farm_respawns_its_overlay():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "farm")
	manager._unload_chunk(_berlin_chunk)
	assert_eq(_sprites_in_entities_parent().size(), 0, "unloading should free the overlay")
	manager._load_chunk(_berlin_chunk)
	assert_eq(_sprites_in_entities_parent().size(), 1, "reloading should respawn it")
