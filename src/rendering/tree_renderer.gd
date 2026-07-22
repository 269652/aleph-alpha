extends RefCounted

const TreePlacement = preload("res://src/world/tree_placement.gd")
const Chunk = preload("res://src/world/chunk.gd")
const ChoppableTree = preload("res://src/rendering/choppable_tree.gd")
const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const TreeGenome = preload("res://src/gameplay/tree_genome.gd")

## Tree sprite size in pixels (see ProceduralTreeSprite), and how much
## smaller than the sprite the actual collision box is (a little forgiving,
## not a hard rectangle edge).
const TREE_SIZE := Vector2(ProceduralTreeSprite.SIZE)
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


## Spawns a collidable tree node (as a child of `parent`) for every forested
## cell in the chunk, positioned at its global tile coordinate. Returns the
## spawned nodes so the caller can free them again when the chunk unloads.
func spawn_trees(
	parent: Node2D, chunk: Chunk, chunk_origin_tiles: Vector2i, tile_size: int
) -> Array[Node2D]:
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
func spawn_tree_at(parent: Node2D, position: Vector2) -> ChoppableTree:
	var tree := _build_tree_node(position)
	tree.position = position
	parent.add_child(tree)
	return tree


## A collidable, choppable tree (see ChoppableTree), textured from this
## position's TreeGenome (see _texture_for). Trees deliberately run NO
## per-frame script: there are thousands loaded at once, so forage dropping is
## handled centrally and throttled by EarthChunkManager (see ForageScheduler)
## instead; take_damage() only runs on demand when an axe hits one.
func _build_tree_node(position: Vector2) -> ChoppableTree:
	var body := ChoppableTree.new()

	var genome := TreeGenome.new(hash("%d_%d" % [int(position.x), int(position.y)]))
	body.species_bias = genome.species_bias
	body.sprite_seed = hash("%d_%d" % [int(position.x), int(position.y)])

	var sprite := Sprite2D.new()
	sprite.texture = _texture_for(position)
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
