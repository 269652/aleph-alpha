extends RefCounted

const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const HydrologyField = preload("res://src/world/hydrology_field.gd")
const RiverCatalog = preload("res://src/world/river_catalog.gd")
const StonePlacement = preload("res://src/world/stone_placement.gd")
const StoneSize = preload("res://src/world/stone_size.gd")
const OrePlacement = preload("res://src/world/ore_placement.gd")
const OpenChannelFlow = preload("res://src/world/open_channel_flow.gd")
const ProceduralRiverFlowSprite = preload("res://src/rendering/procedural_river_flow_sprite.gd")
const DamImpoundment = preload("res://src/world/dam_impoundment.gd")

## The BuildingPiece id a player-built check dam is stored as (see
## docs/concept/rivers.md). One string is deliberately both the item id and
## the piece id, so the existing placeable-arming path places it while
## BuildingPiece.has_piece lights up collision/atlas/persistence.
const DAM_PIECE_ID := "stone_dam"

## The droppable boulder piece (see BuildingPiece "boulder" and
## docs/concept/rivers.md "Boulders shape the flow").
const BOULDER_PIECE_ID := "boulder"

## The same deterministic stone roll StoneRenderer spawns from -- so the
## water bends around exactly the boulders the player can see.
var _flow_stone_placement := StonePlacement.new()
var _flow_ore_placement := OrePlacement.new()
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const TreeRenderer = preload("res://src/rendering/tree_renderer.gd")
const StoneRenderer = preload("res://src/rendering/stone_renderer.gd")
const GeologyRenderer = preload("res://src/rendering/geology_renderer.gd")
const Strata = preload("res://src/world/strata.gd")
const CaveEntrancePlacement = preload("res://src/world/cave_entrance_placement.gd")
const TallGrass = preload("res://src/world/tall_grass.gd")
const DecorationLod = preload("res://src/rendering/decoration_lod.gd")
const DisplayScaling = preload("res://src/rendering/display_scaling.gd")
const ProceduralGrassSprite = preload("res://src/rendering/procedural_grass_sprite.gd")
const IllustratedGrassPatch = preload("res://src/rendering/illustrated_grass_patch.gd")
const FlowerPatch = preload("res://src/world/flower_patch.gd")
const SeedDispersal = preload("res://src/world/seed_dispersal.gd")
const SeedCaching = preload("res://src/gameplay/seed_caching.gd")
const SquirrelNutCaching = preload("res://src/gameplay/squirrel_nut_caching.gd")
const ScentField = preload("res://src/world/scent_field.gd")
const ProceduralFlowerSprite = preload("res://src/rendering/procedural_flower_sprite.gd")
const ProceduralSeedSprite = preload("res://src/rendering/procedural_seed_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const WildCropPatch = preload("res://src/world/wild_crop_patch.gd")
const WildCropRenderer = preload("res://src/rendering/wild_crop_renderer.gd")
const DecomposerRenderer = preload("res://src/rendering/decomposer_renderer.gd")
const LumberjackMarker = preload("res://src/rendering/lumberjack_marker.gd")
const LogisticsMarker = preload("res://src/rendering/logistics_marker.gd")
const StructureStockStore = preload("res://src/emergence/structure_stock_store.gd")

## How much of a tile a ground-cover tuft (grass, scrub, lichen) covers.
## Well under 1: a clump of grass sits ON the ground, it is not the ground.
const TUFT_WORLD_SCALE := 0.5
const DesertScrub = preload("res://src/world/desert_scrub.gd")
const ProceduralScrubSprite = preload("res://src/rendering/procedural_scrub_sprite.gd")
const TundraLichen = preload("res://src/world/tundra_lichen.gd")
const ProceduralLichenSprite = preload("res://src/rendering/procedural_lichen_sprite.gd")
const EarthwormPatch = preload("res://src/world/earthworm_patch.gd")
const ProceduralWormSprite = preload("res://src/rendering/procedural_worm_sprite.gd")
const AntColony = preload("res://src/world/ant_colony.gd")
const ForageClaims = preload("res://src/gameplay/forage_claims.gd")
const WindSway = preload("res://src/rendering/wind_sway.gd")
const WaterShader = preload("res://src/rendering/water_shader.gd")
const HillshadeShader = preload("res://src/rendering/hillshade_shader.gd")
const EntityHillshadeShader = preload("res://src/rendering/entity_hillshade_shader.gd")
const RiverFlowShader = preload("res://src/rendering/river_flow_shader.gd")
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
const EntityRef = preload("res://src/emergence/entity_ref.gd")
const Event = preload("res://src/emergence/event.gd")
const EventStore = preload("res://src/emergence/event_store.gd")
const EventStorePersistence = preload("res://src/emergence/event_store_persistence.gd")
const MemoryStore = preload("res://src/emergence/memory_store.gd")
const MemoryStorePersistence = preload("res://src/emergence/memory_store_persistence.gd")
const Household = preload("res://src/emergence/household.gd")
const HouseholdStore = preload("res://src/emergence/household_store.gd")
const HouseholdStorePersistence = preload("res://src/emergence/household_store_persistence.gd")
const Contract = preload("res://src/emergence/contract.gd")
const ContractStore = preload("res://src/emergence/contract_store.gd")
const ContractStorePersistence = preload("res://src/emergence/contract_store_persistence.gd")
const Market = preload("res://src/emergence/market.gd")
const MarketStore = preload("res://src/emergence/market_store.gd")
const Shop = preload("res://src/gameplay/shop.gd")
const MarketStorePersistence = preload("res://src/emergence/market_store_persistence.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")
const ConstructionProject = preload("res://src/emergence/construction_project.gd")
const ConstructionProjectStore = preload("res://src/emergence/construction_project_store.gd")
const SettlementSpareCapacity = preload("res://src/emergence/settlement_spare_capacity.gd")
const SettlementBuildDecision = preload("res://src/emergence/settlement_build_decision.gd")
const Institution = preload("res://src/emergence/institution.gd")
const InstitutionStore = preload("res://src/emergence/institution_store.gd")
const InstitutionStorePersistence = preload("res://src/emergence/institution_store_persistence.gd")
const InstitutionFormation = preload("res://src/emergence/institution_formation.gd")
const PlayerIdentity = preload("res://src/emergence/player_identity.gd")
const SettlementState = preload("res://src/emergence/settlement_state.gd")
const SettlementFood = preload("res://src/emergence/settlement_food.gd")
const SettlementGranary = preload("res://src/emergence/settlement_granary.gd")
const OccupationProduction = preload("res://src/emergence/occupation_production.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const SettlementTier = preload("res://src/emergence/settlement_tier.gd")
const WorldBoss = preload("res://src/emergence/world_boss.gd")
const WorldBossStore = preload("res://src/emergence/world_boss_store.gd")
const WorldBossStorePersistence = preload("res://src/emergence/world_boss_store_persistence.gd")
const WorldBossFitness = preload("res://src/gameplay/world_boss_fitness.gd")
const NpcEncounter = preload("res://src/emergence/npc_encounter.gd")
const Quest = preload("res://src/emergence/quest.gd")
const Governance = preload("res://src/emergence/governance.gd")
const RegionalTrade = preload("res://src/emergence/regional_trade.gd")
const CaravanTrip = preload("res://src/emergence/caravan_trip.gd")
const CaravanRaid = preload("res://src/emergence/caravan_raid.gd")
const CaravanMarker = preload("res://src/rendering/caravan_marker.gd")
const PathScarring = preload("res://src/world/path_scarring.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const WorldClockPersistence = preload("res://src/world/world_clock_persistence.gd")
const SnowBombShader = preload("res://src/rendering/snow_bomb_shader.gd")
const RoofShape = preload("res://src/rendering/roof_shape.gd")
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
const Pollination = preload("res://src/gameplay/pollination.gd")
const ChunkEcologyCatchup = preload("res://src/world/chunk_ecology_catchup.gd")
const KeptAnimals = preload("res://src/world/kept_animals.gd")
const GrowingJuveniles = preload("res://src/world/growing_juveniles.gd")
const MammalGrowth = preload("res://src/gameplay/mammal_growth.gd")
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
const BuildingStatics = preload("res://src/gameplay/building_statics.gd")
const BuildingDecay = preload("res://src/gameplay/building_decay.gd")
const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const VillageFinder = preload("res://src/world/village_finder.gd")
const ExploredTiles = preload("res://src/world/explored_tiles.gd")
const WeatherForecast = preload("res://src/gameplay/weather_forecast.gd")

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
## Wild mammal juveniles that are not yet fully grown -- kept individually,
## for a different reason than KEPT_ANIMALS_DIR (see GrowingJuveniles' own
## doc comment: nobody tamed or tied these, they simply aren't grown yet).
const GROWING_JUVENILES_DIR := "user://chunk_growing_juveniles"

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

## How many chunks ONE update() call may generate. 0 means "as many as are
## pending", which is what update() has always done and what every existing
## call site and test expects -- so the default changes nothing.
##
## Set to a small number by continuous per-frame gameplay (World's
## _client_process/_server_process call update() every frame): stepping
## across a chunk boundary makes a whole LOAD_RADIUS column pending at once,
## and _load_chunk is real generation plus terrain/water/hillshade/roof/snow
## painting plus every entity that chunk spawns. Five of those inside one
## frame is the periodic stall while walking. Derive the value with
## chunks_per_update_for below rather than picking one; the COLD initial load
## keeps using the update_with_progress coroutine instead.
var max_chunk_loads_per_update := 0

## How much of the streaming lead to actually spend. The one product
## decision in chunks_per_update_for below: the budget is sized to finish the
## worst-case pending set within HALF the distance the player would have to
## walk to reach unloaded ground, so a burst of frame drops, a diagonal run
## or a temporary speed boost still cannot outrun the loader.
const CHUNK_BUDGET_SAFETY_FACTOR := 2.0


## The smallest per-update chunk budget that still keeps the streaming edge
## ahead of a player moving at `tiles_per_second` while the game renders
## `frames_per_second`.
##
## Real geometry, not a guess. Crossing a chunk boundary diagonally makes at
## worst a full row AND a full column pending: 2 * (2 * LOAD_RADIUS + 1) - 1
## chunks. The nearest tile of that newly pending ring is LOAD_RADIUS *
## CHUNK_SIZE tiles from the boundary just crossed, which is the real lead
## available; CHUNK_BUDGET_SAFETY_FACTOR spends only part of it.
##
## At the player's actual base pace (Player.BASE_SPEED 80 world units per
## second over TerrainRenderer.TILE_SIZE 16 = 5 tiles/second) at 30 fps this
## returns 1. A player fast enough to cross the whole lead inside a frame
## gets the entire pending set, i.e. exactly today's unbudgeted behaviour --
## the budget degrades to correctness rather than to a visible hole in the
## ground. Pinned by test_chunks_per_update_at_the_players_real_walking_pace_
## is_one and ..._for_an_impossibly_fast_player_is_the_whole_pending_set.
static func chunks_per_update_for(tiles_per_second: float, frames_per_second: float) -> int:
	var worst_case_pending := 2 * (2 * LOAD_RADIUS + 1) - 1
	if tiles_per_second <= 0.0 or frames_per_second <= 0.0:
		return 0
	var lead_tiles := float(LOAD_RADIUS * CHUNK_SIZE) / CHUNK_BUDGET_SAFETY_FACTOR
	var frames_of_lead := lead_tiles / tiles_per_second * frames_per_second
	if frames_of_lead < 1.0:
		return worst_case_pending
	return clampi(ceili(float(worst_case_pending) / frames_of_lead), 1, worst_case_pending)

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
var _geology_renderer := GeologyRenderer.new()
var _cave_entrance_placement := CaveEntrancePlacement.new()
var _wild_crop_renderer := WildCropRenderer.new()
var _decomposer_renderer := DecomposerRenderer.new()
## "an NPC moves in" (see docs/concept/timber_construction.md's NPC
## section) -- no dedicated renderer class needed (spawning one
## LumberjackMarker per Sägewerk tile is simple enough to do directly, see
## _spawn_lumberjack_for/_despawn_lumberjack_at below), unlike the
## per-chunk-random-count decomposer/wild-crop spawners.
var _grass_sprite_generator := ProceduralGrassSprite.new()
var _illustrated_grass := IllustratedGrassPatch.new()
## The season's tint on living green, as last pushed in by World (see
## set_season_tint / SeasonalFoliage). Stored rather than read live because
## the things that need it are refreshed on their own cadences -- the grass
## material takes it immediately, wild-crop markers take it on the next
## step_wild_crops tick and at chunk load.
var _season_tint := Color.WHITE
var _scrub_sprite_generator := ProceduralScrubSprite.new()
var _lichen_sprite_generator := ProceduralLichenSprite.new()
var _wind_sway := WindSway.new()
var _water_layer: TileMapLayer  # optional GPU water overlay, see set_water_layer
var _water_material: ShaderMaterial  # the water overlay's shared shader material, see set_rain
var _water_shader := WaterShader.new()  # owns _water_material's disturbance buffer, see record_water_disturbance
var _hillshade_layer: TileMapLayer  # optional GPU relief-shading overlay, see set_hillshade_layer
var _hillshade_shader := HillshadeShader.new()
## Shares the same live sun position as _hillshade_shader (see
## set_sun_position below) but shades individual ENTITY sprites (mountain
## ore veins -- see StoneRenderer) directly rather than a ground overlay
## layer -- see EntityHillshadeShader's own doc comment for why it's a
## separate module rather than reusing _hillshade_shader itself.
var _entity_hillshade_shader := EntityHillshadeShader.new()
var _river_flow_layer: TileMapLayer  # optional GPU river-flow overlay, see set_river_flow_layer
var _river_flow_shader := RiverFlowShader.new()
## The player's own current tile, refreshed every update() call -- named for
## its original use (culling far-off water disturbances, see
## record_water_disturbance / DISTURBANCE_RADIUS_TILES) but also doubles as
## the general "where is the player right now" reference for anything else
## that needs it without its own tracking (_warmth_at_pixel, and grass's own
## tile-precise view cutoff -- see _sync_grass_sprites).
var _disturbance_center_tile := Vector2i.ZERO
## Tile the grass tile-precise view window (GRASS_VIEW_BUFFER_TILES) was last
## resynced against -- read by update() to force an immediate grass resync,
## like the chunk-boundary trigger just below it but at TILE granularity.
## Grass's view cutoff is far tighter than the chunk-level _decorates gate
## (a chunk is CHUNK_SIZE=32 tiles square; the camera shows only a fraction
## of that), so a player can walk many tiles -- bringing new ground into
## view -- without ever crossing into a new chunk. Left at the old cadence
## (GRASS_REFRESH_INTERVAL, or a chunk crossing), that stretch of walking
## found bare ground that only caught up in one late batch -- reported live:
## "the blades load way too late and the player walks into a new area
## without any blades which then suddenly appear".
var _grass_view_synced_tile := Vector2i.ZERO
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
## Per-player explored-chunk tracking (see docs/concept/wayfinding.md's Map
## item) -- no automatic caller wired from chunk-loading/generation yet
## (deliberately out of scope for this pass, see ExploredTiles' own doc
## comment); these three coordinator methods exist so a future caller (and
## Map's landmarks_visible_on_map) has something real to read/write.
var _explored_tiles := ExploredTiles.new()
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
## Where ground-flush decoration (flowers, worms, desert scrub, tundra
## lichen) is parented -- a non-y-sorted, always-behind-Entities layer, the
## same "ground effects tier" scenes/world.tscn's WaterFx/SnowFx/HillshadeFx
## siblings already use (z_index=-1, no y_sort_enabled), rather than
## _entities_parent's own y_sort_enabled=true. Ground decor sits flush with
## the floor and is always meant to draw underneath trees/creatures/the
## player regardless of Y position, so it never needed per-sprite Y-order
## interleaving with them in the first place -- forcing it into that
## interleaving is what breaks draw-call batching for the whole Entities
## group under the gl_compatibility renderer.
##
## Falls back to _entities_parent when the constructor isn't given one, so
## every EarthChunkManager.new(...) call site that predates this field keeps
## its old behaviour unchanged.
var _ground_decor_parent: Node2D
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

# -- geology (see docs/concept/geology.md) -----------------------------------
# Per-chunk topsoil/regolith Strata sim (kept for the chunk's lifetime, so a
# chamber re-revealed after the player walks away still shows its real mined
# tunnels), the surface entrance markers those chunks spawn, and which
# entrance (if any) is CURRENTLY revealed -- same "chunk-load-lifetime
# placement, entry-lifetime reveal" split _hidden_roof_chunk_coord already
# keeps for roofs, just one layer down. Only the topsoil/regolith layer is
# wired end-to-end today (see geology.md's Status); deeper layers exist as
# pure, tested Strata configuration only.
var _topsoil_strata: Dictionary = {}  # Vector2i chunk_coord -> Strata
var _cave_entrance_markers: Dictionary = {}  # Vector2i chunk_coord -> Array[Node2D]
var _revealed_cave_entrance_tile = null  # Vector2i global tile, or null
var _revealed_cave_nodes: Array = []

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
## The topsoil/regolith Strata sim for a loaded chunk, or null if that
## chunk isn't currently loaded -- lets a caller (tests, a future hazard
## HUD) inspect real per-cell rock state without reaching into private
## bookkeeping (see docs/concept/geology.md).
func strata_at(chunk_coord: Vector2i) -> Strata:
	return _topsoil_strata.get(chunk_coord)


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
var _grass_sprites: Dictionary = {}  # Vector2i chunk_coord -> {band index int -> MultiMeshInstance2D}
var _grass_refresh_accumulator := 0.0
## Wild carrot/potato (see docs/concept/wild_crops.md). One WildCropPatch per
## chunk PER CROP, not one sim juggling both -- see WildCropPatch's own doc
## comment. chunk_coord -> {crop_id String -> WildCropPatch}.
var _wild_crop_sims: Dictionary = {}
## chunk_coord -> {crop_id String -> {Vector2i cell -> WildCropMarker}}.
var _wild_crop_markers: Dictionary = {}
var _wild_crop_refresh_accumulator := 0.0
## Every crop this world grows in the wild -- the one list both _load_chunk
## and step_wild_crops iterate, so adding a future crop is a one-line change.
const WILD_CROP_IDS := ["carrot", "potato"]

## Ants/carrion bugs (see docs/concept/carrion.md). chunk_coord -> Array of
## DecomposerMarker -- no per-chunk sim needed (unlike wild crops/grass),
## since a decomposer's whole behavior lives on the marker itself and it
## queries the Carcass/CarcassGuts groups directly.
var _decomposer_markers: Dictionary = {}

## The Sägewerk's own Lumberjack -- "an NPC moves in" the moment a
## "sagewerk" modification tile exists (see
## docs/concept/timber_construction.md). chunk_coord -> {Vector2i local_cell
## -> LumberjackMarker}, mirroring _piece_collision_bodies' own per-chunk
## dict-of-cells shape -- one entry per placed Sägewerk instance, keyed by
## its own cell so a rebuild/overwrite/destroy on that exact tile can find
## and despawn just its own worker (see _spawn_lumberjack_for/
## _despawn_lumberjack_at). Persisted implicitly: the "sagewerk" tile itself
## is an ordinary chunk modification (see build_at_global), so a reloaded
## chunk re-staffs a fresh Lumberjack for every persisted Sägewerk found in
## _load_chunk -- the Lumberjack's own in-progress gathering/production
## state (log stock, shaping progress) is NOT persisted across an unload, a
## known/documented gap (see docs/progress.md), same class of limitation as
## geology's mined-tunnel state.
var _sagewerk_lumberjacks: Dictionary = {}

## Every Logistics worker autonomously spawned for a Sägewerk+Storage pair
## (see docs/concept/timber_construction.md's "Storage, logistics, and the
## autonomous dependency chain" section) -- chunk_coord -> {Vector2i
## local_cell (the SÄGEWERK's own cell, NOT any Storage's) -> {storage_key
## -> {item_id -> LogisticsMarker}}}, mirroring _sagewerk_lumberjacks' own
## per-chunk dict-of-cells shape one level deeper. A Sägewerk pairs with
## EVERY real Storage within SAGEWERK_STORAGE_PAIR_RADIUS_TILES, not just
## the single nearest one -- the innermost dict is one full worker-pair
## (one LogisticsMarker per _SAGEWERK_LOGISTICS_ITEM_IDS entry) per paired
## Storage, keyed by that Storage's own position via
## _storage_pairing_key (see _resync_logistics_for_sagewerk), the same
## "position, not structure id, is the identity" reasoning
## _structure_stock_key already uses -- so a specific Storage's own workers
## can be despawned independently of another paired Storage's when it drops
## out of range or is destroyed.
var _logistics_workers: Dictionary = {}

## Which real items a Logistics worker gets spawned for, one worker per id
## -- today's only real accumulating-output producer (the Sägewerk) has
## exactly these two (see SagewerkProduction), matching LogisticsMarker's
## own one-item-id-per-worker design (see its own class doc comment) rather
## than changing that design to carry a list.
const _SAGEWERK_LOGISTICS_ITEM_IDS := ["beam", "plank"]

## How far (in tiles) a Storage may be from a Sägewerk and still count as
## "the same worksite" for auto-spawning Logistics workers -- matches
## LogisticsMarker's own default `search_radius_tiles`: spawning a worker
## whose own search radius could never reach the Storage it was paired for
## would be a real worker that can never actually find its destination.
const SAGEWERK_STORAGE_PAIR_RADIUS_TILES := 20

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
## Vector2i chunk_coord -> AntColony (see step_ants, docs/concept/soil_fauna.md
## "Ants"). No sprite dictionary alongside it -- ants are not rendered this
## pass (see AntColony's own doc comment on scope).
var _ant_colonies: Dictionary = {}
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

## Every placed structure's own real stock -- a Storage building's inventory,
## keyed by its own tile position (see docs/concept/timber_construction.md's
## "Storage, logistics, and the autonomous dependency chain" section, and
## StructureStock/StructureStockStore's own doc comments). Not per-chunk
## tracked/evicted like the render-only dicts above -- this is real state a
## structure carries regardless of whether its chunk is currently loaded, the
## same "survives unload" contract chunk.modifications itself already has.
var _structure_stocks := StructureStockStore.new()

## Optional roof overlay layer (see set_roof_layer) -- separate TileMapLayer
## from _tile_map_layer since a roof piece shares its cell with the floor
## beneath it (Chunk.roof_modifications can't merge into `modifications`).
var _roof_layer: TileMapLayer = null
var _room_detector := RoomDetector.new()
## Real statics (see BuildingStatics / docs/concept/timber_construction.md
## #real-statics-a-support-graph-over-the-piece-grid).
var _building_statics := BuildingStatics.new()
## Withering (see BuildingDecay / docs/concept/timber_construction.md
## #withering-decay-as-a-bounded-closed-form-catch-up).
var _building_decay := BuildingDecay.new()
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

## How wide a range a brand new world may start at within the year (see
## randomize_world_age below, and docs/concept/seasons.md).
##
## Every fresh save used to start at world-age 0 exactly, and SeasonCycle's
## own phase formula puts that moment at warmth ~0.1465 -- just under
## Snowfall.FREEZING_WARMTH (0.15) -- so every new game began mid-winter-
## adjacent and reliably snowed within the first few minutes (reported: "it
## starts to snow deterministically"). A full year of possible starting
## points is the whole point: any season is a valid place for a new world to
## begin.
const NEW_GAME_WORLD_AGE_RANGE_SECONDS := SeasonCycle.SECONDS_PER_YEAR


func _init(
	tile_map_layer: TileMapLayer,
	entities_parent: Node2D,
	creatures_parent: Node2D,
	ground_decor_parent: Node2D = null
) -> void:
	_tile_map_layer = tile_map_layer
	_tile_map_layer.tile_set = _terrain_renderer.build_tile_set()
	# Tiles are painted at ART_TILE_SIZE pixels but must span only TILE_SIZE
	# world units -- scaling the layer down is what keeps art resolution and
	# world footprint independent (see TerrainRenderer.LAYER_SCALE).
	_tile_map_layer.scale = Vector2.ONE * TerrainRenderer.LAYER_SCALE
	_entities_parent = entities_parent
	_creatures_parent = creatures_parent
	# Optional and defaulted to null (see _ground_decor_parent's own doc
	# comment) so every pre-existing 3-argument call site keeps parenting
	# ground decor under Entities exactly as before.
	_ground_decor_parent = ground_decor_parent if ground_decor_parent != null else entities_parent


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
	_sync_decoration_and_grass_tracking(player_global_tile, center_chunk)

	for chunk_coord in _budgeted_load_order(center_chunk):
		_load_chunk(chunk_coord)

	_evict_far_chunks(center_chunk)
	_update_roof_visibility(player_global_tile)
	_update_geology_reveal(player_global_tile)


## The decoration-LOD and grass tile-precise-culling bookkeeping update()
## does before touching any chunk -- split out so update_with_progress below
## can share it exactly rather than drifting a second copy. Pure bookkeeping,
## no chunk generation, so it costs nothing to run up front regardless of how
## the actual load loop that follows is driven (all-at-once vs chunked).
func _sync_decoration_and_grass_tracking(player_global_tile: Vector2i, center_chunk: Vector2i) -> void:
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

	# Grass ALONE is also tile-precise culled (see _grass_view_synced_tile's
	# own doc comment for why the chunk-boundary trigger above isn't tight
	# enough on its own). This also primes sim.advance/shed_seed to run early
	# (step_tall_grass gates both behind the same accumulator) -- harmless,
	# not just cheap: growth is linear in delta and spread carries its own
	# accumulator, so more frequent smaller steps land in exactly the same
	# state (test_growth_lands_in_the_same_place_whether_batched_or_per_
	# frame). Triggering per TILE rather than per frame still matters for
	# cost -- tile crossings happen at a walking pace (a few a second), far
	# below the per-frame (60/sec) rate step_tall_grass's own throttle was
	# introduced to avoid.
	if player_global_tile != _grass_view_synced_tile:
		_grass_view_synced_tile = player_global_tile
		_grass_refresh_accumulator = GRASS_REFRESH_INTERVAL


## The chunks THIS update() call will load, in the order it will load them.
##
## Unbudgeted -- the default, and every existing caller -- this is exactly
## chunks_in_radius' own row-major order over the not-yet-loaded chunks, i.e.
## precisely what update()'s loop always did. Whatever order-sensitivity the
## ~210 existing update() call sites and the game's cold load may have is
## therefore left untouched by default.
##
## Budgeted, the pending set is sorted NEAREST FIRST and then capped.
## chunks_in_radius is row-major, so a merely capped scan would spend the
## whole budget on the far top-left corner of the radius while the ground the
## player is actually walking onto stayed unloaded. Ties (a Chebyshev ring
## holds up to eight chunks) break on row-major position, so the order stays
## fully deterministic rather than depending on sort_custom's instability.
func _budgeted_load_order(center_chunk: Vector2i) -> Array[Vector2i]:
	var pending: Array[Vector2i] = []
	for chunk_coord in chunks_in_radius(center_chunk, LOAD_RADIUS):
		if not _loaded_chunks.has(chunk_coord):
			pending.append(chunk_coord)
	if max_chunk_loads_per_update <= 0:
		return pending

	var nearest_first := func(a: Vector2i, b: Vector2i) -> bool:
		var a_distance := _chebyshev_distance(a, center_chunk)
		var b_distance := _chebyshev_distance(b, center_chunk)
		if a_distance != b_distance:
			return a_distance < b_distance
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	pending.sort_custom(nearest_first)
	if pending.size() > max_chunk_loads_per_update:
		pending.resize(max_chunk_loads_per_update)
	return pending


## The eviction half of update() -- split out for the same reason as
## _sync_decoration_and_grass_tracking above: update_with_progress needs it
## verbatim, after its own chunked load loop rather than update()'s
## all-at-once one.
func _evict_far_chunks(center_chunk: Vector2i) -> void:
	for chunk_coord in _loaded_chunks.keys().duplicate():
		if _chebyshev_distance(chunk_coord, center_chunk) > UNLOAD_RADIUS:
			_unload_chunk(chunk_coord)


## Chunk coordinates update(player_global_tile) would load RIGHT NOW -- those
## within LOAD_RADIUS not already loaded. Pure and cheap (no chunk
## generation, just the same chunks_in_radius/is_chunk_loaded check update()'s
## own load loop already makes) -- this is what makes update_with_progress's
## total knowable up front, for a real determinate percentage rather than an
## indeterminate spinner (see docs/concept/persistence.md's "Loading screens"
## section).
func pending_load_chunks(player_global_tile: Vector2i) -> Array[Vector2i]:
	var center_chunk := _chunk_coord_for_tile(player_global_tile)
	var pending: Array[Vector2i] = []
	for chunk_coord in chunks_in_radius(center_chunk, LOAD_RADIUS):
		if not _loaded_chunks.has(chunk_coord):
			pending.append(chunk_coord)
	return pending


## Same work as update(), but for the INITIAL cold load a fresh New Game/Load
## Game/Join pays (see World._show_loading_overlay) -- awaits one process
## frame after each chunk's real generation cost instead of loading the whole
## radius in one uninterrupted synchronous loop. That one change is what lets
## the engine actually PRESENT a frame between chunks: update()'s own loop
## never yields, so nothing -- not even an indeterminate spinner -- can be
## seen to move for its entire real duration (measured ~39-90s+ per call, see
## docs/progress.md's "Loading screens" entry); reported back as "the loading
## screen ... still looks like it's hanging" even with that spinner in place.
## `on_progress`, called as (loaded_count, real_total) once before the first
## chunk and once after each one, is what a caller (LoadingOverlay) uses to
## show a real percentage instead -- the chunk set to load is bounded and
## known up front (pending_load_chunks), so this was always knowable; it just
## needed update()'s synchronous loop broken up across frames, which is
## exactly the restructuring previously deferred as out of scope for a
## loading screen alone.
##
## Every other caller -- continuous per-frame gameplay in World._process/
## _client_process, and the whole existing update() test suite -- keeps
## calling the synchronous update() completely unchanged; this is purely
## additive.
func update_with_progress(player_global_tile: Vector2i, on_progress: Callable = Callable()) -> void:
	_disturbance_center_tile = player_global_tile
	var center_chunk := _chunk_coord_for_tile(player_global_tile)
	_sync_decoration_and_grass_tracking(player_global_tile, center_chunk)

	var pending := pending_load_chunks(player_global_tile)
	var total := pending.size()
	if on_progress.is_valid():
		on_progress.call(0, total)
	var loaded := 0
	for chunk_coord in pending:
		_load_chunk(chunk_coord)
		loaded += 1
		if on_progress.is_valid():
			on_progress.call(loaded, total)
		await Engine.get_main_loop().process_frame

	_evict_far_chunks(center_chunk)
	_update_roof_visibility(player_global_tile)
	_update_geology_reveal(player_global_tile)


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


## The spawn's own chunk coordinate (see set_spawn_tile above) -- Compass's
## "point me home" default target needs to read this without reaching into
## the private field directly.
func spawn_chunk_coord() -> Vector2i:
	return _spawn_chunk_coord


## Marks `chunk_coord` explored (see ExploredTiles above). Returns true only
## if this chunk was newly marked -- idempotent, same as ExploredTiles.
## mark_visited itself.
func mark_chunk_explored(chunk_coord: Vector2i) -> bool:
	return _explored_tiles.mark_visited(chunk_coord)


## Every distinct chunk coordinate marked explored so far.
func explored_chunks() -> Array:
	return _explored_tiles.visited_chunks()


func is_chunk_explored(chunk_coord: Vector2i) -> bool:
	return _explored_tiles.is_visited(chunk_coord)


func _difficulty_tier_at(chunk_coord: Vector2i) -> int:
	if not _spawn_configured:
		return RegionDifficulty.Tier.HARD
	return _region_difficulty.tier_at(chunk_coord, _spawn_chunk_coord)


func herbivore_population_at_chunk(chunk_coord: Vector2i) -> float:
	return _ecosystem.herbivore_population(chunk_coord)


## This region's herbivore carrying capacity (see EcosystemSimulation.
## herbivore_capacity_at) -- CreatureMarker's own density-vs-capacity signal
## for herd (foot-and-mouth-like) disease transmission pressure (see
## docs/concept/disease.md, DiseaseModel.herd_transmission_chance). Mirrors
## herbivore_population_at_chunk's exact pattern.
func herbivore_capacity_at_chunk(chunk_coord: Vector2i) -> float:
	return _ecosystem.herbivore_capacity_at(chunk_coord)


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
## The withering counterpart to _unloaded_ecology directly above: per-chunk
## piece-condition snapshot recorded at unload + the world-age then, so a
## revisited chunk's placed pieces catch up on the elapsed unloaded time
## (see BuildingDecay / docs/concept/timber_construction.md#withering-decay-
## as-a-bounded-closed-form-catch-up) instead of silently sitting at
## whatever condition a freshly (re)generated Chunk object defaults to.
## chunk_coord -> {unloaded_at: float, condition: Dictionary (local cell ->
## float, the exact snapshot of Chunk.piece_condition at unload time)}.
## In-memory only, same as _unloaded_ecology -- Chunk.piece_condition itself
## is not persisted to disk (see that field's own doc comment), so this
## record does not survive a real app restart either.
var _unloaded_piece_condition: Dictionary = {}
## The offscreen construction-labor catch-up's own unload-time record (see
## docs/concept/timber_construction.md's "Unloaded / offscreen fidelity"
## subsection and _apply_construction_labor_catchup below) -- SIMPLER than
## _unloaded_piece_condition/_unloaded_ecology directly above: those two
## snapshot real per-region STATE because it lives on a Chunk/
## EcosystemSimulation region object that gets discarded on unload.
## _construction_project_store above is never discarded (manager-lifetime
## scope, same as _household_store/_market_store), so a project's own
## labor_hours_accumulated is already safe across an unload -- only the
## world-age this chunk was unloaded AT needs recording, so a reload can
## compute the real elapsed unloaded time to feed
## ConstructionProjectStore.advance_project_labor. chunk_coord -> {unloaded_at:
## float}. In-memory only, same "does not survive a real app restart" caveat
## as its two siblings above.
var _unloaded_construction_labor: Dictionary = {}
var _fruiting_accumulator := 0.0
## The world-age at the previous fruiting step, so fallen_between integrates
## exactly the elapsed interval (all trees share the one world clock).
var _last_fruiting_time := 0.0

## The world's causal event graph (see docs/emergence/00-emergence-architecture.md,
## docs/roadmap.md's "Emergence substrate" section). One shared store, owned
## here alongside the world clock and every other piece of shared world state
## -- the same placement _snow_trail/_forage_claims already use for their own
## reasons.
var _event_store := EventStore.new()


func event_store() -> EventStore:
	return _event_store


## Every entity's own recollection of events it took part in (see
## docs/emergence/02-history-memory-rumors.md "Memory") -- layered on top of
## _event_store rather than folded into it, so appending an event and
## deciding who remembers it stay two separate, independently testable
## steps.
var _memory_store := MemoryStore.new()


func memory_store() -> MemoryStore:
	return _memory_store


## Persistence, reset, and wipe for the memory store -- same four-function
## shape as save_event_store/load_event_store/reset_event_store/
## wipe_event_store immediately above, since the two are wired into the same
## New Game / Load Game / autosave lifecycle together (see World).
func save_memory_store(path: String = MemoryStorePersistence.SAVE_PATH) -> void:
	MemoryStorePersistence.new().save(_memory_store, path)


func load_memory_store(path: String = MemoryStorePersistence.SAVE_PATH) -> void:
	_memory_store = MemoryStorePersistence.new().load_bank(path)


func reset_memory_store() -> void:
	_memory_store = MemoryStore.new()


func wipe_memory_store(path: String = MemoryStorePersistence.SAVE_PATH) -> void:
	MemoryStorePersistence.new().wipe(path)
	reset_memory_store()


## Households and what they own (see docs/emergence/01/03) -- one more piece
## of shared world state alongside the event/memory stores above.
var _household_store := HouseholdStore.new()


func household_store() -> HouseholdStore:
	return _household_store


func save_household_store(path: String = HouseholdStorePersistence.SAVE_PATH) -> void:
	HouseholdStorePersistence.new().save(_household_store, path)


func load_household_store(path: String = HouseholdStorePersistence.SAVE_PATH) -> void:
	_household_store = HouseholdStorePersistence.new().load_store(path)


func reset_household_store() -> void:
	_household_store = HouseholdStore.new()


func wipe_household_store(path: String = HouseholdStorePersistence.SAVE_PATH) -> void:
	HouseholdStorePersistence.new().wipe(path)
	reset_household_store()


## Claims `property_id` for the local player via a real Deed
## (docs/concept/player_citizenship.md's Deed item) -- the exact same
## form_household -> grant_property pairing record_settlement_founded_if_new
## already establishes for a villager's own house, keyed by PlayerIdentity.
## PLAYER_ENTITY_ID instead of an npc id. Both underlying calls are already
## idempotent (form_household returns the same household on a second call;
## grant_property re-granting to the same owner is a no-op), so claiming the
## same property twice is safe and does not change who owns it. Also
## records a real event, the same "one call, two stores kept in sync" shape
## every other coordinator in this file already uses.
## `settlement_id`: when the claimed land sits inside a settlement that
## already exists, claiming it also makes the player a MEMBER of that place
## (see record_player_settled_if_new, and concept/player_citizenship.md's
## "Residency"). Defaults to empty -- claiming land in open wilderness makes
## you a landowner, not a citizen, and there is no one out there to be a
## citizen among.
func claim_property_with_deed(property_id: String, settlement_id: String = "") -> Household:
	var household := _household_store.form_household(PlayerIdentity.PLAYER_ENTITY_ID)
	_household_store.grant_property(household.id, property_id)

	var event := Event.new("player_claimed_property", _world_age_seconds)
	event.actors.append(household.id)
	event.tags.append(property_id)
	_event_store.append(event)
	_memory_store.witness_event(event, _world_age_seconds)

	if settlement_id != "":
		record_player_settled_if_new(settlement_id)

	return household


## Records that the player now LIVES in `settlement_id`, making their
## household a real member of it -- the thing owning property alone never did
## (see concept/player_citizenship.md's "Residency").
##
## A distinct `player_settled` event type rather than reusing `npc_settled`,
## because the player is not an NPC and a log that said otherwise would be a
## lie told to every later reader of the event graph -- `/why` included, which
## exists to explain that graph back to the player. `_households_in_settlement`
## reads both types, so every system that asks "who lives here" (settlement
## tier, InstitutionFormation's thresholds, the settlement's market) picks the
## player up without any of them learning a new concept.
##
## Returns true only when this actually changed something, matching the
## record_*_if_new family. Two guards, and both are load-bearing rather than
## defensive: a settlement with no history is not a settlement (the event graph
## is the authority on what exists, the same way record_settlement_founded_if_new
## and record_path_worn_if_new already treat it), and settling twice is not
## being two people -- /deed re-run in the same chunk is ordinary play, and
## counting it twice would be a free way to push a hamlet over a tier threshold
## or an institution over its formation minimum with nobody moving in.
func record_player_settled_if_new(settlement_id: String) -> bool:
	var history := _event_store.events_for_entity(settlement_id)
	if history.is_empty():
		return false
	for event in history:
		if event.type == "player_settled":
			return false

	# The ACTOR is the player's entity id, not their household id, so
	# _households_in_settlement can resolve it through the same
	# household_for(actors[0]) lookup it already does for an npc_settled
	# event. Same shape in, same shape out, one derivation for both.
	_household_store.form_household(PlayerIdentity.PLAYER_ENTITY_ID)
	var settled := Event.new("player_settled", _world_age_seconds)
	settled.actors = [PlayerIdentity.PLAYER_ENTITY_ID]
	settled.witnesses = [settlement_id]
	_event_store.append(settled)
	_memory_store.witness_event(settled, _world_age_seconds)
	return true


## Contracts and their lifecycle (see docs/emergence/03-contracts-property-
## economy.md "Contracts") -- one more piece of shared world state alongside
## the stores above.
var _contract_store := ContractStore.new()


func contract_store() -> ContractStore:
	return _contract_store


func save_contract_store(path: String = ContractStorePersistence.SAVE_PATH) -> void:
	ContractStorePersistence.new().save(_contract_store, path)


func load_contract_store(path: String = ContractStorePersistence.SAVE_PATH) -> void:
	_contract_store = ContractStorePersistence.new().load_store(path)


func reset_contract_store() -> void:
	_contract_store = ContractStore.new()


func wipe_contract_store(path: String = ContractStorePersistence.SAVE_PATH) -> void:
	ContractStorePersistence.new().wipe(path)
	reset_contract_store()


## Proposes a contract AND records it as a real event, in one call -- the
## same "one call, two stores kept in sync" shape
## record_settlement_founded_if_new already establishes for founding, so a
## contract can never exist in _contract_store without a matching entry in
## _event_store. No live gameplay trigger calls this yet (see
## docs/progress.md's Emergence Phase 4 entry: nothing in the game currently
## produces real economic activity to propose a contract FROM -- no
## production, market, or hiring exists), but the mechanism itself is real,
## tested, and ready for whichever of those lands first.
func propose_contract(
	type: String, parties: Array, obligations: Array, consideration: String, deadline: float
) -> Contract:
	var contract := _contract_store.propose(
		type, parties, obligations, consideration, deadline, _world_age_seconds
	)
	_record_contract_event("contract_proposed", contract)
	return contract


## Proposes a contract naming the local player's own household as one party
## (docs/concept/player_citizenship.md's Ledger item) -- a thin wrapper over
## the existing propose_contract, the same accept/fulfil/breach lifecycle
## _step_settlement_trade already drives for two NPC households. No new
## accept/fulfil/breach counterpart is needed: ContractStore._transition
## never assumes anything about WHICH entity a party is, so the existing
## generic accept_contract/fulfill_contract/breach_contract already work
## unchanged for a contract that names a player household. form_household
## is idempotent, so calling it every time is safe.
func player_propose_contract(
	type: String, counterparty_id: String, obligations: Array, consideration: String, deadline: float
) -> Contract:
	var player_household := _household_store.form_household(PlayerIdentity.PLAYER_ENTITY_ID)
	return propose_contract(
		type, [player_household.id, counterparty_id], obligations, consideration, deadline
	)


func accept_contract(contract_id: String) -> bool:
	return _drive_contract(contract_id, _contract_store.accept(contract_id, _world_age_seconds), "contract_accepted")


func activate_contract(contract_id: String) -> bool:
	return _drive_contract(contract_id, _contract_store.activate(contract_id, _world_age_seconds), "contract_active")


func fulfill_contract(contract_id: String) -> bool:
	return _drive_contract(contract_id, _contract_store.fulfill(contract_id, _world_age_seconds), "contract_fulfilled")


func breach_contract(contract_id: String) -> bool:
	return _drive_contract(contract_id, _contract_store.breach(contract_id, _world_age_seconds), "contract_breached")


func default_on_contract(contract_id: String) -> bool:
	return _drive_contract(contract_id, _contract_store.default_on(contract_id, _world_age_seconds), "contract_defaulted")


func cancel_contract(contract_id: String) -> bool:
	return _drive_contract(contract_id, _contract_store.cancel(contract_id, _world_age_seconds), "contract_cancelled")


## Records the matching event ONLY when the transition actually happened --
## an invalid transition (the store already refused it) records no event,
## since nothing meaningful actually occurred.
func _drive_contract(contract_id: String, transitioned: bool, event_type: String) -> bool:
	if not transitioned:
		return false
	var contract := _contract_store.get_contract(contract_id)
	if contract != null:
		_record_contract_event(event_type, contract)
	return true


## Records one contract lifecycle transition as a real event, naming the
## villagers who were there for the ones worth being there for.
##
## _step_settlement_trade drives this every settlement step, which makes
## contract_proposed/accepted/active/fulfilled the highest-volume real
## settlement activity in this file -- so witnesses land here already
## bounded rather than as an unbounded fan-out into a persisted MemoryStore
## (the same lesson _settlement_production_outcome and
## SETTLEMENT_STATUS_DWELL_STEPS already carry). Two bounds, both on the
## MEMORY side only: the events themselves are always appended in full,
## because each contract really is its own contract and the event ledger is
## what /why reads back.
##
## 1. Only the OUTCOME is witnessed (see _CONTRACT_OUTCOME_EVENTS). The
##    whole propose -> accept -> activate -> fulfil chain runs inside a
##    single step, so witnessing each link would hand every villager four
##    memories of one trade; how it ended is the part a villager carries.
## 2. A repeat of the same outcome between the same parties is not news,
##    exactly _settlement_production_outcome's rule keyed on the pair rather
##    than on settlement|recipe -- the same two households trade every step
##    forever, and "they made good again" is not a thing anyone would
##    re-learn. A CHANGE (a pair that has been fulfilling starts breaching)
##    is news and is witnessed.
func _record_contract_event(event_type: String, contract: Contract) -> void:
	var event := Event.new(event_type, _world_age_seconds)
	for party in contract.parties:
		event.actors.append(party)
	if _contract_outcome_is_news(event_type, event.actors):
		event.witnesses = _villager_witnesses_of(event.actors)
	_event_store.append(event)
	_memory_store.witness_event(event, _world_age_seconds)


## How a contract ENDED -- the transitions a villager would actually carry a
## memory of, as opposed to the bookkeeping that gets a trade to one of
## them. Matches ContractStore's own terminal states.
const _CONTRACT_OUTCOME_EVENTS := [
	"contract_fulfilled", "contract_breached", "contract_defaulted", "contract_cancelled",
]
## "party|party|..." (sorted) -> the last outcome actually fanned to that
## group's villagers. A session-lifetime cache only -- the answer it holds
## is derived from the PERSISTED event history (see
## _recorded_contract_outcome), which is what actually makes the guard
## survive a reload. Without that seeding it was worse than no guard across
## loads: the same two households trade every step forever, so every load
## re-fanned one more identical MemoryRecord to every villager into a
## persisted store, exactly the growth the guard exists to stop.
var _contract_outcome_witnessed: Dictionary = {}


## True when this transition is an OUTCOME these parties have not already
## had witnessed -- and records it as witnessed, so the caller asks exactly
## once per event.
func _contract_outcome_is_news(event_type: String, parties: Array[String]) -> bool:
	if not _CONTRACT_OUTCOME_EVENTS.has(event_type):
		return false
	var sorted_parties: Array[String] = []
	for party in parties:
		sorted_parties.append(party)
	sorted_parties.sort()
	var key := "|".join(sorted_parties)
	# First ask of the session: what these parties last had witnessed is on
	# disk, not gone -- read it back before treating this as their first.
	if not _contract_outcome_witnessed.has(key):
		_contract_outcome_witnessed[key] = _recorded_contract_outcome(sorted_parties)
	if _contract_outcome_witnessed.get(key, "") == event_type:
		return false
	_contract_outcome_witnessed[key] = event_type
	return true


## The last contract OUTCOME actually recorded between exactly these parties,
## read back out of the persisted event graph, or "" if they have never had
## one. Guarded on real history rather than an in-memory flag, the same
## convention record_path_worn_if_new and _record_ruin_from already follow.
##
## Walks one party's own event index backwards and keeps only the outcomes
## whose actor set is exactly this group -- a household trades with several
## neighbours, and "how it went with THIS partner" is the thing the caller's
## key is about.
func _recorded_contract_outcome(sorted_parties: Array[String]) -> String:
	if sorted_parties.is_empty():
		return ""
	var history := _event_store.events_for_entity(sorted_parties[0])
	for i in range(history.size() - 1, -1, -1):
		var event: Event = history[i]
		if not _CONTRACT_OUTCOME_EVENTS.has(event.type):
			continue
		var actors: Array[String] = []
		for actor in event.actors:
			actors.append(actor)
		actors.sort()
		if actors == sorted_parties:
			return event.type
	return ""


## Local supply/demand-driven markets, one per settlement (see
## docs/emergence/03-contracts-property-economy.md "Markets") -- one more
## piece of shared world state alongside the stores above.
var _market_store := MarketStore.new()
var _recipe_book := CraftingRecipeBook.new()

## The Settlement construction ledger (see docs/concept/timber_construction.md
## "Settlement construction ledger" / ConstructionProject/
## ConstructionProjectStore) -- one more piece of shared world state alongside
## _household_store/_market_store above, at the SAME manager-lifetime scope
## (never discarded per-chunk-unload the way a Chunk's own piece_condition or
## EcosystemSimulation's per-region state is) so a project's real
## labor_hours_accumulated survives a chunk unload/reload with no snapshotting
## of its own -- only "how long did this chunk sit unloaded" needs recording
## (see _unloaded_construction_labor below). No persistence wrapper yet (see
## that doc's own "Named, honest limitations" -- to_dicts/from_dicts are real
## but nothing calls them from a save path), the same "additive capability, no
## live save-path caller yet" honesty _market_store's own sibling stores
## already carry elsewhere in this file.
var _construction_project_store := ConstructionProjectStore.new()


func market_store() -> MarketStore:
	return _market_store


func construction_project_store() -> ConstructionProjectStore:
	return _construction_project_store


func save_market_store(path: String = MarketStorePersistence.SAVE_PATH) -> void:
	MarketStorePersistence.new().save(_market_store, path)


func load_market_store(path: String = MarketStorePersistence.SAVE_PATH) -> void:
	_market_store = MarketStorePersistence.new().load_store(path)


func reset_market_store() -> void:
	_market_store = MarketStore.new()


func wipe_market_store(path: String = MarketStorePersistence.SAVE_PATH) -> void:
	MarketStorePersistence.new().wipe(path)
	reset_market_store()


## Attempts `recipe_id` against `settlement_id`'s own market stock AND
## records the outcome as a real event, in one call -- the same "one call,
## two stores kept in sync" shape record_settlement_founded_if_new/
## propose_contract already establish. A resource shortage genuinely blocks
## production (CraftingRecipeBook.can_craft's own check, run against market
## stock instead of a player's inventory) and that failure is exactly as
## recorded as a success -- the Phase 5 exit criterion ("a resource shortage
## can... cause downstream production failure") made concrete and
## /why-inspectable, not a scripted event.
##
## ONE ATTEMPT IS NO LONGER ONE EVENT. This is public API -- the dev console
## calls it directly -- and its contract changed when
## _settlement_production_outcome landed: a repeated FAILURE of the same
## settlement|recipe pair returns a perfectly real `result` and records
## nothing at all, because the shortage is already on record and nothing
## about it has changed. Callers get the truthful outcome of every attempt;
## only a caller that counted EVENTS to count attempts is wrong. Successes
## are unaffected -- every one of them is still recorded, one per attempt
## (see _settlement_production_outcome for why that asymmetry is deliberate).
func attempt_production(settlement_id: String, recipe_id: String) -> Dictionary:
	var market := _market_store.market_for(settlement_id)
	var result: Dictionary = market.produce(_recipe_book, recipe_id)

	# A repeated FAILURE is not news (see _settlement_production_outcome):
	# the shortage is already recorded and nothing about it has changed.
	var outcome_key := "%s|%s" % [settlement_id, recipe_id]
	# First ask of the session for this pair: how it last went is on disk,
	# not gone -- read it back before treating this as their first attempt.
	if not _settlement_production_outcome.has(outcome_key):
		var recorded := _recorded_production_outcome(settlement_id, recipe_id)
		if recorded != "":
			_settlement_production_outcome[outcome_key] = recorded
	var previously_failed: bool = _settlement_production_outcome.get(outcome_key, "") == "failed"
	_settlement_production_outcome[outcome_key] = "succeeded" if result.success else "failed"
	if not result.success and previously_failed:
		return result

	var event := Event.new(
		"production_succeeded" if result.success else "production_failed", _world_age_seconds
	)
	event.actors.append(settlement_id)
	event.tags.append(recipe_id)
	event.witnesses = _villager_witnesses_of(event.actors)
	_event_store.append(event)
	_memory_store.witness_event(event, _world_age_seconds)

	return result


## settlement_id|recipe_id -> the last outcome actually event-sourced for
## that pair, so a settlement that has been short of an input for an hour
## says so ONCE. Exactly the guard _settlement_status already applies to
## status labels, for exactly the same reason ("do not event-source every
## low-level movement"): _step_settlement_production re-attempts every
## household's recipe every SETTLEMENT_STEP_INTERVAL, so an unstocked
## settlement was appending an identical production_failed record roughly
## once per household per 30s forever -- within ten minutes every villager's
## entire memory bank is one repeated non-event, with nothing left to
## gossip about or disagree over.
##
## SUCCESSES are deliberately NOT guarded: each one is real goods that were
## really made, and _production_counts_for_settlement counts them one by one
## to infer specialization -- collapsing repeats there would silently break
## Phase 9's tier/specialization derivation.
##
## A session-lifetime cache only, but not a session-lifetime memory: the
## answer it holds is derived from the PERSISTED event history (see
## _recorded_production_outcome), the same seeding _settlement_status and
## _contract_outcome_witnessed already carry. Without it every load
## re-recorded each still-failing recipe once more -- measured on a real
## six-store reload of an unchanged one-household settlement, that plus the
## tier hole below was +2 events and +2 MemoryRecords per villager, per
## load, forever, into a store that only ever grows.
var _settlement_production_outcome: Dictionary = {}


## How `recipe_id` last actually went for `settlement_id`, read back out of
## the persisted event history ("failed"/"succeeded", or "" if it has never
## been attempted) -- guarded on real history rather than an in-memory flag,
## the same convention _recorded_settlement_status and
## _recorded_contract_outcome already follow.
##
## Matched on BOTH halves of the caller's key: attempt_production records
## the recipe as the event's first tag and the settlement as its actor, and
## a settlement runs one recipe per occupation, so "how it went" is only
## meaningful for this settlement AND this recipe.
func _recorded_production_outcome(settlement_id: String, recipe_id: String) -> String:
	var history := _event_store.events_for_entity(settlement_id)
	for i in range(history.size() - 1, -1, -1):
		var event: Event = history[i]
		if event.type != "production_failed" and event.type != "production_succeeded":
			continue
		if event.tags.is_empty() or event.tags[0] != recipe_id:
			continue
		return "failed" if event.type == "production_failed" else "succeeded"
	return ""


## Institutions (see docs/emergence/01-society-and-institutions.md) -- one
## more piece of shared world state alongside the stores above.
var _institution_store := InstitutionStore.new()


func institution_store() -> InstitutionStore:
	return _institution_store


func save_institution_store(path: String = InstitutionStorePersistence.SAVE_PATH) -> void:
	InstitutionStorePersistence.new().save(_institution_store, path)


func load_institution_store(path: String = InstitutionStorePersistence.SAVE_PATH) -> void:
	_institution_store = InstitutionStorePersistence.new().load_store(path)


func reset_institution_store() -> void:
	_institution_store = InstitutionStore.new()


func wipe_institution_store(path: String = InstitutionStorePersistence.SAVE_PATH) -> void:
	InstitutionStorePersistence.new().wipe(path)
	reset_institution_store()


## Checks REAL accumulated coordination between `party_a` and `party_b`
## (fulfilled contracts between them, see InstitutionFormation) and forms an
## institution if it crosses the formation threshold -- "NPCs can
## independently form... an institution" made concrete: gated by real
## history, not a bare create-on-demand call. Returns null (and records
## nothing) below the threshold, or if an active institution for exactly
## these two already exists (the same once-only guard every other
## coordinator in this file already uses).
func attempt_institution_formation(type: String, party_a: String, party_b: String) -> Institution:
	if not InstitutionFormation.should_form(_contract_store, party_a, party_b):
		return null
	if _institution_store.active_institution_for([party_a, party_b]) != null:
		return null

	var institution := _institution_store.form(type, [party_a, party_b], _world_age_seconds)
	var event := Event.new("institution_formed", _world_age_seconds)
	event.actors.append(party_a)
	event.actors.append(party_b)
	event.importance = 0.3
	event.witnesses = _villager_witnesses_of(event.actors)
	_event_store.append(event)
	_memory_store.witness_event(event, _world_age_seconds)
	return institution


## Attempts to found/join an institution with the local player's own
## household as one party (docs/concept/player_citizenship.md's Charter
## item) -- a thin wrapper over the existing attempt_institution_formation,
## gated by the SAME real InstitutionFormation.should_form threshold an NPC
## pair is held to; a player who hasn't built up real fulfilled contract
## history with `counterparty_id` (see player_propose_contract, above) has
## nothing to found yet, exactly like an NPC pair wouldn't. form_household
## is idempotent, so calling it every time is safe.
func player_attempt_institution_formation(type: String, counterparty_id: String) -> Institution:
	var player_household := _household_store.form_household(PlayerIdentity.PLAYER_ENTITY_ID)
	return attempt_institution_formation(type, player_household.id, counterparty_id)


## Dissolves an institution AND records it as a real event, in one call --
## "Institutions can fail, merge, split, migrate, or disappear"
## (docs/emergence/01's own invariant), and a dissolution is exactly as
## recorded as a founding.
func dissolve_institution(institution_id: String) -> bool:
	if not _institution_store.dissolve(institution_id, _world_age_seconds):
		return false
	var institution := _institution_store.get_institution(institution_id)
	var event := Event.new("institution_dissolved", _world_age_seconds)
	for member in institution.members:
		event.actors.append(member)
	event.witnesses = _villager_witnesses_of(event.actors)
	_event_store.append(event)
	_memory_store.witness_event(event, _world_age_seconds)
	# Emergence Phase 10, source 3 (docs/emergence/05 "Social transformation:
	# criminal hideouts... abandoned prisons") -- a dissolved institution
	# leaves behind a real ruin: its old headquarters/hideout.
	record_ruin_from_dissolved_institution(institution_id, event.id)
	return true


## Emergence Phase 10 (docs/emergence/05-dungeons-bosses-exploration-
## content.md "Ruins": "A ruin is the physical state of a formerly
## functional place. Creation causes must be stored."): shared plumbing for
## all three ruin-formation sources below. Never invented -- always linked
## back to the real, ALREADY-RECORDED event that caused it via
## EventStore.link_cause, so "why does this ruin exist" has a real,
## traceable answer, the literal "Creation causes must be stored" language
## made concrete. No new *Store, same as Phase 8's paths -- a ruin's whole
## lifecycle IS its own event history.
##
## Guarded on real persisted event history the same way
## record_path_worn_if_new/record_settlement_founded_if_new already are:
## once formed from a given source, a second call for the SAME source is a
## harmless no-op rather than a duplicate founding.
func _record_ruin_from(ruin_key: String, cause_event_id: String) -> void:
	var ruin_id := EntityRef.for_kind("ruin", ruin_key)
	if not _event_store.events_for_entity(ruin_id).is_empty():
		return
	var event := Event.new("ruin_formed", _world_age_seconds)
	event.actors.append(ruin_id)
	event.importance = 0.4
	# A ruin has no villagers of its own -- but whoever watched the
	# settlement decline, or the institution collapse, that CAUSED it is
	# exactly who watched the ruin appear. Inherited from the cause rather
	# than re-derived, so the witnesses of an effect can never contradict
	# the witnesses of the event this same call is about to link it to.
	# A cause nobody saw (a path quietly reclaimed by the forest) leaves a
	# ruin nobody saw either, which is the honest answer.
	var cause := _event_store.get_event(cause_event_id)
	if cause != null:
		for witness_id in cause.witnesses:
			event.witnesses.append(witness_id)
	_event_store.append(event)
	_event_store.link_cause(event.id, cause_event_id)
	_memory_store.witness_event(event, _world_age_seconds)


## Source 1 (docs/emergence/05 "Historical catastrophe"): a settlement in
## real, sustained decline (Phase 7's own automatic DECLINING status,
## food-driven) leaves behind a real ruin.
func record_ruin_from_settlement_decline(settlement_id: String, cause_event_id: String) -> void:
	_record_ruin_from("settlement_%s" % EntityRef.key_of(settlement_id), cause_event_id)


## Source 2 (docs/emergence/05 "Ecological transformation... overgrown
## ruins"): nature reclaiming a worn path (Phase 8's own automatic
## path_reclaimed event) IS literally an overgrown ruin forming -- the
## exact real-world phenomenon this dungeon-source category names, not an
## analogy stretched to fit.
func record_ruin_from_reclaimed_path(path_id: String, cause_event_id: String) -> void:
	_record_ruin_from("path_%s" % EntityRef.key_of(path_id), cause_event_id)


## Source 3 (docs/emergence/05 "Social transformation: criminal hideouts...
## abandoned prisons"): a dissolved institution's old headquarters/hideout.
## Institution ids are NOT EntityRef "kind:key" strings
## (InstitutionStore.form's own "inst_<ordinal>_<type>" shape) -- used
## verbatim rather than run through EntityRef.key_of, which only strips a
## colon-separated prefix and would return "" against one of these.
func record_ruin_from_dissolved_institution(institution_id: String, cause_event_id: String) -> void:
	_record_ruin_from("institution_%s" % institution_id, cause_event_id)


## World bosses (see src/gameplay/world_boss_fitness.gd's own fitness/
## promotion math, docs/concept/worldbosses.md) -- one more piece of shared
## world state alongside the stores above.
var _world_boss_store := WorldBossStore.new()
var _world_boss_fitness := WorldBossFitness.new()


func world_boss_store() -> WorldBossStore:
	return _world_boss_store


func save_world_boss_store(path: String = WorldBossStorePersistence.SAVE_PATH) -> void:
	WorldBossStorePersistence.new().save(_world_boss_store, path)


func load_world_boss_store(path: String = WorldBossStorePersistence.SAVE_PATH) -> void:
	_world_boss_store = WorldBossStorePersistence.new().load_store(path)


func reset_world_boss_store() -> void:
	_world_boss_store = WorldBossStore.new()


func wipe_world_boss_store(path: String = WorldBossStorePersistence.SAVE_PATH) -> void:
	WorldBossStorePersistence.new().wipe(path)
	reset_world_boss_store()


## Scores a real individual against WorldBossFitness's real threshold AND
## records a successful promotion as a real event, in one call -- the same
## "one call, two stores kept in sync" shape every other coordinator here
## already establishes. docs/emergence/05's own exit language made
## concrete: "Boss emergence and defeat must permanently affect the
## world" -- a promotion is a real, `/why`-inspectable event, not a
## scripted one. Guarded on `active_boss_for` the same way
## `attempt_institution_formation` guards on `active_institution_for`: an
## already-promoted individual is never re-promoted, and the (potentially
## costly) phase_generator is never invoked for one that fails the
## threshold check (WorldBossFitness.attempt_promotion's own guarantee).
##
## No live gameplay trigger calls this yet -- nothing in this project
## currently tracks a creature's accumulated kills or lifetime age (only
## `CreatureInfo.level` is real, and it is fixed at spawn from the
## creature's seed, not something that grows), so there is no real data to
## attempt promotion FROM automatically yet. The mechanism itself is real,
## tested, and ready the moment that tracking exists -- matches Phase 4's
## own original, honestly-documented gap before Phase 5/6 gave it real data
## to work from.
func attempt_world_boss_promotion(
	individual_id: String,
	species: String,
	level: int,
	kills: int,
	age_seconds: float,
	trait_description: String,
	phase_generator
) -> WorldBoss:
	if _world_boss_store.active_boss_for(individual_id) != null:
		return null
	var score := _world_boss_fitness.fitness_score(level, kills, age_seconds)
	var result: Dictionary = _world_boss_fitness.attempt_promotion(
		individual_id, species, score, trait_description, phase_generator
	)
	if result.is_empty():
		return null

	var boss := _world_boss_store.promote(
		individual_id, species, result["score"], result["threshold"], result["phases"], _world_age_seconds
	)
	var event := Event.new("world_boss_promoted", _world_age_seconds)
	event.actors.append(individual_id)
	event.tags.append(species)
	event.importance = 0.6
	_event_store.append(event)
	_memory_store.witness_event(event, _world_age_seconds)
	return boss


## Defeats a promoted boss AND records it as a real event, in one call --
## "Killing a boss emits a major historical event" (docs/emergence/05 "World
## bosses"), made concrete. An invalid defeat (an unknown boss, or one
## already defeated) records no event, the same guard every other
## coordinator here already respects.
func defeat_world_boss(boss_id: String) -> bool:
	if not _world_boss_store.defeat(boss_id, _world_age_seconds):
		return false
	var boss := _world_boss_store.get_boss(boss_id)
	var event := Event.new("world_boss_defeated", _world_age_seconds)
	event.actors.append(boss.individual_id)
	event.importance = 0.7
	_event_store.append(event)
	_memory_store.witness_event(event, _world_age_seconds)
	return true


## Gap-closing (docs/progress.md's Emergence Phase 2 entry): rumor
## auto-propagation, closing the ONE gap `npc.md`'s own memory/rumor
## section explicitly named -- "nothing yet calls it automatically when
## two NPCs meet at a settlement's shared landmarks on their daily
## schedule." Reads directly off ALREADY-LIVE NpcMarker state
## (`_loaded_villages`, `.schedule`) via `NpcEncounter.
## group_by_shared_landmark` -- no new position/scheduling system, exactly
## as `npc.md` itself says. Same throttled-accumulator shape
## SPREAD_INTERVAL/step_tree_spread already use.
const NPC_ENCOUNTER_INTERVAL := 30.0
var _npc_encounter_accumulator := 0.0


func step_npc_encounters(delta_seconds: float) -> void:
	_npc_encounter_accumulator += delta_seconds
	if _npc_encounter_accumulator < NPC_ENCOUNTER_INTERVAL:
		return
	_npc_encounter_accumulator -= NPC_ENCOUNTER_INTERVAL
	if _npc_encounter_accumulator >= NPC_ENCOUNTER_INTERVAL:
		_npc_encounter_accumulator = fmod(_npc_encounter_accumulator, NPC_ENCOUNTER_INTERVAL)

	var hour := _current_hour_of_day()
	for node_list in _loaded_villages.values():
		var schedules_by_npc_id: Dictionary = {}
		for node in node_list:
			if not (node is NpcMarker) or node.schedule.is_empty():
				continue
			schedules_by_npc_id[EntityRef.for_npc(node.identity.seed_value)] = node.schedule

		var groups: Dictionary = NpcEncounter.group_by_shared_landmark(schedules_by_npc_id, hour)
		for tag in groups:
			_exchange_recent_memories(groups[tag])


## Every pair in `npc_ids` exchanges their single most-recently-formed
## memory -- "catching up on the latest" rather than an exhaustive dump of
## everything each has ever witnessed. Each npc's "most recent" is
## snapshotted BEFORE any transmission in this group runs, not re-queried
## mid-loop -- otherwise the second half of a pair's exchange would hand
## back whatever the first half JUST told them a moment earlier in this
## same step, rather than their own actual news.
func _exchange_recent_memories(npc_ids: Array) -> void:
	var most_recent_event_id: Dictionary = {}
	for npc_id in npc_ids:
		var memories := _memory_store.memories_for(npc_id)
		if not memories.is_empty():
			most_recent_event_id[npc_id] = memories.back().event_id

	for i in npc_ids.size():
		for j in npc_ids.size():
			if i == j:
				continue
			var teller: String = npc_ids[i]
			if not most_recent_event_id.has(teller):
				continue
			_memory_store.transmit(teller, npc_ids[j], most_recent_event_id[teller], _world_age_seconds)


## A REAL SHARED hour-of-day derived from the world clock -- deliberately
## NOT NpcMarker's own `_current_hour()`, which is a private per-marker
## clock (elapsed real seconds since THAT marker happened to spawn, never
## synced across markers). Fine for a marker's own walk-toward-target
## movement; useless for comparing two different NPCs' schedules against
## each other, which is exactly what grouping needs. Mirrors NpcMarker.
## SECONDS_PER_SIMULATED_DAY's own pacing (both intentionally the same
## constant, see that file's own doc comment) applied to the real world
## clock instead of a per-marker one.
func _current_hour_of_day() -> int:
	var day_fraction := fmod(_world_age_seconds, SECONDS_PER_SIMULATED_DAY) / SECONDS_PER_SIMULATED_DAY
	return int(day_fraction * 24.0)


## Emergence Phase 12 (docs/concept/quests.md "Supply and demand quests",
## docs/emergence/07's own exit language: "projections... not authored
## content"): a settlement's real, currently-discoverable production
## shortfall quests, derived ENTIRELY from real household/market/recipe
## state already read by _step_settlement_production/
## production_counts_for_settlement above -- no new persisted entity, no
## event recorded (a quest is a VIEW, not a fact; there is nothing to
## event-source). Always current: called fresh, it can never go stale the
## way a recorded "quest offered" event could once the shortage it named
## resolves.
func production_shortfall_quests_for_settlement(settlement_id: String) -> Array:
	var household_occupations := _household_occupations_for_settlement(settlement_id)
	var market := _market_store.market_for(settlement_id)
	return Quest.production_shortfall_quests_for(settlement_id, household_occupations, market, _recipe_book)


## household_id -> occupation for every household in `settlement_id` with a
## real, known occupation -- the shape production_shortfall_quests_for_
## settlement above ALREADY built inline; lifted out so SettlementSpareCapacity
## (docs/concept/timber_construction.md's "Deciding what to build, and who
## builds it" section) can read the SAME real map rather than a second,
## separately-derived copy of it.
func _household_occupations_for_settlement(settlement_id: String) -> Dictionary:
	var household_occupations: Dictionary = {}
	for household_id in _households_in_settlement(settlement_id):
		var occupation := _occupation_of_household(household_id)
		if occupation != "":
			household_occupations[household_id] = occupation
	return household_occupations


## Settlement assessment cadence: every SETTLEMENT_STEP_INTERVAL of real
## time, every settlement that has ever been founded is reassessed. The same
## throttled-accumulator shape SPREAD_INTERVAL/step_tree_spread already
## uses, and the FIRST emergence coordinator with a genuinely automatic
## live trigger -- Phases 4/5/6 built real, tested, callable mechanisms with
## nothing in live gameplay calling them yet; this one is wired straight
## into World's own per-frame ecology step (see World._step_ecology_batch),
## so it runs in every real session without a console command.
const SETTLEMENT_STEP_INTERVAL := 30.0
var _settlement_step_accumulator := 0.0
## settlement_id -> last recorded SettlementState status, so a status is
## only ever event-sourced on a real CHANGE -- "do not event-source every
## low-level movement," the same principle every other coordinator in this
## file already respects. A session-lifetime cache only, but NOT a
## session-lifetime memory: the first time a settlement is assessed in a
## session this is seeded from the settlement's own PERSISTED event history
## (see _recorded_settlement_status), so a status that has not actually
## changed since the last session emits nothing.
##
## That seeding is the whole reason the dwell below is worth anything. The
## dwell exempts a settlement's FIRST assessment -- and without seeding,
## EVERY settlement ever founded is first-assessed again on every load,
## re-firing one event and one MemoryRecord per villager into stores that
## are persisted and only ever grow. Worse still right after a load, when
## almost no chunk is loaded and SettlementFood.village_market_for returns
## null for nearly the whole world, so nearly the whole world would re-fire
## settlement_declining at once.
var _settlement_status: Dictionary = {}
## How many consecutive assessments a NEW status has to hold before it is
## event-sourced -- the dwell half of the guard above, added once capacity
## started reading the LIVE VillageMarket (see SettlementFood). Before that
## it read a Market live play never stocks, so capacity was ~always 0,
## status was pinned DECLINING and this event effectively never re-fired;
## now the number under it rises every time a villager gathers, falls every
## time one eats, and collapses whenever the chunk unloads, so a settlement
## parked on a band boundary re-crosses it every step -- appending an event
## AND, since witnesses were wired, fanning a MemoryRecord to every villager
## into an unbounded, persisted MemoryStore. Exactly the noise
## _settlement_production_outcome exists to stop, multiplied by the villager
## count.
##
## Not a taste number, but be honest about which number it is. It is
## borrowed from the capacity rule, not measured against the clock: capacity
## is floor(food / FOOD_PER_HOUSEHOLD) and a VillageMarket's smallest real
## food move is one whole meal (its own FOOD_UNITS_PER_MEAL, the unit
## SettlementFood counts in), so FOOD_PER_HOUSEHOLD single-meal moves is the
## smallest food change that can shift capacity by one whole household --
## the smallest change that is the settlement changing rather than the band
## boundary being brushed.
##
## MEALS AND ASSESSMENTS ARE NOT THE SAME UNIT, and this constant does not
## pretend they are. SETTLEMENT_STEP_INTERVAL is 30 world-seconds and
## villagers gather and eat continuously, so many meals move between any two
## assessments -- requiring FOOD_PER_HOUSEHOLD assessments is therefore not
## "wait exactly as long as one household of capacity takes to move." It is
## an ordinal taken from the one real quantity the classification is already
## built on, so the window is derived from the same rule rather than picked,
## and it is deliberately the loosest such number available rather than a
## fitted one. What it actually buys is pinned in tests, not asserted here:
## a status that flips back and forth across a band boundary never fires,
## and one that holds for this many consecutive assessments does.
const SETTLEMENT_STATUS_DWELL_STEPS := SettlementState.FOOD_PER_HOUSEHOLD
## settlement_id -> {"status", "steps"}: the status currently being dwelt on
## and how many consecutive assessments it has held. Cleared the moment the
## settlement reads as its already-recorded status again, so a wobble never
## accumulates across an intervening return to normal. Session-lifetime, and
## unlike _settlement_status it needs no seeding: a settlement whose status
## is unchanged since the last session never reaches the dwell at all, and
## one whose status really has changed is genuinely at step one of holding
## it. An assessment that is SKIPPED (see step_settlements' unloaded-chunk
## guard) leaves the count frozen rather than resetting it -- no assessment
## happened, so nothing contradicted the run so far.
var _settlement_status_dwell: Dictionary = {}
## settlement_id -> last recorded SettlementTier tier / specialization,
## same "event-source only a real CHANGE" reasoning as _settlement_status
## immediately above -- and, like it, session-lifetime caches whose first
## answer of a session is read back out of the PERSISTED event history (see
## _recorded_settlement_tier / _recorded_settlement_specialization).
##
## Unseeded, the tier one was the single largest re-fire of this whole
## shape: EVERY settlement ever founded has a tier, always, so every load
## re-announced one for every settlement in the world -- one event and one
## MemoryRecord per villager apiece, into stores that only ever grow.
var _settlement_tier: Dictionary = {}
var _settlement_specialization: Dictionary = {}


## The tier `settlement_id` was last actually event-sourced as, read back
## out of its own persisted event history, or "" if it has never been
## classified -- the same convention _recorded_settlement_status follows,
## one event type over.
##
## Checked against SettlementTier.TIERS rather than trusted from the prefix,
## so a future settlement_became_<something-else> can never be mistaken for
## a tier the classifier would ever produce.
func _recorded_settlement_tier(settlement_id: String) -> String:
	var history := _event_store.events_for_entity(settlement_id)
	for i in range(history.size() - 1, -1, -1):
		var event: Event = history[i]
		if not event.type.begins_with("settlement_became_"):
			continue
		var tier := event.type.substr("settlement_became_".length())
		if SettlementTier.TIERS.has(tier):
			return tier
	return ""


## What `settlement_id` was last actually event-sourced as specializing in,
## read back out of its own persisted event history, or "" if it never has
## been. The specialization itself is the event's first TAG rather than part
## of its type (see _step_settlement_classification), so an untagged
## settlement_specialized -- which nothing writes -- reads as never having
## specialized rather than as an empty specialization.
func _recorded_settlement_specialization(settlement_id: String) -> String:
	var history := _event_store.events_for_entity(settlement_id)
	for i in range(history.size() - 1, -1, -1):
		var event: Event = history[i]
		if event.type == "settlement_specialized" and not event.tags.is_empty():
			return event.tags[0]
	return ""


func step_settlements(delta_seconds: float) -> void:
	_settlement_step_accumulator += delta_seconds
	if _settlement_step_accumulator < SETTLEMENT_STEP_INTERVAL:
		return
	_settlement_step_accumulator -= SETTLEMENT_STEP_INTERVAL
	if _settlement_step_accumulator >= SETTLEMENT_STEP_INTERVAL:
		_settlement_step_accumulator = fmod(_settlement_step_accumulator, SETTLEMENT_STEP_INTERVAL)

	for settlement_id in _known_settlement_ids():
		var market := _market_store.market_for(settlement_id)
		var household_ids := _households_in_settlement(settlement_id)
		# BOTH markets, not just the persisted emergence one (see
		# SettlementFood): live play essentially never stocks that one, while
		# the villagers' own VillageMarket holds the food they actually
		# gathered and actually eat -- reading only the first classified every
		# settlement in the world DECLINING forever, which Governance then
		# read straight back out as illegitimate.
		var village_market = SettlementFood.village_market_for(settlement_id, _loaded_villages)
		# BEFORE capacity is read, because this is what finally puts a real
		# number in front of it (see _step_settlement_granary).
		_step_settlement_granary(settlement_id, market, village_market, household_ids)
		var capacity := SettlementFood.carrying_capacity(market, village_market)
		var status := SettlementState.status_for(household_ids.size(), capacity)

		# Emergence Phase 5/4/6's own automatic triggers, closing the gap
		# Phase 7's own settlement assessment originally left open (see
		# docs/progress.md's Emergence Phase 7 entry). Run every step
		# regardless of whether `status` itself changed below -- production
		# and trade are real recurring activity, not a one-off status label.
		_step_settlement_production(settlement_id, household_ids)
		_step_settlement_trade(settlement_id, household_ids, status)
		# Runs AFTER trade, not before: an institution that just traded
		# again THIS step needs to see its own fresh fulfilled contract in
		# the recent window, not a stale pre-trade snapshot.
		_step_settlement_institution_health(household_ids)
		_step_settlement_classification(settlement_id, household_ids)

		# First assessment of this settlement THIS SESSION is not the same
		# thing as its first assessment ever: what it was last actually
		# event-sourced as is in the persisted event history, so read it
		# back before the guards below decide anything (see
		# _settlement_status).
		if not _settlement_status.has(settlement_id):
			var recorded := _recorded_settlement_status(settlement_id)
			if recorded != "":
				_settlement_status[settlement_id] = recorded

		if _settlement_status.get(settlement_id, "") == status:
			_settlement_status_dwell.erase(settlement_id)
			continue
		# An UNLOADED settlement has no live VillageMarket in memory at all,
		# so its combined food reads 0 and status_for calls it DECLINING --
		# absence of evidence, not evidence of famine. Almost the whole world
		# is in that state at any moment, and nearly all of it right after a
		# load. Once a settlement has a status on record, a capacity of zero
		# read with no live market is not a reading anyone took, so the last
		# real one stands until one can be taken again. Note what `capacity
		# <= 0` actually tests, which is NOT "no stock at all": capacity is
		# floor(food / FOOD_PER_HOUSEHOLD), so it is zero for anything up to
		# FOOD_PER_HOUSEHOLD - 1 units of real persisted food -- less than
		# one household's worth, which cannot tell a genuinely empty
		# emergence market apart from a nearly-empty one anyway. Deliberately
		# narrow: a settlement that has never been assessed still gets its
		# first, honest classification; a LOADED settlement whose live market
		# is really empty is a real famine and still declines; and an
		# unloaded settlement whose persisted emergence market carries a
		# household's worth of food or more is classified off that real
		# number (capacity > 0), guard or no guard.
		#
		# ITS PREMISE IS WEAKER NOW, and saying so is cheaper than letting
		# the paragraph above quietly go stale. An unloaded settlement's
		# granary is assessed every step (see _step_settlement_granary), so
		# a capacity of zero there is increasingly a reading somebody took
		# rather than a reading nobody could -- and the perverse consequence
		# is live: a village declines offscreen while it still has SOMETHING
		# put by, and stops being able to the moment it has nothing (pinned,
		# named, in test_an_unloaded_settlement_really_declines_by_eating_
		# through_its_stores). What is still genuinely unevidenced is the
		# settlement that has only just unloaded: while loaded it banks
		# nothing, so its granary reads empty for the first assessment or
		# two afterwards through no fault of its own. Narrowing this guard
		# is therefore downstream of a loaded settlement banking its own
		# surplus, not a change to make on its own.
		if (
			status == SettlementState.DECLINING
			and village_market == null
			and capacity <= 0
			and _settlement_status.has(settlement_id)
		):
			continue
		# A settlement's FIRST assessed status is news the moment it is
		# assessed -- nothing was on record to wobble away from, the same
		# "first failure is news" shape _settlement_production_outcome
		# already uses. Every later flip has to hold (see
		# SETTLEMENT_STATUS_DWELL_STEPS).
		if _settlement_status.has(settlement_id) and not _status_change_has_dwelled(settlement_id, status):
			continue
		_settlement_status_dwell.erase(settlement_id)
		_settlement_status[settlement_id] = status

		var event := Event.new("settlement_%s" % status, _world_age_seconds)
		event.actors.append(settlement_id)
		event.witnesses = _villager_witnesses_of(event.actors)
		_event_store.append(event)
		_memory_store.witness_event(event, _world_age_seconds)

		# Emergence Phase 10, source 1 (docs/emergence/05 "Historical
		# catastrophe"): a settlement's real, automatic decline leaves
		# behind a real ruin too.
		if status == SettlementState.DECLINING:
			record_ruin_from_settlement_decline(settlement_id, event.id)


## The status `settlement_id` was last actually event-sourced as, read back
## out of its own persisted event history, or "" if it has never had one.
## Guarded on real history rather than an in-memory flag, exactly the
## convention record_path_worn_if_new and _record_ruin_from already follow --
## a settlement's status, like a path's wear and a ruin's existence, IS its
## event history, so there is no second thing to keep in sync with it.
##
## settlement_founded shares the "settlement_" prefix and is deliberately
## NOT a status: only the three SettlementState.STATUSES count, so a
## settlement that has been founded and never assessed still reads "".
func _recorded_settlement_status(settlement_id: String) -> String:
	var history := _event_store.events_for_entity(settlement_id)
	for i in range(history.size() - 1, -1, -1):
		var event: Event = history[i]
		if not event.type.begins_with("settlement_"):
			continue
		var status := event.type.substr("settlement_".length())
		if SettlementState.STATUSES.has(status):
			return status
	return ""


## Counts one more consecutive assessment of `status` for this settlement
## and answers whether it has now held long enough to be a real change
## rather than a boundary wobble (see SETTLEMENT_STATUS_DWELL_STEPS). A
## different status restarts the count from one, so an alternating
## growing/stable flicker never accumulates toward either.
func _status_change_has_dwelled(settlement_id: String, status: String) -> bool:
	var dwell: Dictionary = _settlement_status_dwell.get(settlement_id, {})
	var steps := 1
	if dwell.get("status", "") == status:
		steps = int(dwell.get("steps", 0)) + 1
	_settlement_status_dwell[settlement_id] = {"status": status, "steps": steps}
	return steps >= SETTLEMENT_STATUS_DWELL_STEPS


## The occupation of a household's founder, reconstructed from the founder's
## own seed rather than requiring a live NpcMarker node -- NpcIdentity is
## deterministic per seed (see its own doc comment: "a settlement
## regenerates the same villagers every time its chunk reloads"), so this
## reads purely from persisted store data. "" for an unknown household or
## one whose founder is not an npc (should not happen in practice, but never
## crashes on it).
func _occupation_of_household(household_id: String) -> String:
	var household := _household_store.get_household(household_id)
	if household == null or household.members.is_empty():
		return ""
	var founder_id: String = household.members[0]
	if EntityRef.kind_of(founder_id) != "npc":
		return ""
	return NpcIdentity.new(int(EntityRef.key_of(founder_id))).occupation


## THE OFFSCREEN HALF OF A VILLAGE'S GATHERING (see SettlementGranary for
## the model and what each side of it is anchored to).
##
## Nothing had ever CREATED stock in a settlement's persisted emergence
## Market -- its only three writers all merely moved stock around -- so
## capacity, offscreen growth, offscreen decline, caravans, raids,
## specialization and every household's quest ask were all built on a ledger
## that was permanently empty. Villagers really gather; it just never
## reached the ledger the simulation reasons about.
##
## MEASURED on the same probe both ways -- an eight-household settlement
## covering all eight occupations, stepped 40 times with step_settlements +
## step_regional_trade + step_caravans (test_probe_eight_household_
## settlement, which is the reproduction and not a summary of one):
##   before: stock {}, production_succeeded 0, production_failed 8, capacity 0
##   after:  stock {fish 877, meat 25, cooked_meat 1, fruit 8},
##           production_succeeded 40, production_failed 7, capacity 227,
##           and one real settlement_specialized ("hunting center").
## With a second settlement to trade with, 20 caravans departed, 14 arrived
## and 6 were raided, where the correct count before was structurally zero
## -- RegionalTrade.has_surplus could never be true anywhere in the world.
##
## LOADED settlements are deliberately left alone. There the villagers' own
## NpcMarker/NpcEconomy really is ticking, really is gathering into the
## shared live VillageMarket and really is eating out of it every frame --
## that IS the settlement's food, and SettlementFood already counts it
## alongside the granary. Running this on top would be the same catch banked
## twice.
##
## SAY WHAT THAT COSTS, rather than letting it read as free: while a
## settlement is loaded its granary neither fills nor drains, so a village
## the player camps in banks nothing into the persisted ledger and its
## villagers' surplus goes when the chunk does -- the same "regenerates on
## revisit, no persistence" simplification the live VillageMarket itself
## already accepts. A skim (move the larder's surplus into the granary each
## assessment) would close that, and is deliberately NOT built here: it
## moves food a player can see, which is a visible gameplay change rather
## than the substrate fix this is, and SettlementFood already sums both
## ledgers so it would change no capacity, status or classification.
##
## An UNLOADED settlement has no VillageMarket and no NpcMarker at all, and
## almost the whole world is unloaded at any moment. That is exactly the
## population this exists for: without it a village only lives while the
## player is standing in it, which is the difference between a world and a
## stage set. So this is a CATCH-UP, the same shape _apply_ecology_catchup
## and _apply_piece_condition_catchup already use one section over -- the
## same rule the loaded villagers run, integrated over the assessment
## interval instead of accumulated per frame.
##
## The sub-unit remainder is carried across steps (SettlementGranary.catchup
## returns it) so a slow trickle banks eventually rather than truncating to
## nothing forever. Session-lifetime and deliberately not persisted: it is
## strictly less than one whole food unit per item, the same scope
## NpcEconomy._accumulated_yield already accepts for exactly the same
## quantity.
func _step_settlement_granary(
	settlement_id: String, market, village_market, household_ids: Array[String]
) -> void:
	if village_market != null or household_ids.is_empty():
		return

	var occupations: Array = []
	for household_id in household_ids:
		occupations.append(_occupation_of_household(household_id))
	var has_producer := SettlementGranary.has_producer(occupations)

	# A settlement with no producer among its households gathers nothing --
	# and with an empty granary there is nothing to eat either, so there is
	# no reading to take. Checked BEFORE _seeded_region_for, whose first call
	# generates a chunk.
	if not has_producer and market.stock.is_empty():
		return

	var gathered: Dictionary = {}
	if has_producer:
		gathered = SettlementGranary.gathered_over(
			occupations, _seeded_region_for(settlement_id), SETTLEMENT_STEP_INTERVAL
		)

	var result: Dictionary = SettlementGranary.catchup(
		gathered,
		_settlement_gather_carry.get(settlement_id, {}),
		market.stock,
		household_ids.size(),
		_item_catalog
	)
	_settlement_gather_carry[settlement_id] = result["carry"]
	var stock_delta: Dictionary = result["stock_delta"]
	for item_id in stock_delta:
		market.add_stock(str(item_id), int(stock_delta[item_id]))


## settlement_id -> the sub-unit gathering remainder carried into its next
## assessment (see _step_settlement_granary).
var _settlement_gather_carry: Dictionary = {}
## settlement_id -> SettlementGranary.SeededRegion, cached for the session.
var _settlement_seeded_region: Dictionary = {}


## What `settlement_id`'s own region really holds, for a settlement whose
## chunk is NOT loaded -- so its villagers gather off a real local number
## rather than a world average.
##
## Not an invented number and not a second model: this runs the settlement's
## own deterministically generated chunk through EcosystemSimulation.
## add_region and reads the three aggregates straight back out, so it is
## precisely what the live `_ecosystem` would hold the instant that chunk
## loads. EcosystemSimulation's own doc comment is what makes that the right
## reading for an unloaded region: nothing decays or grows while unloaded,
## and add_region seeds a region at equilibrium because "the world is
## assumed to already contain a mature ecosystem, not one growing from
## nothing on first visit."
##
## Cached per settlement for the session because it is a pure function of
## terrain, which is deterministic and does not change -- one chunk
## generation per settlement that actually has someone to gather, ever,
## rather than one per assessment.
##
## KNOWN LIMIT, stated rather than implied: a region the player HAS visited
## and depleted (land health, a hunted-down herd) recovers into this
## pristine baseline the moment its chunk unloads, because there is no
## persisted per-region ecology for an unloaded chunk to read -- the same
## simplification EcosystemSimulation.remove_region already documents.
func _seeded_region_for(settlement_id: String):
	if _settlement_seeded_region.has(settlement_id):
		return _settlement_seeded_region[settlement_id]
	var chunk_coord := RegionalTrade.chunk_coord_of(settlement_id)
	var probe := EcosystemSimulation.new()
	probe.add_region(chunk_coord, generator.generate_chunk(chunk_coord, CHUNK_SIZE))
	var region = SettlementGranary.SeededRegion.new()
	region.vegetation_density = probe.average_vegetation_density(chunk_coord)
	region.herbivore_population = probe.herbivore_population(chunk_coord)
	region.fish_population = probe.fish_population(chunk_coord)
	_settlement_seeded_region[settlement_id] = region
	return region


## Attempts each household's occupation-grounded recipe (see
## OccupationProduction) against its own settlement's market -- Emergence
## Phase 5's automatic trigger. Every household whose founder's occupation
## maps to a real recipe gets one attempt per settlement step; the recipe
## itself may still fail from a genuine stock shortage
## (attempt_production's own behaviour), recorded exactly like a manual
## attempt. A household with no grounded recipe (see OccupationProduction's
## own doc comment) is silently skipped, not forced onto an unrelated one.
func _step_settlement_production(settlement_id: String, household_ids: Array[String]) -> void:
	for household_id in household_ids:
		var recipe_id := OccupationProduction.recipe_for(_occupation_of_household(household_id))
		if recipe_id != "":
			attempt_production(settlement_id, recipe_id)


## A settlement's own households periodically trade with each other --
## Emergence Phase 4's automatic trigger. Deterministic, not random: the
## same two households (lowest id first) trade every step, so repeated
## success/failure is genuine accumulated history for InstitutionFormation
## to read (see below), not noise from a shuffling partner. A settlement
## with fewer than two households has no one to trade with and is skipped.
##
## The full propose -> accept -> activate -> fulfill/breach lifecycle runs
## within one step (a trade between two villagers in the same settlement is
## not a long negotiation) rather than being spread across steps. Outcome is
## tied to the settlement's OWN current prosperity (see SettlementState,
## Phase 7): a growing/stable settlement fulfills (real capacity to make
## good on a trade); a declining settlement's trade breaches (times are
## hard enough that the counterparty cannot deliver) -- the same "one real
## number, multiple downstream consequences" pattern Phase 5's own pricing
## already established, now driving Phase 4's automatic outcome too.
##
## Once the same pair's fulfilled trades cross InstitutionFormation's real
## threshold, this is also what makes Phase 6 form an institution with no
## manual call -- genuinely downstream of Phase 4, not a separate trigger of
## its own. Emergence Phase 13: WHICH institution type gets attempted is no
## longer a hardcoded "cooperative" -- it reads the settlement's own real
## governance form (Governance.institution_type_for_new_formation), so a
## settlement with a real military-rule/merchant-oligarchy history attempts
## a militia/merchant_company instead. A settlement with no governance
## history yet still defaults to "cooperative," unchanged from before this
## phase existed.
func _step_settlement_trade(settlement_id: String, household_ids: Array[String], status: String) -> void:
	if household_ids.size() < 2:
		return
	var sorted_ids := household_ids.duplicate()
	sorted_ids.sort()
	var party_a: String = sorted_ids[0]
	var party_b: String = sorted_ids[1]
	if not _routine_trade_is_worth_running(party_a, party_b, status):
		return

	var contract := propose_contract(
		"trade", [party_a, party_b],
		["%s delivers goods" % party_a, "%s delivers goods" % party_b],
		"mutual goods exchange", -1.0
	)
	accept_contract(contract.id)
	activate_contract(contract.id)
	if status == SettlementState.DECLINING:
		breach_contract(contract.id)
	else:
		fulfill_contract(contract.id)

	var governance_form := Governance.form_for(_institution_type_counts_for(household_ids))
	var institution_type := Governance.institution_type_for_new_formation(governance_form)
	attempt_institution_formation(institution_type, party_a, party_b)


## Whether running the routine trade above would change anything -- the same
## change-guard every other emitter in this file already applies, finally
## applied to the highest-volume one.
##
## MEASURED before it existed: a three-household settlement appended four
## events (proposed/accepted/active/fulfilled-or-breached) and signed one
## fresh Contract EVERY assessment, forever. The MEMORY side was already
## bounded (see _record_contract_event), so villagers did not re-learn what
## they knew -- but the persisted event store and the persisted contract
## store are not memories, and they only ever grow. The same two households,
## the same terms, the same outcome, every thirty seconds, is not history.
##
## Three reasons to actually run it, and nothing else:
##
## 1. THE OUTCOME WOULD BE DIFFERENT from the last one on record between
##    exactly these two (or there is no record yet). A pair that has been
##    making good and starts breaching is the settlement's real news, and it
##    is the one contract transition villagers are given a memory of.
##    Read off the persisted event graph via the same _recorded_contract_
##    outcome the memory guard already uses, so it survives a load.
## 2. THE TRACK RECORD IS STILL BEING BUILT. InstitutionFormation.should_form
##    needs FORMATION_THRESHOLD fulfilled contracts between the pair before
##    an institution can exist at all, so repetition genuinely accumulates
##    into something until it crosses that line.
## 3. AN INSTITUTION IS ALIVE AND ITS WINDOW HAS AGED DOWN. should_dissolve
##    is deliberately windowed rather than all-time, so a living institution
##    genuinely requires ongoing coordination -- stop trading and it
##    dissolves. The rate is therefore NOT invented here: it is exactly
##    InstitutionFormation's own DISSOLUTION_THRESHOLD. We trade once the
##    recent count has fallen to the last value that is still safe, so the
##    window is restocked just before it can cross rather than exactly on
##    the edge, and no more often than that.
##
## BE HONEST ABOUT WHAT THIS DOES NOT DO: it does not make the stores
## bounded. Reason 3 is a real, ongoing requirement of a mechanism that
## exists on purpose -- an institution nobody has worked with recently is
## meant to be at risk -- so a settlement with a living institution really
## does keep signing contracts forever. What changes is the rate: from one
## per assessment to the minimum RECENT_WINDOW_SECONDS/DISSOLUTION_THRESHOLD
## actually require, and to nothing at all for a settlement with no living
## institution and no change of outcome to report. Measured over 40
## assessments of a real eight-household settlement with a living
## institution: 160 contract events and 40 contracts before, 52 and 13
## after. Measured on a settlement with no institution and an unchanging
## outcome: zero after the first, forever (both pinned by tests).
func _routine_trade_is_worth_running(party_a: String, party_b: String, status: String) -> bool:
	var outcome := "contract_breached" if status == SettlementState.DECLINING else "contract_fulfilled"
	var sorted_parties: Array[String] = [party_a, party_b]
	sorted_parties.sort()
	if _recorded_contract_outcome(sorted_parties) != outcome:
		return true
	# Only a FULFILMENT builds a track record -- InstitutionFormation counts
	# fulfilled contracts and nothing else, so a pair that is breaching is
	# not accumulating toward anything and repeating the breach adds nothing.
	if outcome == "contract_fulfilled" and InstitutionFormation.shared_contract_count(
		_contract_store, party_a, party_b
	) < InstitutionFormation.FORMATION_THRESHOLD:
		return true
	if _institution_store.active_institution_for([party_a, party_b]) == null:
		return false
	return InstitutionFormation.recent_shared_contract_count(
		_contract_store, party_a, party_b, _world_age_seconds
	) <= InstitutionFormation.DISSOLUTION_THRESHOLD + 1


## Gap-closing (docs/progress.md's Emergence Phase 6 entry): checks each of
## this settlement's ACTIVE institutions for real, RECENT coordination
## collapse (InstitutionFormation.should_dissolve, now windowed rather than
## all-time -- see that module's own doc comment for why the all-time count
## alone structurally could never fire once formed) and dissolves any that
## have genuinely gone quiet. Only meaningful for the two-party
## institutions this substrate builds (Phase 6's own documented scope); an
## institution with a different member count is skipped rather than
## guessed at. Deduped by institution id so a shared institution between
## two of this settlement's households is only checked once per step.
func _step_settlement_institution_health(household_ids: Array[String]) -> void:
	var seen := {}
	for household_id in household_ids:
		for institution in _institution_store.institutions_for(household_id):
			if institution.status != Institution.ACTIVE or seen.has(institution.id):
				continue
			seen[institution.id] = true
			if institution.members.size() != 2:
				continue
			var party_a: String = institution.members[0]
			var party_b: String = institution.members[1]
			if InstitutionFormation.should_dissolve(_contract_store, party_a, party_b, _world_age_seconds):
				dissolve_institution(institution.id)


## Emergence Phase 9 (docs/emergence/04-settlements-cities-infrastructure.md
## "City threshold"/"Specialization", `src/emergence/settlement_tier.gd`):
## re-derives this settlement's town/city tier and dominant specialization
## from real flows every step -- production (Phase 5), trade-fed
## institutions (Phase 4/6), and households (Phase 3/7), the exact same
## data _step_settlement_production/_step_settlement_trade above already
## produce. Event-sources only a real CHANGE, the same discipline
## _settlement_status already uses.
func _step_settlement_classification(settlement_id: String, household_ids: Array[String]) -> void:
	var institutions := _active_institution_count_for(household_ids)
	var production_counts := _production_counts_for_settlement(settlement_id)
	var tier := SettlementTier.tier_for(household_ids.size(), institutions, production_counts.size())

	# First classification of this settlement THIS SESSION is not its first
	# ever: what it was last event-sourced as is in the persisted event
	# history, so read it back before either guard decides anything (see
	# _settlement_tier).
	if not _settlement_tier.has(settlement_id):
		var recorded_tier := _recorded_settlement_tier(settlement_id)
		if recorded_tier != "":
			_settlement_tier[settlement_id] = recorded_tier
	if not _settlement_specialization.has(settlement_id):
		var recorded_specialization := _recorded_settlement_specialization(settlement_id)
		if recorded_specialization != "":
			_settlement_specialization[settlement_id] = recorded_specialization

	if _settlement_tier.get(settlement_id, "") != tier:
		_settlement_tier[settlement_id] = tier
		var tier_event := Event.new("settlement_became_%s" % tier, _world_age_seconds)
		tier_event.actors.append(settlement_id)
		tier_event.witnesses = _villager_witnesses_of(tier_event.actors)
		_event_store.append(tier_event)
		_memory_store.witness_event(tier_event, _world_age_seconds)

	var specialization := SettlementTier.specialization_for(production_counts)
	if specialization != "" and _settlement_specialization.get(settlement_id, "") != specialization:
		_settlement_specialization[settlement_id] = specialization
		var spec_event := Event.new("settlement_specialized", _world_age_seconds)
		spec_event.actors.append(settlement_id)
		spec_event.tags.append(specialization)
		spec_event.witnesses = _villager_witnesses_of(spec_event.actors)
		_event_store.append(spec_event)
		_memory_store.witness_event(spec_event, _world_age_seconds)


## How many currently-ACTIVE institutions belong to any of these
## households -- deduped by institution id, so an institution shared by two
## of the settlement's own households (the common case, given
## _step_settlement_trade's own two-party pairing) is counted once, not
## twice.
func _active_institution_count_for(household_ids: Array[String]) -> int:
	var seen := {}
	for household_id in household_ids:
		for institution in _institution_store.institutions_for(household_id):
			if institution.status == Institution.ACTIVE:
				seen[institution.id] = true
	return seen.size()


## institution_type -> how many DISTINCT institutions (active OR dissolved
## -- "historical precedent," Governance's own grounding) any of these
## households have ever belonged to. Deduped by institution id, the same
## reasoning _active_institution_count_for already uses, so an institution
## shared by two of the settlement's own households is counted once.
func _institution_type_counts_for(household_ids: Array[String]) -> Dictionary:
	var seen := {}
	var counts := {}
	for household_id in household_ids:
		for institution in _institution_store.institutions_for(household_id):
			if seen.has(institution.id):
				continue
			seen[institution.id] = true
			counts[institution.type] = counts.get(institution.type, 0) + 1
	return counts


## Emergence Phase 13 (docs/concept/governance.md, docs/emergence/01
## "Governance"/"Legitimacy"): a settlement's real, derived governance form
## and legitimacy -- for a console command to report without reaching into
## private reconstruction, the same reasoning household_count_for_settlement
## already established.
func governance_form_for_settlement(settlement_id: String) -> String:
	return Governance.form_for(_institution_type_counts_for(_households_in_settlement(settlement_id)))


func institution_type_counts_for_settlement(settlement_id: String) -> Dictionary:
	return _institution_type_counts_for(_households_in_settlement(settlement_id))


func legitimacy_for_settlement(settlement_id: String) -> String:
	var market := _market_store.market_for(settlement_id)
	var household_count := _households_in_settlement(settlement_id).size()
	# The same BOTH-markets stock step_settlements now assesses on (see
	# SettlementFood): Governance reads this status as legitimacy, so
	# leaving this one on the emergence market alone would report a
	# settlement illegitimate that step_settlements calls GROWING.
	var capacity := SettlementFood.carrying_capacity(
		market, SettlementFood.village_market_for(settlement_id, _loaded_villages)
	)
	return Governance.legitimacy_for(SettlementState.status_for(household_count, capacity))


## Emergence Phase 14 (docs/concept/regional_trade.md, docs/emergence/07's
## own "trade networks" element): every settlement's real production
## shortfall (Phase 12's own Quest) can be resupplied by the NEAREST
## other real settlement with genuine surplus of the missing item -- the
## region's most basic trade network, one real edge at a time, reusing
## Phase 12's shortage detection rather than a parallel "who needs what"
## system. Same throttled-accumulator shape SPREAD_INTERVAL/
## step_tree_spread already use.
const REGIONAL_TRADE_INTERVAL := 30.0
var _regional_trade_accumulator := 0.0

## Real in-flight regional-trade shipments (docs/concept/trade.md, the
## "supply really in transit, real risk" layer this builds on top of
## step_regional_trade's own dispatch decision above). Array of
## {"trip": CaravanTrip, "marker": CaravanMarker, "last_tile": Vector2i} --
## a plain Array, not keyed by chunk, since a caravan is never tied to a
## single chunk's load/unload lifecycle the way DecomposerMarker's
## _decomposer_markers is: it is real and progressing whether or not the
## player is anywhere near its route (see step_caravans).
var _active_caravans: Array = []

## Real ground worn by real caravan traffic -- the same PathScarring class
## World._path_scarring already uses for the player's own footsteps
## (world.gd's own doc comment on _step_path_scarring notes it is
## "PLAYER-ONLY for now"), now real for a second caller. A separate
## instance from world.gd's: nothing here reaches into a Node the way
## world.gd's private player-tracking one is scoped, so caravan wear is
## tracked on its own and not yet merged into the same rendered dirt-path
## pass -- a real, honestly-scoped follow-up, not a silent gap (see
## docs/concept/trade.md's Status section).
var _caravan_path_scarring := PathScarring.new()

var _item_catalog := ItemCatalog.new()


func step_regional_trade(delta_seconds: float) -> void:
	_regional_trade_accumulator += delta_seconds
	if _regional_trade_accumulator < REGIONAL_TRADE_INTERVAL:
		return
	_regional_trade_accumulator -= REGIONAL_TRADE_INTERVAL
	if _regional_trade_accumulator >= REGIONAL_TRADE_INTERVAL:
		_regional_trade_accumulator = fmod(_regional_trade_accumulator, REGIONAL_TRADE_INTERVAL)

	var settlement_ids := _known_settlement_ids()
	for settlement_id in settlement_ids:
		for quest in production_shortfall_quests_for_settlement(settlement_id):
			for entry in quest["missing"]:
				_attempt_regional_resupply(settlement_id, entry["item_id"], entry["need"], settlement_ids)


## Dispatches a real caravan carrying `need` units of `item_id` from the
## NEAREST real settlement (by real Euclidean distance between chunk
## coordinates) holding genuine surplus of it. The supplier's stock is gone
## the moment the caravan departs -- goods really in transit, real risk
## (docs/concept/trade.md) -- but the shortage settlement is credited only
## once a real CaravanTrip (see step_caravans) actually finishes walking
## there, or its goods scatter into the world if raided along the way. A
## no-op if no known settlement has real surplus (RegionalTrade.has_surplus's
## own safety margin), the same "an invalid/impossible transition does
## nothing" discipline every other coordinator here already respects.
func _attempt_regional_resupply(
	shortage_settlement_id: String, item_id: String, need: int, settlement_ids: Array
) -> void:
	var supplier_id := ""
	var supplier_distance := INF
	for candidate_id in settlement_ids:
		if candidate_id == shortage_settlement_id:
			continue
		var candidate_stock := _market_store.market_for(candidate_id).stock_of(item_id)
		if not RegionalTrade.has_surplus(candidate_stock, need):
			continue
		var distance := RegionalTrade.distance_between(shortage_settlement_id, candidate_id)
		if distance < supplier_distance:
			supplier_distance = distance
			supplier_id = candidate_id

	if supplier_id == "":
		return

	_market_store.market_for(supplier_id).add_stock(item_id, -need)

	var origin := _well_position_for_settlement(supplier_id)
	var destination := _well_position_for_settlement(shortage_settlement_id)
	# The route is only as safe as its most dangerous stretch -- the worse
	# of the two endpoints' own real RegionDifficulty tier, not just the
	# destination's (see docs/concept/trade.md's open-questions call).
	var tier := maxi(
		_difficulty_tier_at(RegionalTrade.chunk_coord_of(supplier_id)),
		_difficulty_tier_at(RegionalTrade.chunk_coord_of(shortage_settlement_id))
	)
	var raid_roll := CaravanRaid.roll_for(
		supplier_id, shortage_settlement_id, item_id, _world_age_seconds, "raid_check"
	)
	var raided := CaravanRaid.is_raided(tier, raid_roll)
	var raid_fraction := CaravanRaid.roll_for(
		supplier_id, shortage_settlement_id, item_id, _world_age_seconds, "raid_fraction"
	) if raided else 1.0

	var trip := CaravanTrip.new(
		supplier_id, shortage_settlement_id, item_id, need,
		origin, destination, _world_age_seconds, tier, raided, raid_fraction
	)
	var marker := CaravanMarker.new()
	marker.item_id = item_id
	marker.count = need
	marker.position = origin
	if _entities_parent != null:
		_entities_parent.add_child(marker)
	_active_caravans.append({"trip": trip, "marker": marker, "last_tile": _world_tile_for_pixel(origin)})

	var departed_event := Event.new("regional_trade_departed", _world_age_seconds)
	departed_event.actors.append(supplier_id)
	departed_event.actors.append(shortage_settlement_id)
	departed_event.tags.append(item_id)
	# BOTH ends of the route: the village that loaded the caravan and the
	# village waiting on it both watched this happen, which is what makes a
	# caravan the one thing two DIFFERENT settlements can gossip about.
	departed_event.witnesses = _villager_witnesses_of(departed_event.actors)
	_event_store.append(departed_event)
	_memory_store.witness_event(departed_event, _world_age_seconds)


## `settlement_id`'s real "well" landmark world position -- a caravan's real
## start/end point, the same lookup find_nearest_village already does to
## turn a discovered settlement chunk into a real teleport target.
func _well_position_for_settlement(settlement_id: String) -> Vector2:
	var chunk_coord := RegionalTrade.chunk_coord_of(settlement_id)
	var settlement := _settlement_generator.generate_settlement(
		chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TerrainRenderer.TILE_SIZE
	)
	return settlement.landmarks.well


## Advances every real in-flight caravan (see _active_caravans) to the
## current _world_age_seconds -- called after advance_world_age each slice
## (see World._step_ecology_fine), never throttled itself: CaravanTrip's own
## position_at is a pure closed-form function of elapsed time, so this is
## cheap regardless of how often it runs, and running it every slice is what
## gives PathScarring real tile-by-tile wear along the route instead of one
## coarse jump. Resolves each trip exactly once, either into a real market
## credit (arrival) or a real scattered drop (raid) -- never both.
func step_caravans() -> void:
	var still_active: Array = []
	for entry in _active_caravans:
		var trip: CaravanTrip = entry["trip"]
		var marker: CaravanMarker = entry["marker"]
		var position := trip.position_at(_world_age_seconds)
		if is_instance_valid(marker):
			marker.sync(position)

		var tile := trip.tile_at(_world_age_seconds, TerrainRenderer.TILE_SIZE)
		if tile != entry["last_tile"]:
			_caravan_path_scarring.step_on(tile)
			entry["last_tile"] = tile

		if trip.raid_triggered(_world_age_seconds):
			_resolve_caravan_raid(trip, position)
			if is_instance_valid(marker):
				marker.queue_free()
			continue
		if trip.is_arrived(_world_age_seconds):
			_resolve_caravan_arrival(trip)
			if is_instance_valid(marker):
				marker.queue_free()
			continue
		still_active.append(entry)
	_active_caravans = still_active


## Real delivery: the shortage settlement is credited only now, and the
## "shipped" event only becomes real now -- see _attempt_regional_resupply's
## own doc comment on why this moved out of the departure call.
func _resolve_caravan_arrival(trip: CaravanTrip) -> void:
	_market_store.market_for(trip.shortage_settlement_id).add_stock(trip.item_id, trip.count)

	var event := Event.new("regional_trade_shipped", _world_age_seconds)
	event.actors.append(trip.supplier_id)
	event.actors.append(trip.shortage_settlement_id)
	event.tags.append(trip.item_id)
	event.witnesses = _villager_witnesses_of(event.actors)
	_event_store.append(event)
	_memory_store.witness_event(event, _world_age_seconds)


## Real failure: the shortage settlement never sees this shipment. Its
## carried goods scatter into the world at the raid position via
## WorldItemBus -- the same real ground-drop path a felled tree or a
## smashed stone already uses, not a silent stock deletion.
func _resolve_caravan_raid(trip: CaravanTrip, raid_position: Vector2) -> void:
	if _item_catalog.has(trip.item_id):
		var stack := ItemStack.new(_item_catalog.make(trip.item_id), trip.count)
		WorldItemBus.item_dropped.emit(stack, raid_position)

	var event := Event.new("regional_trade_raided", _world_age_seconds)
	event.actors.append(trip.supplier_id)
	event.actors.append(trip.shortage_settlement_id)
	event.tags.append(trip.item_id)
	event.witnesses = _villager_witnesses_of(event.actors)
	_event_store.append(event)
	_memory_store.witness_event(event, _world_age_seconds)


## Real production HISTORY for `settlement_id` -- recipe_id -> how many
## times a production attempt for it has SUCCEEDED, read back out of the
## event graph itself (Phase 5's own production_succeeded events already
## tag which recipe), the same "the event graph already is the record"
## reasoning _known_settlement_ids established. Failed attempts do not
## count -- specialization is inferred from what a settlement actually
## PRODUCES, not what it merely attempted.
func _production_counts_for_settlement(settlement_id: String) -> Dictionary:
	var counts := {}
	for event in _event_store.events_for_entity(settlement_id):
		if event.type != "production_succeeded" or event.tags.is_empty():
			continue
		var recipe_id: String = event.tags[0]
		counts[recipe_id] = counts.get(recipe_id, 0) + 1
	return counts


## Public wrappers, same "for a console command to report without reaching
## into private reconstruction" reasoning household_count_for_settlement
## already established.
func active_institution_count_for_settlement(settlement_id: String) -> int:
	return _active_institution_count_for(_households_in_settlement(settlement_id))


func production_counts_for_settlement(settlement_id: String) -> Dictionary:
	return _production_counts_for_settlement(settlement_id)


## The settlement's LIVE VillageMarket, or null when its chunk is not
## loaded -- so a console command can explain a settlement off the same
## both-markets food source step_settlements classifies it with (see
## Why.explain_settlement's optional live-market argument).
func village_market_for_settlement(settlement_id: String):
	return SettlementFood.village_market_for(settlement_id, _loaded_villages)


## How many real households a settlement currently has, for a console
## command to report without reaching into the private membership
## reconstruction itself.
func household_count_for_settlement(settlement_id: String) -> int:
	return _households_in_settlement(settlement_id).size()


## Emergence Phase 8 (docs/concept/infrastructure.md, docs/emergence/04-
## settlements-cities-infrastructure.md "Infrastructure": "Repeated movement
## upgrades path -> trail -> road"): gives the ALREADY-LIVE `PathScarring`
## wear mechanism (World._step_path_scarring) a real, `/why`-inspectable
## entity, the same way `record_settlement_founded_if_new` did for
## settlement founding. No new store needed -- a path's whole lifecycle IS
## its own event history, read back the same way `_known_settlement_ids`
## reads settlements out of the event graph itself.
##
## Guarded on real persisted event history (was this path's MOST RECENT
## event already a formation?), not the caller's own in-memory transition
## flag (`World._scarred_tiles`, not persisted) -- so a fresh reload, which
## resets that in-memory flag but not the event store, cannot record a
## duplicate founding for a path already known to be worn.
func record_path_worn_if_new(tile: Vector2i) -> void:
	var path_id := EntityRef.for_kind("path", "%d_%d" % [tile.x, tile.y])
	var history := _event_store.events_for_entity(path_id)
	if not history.is_empty() and history.back().type == "path_worn":
		return
	var event := Event.new("path_worn", _world_age_seconds)
	event.actors.append(path_id)
	_event_store.append(event)
	_memory_store.witness_event(event, _world_age_seconds)


## The mirror of record_path_worn_if_new -- nature reclaiming a path
## (docs/emergence/04 "Infrastructure degrades") is exactly as recorded as
## one forming. NOT once-only the way founding is: a path can be worn,
## reclaimed, and worn again over a real session, and each cycle is real,
## distinct history. Only fires while the path's most recent event actually
## IS a formation -- reclaiming a path that was never worn (or is already
## reclaimed) would not be a real transition, so nothing is recorded.
func record_path_reclaimed(tile: Vector2i) -> void:
	var path_id := EntityRef.for_kind("path", "%d_%d" % [tile.x, tile.y])
	var history := _event_store.events_for_entity(path_id)
	if history.is_empty() or history.back().type != "path_worn":
		return
	var event := Event.new("path_reclaimed", _world_age_seconds)
	event.actors.append(path_id)
	_event_store.append(event)
	_memory_store.witness_event(event, _world_age_seconds)

	# Emergence Phase 10, source 2 (docs/emergence/05 "Ecological
	# transformation... overgrown ruins"): nature reclaiming a path IS this
	# dungeon source, verbatim.
	record_ruin_from_reclaimed_path(path_id, event.id)


## Every settlement that has ever recorded a founding -- read back out of the
## event graph itself (settlement_founded's own actor) rather than a second,
## separately-tracked list of "settlements that exist," so there is exactly
## one place that decides a settlement is real: EventStore.
func _known_settlement_ids() -> Array[String]:
	var ids: Array[String] = []
	for event in _event_store.events_of_type("settlement_founded"):
		if not event.actors.is_empty():
			ids.append(event.actors[0])
	return ids


## The households belonging to `settlement_id`, reconstructed from the
## settling events that settlement witnessed -- one more read against the
## event graph rather than a second membership index to keep in sync with
## it. household_for returns null for an npc with no household yet, which
## this simply skips.
##
## Both settling types count. `player_settled` is the player's own (see
## record_player_settled_if_new); it is a separate type because the player is
## not an NPC, but it means exactly the same thing HERE, which is why the two
## are read together rather than every caller learning the difference.
##
## Deduped by household id: one household is one member however many times it
## was witnessed settling, and without this a household that settled twice
## would inflate the settlement's own tier and institution thresholds.
const SETTLING_EVENT_TYPES := ["npc_settled", "player_settled"]


func _households_in_settlement(settlement_id: String) -> Array[String]:
	var household_ids: Array[String] = []
	var seen := {}
	for event in _event_store.events_for_entity(settlement_id):
		if not SETTLING_EVENT_TYPES.has(event.type) or event.actors.is_empty():
			continue
		var household := _household_store.household_for(event.actors[0])
		if household == null or seen.has(household.id):
			continue
		seen[household.id] = true
		household_ids.append(household.id)
	return household_ids


## Every villager of `settlement_id` -- the exact sibling of
## _households_in_settlement above, one link earlier in the same chain: an
## npc_settled event already names the villager as its own actor, so this
## reads the event graph rather than adding a second membership index to
## keep in sync with it.
##
## Works for an UNLOADED settlement, which is the normal case rather than
## the exception: step_settlements assesses every settlement that has ever
## been founded, and at any moment almost none of them have live NpcMarker
## nodes. Reading `_loaded_villages` instead would mean a settlement's own
## history stops being witnessed by anyone the moment the player walks away
## from it -- exactly the settlements whose news is worth hearing later.
func _villagers_in_settlement(settlement_id: String) -> Array[String]:
	var npc_ids: Array[String] = []
	for event in _event_store.events_for_entity(settlement_id):
		if event.type != "npc_settled" or event.actors.is_empty():
			continue
		npc_ids.append(event.actors[0])
	return npc_ids


## The settlement `party_id` lives in, or "" if it has none. Households are
## resolved through their founder (Household.for_founder keys a household by
## its founder's own ref and members[0] IS that founder -- the same
## reconstruction _occupation_of_household already relies on), and an npc's
## own npc_settled event names its settlement as the witness, so no
## npc -> settlement index has to be built or persisted for this either.
##
## "" for the local player's household (PlayerIdentity never settled
## anywhere) and for any party with no founding on record -- not an error,
## just nobody to tell.
func _settlement_of_party(party_id: String) -> String:
	var npc_id := party_id
	if EntityRef.kind_of(party_id) == "household":
		var household := _household_store.get_household(party_id)
		if household == null or household.members.is_empty():
			return ""
		npc_id = household.members[0]
	if EntityRef.kind_of(npc_id) != "npc":
		return ""
	for event in _event_store.events_for_entity(npc_id):
		if event.type == "npc_settled" and not event.witnesses.is_empty():
			return event.witnesses[0]
	return ""


## The villagers who were THERE for an event about `entity_ids` -- what to
## assign to Event.witnesses just before appending, the missing half of the
## record_settlement_founded_if_new idiom every other emitter in this file
## had been skipping. EventStore/MemoryStore already consume it: a witnessed
## event becomes a real WITNESSED MemoryRecord for each of them (see
## MemoryRecord.from_event), which is what step_npc_encounters then has
## something real to trade at a shared landmark.
##
## Takes the event's own `actors` rather than a settlement id so ONE helper
## covers all three shapes the emitters actually name: a settlement directly
## (production, status, tier, specialization), a household (institution
## formation/dissolution), and two settlements at once (a caravan's supplier
## and its destination -- the one case where two different villages witness
## the same thing).
##
## Deduped, because a two-party institution between two households of the
## SAME settlement would otherwise name every villager twice and index each
## of them twice in EventStore's own reverse entity index. An entity with no
## settlement behind it contributes nobody rather than blocking the event --
## the same fail-open shape every other reconstruction here uses; an event
## nobody saw is still an event that happened.
func _villager_witnesses_of(entity_ids: Array[String]) -> Array[String]:
	var witnesses: Array[String] = []
	var seen := {}
	for entity_id in entity_ids:
		var settlement_id := entity_id
		if EntityRef.kind_of(entity_id) != "settlement":
			settlement_id = _settlement_of_party(entity_id)
		if settlement_id == "":
			continue
		for npc_id in _villagers_in_settlement(settlement_id):
			if seen.has(npc_id):
				continue
			seen[npc_id] = true
			witnesses.append(npc_id)
	return witnesses


## Persists the live event store, following the same store_var convention
## PlayerSave/ChunkSerializer already established for world-scoped state (see
## EventStorePersistence).
func save_event_store(path: String = EventStorePersistence.SAVE_PATH) -> void:
	EventStorePersistence.new().save(_event_store, path)


## Replaces the live store with whatever is persisted at `path` (an empty
## store if there is nothing there yet) -- the Load Game side of the same
## convention.
func load_event_store(path: String = EventStorePersistence.SAVE_PATH) -> void:
	_event_store = EventStorePersistence.new().load_store(path)


## Discards the live store's in-memory state, without touching disk.
func reset_event_store() -> void:
	_event_store = EventStore.new()


## The New Game side: clears both the persisted file and the live store, so
## a freshly spawned character loads into a world with no prior history --
## the same "New Game means new" pillar docs/concept/persistence.md already
## established for the player save and the per-chunk persistence dirs.
func wipe_event_store(path: String = EventStorePersistence.SAVE_PATH) -> void:
	EventStorePersistence.new().wipe(path)
	reset_event_store()


## Records that a settlement was founded, and that every one of its villagers
## settled there -- but only the FIRST time a given settlement is seen. Called
## by VillageRenderer.spawn_village (duck-typed) every time a chunk carrying a
## settlement loads, which is NOT the same as "every time it is founded": a
## chunk reload happens whenever a player walks back near it, so the event
## store's own state (has this settlement ever recorded anything?) is the
## guard, not an in-memory flag -- the same robustness reasoning as every
## other "spawn once, persist across reload" system in this file.
func record_settlement_founded_if_new(chunk_coord: Vector2i, npcs: Array) -> void:
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	if not _event_store.events_for_entity(settlement_id).is_empty():
		return

	var npc_ids: Array[String] = []
	for npc in npcs:
		npc_ids.append(EntityRef.for_npc(npc.seed_value))

	var founded := Event.new("settlement_founded", _world_age_seconds)
	founded.actors = [settlement_id]
	founded.witnesses = npc_ids
	founded.importance = 0.2
	_event_store.append(founded)
	_memory_store.witness_event(founded, _world_age_seconds)

	for i in npcs.size():
		var settled := Event.new("npc_settled", _world_age_seconds)
		settled.actors = [npc_ids[i]]
		settled.witnesses = [settlement_id]
		_event_store.append(settled)
		_memory_store.witness_event(settled, _world_age_seconds)

		# A single-member household of its own, owning the house it lives in
		# (see docs/emergence/01/03 "Households"/"Property"). Single-member
		# because no partnership/reproduction system exists yet to justify
		# who belongs to whose household (docs/roadmap.md's Emergence
		# Phase 3 note) -- keyed the same way VillageRenderer._stamp_house
		# derives that villager's own house seed, so this needs no new
		# per-house id scheme: house index `i` and npc index `i` are the
		# same villager by construction (SettlementGenerator.generate_
		# settlement builds npcs and house_positions in the same loop).
		var household := _household_store.form_household(npc_ids[i])
		var house_id := EntityRef.for_kind(
			"house", "%d_%d_%d" % [chunk_coord.x, chunk_coord.y, i]
		)
		_household_store.grant_property(household.id, house_id)


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
	# Belt and braces only: the canopy season is the CLOCK's job now (see
	# sync_tree_season, called from set_world_age_seconds/advance_world_age/
	# jump_to_season and World._client_process), and the signature guard makes
	# this a no-op whenever one of those already dressed this moment. It is not
	# load-bearing -- a peer that never runs this tick at all still has correct
	# trees -- but fruiting is about to redraw these canopies anyway, so it may
	# as well redraw them in the right season.
	#
	# Passes player_pixel through so a season change (rare, but touches every
	# loaded tree when it happens) respects the same FRUITING_DETAIL_RADIUS
	# gate as the per-tree loop below -- otherwise a tree this loop has
	# deliberately skipped for being out of range gets re-dressed right back
	# in with its own stale cached ripe_fruit_count() the moment the season
	# turns, and the "frozen forever" bug reappears through this door instead.
	sync_tree_season(player_pixel)
	# ONE answer to "which canopy is this tree wearing", read from the same
	# place the rest of the wood was just dressed from -- and read ONCE, not
	# per tree. This used to be the calendar season plus a SeasonTransition
	# call inside the loop below, which is a second schedule: harmless while
	# the canopy still turned on the ground's curve, wrong the moment it got
	# its own (see TreePhenology), because then the trees inside the fruiting
	# radius wear a different year from the wood around them -- blossom on the
	# first day of spring for the handful next to the player, bare branches
	# everywhere else.
	var canopy := _tree_renderer.canopy_state()
	var canopy_season: String = canopy["season"]
	var canopy_turning_into: String = canopy["turning_into"]
	var canopy_turn_progress: float = canopy["turn_progress"]
	for trees in _loaded_trees.values():
		for tree in trees:
			if not tree.has_method("set_ripe_fruit"):
				continue
			# Distance pre-filter, BEFORE any per-tree work: genome lookup,
			# species/pollination lookups, FruitingModel.state_at, and above
			# all tree.set_ripe_fruit's canopy texture redraw are all real
			# per-tree cost, and this loop used to pay it for EVERY loaded
			# tree in the whole streaming radius -- potentially thousands --
			# roughly once a second, forever, including trees the player has
			# never been anywhere near (reported: a real perf hit from a
			# handful of loaded forests).
			#
			# FRUITING_DETAIL_RADIUS already covers the full visible
			# viewport (1280x720 screen / Player.CAMERA_ZOOM's 4x zoom =
			# 320x180 world px, half-diagonal ~183.6px, comfortably inside
			# 280px), so nothing actually on screen is skipped -- and
			# because FruitingModel.state_at is a PURE function of elapsed
			# world time rather than a running simulation, a skipped tree is
			# not frozen: it simply shows the correct catch-up ripeness the
			# next time it comes back into range (see
			# chunk_ecology_catchup.gd for the same "catch up divergent
			# world state when it comes back into scope" pattern elsewhere
			# in this codebase).
			#
			# This check used to only gate whether a tree's fruit dropped as
			# real ground items further below, which is what let every
			# loaded tree's canopy redraw through here regardless of
			# distance in the first place.
			if player_pixel.distance_to(tree.position) > FRUITING_DETAIL_RADIUS:
				continue
			var genome := _forage_scheduler.genome_for(tree.position)
			# NAMED species (Walnut/Cherry/Apple -- see TreeSpecies), not the
			# raw nut/fruit spectrum: both the canopy's ripe crop and the
			# fallen count scale by this species' own yield/ripening
			# character on top of the genome's raw traits.
			var species_id := TreeSpecies.species_for_bias(genome.species_bias)
			# Bee visits nudge an insect-pollinated tree's yield (see
			# FruitingModel.pollination_factor / docs/concept/flora.md) --
			# composed INTO the species' own yield multiplier, not instead of
			# it, so a well-visited apple can still reach exactly the ceiling
			# it always could. Wind-pollinated species (pine/acorn/hazelnut/
			# walnut) get a flat 1.0 regardless of tree.pollination_visits_
			# in_cycle -- a real pine sets its cone crop with no insect's help.
			var pollination_factor := 1.0
			if TreeSpecies.needs_pollinators_for(species_id):
				pollination_factor = FruitingModel.pollination_factor(
					tree.pollination_visits_in_cycle(FruitingModel.BEARING_CYCLE_SECONDS, now)
				)
			var yield_multiplier := TreeSpecies.yield_multiplier_for(species_id) * pollination_factor
			var ripening_multiplier := TreeSpecies.ripening_multiplier_for(species_id)
			var state: Dictionary = _fruiting_model.state_at(
				genome, now, warmth, yield_multiplier, ripening_multiplier
			)
			# _snow_depth, not a value read once at the top of this function:
			# this call site is the only one of the two per-tree redraw
			# loops (see sync_tree_season's own) that runs on every single
			# fruiting tick regardless of the season/turn/snow signature --
			# leaving snow out of this call would silently reset a nearby
			# tree's snow back to zero on the very next tick.
			tree.set_ripe_fruit(
				int(state.get("ripe", 0)),
				canopy_season,
				canopy_turning_into,
				canopy_turn_progress,
				_snow_depth
			)

			# Every tree reaching here already passed the FRUITING_DETAIL_RADIUS
			# gate above, so it drops its fallen fruit as real ground items too
			# -- capped below, so the ground under a tree stand never turns
			# into a hundred clickable nodes.
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


## Sets the world clock, and keeps every OTHER clock-tracking mark that reads
## against it in step -- the shared plumbing under both randomize_world_age
## (a brand new world) and load_world_clock (a resumed one).
##
## Without this, a mark like _last_fruiting_time/_snow_world_age would still
## read 0 the instant the real clock jumped to a random or loaded value, and
## the NEXT step_fruiting/step_snow call would see the whole jump as elapsed
## time -- the same "two clocks that have to agree" trap jump_to_season's own
## doc comment describes, just at world-creation/load time instead of a
## /season skip.
func set_world_age_seconds(value: float) -> void:
	_world_age_seconds = value
	_last_fruiting_time = value
	_snow_world_age = value
	# The canopies are one of those readers, and this is the earliest moment
	# they can possibly be right: both randomize_world_age (New Game) and
	# load_world_clock (Load Game) come through here BEFORE the first chunk
	# load, so a world that opens in winter opens with bare trees instead of
	# summer ones that correct themselves a tick later (see sync_tree_season).
	sync_tree_season()


## Rolls a brand new world's starting point in the year, once (see
## NEW_GAME_WORLD_AGE_RANGE_SECONDS) -- called only at New Game/Host Game
## creation (see World._wipe_persisted_world), never on Load Game (see
## load_world_clock, which restores the persisted value instead of rerolling
## it -- a load must resume exactly where the save left off, not time-travel
## on every session).
func randomize_world_age() -> void:
	set_world_age_seconds(randf() * NEW_GAME_WORLD_AGE_RANGE_SECONDS)


## Persists the world clock, following the same store_var convention
## PlayerSave/EventStorePersistence already established (see
## WorldClockPersistence).
func save_world_clock(path: String = WorldClockPersistence.SAVE_PATH) -> void:
	WorldClockPersistence.new().save(_world_age_seconds, path)


## Restores the world clock from disk -- the Load Game side of the same
## convention. A missing file (e.g. a --solo dev launch with no save yet)
## leaves the clock exactly where it already was, matching PlayerSave/
## EventStorePersistence's own "nothing to load" behaviour rather than
## silently resetting it.
func load_world_clock(path: String = WorldClockPersistence.SAVE_PATH) -> void:
	var persistence := WorldClockPersistence.new()
	if not persistence.has_save(path):
		return
	set_world_age_seconds(persistence.load_seconds(path))


func wipe_world_clock(path: String = WorldClockPersistence.SAVE_PATH) -> void:
	WorldClockPersistence.new().wipe(path)


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
	# /season winter should show winter trees NOW, not once the next fruiting
	# tick comes round -- and on a peer that owns no simulation, never (see
	# sync_tree_season). This skips the clock without going through
	# set_world_age_seconds, so it needs the push of its own.
	sync_tree_season()
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


## Registers the GPU relief-shading overlay layer (see HillshadeShader,
## TerrainRenderer.build_hillshade_overlay_tile_set,
## docs/concept/terrain_relief.md's "Hillshading" section) -- same optional,
## fail-open shape as set_water_layer above: a caller that never registers
## this simply never sees terrain shading. Every loaded cell gets a real
## slope/aspect data tile (see _paint_hillshade_overlay) and the layer
## shares HillshadeShader's one material, so a single set_sun_position call
## re-shades every painted tile at once rather than needing a repaint.
func set_hillshade_layer(hillshade_layer: TileMapLayer) -> void:
	_hillshade_layer = hillshade_layer
	hillshade_layer.tile_set = _terrain_renderer.build_hillshade_overlay_tile_set()
	# Must match the base terrain layer's scale exactly, same reasoning as
	# set_water_layer's own identical line.
	hillshade_layer.scale = Vector2.ONE * TerrainRenderer.LAYER_SCALE
	hillshade_layer.material = _hillshade_shader.shared_material()
	for chunk_coord in _loaded_chunks:
		_paint_hillshade_overlay(chunk_coord, _loaded_chunks[chunk_coord])


## In-river boulder tiles currently painted, keyed by global tile -- fed
## to the flow shader as world positions so it can bend the current lines
## and cut a round dry eyot around each rock PER FRAGMENT. Baking the
## deflection into per-tile across values was tried first and produced
## exactly the square artefacts it was meant to prevent: a tile is far too
## coarse a brush for a bump the size of a rock.
var _river_flow_boulder_tiles: Dictionary = {}

## The float across map the flow shader samples bilinearly -- one texel
## per world tile over the loaded span, addressed toroidally (tile mod
## size), so streaming never re-anchors it. This is what replaced the
## atlas across bins after three rounds of quantization artefacts.
var _flow_across_image: Image
var _flow_across_texture: ImageTexture

## How many boulders the shader accepts -- mirrors the uniform array size.
const RIVER_FLOW_BOULDER_SLOTS := 24


func river_flow_boulder_positions() -> PackedVector2Array:
	# Prune first: a chunk that unloaded takes its boulders with it, and a
	# stale far-away rock must not hold one of the limited uniform slots.
	var stale: Array = []
	for tile in _river_flow_boulder_tiles:
		if not _loaded_chunks.has(_chunk_coord_for_tile(tile)):
			stale.append(tile)
	for tile in stale:
		_river_flow_boulder_tiles.erase(tile)
	var positions := PackedVector2Array()
	for tile in _river_flow_boulder_tiles:
		if positions.size() >= RIVER_FLOW_BOULDER_SLOTS:
			break
		positions.append(Vector2(
			float(tile.x) * TerrainRenderer.TILE_SIZE + TerrainRenderer.TILE_SIZE * 0.5,
			float(tile.y) * TerrainRenderer.TILE_SIZE + TerrainRenderer.TILE_SIZE * 0.5
		))
	return positions


## Re-evaluates one tile against the flow-boulder predicate and pushes the
## set to the shader -- called from build/destroy so a dropped boulder
## bends the water the moment it lands, and stops the moment it is
## demolished, without waiting for a chunk repaint.
func _sync_flow_boulder(tile: Vector2i) -> void:
	if flow_boulder_at_global(tile.x, tile.y):
		_river_flow_boulder_tiles[tile] = true
	else:
		_river_flow_boulder_tiles.erase(tile)
	sync_river_flow_boulders()


## One texel of the flow map, written toroidally -- see _flow_across_image.
## Carries the WHOLE per-tile reconstruction frame as REAL floats
## (FORMAT_RGBAF, no encode range): R the signed across-fraction, GB the
## course's downstream unit vector (same sin/-cos convention the atlas
## sprite bakes), A the real solved current speed in m/s -- so the shader
## interpolates direction and speed bilinearly exactly like across, and no
## per-tile quantity is left to draw the tile grid.
func _write_flow_across_texel(
	global: Vector2i, across_fraction: float, bearing_deg: float, speed_mps: float
) -> void:
	if _flow_across_image == null:
		var side := RiverFlowShader.FLOW_MAP_TILES
		_flow_across_image = Image.create(side, side, false, Image.FORMAT_RGBAF)
	var side := RiverFlowShader.FLOW_MAP_TILES
	var radians := deg_to_rad(bearing_deg)
	_flow_across_image.set_pixel(
		posmod(global.x, side), posmod(global.y, side),
		Color(across_fraction, sin(radians), -cos(radians), speed_mps)
	)


## Pushes the filled map into the shared flow material after a paint pass.
func _push_flow_across_map() -> void:
	if _flow_across_image == null:
		return
	if _flow_across_texture == null:
		_flow_across_texture = ImageTexture.create_from_image(_flow_across_image)
	else:
		_flow_across_texture.update(_flow_across_image)
	_river_flow_shader.shared_material().set_shader_parameter(
		"flow_across_map", _flow_across_texture
	)


## Pushes the current boulder set into the shared flow material -- called
## after chunk paints and after building/destroying pieces so a dropped
## boulder bends the water the moment it lands.
func sync_river_flow_boulders() -> void:
	var positions := river_flow_boulder_positions()
	var material := _river_flow_shader.shared_material()
	material.set_shader_parameter("boulder_count", positions.size())
	material.set_shader_parameter("boulders", positions)


## Feeds the river strokes the same sunlight that drives the day/night
## tint, each frame -- the night CanvasModulate multiplies every canvas
## pixel, so the flow shader lifts its strokes toward the moonlit ceiling
## as the sky darkens (see RiverFlowShader.night_lift_for_sunlight).
## Safe with no layer registered: the shared material exists regardless.
func set_river_flow_night_lift(sunlight: float) -> void:
	_river_flow_shader.shared_material().set_shader_parameter(
		"night_lift", RiverFlowShader.night_lift_for_sunlight(sunlight)
	)


## The wading player as a live flow obstacle ("a player walking through the
## stream should cause realistic current displacement") -- world.gd feeds
## the player's pixel position and in-water state every frame, same shape
## as set_river_flow_night_lift above; the shader stretches the push
## downstream into a trailing wake (see RiverFlowShader.wader_across_push).
func set_river_flow_waders(positions: PackedVector2Array) -> void:
	var material := _river_flow_shader.shared_material()
	var capped := positions.slice(0, RiverFlowShader.WADER_SLOTS)
	var padded := capped.duplicate()
	padded.resize(RiverFlowShader.WADER_SLOTS)
	material.set_shader_parameter("wader_count", capped.size())
	material.set_shader_parameter("waders", padded)


## Filters wader candidates (pixel positions: the player plus any creature
## markers) down to the ones actually standing in river water, capped at
## the shader's wader slots. The river lookup walks real polylines, so
## answers are memoised per tile -- rivers never move -- with a cap so a
## migrating herd cannot hold the whole world in memory.
const RIVER_WADER_MEMO_CAP := 50_000
var _wader_river_memo := {}


func river_wader_positions(candidates: Array) -> PackedVector2Array:
	var kept := PackedVector2Array()
	var tile_px := float(TerrainRenderer.TILE_SIZE)
	for candidate in candidates:
		if kept.size() >= RiverFlowShader.WADER_SLOTS:
			break
		var pos: Vector2 = candidate
		var tile := Vector2i(floori(pos.x / tile_px), floori(pos.y / tile_px))
		var in_river = _wader_river_memo.get(tile)
		if in_river == null:
			# Any water, not only rivers: a fish or a swimmer in a lake or
			# the sea rings the still water (the shader's wake stays
			# symmetric there) -- third playtest: "pond fish ripples need
			# to be reimplemented with the river contour system".
			in_river = (
				is_river_at_global(tile.x, tile.y)
				or is_lake_at_global(tile.x, tile.y)
				or biome_at_global(tile.x, tile.y) == "ocean"
			)
			if _wader_river_memo.size() > RIVER_WADER_MEMO_CAP:
				_wader_river_memo.clear()
			_wader_river_memo[tile] = in_river
		if in_river:
			kept.append(pos)
	return kept


## Registers the GPU river-flow overlay layer (see RiverFlowShader,
## TerrainRenderer.build_river_flow_tile_set, docs/concept/rivers.md) --
## same optional, fail-open shape as set_hillshade_layer above, but the
## layer itself is SPARSE (see _paint_river_flow_overlay): only real river
## cells ever get a tile, everywhere else stays empty/transparent.
func set_river_flow_layer(river_flow_layer: TileMapLayer) -> void:
	_river_flow_layer = river_flow_layer
	river_flow_layer.tile_set = _terrain_renderer.build_river_flow_tile_set()
	river_flow_layer.scale = Vector2.ONE * TerrainRenderer.LAYER_SCALE
	river_flow_layer.material = _river_flow_shader.shared_material()
	for chunk_coord in _loaded_chunks:
		_paint_river_flow_overlay(chunk_coord, _loaded_chunks[chunk_coord])
	sync_river_flow_boulders()


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
	# The room's own cells AND the wall ring around it -- see
	# RoofShape.revealed_cells for why the walls have to come off too now
	# that roofs cover them.
	_terrain_renderer.paint_roofs(
		_roof_layer, chunk, chunk_coord * CHUNK_SIZE,
		RoofShape.revealed_cells(room_cells, chunk.modifications)
	)


## How many tiles out from the player a cave entrance still triggers a
## reveal -- standing right at the mouth or immediately beside it, not
## a proximity radius wide enough to reveal chambers the player can't
## even see yet.
const CAVE_ENTRY_TRIGGER_RADIUS := 1

## Reveals the real diggable-rock chamber under whichever cave entrance (if
## any) the player is currently standing at/beside, and despawns whichever
## chamber was PREVIOUSLY revealed the moment the player is no longer near
## it -- the same reveal-on-entry shape as _update_roof_visibility, one
## layer down (see docs/concept/geology.md "Reveal-on-entry, reused
## recursively"). Only the topsoil/regolith layer has a Strata instance
## wired here today (_topsoil_strata); deeper layers are not yet reachable
## (see geology.md's Status).
func _update_geology_reveal(player_global_tile: Vector2i) -> void:
	var entrance_tile = _nearby_cave_entrance(player_global_tile)

	if entrance_tile == _revealed_cave_entrance_tile:
		return  # nothing changed -- still at the same entrance (or still away from one)

	for node in _revealed_cave_nodes:
		if is_instance_valid(node):
			node.free()
	_revealed_cave_nodes = []
	_revealed_cave_entrance_tile = null

	if entrance_tile == null:
		return

	var entrance_chunk_coord := _chunk_coord_for_tile(entrance_tile)
	var strata: Strata = _topsoil_strata.get(entrance_chunk_coord)
	if strata == null:
		return  # the entrance's own chunk isn't loaded (yet) -- nothing to reveal

	var local_cell := _local_coord(entrance_tile.x, entrance_tile.y)
	_revealed_cave_nodes = _geology_renderer.reveal_chamber(
		_entities_parent, strata, local_cell, entrance_chunk_coord * CHUNK_SIZE, TerrainRenderer.TILE_SIZE
	)
	_revealed_cave_entrance_tile = entrance_tile


## The global tile of a real cave entrance within CAVE_ENTRY_TRIGGER_RADIUS
## of the player, or null if none -- scans a small fixed neighborhood
## rather than the whole loaded area, cheap enough to run every frame the
## same way _update_roof_visibility's own per-frame room lookup already is.
func _nearby_cave_entrance(player_global_tile: Vector2i):
	for dy in range(-CAVE_ENTRY_TRIGGER_RADIUS, CAVE_ENTRY_TRIGGER_RADIUS + 1):
		for dx in range(-CAVE_ENTRY_TRIGGER_RADIUS, CAVE_ENTRY_TRIGGER_RADIUS + 1):
			var candidate := player_global_tile + Vector2i(dx, dy)
			var biome_name: String = generator.biome_at_global(candidate.x, candidate.y)
			if _cave_entrance_placement.has_entrance_at(candidate.x, candidate.y, biome_name):
				return candidate
	return null


## Marks every ocean OR river cell of a loaded chunk on the water overlay
## layer with the shore-distance tile matching its own cardinal water
## neighbors (empty == open water) -- the shader reads that tile as
## per-pixel proximity data to blend and animate the shore continuously, not
## as art. A river cell's own chunk.biome entry is untouched by this (see
## docs/concept/rivers.md's "Rendering" section -- a river never becomes an
## eighth BiomeClassifier.KNOWN_BIOMES value), so river-ness is re-asked of
## the generator here rather than read from the chunk's own biome array.
func _paint_water_overlay(chunk_coord: Vector2i, chunk: Chunk) -> void:
	if _water_layer == null:
		return
	var origin := chunk_coord * CHUNK_SIZE
	for y in chunk.height:
		for x in chunk.width:
			var global := origin + Vector2i(x, y)
			# Ocean ONLY. Rivers used to be painted here too, but this
			# translucent per-tile overlay is exactly what put square water
			# tiles under the flow layer's smooth bank curve -- the flow
			# overlay is now the river's entire water surface, clipped at
			# the real bank line, with the ground showing past it.
			# NOTHING is painted here any more when the river flow overlay is
			# wired: rivers, lakes AND the sea ride that one overlay as one
			# water surface (docs/concept/hydrology.md "Water kinds"; first
			# playtest: this overlay's square tiles read as "a very
			# different art style" beside the river's contour lines). This
			# layer stays as the fallback for a scene that never registers a
			# flow layer, exactly as it drew before.
			if _river_flow_layer != null:
				_water_layer.erase_cell(origin + Vector2i(x, y))
				continue
			var is_water: bool = chunk.biome[y * chunk.width + x] == "ocean"
			if not is_water:
				continue
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


## Real slope/aspect shading for every cell in the chunk, not gated by
## biome -- a GENERAL mechanism (docs/concept/terrain_relief.md: "not
## mountain-specific code"), reads most dramatically where slope is high
## but applies everywhere, unlike the ocean-only water overlay above.
##
## Takes ONE elevation gradient per tile and derives both readings from it,
## rather than calling slope_at_global and aspect_at_global separately: those
## are two readings of the same gradient (see TerrainRelief.gradient_at), so
## the pair sampled elevation eight times per tile where four do -- 32,768
## byte reads per 32x32 chunk against 8,192 for generating the chunk itself,
## i.e. hillshading alone was ~4x the whole chunk generator and exactly half
## of that was redundant. Invisible to most of this file's tests, which never
## call set_hillshade_layer and so return at the guard below; scenes/world.gd
## does set it, which is why the instrumented in-game cost of a full-radius
## update() is so much worse than a headless one.
##
## Every painted tile is unchanged, pinned by
## test_hillshade_tiles_are_exactly_the_slope_and_aspect_atlas_coords.
func _paint_hillshade_overlay(chunk_coord: Vector2i, chunk: Chunk) -> void:
	if _hillshade_layer == null:
		return
	var relief := generator.terrain_relief()
	var origin := chunk_coord * CHUNK_SIZE
	for y in chunk.height:
		for x in chunk.width:
			var global := origin + Vector2i(x, y)
			var gradient := gradient_at_global(global.x, global.y)
			var slope := relief.slope_degrees_from_gradient(gradient.x, gradient.y)
			var aspect := relief.aspect_degrees_from_gradient(gradient.x, gradient.y)
			_hillshade_layer.set_cell(
				global, 0, _terrain_renderer.atlas_coords_for_hillshade(slope, aspect)
			)


## Marks every RIVER cell of a loaded chunk (see EarthChunkGenerator.
## is_river_at_global, docs/concept/rivers.md) with its real downhill flow
## direction (TerrainRelief.aspect_degrees_from_gradient -- "the direction
## water would actually flow"), and erases anything already painted at a
## now-non-river cell. Deliberately SPARSE, unlike _paint_hillshade_overlay
## above (which paints every cell): only water should ever show a flowing
## current. Rivers previously looked exactly like still ocean water
## (reported: "rivers should flow").
## A dry tile whose lake-shoreline across (HydrologyField.lake_across) is
## below this still gets painted, so the waterline's feather has a cell to
## draw in wherever the shore is gentle; a steep shore jumps well past it
## and the waterline then falls inside the wet cell anyway.
const LAKE_PAINT_ACROSS := 1.6


func _paint_river_flow_overlay(chunk_coord: Vector2i, chunk: Chunk) -> void:
	if _river_flow_layer == null:
		return
	var origin := chunk_coord * CHUNK_SIZE
	for y in chunk.height:
		for x in chunk.width:
			var global := origin + Vector2i(x, y)
			# ONE WATER SURFACE (docs/concept/hydrology.md): rivers, lakes
			# and the sea all ride this overlay. A river tile (including a
			# mouth reaching into sea cells, so the current visibly runs
			# into the sea) takes the flowing branch below. Otherwise a lake
			# tile, a sea tile, or a dry tile inside either shoreline's
			# paint band writes the elevation-contour across -- the spill
			# for a lake, sea level for the sea -- with ZERO current, so the
			# shader draws the same smooth waterline, ink and feather it
			# gives a river bank, and only ripples. First playtest: "ponds
			# have a very different art style", "unify river and pond water".
			var probe := generator.hydrology_at_global(global.x, global.y)
			var still_across: float = probe["lake_across"]
			var still_water: bool = (
				probe["kind"] == "lake" or probe.get("sea", false) or still_across < LAKE_PAINT_ACROSS
			)
			if probe["kind"] != "river" and still_water:
				# A river mouth's current runs on into the still water and
				# fades (HydrologyField.mouth_plume): the texel carries the
				# mouth's bearing and a fading speed, so the flow lines
				# continue out of the mouth and settle into ripples.
				var plume_speed: float = HydrologyField.PLUME_SPEED_M_S * probe["plume_factor"]
				_write_flow_across_texel(global, still_across, probe["plume_bearing_deg"], plume_speed)
				_river_flow_boulder_tiles.erase(global)
				_river_flow_layer.set_cell(
					global, 0,
					_terrain_renderer.atlas_coords_for_river_flow(
						probe["plume_bearing_deg"], RiverFlowShader.is_fast_flow(plume_speed)
					)
				)
				continue
			# The generator's own nearest_river_at: the curated answer
			# wherever a curated river reaches, else (when enabled) the
			# nearest baked hydrology channel in the same shape -- see
			# docs/concept/hydrology.md's relationship to rivers.md. Each
			# answer carries its own half-width (the catalog's uniform one,
			# or the baked channel's discharge-derived one), and the across
			# texel is normalized by THAT, so a confluence reads wider.
			var nearest := generator.nearest_river_at(global.x, global.y)
			var half_width: float = nearest.get("half_width_tiles", RiverCatalog.RIVER_HALF_WIDTH_TILES)
			var apron := half_width + RiverCatalog.RIVER_BANK_APRON_TILES
			# Painted out past the bank line (the apron): the shader clips
			# the water at the REAL bank curve, |across| == 1, and that
			# curve runs through cells whose centres sit beyond the
			# half-width -- a fragment can only be clipped smooth if its
			# cell was painted at all. Gated on the euclidean distance, not
			# |signed across|: past a course's endpoints the perpendicular
			# component goes small while the distance does not, and cells
			# off the end of a river must not be painted as water.
			if nearest.distance_tiles > apron:
				_river_flow_layer.erase_cell(global)
				# Still write the texel: a dry cell one tile past the apron
				# is a bilinear NEIGHBOUR of a wet one, and an unwritten
				# texel there would bleed garbage into the waterline.
				var apron_hydraulics := generator.river_hydraulics_at_global(
					global.x, global.y
				)
				_write_flow_across_texel(
					global,
					nearest.signed_across_tiles / half_width,
					nearest.course_bearing_deg,
					apron_hydraulics.velocity_m_s
				)
				continue

			# Everything the look needs comes from REAL simulation state:
			# the flow direction is the course polyline's own downstream
			# tangent (water flows along its CHANNEL, not down the local
			# DEM hillside), the signed cross-channel offset drives the
			# continuous per-fragment cross-section and the smooth
			# waterline, and the fast flag comes from the real solved
			# current.
			var hydraulics := generator.river_hydraulics_at_global(global.x, global.y)
			var across_fraction: float = nearest.signed_across_tiles / half_width
			_write_flow_across_texel(
				global, across_fraction,
				nearest.course_bearing_deg, hydraulics.velocity_m_s
			)
			if flow_boulder_at_global(global.x, global.y):
				_river_flow_boulder_tiles[global] = true
			else:
				_river_flow_boulder_tiles.erase(global)
			_river_flow_layer.set_cell(
				global, 0,
				_terrain_renderer.atlas_coords_for_river_flow(
					nearest.course_bearing_deg,
					RiverFlowShader.is_fast_flow(hydraulics.velocity_m_s)
				)
			)
	# Every paint re-syncs the shader's boulder set -- found live: only
	# layer setup and build/destroy synced, so a fresh session's NATURAL
	# river boulders were collected here but never reached the uniform,
	# and the water bent around nothing.
	sync_river_flow_boulders()
	_push_flow_across_map()


## Cardinal directions from (global_x, global_y) that hold a non-ocean,
## currently-loaded neighbor. A neighbor in an unloaded chunk (streaming
## edge) is treated as unknown, not land -- avoids false shore-marking right
## at the load radius boundary.
func _land_directions_at(global_x: int, global_y: int) -> Array:
	var land_directions := []
	for direction in _DIRECTIONS:
		var neighbor_x := global_x + direction.x
		var neighbor_y := global_y + direction.y
		if _is_land_at(neighbor_x, neighbor_y):
			land_directions.append(direction)
	return land_directions


## True if (global_x, global_y) is real land for water-overlay shore-blend
## purposes -- neither ocean nor a river (see docs/concept/rivers.md). A
## river cell's OWN chunk.biome entry reads as ordinary land (forest,
## grassland, ...), so this re-asks the generator directly rather than
## trusting biome_at_global alone -- otherwise a river tile's own
## neighboring river tiles would each register as "land", and a several-
## tiles-wide river would never show an open-water interior, only shore.
func _is_land_at(global_x: int, global_y: int) -> bool:
	var neighbor_biome := biome_at_global(global_x, global_y)
	if neighbor_biome == "" or neighbor_biome == "ocean":
		return false
	if generator.is_lake_at_global(global_x, global_y):
		return false
	return not generator.is_river_at_global(global_x, global_y)


## Distance in tiles to the nearest land (neither ocean nor river),
## currently-loaded cell, found by checking each expanding Chebyshev ring
## (radius 1, then 2, ...) in turn -- diagonals included, since flat ring
## tiles (see TerrainRenderer.atlas_coords_for_water_overlay) don't need
## cardinal precision the way the direct-touching ring-0 tile does. Only
## called when _land_directions_at already found nothing at radius 0.
## Returns `max_ring` (== "open water") if no land is found within that range.
func _ring_distance_at(global_x: int, global_y: int, max_ring: int) -> int:
	for radius in range(1, max_ring):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue  # only this ring's perimeter, smaller radii already checked
				if _is_land_at(global_x + dx, global_y + dy):
					return radius
	return max_ring


## Sets how strongly raindrop ripples show on the water overlay (see
## WaterShader.set_rain_intensity), driven from the live weather model.
## Purely a continuous shader-uniform update now -- no tile repainting, since
## rain moved entirely off the baked tile system onto the GPU shader.
## The warmth where the player is standing -- climate and season together.
func current_warmth() -> float:
	return _warmth_at_pixel(_disturbance_center_tile * TerrainRenderer.TILE_SIZE)


## The overlay snow is painted onto (see SnowBombShader). Registered like the
## water overlay, and optional: a caller that never sets one simply gets no
## snow. Its cells now carry only PRESENCE (see set_snow_layer) -- the actual
## coverage/variant/level art is read per pixel by the shader itself, off
## world position and the two uniforms this class pushes (snow_depth, the
## trail mask), not painted per tile any more.
var _snow_layer: TileMapLayer = null
var _snow_shader := SnowBombShader.new()
var _snow_material: ShaderMaterial = null
## Footprints, and how much snow is lying (see SnowTrail / Snowfall).
var _snow_trail := SnowTrail.new()
var _snow_depth := 0.0
## The last tile tread_snow_at was called with -- the trail mask window (see
## _refresh_snow_trail_mask) is centred here, since SnowTrail's own
## dictionary carries no notion of "where the player is" by itself.
var _snow_trail_center_tile := Vector2i.ZERO

## How wide, in TILES, the trail mask window pushed to the shader is. Matches
## SHADER_CODE's own trail_world_size uniform DEFAULT (1024.0 world units)
## exactly, divided by TerrainRenderer.TILE_SIZE (16) -- not load-bearing
## (set_trail_mask always pushes the real world_size alongside the texture,
## so a mismatch could not silently misalign anything), just keeping the two
## numbers honestly in sync rather than picking an unrelated one.
const SNOW_TRAIL_WINDOW_TILES := 64


func set_snow_layer(snow_layer: TileMapLayer) -> void:
	_snow_layer = snow_layer
	snow_layer.tile_set = SnowBombShader.build_presence_tile_set()
	# Must match the terrain layer's scale exactly, or the cover drifts out of
	# alignment with the ground it lies on.
	snow_layer.scale = Vector2.ONE * TerrainRenderer.LAYER_SCALE
	_snow_material = _snow_shader.shared_material()
	snow_layer.material = _snow_material
	_snow_shader.set_snow_depth(_snow_depth)
	if _snow_depth > 0.0:
		_paint_all_loaded_snow_presence()


## How much snow is lying, 0 bare to 1 covered (see Snowfall). Pushed to the
## shader as one float uniform -- see step_snow's own doc comment for why
## this no longer means touching the TileMapLayer per DEPTH change. Presence
## itself still needs syncing on the rarer bare<->lying transition -- see
## _sync_snow_presence.
func set_snow_depth(depth: float) -> void:
	var previous := _snow_depth
	_snow_depth = clampf(depth, 0.0, 1.0)
	# Forwards to the canopy the same way set_wind_strength forwards to
	# _tree_renderer -- so a tree spawned right after a deliberate depth set
	# (this call; /weather or similar) is already dressed for it. The other,
	# more frequent live path (step_snow, called every frame and NOT routed
	# through this setter -- see its own body) is carried the rest of the
	# way by sync_tree_season instead, which is what actually reaches an
	# ALREADY-standing tree (see its own doc comment).
	_tree_renderer.set_snow_coverage(_snow_depth)
	if _snow_layer != null:
		_snow_shader.set_snow_depth(_snow_depth)
		_sync_snow_presence(previous)


## How much snow is lying, 0 bare to 1 covered.
func loaded_chunk_count() -> int:
	return _loaded_chunks.size()


func snow_depth() -> float:
	return _snow_depth


## Marks a tile as walked on, packing the snow down (see SnowTrail). The
## actual GPU-facing mask texture is rebuilt once per step_snow call, not
## here -- see _refresh_snow_trail_mask.
func tread_snow_at(pixel_position: Vector2) -> void:
	if _snow_depth <= 0.0:
		return
	_snow_trail_center_tile = _world_tile_for_pixel(pixel_position)
	_snow_trail.step_on(_snow_trail_center_tile)


## The world clock as of the last snow step, so snow can advance on the same
## clock everything else does.
var _snow_world_age := 0.0


## Accumulates or melts the lying snow, fills tracks back in while it is
## snowing, and pushes both to the shader.
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
##
## Used to end with a diff-aware sweep over every loaded tile, throttled to
## once every 2 real seconds so an unconditional per-tile scan would not cost
## the ~40-50ms/pass it was measured at (see git history). SnowBombShader
## deletes that PER-TILE cost outright by moving coverage/level/variant into
## the fragment shader, read per PIXEL off world position and the one
## `snow_depth` uniform below -- so the DEPTH push itself is now continuous
## and unthrottled, the same shape `set_rain`'s own `rain_intensity` push
## already is a few lines down. Presence still needs syncing on the rarer
## bare<->lying transition (see _sync_snow_presence), and the TRAIL mask is
## a real GPU texture upload rather than a uniform float, so it keeps its
## own throttle too -- see _refresh_snow_trail_mask.
func step_snow(snowing: bool, warmth: float) -> void:
	var elapsed: float = maxf(_world_age_seconds - _snow_world_age, 0.0)
	_snow_world_age = _world_age_seconds
	var previous_depth := _snow_depth
	_snow_depth = Snowfall.accumulate(_snow_depth, snowing, warmth, elapsed)
	_snow_trail.advance(elapsed, snowing)

	# Pushing shader uniforms is optional -- a headless server has no snow
	# layer but still has weather, so the depth/trail state above has to be
	# kept either way.
	if _snow_layer == null:
		return
	_snow_shader.set_snow_depth(_snow_depth)
	_sync_snow_presence(previous_depth)
	_refresh_snow_trail_mask()


## Presence cells are what make the SnowFx TileMapLayer have anything to
## draw at all -- see build_presence_tile_set's own doc comment: an erased
## cell submits no quad and never runs fragment(), so a layer with NOTHING
## painted costs exactly what it did before this shader existed, which
## matters every bit as much as the per-pixel cost does. Painting every
## land tile unconditionally, at every chunk load, regardless of season,
## was the actual cause of a real, measured slowdown even in full summer
## with snow_depth at a flat 0.0 -- the old per-tile mechanism this
## replaces painted NOTHING while it wasn't snowing (a genuinely empty
## layer), where presence-always-painted instead has the entire visible
## ground submitting real quads to a custom-shader material, always, whether
## or not there is any snow to show.
##
## Fixed at a coarser grain than the deleted per-tile sweep: presence is
## painted for every currently loaded chunk on the RARE 0 -> nonzero
## transition (a real snowfall beginning) and the whole layer is cleared on
## the equally rare nonzero -> 0 one (a full thaw) -- not diffed per tile,
## not re-touched for any depth change strictly between those two, so this
## costs nothing on the vast majority of step_snow calls, which report no
## transition at all.
func _sync_snow_presence(previous_depth: float) -> void:
	if previous_depth <= 0.0 and _snow_depth > 0.0:
		_paint_all_loaded_snow_presence()
	elif previous_depth > 0.0 and _snow_depth <= 0.0:
		_snow_layer.clear()


func _paint_all_loaded_snow_presence() -> void:
	for chunk_coord in _loaded_chunks:
		_paint_snow_presence(chunk_coord, _loaded_chunks[chunk_coord])


## The tile the currently-pushed trail mask texture is centred on, and when
## it was last rebuilt -- see _refresh_snow_trail_mask.
var _snow_trail_mask_center_tile := Vector2i.ZERO
var _snow_trail_refreshed_age := -INF

## How often the trail mask is allowed to rebuild, at minimum -- also rebuilt
## immediately whenever the player crosses into a new tile, so the window
## never visibly lags behind them.
##
## ImageTexture.create_from_image is a real GPU upload, discarding whatever
## texture was there before -- unlike set_snow_depth's plain uniform push,
## this is NOT free to do unconditionally every frame. Measured live: doing
## it every step_snow call (i.e. every frame, same as the depth push) was
## the actual cause of a 60fps -> single-digit-fps collapse the instant snow
## started actually lying (fragment()'s own early-out means nothing pays for
## the shader at all before then, which is why it only showed up once snow
## was on screen). SnowTrail.build_mask_texture's own cost is bounded by
## tracked footprints and stays cheap; the upload itself is what needed
## bounding, the same lesson SNOW_SWEEP_INTERVAL_SECONDS already encoded for
## the deleted per-tile sweep.
const SNOW_TRAIL_REFRESH_INTERVAL_SECONDS := 0.25


## Rebuilds and pushes the GPU-facing trail mask, centred on wherever
## tread_snow_at was last called (the player's own tile) -- but only when the
## window actually needs to move or enough time has passed to catch newly
## packed/refilled tread, not unconditionally every call (see this
## constant's own doc comment).
func _refresh_snow_trail_mask() -> void:
	var due := _world_age_seconds - _snow_trail_refreshed_age >= SNOW_TRAIL_REFRESH_INTERVAL_SECONDS
	if not due and _snow_trail_center_tile == _snow_trail_mask_center_tile:
		return
	var window := SNOW_TRAIL_WINDOW_TILES
	var half := window / 2
	var origin := Vector2(_snow_trail_center_tile - Vector2i(half, half)) * TerrainRenderer.TILE_SIZE
	_snow_shader.set_trail_mask(
		_snow_trail.build_mask_texture(_snow_trail_center_tile, window),
		origin, float(window) * TerrainRenderer.TILE_SIZE
	)
	_snow_trail_mask_center_tile = _snow_trail_center_tile
	_snow_trail_refreshed_age = _world_age_seconds


## Marks every non-ocean cell of a loaded chunk with the single presence tile
## SnowBombShader.build_presence_tile_set provides -- see set_snow_layer for
## why a painted cell means nothing but "snow may render here" now. Painted
## ONCE, at chunk load (mirrors _paint_water_overlay's own shape), and never
## revisited: unlike the deleted per-tile band mechanism this replaces,
## coverage no longer depends on which cells are painted, only on the
## snow_depth uniform, so there is nothing here for a later depth change to
## invalidate.
func _paint_snow_presence(chunk_coord: Vector2i, chunk: Chunk) -> void:
	if _snow_layer == null:
		return
	var origin: Vector2i = chunk_coord * CHUNK_SIZE
	for y in chunk.height:
		for x in chunk.width:
			var global := origin + Vector2i(x, y)
			# Water does not take snow -- it freezes or it does not, which is
			# a different thing and not this one. A river's own biome is
			# untouched land (see docs/concept/rivers.md's Rendering
			# section), so it must be excluded separately from ocean --
			# reported live: "snow falls on rivers".
			if chunk.biome[y * chunk.width + x] == "ocean":
				continue
			# Rivers AND lakes (docs/concept/hydrology.md) -- both are
			# overlay flags on land biome, both read from the one predicate.
			if chunk.blocks_ground_cover(y * chunk.width + x):
				continue
			_snow_layer.set_cell(global, 0, SnowBombShader.PRESENCE_ATLAS_COORD)


func set_rain(raining: bool) -> void:
	if _water_material != null:
		_water_material.set_shader_parameter("rain_intensity", 1.0 if raining else 0.0)


## Sets how energetic the live wind is (see WeatherModel.wind_strength_for --
## pass WeatherModel.wind_strength_for(the current weather)) across every
## wind-reactive visual this manager owns:
## - the water's wind-driven surface shimmer (see WaterShader.set_wind_strength
##   -- paces the surface TEXTURE only; ripple rings come from rain and
##   movement, never from wind);
## - tree canopy sway (WindSway, via _tree_renderer's own shared material);
## - grass/scrub/lichen tuft AND flower bloom sway (WindSway.tuft_material --
##   blooms share this exact tuft material, see the render call sites in this
##   file; there is no separate flower-sway system to also wire up);
## - illustrated tall-grass's own ambient wind term (walker-push parting is
##   deliberately left unscaled -- see IllustratedGrassPatch.set_wind_strength).
func set_wind_strength(strength: float) -> void:
	_water_shader.set_wind_strength(strength)
	_wind_sway.set_wind_strength(strength)
	_tree_renderer.set_wind_strength(strength)
	_illustrated_grass.set_wind_strength(strength)


## The season's tint on living green (see SeasonalFoliage, forwarded from
## World._client_process), pushed onto every green thing this manager owns.
## Same "live value pushed into a shared uniform every tick" shape as
## set_wind_strength/set_sun_position above. The terrain layer's own
## GroundTint material is pushed by World, which is what owns that layer.
func set_season_tint(tint: Color) -> void:
	_season_tint = tint
	_illustrated_grass.set_season_tint(tint)


## Pushes the real, live sun position (see solar_position.gd's
## elevation_degrees/azimuth_degrees -- the same values already driving
## day/night lighting in world.gd) into the shared hillshade materials --
## both the ground overlay's and individual entities' (mountain ore veins),
## the same "live value pushed into a shared uniform every tick" shape
## set_wind_strength/set_rain above already use for weather.
func set_sun_position(elevation_deg: float, azimuth_deg: float) -> void:
	_hillshade_shader.set_sun_position(elevation_deg, azimuth_deg)
	_entity_hillshade_shader.set_sun_position(elevation_deg, azimuth_deg)


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


## The Weather glass item's real prerequisite (docs/concept/wayfinding.md's
## Weather glass) -- mirrors current_weather's own day/region-seed
## derivation exactly, but reads one period ahead via
## WeatherForecast.upcoming_weather instead of calling
## _weather_model.weather_at directly, so a forecast can never disagree with
## what current_weather will itself report once that period arrives.
func upcoming_weather(player_pixel: Vector2) -> String:
	var chunk_coord := _chunk_coord_for_tile(_world_tile_for_pixel(player_pixel))
	var day := int(_world_age_seconds / WEATHER_PERIOD_SECONDS)
	return WeatherForecast.upcoming_weather(_weather_model, day, hash("%d_%d" % [chunk_coord.x, chunk_coord.y]))


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
	# Time passing is the ONLY thing a canopy depends on, so the canopies move
	# with the clock rather than with any simulation step (see
	# sync_tree_season). The quantised signature guard keeps this a string
	# compare on all but a handful of calls per in-game year.
	sync_tree_season()


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
	# Nothing takes root on a floor. TreeRooting answers the BIOME question
	# only; occupancy by a real building piece is a separate refusal, and the
	# other two directions of the same rule live in stamp_structure_at_global
	# and TreeRenderer.spawn_trees.
	if BuildingPiece.has_piece(chunk.modifications.get(local, "")):
		return false
	# A river's own biome is untouched land (see docs/concept/rivers.md's
	# Rendering section), so TreeRooting.can_root_in alone can't see it --
	# the same "trees standing in a lake" bug class this function's own
	# doc comment already names, now recurring for rivers specifically.
	if is_river_at_global(tile.x, tile.y):
		return false
	# A lake bed is the original "trees standing in a lake" case, now with
	# real lakes (docs/concept/hydrology.md) -- same overlay flag shape.
	if chunk.blocks_ground_cover(local.y * chunk.width + local.x):
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
		var elapsed := delta_seconds
		# Maggots eat the rot they hatched in (see FlyColony.decay_hastened_by,
		# docs/concept/flies.md): a windfall with an active colony on it goes
		# over sooner than the same windfall with none. decay_hastened_by
		# answers in a FRACTION of the item's whole shelf life, so it is
		# converted to seconds against this item's own spoil_seconds before
		# being added on top of ordinary aging.
		var colony: FlyColony = _fly_colonies.get(item)
		if colony != null:
			elapsed += colony.decay_hastened_by(delta_seconds) * item.spoil_seconds
		item.advance(elapsed)


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
	var growth_modifier := _season_cycle.growth_modifier(_world_age_seconds)
	for sim in _grass_sims.values():
		sim.advance(elapsed, growth_modifier)
		sim.shed_seed(elapsed)

	_graze_by_herbivores()
	for chunk_coord in _grass_sims.keys():
		_sync_grass_sprites(chunk_coord)


## The `accelerate_growth` spell atom's real hook (see docs/concept/
## spell_runtime.md): advances every wild crop patch in the chunk containing
## `global_tile` by `extra_seconds` -- the exact same real
## WildCropPatch.advance() step_wild_crops already calls on its own
## throttled per-chunk-batch clock, just triggered instantly instead of
## waited for. Chunk-wide, not single-plant: WildCropPatch has no per-cell
## targeting granularity, so this is an honestly coarser scope than "the one
## plant you're facing," not a fake finer one. Returns whether the chunk
## even had wild crops to accelerate (false for an unloaded/crop-less one --
## "even an affordable spell still has to land").
func accelerate_wild_crop_growth(global_tile: Vector2i, extra_seconds: float) -> bool:
	var chunk_coord := _chunk_coord_for_tile(global_tile)
	if not _wild_crop_sims.has(chunk_coord):
		return false
	var season_growth := _season_cycle.growth_modifier(_world_age_seconds)
	var sims: Dictionary = _wild_crop_sims[chunk_coord]
	var markers: Dictionary = _wild_crop_markers[chunk_coord]
	for crop_id in sims:
		var sim: WildCropPatch = sims[crop_id]
		sim.advance(extra_seconds, season_growth)
		_wild_crop_renderer.sync_markers(
			_entities_parent, sim, crop_id, chunk_coord * CHUNK_SIZE, TerrainRenderer.TILE_SIZE,
			markers[crop_id], _season_tint
		)
	return true


## Wild carrot/potato growth + spread (see docs/concept/wild_crops.md) --
## same throttled-accumulator shape as step_tall_grass, batched for the same
## reason: advancing every loaded patch 60 times a second would be pure
## waste for growth this slow.
func step_wild_crops(delta_seconds: float) -> void:
	_wild_crop_refresh_accumulator += delta_seconds
	if _wild_crop_refresh_accumulator < GRASS_REFRESH_INTERVAL:
		return
	var elapsed := _wild_crop_refresh_accumulator
	_wild_crop_refresh_accumulator = 0.0

	# A root crop does not stop in winter, it goes dormant -- growth_modifier's
	# own floor is 0.2, not 0 (see docs/concept/wild_crops.md "The season").
	# Computed once per batched tick rather than per patch: it is a pure
	# function of the world clock, which does not move inside this loop.
	var growth_modifier := _season_cycle.growth_modifier(_world_age_seconds)
	for chunk_coord in _wild_crop_sims.keys():
		var sims: Dictionary = _wild_crop_sims[chunk_coord]
		var markers: Dictionary = _wild_crop_markers[chunk_coord]
		for crop_id in sims:
			var sim: WildCropPatch = sims[crop_id]
			sim.advance(elapsed, growth_modifier)
			_wild_crop_renderer.sync_markers(
				_entities_parent, sim, crop_id, chunk_coord * CHUNK_SIZE, TerrainRenderer.TILE_SIZE,
				markers[crop_id], _season_tint
			)


## One shared shader-uniform write per frame makes nearby blades yield to a
## walker; individual cards intentionally have no process callbacks.
func set_grass_walker_position(world_position: Vector2) -> void:
	_illustrated_grass.set_walker_position(world_position)


## How grown the tall-grass patch at `pixel_position` is (0..1, 1 mature), or
## a negative number if there is no patch there. Grass has no per-tuft
## Node2D of its own (see _sync_grass_sprites), so it cannot join
## HoverTargetFinder's group like every other hoverable entity -- World reads
## this directly instead to special-case the mouse-hover tooltip over grass.
func tall_grass_growth_at(pixel_position: Vector2) -> float:
	var tile := _world_tile_for_pixel(pixel_position)
	var chunk_coord := _chunk_coord_for_tile(tile)
	var sim: TallGrass = _grass_sims.get(chunk_coord)
	if sim == null:
		return -1.0
	var local := _local_coord(tile.x, tile.y)
	if not sim.has_grass(local):
		return -1.0
	return sim.get_growth(local)


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
##
## Land health (docs/concept/world.md "Land health: overharvesting leaves a
## lasting mark, not just a slower respawn"): the exact same real growth just
## eaten ALSO leaves this region's real standing vegetation -- previously a
## grazer's bite only ever removed the cosmetic per-tuft TallGrass patch,
## never touched EcosystemSimulation's aggregate density/land-health at all
## (mirrors NpcEconomy._gather's identical farmer-side wiring, which passes
## its own real gathered amount to the same record_vegetation_harvest).
## `growth` is always 1.0 here (only mature patches are ever offered by
## grass_near/grazed here), read live off the sim rather than hardcoded, so
## this stays correct if TallGrass ever grows a partial-bite mechanic.
func graze_grass_at(pixel_position: Vector2) -> bool:
	var tile := _world_tile_for_pixel(pixel_position)
	var chunk_coord := _chunk_coord_for_tile(tile)
	var sim: TallGrass = _grass_sims.get(chunk_coord)
	if sim == null:
		return false
	var cell := tile - chunk_coord * CHUNK_SIZE
	var growth := sim.get_growth(cell)
	if growth < 1.0:
		return false
	if not sim.graze(cell):
		return false
	_ecosystem.record_vegetation_harvest(chunk_coord, growth)
	# Refresh THIS chunk immediately rather than waiting for the next
	# throttled step, the same reasoning as take_worm_at/take_seed_at: the
	# player just watched the animal eat it, so it has to vanish on that
	# frame rather than seconds later.
	_sync_grass_sprites(chunk_coord)
	return true


## Every grass-shed seed lying on the ground within `radius_tiles` of
## `pixel_position` (see TallGrass.shed_seed / ground_seed_cells), in the
## same {position} shape as worms_near/seeds_near/fruit_near/grass_near so
## GroundForageBehavior and GrazerForaging can treat it identically to any
## other forageable entity.
##
## Scans only the 3x3 chunk neighbourhood, the same bound and reason as
## flowers_near/seeds_near/worms_near/grass_near: this runs per forager per
## sniff.
func grass_seeds_near(pixel_position: Vector2, radius_tiles: int = 8) -> Array:
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
			for cell in sim.ground_seed_cells():
				var tile: Vector2i = origin + cell
				if maxi(absi(tile.x - center.x), absi(tile.y - center.y)) > radius_tiles:
					continue
				out.append({
					"position": Vector2(
						float(tile.x) + 0.5, float(tile.y) + 0.5
					) * float(TerrainRenderer.TILE_SIZE),
				})
	return out


## Takes the grass seed lying at `pixel_position`, if there is one (see
## grass_seeds_near). Returns whether anything was actually there -- the
## mutation counterpart of grass_seeds_near, mirroring take_worm_at (no
## species to report, unlike take_seed_at -- see TallGrass.take_ground_seed).
func take_grass_seed_at(pixel_position: Vector2) -> bool:
	var tile := _world_tile_for_pixel(pixel_position)
	var chunk_coord := _chunk_coord_for_tile(tile)
	var sim: TallGrass = _grass_sims.get(chunk_coord)
	if sim == null:
		return false
	return sim.take_ground_seed(tile - chunk_coord * CHUNK_SIZE)


## Plants a NEW, immature tall-grass patch at `pixel_position` (see
## TallGrass.plant), if the chunk is loaded and the ground there can
## actually take it (grassland, under the chunk's own MAX_PATCHES cap). The
## sink a bird's or mouse's carried grass seed calls once it is done being
## carried, mirroring plant_flower_at/try_plant_seed_at -- this is what lets
## a carried seed found a genuinely NEW field _step_spread's contiguous
## local growth could never reach on its own (see
## docs/concept/long_grass.md's "Reproduction" section).
func plant_grass_at(pixel_position: Vector2) -> bool:
	var tile := _world_tile_for_pixel(pixel_position)
	var chunk_coord := _chunk_coord_for_tile(tile)
	var sim: TallGrass = _grass_sims.get(chunk_coord)
	if sim == null:
		return false
	if not sim.plant(tile - chunk_coord * CHUNK_SIZE):
		return false
	_sync_grass_sprites(chunk_coord)
	return true


## Any herbivore-role creature standing on a mature grass patch's tile eats
## it -- the "tall grass is eaten by herbivores" loop, driven by where the
## creatures' own AI already took them rather than a separate seek behavior.
##
## Land health (docs/concept/world.md "Land health: overharvesting leaves a
## lasting mark, not just a slower respawn"): this ambient standing-on-grass
## sweep is genuine herbivore pressure exactly like GrazerForaging's own
## deliberate bite (see graze_grass_at's identical wiring/doc comment) -- a
## horse or sheep that happens to be standing on a mature tuft eats real
## vegetation whether or not it walked there on purpose. Previously this only
## ever touched the cosmetic per-tuft TallGrass sim, never
## EcosystemSimulation's aggregate density/land-health.
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
			var growth := sim.get_growth(local)
			if growth >= 1.0 and sim.graze(local):
				_ecosystem.record_vegetation_harvest(chunk_coord, growth)
			_step_seed_dispersal(creature)
			_step_grass_seed_caching(creature)
			_step_squirrel_nut_caching(creature)


## Rodent scatter-hoarding (see SeedCaching / docs/concept/long_grass.md's
## "Reproduction" section): a mouse that passes near a fallen grass seed
## picks it up, carries it a short GROUND distance while it goes on foraging,
## and caches (plants) it nearby but not adjacent. Gated to mice specifically
## (species == "mouse"), not the whole "Forager" diet label -- this is a real
## mouse behaviour (scatter-hoarding), not a generic dietary fact that should
## attach to anything sharing mice's diet table entry.
##
## Deliberately NOT the bird endozoochory model (swallow, digest over real
## flight time, deposit far away): a real mouse does not fly and does not
## digest a whole seed in transit -- it carries one in its cheek pouch on
## foot and caches it close to where it found it, which is why
## SeedCaching's carry range is a fraction of SeedEndozoochory's.
func _step_grass_seed_caching(creature) -> void:
	if creature.info == null or creature.info.species != "mouse":
		return
	if not creature.carried_grass_seed:
		var nearby := grass_seeds_near(creature.position, int(SeedCaching.PICKUP_RADIUS_TILES))
		if nearby.is_empty():
			return
		# The nearest seed actually within reach, not just anything in the
		# wider query radius -- a mouse grabs what it is standing next to.
		var nearest_position: Vector2 = nearby[0]["position"]
		var nearest_distance: float = creature.position.distance_to(nearest_position)
		for candidate in nearby:
			var candidate_position: Vector2 = candidate["position"]
			var distance: float = creature.position.distance_to(candidate_position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_position = candidate_position
		if nearest_distance > SeedCaching.PICKUP_RADIUS_TILES * TerrainRenderer.TILE_SIZE:
			return
		if not take_grass_seed_at(nearest_position):
			return
		creature.carried_grass_seed = true
		creature.carried_grass_seed_origin = creature.position
		# A real heading to lean into while caching (see CreatureMarker.
		# _wander_step) -- ordinary wander alone (CreatureWander, the SAME
		# home-tethered containment shape AmbientFlyerMovement uses for
		# birds) is measured at a hard ~2.6-tile ceiling regardless of
		# wander_seed, short of this module's own 1-6 tile range without it
		# (see docs/progress.md).
		creature.carried_grass_seed_direction = SeedCaching.carry_direction(creature.wander_seed)
		return

	# Carrying: cache once it has actually travelled its own (short) carry
	# distance, so the seed lands somewhere new rather than right back where
	# it was picked up.
	var carried_tiles: float = (
		creature.position.distance_to(creature.carried_grass_seed_origin) / float(TerrainRenderer.TILE_SIZE)
	)
	if carried_tiles < SeedCaching.carry_distance_tiles(creature.wander_seed):
		return
	plant_grass_at(creature.position)
	creature.carried_grass_seed = false
	creature.carried_grass_seed_direction = Vector2.ZERO


## Squirrel scatter-hoarding of fallen tree NUTS (see SquirrelNutCaching /
## docs/concept/flora.md's disperser-vs-predator tension): a squirrel that
## passes near a fallen NUT (TreeSpecies.is_nut -- pine/acorn/hazelnut/
## walnut, not fleshy fruit) takes it and carries it a short GROUND distance
## while it goes on foraging, exactly the same on-foot shape
## _step_grass_seed_caching uses for a mouse. Once it has carried the nut its
## own carry distance, the outcome resolves: mostly it just eats the nut
## outright (SquirrelNutCaching.nut_is_consumed, the real majority outcome
## for a scatter-hoarder), but sometimes it caches it instead, sprouting a
## new sapling via the SAME tree-seed sink robin's own fruit dispersal
## already uses (try_plant_seed_at, gated to forest/rainforest). Gated to
## squirrels specifically (species == "squirrel"), not the whole "Forager"
## diet label -- this is a real squirrel behaviour, not a generic dietary
## fact. Fleshy fruit (cherry/apple) is deliberately left untouched here --
## a squirrel finding one just eats it like any other fruit-eating forager
## via GrazerForaging's ungated FOOD_FRUIT path; only a genuine hard-shelled
## nut is a candidate for the crack-or-cache tension this mechanic models.
func _step_squirrel_nut_caching(creature) -> void:
	if creature.info == null or creature.info.species != "squirrel":
		return
	if creature.carried_nut_species == "":
		var nearby := fruit_near(creature.position, int(SquirrelNutCaching.PICKUP_RADIUS_TILES))
		nearby = nearby.filter(func(f): return TreeSpecies.is_nut(String(f.get("species", ""))))
		if nearby.is_empty():
			return
		# The nearest nut actually within reach, not just anything in the
		# wider query radius -- a squirrel grabs what it is standing next to.
		var nearest_position: Vector2 = nearby[0]["position"]
		var nearest_species: String = nearby[0]["species"]
		var nearest_distance: float = creature.position.distance_to(nearest_position)
		for candidate in nearby:
			var candidate_position: Vector2 = candidate["position"]
			var distance: float = creature.position.distance_to(candidate_position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_position = candidate_position
				nearest_species = candidate["species"]
		if nearest_distance > SquirrelNutCaching.PICKUP_RADIUS_TILES * TerrainRenderer.TILE_SIZE:
			return
		var eaten_species := take_fruit_at(nearest_position)
		if eaten_species == "":
			return
		creature.carried_nut_species = eaten_species
		creature.carried_nut_origin = creature.position
		# A real heading to lean into while carrying (see CreatureMarker.
		# _wander_step) -- ordinary wander alone (CreatureWander, the SAME
		# home-tethered containment shape AmbientFlyerMovement uses for
		# birds) cannot be trusted to reach this module's own 2-9 tile
		# range, the same measured ~2.6-tile ceiling its siblings
		# (SeedDispersal/SeedCaching) needed this fix for (see
		# docs/progress.md).
		creature.carried_nut_direction = SquirrelNutCaching.carry_direction(creature.wander_seed)
		return

	# Carrying: resolve once it has actually travelled its own (short) carry
	# distance -- eaten outright (the majority outcome) or cached as a new
	# sapling (the minority, real scatter-hoarding).
	var carried_tiles: float = (
		creature.position.distance_to(creature.carried_nut_origin) / float(TerrainRenderer.TILE_SIZE)
	)
	if carried_tiles < SquirrelNutCaching.carry_distance_tiles(creature.wander_seed):
		return
	# forager_seed is THIS squirrel's own identity seed (wander_seed) -- a
	# fitter individual forager is a slightly more efficient predator (see
	# SquirrelNutCaching.NUT_FITNESS_CHANCE_SWING), threaded through the same
	# way AmbientFlyerMarker._step_seed_carrying threads its own wander_seed
	# into SeedEndozoochory.seed_is_consumed.
	if not SquirrelNutCaching.nut_is_consumed(creature.wander_seed, creature.wander_seed):
		try_plant_seed_at(creature.position, creature.carried_nut_species)
	creature.carried_nut_species = ""
	creature.carried_nut_direction = Vector2.ZERO


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
			# A real heading to lean into while carrying (see CreatureMarker.
			# _wander_step) -- ordinary wander alone (CreatureWander, the
			# SAME home-tethered containment shape AmbientFlyerMovement uses
			# for birds) is measured at a hard ~2.6-tile ceiling regardless
			# of wander_seed, well short of this module's own 3-14 tile
			# range without it -- the worst-affected of the three ground
			# carriers (0/30 sampled seeds ever reached it under pure
			# wander, see docs/progress.md).
			creature.carried_seed_direction = SeedDispersal.carry_direction(creature.wander_seed)
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
	creature.carried_seed_direction = Vector2.ZERO


## Adds/removes tuft sprites so the rendered layer matches the sim's patch
## set; a growing patch is scaled by its growth so grass visibly rises.
## How far out decoration is drawn, derived from what the camera actually
## frames (see DecorationLod.radius_chunks) rather than fixed at a guess, so
## changing the zoom or the window size can never leave the radius too small
## and start showing bare ground at the edges. Falls back to the derived
## default if there is no viewport to ask (headless tests).
func _derive_decoration_radius() -> int:
	return DecorationLod.radius_chunks(_visible_half_span_tiles(), CHUNK_SIZE)


## Real half-span of tiles the camera actually frames -- shared by
## _derive_decoration_radius (the coarser chunk-level gate) and grass's own
## tighter tile-level cutoff (see GRASS_VIEW_BUFFER_TILES/_sync_grass_
## sprites). Asked in TILES rather than measured off raw viewport pixels:
## with `canvas_items` stretch the viewport reports the window's real size
## while the canvas is scaled to match, so pixels alone would say a 4K
## player sees three times as much world as a 720p one. They see the same
## amount (see DisplayScaling.visible_tiles_across) -- this is why
## DecorationLod.visible_half_span_tiles' own raw-pixel math isn't reused
## here despite doing the same conceptual job.
func _visible_half_span_tiles() -> Vector2:
	var viewport_size := Vector2(DEFAULT_VIEWPORT_SIZE)
	if _tile_map_layer != null and _tile_map_layer.is_inside_tree():
		viewport_size = _tile_map_layer.get_viewport_rect().size
	var across := DisplayScaling.visible_tiles_across(viewport_size.x, viewport_size.y)
	var down := DisplayScaling.visible_tiles_across(viewport_size.y, viewport_size.y)
	return Vector2(across, down) * 0.5


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
		if sprite is Array:
			for card in sprite:
				card.queue_free()
		else:
			sprite.queue_free()
	holder[chunk_coord] = {}


## Tile-precise buffer beyond the camera's own visible window (see
## _visible_half_span_tiles) that grass keeps drawn, once a chunk has
## already passed the coarser chunk-level _decorates gate. Reported live:
## "optimize the grass blade rendering so it only draws what the player
## currently sees +2 tiles of buffer in every direction... to improve
## framerate" -- see docs/concept/long_grass.md.
const GRASS_VIEW_BUFFER_TILES := 2

## One MultiMeshInstance2D draw call per Y-band, not one Sprite2D per card
## (see IllustratedGrassPatch.BAND_COUNT for why bands, not per-tile or
## per-chunk). Every band fully rebuilds from the sim's current patch set
## and growth on each throttled sync (see GRASS_REFRESH_INTERVAL) - cheap
## under GPU instancing, unlike the individual-node churn this replaced. On
## top of that, each individual cell is further filtered to the player's
## own tile-precise view window (see GRASS_VIEW_BUFFER_TILES) rather than
## the whole chunk being all-or-nothing.
func _sync_grass_sprites(chunk_coord: Vector2i) -> void:
	if not _decorates(chunk_coord):
		_drop_decoration(_grass_sprites, chunk_coord)
		return
	var sim: TallGrass = _grass_sims.get(chunk_coord)
	if sim == null:
		return
	var bands: Dictionary = _grass_sprites.get(chunk_coord, {})

	var origin := chunk_coord * CHUNK_SIZE
	var half_span := _visible_half_span_tiles()
	var cards_by_band: Dictionary = {}  # band index -> Array[Dictionary] of per-card specs
	for cell in sim.get_patch_cells():
		var tile: Vector2i = origin + cell
		# Tile-precise cutoff on top of the coarser chunk-level _decorates
		# gate above: a chunk is CHUNK_SIZE tiles square while the camera
		# only ever shows a much smaller window (DecorationLod's own doc
		# comment: "three times what the camera can actually show").
		# Re-evaluated on the same cadence _sync_grass_sprites already runs
		# at (GRASS_REFRESH_INTERVAL, plus immediately on a chunk-boundary
		# crossing -- see update()), so cards genuinely load/unload as the
		# player walks, not just once per chunk.
		if not DecorationLod.keeps_decoration_tile(tile, _disturbance_center_tile, half_span, GRASS_VIEW_BUFFER_TILES):
			continue
		# Per-seed, not a single flat constant: IllustratedGrassPatch derives
		# each tuft's atlas variant, card offsets and depth ordering from this
		# same seed (card_specs_for_seed), so a meadow shows real per-tuft
		# variety instead of identically-placed clumps.
		var seed_value := hash("%d_%d_grass_tuft" % [tile.x, tile.y])
		var cell_spec := {
			"seed": seed_value,
			"ground_position": Vector2(
				(tile.x + 0.5) * TerrainRenderer.TILE_SIZE,
				(tile.y + 0.5) * TerrainRenderer.TILE_SIZE
			),
			"growth": sim.get_growth(cell),
		}
		# Bucketed per CARD, not per cell: each of the cell's own CARD_COUNT
		# cards carries its own random offset from the cell's nominal ground
		# position (see IllustratedGrassPatch.card_specs_for_seed), so a
		# card's own REAL, offset-adjusted world Y -- not the cell's raw,
		# un-offset row -- decides which band it Y-sorts with. Reported
		# live, after the BAND_COUNT 8->32 fix: "y sorting works for some
		# [tufts] but not all... it parts and bends but y ordering is
		# correct only for some" -- see IllustratedGrassPatch.cards_for_cell
		# and docs/concept/long_grass.md for the full mechanism.
		for card in IllustratedGrassPatch.cards_for_cell(cell_spec):
			var local_row := IllustratedGrassPatch.local_row_for_world_y(card.position.y, origin.y, TerrainRenderer.TILE_SIZE)
			var band := IllustratedGrassPatch.band_index_for_local_y(local_row, CHUNK_SIZE)
			var list: Array = cards_by_band.get(band, [])
			list.append(card)
			cards_by_band[band] = list

	# A band whose last patch died (grazed/built on) is freed outright
	# rather than left holding a zero-instance MultiMesh.
	for band in bands.keys().duplicate():
		if not cards_by_band.has(band):
			bands[band].queue_free()
			bands.erase(band)

	for band in cards_by_band.keys():
		var mmi: MultiMeshInstance2D = bands.get(band)
		if mmi == null:
			mmi = MultiMeshInstance2D.new()
			mmi.position = Vector2(
				(origin.x + CHUNK_SIZE * 0.5) * TerrainRenderer.TILE_SIZE,
				IllustratedGrassPatch.band_anchor_world_y(band, origin.y, CHUNK_SIZE, TerrainRenderer.TILE_SIZE)
			)
			_entities_parent.add_child(mmi)
			bands[band] = mmi
		_illustrated_grass.fill_band(mmi, mmi.position, cards_by_band[band])

	_grass_sprites[chunk_coord] = bands


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
		# Anchor at the stem's foot, matching how flowers_near/blossom_height_
		# world measure a landing point from this same sprite's position --
		# not for Y-sorting, since ground decor never Y-sorts (see
		# _ground_decor_parent's own doc comment): it always draws underneath
		# via z_index instead.
		sprite.offset.y = -float(ProceduralFlowerSprite.SIZE.y) * 0.5
		# Blooms nod in the wind on the shared GPU material (see WindSway).
		sprite.material = _wind_sway.tuft_material()
		sprite.position = Vector2(
			(origin.x + cell.x + 0.5) * TerrainRenderer.TILE_SIZE,
			(origin.y + cell.y + 0.5) * TerrainRenderer.TILE_SIZE
		)
		_ground_decor_parent.add_child(sprite)
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
					# the stem's foot (which is what "position" is). Scaled by
					# THIS plant's actual size -- species norm, its own
					# variance, and how far it has grown -- the exact scale
					# _flower_scale_for draws its sprite at, so the landing
					# point can never drift from a plant smaller, or still
					# growing, than the species' nominal size (see
					# ProceduralFlowerSprite.blossom_height_world).
					"landing": flower_position - Vector2(
						0.0,
						ProceduralFlowerSprite.blossom_height_world(
							sprite_seed,
							_flower_scale_for(species, patch.growth_at(cell), sprite_seed).y
						)
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


## An animal DIED at this world position -- predator kill, player weapon,
## disease or starvation, all of which funnel through CreatureMarker._die().
## record_birth_at's mirror, and the other half of a conversation that until
## now only ran one way: a kill in front of the player would otherwise vanish
## the moment the chunk unloaded and reloaded.
##
## `is_predator` travels with the death rather than being looked up here,
## because the marker already knows what it was and the two aggregate pools
## are separate -- booking a wolf against the herbivore pool would under-count
## the wolves and shrink what the land is said to support.
func record_death_at(position: Vector2, is_predator: bool, count: float = 1.0) -> void:
	_ecosystem.record_death(
		_chunk_coord_for_tile(_world_tile_for_pixel(position)), is_predator, count
	)


## A courting pair produced young (see Courtship / AmbientFlyerMarker).
##
## Two things happen, and both matter. The offspring is spawned as a real
## flyer, so the player watching a dance sees a third butterfly appear. AND
## the region's aggregate population is told about it (see
## EcosystemSimulation.record_birth), so the birth is not lost the moment the
## chunk unloads -- the individual and aggregate halves of the simulation are
## the same population seen at two fidelities, not two separate worlds.
## `inherited_traits` is the child's PERSONALITY, already crossed from both
## parents by the courting pair itself (see AmbientFlyerMarker.
## _finish_courtship / FlyerPersonality). Optional, and empty by default, so a
## caller that has no parents to cross -- anything spawning a flyer that was
## not born from a dance -- still gets an ordinary butterfly, which then
## derives its own personality from its seed like every seeded adult does.
func spawn_flyer_offspring(
	species: String, position: Vector2, inherited_traits: Dictionary = {}
) -> void:
	var chunk_coord := _chunk_coord_for_tile(_world_tile_for_pixel(position))
	if not _loaded_ambient_flyers.has(chunk_coord):
		return
	# A meadow supports what it supports. Births with no ceiling is how the
	# deer explosion started, and courting butterflies breed far faster than
	# deer do -- measured climbing steadily across a single session before
	# this cap existed.
	#
	# Asked about THIS chunk's blooms, using the very multiplier the spawn
	# pass was handed on load (see _pollinator_multiplier_for). Against the
	# bare-ground ceiling, a flower-rich chunk was already over capacity the
	# moment it loaded, so courtship was refused precisely where there was
	# most reason to breed. Re-sampled rather than remembered, so a meadow
	# that has since bloomed harder raises its own capacity and one that has
	# withered lowers it.
	if (
		_loaded_ambient_flyers[chunk_coord].size()
		>= AmbientFlyerRenderer.max_flyers_per_chunk(_pollinator_multiplier_for(chunk_coord))
	):
		return
	var offspring := _ambient_flyer_renderer.spawn_offspring(
		_creatures_parent, species, position,
		hash("%d_%d_%d_offspring" % [int(position.x), int(position.y), _loaded_ambient_flyers[chunk_coord].size()]),
		self,
		inherited_traits
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


## Delivers pollen from a visiting bee/butterfly to the flower at
## `pixel_position` (see FlowerPatch.pollinate) -- the flower-side counterpart
## of record_pollination_visit_at for a blossoming tree. Nectar and pollen are
## separate resources here (FlowerPatch tracks them as separate dicts), so
## this is a wholly independent visit outcome from drink_nectar_at, not
## conditioned on it.
##
## Returns what the visitor now carries afterward (see Pollination.
## pollen_after_visit): unchanged when there is no patch or no flower here,
## and otherwise the visited flower's own species if it just gave pollen, or
## whatever the visitor already carried if it did not.
func pollinate_flower_at(pixel_position: Vector2, carried_species: String) -> String:
	var tile := _world_tile_for_pixel(pixel_position)
	var chunk_coord := _chunk_coord_for_tile(tile)
	var patch: FlowerPatch = _flower_patches.get(chunk_coord)
	if patch == null:
		return carried_species
	var cell := tile - chunk_coord * CHUNK_SIZE
	if not patch.has_flower(cell):
		return carried_species
	var species := patch.species_at(cell)
	var sex := patch.sex_at(cell)
	patch.pollinate(cell, carried_species)
	return Pollination.pollen_after_visit(carried_species, species, sex)


## Blossoming, insect-pollinated trees near `pixel_position` -- the tree-side
## counterpart of flowers_near, in the exact same {position, species, nectar,
## landing} shape so a bee's existing targeting machinery
## (PollinatorForaging.choose_target, unvisited_only, remember_visit)
## can treat a tree it is worth visiting exactly like a flower it already
## knows how to work, with no changes to that machinery at all.
##
## Wind-pollinated species (pine/acorn/hazelnut/walnut -- see
## TreeSpecies.needs_pollinators_for) never appear here: a real bee has
## nothing to gain landing on a catkin or a cone, unlike an apple or cherry
## blossom's real nectar reward.
##
## Blossom is a whole-world state (IllustratedTree.CANOPY_BLOSSOM only ever
## draws in spring -- see _sync_tree_season), not a per-tree one, so this
## gates on the season once rather than asking each tree what it is drawn as.
##
## Scoped to the loaded-tree chunk neighbourhood exactly like
## solid_obstacles_near scans _loaded_trees -- cheap for the same reason: it
## runs per bee per sniff, and _loaded_trees is already bucketed per chunk.
func blossoms_near(pixel_position: Vector2, radius_tiles: int = 8) -> Array:
	var out: Array = []
	if current_season() != "spring":
		return out
	var radius_px := float(radius_tiles) * TerrainRenderer.TILE_SIZE
	var chunk_px := float(CHUNK_SIZE) * TerrainRenderer.TILE_SIZE
	var min_chunk := Vector2i(
		floori((pixel_position.x - radius_px) / chunk_px),
		floori((pixel_position.y - radius_px) / chunk_px)
	)
	var max_chunk := Vector2i(
		floori((pixel_position.x + radius_px) / chunk_px),
		floori((pixel_position.y + radius_px) / chunk_px)
	)
	for chunk_y in range(min_chunk.y, max_chunk.y + 1):
		for chunk_x in range(min_chunk.x, max_chunk.x + 1):
			for tree in _loaded_trees.get(Vector2i(chunk_x, chunk_y), []):
				if not is_instance_valid(tree):
					continue
				if tree.position.distance_to(pixel_position) > radius_px:
					continue
				var species_id := TreeSpecies.species_for_bias(tree.species_bias)
				if not TreeSpecies.needs_pollinators_for(species_id):
					continue
				out.append({
					"position": tree.position,
					"species": species_id,
					# A blossom's reward is not modelled as a depleting
					# resource the way flower nectar is (see FlowerPatch) --
					# out of scope for this pass (see docs/progress.md). A
					# constant, always-present 1.0 is what makes a blossoming
					# tree always worth checking, exactly like an unchecked
					# flower already is regardless of how full it turns out
					# to be (see PollinatorForaging.is_worth_visiting).
					"nectar": 1.0,
				})
	return out


## Records a bee's visit to the blossoming tree at `tree_position` (see
## ChoppableTree.record_pollination_visit / FruitingModel.pollination_factor)
## -- the tree-side counterpart of drink_nectar_at. Returns whether a tree was
## actually found there, the same "did this really land on something"
## contract drink_nectar_at already has.
##
## `visit_weight` defaults to a flat 1.0 (an ordinary visit) but the caller
## (AmbientFlyerMarker) passes its own fitness-scaled weight for a real bee
## landing -- see FruitingModel.visit_weight_for_fitness.
func record_pollination_visit_at(tree_position: Vector2, visit_weight: float = 1.0) -> bool:
	var chunk_coord := _chunk_coord_for_tile(_world_tile_for_pixel(tree_position))
	for tree in _loaded_trees.get(chunk_coord, []):
		if not is_instance_valid(tree):
			continue
		# Same positional tolerance as flower visit-memory/claims (see
		# PollinatorForaging._was_visited/_is_claimed) -- a tree's position is
		# a real Node2D position rather than one rebuilt per query, but the
		# bee only ever hands back exactly the position blossoms_near gave
		# it, so an exact-enough tolerance is what's actually being matched.
		if tree.position.distance_to(tree_position) >= PollinatorForaging.LANDING_DISTANCE:
			continue
		if not tree.has_method("record_pollination_visit"):
			continue
		tree.record_pollination_visit(FruitingModel.BEARING_CYCLE_SECONDS, _world_age_seconds, visit_weight)
		return true
	return false


## Refills drained nectar across every loaded meadow.
func step_flowers(delta: float) -> void:
	var season := current_season()
	var growth_modifier := _season_cycle.growth_modifier(_world_age_seconds)
	for chunk_coord in _flower_patches:
		var patch: FlowerPatch = _flower_patches[chunk_coord]
		patch.advance(delta, growth_modifier)
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


## Dresses the trees -- the renderer new ones are built from, and every tree
## already loaded -- in the season the WORLD CLOCK says it is.
##
## Driven by the clock rather than by the simulation (see
## docs/concept/seasons.md, "The canopy is on the clock, not on the
## simulation"). This used to be private and called from step_fruiting alone,
## which runs only behind World._owns_ecosystem_simulation() and a ~1s
## accumulator -- so the first awaited chunk load built its trees before it
## ever fired (no season at all -> IllustratedTree's summer fallback -> green
## trees in the snow), and a joined client, owning no simulation, never ran it
## at all and kept a summer-green forest all year. It is public now because
## every path that establishes or moves the clock calls it, World's ungated
## per-frame _client_process included.
##
## Cheap enough for that: the TURN, not just the season name, is the
## signature, and SeasonTransition quantises progress precisely so a rebuild
## happens a handful of times per in-game year rather than every frame. (That
## quantised signature is also what stopped the whole world swapping canopies
## on a single frame boundary, which the gradual transition exists to avoid.)
##
## `player_pixel` (Vector2, optional) gates the per-tree redraw below by
## FRUITING_DETAIL_RADIUS, same as step_fruiting's own loop and for the same
## reason: without it, every loaded tree -- potentially thousands -- gets
## re-dressed with tree.ripe_fruit_count() (which clamps the "never touched"
## -1 sentinel to 0) each time the signature changes, including the very
## first-ever call, since _last_tree_season starts empty and so never
## matches. A tree step_fruiting deliberately skipped for being out of range
## must stay skipped here too, or it gets permanently un-skipped the moment a
## season turns.
##
## Left unfiltered (the null default) for set_world_age_seconds/
## jump_to_season: those are rare, deliberate whole-world refreshes -- a new
## or loaded world's clock landing on a season, or a /season command -- and
## are meant to dress every loaded tree at once, not just the ones near
## whichever player happened to trigger them.
func sync_tree_season(player_pixel: Variant = null) -> void:
	_tree_renderer.set_world_age_seconds(_world_age_seconds)
	# Snow, alongside the clock: this is the "redraw path" that reaches a
	# tree ALREADY standing (see TreeRenderer.set_snow_coverage's own doc
	# comment for why that setter alone only reaches a freshly SPAWNED one).
	# Read directly off _snow_depth rather than relying on set_snow_depth
	# having been called -- step_snow, the real per-frame path, sets it
	# directly and does not go through that setter (see step_snow's body).
	_tree_renderer.set_snow_coverage(_snow_depth)
	var canopy := _tree_renderer.canopy_state()
	var season_name: String = canopy["season"]
	var turning_into: String = canopy["turning_into"]
	var turn_progress: float = canopy["turn_progress"]
	# Snow is folded into the signature QUANTISED (see ProceduralTreeSprite.
	# snow_level), not raw -- lying snow changes by fractions of a percent
	# every frame, and comparing the raw value would defeat the whole point
	# of this guard, redrawing every tree in range on every tick of a
	# snowfall instead of a handful of times per snowfall the way a season
	# turn already does.
	var snow_signature := ProceduralTreeSprite.snow_level(_snow_depth)
	var signature := "%s/%s/%.2f/%.2f" % [season_name, turning_into, turn_progress, snow_signature]
	if signature == _last_tree_season:
		return
	_last_tree_season = signature
	for trees in _loaded_trees.values():
		for tree in trees:
			if not tree.has_method("set_ripe_fruit"):
				continue
			if (
				player_pixel is Vector2
				and player_pixel.distance_to(tree.position) > FRUITING_DETAIL_RADIUS
			):
				continue
			tree.set_ripe_fruit(
				tree.ripe_fruit_count(), season_name, turning_into, turn_progress, _snow_depth
			)


## The season the loaded trees were last drawn for -- see sync_tree_season.
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


## The nearest tree within `max_distance` of `pixel_position` that currently
## carries real hanging fruit (FruitingModel.hanging_at > 0) -- the direct-
## from-the-branch counterpart to fruit_near/take_fruit_at above, which only
## ever see WINDFALL already on the ground (docs/concept/progression.md
## "Ecological literacy"). Returns {"species_id": String, "is_peak": bool}
## for the nearest qualifying tree, or {} if none is in reach. Read-only:
## this does NOT reduce the tree's own crop -- hanging_at is a pure function
## of elapsed time (see fruiting_model.gd), the same number _step_fruiting
## already computes every step, so a direct pick needs no separate mutable
## stock to decrement.
func harvest_peak_fruit_near(pixel_position: Vector2, max_distance: float) -> Dictionary:
	var found := {}
	var nearest_distance := max_distance
	for trees in _loaded_trees.values():
		for tree in trees:
			if not is_instance_valid(tree):
				continue
			var distance: float = pixel_position.distance_to(tree.position)
			if distance > nearest_distance:
				continue
			var genome := _forage_scheduler.genome_for(tree.position)
			var species_id := TreeSpecies.species_for_bias(genome.species_bias)
			if not _NAMED_FRUIT_ITEMS.has(species_id):
				continue
			var yield_multiplier := TreeSpecies.yield_multiplier_for(species_id)
			var ripening_multiplier := TreeSpecies.ripening_multiplier_for(species_id)
			var warmth := _warmth_at_pixel(tree.position)
			var hanging := _fruiting_model.hanging_at(
				genome, _world_age_seconds, warmth, yield_multiplier, ripening_multiplier
			)
			if hanging <= 0:
				continue
			nearest_distance = distance
			found = {
				"species_id": species_id,
				"is_peak": _fruiting_model.is_peak_ripe(
					genome, _world_age_seconds, warmth, yield_multiplier, ripening_multiplier
				),
			}
	return found


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


## Central ant-mound step (see AntColony, docs/concept/soil_fauna.md
## "Ants"): every loaded chunk's colonies advance every call, and each mound
## rolls its own small per-step chance (AntColony.should_forage) to send a
## forager out for a nearby food item -- a fallen grass seed on a grassland
## mound (myrmecochory, the shortest-range seed carrier the game has, see
## AntColony.CARRY_MIN_TILES/CARRY_MAX_TILES's own doc comment on why), or a
## fallen windfall fruit/nut on a forest/rainforest mound
## (_forage_windfall_near_mound) -- TallGrass, the sole source of ground SEED
## in this game, only grows on grassland, so a forest/rainforest mound would
## otherwise have nothing to harvest at all (see AntColony's own doc comment).
## Branches on the MOUND's own biome, not the colony's -- a single chunk can
## straddle a biome boundary, so different mounds in the same colony can take
## different branches.
func step_ants(delta_seconds: float) -> void:
	for chunk_coord in _ant_colonies:
		var colony: AntColony = _ant_colonies[chunk_coord]
		colony.advance(delta_seconds)
		var origin: Vector2i = chunk_coord * CHUNK_SIZE
		for cell in colony.mound_cells():
			if not colony.should_forage(cell):
				continue
			var global_tile: Vector2i = origin + cell
			if biome_at_global(global_tile.x, global_tile.y) == "grassland":
				_forage_seed_near_mound(colony, origin, cell)
			else:
				_forage_windfall_near_mound(colony, origin, cell)


## One mound's forager: look for the nearest fallen grass seed within its
## SHORT foraging reach (AntColony.FORAGE_RADIUS_TILES, well under a mouse's
## own SeedCaching.PICKUP_RADIUS_TILES -- an ant's range from its mound is
## far smaller than a mouse's whole home range) and, if there is one, take
## it and cache it a short carry away (AntColony.carry_distance_tiles /
## carry_direction). Mirrors _step_grass_seed_caching's take-then-plant
## shape, but there is no individual carrier here to walk the distance over
## time -- a mound is a background population effect, not a pathfinding
## creature, so the whole harvest-and-cache resolves in one step.
func _forage_seed_near_mound(colony: AntColony, origin: Vector2i, cell: Vector2i) -> void:
	var mound_pixel := Vector2(
		float(origin.x + cell.x) + 0.5, float(origin.y + cell.y) + 0.5
	) * float(TerrainRenderer.TILE_SIZE)
	var nearby := grass_seeds_near(mound_pixel, int(ceil(AntColony.FORAGE_RADIUS_TILES)))
	if nearby.is_empty():
		return
	var reach := AntColony.FORAGE_RADIUS_TILES * float(TerrainRenderer.TILE_SIZE)
	# The nearest seed actually within reach, not just anything in the wider
	# query radius -- the same nearest-in-reach shape
	# _step_grass_seed_caching uses for a mouse.
	var nearest_position: Vector2 = nearby[0]["position"]
	var nearest_distance: float = mound_pixel.distance_to(nearest_position)
	for candidate in nearby:
		var candidate_position: Vector2 = candidate["position"]
		var distance: float = mound_pixel.distance_to(candidate_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_position = candidate_position
	if nearest_distance > reach:
		return
	if not take_grass_seed_at(nearest_position):
		return
	var carrier_seed := colony.carrier_seed_for(cell)
	var carry_tiles := AntColony.carry_distance_tiles(carrier_seed)
	var direction: Vector2 = AntColony.carry_direction(carrier_seed)
	var target := nearest_position + direction * carry_tiles * float(TerrainRenderer.TILE_SIZE)
	plant_grass_at(target)


## One mound's forager in a forest/rainforest chunk: TallGrass never grows
## outside grassland (see AntColony's own doc comment), so a forest/
## rainforest mound instead checks for a nearby fallen windfall fruit/nut
## ground item -- the same fruit_near/take_fruit_at API SquirrelNutCaching
## already uses -- gated to real NUTS (TreeSpecies.is_nut) exactly like
## SquirrelNutCaching's own gate: a single forager ant cannot meaningfully
## interact with an intact fleshy fruit the way a bird or squirrel does, so a
## fallen cherry/apple is left for the ordinary generic fruit-eating path,
## the same reasoning _step_squirrel_nut_caching's own doc comment gives.
##
## Mirrors _forage_seed_near_mound's find-then-carry shape exactly (same
## FORAGE_RADIUS_TILES reach, same carrier_seed_for/carry_distance_tiles/
## carry_direction for placing the result), but resolves through
## AntColony.windfall_is_consumed first: most finds are consumed outright on
## the spot (a colony scavenging soft pulp/residue, not carrying off an
## intact propagule -- see WINDFALL_CONSUMED_CHANCE's own doc comment), and
## only rarely does one survive to be cached as a new sapling via the SAME
## try_plant_seed_at sink robin/squirrel dispersal already use.
func _forage_windfall_near_mound(colony: AntColony, origin: Vector2i, cell: Vector2i) -> void:
	var mound_pixel := Vector2(
		float(origin.x + cell.x) + 0.5, float(origin.y + cell.y) + 0.5
	) * float(TerrainRenderer.TILE_SIZE)
	var nearby := fruit_near(mound_pixel, int(ceil(AntColony.FORAGE_RADIUS_TILES)))
	nearby = nearby.filter(func(f): return TreeSpecies.is_nut(String(f.get("species", ""))))
	if nearby.is_empty():
		return
	var reach := AntColony.FORAGE_RADIUS_TILES * float(TerrainRenderer.TILE_SIZE)
	# The nearest nut actually within reach, not just anything in the wider
	# query radius -- the same nearest-in-reach shape _forage_seed_near_mound
	# uses for a grass seed.
	var nearest_position: Vector2 = nearby[0]["position"]
	var nearest_distance: float = mound_pixel.distance_to(nearest_position)
	for candidate in nearby:
		var candidate_position: Vector2 = candidate["position"]
		var distance: float = mound_pixel.distance_to(candidate_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_position = candidate_position
	if nearest_distance > reach:
		return
	var eaten_species := take_fruit_at(nearest_position)
	if eaten_species == "":
		return
	if AntColony.windfall_is_consumed(colony.windfall_carrier_seed_for(cell)):
		return
	var carrier_seed := colony.carrier_seed_for(cell)
	var carry_tiles := AntColony.carry_distance_tiles(carrier_seed)
	var direction: Vector2 = AntColony.carry_direction(carrier_seed)
	var target := nearest_position + direction * carry_tiles * float(TerrainRenderer.TILE_SIZE)
	try_plant_seed_at(target, eaten_species)


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
		# Anchored at the worm's own footprint like flowers are, rather than
		# sorting from its middle (not for Y-sorting -- ground decor never
		# Y-sorts, see _ground_decor_parent's own doc comment); and starting
		# at however far out of the ground it actually is, so a worm that has
		# just broken the surface shows a nose rather than a body.
		_show_worm_emerged(sprite, EarthwormPatch.emergence_for(patch.surfacing_at(cell)))
		sprite.position = Vector2(
			(origin.x + cell.x + 0.5) * TerrainRenderer.TILE_SIZE,
			(origin.y + cell.y + 0.5) * TerrainRenderer.TILE_SIZE
		)
		_ground_decor_parent.add_child(sprite)
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
	var growth_modifier := _season_cycle.growth_modifier(_world_age_seconds)
	for sim in _scrub_sims.values():
		sim.advance(delta_seconds, growth_modifier)

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
			_ground_decor_parent.add_child(sprite)
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
	var growth_modifier := _season_cycle.growth_modifier(_world_age_seconds)
	for sim in _lichen_sims.values():
		sim.advance(delta_seconds, growth_modifier)

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
			_ground_decor_parent.add_child(sprite)
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
	_refresh_bird_food_density()
	_ecosystem.step(delta_days)
	_refresh_creatures()


## Reports every loaded chunk's live worm/seed density into the ecosystem
## simulation before it steps, so robin/sparrow carrying capacity tracks the
## real state of the soil/meadow instead of only the snapshot taken when the
## chunk first loaded (see EcosystemSimulation.update_worm_density/
## update_seed_density). Worm burrow count is fixed for a chunk's whole
## lifetime (EarthwormPatch's own doc comment), so this re-reports an
## unchanged number for robins in practice; ground-seed count genuinely
## shifts as TallGrass/FlowerPatch grow and shed seed over time, which is
## what sparrow capacity actually needs to track.
func _refresh_bird_food_density() -> void:
	for chunk_coord in _loaded_chunks.keys():
		var worm_patch: EarthwormPatch = _worm_patches.get(chunk_coord)
		if worm_patch != null:
			_ecosystem.update_worm_density(chunk_coord, worm_patch.worm_cells().size())
		var seed_count := 0
		var grass: TallGrass = _grass_sims.get(chunk_coord)
		if grass != null:
			seed_count += grass.ground_seed_cells().size()
		var flowers: FlowerPatch = _flower_patches.get(chunk_coord)
		if flowers != null:
			seed_count += flowers.ground_seed_cells().size()
		_ecosystem.update_seed_density(chunk_coord, seed_count)


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
		# One rule, one place: CreatureMarker.is_player_invested() is the same
		# question _die() asks before booking a death against the region, so
		# the two cannot drift into disagreeing about whose animal this is.
		var invested: bool = creature.is_player_invested()
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


## Real slope in degrees at a global tile (see terrain_relief.gd,
## docs/concept/terrain_relief.md). Always delegates to the generator --
## unlike elevation_at_global above, no chunk caches a per-tile slope array
## to read from instead, so there is no faster path to take when the chunk
## happens to be loaded.
func slope_at_global(global_x: int, global_y: int) -> float:
	return generator.slope_at_global(global_x, global_y)


## Real aspect (compass bearing the slope faces) at a global tile -- same
## always-delegates shape as slope_at_global above.
func aspect_at_global(global_x: int, global_y: int) -> float:
	return generator.aspect_at_global(global_x, global_y)


## The raw elevation gradient at a global tile, for a caller that wants BOTH
## slope and aspect there. Same always-delegates shape as the two above.
##
## Slope and aspect are two readings of ONE gradient (see
## TerrainRelief.gradient_at), and each of the two functions above takes its
## own four elevation samples -- so asking for both, which is exactly what
## hillshading every tile of every chunk does, sampled twice over.
func gradient_at_global(global_x: int, global_y: int) -> Vector2:
	return generator.gradient_at_global(global_x, global_y)


## Whether a global tile renders as a river on the water overlay (see
## docs/concept/rivers.md) -- a curated real river's course or a procedural
## fallback candidate. Same always-delegates shape as gradient_at_global
## above; unlike biome_at_global below, needs no loaded-chunk cache since a
## river is never stored per-chunk (see _paint_water_overlay).
func is_river_at_global(global_x: int, global_y: int) -> bool:
	return generator.is_river_at_global(global_x, global_y)


## A tile under a baked lake's surface (docs/concept/hydrology.md) -- an
## overlay flag on land biome exactly like is_river_at_global.
func is_lake_at_global(global_x: int, global_y: int) -> bool:
	return generator.is_lake_at_global(global_x, global_y)


## Real metres of lake water over a tile, 0.0 off a lake. Unlike river
## depth this delegates directly: nothing a player builds ponds a lake.
func lake_depth_meters_at_global(global_x: int, global_y: int) -> float:
	return generator.lake_depth_meters_at_global(global_x, global_y)


## One byte per cell, 1 where a river or lake covers the ground -- the
## per-chunk form of Chunk.blocks_ground_cover, for consumers that take a
## whole flag array (TallGrass) rather than a Chunk.
func _ground_cover_blockers(chunk: Chunk) -> PackedByteArray:
	var blockers := PackedByteArray()
	blockers.resize(chunk.width * chunk.height)
	for index in blockers.size():
		blockers[index] = 1 if chunk.blocks_ground_cover(index) else 0
	return blockers


## Real river depth at a global tile -- the natural solved depth (see
## EarthChunkGenerator.river_hydraulics_at_global), raised where a
## player-built dam downstream is ponding this cell (see
## docs/concept/rivers.md's "Dams").
##
## Unlike is_river_at_global above this can NOT just delegate: whether a
## cell is ponded depends on placed dams, which live in chunk.modifications
## and so are the manager's knowledge, not the generator's.
func river_depth_meters_at_global(global_x: int, global_y: int) -> float:
	var natural := generator.river_depth_meters_at_global(global_x, global_y)
	if natural <= 0.0:
		return natural  # not a river cell; a dam here ponds nothing
	return _impounded_depth_at(global_x, global_y, natural)


## Whether this tile holds a boulder the water must flow around: a dropped
## boulder piece, or the natural stone roll landing a boulder-class stone
## on a river cell (the same roll StoneRenderer spawns, so the water bends
## around exactly the rocks the player sees). Any OTHER real piece on the
## tile means the ground is built over -- no stone spawns there.
func flow_boulder_at_global(global_x: int, global_y: int) -> bool:
	var piece := modification_at_global(global_x, global_y)
	if piece == BOULDER_PIECE_ID:
		return true
	if BuildingPiece.has_piece(piece):
		return false
	# On the river OR on its bank apron: a rock at the water's edge must
	# part the waterline around itself too ("wrap shorelines around edge
	# boulders"), not only a rock standing mid-stream.
	if not generator.is_within_river_apron(global_x, global_y):
		return false
	var biome := biome_at_global(global_x, global_y)
	if not StonePlacement.STONE_BIOMES.has(biome):
		return false
	if not _flow_stone_placement.has_stone_at(global_x, global_y, biome):
		return false
	# An ore deposit rides the same stone roll (OrePlacement.is_ore_at) and
	# spawns a chunky minable rock -- it bends the water exactly like a
	# boulder ("ore should also bend the water").
	if _flow_ore_placement.is_ore_at(global_x, global_y, biome):
		return true
	var diameter := StoneSize.diameter_for(_flow_stone_placement.seed_at(global_x, global_y))
	return StoneSize.class_for(diameter) == StoneSize.CLASS_BOULDER


## Whether the channel is dammed at this course position, scanning the
## perpendicular wet row rather than the single walked tile -- the course
## polyline is Chaikin-smoothed, so the walked line can pass a tile BESIDE
## a built dam (found live: the ponding tests went red the moment the
## smoothing landed, because the exact-tile check missed the piece).
##
## Two ways to be a crest:
##   * an engineered stone_dam piece ANYWHERE in the row -- it is a
##     constructed full-channel weir, one piece blocks the channel
##   * loose boulders on EVERY wet tile of the row (at least two) -- one
##     mid-channel rock never dams a river; a closed row does. This is
##     what lets "dropping boulders into the river" build a pond.
func crest_blocks_at_global(global_x: int, global_y: int) -> bool:
	var verdict := _row_crest_verdict(global_x, global_y)
	return verdict.dam_piece or verdict.boulders_closed


## The boulder half of the crest rule alone -- exposed for tests that pin
## "a partial row must not pond" without a stone_dam muddying the answer.
func boulder_row_blocks_at_global(global_x: int, global_y: int) -> bool:
	return _row_crest_verdict(global_x, global_y).boulders_closed


## Every wet tile in the channel CROSS-SECTION through this course
## position: tiles in the surrounding box whose along-course offset stays
## under a tolerance. A box-and-slice, deliberately not a walked
## perpendicular line -- on a diagonal reach the wet row is a STAIRCASE of
## tiles, and a rounded perpendicular walk steps over half of them (found
## live: a dam one tile off the walked diagonal was invisible to the
## crest check).
func wet_row_tiles_at_global(global_x: int, global_y: int) -> Array:
	var nearest := generator.river_catalog().nearest_river_at(
		global_x, global_y,
		EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	var row: Array = []
	if nearest.distance_tiles > RiverCatalog.RIVER_HALF_WIDTH_TILES:
		return row
	var radians := deg_to_rad(nearest.course_bearing_deg)
	var along_dir := Vector2(sin(radians), -cos(radians))
	var reach := int(ceil(RiverCatalog.RIVER_HALF_WIDTH_TILES)) + 2
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			if absf(along_dir.dot(Vector2(dx, dy))) > 0.75:
				continue
			var tile := Vector2i(global_x + dx, global_y + dy)
			var tile_nearest := generator.river_catalog().nearest_river_at(
				tile.x, tile.y,
				EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
			)
			var across: float = absf(
				tile_nearest.signed_across_tiles / RiverCatalog.RIVER_HALF_WIDTH_TILES
			)
			if across < 0.97:
				row.append(tile)
	return row


func _row_crest_verdict(global_x: int, global_y: int) -> Dictionary:
	var verdict := {"dam_piece": false, "boulders_closed": false}
	var nearest := generator.river_catalog().nearest_river_at(
		global_x, global_y,
		EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	if nearest.distance_tiles > RiverCatalog.RIVER_HALF_WIDTH_TILES:
		return verdict
	# Closure is judged by LATERAL POSITION, not by tile membership: on a
	# diagonal reach the slice window catches a two-column staircase, and a
	# perfectly good one-column boulder row would fail a per-tile check on
	# the second column. Water cannot pass any across-band that holds a
	# boulder, whichever staircase column the boulder sits in -- so bucket
	# the slice by across and require every wet band blocked.
	#
	# And the along-window SLIDES: the window is re-anchored to each asking
	# tile, so a wall a fraction of a tile up- or downstream of the asked
	# course position would slide half out of a fixed window and read as
	# open (found live: the impound walk visited a wall tile whose own
	# window had slid ~0.7 tiles, traded away half the wall, and the pond
	# never formed). A wall anywhere within one window-width of this tile
	# dams the water AT this tile, so the closure is tried at three window
	# anchors and any closed one counts.
	# Closure is judged from the WALL ITSELF -- the connected chain of
	# blocked wet tiles -- not from windows around the asking tile. Two
	# earlier versions judged windows ("every wet band in the window must
	# be blocked", then "the blocked tiles in a fixed along-window must
	# cover the width") and both broke, because what falls in a window is
	# an accident of the asking tile's own bearing and anchor: a diagonal
	# wall asked from its end tile extends ~2 along-tiles away and slid
	# half out of every window. The wall is the only stable object here,
	# so: seed from blocked tiles near this course position, flood-fill
	# through 8-adjacent blocked wet tiles, and ask whether the CHAIN
	# reaches both waterlines. Adjacency is also the honest watertightness
	# rule -- a one-tile hole breaks the chain, so no separate gap logic.
	var radians := deg_to_rad(nearest.course_bearing_deg)
	var along_dir := Vector2(sin(radians), -cos(radians))
	var reach := int(ceil(RiverCatalog.RIVER_HALF_WIDTH_TILES)) + 2
	var seeds: Array = []
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var along := along_dir.dot(Vector2(dx, dy))
			if absf(along) > 0.75:
				continue
			var tile := Vector2i(global_x + dx, global_y + dy)
			if modification_at_global(tile.x, tile.y) == DAM_PIECE_ID:
				var dam_nearest := generator.river_catalog().nearest_river_at(
					tile.x, tile.y,
					EarthChunkGenerator.WORLD_WIDTH_TILES,
					EarthChunkGenerator.WORLD_HEIGHT_TILES
				)
				var dam_across: float = (
					dam_nearest.signed_across_tiles / RiverCatalog.RIVER_HALF_WIDTH_TILES
				)
				if absf(dam_across) < 0.97:
					verdict.dam_piece = true
				continue
			if _blocked_wet_across_at(tile) != null:
				seeds.append(tile)
	if seeds.is_empty():
		return verdict
	var component := {}
	var frontier := seeds.duplicate()
	var min_across := INF
	var max_across := -INF
	while not frontier.is_empty():
		var tile: Vector2i = frontier.pop_back()
		if component.has(tile):
			continue
		var across = _blocked_wet_across_at(tile)
		if across == null:
			continue
		component[tile] = true
		min_across = minf(min_across, across)
		max_across = maxf(max_across, across)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				frontier.append(tile + Vector2i(dx, dy))
	if component.size() < 2:
		return verdict
	# How close to each waterline the chain's end boulders must reach: one
	# tile's lateral footprint short of the bank line, derived from the
	# real channel geometry and pinned by the closed-row / partial-row
	# ponding tests.
	var end_reach := 0.97 - 1.0 / RiverCatalog.RIVER_HALF_WIDTH_TILES
	verdict.boulders_closed = min_across <= -end_reach and max_across >= end_reach
	return verdict


## The signed across-fraction of a tile IF it is a wet, flow-blocking tile
## (a dropped or natural boulder standing in the channel) -- null
## otherwise. The flood-fill's single membership test.
func _blocked_wet_across_at(tile: Vector2i):
	if not flow_boulder_at_global(tile.x, tile.y):
		return null
	var tile_nearest := generator.river_catalog().nearest_river_at(
		tile.x, tile.y,
		EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	var across: float = (
		tile_nearest.signed_across_tiles / RiverCatalog.RIVER_HALF_WIDTH_TILES
	)
	if absf(across) >= 0.97:
		return null
	return across


## True if a player-built dam stands on this tile.
func has_dam_at_global(global_x: int, global_y: int) -> bool:
	return modification_at_global(global_x, global_y) == DAM_PIECE_ID


## The river tile `tiles_back` steps UPSTREAM of `from` along its own
## curated course -- negative walks downstream instead. Returns `from`
## itself when there is no river there to walk along.
##
## Upstream is "toward the source", i.e. toward a smaller course fraction
## (see RiverCatalog.nearest_river_at), and one tile of course is stepped by
## converting that fraction change back through the river's own tile-space
## polyline. Exposed because both the ponding search and its tests need the
## same notion of "further up this river".
func upstream_river_tile(from: Vector2i, tiles_back: int) -> Vector2i:
	return _course_tile_offset(from, float(tiles_back))


## The tile `tiles_upstream` along the course from `from` -- fractional, so
## a caller can step finer than one tile. Negative walks downstream.
##
## Fractional steps matter for the dam search: the walk rounds to integer
## tiles, so stepping a whole tile at a time can skip straight past the cell
## a dam actually stands on.
func _course_tile_offset(from: Vector2i, tiles_upstream: float) -> Vector2i:
	var here := generator.river_catalog().nearest_river_at(
		from.x, from.y, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	if here.name == "":
		return from
	var polylines := RiverCatalog.tile_polylines(
		EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	var points: Array = polylines[here.name]
	var total := 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	if total <= 0.0:
		return from
	# A real tile distance along the course, expressed as the fraction of
	# the whole river that distance represents.
	var target_fraction := clampf(here.course_fraction - tiles_upstream / total, 0.0, 1.0)
	return _tile_at_course_fraction(points, target_fraction)


## The tile sitting `fraction` of the way along a course polyline.
func _tile_at_course_fraction(points: Array, fraction: float) -> Vector2i:
	var total := 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	var want := total * clampf(fraction, 0.0, 1.0)
	var travelled := 0.0
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var segment := a.distance_to(b)
		if travelled + segment >= want and segment > 0.0:
			var t := (want - travelled) / segment
			var p := a + (b - a) * t
			return Vector2i(roundi(p.x), roundi(p.y))
		travelled += segment
	var last: Vector2 = points[points.size() - 1]
	return Vector2i(roundi(last.x), roundi(last.y))


## The real depth at a river cell once any downstream dam's pool is taken
## into account.
##
## Walks DOWNSTREAM along this cell's own river looking for a dam within
## MAX_BACKWATER_TILES. Downstream rather than upstream because a dam ponds
## what is BEHIND it, so the cell being asked about is the one upstream of
## the dam -- and bounded because an unbounded walk is exactly what a
## chunk-streamed world cannot afford (see rivers.md's own "no global pass"
## constraint).
##
## Nothing is stored: the pool is re-derived from the dam's presence, the
## river's real discharge and the real terrain every time it is asked for.
## That is what lets an impoundment persist across an unload, survive a
## chunk seam, and need no catch-up integration -- it is a pure function of
## state that already persists.
func _impounded_depth_at(global_x: int, global_y: int, natural_depth: float) -> float:
	var here := Vector2i(global_x, global_y)

	# Half-tile steps, not whole ones: the course walk rounds to integer
	# tiles, so stepping a whole tile at a time can skip straight over the
	# very cell the dam stands on and miss it entirely. Stepping finer and
	# de-duplicating visits every tile the course actually passes through.
	var seen := {}
	for step in range(0, DamImpoundment.MAX_BACKWATER_TILES * 2 + 1):
		var tiles_downstream := step * 0.5
		var downstream := _course_tile_offset(here, -tiles_downstream)
		if seen.has(downstream):
			continue
		seen[downstream] = true
		if not crest_blocks_at_global(downstream.x, downstream.y):
			continue

		var flow := generator.river_hydraulics_at_global(downstream.x, downstream.y)
		if flow.discharge_m3_s <= 0.0:
			continue
		# Pool depth AT THE DAM FACE, from real weir physics: its own crest
		# height plus the head the river's real discharge needs to spill
		# over that crest.
		var dam_bed := generator.terrain_relief().elevation_meters(
			generator.macro_elevation_at_global(downstream.x, downstream.y)
		)
		var face_depth := DamImpoundment.pooled_depth_m(
			dam_bed,
			DamImpoundment.pool_surface_elevation_m(dam_bed, flow.discharge_m3_s, flow.width_m)
		)
		# Thinning upstream along the (compressed) backwater -- see
		# DamImpoundment.MAX_BACKWATER_TILES for why the EXTENT is
		# represented rather than measured against real elevations, while
		# the DEPTH above stays real.
		var pooled := face_depth * DamImpoundment.backwater_falloff(tiles_downstream)
		# A dam raises water and never lowers it.
		return maxf(natural_depth, pooled)
	return natural_depth


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


## This pixel's chunk's average vegetation density -- the same
## effective_capacity-chasing number that visibly thins wild grass under
## drought (see EcosystemSimulation.add_region/step), exposed for a farmer
## NPC's production yield to read (docs/concept/npc.md "Needs and the local
## production economy") -- never an invented economy stat. Mirrors
## fish_population_near's exact pattern.
func vegetation_density_near(pixel_position: Vector2) -> float:
	var chunk_coord := _chunk_coord_for_tile(_world_tile_for_pixel(pixel_position))
	return _ecosystem.average_vegetation_density(chunk_coord)


## This pixel's chunk's aggregate herbivore population -- the same regional-
## game number wildlife density already runs on, exposed for a hunter NPC's
## production yield to read (docs/concept/npc.md). Mirrors
## fish_population_near's exact pattern.
func herbivore_population_near(pixel_position: Vector2) -> float:
	var chunk_coord := _chunk_coord_for_tile(_world_tile_for_pixel(pixel_position))
	return _ecosystem.herbivore_population(chunk_coord)


## This pixel's chunk's herbivore carrying capacity -- see
## herbivore_capacity_at_chunk. Mirrors herbivore_population_near's exact
## pattern; the two together are CreatureMarker's herd-disease density
## signal (docs/concept/disease.md).
func herbivore_capacity_near(pixel_position: Vector2) -> float:
	var chunk_coord := _chunk_coord_for_tile(_world_tile_for_pixel(pixel_position))
	return _ecosystem.herbivore_capacity_at(chunk_coord)


## This pixel's chunk's persistent land health (docs/concept/world.md "Land
## health: overharvesting leaves a lasting mark, not just a slower
## respawn") -- the extra multiplier on top of vegetation_density_near's
## weather-driven ceiling. Mirrors fish_population_near's exact pattern.
func land_health_near(pixel_position: Vector2) -> float:
	var chunk_coord := _chunk_coord_for_tile(_world_tile_for_pixel(pixel_position))
	return _ecosystem.land_health(chunk_coord)


## Records a real vegetation harvest against this pixel's chunk -- the
## explicit mortality term vegetation_density_near previously lacked
## entirely (only weather ever moved it; see EcosystemSimulation.
## record_vegetation_harvest's own doc comment). Sustained harvest here,
## faster than the region can regrow, is what depletes land_health_near
## (see EcosystemSimulation.step). Mirrors record_fish_catch_near's
## chunk-resolution pattern, without a discrete world node to remove --
## vegetation density has no individual on-screen entity the way a fish
## does.
func record_vegetation_harvest_near(pixel_position: Vector2, amount: float) -> void:
	var chunk_coord := _chunk_coord_for_tile(_world_tile_for_pixel(pixel_position))
	_ecosystem.record_vegetation_harvest(chunk_coord, amount)


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
	return _merchant_chunk_near(pixel_position, max_distance) != null


## The chunk key of the nearest in-range merchant's own village, or null.
## Factored out of has_merchant_near so the market lookup below runs the same
## single loop rather than a near-copy of it that could drift.
func _merchant_chunk_near(pixel_position: Vector2, max_distance: float):
	for chunk_coord in _loaded_villages:
		for node in _loaded_villages[chunk_coord]:
			if not (node is NpcMarker):
				continue
			if node.identity.occupation != "merchant":
				continue
			if pixel_position.distance_to(node.position) <= max_distance:
				return chunk_coord
	return null


## The real market of the settlement a nearby merchant belongs to, or null if
## no merchant is in reach.
##
## This is what makes shop prices local (see Shop.market_price_of and
## docs/emergence/03-contracts-property-economy.md's "Do not use one global
## price"). `_loaded_villages` is keyed by chunk, and a chunk coordinate is
## exactly what EntityRef.for_settlement names a settlement by, so the
## merchant's own key IS the settlement -- no new lookup table.
##
## The market is stocked with the goods a merchant sells on first access
## (Shop.stock_initial_goods, idempotent). Without that a never-visited
## village would hand back MarketStore's fresh EMPTY market, which prices at
## twenty times the catalog -- so the stocking is not flavour, it is what
## keeps an untraded village charging exactly what it charged before prices
## became local at all.
func merchant_market_near(pixel_position: Vector2, max_distance: float):
	var chunk_coord = _merchant_chunk_near(pixel_position, max_distance)
	if chunk_coord == null:
		return null
	var market := _market_store.market_for(EntityRef.for_settlement(chunk_coord))
	Shop.new().stock_initial_goods(market)
	return market


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


## The withering condition (1.0 = new, decaying toward 0.0 -- see
## BuildingDecay / docs/concept/timber_construction.md#withering-decay-as-a-
## bounded-closed-form-catch-up) of the piece at a global tile. 1.0 for a
## piece with no recorded decay yet (the same "absent means default"
## convention structural_instability/checked_at already use) and for an
## unloaded chunk or a non-piece cell.
func piece_condition_at_global(global_x: int, global_y: int) -> float:
	var chunk: Chunk = _loaded_chunks.get(_chunk_coord_for_tile(Vector2i(global_x, global_y)))
	if chunk == null:
		return 1.0
	return float(chunk.piece_condition.get(_local_coord(global_x, global_y), 1.0))


## Places a modification tile (Phase 3 building) at a global tile, repainting
## just its owning chunk. Returns false (no-op) if that tile isn't in a
## currently-loaded chunk -- building far outside the streamed area isn't
## meaningful since nothing there is being rendered or simulated.
func build_at_global(global_x: int, global_y: int, tile_id: String) -> bool:
	var chunk_coord := _chunk_coord_for_tile(Vector2i(global_x, global_y))
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk == null:
		return false
	var local := _local_coord(global_x, global_y)
	var previous_tile_id: String = chunk.modifications.get(local, "")
	chunk.modifications[local] = tile_id
	_terrain_renderer.paint(_tile_map_layer, chunk, chunk_coord * CHUNK_SIZE, generator.biome_at_global)
	_sync_piece_collision(Vector2i(global_x, global_y), tile_id)
	_sync_sagewerk_lumberjack(chunk_coord, local, previous_tile_id, tile_id)
	_sync_logistics_workers(chunk_coord, local, previous_tile_id, tile_id)
	if previous_tile_id != tile_id:
		# A different piece now occupies this cell (build_at_global doesn't
		# check occupancy, see _sync_piece_collision's own doc comment) --
		# whatever statics tracking belonged to the OLD piece here must not
		# leak onto the new one (see destroy_at_global's matching comment).
		chunk.structural_instability.erase(local)
		chunk.structural_checked_at.erase(local)
	_sync_statics(chunk_coord, chunk, local)
	_sync_flow_boulder(Vector2i(global_x, global_y))
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
	var previous_tile_id: String = chunk.modifications[local]
	chunk.modifications.erase(local)
	_terrain_renderer.paint(_tile_map_layer, chunk, chunk_coord * CHUNK_SIZE, generator.biome_at_global)
	_remove_piece_collision(Vector2i(global_x, global_y))
	_sync_sagewerk_lumberjack(chunk_coord, local, previous_tile_id, "")
	_sync_logistics_workers(chunk_coord, local, previous_tile_id, "")
	_sync_flow_boulder(Vector2i(global_x, global_y))
	# This cell no longer holds a piece at all -- its own statics tracking
	# (if any) belonged to whatever WAS here, not to bare ground. Clear it
	# before recomputing, or a piece rebuilt on this exact cell later could
	# inherit a stale checked_at timestamp and appear to have been
	# unsupported for far longer than it actually has.
	chunk.structural_instability.erase(local)
	chunk.structural_checked_at.erase(local)
	_sync_statics(chunk_coord, chunk, local)
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
	var occupied_cells := {}
	for local_cell in ground_pieces:
		var global_cell: Vector2i = origin_tile + local_cell
		if _chunk_coord_for_tile(global_cell) != chunk_coord:
			continue
		chunk.modifications[_local_coord(global_cell.x, global_cell.y)] = ground_pieces[local_cell]
		if BuildingPiece.has_piece(ground_pieces[local_cell]):
			occupied_cells[global_cell] = true
	_clear_vegetation_on_cells(chunk_coord, chunk, occupied_cells)
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
	# One recompute per distinct connected structure would be more precise,
	# but _sync_statics itself is O(structure size), and a stamped footprint
	# is exactly one small structure (HouseBlueprint's own scale) -- so a
	# single recompute seeded from any one of its own cells already covers
	# the whole thing, the same way find_rooms floods outward from wherever
	# it starts.
	for local_cell in ground_pieces:
		var global_cell: Vector2i = origin_tile + local_cell
		if _chunk_coord_for_tile(global_cell) == chunk_coord:
			_sync_statics(chunk_coord, chunk, _local_coord(global_cell.x, global_cell.y))
			break


## Clears whatever stands on `occupied_global_cells` -- trees and loose stone
## alike -- and drops any persisted record of it, so a stamped structure is
## never built AROUND a standing trunk or boulder
## (reported: a tree rooted in a village house's stone floor with its canopy
## drawn over the masonry).
##
## This is the only place that direction can be closed: _load_chunk spawns
## trees BEFORE it spawns the village that stamps houses over them, so on a
## fresh visit the house always arrives second. The other two directions of
## the same rule -- a tree respawning onto a persisted piece next load, and a
## spread seed sprouting on a floor -- live in TreeRenderer.spawn_trees and
## _can_root_at. planted_trees is pruned too, or a sapling under the footprint
## simply comes back from disk on the next load.
##
## The node is queue_free()d AND dropped from _loaded_trees in the same breath:
## _loaded_tree_positions and the forage loop both iterate that registry and
## read tree.position without an is_instance_valid guard.
func _clear_vegetation_on_cells(
	chunk_coord: Vector2i, chunk: Chunk, occupied_global_cells: Dictionary
) -> void:
	if occupied_global_cells.is_empty():
		return
	if _loaded_trees.has(chunk_coord):
		var survivors: Array[Node2D] = []
		for tree in _loaded_trees[chunk_coord]:
			# An already-freed entry is dropped rather than carried over: a
			# chopped tree queue_free()s itself while STAYING in this array
			# (choppable_tree.gd), and re-appending a dead reference into a
			# typed Array[Node2D] is not safe.
			if not is_instance_valid(tree):
				continue
			if occupied_global_cells.has(_world_tile_for_pixel(tree.position)):
				tree.queue_free()
			else:
				survivors.append(tree)
		_loaded_trees[chunk_coord] = survivors
	if _loaded_stones.has(chunk_coord):
		# Boulders and ore veins get built over exactly like trees do: _load_chunk
		# spawns them before the village stamps its houses, so on a fresh visit
		# the house always arrives second. Same drop-what-we-free discipline as
		# the tree loop above -- _loaded_stones is iterated without an
		# is_instance_valid guard elsewhere, and re-appending a dead reference
		# into a typed Array[Node2D] is not safe. No persisted-record prune is
		# needed: stone has no planted_trees equivalent, it is regenerated
		# deterministically, and StoneRenderer closes the respawn direction.
		var stone_survivors: Array[Node2D] = []
		for stone in _loaded_stones[chunk_coord]:
			if not is_instance_valid(stone):
				continue
			if occupied_global_cells.has(_world_tile_for_pixel(stone.position)):
				stone.queue_free()
			else:
				stone_survivors.append(stone)
		_loaded_stones[chunk_coord] = stone_survivors
	var kept: Array = []
	for record in chunk.planted_trees:
		if not occupied_global_cells.has(_world_tile_for_pixel(record["position"])):
			kept.append(record)
	chunk.planted_trees = kept


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


## Half the chunk size: the Chebyshev distance from a chunk's own CENTER
## tile to any of its four edges is exactly CHUNK_SIZE/2 -- the natural scan
## radius for "is a structure present anywhere in this settlement's own
## chunk" from that center tile (see
## _present_structure_ids_for_settlement_chunk below), reusing has_structure_
## near's own real distance metric rather than inventing a second one.
const SETTLEMENT_STRUCTURE_SCAN_RADIUS_TILES := CHUNK_SIZE / 2

## Every real placeable structure id (ItemCatalog "placeable" kind --
## sagewerk/storage/campfire/furnace, generalized over every future one too,
## not hardcoded to just today's two construction-relevant ids) actually
## present within SETTLEMENT_STRUCTURE_SCAN_RADIUS_TILES of `chunk_coord`'s
## own center tile -- the real `present_structure_ids` ConstructionPriority.
## decide/SettlementBuildDecision need (see docs/concept/timber_
## construction.md's "Deciding what to build, and who builds it" section),
## derived the SAME has_structure_near chunk-scan style every other real
## structure-presence check in this file already uses.
func _present_structure_ids_for_settlement_chunk(chunk_coord: Vector2i) -> Array:
	var center := chunk_coord * CHUNK_SIZE + Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2)
	var present: Array = []
	for item_id in _item_catalog.known_ids():
		if _item_catalog.kind_of(item_id) != "placeable":
			continue
		if has_structure_near(center.x, center.y, item_id, SETTLEMENT_STRUCTURE_SCAN_RADIUS_TILES):
			present.append(item_id)
	return present


## Keeps `_sagewerk_lumberjacks` in sync with a modification change at
## `local_cell`: a tile that just BECAME "sagewerk" gets staffed (if it
## isn't already -- rebuilding the same tile twice must not double-spawn), a
## tile that just STOPPED being "sagewerk" (overwritten by something else,
## or destroyed -- `new_tile_id` is "" for a destroy) has its worker
## despawned. A tile going from one non-sagewerk id to another is a no-op.
func _sync_sagewerk_lumberjack(
	chunk_coord: Vector2i, local_cell: Vector2i, previous_tile_id: String, new_tile_id: String
) -> void:
	if previous_tile_id == "sagewerk" and new_tile_id != "sagewerk":
		_despawn_lumberjack_at(chunk_coord, local_cell)
	elif new_tile_id == "sagewerk":
		_spawn_lumberjack_for(chunk_coord, local_cell)


## Spawns exactly one LumberjackMarker for the Sägewerk at `local_cell`, or
## does nothing if one already exists there -- "an NPC moves in", once, per
## Sägewerk instance.
func _spawn_lumberjack_for(chunk_coord: Vector2i, local_cell: Vector2i) -> void:
	if not _sagewerk_lumberjacks.has(chunk_coord):
		_sagewerk_lumberjacks[chunk_coord] = {}
	var by_cell: Dictionary = _sagewerk_lumberjacks[chunk_coord]
	if by_cell.has(local_cell):
		return
	var global_cell: Vector2i = chunk_coord * CHUNK_SIZE + local_cell
	var home := (Vector2(global_cell) + Vector2(0.5, 0.5)) * TerrainRenderer.TILE_SIZE
	var marker := LumberjackMarker.new()
	marker.home = home
	marker.position = home
	_entities_parent.add_child(marker)
	by_cell[local_cell] = marker


func _despawn_lumberjack_at(chunk_coord: Vector2i, local_cell: Vector2i) -> void:
	var by_cell: Dictionary = _sagewerk_lumberjacks.get(chunk_coord, {})
	var marker: Node = by_cell.get(local_cell)
	if marker == null:
		return
	marker.free()
	by_cell.erase(local_cell)


## Keeps `_logistics_workers` in sync with a modification change at
## `local_cell`. Two independent triggers matter: the tile itself becoming/
## stopping being a Sägewerk (re-decide staffing for exactly this cell), or
## a Storage appearing/disappearing anywhere nearby (re-decide staffing for
## EVERY already-known Sägewerk, since any one of them might have just
## gained or lost one of its paired Storages). Called AFTER _sync_sagewerk_
## lumberjack in both build_at_global/destroy_at_global, so
## `_sagewerk_lumberjacks` already reflects this change by the time this
## runs.
func _sync_logistics_workers(
	chunk_coord: Vector2i, local_cell: Vector2i, previous_tile_id: String, new_tile_id: String
) -> void:
	if previous_tile_id == "sagewerk" or new_tile_id == "sagewerk":
		_resync_logistics_for_sagewerk(chunk_coord, local_cell)
	if previous_tile_id == "storage" or new_tile_id == "storage":
		for sagewerk_chunk_coord in _sagewerk_lumberjacks:
			for sagewerk_local_cell in _sagewerk_lumberjacks[sagewerk_chunk_coord]:
				_resync_logistics_for_sagewerk(sagewerk_chunk_coord, sagewerk_local_cell)


## Re-decides whether the Sägewerk at (chunk_coord, local_cell) -- if one is
## actually there right now, per `_sagewerk_lumberjacks` -- should have
## Logistics workers: one full worker-pair (one per
## `_SAGEWERK_LOGISTICS_ITEM_IDS` entry) per real Storage currently within
## SAGEWERK_STORAGE_PAIR_RADIUS_TILES -- EVERY Storage in range, not just
## the nearest one. Reconciles rather than blindly spawning: a Storage
## newly in range gets a fresh pair, a previously-paired Storage no longer
## in range/present has its own pair despawned, and an already-correctly-
## staffed pair is left alone. Safe to call redundantly -- a no-op for
## already-staffed Storages (see the "already staffed" guard below), so
## callers don't need to know which of _sync_logistics_workers' two
## independent triggers actually applies.
func _resync_logistics_for_sagewerk(chunk_coord: Vector2i, local_cell: Vector2i) -> void:
	if not _sagewerk_lumberjacks.get(chunk_coord, {}).has(local_cell):
		_despawn_logistics_workers_at(chunk_coord, local_cell)
		return

	var global_cell: Vector2i = chunk_coord * CHUNK_SIZE + local_cell
	var sagewerk_pixel := (Vector2(global_cell) + Vector2(0.5, 0.5)) * TerrainRenderer.TILE_SIZE
	var storages_found: Array[Vector2] = nearby_structure_positions(
		sagewerk_pixel, "storage", float(SAGEWERK_STORAGE_PAIR_RADIUS_TILES) * TerrainRenderer.TILE_SIZE
	)
	if storages_found.is_empty():
		_despawn_logistics_workers_at(chunk_coord, local_cell)
		return

	var by_storage: Dictionary = _logistics_workers.get(chunk_coord, {}).get(local_cell, {})

	var in_range_keys := {}
	for storage_pixel in storages_found:
		var key := _storage_pairing_key(storage_pixel)
		in_range_keys[key] = true
		if by_storage.has(key):
			continue  # already staffed for this specific Storage -- no double-spawn
		var by_item: Dictionary = {}
		for item_id in _SAGEWERK_LOGISTICS_ITEM_IDS:
			var marker := LogisticsMarker.new()
			marker.earth = self
			marker.item_id = item_id
			marker.source_structure_id = "sagewerk"
			marker.storage_structure_id = "storage"
			marker.search_radius_tiles = SAGEWERK_STORAGE_PAIR_RADIUS_TILES
			marker.position = sagewerk_pixel
			marker.preferred_storage_position = storage_pixel
			_entities_parent.add_child(marker)
			by_item[item_id] = marker
		by_storage[key] = by_item

	# A previously-paired Storage that dropped out of range (or was
	# destroyed) gets its OWN pair despawned -- the other paired Storages'
	# own workers are untouched.
	for key in by_storage.keys().duplicate():
		if not in_range_keys.has(key):
			for marker in by_storage[key].values():
				marker.free()
			by_storage.erase(key)

	if not _logistics_workers.has(chunk_coord):
		_logistics_workers[chunk_coord] = {}
	_logistics_workers[chunk_coord][local_cell] = by_storage


## The stable key one paired Storage resolves to under a Sägewerk's own
## `_logistics_workers` entry -- position, not structure id, is the
## identity, the exact same "%d_%d" position-keying pattern
## `_structure_stock_key` already uses (two Storages never share an
## identity, the same way they never share a stock). Takes
## nearby_structure_positions' own tile-center pixel return shape.
func _storage_pairing_key(storage_pixel_position: Vector2) -> String:
	var tile := Vector2i(
		floori(storage_pixel_position.x / TerrainRenderer.TILE_SIZE),
		floori(storage_pixel_position.y / TerrainRenderer.TILE_SIZE)
	)
	return _structure_stock_key(tile.x, tile.y)


func _despawn_logistics_workers_at(chunk_coord: Vector2i, local_cell: Vector2i) -> void:
	var by_cell: Dictionary = _logistics_workers.get(chunk_coord, {})
	var by_storage = by_cell.get(local_cell)
	if by_storage == null:
		return
	for by_item in by_storage.values():
		for marker in by_item.values():
			marker.free()
	by_cell.erase(local_cell)


# -- real statics: a support graph over the piece grid (see
# docs/concept/timber_construction.md#real-statics-a-support-graph-over-the-
# piece-grid, src/gameplay/building_statics.gd) ------------------------------

## Keeps a structure's support graph in sync with a piece placement/removal/
## collapse at `local_cell` -- event-driven, not per-tick, exactly the doc's
## own framing: "a graph recompute over O(structure size) cells whenever a
## piece is placed, removed, or decays away... it never needs to run every
## frame." Scoped to just the touched structure's own connected piece grid
## via _structure_statics_view -- O(structure size), never the whole chunk.
func _sync_statics(chunk_coord: Vector2i, chunk: Chunk, local_cell: Vector2i) -> void:
	var seed_cells: Array[Vector2i] = [local_cell]
	for offset in _STATICS_NEIGHBORS:
		seed_cells.append(local_cell + offset)
	var view := _structure_statics_view(chunk, seed_cells)
	var grid: Dictionary = view["grid"]
	if grid.is_empty():
		return
	var grounded: Dictionary = view["grounded"]

	var prior_instability := {}
	var elapsed := 0.0
	for cell in grid:
		if chunk.structural_instability.has(cell):
			prior_instability[cell] = chunk.structural_instability[cell]
		if chunk.structural_checked_at.has(cell):
			elapsed = maxf(elapsed, _world_age_seconds - chunk.structural_checked_at[cell])

	var result := _building_statics.resolve(grid, grounded, prior_instability, elapsed)

	for cell in grid:
		if cell in result["collapsed"]:
			continue
		if result["instability"].has(cell):
			chunk.structural_instability[cell] = result["instability"][cell]
			chunk.structural_checked_at[cell] = _world_age_seconds
		else:
			chunk.structural_instability.erase(cell)
			chunk.structural_checked_at.erase(cell)

	for cell in result["collapsed"]:
		chunk.structural_instability.erase(cell)
		chunk.structural_checked_at.erase(cell)
		_collapse_piece(chunk_coord, chunk, cell, grid[cell])


## Neighbor offsets shared with BuildingStatics/RoomDetector's own 4-neighbor
## orthogonal convention.
const _STATICS_NEIGHBORS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]


## Flood-fills chunk.modifications from `seed_cells` through piece adjacency
## (any two BuildingPiece cells sharing an edge belong to the same
## structure), collecting just the touched structure's own local-cell ->
## piece_id grid (BuildingStatics' own input shape) plus the bare-terrain
## cells bordering it (a piece cell's neighbor that is NOT itself a piece --
## BuildingStatics' "grounded" input; no foundation-piece category exists
## yet, so bare terrain is the only real grounding source today). Only cells
## actually connected to `seed_cells` are ever visited -- never the whole
## chunk -- so this is O(structure size), matching _piece_grid_for's own
## per-cell shape without that helper's whole-chunk scan.
func _structure_statics_view(chunk: Chunk, seed_cells: Array) -> Dictionary:
	var grid := {}
	var grounded := {}
	var visited := {}
	var queue: Array[Vector2i] = []
	for seed in seed_cells:
		if visited.has(seed):
			continue
		var tile_id: String = chunk.modifications.get(seed, "")
		if BuildingPiece.has_piece(tile_id):
			visited[seed] = true
			grid[seed] = tile_id
			queue.append(seed)

	var head := 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		for offset in _STATICS_NEIGHBORS:
			var next: Vector2i = current + offset
			if visited.has(next):
				continue
			var next_tile_id: String = chunk.modifications.get(next, "")
			if BuildingPiece.has_piece(next_tile_id):
				visited[next] = true
				grid[next] = next_tile_id
				queue.append(next)
			else:
				grounded[next] = true
	return {"grid": grid, "grounded": grounded}


## A piece that lost its support path for too long topples (see
## docs/concept/materials.md's "Topple / collapse" verb, reused here rather
## than a bespoke "building HP" system, per this doc's pillar 2 -- "it
## eventually falls"). Drops its own constituent material back to the
## ground -- the exact reverse of BuildingPiece.cost_of, mirroring how
## breaking terrain/felling a tree already "drops its constituent
## materials, closing the loop straight back into crafting supply"
## (materials.md), via the same WorldItemBus.item_dropped path
## _resolve_caravan_raid already uses. Does NOT itself re-walk the support
## graph for what this piece was holding up -- _sync_statics' own resolve()
## call already found the WHOLE cascade in one pass (see BuildingStatics.
## resolve's own doc comment), so every collapsed cell in that pass is
## handled here independently, not by re-triggering a second recompute.
func _collapse_piece(chunk_coord: Vector2i, chunk: Chunk, local_cell: Vector2i, piece_id: String) -> void:
	var global_cell: Vector2i = chunk_coord * CHUNK_SIZE + local_cell
	var drop_position := (Vector2(global_cell) + Vector2(0.5, 0.5)) * TerrainRenderer.TILE_SIZE
	var cost := BuildingPiece.cost_of(piece_id)
	for item_id in cost:
		if not _item_catalog.has(item_id):
			continue
		var stack := ItemStack.new(_item_catalog.make(item_id), int(cost[item_id]))
		WorldItemBus.item_dropped.emit(stack, drop_position)

	chunk.modifications.erase(local_cell)
	_terrain_renderer.paint(_tile_map_layer, chunk, chunk_coord * CHUNK_SIZE, generator.biome_at_global)
	_remove_piece_collision(global_cell)


## The pixel-space center of the nearest modification tile matching
## `structure_id` within `max_distance` pixels of `pixel_position`, or null
## if none is loaded/in range -- has_structure_near's own boolean answer plus
## WHERE, for a caller that needs to walk there (see LogisticsMarker's own
## SEEKING/CARRYING legs, docs/concept/timber_construction.md's "Storage,
## logistics, and the autonomous dependency chain" section). Scans the same
## chunk-Chebyshev-radius-1 window has_structure_near uses, for the same
## reason (see its own doc comment) -- exact for any `max_distance` up to one
## chunk's width in pixels.
func nearest_structure_position(pixel_position: Vector2, structure_id: String, max_distance: float):
	var query_tile := Vector2i(
		floori(pixel_position.x / TerrainRenderer.TILE_SIZE), floori(pixel_position.y / TerrainRenderer.TILE_SIZE)
	)
	var center_chunk := _chunk_coord_for_tile(query_tile)
	var nearest_distance := max_distance
	var nearest: Vector2 = Vector2.ZERO
	var found := false

	for chunk_coord in chunks_in_radius(center_chunk, 1):
		var chunk: Chunk = _loaded_chunks.get(chunk_coord)
		if chunk == null:
			continue
		var origin := chunk_coord * CHUNK_SIZE
		for local_coord in chunk.modifications:
			if chunk.modifications[local_coord] != structure_id:
				continue
			var tile_global: Vector2i = origin + local_coord
			var tile_pixel := (
				Vector2(tile_global) * TerrainRenderer.TILE_SIZE
				+ Vector2.ONE * (TerrainRenderer.TILE_SIZE * 0.5)
			)
			var distance: float = pixel_position.distance_to(tile_pixel)
			if distance <= nearest_distance:
				nearest = tile_pixel
				nearest_distance = distance
				found = true
	if not found:
		return null
	return nearest


## Every matching structure's pixel-space tile center within `max_distance`
## of `pixel_position` -- the ALL-matches counterpart to
## nearest_structure_position's single-closest answer (see its own doc
## comment), reusing the exact same chunk-Chebyshev-radius-1 scan loop, just
## collecting every match instead of tracking one nearest. Closes this doc's
## own previously-named honest constraint: "a Sägewerk pairs with only its
## single nearest Storage, not every Storage within range" (see
## _resync_logistics_for_sagewerk, docs/concept/timber_construction.md's
## "Storage, logistics, and the autonomous dependency chain" section).
## nearest_structure_position itself is unchanged -- other callers (and
## LogisticsMarker's own single-storage fallback lookup) still need "just
## the closest one."
func nearby_structure_positions(pixel_position: Vector2, structure_id: String, max_distance: float) -> Array[Vector2]:
	var query_tile := Vector2i(
		floori(pixel_position.x / TerrainRenderer.TILE_SIZE), floori(pixel_position.y / TerrainRenderer.TILE_SIZE)
	)
	var center_chunk := _chunk_coord_for_tile(query_tile)
	var found: Array[Vector2] = []

	for chunk_coord in chunks_in_radius(center_chunk, 1):
		var chunk: Chunk = _loaded_chunks.get(chunk_coord)
		if chunk == null:
			continue
		var origin := chunk_coord * CHUNK_SIZE
		for local_coord in chunk.modifications:
			if chunk.modifications[local_coord] != structure_id:
				continue
			var tile_global: Vector2i = origin + local_coord
			var tile_pixel := (
				Vector2(tile_global) * TerrainRenderer.TILE_SIZE
				+ Vector2.ONE * (TerrainRenderer.TILE_SIZE * 0.5)
			)
			var distance: float = pixel_position.distance_to(tile_pixel)
			if distance <= max_distance:
				found.append(tile_pixel)
	return found


## The stock key a structure's own tile position resolves to -- position, not
## structure id, is the identity (see StructureStockStore's own doc comment:
## two structures never share a stock).
func _structure_stock_key(global_x: int, global_y: int) -> String:
	return "%d_%d" % [global_x, global_y]


## `item_id`'s count in the stock belonging to the structure at
## (global_x, global_y). 0 if nothing has ever been deposited there.
func structure_stock_at(global_x: int, global_y: int, item_id: String) -> int:
	return _structure_stocks.stock_for(_structure_stock_key(global_x, global_y)).stock_of(item_id)


## Deposits `count` of `item_id` into the stock belonging to the structure at
## (global_x, global_y) -- a Logistics worker's DEPOSITING action (see
## LogisticsMarker), or a future production building crediting its own
## accumulated output.
func deposit_to_structure_at(global_x: int, global_y: int, item_id: String, count: int) -> void:
	_structure_stocks.stock_for(_structure_stock_key(global_x, global_y)).add_stock(item_id, count)


## Withdraws `count` of `item_id` from the stock belonging to the structure at
## (global_x, global_y). All-or-nothing, mirroring StructureStock.remove_stock
## itself -- returns false (no-op) if less than `count` is present.
func withdraw_from_structure_at(global_x: int, global_y: int, item_id: String, count: int) -> bool:
	return _structure_stocks.stock_for(_structure_stock_key(global_x, global_y)).remove_stock(item_id, count)


## All chunk coordinates within `radius` chunks of center (a square/Chebyshev
## radius, not circular -- simpler, and streaming radii don't need to be exact).
func chunks_in_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			result.append(center + Vector2i(dx, dy))
	return result


## Idempotent on purpose: update()/update_with_progress() each snapshot their
## own pending set up front (chunks_in_radius / pending_load_chunks) and then
## call this per-coord across many frames (update_with_progress awaits a
## process frame between every chunk) or, for update(), across many separate
## per-frame calls on the same manager. Neither guards against a SECOND
## caller reaching the same still-pending coord before the first one's call
## here finishes -- e.g. two multiplayer peers connecting within the same
## loading window (World._on_peer_connected has no re-entrancy guard) or a
## peer joining while the host's own per-frame update() is already loading
## the same spawn-adjacent chunks. Without this guard, a re-entrant call
## regenerates the chunk from scratch and overwrites _loaded_chunks/
## _loaded_trees/_loaded_stones/etc. with a brand-new batch of spawned
## nodes -- silently leaking every node the first call already added as a
## child, never queue_free'd (see the re-entrancy test group in
## test_earth_chunk_manager.gd, right after the update_with_progress tests).
## Bailing out here, at the actual mutation point, protects every caller/
## call path at once rather than requiring each one to re-check
## is_chunk_loaded itself.
func _load_chunk(chunk_coord: Vector2i) -> void:
	if _loaded_chunks.has(chunk_coord):
		return
	var chunk := generator.generate_chunk(chunk_coord, CHUNK_SIZE)
	chunk.modifications = _chunk_serializer.load_modifications(_modifications_path(chunk_coord))
	chunk.roof_modifications = _chunk_serializer.load_modifications(_roof_modifications_path(chunk_coord))
	chunk.planted_trees = _chunk_serializer.load_planted_trees(_planted_trees_path(chunk_coord))
	_loaded_chunks[chunk_coord] = chunk
	# Withering catch-up BEFORE the first paint/collision pass below, so a
	# piece that decayed away entirely while this chunk sat unloaded is
	# already gone from chunk.modifications by the time anything paints or
	# spawns collision for it -- see _apply_piece_condition_catchup's own
	# doc comment.
	_apply_piece_condition_catchup(chunk_coord, chunk)
	_terrain_renderer.paint(_tile_map_layer, chunk, chunk_coord * CHUNK_SIZE, generator.biome_at_global)
	_paint_water_overlay(chunk_coord, chunk)
	_paint_hillshade_overlay(chunk_coord, chunk)
	_paint_river_flow_overlay(chunk_coord, chunk)
	# So a chunk streamed in mid-snowfall shows the snow already lying,
	# instead of staying bare until the next 0->nonzero transition happens
	# to paint it (see _sync_snow_presence). Gated on _snow_depth, unlike
	# the old _paint_snow_tile this replaces once painted a real per-tile
	# band regardless -- an empty layer while it is not snowing is the whole
	# point (see _sync_snow_presence's own doc comment), and a freshly
	# loaded chunk must not undo that by painting presence nobody asked for.
	if _snow_depth > 0.0:
		_paint_snow_presence(chunk_coord, chunk)
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
	) + _stone_renderer.spawn_mountain_veins(
		_entities_parent, chunk, chunk_coord * CHUNK_SIZE, TerrainRenderer.TILE_SIZE, self
	)

	# Geology (see docs/concept/geology.md): a real per-chunk topsoil/
	# regolith Strata sim, plus the surface markers for whichever cave
	# entrances this chunk's own tiles roll (sparse -- most chunks have
	# none). Strata is kept for the chunk's lifetime so a chamber
	# re-revealed later still shows real mined tunnels; only ever mutated
	# by _update_geology_reveal's spawned DiggableRock nodes.
	_topsoil_strata[chunk_coord] = Strata.new(Strata.LAYER_TOPSOIL_REGOLITH, chunk_coord * CHUNK_SIZE)
	_cave_entrance_markers[chunk_coord] = _geology_renderer.spawn_entrance_markers(
		_entities_parent, chunk_coord * CHUNK_SIZE, chunk.biome, chunk.width, chunk.height, TerrainRenderer.TILE_SIZE
	)

	_grass_sims[chunk_coord] = TallGrass.new(
		hash("%d_%d_tall_grass" % [chunk_coord.x, chunk_coord.y]), chunk.width, chunk.height, chunk.biome,
		_ground_cover_blockers(chunk)
	)
	_grass_sprites[chunk_coord] = {}
	_sync_grass_sprites(chunk_coord)

	var crop_sims := {}
	var crop_markers := {}
	for crop_id in WILD_CROP_IDS:
		var sim := WildCropPatch.new(
			crop_id, hash("%d_%d_wild_crop" % [chunk_coord.x, chunk_coord.y]),
			chunk.width, chunk.height, chunk.biome
		)
		crop_sims[crop_id] = sim
		# Already carrying the current season, so a chunk streamed in during
		# winter arrives dead-topped instead of popping in summer-green and
		# correcting itself up to GRASS_REFRESH_INTERVAL later, in plain sight.
		crop_markers[crop_id] = _wild_crop_renderer.spawn_markers(
			_entities_parent, sim, crop_id, chunk_coord * CHUNK_SIZE, TerrainRenderer.TILE_SIZE,
			_season_tint
		)
	_wild_crop_sims[chunk_coord] = crop_sims
	_wild_crop_markers[chunk_coord] = crop_markers

	_decomposer_markers[chunk_coord] = _decomposer_renderer.spawn_decomposers(
		_entities_parent, _biome_classifier.dominant_biome(chunk.biome), chunk_coord * CHUNK_SIZE,
		CHUNK_SIZE, TerrainRenderer.TILE_SIZE, hash("%d_%d_decomposers" % [chunk_coord.x, chunk_coord.y])
	)

	# Re-staff every Sägewerk this chunk already had persisted, before this
	# load, with a fresh Lumberjack -- "an NPC moves in" applies just as much
	# to a revisited worksite as a freshly-placed one (see
	# _spawn_lumberjack_for's own doc comment).
	for local_cell in chunk.modifications:
		if chunk.modifications[local_cell] == "sagewerk":
			_spawn_lumberjack_for(chunk_coord, local_cell)

	# A freshly (re)loaded chunk can bring either a Sägewerk or a Storage
	# into range of a Sägewerk that was already staffed -- re-decide every
	# currently-known Sägewerk's Logistics staffing, the same broad resync
	# _sync_logistics_workers' own "storage changed" trigger uses.
	for sagewerk_chunk_coord in _sagewerk_lumberjacks:
		for sagewerk_local_cell in _sagewerk_lumberjacks[sagewerk_chunk_coord]:
			_resync_logistics_for_sagewerk(sagewerk_chunk_coord, sagewerk_local_cell)

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

	# Ant mounds in the soil (see docs/concept/soil_fauna.md "Ants"). Not
	# rendered this pass -- see AntColony's own doc comment on scope.
	_ant_colonies[chunk_coord] = AntColony.new(
		hash("%d_%d_ants" % [chunk_coord.x, chunk_coord.y]), chunk.width, chunk.height, chunk.biome
	)

	_ecosystem.add_region(chunk_coord, chunk)
	# Robin/sparrow's food-density signal (worm burrows, ground seed cells)
	# lives in the patch instances just created above, not in Chunk data --
	# report it in immediately so this chunk's robin/sparrow population
	# bootstraps to a real equilibrium on load instead of sitting at zero
	# until the next periodic step_ecosystem tick (see
	# EcosystemSimulation.update_worm_density/update_seed_density).
	_ecosystem.update_worm_density(chunk_coord, _worm_patches[chunk_coord].worm_cells().size())
	_ecosystem.update_seed_density(
		chunk_coord,
		_grass_sims[chunk_coord].ground_seed_cells().size()
		+ _flower_patches[chunk_coord].ground_seed_cells().size()
	)
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
	_restore_growing_juveniles(chunk_coord)
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
		self,
		_ecosystem.robin_population(chunk_coord),
		_ecosystem.sparrow_population(chunk_coord)
	)
	_loaded_piscivore_birds[chunk_coord] = _piscivore_bird_renderer.spawn_piscivore_birds(
		_creatures_parent, chunk_coord, chunk, chunk_coord * CHUNK_SIZE, TerrainRenderer.TILE_SIZE, self,
		_ecosystem.kingfisher_population(chunk_coord)
	)

	# Settlement build decision (see _apply_settlement_build_decision's own
	# doc comment) runs BEFORE construction labor catch-up -- a project this
	# call decides to abandon (double-fix cancellation) or start is resolved
	# before the labor/completion sync below runs against it, not racing it.
	_apply_settlement_build_decision(chunk_coord)

	# Construction labor catch-up (see _apply_construction_labor_catchup's
	# own doc comment) -- last, so it runs against a chunk that is already
	# fully loaded (statics/collision/lumberjack/logistics wiring all
	# already in place): a completed project's own build_at_global call
	# below reuses every one of those existing sync paths rather than
	# needing a second, earlier-in-load-order variant of its own.
	_apply_construction_labor_catchup(chunk_coord)


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
		"robin_capacity": _ecosystem.robin_capacity_at(chunk_coord),
		"sparrow_capacity": _ecosystem.sparrow_capacity_at(chunk_coord),
	}
	var advanced: Dictionary = _ecology_catchup.advance(record["state"], elapsed, capacity)
	# Land health (docs/concept/world.md "Land health: overharvesting leaves a
	# lasting mark, not just a slower respawn") keeps recovering while this
	# chunk sat unloaded, at the same slow real-grounded pace loaded chunks
	# use (see ChunkEcologyCatchup.advance/VegetationGrowthModel.
	# step_land_health) -- it must NOT silently reset to pristine on reload.
	_ecosystem.seed_land_health(chunk_coord, float(advanced.get("land_health", 1.0)))
	_ecosystem.seed_populations(chunk_coord, advanced["herbivores"], advanced["predators"])
	_ecosystem.seed_fish_population(chunk_coord, advanced["fish"])
	# Robin/sparrow/kingfisher (docs/concept/ecosystem_dynamics.md's
	# "Persistence/catch-up gap, robin/sparrow/kingfisher", now resolved) --
	# same override role as seed_populations/seed_fish_population just above,
	# instead of add_region's/update_worm_density's/update_seed_density's
	# fresh seeding standing.
	_ecosystem.seed_robin_population(chunk_coord, float(advanced.get("robins", 0.0)))
	_ecosystem.seed_sparrow_population(chunk_coord, float(advanced.get("sparrows", 0.0)))
	_ecosystem.seed_kingfisher_population(chunk_coord, float(advanced.get("kingfishers", 0.0)))


# -- withering: decay as a bounded, closed-form catch-up (see
# docs/concept/timber_construction.md#withering-decay-as-a-bounded-closed-
# form-catch-up, src/gameplay/building_decay.gd) -- the direct sibling of the
# ecology catch-up immediately above, same "record unload world-time, advance
# by elapsed time on reload" shape, applied per-piece instead of per-region.

## The withering counterpart to _apply_ecology_catchup directly above:
## advances every real placed piece in `chunk` by however long this chunk
## sat unloaded, using BuildingDecay's SAME closed-form shape
## ChunkEcologyCatchup uses for vegetation. No-ops if this chunk has no
## in-session unload record (first-ever load this session, or a real app
## restart -- see Chunk.piece_condition's own "not persisted" doc comment).
##
## elapsed_days is capped at MAX_CATCHUP_DAYS, reusing the EXACT same
## constant/exchange-rate the ecology catch-up already established below --
## "a decade-unloaded structure converges to a fixed 'ruins' condition, not
## an ever-precise unbounded timer" (the doc's own framing, mirroring
## ecology's own "logistic growth converges anyway").
##
## A piece whose caught-up condition crosses BuildingDecay.
## RUINED_CONDITION_THRESHOLD feeds the EXACT SAME _collapse_piece/
## _sync_statics path a severed support does (see the "real statics"
## section further below) -- decay and a severed support are two INPUTS
## into one collapse mechanism, per the doc's own explicit framing, not two
## parallel ones.
func _apply_piece_condition_catchup(chunk_coord: Vector2i, chunk: Chunk) -> void:
	if not _unloaded_piece_condition.has(chunk_coord):
		return
	var record: Dictionary = _unloaded_piece_condition[chunk_coord]
	_unloaded_piece_condition.erase(chunk_coord)
	# No early-return on zero/negative elapsed time (e.g. an immediate
	# unload/reload flicker with no world-age passing in between): the loop
	# below still needs to run to carry `saved_condition` forward into this
	# FRESH Chunk object's own piece_condition dict, or a piece that had
	# already decayed on a PREVIOUS cycle would silently reset to 1.0 here.
	# advance_condition(..., 0.0) is exactly a no-op (exp(0) == 1), so this
	# is safe and correct either way, not just a defensive branch.
	var elapsed_seconds := maxf(0.0, _world_age_seconds - float(record["unloaded_at"]))
	var elapsed_days := minf(elapsed_seconds / REAL_SECONDS_PER_ECOLOGICAL_DAY, MAX_CATCHUP_DAYS)
	var saved_condition: Dictionary = record["condition"]
	var grid := _piece_grid_for(chunk)
	# find_rooms is O(chunk piece count) -- computed ONCE for the whole
	# chunk here and reused as a plain cell membership lookup below, rather
	# than letting _is_piece_roofed call RoomDetector.is_indoors (which
	# internally re-runs find_rooms) per neighbor per piece, which would
	# make this whole pass O(pieces^2) on a large stamped structure.
	var indoor_cells := {}
	for room in _room_detector.find_rooms(grid):
		for room_cell in room:
			indoor_cells[room_cell] = true
	var collapsed_cells: Array[Vector2i] = []

	for cell in grid:
		var piece_id: String = grid[cell]
		var starting_condition: float = float(saved_condition.get(cell, 1.0))
		var material := BuildingPiece.material_of(piece_id)
		var is_roofed := _is_piece_roofed(cell, indoor_cells)
		var owner_id: String = _household_store.owner_of(_piece_property_id(chunk_coord, cell))
		var exposure := _building_decay.exposure_for(is_roofed, owner_id)
		var new_condition := _building_decay.advance_condition(starting_condition, material, exposure, elapsed_days)
		if _building_decay.is_ruined(new_condition):
			collapsed_cells.append(cell)
		else:
			chunk.piece_condition[cell] = new_condition
			chunk.piece_condition_checked_at[cell] = _world_age_seconds

	# A cascade earlier in this SAME loop (via _sync_statics, e.g. a
	# grounding post decaying away and immediately taking an already-at-risk
	# neighbor down with it) can have already erased a LATER cell in this
	# list -- re-check chunk.modifications rather than trusting the
	# `piece_id` this cell had when the list was built, so nothing gets
	# double-collapsed/double-dropped.
	for cell in collapsed_cells:
		var piece_id: String = chunk.modifications.get(cell, "")
		if piece_id == "":
			continue
		_collapse_piece(chunk_coord, chunk, cell, piece_id)
		_sync_statics(chunk_coord, chunk, cell)


# -- construction labor catch-up (see docs/concept/timber_construction.md's
# "Unloaded / offscreen fidelity" subsection, construction_catchup.gd,
# ConstructionProjectStore.advance_project_labor) -- the settlement
# construction ledger's own real chunk-load caller: gives every real
# IN_PROGRESS ConstructionProject sited in a reloaded chunk its real elapsed
# unloaded time's worth of labor, and actually places a completed project's
# real placeable output in the world.

## Advances every real IN_PROGRESS ConstructionProject sited at `chunk_coord`
## by however long this chunk sat unloaded, mirroring _apply_ecology_catchup/
## _apply_piece_condition_catchup's own identical "no-op with no in-session
## unload record" shape directly above. builder_count is real SPARE capacity
## (SettlementSpareCapacity.for_settlement, docs/concept/timber_
## construction.md's "Deciding what to build, and who builds it" section),
## keyed off the SAME settlement_id record_settlement_founded_if_new derives
## a chunk's settlement under (EntityRef.for_settlement(chunk_coord)) -- not
## reinvented here.
##
## **Corrected (see that section's own "Spare capacity" paragraph)**: this
## used to pass `float(household_count_for_settlement(settlement_id))` --
## TOTAL population, not spare capacity, a real bug relative to that
## section's own design: construction should only ever consume population
## BEYOND what farmer/hunter/fisher require, never compete with the survival
## occupations SettlementState.carrying_capacity itself depends on. A
## settlement whose entire population works a real survival occupation now
## correctly accrues ZERO construction labor even though household_count_
## for_settlement is nonzero (see test_earth_chunk_manager.gd's own
## "construction labor only advances using spare capacity" case) -- the
## exact "population growth is what raises builder_count" throttle this
## doc's own framing names, now measuring the real thing it names.
##
## Deliberately does NOT decide which project to START -- only advances
## labor on projects that are ALREADY IN_PROGRESS. Deciding WHICH project to
## start next is _apply_settlement_build_decision's own job, called
## alongside this one from _load_chunk (see that function's own doc
## comment) -- this function stays scoped to advancing what already exists.
func _apply_construction_labor_catchup(chunk_coord: Vector2i) -> void:
	if not _unloaded_construction_labor.has(chunk_coord):
		return
	var record: Dictionary = _unloaded_construction_labor[chunk_coord]
	_unloaded_construction_labor.erase(chunk_coord)
	var elapsed := maxf(0.0, _world_age_seconds - float(record["unloaded_at"]))
	if elapsed <= 0.0:
		return

	var settlement_id := EntityRef.for_settlement(chunk_coord)
	var household_occupations := _household_occupations_for_settlement(settlement_id)
	var spare_capacity := SettlementSpareCapacity.for_settlement(
		household_count_for_settlement(settlement_id), household_occupations
	)
	var capacity := {"builder_count": float(spare_capacity)}
	for project in _construction_project_store.in_progress_projects_in_chunk(chunk_coord):
		var result: Dictionary = _construction_project_store.advance_project_labor(
			project.id, elapsed, capacity, _recipe_book, _household_store
		)
		if result.get("action", "") == "completed":
			_place_completed_construction_project(project)


## The real, live chunk-load caller for docs/concept/timber_construction.md's
## "Deciding what to build, and who builds it" section: gives a settlement
## the chance to decide WHICH project to start next (SettlementBuildDecision,
## which also composes the "double-fix cancellation" sweep), closing the gap
## _apply_construction_labor_catchup's own doc comment names ("this used to
## only ever advance real, already-reserved-material work... 'which
## structure should this settlement build next' ... remains unimplemented").
##
## Deliberately runs on EVERY real chunk load, NOT gated on
## `_unloaded_construction_labor`'s own "was there already in-progress work"
## record above -- a settlement with ZERO in-progress projects still needs a
## real chance to decide whether to START one; gating on that record would
## mean a settlement that has never yet started building could never be
## reached by this call at all. Runs BEFORE _apply_construction_labor_catchup
## (called right after this one, see the shared call site in _load_chunk) so
## a project this SAME call decides to abandon or start is resolved before
## the completed-work sync runs, not racing it.
##
## No-ops for a chunk with no real households (household_count_for_settlement
## == 0) -- an ordinary wilderness chunk has no settlement decision to make,
## and this avoids the real shortfall/structure-scan work below for the vast
## majority of chunks that are not settlements at all.
##
## **Named, honest limitation** (see docs/concept/timber_construction.md's
## own "Deciding what to build" section for the fuller account): `origin` is
## `Vector2i.ZERO` -- bookkeeping only, the SAME "not real siting" honest gap
## SettlementConstruction._handle_build_producer_first's own queued producer
## project already carries (this pass does not add a real placement/
## collision algorithm either). `household_id` is the settlement's own
## lexicographically-first household id -- deterministic, but an arbitrary
## real household to credit a communal structure's eventual property to;
## there is no real "settlement-owned" property concept yet to grant it to
## instead. And per production_shortfall_quests_for_settlement's own real,
## narrow wiring (OccupationProduction only grounds "hunter"->cooked_meat and
## "blacksmith"->stone_pickaxe today, and NEITHER recipe requires a
## structure) -- this real decision can genuinely fire (double-fix
## cancellation is real and reachable today, see test_earth_chunk_manager.gd),
## but the "start a producer project from a real detected shortfall" branch
## essentially never finds an actionable one in real play yet, honestly, the
## same "real, reachable, but rarely the lived case today" honesty this doc's
## VillageRenderer._stamp_house partial-completion entry already carries.
func _apply_settlement_build_decision(chunk_coord: Vector2i) -> void:
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	var household_ids := _households_in_settlement(settlement_id)
	if household_ids.is_empty():
		return
	household_ids.sort()

	var household_occupations := _household_occupations_for_settlement(settlement_id)
	var spare_capacity := SettlementSpareCapacity.for_settlement(household_ids.size(), household_occupations)
	var market := _market_store.market_for(settlement_id)
	var present_structure_ids := _present_structure_ids_for_settlement_chunk(chunk_coord)
	var shortfalls := production_shortfall_quests_for_settlement(settlement_id)

	SettlementBuildDecision.decide_and_advance(
		_construction_project_store, market, chunk_coord, Vector2i.ZERO, household_ids[0],
		present_structure_ids, _recipe_book, shortfalls, spare_capacity
	)


## Closes docs/concept/timber_construction.md's own previously-named gap:
## "completing a project today only marks status + grants household
## property, it never actually builds anything." If `project`'s own
## blueprint_id names a real CraftingRecipeBook recipe whose OUTPUT item is a
## real placeable (ItemCatalog.kind_of == "placeable" -- sagewerk/storage/
## campfire/furnace), places it via build_at_global at the project's own
## (chunk_coord, origin) -- the SAME call Player's own placeable-handling
## build step makes (see scenes/player.gd's _build_step), no new placement
## path. A recipe whose output is not a placeable (e.g. "log_to_balken" ->
## "beam", a plain material) is a deliberate no-op here -- the project still
## reaches real COMPLETE status and still grants its household real property
## (see complete_project), there is simply nothing to place in the world for
## a raw-material output. Does NOT invent a siting/placement algorithm --
## `project.origin` is whatever real local cell the project was started at
## (this pass's own explicit scope), exactly as the doc's "Named, honest
## limitations" already frame a queued producer project's own origin as
## "bookkeeping, not real siting."
func _place_completed_construction_project(project) -> void:
	var output: Dictionary = _recipe_book.recipe_output(project.blueprint_id)
	if output.is_empty():
		return
	var output_item_id: String = output["item_id"]
	if _item_catalog.kind_of(output_item_id) != "placeable":
		return
	var global_cell: Vector2i = project.chunk_coord * CHUNK_SIZE + project.origin
	build_at_global(global_cell.x, global_cell.y, output_item_id)


## A property_id convention for HouseholdStore.owner_of, keyed per PIECE
## CELL (global coordinates) rather than per structure -- the smallest
## honest thing available today. Grouping cells into one real per-house
## property (the doc's own "house_<chunk>_<origin>" convention) needs the
## Settlement construction ledger (ConstructionProject/
## ConstructionProjectStore), a separate, still-⬜ piece of this doc, out of
## scope here. No real caller grants property under this exact key yet, so
## this exposure branch currently always resolves to "" (unowned) in real
## play today -- it is wired to the real HouseholdStore rather than stubbed
## out, so a future caller (the settlement ledger, or a player claiming a
## specific tile with a Deed) makes it live with no changes needed here.
func _piece_property_id(chunk_coord: Vector2i, local_cell: Vector2i) -> String:
	var global_cell: Vector2i = chunk_coord * CHUNK_SIZE + local_cell
	return "house_%d_%d" % [global_cell.x, global_cell.y]


## Is `cell` (a piece in the grid `indoor_cells` was computed from) roofed
## for withering-exposure purposes? A wall/door/window cell is, by
## construction, never itself part of RoomDetector's own interior "room"
## region (it's the enclosing boundary, not the inside -- see
## RoomDetector.find_rooms' own "a wall or a door stops the fill" comment),
## so a literal indoor_cells.has(cell) would always read false for exactly
## the load-bearing pieces this doc's own "ground-contact/post-rot"
## grounding cares about most (sill rot, post rot). A piece counts as
## roofed if IT, or any orthogonal neighbor, sits inside a real enclosed
## room -- "this wall bounds a real roofed room" is the doc's actual intent
## ("why old timber buildings sit on a stone footing... and why a roof
## overhang exists at all"), not "this wall's own single cell happens to be
## the interior." A free-standing wall touching no interior anywhere stays
## exposed, exactly as it should. `indoor_cells` is every interior cell of
## every room in the chunk (Vector2i -> true), computed ONCE by the caller
## via RoomDetector.find_rooms -- see _apply_piece_condition_catchup's own
## doc comment for why this isn't a live RoomDetector.is_indoors call here.
func _is_piece_roofed(cell: Vector2i, indoor_cells: Dictionary) -> bool:
	if indoor_cells.has(cell):
		return true
	for offset in _STATICS_NEIGHBORS:
		if indoor_cells.has(cell + offset):
			return true
	return false


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

	# Withering (see _apply_piece_condition_catchup above): snapshot this
	# chunk's real per-piece condition state and the world-age it was taken
	# at, so a later revisit can catch up on the elapsed unloaded time
	# instead of the freshly (re)generated Chunk object silently defaulting
	# every piece back to full condition. In-memory only, mirroring
	# _unloaded_ecology's own unload-time record just below in spirit (not
	# persisted to disk -- see Chunk.piece_condition's own doc comment).
	if chunk != null and not chunk.modifications.is_empty():
		_unloaded_piece_condition[chunk_coord] = {
			"unloaded_at": _world_age_seconds,
			"condition": chunk.piece_condition.duplicate(),
		}

	# Construction labor catch-up (see _apply_construction_labor_catchup
	# below): snapshot the world-age this chunk was unloaded at, so a
	# revisit can advance any real IN_PROGRESS ConstructionProject sited
	# here by the real elapsed unloaded time. Only recorded when there is
	# real IN_PROGRESS work to catch up on -- mirrors _unloaded_piece_
	# condition's own "not chunk.modifications.is_empty()" guard, avoiding
	# growing this dict for every ordinary chunk unload.
	if not _construction_project_store.in_progress_projects_in_chunk(chunk_coord).is_empty():
		_unloaded_construction_labor[chunk_coord] = {"unloaded_at": _world_age_seconds}

	_terrain_renderer.erase(_tile_map_layer, CHUNK_SIZE, chunk_coord * CHUNK_SIZE)
	if _water_layer != null:
		_terrain_renderer.erase(_water_layer, CHUNK_SIZE, chunk_coord * CHUNK_SIZE)
	if _hillshade_layer != null:
		_terrain_renderer.erase(_hillshade_layer, CHUNK_SIZE, chunk_coord * CHUNK_SIZE)
	if _river_flow_layer != null:
		_terrain_renderer.erase(_river_flow_layer, CHUNK_SIZE, chunk_coord * CHUNK_SIZE)
	if _roof_layer != null:
		_terrain_renderer.erase(_roof_layer, CHUNK_SIZE, chunk_coord * CHUNK_SIZE)
	if _snow_layer != null:
		_terrain_renderer.erase(_snow_layer, CHUNK_SIZE, chunk_coord * CHUNK_SIZE)
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

	for marker in _cave_entrance_markers.get(chunk_coord, []):
		marker.free()
	_cave_entrance_markers.erase(chunk_coord)
	# Mined-tunnel state does NOT persist across an unload -- a documented
	# gap (see geology.md's Status), same class of limitation as every
	# other per-chunk sim here that isn't yet written to the modifications
	# save file. If the chamber currently revealed belongs to this chunk,
	# its nodes are about to be orphaned by the chunk unload -- free them
	# now rather than leaking, and forget the reveal.
	if _revealed_cave_entrance_tile != null and _chunk_coord_for_tile(_revealed_cave_entrance_tile) == chunk_coord:
		for node in _revealed_cave_nodes:
			if is_instance_valid(node):
				node.free()
		_revealed_cave_nodes = []
		_revealed_cave_entrance_tile = null
	_topsoil_strata.erase(chunk_coord)

	for mmi in _grass_sprites.get(chunk_coord, {}).values():
		mmi.free()
	_grass_sprites.erase(chunk_coord)
	_grass_sims.erase(chunk_coord)

	for markers_by_crop in _wild_crop_markers.get(chunk_coord, {}).values():
		for marker in markers_by_crop.values():
			marker.free()
	_wild_crop_markers.erase(chunk_coord)
	_wild_crop_sims.erase(chunk_coord)

	for marker in _decomposer_markers.get(chunk_coord, []):
		marker.free()
	_decomposer_markers.erase(chunk_coord)

	for marker in _sagewerk_lumberjacks.get(chunk_coord, {}).values():
		marker.free()
	_sagewerk_lumberjacks.erase(chunk_coord)

	for by_storage in _logistics_workers.get(chunk_coord, {}).values():
		for by_item in by_storage.values():
			for marker in by_item.values():
				marker.free()
	_logistics_workers.erase(chunk_coord)
	# This chunk may have held the Storage (or Sägewerk) a worker elsewhere
	# was paired against -- re-decide every REMAINING known Sägewerk's
	# Logistics staffing now that this chunk's own structures are gone,
	# mirroring _load_chunk's own identical broad resync on the way in.
	for sagewerk_chunk_coord in _sagewerk_lumberjacks:
		for sagewerk_local_cell in _sagewerk_lumberjacks[sagewerk_chunk_coord]:
			_resync_logistics_for_sagewerk(sagewerk_chunk_coord, sagewerk_local_cell)

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

	_ant_colonies.erase(chunk_coord)

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
				"land_health": _ecosystem.land_health(chunk_coord),
				# Robin/sparrow/kingfisher parity with herbivore/predator/fish
				# (docs/concept/ecosystem_dynamics.md's "Persistence/catch-up
				# gap, robin/sparrow/kingfisher", now resolved).
				"robins": _ecosystem.robin_population(chunk_coord),
				"sparrows": _ecosystem.sparrow_population(chunk_coord),
				"kingfishers": _ecosystem.kingfisher_population(chunk_coord),
			},
		}
		DirAccess.make_dir_recursive_absolute(FISH_POPULATION_DIR)
		_chunk_serializer.save_fish_population(fish_population, _fish_population_path(chunk_coord))
		# ...and the land with it, stamped in WALL-CLOCK time so a revisit
		# tomorrow can advance the region by however long the player was
		# actually away (see _apply_persisted_ecology). Land health is saved
		# alongside it (docs/concept/world.md "Land health: overharvesting
		# leaves a lasting mark, not just a slower respawn") -- this is
		# exactly the kind of lasting change that must survive a real
		# restart, not just an in-session unload/reload. Robin/sparrow/
		# kingfisher are saved alongside it for the same reason.
		DirAccess.make_dir_recursive_absolute(ECOLOGY_DIR)
		_chunk_serializer.save_ecology(
			{
				"herbivores": _ecosystem.herbivore_population(chunk_coord),
				"predators": _ecosystem.predator_population(chunk_coord),
				"vegetation": _ecosystem.average_vegetation_density(chunk_coord),
				"land_health": _ecosystem.land_health(chunk_coord),
				"saved_at_unix": Time.get_unix_time_from_system(),
				"robins": _ecosystem.robin_population(chunk_coord),
				"sparrows": _ecosystem.sparrow_population(chunk_coord),
				"kingfishers": _ecosystem.kingfisher_population(chunk_coord),
			},
			_ecology_path(chunk_coord)
		)

	# The player's own animals are kept individually, not as a number in the
	# region's population (see KeptAnimals) -- a tamed horse is a particular
	# animal in a particular place, not an interchangeable head of livestock.
	_save_kept_animals(chunk_coord)
	# A wild juvenile's own growth-in-progress is a DIFFERENT reason to keep
	# an individual (see GrowingJuveniles) -- nobody tamed or tied it, it
	# simply is not grown yet, and its real 30-180 real-day maturity window
	# (see MammalGrowth) is almost certainly longer than this chunk stays
	# loaded.
	_save_growing_juveniles(chunk_coord)

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
			"land_health": float(saved.get("land_health", 1.0)),
			"robins": float(saved.get("robins", 0.0)),
			"sparrows": float(saved.get("sparrows", 0.0)),
			"kingfishers": float(saved.get("kingfishers", 0.0)),
		},
		elapsed,
		{
			"herbivore_capacity": _ecosystem.herbivore_capacity_at(chunk_coord),
			"fruit_growth_rate": 0.0,
			"fish_capacity": _ecosystem.fish_capacity_at(chunk_coord),
			"robin_capacity": _ecosystem.robin_capacity_at(chunk_coord),
			"sparrow_capacity": _ecosystem.sparrow_capacity_at(chunk_coord),
		}
	)
	_ecosystem.seed_populations(
		chunk_coord,
		float(caught_up.get("herbivores", 0.0)),
		float(caught_up.get("predators", 0.0))
	)
	# Land health (docs/concept/world.md "Land health: overharvesting leaves a
	# lasting mark, not just a slower respawn") -- restores the real persisted
	# value (recovered by however long the player was genuinely away) instead
	# of leaving add_region's fresh-pristine seeding stand, the same override
	# seed_populations does for herbivores/predators just above.
	_ecosystem.seed_land_health(chunk_coord, float(caught_up.get("land_health", 1.0)))
	# Robin/sparrow/kingfisher parity (docs/concept/ecosystem_dynamics.md's
	# "Persistence/catch-up gap, robin/sparrow/kingfisher", now resolved) --
	# same override role as seed_populations/seed_land_health just above.
	_ecosystem.seed_robin_population(chunk_coord, float(caught_up.get("robins", 0.0)))
	_ecosystem.seed_sparrow_population(chunk_coord, float(caught_up.get("sparrows", 0.0)))
	_ecosystem.seed_kingfisher_population(chunk_coord, float(caught_up.get("kingfishers", 0.0)))
	# Fish parity: the raw last-known count was already installed (by the
	# load_fish_population call at this function's own call site, before this
	# runs), but `advance()` above steps it forward for the elapsed away-time
	# exactly like every population above -- without this call that advanced
	# value was computed and then silently discarded, so a fish population
	# left under capacity across a real session gap came back frozen at its
	# pre-gap value instead of catching up like everything else does.
	_ecosystem.seed_fish_population(chunk_coord, float(caught_up.get("fish", 0.0)))


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
			"wander_seed": creature.wander_seed,
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
			self, TerrainRenderer.TILE_SIZE, int(record.get("wander_seed", -1))
		)
		if creature == null:
			continue
		creature.restore_taming(
			float(record["trust"]), int(record["order"]),
			bool(record["is_tied"]), record["tied_to"]
		)
		_loaded_creatures[chunk_coord].append(creature)


func _growing_juveniles_path(chunk_coord: Vector2i) -> String:
	return "%s/%d_%d.bin" % [GROWING_JUVENILES_DIR, chunk_coord.x, chunk_coord.y]


## Saves the WILD juveniles standing in this chunk that are not yet fully
## grown, and returns how many. See GrowingJuveniles' own doc comment for why
## this bounded set does not reopen KeptAnimals' "no unbounded per-animal
## saves" rule.
##
## A creature already worth keeping by KeptAnimals (tamed or tied) is
## deliberately EXCLUDED here, so the same individual is never saved -- and
## so never re-spawned -- by both this and _save_kept_animals at once (see
## GrowingJuveniles' own doc comment on this exact trade-off).
##
## Written on every unload including an empty list, so a juvenile that grew
## up (or died) since the last unload does not linger in the file forever.
func _save_growing_juveniles(chunk_coord: Vector2i) -> int:
	var growing: Array = []
	for creature in _loaded_creatures.get(chunk_coord, []):
		if not is_instance_valid(creature) or creature.info == null:
			continue
		if KeptAnimals.is_worth_keeping(float(creature.trust), creature.is_tied_up()):
			continue
		if not GrowingJuveniles.is_worth_persisting(creature.age_seconds, creature.info.species):
			continue
		growing.append({
			"species": creature.info.species,
			"position": creature.position,
			"age_seconds": creature.age_seconds,
			"wander_seed": creature.wander_seed,
		})
	DirAccess.make_dir_recursive_absolute(GROWING_JUVENILES_DIR)
	GrowingJuveniles.save_all(growing, _growing_juveniles_path(chunk_coord))
	return growing.size()


## Re-spawns this chunk's still-growing wild juveniles, ON TOP of whatever
## the aggregate says the region holds -- same "deliberately extra" shape as
## _restore_kept_animals, for the same reason: carrying capacity governs an
## ordinary wild population, and a specific juvenile already being tracked
## individually must not be silently absorbed back into it.
##
## Restores the SAME individual, not a fresh one: `wander_seed` is passed
## through to spawn_single exactly like _restore_kept_animals does, and
## `age_seconds` is set directly afterward -- CreatureMarker's own
## `_apply_action_scale` re-derives the rendered growth scale from
## `age_seconds` every frame regardless of how it got set, so no separate
## "resume growing" call is needed here.
func _restore_growing_juveniles(chunk_coord: Vector2i) -> void:
	var growing := GrowingJuveniles.load_all(_growing_juveniles_path(chunk_coord))
	if growing.is_empty():
		return
	for record in growing:
		var creature := _creature_renderer.spawn_single(
			_creatures_parent, String(record["species"]), record["position"],
			self, TerrainRenderer.TILE_SIZE, int(record.get("wander_seed", -1))
		)
		if creature == null:
			continue
		creature.age_seconds = float(record["age_seconds"])
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
