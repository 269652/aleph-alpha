extends RefCounted

## Spawns collidable boulder nodes for a chunk's stone cells (see
## StonePlacement) -- the stone-entity equivalent of TreeRenderer, and
## deliberately the same shape: deterministic per-position placement, a
## seeded procedural sprite (see ProceduralStoneSprite), a slightly-forgiving
## collision box, no per-frame script. Mining them (MiningYield) is a later
## wiring step; for now they are terrain landmarks that block movement.

const StonePlacement = preload("res://src/world/stone_placement.gd")
const OrePlacement = preload("res://src/world/ore_placement.gd")
const Chunk = preload("res://src/world/chunk.gd")
const ProceduralStoneSprite = preload("res://src/rendering/procedural_stone_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const ProceduralOreSprite = preload("res://src/rendering/procedural_ore_sprite.gd")
const SmashableStone = preload("res://src/rendering/smashable_stone.gd")
const MinableOre = preload("res://src/rendering/minable_ore.gd")

## The boulder's WORLD footprint -- derived from its art size, which is
## authored DETAIL_MULTIPLIER times oversized (see
## docs/concept/art_resolution.md). Collision sizes off this, so it stays
## matched to what the player actually sees.
const STONE_SIZE := Vector2(ProceduralStoneSprite.SIZE) * ArtResolution.SPRITE_SCALE
const COLLISION_SCALE := 0.6

## Bounded texture variety (same reasoning as TreeRenderer.SPECIES_BUCKETS):
## many stones load at once, so textures are cached per seed bucket rather
## than generated per stone.
const TEXTURE_BUCKETS := 4

var _stone_placement := StonePlacement.new()
var _stone_sprite_generator := ProceduralStoneSprite.new()
var _ore_sprite_generator := ProceduralOreSprite.new()
var _ore_placement := OrePlacement.new()
var _texture_cache: Dictionary = {}  # bucket (int) -> ImageTexture


## Spawns a collidable stone node (as a child of `parent`) for every stone
## cell in the chunk. A minority of stone cells are ore-bearing (see
## OrePlacement.is_ore_at) and spawn a MinableOre node instead of a plain
## SmashableStone boulder. Returns the spawned nodes so the caller can free
## them again when the chunk unloads.
func spawn_stones(
	parent: Node2D, chunk: Chunk, chunk_origin_tiles: Vector2i, tile_size: int
) -> Array[Node2D]:
	var spawned: Array[Node2D] = []
	for cell in _stone_placement.stones_in_chunk(
		chunk_origin_tiles, chunk.biome, chunk.width, chunk.height
	):
		var global_x := chunk_origin_tiles.x + cell.x
		var global_y := chunk_origin_tiles.y + cell.y
		var position := Vector2((global_x + 0.5) * tile_size, (global_y + 0.5) * tile_size)
		var biome_name: String = chunk.biome[cell.y * chunk.width + cell.x]

		var node: StaticBody2D
		if _ore_placement.is_ore_at(global_x, global_y, biome_name):
			node = _build_ore_node(global_x, global_y)
		else:
			node = _build_stone_node(_stone_placement.seed_at(global_x, global_y))
		node.position = position
		parent.add_child(node)
		spawned.append(node)
	return spawned


func _build_stone_node(seed_value: int) -> StaticBody2D:
	var body := SmashableStone.new()
	body.stone_seed = seed_value
	_attach_body_parts(body, _texture_for(seed_value))
	return body


func _build_ore_node(global_x: int, global_y: int) -> StaticBody2D:
	var ore_type := _ore_placement.ore_type_at(global_x, global_y)
	var seed_value := _ore_placement.seed_at(global_x, global_y)
	var body := MinableOre.new()
	body.ore_type = ore_type
	body.ore_seed = seed_value
	# Ore art isn't cached by bucket -- there are far fewer ore nodes than
	# plain boulders, and the flecks should reflect the actual ore type/seed.
	_attach_body_parts(body, _ore_sprite_generator.generate_texture(ore_type, seed_value))
	return body


func _attach_body_parts(body: StaticBody2D, texture: Texture2D) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE
	body.add_child(sprite)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = STONE_SIZE * COLLISION_SCALE
	collision.shape = shape
	body.add_child(collision)


func _texture_for(seed_value: int) -> ImageTexture:
	var bucket := absi(seed_value) % TEXTURE_BUCKETS
	if not _texture_cache.has(bucket):
		_texture_cache[bucket] = _stone_sprite_generator.generate_texture(bucket)
	return _texture_cache[bucket]
