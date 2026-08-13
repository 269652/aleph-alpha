extends RefCounted

const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const FishRenderer = preload("res://src/rendering/fish_renderer.gd")

## How big each flyer is in the world, expressed as a MULTIPLE OF A FISH.
## Sizing these against a concrete, visible reference rather than in the
## abstract is what finally made them read correctly: a butterfly is half a
## fish, a sparrow is about one fish, a robin only SLIGHTLY bigger, and the
## kingfisher the largest of them. These are small birds -- the range from
## smallest to largest is deliberately narrow.
const FLYER_WORLD_SCALE := {
	"sparrow": 1.0,
	"robin": 0.92,
	"kingfisher": 1.25,
	"monarch": 0.5,
	"swallowtail": 0.55,
	"blue_morpho": 0.6,
}

## Chunk-based spawn/despawn of ambient wildlife (butterflies, songbirds) --
## same "one node per qualifying cell, deterministic per global coordinate,
## capped" shape as FishRenderer/CreatureRenderer, but deliberately
## decorative/capped only: no population simulation behind these, unlike
## herbivores/predators/fish (see
## docs/concept/ecosystem_dynamics.md's Species roster -- "A new aerial
## tier"). The fish-eating kingfisher is NOT spawned here -- it's a separate
## piscivore behavior gated by water, not a land biome (see
## piscivore_bird_renderer.gd).

const AmbientFlyerMarker = preload("res://src/rendering/ambient_flyer_marker.gd")
const AmbientFlyerMovement = preload("res://src/rendering/ambient_flyer_movement.gd")
const ProceduralButterflySprite = preload("res://src/rendering/procedural_butterfly_sprite.gd")
const ProceduralBirdSprite = preload("res://src/rendering/procedural_bird_sprite.gd")
const Chunk = preload("res://src/world/chunk.gd")

## Butterflies flutter: fast-ish direction changes, small radius, slow speed.
## (Interval bumped from an earlier 0.4s -- fast enough to feel jittery
## rather than readable as fluttering at a glance.)
const BUTTERFLY_SPEED := 16.0
const BUTTERFLY_RADIUS := 30.0
const BUTTERFLY_INTERVAL := 0.7

## Songbirds glide: slower direction changes, larger radius, faster speed.
const BIRD_SPEED := 34.0
const BIRD_RADIUS := 70.0
const BIRD_INTERVAL := 1.8

## kingfisher is deliberately excluded -- it's the piscivore, spawned near
## water by piscivore_bird_renderer.gd instead, not an ambient land presence.
const BUTTERFLY_SPECIES_POOL: Array[String] = ["monarch", "swallowtail", "blue_morpho"]
const BIRD_SPECIES_POOL: Array[String] = ["sparrow", "robin"]

## Real butterflies/songbirds are a warm/flowering-habitat presence --
## excluded from desert/tundra/mountain/ocean as implausible.
const BUTTERFLY_BIOMES := {"grassland": true, "forest": true, "rainforest": true}
const BIRD_BIOMES := {"grassland": true, "forest": true, "rainforest": true}

## Sparse, decorative caps -- much sparser than fish/creatures since these
## are pure ambience, not gameplay-relevant. A guaranteed MIN..MAX range per
## qualifying chunk (deterministic ranked selection, same technique as
## FishRenderer's target_count), not an independent per-cell probability
## roll -- an independent low-probability roll could plausibly land on zero
## hits for some real-world coordinate ranges even when astronomically
## unlikely over a full chunk, and "a qualifying biome sometimes shows
## nothing" isn't an acceptable outcome for a presence that's supposed to
## always be there.
const MIN_BUTTERFLIES_PER_CHUNK := 2
const MAX_BUTTERFLIES_PER_CHUNK := 4
const MIN_BIRDS_PER_CHUNK := 1
const MAX_BIRDS_PER_CHUNK := 3

## Butterflies render at half size -- a real scale difference from songbirds
## (butterflies really are much smaller), and reads better against tall
## grass/trees at this pixel density than the full 14x10 source art.
const BUTTERFLY_SCALE := 0.5
const BIRD_SCALE := 1.0

var _butterfly_sprite := ProceduralButterflySprite.new()
var _bird_sprite := ProceduralBirdSprite.new()


func spawn_ambient_flyers(
	parent: Node2D, chunk: Chunk, chunk_origin_tiles: Vector2i, tile_size: int, biome_name: String
) -> Array[Node2D]:
	var spawned: Array[Node2D] = []
	if BUTTERFLY_BIOMES.has(biome_name):
		spawned.append_array(
			_spawn_species(
				parent, chunk, chunk_origin_tiles, tile_size, "butterfly_spawn",
				BUTTERFLY_SPECIES_POOL, MIN_BUTTERFLIES_PER_CHUNK, MAX_BUTTERFLIES_PER_CHUNK,
				AmbientFlyerMovement.new(BUTTERFLY_SPEED, BUTTERFLY_RADIUS, BUTTERFLY_INTERVAL),
				_butterfly_sprite
			)
		)
	if BIRD_BIOMES.has(biome_name):
		spawned.append_array(
			_spawn_species(
				parent, chunk, chunk_origin_tiles, tile_size, "bird_spawn",
				BIRD_SPECIES_POOL, MIN_BIRDS_PER_CHUNK, MAX_BIRDS_PER_CHUNK,
				AmbientFlyerMovement.new(BIRD_SPEED, BIRD_RADIUS, BIRD_INTERVAL),
				_bird_sprite
			)
		)
	return spawned


## Deterministically picks between min_count and max_count of this chunk's
## cells (ranked by a per-cell hash, so the chosen subset still reads as
## scattered rather than clustered in raster order -- same technique as
## FishRenderer._spawn_target_count), guaranteeing a qualifying chunk always
## shows at least min_count, never relying on an independent per-cell
## probability that could land on zero.
func _spawn_species(
	parent: Node2D,
	chunk: Chunk,
	chunk_origin_tiles: Vector2i,
	tile_size: int,
	salt: String,
	species_pool: Array[String],
	min_count: int,
	max_count: int,
	movement: AmbientFlyerMovement,
	sprite_generator,
) -> Array[Node2D]:
	var candidates: Array[Vector2i] = []
	for y in chunk.height:
		var global_y := chunk_origin_tiles.y + y
		for x in chunk.width:
			candidates.append(Vector2i(chunk_origin_tiles.x + x, global_y))

	candidates.sort_custom(func(a, b): return _spawn_rank(a.x, a.y, salt) < _spawn_rank(b.x, b.y, salt))

	var count_range := maxi(1, max_count - min_count + 1)
	var count_roll := absi(
		hash("%d_%d_%s_count" % [chunk_origin_tiles.x, chunk_origin_tiles.y, salt])
	) % count_range
	var wanted := clampi(min_count + count_roll, 0, mini(max_count, candidates.size()))

	var spawned: Array[Node2D] = []
	for i in wanted:
		var cell: Vector2i = candidates[i]
		var seed_value := absi(hash("%d_%d_%s_species" % [cell.x, cell.y, salt]))
		var species: String = species_pool[seed_value % species_pool.size()]
		var position := Vector2((cell.x + 0.5) * tile_size, (cell.y + 0.5) * tile_size)
		spawned.append(
			_build_marker(parent, species, position, seed_value, movement, sprite_generator)
		)
	return spawned


func _spawn_rank(global_x: int, global_y: int, salt: String) -> float:
	return float(absi(hash("%d_%d_%s" % [global_x, global_y, salt])) % 10000) / 10000.0


func _build_marker(
	parent: Node2D,
	species: String,
	position: Vector2,
	seed_value: int,
	movement: AmbientFlyerMovement,
	sprite_generator
) -> AmbientFlyerMarker:
	var marker := AmbientFlyerMarker.new()
	marker.texture = sprite_generator.generate_texture(species, seed_value)
	# Wing-beat frames, so the flyer actually flaps rather than gliding with
	# frozen wings (see AmbientFlyerMarker._animate_wings).
	if sprite_generator.has_method("generate_flap_textures"):
		marker.flap_frames = sprite_generator.generate_flap_textures(species, seed_value)
	if sprite_generator.has_method("generate_perched_texture"):
		marker.perched_frame = sprite_generator.generate_perched_texture(species, seed_value)
	# Size comes from two factors only: the art resolution, and the species'
	# own size relative to a fish (see FLYER_WORLD_SCALE). This used to also
	# take a `sprite_scale` argument from the caller, which is now dead --
	# leaving it would be a third, silent input to a number that has already
	# been hard to get right.
	marker.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE * FishRenderer.FISH_WORLD_SCALE * FLYER_WORLD_SCALE.get(species, 1.0)
	marker.position = position
	marker.home = position
	marker.wander_seed = seed_value
	marker.species = species
	marker.setup(movement)
	parent.add_child(marker)
	return marker
