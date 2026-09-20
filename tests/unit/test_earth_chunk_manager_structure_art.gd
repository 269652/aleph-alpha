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
const VillageFarm = preload("res://src/gameplay/village_farm.gd")
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


## Every overlay sprite standing on _berlin_tile. One cell can carry more
## than one: a SHARED LINE between two neighbouring fields is both their
## rails on the same tile (VillageFarm.SHARED_FENCE_TILE_IDS).
func _structure_art_sprites_at_berlin_tile() -> Array:
	var local_cell := manager._local_coord(_berlin_tile.x, _berlin_tile.y)
	return manager._structure_art_sprites.get(_berlin_chunk, {}).get(local_cell, [])


## The first of them, or null -- for tests that inspect one sprite.
func _structure_art_sprite_at_berlin_tile() -> Sprite2D:
	var sprites := _structure_art_sprites_at_berlin_tile()
	return null if sprites.is_empty() else sprites[0]


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


## The overlay's own texture width matches the structure's drawn footprint
## (see IllustratedStructureSprite.footprint_texture) -- not left at the
## sheet's own raw cell size, and not one tile either: a farm drawn one tile
## wide was shorter than its own farmer (reported live, "there's a weird
## shrunk farmhouse"), so it is drawn at the footprint its catalog twin
## claims. The WIRING pin; the size itself is measured against the real art
## over in test_illustrated_structure_sprite.gd.
func test_the_overlay_sprites_texture_width_matches_its_drawn_footprint():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "farm")
	var sprite := _structure_art_sprite_at_berlin_tile()
	assert_eq(
		sprite.texture.get_width(),
		TerrainRenderer.TILE_SIZE * IllustratedStructureSprite.drawn_width_tiles("farm")
	)
	assert_gt(
		IllustratedStructureSprite.drawn_width_tiles("farm"), 1,
		"the premise: a farm is drawn wider than the single tile it stands on"
	)


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
# Asked for directly, with two sides arrowed in a screenshot: "move the
# fences to the inner edge of the enclosure and treat the rest of the tile
# as street". The WIRING pin for IllustratedStructureSprite.footprint_offset
# -- an offset nothing applies moves no fence anywhere. Where that offset
# should land is measured against the real art over in
# test_illustrated_structure_sprite.gd; what is checked here is only that
# the overlay really carries it. See docs/concept/village_farms.md, "The
# rail stands on the inner edge".


## Where the overlay would stand with no offset at all: horizontally centred
## on the tile, its own bottom edge on the tile's bottom edge.
func _unoffset_position_for(texture_height: int) -> Vector2:
	var tile_center := (Vector2(_berlin_tile) + Vector2(0.5, 0.5)) * TerrainRenderer.TILE_SIZE
	var tile_bottom := tile_center.y + TerrainRenderer.TILE_SIZE * 0.5
	return Vector2(tile_center.x, tile_bottom - float(texture_height) * 0.5)


func test_every_rails_overlay_really_carries_its_own_inner_edge_offset():
	var art := IllustratedStructureSprite.new()
	for facing in VillageFarm.FENCE_TILE_IDS:
		var subject: String = VillageFarm.fence_tile_for(facing)
		if VillageFarm.is_fence_corner_tile(subject):
			continue  # a corner draws nothing, so it has no overlay to offset
		manager.build_at_global(_berlin_tile.x, _berlin_tile.y, subject)
		var sprite := _structure_art_sprite_at_berlin_tile()
		var offset: Vector2 = art.footprint_offset(subject, TerrainRenderer.TILE_SIZE)
		assert_ne(offset, Vector2.ZERO, "%s should not be drawn where a building would be" % subject)
		assert_eq(
			sprite.position, _unoffset_position_for(sprite.texture.get_height()) + offset,
			"%s's overlay is drawn in the middle of its tile, not on its inner edge" % subject
		)
		manager.destroy_at_global(_berlin_tile.x, _berlin_tile.y)


## And the buildings that really do stand on their whole tile are untouched.
func test_a_farms_overlay_still_stands_in_the_middle_of_its_tile():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "farm")
	var sprite := _structure_art_sprite_at_berlin_tile()
	assert_eq(sprite.position, _unoffset_position_for(sprite.texture.get_height()))


# -- a farm fence's side walls stand on the frame's INNER edge -------------
#
# This section used to pin the opposite direction, from an earlier report
# ("the side walls of the fence should be moved outwards and corner pieces
# added so it doesn't look that broken"). The later ask, with the west and
# south sides arrowed toward the beds, reverses it: "move the fences to the
# inner edge of the enclosure and treat the rest of the tile as street".
# What survives from the first report is everything except the sign -- the
# two side walls still move by the same distance in opposite directions, a
# corner post still lines up exactly with the wall it caps, and a north or
# south rail still stands on its own tile centre horizontally.


func _art_x_for(tile_id: String) -> float:
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, tile_id)
	var sprite := _structure_art_sprite_at_berlin_tile()
	assert_not_null(sprite, "%s should have real art" % tile_id)
	return sprite.position.x


func test_a_north_or_south_rail_stands_on_its_own_tile_centre():
	var centre := (float(_berlin_tile.x) + 0.5) * TerrainRenderer.TILE_SIZE
	assert_almost_eq(_art_x_for(VillageFarm.fence_tile_for("north")), centre, 0.001)
	assert_almost_eq(_art_x_for(VillageFarm.fence_tile_for("south")), centre, 0.001)


func test_a_west_rail_stands_on_its_own_east_edge_where_its_beds_are():
	var centre := (float(_berlin_tile.x) + 0.5) * TerrainRenderer.TILE_SIZE
	assert_gt(
		_art_x_for(VillageFarm.fence_tile_for("west")), centre,
		"a west rail's beds lie east, so its rails belong on its east edge"
	)


func test_an_east_rail_stands_on_its_own_west_edge_where_its_beds_are():
	var centre := (float(_berlin_tile.x) + 0.5) * TerrainRenderer.TILE_SIZE
	assert_lt(
		_art_x_for(VillageFarm.fence_tile_for("east")), centre,
		"an east rail's beds lie west, so its rails belong on its west edge"
	)


## And the two side walls move by the SAME distance in opposite directions
## -- a frame with one wall further in than the other is the lopsided look
## the first report was about, and reversing the direction does not excuse
## it. Not exact: each wall is placed on its own art's measured centre line
## (IllustratedStructureSprite.footprint_offset) and the sheet's two
## top-view cells are not drawn pixel-identically, so they differ by well
## under one screen pixel rather than by nothing at all.
func test_the_two_side_walls_move_in_by_the_same_distance():
	var centre := (float(_berlin_tile.x) + 0.5) * TerrainRenderer.TILE_SIZE
	var west := _art_x_for(VillageFarm.fence_tile_for("west")) - centre
	var east := centre - _art_x_for(VillageFarm.fence_tile_for("east"))
	assert_almost_eq(west, east, 0.5)
	# How far in that is, DERIVED rather than pinned at a number: a wall sits
	# flush against its own inner edge, so its centre line stands half the
	# rail's own thickness back from that edge -- half a tile in, less half a
	# rail. That used to be "half a tile" because the rail was thin enough
	# for the difference to vanish into the tolerance; a rail scaled by its
	# post spacing (docs/concept/village_farms.md, "Consecutive rails SHARE a
	# post") is about a quarter thicker, and the distance shrinks with it.
	# Pinning 8.0 would pin the old thickness, not the rule.
	var thickness := _drawn_rail_thickness(VillageFarm.fence_tile_for("west"))
	assert_gt(thickness, 0.0, "precondition: the west rail's wood was measured")
	assert_almost_eq(
		west, TerrainRenderer.TILE_SIZE * 0.5 - thickness * 0.5, 0.5,
		"half a tile in, less half a rail"
	)


## How thick a side rail's wood really draws, across the run it travels --
## the only number the distance above depends on, measured off the real
## texture so it follows the art instead of restating it.
func _drawn_rail_thickness(subject: String) -> float:
	const IllustratedStructureSprite = preload(
		"res://src/rendering/illustrated_structure_sprite.gd"
	)
	var texture := IllustratedStructureSprite.new().footprint_texture(
		subject, TerrainRenderer.TILE_SIZE
	)
	if texture == null:
		return 0.0
	var image := texture.get_image()
	var first := -1
	var last := -1
	for x in range(image.get_width()):
		for y in range(image.get_height()):
			if image.get_pixel(x, y).a > 0.5:
				if first < 0:
					first = x
				last = x
				break
	return 0.0 if first < 0 else float(last - first + 1)


## A corner raises NO post at all now -- asked for directly with two
## enclosures in shot: *"also the corner post can be removed"*. Each of the
## two runs meeting there already carries a post at its own end
## (tools/probe_fence_posts.gd measured them 12.5px apart inside a 16px
## tile), so the corner's own was a third one beside them.
##
## This used to assert that a corner post lined up with the side wall it
## caps, which is the right question to ask of a post that exists. The
## stronger statement is that none does.
func test_a_corner_raises_no_post_at_all():
	for facing in ["corner_nw", "corner_sw", "corner_ne", "corner_se"]:
		manager.build_at_global(
			_berlin_tile.x, _berlin_tile.y, VillageFarm.fence_tile_for(facing)
		)
		assert_true(
			_structure_art_sprites_at_berlin_tile().is_empty(),
			"%s still draws a post of its own" % facing
		)
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, VillageFarm.fence_tile_for("west"))
	assert_false(
		_structure_art_sprites_at_berlin_tile().is_empty(),
		"precondition: a length of rail is still drawn"
	)


## And a SHARED LINE raises BOTH its fields' rails on the one tile -- asked
## for directly: *"It should be possible to build two rails on a single tile
## so both enclosures are fenced properly."*
func test_a_shared_line_raises_both_its_rails_on_one_tile():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "farm_fence_east_west")
	var sprites := _structure_art_sprites_at_berlin_tile()
	assert_eq(sprites.size(), 2, "a line between two fields is two rails")
	assert_ne(
		sprites[0].position.x, sprites[1].position.x,
		"each is drawn on its OWN inner edge, or they stand on top of each other"
	)

