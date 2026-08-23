extends RefCounted

const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const FishRenderer = preload("res://src/rendering/fish_renderer.gd")

## How big each flyer is in the world, expressed as a MULTIPLE OF A FISH.
## Sizing these against a concrete, visible reference rather than in the
## abstract is what finally made them read correctly: a butterfly is half a
## fish, a sparrow about one fish, a robin about one and a half, and the
## kingfisher the largest.
##
## Worth knowing before tuning these: for a long stretch these numbers had
## NO effect at all, because _build_marker overwrote the computed scale a
## few lines after calculating it. Several rounds of "still too big/small"
## were spent adjusting a table that never reached the screen. If a change
## here appears to do nothing, suspect the wiring before the value.
const FLYER_WORLD_SCALE := {
	"sparrow": 1.0,
	"robin": 1.5,
	"kingfisher": 1.7,
	"monarch": 0.5,
	"swallowtail": 0.55,
	"blue_morpho": 0.6,
	"bee": 0.3,
	# The smallest thing in the air. A fly is a speck with wings.
	"fly": 0.2,
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
const FlyerDiet = preload("res://src/gameplay/flyer_diet.gd")
const GroundForageBehavior = preload("res://src/gameplay/ground_forage_behavior.gd")

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
##
## Bees are a SEPARATE pool from the true butterflies, each with their own
## guaranteed per-chunk minimum (see MIN_BEES_PER_CHUNK below) -- they used
## to ride the same shared pool as butterflies, which meant every bee that
## rolled was one fewer butterfly out of the same fixed MIN..MAX budget,
## silently halving true butterfly sightings once bees joined (reported:
## "there are much less butterflies and bees"). Splitting the pools makes
## bees a genuine ADDITION to the meadow's pollinator presence instead of a
## slice out of it.
const TRUE_BUTTERFLY_SPECIES_POOL: Array[String] = ["monarch", "swallowtail", "blue_morpho"]
const BEE_SPECIES_POOL: Array[String] = ["bee"]
## Kept for callers that only care "is this species a pollinator flyer"
## (spawn-count bookkeeping, tests) -- the union of both pools above.
const BUTTERFLY_SPECIES_POOL: Array[String] = ["monarch", "swallowtail", "blue_morpho", "bee"]
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
## Bees' own budget, additive to the butterfly one above -- deliberately
## smaller (bees read as a background buzz, not the headline presence).
const MIN_BEES_PER_CHUNK := 1
const MAX_BEES_PER_CHUNK := 2
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
	parent: Node2D,
	chunk: Chunk,
	chunk_origin_tiles: Vector2i,
	tile_size: int,
	biome_name: String,
	scent_multiplier: float = 1.0,
	scent_world = null
) -> Array[Node2D]:
	var spawned: Array[Node2D] = []
	if BUTTERFLY_BIOMES.has(biome_name):
		# Pollinators are drawn to flowers: a chunk thick with blooms hatches
		# proportionally more pollinators than bare grass (see
		# ScentField.pollinator_spawn_multiplier, which saturates so a big
		# meadow can never spawn an unbounded swarm). Birds below are
		# deliberately NOT scaled -- they aren't pollinators.
		#
		# Butterflies and bees are spawned from separate pools/budgets (see
		# TRUE_BUTTERFLY_SPECIES_POOL/BEE_SPECIES_POOL) -- a bee is an
		# ADDITION to a meadow's pollinator presence, not drawn out of the
		# butterfly count.
		var scented_butterfly_min := int(round(float(MIN_BUTTERFLIES_PER_CHUNK) * scent_multiplier))
		var scented_butterfly_max := int(round(float(MAX_BUTTERFLIES_PER_CHUNK) * scent_multiplier))
		spawned.append_array(
			_spawn_species(
				parent, chunk, chunk_origin_tiles, tile_size, "butterfly_spawn",
				TRUE_BUTTERFLY_SPECIES_POOL, scented_butterfly_min, scented_butterfly_max,
				AmbientFlyerMovement.new(BUTTERFLY_SPEED, BUTTERFLY_RADIUS, BUTTERFLY_INTERVAL),
				_butterfly_sprite,
				scent_world
			)
		)
		var scented_bee_min := int(round(float(MIN_BEES_PER_CHUNK) * scent_multiplier))
		var scented_bee_max := int(round(float(MAX_BEES_PER_CHUNK) * scent_multiplier))
		spawned.append_array(
			_spawn_species(
				parent, chunk, chunk_origin_tiles, tile_size, "bee_spawn",
				BEE_SPECIES_POOL, scented_bee_min, scented_bee_max,
				AmbientFlyerMovement.new(BUTTERFLY_SPEED, BUTTERFLY_RADIUS, BUTTERFLY_INTERVAL),
				_butterfly_sprite,
				scent_world
			)
		)
	if BIRD_BIOMES.has(biome_name):
		# Birds are passed the same world the pollinators get. It is NOT a
		# scent world for them -- _build_marker gates that on the diet table,
		# and no bird drinks nectar -- it is what a robin queries for
		# earthworms (see FlyerDiet / docs/concept/soil_fauna.md). Songbirds
		# used to be handed nothing at all, which is why they had literally no
		# behaviour beyond home-tethered drift.
		spawned.append_array(
			_spawn_species(
				parent, chunk, chunk_origin_tiles, tile_size, "bird_spawn",
				BIRD_SPECIES_POOL, MIN_BIRDS_PER_CHUNK, MAX_BIRDS_PER_CHUNK,
				AmbientFlyerMovement.new(BIRD_SPEED, BIRD_RADIUS, BIRD_INTERVAL),
				_bird_sprite,
				scent_world
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
	scent_world = null,
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
			_build_marker(parent, species, position, seed_value, movement, sprite_generator, scent_world)
		)
	return spawned


func _spawn_rank(global_x: int, global_y: int, salt: String) -> float:
	return float(absi(hash("%d_%d_%s" % [global_x, global_y, salt])) % 10000) / 10000.0


## Spawns ONE flyer -- the offspring of a courting pair (see Courtship).
##
## Goes through the same `_build_marker` every other flyer does, so a
## butterfly born in front of the player is in every respect an ordinary
## butterfly: same art, same movement, same diet wiring, and it can court in
## its turn.
## The most flyers one chunk is ever meant to carry.
##
## The spawn pass fills a chunk to somewhere between its MIN and MAX per
## species; courtship can then add more (see Courtship), and without a
## ceiling that is a population with births and no bound -- measured climbing
## steadily in a single session, which is precisely how the deer explosion
## started. A meadow supports what it supports.
static func max_flyers_per_chunk() -> int:
	return MAX_BUTTERFLIES_PER_CHUNK + MAX_BEES_PER_CHUNK + MAX_BIRDS_PER_CHUNK


func spawn_offspring(
	parent: Node2D, species: String, position: Vector2, seed_value: int, scent_world = null
) -> AmbientFlyerMarker:
	# Art and flight come from the SPECIES, never from an assumption about
	# who courts. This hardcoded the butterfly pair on the reasoning that
	# "courtship only applies to pollinators" -- which nothing enforced, and
	# sparrows court sparrows, so a sparrow chick came out with monarch wings:
	# it flew like a butterfly and looked like one while the hover panel said
	# "sparrow" and it went off to eat seeds (reported exactly that way).
	var is_bird := BIRD_SPECIES_POOL.has(species)
	var movement := (
		AmbientFlyerMovement.new(BIRD_SPEED, BIRD_RADIUS, BIRD_INTERVAL)
		if is_bird
		else AmbientFlyerMovement.new(BUTTERFLY_SPEED, BUTTERFLY_RADIUS, BUTTERFLY_INTERVAL)
	)
	var offspring := _build_marker(
		parent, species, position, seed_value, movement,
		_bird_sprite if is_bird else _butterfly_sprite,
		scent_world
	)
	# Born, not spawned: it starts at the beginning of its life and takes the
	# full week to grow up (see LifeCycle), unlike the adults the world seeds
	# a meadow with.
	offspring.begin_life()
	return offspring


## Builds one flyer at a position, for callers that place their own rather
## than spawning a chunk's worth.
##
## Flies are the case this exists for: they belong to a rotting thing rather
## than to a chunk, so they are spawned where the rot is (see
## EarthChunkManager.step_flies) instead of scattered over a cell.
func build_flyer(parent: Node2D, species: String, position: Vector2, seed_value: int) -> AmbientFlyerMarker:
	return _build_marker(
		parent,
		species,
		position,
		seed_value,
		AmbientFlyerMovement.new(BUTTERFLY_SPEED, BUTTERFLY_RADIUS, BUTTERFLY_INTERVAL),
		_butterfly_sprite
	)


func _build_marker(
	parent: Node2D,
	species: String,
	position: Vector2,
	seed_value: int,
	movement: AmbientFlyerMovement,
	sprite_generator,
	scent_world = null
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
	# Who to tell when a courting pair produces young (see Courtship). Every
	# caller passes the chunk manager as `scent_world`; courtship needs the
	# same object, but for spawning rather than for smelling, so it is named
	# for what it is used for.
	marker.courtship_world = scent_world
	# Remembered before anything shrinks it, so a juvenile grows toward this
	# species' own adult size (see AmbientFlyerMarker._step_growing).
	marker.set_adult_scale(marker.scale)
	marker.setup(movement)
	# What this flyer is wired to feed on comes from the DIET TABLE, not from
	# which spawn call it came out of (see FlyerDiet /
	# docs/concept/soil_fauna.md). Every caller now passes the same world; the
	# table decides which parts of it a given species can even see, which is
	# what makes "sparrows don't hunt worms" structural rather than a branch
	# somewhere inside the shared marker.
	#
	# Nectar: pollinators only. Birds get null here and keep flying blind past
	# every flower, exactly as before.
	if FlyerDiet.eats(species, FlyerDiet.FOOD_NECTAR):
		marker.scent_world = scent_world
	# Seed: sparrows. Flowers whose bloom is over have gone to seed (see
	# FlowerPatch.seed_cells / concept/flora.md), so the same meadow that
	# feeds pollinators in season feeds granivores out of it. This is the
	# "parallel seed_world line" the worm wiring below anticipated -- and
	# nothing else had to move, exactly as predicted.
	if FlyerDiet.eats(species, FlyerDiet.FOOD_SEEDS) and scent_world != null:
		marker.seed_world = scent_world
		if marker.ground_forage == null:
			marker.ground_forage = GroundForageBehavior.new()
		if sprite_generator.has_method("generate_pecking_texture"):
			marker.peck_frame = sprite_generator.generate_pecking_texture(species, seed_value)
	# Worms: robins only.
	if FlyerDiet.eats(species, FlyerDiet.FOOD_WORMS) and scent_world != null:
		marker.worm_world = scent_world
		marker.ground_forage = GroundForageBehavior.new()
		if sprite_generator.has_method("generate_pecking_texture"):
			marker.peck_frame = sprite_generator.generate_pecking_texture(species, seed_value)
	# Fallen tree fruit: robins again (see FlyerDiet -- a second diet entry,
	# not a new species), bird endozoochory (see SeedEndozoochory /
	# docs/concept/flora.md#bird-endozoochory). Shares ground_forage with
	# worm-hunting above rather than needing a second state machine -- a bird
	# only ever pursues one prey at a time regardless of how many foods are
	# on its diet.
	# Sparrows qualify here too now (walnuts), not just robins -- which fruit
	# each takes is decided per species in FlyerDiet.eats_fruit_species.
	if FlyerDiet.eats(species, FlyerDiet.FOOD_FRUIT) and scent_world != null:
		marker.fruit_world = scent_world
		if marker.ground_forage == null:
			marker.ground_forage = GroundForageBehavior.new()
		if marker.peck_frame == null and sprite_generator.has_method("generate_pecking_texture"):
			marker.peck_frame = sprite_generator.generate_pecking_texture(species, seed_value)
	parent.add_child(marker)
	return marker
