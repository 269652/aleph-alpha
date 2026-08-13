extends RefCounted

const ArtResolution = preload("res://src/rendering/art_resolution.gd")

## How big the bird is in the world, relative to its drawn art.
const BIRD_WORLD_SCALE := 0.46

## Chunk-based spawn/despawn of fish-eating birds (kingfishers) -- gated by
## water presence (not a land biome pool, unlike AmbientFlyerRenderer),
## since piscivores hunt over water specifically. See
## docs/concept/ecosystem_dynamics.md's "fish-eating birds" (A new aerial
## tier).

const PiscivoreBirdMarker = preload("res://src/rendering/piscivore_bird_marker.gd")
const AmbientFlyerMovement = preload("res://src/rendering/ambient_flyer_movement.gd")
const ProceduralBirdSprite = preload("res://src/rendering/procedural_bird_sprite.gd")
const WaterAreaSurvey = preload("res://src/world/water_area_survey.gd")
const Chunk = preload("res://src/world/chunk.gd")

const SPECIES := "kingfisher"

## Same cruise tuning as ambient songbirds (see AmbientFlyerRenderer) --
## kingfishers glide the same way when not diving.
const CRUISE_SPEED := 34.0
const CRUISE_RADIUS := 60.0
const CRUISE_INTERVAL := 1.8

## Deliberately rare -- a special sight, not filling the sky. At most one
## per water chunk, regardless of how much water it has.
const SPAWN_CHANCE := 0.15
const MAX_PER_CHUNK := 1

var _sprite := ProceduralBirdSprite.new()
var _water_survey := WaterAreaSurvey.new()


## `world` is passed straight through to the spawned marker (duck-typed
## fish_population_near/record_fish_catch_near -- see PiscivoreBirdMarker
## and EarthChunkManager); pass null (default) for callers that only need a
## static placeholder (e.g. isolated rendering tests).
func spawn_piscivore_birds(
	parent: Node2D, chunk_coord: Vector2i, chunk: Chunk, chunk_origin_tiles: Vector2i, tile_size: int, world = null
) -> Array[Node2D]:
	var water_cells: Array[Vector2i] = []
	for y in chunk.height:
		for x in chunk.width:
			if _water_survey.is_interior_water(chunk, x, y):
				water_cells.append(Vector2i(x, y))
	if water_cells.is_empty():
		return []

	var spawn_roll := float(
		absi(hash("%d_%d_kingfisher_spawn" % [chunk_coord.x, chunk_coord.y])) % 10000
	) / 10000.0
	if spawn_roll > SPAWN_CHANCE:
		return []

	var seed_value := absi(hash("%d_%d_kingfisher" % [chunk_coord.x, chunk_coord.y]))
	var cell: Vector2i = water_cells[seed_value % water_cells.size()]
	var global := chunk_origin_tiles + cell
	var position := Vector2((global.x + 0.5) * tile_size, (global.y + 0.5) * tile_size)

	var marker := PiscivoreBirdMarker.new()
	marker.species = SPECIES
	marker.texture = _sprite.generate_texture(SPECIES, seed_value)
	# Art is authored DETAIL_MULTIPLIER times oversized; scaling it back
	# keeps the flyer the same size in the world (see
	# docs/concept/art_resolution.md).
	# A kingfisher is a small bird, not a gull (see
	# AmbientFlyerRenderer.FLYER_WORLD_SCALE for the same reasoning).
	marker.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE * BIRD_WORLD_SCALE
	marker.position = position
	marker.home = position
	marker.wander_seed = seed_value
	marker.setup(world, AmbientFlyerMovement.new(CRUISE_SPEED, CRUISE_RADIUS, CRUISE_INTERVAL))
	parent.add_child(marker)
	return [marker]
