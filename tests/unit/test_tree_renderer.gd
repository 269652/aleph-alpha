extends GutTest

const TreeRenderer = preload("res://src/rendering/tree_renderer.gd")
const TreePlacement = preload("res://src/world/tree_placement.gd")
const Chunk = preload("res://src/world/chunk.gd")
const ChoppableTree = preload("res://src/rendering/choppable_tree.gd")
const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")
const ForageScheduler = preload("res://src/gameplay/forage_scheduler.gd")

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


# -- named species (see TreeSpecies) ------------------------------------------
#
# Canopy textures used to be cached per continuously-rounded species_bias
## bucket (5 possible values); they are cached per NAMED species instead, so
## the count is bounded by the roster rather than by how many trees are loaded.

## Bounded by the SPECIES ROSTER, not by the number of trees.
##
## This asserted a literal 3 -- walnut, cherry, apple -- and broke the moment
## the roster grew to six. The bound that actually matters is that a wood of
## two hundred trees does not produce two hundred textures, so it is expressed
## against the roster itself and grows with it.
func test_texture_cache_stays_bounded_to_the_species_roster():
	for i in 200:
		renderer._texture_for(Vector2(i * 37, i * 53))
	assert_lte(
		renderer._texture_cache.size(), TreeSpecies.IDS.size(),
		"a wood should not cache a texture per tree"
	)


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


## The tree BODY's origin is anchored at the trunk's FOOT, not its center
## (see _build_tree_node's anchor comment -- Y-sorting needs this). The
## shadow's offset formula predates that change and still used the OLD
## center-anchored convention (half the tree's total height below origin),
## which put the shadow ~11 world units south of the actual trunk -- nearly
## a tile away, nowhere near the visible trunk it was supposed to ground
## (reported: "trees float"). The shadow must sit right at the foot.
func test_the_drop_shadow_sits_at_the_trunk_foot_not_a_tile_south_of_it():
	var chunk := _make_forest_chunk()
	var spawned := renderer.spawn_trees(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_gt(spawned.size(), 0)
	for tree in spawned:
		var shadow: Sprite2D = tree.get_node("Shadow")
		assert_between(
			shadow.position.y, 0.0, TreeRenderer.TRUNK_COLLISION_DEPTH * 2.0,
			"the shadow should sit at the trunk's foot, not drift toward the tile below it"
		)


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


## Trees must sway harder in stronger live wind (see WindSway.set_wind_strength,
## EarthChunkManager.set_wind_strength) -- forwarded through the SAME shared
## material every spawned tree sprite already uses.
func test_set_wind_strength_forwards_to_the_shared_sway_material():
	var chunk := _make_forest_chunk()
	var spawned := renderer.spawn_trees(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	renderer.set_wind_strength(1.8)
	var checked_any := false
	for tree in spawned:
		for child in tree.get_children():
			if child is Sprite2D and child.name != "Shadow":
				assert_eq(child.material.get_shader_parameter("wind_strength"), 1.8)
				checked_any = true
	assert_true(checked_any, "precondition: the forest chunk spawned at least one tree sprite")


# -- live snow reaching a newly spawned tree ---------------------------------
#
# set_snow_coverage is the SPAWN-path half of canopy snow (see
# EarthChunkManager.set_snow_depth/sync_tree_season for the other half, which
# reaches an ALREADY-standing tree instead): a tree spawned after it is set
# should be built already wearing the live snow depth, the same way a tree
# spawned after set_world_age_seconds is already dressed for the right
# season.

func _position_for_species(species_id: String) -> Vector2:
	var scheduler := ForageScheduler.new()
	for step in 4000:
		var position := Vector2(step * 37, step * 53)
		if TreeSpecies.species_for_bias(scheduler.genome_for(position).species_bias) == species_id:
			return position
	return Vector2.ZERO


func test_set_snow_coverage_reaches_a_freshly_spawned_snow_capable_tree():
	var cherry_position := _position_for_species("cherry")
	var bare := renderer._texture_for(cherry_position)
	renderer.set_snow_coverage(0.8)
	var snowed := renderer._texture_for(cherry_position)
	assert_ne(
		bare.get_image().get_data(), snowed.get_image().get_data(),
		"a freshly spawned cherry should pick up the live snow depth"
	)


func test_texture_cache_still_stays_bounded_with_snow_coverage_set():
	renderer.set_snow_coverage(0.5)
	for i in 200:
		renderer._texture_for(Vector2(i * 37, i * 53))
	assert_lte(
		renderer._texture_cache.size(), TreeSpecies.IDS.size(),
		"snow coverage is one live value, not one bucket per tree"
	)


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


## Tolerance widened 0.001 -> 0.02: at 2x MATURITY_SECONDS a tree has
## already earned a small old-growth head start (see TreeGrowth's own "old
## growth" doc comment) rather than sitting at the exact pre-old-growth
## literal.
func test_a_long_established_tree_spawns_full_grown():
	var tree := renderer.spawn_tree_at(parent, Vector2(64, 64), TreeGrowth.MATURITY_SECONDS * 2.0)
	assert_almost_eq(tree.growth_scale, 1.0, 0.02)


## A half-grown sapling is visibly between the two, which is the whole point
## of having stages.
func test_a_half_grown_tree_is_between_seedling_and_full():
	var tree := renderer.spawn_tree_at(parent, Vector2(96, 96), TreeGrowth.MATURITY_SECONDS * 0.5)
	assert_gt(tree.growth_scale, TreeGrowth.SEEDLING_SCALE)
	assert_lt(tree.growth_scale, 1.0)


## Map-generated forest predates the session, so every tree stands at LEAST
## mature -- never a sapling. No longer pinned to exactly 1.0: bulk-spawned
## trees now draw a real per-tile old-growth age (see
## test_original_forest_trees_have_a_real_age_structure below), so some are
## bigger than simple maturity.
func test_original_forest_trees_spawn_mature():
	var chunk := _make_forest_chunk()
	var spawned := renderer.spawn_trees(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_gt(spawned.size(), 0)
	for tree in spawned:
		assert_gte(tree.growth_scale, 1.0, "an original forest tree should never be a sapling")


## Asked directly: "keep it but make trees another 30% bigger, varying by
## age." A real forest has an age structure -- some trees decades older
## than others -- not one uniform stand where every original tree is
## pixel-identically "mature". Deterministic per tile (see _seeded_age), so
## this is a property of a forest that regenerates identically every time,
## not randomness that would make a reloaded chunk's trees resize
## themselves.
func test_original_forest_trees_have_a_real_age_structure():
	var chunk := _make_forest_chunk()
	var spawned := renderer.spawn_trees(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_gt(spawned.size(), 1, "fixture should spawn more than one tree to show variety")
	var sizes := {}
	for tree in spawned:
		sizes[snappedf(tree.growth_scale, 0.001)] = true
	assert_gt(sizes.size(), 1, "every original forest tree spawned at the exact same size")


## And it has to be a real forest-scale distribution, reaching all the way
## to the old-growth ceiling somewhere -- not just a narrow band just past
## simple maturity.
func test_original_forest_trees_include_some_at_the_old_growth_ceiling():
	var chunk := _make_forest_chunk()
	var spawned := renderer.spawn_trees(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	var reached_ceiling := false
	for tree in spawned:
		if is_equal_approx(tree.growth_scale, 1.0 + TreeGrowth.OLD_GROWTH_BONUS):
			reached_ceiling = true
			break
	assert_true(reached_ceiling, "no original forest tree reached the old-growth ceiling")


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


# -- collision sits at the trunk, not under it ------------------------------
#
# Anchoring the sprite at the trunk's foot (for Y-sorting) moved the node's
# origin without moving the collision box, which stayed centred on that
# origin and sized to the whole canopy. The result: the square BELOW a tree
# was blocked while the trunk itself was walkable.

func _collision_of(tree: Node2D) -> CollisionShape2D:
	for child in tree.get_children():
		if child is CollisionShape2D:
			return child
	return null


func test_collision_is_a_trunk_sized_box_not_a_canopy_sized_one():
	var tree := renderer.spawn_tree_at(parent, Vector2(48, 48))
	var shape: RectangleShape2D = _collision_of(tree).shape
	assert_lt(
		shape.size.x, TreeRenderer.TREE_SIZE.x * 0.5,
		"you should be able to walk under the canopy -- only the trunk is solid"
	)
	assert_gte(
		shape.size.x, ProceduralTreeSprite.trunk_world_width() * 0.8,
		"the solid box must actually cover the trunk"
	)


## The blocked cell is the one the trunk stands in -- the node's own origin.
func test_collision_is_centred_on_the_trunks_foot():
	var tree := renderer.spawn_tree_at(parent, Vector2(48, 48))
	var collision := _collision_of(tree)
	var shape: RectangleShape2D = collision.shape
	assert_almost_eq(collision.position.x, 0.0, 0.01)
	# Centred vertically on the origin (within its own small height), so the
	# tile below the tree is NOT blocked.
	assert_lte(
		absf(collision.position.y), shape.size.y,
		"the solid box should sit at the trunk's foot, not a canopy-height below it"
	)


func test_collision_is_short_so_it_blocks_only_the_trunks_own_tile():
	var tree := renderer.spawn_tree_at(parent, Vector2(48, 48))
	var shape: RectangleShape2D = _collision_of(tree).shape
	assert_lt(shape.size.y, TreeRenderer.TREE_SIZE.y * 0.4)

# NOTE: an attempt to fix "the canopy visually rests on an approaching
# player's head" by deepening TRUNK_COLLISION_DEPTH was tried and reverted
# (see tree_renderer.gd's TRUNK_COLLISION_DEPTH comment) -- it reintroduced
# the tile-below-blocked regression this box was shrunk to fix. The player
# being center-anchored while the tree is foot-anchored means no trunk-depth
# number alone satisfies both constraints; still open, affects stones too.


# -- a forest is not a grid --------------------------------------------------

## Trees stood at exact tile centres, so an original forest read as a lattice:
## every trunk on a perfect grid, which no wood has ever looked like.
##
## Offset within their own tile, deterministically, so a tree is still THE tree
## for that tile -- it just is not standing in the middle of it.
func test_trees_do_not_all_stand_at_tile_centres():
	var chunk := _make_forest_chunk()
	var spawned := renderer.spawn_trees(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	if spawned.size() < 3:
		pass_test("not enough trees rolled in this chunk")
		return
	var centred := 0
	for tree in spawned:
		var from_centre := Vector2(
			fposmod(tree.position.x, float(TILE_SIZE)) - float(TILE_SIZE) * 0.5,
			fposmod(tree.position.y, float(TILE_SIZE)) - float(TILE_SIZE) * 0.5
		)
		if from_centre.length() < 0.01:
			centred += 1
	assert_lt(
		float(centred) / float(spawned.size()), 0.5,
		"most trees are standing dead centre in their tile -- the wood is a grid"
	)


## ...but each stays on its OWN tile, so the tile that has a tree still has it
## and nothing drifts into a neighbour.
func test_a_tree_stays_within_its_own_tile():
	var chunk := _make_forest_chunk()
	var spawned := renderer.spawn_trees(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	for tree in spawned:
		var tile := Vector2i(
			int(floor(tree.position.x / float(TILE_SIZE))),
			int(floor(tree.position.y / float(TILE_SIZE)))
		)
		# The tile it stands on must actually be a tree tile: an offset that
		# pushed a trunk into a neighbouring tile would put a tree where the
		# placement rules say there is none.
		var local := tile - CHUNK_ORIGIN
		assert_true(
			tree_placement.has_tree_at(tile.x, tile.y, chunk.biome[local.y * chunk.width + local.x]),
			"a tree wandered onto a tile that should not have one"
		)


## The same tile always puts its tree in the same place, so a wood does not
## rearrange itself when a chunk reloads.
func test_a_tree_stands_in_the_same_spot_every_time():
	var chunk := _make_forest_chunk()
	var first := renderer.spawn_trees(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	var places: Array[Vector2] = []
	for tree in first:
		places.append(tree.position)
	for tree in first:
		tree.free()
	var second := renderer.spawn_trees(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	for index in second.size():
		assert_eq(second[index].position, places[index])


# -- a building piece occupies its tile against vegetation ---------------------
#
# Reported: a tree with its trunk rooted in a village house's stone floor and
# its canopy drawn over the masonry. Half of that is this file's: chunk
# modifications are loaded from disk BEFORE spawn_trees runs (see
# EarthChunkManager._load_chunk), so without a check here the deterministic
# forest respawns straight into a persisted house on every revisit. The other
# half -- a house stamped over a tree that is already standing -- lives in
# EarthChunkManager.stamp_structure_at_global.


## The first local cell of `chunk` that the placement rules put a tree on, or
## (-1, -1) if this chunk happens to have rolled none.
func _first_tree_cell(chunk: Chunk) -> Vector2i:
	for y in chunk.height:
		for x in chunk.width:
			if tree_placement.has_tree_at(
				CHUNK_ORIGIN.x + x, CHUNK_ORIGIN.y + y, chunk.biome[y * chunk.width + x]
			):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _spawned_on_cell(spawned: Array[Node2D], cell: Vector2i) -> bool:
	for tree in spawned:
		var tile := Vector2i(
			int(floor(tree.position.x / float(TILE_SIZE))),
			int(floor(tree.position.y / float(TILE_SIZE)))
		)
		if tile == CHUNK_ORIGIN + cell:
			return true
	return false


func test_no_tree_spawns_on_a_cell_a_building_piece_occupies():
	var chunk := _make_forest_chunk()
	var cell := _first_tree_cell(chunk)
	assert_ne(cell, Vector2i(-1, -1), "this chunk rolled no trees at all")
	var without_house := _expected_tree_count(chunk)

	chunk.modifications[cell] = "stone_floor"
	var spawned := renderer.spawn_trees(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)

	assert_false(
		_spawned_on_cell(spawned, cell),
		"a tree spawned on a cell a building piece already stands on"
	)
	assert_eq(spawned.size(), without_house - 1)


## Reported directly after playtesting: rivers were "still treated like
## normal biome... grass and trees grow in rivers" -- a river never
## changes chunk.biome itself (docs/concept/rivers.md's Rendering
## section), so the forest-cell check alone can't see it; chunk.is_river
## is the new field that lets this be excluded without spawn_trees needing
## its own live generator reference.
func test_no_tree_spawns_on_a_river_cell():
	var chunk := _make_forest_chunk()
	var cell := _first_tree_cell(chunk)
	assert_ne(cell, Vector2i(-1, -1), "this chunk rolled no trees at all")
	var without_river := _expected_tree_count(chunk)

	chunk.is_river = PackedByteArray()
	chunk.is_river.resize(chunk.width * chunk.height)
	chunk.is_river[cell.y * chunk.width + cell.x] = 1
	var spawned := renderer.spawn_trees(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)

	assert_false(_spawned_on_cell(spawned, cell), "a tree spawned on a real river cell")
	assert_eq(spawned.size(), without_river - 1)


## The rule is narrow on purpose: an earth path or a campfire is a chunk
## modification too, and neither of those uproots a tree. Only a real
## BuildingPiece occupies its tile -- the same distinction
## EarthChunkManager._piece_grid_for already draws.
func test_a_non_piece_modification_does_not_stop_a_tree_spawning():
	var chunk := _make_forest_chunk()
	var cell := _first_tree_cell(chunk)
	assert_ne(cell, Vector2i(-1, -1), "this chunk rolled no trees at all")
	var without_house := _expected_tree_count(chunk)

	chunk.modifications[cell] = "earth"
	var spawned := renderer.spawn_trees(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)

	assert_true(
		_spawned_on_cell(spawned, cell),
		"an earth tile is not a building -- it should not have uprooted the tree"
	)
	assert_eq(spawned.size(), without_house)


## ## The canopy is on the clock, not on the simulation
##
## (see docs/concept/seasons.md, "The canopy is on the clock, not on the
## simulation"). `season` used to be an empty String written from exactly one
## place -- EarthChunkManager._sync_tree_season, reachable only from
## step_fruiting, reachable only from World._process behind
## _owns_ecosystem_simulation() and a ~1s accumulator. A tree built before
## that ever fired had no season at all and fell through
## IllustratedTree._FALLBACK_SEASON to summer leaf: a fresh world's first
## chunks flashed green in the snow, and a joined multiplayer client (which
## owns no simulation, so the tick never runs) stayed summer-green all year.
##
## So the renderer holds the CLOCK, and the season is derived from it. There
## is no unset state left to fall back from.

const SeasonCycle = preload("res://src/world/season_cycle.gd")
const SeasonTransition = preload("res://src/world/season_transition.gd")
const TreePhenology = preload("res://src/world/tree_phenology.gd")

var _cycle := SeasonCycle.new()


func _clock_at(season: String) -> float:
	return _cycle.seconds_until_season(0.0, season)


func test_a_renderer_nobody_has_told_anything_still_has_a_real_season():
	var state: Dictionary = renderer.canopy_state()

	assert_true(
		SeasonCycle.SEASONS.has(state["season"]),
		"a freshly built renderer had no season at all: %s" % [state]
	)


## Not merely non-empty -- it must be the clock's own zero, read the way a
## CANOPY reads it (TreePhenology, not the calendar label: the first instant
## of spring is still bare wood). Silently reading as high summer is what let
## the wiring bug pass for a healthy forest.
func test_an_untouched_renderer_reads_the_clocks_own_zero_and_not_summer():
	assert_eq(
		renderer.canopy_state()["season"],
		TreePhenology.canopy_state_at(_cycle.year_fraction(0.0))["from"]
	)
	assert_ne(
		renderer.canopy_state()["season"],
		"summer",
		"an unset season must not look like a healthy summer tree"
	)


## ## The canopy walks its OWN schedule, off the same clock
##
## The reported bug (see docs/concept/seasons.md, "Winter stays bare: the
## canopy has its own phenology"): a world that opened in winter showed pink
## blossom and green crowns in the snow. Nothing was mis-mapped -- the last
## third of every season already reports itself as turning into the next one,
## which a LAWN expresses as an imperceptible colour lerp and a CANOPY
## expresses as a fifth of a much denser, much pinker picture painted over
## bare branches.
##
## So the canopy is on `TreePhenology`'s schedule and the ground stays on
## `SeasonTransition`'s. This is the table the player actually sees, asserted
## where the game actually reads it: winter bare, blossom a brief early-spring
## event, leaf from late spring through summer, turning in autumn.
const _SEASON_SECONDS := SeasonCycle.SECONDS_PER_YEAR / 4.0


func _canopy_at(season: String, through: float) -> String:
	renderer.set_world_age_seconds(_clock_at(season) + _SEASON_SECONDS * through)
	return renderer.canopy_state()["season"]


func test_the_canopy_a_tree_wears_follows_the_year():
	assert_eq(_canopy_at("winter", 0.5), "winter", "deep winter should be bare")
	assert_eq(_canopy_at("spring", 0.09), "spring", "early spring should be in blossom")
	assert_eq(_canopy_at("spring", 0.6), "summer", "late spring should be in leaf")
	assert_eq(_canopy_at("summer", 0.5), "summer")
	assert_eq(_canopy_at("autumn", 0.5), "autumn")


## The whole of winter, not just its middle. Winter's last third is exactly
## where blossom used to bleed back in, because that is when the GROUND starts
## turning toward spring.
func test_winter_is_bare_end_to_end():
	for step in 40:
		var through := float(step) / 40.0

		assert_eq(
			_canopy_at("winter", through),
			"winter",
			"blossom bled back into winter, %d%% through it" % int(through * 100.0)
		)


## ...and it is bare in the strong sense: not part-way into a blend toward
## blossom either, which would already read as pink on a canopy.
func test_late_winter_is_not_even_part_turned_though_the_ground_is():
	var late_winter := _clock_at("winter") + _SEASON_SECONDS * 0.9
	var ground := SeasonTransition.state_at(_cycle.year_fraction(late_winter))
	assert_eq(ground["to"], "spring", "precondition: the GROUND is turning by now")
	assert_gt(float(ground["progress"]), 0.0, "precondition: and visibly so")

	renderer.set_world_age_seconds(late_winter)

	assert_almost_eq(float(renderer.canopy_state()["turn_progress"]), 0.0, 0.0001)


## The renderer is the one place the canopy schedule is read (the trees
## already loaded are dressed from this same call -- see
## EarthChunkManager.sync_tree_season), so it has to BE the schedule rather
## than an approximation of it that can drift.
func test_the_renderer_reports_exactly_what_the_phenology_says():
	for step in 48:
		var moment := SeasonCycle.SECONDS_PER_YEAR * float(step) / 48.0
		renderer.set_world_age_seconds(moment)
		var state: Dictionary = renderer.canopy_state()
		var expected := TreePhenology.canopy_state_at(_cycle.year_fraction(moment))

		assert_eq(state["season"], expected["from"], "stage disagreed at step %d" % step)
		assert_eq(state["turning_into"], expected["to"], "target disagreed at step %d" % step)
		assert_almost_eq(
			float(state["turn_progress"]), float(expected["progress"]), 0.001
		)


## The behavioural end of it: the picture a tree is actually built with.
## A tree spawned before anyone sets a clock must not be the same picture as
## a tree spawned in high summer -- that identity IS the reported bug.
func test_a_tree_built_before_anyone_sets_a_clock_is_not_drawn_in_summer():
	var untouched := renderer.spawn_tree_at(parent, Vector2(48.0, 48.0))
	var untouched_texture: Texture2D = _canopy_texture_of(untouched)

	renderer.set_world_age_seconds(_clock_at("summer"))
	var summer := renderer.spawn_tree_at(parent, Vector2(48.0, 48.0))

	assert_ne(
		untouched_texture,
		_canopy_texture_of(summer),
		"a tree built with no clock set was drawn as a summer tree"
	)


func test_a_winter_tree_and_a_summer_tree_are_different_pictures():
	renderer.set_world_age_seconds(_clock_at("winter"))
	var winter_texture: Texture2D = _canopy_texture_of(
		renderer.spawn_tree_at(parent, Vector2(48.0, 48.0))
	)

	renderer.set_world_age_seconds(_clock_at("summer"))

	assert_ne(
		winter_texture,
		_canopy_texture_of(renderer.spawn_tree_at(parent, Vector2(48.0, 48.0))),
		"the same canopy stood through winter and summer alike"
	)


## The CANOPY sprite, not the contact shadow -- _build_tree_node adds the
## shadow first (sibling order is draw order), and a shadow is the same
## picture in every season, so taking the first Sprite2D child would compare
## two shadows and pass no matter what the canopy did.
func _canopy_texture_of(tree: ChoppableTree) -> Texture2D:
	return tree._canopy_sprite.texture
