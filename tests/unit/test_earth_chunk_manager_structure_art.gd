extends GutTest

## EarthChunkManager's real-illustrated-art overlay Sprite2D for the four
## structures IllustratedStructureSprite knows about (farm/sagewerk/
## storage/wooden_fence -- see docs/concept/npc_farm_production.md).
## Purely visual: the underlying ground tile is unchanged (bare earth, the
## same as any other prop-bearing tile -- a tree or mushroom doesn't
## change its own ground tile either). Mirrors test_earth_chunk_manager_
## bees.gd's own dedicated-file shape -- uses `_load_chunk` directly, never
## the slow real `update()`.
##
## This file's own reload test calls `_unload_chunk`, which persists REAL
## modifications to user://chunk_modifications/<chunk>.bin for the exact
## real-world Berlin tile every test here anchors on -- state that is NEVER
## cleared between separate Godot process invocations, and (user:// is keyed
## only by the Godot project name, not by checkout path) is the SAME real
## directory every git worktree on this machine shares (see
## test_builder_marker.gd's own header for the fuller account of this class
## of bug). before_each/after_each below scrub exactly this file's own real
## chunk_coord (never the whole shared directory) before trusting/leaving a
## fresh EarthChunkManager, so an earlier run of this exact file (or a
## concurrent session/worktree) can never leak a stale farm/sagewerk/
## storage/wooden_fence tile into these assertions.

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
	_forget_persisted_berlin_chunk()
	manager._load_chunk(_berlin_chunk)


## Removes REAL persisted modifications/roof_modifications/planted_trees
## for the real-world Berlin chunk this whole file anchors on -- narrow ON
## PURPOSE (never the whole shared user://chunk_modifications directory),
## mirrors test_builder_marker.gd's own identically-named helper exactly.
func _forget_persisted_berlin_chunk() -> void:
	for dir in [
		EarthChunkManager.MODIFICATIONS_DIR,
		EarthChunkManager.ROOF_MODIFICATIONS_DIR,
		EarthChunkManager.PLANTED_TREES_DIR,
	]:
		var path := "%s/%d_%d.bin" % [dir, _berlin_chunk.x, _berlin_chunk.y]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func after_each():
	_forget_persisted_berlin_chunk()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


## Counts real-art overlay sprites via `manager._structure_art_sprites`
## directly, NOT a blanket `entities_parent.get_children()` Sprite2D scan --
## the chunk this test loads generates its own real, unrelated Sprite2D
## content (trees, stones, decomposers, etc.), so a broad scan is not a
## reliable proxy for "how many structure art overlays exist" (a real,
## found-in-practice test-fragility, not a structure-art bug: a broad scan
## passed against an emptier Berlin chunk earlier in this project's history
## and started overcounting once more incidental world content generated
## there).
func _structure_art_sprite_count() -> int:
	var total := 0
	for by_cell in manager._structure_art_sprites.values():
		total += by_cell.size()
	return total


## The one real overlay sprite for _berlin_tile itself, or null -- for
## tests that need to inspect the sprite, not just count it.
func _structure_art_sprite_at_berlin_tile() -> Sprite2D:
	var local_cell := manager._local_coord(_berlin_tile.x, _berlin_tile.y)
	return manager._structure_art_sprites.get(_berlin_chunk, {}).get(local_cell)


func test_placing_a_farm_spawns_a_real_art_overlay_sprite():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "farm")
	assert_eq(_structure_art_sprite_count(), 1)


func test_placing_a_sagewerk_spawns_a_real_art_overlay_sprite():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "sagewerk")
	assert_eq(_structure_art_sprite_count(), 1)


func test_placing_storage_spawns_a_real_art_overlay_sprite():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "storage")
	assert_eq(_structure_art_sprite_count(), 1)


func test_placing_a_wooden_fence_spawns_a_real_art_overlay_sprite():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "wooden_fence")
	assert_eq(_structure_art_sprite_count(), 1)


## A structure with no real art wired yet (campfire) must NOT get a
## surprise overlay sprite -- it keeps rendering via its existing
## baked-into-the-tile-atlas ProceduralStructureSprite look, unaffected.
func test_placing_a_campfire_spawns_no_art_overlay_sprite():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "campfire")
	assert_eq(_structure_art_sprite_count(), 0)


func test_destroying_a_farm_removes_its_art_overlay_sprite():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "farm")
	manager.destroy_at_global(_berlin_tile.x, _berlin_tile.y)
	assert_eq(_structure_art_sprite_count(), 0)


## Rebuilding the SAME tile with a different real-art structure must not
## leave the old overlay behind alongside the new one.
func test_replacing_a_farm_with_a_different_structure_swaps_the_overlay_not_stacks_it():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "farm")
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "storage")
	assert_eq(_structure_art_sprite_count(), 1)


## The overlay's own texture width matches the tile footprint (see
## IllustratedStructureSprite.footprint_texture) -- not left at the sheet's
## own raw cell size.
func test_the_overlay_sprites_texture_width_matches_the_tile_size():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "farm")
	var sprite := _structure_art_sprite_at_berlin_tile()
	assert_eq(sprite.texture.get_width(), TerrainRenderer.TILE_SIZE)


## Re-loading a chunk that already has a persisted farm tile re-spawns its
## overlay -- "an art overlay is there" survives a chunk unload/reload the
## same way the Sagewerk's own Lumberjack re-staffs on reload.
func test_reloading_a_chunk_with_a_persisted_farm_respawns_its_overlay():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "farm")
	manager._unload_chunk(_berlin_chunk)
	assert_eq(_structure_art_sprite_count(), 0, "unloading should free the overlay")
	manager._load_chunk(_berlin_chunk)
	assert_eq(_structure_art_sprite_count(), 1, "reloading should respawn it")


# -- a rail's art stands on its tile's INNER EDGE --------------------------
#
# Asked for directly, with the two sides arrowed in a screenshot: "move the
# fences to the inner edge of the enclosure and treat the rest of the tile
# as street". The wiring pin for IllustratedStructureSprite.footprint_offset
# -- an offset nothing applies moves no fence anywhere. See
# docs/concept/village_farms.md, "The rail stands on the inner edge".


## Where the overlay would stand with no offset at all: horizontally centred
## on the tile, its own bottom edge on the tile's bottom edge.
func _unoffset_position_for(texture_height: int) -> Vector2:
	var tile_center := (Vector2(_berlin_tile) + Vector2(0.5, 0.5)) * TerrainRenderer.TILE_SIZE
	var tile_bottom := tile_center.y + TerrainRenderer.TILE_SIZE * 0.5
	return Vector2(tile_center.x, tile_bottom - float(texture_height) * 0.5)


func test_a_south_rails_overlay_is_lifted_onto_its_own_north_edge():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "farm_fence_south")
	var sprite := _structure_art_sprite_at_berlin_tile()
	assert_eq(
		sprite.position - _unoffset_position_for(sprite.texture.get_height()),
		Vector2(0, -TerrainRenderer.TILE_SIZE),
		"a south rail drawn in the middle of its tile is a fence a tile away from the bed"
	)


func test_a_west_rails_overlay_is_pushed_onto_its_own_east_edge():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "farm_fence_west")
	var sprite := _structure_art_sprite_at_berlin_tile()
	assert_eq(
		sprite.position - _unoffset_position_for(sprite.texture.get_height()),
		Vector2(TerrainRenderer.TILE_SIZE * 0.5, 0)
	)


## And the buildings that really do stand on their whole tile are untouched.
func test_a_farms_overlay_still_stands_in_the_middle_of_its_tile():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "farm")
	var sprite := _structure_art_sprite_at_berlin_tile()
	assert_eq(sprite.position, _unoffset_position_for(sprite.texture.get_height()))
