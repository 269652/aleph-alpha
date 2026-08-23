extends RefCounted

const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const TreeRenderer = preload("res://src/rendering/tree_renderer.gd")
const StoneRenderer = preload("res://src/rendering/stone_renderer.gd")
const TallGrass = preload("res://src/world/tall_grass.gd")
const DecorationLod = preload("res://src/rendering/decoration_lod.gd")
const DisplayScaling = preload("res://src/rendering/display_scaling.gd")
const ProceduralGrassSprite = preload("res://src/rendering/procedural_grass_sprite.gd")
const FlowerPatch = preload("res://src/world/flower_patch.gd")
const SeedDispersal = preload("res://src/world/seed_dispersal.gd")
const ScentField = preload("res://src/world/scent_field.gd")
const ProceduralFlowerSprite = preload("res://src/rendering/procedural_flower_sprite.gd")
const ProceduralSeedSprite = preload("res://src/rendering/procedural_seed_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")

## How much of a tile a ground-cover tuft (grass, scrub, lichen) covers.
## Well under 1: a clump of grass sits ON the ground, it is not the ground.
const TUFT_WORLD_SCALE := 0.5
const DesertScrub = preload("res://src/world/desert_scrub.gd")
const ProceduralScrubSprite = preload("res://src/rendering/procedural_scrub_sprite.gd")
const TundraLichen = preload("res://src/world/tundra_lichen.gd")
const ProceduralLichenSprite = preload("res://src/rendering/procedural_lichen_sprite.gd")
const EarthwormPatch = preload("res://src/world/earthworm_patch.gd")
const ProceduralWormSprite = preload("res://src/rendering/procedural_worm_sprite.gd")
const ForageClaims = preload("res://src/gameplay/forage_claims.gd")
const WindSway = preload("res://src/rendering/wind_sway.gd")
const WaterShader = preload("res://src/rendering/water_shader.gd")
const CreatureRenderer = preload("res://src/rendering/creature_renderer.gd")
const FishRenderer = preload("res://src/rendering/fish_renderer.gd")
const AmbientFlyerRenderer = preload("res://src/rendering/ambient_flyer_renderer.gd")
const PiscivoreBirdRenderer = preload("res://src/rendering/piscivore_bird_renderer.gd")
const VillageRenderer = preload("res://src/rendering/village_renderer.gd")
const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const EcosystemSimulation = preload("res://src/world/ecosystem_simulation.gd")
const ChunkSerializer = preload("res://src/world/chunk_serializer.gd")
const ForageScheduler = preload("res://src/gameplay/forage_scheduler.gd")
const TreeSpread = preload("res://src/gameplay/tree_spread.gd")
const FruitFall = preload("res://src/world/fruit_fall.gd")
const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const SnowLayer = preload("res://src/rendering/snow_layer.gd")
const PickableSeed = preload("res://src/rendering/pickable_seed.gd")
const SnowTrail = preload("res://src/world/snow_trail.gd")
const Snowfall = preload("res://src/world/snowfall.gd")
const SeasonTransition = preload("res://src/world/season_transition.gd")
const FlowerBloom = preload("res://src/world/flower_bloom.gd")
const TreeRooting = preload("res://src/world/tree_rooting.gd")
const FruitSpoilage = preload("res://src/gameplay/fruit_spoilage.gd")
const Olfaction = preload("res://src/gameplay/olfaction.gd")
const Flies = preload("res://src/gameplay/flies.gd")
const FlyLifeCycle = preload("res://src/gameplay/fly_life_cycle.gd")
const FlyColony = preload("res://src/gameplay/fly_colony.gd")
const PollinatorForaging = preload("res://src/gameplay/pollinator_foraging.gd")
const DroppedItem = preload("res://src/rendering/dropped_item.gd")
const FruitingModel = preload("res://src/world/fruiting_model.gd")
const ChunkEcologyCatchup = preload("res://src/world/chunk_ecology_catchup.gd")
const KeptAnimals = preload("res://src/world/kept_animals.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")
const WeatherModel = preload("res://src/world/weather_model.gd")
const TreeMaturity = preload("res://src/gameplay/tree_maturity.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")
const SeedEndozoochory = preload("res://src/gameplay/seed_endozoochory.gd")
const Item = preload("res://src/gameplay/item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")
const Chunk = preload("res://src/world/chunk.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const RegionDifficulty = preload("res://src/world/region_difficulty.gd")
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")
const RoomDetector = preload("res://src/gameplay/room_detector.gd")
const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const VillageFinder = preload("res://src/world/village_finder.gd")

## Where player-made tile modifications (Phase 3 building) are persisted,
## keyed per chunk -- terrain itself is deterministically regenerable (see
## update()'s doc comment), so only modifications need saving.
const MODIFICATIONS_DIR := "user://chunk_modifications"

## Where trees that have spread since a chunk was generated (see
## step_tree_spread) are persisted -- the original forest is deterministically
## regenerable like terrain, so only spread-in trees need saving.
const PLANTED_TREES_DIR := "user://chunk_planted_trees"

## Where each water chunk's aggregate fish population is persisted -- unlike
## herbivore/predator/vegetation state (in-memory only, see _unloaded_ecology),
## this is meant to survive a real game restart (see
## docs/concept/fishing.md#persistence-a-gap-shared-with-land-ecology-worth-closing-here-first).
## How long one weather spell lasts. Short enough that a session sees the
## sky change, long enough that it is weather rather than flicker -- see the
## note in the weather step on why this is not the calendar day.
## The one definition lives with the weather (see WeatherModel) -- anything
## reasoning about how long a spell gets to act reads the same number.
const WEATHER_PERIOD_SECONDS := WeatherModel.WEATHER_PERIOD_SECONDS

const FISH_POPULATION_DIR := "user://chunk_fish_population"
## Land ecology (herbivores, predators, vegetation) -- see
## ChunkSerializer.save_ecology. Persisted for the same reason fish are:
## the world should have moved on when the player comes back tomorrow,
## rather than resetting to a freshly-seeded region at full capacity.
const ECOLOGY_DIR := "user://chunk_ecology"
## Animals the player has tamed or tied up -- kept individually rather
## than as a number in the region's aggregate (see KeptAnimals).
const KEPT_ANIMALS_DIR := "user://chunk_kept_animals"

## Where roof pieces are persisted (see Chunk.roof_modifications) -- same
## generic Dictionary save/load ChunkSerializer already uses for
## `modifications`, just a separate directory since a roof shares its cell
## with the floor beneath it and can't live in that same dict.
const ROOF_MODIFICATIONS_DIR := "user://chunk_roof_modifications"

const CHUNK_SIZE := 32
## Chunks within this many chunks of the player are generated/painted.
const LOAD_RADIUS := 2
## Chunks beyond this are evicted. Larger than LOAD_RADIUS so a player
## oscillating near a boundary doesn't thrash load/unload every frame.
const UNLOAD_RADIUS := 3

## Real seconds of elapsed play time per simulated ecosystem day -- fast
## enough that population/vegetation shifts are noticeable within a play
## session, slow enough that creature markers aren't visibly flickering.
const SECONDS_PER_SIMULATED_DAY := 60.0

## Forage cadence: every FORAGE_INTERVAL seconds, FORAGE_DROPS_PER_TICK trees
## (chosen among all loaded) drop a fruit/nut. Central + bounded so cost is
## O(drops), not O(loaded trees) -- individual trees run no per-frame script.
const FORAGE_INTERVAL := 4.0
const FORAGE_DROPS_PER_TICK := 2
const _FORAGE_ITEMS := {
	"fruit": ["Fruit", "food", 20],
	"nut": ["Nut", "food", 20],
}

## Near-detail step_fruiting (unlike the ambient step_forage above) runs real
## per-tree phenology and drops the tree's actual NAMED species (see
## TreeSpecies) rather than the generic fruit/nut above -- its own small
## item-spec table, parallel to _FORAGE_ITEMS.
## How many separate places one tree's windfall lands in per drop tick.
##
## Fruit lying under a tree, not a pile against the stem. Bounded because each
## landing is a real node and the ground-item budget is finite.
const MAX_SEPARATE_WINDFALLS := 5

## Every species in TreeSpecies needs an entry: the drop path indexes this by
## species id, so a species bearing fruit with no entry here is a crash waiting
## for its season. Pine, acorn and hazelnut joined the roster and this did not.
const _NAMED_FRUIT_ITEMS := {
	"cherry": ["Cherry", "food", 20],
	"apple": ["Apple", "food", 20],
	"walnut": ["Walnut", "food", 20],
	"acorn": ["Acorn", "food", 20],
	"hazelnut": ["Hazelnut", "food", 20],
	"pine": ["Pine Nuts", "food", 20],
}

## Spread cadence: every SPREAD_INTERVAL seconds, SPREAD_ATTEMPTS_PER_TICK
## mature trees each attempt to plant a mutated-child sapling nearby (see
## TreeSpread) -- slower than forage since it's meant to read as a forest
## gradually creeping outward, not a burst of new growth. Central + bounded,
## same reasoning as forage: cost is O(attempts), not O(loaded trees).
const SPREAD_INTERVAL := 20.0
const SPREAD_ATTEMPTS_PER_TICK := 3

var generator := EarthChunkGenerator.new()

var _terrain_renderer := TerrainRenderer.new()
var _tree_renderer := TreeRenderer.new()
var _stone_renderer := StoneRenderer.new()
var _grass_sprite_generator := ProceduralGrassSprite.new()
var _scrub_sprite_generator := ProceduralScrubSprite.new()
var _lichen_sprite_generator := ProceduralLichenSprite.new()
var _wind_sway := WindSway.new()
var _water_layer: TileMapLayer  # optional GPU water overlay, see set_water_layer
var _water_material: ShaderMaterial  # the water overlay's shared shader material, see set_rain
var _water_shader := WaterShader.new()  # owns _water_material's disturbance buffer, see record_water_disturbance
## Last streamed-around tile, used to cull far-off water disturbances (see
## record_water_disturbance / DISTURBANCE_RADIUS_TILES).
var _disturbance_center_tile := Vector2i.ZERO
var _creature_renderer := CreatureRenderer.new()
var _fish_renderer := FishRenderer.new()
var _ambient_flyer_renderer := AmbientFlyerRenderer.new()
var _piscivore_bird_renderer := PiscivoreBirdRenderer.new()
var _village_renderer := VillageRenderer.new()
var _biome_classifier := BiomeClassifier.new()
var _region_difficulty := RegionDifficulty.new()
## Separate from _village_renderer's own internal instance -- SettlementGenerator
## is stateless/pure (see its own doc comment), so a second instance here for
## find_nearest_village's discovery-only lookups (no spawning) costs nothing
## and keeps this independent of VillageRenderer's rendering concerns.
var _settlement_generator := SettlementGenerator.new()
var _village_finder := VillageFinder.new()
var _spawn_chunk_coord := Vector2i.ZERO
## True once set_spawn_tile has actually been called -- distinguishes "spawn
## is genuinely at the world origin" from "no spawn configured yet", so the
## latter can safely default to Tier.HARD (unrestricted) instead of
## silently treating the origin as always-EASY.
var _spawn_configured := false
var _ecosystem := EcosystemSimulation.new()
var _chunk_serializer := ChunkSerializer.new()
var _forage_scheduler := ForageScheduler.new()
var _tree_spread := TreeSpread.new()
var _tree_maturity := TreeMaturity.new()
var _tile_map_layer: TileMapLayer
var _entities_parent: Node2D
var _creatures_parent: Node2D
var _loaded_chunks: Dictionary = {}  # Vector2i chunk_coord -> Chunk

## The chunk the player is standing in, and how far out from it decoration is
## drawn (see DecorationLod). Decoration is scoped to what the camera can
## actually show; the simulation itself still runs across every loaded chunk.
## What the camera frames when there is no live viewport to measure (headless
## runs): the project's own design size, see project.godot and DisplayScaling.
const DEFAULT_VIEWPORT_SIZE := Vector2i(1280, 720)

var _decoration_center := Vector2i.ZERO
var _decoration_radius := 1
## Set when the player crosses into a new chunk, so the newly-near chunks get
## their sprites on the next step rather than waiting out a refresh interval.
var _decoration_dirty := true
var _loaded_trees: Dictionary = {}  # Vector2i chunk_coord -> Array[Node2D]
var _loaded_stones: Dictionary = {}  # Vector2i chunk_coord -> Array[Node2D]

## Fallback half-extent for a solid prop carrying no CollisionShape2D of its
## own to measure -- see solid_obstacles_near.
const DEFAULT_OBSTACLE_RADIUS := 8.0


## Solid props (tree trunks, stones, ore) within `radius` of `at`, as plain
## {position, radius} dictionaries for CreatureMovementGate. Bounded to the
## chunks the query circle overlaps -- CreatureMarker used to find these by
## scanning the ENTIRE "tree"/"stone" node groups, every node in every
## loaded chunk, per creature, on every sensing tick (reported: "since the
## last change the game is laggy"); the per-chunk bookkeeping this class
## already keeps makes the same lookup O(nearby) instead of O(world).
func solid_obstacles_near(at: Vector2, radius: float) -> Array:
	var chunk_px := float(CHUNK_SIZE * TerrainRenderer.TILE_SIZE)
	var min_chunk := Vector2i(floori((at.x - radius) / chunk_px), floori((at.y - radius) / chunk_px))
	var max_chunk := Vector2i(floori((at.x + radius) / chunk_px), floori((at.y + radius) / chunk_px))
	var result: Array = []
	for chunk_y in range(min_chunk.y, max_chunk.y + 1):
		for chunk_x in range(min_chunk.x, max_chunk.x + 1):
			var coord := Vector2i(chunk_x, chunk_y)
			# Two separate loops, not a concatenated temporary array -- this
			# runs per creature per sensing tick, so avoidable allocations
			# add up (see the lag report this method exists to fix).
			for node in _loaded_trees.get(coord, []):
				_append_if_near(result, node, at, radius)
			for node in _loaded_stones.get(coord, []):
				_append_if_near(result, node, at, radius)
	return result


func _append_if_near(result: Array, node: Node, at: Vector2, radius: float) -> void:
	if not is_instance_valid(node):
		return
	if at.distance_to(node.position) > radius:
		return
	result.append({"position": node.position, "radius": _obstacle_radius(node)})


## An obstacle's blocking radius, measured from its OWN collision shape: a
## tree's solid part is just its trunk (see TreeRenderer, which sizes the
## box to the trunk so canopies stay walkable), and stones vary in size.
func _obstacle_radius(node: Node) -> float:
	for child in node.get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			var extents: Vector2 = (child.shape as RectangleShape2D).size * 0.5
			return maxf(extents.x, extents.y)
	return DEFAULT_OBSTACLE_RADIUS
var _grass_sims: Dictionary = {}  # Vector2i chunk_coord -> TallGrass
## Vector2i chunk_coord -> FlowerPatch, and the Sprite2D per flower cell.
var _flower_patches: Dictionary = {}
var _flower_sprites: Dictionary = {}
## Vector2i chunk_coord -> {Vector2i cell -> Sprite2D} for shed seed lying on
## the ground (see FlowerPatch.shed_seed).
var _seed_sprites: Dictionary = {}
var _flower_sprite_generator := ProceduralFlowerSprite.new()
var _grass_sprites: Dictionary = {}  # Vector2i chunk_coord -> {local cell Vector2i -> Sprite2D}
var _grass_refresh_accumulator := 0.0
var _scrub_sims: Dictionary = {}  # Vector2i chunk_coord -> DesertScrub
var _scrub_sprites: Dictionary = {}  # Vector2i chunk_coord -> {local cell Vector2i -> Sprite2D}
var _scrub_refresh_accumulator := 0.0
var _lichen_sims: Dictionary = {}  # Vector2i chunk_coord -> TundraLichen
var _lichen_sprites: Dictionary = {}  # Vector2i chunk_coord -> {local cell Vector2i -> Sprite2D}
var _lichen_refresh_accumulator := 0.0
## Vector2i chunk_coord -> EarthwormPatch, and the Sprite2D per SURFACED worm
## cell (see step_worms/_sync_worm_sprites, docs/concept/soil_fauna.md).
var _worm_patches: Dictionary = {}
var _worm_sprites: Dictionary = {}
var _worm_sprite_generator := ProceduralWormSprite.new()
var _loaded_creatures: Dictionary = {}  # Vector2i chunk_coord -> Array[Node2D]
var _loaded_fish: Dictionary = {}  # Vector2i chunk_coord -> Array[Node2D]
var _loaded_ambient_flyers: Dictionary = {}  # Vector2i chunk_coord -> Array[Node2D]
var _loaded_piscivore_birds: Dictionary = {}  # Vector2i chunk_coord -> Array[Node2D]
var _loaded_villages: Dictionary = {}  # Vector2i chunk_coord -> Array[Node2D]

## Wall/window building-piece collision (see docs/concept/building.md#pieces):
## a StaticBody2D+CollisionShape2D per solid piece cell, the same mechanism
## TreeRenderer already uses for trunks/boulders/ore -- this project has no
## generic tile-solidity check. Tracked per chunk so unloading frees exactly
## that chunk's bodies, mirroring _loaded_trees/_loaded_stones.
var _piece_collision_bodies: Dictionary = {}  # Vector2i chunk_coord -> {Vector2i global_cell -> StaticBody2D}

## Optional roof overlay layer (see set_roof_layer) -- separate TileMapLayer
## from _tile_map_layer since a roof piece shares its cell with the floor
## beneath it (Chunk.roof_modifications can't merge into `modifications`).
var _roof_layer: TileMapLayer = null
var _room_detector := RoomDetector.new()
## Which chunk/room's roof is currently hidden (the player is standing under
## it), so update() can restore it the moment that stops being true rather
## than leaving it hidden forever. null chunk_coord means nothing is hidden.
var _hidden_roof_chunk_coord = null
var _hidden_roof_room_cells: Array = []

var _ecosystem_time_accumulator := 0.0
var _forage_accumulator := 0.0
var _forage_tick := 0
var _spread_accumulator := 0.0
var _spread_tick := 0
## Total authoritative simulation time elapsed (seconds) -- used as the
## clock a sapling's planted_at is measured against (see TreeMaturity).
## Advances every step_tree_spread call regardless of the spread-attempt
## throttle, so a sapling's age tracks real elapsed time, not spread ticks.
var _world_age_seconds := 0.0


func _init(tile_map_layer: TileMapLayer, entities_parent: Node2D, creatures_parent: Node2D) -> void:
	_tile_map_layer = tile_map_layer
	_tile_map_layer.tile_set = _terrain_renderer.build_tile_set()
	# Tiles are painted at ART_TILE_SIZE pixels but must span only TILE_SIZE
	# world units -- scaling the layer down is what keeps art resolution and
	# world footprint independent (see TerrainRenderer.LAYER_SCALE).
	_tile_map_layer.scale = Vector2.ONE * TerrainRenderer.LAYER_SCALE
	_entities_parent = entities_parent
	_creatures_parent = creatures_parent


## Loads/generates chunks within LOAD_RADIUS of the player's global tile
## position, and evicts previously-loaded chunks now beyond UNLOAD_RADIUS.
## Chunks aren't persisted on eviction: real elevation is deterministic and
## fixed-seed procedural detail is deterministic too, so regenerating a
## revisited chunk reproduces it exactly. (Once player-made edits exist --
## Phase 3 building -- evicting a *modified* chunk should save it via
## ChunkSerializer first; this is the natural place to add that later.)
func update(player_global_tile: Vector2i) -> void:
	# Remembered so record_water_disturbance can drop wakes far out of view
	# (see DISTURBANCE_RADIUS_TILES).
	_disturbance_center_tile = player_global_tile
	var center_chunk := _chunk_coord_for_tile(player_global_tile)

	# Decoration follows the player's CHUNK, not the player: crossing a chunk
	# boundary is what changes which chunks are worth drawing, and it forces
	# an immediate re-sync so a newly-near chunk isn't bare ground until its
	# next throttled refresh comes round.
	if center_chunk != _decoration_center or _decoration_dirty:
		_decoration_center = center_chunk
		_decoration_radius = _derive_decoration_radius()
		# The chunk the player is standing in has changed, so which chunks are
		# worth drawing has too. Rather than build the sprites here, the
		# throttled refreshes that already do that work are made due
		# immediately -- grass alone refreshes only every
		# GRASS_REFRESH_INTERVAL seconds, long enough to walk into view of
		# ground that is visibly bare. Sprite creation stays where it always
		# was, in the step_* functions.
		_grass_refresh_accumulator = GRASS_REFRESH_INTERVAL
		_worm_refresh_accumulator = WORM_REFRESH_INTERVAL
		_decoration_dirty = false

	for chunk_coord in chunks_in_radius(center_chunk, LOAD_RADIUS):
		if not _loaded_chunks.has(chunk_coord):
			_load_chunk(chunk_coord)

	for chunk_coord in _loaded_chunks.keys().duplicate():
		if _chebyshev_distance(chunk_coord, center_chunk) > UNLOAD_RADIUS:
			_unload_chunk(chunk_coord)

	_update_roof_visibility(player_global_tile)


func is_chunk_loaded(chunk_coord: Vector2i) -> bool:
	return _loaded_chunks.has(chunk_coord)


func has_ecosystem_region(chunk_coord: Vector2i) -> bool:
	return _ecosystem.has_region(chunk_coord)


## Sets the world's spawn point (its chunk becomes the center of the
## EASY-difficulty region -- see RegionDifficulty and
## docs/concept/ecosystem_dynamics.md's Region difficulty section). Callers
## (World._compute_dry_land_spawn_tile) should call this once, with the
## real computed dry-land spawn tile, before the first update() -- if never
## called, difficulty defaults to Tier.HARD everywhere (unrestricted, not
## gated), the same safe-default philosophy `biome_name`'s "" default uses.
func set_spawn_tile(spawn_tile: Vector2i) -> void:
	_spawn_chunk_coord = _chunk_coord_for_tile(spawn_tile)
	_spawn_configured = true


func _difficulty_tier_at(chunk_coord: Vector2i) -> int:
	if not _spawn_configured:
		return RegionDifficulty.Tier.HARD
	return _region_difficulty.tier_at(chunk_coord, _spawn_chunk_coord)


func herbivore_population_at_chunk(chunk_coord: Vector2i) -> float:
	return _ecosystem.herbivore_population(chunk_coord)


## Whether the chunk containing `pixel_position` can support another
## individual herbivore -- the aggregate carrying capacity (vegetation and
## water at that location) expressed as a yes/no for individual-fidelity
## reproduction. This is the "two fidelities, one truth" pillar in
## concept/ecosystem_dynamics.md doing real work: what the player can see
## must obey the same limits the unseen aggregate does.
func can_support_another_herbivore(pixel_position: Vector2, live_nearby: int) -> bool:
	var chunk_coord := _chunk_coord_for_tile(_world_tile_for_pixel(pixel_position))
	var capacity := _ecosystem.herbivore_capacity_at(chunk_coord)
	if capacity <= 0.0:
		return false
	return float(live_nearby) < capacity


func predator_population_at_chunk(chunk_coord: Vector2i) -> float:
	return _ecosystem.predator_population(chunk_coord)


func fish_population_at_chunk(chunk_coord: Vector2i) -> float:
	return _ecosystem.fish_population(chunk_coord)


## Central, throttled tree forage: every FORAGE_INTERVAL of real time, a small
## bounded number of mature loaded trees drop a fruit/nut ground item (via
## WorldItemBus, like creature loot) -- a sapling still below its own
## genome's maturity_time (see TreeMaturity) doesn't forage yet. Cost is
## O(FORAGE_DROPS_PER_TICK), not per-tree, so it doesn't scale with the
## thousands of loaded trees.
func step_forage(delta_seconds: float) -> void:
	_forage_accumulator += delta_seconds
	if _forage_accumulator < FORAGE_INTERVAL:
		return
	# Subtract one interval, then shed any remaining surplus.
	#
	# Subtracting alone is exact while a frame is shorter than the interval,
	# and leaks forever once it is not: the accumulator keeps whatever it did
	# not spend and drifts upward, so the cadence stops meaning anything. A
	# long frame hitch does it today; running the ecology fast (/ecotest, see
	# TimeLapse) does it every slice.
	_forage_accumulator -= FORAGE_INTERVAL
	if _forage_accumulator >= FORAGE_INTERVAL:
		_forage_accumulator = fmod(_forage_accumulator, FORAGE_INTERVAL)

	var tree_positions := _mature_tree_positions()
	var tree_index := 0
	for drop in _forage_scheduler.drops(tree_positions, _forage_tick, FORAGE_DROPS_PER_TICK):
		tree_index += 1
		var spec: Array = _FORAGE_ITEMS[drop.id]
		var stack := ItemStack.new(Item.new(drop.id, spec[0], spec[1], spec[2]))
		# Fruit falls across the canopy block -- the parent's own tile and the
		# eight around it (see FruitFall). It used to land on the tree's exact
		# position, so every seed a wood produced landed on a tile that already
		# had a tree in it, and woods never spread.
		WorldItemBus.item_dropped.emit(
			stack, drop.position + FruitFall.fall_offset(_forage_tick * 31 + tree_index)
		)
	_forage_tick += 1


## Detail radius (px) within which trees run full individual fruit phenology:
## visible ripe-fruit pixel dots on the canopy and phenology-driven fruit fall
## (see FruitingModel / concept/ecosystem_dynamics.md). Trees outside this but
## still loaded only get the cheap ambient step_forage drops.
const FRUITING_DETAIL_RADIUS := 280.0
const FRUITING_INTERVAL := 1.0

var _fruiting_model := FruitingModel.new()
var _ecology_catchup := ChunkEcologyCatchup.new()
var _season_cycle := SeasonCycle.new()
var _weather_model := WeatherModel.new()
## Per-chunk aggregate ecology snapshot recorded at unload + the world-age then,
## so a revisited chunk can be catch-up integrated over the elapsed unloaded
## time (variable-fidelity LOD, see concept/ecosystem_dynamics.md) rather than
## reset to fresh equilibrium. chunk_coord -> {state Dictionary, unloaded_at float}.
var _unloaded_ecology: Dictionary = {}
var _fruiting_accumulator := 0.0
## The world-age at the previous fruiting step, so fallen_between integrates
## exactly the elapsed interval (all trees share the one world clock).
var _last_fruiting_time := 0.0


## Individual-fidelity fruiting for trees near `player_pixel` (see the "two
## fidelities" pillar in concept/ecosystem_dynamics.md): each nearby tree shows
## its current ripe crop as canopy pixel dots, and any fruit that abscised
## since the last step falls as a ground item. Bounded by the detail radius
## (only a handful of trees are ever this close), and throttled.
func step_fruiting(delta_seconds: float, player_pixel: Vector2) -> void:
	_fruiting_accumulator += delta_seconds
	if _fruiting_accumulator < FRUITING_INTERVAL:
		return
	_fruiting_accumulator = 0.0

	var now := _world_age_seconds
	var warmth := _warmth_at_pixel(player_pixel)
	var season_name := current_season()
	_sync_tree_season(season_name)
	for trees in _loaded_trees.values():
		for tree in trees:
			if not tree.has_method("set_ripe_fruit"):
				continue
			# Whether this tree is close enough to DROP its fruit as real
			# items. Showing a crop is cheap -- the textures are shared
			# between trees of the same species, season and crop level -- but
			# every fallen fruit is a node, so the drops stay near the player.
			#
			# This check used to skip the whole tree, so only the handful
			# within the detail radius carried any fruit at all and the rest of
			# the wood stood bare in the middle of autumn (reported: apples on
			# only some trees).
			var drops_fruit: bool = (
				player_pixel.distance_to(tree.position) <= FRUITING_DETAIL_RADIUS
			)
			var genome := _forage_scheduler.genome_for(tree.position)
			# NAMED species (Walnut/Cherry/Apple -- see TreeSpecies), not the
			# raw nut/fruit spectrum: both the canopy's ripe crop and the
			# fallen count scale by this species' own yield/ripening
			# character on top of the genome's raw traits.
			var species_id := TreeSpecies.species_for_bias(genome.species_bias)
			var yield_multiplier := TreeSpecies.yield_multiplier_for(species_id)
			var ripening_multiplier := TreeSpecies.ripening_multiplier_for(species_id)
			var state: Dictionary = _fruiting_model.state_at(
				genome, now, warmth, yield_multiplier, ripening_multiplier
			)
			var turn := SeasonTransition.state_at(
				_season_cycle.year_fraction(_world_age_seconds)
			)
			tree.set_ripe_fruit(
				int(state.get("ripe", 0)), season_name, turn.to, turn.progress
			)

			if not drops_fruit:
				continue
			# How many were on the tree before this step, so the ones that leave
			# can be identified: fruit leave from the top of the crop's order
			# (see FruitingModel.fallen_indices).
			var hanging_before: int = _fruiting_model.hanging_at(
				genome, _last_fruiting_time, warmth, yield_multiplier, ripening_multiplier
			)
			var fallen: int = _fruiting_model.fallen_between(
				genome, _last_fruiting_time, now, warmth, yield_multiplier, ripening_multiplier
			)
			if fallen > 0:
				var spec: Array = _NAMED_FRUIT_ITEMS[species_id]
				# Each fruit lands AS ITSELF, under where it was hanging.
				#
				# Windfall used to be spawned as up to five arbitrary stacks
				# scattered by a hash with no relation to the canopy, so what
				# hit the ground was a new cherry rather than the one that had
				# been on the tree (reported). The index that left the tree
				# picks the landing spot, and the canopy drew that same index in
				# that same place (see ProceduralTreeSprite.fruit_polar).
				#
				# Capped per step for the reason the old stack-splitting was:
				# a measured 1524 fruit a minute from a forty-tree stand once
				# turned the ground under every tree into a hundred clickable
				# nodes. In ordinary play at most one fruit leaves a tree per
				# step, so the cap is a backstop against a catch-up span rather
				# than something the normal case meets.
				var variant: int = ProceduralTreeSprite.tree_variant_for(tree.sprite_seed)
				var leaving: Array = _fruiting_model.fallen_indices(
					maxi(hanging_before, fallen), fallen
				)
				var spawned := 0
				for fruit_index in leaving:
					if spawned >= MAX_SEPARATE_WINDFALLS:
						break
					spawned += 1
					var stack := ItemStack.new(
						Item.new(species_id, spec[0], spec[1], spec[2]), 1
					)
					WorldItemBus.item_dropped.emit(
						stack,
						tree.position + ProceduralTreeSprite.fruit_ground_offset(
							variant, fruit_index
						)
					)
	_last_fruiting_time = now


## Local warmth [0,1] driving ripening rate (growing-degree-day analogue): the
## real Earth temperature at the player's tile, modulated by the current season
## (see SeasonCycle / concept/seasons.md) -- so trees ripen and drop fruit fast
## in summer and slowly in winter, on top of the baseline climate.
func _warmth_at_pixel(player_pixel: Vector2) -> float:
	var tile := _world_tile_for_pixel(player_pixel)
	var climate := clampf(generator.temperature_at_global(tile.x, tile.y), 0.0, 1.0)
	return climate * _season_cycle.warmth_modifier(_world_age_seconds)


## The current season label (see SeasonCycle) -- for the HUD.
func current_season() -> String:
	return _season_cycle.season_at(_world_age_seconds)


## The world clock, in seconds since this world began.
func world_age_seconds() -> float:
	return _world_age_seconds


## Skips the world FORWARD to the start of `season` (see /season). Returns
## whether that was a season we have.
##
## The skipped time is not replayed. The jump is up to a whole year of world
## time and fruiting counts what fell between the last time it ran and now, so
## moving the clock without moving that mark hands `fallen_between` a year-long
## span -- and `/season autumn` would empty every nearby canopy onto the ground
## in one step. The same two-clocks trap that has already bitten bird dispersal
## and tree maturity: two numbers that must agree, moved independently.
##
## Trees are deliberately NOT caught up the same way: a sapling really has aged
## by the time you skip past, and watching it be older is the point of the
## command.
func jump_to_season(season: String) -> bool:
	var skip: float = _season_cycle.seconds_until_season(_world_age_seconds, season)
	if skip <= 0.0:
		return false
	_world_age_seconds += skip
	_last_fruiting_time = _world_age_seconds
	return true


## Pins the weather (see /weather). Returns whether that was a state we have.
func force_weather(state: String) -> bool:
	return _weather_model.force_weather(state)


func clear_forced_weather() -> void:
	_weather_model.clear_forced_weather()


func is_weather_forced() -> bool:
	return _weather_model.is_forced()


## How far (in chunks, Chebyshev distance) find_nearest_village will search
## outward before giving up -- bounded so an unlucky run of ocean/mountain
## chunks (never habitable, see SettlementGenerator) can't turn one /village
## command into an unbounded terrain-generation sweep. At
## SETTLEMENT_CHANCE_DENOMINATOR (30) this comfortably covers the expected
## distance to the nearest settlement many times over.
const MAX_VILLAGE_SEARCH_RADIUS_CHUNKS := 24


## Nearest chunk hosting a settlement (see SettlementGenerator), searching
## outward from `from_tile`'s own chunk -- the discovery half of the
## /village dev-console command (see World._handle_village_command).
## Returns the settlement's "well" landmark world position (every settlement
## always has one, its natural teleport target -- see SettlementGenerator's
## _LANDMARK_OFFSETS_TILES) or null if none is found within
## MAX_VILLAGE_SEARCH_RADIUS_CHUNKS. Pure discovery: doesn't load or spawn
## the found chunk itself -- update() picks that up normally once the player
## arrives.
func find_nearest_village(from_tile: Vector2i) -> Variant:
	var start_chunk := _chunk_coord_for_tile(from_tile)
	var found_chunk: Variant = _village_finder.find_nearest(
		start_chunk,
		MAX_VILLAGE_SEARCH_RADIUS_CHUNKS,
		_settlement_generator,
		func(chunk_coord: Vector2i) -> String:
			var chunk := generator.generate_chunk(chunk_coord, CHUNK_SIZE)
			return _biome_classifier.dominant_biome(chunk.biome)
	)
	if found_chunk == null:
		return null
	var settlement := _settlement_generator.generate_settlement(
		found_chunk, found_chunk * CHUNK_SIZE, CHUNK_SIZE, TerrainRenderer.TILE_SIZE
	)
	return settlement.landmarks.well


## How warm it feels around `player_pixel` right now, [0,1]: the real climate
## temperature scaled by the season and the current weather (see
## SurvivalMeters.regulate_temperature / concept/survival.md). Feeds the
## player's body-temperature regulation.
func ambient_warmth(player_pixel: Vector2) -> float:
	var tile := _world_tile_for_pixel(player_pixel)
	var climate := clampf(generator.temperature_at_global(tile.x, tile.y), 0.0, 1.0)
	var season := _season_cycle.warmth_modifier(_world_age_seconds)
	var weather := _weather_model.warmth_factor(current_weather(player_pixel))
	return clampf(climate * season * weather, 0.0, 1.0)


## Movement-speed multiplier from the current weather at the player (rain/storm
## slow you down; see WeatherModel.movement_speed_modifier).
func weather_speed_modifier(player_pixel: Vector2) -> float:
	return _weather_model.movement_speed_modifier(current_weather(player_pixel))


## The current weather at the player's region (see WeatherModel), derived from
## the world-age (as a day count) and the player's chunk as the region seed --
## for the HUD and, later, survival/combat weather effects.
## The 4 cardinal directions checked for land neighbors, matching
## TerrainRenderer's own _DIRECTIONS convention (kept as a small local
## duplicate -- TerrainRenderer's is private, and this is 4 well-known
## constant vectors, not worth threading an accessor through for).
const _DIRECTIONS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]


## Registers the GPU water overlay layer (see WaterShader/
## TerrainRenderer.build_water_overlay_tile_set): it gets the small shore-
## distance tile set plus the animated water material, and from then on
## every loaded ocean cell is marked with the tile matching its OWN land
## neighbors (see _paint_water_overlay). Chunks already loaded before
## registration get marked immediately.
func set_water_layer(water_layer: TileMapLayer) -> void:
	_water_layer = water_layer
	water_layer.tile_set = _terrain_renderer.build_water_overlay_tile_set()
	# Must match the base terrain layer's scale exactly or the overlay would
	# drift out of alignment with the ground it shades (see
	# TerrainRenderer.LAYER_SCALE).
	water_layer.scale = Vector2.ONE * TerrainRenderer.LAYER_SCALE
	_water_material = _water_shader.shared_material()
	water_layer.material = _water_material
	for chunk_coord in _loaded_chunks:
		_paint_water_overlay(chunk_coord, _loaded_chunks[chunk_coord])


## Registers the roof overlay layer (see docs/concept/
## building.md#what-enterable-means-in-a-top-down-game): a roof piece shares
## its cell with the floor beneath it, so it paints onto its own TileMapLayer
## rather than `_tile_map_layer`'s single-tile-per-cell `modifications`.
## Reuses the SAME TileSet as the main terrain layer (roof tiles already live
## in that shared atlas -- see TerrainRenderer._building_piece_linear), not a
## second one. Optional: a caller that never sets this simply never sees
## roofs rendered at all, same fail-open shape as _water_layer.
func set_roof_layer(roof_layer: TileMapLayer) -> void:
	_roof_layer = roof_layer
	roof_layer.tile_set = _tile_map_layer.tile_set
	roof_layer.scale = Vector2.ONE * TerrainRenderer.LAYER_SCALE
	for chunk_coord in _loaded_chunks:
		_terrain_renderer.paint_roofs(
			_roof_layer, _loaded_chunks[chunk_coord], chunk_coord * CHUNK_SIZE, _hidden_cells_for(chunk_coord)
		)


## World's own ground-item container (see World._ground_items /
## _on_item_dropped) -- registered so fruit_near/take_fruit_at (bird
## endozoochory, see SeedEndozoochory) can see and consume real, already-
## rendered fallen fruit instead of needing a second, parallel ground-item
## model of their own. Optional, same fail-open shape as _water_layer/
## _roof_layer: a caller that never sets this simply sees no fruit to forage.
var _ground_items: Node2D = null


func set_ground_items(ground_items: Node2D) -> void:
	_ground_items = ground_items


## The local-cell hidden-set paint_roofs expects for `chunk_coord` right now
## -- the currently-hidden room's cells if the player is standing under this
## chunk's own roof, otherwise empty (nothing hidden).
func _hidden_cells_for(chunk_coord: Vector2i) -> Dictionary:
	if _hidden_roof_chunk_coord != chunk_coord:
		return {}
	var hidden := {}
	for cell in _hidden_roof_room_cells:
		hidden[cell] = true
	return hidden


## Only the actual BuildingPiece ids in `chunk.modifications` -- earth/
## campfire/furnace and any other non-piece modification must not be treated
## as walls/floors for enclosure purposes (see RoomDetector.find_rooms).
func _piece_grid_for(chunk: Chunk) -> Dictionary:
	var grid := {}
	for cell in chunk.modifications:
		var tile_id: String = chunk.modifications[cell]
		if BuildingPiece.has_piece(tile_id):
			grid[cell] = tile_id
	return grid


## Hides the roof over whichever room (if any) the player is currently
## standing in, and restores whichever room was PREVIOUSLY hidden the moment
## the player is no longer in it. Called every frame from update(), same as
## the rest of chunk streaming -- deliberately NOT throttled on "the
## player's tile hasn't changed": a structure can be built/destroyed (see
## stamp_structure_at_global/build_at_global) while the player stands
## perfectly still, and a tile-based throttle would then never re-check
## room membership at all (a real bug this caught: stamping a hut around a
## stationary player never hid its roof, because the player's own tile
## never changed between the load and the stamp). The room-unchanged check
## just below already skips the expensive repaint on every frame where
## nothing actually needs to change, so this stays cheap regardless.
func _update_roof_visibility(player_global_tile: Vector2i) -> void:
	if _roof_layer == null:
		return

	var chunk_coord := _chunk_coord_for_tile(player_global_tile)
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	var room_cells: Array = []
	if chunk != null:
		var local_cell := _local_coord(player_global_tile.x, player_global_tile.y)
		room_cells = _room_detector.room_containing(local_cell, _piece_grid_for(chunk))

	if chunk_coord == _hidden_roof_chunk_coord and room_cells == _hidden_roof_room_cells:
		return  # nothing changed -- still in the same room (or still outside)

	# Un-hide whatever was previously hidden.
	if _hidden_roof_chunk_coord != null and _loaded_chunks.has(_hidden_roof_chunk_coord):
		var previous_chunk: Chunk = _loaded_chunks[_hidden_roof_chunk_coord]
		_terrain_renderer.paint_roofs(_roof_layer, previous_chunk, _hidden_roof_chunk_coord * CHUNK_SIZE, {})

	if room_cells.is_empty():
		_hidden_roof_chunk_coord = null
		_hidden_roof_room_cells = []
		return

	_hidden_roof_chunk_coord = chunk_coord
	_hidden_roof_room_cells = room_cells
	var hidden := {}
	for cell in room_cells:
		hidden[cell] = true
	_terrain_renderer.paint_roofs(_roof_layer, chunk, chunk_coord * CHUNK_SIZE, hidden)


## Marks every ocean cell of a loaded chunk on the water overlay layer with
## the shore-distance tile matching its own cardinal land neighbors (empty ==
## open water) -- the shader reads that tile as per-pixel proximity data to
## blend and animate the shore continuously, not as art.
func _paint_water_overlay(chunk_coord: Vector2i, chunk: Chunk) -> void:
	if _water_layer == null:
		return
	var origin := chunk_coord * CHUNK_SIZE
	for y in chunk.height:
		for x in chunk.width:
			if chunk.biome[y * chunk.width + x] != "ocean":
				continue
			var global := origin + Vector2i(x, y)
			var land_directions := _land_directions_at(global.x, global.y)
			# Only search farther rings when nothing touches land directly --
			# ring 0 already answers the common case for free.
			var ring_distance := 0
			if land_directions.is_empty():
				ring_distance = _ring_distance_at(global.x, global.y, TerrainRenderer.RING_MAX)
			_water_layer.set_cell(
				global, 0,
				_terrain_renderer.atlas_coords_for_water_overlay(land_directions, ring_distance)
			)


## Cardinal directions from (global_x, global_y) that hold a non-ocean,
## currently-loaded neighbor. A neighbor in an unloaded chunk (streaming
## edge) is treated as unknown, not land -- avoids false shore-marking right
## at the load radius boundary.
func _land_directions_at(global_x: int, global_y: int) -> Array:
	var land_directions := []
	for direction in _DIRECTIONS:
		var neighbor_biome := biome_at_global(global_x + direction.x, global_y + direction.y)
		if neighbor_biome != "" and neighbor_biome != "ocean":
			land_directions.append(direction)
	return land_directions


## Distance in tiles to the nearest non-ocean, currently-loaded cell, found
## by checking each expanding Chebyshev ring (radius 1, then 2, ...) in
## turn -- diagonals included, since flat ring tiles (see
## TerrainRenderer.atlas_coords_for_water_overlay) don't need cardinal
## precision the way the direct-touching ring-0 tile does. Only called when
## _land_directions_at already found nothing at radius 0. Returns `max_ring`
## (== "open water") if no land is found within that range.
func _ring_distance_at(global_x: int, global_y: int, max_ring: int) -> int:
	for radius in range(1, max_ring):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue  # only this ring's perimeter, smaller radii already checked
				var neighbor_biome := biome_at_global(global_x + dx, global_y + dy)
				if neighbor_biome != "" and neighbor_biome != "ocean":
					return radius
	return max_ring


## Sets how strongly raindrop ripples show on the water overlay (see
## WaterShader.set_rain_intensity), driven from the live weather model.
## Purely a continuous shader-uniform update now -- no tile repainting, since
## rain moved entirely off the baked tile system onto the GPU shader.
## The warmth where the player is standing -- climate and season together.
func current_warmth() -> float:
	return _warmth_at_pixel(_disturbance_center_tile * TerrainRenderer.TILE_SIZE)


## The overlay snow is painted onto (see SnowLayer). Registered like the water
## overlay, and optional: a caller that never sets one simply gets no snow.
var _snow_layer: TileMapLayer = null
var _snow_renderer := SnowLayer.new()
## Footprints, and how much snow is lying (see SnowTrail / Snowfall).
var _snow_trail := SnowTrail.new()
var _snow_depth := 0.0


func set_snow_layer(snow_layer: TileMapLayer) -> void:
	_snow_layer = snow_layer
	snow_layer.tile_set = _snow_renderer.build_tile_set()
	# Must match the terrain layer's scale exactly, or the cover drifts out of
	# alignment with the ground it lies on.
	snow_layer.scale = Vector2.ONE * TerrainRenderer.LAYER_SCALE


## How much snow is lying, 0 bare to 1 covered (see Snowfall).
##
## Painted as TILES rather than as a tint on the ground layer. A tint is one
## number for the whole world and cannot express "this tile is trodden and that
## one is not", so footprints could not exist at all -- which is exactly what
## this was before.
##
## Only the ground is covered: the grass, stones and trees keep their shape on
## top of it. The ground is covered, not replaced.
func set_snow_depth(depth: float) -> void:
	_snow_depth = clampf(depth, 0.0, 1.0)
	_repaint_snow()


## How much snow is lying, 0 bare to 1 covered.
func loaded_chunk_count() -> int:
	return _loaded_chunks.size()


func snow_depth() -> float:
	return _snow_depth


## Marks a tile as walked on, packing the snow down (see SnowTrail).
func tread_snow_at(pixel_position: Vector2) -> void:
	if _snow_depth <= 0.0:
		return
	var tile := _world_tile_for_pixel(pixel_position)
	_snow_trail.step_on(tile)
	_snow_dirty[tile] = true


## The world clock as of the last snow step, so snow can advance on the same
## clock everything else does.
var _snow_world_age := 0.0


## Accumulates or melts the lying snow, fills tracks back in while it is
## snowing, and repaints.
##
## Takes NO delta: it reads the world clock itself. Snow used to be advanced by
## the real frame delta while the season ran on the world clock, which is two
## clocks that have to agree and were never made to. `/season summer` leaps the
## world clock up to a year forward, the snow saw one frame -- about sixteen
## milliseconds -- and went on lying there in the sunshine (reported). The same
## mismatch left a `/ecotest` winter thawing at real-time speed while the
## seasons flew past.
##
## Reading the clock here rather than being handed a delta is what makes that
## impossible to reintroduce: there is one clock, not two kept in step by hand.
func step_snow(snowing: bool, warmth: float) -> void:
	var elapsed: float = maxf(_world_age_seconds - _snow_world_age, 0.0)
	_snow_world_age = _world_age_seconds
	_snow_depth = Snowfall.accumulate(_snow_depth, snowing, warmth, elapsed)

	# The painting is optional -- a headless server has no snow layer but still
	# has weather, so the depth above has to be kept either way.
	if _snow_layer == null:
		return
	if snowing:
		# Filling in changes every track at once, so they all need repainting.
		for tile in _snow_trail.trodden_tiles(0.0):
			_snow_dirty[tile] = true
	_snow_trail.advance(elapsed, snowing)
	_repaint_snow()


## The depth band the whole field was last painted at, and the tiles whose
## tread has changed since.
##
## Repainting every loaded tile every frame is thousands of set_cell calls for
## a field that mostly has not changed -- the same shape of cost that took the
## frame rate down when the fast-forward first ran. The FIELD is repainted only
## when its depth crosses into a new band, which happens a handful of times a
## snowfall; footprints repaint only the tiles that were actually walked on.
var _snow_painted_band := -1
var _snow_dirty: Dictionary = {}


## Paints the tiles that need it.
func _repaint_snow() -> void:
	if _snow_layer == null:
		return
	if _snow_depth <= 0.0:
		if _snow_painted_band != -1:
			_snow_layer.clear()
			_snow_painted_band = -1
			_snow_dirty.clear()
		return

	var band := _snow_renderer.band_for(_snow_depth, 0.0)
	if band != _snow_painted_band:
		_snow_painted_band = band
		_snow_dirty.clear()
		_repaint_whole_field()
		return
	for tile in _snow_dirty:
		_paint_snow_tile(tile)
	_snow_dirty.clear()


func _repaint_whole_field() -> void:
	for chunk_coord in _loaded_chunks:
		var origin: Vector2i = chunk_coord * CHUNK_SIZE
		var chunk: Chunk = _loaded_chunks[chunk_coord]
		for local_y in chunk.height:
			for local_x in chunk.width:
				_paint_snow_tile(origin + Vector2i(local_x, local_y))


func _paint_snow_tile(tile: Vector2i) -> void:
	# Water does not take snow -- it freezes or it does not, which is a
	# different thing and not this one.
	if biome_at_global(tile.x, tile.y) == "ocean":
		_snow_layer.erase_cell(tile)
		return
	var band := _snow_renderer.band_for(_snow_depth, _snow_trail.tread_at(tile))
	if band < 0:
		_snow_layer.erase_cell(tile)
	else:
		_snow_layer.set_cell(tile, 0, Vector2i(band, 0))


func set_rain(raining: bool) -> void:
	if _water_material != null:
		_water_material.set_shader_parameter("rain_intensity", 1.0 if raining else 0.0)


## Sets how energetic the water's wind-driven surface shimmer is (see
## WaterShader.set_wind_strength) -- pass WeatherModel.wind_strength_for(the
## current weather). Paces the surface TEXTURE only; ripple rings come from
## rain and movement, never from wind.
func set_wind_strength(strength: float) -> void:
	_water_shader.set_wind_strength(strength)


## How far from the streaming center a disturbance may be and still be worth
## recording, in tiles. Every loaded fish emits a wake on a timer, including
## ones several chunks away that the player cannot possibly see; without this
## they churn the (small, fixed-size) disturbance buffer so fast that
## on-screen wakes are evicted almost the instant they appear -- which is why
## rain rendered fine while movement wakes stayed invisible.
##
## Sized to just past the visible screen: at TARGET_TILE_SCREEN_PX the view
## spans roughly 20x11 tiles, so this covers it with margin while excluding
## the ~25 loaded chunks' worth of fish that would otherwise crowd it out. A
## first attempt at 40 was still far too generous -- it admitted several
## hundred off-screen fish and the wakes stayed invisible.
const DISTURBANCE_RADIUS_TILES := 14


## Records a ripple-causing disturbance in the water overlay at `world_pos`
## (see WaterShader.add_disturbance) -- a fish darting past, or a player/
## animal wading or swimming. Renders as an expanding, fading ring that
## genuinely interferes with rain ripples rather than drawing over them.
## Disturbances too far from the streaming center are dropped (see
## DISTURBANCE_RADIUS_TILES). Callers are responsible for their own
## throttling (e.g. once per swim step, not every frame).
func record_water_disturbance(world_pos: Vector2) -> void:
	var tile := _world_tile_for_pixel(world_pos)
	var offset := tile - _disturbance_center_tile
	if maxi(absi(offset.x), absi(offset.y)) > DISTURBANCE_RADIUS_TILES:
		return
	_water_shader.add_disturbance(world_pos)


## Ages every live water disturbance so its ring actually expands/fades on
## screen (see WaterShader.advance_disturbances) -- must run every frame,
## not just when a new disturbance is recorded.
func step_water_disturbances(delta: float) -> void:
	_water_shader.advance_disturbances(delta)


func current_weather(player_pixel: Vector2) -> String:
	var chunk_coord := _chunk_coord_for_tile(_world_tile_for_pixel(player_pixel))
	# Weather turns over several times a DAY, not once per day.
	#
	# It used to roll once per weather-day, which was 25 seconds. Now that a
	# day is four real hours (SeasonCycle.SECONDS_PER_DAY) the same rule would
	# lock a whole play session into one weather state -- a player who logged
	# in during rain would see nothing but rain. Real weather turns over
	# within a day anyway, so it gets its own period.
	var day := int(_world_age_seconds / WEATHER_PERIOD_SECONDS)
	return _weather_model.weather_at(day, hash("%d_%d" % [chunk_coord.x, chunk_coord.y]))


func _loaded_tree_positions() -> Array:
	var positions: Array = []
	for trees in _loaded_trees.values():
		for tree in trees:
			positions.append(tree.position)
	return positions


## All sapling records ({position, planted_at}) across every loaded chunk --
## see Chunk.planted_trees.
func _loaded_sapling_records() -> Array:
	var records: Array = []
	for chunk in _loaded_chunks.values():
		records.append_array(chunk.planted_trees)
	return records


## Loaded tree positions eligible to forage-drop or spread seeds of their
## own (see TreeMaturity): the original map-generated forest (always mature)
## plus any spread-in sapling that's reached its own genome's maturity_time.
func _mature_tree_positions() -> Array:
	var saplings := _loaded_sapling_records()
	var sapling_positions := {}
	for sapling in saplings:
		sapling_positions[sapling.position] = true

	var original_positions: Array = []
	for position in _loaded_tree_positions():
		if not sapling_positions.has(position):
			original_positions.append(position)

	return _tree_maturity.mature_positions(original_positions, saplings, _world_age_seconds)


## Advances the world clock.
##
## Separated from step_tree_spread, which used to own it. The two have quite
## different needs once time can run fast (see TimeLapse): the CLOCK is what
## seasons, ripening and tree growth all read, so it must advance by every bit
## of simulated time -- while SPREAD adds trees to the world, and running that
## at the same multiple fills the map.
func advance_world_age(delta_seconds: float) -> void:
	_world_age_seconds += delta_seconds


## Central, throttled tree spread: every SPREAD_INTERVAL of real time, a
## small bounded number of mature trees each attempt to plant a mutated-child
## sapling nearby (see TreeSpread) -- an immature sapling can't seed yet. A
## sapling that lands in a currently-loaded chunk is spawned immediately and
## recorded on that chunk's planted_trees (persisted across unload/reload,
## see _unload_chunk/_load_chunk) with the world-age it was planted at; one
## that lands outside any loaded chunk is simply not planted.
func step_tree_spread(delta_seconds: float) -> void:
	_spread_accumulator += delta_seconds
	if _spread_accumulator < SPREAD_INTERVAL:
		return
	# Subtract one interval, then shed any surplus -- see step_forage for why
	# subtracting alone leaks once a frame outruns the interval.
	_spread_accumulator -= SPREAD_INTERVAL
	if _spread_accumulator >= SPREAD_INTERVAL:
		_spread_accumulator = fmod(_spread_accumulator, SPREAD_INTERVAL)

	var mature_positions := _mature_tree_positions()
	var all_positions := _loaded_tree_positions()
	var saplings := _tree_spread.propose_saplings(
		mature_positions, all_positions, _spread_tick, SPREAD_ATTEMPTS_PER_TICK
	)
	for sapling in saplings:
		var position: Vector2 = sapling.position
		var chunk_coord := _chunk_coord_for_tile(_world_tile_for_pixel(position))
		var chunk: Chunk = _loaded_chunks.get(chunk_coord)
		if chunk == null:
			continue
		if not _can_root_at(chunk, chunk_coord, position):
			continue
		_plant_sapling_record(chunk, chunk_coord, position)
	_spread_tick += 1


## Whether a tree can stand on the tile at `position`.
##
## Seeds only started travelling far enough for this to matter once the
## spread-radius unit bug was fixed -- before that every seed landed on its
## parent's own tile, which was necessarily land. The first thing the fix
## produced was trees standing in a lake (reported).
func _can_root_at(chunk: Chunk, chunk_coord: Vector2i, position: Vector2) -> bool:
	var tile := _world_tile_for_pixel(position)
	var local := tile - chunk_coord * CHUNK_SIZE
	if local.x < 0 or local.y < 0 or local.x >= chunk.width or local.y >= chunk.height:
		return false
	var biome_name: String = chunk.biome[local.y * chunk.width + local.x]
	return TreeRooting.can_root_in(biome_name)


## Records and spawns a freshly-planted sapling at `position` (already known
## to belong to `chunk`/`chunk_coord`): appended to that chunk's
## planted_trees (persisted across unload/reload, see _unload_chunk/
## _load_chunk) with the world-age it was planted at, and spawned as a
## seedling that thickens over TreeGrowth's stages rather than popping in
## full-grown. Shared by step_tree_spread's own ground-planted saplings and
## try_plant_seed_at's bird-dispersed ones -- from this instant on a
## bird-planted tree is indistinguishable from a ground-spread one.
func _plant_sapling_record(chunk: Chunk, chunk_coord: Vector2i, position: Vector2) -> void:
	# Backstop, not a duplicate: both callers check first, and this is the one
	# place neither can bypass. Trees in a lake got through because the single
	# path that could produce them had no check at all.
	if not _can_root_at(chunk, chunk_coord, position):
		return
	chunk.planted_trees.append({"position": position, "planted_at": _world_age_seconds})
	var tree := _tree_renderer.spawn_tree_at(_entities_parent, position, 0.0)
	# Remembered on the node so step_tree_growth can age it in place. Without
	# it a sapling only ever grew by having its chunk unloaded and reloaded.
	if "planted_at" in tree:
		tree.planted_at = _world_age_seconds
	_loaded_trees[chunk_coord].append(tree)


## ## Flies on the rot
##
## One colony per rotting ground item (see FlyColony), and one marker per adult
## in it. The colony is the model -- eggs, maggots and pupae live IN the fruit
## and are never nodes; only the adults fly, so only the adults are drawn.
##
## This is what makes a pile of rotten apples end up with a swarm that is its
## OWN offspring rather than flies conjured because a swarm was due.
var _fly_colonies: Dictionary = {}  # item node -> FlyColony
var _fly_markers: Dictionary = {}  # item node -> Array[Node2D]

## How often the colonies are stepped. Their whole life runs in days, so there
## is nothing to gain from touching them every frame.
const FLY_INTERVAL := 1.5
var _fly_accumulator := 0.0


## Advances every fly colony and keeps the drawn swarms matching them.
func step_flies(delta_seconds: float) -> void:
	_fly_accumulator += delta_seconds
	if _fly_accumulator < FLY_INTERVAL:
		return
	var elapsed := _fly_accumulator
	_fly_accumulator = 0.0
	if _ground_items == null or _entities_parent == null:
		return

	var world_flies := 0
	for markers in _fly_markers.values():
		world_flies += markers.size()

	# Rot that is still there, and what it smells of.
	var living := {}
	for item in _ground_items.get_children():
		if item.is_queued_for_deletion() or item.item_stack == null:
			continue
		if item.item_stack.item.kind != "food":
			continue
		var freshness := 1.0
		if item.has_method("spoilage"):
			freshness = 1.0 - item.spoilage()
		var mixture := Olfaction.fruit_mixture(item.item_stack.item.id, freshness)
		if not FlyLifeCycle.can_lay_on(mixture):
			continue
		living[item] = mixture

	# Colonies on rot that has gone: advanced with nothing to eat, so they run
	# out rather than vanishing the instant the apple does.
	for item in _fly_colonies.keys():
		var colony: FlyColony = _fly_colonies[item]
		var gone: bool = not living.has(item) or not is_instance_valid(item)
		colony.advance(elapsed, not gone)
		if colony.total() <= 0 or not is_instance_valid(item):
			_clear_fly_markers(item)
			_fly_colonies.erase(item)

	# A carrier walking around with something that has gone over gets its own
	# swarm: the flies follow the smell, not a fixed point on the ground.
	#
	# No colony and no breeding here -- nothing can lay eggs in a pack that
	# keeps moving, and a swarm bred in an inventory would be a strange thing
	# to own. These are flies that have simply caught the scent and stayed
	# with it.
	_sync_carrier_flies()

	# Rot with no colony yet: the first fly finds it.
	for item in living:
		if _fly_colonies.has(item):
			continue
		if not FlyLifeCycle.may_add_to_world(world_flies):
			break
		var founders := Flies.swarm_size_for(living[item], 0.0)
		if founders <= 0:
			continue
		var colony := FlyColony.new()
		# ONE founder, not a whole swarm: the swarm has to be bred, which is
		# the entire point. A pile that starts full has no loop in it.
		colony.settle(1)
		_fly_colonies[item] = colony
		world_flies += 1

	_sync_fly_markers()


## Flies trailing whoever is carrying something rotten.
##
## Keyed by the carrier rather than by a colony: the swarm follows a moving
## thing, so its markers are repositioned every step rather than orbiting a
## spot on the ground.
var _carrier_flies: Dictionary = {}


func _sync_carrier_flies() -> void:
	var season := current_season()
	for carrier in _scent_carriers:
		var wanted := 0
		if is_instance_valid(carrier) and carrier.inventory != null:
			var carried: float = carrier.inventory.rot_freshness(season)
			if carried < 1.0:
				wanted = Flies.swarm_size_for(
					Olfaction.fruit_mixture("carried", carried), 0.0
				)
		var markers: Array = _carrier_flies.get(carrier, [])
		while markers.size() > wanted:
			var spare: Node = markers.pop_back()
			if is_instance_valid(spare):
				spare.queue_free()
		while markers.size() < wanted and is_instance_valid(carrier):
			markers.append(_build_fly(carrier, markers.size()))
		if markers.is_empty():
			_carrier_flies.erase(carrier)
			continue
		_carrier_flies[carrier] = markers
		for index in markers.size():
			var marker: Node = markers[index]
			if is_instance_valid(marker) and is_instance_valid(carrier):
				marker.position = (
					carrier.position + Flies.swarm_offset(index, _world_age_seconds)
				)


## Puts exactly as many fly markers over each source as its colony has adults.
func _sync_fly_markers() -> void:
	for item in _fly_colonies:
		if not is_instance_valid(item):
			continue
		var wanted: int = _fly_colonies[item].adults()
		var markers: Array = _fly_markers.get(item, [])
		while markers.size() > wanted:
			var spare: Node = markers.pop_back()
			if is_instance_valid(spare):
				spare.queue_free()
		while markers.size() < wanted:
			markers.append(_build_fly(item, markers.size()))
		_fly_markers[item] = markers
		# Each fly orbits its own source, at its own place in the swarm.
		for index in markers.size():
			var marker: Node = markers[index]
			if not is_instance_valid(marker):
				continue
			marker.position = item.position + Flies.swarm_offset(index, _world_age_seconds)


func _build_fly(item: Node2D, index: int) -> Node2D:
	return _ambient_flyer_renderer.build_flyer(
		_entities_parent,
		"fly",
		item.position + Flies.swarm_offset(index, _world_age_seconds),
		hash("%d_%d_fly" % [int(item.position.x), index])
	)


func _clear_fly_markers(item) -> void:
	for marker in _fly_markers.get(item, []):
		if is_instance_valid(marker):
			marker.queue_free()
	_fly_markers.erase(item)


## Rots the food lying on the ground.
##
## Ground food ages on WORLD time, not wall-clock: rot is a thing the seasons
## do, so it runs on the same clock as the seasons. Otherwise a run of
## /ecotest sweeps a year past a windfall that has aged ninety seconds.
## Anything walking around with food in its pack. Registered rather than
## searched for, because the chunk manager has no business knowing what a
## Player is.
var _scent_carriers: Array = []


func register_scent_carrier(carrier) -> void:
	if carrier != null and not _scent_carriers.has(carrier):
		_scent_carriers.append(carrier)


## Ages what every carrier is holding, so food goes off in the pack on the same
## clock as food on the ground.
func step_carried_food(delta_seconds: float) -> void:
	for carrier in _scent_carriers:
		if is_instance_valid(carrier) and carrier.inventory != null:
			carrier.inventory.age_contents(delta_seconds)


func step_ground_food(delta_seconds: float) -> void:
	var season := current_season()
	for item in _entities_parent.get_tree().get_nodes_in_group(DroppedItem.GROUP_NAME):
		if not item.has_method("advance") or not ("ages_on_world_time" in item):
			continue
		if not item.ages_on_world_time:
			continue
		if item.item_stack != null:
			item.spoil_seconds = FruitSpoilage.edible_seconds(item.item_stack.item.id, season)
		item.advance(delta_seconds)


## Ages every loaded sapling, so a tree planted while you watch actually grows.
##
## `growth_scale` used to be set once at spawn and never touched again, which
## meant a sapling stayed a seedling for as long as it stayed loaded -- the
## only way to see one mature was to walk away and come back (reported as
## newborn trees not maturing properly).
##
## Only saplings: a tree with planted_at 0 predates the session and is already
## grown, so the common case costs one comparison.
func step_tree_growth() -> void:
	for trees in _loaded_trees.values():
		for tree in trees:
			if not ("planted_at" in tree) or tree.planted_at <= 0.0:
				continue
			if not tree.has_method("set_age"):
				continue
			tree.set_age(_world_age_seconds - tree.planted_at)


## How often the tall-grass sprite layer re-syncs to the simulation (and
## nearby herbivores get a chance to graze a patch). The sims themselves
## advance every call; only the node churn is throttled.
const GRASS_REFRESH_INTERVAL := 5.0

## Central tall-grass step (see TallGrass): every loaded chunk's grass sim
## grows/spreads, and on a throttled interval (1) any herbivore-role creature
## standing on a mature patch eats it, and (2) the tuft sprites are re-synced
## to the sim's patch set.
func step_tall_grass(delta_seconds: float) -> void:
	_grass_refresh_accumulator += delta_seconds
	if _grass_refresh_accumulator < GRASS_REFRESH_INTERVAL:
		return
	var elapsed := _grass_refresh_accumulator
	_grass_refresh_accumulator = 0.0

	# Advanced in ONE batched step per refresh rather than every frame. This
	# walked every loaded chunk's every patch 60 times a second -- ~5ms of
	# the frame budget, measured -- to resolve growth of 0.01 per second.
	# Growth is linear in delta and spread carries its own accumulator, so
	# the batched call lands in exactly the same state (pinned by
	# test_growth_lands_in_the_same_place_whether_batched_or_per_frame), and
	# nothing between refreshes could observe the difference anyway: the
	# sprites are only re-synced here too.
	for sim in _grass_sims.values():
		sim.advance(elapsed)

	_graze_by_herbivores()
	for chunk_coord in _grass_sims.keys():
		_sync_grass_sprites(chunk_coord)


## Whether a wild carrot (Daucus carota) is growing in the clump at `tile`.
##
## The carrot existed as an item with nothing in the world producing it, which
## left the whole taming loop unreachable in normal play (see
## docs/concept/taming.md). Wild carrot is a meadow plant that grows among the
## grasses, so it turns up where the player is already pulling grass for fibre
## -- rather than waiting on a farming system that is not wired into the game.
##
## Hash-derived rather than rolled, matching the "the same tile always answers
## the same" idiom used throughout the world sim (TallGrass, FlowerPatch,
## TreeGenome): a reloaded chunk agrees with itself.
const WILD_CARROT_CHANCE := 0.18


static func has_wild_carrot(tile: Vector2i) -> bool:
	var roll := float(absi(hash("%d_%d_wild_carrot" % [tile.x, tile.y])) % 10000) / 10000.0
	return roll < WILD_CARROT_CHANCE


## Harvests the tall-grass patch nearest `pixel_position` within
## `radius_tiles`, dropping plant fibre as a ground item (the fibre in the
## stick+shard+fibre crude-blade recipe). Returns true if a patch was
## harvested. Only mature patches yield fibre -- young shoots tear uselessly.
func harvest_grass_near(pixel_position: Vector2, radius_tiles: int = 1) -> bool:
	var center_tile := _world_tile_for_pixel(pixel_position)
	for dy in range(-radius_tiles, radius_tiles + 1):
		for dx in range(-radius_tiles, radius_tiles + 1):
			var tile := center_tile + Vector2i(dx, dy)
			var chunk_coord := _chunk_coord_for_tile(tile)
			var sim: TallGrass = _grass_sims.get(chunk_coord)
			if sim == null:
				continue
			var local := _local_coord(tile.x, tile.y)
			if sim.get_growth(local) >= 1.0 and sim.graze(local):
				var drop_position := Vector2(
					(tile.x + 0.5) * TerrainRenderer.TILE_SIZE,
					(tile.y + 0.5) * TerrainRenderer.TILE_SIZE
				)
				var fibre := ItemStack.new(
					Item.new("plant_fibre", "Plant Fibre", "material", 40), 2
				)
				WorldItemBus.item_dropped.emit(fibre, drop_position)
				# Wild carrot grows among the meadow grasses, so it comes up
				# with them (see has_wild_carrot).
				if has_wild_carrot(tile):
					WorldItemBus.item_dropped.emit(
						ItemStack.new(Item.new("carrot", "Carrot", "food", 20), 1), drop_position
					)
				_sync_grass_sprites(chunk_coord)
				return true
	return false


## Every MATURE tall-grass tuft within `radius_tiles`, in the same
## {position} shape as worms_near/seeds_near/fruit_near so GrazerForaging can
## treat all four food kinds alike -- this is what lets a hungry horse pick a
## specific tuft and walk to it (see concept/ecosystem_dynamics.md's "Grazing
## is an act, not an aura") instead of absorbing food from the biome it
## happens to be standing on.
##
## Only mature patches are reported, for the same reason harvest_grass_near
## only yields fibre from them: TallGrass.graze is what the animal will
## actually call on arrival, and offering a shoot it cannot crop would send
## it walking to a meal that isn't there.
##
## Scans the 3x3 chunk neighbourhood rather than every loaded chunk, the same
## bound and the same reason as flowers_near: this runs per grazer per sniff.
func grass_near(pixel_position: Vector2, radius_tiles: int = 8) -> Array:
	var out: Array = []
	var center := _world_tile_for_pixel(pixel_position)
	var center_chunk := _chunk_coord_for_tile(center)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var chunk_coord := center_chunk + Vector2i(dx, dy)
			var sim: TallGrass = _grass_sims.get(chunk_coord)
			if sim == null:
				continue
			var origin := chunk_coord * CHUNK_SIZE
			for cell in sim.get_patch_cells():
				if sim.get_growth(cell) < 1.0:
					continue
				var tile: Vector2i = origin + cell
				if maxi(absi(tile.x - center.x), absi(tile.y - center.y)) > radius_tiles:
					continue
				out.append({
					"position": Vector2(
						float(tile.x) + 0.5, float(tile.y) + 0.5
					) * float(TerrainRenderer.TILE_SIZE),
				})
	return out


## Crops the tuft at `pixel_position`, returning whether there was a mature
## one to take -- the mutation counterpart of grass_near, mirroring
## take_worm_at/take_seed_at.
func graze_grass_at(pixel_position: Vector2) -> bool:
	var tile := _world_tile_for_pixel(pixel_position)
	var chunk_coord := _chunk_coord_for_tile(tile)
	var sim: TallGrass = _grass_sims.get(chunk_coord)
	if sim == null:
		return false
	var cell := tile - chunk_coord * CHUNK_SIZE
	if sim.get_growth(cell) < 1.0:
		return false
	if not sim.graze(cell):
		return false
	# Refresh THIS chunk immediately rather than waiting for the next
	# throttled step, the same reasoning as take_worm_at/take_seed_at: the
	# player just watched the animal eat it, so it has to vanish on that
	# frame rather than seconds later.
	_sync_grass_sprites(chunk_coord)
	return true


## Any herbivore-role creature standing on a mature grass patch's tile eats
## it -- the "tall grass is eaten by herbivores" loop, driven by where the
## creatures' own AI already took them rather than a separate seek behavior.
func _graze_by_herbivores() -> void:
	for chunk_key in _loaded_creatures.keys():
		var chunk_coord: Vector2i = chunk_key
		var sim: TallGrass = _grass_sims.get(chunk_coord)
		if sim == null:
			continue
		for creature in _loaded_creatures[chunk_coord]:
			if creature.info == null or creature.info.is_predator:
				continue
			var tile := _world_tile_for_pixel(creature.position)
			var local: Vector2i = tile - chunk_coord * CHUNK_SIZE
			if sim.get_growth(local) >= 1.0:
				sim.graze(local)
			_step_seed_dispersal(creature)


## Flowers spread on the backs of grazing animals (see SeedDispersal /
## flora.md#spread-by-animal-seed-dispersal). Run from the same throttled
## herbivore walk as grazing rather than per-frame: a herbivore brushing a
## bloom picks its seed up, and once it has wandered its own carry distance
## away it drops it. Tying this to real grazer movement is the point -- a
## region that loses its herbivores stops spreading flowers.
func _step_seed_dispersal(creature) -> void:
	var season := current_season()
	if creature.carried_seed_species == "":
		var picked := SeedDispersal.pickup_species(
			creature.position,
			flowers_near(creature.position, 2),
			season,
			TerrainRenderer.TILE_SIZE,
			creature.wander_seed
		)
		if picked != "":
			creature.carried_seed_species = picked
			creature.carried_seed_origin = creature.position
		return

	# Carrying: drop once it has actually travelled its own carry distance,
	# so seed lands somewhere new rather than back on its parent.
	var carried_tiles: float = (
		creature.position.distance_to(creature.carried_seed_origin) / float(TerrainRenderer.TILE_SIZE)
	)
	if carried_tiles < SeedDispersal.carry_distance_tiles(creature.wander_seed):
		return
	plant_flower_at(creature.position, creature.carried_seed_species)
	creature.carried_seed_species = ""


## Adds/removes tuft sprites so the rendered layer matches the sim's patch
## set; a growing patch is scaled by its growth so grass visibly rises.
## How far out decoration is drawn, derived from what the camera actually
## frames (see DecorationLod.radius_chunks) rather than fixed at a guess, so
## changing the zoom or the window size can never leave the radius too small
## and start showing bare ground at the edges. Falls back to the derived
## default if there is no viewport to ask (headless tests).
func _derive_decoration_radius() -> int:
	var viewport_size := Vector2(DEFAULT_VIEWPORT_SIZE)
	if _tile_map_layer != null and _tile_map_layer.is_inside_tree():
		viewport_size = _tile_map_layer.get_viewport_rect().size
	# Asked in TILES rather than measured off raw viewport pixels: with
	# `canvas_items` stretch the viewport reports the window's real size while
	# the canvas is scaled to match, so pixels alone would say a 4K player
	# sees three times as much world as a 720p one. They see the same amount
	# (see DisplayScaling.visible_tiles_across).
	var across := DisplayScaling.visible_tiles_across(viewport_size.x, viewport_size.y)
	var down := DisplayScaling.visible_tiles_across(viewport_size.y, viewport_size.y)
	return DecorationLod.radius_chunks(Vector2(across, down) * 0.5, CHUNK_SIZE)


## Whether this chunk is close enough to the player to be worth drawing (see
## DecorationLod). Chunks that fail this keep simulating -- their grass grows
## and their worms surface exactly as before -- they just carry no sprites
## while nobody can see them.
func _decorates(chunk_coord: Vector2i) -> bool:
	return DecorationLod.keeps_decoration(chunk_coord, _decoration_center, _decoration_radius)


## Frees every sprite this chunk is holding in `holder`, for when it drops out
## of decoration range. Without this the sprites would simply stop being
## updated while staying on screen forever.
func _drop_decoration(holder: Dictionary, chunk_coord: Vector2i) -> void:
	var sprites: Dictionary = holder.get(chunk_coord, {})
	if sprites.is_empty():
		return
	for sprite in sprites.values():
		sprite.queue_free()
	holder[chunk_coord] = {}


func _sync_grass_sprites(chunk_coord: Vector2i) -> void:
	if not _decorates(chunk_coord):
		_drop_decoration(_grass_sprites, chunk_coord)
		return
	var sim: TallGrass = _grass_sims.get(chunk_coord)
	var sprites: Dictionary = _grass_sprites.get(chunk_coord, {})
	if sim == null:
		return

	for cell in sprites.keys().duplicate():
		if not sim.has_grass(cell):
			sprites[cell].free()
			sprites.erase(cell)

	var origin := chunk_coord * CHUNK_SIZE
	for cell in sim.get_patch_cells():
		var seed_value := hash("%d_%d_grass_tuft" % [origin.x + cell.x, origin.y + cell.y])
		# Per-seed, not a single flat constant: each tuft's rolled variant
		# (see ProceduralGrassSprite.VARIANTS) sets its own world-space
		# height between 0.75 and 1.5 tiles, so a meadow shows real height
		# variety instead of identically-sized clumps.
		var base_scale := ProceduralGrassSprite.world_scale_for_seed(seed_value)
		if not sprites.has(cell):
			var sprite := Sprite2D.new()
			sprite.texture = _grass_sprite_generator.generate_texture(seed_value)
			sprite.scale = Vector2.ONE * base_scale
			# Anchor at the blade BASE, not the sprite's middle. Blades are
			# drawn in the lower part of the canvas, so a centred sprite has
			# its origin ABOVE its own visible grass -- Y-sort then treats
			# the tuft as standing further north than it looks and it draws
			# behind a player whose feet are actually further back. Same
			# anchor bug, and same fix, as TreeRenderer's canopy.
			sprite.offset.y = -float(ProceduralGrassSprite.SIZE.y) * 0.5
			# Blades sway in the wind (shared GPU shader, see WindSway).
			sprite.material = _wind_sway.tuft_material()
			sprite.position = Vector2(
				(origin.x + cell.x + 0.5) * TerrainRenderer.TILE_SIZE,
				(origin.y + cell.y + 0.5) * TerrainRenderer.TILE_SIZE
			)
			_entities_parent.add_child(sprite)
			sprites[cell] = sprite
		# Growth MULTIPLIES onto the base world scale above -- it must never
		# replace it outright, or a mature patch (growth 1.0) renders at the
		# full oversized art canvas instead of its intended clump size (see
		# test_a_mature_grass_tuft_stays_at_its_intended_world_scale).
		sprites[cell].scale = Vector2.ONE * base_scale * maxf(0.3, sim.get_growth(cell))


## Adds/removes a Sprite2D per flower cell so the rendered blooms match the
## chunk's FlowerPatch. Unlike grass tufts there is no growth animation --
## a flower is either there or it isn't -- so this only ever adds newly
## planted ones (see SeedDispersal) and frees any that were removed.
## How big a bloom is drawn: THIS PLANT's size -- its species' world size
## nudged by the plant's own variance, so a bed does not read as stamped-out
## copies -- scaled down while it is still growing (see
## ProceduralFlowerSprite.growth_scale).
func _flower_scale_for(species: String, growth: float, seed_value: int) -> Vector2:
	return (
		Vector2.ONE
		* ProceduralFlowerSprite.plant_scale_for(species, seed_value)
		* ProceduralFlowerSprite.growth_scale(growth)
	)


func _sync_flower_sprites(chunk_coord: Vector2i) -> void:
	if not _decorates(chunk_coord):
		_drop_decoration(_flower_sprites, chunk_coord)
		return
	var patch: FlowerPatch = _flower_patches.get(chunk_coord)
	var sprites: Dictionary = _flower_sprites.get(chunk_coord, {})
	if patch == null:
		return

	# Only what is actually IN BLOOM right now gets drawn (see
	# FlowerPatch.blooming_cells): a flower on screen must be one a
	# pollinator will actually visit, or the world is lying about what it is
	# offering. The plant is still planted and still simulated when its
	# sprite is gone -- it just isn't blooming this season. SEED is its own
	# ground entity that falls from the plant (see _sync_seed_sprites), not a
	# state of the flower sprite.
	var in_bloom := {}
	for cell in patch.blooming_cells(current_season()):
		in_bloom[cell] = true

	for cell in sprites.keys().duplicate():
		if not patch.has_flower(cell) or not in_bloom.has(cell):
			sprites[cell].free()
			sprites.erase(cell)

	var origin := chunk_coord * CHUNK_SIZE
	for cell in in_bloom.keys():
		if sprites.has(cell):
			continue
		var species: String = patch.species_at(cell)
		var seed_value := hash("%d_%d_flower" % [origin.x + cell.x, origin.y + cell.y])
		var sprite := Sprite2D.new()
		sprite.texture = _flower_sprite_generator.generate_texture(
			species,
			seed_value,
			patch.nectar_at(cell),
			FlowerBloom.is_withered(species, _season_cycle.year_fraction(_world_age_seconds))
		)
		# Per-species world scale, derived from a world-space constant rather
		# than the art canvas -- raising the canvas for detail must never
		# change how big a flower looks (a trap this project has hit twice).
		sprite.scale = _flower_scale_for(species, patch.growth_at(cell), seed_value)
		# Anchor at the stem's foot so flowers Y-sort against the player like
		# trees do, rather than sorting from their middle.
		sprite.offset.y = -float(ProceduralFlowerSprite.SIZE.y) * 0.5
		# Blooms nod in the wind on the shared GPU material (see WindSway).
		sprite.material = _wind_sway.tuft_material()
		sprite.position = Vector2(
			(origin.x + cell.x + 0.5) * TerrainRenderer.TILE_SIZE,
			(origin.y + cell.y + 0.5) * TerrainRenderer.TILE_SIZE
		)
		_entities_parent.add_child(sprite)
		sprites[cell] = sprite

	# Seedlings grow, so an already-drawn bloom is re-scaled rather than left
	# at whatever size it was created at (see FlowerPatch.growth_at). Cheap:
	# this runs on the same throttled refresh the sprite diff does, and a
	# flower takes a quarter of an hour to grow up.
	for cell in sprites.keys():
		# The same seed the sprite was generated from, so a plant keeps its
		# own size across re-scales rather than changing size as it grows.
		var cell_seed := hash("%d_%d_flower" % [origin.x + cell.x, origin.y + cell.y])
		sprites[cell].scale = _flower_scale_for(
			patch.species_at(cell), patch.growth_at(cell), cell_seed
		)


## How much this chunk's flowers should boost pollinator spawning (see
## ScentField.pollinator_spawn_multiplier).
##
## Sampled at the STRONGEST bloom, not at the chunk's centre. Centre-sampling
## made attraction effectively all-or-nothing: a lone flower off in a corner
## sits outside ScentField.RADIUS_TILES of the centre and so contributed
## exactly zero, meaning a single bloom attracted nothing at all. Taking the
## peak keeps the response continuous with how much is actually growing --
## one flower gives a small boost, a clump a larger one, a full meadow the
## most (bounded by MAX_SPAWN_MULTIPLIER) -- because concentration_at itself
## superposes at each sample point.
##
## Note the ordering dependency -- _load_chunk creates the FlowerPatch before
## it spawns flyers, so the meadow already exists when this is asked.
## Cap on how many blooms are probed when scoring a chunk (see below).
const _POLLINATOR_PROBE_LIMIT := 8


func _pollinator_multiplier_for(chunk_coord: Vector2i) -> float:
	var patch: FlowerPatch = _flower_patches.get(chunk_coord)
	if patch == null:
		return 1.0
	var origin := chunk_coord * CHUNK_SIZE
	var flowers := patch.flowers_for_field(origin, TerrainRenderer.TILE_SIZE)
	if flowers.is_empty():
		return 1.0
	var season := current_season()
	# Probe a bounded SUBSET of blooms rather than every one: this is
	# O(probes x flowers), and probing all 40 flowers against each other was
	# ~64k distance checks per chunk load, x25 chunks at startup. Sampling
	# evenly across the list still finds a dense patch, because
	# concentration_at at any bloom inside a clump already sums its
	# neighbours.
	var probe_count: int = mini(flowers.size(), _POLLINATOR_PROBE_LIMIT)
	var stride: int = maxi(1, flowers.size() / probe_count)
	var peak := 0.0
	var i := 0
	while i < flowers.size():
		peak = maxf(
			peak,
			ScentField.concentration_at(
				flowers[i]["position"], flowers, season, float(TerrainRenderer.TILE_SIZE)
			)
		)
		i += stride
	return ScentField.pollinator_spawn_multiplier(peak)


## Every blooming flower within `radius_tiles` of `pixel_position`, in the
## shape ScentField and SeedDispersal expect.
##
## Scans only the CHUNK NEIGHBOURHOOD around the query point, not every
## loaded chunk. This is called by every pollinator twice a second and by
## every grazing herbivore, so walking all ~25 loaded chunks' flower lists
## each time was a real per-frame cost (it showed up as lag as soon as
## steering was wired). The radius is far smaller than a chunk, so the 3x3
## neighbourhood is a strict superset of what can possibly be in range.
func flowers_near(pixel_position: Vector2, radius_tiles: int = 8) -> Array:
	var out: Array = []
	var season_name := current_season()
	var year_fraction := _season_cycle.year_fraction(_world_age_seconds)
	var center := _world_tile_for_pixel(pixel_position)
	var center_chunk := _chunk_coord_for_tile(center)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var chunk_coord := center_chunk + Vector2i(dx, dy)
			var patch: FlowerPatch = _flower_patches.get(chunk_coord)
			if patch == null:
				continue
			var origin := chunk_coord * CHUNK_SIZE
			# Only blooms actually IN FLOWER this season, and only ones that
			# have not visibly gone over.
			#
			# This iterated every planted cell, while the renderer only ever
			# DREW patch.blooming_cells(season) -- so pollinators flew to
			# flowers that were out of season and not on screen at all, and
			# landed on ones drawn wilted (reported: butterflies and bees
			# foraging withered and spent flowers). Neither is the omniscience
			# the candidate search guards against: a bee can see whether a
			# plant is in flower.
			for cell in patch.blooming_cells(season_name):
				var tile: Vector2i = origin + cell
				if maxi(absi(tile.x - center.x), absi(tile.y - center.y)) > radius_tiles:
					continue
				# WITHERED, not drained. A flower that has just been emptied
				# refills in about a minute and its local pollinators come
				# back to it; one that has gone over is done for the year.
				if not PollinatorForaging.is_worth_visiting(
					FlowerBloom.is_withered(patch.species_at(cell), year_fraction)
				):
					continue
				var species: String = patch.species_at(cell)
				var flower_position := Vector2(
					float(tile.x) + 0.5, float(tile.y) + 0.5
				) * float(TerrainRenderer.TILE_SIZE)
				# Same seed the sprite was generated with, so the landing
				# point matches the blossom this flower actually drew.
				var sprite_seed := hash("%d_%d_flower" % [tile.x, tile.y])
				out.append({
					"position": flower_position,
					"species": species,
					"nectar": patch.nectar_at(cell),
					# Where a pollinator should settle: on the bloom, not at
					# the stem's foot (which is what "position" is).
					"landing": flower_position - Vector2(
						0.0, ProceduralFlowerSprite.blossom_height_world(species, sprite_seed)
					),
				})
	return out


## Where each live pollinator has announced it is heading (see ForageClaims).
##
## The three methods below are the duck-typed surface the markers already
## reach through their `scent_world` -- they are handed `self`, exactly like
## flowers_near/drink_nectar_at -- so no new plumbing is needed to give a
## flyer a view of what its neighbours are doing. Held here rather than on the
## markers because it has to be SHARED between them, and because the chunk
## lifecycle (which already owns spawn/despawn) is the only place that can
## reliably clean it up.
var _forage_claims := ForageClaims.new()


func claim_flower(flower_position: Vector2, flyer_id: int) -> void:
	_forage_claims.claim(flower_position, flyer_id)


func release_flower_claim(flyer_id: int) -> void:
	_forage_claims.release(flyer_id)


## An animal was born at this world position -- tells whichever region owns
## that spot (see EcosystemSimulation.record_birth). The individual half of
## the simulation reporting to the aggregate half, so a herd the player
## watched grow is still there after the chunk unloads and reloads.
func record_birth_at(position: Vector2, count: float = 1.0) -> void:
	_ecosystem.record_birth(_chunk_coord_for_tile(_world_tile_for_pixel(position)), count)


## A courting pair produced young (see Courtship / AmbientFlyerMarker).
##
## Two things happen, and both matter. The offspring is spawned as a real
## flyer, so the player watching a dance sees a third butterfly appear. AND
## the region's aggregate population is told about it (see
## EcosystemSimulation.record_birth), so the birth is not lost the moment the
## chunk unloads -- the individual and aggregate halves of the simulation are
## the same population seen at two fidelities, not two separate worlds.
func spawn_flyer_offspring(species: String, position: Vector2) -> void:
	var chunk_coord := _chunk_coord_for_tile(_world_tile_for_pixel(position))
	if not _loaded_ambient_flyers.has(chunk_coord):
		return
	# A meadow supports what it supports. Births with no ceiling is how the
	# deer explosion started, and courting butterflies breed far faster than
	# deer do -- measured climbing steadily across a single session before
	# this cap existed.
	if _loaded_ambient_flyers[chunk_coord].size() >= AmbientFlyerRenderer.max_flyers_per_chunk():
		return
	var offspring := _ambient_flyer_renderer.spawn_offspring(
		_creatures_parent, species, position,
		hash("%d_%d_%d_offspring" % [int(position.x), int(position.y), _loaded_ambient_flyers[chunk_coord].size()]),
		self
	)
	if offspring == null:
		return
	offspring.courtship_world = self
	_loaded_ambient_flyers[chunk_coord].append(offspring)
	_ecosystem.record_birth(chunk_coord, 1.0)


func claims_near(position: Vector2, radius: float, exclude_flyer_id: int) -> Array:
	return _forage_claims.claimed_positions_near(position, radius, exclude_flyer_id)


## Drains the bloom at `pixel_position`, if there is one with nectar left
## (see FlowerPatch.drink). Returns true if the pollinator actually got a
## drink -- which is what stops it sitting on an empty flower.
func drink_nectar_at(pixel_position: Vector2) -> bool:
	var tile := _world_tile_for_pixel(pixel_position)
	var chunk_coord := _chunk_coord_for_tile(tile)
	var patch: FlowerPatch = _flower_patches.get(chunk_coord)
	if patch == null:
		return false
	return patch.drink(tile - chunk_coord * CHUNK_SIZE)


## Refills drained nectar across every loaded meadow.
func step_flowers(delta: float) -> void:
	var season := current_season()
	for chunk_coord in _flower_patches:
		var patch: FlowerPatch = _flower_patches[chunk_coord]
		patch.advance(delta)
		# Plants past their bloom drop seed around themselves, which lies in the
		# grass as its own entity for a granivore to find (see
		# FlowerPatch.shed_seed / concept/flora.md).
		var before: int = patch.ground_seed_cells().size()
		patch.shed_seed(delta, season)
		if patch.ground_seed_cells().size() != before:
			_sync_seed_sprites(chunk_coord)
	# Which flowers are in bloom changes with the season, and sprites are
	# otherwise only built at chunk load -- without this a meadow would keep
	# showing last season's blooms (or stay bare through the season its own
	# species finally open) until the player walked far enough away to
	# unload the chunk. Cheap: only re-syncs when the season name actually
	# changes, which is a handful of times per in-game year.
	if season == _last_flower_bloom_season:
		return
	_last_flower_bloom_season = season
	for chunk_coord in _flower_patches.keys():
		_sync_flower_sprites(chunk_coord)


func _sync_tree_season(season_name: String) -> void:
	# The TURN, not just the season name.
	#
	# This only ever fired when the season NAME changed, so every tree in the
	# world swapped canopies on one frame -- which is exactly the instant
	# change the gradual transition was built to remove, and the blend sat
	# there unused because nothing ever passed it a progress. It now re-syncs
	# whenever the turn advances a step (SeasonTransition quantises progress
	# precisely so that is a handful of times, not every frame).
	var turn := SeasonTransition.state_at(_season_cycle.year_fraction(_world_age_seconds))
	var signature := "%s/%s/%.2f" % [season_name, turn.to, turn.progress]
	if signature == _last_tree_season:
		return
	_last_tree_season = signature
	_tree_renderer.season = season_name
	_tree_renderer.turning_into = turn.to
	_tree_renderer.turn_progress = turn.progress
	for trees in _loaded_trees.values():
		for tree in trees:
			if tree.has_method("set_ripe_fruit"):
				tree.set_ripe_fruit(
					tree.ripe_fruit_count(), season_name, turn.to, turn.progress
				)


## The season the loaded trees were last drawn for -- see _sync_tree_season.
var _last_tree_season := ""


## The season the flower sprite layer was last rebuilt for -- see
## step_flowers.
var _last_flower_bloom_season := ""


## How often the worm sprite layer re-syncs to the simulation, and how often
## each chunk's weather/season conditions are refreshed. The sims themselves
## advance every call; only node churn and the (day-timescale) condition
## lookup are throttled. Mirrors GRASS_REFRESH_INTERVAL -- a node-churn
## throttle, not an ecology tunable.
const WORM_REFRESH_INTERVAL := 5.0
var _worm_refresh_accumulator := 0.0


## Every surfaced worm within `radius_tiles` of `pixel_position`, in the shape
## a ground-foraging bird expects (see GroundForageBehavior / AmbientFlyerMarker).
##
## Scans only the 3x3 CHUNK NEIGHBOURHOOD around the query point, not every
## loaded chunk -- the same bound (and the same reason) as flowers_near: this
## runs per bird per sniff, and walking all ~25 loaded chunks each time is a
## real per-frame cost. GroundForageBehavior.SEARCH_TILES is far smaller than
## a chunk, so the neighbourhood is a strict superset of what can be in range.
##
## Only worms that are actually UP are reported (see EarthwormPatch.is_surfaced),
## so the list a bird hunts from is exactly the set of sprites the player can
## see on the ground.
func worms_near(pixel_position: Vector2, radius_tiles: int = 8) -> Array:
	var out: Array = []
	var center := _world_tile_for_pixel(pixel_position)
	var center_chunk := _chunk_coord_for_tile(center)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var chunk_coord := center_chunk + Vector2i(dx, dy)
			var patch: EarthwormPatch = _worm_patches.get(chunk_coord)
			if patch == null:
				continue
			var origin := chunk_coord * CHUNK_SIZE
			for cell in patch.worm_cells():
				if not patch.is_surfaced(cell):
					continue
				var tile: Vector2i = origin + cell
				if maxi(absi(tile.x - center.x), absi(tile.y - center.y)) > radius_tiles:
					continue
				out.append({
					"position": Vector2(
						float(tile.x) + 0.5, float(tile.y) + 0.5
					) * float(TerrainRenderer.TILE_SIZE),
				})
	return out


## Eats the worm at `pixel_position`, if there is one at the surface there
## (see EarthwormPatch.take). Returns true if the bird actually got it -- the
## mutation counterpart of worms_near, mirroring drink_nectar_at.
## Every plant within `radius_tiles` that has gone to SEED this season (see
## FlowerPatch.seed_cells / concept/flora.md "Seed: the other half of a
## flower's year"), in the shape a granivorous bird expects -- the same
## {position, species} shape worms_near/fruit_near use, so GroundForage
## can treat all three the same way.
func seeds_near(pixel_position: Vector2, radius_tiles: int = 8) -> Array:
	var out: Array = []
	var center := _world_tile_for_pixel(pixel_position)
	var center_chunk := _chunk_coord_for_tile(center)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var chunk_coord := center_chunk + Vector2i(dx, dy)
			var patch: FlowerPatch = _flower_patches.get(chunk_coord)
			if patch == null:
				continue
			var origin := chunk_coord * CHUNK_SIZE
			for cell in patch.ground_seed_cells():
				var tile: Vector2i = origin + cell
				if maxi(absi(tile.x - center.x), absi(tile.y - center.y)) > radius_tiles:
					continue
				out.append({
					"position": Vector2(
						float(tile.x) + 0.5, float(tile.y) + 0.5
					) * float(TerrainRenderer.TILE_SIZE),
					"species": patch.species_of_ground_seed(cell),
				})
	return out


## Takes the seed at this position, returning the SPECIES id eaten (""
## when there was nothing). The species matters because the bird carries it
## and plants it again later -- see SeedEndozoochory / plant_flower_at.
func take_seed_at(pixel_position: Vector2) -> String:
	var tile := _world_tile_for_pixel(pixel_position)
	var chunk_coord := _chunk_coord_for_tile(tile)
	var patch: FlowerPatch = _flower_patches.get(chunk_coord)
	if patch == null:
		return ""
	var species: String = patch.take_ground_seed(tile - chunk_coord * CHUNK_SIZE)
	if species == "":
		return ""
	# Refresh THIS chunk immediately rather than waiting for the next step, the
	# same reasoning as take_worm_at: the player just watched a bird peck it
	# up, so the seed must vanish on that frame, not seconds later.
	_sync_seed_sprites(chunk_coord)
	return species


## Adds/removes a Sprite2D per shed seed so what is rendered matches the
## chunk's FlowerPatch. Same diff-against-the-sim shape as the flower and
## worm layers.
func _sync_seed_sprites(chunk_coord: Vector2i) -> void:
	if not _decorates(chunk_coord):
		_drop_decoration(_seed_sprites, chunk_coord)
		return
	var patch: FlowerPatch = _flower_patches.get(chunk_coord)
	var sprites: Dictionary = _seed_sprites.get(chunk_coord, {})
	if patch == null:
		return
	var present := {}
	for cell in patch.ground_seed_cells():
		present[cell] = true
	for cell in sprites.keys().duplicate():
		if not present.has(cell):
			sprites[cell].free()
			sprites.erase(cell)
	var origin := chunk_coord * CHUNK_SIZE
	for cell in present:
		if sprites.has(cell):
			continue
		# A PickableSeed rather than a bare Sprite2D: a seed you can take is
		# what makes deliberate planting possible, and it costs nothing but
		# joining the group the pickup sweep already reads.
		var sprite := PickableSeed.new()
		sprite.species = patch.species_of_ground_seed(cell)
		sprite.cell = cell
		sprite.seed_world = patch
		sprite.texture = ProceduralSeedSprite.generate_texture(
			patch.species_of_ground_seed(cell),
			hash("%d_%d_seed" % [origin.x + cell.x, origin.y + cell.y])
		)
		sprite.scale = Vector2.ONE * ProceduralSeedSprite.world_scale()
		# Anchored at its own footprint so it Y-sorts against whoever walks
		# over it, like worms and flowers do.
		sprite.offset.y = -float(ProceduralSeedSprite.SIZE.y) * 0.5
		sprite.position = Vector2(
			(origin.x + cell.x + 0.5) * TerrainRenderer.TILE_SIZE,
			(origin.y + cell.y + 0.5) * TerrainRenderer.TILE_SIZE
		)
		_entities_parent.add_child(sprite)
		sprites[cell] = sprite
	_seed_sprites[chunk_coord] = sprites


func take_worm_at(pixel_position: Vector2) -> bool:
	var tile := _world_tile_for_pixel(pixel_position)
	var chunk_coord := _chunk_coord_for_tile(tile)
	var patch: EarthwormPatch = _worm_patches.get(chunk_coord)
	if patch == null:
		return false
	if not patch.take(tile - chunk_coord * CHUNK_SIZE):
		return false
	# Re-sync THIS chunk immediately rather than waiting for the next
	# WORM_REFRESH_INTERVAL tick, the same way plant_flower_at does after
	# planting. Found by a live runtime probe: it reported 59 rendered worms
	# against 56 actually at the surface, i.e. worms robins had already eaten
	# went on lying in the grass for up to five more seconds. The player
	# watching the bird peck would have seen the worm stay exactly where it
	# was, which undermines the whole point of the mechanic. The refresh
	# interval is a throttle on BACKGROUND node churn; an eaten worm is a
	# direct consequence of something the player just watched happen.
	_sync_worm_sprites(chunk_coord)
	return true


## Every fallen, NAMED-SPECIES tree-fruit item lying within `radius_tiles` of
## `pixel_position` (see TreeSpecies -- cherry/apple/walnut, dropped via
## step_fruiting), in the shape a fruit-eating bird expects (see
## GroundForageBehavior / AmbientFlyerMarker.fruit_world / SeedEndozoochory).
##
## Reads World's own already-rendered ground items (see set_ground_items)
## rather than a second, parallel model -- the same real DroppedItem nodes
## the player can see and click are exactly what a bird can peck at. Fails
## open to an empty list if ground items were never registered (matching
## _water_layer/_roof_layer's optional-setter convention), so a world that
## predates this still forages, just without fruit.
func fruit_near(pixel_position: Vector2, radius_tiles: int = 8) -> Array:
	var out: Array = []
	if _ground_items == null:
		return out
	var radius_px := float(radius_tiles) * TerrainRenderer.TILE_SIZE
	for item in _ground_items.get_children():
		if item.is_queued_for_deletion() or item.item_stack == null:
			continue
		var id: String = item.item_stack.item.id
		if not TreeSpecies.IDS.has(id):
			continue
		if item.position.distance_to(pixel_position) > radius_px:
			continue
		out.append({"position": item.position, "species": id})
	return out


## Every food on the ground near here, with what it SMELLS of (see Olfaction).
##
## Distinct from fruit_near, which answers "what food is within sight": this
## answers "what can be smelled from here", which reaches much further and
## carries the mixture rather than just the species. What an animal makes of
## that mixture is its own business -- a rotting apple is a meal to a fly and
## a thing to avoid for a deer.
func smells_near(pixel_position: Vector2, radius_tiles: float) -> Array:
	var out: Array = []
	if _ground_items == null:
		return out
	var season := current_season()
	var radius_px := radius_tiles * TerrainRenderer.TILE_SIZE
	# A player carrying something that has gone over smells of it, which is
	# what lets flies follow them (see Inventory.rot_freshness).
	for carrier in _scent_carriers:
		if not is_instance_valid(carrier) or carrier.inventory == null:
			continue
		if carrier.position.distance_to(pixel_position) > radius_px:
			continue
		var carried: float = carrier.inventory.rot_freshness(season)
		if carried >= 1.0:
			continue
		out.append({
			"position": carrier.position,
			"mixture": Olfaction.fruit_mixture("carried", carried),
			"species": "",
		})
	for item in _ground_items.get_children():
		if item.is_queued_for_deletion() or item.item_stack == null:
			continue
		if item.item_stack.item.kind != "food":
			continue
		if item.position.distance_to(pixel_position) > radius_px:
			continue
		var freshness := 1.0
		if item.has_method("spoilage"):
			freshness = 1.0 - item.spoilage()
		out.append({
			"position": item.position,
			"mixture": Olfaction.fruit_mixture(item.item_stack.item.id, freshness),
			"species": item.item_stack.item.id,
		})
	return out


## Eats the named-species fruit item standing at `pixel_position`, if there is
## one (see fruit_near). Returns the species eaten, or "" if there was
## nothing there -- the mutation counterpart of fruit_near, mirroring
## take_worm_at, but returning the species rather than a bool since the
## caller needs to know WHAT it just swallowed to carry the right seed.
func take_fruit_at(pixel_position: Vector2) -> String:
	if _ground_items == null:
		return ""
	for item in _ground_items.get_children():
		if item.is_queued_for_deletion() or item.item_stack == null:
			continue
		var id: String = item.item_stack.item.id
		if not TreeSpecies.IDS.has(id):
			continue
		if item.position.distance_to(pixel_position) > 1.0:
			continue
		item.queue_free()
		return id
	return ""


## Plants a sapling of `species_id` at `pixel_position`, if a tree can
## actually establish there (see SeedEndozoochory.can_root_in -- forest/
## rainforest only) and the chunk is loaded. The bird-endozoochory
## counterpart of step_tree_spread's own per-sapling planting, reusing the
## same _plant_sapling_record sink so a bird-planted tree behaves exactly
## like a ground-spread one from this point on (ages up via TreeGrowth,
## persists via Chunk.planted_trees, forages/spreads again once mature).
##
## Species, like every other tree trait in this codebase, is still derived
## from the LANDING position's own genome (see TreeRenderer._texture_for) --
## a bird-planted sapling is not force-inherited from the exact fruit eaten,
## the same "no stored per-tree genome, position derives everything" model
## TreeSpread's own ground-planted saplings already follow (see
## docs/concept/flora.md#bird-endozoochory for the tradeoff this accepts).
func try_plant_seed_at(pixel_position: Vector2, _species_id: String) -> bool:
	var tile := _world_tile_for_pixel(pixel_position)
	var chunk_coord := _chunk_coord_for_tile(tile)
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk == null:
		return false
	if not SeedEndozoochory.can_root_in(biome_at_global(tile.x, tile.y)):
		return false
	var position := Vector2(
		(tile.x + 0.5) * TerrainRenderer.TILE_SIZE, (tile.y + 0.5) * TerrainRenderer.TILE_SIZE
	)
	for existing in _loaded_tree_positions():
		if position.distance_to(existing) < TreeSpread.MIN_TREE_SPACING:
			return false
	# The same three-per-tile ceiling ground spread respects: a bird-planted
	# tree is indistinguishable from a ground-spread one from this instant on,
	# so it has to arrive under the same rules.
	if _trees_on_tile(tile) >= TreeSpread.MAX_TREES_PER_TILE:
		return false
	_plant_sapling_record(chunk, chunk_coord, position)
	return true


## How many trees already stand on this tile.
func _trees_on_tile(tile: Vector2i) -> int:
	var standing := 0
	for position in _loaded_tree_positions():
		if _world_tile_for_pixel(position) == tile:
			standing += 1
	return standing


## Central earthworm step (see EarthwormPatch): every loaded chunk's soil
## advances every call, while the weather/season conditions driving surfacing
## and the sprite layer refresh on the slower WORM_REFRESH_INTERVAL.
func step_worms(delta_seconds: float) -> void:
	for patch in _worm_patches.values():
		patch.advance(delta_seconds)
	_crawl_worm_sprites()

	_worm_refresh_accumulator += delta_seconds
	if _worm_refresh_accumulator < WORM_REFRESH_INTERVAL:
		return
	_worm_refresh_accumulator = 0.0

	var season_warmth := _season_cycle.warmth_modifier(_world_age_seconds)
	for chunk_coord in _worm_patches:
		var patch: EarthwormPatch = _worm_patches[chunk_coord]
		# Sampled per CHUNK, not once for the player's tile: weather is
		# already a per-region roll (see current_weather), and the climate
		# temperature genuinely differs across a loaded neighbourhood.
		var centre_tile: Vector2i = chunk_coord * CHUNK_SIZE + Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2)
		var centre_pixel := Vector2(
			float(centre_tile.x) + 0.5, float(centre_tile.y) + 0.5
		) * float(TerrainRenderer.TILE_SIZE)
		var climate := clampf(
			generator.temperature_at_global(centre_tile.x, centre_tile.y), 0.0, 1.0
		)
		patch.set_conditions(
			_weather_model.soil_moisture(current_weather(centre_pixel)),
			EarthwormPatch.soil_warmth(climate, season_warmth)
		)
		_sync_worm_sprites(chunk_coord)


## Inches every surfaced worm along, every frame. A worm at the surface is
## not a decal -- it crawls, slowly, within its own cell (see
## EarthwormPatch.crawl_offset for why the CELL never changes). Cheap by
## construction: one sine pair and one assignment per visible worm, no
## allocation and no queries.
func _crawl_worm_sprites() -> void:
	for chunk_coord in _worm_sprites:
		var origin: Vector2i = chunk_coord * CHUNK_SIZE
		var sprites: Dictionary = _worm_sprites[chunk_coord]
		for cell in sprites:
			var base := Vector2(
				(origin.x + cell.x + 0.5) * TerrainRenderer.TILE_SIZE,
				(origin.y + cell.y + 0.5) * TerrainRenderer.TILE_SIZE
			)
			sprites[cell].position = base + EarthwormPatch.crawl_offset(
				hash("%d_%d_crawl" % [origin.x + cell.x, origin.y + cell.y]),
				_world_age_seconds
			)
			# ...and how much of it is above ground. A worm crawls out of the
			# earth and back down it rather than blinking into existence (see
			# EarthwormPatch "Crawling out, and back down").
			var patch: EarthwormPatch = _worm_patches.get(chunk_coord)
			if patch != null:
				_show_worm_emerged(
					sprites[cell], EarthwormPatch.emergence_for(patch.surfacing_at(cell))
				)


## Shows `emerged` (0..1) of a worm, as if it were crawling out of its burrow.
##
## Revealed along the worm's own length rather than faded in: a worm coming up
## is a nose, then a body, then a tail, and fading would just be a ghost
## appearing. The sprite's region grows from the burrow end, and the sprite is
## shifted by half of what is still hidden so the emerged part stays PUT --
## without that the worm slides sideways as it comes up, which reads as it
## being dragged rather than crawling.
func _show_worm_emerged(sprite: Sprite2D, emerged: float) -> void:
	var full := float(ProceduralWormSprite.SIZE.x)
	var shown := maxf(1.0, full * clampf(emerged, 0.0, 1.0))
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0.0, 0.0, shown, float(ProceduralWormSprite.SIZE.y))
	sprite.offset.x = -(full - shown) * 0.5
	sprite.offset.y = -float(ProceduralWormSprite.SIZE.y) * 0.5


## Adds/removes a Sprite2D per SURFACED worm so what is rendered matches the
## chunk's EarthwormPatch. Unlike grass there is no growth animation -- a worm
## is either up or it isn't -- so this only adds newly-surfaced ones and frees
## the ones that have gone back down or been eaten. Same diff-against-the-sim
## shape as _sync_flower_sprites.
func _sync_worm_sprites(chunk_coord: Vector2i) -> void:
	if not _decorates(chunk_coord):
		_drop_decoration(_worm_sprites, chunk_coord)
		return
	var patch: EarthwormPatch = _worm_patches.get(chunk_coord)
	var sprites: Dictionary = _worm_sprites.get(chunk_coord, {})
	if patch == null:
		return

	for cell in sprites.keys().duplicate():
		if not patch.is_surfaced(cell):
			sprites[cell].free()
			sprites.erase(cell)

	var origin := chunk_coord * CHUNK_SIZE
	for cell in patch.worm_cells():
		if not patch.is_surfaced(cell) or sprites.has(cell):
			continue
		var sprite := Sprite2D.new()
		sprite.texture = _worm_sprite_generator.generate_texture(
			hash("%d_%d_worm" % [origin.x + cell.x, origin.y + cell.y])
		)
		# World scale from a world-space constant, never re-derived from the
		# art canvas -- raising SIZE for detail must not change how big a worm
		# looks (a trap this project has hit twice).
		sprite.scale = Vector2.ONE * ProceduralWormSprite.world_scale()
		# Anchored at the worm's own footprint so it Y-sorts against the
		# player like flowers do, rather than sorting from its middle; and
		# starting at however far out of the ground it actually is, so a worm
		# that has just broken the surface shows a nose rather than a body.
		_show_worm_emerged(sprite, EarthwormPatch.emergence_for(patch.surfacing_at(cell)))
		sprite.position = Vector2(
			(origin.x + cell.x + 0.5) * TerrainRenderer.TILE_SIZE,
			(origin.y + cell.y + 0.5) * TerrainRenderer.TILE_SIZE
		)
		_entities_parent.add_child(sprite)
		sprites[cell] = sprite


## Plants carried seed at a world position, if anything can grow there (see
## SeedDispersal.can_root_in and FlowerPatch.plant, which between them reject
## non-grassland, occupied and over-capacity cells). Returns true if a new
## flower actually took.
## Leaves a bird dropping on the ground.
##
## The visible half of dispersal: without it a seed simply appears somewhere a
## bird happened to be, and the player never sees the connection between the
## bird that ate the berry and the flower that comes up under the perch.
##
## Bounded like every other decoration -- droppings are scenery, and scenery
## that accumulates forever is a leak with a sprite.
const MAX_GUANO := 24
var _guano: Array[Node2D] = []


func drop_guano_at(pixel_position: Vector2, _seed_species: String) -> void:
	if _entities_parent == null:
		return
	while _guano.size() >= MAX_GUANO:
		var oldest: Node2D = _guano.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var mark := Sprite2D.new()
	mark.texture = _guano_texture()
	mark.position = pixel_position
	mark.z_index = -1
	_entities_parent.add_child(mark)
	_guano.append(mark)


## One shared speck, built once. A dropping is a couple of pale pixels -- at
## this scale there is nothing else it could be.
static var _guano_cached: ImageTexture = null


func _guano_texture() -> ImageTexture:
	if _guano_cached != null:
		return _guano_cached
	var image := Image.create(3, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	image.set_pixel(1, 0, Color(0.92, 0.92, 0.88, 0.9))
	image.set_pixel(0, 1, Color(0.86, 0.86, 0.82, 0.85))
	image.set_pixel(2, 1, Color(0.88, 0.88, 0.84, 0.8))
	_guano_cached = ImageTexture.create_from_image(image)
	return _guano_cached


func plant_flower_at(pixel_position: Vector2, species: String) -> bool:
	var tile := _world_tile_for_pixel(pixel_position)
	var chunk_coord := _chunk_coord_for_tile(tile)
	var patch: FlowerPatch = _flower_patches.get(chunk_coord)
	if patch == null:
		return false
	if not SeedDispersal.can_root_in(biome_at_global(tile.x, tile.y)):
		return false
	var local: Vector2i = tile - chunk_coord * CHUNK_SIZE
	if not patch.plant(local, species):
		return false
	_sync_flower_sprites(chunk_coord)
	return true


## How often the desert-scrub sprite layer re-syncs to the simulation. The
## sims themselves advance every call; only the node churn is throttled.
## Mirrors GRASS_REFRESH_INTERVAL -- this is a node-churn throttle, not a
## biome flavor tunable, so there's no reason for it to differ.
const SCRUB_REFRESH_INTERVAL := 5.0

## Central desert-scrub step (see DesertScrub): every loaded chunk's scrub sim
## grows/spreads, and on a throttled interval the tuft sprites are re-synced
## to the sim's patch set. Unlike tall grass, nothing grazes scrub yet --
## wiring it into a harvest/forage action is a deliberate follow-up, not done
## here (see docs/progress.md's Flora section).
func step_desert_scrub(delta_seconds: float) -> void:
	for sim in _scrub_sims.values():
		sim.advance(delta_seconds)

	_scrub_refresh_accumulator += delta_seconds
	if _scrub_refresh_accumulator < SCRUB_REFRESH_INTERVAL:
		return
	_scrub_refresh_accumulator = 0.0

	for chunk_coord in _scrub_sims.keys():
		_sync_scrub_sprites(chunk_coord)


## Adds/removes tuft sprites so the rendered layer matches the sim's patch
## set; a growing patch is scaled by its growth so scrub visibly rises.
func _sync_scrub_sprites(chunk_coord: Vector2i) -> void:
	var sim: DesertScrub = _scrub_sims.get(chunk_coord)
	var sprites: Dictionary = _scrub_sprites.get(chunk_coord, {})
	if sim == null:
		return

	for cell in sprites.keys().duplicate():
		if not sim.has_scrub(cell):
			sprites[cell].free()
			sprites.erase(cell)

	var origin := chunk_coord * CHUNK_SIZE
	for cell in sim.get_patch_cells():
		if not sprites.has(cell):
			var sprite := Sprite2D.new()
			sprite.texture = _scrub_sprite_generator.generate_texture(
				hash("%d_%d_scrub_tuft" % [origin.x + cell.x, origin.y + cell.y])
			)
			# Art is DETAIL_MULTIPLIER times oversized, and a tuft is a
			# CLUMP standing on a tile rather than a tile-sized carpet --
			# at full tile width the ground cover read as giant plants.
			sprite.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE * TUFT_WORLD_SCALE
			# Scrub sways too (shared GPU shader, see WindSway). Lichen
			# deliberately doesn't -- it's crusty ground cover, not foliage.
			sprite.material = _wind_sway.tuft_material()
			sprite.position = Vector2(
				(origin.x + cell.x + 0.5) * TerrainRenderer.TILE_SIZE,
				(origin.y + cell.y + 0.5) * TerrainRenderer.TILE_SIZE
			)
			_entities_parent.add_child(sprite)
			sprites[cell] = sprite
		# Growth multiplies onto the base world scale, never replaces it (see
		# the matching comment in _sync_grass_sprites).
		sprites[cell].scale = (
			Vector2.ONE * ArtResolution.SPRITE_SCALE * TUFT_WORLD_SCALE * maxf(0.3, sim.get_growth(cell))
		)


## How often the tundra-lichen sprite layer re-syncs to the simulation. The
## sims themselves advance every call; only the node churn is throttled.
## Mirrors GRASS_REFRESH_INTERVAL -- this is a node-churn throttle, not a
## biome flavor tunable, so there's no reason for it to differ.
const LICHEN_REFRESH_INTERVAL := 5.0

## Central tundra-lichen step (see TundraLichen): every loaded chunk's lichen
## sim grows/spreads, and on a throttled interval the patch sprites are
## re-synced to the sim's patch set. Unlike tall grass, nothing grazes lichen
## yet -- wiring it into a harvest/forage action is a deliberate follow-up,
## not done here (see docs/progress.md's Flora section).
func step_tundra_lichen(delta_seconds: float) -> void:
	for sim in _lichen_sims.values():
		sim.advance(delta_seconds)

	_lichen_refresh_accumulator += delta_seconds
	if _lichen_refresh_accumulator < LICHEN_REFRESH_INTERVAL:
		return
	_lichen_refresh_accumulator = 0.0

	for chunk_coord in _lichen_sims.keys():
		_sync_lichen_sprites(chunk_coord)


## Adds/removes patch sprites so the rendered layer matches the sim's patch
## set; a growing patch is scaled by its growth so lichen visibly spreads.
func _sync_lichen_sprites(chunk_coord: Vector2i) -> void:
	var sim: TundraLichen = _lichen_sims.get(chunk_coord)
	var sprites: Dictionary = _lichen_sprites.get(chunk_coord, {})
	if sim == null:
		return

	for cell in sprites.keys().duplicate():
		if not sim.has_lichen(cell):
			sprites[cell].free()
			sprites.erase(cell)

	var origin := chunk_coord * CHUNK_SIZE
	for cell in sim.get_patch_cells():
		if not sprites.has(cell):
			var sprite := Sprite2D.new()
			sprite.texture = _lichen_sprite_generator.generate_texture(
				hash("%d_%d_lichen_tuft" % [origin.x + cell.x, origin.y + cell.y])
			)
			# Art is DETAIL_MULTIPLIER times oversized, and a tuft is a
			# CLUMP standing on a tile rather than a tile-sized carpet --
			# at full tile width the ground cover read as giant plants.
			sprite.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE * TUFT_WORLD_SCALE
			sprite.position = Vector2(
				(origin.x + cell.x + 0.5) * TerrainRenderer.TILE_SIZE,
				(origin.y + cell.y + 0.5) * TerrainRenderer.TILE_SIZE
			)
			_entities_parent.add_child(sprite)
			sprites[cell] = sprite
		# Growth multiplies onto the base world scale, never replaces it (see
		# the matching comment in _sync_grass_sprites).
		sprites[cell].scale = (
			Vector2.ONE * ArtResolution.SPRITE_SCALE * TUFT_WORLD_SCALE * maxf(0.3, sim.get_growth(cell))
		)


func _world_tile_for_pixel(pixel_position: Vector2) -> Vector2i:
	return Vector2i(floori(pixel_position.x / TerrainRenderer.TILE_SIZE), floori(pixel_position.y / TerrainRenderer.TILE_SIZE))


## Advances the living-ecosystem simulation (Phase 1: vegetation growth,
## herbivore/predator population, migration) and refreshes creature markers
## for currently-loaded regions -- gated to once per SECONDS_PER_SIMULATED_DAY
## of real elapsed time, not every frame, so markers don't churn constantly.
func step_ecosystem(delta_seconds: float) -> void:
	_ecosystem_time_accumulator += delta_seconds
	if _ecosystem_time_accumulator < SECONDS_PER_SIMULATED_DAY:
		return

	var delta_days := _ecosystem_time_accumulator / SECONDS_PER_SIMULATED_DAY
	_ecosystem_time_accumulator = 0.0
	_ecosystem.step(delta_days)
	_refresh_creatures()


## Refreshes both creature and fish markers to match the ecosystem's current
## aggregate populations -- a fished-down or recovering water chunk visibly
## shows fewer/more fish on the next periodic refresh, not just on reload.
func _refresh_creatures() -> void:
	for chunk_coord in _loaded_chunks.keys():
		_reconcile_chunk_creatures(chunk_coord)

		var chunk: Chunk = _loaded_chunks[chunk_coord]
		for fish in _loaded_fish.get(chunk_coord, []):
			fish.free()
		_loaded_fish[chunk_coord] = _fish_renderer.spawn_fish(
			_creatures_parent, chunk_coord, chunk, chunk_coord * CHUNK_SIZE, TerrainRenderer.TILE_SIZE, self,
			_fish_target_count(chunk_coord)
		)


## Brings one chunk's creature markers in line with its aggregate population
## by ADDING or REMOVING, never by rebuilding: everything already alive stays
## exactly where it is, with everything it has learned.
##
## The rebuild it replaces freed every marker in every loaded chunk once a
## minute and respawned the lot at their deterministic spawn points. The
## visible half of that was every animal on screen blinking out and reappearing
## back where it first spawned (reported: "every N seconds horses and deer
## disappear and respawn at original spawn point"). The worse half was silent:
## it wiped all per-animal state with it -- hunger, energy, and once taming
## existed, trust and tamed status -- so a horse the player had spent five
## carrots taming was deleted and replaced by a wild one a minute later, which
## made taming impossible to keep hold of.
##
## Like the 30-second reproduction cooldown and the twice-a-minute fruiting
## cycle, this only ever looked survivable because the ecology simulation was
## never actually running (see World.owns_ecosystem_simulation_for).
func _reconcile_chunk_creatures(chunk_coord: Vector2i) -> void:
	var alive: Array = []
	for creature in _loaded_creatures.get(chunk_coord, []):
		if is_instance_valid(creature) and not creature.is_queued_for_deletion():
			alive.append(creature)

	var chunk: Chunk = _loaded_chunks[chunk_coord]
	var target := _creature_renderer.marker_count_for(
		_ecosystem.herbivore_population(chunk_coord)
	) + _creature_renderer.marker_count_for(_ecosystem.predator_population(chunk_coord))

	if alive.size() > target:
		alive = _thin_creatures(alive, alive.size() - target)
	elif alive.size() < target:
		alive.append_array(
			_creature_renderer.spawn_creatures(
				_creatures_parent,
				chunk_coord,
				chunk_coord * CHUNK_SIZE,
				CHUNK_SIZE,
				TerrainRenderer.TILE_SIZE,
				_ecosystem.herbivore_population(chunk_coord),
				_ecosystem.predator_population(chunk_coord),
				self,
				_biome_classifier.dominant_biome(chunk.biome),
				_difficulty_tier_at(chunk_coord),
				alive.size()
			)
		)
	_loaded_creatures[chunk_coord] = alive


## Removes `surplus` animals from a chunk whose population has fallen, and
## returns what is left.
##
## Anything the player has a stake in is kept regardless of the numbers: a
## tamed animal, one on the end of a rope, or one part-way to being tamed. The
## aggregate model is a background process, and it does not get to delete the
## horse the player spent an evening winning over just because the herd it
## belongs to had a bad season.
func _thin_creatures(alive: Array, surplus: int) -> Array:
	var keep: Array = []
	var removed := 0
	for creature in alive:
		var invested: bool = float(creature.get("trust")) > 0.0 or creature.is_restrained()
		if removed < surplus and not invested:
			creature.queue_free()
			removed += 1
			continue
		keep.append(creature)
	return keep


## How many fish markers a chunk should visibly show right now: its aggregate
## fish population as a fraction of its capacity, scaled onto
## FishRenderer.MAX_FISH_PER_CHUNK -- see
## docs/concept/fishing.md#individual-fidelity-promotion. A capacity-less
## chunk (no water) always shows zero, never divides by zero.
func _fish_target_count(chunk_coord: Vector2i) -> int:
	var capacity := _ecosystem.fish_capacity_at(chunk_coord)
	if capacity <= 0.0:
		return 0
	var population := _ecosystem.fish_population(chunk_coord)
	return clampi(
		roundi(population / capacity * FishRenderer.MAX_FISH_PER_CHUNK), 0, FishRenderer.MAX_FISH_PER_CHUNK
	)


func elevation_at_global(global_x: int, global_y: int) -> float:
	var chunk: Chunk = _loaded_chunks.get(_chunk_coord_for_tile(Vector2i(global_x, global_y)))
	if chunk == null:
		return generator.elevation_at_global(global_x, global_y)
	return chunk.elevation[_local_index(global_x, global_y)]


func biome_at_global(global_x: int, global_y: int) -> String:
	var chunk: Chunk = _loaded_chunks.get(_chunk_coord_for_tile(Vector2i(global_x, global_y)))
	if chunk == null:
		return ""  # not currently loaded/rendered; callers shouldn't query far outside the load radius
	return chunk.biome[_local_index(global_x, global_y)]


## Finds the nearest loaded FishMarker within max_distance pixels of
## `pixel_position`, frees it, and returns its species -- or "" if none is in
## range. Used to give the abstract fishing minigame (see FishingSession,
## Player._fishing_step) a real visible fish to make disappear and flavor the
## catch message with, without coupling the catch's success/rarity to whether
## a fish happens to be rendered nearby (that stays purely
## FishingMinigame.attempt_catch's call, unaffected by this). Also records the
## harvest against the fish's own chunk's aggregate population (see
## docs/concept/fishing.md#harvest-fishing-as-the-mortality-term) -- unlike
## land hunting, a caught fish now actually depletes the region it came from.
## Where the nearest fish is, WITHOUT taking it -- what a hunting kingfisher
## needs to pick a target and fly to it (see PiscivoreBirdMarker).
##
## The bird used to dive only when its random wander happened to carry it over
## water that had fish in it, so one living inland essentially never fished at
## all. Hunting means going to the fish.
## What this pixel's water could support if it were healthy -- the other half
## of the question "is this pond worth working" (see
## PiscivoreAppetite.will_hunt). Paired with fish_population_near, which
## answers what is actually in it.
func fish_capacity_near(pixel_position: Vector2) -> float:
	return _ecosystem.fish_capacity_at(_chunk_coord_for_tile(_world_tile_for_pixel(pixel_position)))


func nearest_fish_position(pixel_position: Vector2, max_distance: float):
	var nearest = null
	var nearest_distance := max_distance
	for fish_list in _loaded_fish.values():
		for fish in fish_list:
			if not is_instance_valid(fish):
				continue
			var distance: float = pixel_position.distance_to(fish.position)
			if distance <= nearest_distance:
				nearest = fish
				nearest_distance = distance
	return nearest


## Tells the fish nearest this point to bolt -- what a MISSED strike looks
## like from the water's side. Returns whether anything was there to flee.
func startle_fish_near(pixel_position: Vector2, threat: Vector2, max_distance: float) -> bool:
	var fish = nearest_fish_position(pixel_position, max_distance)
	if fish == null or not fish.has_method("bolt_from"):
		return false
	fish.bolt_from(threat)
	return true


func catch_nearest_fish(pixel_position: Vector2, max_distance: float) -> String:
	var nearest: Node2D = null
	var nearest_distance := max_distance
	for fish_list in _loaded_fish.values():
		for fish in fish_list:
			var distance: float = pixel_position.distance_to(fish.position)
			if distance <= nearest_distance:
				nearest = fish
				nearest_distance = distance
	if nearest == null:
		return ""
	var species: String = nearest.species
	var chunk_coord := _chunk_coord_for_tile(_world_tile_for_pixel(nearest.position))
	for chunk_key in _loaded_fish.keys():
		_loaded_fish[chunk_key].erase(nearest)
	nearest.free()
	_ecosystem.record_catch(chunk_coord, 1.0)
	return species


## This pixel's chunk's aggregate fish population -- the duck-typed hook
## PiscivoreBirdMarker uses to decide whether to dive, so a kingfisher and
## the player's own rod read the exact same live number.
func fish_population_near(pixel_position: Vector2) -> float:
	var chunk_coord := _chunk_coord_for_tile(_world_tile_for_pixel(pixel_position))
	return _ecosystem.fish_population(chunk_coord)


## Records a harvest against this pixel's chunk's aggregate fish population --
## the duck-typed hook a piscivore bird's successful grab calls (see
## PiscivoreBirdMarker), the same EcosystemSimulation.record_catch
## catch_nearest_fish above uses for the player's own catch.
## Returns true if a fish was actually taken.
##
## This used to only decrement the chunk's aggregate float, so a bird's
## successful dive removed NOTHING the player could see -- no fish vanished
## from the water, no feedback of any kind, which is why the mechanic was
## invisible despite being fully wired. It now removes a real FishMarker
## within BIRD_CATCH_RADIUS as well, exactly as the player's own catch does
## (see catch_nearest_fish), so a hunting bird visibly thins the shoal.
func record_fish_catch_near(pixel_position: Vector2, count: float) -> bool:
	var chunk_coord := _chunk_coord_for_tile(_world_tile_for_pixel(pixel_position))
	_ecosystem.record_catch(chunk_coord, count)

	var nearest: Node2D = null
	var nearest_distance := BIRD_CATCH_RADIUS
	for fish_list in _loaded_fish.values():
		for fish in fish_list:
			var distance: float = pixel_position.distance_to(fish.position)
			if distance <= nearest_distance:
				nearest = fish
				nearest_distance = distance
	if nearest == null:
		return false

	for chunk_key in _loaded_fish.keys():
		_loaded_fish[chunk_key].erase(nearest)
	nearest.queue_free()
	return true


## How close a diving bird must be to a fish to actually take it. Generous
## relative to the dive animation, since the bird aims at the shoal's
## aggregate population rather than at one tracked target.
const BIRD_CATCH_RADIUS := 48.0


## True if a merchant villager (see VillageRenderer, NpcIdentity.OCCUPATIONS)
## is within max_distance pixels of pixel_position -- gates Player's shop
## interaction (see Shop).
func has_merchant_near(pixel_position: Vector2, max_distance: float) -> bool:
	for node_list in _loaded_villages.values():
		for node in node_list:
			if not (node is NpcMarker):
				continue
			if node.identity.occupation != "merchant":
				continue
			if pixel_position.distance_to(node.position) <= max_distance:
				return true
	return false


## The closest villager (any occupation) within max_distance pixels of
## pixel_position, or null if none qualify -- gates Player's talk interaction
## (see NpcGreeting, the "Talk (key)" prompt). Same shape as has_merchant_near
## but returns the marker itself since the talk prompt/greeting need the
## NPC's identity, not just a yes/no.
func nearest_npc_near(pixel_position: Vector2, max_distance: float) -> NpcMarker:
	var nearest: NpcMarker = null
	var nearest_distance := max_distance
	for node_list in _loaded_villages.values():
		for node in node_list:
			if not (node is NpcMarker):
				continue
			var distance: float = pixel_position.distance_to(node.position)
			if distance <= nearest_distance:
				nearest = node
				nearest_distance = distance
	return nearest


## The nearest LOOSE, LIFTABLE stone within `max_distance` of `pixel_position`
## -- same shape as nearest_npc_near, for the "Pick (<key>)" interaction
## prompt (see World._update_interaction_prompt). Duck-typed on has_method
## ("pick_up") rather than an `is LiftableStone` check, the same convention
## test_stone_renderer.gd already uses -- a boulder/ore node (StaticBody2D,
## no pick_up) never qualifies, since there is nothing to press the pickup
## key FOR.
func nearest_liftable_stone_near(pixel_position: Vector2, max_distance: float) -> Node2D:
	var nearest: Node2D = null
	var nearest_distance := max_distance
	for node_list in _loaded_stones.values():
		for node in node_list:
			if not is_instance_valid(node) or not node.has_method("pick_up"):
				continue
			var distance: float = pixel_position.distance_to(node.position)
			if distance <= nearest_distance:
				nearest = node
				nearest_distance = distance
	return nearest


## Every liftable stone within `max_distance` of `pixel_position`, not just
## the closest one -- pebble dispersion (see PebbleDispersion,
## World._step_pebble_dispersion) needs every nearby member checked, since a
## flock can put several within reach of a walker at once.
func liftable_stones_near(pixel_position: Vector2, max_distance: float) -> Array:
	var found: Array = []
	for node_list in _loaded_stones.values():
		for node in node_list:
			if not is_instance_valid(node) or not node.has_method("pick_up"):
				continue
			if pixel_position.distance_to(node.position) <= max_distance:
				found.append(node)
	return found


## Draws every loaded fish within `radius` of `position` toward it instead of
## their normal wander target (see FishMarker.set_attraction) -- a cast
## fishing line nearby (Player._fishing_step/FishingCast). Call every frame
## while a line is out, since fish (and the player) can move in/out of
## range; fish now outside the radius are un-attracted in the same pass, not
## left stuck steering at a stale target.
func set_attraction_point(pixel_position: Vector2, radius: float) -> void:
	for fish_list in _loaded_fish.values():
		for fish in fish_list:
			if fish.position.distance_to(pixel_position) <= radius:
				fish.set_attraction(pixel_position)
			else:
				fish.clear_attraction()


## Releases every loaded fish back to normal wandering -- call once a line is
## reeled in or the catch is resolved.
func clear_attraction_point() -> void:
	for fish_list in _loaded_fish.values():
		for fish in fish_list:
			fish.clear_attraction()


func modification_at_global(global_x: int, global_y: int) -> String:
	var chunk: Chunk = _loaded_chunks.get(_chunk_coord_for_tile(Vector2i(global_x, global_y)))
	if chunk == null:
		return ""
	return chunk.modifications.get(_local_coord(global_x, global_y), "")


## Places a modification tile (Phase 3 building) at a global tile, repainting
## just its owning chunk. Returns false (no-op) if that tile isn't in a
## currently-loaded chunk -- building far outside the streamed area isn't
## meaningful since nothing there is being rendered or simulated.
func build_at_global(global_x: int, global_y: int, tile_id: String) -> bool:
	var chunk_coord := _chunk_coord_for_tile(Vector2i(global_x, global_y))
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk == null:
		return false
	chunk.modifications[_local_coord(global_x, global_y)] = tile_id
	_terrain_renderer.paint(_tile_map_layer, chunk, chunk_coord * CHUNK_SIZE, generator.biome_at_global)
	_sync_piece_collision(Vector2i(global_x, global_y), tile_id)
	return true


## Removes a previously-built modification, reverting that cell to its
## generated biome tile. Returns false if the chunk isn't loaded or the tile
## had no modification to remove.
func destroy_at_global(global_x: int, global_y: int) -> bool:
	var chunk_coord := _chunk_coord_for_tile(Vector2i(global_x, global_y))
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk == null:
		return false
	var local := _local_coord(global_x, global_y)
	if not chunk.modifications.has(local):
		return false
	chunk.modifications.erase(local)
	_terrain_renderer.paint(_tile_map_layer, chunk, chunk_coord * CHUNK_SIZE, generator.biome_at_global)
	_remove_piece_collision(Vector2i(global_x, global_y))
	return true


## Stamps every cell of `ground_pieces`/`roof_pieces` (footprint-relative,
## see HouseBlueprint.build/build_roofs) into the chunk at `chunk_coord`,
## with `origin_tile` as the footprint's global top-left. Writes directly
## into the chunk's modification dicts and repaints/rebuilds collision ONCE
## for the whole structure, rather than looping build_at_global per cell --
## which would repaint the whole chunk once PER CELL, ruinous for a
## multi-house village at chunk-load time. Cells that would land outside
## `chunk_coord` (a footprint spilling into a neighboring chunk) are silently
## skipped -- a Phase 1 simplification, matching HouseBlueprint's small
## footprint sizes and this codebase's existing "regenerates identically on
## revisit" tolerance for minor placement imperfections. No-ops entirely if
## `chunk_coord` isn't currently loaded.
func stamp_structure_at_global(
	chunk_coord: Vector2i, origin_tile: Vector2i, ground_pieces: Dictionary, roof_pieces: Dictionary
) -> void:
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk == null:
		return
	for local_cell in ground_pieces:
		var global_cell: Vector2i = origin_tile + local_cell
		if _chunk_coord_for_tile(global_cell) != chunk_coord:
			continue
		chunk.modifications[_local_coord(global_cell.x, global_cell.y)] = ground_pieces[local_cell]
	for local_cell in roof_pieces:
		var global_cell: Vector2i = origin_tile + local_cell
		if _chunk_coord_for_tile(global_cell) != chunk_coord:
			continue
		chunk.roof_modifications[_local_coord(global_cell.x, global_cell.y)] = roof_pieces[local_cell]
	_terrain_renderer.paint(_tile_map_layer, chunk, chunk_coord * CHUNK_SIZE, generator.biome_at_global)
	for local_cell in ground_pieces:
		var global_cell: Vector2i = origin_tile + local_cell
		if _chunk_coord_for_tile(global_cell) == chunk_coord:
			_sync_piece_collision(global_cell, ground_pieces[local_cell])
	if _roof_layer != null:
		_terrain_renderer.paint_roofs(_roof_layer, chunk, chunk_coord * CHUNK_SIZE, _hidden_cells_for(chunk_coord))


## Adds, replaces, or removes `global_cell`'s collision body to match
## `tile_id`: a wall/window piece gets a full-tile StaticBody2D (the same
## trunk/boulder-blocking mechanism TreeRenderer already uses -- this project
## has no generic tile-solidity check), anything else (floor, door, a
## non-piece id) has none. Always clears any PRE-EXISTING body at the cell
## first -- build_at_global doesn't check occupancy the way
## BuildingPlacement.can_place does, so overwriting a wall with a door must
## not leave the old wall's collision behind.
func _sync_piece_collision(global_cell: Vector2i, tile_id: String) -> void:
	_remove_piece_collision(global_cell)
	if BuildingPiece.has_piece(tile_id) and not BuildingPiece.is_walkable(tile_id):
		_spawn_piece_collision(global_cell, tile_id)


func _spawn_piece_collision(global_cell: Vector2i, piece_id: String) -> void:
	var body := StaticBody2D.new()
	body.name = "PieceCollision"
	body.position = Vector2(
		(global_cell.x + 0.5) * TerrainRenderer.TILE_SIZE, (global_cell.y + 0.5) * TerrainRenderer.TILE_SIZE
	)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2.ONE * TerrainRenderer.TILE_SIZE
	shape.shape = rect
	body.add_child(shape)
	_entities_parent.add_child(body)
	var chunk_coord := _chunk_coord_for_tile(global_cell)
	if not _piece_collision_bodies.has(chunk_coord):
		_piece_collision_bodies[chunk_coord] = {}
	_piece_collision_bodies[chunk_coord][global_cell] = body


func _remove_piece_collision(global_cell: Vector2i) -> void:
	var chunk_coord := _chunk_coord_for_tile(global_cell)
	var bodies: Dictionary = _piece_collision_bodies.get(chunk_coord, {})
	var body: Node = bodies.get(global_cell)
	if body == null:
		return
	body.free()
	bodies.erase(global_cell)


## True if a modification tile matching `structure_id` (e.g. "campfire",
## "furnace" -- see item_catalog.gd's placeable items) exists within `radius`
## tiles of (global_x, global_y), Chebyshev/square distance (max(|dx|, |dy|)
## <= radius) -- simplest metric, and fine for a "standing near it" proximity
## check like heat-source range (see Player.HEAT_SOURCE_RADIUS_TILES).
##
## Simplification: only scans the query tile's own chunk plus its 8 immediate
## neighbors (a chunk-Chebyshev-radius of 1), not however many chunks `radius`
## tiles could theoretically span. This is exact for any `radius` up to
## CHUNK_SIZE (32) -- comfortably more than any realistic proximity check (a
## "standing near the fire" range is a handful of tiles) -- and simply won't
## find a match past that. Unloaded chunks are skipped (nothing to query).
func has_structure_near(global_x: int, global_y: int, structure_id: String, radius: int) -> bool:
	var query_tile := Vector2i(global_x, global_y)
	var center_chunk := _chunk_coord_for_tile(query_tile)

	for chunk_coord in chunks_in_radius(center_chunk, 1):
		var chunk: Chunk = _loaded_chunks.get(chunk_coord)
		if chunk == null:
			continue
		var origin := chunk_coord * CHUNK_SIZE
		for local_coord in chunk.modifications:
			if chunk.modifications[local_coord] != structure_id:
				continue
			var tile_global: Vector2i = origin + local_coord
			if _chebyshev_distance(tile_global, query_tile) <= radius:
				return true
	return false


## All chunk coordinates within `radius` chunks of center (a square/Chebyshev
## radius, not circular -- simpler, and streaming radii don't need to be exact).
func chunks_in_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			result.append(center + Vector2i(dx, dy))
	return result


func _load_chunk(chunk_coord: Vector2i) -> void:
	var chunk := generator.generate_chunk(chunk_coord, CHUNK_SIZE)
	chunk.modifications = _chunk_serializer.load_modifications(_modifications_path(chunk_coord))
	chunk.roof_modifications = _chunk_serializer.load_modifications(_roof_modifications_path(chunk_coord))
	chunk.planted_trees = _chunk_serializer.load_planted_trees(_planted_trees_path(chunk_coord))
	_loaded_chunks[chunk_coord] = chunk
	_terrain_renderer.paint(_tile_map_layer, chunk, chunk_coord * CHUNK_SIZE, generator.biome_at_global)
	_paint_water_overlay(chunk_coord, chunk)
	# Restores collision for every wall/window piece PERSISTED from a
	# previous session -- fresh village-stamped pieces get their collision
	# immediately inside stamp_structure_at_global instead, further below in
	# this function, since they don't exist in `chunk.modifications` yet at
	# this point.
	for local_cell in _piece_grid_for(chunk):
		var global_cell: Vector2i = chunk_coord * CHUNK_SIZE + local_cell
		_sync_piece_collision(global_cell, chunk.modifications[local_cell])
	if _roof_layer != null:
		_terrain_renderer.paint_roofs(_roof_layer, chunk, chunk_coord * CHUNK_SIZE, _hidden_cells_for(chunk_coord))
	_loaded_trees[chunk_coord] = _tree_renderer.spawn_trees(
		_entities_parent, chunk, chunk_coord * CHUNK_SIZE, TerrainRenderer.TILE_SIZE
	)
	for record in chunk.planted_trees:
		# A sapling reloaded with its chunk resumes at the size its age
		# earns it, rather than restarting as a seedling every time the
		# player walks away and back.
		var sapling_age: float = _world_age_seconds - float(record.get("planted_at", 0.0))
		_loaded_trees[chunk_coord].append(
			_tree_renderer.spawn_tree_at(_entities_parent, record.position, sapling_age)
		)

	_loaded_stones[chunk_coord] = _stone_renderer.spawn_stones(
		_entities_parent, chunk, chunk_coord * CHUNK_SIZE, TerrainRenderer.TILE_SIZE
	)

	_grass_sims[chunk_coord] = TallGrass.new(
		hash("%d_%d_tall_grass" % [chunk_coord.x, chunk_coord.y]), chunk.width, chunk.height, chunk.biome
	)
	_grass_sprites[chunk_coord] = {}
	_sync_grass_sprites(chunk_coord)

	_flower_patches[chunk_coord] = FlowerPatch.new(
		hash("%d_%d_flowers" % [chunk_coord.x, chunk_coord.y]), chunk.width, chunk.height, chunk.biome
	)
	_flower_sprites[chunk_coord] = {}
	_seed_sprites[chunk_coord] = {}
	_sync_flower_sprites(chunk_coord)

	_scrub_sims[chunk_coord] = DesertScrub.new(
		hash("%d_%d_desert_scrub" % [chunk_coord.x, chunk_coord.y]), chunk.width, chunk.height, chunk.biome
	)
	_scrub_sprites[chunk_coord] = {}
	_sync_scrub_sprites(chunk_coord)

	_lichen_sims[chunk_coord] = TundraLichen.new(
		hash("%d_%d_tundra_lichen" % [chunk_coord.x, chunk_coord.y]), chunk.width, chunk.height, chunk.biome
	)
	_lichen_sprites[chunk_coord] = {}
	_sync_lichen_sprites(chunk_coord)

	# Earthworms in the soil (see docs/concept/soil_fauna.md). No sprites yet:
	# every worm starts underground and surfaces over the next step_worms
	# ticks according to the live weather, rather than popping onto the grass
	# the instant a chunk loads.
	_worm_patches[chunk_coord] = EarthwormPatch.new(
		hash("%d_%d_earthworms" % [chunk_coord.x, chunk_coord.y]), chunk.width, chunk.height, chunk.biome
	)
	_worm_sprites[chunk_coord] = {}

	_ecosystem.add_region(chunk_coord, chunk)
	# In-session catch-up (elapsed time since this chunk was last unloaded,
	# still tracked in memory) takes precedence over the disk-persisted fish
	# population below -- it's the more accurate figure (it accounts for
	# regrowth since unload; the disk snapshot doesn't). Disk is only
	# consulted when there's no in-session record at all, i.e. this is a
	# revisit from a previous game session.
	var had_in_session_catchup := _unloaded_ecology.has(chunk_coord)
	_apply_ecology_catchup(chunk_coord)
	if not had_in_session_catchup:
		var fish_population_path := _fish_population_path(chunk_coord)
		if FileAccess.file_exists(fish_population_path):
			_ecosystem.seed_fish_population(
				chunk_coord, _chunk_serializer.load_fish_population(fish_population_path)
			)
		_apply_persisted_ecology(chunk_coord)
	_loaded_creatures[chunk_coord] = _creature_renderer.spawn_creatures(
		_creatures_parent,
		chunk_coord,
		chunk_coord * CHUNK_SIZE,
		CHUNK_SIZE,
		TerrainRenderer.TILE_SIZE,
		_ecosystem.herbivore_population(chunk_coord),
		_ecosystem.predator_population(chunk_coord),
		self,
		_biome_classifier.dominant_biome(chunk.biome),
		_difficulty_tier_at(chunk_coord)
	)
	_restore_kept_animals(chunk_coord)
	_loaded_fish[chunk_coord] = _fish_renderer.spawn_fish(
		_creatures_parent, chunk_coord, chunk, chunk_coord * CHUNK_SIZE, TerrainRenderer.TILE_SIZE, self,
		_fish_target_count(chunk_coord)
	)
	_loaded_villages[chunk_coord] = _village_renderer.spawn_village(
		_creatures_parent,
		chunk_coord,
		chunk_coord * CHUNK_SIZE,
		CHUNK_SIZE,
		TerrainRenderer.TILE_SIZE,
		_biome_classifier.dominant_biome(chunk.biome),
		self
	)
	_loaded_ambient_flyers[chunk_coord] = _ambient_flyer_renderer.spawn_ambient_flyers(
		_creatures_parent, chunk, chunk_coord * CHUNK_SIZE, TerrainRenderer.TILE_SIZE,
		_biome_classifier.dominant_biome(chunk.biome),
		_pollinator_multiplier_for(chunk_coord),
		self
	)
	_loaded_piscivore_birds[chunk_coord] = _piscivore_bird_renderer.spawn_piscivore_birds(
		_creatures_parent, chunk_coord, chunk, chunk_coord * CHUNK_SIZE, TerrainRenderer.TILE_SIZE, self
	)


## If this chunk was visited before, advance its aggregate ecology over the
## time it spent unloaded and install the caught-up populations, instead of
## add_region's fresh equilibrium -- so a region the player left keeps evolving
## (herds grow or get thinned by predators) rather than resetting on revisit.
func _apply_ecology_catchup(chunk_coord: Vector2i) -> void:
	if not _unloaded_ecology.has(chunk_coord):
		return
	var record: Dictionary = _unloaded_ecology[chunk_coord]
	var elapsed := _world_age_seconds - float(record["unloaded_at"])
	_unloaded_ecology.erase(chunk_coord)
	if elapsed <= 0.0:
		return
	var capacity := {
		"herbivore_capacity": _ecosystem.herbivore_capacity_at(chunk_coord),
		"fruit_growth_rate": 0.0,  # fruit stock is cosmetic here; populations are what matters
		"fish_capacity": _ecosystem.fish_capacity_at(chunk_coord),
	}
	var advanced: Dictionary = _ecology_catchup.advance(record["state"], elapsed, capacity)
	_ecosystem.seed_populations(chunk_coord, advanced["herbivores"], advanced["predators"])
	_ecosystem.seed_fish_population(chunk_coord, advanced["fish"])


func _unload_chunk(chunk_coord: Vector2i) -> void:
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk != null and not chunk.modifications.is_empty():
		DirAccess.make_dir_recursive_absolute(MODIFICATIONS_DIR)
		_chunk_serializer.save_modifications(chunk.modifications, _modifications_path(chunk_coord))
	if chunk != null and not chunk.planted_trees.is_empty():
		DirAccess.make_dir_recursive_absolute(PLANTED_TREES_DIR)
		_chunk_serializer.save_planted_trees(chunk.planted_trees, _planted_trees_path(chunk_coord))
	if chunk != null and not chunk.roof_modifications.is_empty():
		DirAccess.make_dir_recursive_absolute(ROOF_MODIFICATIONS_DIR)
		_chunk_serializer.save_modifications(chunk.roof_modifications, _roof_modifications_path(chunk_coord))

	_terrain_renderer.erase(_tile_map_layer, CHUNK_SIZE, chunk_coord * CHUNK_SIZE)
	if _water_layer != null:
		_terrain_renderer.erase(_water_layer, CHUNK_SIZE, chunk_coord * CHUNK_SIZE)
	if _roof_layer != null:
		_terrain_renderer.erase(_roof_layer, CHUNK_SIZE, chunk_coord * CHUNK_SIZE)
	if _hidden_roof_chunk_coord == chunk_coord:
		_hidden_roof_chunk_coord = null
		_hidden_roof_room_cells = []
	_loaded_chunks.erase(chunk_coord)

	for body in _piece_collision_bodies.get(chunk_coord, {}).values():
		body.free()
	_piece_collision_bodies.erase(chunk_coord)

	for tree in _loaded_trees.get(chunk_coord, []):
		tree.free()
	_loaded_trees.erase(chunk_coord)

	for stone in _loaded_stones.get(chunk_coord, []):
		stone.free()
	_loaded_stones.erase(chunk_coord)

	for sprite in _grass_sprites.get(chunk_coord, {}).values():
		sprite.free()
	_grass_sprites.erase(chunk_coord)
	_grass_sims.erase(chunk_coord)

	for sprite in _flower_sprites.get(chunk_coord, {}).values():
		sprite.free()
	_flower_sprites.erase(chunk_coord)
	for sprite in _seed_sprites.get(chunk_coord, {}).values():
		sprite.free()
	_seed_sprites.erase(chunk_coord)
	_flower_patches.erase(chunk_coord)

	for sprite in _scrub_sprites.get(chunk_coord, {}).values():
		sprite.free()
	_scrub_sprites.erase(chunk_coord)
	_scrub_sims.erase(chunk_coord)

	for sprite in _lichen_sprites.get(chunk_coord, {}).values():
		sprite.free()
	_lichen_sprites.erase(chunk_coord)
	_lichen_sims.erase(chunk_coord)

	for sprite in _worm_sprites.get(chunk_coord, {}).values():
		sprite.free()
	_worm_sprites.erase(chunk_coord)
	_worm_patches.erase(chunk_coord)

	# Snapshot the aggregate ecology before dropping the region, so revisiting
	# this chunk catch-up integrates from where it left off (see
	# _apply_ecology_catchup).
	if _ecosystem.has_region(chunk_coord):
		var fish_population := _ecosystem.fish_population(chunk_coord)
		_unloaded_ecology[chunk_coord] = {
			"unloaded_at": _world_age_seconds,
			"state": {
				"herbivores": _ecosystem.herbivore_population(chunk_coord),
				"predators": _ecosystem.predator_population(chunk_coord),
				"fruit_stock": 0.0,
				"vegetation": _ecosystem.average_vegetation_density(chunk_coord),
				"fish": fish_population,
			},
		}
		DirAccess.make_dir_recursive_absolute(FISH_POPULATION_DIR)
		_chunk_serializer.save_fish_population(fish_population, _fish_population_path(chunk_coord))
		# ...and the land with it, stamped in WALL-CLOCK time so a revisit
		# tomorrow can advance the region by however long the player was
		# actually away (see _apply_persisted_ecology).
		DirAccess.make_dir_recursive_absolute(ECOLOGY_DIR)
		_chunk_serializer.save_ecology(
			{
				"herbivores": _ecosystem.herbivore_population(chunk_coord),
				"predators": _ecosystem.predator_population(chunk_coord),
				"vegetation": _ecosystem.average_vegetation_density(chunk_coord),
				"saved_at_unix": Time.get_unix_time_from_system(),
			},
			_ecology_path(chunk_coord)
		)

	# The player's own animals are kept individually, not as a number in the
	# region's population (see KeptAnimals) -- a tamed horse is a particular
	# animal in a particular place, not an interchangeable head of livestock.
	_save_kept_animals(chunk_coord)

	_ecosystem.remove_region(chunk_coord)
	for creature in _loaded_creatures.get(chunk_coord, []):
		creature.free()
	_loaded_creatures.erase(chunk_coord)

	for fish in _loaded_fish.get(chunk_coord, []):
		fish.free()
	_loaded_fish.erase(chunk_coord)

	for node in _loaded_villages.get(chunk_coord, []):
		node.free()
	_loaded_villages.erase(chunk_coord)

	# Drop these flyers' forage claims BEFORE freeing them: a claim is keyed by
	# instance id, and a freed node can't be asked for its own id afterwards.
	# This is the ONLY despawn path that releases claims (NOTIFICATION_PREDELETE
	# is not reliable for it), so skipping it leaks a row per despawned
	# pollinator and slowly fills the table with blooms nothing is heading for.
	var departing_flyer_ids: Array = []
	for flyer in _loaded_ambient_flyers.get(chunk_coord, []):
		departing_flyer_ids.append(flyer.get_instance_id())
	_forage_claims.release_many(departing_flyer_ids)

	for flyer in _loaded_ambient_flyers.get(chunk_coord, []):
		flyer.free()
	_loaded_ambient_flyers.erase(chunk_coord)

	for bird in _loaded_piscivore_birds.get(chunk_coord, []):
		bird.free()
	_loaded_piscivore_birds.erase(chunk_coord)


func _modifications_path(chunk_coord: Vector2i) -> String:
	return "%s/%d_%d.bin" % [MODIFICATIONS_DIR, chunk_coord.x, chunk_coord.y]


func _roof_modifications_path(chunk_coord: Vector2i) -> String:
	return "%s/%d_%d.bin" % [ROOF_MODIFICATIONS_DIR, chunk_coord.x, chunk_coord.y]


func _planted_trees_path(chunk_coord: Vector2i) -> String:
	return "%s/%d_%d.bin" % [PLANTED_TREES_DIR, chunk_coord.x, chunk_coord.y]


func _fish_population_path(chunk_coord: Vector2i) -> String:
	return "%s/%d_%d.bin" % [FISH_POPULATION_DIR, chunk_coord.x, chunk_coord.y]


## How much ecological time one real second away counts for, and the ceiling
## on it.
##
## A player gone for a real hour finds a region a day further along -- the same
## exchange rate the in-session catch-up already uses
## (ChunkEcologyCatchup.SECONDS_PER_DAY), applied to wall-clock time so being
## away actually means something. Capped because the models are logistic and
## converge anyway: past a season of absence a region is simply at whatever
## equilibrium its land supports, and integrating a decade of it is arithmetic
## nobody can see.
const REAL_SECONDS_PER_ECOLOGICAL_DAY := ChunkEcologyCatchup.SECONDS_PER_DAY
const MAX_CATCHUP_DAYS := 120.0


## Restores a region's land ecology from a previous SESSION and advances it by
## however long the player has been away.
##
## Only reached when there is no in-session record for this chunk (see the
## caller): a chunk unloaded and reloaded during one session already has the
## more accurate in-memory catch-up. This is the "came back tomorrow" path.
func _apply_persisted_ecology(chunk_coord: Vector2i) -> void:
	var saved := _chunk_serializer.load_ecology(_ecology_path(chunk_coord))
	if saved.is_empty():
		return  # never persisted: the freshly-seeded region stands
	var away_seconds := maxf(
		0.0, Time.get_unix_time_from_system() - float(saved.get("saved_at_unix", 0.0))
	)
	# Capped, then handed to the SAME catch-up model the in-session path uses,
	# so a region reloaded after a week away and one reloaded after walking
	# away for a minute are advanced by one set of rules.
	var elapsed := minf(away_seconds, MAX_CATCHUP_DAYS * REAL_SECONDS_PER_ECOLOGICAL_DAY)
	var caught_up := _ecology_catchup.advance(
		{
			"herbivores": float(saved.get("herbivores", 0.0)),
			"predators": float(saved.get("predators", 0.0)),
			"vegetation": float(saved.get("vegetation", 0.0)),
			"fruit_stock": 0.0,
			"fish": _ecosystem.fish_population(chunk_coord),
		},
		elapsed,
		{
			"herbivore_capacity": _ecosystem.herbivore_capacity_at(chunk_coord),
			"fruit_growth_rate": 0.0,
			"fish_capacity": _ecosystem.fish_capacity_at(chunk_coord),
		}
	)
	_ecosystem.seed_populations(
		chunk_coord,
		float(caught_up.get("herbivores", 0.0)),
		float(caught_up.get("predators", 0.0))
	)


func _ecology_path(chunk_coord: Vector2i) -> String:
	return "%s/%d_%d.bin" % [ECOLOGY_DIR, chunk_coord.x, chunk_coord.y]


func _kept_animals_path(chunk_coord: Vector2i) -> String:
	return "%s/%d_%d.bin" % [KEPT_ANIMALS_DIR, chunk_coord.x, chunk_coord.y]


## Saves the tamed/tied animals standing in this chunk, and returns how many.
##
## Written on every unload including an empty list, so an animal that was
## released, untied or died does not come back: "no kept animals here" is a
## fact worth recording, not an absence of one.
func _save_kept_animals(chunk_coord: Vector2i) -> int:
	var kept: Array = []
	for creature in _loaded_creatures.get(chunk_coord, []):
		if not is_instance_valid(creature) or creature.info == null:
			continue
		if not KeptAnimals.is_worth_keeping(float(creature.trust), creature.is_tied_up()):
			continue
		kept.append({
			"species": creature.info.species,
			"position": creature.position,
			"trust": creature.trust,
			"order": creature.order,
			"is_tied": creature.is_tied_up(),
			"tied_to": creature.tie_anchor(),
		})
	DirAccess.make_dir_recursive_absolute(KEPT_ANIMALS_DIR)
	KeptAnimals.save_all(kept, _kept_animals_path(chunk_coord))
	return kept.size()


## Re-spawns the animals the player left here, ON TOP of whatever the
## aggregate says the region holds.
##
## Deliberately extra: carrying capacity governs WILD animals, and a tamed
## horse must not be crowded out of existence because the meadow it is
## standing in is already full of deer.
func _restore_kept_animals(chunk_coord: Vector2i) -> void:
	var kept := KeptAnimals.load_all(_kept_animals_path(chunk_coord))
	if kept.is_empty():
		return
	for record in kept:
		var creature := _creature_renderer.spawn_single(
			_creatures_parent, String(record["species"]), record["position"],
			self, TerrainRenderer.TILE_SIZE
		)
		if creature == null:
			continue
		creature.restore_taming(
			float(record["trust"]), int(record["order"]),
			bool(record["is_tied"]), record["tied_to"]
		)
		_loaded_creatures[chunk_coord].append(creature)


func _chunk_coord_for_tile(global_tile: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(global_tile.x) / CHUNK_SIZE), floori(float(global_tile.y) / CHUNK_SIZE)
	)


func _local_index(global_x: int, global_y: int) -> int:
	var local := _local_coord(global_x, global_y)
	return local.y * CHUNK_SIZE + local.x


func _local_coord(global_x: int, global_y: int) -> Vector2i:
	return Vector2i(posmod(global_x, CHUNK_SIZE), posmod(global_y, CHUNK_SIZE))


func _chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
