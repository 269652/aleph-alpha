extends RefCounted

## Placeholder visual promotion of a region's aggregate herbivore/predator
## population into individually-rendered markers (Phase 1 roadmap's
## "promotion rule"). Each marker idle-wanders (see CreatureMarker) but has
## no real AI/pathfinding/behavior yet.

const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const AnimalAnatomy = preload("res://src/rendering/animal_anatomy.gd")
const ProceduralAnimalSprite = preload("res://src/rendering/procedural_animal_sprite.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const DropShadow = preload("res://src/rendering/drop_shadow.gd")
const RegionDifficulty = preload("res://src/world/region_difficulty.gd")

const HERBIVORE_COLOR := Color(0.65, 0.5, 0.2)
const BOAR_COLOR := Color(0.25, 0.18, 0.12)
const PREDATOR_COLOR := Color(0.55, 0.08, 0.08)
const LYNX_COLOR := Color(0.45, 0.48, 0.55)

## Species variety within each ecosystem role (see CreatureInfo's doc comment
## on boar/lynx): a promoted herbivore-role individual is usually a plain
## herbivore but sometimes a boar, deterministically per (chunk, index) --
## weighted by simple repetition, not a probability table. Same idea for
## predator-role individuals and lynx. This pair is also the fail-safe
## default pool for any biome not present in the *_BY_BIOME maps below (see
## spawn_creatures's biome_name doc), matching today's pre-biome behavior.
const HERBIVORE_SPECIES_POOL := ["herbivore", "herbivore", "herbivore", "boar"]
const PREDATOR_SPECIES_POOL := ["predator", "predator", "predator", "lynx"]

## Per-biome species pools (Phase 1's "boars live where boars thrive" pillar,
## realized): which species a promoted herbivore/predator-role individual is
## drawn from now depends on the chunk's dominant biome (see
## BiomeClassifier.dominant_biome), not one global pool -- so a desert and a
## rainforest actually look like different ecosystems instead of drawing from
## the same 4 species. grassland's entry is today's pre-biome pool unchanged
## (deer-dominant herbivores, wolf-dominant predators), now made explicit as
## grassland's own identity. Biomes with no entry here (currently just ocean,
## whose vegetation carrying capacity stays 0 -- see
## VegetationGrowthModel.CARRYING_CAPACITY_BY_BIOME -- so population always
## rounds to 0 there regardless of pool) fall back to the generic
## HERBIVORE_SPECIES_POOL/PREDATOR_SPECIES_POOL above.
## Mouse joins every non-ocean biome's pool (real mice are near-ubiquitous
## generalists, not a biome specialist like the others); horse joins only
## grassland and desert (real wild/feral horses are a grassland/dry-steppe
## grazer) -- see docs/concept/ecosystem_dynamics.md's Species roster section.
## Deer/nonvenomous_snake join alongside the existing specialists (ordinary,
## ungated roster additions -- real deer are a common temperate grazer, real
## non-venomous snakes are widespread). Bear/lion/venomous_snake also join
## here, but are gated by MIN_DIFFICULTY_TIER_BY_SPECIES below -- being
## listed in a biome's pool means "ecologically plausible there", not
## "always spawns there" for the dangerous three (see
## docs/concept/ecosystem_dynamics.md's Region difficulty section).
const HERBIVORE_SPECIES_POOL_BY_BIOME := {
	"grassland": ["herbivore", "herbivore", "herbivore", "boar", "horse", "mouse", "mouse", "deer", "nonvenomous_snake"],
	"forest": ["boar", "boar", "boar", "herbivore", "mouse", "mouse", "deer", "nonvenomous_snake"],
	"desert": ["camel", "camel", "camel", "herbivore", "horse", "mouse", "nonvenomous_snake"],
	"tundra": ["reindeer", "reindeer", "reindeer", "herbivore", "mouse", "deer"],
	"rainforest": ["tapir", "tapir", "tapir", "herbivore", "mouse", "mouse", "nonvenomous_snake"],
	"mountain": ["goat", "goat", "goat", "herbivore", "mouse"],
}
const PREDATOR_SPECIES_POOL_BY_BIOME := {
	"grassland": ["predator", "predator", "predator", "lynx", "lion"],
	"forest": ["lynx", "lynx", "lynx", "predator", "bear"],
	"desert": ["jackal", "jackal", "jackal", "predator", "lion", "venomous_snake"],
	"tundra": ["arctic_fox", "arctic_fox", "arctic_fox", "predator", "bear"],
	"rainforest": ["jaguar", "jaguar", "jaguar", "predator", "venomous_snake"],
	"mountain": ["mountain_lion", "mountain_lion", "mountain_lion", "predator"],
}

## The three genuinely dangerous new additions -- everything else in the
## roster (including the original 12 species, mice, horses, deer,
## nonvenomous_snake) has no entry here and defaults to Tier.EASY (always
## available wherever its biome already allows), so this is additive to the
## existing roster, not a retrofit/rebalance of it. See
## docs/concept/ecosystem_dynamics.md#region-difficulty-gating-the-roster-by-player-readiness.
const MIN_DIFFICULTY_TIER_BY_SPECIES := {
	"bear": RegionDifficulty.Tier.HARD,
	"lion": RegionDifficulty.Tier.HARD,
	"venomous_snake": RegionDifficulty.Tier.HARD,
}

const SPECIES_COLORS := {
	"herbivore": HERBIVORE_COLOR,
	"boar": BOAR_COLOR,
	"predator": PREDATOR_COLOR,
	"lynx": LYNX_COLOR,
}

## A region's aggregate population can be arbitrarily large; capped so one
## dense chunk can't spawn hundreds of nodes. Verified by
## test_caps_marker_count_for_a_very_large_population.
const MAX_MARKERS_PER_SPECIES := 12

var _animal_sprite := ProceduralAnimalSprite.new()
var _drop_shadow := DropShadow.new()


## Spawns placeholder marker nodes (as children of `parent`) for a region's
## rounded herbivore/predator population counts, at positions deterministic
## for (chunk_coord, species, index) so revisiting a region looks stable
## rather than re-randomizing. Each individual gets species-shaped procedural
## pixel art (see ProceduralAnimalSprite -- boars look like boars, lynx like
## lynx) with per-individual seeded shade variation. Returns the spawned nodes so the caller
## can free them again when the region unloads.
## `world` (duck-typed biome_at_global) is handed to each marker so it can
## sense terrain/threats/prey and run full AI; pass null (default) for callers
## that only need static placeholders (e.g. isolated rendering tests).
## `biome_name` (default "", appended so every pre-existing call site keeps
## compiling unchanged) picks this chunk's species pool from
## HERBIVORE_SPECIES_POOL_BY_BIOME/PREDATOR_SPECIES_POOL_BY_BIOME; empty or
## unmapped falls back to the generic HERBIVORE_SPECIES_POOL/
## PREDATOR_SPECIES_POOL, i.e. today's pre-biome behavior.
## `difficulty_tier` (default RegionDifficulty.Tier.HARD, the most
## permissive tier, so every pre-existing call site keeps behaving exactly
## as before) filters out any species whose MIN_DIFFICULTY_TIER_BY_SPECIES
## exceeds it -- see docs/concept/ecosystem_dynamics.md's Region difficulty
## section.
func spawn_creatures(
	parent: Node2D,
	chunk_coord: Vector2i,
	chunk_origin_tiles: Vector2i,
	chunk_size: int,
	tile_size: int,
	herbivore_population: float,
	predator_population: float,
	world = null,
	biome_name: String = "",
	difficulty_tier: int = RegionDifficulty.Tier.HARD
) -> Array[Node2D]:
	var herbivore_pool := _allowed_pool(
		HERBIVORE_SPECIES_POOL_BY_BIOME.get(biome_name, HERBIVORE_SPECIES_POOL), difficulty_tier
	)
	var predator_pool := _allowed_pool(
		PREDATOR_SPECIES_POOL_BY_BIOME.get(biome_name, PREDATOR_SPECIES_POOL), difficulty_tier
	)

	var spawned: Array[Node2D] = []
	spawned.append_array(
		_spawn_species(
			parent, chunk_coord, chunk_origin_tiles, chunk_size, tile_size,
			herbivore_population, herbivore_pool, 1, world
		)
	)
	spawned.append_array(
		_spawn_species(
			parent, chunk_coord, chunk_origin_tiles, chunk_size, tile_size,
			predator_population, predator_pool, 2, world
		)
	)
	return spawned


## Drops any pool entry whose own minimum difficulty tier exceeds the
## region's current tier -- e.g. "bear" is filtered out of forest's pool
## below Tier.HARD. Species with no MIN_DIFFICULTY_TIER_BY_SPECIES entry
## default to Tier.EASY (0), so they're never filtered.
func _allowed_pool(pool: Array, difficulty_tier: int) -> Array:
	var allowed: Array = []
	for species in pool:
		if MIN_DIFFICULTY_TIER_BY_SPECIES.get(species, RegionDifficulty.Tier.EASY) <= difficulty_tier:
			allowed.append(species)
	return allowed


func _spawn_species(
	parent: Node2D,
	chunk_coord: Vector2i,
	chunk_origin_tiles: Vector2i,
	chunk_size: int,
	tile_size: int,
	population: float,
	species_pool: Array,
	species_salt: int,
	world
) -> Array[Node2D]:
	var count := mini(int(roundi(population)), MAX_MARKERS_PER_SPECIES)
	var spawned: Array[Node2D] = []
	for i in count:
		var wander_seed := hash("%d_%d_%d_%d_wander" % [chunk_coord.x, chunk_coord.y, species_salt, i])
		var species_seed := absi(hash("%d_%d_%d_%d_species" % [chunk_coord.x, chunk_coord.y, species_salt, i]))
		var species_name: String = species_pool[species_seed % species_pool.size()]
		var position := _deterministic_position(
			chunk_coord, chunk_origin_tiles, chunk_size, tile_size, species_salt, i
		)
		spawned.append(
			_build_marker(parent, species_name, position, wander_seed, world, tile_size)
		)
	return spawned


## Spawns exactly one marker at an explicit position, not tied to chunk-based
## population promotion -- for on-demand spawning (see DevConsole's /spawn
## command), where the caller picks where and doesn't care about deterministic
## per-chunk placement. Non-deterministic (randi()) wander seed: unlike the
## world's own creatures, a debug-spawned individual isn't expected to look
## the same across sessions. `tile_size` only affects CreatureMarker's own
## terrain sensing (see setup()), not this marker's position.
func spawn_single(
	parent: Node2D, species_name: String, position: Vector2, world = null, tile_size: int = 16
) -> CreatureMarker:
	return _build_marker(parent, species_name, position, randi(), world, tile_size)


func _build_marker(
	parent: Node2D,
	species_name: String,
	position: Vector2,
	wander_seed: int,
	world,
	tile_size: int
) -> CreatureMarker:
	var marker := CreatureMarker.new()
	marker.texture = _animal_sprite.generate_texture(species_name, wander_seed)
	# The animal art is authored DETAIL_MULTIPLIER times oversized for pixel
	# detail; scaling it back down keeps the creature's world footprint
	# unchanged (see docs/concept/art_resolution.md).
	# Scaled by the species' real relative size as well as the art
	# resolution -- a horse must tower over a mouse even though both are
	# drawn on the same canvas (see AnimalAnatomy.world_scale).
	var species_scale: float = AnimalAnatomy.profile_for(species_name).world_scale
	marker.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE * species_scale
	marker.position = position
	marker.home = position
	marker.wander_seed = wander_seed
	marker.info = CreatureInfo.new(species_name, wander_seed)
	marker.setup(world, tile_size)
	# Contact shadow under the body (draws behind the marker's own sprite).
	marker.add_child(
		_drop_shadow.make_shadow(
			int(ProceduralAnimalSprite.WIDTH * 0.7), ProceduralAnimalSprite.HEIGHT * 0.5 - 1.0
		)
	)
	parent.add_child(marker)
	return marker


func _deterministic_position(
	chunk_coord: Vector2i,
	chunk_origin_tiles: Vector2i,
	chunk_size: int,
	tile_size: int,
	species_salt: int,
	index: int
) -> Vector2:
	var seed_value := hash("%d_%d_%d_%d" % [chunk_coord.x, chunk_coord.y, species_salt, index])
	var local_x := seed_value % chunk_size
	var local_y := (seed_value / chunk_size) % chunk_size
	return Vector2(
		(chunk_origin_tiles.x + local_x + 0.5) * tile_size,
		(chunk_origin_tiles.y + local_y + 0.5) * tile_size
	)
