extends RefCounted

## Chunk-based spawn/despawn of visible, catchable fish on ocean cells -- same
## shape as TreeRenderer/CreatureRenderer: one node per qualifying tile,
## deterministic per global coordinate (so revisiting a pond looks stable),
## capped so a large water body doesn't spawn hundreds of nodes. Each fish is
## a lightweight FishMarker (see fish_marker.gd), not full creature AI.

const Chunk = preload("res://src/world/chunk.gd")
const FishMarker = preload("res://src/rendering/fish_marker.gd")
const ProceduralFishSprite = preload("res://src/rendering/procedural_fish_sprite.gd")

## "Colorful and multiple varieties" -- every ocean tile's spawn roll picks
## among these (see ProceduralFishSprite.SPECIES_IDS for their art).
const SPECIES_POOL: Array[String] = ["goldfish", "bluegill", "trout", "koi"]

## Fraction of ocean tiles that host a fish -- keeps them sparse rather than
## carpeting every water tile, mirroring how sparse trees/creatures already
## are relative to their placement grid.
const SPAWN_CHANCE := 0.12

## Caps how many fish one chunk can spawn, regardless of how much ocean it
## contains -- same "arbitrarily large source, bounded node count" reasoning
## as CreatureRenderer.MAX_MARKERS_PER_SPECIES.
const MAX_FISH_PER_CHUNK := 10

var _fish_sprite := ProceduralFishSprite.new()


## Spawns a FishMarker (as a child of `parent`) for a deterministic subset of
## this chunk's ocean cells, positioned at each cell's global tile coordinate.
## `world` (duck-typed biome_at_global, same contract as CreatureRenderer) is
## handed to each fish so it stays confined to water when it wanders; pass
## null (default) for callers that only need static placeholders (e.g.
## isolated rendering tests).
func spawn_fish(
	parent: Node2D, chunk_coord: Vector2i, chunk: Chunk, chunk_origin_tiles: Vector2i, tile_size: int, world = null
) -> Array[Node2D]:
	var spawned: Array[Node2D] = []
	for y in chunk.height:
		var global_y := chunk_origin_tiles.y + y
		for x in chunk.width:
			var global_x := chunk_origin_tiles.x + x
			# Interior water only: a shore-adjacent spawn starts life
			# half-beached (see FishMarker.CLEARANCE_PX) -- the reported
			# "fish all strand at the shoreline" look. Chunk-edge cells are
			# excluded too (their neighbors aren't knowable from this chunk
			# alone), erring toward open water.
			if not _is_interior_water(chunk, x, y):
				continue
			if spawned.size() >= MAX_FISH_PER_CHUNK:
				continue

			var spawn_roll := float(absi(hash("%d_%d_fish_spawn" % [global_x, global_y])) % 10000) / 10000.0
			if spawn_roll > SPAWN_CHANCE:
				continue

			var seed_value := absi(hash("%d_%d_fish_species" % [global_x, global_y]))
			var species: String = SPECIES_POOL[seed_value % SPECIES_POOL.size()]
			var position := Vector2((global_x + 0.5) * tile_size, (global_y + 0.5) * tile_size)
			spawned.append(_build_fish(parent, species, position, seed_value, world, tile_size))

	return spawned


## True when (x, y) is an ocean cell whose 4 cardinal neighbors are all ocean
## too -- and not on the chunk's edge (cross-chunk neighbors aren't knowable
## from this chunk alone, so edge cells conservatively don't qualify).
func _is_interior_water(chunk: Chunk, x: int, y: int) -> bool:
	if x <= 0 or y <= 0 or x >= chunk.width - 1 or y >= chunk.height - 1:
		return false
	if chunk.biome[y * chunk.width + x] != "ocean":
		return false
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if chunk.biome[(y + offset.y) * chunk.width + (x + offset.x)] != "ocean":
			return false
	return true


func _build_fish(
	parent: Node2D, species: String, position: Vector2, seed_value: int, world, tile_size: int
) -> FishMarker:
	var marker := FishMarker.new()
	marker.texture = _fish_sprite.generate_texture(species, seed_value)
	marker.position = position
	marker.home = position
	marker.wander_seed = seed_value
	marker.species = species
	marker.setup(world, tile_size)
	parent.add_child(marker)
	return marker
