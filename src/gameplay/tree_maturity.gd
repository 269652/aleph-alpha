extends RefCounted

## Filters loaded trees down to the ones actually eligible to forage-drop or
## spread seeds of their own. The original map-generated forest is always
## mature (deterministic, position-derived -- see TreeRenderer); only
## spread-in saplings (see TreeSpread) have real growth, tracked by the
## world-age they were planted at.

const TreeGenome = preload("res://src/gameplay/tree_genome.gd")


## `original_positions` are always-mature tree positions. `saplings` is an
## Array of {position: Vector2, planted_at: float} -- a sapling is included
## once `world_age - planted_at` reaches its own genome's maturity_time
## (genome derived from its position, same as everywhere else in the game).
func mature_positions(original_positions: Array, saplings: Array, world_age: float) -> Array:
	var result: Array = original_positions.duplicate()
	for sapling in saplings:
		var position: Vector2 = sapling.position
		var genome := TreeGenome.new(hash("%d_%d" % [int(position.x), int(position.y)]))
		if world_age - float(sapling.planted_at) >= genome.maturity_time:
			result.append(position)
	return result
