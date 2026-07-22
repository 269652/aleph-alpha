extends RefCounted

## Deterministic, per-tile tree placement for forest/rainforest biomes. Uses a
## coordinate hash rather than noise: sampling gradient noise exactly at
## integer lattice points is a known way to get unlucky (many noise
## implementations are zero or heavily patterned at integer coordinates),
## which a plain per-tile density check doesn't need to risk.

const FOREST_BIOMES: Array[String] = ["forest", "rainforest"]
const TREE_DENSITY := 0.35


## Whether a tree stands at this global tile, given its biome.
func has_tree_at(global_x: int, global_y: int, biome_name: String) -> bool:
	if not FOREST_BIOMES.has(biome_name):
		return false
	var value := absi(hash(Vector2i(global_x, global_y))) % 10000 / 10000.0
	return value < TREE_DENSITY
