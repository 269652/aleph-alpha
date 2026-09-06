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

const MIN_BUGS_PER_CHUNK := 1
const MAX_BUGS_PER_CHUNK := 2


## Spawns this chunk's decomposers into `parent`, returning the markers so
## the caller (EarthChunkManager) can track/despawn them per chunk, same
## contract as WildCropRenderer.spawn_markers.
##
## "ant" retired as a decomposer species (2026-09-06, "unify any
## duplicates" -- see docs/concept/soil_fauna.md's "A real food economy"
## section): a decomposer-flavoured ant and a real AntColony forager
## (AntForagerMarker) drew the identical art and were impossible for a
## player to tell apart, yet only the real forager could ever carry
## anything home, grow a colony, or register on a mound's food stat --
## this one just wandered decoratively, with no mound behind it at all,
## even on biomes (desert/tundra/mountain) no real AntColony mound can
## ever exist on. Every "ant" in the world now means the same real thing.
func spawn_decomposers(
	parent: Node, biome_name: String, chunk_origin: Vector2i, chunk_size: int,
	tile_size: float, chunk_seed: int
) -> Array:
	var markers: Array = []
	if not LAND_BIOMES.has(biome_name):
		return markers
	markers.append_array(
		_spawn_species(parent, "bug", chunk_origin, chunk_size, tile_size, chunk_seed, MIN_BUGS_PER_CHUNK, MAX_BUGS_PER_CHUNK)
	)
	return markers


func _spawn_species(
	parent: Node, species: String, chunk_origin: Vector2i, chunk_size: int, tile_size: float,
	chunk_seed: int, min_count: int, max_count: int
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
		parent.add_child(marker)
		markers.append(marker)
	return markers
