extends GutTest

const TreeRenderer = preload("res://src/rendering/tree_renderer.gd")
const TreePlacement = preload("res://src/world/tree_placement.gd")
const Chunk = preload("res://src/world/chunk.gd")
const ChoppableTree = preload("res://src/rendering/choppable_tree.gd")
const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")

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


## Every tree casts a soft contact shadow (see drop_shadow.gd) so it sits ON
## the ground instead of floating over it.
func test_spawned_trees_have_a_drop_shadow():
	var chunk := _make_forest_chunk()
	var spawned := renderer.spawn_trees(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_gt(spawned.size(), 0)
	for tree in spawned:
		var shadow := tree.get_node_or_null("Shadow")
		assert_not_null(shadow, "tree should have a Shadow child")
		assert_true(shadow is Sprite2D and shadow.show_behind_parent)


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
			# The contact shadow is deliberately NOT wind-swayed -- a shadow
			# stays planted on the ground while the canopy above it moves.
			if child is Sprite2D and child.name != "Shadow":
				assert_true(child.material is ShaderMaterial, "tree sprite should sway via the wind shader")
				if seen_material == null:
					seen_material = child.material
				assert_eq(child.material, seen_material, "all trees should share one material instance")


# -- art resolution (docs/concept/art_resolution.md phase 2) -----------------
#
# Trees are authored at ArtResolution.DETAIL_MULTIPLIER times their world
# size and drawn scaled back down, so a tree gains real pixel detail without
# growing in the world. Phase 1's mistake on the ground plane -- raising art
# size and world footprint together -- is exactly what these pin against.

## The world size follows the sprite's declared footprint rather than a
## literal, so growing the tree (see WORLD_SIZE) does not need this edited.
func test_tree_world_size_follows_the_sprites_declared_footprint():
	assert_eq(TreeRenderer.TREE_SIZE, Vector2(ProceduralTreeSprite.WORLD_SIZE))


func test_tree_art_is_authored_at_the_shared_detail_multiplier():
	assert_eq(ProceduralTreeSprite.SIZE, ArtResolution.art_size(ProceduralTreeSprite.WORLD_SIZE))


## The sprite must be scaled back down, or the oversized art would render a
## tree 4x its world footprint.
func test_tree_sprite_is_scaled_back_to_its_world_footprint():
	var chunk := _make_forest_chunk()
	var spawned := renderer.spawn_trees(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_gt(spawned.size(), 0, "fixture should spawn at least one tree")
	# The canopy sprite, not the drop shadow -- the shadow is added first and
	# is also a Sprite2D, so take the one TreeRenderer bound as the canopy.
	var sprite: Sprite2D = spawned[0]._canopy_sprite
	assert_not_null(sprite, "a tree should have a bound canopy sprite")
	assert_almost_eq(sprite.scale.x, ArtResolution.SPRITE_SCALE, 0.0001)
	assert_almost_eq(sprite.scale.y, ArtResolution.SPRITE_SCALE, 0.0001)
	# The drawn size is the art size times the scale -- i.e. the world size.
	var drawn := Vector2(sprite.texture.get_size()) * sprite.scale
	assert_almost_eq(drawn.x, TreeRenderer.TREE_SIZE.x, 0.01)
	assert_almost_eq(drawn.y, TreeRenderer.TREE_SIZE.y, 0.01)


# -- saplings actually start small ------------------------------------------
#
# TreeGrowth was plumbed in but every spawn path defaulted to "mature", so
# a freshly spread sapling appeared as a full-grown tree and the growth
# stages were never seen.

const TreeGrowth = preload("res://src/gameplay/tree_growth.gd")


func test_a_freshly_planted_tree_spawns_as_a_seedling():
	var tree := renderer.spawn_tree_at(parent, Vector2(32, 32), 0.0)
	assert_almost_eq(tree.growth_scale, TreeGrowth.SEEDLING_SCALE, 0.001)


func test_a_long_established_tree_spawns_full_grown():
	var tree := renderer.spawn_tree_at(parent, Vector2(64, 64), TreeGrowth.MATURITY_SECONDS * 2.0)
	assert_almost_eq(tree.growth_scale, 1.0, 0.001)


## A half-grown sapling is visibly between the two, which is the whole point
## of having stages.
func test_a_half_grown_tree_is_between_seedling_and_full():
	var tree := renderer.spawn_tree_at(parent, Vector2(96, 96), TreeGrowth.MATURITY_SECONDS * 0.5)
	assert_gt(tree.growth_scale, TreeGrowth.SEEDLING_SCALE)
	assert_lt(tree.growth_scale, 1.0)


## Map-generated forest predates the session, so it stands mature.
func test_original_forest_trees_spawn_mature():
	var chunk := _make_forest_chunk()
	var spawned := renderer.spawn_trees(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_gt(spawned.size(), 0)
	assert_almost_eq(spawned[0].growth_scale, 1.0, 0.001)


# -- draw order: a tree occludes whoever walks behind it --------------------
#
# Trees drew as flat cutouts, so a player walking behind one appeared on top
# of its trunk. Correct top-down draw order sorts by Y, which needs two
# things: the containers Y-sorted, and each tree anchored at its BASE rather
# than its middle, or a tall canopy sorts as though it stood where its
# crown is.

func test_a_tree_anchors_at_its_base_not_its_middle():
	var tree := renderer.spawn_tree_at(parent, Vector2(48, 48))
	var sprite: Sprite2D = tree._canopy_sprite
	assert_lt(
		sprite.offset.y, 0.0,
		"the canopy should be drawn ABOVE the node's origin, so the origin sits at the trunk's foot"
	)


## Two trees at different depths must sort by their Y, so the nearer one
## draws in front.
func test_trees_sort_by_depth():
	var near := renderer.spawn_tree_at(parent, Vector2(0, 100))
	var far := renderer.spawn_tree_at(parent, Vector2(0, 20))
	assert_gt(near.position.y, far.position.y)
	assert_true(parent.y_sort_enabled, "the entity container must Y-sort its trees")
