extends RefCounted

## Deterministic, per-tile stone/boulder placement on grassland and forest
## cells. Same coordinate-hash approach as TreePlacement (see that file for
## why a hash beats sampling noise at integer lattice points), but much
## sparser -- boulders are scattered landmarks, not ground cover. In forest,
## a cell that already carries a tree never also carries a stone.

const TreePlacement = preload("res://src/world/tree_placement.gd")

const STONE_BIOMES: Array[String] = ["grassland", "forest"]
const STONE_DENSITY := 0.012

var _tree_placement := TreePlacement.new()


## Whether a boulder sits at this global tile, given its biome.
func has_stone_at(global_x: int, global_y: int, biome_name: String) -> bool:
	if not STONE_BIOMES.has(biome_name):
		return false
	if _tree_placement.has_tree_at(global_x, global_y, biome_name):
		return false
	var value := float(absi(hash("%d_%d_stone" % [global_x, global_y])) % 10000) / 10000.0
	return value < STONE_DENSITY


## Local cell positions (within a `width` x `height` chunk biome grid at
## `chunk_origin_tiles`) that carry a stone. `biome` is the chunk's flat
## row-major biome-name array, same layout as Chunk.biome.
func stones_in_chunk(
	chunk_origin_tiles: Vector2i, biome: Array, width: int, height: int
) -> Array[Vector2i]:
	var stones: Array[Vector2i] = []
	for y in height:
		for x in width:
			var biome_name: String = biome[y * width + x]
			if has_stone_at(chunk_origin_tiles.x + x, chunk_origin_tiles.y + y, biome_name):
				stones.append(Vector2i(x, y))
	return stones


## Deterministic per-tile seed for this stone's sprite variation.
func seed_at(global_x: int, global_y: int) -> int:
	return hash("%d_%d_stone_seed" % [global_x, global_y])
