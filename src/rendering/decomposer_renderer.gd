extends RefCounted

## Spawns ants/bugs per chunk -- see docs/concept/carrion.md. Mirrors
## WildCropRenderer's minimal shape rather than AmbientFlyerRenderer's fuller
## scent/species-pool machinery: a decomposer's placement doesn't depend on
## anything chunk-specific beyond biome, just a guaranteed min/max count per
## chunk (the same "guaranteed, not a coin-flip that can plausibly land on
## zero" fix AmbientFlyerRenderer's own butterflies/bees already needed).

const DecomposerMarker = preload("res://src/rendering/decomposer_marker.gd")

## Land biomes only -- no decomposers wandering the open ocean. Mirrors
## AmbientFlyerRenderer.BIRD_BIOMES's own land-only gate, but wider: a
## decomposer's job (finish whatever a hunt leaves behind) applies anywhere
## a creature can actually die, not just the grassland/forest/rainforest
## slice birds specifically forage in.
const LAND_BIOMES := {
	"grassland": true, "forest": true, "rainforest": true,
	"desert": true, "tundra": true, "mountain": true,
}

const MIN_ANTS_PER_CHUNK := 2
const MAX_ANTS_PER_CHUNK := 4
const MIN_BUGS_PER_CHUNK := 1
const MAX_BUGS_PER_CHUNK := 2


## Spawns this chunk's decomposers into `parent`, returning the markers so
## the caller (EarthChunkManager) can track/despawn them per chunk, same
## contract as WildCropRenderer.spawn_markers.
##
## `snow_depth` is the world's current lying snow (EarthChunkManager.
## snow_depth): a chunk loaded mid-winter spawns its decomposers already
## dormant (DecomposerMarker.is_dormant_under) rather than live on the
## snow for even one frame -- see docs/concept/carrion.md "Dormant under
## lying snow".
func spawn_decomposers(
	parent: Node, biome_name: String, chunk_origin: Vector2i, chunk_size: int,
	tile_size: float, chunk_seed: int, snow_depth: float = 0.0
) -> Array:
	var markers: Array = []
	if not LAND_BIOMES.has(biome_name):
		return markers
	var dormant := DecomposerMarker.is_dormant_under(snow_depth)
	markers.append_array(
		_spawn_species(parent, "ant", chunk_origin, chunk_size, tile_size, chunk_seed, MIN_ANTS_PER_CHUNK, MAX_ANTS_PER_CHUNK, dormant)
	)
	markers.append_array(
		_spawn_species(parent, "bug", chunk_origin, chunk_size, tile_size, chunk_seed, MIN_BUGS_PER_CHUNK, MAX_BUGS_PER_CHUNK, dormant)
	)
	return markers


func _spawn_species(
	parent: Node, species: String, chunk_origin: Vector2i, chunk_size: int, tile_size: float,
	chunk_seed: int, min_count: int, max_count: int, dormant: bool
) -> Array:
	var markers: Array = []
	var h := absi(hash("%d_%d_%s_decomposer_count" % [chunk_origin.x, chunk_origin.y, species]))
	var count := min_count + (h % (max_count - min_count + 1))
	for i in count:
		var wander_seed := hash("%d_%d_%s_decomposer_%d" % [chunk_origin.x, chunk_origin.y, species, i])
		var local_x := absi(wander_seed) % chunk_size
		var local_y := absi(wander_seed / 7) % chunk_size
		var home := Vector2(chunk_origin) * tile_size + Vector2(local_x, local_y) * tile_size

		var marker := DecomposerMarker.new()
		marker.species = species
		marker.home = home
		marker.position = home
		marker.wander_seed = wander_seed
		marker.set_snow_dormant(dormant)
		parent.add_child(marker)
		markers.append(marker)
	return markers
