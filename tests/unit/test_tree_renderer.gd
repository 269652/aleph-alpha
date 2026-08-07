extends GutTest

const TreeRenderer = preload("res://src/rendering/tree_renderer.gd")
const TreePlacement = preload("res://src/world/tree_placement.gd")
const Chunk = preload("res://src/world/chunk.gd")
const ChoppableTree = preload("res://src/rendering/choppable_tree.gd")

var renderer: TreeRenderer
var parent: Node2D
var tree_placement := TreePlacement.new()

const TILE_SIZE := 16
const CHUNK_ORIGIN := Vector2i(64, 128)


func before_each():
	renderer = TreeRenderer.new()
	parent = Node2D.new()


func after_each():
	parent.free()


func _make_forest_chunk() -> Chunk:
	var chunk := Chunk.new()
	chunk.width = 4
	chunk.height = 4
	chunk.elevation = PackedFloat32Array()
	chunk.elevation.resize(16)
	chunk.biome = PackedStringArray()
	for i in 16:
		chunk.biome.append("forest")
	return chunk


func _expected_tree_count(chunk: Chunk) -> int:
	var count := 0
	for y in chunk.height:
		for x in chunk.width:
			var global_x := CHUNK_ORIGIN.x + x
			var global_y := CHUNK_ORIGIN.y + y
			if tree_placement.has_tree_at(global_x, global_y, chunk.biome[y * chunk.width + x]):
				count += 1
	return count


func test_spawns_one_node_per_tree_tile():
	var chunk := _make_forest_chunk()
	var spawned := renderer.spawn_trees(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_eq(spawned.size(), _expected_tree_count(chunk))
	assert_eq(parent.get_child_count(), spawned.size())


func test_no_trees_spawn_on_a_non_forest_chunk():
	var chunk := Chunk.new()
	chunk.width = 4
	chunk.height = 4
	chunk.elevation = PackedFloat32Array()
	chunk.elevation.resize(16)
	chunk.biome = PackedStringArray()
	for i in 16:
		chunk.biome.append("ocean")

	var spawned := renderer.spawn_trees(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_eq(spawned.size(), 0)


func test_spawned_trees_are_positioned_at_their_global_tile():
	var chunk := _make_forest_chunk()
	var spawned := renderer.spawn_trees(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_gt(spawned.size(), 0)
	for tree in spawned:
		var tile_x := int(tree.position.x / TILE_SIZE)
		var tile_y := int(tree.position.y / TILE_SIZE)
		assert_between(tile_x, CHUNK_ORIGIN.x, CHUNK_ORIGIN.x + 3)
		assert_between(tile_y, CHUNK_ORIGIN.y, CHUNK_ORIGIN.y + 3)


func test_spawned_trees_have_a_collision_shape():
	var chunk := _make_forest_chunk()
	var spawned := renderer.spawn_trees(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_gt(spawned.size(), 0)
	for tree in spawned:
		assert_true(tree is StaticBody2D)
		var has_collision_shape := false
		for child in tree.get_children():
			if child is CollisionShape2D:
				has_collision_shape = true
		assert_true(has_collision_shape)


func test_spawned_trees_are_choppable():
	# Group membership (ChoppableTree.GROUP_NAME) is assigned in _ready(),
	# which -- as with the rest of this file -- doesn't fire here since
	# `parent` is never added to a live scene tree; that path is covered by
	# test_choppable_tree.gd instead. This just proves TreeRenderer spawns
	# the right node type.
	var chunk := _make_forest_chunk()
	var spawned := renderer.spawn_trees(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_gt(spawned.size(), 0)
	for tree in spawned:
		assert_true(tree is ChoppableTree)


func test_spawn_tree_at_places_a_single_choppable_tree_at_the_given_position():
	var tree := renderer.spawn_tree_at(parent, Vector2(500, 500))
	assert_true(tree is ChoppableTree)
	assert_eq(tree.position, Vector2(500, 500))
	assert_eq(parent.get_child_count(), 1)


## Trees sway in the wind: every spawned tree's sprite carries the shared
## WindSway shader material (see wind_sway.gd), one material instance shared
## across all trees rather than one per node.
func test_spawned_tree_sprites_share_the_wind_sway_material():
	var chunk := _make_forest_chunk()
	var spawned := renderer.spawn_trees(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_gt(spawned.size(), 0)
	var seen_material: Material = null
	for tree in spawned:
		for child in tree.get_children():
			if child is Sprite2D:
				assert_true(child.material is ShaderMaterial, "tree sprite should sway via the wind shader")
				if seen_material == null:
					seen_material = child.material
				assert_eq(child.material, seen_material, "all trees should share one material instance")
