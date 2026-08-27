extends RefCounted

const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

## How big a fish is relative to its drawn art -- a pond fish is a
## fraction of a land animal's bulk.
const FISH_WORLD_SCALE := 0.55

## Chunk-based spawn/despawn of visible, catchable fish on ocean cells -- same
## shape as TreeRenderer/CreatureRenderer: one node per qualifying tile,
## deterministic per global coordinate (so revisiting a pond looks stable),
## capped so a large water body doesn't spawn hundreds of nodes. Each fish is
## a lightweight FishMarker (see fish_marker.gd), not full creature AI.

const Chunk = preload("res://src/world/chunk.gd")
const FishMarker = preload("res://src/rendering/fish_marker.gd")
const ProceduralFishSprite = preload("res://src/rendering/procedural_fish_sprite.gd")
const WaterAreaSurvey = preload("res://src/world/water_area_survey.gd")

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
var _water_survey := WaterAreaSurvey.new()


## Spawns a FishMarker (as a child of `parent`) for a subset of this chunk's
## interior-water cells, positioned at each cell's global tile coordinate.
## `world` (duck-typed biome_at_global, same contract as CreatureRenderer) is
## handed to each fish so it stays confined to water when it wanders; pass
## null (default) for callers that only need static placeholders (e.g.
## isolated rendering tests).
##
## `target_count` (default -1, appended last so every pre-existing call site
## keeps compiling and behaving unchanged, same convention as
## CreatureRenderer's biome_name parameter) switches spawn *count* from the
## legacy independent per-cell SPAWN_CHANCE roll to the aquatic population
## model's aggregate count (see
## docs/concept/fishing.md#individual-fidelity-promotion): -1 keeps the old
## probabilistic scatter; >= 0 deterministically picks exactly that many
## interior-water cells (capped by MAX_FISH_PER_CHUNK and by how much
## interior water the chunk actually has), so a fished-down chunk's aggregate
## population visibly shows fewer swimming markers on next spawn.
func spawn_fish(
	parent: Node2D,
	chunk_coord: Vector2i,
	chunk: Chunk,
	chunk_origin_tiles: Vector2i,
	tile_size: int,
	world = null,
	target_count: int = -1
) -> Array[Node2D]:
	if target_count >= 0:
		return _spawn_target_count(parent, chunk, chunk_origin_tiles, tile_size, world, target_count)
	return _spawn_by_probability(parent, chunk, chunk_origin_tiles, tile_size, world)


func _spawn_by_probability(
	parent: Node2D, chunk: Chunk, chunk_origin_tiles: Vector2i, tile_size: int, world
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
			if not _water_survey.is_interior_water(chunk, x, y):
				continue
			if spawned.size() >= MAX_FISH_PER_CHUNK:
				continue
			if _spawn_roll(global_x, global_y) > SPAWN_CHANCE:
				continue
			spawned.append(_spawn_cell(parent, chunk_origin_tiles, tile_size, world, global_x, global_y))
	return spawned


## Deterministically picks up to `target_count` of this chunk's interior-water
## cells, ranked by the same per-cell hash the probability path rolls against
## (so the chosen subset still reads as scattered rather than clustered in
## raster order) -- the count-vs-placement split fishing.md's spec calls for.
func _spawn_target_count(
	parent: Node2D, chunk: Chunk, chunk_origin_tiles: Vector2i, tile_size: int, world, target_count: int
) -> Array[Node2D]:
	var candidates: Array[Vector2i] = []
	for y in chunk.height:
		var global_y := chunk_origin_tiles.y + y
		for x in chunk.width:
			var global_x := chunk_origin_tiles.x + x
			if _water_survey.is_interior_water(chunk, x, y):
				candidates.append(Vector2i(global_x, global_y))

	candidates.sort_custom(func(a, b): return _spawn_roll(a.x, a.y) < _spawn_roll(b.x, b.y))

	var wanted := clampi(target_count, 0, mini(MAX_FISH_PER_CHUNK, candidates.size()))
	var spawned: Array[Node2D] = []
	for i in wanted:
		var cell: Vector2i = candidates[i]
		spawned.append(_spawn_cell(parent, chunk_origin_tiles, tile_size, world, cell.x, cell.y))
	return spawned


func _spawn_roll(global_x: int, global_y: int) -> float:
	return float(absi(hash("%d_%d_fish_spawn" % [global_x, global_y])) % 10000) / 10000.0


func _spawn_cell(
	parent: Node2D, chunk_origin_tiles: Vector2i, tile_size: int, world, global_x: int, global_y: int
) -> FishMarker:
	var seed_value := absi(hash("%d_%d_fish_species" % [global_x, global_y]))
	var species: String = SPECIES_POOL[seed_value % SPECIES_POOL.size()]
	var position := Vector2((global_x + 0.5) * tile_size, (global_y + 0.5) * tile_size)
	return _build_fish(parent, species, position, seed_value, world, tile_size)


## Public wrapper around _build_fish -- for callers outside this renderer
## that need one real, correctly-rendered fish materialized directly (the
## character preview diorama's own small standalone pond, see
## src/rendering/character_preview_diorama.gd -- not chunk-based ocean-tile
## spawning at all) rather than reaching into a private method across
## files, the same convention StoneRenderer.build_liftable_stone_node
## already established for the same reason. `world` left null (its own
## documented, supported standalone-rendering fallback -- see
## FishMarker.setup's own doc comment) means the fish swims unconfined by
## any water-tile check, just its own home-anchored wander.
func spawn_fish_at(parent: Node2D, species: String, position: Vector2, seed_value: int) -> FishMarker:
	return _build_fish(parent, species, position, seed_value, null, TerrainRenderer.TILE_SIZE)


func _build_fish(
	parent: Node2D, species: String, position: Vector2, seed_value: int, world, tile_size: int
) -> FishMarker:
	var marker := FishMarker.new()
	marker.texture = _fish_sprite.generate_texture(species, seed_value)
	# Fish art is authored DETAIL_MULTIPLIER times oversized; scaling it
	# back keeps the fish the same size in the water (see
	# docs/concept/art_resolution.md).
	# Fish are SMALL. Drawn at the art scale alone they came out the size
	# of a boar, so their world size is knocked down further.
	marker.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE * FISH_WORLD_SCALE
	marker.position = position
	marker.home = position
	marker.wander_seed = seed_value
	marker.species = species
	marker.setup(world, tile_size)
	parent.add_child(marker)
	return marker
