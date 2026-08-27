extends RefCounted

## Visual promotion of a region's aggregate herbivore/predator population into
## individually-rendered markers (Phase 1 roadmap's "promotion rule"). Each
## marker now runs a real per-agent sense-decide-act AI loop (flee/hunt/graze/
## drink, temperament-driven; see CreatureMarker + CreatureBehavior/
## CreaturePerception/CreatureNeeds), not just idle-wandering.

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
## Squirrel joins forest ONLY -- unlike mouse's near-ubiquitous generalism,
## real tree squirrels are a genuine forest/woodland specialist: this is
## where the nut trees they depend on (TreeSpecies.is_nut) actually grow
## (see docs/concept/flora.md's disperser-vs-predator tension).
const HERBIVORE_SPECIES_POOL_BY_BIOME := {
	"grassland": ["herbivore", "herbivore", "herbivore", "boar", "horse", "mouse", "mouse", "deer", "nonvenomous_snake", "sheep"],
	"forest": ["boar", "boar", "boar", "herbivore", "mouse", "mouse", "deer", "nonvenomous_snake", "squirrel", "squirrel"],
	"desert": ["camel", "camel", "camel", "herbivore", "horse", "mouse", "nonvenomous_snake"],
	"tundra": ["reindeer", "reindeer", "reindeer", "herbivore", "mouse", "deer"],
	"rainforest": ["tapir", "tapir", "tapir", "herbivore", "mouse", "mouse", "nonvenomous_snake"],
	"mountain": ["goat", "goat", "goat", "herbivore", "mouse", "sheep", "sheep"],
}
## wolf joins grassland's and forest's pools -- real grey wolves are the
## classic temperate grassland/forest apex predator (see
## docs/concept/ecosystem_dynamics.md's Species roster section). An ordinary,
## ungated addition like deer/nonvenomous_snake, not gated by
## MIN_DIFFICULTY_TIER_BY_SPECIES.
const PREDATOR_SPECIES_POOL_BY_BIOME := {
	"grassland": ["predator", "predator", "predator", "lynx", "lion", "wolf"],
	"forest": ["lynx", "lynx", "lynx", "predator", "bear", "wolf"],
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
## Real illustrated art for species that have it (see IllustratedAnimalSprite,
## reported: "the procedural generated sprites are too bad... let's switch to
## illustrated ones") -- checked first for the spawn-time texture/scale/
## shadow anchor below; every other species still spawns from _animal_sprite
## exactly as before.
var _illustrated := preload("res://src/rendering/illustrated_animal_sprite.gd").new()


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
## How many markers one species' aggregate population is drawn as. Shared with
## the reconcile pass so "how many should be here" has exactly one answer.
func marker_count_for(population: float) -> int:
	return mini(int(roundi(population)), MAX_MARKERS_PER_SPECIES)


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
	difficulty_tier: int = RegionDifficulty.Tier.HARD,
	start_index: int = 0
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
			herbivore_population, herbivore_pool, 1, world, start_index
		)
	)
	spawned.append_array(
		_spawn_species(
			parent, chunk_coord, chunk_origin_tiles, chunk_size, tile_size,
			predator_population, predator_pool, 2, world, start_index
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
	world,
	start_index: int = 0
) -> Array[Node2D]:
	var count := marker_count_for(population)
	var spawned: Array[Node2D] = []
	# `start_index` lets a chunk TOP UP rather than rebuild (see
	# EarthChunkManager._reconcile_chunk_creatures): a newcomer takes the next
	# unused index, so it gets its own deterministic seed and spawn point
	# rather than landing on top of an animal already standing there.
	for i in range(start_index, count):
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
## `wander_seed`, when given, is used as-is instead of a fresh `randi()` roll --
## this is what lets a restored kept animal (see KeptAnimals /
## EarthChunkManager._restore_kept_animals) come back as the SAME individual
## rather than having its AnimalFitness phenotype (strength/agility/
## coat_vibrancy, all deterministic from this one seed) silently re-rolled on
## every reload. Every other caller (a wild spawn, a courtship offspring)
## leaves this at its default and keeps getting a fresh individual, exactly as
## before.
func spawn_single(
	parent: Node2D,
	species_name: String,
	position: Vector2,
	world = null,
	tile_size: int = 16,
	wander_seed: int = -1
) -> CreatureMarker:
	var seed_value := wander_seed if wander_seed >= 0 else randi()
	return _build_marker(parent, species_name, position, seed_value, world, tile_size)


func _build_marker(
	parent: Node2D,
	species_name: String,
	position: Vector2,
	wander_seed: int,
	world,
	tile_size: int
) -> CreatureMarker:
	var marker := CreatureMarker.new()
	if _illustrated.has_species(species_name):
		# The idle frame (see IllustratedAnimalSprite) -- CreatureMarker's own
		# _animation_step immediately takes over texture/scale afterward, but
		# the shadow below is built from THIS initial texture, so it has to
		# already be the real illustrated art, not a procedural placeholder
		# that would leave the shadow's silhouette mismatched with the
		# sprite shown from the very next frame on.
		marker.texture = _illustrated.generate_textures(species_name, "idle")[0]
		marker.scale = Vector2.ONE * _illustrated.marker_scale(species_name, "idle")
	else:
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
	# Contact shadow under the body: the creature's own sprite, flipped
	# upside down and anchored at its feet (see DropShadow.make_silhouette_
	# shadow) -- a real silhouette instead of one fixed oval every species
	# used to share. Drawn behind the marker's own sprite.
	var shadow := _drop_shadow.make_silhouette_shadow(
		marker.texture, _shadow_foot_offset_y(species_name)
	)
	marker.add_child(shadow)
	# set_shadow (not just add_child): a plain child would inherit the
	# marker's own rotation, tilting the shadow along with a turning
	# serpent's body -- see CreatureMarker.set_shadow. The shadow is
	# top_level (see set_shadow), so it doesn't inherit the marker's own
	# scale either -- passed explicitly here so the silhouette actually
	# matches the creature's real on-screen size (species scale + the
	# art-resolution downscale, see art_resolution.md) instead of the
	# oversized raw texture.
	marker.set_shadow(shadow, marker.scale)
	parent.add_child(marker)
	return marker


## Where a species' own feet actually meet the ground, in the marker's local
## Y (its texture is centered on the marker's origin, so canvas Y 0 is
## -HEIGHT/2 locally). Mirrors procedural_animal_sprite.gd's own `ground`
## calculation (body_y + half the body's height + the leg length, all canvas
## fractions -- see AnimalAnatomy's field doc comment) instead of guessing a
## fixed half-height offset: that generic guess put the shadow visibly below
## a boar's actual hooves, reading as the creature floating a few pixels
## above its own shadow (reported: "the shadow is a few pixel below sprite
## so it looks like it's floating").
func _shadow_foot_offset_y(species_name: String) -> float:
	if _illustrated.has_species(species_name):
		return _illustrated.ground_offset_y()
	var profile := AnimalAnatomy.profile_for(species_name)
	var h := float(ProceduralAnimalSprite.HEIGHT)
	var ground_y: float = h * (float(profile.body_y) + float(profile.body_height) * 0.5 + float(profile.leg_length))
	return ground_y - h * 0.5


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
