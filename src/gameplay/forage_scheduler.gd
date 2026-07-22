extends RefCounted

## Picks a small, bounded set of forage drops from the currently-loaded trees
## each forage tick. Central and O(count) per tick -- deliberately NOT
## per-tree-per-frame, which would scale with the (thousands of) loaded trees
## and tank the frame rate. Deterministic per tick so it's testable.
##
## Each tree's species (fruit vs nut) leans toward its own TreeGenome.species_bias
## -- its "DNA" -- rather than a flat coin flip independent of which tree it
## is. A tree's genome is derived deterministically from its position (no
## per-tree state needed for the always-mature original forest; see
## TreeGenome and ForageTree's known-gaps notes for planted/spread saplings).

const TreeGenome = preload("res://src/gameplay/tree_genome.gd")


## Returns up to `count` drops, each {position, id}, chosen from tree_positions.
func drops(tree_positions: Array, tick: int, count: int) -> Array:
	var result: Array = []
	if tree_positions.is_empty():
		return result
	for i in count:
		var h: int = absi(hash("%d_%d" % [tick, i]))
		var position: Vector2 = tree_positions[h % tree_positions.size()]
		var genome := genome_for(position)
		var roll := float((h / 31) % 10000) / 10000.0
		var id := "fruit" if roll < genome.species_bias else "nut"
		result.append({"position": position, "id": id})
	return result


## The deterministic genome for the tree at `position` -- always the same
## genome for the same position, so a given tree's species lean is stable
## across ticks even though the roll each tick still varies.
func genome_for(position: Vector2) -> TreeGenome:
	return TreeGenome.new(hash("%d_%d" % [int(position.x), int(position.y)]))
