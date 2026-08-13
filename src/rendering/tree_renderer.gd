extends RefCounted

const TreePlacement = preload("res://src/world/tree_placement.gd")
const Chunk = preload("res://src/world/chunk.gd")
const ChoppableTree = preload("res://src/rendering/choppable_tree.gd")
const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const TreeGenome = preload("res://src/gameplay/tree_genome.gd")
const WindSway = preload("res://src/rendering/wind_sway.gd")
const DropShadow = preload("res://src/rendering/drop_shadow.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const TreeGrowth = preload("res://src/gameplay/tree_growth.gd")

## A tree's WORLD footprint (see ProceduralTreeSprite.WORLD_SIZE) -- derived
## from the art size through ArtResolution rather than equal to it, since
## the art is authored DETAIL_MULTIPLIER times oversized and drawn scaled
## back down (see docs/concept/art_resolution.md). Shadow and collision size
## off this, so they stay matched to the tree's actual world presence.
const TREE_SIZE := Vector2(ProceduralTreeSprite.WORLD_SIZE)
## How much smaller than the sprite the actual collision box is (a little
## forgiving, not a hard rectangle edge).
const COLLISION_SCALE := 0.6

## How many distinct species_bias buckets get their own generated texture.
## Bounded and cached (see _texture_for) rather than one unique texture per
## tree -- thousands of trees can be loaded at once, so per-instance pixel
## generation would be wasteful; a genome-tinted canopy only needs a handful
## of visibly distinct looks, not one per tree.
const SPECIES_BUCKETS := 4

var _tree_placement := TreePlacement.new()
var _tree_sprite_generator := ProceduralTreeSprite.new()
var _texture_cache: Dictionary = {}  # bucket (float) -> ImageTexture
var _wind_sway := WindSway.new()
var _drop_shadow := DropShadow.new()


## Spawns a collidable tree node (as a child of `parent`) for every forested
## cell in the chunk, positioned at its global tile coordinate. Returns the
## spawned nodes so the caller can free them again when the chunk unloads.
func spawn_trees(
	parent: Node2D, chunk: Chunk, chunk_origin_tiles: Vector2i, tile_size: int
) -> Array[Node2D]:
	# Trees must sort against each other and against whoever walks among
	# them (see _build_tree_node's anchor comment).
	parent.y_sort_enabled = true

	var spawned: Array[Node2D] = []
	for y in chunk.height:
		var global_y := chunk_origin_tiles.y + y
		for x in chunk.width:
			var global_x := chunk_origin_tiles.x + x
			var biome_name := chunk.biome[y * chunk.width + x]
			if not _tree_placement.has_tree_at(global_x, global_y, biome_name):
				continue

			var position := Vector2((global_x + 0.5) * tile_size, (global_y + 0.5) * tile_size)
			var tree := _build_tree_node(position)
			tree.position = position
			parent.add_child(tree)
			spawned.append(tree)

	return spawned


## Spawns a single collidable tree node at an explicit position -- for a
## seed-spread sapling (see TreeSpread/EarthChunkManager.step_tree_spread)
## planted outside the original map-generated forest.
## `age_seconds` is how long the tree has stood (see TreeGrowth). Defaults
## to INF -- fully grown -- for callers that mean "a tree that was always
## here"; a freshly spread sapling passes 0.0 and starts as a seedling.
func spawn_tree_at(parent: Node2D, position: Vector2, age_seconds: float = INF) -> ChoppableTree:
	parent.y_sort_enabled = true
	var tree := _build_tree_node(position, age_seconds)
	tree.position = position
	parent.add_child(tree)
	return tree


## A collidable, choppable tree (see ChoppableTree), textured from this
## position's TreeGenome (see _texture_for). Trees deliberately run NO
## per-frame script: there are thousands loaded at once, so forage dropping is
## handled centrally and throttled by EarthChunkManager (see ForageScheduler)
## instead; take_damage() only runs on demand when an axe hits one.
func _build_tree_node(position: Vector2, age_seconds: float = INF) -> ChoppableTree:
	var body := ChoppableTree.new()

	var genome := TreeGenome.new(hash("%d_%d" % [int(position.x), int(position.y)]))
	body.species_bias = genome.species_bias
	body.sprite_seed = hash("%d_%d" % [int(position.x), int(position.y)])

	# Contact shadow at the trunk's base, added first so it draws under the
	# canopy sprite (sibling order == draw order).
	body.add_child(
		_drop_shadow.make_shadow(int(TREE_SIZE.x * 0.85), TREE_SIZE.y * 0.5 - 2.0)
	)

	var sprite := Sprite2D.new()
	sprite.texture = _texture_for(position)
	# Growth stage: a tree spread in mid-session starts as a seedling and
	# thickens over time (see TreeGrowth), so a forest shows an age
	# structure instead of every trunk arriving full-grown. Original forest
	# trees are already mature -- they predate the session.
	body.growth_scale = TreeGrowth.new().scale_at(age_seconds)
	# The canopy art is authored DETAIL_MULTIPLIER times oversized for pixel
	# detail; scaling it back down is what keeps the tree's world footprint
	# unchanged (see docs/concept/art_resolution.md).
	sprite.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE
	# Anchor the tree at the FOOT of its trunk rather than its middle, by
	# drawing the canopy above the node's origin. Y-sorting compares node
	# origins, so a centre-anchored tree sorts as though it stood where its
	# crown is -- and a player walking behind it would draw in front.
	sprite.offset.y = -float(ProceduralTreeSprite.SIZE.y) * 0.5
	# Canopy sways in the wind (GPU-only, preserving this function's no-per-
	# frame-script constraint) -- one shared material across all trees.
	sprite.material = _wind_sway.shared_material()
	body.add_child(sprite)
	body.bind_canopy(sprite)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = TREE_SIZE * COLLISION_SCALE
	collision.shape = shape
	body.add_child(collision)

	return body


## The genome-tinted tree texture for a tree at `position` -- the same genome
## a tree at this position drops forage under (see ForageScheduler.genome_for),
## so a visibly fruit-leaning canopy actually drops more fruit. Textures are
## cached per species_bias bucket (not per tree) to keep the total generated
## texture count bounded regardless of how many trees are loaded.
func _texture_for(position: Vector2) -> ImageTexture:
	var genome := TreeGenome.new(hash("%d_%d" % [int(position.x), int(position.y)]))
	var bucket := roundf(genome.species_bias * SPECIES_BUCKETS) / float(SPECIES_BUCKETS)
	if not _texture_cache.has(bucket):
		_texture_cache[bucket] = _tree_sprite_generator.generate_texture(bucket, hash(bucket))
	return _texture_cache[bucket]
