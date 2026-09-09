extends RefCounted

## Spawns grass frogs per chunk -- part of the seasonal-behavior epic's
## phase 10 (docs/concept/seasonal_behavior.md), the most novel "new
## species from nothing" piece in that pass, built last so its earlier
## phases' patterns were proven first. Mirrors CaterpillarRenderer's own
## minimal shape (a guaranteed min/max count per qualifying chunk, no
## scent/species-pool machinery -- a frog's placement doesn't depend on
## anything chunk-specific beyond biome+water), with two gates
## CaterpillarRenderer's identical shape doesn't both need:
##
## - A season gate, same "spawn-time gate, not a per-frame one" shape as
##   CaterpillarRenderer.ACTIVE_SEASONS -- but flipped to real grass frog
##   biology: active spring through autumn, brumates (buries into mud/leaf
##   litter, inactive) through winter, rather than caterpillar's
##   spring/summer-only life stage.
## - A real WATER-PRESENCE gate: a grass frog needs actual water nearby,
##   not just the right land biome. Reuses WaterAreaSurvey.interior_water_
##   cell_count -- the same real "how much water is in this chunk" signal
##   the aquatic fish population model already uses (see docs/concept/
##   fishing.md) -- rather than inventing a second one. Any real water
##   (river, lake, or ocean-adjacent) counts; a threshold of "more than
##   zero" is enough, since this is a presence/absence gate, not a capacity
##   input the way fish's own aquatic population model uses the same count.

const GrassFrogMarker = preload("res://src/rendering/grass_frog_marker.gd")
const WaterAreaSurvey = preload("res://src/world/water_area_survey.gd")
const Chunk = preload("res://src/world/chunk.gd")

## Where a grass frog actually lives -- mirrors CaterpillarRenderer.
## CATERPILLAR_BIOMES/AmbientFlyerRenderer.BIRD_BIOMES exactly rather than
## DecomposerRenderer's wider LAND_BIOMES: a temperate pond-edge amphibian
## doesn't extend to desert/tundra/mountain.
const GRASS_FROG_BIOMES := {"grassland": true, "forest": true, "rainforest": true}

## Real biology: active spring through autumn, brumates through winter --
## see the class doc comment for why this is a spawn-time gate, not a
## per-frame one.
const ACTIVE_SEASONS := {"spring": true, "summer": true, "autumn": true}

const MIN_GRASS_FROGS_PER_CHUNK := 1
const MAX_GRASS_FROGS_PER_CHUNK := 3

var _water_survey := WaterAreaSurvey.new()


## Spawns this chunk's grass frogs into `parent`, returning the markers so
## the caller (EarthChunkManager) can track/despawn them per chunk, same
## contract as CaterpillarRenderer.spawn_caterpillars/DecomposerRenderer.
## spawn_decomposers.
func spawn_grass_frogs(
	parent: Node, chunk: Chunk, biome_name: String, season: String, chunk_origin: Vector2i,
	chunk_size: int, tile_size: float, chunk_seed: int
) -> Array:
	var markers: Array = []
	if not GRASS_FROG_BIOMES.has(biome_name) or not ACTIVE_SEASONS.has(season):
		return markers
	if _water_survey.interior_water_cell_count(chunk) <= 0:
		return markers
	var h := absi(hash("%d_%d_grass_frog_count" % [chunk_origin.x, chunk_origin.y]))
	var count := MIN_GRASS_FROGS_PER_CHUNK + (h % (MAX_GRASS_FROGS_PER_CHUNK - MIN_GRASS_FROGS_PER_CHUNK + 1))
	for i in count:
		var wander_seed := hash("%d_%d_grass_frog_%d" % [chunk_origin.x, chunk_origin.y, i])
		var local_x := absi(wander_seed) % chunk_size
		var local_y := absi(wander_seed / 7) % chunk_size
		var home := Vector2(chunk_origin) * tile_size + Vector2(local_x, local_y) * tile_size

		var marker := GrassFrogMarker.new()
		marker.home = home
		marker.position = home
		marker.wander_seed = wander_seed
		parent.add_child(marker)
		markers.append(marker)
	return markers
