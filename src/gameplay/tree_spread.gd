extends RefCounted

## Picks where mature trees' seeds land each spread tick -- deterministic and
## bounded per call (same centralized-ticking pattern as ForageScheduler,
## deliberately NOT per-tree-per-frame, since thousands of trees can be
## loaded at once). Each proposed sapling's genome is a mutated child of its
## parent tree's genome (see TreeGenome.mutate), so a spreading forest's
## traits drift instead of resetting every generation.
##
## The original (map-generated) forest is treated as always mature -- only
## these spread saplings need real growth/aging (tracked by the caller, e.g.
## EarthChunkManager, once planted).

const TreeGenome = preload("res://src/gameplay/tree_genome.gd")

## Minimum distance (px) a sapling must keep from any existing tree, so
## spread doesn't stack saplings directly on top of other trees. Deliberately
## kept below TreeGenome.MIN_SPREAD_RADIUS (2.0) so even a tightly-genomed
## parent tree still has a real (if narrow) band it can successfully seed
## into, rather than being unable to ever spread at all.
const MIN_TREE_SPACING := 1.5


## Returns up to `count` proposed saplings, each {position, genome_seed},
## grown from a randomly (but deterministically) chosen tree in
## `tree_positions` and landing within that parent's own spread_radius.
## Candidates too close to any position in `tree_positions` or
## `existing_saplings` are skipped, so the result can be smaller than count.
func propose_saplings(tree_positions: Array, existing_saplings: Array, tick: int, count: int) -> Array:
	var result: Array = []
	if tree_positions.is_empty():
		return result

	for i in count:
		var h: int = absi(hash("%d_%d_spread" % [tick, i]))
		var parent_position: Vector2 = tree_positions[h % tree_positions.size()]
		var parent_genome := TreeGenome.new(hash("%d_%d" % [int(parent_position.x), int(parent_position.y)]))

		var angle := float((h / 7) % 360) * PI / 180.0
		var distance_fraction := float((h / 7919) % 1000) / 1000.0
		var offset := Vector2(cos(angle), sin(angle)) * distance_fraction * parent_genome.spread_radius
		var sapling_position := parent_position + offset

		if _too_close(sapling_position, tree_positions) or _too_close(sapling_position, existing_saplings):
			continue

		var child_genome: TreeGenome = parent_genome.mutate(h)
		result.append({"position": sapling_position, "genome_seed": child_genome.seed_value})

	return result


func _too_close(candidate: Vector2, positions: Array) -> bool:
	for other in positions:
		if candidate.distance_to(other) < MIN_TREE_SPACING:
			return true
	return false
