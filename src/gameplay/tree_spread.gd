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

const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

## Minimum distance (px) a sapling must keep from any existing tree.
##
## Was 1.5px -- a tenth of a tile -- chosen to sit below TreeGenome's
## MIN_SPREAD_RADIUS of 2.0 so that spread would not reject every candidate.
## That reasoning was sound only because the radius was being misread: it is
## documented in TILES and was being added to a position in PIXELS, so seeds
## landed a couple of pixels from the trunk and the spacing rule had to be
## smaller still to let any through. Both are now in the same units.
##
## A third of a tile: close enough that MAX_TREES_PER_TILE is reachable, far
## enough that two trunks are not the same pixel.
const MIN_TREE_SPACING := TerrainRenderer.TILE_SIZE / 3.0

## How many trees one tile may carry.
##
## Nothing bounded this before, and with a pixel-and-a-half spacing rule a
## sixteen-pixel tile could in principle hold a hundred trunks. Three is a
## thicket you can walk into; more is a wall of overlapping sprites that reads
## as a rendering fault rather than as a wood.
const MAX_TREES_PER_TILE := 3

## A backstop against a runaway wood -- NOT a carrying capacity.
##
## Set well above what a real forest loads. A loaded forest around Berlin
## carries about 3,500 trees (measured, see test_earth_chunk_manager), so a
## ceiling anywhere near that number does not bound a runaway, it stops
## ordinary spread dead -- which is exactly what a first attempt at 900 did.
##
## What actually bounds tree density is MAX_TREES_PER_TILE, which bounds it by
## AREA and so scales with how much world is loaded. This only catches the case
## where something has gone wrong enough to plant tens of thousands.
const MAX_TREES_IN_WORLD := 20000


## Returns up to `count` proposed saplings, each {position, genome_seed},
## grown from a randomly (but deterministically) chosen tree in
## `tree_positions` and landing within that parent's own spread_radius.
## Candidates too close to any position in `tree_positions` or
## `existing_saplings` are skipped, so the result can be smaller than count.
func propose_saplings(tree_positions: Array, existing_saplings: Array, tick: int, count: int) -> Array:
	var result: Array = []
	if tree_positions.is_empty():
		return result

	# A full wood proposes nothing, however often it is asked.
	if existing_saplings.size() >= MAX_TREES_IN_WORLD:
		return result

	for i in count:
		var h: int = absi(hash("%d_%d_spread" % [tick, i]))
		var parent_position: Vector2 = tree_positions[h % tree_positions.size()]
		var parent_genome := TreeGenome.new(hash("%d_%d" % [int(parent_position.x), int(parent_position.y)]))

		var angle := float((h / 7) % 360) * PI / 180.0
		var distance_fraction := float((h / 7919) % 1000) / 1000.0
		# spread_radius is in TILES (see TreeGenome) and positions are in
		# pixels. Adding it raw put every seed inside the parent's own tile,
		# which is why woods never spread.
		var reach: float = parent_genome.spread_radius * TerrainRenderer.TILE_SIZE
		var offset := Vector2(cos(angle), sin(angle)) * distance_fraction * reach
		var sapling_position := parent_position + offset

		if _too_close(sapling_position, tree_positions) or _too_close(sapling_position, existing_saplings):
			continue
		if _tile_is_full(sapling_position, tree_positions, existing_saplings):
			continue

		var child_genome: TreeGenome = parent_genome.mutate(h)
		result.append({"position": sapling_position, "genome_seed": child_genome.seed_value})

	return result


## Whether the tile this candidate falls on already carries its limit.
func _tile_is_full(candidate: Vector2, tree_positions: Array, existing_saplings: Array) -> bool:
	var tile := _tile_of(candidate)
	var standing := 0
	for other in tree_positions:
		if _tile_of(other) == tile:
			standing += 1
	for other in existing_saplings:
		if _tile_of(other) == tile:
			standing += 1
	return standing >= MAX_TREES_PER_TILE


static func _tile_of(position: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(position.x / TerrainRenderer.TILE_SIZE)),
		int(floor(position.y / TerrainRenderer.TILE_SIZE))
	)


func _too_close(candidate: Vector2, positions: Array) -> bool:
	for other in positions:
		if candidate.distance_to(other) < MIN_TREE_SPACING:
			return true
	return false
