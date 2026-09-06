extends RefCounted

## Spawns caterpillars per chunk -- requested live: "wire caterpillars
## which live on trees and on the ground around them; they should also do
## groundforaging and eat green leaves (spring, summer only)". Mirrors
## DecomposerRenderer's own minimal shape (a guaranteed min/max count per
## qualifying chunk, no scent/species-pool machinery -- a caterpillar's
## placement doesn't depend on anything chunk-specific beyond biome), with
## one addition: a SEASON gate, checked here rather than continuously at
## runtime (see CaterpillarMarker's own doc comment for why that is the
## right place for it -- the same accepted approximation every other
## ambient decoration in this codebase already has for its own season/
## biome eligibility).

const CaterpillarMarker = preload("res://src/rendering/caterpillar_marker.gd")

## Where trees actually grow -- mirrors AmbientFlyerRenderer.BIRD_BIOMES
## exactly rather than DecomposerRenderer's wider LAND_BIOMES: "lives on
## trees" doesn't extend to desert/tundra/mountain the way "finishes
## whatever a hunt leaves behind" does.
const CATERPILLAR_BIOMES := {"grassland": true, "forest": true, "rainforest": true}

## A real caterpillar is a growing-season life stage -- see the class doc
## comment for why this is a spawn-time gate, not a per-frame one.
const ACTIVE_SEASONS := {"spring": true, "summer": true}

const MIN_CATERPILLARS_PER_CHUNK := 2
const MAX_CATERPILLARS_PER_CHUNK := 4


## Spawns this chunk's caterpillars into `parent`, returning the markers so
## the caller (EarthChunkManager) can track/despawn them per chunk, same
## contract as DecomposerRenderer.spawn_decomposers.
func spawn_caterpillars(
	parent: Node, biome_name: String, season: String, chunk_origin: Vector2i, chunk_size: int,
	tile_size: float, chunk_seed: int
) -> Array:
	var markers: Array = []
	if not CATERPILLAR_BIOMES.has(biome_name) or not ACTIVE_SEASONS.has(season):
		return markers
	var h := absi(hash("%d_%d_caterpillar_count" % [chunk_origin.x, chunk_origin.y]))
	var count := MIN_CATERPILLARS_PER_CHUNK + (h % (MAX_CATERPILLARS_PER_CHUNK - MIN_CATERPILLARS_PER_CHUNK + 1))
	for i in count:
		var wander_seed := hash("%d_%d_caterpillar_%d" % [chunk_origin.x, chunk_origin.y, i])
		var local_x := absi(wander_seed) % chunk_size
		var local_y := absi(wander_seed / 7) % chunk_size
		var home := Vector2(chunk_origin) * tile_size + Vector2(local_x, local_y) * tile_size

		var marker := CaterpillarMarker.new()
		marker.home = home
		marker.position = home
		marker.wander_seed = wander_seed
		parent.add_child(marker)
		markers.append(marker)
	return markers
