extends RefCounted

## Spawns millipedes per chunk -- see docs/concept/soil_fauna.md
## "Millipedes: a dedicated autumn leaf-litter decomposer". Mirrors
## CaterpillarRenderer's own minimal shape (a guaranteed min/max count per
## qualifying chunk, no scent/species-pool machinery), minus the one gate
## CaterpillarRenderer needs and this must not: no season restriction at
## all. A real millipede is present year-round, not a growing-season life
## stage -- and being present for autumn specifically, when a caterpillar
## structurally cannot forage its own leaf litter, is the entire reason
## this creature exists.

const MillipedeMarker = preload("res://src/rendering/millipede_marker.gd")

## Wherever trees can grow leaf litter to decompose -- mirrors
## CaterpillarRenderer.CATERPILLAR_BIOMES exactly (see
## test_qualifying_biomes_match_caterpillars_exactly), not the wider,
## carrion-adjacent land set DecomposerRenderer's "bug" uses.
const MILLIPEDE_BIOMES := {"grassland": true, "forest": true, "rainforest": true}

const MIN_MILLIPEDES_PER_CHUNK := 2
const MAX_MILLIPEDES_PER_CHUNK := 4


## Spawns this chunk's millipedes into `parent`, returning the markers so
## the caller (EarthChunkManager) can track/despawn them per chunk, same
## contract as CaterpillarRenderer.spawn_caterpillars/DecomposerRenderer.
## spawn_decomposers -- minus the `season` parameter neither of this
## class's needs require.
func spawn_millipedes(
	parent: Node, biome_name: String, chunk_origin: Vector2i, chunk_size: int,
	tile_size: float, chunk_seed: int
) -> Array:
	var markers: Array = []
	if not MILLIPEDE_BIOMES.has(biome_name):
		return markers
	var h := absi(hash("%d_%d_millipede_count" % [chunk_origin.x, chunk_origin.y]))
	var count := MIN_MILLIPEDES_PER_CHUNK + (h % (MAX_MILLIPEDES_PER_CHUNK - MIN_MILLIPEDES_PER_CHUNK + 1))
	for i in count:
		var wander_seed := hash("%d_%d_millipede_%d" % [chunk_origin.x, chunk_origin.y, i])
		var local_x := absi(wander_seed) % chunk_size
		var local_y := absi(wander_seed / 7) % chunk_size
		var home := Vector2(chunk_origin) * tile_size + Vector2(local_x, local_y) * tile_size

		var marker := MillipedeMarker.new()
		marker.home = home
		marker.position = home
		marker.wander_seed = wander_seed
		parent.add_child(marker)
		markers.append(marker)
	return markers
