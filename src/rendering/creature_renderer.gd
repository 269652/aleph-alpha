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
const PopulationMarkers = preload("res://src/world/population_markers.gd")

const HERBIVORE_COLOR := Color(0.65, 0.5, 0.2)
const BOAR_COLOR := Color(0.25, 0.18, 0.12)
const PREDATOR_COLOR := Color(0.55, 0.08, 0.08)
const LYNX_COLOR := Color(0.45, 0.48, 0.55)

## Species variety within each ecosystem role (see CreatureInfo's doc comment
## on boar/lynx): a promoted herbivore-role individual is usually a deer but
## sometimes a boar, deterministically per (chunk, index) -- weighted by
## simple repetition, not a probability table. Same idea for predator-role
## individuals and jackal. This pair is also the fail-safe default pool for
## any biome not present in the *_BY_BIOME maps below (see spawn_creatures's
## biome_name doc) -- in practice only ocean, whose vegetation carrying
## capacity is 0 so nothing is ever promoted there, and the empty default
## biome_name used by isolated callers. Two of the roster's most widespread
## species per role, making no biome claim of their own.
##
## These pools used to read ["herbivore" x3, "boar"] / ["predator" x3,
## "lynx"]. "herbivore" and "predator" are this project's own ANONYMOUS
## STAND-INS, not species -- ProceduralAnimalSprite.SPECIES_SHAPE_FAMILY maps
## "herbivore" to deer_shape and "predator" to wolf_shape, from before deer
## and wolf existed as real named species with real illustrated art. Naming
## those two never removed the stand-ins from the pools, so a promoted
## individual could still reach the creature panel as a nameless "Herbivore
## Lv.5" standing next to a "Boar Lv.1" (CreatureInfo.display_name is just
## the species id capitalized). They are retired from SPAWNING here, but
## deliberately KEPT as data-table keys everywhere else: AnimalAnatomy
## .profile_for falls back to _PROFILES["herbivore"] and ProceduralAnimalSprite
## resolves any unknown species to "herbivore", so those entries are the
## never-crash-on-an-odd-id default and must not be deleted.
const HERBIVORE_SPECIES_POOL := ["deer", "deer", "deer", "boar"]
const PREDATOR_SPECIES_POOL := ["lynx", "lynx", "lynx", "jackal"]

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
## Sheep already grazed grassland and mountain; it now joins forest too,
## alongside deer -- real prey for forest's own wolves below, not just a
## general-purpose grazer (see docs/concept/ecosystem_dynamics.md's Species
## roster section).
## Deer take over grassland's dominant grazer slot from the retired
## "herbivore" placeholder they were always the stand-in for (deer_shape),
## and bring real illustrated art with them; every other biome simply drops
## its single placeholder entry, each already having a dominant named
## specialist x3 plus named fillers.
## Squirrel joins forest ONLY -- unlike mouse's near-ubiquitous generalism,
## real tree squirrels are a genuine forest/woodland specialist: this is
## where the nut trees they depend on (TreeSpecies.is_nut) actually grow
## (see docs/concept/flora.md's disperser-vs-predator tension).
##
## grassland/forest carry extra "boar" entries beyond their original ratio
## (docs/concept/ecosystem_dynamics.md, "Steady combat near spawn") -- see
## SPAWN_REACHABLE_BIOMES and MIN_FIGHT_CAPABLE_HERBIVORE_FRACTION just
## below. Every real spawn candidate lands in one of these two biomes, and
## boar is the only herbivore-role species with an aggressive temperament
## (CreatureInfo.TEMPERAMENT_BY_SPECIES), so it is the one lever that raises
## how often the single animal a player meets near spawn will fight, without
## touching the predator trophic pyramid, the difficulty-tier gate, or a
## single other species' own documented temperament. Appended, never
## removed, so every species already promotable here still is, at its
## original relative weight against every OTHER calm filler. Counts (8 more
## for grassland, 4 more for forest) are the minimum that clears the floor
## exactly -- test_every_spawn_reachable_biomes_herbivore_pool_is_at_least_
## half_fight_capable pins both at exactly 9/18 and 7/14.
const HERBIVORE_SPECIES_POOL_BY_BIOME := {
	"grassland": [
		"deer", "deer", "deer", "boar", "horse", "mouse", "mouse", "nonvenomous_snake", "sheep", "alpaca",
		"boar", "boar", "boar", "boar", "boar", "boar", "boar", "boar",
		# Goblin (docs/concept/monsters.md, entry 10): "way more enemies...
		# you should not have to walk far", answered the same lever boar
		# already is -- more herbivore-role fighters, not a predator-density
		# change (see ecosystem_dynamics.md's spawn safe-zone section).
		"goblin", "goblin", "goblin", "goblin",
	],
	"forest": [
		"boar", "boar", "boar", "mouse", "mouse", "deer", "sheep", "nonvenomous_snake", "squirrel", "squirrel",
		"boar", "boar", "boar", "boar",
		"goblin", "goblin", "goblin",
	],
	"desert": ["camel", "camel", "camel", "horse", "mouse", "nonvenomous_snake"],
	"tundra": ["reindeer", "reindeer", "reindeer", "mouse", "deer"],
	"rainforest": ["tapir", "tapir", "tapir", "mouse", "mouse", "nonvenomous_snake"],
	"mountain": ["goat", "goat", "goat", "mouse", "sheep", "sheep", "alpaca"],
}

## Every real spawn candidate (World._spawn_candidate_acceptable) is a warm,
## dry-land, non-mountain river bank drawn from RiverCatalog's ten
## Central-European rivers, all 47-54 deg N -- test_world_spawn_location.gd
## already pins "warm"/"not ocean or mountain" as a property every candidate
## has. BiomeClassifier.classify can only resolve that combination to
## "grassland" or "forest": these latitudes never reach the COLD_TEMPERATURE
## band tundra needs, and never clear the HOT_TEMPERATURE band desert/
## rainforest need. So "combat steady from the get go" is a claim about
## exactly these two biomes -- see docs/concept/ecosystem_dynamics.md,
## "Steady combat near spawn".
const SPAWN_REACHABLE_BIOMES: Array[String] = ["grassland", "forest"]

## The least a spawn-reachable biome's herbivore-role pool can be and still
## call meeting something in it "steady combat": a coin flip, PER MARKER
## drawn (PopulationMarkers.count_for) -- below half, more of the markers a
## chunk draws from this pool are calm than fight-capable. Not pushed
## higher: that would crowd out the calm-grazer variety the pool also
## exists for, and half is the natural, non-arbitrary inflection point
## between the two. Applies only to SPAWN_REACHABLE_BIOMES -- see that
## constant's own doc comment for why the other four biomes are
## deliberately left alone. See SPAWN_REACHABLE_POPULATION_MULTIPLIER below
## for the separate, larger lever controlling how MANY markers a chunk
## draws in the first place.
const MIN_FIGHT_CAPABLE_HERBIVORE_FRACTION := 0.5

## The real bottleneck behind "no encounters while walking"
## (docs/concept/ecosystem_dynamics.md's "More wildlife where you'll
## actually meet it"): raw population COUNT, not which species a drawn
## marker is -- the fraction above only ever decided the latter, and can't
## rescue a chunk the population roll never gave anything to in the first
## place. Applied to herbivore (and, derived from it, predator) carrying
## capacity in EcosystemSimulation.add_region, for SPAWN_REACHABLE_BIOMES
## chunks only. Real measured density before this existed: 0.40-1.26
## herbivores/chunk (population_markers.gd's own doc comment) -- below
## PopulationMarkers.count_for's guaranteed-marker threshold (1.0) at the
## sparse end. 5x pushes that same range to 2.0-6.3, clearing the threshold
## with real margin even at the sparsest measured chunk (0.40 * 5.0 = 2.0),
## not just barely. Pinned by
## test_spawn_reachable_population_multiplier_clears_the_guaranteed_
## marker_threshold_with_margin.
const SPAWN_REACHABLE_POPULATION_MULTIPLIER := 5.0

## "I still don't encounter any goblin settlements or groups of monsters"
## (docs/concept/ecosystem_dynamics.md's "Goblins raiding together"):
## every density fix above still draws each marker INDEPENDENTLY, so Goblin
## was just one more entry in the per-index pool draw -- never a readable
## group. A deterministic per-CHUNK roll (one hash of chunk_coord, unlike
## MOUND_CHANCE/HIVE_CHANCE's per-cell roll -- a camp is a property of the
## whole chunk), scoped to SPAWN_REACHABLE_BIOMES and gated off on
## spawn-safe chunks by _is_goblin_camp_chunk below. ~16 non-safe
## spawn-reachable chunks sit in a loaded neighbourhood (measured directly)
## -- 0.15 means an expected ~2.4 camps typically within reach: findable,
## not tripped over on every excursion. Pinned by
## test_goblin_camp_chance_is_fifteen_percent and its own statistical
## verification test.
const GOBLIN_CAMP_CHANCE := 0.15

## How far (in tiles) a camp's goblins scatter from their shared anchor
## point -- close enough to read as "together," never on the exact same
## tile. 3 tiles (48px at TILE_SIZE=16) keeps a camp tight and readable
## on screen without every goblin standing on the same pixel.
const CAMP_CLUSTER_RADIUS_TILES := 3

## Wolf joins forest only (real wolves are the classic temperate/boreal
## forest apex predator, and this project's own dominant-species-per-biome
## pattern -- jackal/desert, arctic_fox/tundra, jaguar/rainforest,
## mountain_lion/mountain -- had left forest as the one biome without a
## dedicated named predator of its own; see
## docs/concept/ecosystem_dynamics.md's Species roster section). Purely
## additive to forest's existing lynx dominance/bear entries, not a
## replacement of them -- lynx keeps its own real habitat here.
## Jackals take grassland's dominant predator slot from the retired
## "predator" placeholder. Real golden jackals are an open grassland/steppe
## canid across Eurasia and Africa, not only a desert one -- an ordinary
## roster placement, the same kind as mouse joining every biome. Wolf is NOT
## used here despite being what "predator" was drawn as: wolves are
## forest-exclusive by design (see docs/concept/ecosystem_dynamics.md's
## "Forest gets its own named predator"), and reversing that would be a
## design decision, not a placeholder cleanup.
const PREDATOR_SPECIES_POOL_BY_BIOME := {
	# Nachzehrer (docs/concept/monsters.md, entry 11) joins grassland and
	# forest, one slot each -- rare, like Alp's own single forest slot, not
	# a second common fighter (that job belongs to the herbivore-role pool
	# above, see Goblin).
	"grassland": ["jackal", "jackal", "jackal", "lynx", "lion", "nachzehrer"],
	"forest": ["lynx", "lynx", "lynx", "wolf", "wolf", "bear", "alp", "nachzehrer"],
	"desert": ["jackal", "jackal", "jackal", "lion", "venomous_snake"],
	"tundra": ["arctic_fox", "arctic_fox", "arctic_fox", "bear"],
	"rainforest": ["jaguar", "jaguar", "jaguar", "venomous_snake", "curupira"],
	"mountain": ["mountain_lion", "mountain_lion", "mountain_lion"],
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

## A second, much smaller radius than any RegionDifficulty tier -- the
## literal spawn clearing (docs/concept/ecosystem_dynamics.md's "A safe
## clearing at the literal spawn point"). A chunk within this many chunks
## (Chebyshev; see EarthChunkManager._is_spawn_safe_chunk) of the spawn
## chunk drops every hostile species from both pools via _allowed_pool's
## spawn_safe flag below -- orthogonal to difficulty_tier, which stays
## unaffected.
const SPAWN_SAFE_RADIUS_CHUNKS := 1

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
## `spawn_safe` (default false, so every pre-existing call site keeps
## behaving exactly as before) additionally drops every HOSTILE species
## (is_predator or AGGRESSIVE temperament) from both pools -- see
## SPAWN_SAFE_RADIUS_CHUNKS above. Orthogonal to difficulty_tier: a chunk
## can be EASY difficulty and still spawn a hostile boar/jackal outside the
## much smaller spawn-safe radius.
## How many markers one species' aggregate population is drawn as. Shared
## with the reconcile pass so "how many should be here" has exactly one
## answer -- which is why both callers must pass the SAME chunk and salt, or
## a chunk would gain and lose an animal every time it streamed.
##
## `PopulationMarkers.count_for` keeps the fractional part as a seeded
## chance rather than rounding it away. Measured in a real --solo launch:
## predator density around spawn is 0.03..0.10 per chunk, which summed to
## 1.66 real animals across the streamed neighbourhood and drew as ZERO
## under the old `roundi`, because every chunk individually rounds below a
## half. The world near spawn had no predators in it at all.
func marker_count_for(
	population: float, chunk_coord: Vector2i = Vector2i.ZERO, species_salt: int = 0
) -> int:
	return PopulationMarkers.count_for(
		population,
		hash("%d_%d_%d_markers" % [chunk_coord.x, chunk_coord.y, species_salt]),
		MAX_MARKERS_PER_SPECIES
	)


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
	start_index: int = 0,
	spawn_safe: bool = false
) -> Array[Node2D]:
	var herbivore_pool := _allowed_pool(
		HERBIVORE_SPECIES_POOL_BY_BIOME.get(biome_name, HERBIVORE_SPECIES_POOL), difficulty_tier, spawn_safe
	)
	var predator_pool := _allowed_pool(
		PREDATOR_SPECIES_POOL_BY_BIOME.get(biome_name, PREDATOR_SPECIES_POOL), difficulty_tier, spawn_safe
	)
	# Goblins raiding together (docs/concept/ecosystem_dynamics.md): never
	# computed when spawn_safe, so a camp can never land in the literal
	# spawn clearing -- the same guarantee _allowed_pool's own spawn_safe
	# filtering already makes for every other hostile species.
	var is_camp := not spawn_safe and _is_goblin_camp_chunk(chunk_coord, biome_name)

	var spawned: Array[Node2D] = []
	spawned.append_array(
		_spawn_species(
			parent, chunk_coord, chunk_origin_tiles, chunk_size, tile_size,
			herbivore_population, herbivore_pool, 1, world, start_index, difficulty_tier, is_camp
		)
	)
	spawned.append_array(
		_spawn_species(
			parent, chunk_coord, chunk_origin_tiles, chunk_size, tile_size,
			predator_population, predator_pool, 2, world, start_index, difficulty_tier
		)
	)
	return spawned


## The nearest dry tile centre to `position`, or null when there is nothing
## but water within SPAWN_DRY_SEARCH_TILES.
##
## "Slides clear of water instead of not existing" is this project's own
## established answer to a deterministic placement landing wet (see the
## village square, which slides rather than vanishing): a lakeside chunk
## should still carry its animals, just not out on the lake, and silently
## dropping every individual whose point happened to land wet would thin a
## shoreline population for no reason a player could see.
##
## Rings outward in a fixed order, so it stays as deterministic as the
## point it corrects -- the same chunk gives the same animals the same
## places on every load. Bounded rather than exhaustive: an animal that
## cannot find land within a few tiles genuinely has no business there, and
## the cap keeps the cost of a fully-flooded chunk bounded too.
##
## `world` is duck-typed and optional: every test that spawns creatures
## without a world, and every caller that has none, gets the unchanged
## point back.
const SPAWN_DRY_SEARCH_TILES := 8


func _slid_clear_of_water(position: Vector2, world, tile_size: int):
	if world == null or not world.has_method("is_water_at_global"):
		return position
	var tile := Vector2i(int(position.x / tile_size), int(position.y / tile_size))
	if not world.is_water_at_global(tile.x, tile.y):
		return position
	for radius in range(1, SPAWN_DRY_SEARCH_TILES + 1):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				# The ring only, not the filled square: the inner cells were
				# already answered by a smaller radius.
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var candidate := tile + Vector2i(dx, dy)
				if world.is_water_at_global(candidate.x, candidate.y):
					continue
				return Vector2(
					(candidate.x + 0.5) * tile_size, (candidate.y + 0.5) * tile_size
				)
	return null


## "Hostile" is the same vocabulary the targeting system already committed
## to -- Player._nearby_enemy_candidates' own `info.is_predator or
## info.temperament == CreatureInfo.AGGRESSIVE` -- read here directly from
## CreatureInfo's own tables by species name (the same shape
## MIN_DIFFICULTY_TIER_BY_SPECIES.get(species, ...) below already uses)
## rather than constructing a throwaway CreatureInfo instance per species.
static func _is_hostile_species(species: String) -> bool:
	return (
		bool(CreatureInfo.PREDATOR_SPECIES.get(species, false))
		or CreatureInfo.TEMPERAMENT_BY_SPECIES.get(species, "calm") == CreatureInfo.AGGRESSIVE
	)


## Drops any pool entry whose own minimum difficulty tier exceeds the
## region's current tier -- e.g. "bear" is filtered out of forest's pool
## below Tier.HARD. Species with no MIN_DIFFICULTY_TIER_BY_SPECIES entry
## default to Tier.EASY (0), so they're never filtered.
## `spawn_safe` (default false, so every pre-existing call site keeps
## behaving exactly as before) additionally drops every hostile species --
## see SPAWN_SAFE_RADIUS_CHUNKS above.
func _allowed_pool(pool: Array, difficulty_tier: int, spawn_safe: bool = false) -> Array:
	var allowed: Array = []
	for species in pool:
		if MIN_DIFFICULTY_TIER_BY_SPECIES.get(species, RegionDifficulty.Tier.EASY) > difficulty_tier:
			continue
		if spawn_safe and _is_hostile_species(species):
			continue
		allowed.append(species)
	return allowed


## Whether this chunk should read as a goblin camp (see GOBLIN_CAMP_CHANCE
## above) -- a deterministic, seeded, per-chunk coin flip, exactly the
## shape AntColony.MOUND_CHANCE/BeeColony.HIVE_CHANCE already use for
## "fixed for the chunk's life, nothing placed by hand or on a timer",
## scoped to SPAWN_REACHABLE_BIOMES the same way every other Goblin-density
## lever already is.
func _is_goblin_camp_chunk(chunk_coord: Vector2i, biome_name: String) -> bool:
	if not (biome_name in SPAWN_REACHABLE_BIOMES):
		return false
	var roll := float(absi(hash("%d_%d_goblin_camp" % [chunk_coord.x, chunk_coord.y])) % 10000) / 10000.0
	return roll < GOBLIN_CAMP_CHANCE


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
	start_index: int = 0,
	difficulty_tier: int = RegionDifficulty.Tier.EASY,
	is_camp: bool = false
) -> Array[Node2D]:
	# Every PREDATOR_SPECIES_POOL_BY_BIOME entry is hostile by definition, so
	# a spawn-safe chunk's _allowed_pool call empties the predator pool
	# completely -- marker_count_for can still roll a nonzero count from a
	# nonzero population regardless of pool size, and species_pool[x %
	# species_pool.size()] below would divide by zero on an empty pool.
	if species_pool.is_empty():
		return []
	# A camp REASSIGNS the already-drawn count to goblin rather than ever
	# changing it -- defensive, since spawn_creatures already never computes
	# is_camp=true for a spawn_safe chunk (goblin is AGGRESSIVE-tempered, so
	# _allowed_pool would have stripped it from species_pool there anyway).
	var camp_active := is_camp and species_pool.has("goblin")
	var count := marker_count_for(population, chunk_coord, species_salt)
	var spawned: Array[Node2D] = []
	# `start_index` lets a chunk TOP UP rather than rebuild (see
	# EarthChunkManager._reconcile_chunk_creatures): a newcomer takes the next
	# unused index, so it gets its own deterministic seed and spawn point
	# rather than landing on top of an animal already standing there.
	for i in range(start_index, count):
		var wander_seed := hash("%d_%d_%d_%d_wander" % [chunk_coord.x, chunk_coord.y, species_salt, i])
		var species_name: String
		var position: Vector2
		if camp_active:
			species_name = "goblin"
			position = _camp_cluster_position(chunk_coord, chunk_origin_tiles, chunk_size, tile_size, i)
		else:
			var species_seed := absi(hash("%d_%d_%d_%d_species" % [chunk_coord.x, chunk_coord.y, species_salt, i]))
			species_name = species_pool[species_seed % species_pool.size()]
			position = _deterministic_position(
				chunk_coord, chunk_origin_tiles, chunk_size, tile_size, species_salt, i
			)
		# A land animal does not stand on open water. The deterministic
		# point takes no account of it, so an all-water chunk was given a
		# full land population standing on the lake (reported live with a
		# screenshot taken while swimming: an alpaca out on the water).
		var dry = _slid_clear_of_water(position, world, tile_size)
		if dry == null:
			continue  # nothing but water within reach -- no land animal here
		position = dry
		var marker := _build_marker(parent, species_name, position, wander_seed, world, tile_size)
		# See docs/concept/disease.md "Region pressure": carried forward so
		# disease transmission scales with the SAME distance-from-spawn
		# signal that already gated this individual's species pool above.
		marker.region_tier = difficulty_tier
		spawned.append(marker)
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


## Where a camp's goblins stand (see GOBLIN_CAMP_CHANCE/_is_goblin_camp_chunk
## above): one shared ANCHOR point, seeded from chunk_coord alone so every
## index in the camp agrees on it, then a small per-index offset (seeded
## from chunk_coord + index, bounded to CAMP_CLUSTER_RADIUS_TILES) so
## individuals don't stack on the exact same tile. The same shape
## _deterministic_position already uses, with one extra shared anchor step.
func _camp_cluster_position(
	chunk_coord: Vector2i,
	chunk_origin_tiles: Vector2i,
	chunk_size: int,
	tile_size: int,
	index: int
) -> Vector2:
	var anchor_seed := hash("%d_%d_goblin_camp_anchor" % [chunk_coord.x, chunk_coord.y])
	var anchor_x := anchor_seed % chunk_size
	var anchor_y := (anchor_seed / chunk_size) % chunk_size

	var span := CAMP_CLUSTER_RADIUS_TILES * 2 + 1
	var offset_seed := hash("%d_%d_goblin_camp_offset_%d" % [chunk_coord.x, chunk_coord.y, index])
	var offset_x := (offset_seed % span) - CAMP_CLUSTER_RADIUS_TILES
	var offset_y := ((offset_seed / span) % span) - CAMP_CLUSTER_RADIUS_TILES

	var local_x := clampi(anchor_x + offset_x, 0, chunk_size - 1)
	var local_y := clampi(anchor_y + offset_y, 0, chunk_size - 1)
	return Vector2(
		(chunk_origin_tiles.x + local_x + 0.5) * tile_size,
		(chunk_origin_tiles.y + local_y + 0.5) * tile_size
	)
