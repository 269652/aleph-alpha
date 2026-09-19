extends RefCounted

const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const HydrologyField = preload("res://src/world/hydrology_field.gd")
const RiverCatalog = preload("res://src/world/river_catalog.gd")
const StonePlacement = preload("res://src/world/stone_placement.gd")
const StoneSize = preload("res://src/world/stone_size.gd")
const GroundSlide = preload("res://src/gameplay/ground_slide.gd")
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
const BoulderHydraulics = preload("res://src/world/boulder_hydraulics.gd")
## The dropped boulder piece and an ore rock have no stone roll to size
## them; they are the smashable stone's default size (SmashableStone
## diameter_cm), the boulder the player already knows.
const DROPPED_BOULDER_DIAMETER_CM := 60.0

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
const IllustratedWheatPatch = preload("res://src/rendering/illustrated_wheat_patch.gd")
const FlowerPatch = preload("res://src/world/flower_patch.gd")
const SeedDispersal = preload("res://src/world/seed_dispersal.gd")
const SeedCaching = preload("res://src/gameplay/seed_caching.gd")
const SquirrelNutCaching = preload("res://src/gameplay/squirrel_nut_caching.gd")
const ScentField = preload("res://src/world/scent_field.gd")
const ProceduralFlowerSprite = preload("res://src/rendering/procedural_flower_sprite.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const ProceduralSeedSprite = preload("res://src/rendering/procedural_seed_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const WildCropPatch = preload("res://src/world/wild_crop_patch.gd")
const WildCropRenderer = preload("res://src/rendering/wild_crop_renderer.gd")
const WildMushroomPatch = preload("res://src/world/wild_mushroom_patch.gd")
const WaterProximity = preload("res://src/world/water_proximity.gd")
const MushroomRenderer = preload("res://src/rendering/mushroom_renderer.gd")
const MushroomFlush = preload("res://src/world/mushroom_flush.gd")
const FarmPlotMarker = preload("res://src/rendering/farm_plot_marker.gd")
const DecomposerRenderer = preload("res://src/rendering/decomposer_renderer.gd")
const CaterpillarRenderer = preload("res://src/rendering/caterpillar_renderer.gd")
const MillipedeRenderer = preload("res://src/rendering/millipede_renderer.gd")
const GrassFrogRenderer = preload("res://src/rendering/grass_frog_renderer.gd")
const GrassFrogMarker = preload("res://src/rendering/grass_frog_marker.gd")
const LumberjackMarker = preload("res://src/rendering/lumberjack_marker.gd")
const ProceduralBuildingPieceSprite = preload("res://src/rendering/procedural_building_piece_sprite.gd")
const LogisticsMarker = preload("res://src/rendering/logistics_marker.gd")
const StructureStockStore = preload("res://src/emergence/structure_stock_store.gd")
const IllustratedStructureSprite = preload("res://src/rendering/illustrated_structure_sprite.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const InteriorTemplates = preload("res://src/gameplay/interior_templates.gd")
const ProceduralBuildingPlaceholderSprite = preload("res://src/rendering/procedural_building_placeholder_sprite.gd")
const FarmerMarker = preload("res://src/rendering/farmer_marker.gd")
const MillMarker = preload("res://src/rendering/mill_marker.gd")
const BakeryMarker = preload("res://src/rendering/bakery_marker.gd")
const SettlementDemand = preload("res://src/emergence/settlement_demand.gd")

## How much of a tile a ground-cover tuft (grass, scrub, lichen) covers.
## Well under 1: a clump of grass sits ON the ground, it is not the ground.
const TUFT_WORLD_SCALE := 0.5
const DesertScrub = preload("res://src/world/desert_scrub.gd")
const ProceduralScrubSprite = preload("res://src/rendering/procedural_scrub_sprite.gd")
const TundraLichen = preload("res://src/world/tundra_lichen.gd")
const ProceduralLichenSprite = preload("res://src/rendering/procedural_lichen_sprite.gd")
const EarthwormPatch = preload("res://src/world/earthworm_patch.gd")
const CrushMechanic = preload("res://src/world/crush_mechanic.gd")
const IllustratedWormSprite = preload("res://src/rendering/illustrated_worm_sprite.gd")
const WormMarker = preload("res://src/rendering/worm_marker.gd")
const AquaticVegetation = preload("res://src/world/aquatic_vegetation.gd")
const ProceduralAquaticVegetationSprite = preload("res://src/rendering/procedural_aquatic_vegetation_sprite.gd")
const AquaticInvertebrates = preload("res://src/world/aquatic_invertebrates.gd")
const ProceduralAquaticInvertebrateSprite = preload("res://src/rendering/procedural_aquatic_invertebrate_sprite.gd")
const AntColony = preload("res://src/world/ant_colony.gd")
const AntMoundMarker = preload("res://src/rendering/ant_mound_marker.gd")
const AntForagerMarker = preload("res://src/rendering/ant_forager_marker.gd")
const BeeColony = preload("res://src/world/bee_colony.gd")
const BeeHiveMarker = preload("res://src/rendering/bee_hive_marker.gd")
const BeeForagerMarker = preload("res://src/rendering/bee_forager_marker.gd")
const WildBeePatch = preload("res://src/world/wild_bee_patch.gd")
const WildBeeNestMarker = preload("res://src/rendering/wild_bee_nest_marker.gd")
const CicadaPopulation = preload("res://src/world/cicada_population.gd")
const CicadaMarker = preload("res://src/rendering/cicada_marker.gd")
const LeafLitterField = preload("res://src/world/leaf_litter_field.gd")
const LeafLitterRenderer = preload("res://src/rendering/leaf_litter_renderer.gd")
const FootstepGait = preload("res://src/gameplay/footstep_gait.gd")
const FootprintField = preload("res://src/world/footprint_field.gd")
const FootprintRenderer = preload("res://src/rendering/footprint_renderer.gd")
const GroundImprint = preload("res://src/world/ground_imprint.gd")
const CreatureMass = preload("res://src/world/creature_mass.gd")
const SimulationSettings = preload("res://src/gameplay/simulation_settings.gd")

## The player's own simulation-density knobs (SimulationSettings, docs/
## concept/ecosystem_dynamics.md "Simulation density"), one fraction per
## knob, read by the ant and bee forager dispatch gates and the pollinator
## spawn/offspring budgets. World loads and applies them (see World.
## _apply_simulation_settings); a knob never culls what is already alive,
## it only gates new dispatches and spawns.
var _population_density: Dictionary = SimulationSettings.default_densities()


func set_population_density(knob: String, density: float) -> void:
	if not SimulationSettings.KNOBS.has(knob):
		return
	_population_density[knob] = SimulationSettings.sanitize_density(density)


func population_density(knob: String) -> float:
	return float(_population_density.get(knob, SimulationSettings.DEFAULT_DENSITY))
const PebbleDispersion = preload("res://src/rendering/pebble_dispersion.gd")
const ForageClaims = preload("res://src/gameplay/forage_claims.gd")
const WindSway = preload("res://src/rendering/wind_sway.gd")
const WaterShader = preload("res://src/rendering/water_shader.gd")
const HillshadeShader = preload("res://src/rendering/hillshade_shader.gd")
const EntityHillshadeShader = preload("res://src/rendering/entity_hillshade_shader.gd")
const RiverFlowShader = preload("res://src/rendering/river_flow_shader.gd")
const CreatureRenderer = preload("res://src/rendering/creature_renderer.gd")
const FishRenderer = preload("res://src/rendering/fish_renderer.gd")
const AmbientFlyerRenderer = preload("res://src/rendering/ambient_flyer_renderer.gd")
const FlyerPersonality = preload("res://src/gameplay/flyer_personality.gd")
const PiscivoreBirdRenderer = preload("res://src/rendering/piscivore_bird_renderer.gd")
const VillageRenderer = preload("res://src/rendering/village_renderer.gd")
const VillageFarm = preload("res://src/gameplay/village_farm.gd")
const VillagePond = preload("res://src/gameplay/village_pond.gd")
const AquaticPopulationModel = preload("res://src/world/aquatic_population_model.gd")
const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const EcosystemSimulation = preload("res://src/world/ecosystem_simulation.gd")
const ChunkSerializer = preload("res://src/world/chunk_serializer.gd")
const ForageScheduler = preload("res://src/gameplay/forage_scheduler.gd")
const TreeSpread = preload("res://src/gameplay/tree_spread.gd")
const FruitFall = preload("res://src/world/fruit_fall.gd")
const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
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
const NpcSeenLedger = preload("res://src/dialogue/npc_seen_ledger.gd")
const Market = preload("res://src/emergence/market.gd")
const MarketStore = preload("res://src/emergence/market_store.gd")
const Shop = preload("res://src/gameplay/shop.gd")
const MarketStorePersistence = preload("res://src/emergence/market_store_persistence.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")
const ConstructionProject = preload("res://src/emergence/construction_project.gd")
const ConstructionProjectStore = preload("res://src/emergence/construction_project_store.gd")
const HouseBlueprint = preload("res://src/gameplay/house_blueprint.gd")
const SettlementSpareCapacity = preload("res://src/emergence/settlement_spare_capacity.gd")
const NpcProduction = preload("res://src/world/npc_production.gd")
const FurniturePlacement = preload("res://src/gameplay/furniture_placement.gd")
const SettlementBuildDecision = preload("res://src/emergence/settlement_build_decision.gd")
const CivicBuildDecision = preload("res://src/emergence/civic_build_decision.gd")
const SettlementConstruction = preload("res://src/emergence/settlement_construction.gd")
const VillageGrowth = preload("res://src/emergence/village_growth.gd")
const VillageCensus = preload("res://src/emergence/village_census.gd")
const VillageImmigration = preload("res://src/emergence/village_immigration.gd")
const MerchantVisit = preload("res://src/emergence/merchant_visit.gd")
const HouseholdWellbeing = preload("res://src/emergence/household_wellbeing.gd")
const ConstructionLabor = preload("res://src/emergence/construction_labor.gd")
const SettlementReserve = preload("res://src/emergence/settlement_reserve.gd")
const VillageLayout = preload("res://src/world/village_layout.gd")
const Institution = preload("res://src/emergence/institution.gd")
const InstitutionStore = preload("res://src/emergence/institution_store.gd")
const InstitutionStorePersistence = preload("res://src/emergence/institution_store_persistence.gd")
const InstitutionFormation = preload("res://src/emergence/institution_formation.gd")
const PlayerIdentity = preload("res://src/emergence/player_identity.gd")
const SettlementState = preload("res://src/emergence/settlement_state.gd")
const SettlementFood = preload("res://src/emergence/settlement_food.gd")
const SettlementGathering = preload("res://src/emergence/settlement_gathering.gd")
const SettlementGranary = preload("res://src/emergence/settlement_granary.gd")
const OccupationProduction = preload("res://src/emergence/occupation_production.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const SettlementTier = preload("res://src/emergence/settlement_tier.gd")
const WorldBoss = preload("res://src/emergence/world_boss.gd")
const WorldBossStore = preload("res://src/emergence/world_boss_store.gd")
const WorldBossStorePersistence = preload("res://src/emergence/world_boss_store_persistence.gd")
const ConstructionProjectStorePersistence = preload("res://src/emergence/construction_project_store_persistence.gd")
const WorldBossFitness = preload("res://src/gameplay/world_boss_fitness.gd")
const NpcEncounter = preload("res://src/emergence/npc_encounter.gd")
const Quest = preload("res://src/emergence/quest.gd")
const Governance = preload("res://src/emergence/governance.gd")
const NpcEconomy = preload("res://src/world/npc_economy.gd")
const RegionalTrade = preload("res://src/emergence/regional_trade.gd")
const CaravanTrip = preload("res://src/emergence/caravan_trip.gd")
const CaravanRaid = preload("res://src/emergence/caravan_raid.gd")
const CaravanMarker = preload("res://src/rendering/caravan_marker.gd")
const PathScarring = preload("res://src/world/path_scarring.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const VillageMarket = preload("res://src/world/village_market.gd")
const WorldClockPersistence = preload("res://src/world/world_clock_persistence.gd")
const SnowBombShader = preload("res://src/rendering/snow_bomb_shader.gd")
const RoofShape = preload("res://src/rendering/roof_shape.gd")
const PickableSeed = preload("res://src/rendering/pickable_seed.gd")
const SnowTrail = preload("res://src/world/snow_trail.gd")
const Snowfall = preload("res://src/world/snowfall.gd")
const SeasonTransition = preload("res://src/world/season_transition.gd")
const SeasonalFoliage = preload("res://src/rendering/seasonal_foliage.gd")
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

## Where furniture pieces are persisted (see Chunk.furniture_modifications, docs/concept/housing.md) -- the same generic Dictionary save/load ChunkSerializer already uses for `modifications`/`roof_modifications`, just its own directory since furniture shares its cell with the floor beneath it.
const FURNITURE_MODIFICATIONS_DIR := "user://chunk_furniture_modifications"

## Where a two-story house's upper storey is persisted (see Chunk.upper_floor_modifications, docs/concept/housing.md's "Two-story houses" section) -- the same generic Dictionary save/load ChunkSerializer already uses for `modifications`/`roof_modifications`/`furniture_modifications`, just its own directory since it shares its cell with the ground floor beneath it.
const UPPER_FLOOR_MODIFICATIONS_DIR := "user://chunk_upper_floor_modifications"

## Where the upper floor's OWN furniture is persisted (see Chunk.
## upper_floor_furniture_modifications, docs/concept/housing.md's
## "Interior furniture" section) -- the same generic save/load every
## other modification dict already uses, its own directory for the same
## reason FURNITURE_MODIFICATIONS_DIR itself has one.
const UPPER_FLOOR_FURNITURE_MODIFICATIONS_DIR := "user://chunk_upper_floor_furniture_modifications"

## Where whole-building entity records are persisted (see Chunk.buildings,
## docs/concept/building.md "Buildings are entities; interiors are
## scenes") -- the same generic Dictionary save/load ChunkSerializer
## already uses for every other modification layer; a building's anchor id
## and footprint markers live in `modifications` itself (see
## BuildingCatalog.FOOTPRINT_TILE_ID) and need no separate file, this one
## carries the rest of a building's own state (facing/seed/condition/
## progress/owner).
const BUILDINGS_DIR := "user://chunk_buildings"

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

## Fallen leaves are no longer a real Item/ItemStack (see
## docs/concept/leaf_litter.md) -- step_fruiting's own leaf-fall block below
## adds a LeafLitterField record (species id + season) directly, with no
## display-name/kind/max_stack table needed: litter is never inventoried,
## inspected, or hover-named, so that data (this table used to carry it --
## "Cherry Leaf", "Oak Leaf", "Pine Needles" for pine's needles specifically,
## kind "material" since litter does not spoil the way a dropped nut does)
## has no consumer left to serve. See git history for the removed
## _LEAF_ITEMS table if a future feature needs it back (e.g. a litter
## tooltip).

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
var _caterpillar_renderer := CaterpillarRenderer.new()
var _millipede_renderer := MillipedeRenderer.new()
var _grass_frog_renderer := GrassFrogRenderer.new()
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
## The most recent real sun elevation pushed in by set_sun_position below --
## a settlement chunk streaming in later (see _load_chunk's own
## spawn_village call) reads this to decide whether its houses' windows
## light up for the night (VillageRenderer.is_night, docs/concept/
## housing.md#night-lighting-ambient), rather than a second, independently
## -computed elevation. Starts at bright daylight, the same "nothing pinned
## yet" default spawn_village itself falls back to.
var _current_sun_elevation_deg := VillageRenderer.DEFAULT_SUN_ELEVATION_DEG
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
## See CicadaPopulation/CicadaMarker (docs/concept/creature_and_footstep_
## audio.md's "Cicadas" section) -- one CicadaMarker per real tree that
## rolled a hit this chunk load, tree-anchored the same way _loaded_trees
## itself is keyed.
var _cicada_markers: Dictionary = {}  # Vector2i chunk_coord -> Array[Node2D]

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


## `node` is deliberately UNTYPED, and that is the whole of a crash reported
## live in the middle of play:
##
##   Invalid type in function '_append_if_near' ... The Object-derived class
##   of argument 2 (previously freed) is not a subclass of the expected
##   argument class.
##     at: solid_obstacles_near   [1] _blockers_near (creature_marker.gd)
##
## A felled tree stays in _loaded_trees after it frees itself (choppable_
## tree.gd calls queue_free() while leaving the entry in the array -- see
## _clear_vegetation_on_cells' own note). The is_instance_valid guard below
## was always here, as the first line; but GDScript type-checks a declared
## `node: Node` parameter at the CALL, and a freed object fails that check
## before the body is ever entered. A guard behind a type annotation that
## rejects exactly the value it guards against cannot run.
##
## Worse than a log line: the failed call aborted the whole sensing pass, so
## every obstacle AFTER the dead one went unseen and creatures walked
## through standing trees.
func _append_if_near(result: Array, node, at: Vector2, radius: float) -> void:
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
## The SECOND, "turning into" season's mesh per band, ONLY populated for a
## band currently mid-transition (see sync_grass_season/_sync_grass_sprites
## and docs/concept/long_grass.md's "Seasonal art") -- a settled season
## (no active transition, the common case) leaves this empty entirely, so
## the ordinary single-mesh-per-band draw-call cost this system was built
## around is untouched outside a transition's own brief window.
var _grass_sprites_turning: Dictionary = {}  # Vector2i chunk_coord -> {band index int -> MultiMeshInstance2D}
## The live season state _sync_grass_sprites reads to pick which of the four
## grass_blades_*.png sheets (and, mid-transition, which SECOND sheet) a
## band's cards sample from -- kept as fields rather than re-derived inside
## _sync_grass_sprites itself so a chunk load and a season change both drive
## the exact same rendering path. Updated only by sync_grass_season.
var _grass_season_name := SeasonalFoliage.FALLBACK_SEASON
var _grass_turning_into := SeasonalFoliage.FALLBACK_SEASON
var _grass_turn_progress := 0.0
## The grass season the loaded fields were last drawn for -- see
## sync_grass_season, mirroring _last_tree_season exactly.
var _last_grass_season := ""
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

## Wild mushrooms (see docs/concept/mushrooms.md). One WildMushroomPatch per
## chunk covering all 5 species together -- see that class's own doc
## comment for why this does NOT mirror wild crops' one-sim-per-crop
## territory partition. chunk_coord -> WildMushroomPatch.
var _mushroom_sims: Dictionary = {}
## chunk_coord -> {Vector2i cell -> MushroomMarker}.
var _mushroom_markers: Dictionary = {}
var _mushroom_refresh_accumulator := 0.0
var _mushroom_renderer := MushroomRenderer.new()

## Player-tilled farm plots (docs/concept/farming.md's "farming loop") --
## flat and NOT chunk-scoped, unlike wild crops: a farm plot is a single,
## independent, player-placed instance (see FarmPlotMarker's own doc
## comment for why it owns its FarmPlot directly rather than through a
## per-chunk sim class), so one Dictionary keyed by the plot's own global
## tile is enough. Vector2i global tile -> FarmPlotMarker.
var _farm_plots: Dictionary = {}

## Ants/carrion bugs (see docs/concept/carrion.md). chunk_coord -> Array of
## DecomposerMarker -- no per-chunk sim needed (unlike wild crops/grass),
## since a decomposer's whole behavior lives on the marker itself and it
## queries the Carcass/CarcassGuts groups directly.
var _decomposer_markers: Dictionary = {}
## Vector2i chunk_coord -> Array[CaterpillarMarker], same per-chunk-array
## shape as _decomposer_markers immediately above, for the same reason: a
## caterpillar's whole behaviour lives on the marker itself.
var _caterpillar_markers: Dictionary = {}
## Vector2i chunk_coord -> Array[MillipedeMarker], same per-chunk-array
## shape as _caterpillar_markers immediately above, for the same reason
## (see docs/concept/soil_fauna.md "Millipedes: a dedicated autumn
## leaf-litter decomposer").
var _millipede_markers: Dictionary = {}
## Vector2i chunk_coord -> Array[GrassFrogMarker], same per-chunk-array
## shape as _caterpillar_markers/_millipede_markers immediately above, for
## the same reason (see docs/concept/seasonal_behavior.md's phase 10,
## "Grass frog: new species, brumating, decorative-but-real").
var _grass_frog_markers: Dictionary = {}

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

## Real illustrated-art overlay Sprite2D per placed structure this codebase
## has real art for (see IllustratedStructureSprite -- farm/sagewerk/
## storage/wooden_fence today, docs/concept/npc_farm_production.md).
## chunk_coord -> {local_cell -> Sprite2D}. Purely visual: the underlying
## ground tile is unchanged (bare earth, same as any other prop-bearing
## tile -- a tree or mushroom doesn't change its own ground tile either).
## Every other placeable (campfire/furnace/stone_dam) has no real art wired
## yet and keeps rendering via its existing baked-into-the-tile-atlas
## ProceduralStructureSprite look, unaffected by this dict.
var _structure_art_sprites: Dictionary = {}
var _illustrated_structure_sprite := IllustratedStructureSprite.new()
var _building_placeholder_sprite := ProceduralBuildingPlaceholderSprite.new()

## Every placed Farm currently staffed with a real FarmerMarker (see
## docs/concept/npc_farm_production.md) -- chunk_coord -> {local_cell ->
## FarmerMarker}, mirroring _sagewerk_lumberjacks' own shape exactly. Unlike
## the Sagewerk, a placed "farm" tile does NOT automatically get a Farmer:
## reported directly, "buildings like the farm require a fence and then an
## NPC can get hired" -- staffing is gated on a real "wooden_fence" standing
## within FARM_FENCE_GATE_RADIUS_TILES (see _reconcile_farmer_at).
var _farm_farmers: Dictionary = {}

## The Mill's Miller and the Bakery's Baker (docs/concept/milling_and_
## baking.md): every placed conversion structure currently staffed with its
## own StructureConversionMarker -- chunk_coord -> {local_cell -> marker},
## the SAME shape as _sagewerk_lumberjacks/_farm_farmers, one dict for both
## trades since they differ only in which marker class moves in (see
## CONVERSION_WORKER_BY_STRUCTURE). Staffed unconditionally the moment the
## tile exists, like the Sägewerk (no fence gate -- a quern-house and a
## bakehouse need no plot to protect).
var _conversion_workers: Dictionary = {}
const CONVERSION_WORKER_BY_STRUCTURE := {"mill": MillMarker, "bakery": BakeryMarker}

## Hauling between the bread chain's links (docs/concept/milling_and_
## baking.md, "Hauling between the links"): each leg is (source structure,
## item ids, destination structure), worked by the SAME LogisticsMarker
## the Sägewerk/Farm -> Storage pairing already uses, with a consumer as its
## destination. Wheat reaches the Mill both straight from a Farm and out
## of any Storage it was hauled into first (the existing Farm -> Storage
## pairing keeps running; two haulers on one Farm simply race, the loser
## aborting its pickup -- see LogisticsMarker), so no wheat is ever
## stranded in a Storage the Mill can't see. A leg is only staffed while
## its source is: a Farm with a Farmer, a Mill/Bakery with its worker, a
## Storage by existing at all.
const CHAIN_LOGISTICS_LEGS := [
	{"source": "farm", "items": ["wheat"], "destination": "mill"},
	{"source": "storage", "items": ["wheat"], "destination": "mill"},
	{"source": "mill", "items": ["flour"], "destination": "bakery"},
	{"source": "bakery", "items": ["bread"], "destination": "storage"},
]

## chunk_coord -> {source_local_cell -> {destination_id -> {destination_
## pairing_key -> {item_id -> LogisticsMarker}}}}: _logistics_workers' own
## shape with one more level (the destination KIND) so each leg's pairs are
## pruned independently -- a Farm's Mill legs and its Storage legs (kept in
## _logistics_workers) must never prune each other.
var _chain_logistics_workers: Dictionary = {}

## How far (in tiles) a wooden_fence must stand from a Farm for a Farmer to
## move in. Matches SAGEWERK_STORAGE_PAIR_RADIUS_TILES' own magnitude --
## "the same worksite," not a farm-specific number invented separately.
const FARM_FENCE_GATE_RADIUS_TILES := SAGEWERK_STORAGE_PAIR_RADIUS_TILES

## Which real items a Farm's Logistics worker gets spawned for -- today's
## only real Farm output (see FarmerMarker.CROP_ID), matching
## _SAGEWERK_LOGISTICS_ITEM_IDS' own one-list-per-producer shape.
const _FARM_LOGISTICS_ITEM_IDS := ["wheat"]

## How far (in tiles) a real "city_hall" must stand from a query point for
## city_hall_demands_near to answer at all. Matches SAGEWERK_STORAGE_
## PAIR_RADIUS_TILES' own magnitude -- "the same settlement," not a
## City-Hall-specific number invented separately.
const CITY_HALL_DEMAND_RADIUS_TILES := SAGEWERK_STORAGE_PAIR_RADIUS_TILES

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
var _worm_sprite_generator := IllustratedWormSprite.new()

## How often the "crawl" cycle and the "die" squash advance a frame -- see
## _worm_texture_for. Pinned separately (not reused from WORM_REFRESH_
## INTERVAL, which throttles sprite CREATION/REMOVAL on a weather
## timescale, an unrelated concern): a worm's own body should visibly
## step through its walk cycle at an ordinary creature-animation pace,
## not once every 5 real seconds.
const WORM_CRAWL_FRAME_SECONDS := 0.2
## Chosen so the whole 8-frame squash plays out in 1.6s -- a quick,
## legible reaction, comfortably shorter than the RECOVERY_SECONDS (45s)
## window the corpse then lies there afterward holding the last frame.
const WORM_DEATH_FRAME_SECONDS := 0.2
## Vector2i chunk_coord -> AquaticVegetation, and the Sprite2D per real
## vegetation cell (see step_aquatic_vegetation/_sync_aquatic_vegetation_
## sprites, docs/concept/aquatic_foraging.md). Only chunks that actually
## contain water get an entry -- the same "don't allocate a sim for a
## chunk with nothing for it to do" discipline EarthwormPatch's own
## soil-biome gate already uses.
var _aquatic_vegetation: Dictionary = {}
var _aquatic_vegetation_sprites: Dictionary = {}
var _aquatic_vegetation_sprite_generator := ProceduralAquaticVegetationSprite.new()
var _aquatic_vegetation_refresh_accumulator := 0.0
## The second real aquatic food layer (see docs/concept/aquatic_foraging.md's
## "Revised (2026-09-07)") -- mirrors _aquatic_vegetation's own exact shape
## and gate, seeded alongside it in the same water-cell chunks.
var _aquatic_invertebrates: Dictionary = {}
var _aquatic_invertebrates_sprites: Dictionary = {}
var _aquatic_invertebrates_sprite_generator := ProceduralAquaticInvertebrateSprite.new()
var _aquatic_invertebrates_refresh_accumulator := 0.0
## Vector2i chunk_coord -> AntColony (see step_ants, docs/concept/soil_fauna.md
## "Ants").
var _ant_colonies: Dictionary = {}
## How often each loaded colony's own mounds resample live soil moisture
## (see step_ants) -- reuses WORM_REFRESH_INTERVAL's own cadence exactly:
## weather turns over on a day scale for ants same as it does for worms,
## so there is no reason for a second, independently-tuned interval for
## the identical kind of lookup.
var _ant_moisture_refresh_accumulator := 0.0
## Vector2i chunk_coord -> BeeColony (see step_bees, docs/concept/bees.md).
## Unlike _ant_colonies, hive_cells() CAN change over a loaded chunk's own
## life (swarming, absconding -- see BeeColony.bud_new_hive/abscond_to),
## not fixed for the chunk's whole lifetime the way a mound's placement is.
var _bee_colonies: Dictionary = {}
## How often each loaded colony's own hives resample live soil/air warmth
## (see step_bees/_refresh_bee_warmth) -- reuses WORM_REFRESH_INTERVAL's own
## cadence, the same reasoning _ant_moisture_refresh_accumulator already has.
var _bee_warmth_refresh_accumulator := 0.0
## Vector2i chunk_coord -> WildBeePatch (see step_bees, docs/concept/
## bees.md's own "Wild bee nests") -- a separate, much lighter population
## from _bee_colonies just above.
var _wild_bee_patches: Dictionary = {}
## Vector2i chunk_coord -> LeafLitterField (see step_leaf_litter,
## docs/concept/leaf_litter.md). Same create-at-load/erase-at-unload
## lifecycle as _ant_colonies just above.
var _leaf_litter_fields: Dictionary = {}
## Vector2i chunk_coord -> MultiMeshInstance2D -- the visible counterpart to
## _leaf_litter_fields, one GPU-instanced draw call per chunk (see
## LeafLitterRenderer), parented under _ground_decor_parent (never
## _ground_items -- see that field's own doc comment on why). Shares ONE
## LeafLitterRenderer instance (_leaf_litter_renderer below) across every
## chunk, the same "one generator, many sprites" convention
## _illustrated_grass/_wind_sway already use -- the shader material and
## atlas texture are identical for every chunk, so building them once and
## reusing them is what keeps this a single shared cost, not a per-chunk one.
var _leaf_litter_mmis: Dictionary = {}
var _leaf_litter_renderer := LeafLitterRenderer.new()
## Vector2i chunk_coord -> the LeafLitterField.generation() value actually
## pushed to _leaf_litter_renderer.fill for that chunk, last time it
## happened (see step_leaf_litter's own doc comment for why comparing
## against this -- not a periodic throttle -- is what lets a long-settled
## chunk's litter stop costing a full MultiMesh rebuild every single frame
## once nothing about it is actually changing, while a chunk that IS
## changing still refills the very same frame it changes, exactly as
## before). Same create-at-load/erase-at-unload lifecycle as
## _leaf_litter_fields/_leaf_litter_mmis above.
var _leaf_litter_filled_generation: Dictionary = {}
## Tile _leaf_litter_filled_generation's own filtered fill was last derived
## against (see LeafLitterRenderer.leaves_in_view / LEAF_LITTER_VIEW_BUFFER_
## TILES) -- mirrors _grass_view_synced_tile's identical role for grass.
## Unlike a chunk's own generation() (which answers "did the DATA change"),
## this answers the second, independent question a per-leaf visible-area
## filter introduces: "did WHAT COUNTS AS NEARBY change" -- the player
## walking toward a leaf that never itself moved must still reveal it, even
## though field.generation() never bumped at all. step_leaf_litter forces a
## refill of every currently-decorating chunk whenever this differs from
## _disturbance_center_tile, then syncs it, the same "compare, act, sync"
## shape _leaf_litter_filled_generation itself already uses.
var _leaf_litter_view_synced_tile := Vector2i.ZERO

## Vector2i chunk_coord -> FootprintField (see FootstepGait,
## docs/concept/snow_cover.md's "Footprints" / docs/concept/
## infrastructure.md's path-scarring framing). Same create-at-load/
## erase-at-unload lifecycle as _leaf_litter_fields above.
var _footprint_fields: Dictionary = {}

## How often a chunk OUTSIDE decoration range advances its leaf litter and
## footprints, in seconds of (world) time -- every frame inside it, exactly
## as before. FPS regression round 11 (docs/concept/soil_fauna.md): both
## steps used to advance every LOADED chunk's field every frame -- 30
## chunks, of which only the 9 inside decoration range can be seen --
## measured live at ~8 ms (litter) + ~2-4 ms (prints) per frame, fps-
## independent. A far chunk's litter hands over everything it accumulated
## when it does advance (no time is ever lost, and a chunk coming back into
## range flushes whatever is pending on that very frame); footprints take an
## absolute clock, so advancing them rarely is lossless by construction.
## Pinned by test_earth_chunk_manager_far_chunk_advance.gd.
const FAR_CHUNK_ADVANCE_SECONDS := 1.0
## Chunk coord -> seconds of litter time accumulated but not yet advanced.
var _leaf_litter_far_pending: Dictionary = {}
## Chunk coord -> world age at which its footprints last advanced.
var _footprint_far_advanced_at: Dictionary = {}
## Vector2i chunk_coord -> {surface: MultiMeshInstance2D} (see
## FootprintRenderer.SURFACES) -- the visible counterpart to
## _footprint_fields, three plain MultiMeshInstance2D per chunk (one per
## real surface), parented under _ground_decor_parent exactly like
## _leaf_litter_mmis.
var _footprint_mmis: Dictionary = {}
var _footprint_renderer := FootprintRenderer.new()
## Vector2i chunk_coord -> the FootprintField.generation() value actually
## pushed to _footprint_renderer.fill for that chunk, last time it
## happened -- same dirty-tracking convention _leaf_litter_filled_
## generation above already established (see docs/concept/soil_fauna.md's
## "FPS regression round 4": rebuilding an unchanged MultiMesh buffer
## every single frame is exactly the cost that regression was).
var _footprint_filled_generation: Dictionary = {}

## The single continuous stride accumulator for the PLAYER's own real
## walking gait -- mirrors _last_player_snow_tile's own "one continuous,
## cross-chunk accumulator" shape: a stride is inherently a single-walker
## concern that must not reset at a chunk (or even a tile) boundary,
## unlike _footprint_fields/_footprint_mmis above which are genuinely
## per-chunk. Owns its own last-known position and teleport detection
## internally now too (see FootstepGait.step_at) -- there is no separate
## _last_footstep_position field any more; this object IS the player's
## whole footstep record, the same "one object, one walker" shape a
## CreatureMarker's own lazily-built FootstepGait now also has.
var _player_footstep_gait := FootstepGait.new()

## Vector2i chunk_coord -> Array[AntMoundMarker] -- the visible counterpart
## to _ant_colonies' own mound_cells(), one static marker per mound, spawned
## alongside the colony and freed with its chunk exactly like every other
## per-chunk marker dictionary here.
var _ant_mound_markers: Dictionary = {}
## Vector2i GLOBAL mound tile -> Array[AntForagerMarker] currently out on a
## real trip for that mound (see _dispatch_ant_forager) -- stale (freed)
## entries are pruned lazily on the next dispatch attempt rather than
## eagerly, since nothing else needs this list kept tidy between dispatch
## calls. Capped per mound at AntColony.active_forager_cap_at(cell), which
## scales with the mound's own queen-driven population (see
## docs/concept/soil_fauna.md "A queen, and where a colony's size comes
## from") -- AntColony.FORAGE_CHANCE can succeed several times a second per
## mound at normal frame rate, and a visible ant for every single one of
## those, uncapped, would be a swarm flicker, not a colony reading as
## alive. Keyed globally (not per-chunk) since a mound's own identity
## (chunk_coord*CHUNK_SIZE + cell) is already a stable global tile.
var _active_ant_foragers: Dictionary = {}

## Vector2i chunk_coord -> Dictionary[Vector2i cell -> BeeHiveMarker] --
## the visible counterpart to _bee_colonies' own hive_cells(). CELL-keyed,
## not a flat Array the way _ant_mound_markers is: unlike a mound, a
## specific hive's own marker can be individually torn down and replaced
## mid-life (swarming adds one, absconding/harvest-destruction moves one),
## so finding "the marker at THIS cell" has to be O(1), not a linear scan
## over every marker in the chunk.
var _bee_hive_markers: Dictionary = {}
## Vector2i GLOBAL hive tile -> Array[BeeForagerMarker] currently out on a
## real trip for that hive -- mirrors _active_ant_foragers exactly, minus
## wave dispatch (see docs/concept/bees.md's own scope note on why bees
## don't get pheromone-trail recruitment this pass).
var _active_bee_foragers: Dictionary = {}
## Same cell-keyed shape as _bee_hive_markers, for the identical reason:
## a wild nest's own marker can be individually replaced when it relocates
## (see WildBeePatch.relocate_to).
var _wild_bee_nest_markers: Dictionary = {}
## Mirrors _active_bee_foragers exactly, for WildBeePatch residents.
var _active_wild_bee_foragers: Dictionary = {}

## Vector2i chunk_coord -> Array[AntForagerMarker], every crushed forager
## currently lying where it died (see AntForagerMarker.is_corpse) --
## registered here by crush_ants_near the moment it actually crushes one,
## chunk-keyed by wherever it died. NOT mound-keyed the way
## _active_ant_foragers is: a corpse belongs to no mound any more once its
## forager dies (see docs/concept/soil_fauna.md "Ant corpses: foraged
## home, not left to vanish") -- any nearby mound's own scout can sense
## and forage it, the same free-for-all "no ownership" contract every
## other forage resource (leaf litter, grass seed, windfall) already has.
## Pruned lazily wherever it's read (ant_corpses_near/take_ant_corpse_near),
## the same "erase a stale/already-freed reference on next access"
## contract _active_ant_foragers already has -- including no explicit
## _unload_chunk cleanup, mirroring that sibling dictionary exactly.
var _ant_corpses: Dictionary = {}

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

## Whole-building entity nodes (docs/concept/building.md "Buildings are
## entities; interiors are scenes"): one Node2D per placed building,
## carrying its own Sprite2D + StaticBody2D covering the whole footprint --
## see _spawn_building_node. Keyed by chunk then ORIGIN local cell (not
## every footprint cell -- a building is one node, unlike
## _piece_collision_bodies' per-cell bodies), mirroring _structure_art_
## sprites' own per-chunk dict shape.
var _building_nodes: Dictionary = {}  # Vector2i chunk_coord -> {Vector2i origin_local -> Node2D}

## Two-story houses (docs/concept/housing.md): real per-floor collision.
## Ground-floor solid pieces stay on Godot's own default physics layer
## (bit 1) exactly as before this pair of constants existed -- confirmed
## nothing anywhere in this project ever sets collision_layer/
## collision_mask (a repo-wide grep found none), so every pre-existing
## collision body (trees, stones, ore, ground walls) keeps colliding
## exactly as it always has, zero blast radius. Upper-floor solid pieces
## get their OWN bit instead of sharing layer 1, which is what makes "block
## movement only on the floor you're actually standing on" a single
## property flip on the PLAYER's own collision_mask (see Player.
## _floor_transition_step) rather than iterating and toggling every
## collision body in the loaded world on every staircase crossing. This
## genuinely matters, not just in principle: a house's ground and upper
## wall rings share the same (x, y) cells almost everywhere (HouseBlueprint.
## build_upper_floor reuses build()'s own footprint), EXCEPT at the ground
## floor's own door cell -- walkable, no collision -- which the upper floor
## fills with a real solid window instead (there is no second entrance up
## there). One shared layer could only ever answer that cell one way; two
## independent layers let each floor be correct on its own terms.
const GROUND_FLOOR_COLLISION_LAYER := 1
const UPPER_FLOOR_COLLISION_LAYER := 2

## The draw order that lets a two-story house READ as one from above (docs/
## concept/building.md's "How a house reads from above", point 5), pinned
## here as constants rather than eyeballed z_index values in world.tscn
## (set_roof_layer/set_upper_floor_layer/set_upper_floor_furniture_layer
## apply them to whatever layer they are handed): the upper storey's own
## facade band is painted OVER the roof's front row from outside, so the
## upper-floor layers must sit above the roof layer; and whoever actually
## stands upstairs (see Player._floor_transition_step) must draw above the
## very floor they stand on, or it paints them over. VillageRenderer's own
## upper-window night lights sit between the two (its own
## UPPER_WINDOW_LIGHT_Z_INDEX), above the facade they belong to and below
## the player.
const ROOF_LAYER_Z_INDEX := 1
const UPPER_FLOOR_LAYER_Z_INDEX := 2
const UPPER_FLOOR_OCCUPANT_Z_INDEX := 4

## The upper-storey twin of _piece_collision_bodies, one layer up -- a
## SEPARATE dict (not reusing the ground one), the same "own layer because
## it coexists with what's already at that cell" reasoning every other
## ground/upper pair in this file already follows (see e.g. _paint_roof/
## _paint_upper_floor). A wall cell can carry a real, independent body on
## BOTH dicts at once -- see UPPER_FLOOR_COLLISION_LAYER's own doc comment
## for exactly when that happens and why it must.
var _upper_piece_collision_bodies: Dictionary = {}  # Vector2i chunk_coord -> {Vector2i global_cell -> StaticBody2D}

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

## Two-story houses (docs/concept/housing.md's "Two-story houses" section).
## Optional upper-storey overlay layer (see set_upper_floor_layer) -- its
## own TileMapLayer for the same reason _roof_layer needs one: an upper
## floor shares its cell with the ground floor beneath it.
var _upper_floor_layer: TileMapLayer = null
## Which floor the LOCAL PLAYER is currently standing on (0 = ground, 1 =
## a house's real upper storey) -- set by Player itself the moment it steps
## on a real wood_stairs piece (see step_on_stairs), read back by
## _update_upper_floor_visibility so a solo/hosting player's own floor
## decides what everyone sees rendered. Deliberately NOT per-viewer (no
## multiplayer camera-per-floor split exists anywhere in this codebase);
## a real, honest single-player-shaped simplification, matching how
## _hidden_roof_chunk_coord above is already scoped to one observer.
var _current_player_floor := 0
## The SAME "which room is the player in" bookkeeping _hidden_roof_chunk_
## coord/_hidden_roof_room_cells already keep for the roof layer, one layer
## up: which house's cells (room + wall ring, local to _upper_view_chunk_
## coord) are currently drawn in INTERIOR mode rather than the exterior
## facade-band view every other upper storey gets (see _paint_upper_floor),
## and which floor the player was on when that was decided -- the floor
## changes what "interior" draws (nothing on floor 0, everything on floor
## 1), so a staircase crossing inside the same house must repaint too.
var _upper_view_chunk_coord = null
var _upper_view_house_cells: Array = []
var _upper_view_floor := 0
## Exactly which local cells each chunk last painted onto the upper-floor
## and upper-furniture layers, so a repaint can erase precisely those first
## -- the exterior view paints a facade cell one row UP from where it
## lives, so "erase every cell in upper_floor_modifications" would leave a
## stale band behind the moment a house is destroyed or a view flips.
var _upper_floor_painted: Dictionary = {}
var _upper_floor_furniture_painted: Dictionary = {}

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

## Where a brand new world's clock always starts (see
## reset_world_age_to_mid_spring below, and docs/concept/seasons.md).
##
## Every fresh save used to start at world-age 0 exactly, and SeasonCycle's
## own phase formula puts that moment at warmth ~0.1465 -- just under
## Snowfall.FREEZING_WARMTH (0.15) -- so every new game began mid-winter-
## adjacent and reliably snowed within the first few minutes (reported: "it
## starts to snow deterministically"). That was first fixed by rolling a
## uniformly random starting point across the whole year -- since superseded
## by a direct, explicit request ("make starting season always mid spring"):
## every new world now begins at this SAME deliberately-chosen instant
## instead, rather than either the original accidental-winter bug or an
## arbitrary unchosen season.
const MID_SPRING_WORLD_AGE_SECONDS := (
	SeasonCycle.SECONDS_PER_YEAR * SeasonCycle.MID_SPRING_YEAR_FRACTION
)


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
	var ground_room := _update_roof_visibility(player_global_tile)
	_update_upper_floor_visibility(player_global_tile, ground_room)
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
		# Trees and stones hide/show with the same crossing (see
		# _sync_static_entity_visibility) -- immediate, like the re-syncs
		# made due above, so a newly-near chunk is never bare until a
		# throttled refresh comes round.
		_sync_static_entity_visibility()

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
	var ground_room := _update_roof_visibility(player_global_tile)
	_update_upper_floor_visibility(player_global_tile, ground_room)
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

## How far a fallen leaf scatters from its own trunk, in world pixels -- a
## real fallen fruit lands under exactly where it hung
## (ProceduralTreeSprite.FRUIT_GROUND_REACH); a leaf's position in the
## drawn canopy carries none of that per-index precision to reuse, and a
## real leaf drifts on the wind rather than dropping straight down from
## one fixed point anyway, so this is deliberately a plain scatter radius
## rather than a per-leaf hanging position.
const LEAF_SCATTER_RADIUS := 28.0

## On/off switch on the leaf-fall block below (see docs/concept/
## leaf_litter.md). Was off by default for a stretch (requested directly:
## "deactivate leaf littering", right after the GPU rewrite shipped) --
## turned back on after ants/bugs were reported foraging nothing at all in
## practice ("just walk back and forth"): carrion and fresh windfall fruit
## alone are not reliably near a wandering decomposer, and this was the
## missing, common, ambient food source. Live-verified before re-enabling
## that the GPU rewrite (LeafLitterField/LeafLitterRenderer) actually fixed
## the original per-node performance report rather than assumed to from
## the architecture change alone -- see leaf_litter.md's own Status entry
## for the real measurement. Same idiom as EarthChunkGenerator.HYDROLOGY_
## RIVERS_ENABLED's own instance flag, except a mutable `static var` rather
## than a `const`: the fall-triggering mechanism itself (angle/distance/
## season roll) stays real, tested logic regardless of which way the
## default sits -- test_earth_chunk_manager.gd's own _find_a_fallen_leaf
## helper forces this on for the duration of a single lookup and restores
## whatever it was after. Pinned on by test_leaf_litter_is_on_by_default.
static var LEAF_LITTER_ENABLED := true

## Roll granularity for the deterministic "does a tree shed a leaf this
## step" check below -- NOT engine randf(): a per-step gameplay roll uses
## a seeded hash instead, the same "looks random, is actually a pure
## function of its inputs" idiom PixelNoise/ProceduralTreeSprite.fruit_polar
## already use elsewhere in this file, rather than non-reproducible engine
## randomness.
const _LEAF_FALL_ROLL_STEPS := 1000

## The flat per-step chance a settled SUMMER tree sheds a leaf -- real
## wind/petal damage, not the main autumn fall (see docs/concept/
## leaf_litter.md). Named rather than derived: a named table beats an
## invented formula, the same "one real table" idiom FruitingModel.
## RIPENING_BY_SPECIES already sets. Reported directly: "double leaf fall
## rate" -- was 0.03 (roughly once every half minute per tree on average
## at FRUITING_INTERVAL's once-a-second cadence), doubled to 0.06 (roughly
## once every ~17 seconds per tree). LEAF_AUTUMN_BASELINE_CHANCE/LEAF_
## SPRING_TRICKLE_CHANCE both derive from this constant, so doubling it
## here doubles the summer trickle, the spring blossom trickle, AND
## autumn's own baseline floor all at once -- see
## test_leaf_summer_trickle_chance_is_pinned_to_double_its_prior_value in
## test_earth_chunk_manager.gd.
const LEAF_SUMMER_TRICKLE_CHANCE := 0.06

## The chance floor a settled AUTUMN tree sheds a leaf at the very START of
## the season -- reported directly: "leaf litter should happen constantly
## at a low rate in normal gameplay ... in autumn all leaves should fall
## eventually". A real deciduous tree does not wait for its colour to
## fully turn before its first leaves come down: ordinary wind and early
## individual-leaf senescence pull a few down all autumn long, the same
## real phenomenon LEAF_SUMMER_TRICKLE_CHANCE already models for summer's
## own wind/petal damage -- reused here at the same value (autumn's early
## trickle and summer's are the same real mechanism, not two
## independently-tuned numbers) but named separately so either can be
## retuned later without coupling the two together. See
## leaf_fall_chance_for's own doc comment for how this rises across the
## rest of the season rather than staying flat at this floor.
const LEAF_AUTUMN_BASELINE_CHANCE := LEAF_SUMMER_TRICKLE_CHANCE

## The flat per-step chance a settled SPRING tree -- specifically while its
## canopy still visibly carries blossom (canopy_season == "spring"; see
## TreePhenology, whose own canopy schedule finishes leafing out well
## before the calendar season does, at which point the EXISTING summer
## trickle above already takes over) -- sheds a petal. Reported directly:
## "there should always be an occasional falling leaf or blossom": a
## falling LEAF makes no botanical sense while a tree is still bare-to-
## blossoming and has no leaves yet, so this is blossom's own equivalent
## of the summer/autumn leaf trickle, not a second unrelated mechanism --
## reused at the same value for the same "one real background-shedding
## rate, not several independently-tuned ones" reason LEAF_AUTUMN_
## BASELINE_CHANCE already gives for reusing it.
const LEAF_SPRING_TRICKLE_CHANCE := LEAF_SUMMER_TRICKLE_CHANCE

## The per-step chance a tree wearing `canopy_season`'s own canopy sheds a
## leaf (summer/autumn) or blossom (spring) this step, given how far [0,1)
## into that CALENDAR season this moment sits (SeasonCycle.
## progress_through_season -- NOT canopy_turn_progress, which reads 0.0 for
## a season's entire settled span; see that function's own doc comment for
## why). Pure: no per-tree state, so directly testable without a real tree
## or roll (see test_earth_chunk_manager.gd).
##
## Autumn rises smoothly from LEAF_AUTUMN_BASELINE_CHANCE at the season's
## first instant up to CERTAINTY (1.0) at its last -- reported directly:
## "leaf litter should happen constantly at a low rate in normal gameplay
## ... in autumn all leaves should fall eventually", i.e. constant (never
## zero), continuous (no jump at the old turn-progress boundary), and
## increasing (strictly rises) across the WHOLE season, not flat for its
## first two-thirds and then a late ramp. Linear: the simplest curve that
## is all three of those things, and nothing in the report asks for a
## particular shape beyond them.
##
## `canopy_turn_progress` (optional, defaults to 0.0 -- a no-op on this
## curve, see below) then TAPERS that same ramp back down as the canopy's
## own visual turn into bare winter actually finishes. Reported directly:
## "when trees are rendered with their bare winter sprite no leaf litter
## should happen". canopy_turn_progress (TreePhenology._settled_then_turn,
## read via TreeRenderer.canopy_state -- the exact same Dictionary
## step_fruiting already hands tree.set_ripe_fruit for the real sprite
## blend) reads 0.0 for autumn's own settled majority, same as
## canopy_turn_progress always has, so multiplying by (1.0 -
## canopy_turn_progress) is a true no-op there -- unchanged from the
## original, twice-confirmed calendar-only ramp. Only in autumn's own
## final turn -- the SAME final stretch season_progress is climbing
## through toward 1.0 -- does this pull the chance back down, reaching
## exactly 0.0 the instant the canopy finishes blending into its bare
## frame (continuous with the `_` branch below: canopy_season itself flips
## to "winter", chance 0.0, at that exact same instant). A tree with
## nothing left to shed no longer keeps shedding at its own peak rate just
## because the calendar alone says so.
##
## Summer and spring stay flat at their own named trickle rate (real wind/
## petal damage is not something that builds across a season the way
## autumn colour change does) -- neither one's canopy is turning toward
## BARE (summer turns into autumn's canopy, spring's own canopy_season
## flips away before its calendar quarter even ends; see LEAF_SPRING_
## TRICKLE_CHANCE's own doc comment), so no taper applies to either. Any
## other season (winter: bare, nothing left to shed) returns 0.0.
static func leaf_fall_chance_for(
	canopy_season: String, season_progress: float, canopy_turn_progress: float = 0.0
) -> float:
	match canopy_season:
		"autumn":
			var ramp := lerpf(LEAF_AUTUMN_BASELINE_CHANCE, 1.0, clampf(season_progress, 0.0, 1.0))
			return ramp * (1.0 - clampf(canopy_turn_progress, 0.0, 1.0))
		"summer":
			return LEAF_SUMMER_TRICKLE_CHANCE
		"spring":
			return LEAF_SPRING_TRICKLE_CHANCE
		_:
			return 0.0

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


## What each villager has already told the player, and when (see
## docs/concept/dialogue.md's pipeline, fourth stage) -- colocated here
## alongside the world clock and the event/memory stores above for the same
## reason those are: a conversation needs all four together to build a real
## frame and pick a real move. One real instance for the manager's whole
## lifetime (see NpcSeenLedger's own doc comment on why a marker cannot hold
## this itself: it is freed with its chunk).
##
## Deliberately NOT wired into save/load in this pass -- unlike the stores
## above, this ledger only affects which of several true things a villager
## says first within one play session, never what is true, so losing it on
## reload costs a repeated line, not incorrect state. Threading it through
## the save-file schema is a real, separate, honestly-scoped follow-up (see
## docs/progress.md's own note on this).
var _seen_ledger := NpcSeenLedger.new()


func seen_ledger() -> NpcSeenLedger:
	return _seen_ledger


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
	if _event_store.latest_event_for_entity(settlement_id) == null:
		return false
	if not _event_store.events_for_entity_of_type(settlement_id, "player_settled").is_empty():
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


## item_id -> the CraftingRecipeBook recipe id it teaches (docs/concept/
## workforce.md's "Blueprints: obtaining one" section). A plain lookup
## table, not a reflection trick over ItemCatalog's own "blueprint" kind --
## the same "explicit and small" convention NpcIdentity.WORK_LOCATION_BY_
## OCCUPATION already sets for a similarly small id->id mapping.
const BLUEPRINT_RECIPE_BY_ITEM_ID := {
	"blueprint_small_house": "small_house",
	"blueprint_cottage": "cottage",
	"blueprint_manor": "manor",
	# Ten sophisticated two-story blueprints (docs/concept/housing.md's
	# "Two-story houses" section) -- item id is always "blueprint_" + the
	# recipe id, the SAME convention every tier above already uses.
	"blueprint_townhouse_narrow": "townhouse_narrow",
	"blueprint_merchant_house": "merchant_house",
	"blueprint_guild_hall": "guild_hall",
	"blueprint_riverside_villa": "riverside_villa",
	"blueprint_timber_longhouse": "timber_longhouse",
	"blueprint_artisan_workshop_house": "artisan_workshop_house",
	"blueprint_tower_keep": "tower_keep",
	"blueprint_harborside_manor": "harborside_manor",
	"blueprint_grand_estate": "grand_estate",
	"blueprint_gambrel_lodge": "gambrel_lodge",
}


## Whether the player has already learned `recipe_id` from a blueprint.
## Reads the event history straight back rather than caching it in a
## session-lifetime dict the way `_settlement_status` needs seeding for --
## this is a rare, low-frequency check (once per attempted build/learn),
## never a per-frame hot path, so there is nothing here that could go stale
## across a save/load: a fresh EarthChunkManager fed the same persisted
## event history answers this correctly with no separate reload path
## needed.
func has_unlocked_blueprint(recipe_id: String) -> bool:
	for event in _event_store.events_for_entity_of_type(
		PlayerIdentity.PLAYER_ENTITY_ID, "blueprint_learned"
	):
		if event.tags.has(recipe_id):
			return true
	return false


## Records that the player has permanently learned `recipe_id` from a
## blueprint (docs/concept/workforce.md) -- mirrors items.md's own already-
## specified spell-scroll pattern: "reading one attempts to permanently
## learn ... consumed only on a successful learn." `Player._try_learn_
## blueprint` only removes the item from inventory when this returns true.
##
## Idempotent, the same "an invalid transition does nothing" discipline
## record_player_settled_if_new already applies above: learning an
## already-known recipe teaches nothing a second time, so a duplicate
## blueprint (a second purchase, a stray /give) is a real no-op rather than
## a second identical event padding the store forever.
func record_blueprint_learned_if_new(recipe_id: String) -> bool:
	if has_unlocked_blueprint(recipe_id):
		return false
	var learned := Event.new("blueprint_learned", _world_age_seconds)
	learned.actors = [PlayerIdentity.PLAYER_ENTITY_ID]
	learned.tags = [recipe_id]
	_event_store.append(learned)
	_memory_store.witness_event(learned, _world_age_seconds)
	return true


## recipe_id -> the HouseBlueprint shape id it stamps (docs/concept/
## workforce.md's "Starting a real player-owned construction project"
## section) -- a plain lookup table, the same "explicit and small"
## convention BLUEPRINT_RECIPE_BY_ITEM_ID/NpcIdentity.WORK_LOCATION_BY_
## OCCUPATION already set, rather than parsing the recipe id itself or
## reflecting over HouseBlueprint's own catalog.
const HOUSE_BLUEPRINT_SHAPE_BY_RECIPE_ID := {
	"small_house": "hut_tiny",
	"cottage": "cottage_bright",
	"manor": "manor_wide",
	# Ten sophisticated two-story blueprints -- recipe id and shape id are
	# the SAME string for all ten (see HouseBlueprint.TWO_STORY_BLUEPRINT_
	# IDS), so this mapping is the identity, still spelled out explicitly
	# rather than a bare fallback, matching this dict's own established
	# "explicit and small" convention.
	"townhouse_narrow": "townhouse_narrow",
	"merchant_house": "merchant_house",
	"guild_hall": "guild_hall",
	"riverside_villa": "riverside_villa",
	"timber_longhouse": "timber_longhouse",
	"artisan_workshop_house": "artisan_workshop_house",
	"tower_keep": "tower_keep",
	"harborside_manor": "harborside_manor",
	"grand_estate": "grand_estate",
	"gambrel_lodge": "gambrel_lodge",
}


## recipe_id -> the BuildingCatalog house a learned blueprint raises
## (docs/concept/building.md "Player building re-route") -- the player's
## own house is ONE whole-building entity placed through place_building,
## the same model every village house already is, never the legacy
## per-tile piece pipeline HOUSE_BLUEPRINT_SHAPE_BY_RECIPE_ID above still
## describes for older saves. The ten two-story blueprints map to "" --
## "no whole-building form yet": their recipe prices are pinned to ten
## distinct legacy shapes a single catalog house cannot honestly stand in
## for, so they are refused with that message (and off the merchant's
## shelf -- see Shop.CATALOG) until the catalog grows real two-story
## sheets. Explicit "" entries rather than absent keys, so no recipe ever
## falls through to a stale default.
const BUILDING_ID_BY_RECIPE_ID := {
	"small_house": "house_small",
	"cottage": "house_medium",
	"manor": "house_large",
	"townhouse_narrow": "",
	"merchant_house": "",
	"guild_hall": "",
	"riverside_villa": "",
	"timber_longhouse": "",
	"artisan_workshop_house": "",
	"tower_keep": "",
	"harborside_manor": "",
	"grand_estate": "",
	"gambrel_lodge": "",
}


## A pure query: could `recipe_id`'s house actually be built at
## `origin_tile` (its global top-left) right now? Never mutates anything
## and never wastes material -- the caller (Player._try_build_house_from_
## blueprint) only calls Player.craft's own atomic skill+material gate
## once this already holds, so nothing is ever consumed on a placement
## that was going to be refused anyway.
##
## Checks, in order: the blueprint must be unlocked, the recipe must map
## to a real catalog house (BUILDING_ID_BY_RECIPE_ID), the target chunk
## must be loaded, and the whole site -- every footprint cell AND the
## doorstep, all inside that one chunk (a building lives in exactly one
## chunk's record, place_building's own contract) -- must be real,
## buildable ground (see is_buildable_terrain_at -- not water, not forest,
## no standing tree; reported directly: "houses / buildings cannot be
## built on river / water; also not in the forest... must first fell all
## trees to make space for the building") with nothing modified there yet.
## The one exception: a doorstep that is already a road cell is accepted
## -- every village house's doorstep IS its street, and a house built
## along one belongs there (stamp_house_and_grant_ownership keeps it
## paved).
func can_build_house_from_blueprint(recipe_id: String, origin_tile: Vector2i) -> bool:
	if not has_unlocked_blueprint(recipe_id):
		return false
	var building_id: String = BUILDING_ID_BY_RECIPE_ID.get(recipe_id, "")
	if building_id == "":
		return false
	var chunk_coord := _chunk_coord_for_tile(origin_tile)
	if not _loaded_chunks.has(chunk_coord):
		return false
	for cell in BuildingCatalog.footprint_cells(building_id, origin_tile):
		if not _house_site_cell_is_clear(chunk_coord, cell, false):
			return false
	var doorstep: Vector2i = origin_tile + BuildingCatalog.doorstep_of(building_id)
	return _house_site_cell_is_clear(chunk_coord, doorstep, true)


## One cell of a would-be house site: inside `chunk_coord`, buildable
## ground, and unmodified -- or, when `road_allowed`, paved as a road.
func _house_site_cell_is_clear(chunk_coord: Vector2i, cell: Vector2i, road_allowed: bool) -> bool:
	if _chunk_coord_for_tile(cell) != chunk_coord:
		return false
	if not is_buildable_terrain_at(cell.x, cell.y):
		return false
	var tile_id := modification_at_global(cell.x, cell.y)
	if tile_id == "":
		return true
	return road_allowed and TerrainRenderer.is_road_tile(tile_id)


## A real, deterministic seed for `recipe_id`'s house AT this exact site --
## the same "deterministic from a real key, not a random roll" philosophy
## this whole file already applies everywhere else (NpcIdentity, tree/
## flower placement, ...). Reusing ConstructionProject.id_for_site's own
## key (chunk_coord + LOCAL origin + recipe_id) rather than inventing a
## second site key, so two calls describing the same site+blueprint always
## resolve to the exact same door/window placement.
func _house_site_seed(chunk_coord: Vector2i, origin_tile: Vector2i, recipe_id: String) -> int:
	var local_origin := origin_tile - chunk_coord * CHUNK_SIZE
	return absi(hash(ConstructionProject.id_for_site(chunk_coord, local_origin, recipe_id)))


## A real, deterministic seed for `recipe_id`'s house's RESIDENT at this
## exact site (docs/concept/workforce.md's "Move-in" section) -- the same
## "deterministic from a real key, not a random roll" philosophy
## _house_site_seed itself already applies one function up, but a
## DIFFERENT, distinctly-salted string (not just the bare site key) so a
## resident's own genome/traits are never numerically identical to their
## own house's geometry seed.
func _house_resident_seed(chunk_coord: Vector2i, origin_tile: Vector2i, recipe_id: String) -> int:
	var local_origin := origin_tile - chunk_coord * CHUNK_SIZE
	return absi(hash(ConstructionProject.id_for_site(chunk_coord, local_origin, recipe_id) + "_resident"))


## The real work, assuming can_build_house_from_blueprint already held --
## the same "just do it" contract place_building itself carries one layer
## down. Places the ONE real whole-building house the recipe maps to
## (BUILDING_ID_BY_RECIPE_ID -> place_building, owned by `household_id` on
## the record itself, seeded from the site), then creates and immediately
## completes a real, player-owned ConstructionProject (docs/concept/
## workforce.md: instant, like every other player craft action -- the
## player already has the skill and has already paid the material by the
## time this is called) and settles the resident, exactly the ledger the
## legacy piece stamp ran. A road doorstep (see can_build_house_from_
## blueprint) is lifted for the placement and paved again after it, so a
## house built along a village street keeps its street.
##
## Returns the real project id, or "" without touching anything if
## `recipe_id` has no whole-building form or the site turns out occupied
## after all (place_building's own defensive re-check) -- no ledger entry
## is ever created for a house that never stood.
func stamp_house_and_grant_ownership(recipe_id: String, origin_tile: Vector2i, household_id: String) -> String:
	var building_id: String = BUILDING_ID_BY_RECIPE_ID.get(recipe_id, "")
	if building_id == "":
		return ""
	var chunk_coord := _chunk_coord_for_tile(origin_tile)
	var local_origin := origin_tile - chunk_coord * CHUNK_SIZE
	var seed_value := _house_site_seed(chunk_coord, origin_tile, recipe_id)
	if not _place_building_over_roads(chunk_coord, local_origin, building_id, seed_value, household_id):
		return ""

	var project := _construction_project_store.start_project(chunk_coord, local_origin, recipe_id, household_id)
	_construction_project_store.complete_project(project.id, _household_store)
	settle_resident_if_new(recipe_id, origin_tile)
	return project.id


## place_building for a site that may be paved: every road cell under the
## footprint and the doorstep is lifted for the placement (place_building
## refuses ANY occupied cell, by design -- villages lay their streets after
## their houses for the same reason), and the doorstep is laid again once
## the building stands, so its door still opens onto the street. A house
## along a village street has only its doorstep on the road (can_build_
## house_from_blueprint refuses a paved footprint); the town hall rises on
## the plaza itself, footprint and all. False, with every road put back,
## when the placement is refused.
## `join_street` lays the paving that ties the new building back to the
## village's own streets (see _lay_frontage_spur). True for what the VILLAGE
## raises -- the growth ladder's rungs, and whatever VillageRenderer places
## through the public wrapper below. Deliberately FALSE for a player's own
## house (stamp_house_and_grant_ownership): a player who builds beside a
## village street asked for a house, not for the village to lay a road they
## never placed.
func _place_building_over_roads(
	chunk_coord: Vector2i, origin_local: Vector2i, building_id: String, seed_value: int,
	owner_household_id: String, join_street: bool = false
) -> bool:
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk == null:
		return false
	var doorstep_local: Vector2i = origin_local + BuildingCatalog.doorstep_of(building_id)
	var lifted: Array = []
	for local in BuildingCatalog.footprint_cells(building_id, origin_local) + [doorstep_local]:
		if TerrainRenderer.is_road_tile(chunk.modifications.get(local, "")):
			chunk.modifications.erase(local)
			lifted.append(local)
	var placed := place_building(chunk_coord, origin_local, building_id, Vector2i(0, 1), seed_value, owner_household_id)
	if not placed:
		for local in lifted:
			chunk.modifications[local] = TerrainRenderer.ROAD_TILE_ID
		return false
	if lifted.has(doorstep_local):
		chunk.modifications[doorstep_local] = TerrainRenderer.ROAD_TILE_ID
		_terrain_renderer.paint(_tile_map_layer, chunk, chunk_coord * CHUNK_SIZE, generator.biome_at_global)
	if join_street:
		_lay_frontage_spur(chunk_coord, origin_local, building_id)
	return true


## Lays the paving that joins a building just raised on village frontage
## back to the village's own streets (VillageLayout.frontage_spur).
##
## A further street is paved by the founding layout only once it really got
## a plot, so the FIRST building the growth ladder raises on a fresh row
## used to get one paved tile at its door and nothing else -- reported in
## play: "There are still Farmhouses not connected by a street". The plot
## that was offered came with this same tie-back; a project raised over real
## labour hours re-derives it here from the chunk's own seed rather than
## carrying it through the construction ledger, so nothing new is persisted
## and a project queued before this existed still lands connected.
##
## A building that fronts no street of this village (the hall on its square,
## a mill out at the timber with its own spur) gets nothing, which is the
## honest answer rather than a lane to nowhere.
func _lay_frontage_spur(chunk_coord: Vector2i, origin_local: Vector2i, building_id: String) -> void:
	var is_occupied := func(cell: Vector2i) -> bool:
		var g: Vector2i = chunk_coord * CHUNK_SIZE + cell
		return modification_at_global(g.x, g.y) != ""
	var is_paved := func(cell: Vector2i) -> bool:
		var g: Vector2i = chunk_coord * CHUNK_SIZE + cell
		return TerrainRenderer.is_road_tile(modification_at_global(g.x, g.y))
	var spur = VillageLayout.frontage_spur(
		building_id, origin_local, CHUNK_SIZE, VillageLayout.seed_for(chunk_coord),
		_is_dry_local(chunk_coord), is_occupied, is_paved
	)
	if spur == null:
		return
	for local_cell in spur:
		var g: Vector2i = chunk_coord * CHUNK_SIZE + (local_cell as Vector2i)
		build_at_global(g.x, g.y, TerrainRenderer.ROAD_TILE_ID)


## Stamps a two-story house's real upper-floor pieces into chunk.upper_
## floor_modifications -- mirrors stamp_structure_at_global's own "cells
## outside chunk_coord are silently skipped" simplification exactly, one
## layer up. A no-op if chunk_coord isn't currently loaded. Public (no
## leading underscore, matching stamp_structure_at_global's own naming) --
## called both by stamp_house_and_grant_ownership below (the player's own
## blueprint path) and, duck-typed via has_method exactly like
## stamp_structure_at_global already is, by VillageRenderer's own two-story
## NPC houses.
func stamp_upper_floor_at_global(chunk_coord: Vector2i, origin_tile: Vector2i, upper_pieces: Dictionary) -> void:
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk == null:
		return
	for local_cell in upper_pieces:
		var global_cell: Vector2i = origin_tile + local_cell
		if _chunk_coord_for_tile(global_cell) != chunk_coord:
			continue
		chunk.upper_floor_modifications[_local_coord(global_cell.x, global_cell.y)] = upper_pieces[local_cell]
		_sync_upper_piece_collision(global_cell, upper_pieces[local_cell])
	_paint_upper_floor(chunk_coord, chunk, _upper_view_cells_for(chunk_coord))


## The upper floor's own twin of furnish_house_at_global (below this
## file's own two-story block -- see that function's own doc comment for
## the full contract, mirrored exactly here one layer up): the SAME real,
## occupation-linked `furniture_ids` list, tried in order against the
## upper floor's own real floor cells (from `upper_pieces`, footprint-
## relative -- NEVER the ground floor's, see BuilderMarker._upper_local_
## grid_snapshot's own identical reasoning for why the two floors must
## never be conflated), validated against `chunk.upper_floor_modifications`
## /`chunk.upper_floor_furniture_modifications` -- its own real layer, not
## `furniture_modifications` reused, because a table on the ground floor
## and a bed on the upper floor can legitimately share the exact same
## (x, y). Repaints with the CURRENT hidden-cells state (unlike ground's
## own unconditional `_paint_furniture`) so newly-placed upper furniture
## respects whatever room is already hidden -- see docs/concept/
## housing.md's own "hide in lockstep" reasoning. Returns how many pieces
## actually landed, 0 for an unloaded chunk or a single-story house with
## no upper pieces at all.
func furnish_upper_floor_at_global(
	chunk_coord: Vector2i, origin_tile: Vector2i, upper_pieces: Dictionary, furniture_ids: Array
) -> int:
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk == null:
		return 0
	var floor_cells: Array[Vector2i] = []
	for local_cell in upper_pieces:
		if BuildingPiece.category_of(upper_pieces[local_cell]) != BuildingPiece.CATEGORY_FLOOR:
			continue
		var global_cell: Vector2i = origin_tile + local_cell
		if _chunk_coord_for_tile(global_cell) == chunk_coord:
			floor_cells.append(global_cell)
	var placer := FurniturePlacement.new()
	var placed := 0
	var cell_index := 0
	for piece_id in furniture_ids:
		while cell_index < floor_cells.size():
			var global_cell: Vector2i = floor_cells[cell_index]
			cell_index += 1
			var local := _local_coord(global_cell.x, global_cell.y)
			if placer.can_place(piece_id, local, chunk.upper_floor_modifications, chunk.upper_floor_furniture_modifications):
				chunk.upper_floor_furniture_modifications[local] = piece_id
				placed += 1
				break
	if placed > 0:
		_paint_upper_floor_furniture(chunk_coord, chunk, _upper_view_cells_for(chunk_coord))
	return placed


## Move-in (docs/concept/workforce.md's "Move-in" section): the moment a
## player-owned house reaches COMPLETE, directly form one new resident
## household there -- a narrow, directly-triggered shortcut, explicitly NOT
## quests.md's full migration system (habitability pull, replan-interrupt,
## active player-invite all stay exactly as unbuilt as they already were).
##
## Idempotent on the house's own ConstructionProject, not a session-lifetime
## flag: a house that already has a real resident_household_id is left
## alone, so calling this twice (or reloading a chunk that already settled
## its houses) never conjures a second resident. "" for a site with no real
## ConstructionProject yet (nothing to attach a resident to).
##
## The resident is deliberately its OWN household, distinct from
## household_id (the OWNER, see ConstructionProject's own resident_
## household_id doc comment) -- seeded from the site itself (_house_
## resident_seed), so the same house always settles the same resident.
## Joins a REAL settlement's own household census (SETTLING_EVENT_TYPES)
## ONLY when one already has real founding history at this chunk --
## record_player_settled_if_new's own established reasoning applies
## unchanged: "a settlement with no history is not a settlement." Built far
## from any real settlement, the house still gets a real resident (pillar 4:
## "a house is population, not scenery"); it simply never joins a household
## census that does not exist.
func settle_resident_if_new(recipe_id: String, origin_tile: Vector2i) -> String:
	var chunk_coord := _chunk_coord_for_tile(origin_tile)
	var local_origin := origin_tile - chunk_coord * CHUNK_SIZE
	var project: ConstructionProject = _construction_project_store.find_project(chunk_coord, local_origin, recipe_id)
	if project == null:
		return ""
	if project.resident_household_id != "":
		return project.resident_household_id

	var resident_id := EntityRef.for_npc(_house_resident_seed(chunk_coord, origin_tile, recipe_id))
	var resident_household := _household_store.form_household(resident_id)
	project.resident_household_id = resident_household.id

	var settled := Event.new("player_house_settled", _world_age_seconds)
	settled.actors = [resident_id]
	settled.tags = [project.id]
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	if _event_store.latest_event_for_entity(settlement_id) != null:
		settled.witnesses = [settlement_id]
	_event_store.append(settled)
	_memory_store.witness_event(settled, _world_age_seconds)

	return resident_household.id


## Worker slots and assignment (docs/concept/workforce.md's "Workforce: a
## real, spendable resource" section) -- resident_household_id ->
## workplace_position (a global tile, the same coordinate space build_at_
## global/modification_at_global already use), a plain Dictionary rather
## than a new store: an assignment is exactly one fact, not a collection
## needing its own lifecycle.
var _workforce_assignments: Dictionary = {}

## The Sägewerk's own worker_slots (see that section: "this doc turns that
## fixed 'one' into worker_slots := 1" -- today's ALREADY-real behavior,
## one LumberjackMarker per placed Sägewerk, made an inspectable number
## rather than an assumption).
const SAGEWERK_WORKER_SLOTS := 1


## How many of workplace_position's own worker_slots are not currently
## filled -- read fresh from _workforce_assignments every call (pillar 5:
## "workforce is derived, never stored"), never a synced counter.
func open_worker_slots_at(workplace_position: Vector2i) -> int:
	var filled := 0
	for resident_id in _workforce_assignments:
		if _workforce_assignments[resident_id] == workplace_position:
			filled += 1
	return maxi(0, SAGEWERK_WORKER_SLOTS - filled)


## Assigns resident_household_id to work at workplace_position -- false, no
## mutation, if that resident already holds a job (reassignment/layoffs stay
## exactly as open a question as docs/concept/workforce.md's own Open
## Questions already leave them) or the workplace has no open slot left.
func assign_resident_to_workplace(resident_household_id: String, workplace_position: Vector2i) -> bool:
	if _workforce_assignments.has(resident_household_id):
		return false
	if open_worker_slots_at(workplace_position) <= 0:
		return false
	_workforce_assignments[resident_household_id] = workplace_position
	return true


func is_resident_assigned(resident_household_id: String) -> bool:
	return _workforce_assignments.has(resident_household_id)


## A direct way to end an assignment (a workplace destroyed, a resident's
## house gone) -- false for a resident who was never assigned.
func unassign_resident(resident_household_id: String) -> bool:
	if not _workforce_assignments.has(resident_household_id):
		return false
	_workforce_assignments.erase(resident_household_id)
	return true


## Population (docs/concept/workforce.md's own "Workforce" section):
## residents of player-built houses in chunk_coord who are NOT currently
## assigned to a worker slot -- the same "spare capacity" idiom
## SettlementSpareCapacity.for_settlement already established one layer
## down for construction, generalized here to any worker slot.
func free_workforce_in_chunk(chunk_coord: Vector2i) -> int:
	var free := 0
	for project: ConstructionProject in _construction_project_store.projects_with_resident_in_chunk(chunk_coord):
		if not _workforce_assignments.has(project.resident_household_id):
			free += 1
	return free


## The build-vs-hire fork's own hire-half query (docs/concept/workforce.md
## section 3): is there a spare household in settlement_id whose own NPC
## clears recipe_id's required_skill? Returns that household's id, or "" if
## none qualify -- a pure query, never mutates anything, the same "just
## answer the question" contract can_build_house_from_blueprint itself
## already keeps for the build-it-yourself half. Its one consumer, the
## instant piece-by-piece hire (hire_builder_for_house), retired with the
## piece pipeline for houses (docs/concept/building.md "Player building
## re-route"); the query stays for the construction-over-time hire that
## replaces it, which needs exactly this answer.
##
## "Spare" mirrors SettlementSpareCapacity.for_settlement's OWN filter
## exactly (excludes any household whose real occupation is a survival
## one), but returns the actual household ids rather than just a count --
## no existing function does this today (SettlementSpareCapacity/
## SettlementBuildDecision only ever pass a bare int upward). A household's
## own NPC is reconstructed the same deterministic-from-seed way
## _occupation_of_household already does -- no live NpcMarker/registry
## needed, so this works identically whether or not that household's chunk
## is even loaded right now.
##
## "" (no filter applied) for a recipe with no carpentry-shaped
## required_skill -- this function is specifically the CARPENTRY hire
## fork, not a general "find someone with skill X" search.
func find_spare_carpenter_household(settlement_id: String, recipe_id: String) -> String:
	var requirement := _recipe_book.recipe_required_skill(recipe_id)
	if requirement.is_empty() or String(requirement.get("stat_name", "")) != "carpentry_level":
		return ""
	var required_level: float = requirement["level"]

	for household_id in _households_in_settlement(settlement_id):
		var occupation := _occupation_of_household(household_id)
		if NpcProduction.PRODUCER_ITEM_BY_OCCUPATION.has(occupation):
			continue  # already working a real survival job -- not spare
		var household := _household_store.get_household(household_id)
		if household == null or household.members.is_empty():
			continue
		var founder_id: String = household.members[0]
		if EntityRef.kind_of(founder_id) != "npc":
			continue
		var carpenter := NpcIdentity.new(int(EntityRef.key_of(founder_id)))
		if carpenter.carpentry_level >= required_level:
			return household_id
	return ""


## The same real, derived GROWING/STABLE/DECLINING classification
## legitimacy_for_settlement already reads (see that function's own doc
## comment for why SettlementFood, not the emergence Market alone, is the
## real source here) -- lifted out as its own small helper so
## step_workforce_economy's rent gate (below) reads the identical status a
## settlement's own governance/legitimacy already does, rather than a
## second, subtly different derivation.
func _settlement_status_for(settlement_id: String) -> String:
	var market := _market_store.market_for(settlement_id)
	var household_count := _households_in_settlement(settlement_id).size()
	var capacity := _settlement_capacity(
		settlement_id, market, SettlementFood.village_market_for(settlement_id, _loaded_villages)
	)
	return SettlementState.status_for(household_count, capacity)


## The one carrying-capacity read every settlement assessment shares (see
## step_settlements, _settlement_status_for, legitimacy_for_settlement):
## SettlementFood over BOTH markets AND the food on the village's own
## shelves (docs/concept/milling_and_baking.md, "Food that counts") -- the
## bread its Bakery bakes and its Storage holds.
func _settlement_capacity(settlement_id: String, market, village_market) -> int:
	return SettlementFood.carrying_capacity(
		market, village_market, _item_catalog, _settlement_structure_stocks(settlement_id)
	)


## Every StructureStock standing in `settlement_id`'s own chunk (a settlement
## IS its chunk -- EntityRef.for_settlement) -- the third food container
## SettlementFood counts. Keys are "%d_%d" global tiles (see
## _structure_stock_key), so the chunk each belongs to is a plain divide.
func _settlement_structure_stocks(settlement_id: String) -> Array:
	var chunk_coord := RegionalTrade.chunk_coord_of(settlement_id)
	var stocks: Array = []
	for instance_key in _structure_stocks.instance_keys():
		var parts: PackedStringArray = str(instance_key).split("_")
		if parts.size() != 2:
			continue
		var tile := Vector2i(int(parts[0]), int(parts[1]))
		if _chunk_coord_for_tile(tile) == chunk_coord:
			stocks.append(_structure_stocks.stock_for(instance_key))
	return stocks


## Wages and Rent (docs/concept/workforce.md's own "Wages"/"Rent" sections)
## -- one periodic tick settling the player's whole tenant/employer ledger,
## the same accumulator-gated cadence step_regional_trade already uses.
## `player_wallet`: the live Player's own Wallet (injected by the caller,
## the same "caller supplies the real dependency" shape advance_project_
## labor's own recipe_book/household_store parameters already use).
const WORKFORCE_ECONOMY_INTERVAL := 30.0
## Real, tuned constants (per this project's Development-process rule
## against eyeballed values) -- deliberately equal for now, so a resident
## who is both employed and housed nets exactly zero; see workforce.md's own
## Open Questions for whether that net should differ.
const WAGE_PER_TICK := 5
const RENT_PER_TICK := 5
var _workforce_economy_accumulator := 0.0


func step_workforce_economy(delta_seconds: float, player_wallet) -> void:
	_workforce_economy_accumulator += delta_seconds
	if _workforce_economy_accumulator < WORKFORCE_ECONOMY_INTERVAL:
		return
	_workforce_economy_accumulator -= WORKFORCE_ECONOMY_INTERVAL
	if _workforce_economy_accumulator >= WORKFORCE_ECONOMY_INTERVAL:
		_workforce_economy_accumulator = fmod(_workforce_economy_accumulator, WORKFORCE_ECONOMY_INTERVAL)

	# Wages: every FILLED worker slot draws real gold from the player.
	# Simply skipped (no debt, no eviction) if the player can't afford it
	# this tick -- see workforce.md's own "Wages" section.
	for resident_id in _workforce_assignments:
		var household: Household = _household_store.get_household(resident_id)
		if household == null:
			continue
		if player_wallet.spend(WAGE_PER_TICK):
			household.wallet.add(WAGE_PER_TICK)

	# Rent: every resident of a player-built house, working or not, pays
	# for the roof -- capped by Wallet.spend's own all-or-nothing contract,
	# and suspended entirely (needs v1) for a DECLINING settlement's own
	# residents, the same real, already-tested classification governance/
	# legitimacy already reads.
	for project: ConstructionProject in _construction_project_store.projects_with_resident():
		var resident_household: Household = _household_store.get_household(project.resident_household_id)
		if resident_household == null:
			continue
		var settlement_id := EntityRef.for_settlement(project.chunk_coord)
		if _settlement_status_for(settlement_id) == SettlementState.DECLINING:
			continue
		if resident_household.wallet.spend(RENT_PER_TICK):
			player_wallet.add(RENT_PER_TICK)

	# Needs v2 (see resident_happiness's own doc comment): a genuinely
	# unhappy assigned resident quits -- deterministic, not a probability
	# roll, matching this whole codebase's "no RNG" convention (see
	# crafting_recipe_book.gd's own file header) -- closing workforce.md's
	# own "does a resident ever leave voluntarily" Open Question with a
	# real, honest yes.
	for resident_id in _workforce_assignments.keys():
		if resident_happiness(resident_id) == "unhappy":
			unassign_resident(resident_id)

	_levy_civic_tax(player_wallet)


## Needs v2 (docs/emergence/03-contracts-property-economy.md and
## housing.md's own already-shipped `appeal_score` formula, extended into a
## real gameplay consequence rather than a purely cosmetic number) --
## deliberately a NARROW, two-factor MVP, not Anno's own full multi-tier
## luxury-goods happiness system (no such system, or anything resembling
## "happiness," existed anywhere in this codebase before this pass).
##
## "unhappy" only when BOTH real signals are bad at once: the resident's
## own settlement is genuinely food-short (`SettlementState.DECLINING`,
## needs v1's own already-real signal) AND their own house has zero real
## furniture in it (housing.md's own `appeal_score` formula, `furniture_
## ids.size()`, read directly off this house's own real footprint rather
## than a second, competing formula). Deliberately conjunctive, not either
## alone: a bare house in a thriving settlement is merely undecorated, not
## a real hardship, and a furnished house in a starving settlement is still
## genuinely fed. "content" for a resident with no real house on record, or
## whose house's own chunk isn't currently loaded (furniture data is real
## and persisted, but this reads it live off the loaded chunk rather than
## paying disk I/O in what may be a hot per-tick loop -- a named, honest
## simplification, not a silent one).
func resident_happiness(resident_household_id: String) -> String:
	var project: ConstructionProject = _construction_project_store.project_for_resident(resident_household_id)
	if project == null:
		return "content"
	var settlement_id := EntityRef.for_settlement(project.chunk_coord)
	if _settlement_status_for(settlement_id) != SettlementState.DECLINING:
		return "content"
	if _house_furniture_count(project) > 0:
		return "content"
	return "unhappy"


## How many real furniture pieces sit inside this ONE house -- the SAME
## real count housing.md's own appeal_score already is (`furniture_ids.
## size()`), scoped to just this house rather than a whole settlement. A
## whole-building house (docs/concept/building.md "Player building
## re-route") keeps its furniture on its own record's "interior"
## (docs/concept/housing.md "Decorating an entered interior"), so that is
## what counts for it; a legacy piece house from an older save still
## counts the per-tile furniture layer inside its shape's footprint. 0 for
## an unloaded chunk or a recipe with no real house shape (see
## resident_happiness's own doc comment on why this stays live-only).
func _house_furniture_count(project: ConstructionProject) -> int:
	var chunk: Chunk = _loaded_chunks.get(project.chunk_coord)
	if chunk == null:
		return 0
	if chunk.buildings.has(project.origin):
		return chunk.buildings[project.origin].get("interior", {}).size()
	var shape_id: String = HOUSE_BLUEPRINT_SHAPE_BY_RECIPE_ID.get(project.blueprint_id, "")
	if shape_id == "":
		return 0
	var footprint := HouseBlueprint.new().footprint_for(shape_id)
	var count := 0
	for x in footprint.x:
		for y in footprint.y:
			if chunk.furniture_modifications.has(project.origin + Vector2i(x, y)):
				count += 1
	return count


## Civic taxation (`docs/emergence/03-contracts-property-economy.md`'s own
## "## Taxation" section: "governments can tax property... Later
## governments can tax property, trade, production, transactions, or
## households" -- and `governance.md`'s own Open Questions, which names
## taxation as needing exactly "a real currency/wealth-flow system that
## doesn't exist yet," now real via Household.wallet). Deliberately the
## OTHER direction from Rent (the "Rent" section above): rent is the player,
## as a landlord, collecting from their own tenants; this is a settlement's
## own real government taxing the PLAYER's own property within it --
## a settlement with no real government (`Governance.NONE`, the SAME
## classification `governance_form_for_settlement` already derives from
## real institution history) has no one to collect a tax, so it simply
## doesn't. Paid into the SAME shared settlement purse `VillageWages`/
## `NpcEconomy` already read/write (`NpcEconomy.PURSE_META`) via the
## generic `Object.set_meta`/`get_meta` Godot already provides on any
## `VillageMarket` -- a taxed player's gold becomes real, spendable
## settlement wealth (more subsistence wages the purse can afford), not a
## number that vanishes into nothing. A real, explicit, flat placeholder
## rate -- differentiating it by governance form (a merchant oligarchy
## taxing harder than a cooperative, say) is a real, named follow-up (see
## Open Questions), not invented here without real grounding.
const CIVIC_TAX_PER_TICK := 4


func _levy_civic_tax(player_wallet) -> void:
	var player_household := _household_store.household_for(PlayerIdentity.PLAYER_ENTITY_ID)
	if player_household == null:
		return
	for project: ConstructionProject in _construction_project_store.projects_owned_by(player_household.id):
		var settlement_id := EntityRef.for_settlement(project.chunk_coord)
		if governance_form_for_settlement(settlement_id) == Governance.NONE:
			continue
		# The REAL purse lives on the older VillageMarket (NpcEconomy.
		# PURSE_META), a different object from _market_store's own newer
		# Market -- SettlementFood.village_market_for is the SAME resolver
		# _settlement_status_for already uses to reach it. Only findable
		# while a live NpcEconomy is loaded in this settlement's own chunk
		# (a real, honest "nobody's home to collect it" gap for a far-away
		# settlement, not a silent write to the wrong object).
		var village_market = SettlementFood.village_market_for(settlement_id, _loaded_villages)
		if village_market == null:
			continue
		if not player_wallet.spend(CIVIC_TAX_PER_TICK):
			continue
		village_market.set_meta(NpcEconomy.PURSE_META, NpcEconomy.purse_of(village_market) + CIVIC_TAX_PER_TICK)


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
	var history := _event_store.events_for_entity_of_types(
		sorted_parties[0], _CONTRACT_OUTCOME_EVENTS
	)
	for i in range(history.size() - 1, -1, -1):
		var event: Event = history[i]
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
## (see _unloaded_construction_labor below). Persisted since 2026-09-16
## (ConstructionProjectStorePersistence, saved/loaded/wiped with the other
## emergence stores by World): a City Hall takes real hours of labour
## (docs/concept/civic_construction.md), and an in-memory ledger threw
## every hour away on restart.
var _construction_project_store := ConstructionProjectStore.new()


func save_construction_project_store(path: String = ConstructionProjectStorePersistence.SAVE_PATH) -> void:
	ConstructionProjectStorePersistence.new().save(_construction_project_store, path)


func load_construction_project_store(path: String = ConstructionProjectStorePersistence.SAVE_PATH) -> void:
	_construction_project_store = ConstructionProjectStorePersistence.new().load_store(path)


func reset_construction_project_store() -> void:
	_construction_project_store = ConstructionProjectStore.new()


func wipe_construction_project_store(path: String = ConstructionProjectStorePersistence.SAVE_PATH) -> void:
	ConstructionProjectStorePersistence.new().wipe(path)
	reset_construction_project_store()


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
	var history := _event_store.events_for_entity_of_types(
		settlement_id, ["production_failed", "production_succeeded"]
	)
	for i in range(history.size() - 1, -1, -1):
		var event: Event = history[i]
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
	if _event_store.latest_event_for_entity(ruin_id) != null:
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


## Every currently-real production-shortfall quest across every settlement
## that has ever been founded -- QuestLog's own reconciliation (see
## docs/concept/karma_and_luck.md's Quest lifecycle) needs the whole live
## set to check the player's accepted offer_ids against, not one settlement
## at a time. Built from the exact same _known_settlement_ids enumeration
## step_settlements itself uses, so this can never see a different set of
## settlements than the rest of this file already assesses.
func all_production_shortfall_quests() -> Array:
	var quests: Array = []
	for settlement_id in _known_settlement_ids():
		quests.append_array(production_shortfall_quests_for_settlement(settlement_id))
	return quests


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

## FPS regression round 14's residual finding (docs/concept/soil_fauna.md
## "FPS regression round 14"): the loop below used to run
## _step_settlement_granary/_production/_trade/_institution_health/
## _classification for EVERY settlement the world has EVER founded, with no
## cap and no chunk-scoping -- so its own per-tick cost grew with total
## lifetime settlement count and never shrank, for the rest of the session
## (a live run measured this stepping from 4-8 ms to 80-113 ms once founded-
## settlement count crossed some threshold, and staying there).
##
## Read the code before reaching for "skip settlements outside some radius"
## -- it is the wrong fix here. Every one of the five per-settlement calls
## is deliberately, explicitly built to keep working for an UNLOADED
## settlement (see _villagers_in_settlement's own doc comment: "step_
## settlements assesses every settlement that has ever been founded, and at
## any moment almost none of them have live NpcMarker nodes" -- and
## _step_settlement_granary's own much longer one: "without it a village
## only lives while the player is standing in it, which is the difference
## between a world and a stage set"). None of the five is a near-player-only
## nicety; production, trade, institution health and classification all
## read and write PERSISTED state precisely so a settlement the player has
## never been near still has a real, discoverable history. Splitting them
## into a "near" set and a "far" set would silently break that guarantee
## for the whole far set, not just slim it down.
##
## So the fix is PAGINATION, not exclusion -- the same shape this project
## already uses for a growing population it cannot afford to step in full
## every frame (SimulationLod: "Creatures still keep living out there --
## this changes the RATE, never the behaviour"). A settlement whose chunk
## is currently LOADED (the player is there or nearby) is always assessed
## in full, every tick, exactly as before -- the same "near is never
## throttled" rule SimulationLod's own FULL_RATE_RADIUS_PX already applies
## to creatures. The rest -- almost the whole world, at any moment, per
## _villagers_in_settlement's own doc comment -- are paginated: at most
## this many of them get a full assessment in any one tick, chosen round-
## robin (see _settlement_ids_due_this_step) so every one of them keeps
## getting turns and none is ever left out forever.
##
## BE HONEST ABOUT WHAT THIS COSTS, the same discipline _step_settlement_
## granary's own doc comment already applies to itself: once total
## unloaded-settlement count exceeds this cap, a background settlement's
## own assessment cadence stretches from SETTLEMENT_STEP_INTERVAL to
## roughly SETTLEMENT_STEP_INTERVAL times (unloaded count / this cap) --
## gathering, eating, production and trade all slow down together,
## proportionally, for that settlement, rather than any one of them
## drifting out of balance with the others (each per-settlement call is
## left completely unchanged; only how OFTEN a background settlement gets a
## turn at all is throttled). Nothing ever stops: every settlement still
## gets a full, ordinary assessment eventually, just less often once the
## world has founded enough of them that stepping all of them every 30
## seconds would itself be the performance bug again.
##
## Pinned in tests/unit/test_earth_chunk_manager.gd: a no-op under the cap
## (existing behaviour, unchanged, for every session that never founds this
## many), a hard cap above it, eventual full coverage, round-robin fairness
## (no repeat before every other background settlement has had its own
## turn), and a loaded settlement never deferred.
const MAX_UNLOADED_SETTLEMENTS_PER_STEP := 20

## Where the next tick's round-robin slice of BACKGROUND (chunk-not-loaded)
## settlements starts -- an index into whatever _known_settlement_ids()
## returns with loaded ones filtered out, not a per-settlement bookkeeping
## entry, so a settlement founded or unloaded mid-session simply joins the
## rotation wherever this currently points rather than needing its own
## ledger row. Session-lifetime only, the same scope every other cache in
## this file's settlement-assessment machinery already accepts.
var _unloaded_settlement_step_cursor := 0
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
## A real stretch of WORLD TIME, and that is the whole point of the change
## that made it one. It used to be SettlementState.FOOD_PER_HOUSEHOLD -- a
## quantity of FOOD read as a count of ASSESSMENTS -- and the comment here
## already had to admit in capitals that meals and assessments are not the
## same unit. Two consequences, both real: nobody could recalibrate what a
## household eats without silently retuning an unrelated anti-flicker
## window, and the number itself said nothing about how long a wobble
## actually lasts (see docs/concept/settlement_food_calibration.md).
##
## Two days, because a status that holds through two whole day-night cycles
## of the village's own life is the village changing, not the band boundary
## being brushed. The value is unchanged (SECONDS_PER_SIMULATED_DAY is 60
## and an assessment is 30, so two days is four assessments, exactly what
## this was before) -- deliberately, so decoupling it changed no behaviour
## and the recalibration that follows can be judged on its own.
##
## What it actually buys is pinned in tests, not asserted here: a status
## that flips back and forth across a band boundary never fires, and one
## that holds for this many consecutive assessments does.
const SETTLEMENT_STATUS_DWELL_DAYS := 2
const SETTLEMENT_STATUS_DWELL_STEPS := int(
	SECONDS_PER_SIMULATED_DAY * SETTLEMENT_STATUS_DWELL_DAYS / SETTLEMENT_STEP_INTERVAL
)
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
	var types: Array = []
	for tier in SettlementTier.TIERS:
		types.append("settlement_became_%s" % tier)
	var history := _event_store.events_for_entity_of_types(settlement_id, types)
	if history.is_empty():
		return ""
	return history.back().type.substr("settlement_became_".length())


## What `settlement_id` was last actually event-sourced as specializing in,
## read back out of its own persisted event history, or "" if it never has
## been. The specialization itself is the event's first TAG rather than part
## of its type (see _step_settlement_classification), so an untagged
## settlement_specialized -- which nothing writes -- reads as never having
## specialized rather than as an empty specialization.
func _recorded_settlement_specialization(settlement_id: String) -> String:
	var history := _event_store.events_for_entity_of_type(settlement_id, "settlement_specialized")
	for i in range(history.size() - 1, -1, -1):
		if not history[i].tags.is_empty():
			return history[i].tags[0]
	return ""


## Every settlement id step_settlements should fully assess THIS tick (see
## MAX_UNLOADED_SETTLEMENTS_PER_STEP for why this exists at all): every
## LOADED settlement, always, plus -- once there are more BACKGROUND
## settlements than the cap -- a round-robin slice of exactly that many of
## them. Below the cap this returns _known_settlement_ids() completely
## unchanged (same settlements, same order), which is what makes this a
## pure no-op for every existing step_settlements test and every real
## session that never founds this many settlements at once.
##
## "Loaded" is read the cheap way -- a settlement's own chunk coordinate
## (RegionalTrade.chunk_coord_of, a plain string parse) is a key of
## _loaded_villages -- rather than resolving all the way to a live
## VillageMarket the way village_market_for does: this only needs to know
## WHETHER the player is near, not read anything out of what is there once
## they are.
##
## Skipped background settlements are tracked as who to LEAVE OUT, not who
## is due, so the ids actually returned keep _known_settlement_ids()'s own
## founding order -- a loaded settlement interleaved between two skipped
## background ones stays exactly where it always was, and every downstream
## per-settlement call sees the same relative ordering it always has.
func _settlement_ids_due_this_step() -> Array[String]:
	var all_ids := _known_settlement_ids()
	var background_ids: Array[String] = []
	for settlement_id in all_ids:
		if not _loaded_villages.has(RegionalTrade.chunk_coord_of(settlement_id)):
			background_ids.append(settlement_id)

	if background_ids.size() <= MAX_UNLOADED_SETTLEMENTS_PER_STEP:
		_unloaded_settlement_step_cursor = 0
		return all_ids

	var start := _unloaded_settlement_step_cursor % background_ids.size()
	var skipped := {}
	for i in range(MAX_UNLOADED_SETTLEMENTS_PER_STEP, background_ids.size()):
		skipped[background_ids[(start + i) % background_ids.size()]] = true
	_unloaded_settlement_step_cursor = (start + MAX_UNLOADED_SETTLEMENTS_PER_STEP) % background_ids.size()

	var due: Array[String] = []
	for settlement_id in all_ids:
		if not skipped.has(settlement_id):
			due.append(settlement_id)
	return due


func step_settlements(delta_seconds: float) -> void:
	_settlement_step_accumulator += delta_seconds
	if _settlement_step_accumulator < SETTLEMENT_STEP_INTERVAL:
		return
	_settlement_step_accumulator -= SETTLEMENT_STEP_INTERVAL
	if _settlement_step_accumulator >= SETTLEMENT_STEP_INTERVAL:
		_settlement_step_accumulator = fmod(_settlement_step_accumulator, SETTLEMENT_STEP_INTERVAL)

	for settlement_id in _settlement_ids_due_this_step():
		var market := _market_store.market_for(settlement_id)
		var household_ids := _households_in_settlement(settlement_id)
		# BOTH markets, not just the persisted emergence one (see
		# SettlementFood): live play essentially never stocks that one, while
		# the villagers' own VillageMarket holds the food they actually
		# gathered and actually eat -- reading only the first classified every
		# settlement in the world DECLINING forever, which Governance then
		# read straight back out as illegitimate.
		var village_market = SettlementFood.village_market_for(settlement_id, _loaded_villages)
		# What the village can HOLD, from what actually stands in it
		# (docs/concept/village_warehouse.md, "The roof is the limit").
		# Refreshed every step rather than set once: a village that loses
		# its warehouse loses the headroom with it, and one that has just
		# had it raised gains it. Deliberately NOT SettlementFood.carrying_
		# capacity, which asks the different question of how many households
		# the food on hand can feed.
		#
		# ONLY while the chunk is LOADED, and that guard is the whole point.
		# Not being able to see a village must never read as "it has no
		# warehouse": without it, every settlement the player is not standing
		# in had its market clamped to a household's corners and everything
		# above that silently discarded, because has_structure_near answers
		# false for an unloaded chunk.
		var settlement_chunk := RegionalTrade.chunk_coord_of(settlement_id)
		if village_market != null and _loaded_chunks.has(settlement_chunk):
			village_market.storage_capacity = VillageMarket.capacity_for_structures(
				_standing_building_ids_in_chunk(settlement_chunk)
			)
		# BEFORE capacity is read, because this is what finally puts a real
		# number in front of it (see _step_settlement_granary).
		_step_settlement_granary(settlement_id, market, village_market, household_ids)
		# The village's spare hands gather building material and keep raising
		# whatever the settlement decided to build (docs/concept/milling_and_
		# baking.md) -- the SAME interval, so a village near the player builds
		# in real time rather than only on a reload after an unload.
		_step_settlement_gathering(settlement_id, market, household_ids)
		# The outside world turns up and pays for what the village made
		# (docs/concept/traveling_merchants.md) -- BEFORE the build and
		# immigration steps, so gold that arrives this tick is gold the
		# village can act on this tick.
		_step_merchant_visits(settlement_id, market)
		# A fed village with room takes a household in, BEFORE the build
		# step: a newcomer arriving this tick is owed a house this tick,
		# not one assessment later.
		_step_village_immigration(settlement_id, market, household_ids)
		_step_settlement_construction(settlement_id, household_ids)
		var capacity := _settlement_capacity(settlement_id, market, village_market)
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
	var types: Array = []
	for status in SettlementState.STATUSES:
		types.append("settlement_%s" % status)
	var history := _event_store.events_for_entity_of_types(settlement_id, types)
	if history.is_empty():
		return ""
	return history.back().type.substr("settlement_".length())


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

## settlement_id -> SettlementGathering's own sub-unit carry for building
## material (see _step_settlement_gathering).
var _settlement_material_carry: Dictionary = {}


## A settlement's spare hands cut timber, pick stone and pull fibre into its
## own persisted Market every assessment (SettlementGathering, docs/concept/
## milling_and_baking.md) -- loaded or not, since nothing else ever stocks
## building material there and every autonomous construction decision
## used to end in SHORTFALL for that reason alone.
func _step_settlement_gathering(settlement_id: String, market, household_ids: Array[String]) -> void:
	if household_ids.is_empty():
		return
	var spare_capacity := SettlementSpareCapacity.for_settlement(
		household_ids.size(), _household_occupations_for_settlement(settlement_id)
	)
	# Deliberately NOT scaled by settlement_productivity, unlike the
	# construction labour it feeds (see _advance_construction_labor): a
	# hungry village must still be able to cut the timber for the farm that
	# would fix its hunger. Scaling the gathering itself is a doom loop --
	# the villages most in need of building their way out become the ones
	# least able to -- and it is also simply wrong about people: hunger is
	# what MOTIVATES the survival work of cutting wood and picking stone,
	# not what slows it. What an unhappy village does worse is RAISE what
	# it gathered, which is where the scale belongs.
	var result: Dictionary = SettlementGathering.material_delta(
		spare_capacity, SETTLEMENT_STEP_INTERVAL, _settlement_material_carry.get(settlement_id, {})
	)
	_settlement_material_carry[settlement_id] = result["carry"]
	var stock_delta: Dictionary = result["stock_delta"]
	for item_id in stock_delta:
		market.add_stock(str(item_id), int(stock_delta[item_id]))


## settlement_id -> MerchantVisit's own sub-visit carry, the same
## per-settlement remainder gathering and immigration already keep.
var _settlement_merchant_carry: Dictionary = {}


## A traveling merchant buys this settlement's surplus and pays gold into
## its shared purse (docs/concept/traveling_merchants.md).
##
## This is the first faucet in the game where a village's gold arrives
## because somebody carried goods away, rather than being conjured per
## food unit gathered whether or not anyone ever bought it
## (NpcProduction.YIELD_TO_GOLD_RATE, which stays for now as the producer's
## own wage). The goods really leave the market and the gold really enters
## the purse VillageWages already pays subsistence out of -- so a visit
## feeds the blacksmith, not only the fisher whose catch was sold.
##
## Runs for loaded and UNLOADED settlements alike, unlike immigration: it
## needs only the market's own stock, which is persisted, so a village goes
## on trading while the player is away.
func _step_merchant_visits(settlement_id: String, market) -> void:
	if market == null:
		return
	var reserved := _construction_reserve_for(settlement_id)
	var result: Dictionary = MerchantVisit.arrivals(
		SETTLEMENT_STEP_INTERVAL, market.stock,
		float(_settlement_merchant_carry.get(settlement_id, 0.0)), reserved
	)
	_settlement_merchant_carry[settlement_id] = result["carry"]
	if not result["arrived"]:
		return

	var sale: Dictionary = MerchantVisit.purchase(market.stock, reserved)
	if int(sale["paid"]) <= 0:
		return
	for item_id in sale["bought"]:
		market.remove_stock(str(item_id), float(sale["bought"][item_id]))
	NpcEconomy.deposit_to_purse(market, float(sale["paid"]))


## What this village is SAVING FOR: item_id -> whole units its own next
## building really needs (docs/concept/traveling_merchants.md, "Surplus, not
## stock"). {} for a village that owes itself nothing.
##
## Read off the SAME VillageGrowth.next_building the ladder walks and the
## SAME recipe that building is priced in -- never a second list of
## "protected goods", which would drift from what a village is actually
## saving for. Measured before this existed (tools/probe_village_growth.gd):
## SettlementGathering is the only thing that puts wood into a settlement's
## market and `wood` is on the merchant's buy list, so a real village's
## stone climbed steadily to 37 while its wood never once got past 2, and a
## village that grew from 10 households to 31 built not one house for any of
## them.
##
## An UNLOADED settlement reserves nothing: the ladder reads what really
## stands in the chunk, and an unloaded one has nothing to read -- the same
## honest limitation _step_village_immigration already carries. A village
## the player is away from therefore trades as it always did.
func _construction_reserve_for(settlement_id: String) -> Dictionary:
	var chunk_coord := RegionalTrade.chunk_coord_of(settlement_id)
	if not _loaded_chunks.has(chunk_coord):
		return {}
	var household_ids := _households_in_settlement(settlement_id)
	if household_ids.is_empty():
		return {}
	var census := _village_census_for(chunk_coord, household_ids)
	var next_building: String = VillageGrowth.next_building(
		household_ids.size(), int(census["housed_count"]),
		_present_structure_ids_for_settlement_chunk(chunk_coord)
	)
	if next_building == "":
		return {}
	var reserved: Dictionary = {}
	for input in _recipe_book.recipe_inputs(next_building):
		reserved[String(input["item_id"])] = int(input["count"])
	return reserved


## docs/concept/village_growth.md mechanism 3: a fed village with room takes
## a household in. Called from the same settlement step that gathers and
## builds, so a village grows on the same clock it works on.
##
## **Honest limitation**: a village only draws while its own chunk is
## LOADED. The room half of the gate (spare roofs, frontage left) is read
## off buildings that really stand, and an unloaded chunk has none to read
## -- guessing at them would be exactly the invented number this project's
## rules forbid. A village therefore grows while the player is near it, the
## same scope _step_settlement_construction already has.
func _step_village_immigration(settlement_id: String, market, household_ids: Array) -> void:
	if household_ids.is_empty():
		return
	var chunk_coord := RegionalTrade.chunk_coord_of(settlement_id)
	if not _loaded_chunks.has(chunk_coord):
		return

	var census := _village_census_for(chunk_coord, household_ids)
	var result: Dictionary = VillageImmigration.arrivals(
		SETTLEMENT_STEP_INTERVAL,
		_food_per_household(settlement_id, market, household_ids.size()),
		int(census["spare_house_capacity"]),
		_growth_site_for(chunk_coord, BuildingCatalog.BUILDING_IDS[0]) != null,
		VillageGrowth.ladder_share(_present_structure_ids_for_settlement_chunk(chunk_coord)),
		float(_settlement_immigration_carry.get(settlement_id, 0.0))
	)
	_settlement_immigration_carry[settlement_id] = result["carry"]
	for i in int(result["arrivals"]):
		admit_household(chunk_coord)


## settlement_id -> VillageImmigration's own sub-unit carry, the same
## per-settlement remainder _settlement_material_carry keeps for gathering.
var _settlement_immigration_carry: Dictionary = {}


## A new household settles here: the NEXT deterministic villager for this
## settlement (SettlementGenerator's own per-index seed, continued past
## POPULATION so an arrival is exactly as reproducible as a founder), a
## real `npc_settled` event naming them, and a real single-member
## household. Returns the new household's id.
##
## The event is what makes the arrival visible to everything else with no
## further plumbing: _households_in_settlement reads the event graph, so
## household_count_for_settlement, SettlementSpareCapacity, SettlementTier
## and VillageGrowth's ladder all see the newcomer immediately. They arrive
## WITHOUT a house on purpose -- the village then owes them one, which is
## exactly the ladder's first rung.
## Old-save migration: a village recorded as founded with FEWER households
## than a village is founded with today takes the missing ones in, once.
##
## Reported live after the founding roster grew from five to ten: *"the
## village still doesn't have 10 people"*. A settlement's household count is
## read back out of the persisted event graph (see _population_for), so a
## village founded under the older rule keeps the roster it was founded with
## for ever and the change is invisible in any world that already has
## villages in it.
##
## Never DOWN: a village that has grown past the founding roster on its own
## (docs/concept/village_growth.md mechanism 3) is not culled back to it. And
## the newcomers are the SAME deterministic villagers the generator would
## have rolled for those indices (admit_household continues its own per-index
## seed), so a village that catches up is the village it would have been
## founded as, not a different one.
##
## No-op for a chunk with no settlement recorded at all -- an ordinary
## wilderness chunk has nobody to settle.
func settle_up_to_founding_roster(chunk_coord: Vector2i) -> void:
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	var count := household_count_for_settlement(settlement_id)
	if count <= 0:
		return
	while count < SettlementGenerator.POPULATION:
		if admit_household(chunk_coord) == "":
			return  # already here -- nothing further to settle
		count += 1


func admit_household(chunk_coord: Vector2i) -> String:
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	var index := _villagers_in_settlement(settlement_id).size()
	var npc_id := EntityRef.for_npc(hash("%d_%d_villager_%d" % [chunk_coord.x, chunk_coord.y, index]))
	if _household_store.household_for(npc_id) != null:
		return ""  # already here -- an arrival is never a duplicate of a villager already settled

	var settled := Event.new("npc_settled", _world_age_seconds)
	settled.actors = [npc_id]
	settled.witnesses = [settlement_id]
	_event_store.append(settled)
	_memory_store.witness_event(settled, _world_age_seconds)
	return _household_store.form_household(npc_id).id


## This settlement's own mean household productivity (HouseholdWellbeing),
## in [MIN_PRODUCTIVITY, 1] -- what _step_settlement_gathering scales by and
## what a readout reports. 1.0 for a settlement with no households at all:
## "nobody lives here to be unhappy" must never read as "everyone here is
## miserable" (see HouseholdWellbeing.mean_productivity).
func settlement_productivity(settlement_id: String) -> float:
	return HouseholdWellbeing.mean_productivity(_household_wellbeing_for_settlement(settlement_id))


## One HouseholdWellbeing.assess result per household of `settlement_id`.
##
## Hunger is the SETTLEMENT-scale reading -- how far the village's own
## larder falls short of a full one -- not any one live villager's NpcNeeds
## clock. At this scale that IS the honest question ("how hungry are these
## people" is "how much food does this village have"), and it is the only
## reading available at all for a settlement whose chunk is not loaded and
## which therefore has no live villagers to ask. A readout about ONE
## household of a LOADED village passes the real resident's own hunger
## instead (see household_report_at).
##
## `house_capacity` for an unloaded settlement falls back to a household's
## own size rather than 0: a founded village really did house its founders
## (record_settlement_founded_if_new), so the roof they were founded with
## is assumed still standing when the chunk is not there to be read. Any
## other default would have every unloaded village in the world read as
## homeless and gather at the productivity floor.
func _household_wellbeing_for_settlement(settlement_id: String) -> Array:
	var household_ids := _households_in_settlement(settlement_id)
	if household_ids.is_empty():
		return []

	var market := _market_store.market_for(settlement_id)
	var food_per_household := _food_per_household(settlement_id, market, household_ids.size())
	var hunger := 1.0 - clampf(
		food_per_household / HouseholdWellbeing.FOOD_STOCK_PER_HOUSEHOLD_TARGET, 0.0, 1.0
	)

	var chunk_coord := RegionalTrade.chunk_coord_of(settlement_id)
	var loaded := _loaded_chunks.has(chunk_coord)
	var ladder_share := (
		VillageGrowth.ladder_share(_present_structure_ids_for_settlement_chunk(chunk_coord)) if loaded else 0.0
	)
	var capacity_by_household := _house_capacity_by_household(chunk_coord) if loaded else {}

	var out: Array = []
	for household_id in household_ids:
		var household = _household_store.get_household(household_id)
		var size: int = 1 if household == null else maxi(household.members.size(), 1)
		out.append(HouseholdWellbeing.assess({
			"hunger": hunger,
			"food_per_household": food_per_household,
			"house_capacity": int(capacity_by_household.get(household_id, size)) if loaded else size,
			"household_size": size,
			"wallet_balance": 0 if household == null else household.wallet.balance,
			"meal_price": VillageMarket.VILLAGE_LOCAL_FOOD_PRICE,
			"ladder_share": ladder_share,
		}))
	return out


## household_id -> the capacity of the house it owns in this chunk. A
## household with no house here is simply absent (its caller supplies the
## homeless 0 or the unloaded fallback).
func _house_capacity_by_household(chunk_coord: Vector2i) -> Dictionary:
	var by_household := {}
	for record in buildings_in_chunk(chunk_coord):
		var capacity := BuildingCatalog.capacity_of(record.get("id", ""))
		if capacity <= 0:
			continue
		var owner := VillageCensus.household_owning(chunk_coord, record.get("origin_local", Vector2i.ZERO), _household_store)
		if owner != "":
			by_household[owner] = maxi(int(by_household.get(owner, 0)), capacity)
	return by_household


## The settlement's real food stock divided across its households -- the
## SAME both-markets reading step_settlements already classifies a
## settlement with (SettlementFood.food_stock), so a village's wellbeing
## and its DECLINING/THRIVING status can never disagree about how fed it is.
func _food_per_household(settlement_id: String, market, household_count: int) -> float:
	if household_count <= 0:
		return 0.0
	var stock := SettlementFood.food_stock(
		market, SettlementFood.village_market_for(settlement_id, _loaded_villages),
		_item_catalog, _settlement_structure_stocks(settlement_id)
	)
	return float(stock) / float(household_count)


## docs/concept/village_growth.md mechanism 5: everything a readout needs
## about the building standing on `(global_x, global_y)` -- what it is, who
## lives there, and how they are doing. {} when no building covers that
## cell (clicking empty ground reports nothing).
##
## A CONSUMER, never a driver: every number here is derived at the moment
## it is asked for, from state that already exists for its own reasons, so
## the readout cannot drift from the simulation -- it IS the simulation,
## read. Calling this changes nothing, and never calling it changes nothing
## either (pinned by test_earth_chunk_manager_village_growth.gd).
##
## A COMMONS (a hall, a mill, a warehouse -- BuildingCatalog.capacity_of
## == 0) has no household and no needs of its own, and is reported that
## way: empty `needs`, no resident name, `is_home` false. Inventing
## residents for a town hall so the panel has something to draw would be
## exactly the fabrication this project's rules forbid.
##
## Hunger is the RESIDENT'S OWN live NpcNeeds clock when that villager is
## really loaded and walking around, and the settlement-scale reading (how
## far the village larder falls short) otherwise -- so an occupied village
## reports the person in front of you, and one whose villagers are not
## currently spawned still reports something true rather than nothing.
func household_report_at(global_x: int, global_y: int) -> Dictionary:
	var record := building_at_global(global_x, global_y)
	if record.is_empty():
		return {}

	var building_id: String = record["id"]
	var chunk_coord: Vector2i = record["chunk_coord"]
	var origin_local: Vector2i = record["origin_local"]
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	var capacity := BuildingCatalog.capacity_of(building_id)

	var report := {
		"building_id": building_id,
		"display_name": BuildingCatalog.display_name_of(building_id),
		"chunk_coord": chunk_coord,
		"origin_local": origin_local,
		"capacity": capacity,
		"is_home": capacity > 0,
		"settlement_id": settlement_id,
		"settlement_productivity": settlement_productivity(settlement_id),
		"household_id": "",
		"resident_name": "",
		"resident_occupation": "",
		"wallet_balance": 0,
		"needs": {},
		"happiness": 0.0,
		"productivity": 0.0,
		# What this building is holding, for the readout's Inventory tab
		# (docs/concept/building_storage.md). Carried on EVERY report, home
		# or commons, because a barn and a workshop are exactly the
		# buildings that hold things and neither is a home.
		"storage_capacity": BuildingCatalog.storage_capacity_of(building_id),
		"stock": building_inventory_at(global_x, global_y),
	}
	if capacity <= 0:
		return report

	var resident_seed := int(record.get("resident_seed", 0))
	if resident_seed != 0:
		var identity := NpcIdentity.new(resident_seed)
		report["resident_name"] = identity.npc_name
		report["resident_occupation"] = identity.occupation
	elif String(record.get("occupation", "")) != "":
		report["resident_occupation"] = String(record["occupation"])

	var household_id := VillageCensus.household_owning(chunk_coord, origin_local, _household_store)
	report["household_id"] = household_id
	var household = _household_store.get_household(household_id) if household_id != "" else null
	var household_size: int = 1 if household == null else maxi(household.members.size(), 1)
	report["wallet_balance"] = 0 if household == null else household.wallet.balance

	var household_count := maxi(_households_in_settlement(settlement_id).size(), 1)
	var food_per_household := _food_per_household(
		settlement_id, _market_store.market_for(settlement_id), household_count
	)
	var wellbeing: Dictionary = HouseholdWellbeing.assess({
		"hunger": _resident_hunger(chunk_coord, resident_seed, food_per_household),
		"food_per_household": food_per_household,
		"house_capacity": capacity,
		"household_size": household_size,
		"wallet_balance": report["wallet_balance"],
		"meal_price": VillageMarket.VILLAGE_LOCAL_FOOD_PRICE,
		"ladder_share": VillageGrowth.ladder_share(_present_structure_ids_for_settlement_chunk(chunk_coord)),
	})
	report["needs"] = wellbeing["needs"]
	report["happiness"] = wellbeing["happiness"]
	report["productivity"] = wellbeing["productivity"]
	return report


## Places a building whose plot IS paved -- the civic seat on the village
## square (VillageRenderer._place_civic_if_missing). The public face of
## _place_building_over_roads, which the completed-project path already
## uses: an ordinary place_building refuses a plot carrying any
## modification, and the plaza's own paving is exactly that.
func place_building_over_roads(
	chunk_coord: Vector2i, origin_local: Vector2i, building_id: String, seed_value: int,
	owner_household_id: String
) -> bool:
	return _place_building_over_roads(
		chunk_coord, origin_local, building_id, seed_value, owner_household_id, true
	)


## This villager's own household's persistent Wallet, or null if they have
## no household yet. What a live NpcEconomy earns into and spends from (see
## NpcEconomy.bind_household_wallet) -- without it a villager's whole
## working life is kept in a wallet that dies with the chunk, which is
## exactly why every villager read 0 gold however long they had worked.
func household_wallet_for_villager(villager_seed: int):
	var household = _household_store.household_for(EntityRef.for_npc(villager_seed))
	return null if household == null else household.wallet


## The LOCAL origin of the house `villager_seed`'s household owns in this
## chunk, or null. What VillageRenderer asks on reload to stand a villager
## at their own front door.
##
## Resolved through OWNERSHIP, not through the per-index seed a founding
## house carries: a newcomer's house was raised by the growth ladder
## (_apply_village_growth_decision), so it has no founding seed at all, and
## matching by seed alone would leave every household that ever moved in
## standing on a fallback ring anchor outside the house it actually owns.
func house_origin_for_villager(chunk_coord: Vector2i, villager_seed: int):
	var household = _household_store.household_for(EntityRef.for_npc(villager_seed))
	if household == null:
		return null
	for record in buildings_in_chunk(chunk_coord):
		if BuildingCatalog.capacity_of(record.get("id", "")) <= 0:
			continue
		var origin_local: Vector2i = record.get("origin_local", Vector2i.ZERO)
		if VillageCensus.household_owning(chunk_coord, origin_local, _household_store) == household.id:
			return origin_local
	return null


## This resident's own live hunger if their NpcMarker is really spawned in
## this chunk, else the settlement-scale reading derived from the larder
## (see _household_wellbeing_for_settlement for why that is the honest
## fallback rather than a guess).
func _resident_hunger(chunk_coord: Vector2i, resident_seed: int, food_per_household: float) -> float:
	if resident_seed != 0:
		for node in _loaded_villages.get(chunk_coord, []):
			if not is_instance_valid(node) or not (node is NpcMarker):
				continue
			var marker: NpcMarker = node
			if marker.identity == null or marker.identity.seed_value != resident_seed:
				continue
			if marker.economy != null and marker.economy.needs != null:
				return clampf(marker.economy.needs.hunger, 0.0, 1.0)
	return 1.0 - clampf(food_per_household / HouseholdWellbeing.FOOD_STOCK_PER_HOUSEHOLD_TARGET, 0.0, 1.0)


## While a settlement's chunk is loaded, its construction keeps going in
## real time: re-take the build decision (a need may have appeared or a
## link may have just been placed) and advance every IN_PROGRESS project
## by the assessment interval -- the SAME closed-form labor math
## _apply_construction_labor_catchup applies to unloaded time, so nothing
## about how fast a village builds depends on whether the player is
## watching. An unloaded settlement is left to the reload catch-up.
func _step_settlement_construction(settlement_id: String, household_ids: Array[String]) -> void:
	if household_ids.is_empty():
		return
	var chunk_coord := RegionalTrade.chunk_coord_of(settlement_id)
	if not _loaded_chunks.has(chunk_coord):
		return
	_apply_settlement_build_decision(chunk_coord)
	_apply_civic_build_decision(chunk_coord)
	_apply_village_growth_decision(chunk_coord)
	# The GAME's own day, not the catch-up's: a village standing in front of
	# the player is not an absence to be integrated over (see
	# _advance_construction_labor's own `seconds_per_day`).
	_advance_construction_labor(chunk_coord, SETTLEMENT_STEP_INTERVAL, SECONDS_PER_SIMULATED_DAY)
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
## The same reading by CHUNK, for a caller that has a coordinate rather than
## a settlement id -- chiefly the founding roster, which has to know what a
## village's land feeds it with (SettlementDemand.trade_for) before that
## village exists.
##
## Deliberately the SEEDED region and not the live one: it is a pure
## function of terrain, so every caller gets the same answer whether or not
## the chunk is loaded, and a village is founded with the same roster on
## every visit. The live ecology would make a roster drift with the weather.
func seeded_region_for_chunk(chunk_coord: Vector2i):
	return _seeded_region_for(EntityRef.for_settlement(chunk_coord))


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
	# A village does not saw the timber it is saving for its own next house
	# (docs/concept/village_growth.md, "What a village is saving for"). The
	# sawyer's own log_to_balken turns 3 wood into 1 beam, so before this a
	# village sawed its construction timber the moment it had three of it --
	# and the merchant, whose cart fills with the dearest goods first,
	# carried the beams off. Measured: stone past 50, wood never past 2, and
	# 31 households living in the 10 houses the village was founded with.
	var market := _market_store.market_for(settlement_id)
	var reserved := _construction_reserve_for(settlement_id)
	for household_id in household_ids:
		var recipe_id := OccupationProduction.recipe_for(_occupation_of_household(household_id))
		if recipe_id == "":
			continue
		if not SettlementReserve.can_spend(_recipe_book.recipe_inputs(recipe_id), market.stock, reserved):
			continue
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
	var capacity := _settlement_capacity(
		settlement_id, market, SettlementFood.village_market_for(settlement_id, _loaded_villages)
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

## FPS regression round 14's second follow-up (docs/concept/soil_fauna.md
## "FPS regression round 14's second follow-up"): step_regional_trade's own
## outer loop called production_shortfall_quests_for_settlement for EVERY
## settlement the world has ever founded, every REGIONAL_TRADE_INTERVAL
## tick, with no cap -- the exact same unbounded-growth shape
## MAX_UNLOADED_SETTLEMENTS_PER_STEP already fixed for step_settlements,
## just not yet confirmed to have caused an observed regression when that
## round shipped. A direct probe confirmed it independently: at 400
## founded settlements, one step_regional_trade tick cost 1164ms in the
## worst case (every settlement genuinely short, no real surplus anywhere,
## so _attempt_regional_resupply's own inner search never short-circuits)
## and 52ms even in the BEST case (every settlement's own recipe already
## amply stocked, so no resupply search ever runs at all) -- that second
## number is the honest floor: pure per-settlement shortfall-checking cost,
## present even in a world where regional trade never actually has
## anything to do, and it alone already matches the magnitude round 14's
## own step_settlements fix was written to eliminate.
##
## Fix: the SAME pagination-not-exclusion shape, applied to the SHORTAGE
## side only. A LOADED settlement is always checked in full, every tick;
## the BACKGROUND majority is paginated round-robin, at most this many per
## tick. Deliberately a SEPARATE cursor/method from step_settlements' own
## _settlement_ids_due_this_step/_unloaded_settlement_step_cursor, not a
## shared one -- two callers sharing one cursor would make each caller's
## own cadence depend on how often the OTHER caller also happens to run
## this tick, silently invalidating step_settlements' own documented
## cadence math. A short-lived structural duplication of that method's
## shape is the honest tradeoff against that entanglement risk; worth
## revisiting only if a third consumer of this exact pattern ever appears.
##
## What this does NOT touch: _attempt_regional_resupply's own INNER
## nearest-supplier search still scans EVERY real settlement as a
## candidate, every single time it runs, completely unbounded --
## deliberately. "Nearest real-surplus settlement" (docs/concept/
## regional_trade.md's own design pillar) is a single cross-settlement
## comparison that has to see the WHOLE real candidate set in one pass to
## answer correctly; spreading that comparison across several ticks the
## way step_settlements' independent per-settlement assessments can be
## paginated would silently risk shipping from a settlement that is not
## actually nearest, or missing a real supplier that exists -- a
## correctness regression, not a perf one. Only HOW OFTEN a background
## settlement gets to ask the question at all is throttled; the answer,
## once asked, is always genuinely correct across every real settlement
## that exists at that moment.
##
## Pinned in tests/unit/test_earth_chunk_manager.gd: a no-op under the cap,
## a hard cap above it, eventual full coverage, round-robin fairness (no
## repeat before every other background settlement has had its own turn),
## and a loaded settlement never deferred -- the exact same guarantees
## _settlement_ids_due_this_step's own tests already pin for
## step_settlements.
const MAX_UNLOADED_SETTLEMENTS_PER_TRADE_STEP := 20
## Session-lifetime rotation cursor for the trade-side pagination above --
## deliberately its OWN field, not step_settlements'
## _unloaded_settlement_step_cursor (see this constant's own doc comment for
## why sharing one would be wrong).
var _unloaded_trade_step_cursor := 0


## Every settlement id step_regional_trade should check as the SHORTAGE side
## THIS tick -- structurally identical to _settlement_ids_due_this_step
## (same background/loaded split, same round-robin slice-selection math),
## kept as its own method/cursor rather than factored into a shared one (see
## MAX_UNLOADED_SETTLEMENTS_PER_TRADE_STEP's own doc comment). Below the cap
## this returns _known_settlement_ids() completely unchanged, the same
## byte-identical no-op guarantee that keeps every pre-existing
## step_regional_trade/caravan test in this file passing unmodified.
func _settlement_ids_due_for_trade_this_step() -> Array[String]:
	var all_ids := _known_settlement_ids()
	var background_ids: Array[String] = []
	for settlement_id in all_ids:
		if not _loaded_villages.has(RegionalTrade.chunk_coord_of(settlement_id)):
			background_ids.append(settlement_id)

	if background_ids.size() <= MAX_UNLOADED_SETTLEMENTS_PER_TRADE_STEP:
		_unloaded_trade_step_cursor = 0
		return all_ids

	var start := _unloaded_trade_step_cursor % background_ids.size()
	var skipped := {}
	for i in range(MAX_UNLOADED_SETTLEMENTS_PER_TRADE_STEP, background_ids.size()):
		skipped[background_ids[(start + i) % background_ids.size()]] = true
	_unloaded_trade_step_cursor = (start + MAX_UNLOADED_SETTLEMENTS_PER_TRADE_STEP) % background_ids.size()

	var due: Array[String] = []
	for settlement_id in all_ids:
		if not skipped.has(settlement_id):
			due.append(settlement_id)
	return due


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

	# Supplier candidates are ALWAYS the full, unpaginated list (see
	# MAX_UNLOADED_SETTLEMENTS_PER_TRADE_STEP's own doc comment) -- only
	# which settlements get checked as the SHORTAGE side this tick is
	# paginated.
	var all_settlement_ids := _known_settlement_ids()
	for settlement_id in _settlement_ids_due_for_trade_this_step():
		for quest in production_shortfall_quests_for_settlement(settlement_id):
			for entry in quest["missing"]:
				_attempt_regional_resupply(settlement_id, entry["item_id"], entry["need"], all_settlement_ids)


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
		chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TerrainRenderer.TILE_SIZE,
		SettlementGenerator.POPULATION, _is_dry_local(chunk_coord),
		seeded_region_for_chunk(chunk_coord)
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
	for event in _event_store.events_for_entity_of_type(settlement_id, "production_succeeded"):
		if event.tags.is_empty():
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
	var latest = _event_store.latest_event_for_entity(path_id)
	if latest != null and latest.type == "path_worn":
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
## IS a currently-worn state -- reclaiming a path that was never worn (or is
## already reclaimed) would not be a real transition, so nothing is
## recorded.
##
## Accepts "trail_formed" alongside "path_worn" as a valid predecessor: a
## tile can decay straight from Trail past Path to bare ground within one
## real gap (a long absence, a big delta) without an intermediate refresh
## ever observing the plain "worn but not a trail" state in between --
## this still has to recognize that as a real reclaim rather than silently
## refusing it because the last-seen tier was the deeper one.
func record_path_reclaimed(tile: Vector2i) -> void:
	var path_id := EntityRef.for_kind("path", "%d_%d" % [tile.x, tile.y])
	var latest = _event_store.latest_event_for_entity(path_id)
	if latest == null or not _CURRENTLY_WORN_EVENTS.has(latest.type):
		return
	var event := Event.new("path_reclaimed", _world_age_seconds)
	event.actors.append(path_id)
	_event_store.append(event)
	_memory_store.witness_event(event, _world_age_seconds)

	# Emergence Phase 10, source 2 (docs/emergence/05 "Ecological
	# transformation... overgrown ruins"): nature reclaiming a path IS this
	# dungeon source, verbatim.
	record_ruin_from_reclaimed_path(path_id, event.id)


## Which event types mean "this path entity is, as of its last recorded
## event, in some currently-worn state" -- read by record_path_reclaimed so
## a full reclaim is recognized whether the tile's last-seen tier was the
## base Path or the deeper Trail (see that function's own doc comment).
const _CURRENTLY_WORN_EVENTS := ["path_worn", "trail_formed"]


## Sustained, heavier use of an already-worn path (docs/concept/
## infrastructure.md's "path -> trail -> road", PathScarring.
## TRAIL_THRESHOLD/is_trail) -- the SAME real path entity deepening, not a
## new kind of thing. Same idempotency shape as record_path_worn_if_new:
## only fires on the actual formation transition.
func record_trail_formed_if_new(tile: Vector2i) -> void:
	var path_id := EntityRef.for_kind("path", "%d_%d" % [tile.x, tile.y])
	var latest = _event_store.latest_event_for_entity(path_id)
	if latest != null and latest.type == "trail_formed":
		return
	var event := Event.new("trail_formed", _world_age_seconds)
	event.actors.append(path_id)
	_event_store.append(event)
	_memory_store.witness_event(event, _world_age_seconds)


## Tapering from Trail back down to an ordinary worn Path -- a real,
## distinct transition from record_path_reclaimed's "reclaimed by nature
## entirely": the ground is still a path, just less intensely used, so this
## does NOT chain into ruin formation the way a full path reclaim does. Only
## fires while the path's most recent event actually IS a trail formation.
func record_trail_reclaimed(tile: Vector2i) -> void:
	var path_id := EntityRef.for_kind("path", "%d_%d" % [tile.x, tile.y])
	var latest = _event_store.latest_event_for_entity(path_id)
	if latest == null or latest.type != "trail_formed":
		return
	var event := Event.new("trail_reclaimed", _world_age_seconds)
	event.actors.append(path_id)
	_event_store.append(event)
	_memory_store.witness_event(event, _world_age_seconds)


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
## All three settling types count. `player_settled` is the player's own (see
## record_player_settled_if_new); `player_house_settled` is a resident who
## moved into a player-built house (see settle_resident_if_new) -- both are
## separate types because neither the player nor a player-house resident's
## own move-in is an ordinary procedural npc_settled, but all three mean
## exactly the same thing HERE, which is why they are read together rather
## than every caller learning the difference.
##
## Deduped by household id: one household is one member however many times it
## was witnessed settling, and without this a household that settled twice
## would inflate the settlement's own tier and institution thresholds.
const SETTLING_EVENT_TYPES := ["npc_settled", "player_settled", "player_house_settled"]


func _households_in_settlement(settlement_id: String) -> Array[String]:
	var household_ids: Array[String] = []
	var seen := {}
	for event in _event_store.events_for_entity_of_types(settlement_id, SETTLING_EVENT_TYPES):
		if event.actors.is_empty():
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
	for event in _event_store.events_for_entity_of_type(settlement_id, "npc_settled"):
		if event.actors.is_empty():
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
	for event in _event_store.events_for_entity_of_type(npc_id, "npc_settled"):
		if not event.witnesses.is_empty():
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
##
## `plots` (docs/concept/building.md "One house id"): VillageLayout's own
## plot list, each carrying `building_index`/`origin`/`building_id` for a
## REAL placed building -- npc index `i`'s own house is the plot whose
## `building_index == i`, not merely "house i" by construction, since a
## villager VillageLayout couldn't fit anywhere is skipped without shifting
## the indices behind it (see VillageLayout's own doc comment). When a
## matching plot exists, ownership is granted through a real
## ConstructionProject started and completed at once -- the SAME
## property_id() scheme stamp_house_and_grant_ownership already grants the
## player's own houses through, so a village house and a player house share
## one id scheme rather than two. Defaults to `[]`, which must behave
## BYTE-IDENTICAL to before this parameter existed: every caller that only
## cares about npcs/households/events (the vast majority of this function's
## own callers, none of them about building ownership specifically) needs no
## change, and a villager with no matching plot -- whether because `plots`
## is empty/omitted, or VillageLayout genuinely left them without a house --
## keeps the exact old per-index id below.
func record_settlement_founded_if_new(chunk_coord: Vector2i, npcs: Array, plots: Array = []) -> void:
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	if _event_store.latest_event_for_entity(settlement_id) != null:
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

	var plot_by_building_index := {}
	for plot in plots:
		plot_by_building_index[plot["building_index"]] = plot

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
		# Phase 3 note). Formed unconditionally -- an economic agent exists
		# even homeless, the same honest state VillageLayout can already
		# leave a villager in.
		var household := _household_store.form_household(npc_ids[i])
		var plot: Variant = plot_by_building_index.get(i)
		if plot != null:
			var project := _construction_project_store.start_project(
				chunk_coord, plot["origin"], plot["building_id"], household.id
			)
			_construction_project_store.complete_project(project.id, _household_store)
		else:
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
	sync_grass_season()
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
	# How far into the CALENDAR season (not the canopy's own turn) this
	# moment sits -- read once, same "one answer, not per tree" discipline
	# as the three canopy locals just above (see leaf_fall_chance_for's own
	# doc comment for why this, not canopy_turn_progress, drives the leaf-
	# fall chance below).
	var season_progress := _season_cycle.progress_through_season(now)
	for trees in _loaded_trees.values():
		for tree in trees:
			# A felled tree stays in the registry after it frees itself --
			# see step_tree_growth, which is where the corpse is dropped.
			if not is_instance_valid(tree):
				continue
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

			# Falling leaves/blossom (see docs/concept/leaf_litter.md): a
			# real leaf (summer/autumn) or blossom petal (spring) falls,
			# driven by the SAME canopy_season/canopy_turn_progress this
			# step already read once above for tree.set_ripe_fruit -- not a
			# second schedule computing its own answer -- plus
			# season_progress (see leaf_fall_chance_for's own doc comment:
			# season_progress drives the RAMP, canopy_turn_progress tapers
			# it back off as the canopy visually finishes emptying into
			# bare winter). Independent of whether fruit fell this same
			# step -- a tree can shed a leaf with nothing left to fruit.
			#
			# Gated on LEAF_LITTER_ENABLED (see that constant's own doc
			# comment) -- requested directly: "deactivate leaf littering".
			if LEAF_LITTER_ENABLED:
				var leaf_fall_chance := leaf_fall_chance_for(
					canopy_season, season_progress, canopy_turn_progress
				)
				if leaf_fall_chance > 0.0:
					# Deterministic per-(tree, step) roll, not engine randf()
					# -- see _LEAF_FALL_ROLL_STEPS' own doc comment.
					var step_bucket := int(now / FRUITING_INTERVAL)
					var roll := PixelNoise.range_index(tree.sprite_seed, step_bucket, 0, _LEAF_FALL_ROLL_STEPS)
					if roll < int(leaf_fall_chance * _LEAF_FALL_ROLL_STEPS):
						var angle := deg_to_rad(float(
							PixelNoise.range_index(tree.sprite_seed, step_bucket + 1, 0, 360)
						))
						var distance_fraction := float(
							PixelNoise.range_index(tree.sprite_seed, step_bucket + 2, 0, 100)
						) / 100.0
						var landing_position: Vector2 = (
							tree.position
							+ Vector2(cos(angle), sin(angle)) * LEAF_SCATTER_RADIUS * distance_fraction
						)
						# Real, individually-addressable litter data (see
						# LeafLitterField), NOT a WorldItemBus/DroppedItem ground
						# item any more -- the whole point of this rewrite (see
						# docs/concept/leaf_litter.md). Species/season stay
						# exactly what they always were; only WHERE that data
						# lives changed. Keyed by the TREE's own chunk (not
						# necessarily whichever chunk_coord _loaded_trees happens
						# to file it under -- see that dict's own flat-iteration
						# doc comment), same lookup take_fruit_at's neighbours
						# use elsewhere in this file.
						var leaf_chunk_coord := _chunk_coord_for_tile(
							_world_tile_for_pixel(tree.position)
						)
						var leaf_field: LeafLitterField = _leaf_litter_fields.get(leaf_chunk_coord)
						if leaf_field != null:
							leaf_field.add_leaf(landing_position, species_id, canopy_season, now)
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


## [0.2, 1.0]: how vigorously vegetation is growing right now (see
## SeasonCycle.growth_modifier) -- for CreatureMarker's own real winter-
## forage-realism fix (see docs/concept/seasonal_behavior.md, "Herbivore
## winter-forage-realism fix"). The SAME signal step_tall_grass already
## feeds real grass maturation with, reused directly rather than a second,
## independent reading of the identical season.
func current_growth_modifier() -> float:
	return _season_cycle.growth_modifier(_world_age_seconds)


## The world clock, in seconds since this world began.
func world_age_seconds() -> float:
	return _world_age_seconds


## Sets the world clock, and keeps every OTHER clock-tracking mark that reads
## against it in step -- the shared plumbing under both
## reset_world_age_to_mid_spring (a brand new world) and load_world_clock (a
## resumed one).
##
## Without this, a mark like _last_fruiting_time/_snow_world_age would still
## read 0 the instant the real clock jumped to its new-game or loaded value,
## and the NEXT step_fruiting/step_snow call would see the whole jump as
## elapsed time -- the same "two clocks that have to agree" trap
## jump_to_season's own doc comment describes, just at world-creation/load
## time instead of a /season skip.
func set_world_age_seconds(value: float) -> void:
	_world_age_seconds = value
	_last_fruiting_time = value
	_snow_world_age = value
	# The canopies are one of those readers, and this is the earliest moment
	# they can possibly be right: both reset_world_age_to_mid_spring (New
	# Game) and load_world_clock (Load Game) come through here BEFORE the
	# first chunk load, so a world that opens in winter opens with bare trees
	# instead of summer ones that correct themselves a tick later (see
	# sync_tree_season).
	sync_tree_season()
	sync_grass_season()


## Sets a brand new world's starting point in the year, once (see
## MID_SPRING_WORLD_AGE_SECONDS) -- called only at New Game/Host Game
## creation (see World._wipe_persisted_world), never on Load Game (see
## load_world_clock, which restores the persisted value instead of
## overwriting it -- a load must resume exactly where the save left off, not
## time-travel to mid-spring on every session).
func reset_world_age_to_mid_spring() -> void:
	set_world_age_seconds(MID_SPRING_WORLD_AGE_SECONDS)


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


## Skips the world FORWARD to `progress` fraction [0,1] into `season` (see
## /season) -- 0.0 (the default) is its start, as before. Returns whether
## that was a season we have.
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
func jump_to_season(season: String, progress: float = 0.0) -> bool:
	var skip: float = _season_cycle.seconds_until_season(_world_age_seconds, season, progress)
	if skip <= 0.0:
		return false
	_world_age_seconds += skip
	_last_fruiting_time = _world_age_seconds
	# /season winter should show winter trees NOW, not once the next fruiting
	# tick comes round -- and on a peer that owns no simulation, never (see
	# sync_tree_season). This skips the clock without going through
	# set_world_age_seconds, so it needs the push of its own.
	sync_tree_season()
	sync_grass_season()
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


## Whether a village would really settle in this chunk -- the SAME
## question VillageRenderer answers at founding (does the layout house the
## whole roster), asked without loading or spawning anything.
##
## has_settlement_at only says a settlement is MEANT to be here; it knows
## nothing about the ground. Since a village only settles where there is
## room for all of it, the two disagree on exactly the chunks a player must
## not be sent to -- reported in play as "It teleports me to where no
## village is".
##
## Occupancy is deliberately "nothing built": this asks the founding-time
## question, which is the one that decides whether a village is ever there
## at all. Run only for chunks that already passed the settlement roll (one
## in SETTLEMENT_CHANCE_DENOMINATOR), so the ring search pays for a layout
## rarely rather than per chunk.
func _village_would_settle(chunk_coord: Vector2i) -> bool:
	var is_dry := _is_dry_local(chunk_coord)
	var settlement := _settlement_generator.generate_settlement(
		chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TerrainRenderer.TILE_SIZE,
		SettlementGenerator.POPULATION, is_dry, seeded_region_for_chunk(chunk_coord)
	)
	var building_ids: Array = SettlementGenerator.house_ids_for(chunk_coord, settlement.npcs)
	var result: Dictionary = VillageLayout.new().layout(
		building_ids, CHUNK_SIZE, VillageLayout.seed_for(chunk_coord),
		is_dry, func(_cell: Vector2i) -> bool: return false
	)
	return VillageLayout.houses_everyone(result, building_ids)


## Nearest chunk hosting a settlement (see SettlementGenerator), searching
## outward from `from_tile`'s own chunk -- the discovery half of the
## /village dev-console command (see World._handle_village_command).
## Returns the settlement's "well" landmark world position (every settlement
## always has one, its natural teleport target -- on the plaza, see
## VillageLayout.skeleton) or null if none is found within
## MAX_VILLAGE_SEARCH_RADIUS_CHUNKS. Pure discovery: doesn't load or spawn
## the found chunk itself -- update() picks that up normally once the player
## arrives.
func find_nearest_village(from_tile: Vector2i) -> Variant:
	var start_chunk := _chunk_coord_for_tile(from_tile)
	# A one-slot box, not a plain local: a GDScript lambda captures locals by
	# VALUE, so the predicate below could not otherwise hand its answer back
	# out. An Array is a reference type and can.
	var landing: Array = [null]
	var found_chunk: Variant = _village_finder.find_nearest(
		start_chunk,
		MAX_VILLAGE_SEARCH_RADIUS_CHUNKS,
		_settlement_generator,
		func(chunk_coord: Vector2i) -> String:
			var chunk := generator.generate_chunk(chunk_coord, CHUNK_SIZE)
			return _biome_classifier.dominant_biome(chunk.biome),
		# The cheap PREDICTION first, then the world itself (docs/concept/
		# village_growth.md, Mechanism 6). _village_would_settle re-derives
		# the roster and the layout and never looks at the ground, because it
		# deliberately loads nothing -- so a chunk it likes can still turn
		# out to be an empty field, which is exactly the second report:
		# "/village teleports me to an empty field...". The load only ever
		# runs for a chunk that already passed the settlement roll AND the
		# prediction, and the player is about to go there anyway.
		func(chunk_coord: Vector2i) -> bool:
			if not _village_would_settle(chunk_coord):
				return false
			var at = standing_village_position(chunk_coord)
			if at == null:
				return false
			landing[0] = at
			return true
	)
	if found_chunk == null:
		return null
	return landing[0]


## Where to land in `chunk_coord`'s village -- a real building's own
## DOORSTEP -- or null when nothing is standing there
## (docs/concept/village_growth.md, Mechanism 6).
##
## A doorstep rather than the planned well: the well comes out of
## VillageLayout.skeleton, which is a plan, while a doorstep is a cell a
## building really has. The lowest (y, x) origin, so the same village answers
## the same way every time rather than by whichever order a Dictionary handed
## its keys back.
##
## Loads the chunk if it is not loaded, and UNLOADS it again if it turns out
## not to be a village -- a rejected candidate leaves nothing behind. A chunk
## that was already loaded is left alone: it may well be the one the player
## is standing in.
func standing_village_position(chunk_coord: Vector2i):
	var was_loaded := _loaded_chunks.has(chunk_coord)
	if not was_loaded:
		_load_chunk(chunk_coord)
	var best: Variant = null
	var best_origin := Vector2i(0, 0)
	for record in buildings_in_chunk(chunk_coord):
		var origin: Vector2i = record["origin_local"]
		if best != null and [origin.y, origin.x] >= [best_origin.y, best_origin.x]:
			continue
		best_origin = origin
		var door: Vector2i = (
			chunk_coord * CHUNK_SIZE + origin + BuildingCatalog.doorstep_of(record.get("id", ""))
		)
		best = (Vector2(door) + Vector2(0.5, 0.5)) * float(TerrainRenderer.TILE_SIZE)
	if best == null and not was_loaded:
		_unload_chunk(chunk_coord)
	return best


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

## A SEPARATE single-purpose map for each tile's real local half-width.
## Width used to ride the direction vector's own magnitude (a direction's
## length otherwise carrying no information) -- but bilinear filtering
## blends GB by ordinary vector addition, and two texels whose BEARINGS
## differ (exactly what neighbouring texels do on a bend) partially
## CANCEL when summed, collapsing the blended magnitude toward zero
## independent of either texel's real width. That corrupted both the
## decoded width (dividing a push by a near-zero half-width) and the
## decoded direction (normalizing a near-zero vector is numerically
## unstable) -- worst exactly on curves, reported as "this huge zigzag
## still persists" after the direction-vector encoding otherwise measurably
## helped. A scalar has no such failure mode: bilinearly blending two
## widths always lands between them. Pinned by
## test_the_scale_map_is_a_real_separate_texture_not_packed_into_direction.
var _flow_scale_image: Image
var _flow_scale_texture: ImageTexture

## How many boulders the shader accepts -- mirrors the uniform array size.
const RIVER_FLOW_BOULDER_SLOTS := 24


func river_flow_boulder_positions() -> PackedVector2Array:
	return _river_flow_boulder_feed()["positions"]


## One radius per fed boulder, in world px, in the SAME order as
## river_flow_boulder_positions -- every rock is a rock of its own size.
func river_flow_boulder_radii() -> PackedFloat32Array:
	return _river_flow_boulder_feed()["radii"]


## The boulder feed, positions and radii built in one pass so the two
## arrays can never disagree about which slot is which rock.
func _river_flow_boulder_feed() -> Dictionary:
	# Prune first: a chunk that unloaded takes its boulders with it, and a
	# stale far-away rock must not hold one of the limited uniform slots.
	var stale: Array = []
	for tile in _river_flow_boulder_tiles:
		if not _loaded_chunks.has(_chunk_coord_for_tile(tile)):
			stale.append(tile)
	for tile in stale:
		_river_flow_boulder_tiles.erase(tile)
	# NEAREST FIRST, then capped -- the same answer _budgeted_load_order
	# already gives for a capped chunk set, and SimulationScheduler for a
	# capped creature step. The slots used to be filled in Dictionary
	# insertion order, i.e. whichever chunk happened to paint first, so once
	# the loaded world held more rocks than slots the water could bend
	# around two dozen rocks off screen while the ones the player is
	# standing next to did nothing at all (measured at the Dreisam fixture:
	# rocks 48 tiles out dropped while rocks 100 tiles out kept their
	# slots). The centre is the tile update() was last called with -- the
	# same one record_water_disturbance already culls distant wakes against.
	var centre := _disturbance_center_tile
	var tiles: Array = _river_flow_boulder_tiles.keys()
	tiles.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return Vector2(a - centre).length_squared() < Vector2(b - centre).length_squared()
	)
	var positions := PackedVector2Array()
	var radii := PackedFloat32Array()
	for tile in tiles:
		if positions.size() >= RIVER_FLOW_BOULDER_SLOTS:
			break
		positions.append(Vector2(
			float(tile.x) * TerrainRenderer.TILE_SIZE + TerrainRenderer.TILE_SIZE * 0.5,
			float(tile.y) * TerrainRenderer.TILE_SIZE + TerrainRenderer.TILE_SIZE * 0.5
		))
		radii.append(RiverFlowShader.boulder_radius_px_for(float(_river_flow_boulder_tiles[tile])))
	return {"positions": positions, "radii": radii}


## Re-evaluates one tile against the flow-boulder predicate and pushes the
## set to the shader -- called from build/destroy so a dropped boulder
## bends the water the moment it lands, and stops the moment it is
## demolished, without waiting for a chunk repaint.
func _sync_flow_boulder(tile: Vector2i) -> void:
	var diameter_cm := flow_boulder_diameter_cm_at_global(tile.x, tile.y)
	if diameter_cm > 0.0:
		_river_flow_boulder_tiles[tile] = diameter_cm
	else:
		_river_flow_boulder_tiles.erase(tile)
	sync_river_flow_boulders()


## One texel of the flow map, written toroidally -- see _flow_across_image.
## Carries the WHOLE per-tile reconstruction frame as REAL floats
## (FORMAT_RGBAF, no encode range): R the signed across-fraction, GB the
## course's downstream UNIT vector (same sin/-cos convention the atlas
## sprite bakes), A the real solved current speed in m/s -- so the shader
## interpolates direction and speed bilinearly exactly like across, and no
## per-tile quantity is left to draw the tile grid. half_width_tiles goes
## into the SEPARATE _flow_scale_image (see that field's own doc comment
## for why it may never share a channel with a vector that gets bilinearly
## filtered).
## every chunk cell no matter how far from any river ever gets a texel
## written here (for the far cell's bilinear neighbours), and its `nearest`
## comes from EarthChunkGenerator.nearest_river_at -- which, once no
## channel (curated or hydrology) is close enough to matter, falls back to
## WHICHEVER curated river is nearest ANYWHERE ON THE PLANET. A cell deep
## in a continent's interior can be 900+ tiles from that river, with a
## totally unrelated width and bearing, and `across_fraction` (that
## distance divided by that river's width) can run into the hundreds --
## bilinearly blended against a real neighbouring texel a few tiles away
## with a normal-sized value, that is an unbounded cliff, not a smooth
## fade. Reported live as a torn, chunky zigzag ("only around bends and
## where the water is deeper at the edge" -- a huge |across| clamps the
## depth shading to its darkest band, and the true-vs-fallback boundary is
## least stable exactly where a bend's curve departs most from a
## straight-line extrapolation). CLAMP_MAGNITUDE is comfortably beyond the
## largest across a channel's OWN real apron+bleed zone can ever produce
## even at HydrologyField.SPRING_HALF_WIDTH_TILES (~12.5), so no genuine
## reading is ever clipped -- only the unrelated-planet-away fallback is.
## Pinned by test_the_written_across_is_always_bounded.
const CLAMP_MAGNITUDE := 16.0


func _write_flow_across_texel(
	global: Vector2i, across_fraction: float, bearing_deg: float, speed_mps: float, half_width_tiles: float,
	drift_speed_m_s: float = 0.0
) -> void:
	var side := RiverFlowShader.FLOW_MAP_TILES
	if _flow_across_image == null:
		_flow_across_image = Image.create(side, side, false, Image.FORMAT_RGBAF)
	if _flow_scale_image == null:
		_flow_scale_image = Image.create(side, side, false, Image.FORMAT_RGBAF)
	var x := posmod(global.x, side)
	var y := posmod(global.y, side)
	var radians := deg_to_rad(bearing_deg)
	var clamped_across := clampf(across_fraction, -CLAMP_MAGNITUDE, CLAMP_MAGNITUDE)
	_flow_across_image.set_pixel(x, y, Color(clamped_across, sin(radians), -cos(radians), speed_mps))
	# G: the reach's drift speed (EarthChunkGenerator.drift_speed_m_s_for_
	# discharge_units) -- constant along a reach, read by the shader through
	# a NEAREST-filtered sampler so no interpolation ramp can diverge.
	_flow_scale_image.set_pixel(x, y, Color(half_width_tiles, drift_speed_m_s, 0.0, 0.0))


## Pushes the filled maps into the shared flow material after a paint pass.
func _push_flow_across_map() -> void:
	if _flow_across_image == null:
		return
	if _flow_across_texture == null:
		_flow_across_texture = ImageTexture.create_from_image(_flow_across_image)
	else:
		_flow_across_texture.update(_flow_across_image)
	if _flow_scale_texture == null:
		_flow_scale_texture = ImageTexture.create_from_image(_flow_scale_image)
	else:
		_flow_scale_texture.update(_flow_scale_image)
	var material := _river_flow_shader.shared_material()
	material.set_shader_parameter("flow_across_map", _flow_across_texture)
	material.set_shader_parameter("flow_scale_map", _flow_scale_texture)
	# The same texture twice: the shader reads half-width through a linear
	# sampler and the reach's drift speed through a nearest one.
	material.set_shader_parameter("flow_drift_map", _flow_scale_texture)


## Pushes the current boulder set into the shared flow material -- called
## after chunk paints and after building/destroying pieces so a dropped
## boulder bends the water the moment it lands.
func sync_river_flow_boulders() -> void:
	var feed := _river_flow_boulder_feed()
	var positions: PackedVector2Array = feed["positions"]
	var radii: PackedFloat32Array = feed["radii"]
	radii.resize(RIVER_FLOW_BOULDER_SLOTS)
	var material := _river_flow_shader.shared_material()
	material.set_shader_parameter("boulder_count", positions.size())
	material.set_shader_parameter("boulders", positions)
	material.set_shader_parameter("boulder_radius", radii)


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


## The SAME wader/fish positions above, fed to every loaded chunk's leaf
## litter field too (see LeafLitterField.set_nearby_waders) -- reported
## directly: fallen leaves/blossoms on a river "should also be influenced
## by turbulence (fish moving; waders)". world.gd passes the identical
## already-computed river_wader_positions() result it hands set_river_flow_
## waders, so a floating leaf's own wobble is driven by the exact same
## obstacles the water's surface art already bends around -- one data
## source, reused, not a second wader gather. Broadcasting the whole
## (small, WADER_SLOTS-capped) list to every field regardless of whether
## that chunk actually has a river is safe and simple: LeafWaterDrift.
## turbulence_velocity_px_s already returns zero for anything outside
## RiverFlowShader.WADER_REACH_PX, so an irrelevant, far-away wader costs
## nothing beyond iterating a short list.
func set_leaf_litter_waders(positions: PackedVector2Array) -> void:
	for field in _leaf_litter_fields.values():
		field.set_nearby_waders(positions)


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


## Turns the river flow overlay's raw-across diagnostic on or off (see
## RiverFlowShader.set_debug_across) -- the /flowdebug console command.
func set_river_flow_debug_across(mode: float) -> void:
	_river_flow_shader.set_debug_across(mode)


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
	roof_layer.z_index = ROOF_LAYER_Z_INDEX
	for chunk_coord in _loaded_chunks:
		_terrain_renderer.paint_roofs(
			_roof_layer, _loaded_chunks[chunk_coord], chunk_coord * CHUNK_SIZE, _hidden_cells_for(chunk_coord)
		)


## Registers the furniture overlay layer (docs/concept/housing.md's
## "Interior furniture" section): a furniture piece shares its cell with the
## floor beneath it, exactly the reason roof pieces already needed their own
## TileMapLayer (see set_roof_layer just above) rather than sharing
## `_tile_map_layer`'s single-tile-per-cell `modifications`. No shape
## classification needed here (unlike roofs' own RoofShape banding) --
## furniture tiles already live in the SAME shared atlas every other
## BuildingPiece uses (TerrainRenderer.atlas_coords_for_modification already
## resolves any BuildingPiece.has_piece id, furniture included, since
## furniture pieces are already real entries in BuildingPiece.PIECE_IDS).
## Optional: a caller that never sets this simply never sees furniture
## rendered, the same fail-open shape _roof_layer/_water_layer already use.
var _furniture_layer: TileMapLayer = null


func set_furniture_layer(furniture_layer: TileMapLayer) -> void:
	_furniture_layer = furniture_layer
	furniture_layer.tile_set = _tile_map_layer.tile_set
	furniture_layer.scale = Vector2.ONE * TerrainRenderer.LAYER_SCALE
	for chunk_coord in _loaded_chunks:
		_paint_furniture(chunk_coord, _loaded_chunks[chunk_coord])


## Paints every real furniture cell already recorded for `chunk` -- a no-op
## if no furniture layer has been registered (fail-open, see set_furniture_
## layer's own doc comment).
func _paint_furniture(chunk_coord: Vector2i, chunk: Chunk) -> void:
	if _furniture_layer == null:
		return
	for local in chunk.furniture_modifications:
		var global: Vector2i = chunk_coord * CHUNK_SIZE + local
		var piece_id: String = chunk.furniture_modifications[local]
		_furniture_layer.set_cell(global, 0, _terrain_renderer.atlas_coords_for_modification(piece_id))


## The player-facing place verb for furniture (docs/concept/housing.md),
## mirroring build_at_global's own shape but writing to chunk.furniture_
## modifications -- its own layer, the same reason roof_modifications needs
## one -- and gated by FurniturePlacement.can_place (real interior floor,
## nothing invented) rather than the general placeable-anywhere-buildable
## rule build_at_global itself applies. False, no mutation, for an unloaded
## chunk or a placement FurniturePlacement itself refuses.
func build_furniture_at_global(global_x: int, global_y: int, piece_id: String) -> bool:
	var chunk_coord := _chunk_coord_for_tile(Vector2i(global_x, global_y))
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk == null:
		return false
	var local := _local_coord(global_x, global_y)
	if not FurniturePlacement.new().can_place(piece_id, local, chunk.modifications, chunk.furniture_modifications):
		return false
	chunk.furniture_modifications[local] = piece_id
	if _furniture_layer != null:
		_furniture_layer.set_cell(
			Vector2i(global_x, global_y), 0, _terrain_renderer.atlas_coords_for_modification(piece_id)
		)
	return true


## Removes a placed furniture piece -- false, no mutation, if there wasn't
## one there. Mirrors destroy_at_global's own split: this only touches the
## world model + rendering; whether/what comes back to an inventory is the
## caller's own decision, the same way destroy_at_global leaves it.
func destroy_furniture_at_global(global_x: int, global_y: int) -> bool:
	var chunk_coord := _chunk_coord_for_tile(Vector2i(global_x, global_y))
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk == null:
		return false
	var local := _local_coord(global_x, global_y)
	if not chunk.furniture_modifications.has(local):
		return false
	chunk.furniture_modifications.erase(local)
	if _furniture_layer != null:
		_furniture_layer.erase_cell(Vector2i(global_x, global_y))
	return true


func furniture_at_global(global_x: int, global_y: int) -> String:
	var chunk: Chunk = _loaded_chunks.get(_chunk_coord_for_tile(Vector2i(global_x, global_y)))
	if chunk == null:
		return ""
	return chunk.furniture_modifications.get(_local_coord(global_x, global_y), "")


## Furnishes a just-stamped house with a real, occupation-linked furniture
## set (see HouseDecor, docs/concept/housing.md's "Occupation-themed decor"
## section). Called by VillageRenderer right after stamp_structure_at_global
## has already written the house's own floor/wall pieces into this same
## chunk -- FurniturePlacement's real interior-floor rule needs those pieces
## already on the chunk to answer RoomDetector.is_indoors truthfully, the
## same ordering build_furniture_at_global's own caller already has to
## respect. `ground_pieces` is the SAME local-cell dict stamp_structure_at_
## global was given for this house -- never a second floor-detection pass --
## and `furniture_ids` is tried in order against that house's own real floor
## cells (in the order they appear in `ground_pieces`), skipping (not
## aborting on) any cell FurniturePlacement itself refuses, so an odd-shaped
## or too-small floor still gets partially furnished rather than emptied.
## Returns how many pieces actually landed, 0 for an unloaded chunk.
func furnish_house_at_global(
	chunk_coord: Vector2i, origin_tile: Vector2i, ground_pieces: Dictionary, furniture_ids: Array
) -> int:
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk == null:
		return 0
	var floor_cells: Array[Vector2i] = []
	for local_cell in ground_pieces:
		if BuildingPiece.category_of(ground_pieces[local_cell]) != BuildingPiece.CATEGORY_FLOOR:
			continue
		var global_cell: Vector2i = origin_tile + local_cell
		if _chunk_coord_for_tile(global_cell) == chunk_coord:
			floor_cells.append(global_cell)
	var placer := FurniturePlacement.new()
	var placed := 0
	var cell_index := 0
	for piece_id in furniture_ids:
		while cell_index < floor_cells.size():
			var global_cell: Vector2i = floor_cells[cell_index]
			cell_index += 1
			var local := _local_coord(global_cell.x, global_cell.y)
			if placer.can_place(piece_id, local, chunk.modifications, chunk.furniture_modifications):
				chunk.furniture_modifications[local] = piece_id
				placed += 1
				break
	if placed > 0:
		_paint_furniture(chunk_coord, chunk)
	return placed


## Two-story houses (docs/concept/housing.md's "Two-story houses" section):
## registers the upper-storey overlay layer, mirroring set_roof_layer/
## set_furniture_layer's own exact "optional, fail-open" shape. Pinned to
## UPPER_FLOOR_LAYER_Z_INDEX -- ABOVE the roof, not between Entities and
## Roof as first shipped: from outside, the only part of an upper storey
## ever drawn is its facade band, one row up, painted over the roof's own
## front row (see _paint_upper_floor), which is what makes a two-story house
## read as one from a bird's-eye view instead of as a one-story house with
## its door painted over.
func set_upper_floor_layer(upper_floor_layer: TileMapLayer) -> void:
	_upper_floor_layer = upper_floor_layer
	upper_floor_layer.tile_set = _tile_map_layer.tile_set
	upper_floor_layer.scale = Vector2.ONE * TerrainRenderer.LAYER_SCALE
	upper_floor_layer.z_index = UPPER_FLOOR_LAYER_Z_INDEX
	for chunk_coord in _loaded_chunks:
		_paint_upper_floor(chunk_coord, _loaded_chunks[chunk_coord], _upper_view_cells_for(chunk_coord))


## How an upper storey is drawn, per cell, decided by where the player is
## (docs/concept/building.md's "How a house reads from above", point 5).
## `house_cells` (local cell keys) is the ONE house the player is currently
## inside -- its room plus wall ring, see _update_upper_floor_visibility --
## drawn in INTERIOR mode; every other upper-storey cell in the chunk is
## drawn in EXTERIOR mode:
##
##   exterior: only a FACADE cell (nothing of the same storey directly south
##       of it -- the same southernmost-per-column rule HouseBlueprint.
##       _facade_cells uses) is drawn, one row UP from where it lives, so it
##       sits over the roof's own front row and the house reads as roof-
##       above-facade-above-facade with the ground door still legible below.
##       Interior, side and back cells are under the roof from outside, the
##       same way the ground floor's own are, and are not drawn at all.
##   interior, floor 0: nothing -- downstairs, the ground room is the view.
##   interior, floor 1: every cell of the storey, in place.
##
## Erases exactly what this chunk painted last time first (_upper_floor_
## painted), since a facade cell's exterior position is not its own cell.
func _paint_upper_floor(chunk_coord: Vector2i, chunk: Chunk, house_cells: Dictionary = {}) -> void:
	if _upper_floor_layer == null:
		return
	for local in _upper_floor_painted.get(chunk_coord, []):
		_upper_floor_layer.erase_cell(chunk_coord * CHUNK_SIZE + local)
	# desired: local cell -> atlas coords. The exterior band is painted from
	# the facade family's UPPER storey (docs/concept/building.md "How a
	# house reads from above", point 6 -- a string course instead of the
	# ground band's plinth, so the two bands read as two storeys, not one
	# row repeated); the storey seen in place from upstairs is its plain
	# wall/window art, the same as the ground room's own interior.
	var desired := {}
	var upstairs := _current_player_floor == 1
	for local in chunk.upper_floor_modifications:
		var piece_id: String = chunk.upper_floor_modifications[local]
		if house_cells.has(local):
			if upstairs:
				desired[local] = _terrain_renderer.atlas_coords_for_modification(piece_id)
		elif _is_upper_facade_cell(chunk, local) and local.y > 0:
			desired[local + Vector2i(0, -1)] = _upper_facade_atlas_coords(piece_id)
	for local in desired:
		_upper_floor_layer.set_cell(chunk_coord * CHUNK_SIZE + local, 0, desired[local])
	_upper_floor_painted[chunk_coord] = desired.keys()


## The upper storey's own front: a cell with nothing of the same storey
## directly south of it (HouseBlueprint._facade_cells' own southernmost-per-
## column rule, read back off the chunk rather than the blueprint, since the
## chunk is all this layer ever sees).
func _is_upper_facade_cell(chunk: Chunk, local: Vector2i) -> bool:
	return not chunk.upper_floor_modifications.has(local + Vector2i(0, 1))


## The tile an upper facade cell is drawn with from outside: the facade
## family's upper-storey variant for a wall/window/door, its plain tile
## for anything else (nothing else is ever a facade cell in practice).
func _upper_facade_atlas_coords(piece_id: String) -> Vector2i:
	var category := BuildingPiece.category_of(piece_id)
	if TerrainRenderer.FACADE_VARIANT_CATEGORIES.has(category):
		return _terrain_renderer.atlas_coords_for_facade_variant(
			BuildingPiece.material_of(piece_id), category, ProceduralBuildingPieceSprite.FACADE_UPPER
		)
	return _terrain_renderer.atlas_coords_for_modification(piece_id)


## Interior furniture on the upper storey (docs/concept/housing.md) --
## optional, fail-open like every other overlay layer here.
var _upper_floor_furniture_layer: TileMapLayer = null


func set_upper_floor_furniture_layer(upper_floor_furniture_layer: TileMapLayer) -> void:
	_upper_floor_furniture_layer = upper_floor_furniture_layer
	upper_floor_furniture_layer.tile_set = _tile_map_layer.tile_set
	upper_floor_furniture_layer.scale = Vector2.ONE * TerrainRenderer.LAYER_SCALE
	upper_floor_furniture_layer.z_index = UPPER_FLOOR_LAYER_Z_INDEX
	for chunk_coord in _loaded_chunks:
		_paint_upper_floor_furniture(chunk_coord, _loaded_chunks[chunk_coord], _upper_view_cells_for(chunk_coord))


## The upper storey's furniture is only ever drawn in place, and only for the
## house the player is actually standing upstairs in (`house_cells`, floor 1
## -- see _paint_upper_floor's own three views): from outside it is under
## the roof, and from the ground floor it is a storey above the room being
## looked at. Deliberately UNLIKE ground _paint_furniture, which never hides
## anything -- nothing ever occludes the ground layer's own room.
func _paint_upper_floor_furniture(chunk_coord: Vector2i, chunk: Chunk, house_cells: Dictionary = {}) -> void:
	if _upper_floor_furniture_layer == null:
		return
	for local in _upper_floor_furniture_painted.get(chunk_coord, []):
		_upper_floor_furniture_layer.erase_cell(chunk_coord * CHUNK_SIZE + local)
	var painted: Array = []
	if _current_player_floor == 1:
		for local in chunk.upper_floor_furniture_modifications:
			if not house_cells.has(local):
				continue
			var piece_id: String = chunk.upper_floor_furniture_modifications[local]
			_upper_floor_furniture_layer.set_cell(
				chunk_coord * CHUNK_SIZE + local, 0, _terrain_renderer.atlas_coords_for_modification(piece_id)
			)
			painted.append(local)
	_upper_floor_furniture_painted[chunk_coord] = painted


func upper_floor_furniture_at_global(global_x: int, global_y: int) -> String:
	var chunk: Chunk = _loaded_chunks.get(_chunk_coord_for_tile(Vector2i(global_x, global_y)))
	if chunk == null:
		return ""
	return chunk.upper_floor_furniture_modifications.get(_local_coord(global_x, global_y), "")


## The local cells `chunk_coord` should currently draw in interior mode --
## the house the player is inside if it is in this chunk, otherwise nothing
## (every storey in exterior mode).
func _upper_view_cells_for(chunk_coord: Vector2i) -> Dictionary:
	if _upper_view_chunk_coord != chunk_coord:
		return {}
	var cells := {}
	for cell in _upper_view_house_cells:
		cells[cell] = true
	return cells


## Only the actual BuildingPiece ids in `chunk.upper_floor_modifications` --
## the SAME real filter _piece_grid_for already applies to the ground
## layer, needed here so RoomDetector can find the upper storey's own real
## enclosed room rather than reading the ground floor's.
func _upper_floor_piece_grid_for(chunk: Chunk) -> Dictionary:
	var grid := {}
	for cell in chunk.upper_floor_modifications:
		var tile_id: String = chunk.upper_floor_modifications[cell]
		if BuildingPiece.has_piece(tile_id):
			grid[cell] = tile_id
	return grid


## Which floor the local player is currently standing on -- called by
## Player itself the moment it steps onto a real wood_stairs piece (see
## step_on_stairs), never guessed at from here.
func set_current_player_floor(current_floor: int) -> void:
	_current_player_floor = current_floor


## The upper-storey twin of _update_roof_visibility, one layer up: works out
## which house (room + wall ring) the player is currently INSIDE -- on the
## floor they are actually standing on, so the upper storey's own real room
## when upstairs, the ground room when not -- and repaints so that ONE house
## is drawn in interior mode while every other upper storey keeps its
## exterior facade-band look (see _paint_upper_floor for the three views).
## Called from update() right after _update_roof_visibility, which hands
## its already-computed ground room in as `ground_room` so the ground-floor
## case costs no second RoomDetector pass per frame; a caller without one
## (null) gets it computed here.
func _update_upper_floor_visibility(player_global_tile: Vector2i, ground_room = null) -> void:
	if _upper_floor_layer == null:
		return

	var chunk_coord := _chunk_coord_for_tile(player_global_tile)
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	var house_cells: Array = []
	if chunk != null:
		var local_cell := _local_coord(player_global_tile.x, player_global_tile.y)
		var room_cells: Array = []
		var structure: Dictionary = chunk.modifications
		if _current_player_floor == 1:
			room_cells = _room_detector.room_containing(local_cell, _upper_floor_piece_grid_for(chunk))
			structure = chunk.upper_floor_modifications
		elif ground_room != null:
			room_cells = ground_room
		else:
			room_cells = _room_detector.room_containing(local_cell, _piece_grid_for(chunk))
		if not room_cells.is_empty():
			house_cells = RoofShape.revealed_cells(room_cells, structure).keys()
			house_cells.sort()

	if (
		chunk_coord == _upper_view_chunk_coord and house_cells == _upper_view_house_cells
		and _current_player_floor == _upper_view_floor
	):
		return  # nothing changed

	# Put whatever was previously drawn in interior mode back to exterior.
	if _upper_view_chunk_coord != null and _loaded_chunks.has(_upper_view_chunk_coord):
		var previous_chunk: Chunk = _loaded_chunks[_upper_view_chunk_coord]
		_paint_upper_floor(_upper_view_chunk_coord, previous_chunk, {})
		_paint_upper_floor_furniture(_upper_view_chunk_coord, previous_chunk, {})

	_upper_view_floor = _current_player_floor
	if house_cells.is_empty():
		_upper_view_chunk_coord = null
		_upper_view_house_cells = []
		return

	_upper_view_chunk_coord = chunk_coord
	_upper_view_house_cells = house_cells
	_paint_upper_floor(chunk_coord, chunk, _upper_view_cells_for(chunk_coord))
	_paint_upper_floor_furniture(chunk_coord, chunk, _upper_view_cells_for(chunk_coord))


func upper_floor_at_global(global_x: int, global_y: int) -> String:
	var chunk: Chunk = _loaded_chunks.get(_chunk_coord_for_tile(Vector2i(global_x, global_y)))
	if chunk == null:
		return ""
	return chunk.upper_floor_modifications.get(_local_coord(global_x, global_y), "")


## The real floor-to-floor transition (docs/concept/housing.md's "Two-story
## houses" section): a real wood_stairs piece sits at the SAME cell on both
## a house's ground and upper layer, so stepping onto it just toggles which
## of the two layers Player itself reads as "the floor I'm on" -- the
## player's own WORLD position never changes, matching the same "no
## teleport, no scene change" shape every other real interaction in this
## codebase already keeps. Returns the new current floor (0 or 1); a no-op
## (returns current_floor unchanged) if global_x/global_y isn't really a
## stairs cell on the floor the caller claims to already be on.
func step_on_stairs(global_x: int, global_y: int, current_floor: int) -> int:
	var piece_id := (
		upper_floor_at_global(global_x, global_y) if current_floor == 1
		else modification_at_global(global_x, global_y)
	)
	if piece_id != "wood_stairs":
		return current_floor
	var new_floor := 0 if current_floor == 1 else 1
	set_current_player_floor(new_floor)
	return new_floor



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


## update()'s per-frame lookups, memoised (FPS regression round 15) -- see
## _update_roof_visibility and _update_geology_reveal. The two counters are
## diagnostics pinned by test_update_roof_visibility_reuses_its_room_lookup_
## while_nothing_changes / test_update_geology_reveal_rescans_for_a_cave_
## entrance_only_on_a_new_tile: how many REAL lookups have been paid.
var room_lookups := 0
var _roof_lookup_chunk = null
var _roof_lookup_cell := Vector2i.ZERO
var _roof_lookup_hash := 0
var _roof_lookup_room: Array = []
var cave_entrance_scans := 0
var _cave_scan_tile = null
var _cave_scan_result = null


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
##
## Returns the ground-floor room the player is standing in (its interior
## cells, local to the player's chunk; empty when outdoors) whether or not a
## roof layer is registered, so _update_upper_floor_visibility, called right
## after it every frame, can reuse the one RoomDetector pass instead of
## running a second identical one.
func _update_roof_visibility(player_global_tile: Vector2i) -> Array:
	var chunk_coord := _chunk_coord_for_tile(player_global_tile)
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	var room_cells: Array = []
	if chunk != null:
		var local_cell := _local_coord(player_global_tile.x, player_global_tile.y)
		# The room lookup is a GDScript flood-fill over the chunk's whole
		# piece grid, and this runs every frame (FPS regression round 15:
		# ~3.8 ms of update() a frame for a standing player). It is memoised
		# on exactly what it reads -- the chunk, the player's cell and the
		# modifications' own hash -- so the stationary-stamp case the doc
		# comment above records still re-checks (a stamp changes the hash),
		# while an unchanged frame answers in O(1) plus one C++ hash.
		var structure_hash := chunk.modifications.hash()
		if (
			chunk_coord == _roof_lookup_chunk and local_cell == _roof_lookup_cell
			and structure_hash == _roof_lookup_hash
		):
			room_cells = _roof_lookup_room
		else:
			room_cells = _room_detector.room_containing(local_cell, _piece_grid_for(chunk))
			room_lookups += 1
			_roof_lookup_chunk = chunk_coord
			_roof_lookup_cell = local_cell
			_roof_lookup_hash = structure_hash
			_roof_lookup_room = room_cells

	if _roof_layer == null:
		return room_cells

	if chunk_coord == _hidden_roof_chunk_coord and room_cells == _hidden_roof_room_cells:
		return room_cells  # nothing changed -- still in the same room (or still outside)

	# Un-hide whatever was previously hidden.
	if _hidden_roof_chunk_coord != null and _loaded_chunks.has(_hidden_roof_chunk_coord):
		var previous_chunk: Chunk = _loaded_chunks[_hidden_roof_chunk_coord]
		_terrain_renderer.paint_roofs(_roof_layer, previous_chunk, _hidden_roof_chunk_coord * CHUNK_SIZE, {})

	if room_cells.is_empty():
		_hidden_roof_chunk_coord = null
		_hidden_roof_room_cells = []
		return room_cells

	_hidden_roof_chunk_coord = chunk_coord
	_hidden_roof_room_cells = room_cells
	# The room's own cells AND the wall ring around it -- see
	# RoofShape.revealed_cells for why the walls have to come off too now
	# that roofs cover them.
	_terrain_renderer.paint_roofs(
		_roof_layer, chunk, chunk_coord * CHUNK_SIZE,
		RoofShape.revealed_cells(room_cells, chunk.modifications)
	)
	return room_cells


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
	# Nine biome reads and entrance rolls a frame for a player who has not
	# moved (FPS regression round 15) -- entrance placement is a pure
	# function of the tile, so the answer is kept until the tile changes.
	var entrance_tile
	if player_global_tile == _cave_scan_tile:
		entrance_tile = _cave_scan_result
	else:
		entrance_tile = _nearby_cave_entrance(player_global_tile)
		cave_entrance_scans += 1
		_cave_scan_tile = player_global_tile
		_cave_scan_result = entrance_tile

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


## One rock, one rule, whatever STYLE of water its tile is painted as.
##
## "ONE WATER SURFACE (docs/concept/hydrology.md): rivers, lakes and the sea
## all ride this overlay" -- _paint_river_flow_overlay's own opening comment
## -- so a boulder standing in a pond parts its surface exactly like one
## standing mid-stream, and the shader has a single boulder uniform set for
## all of them. But only the flowing-river branch ever collected a rock; the
## still-water and shore-band branches ERASED unconditionally, so every
## boulder in a lake, a pond, a sea pocket, a river-mouth plume or a lake
## feather silently did nothing to the water.
##
## That is not a rare corner: a tile can be a curated river cell AND be
## classified a lake by the baked hydrology field at the same time (this
## game's own Dreisam spawn is exactly that -- is_river_at_global true,
## hydrology kind "lake"), so even a boulder the player drops in the river
## in front of them stopped bending the water as soon as its chunk was
## repainted. Reported live: "the boulders in the river doesn't affect
## hydrology whirls and such correctly".
##
## Stores the rock's real DIAMETER, never a flag: _river_flow_boulder_feed
## reads these values back as cm to size each rock's radius, and the push
## reach, the eyot, the shoal, the foam and the wake all scale from that
## radius.
## The cross-section reading for a cell of a dug pond: how close it is to
## the pond's own bank, in the same across-fraction units every other kind
## of water writes (|across| under 1 is water, 1 is the bank line).
##
## A pond has no channel and no spill to solve a contour from -- it is a
## flat-bottomed hole of a fixed size -- so its rim is read straight off
## its own shape: a cell with dry ground orthogonally beside it is a bank
## cell and reads near the waterline, a cell surrounded by its own water
## reads as open water. On a 3x2 pond every cell is a rim cell, which is
## correct: a pond that small IS all shore.
const POND_RIM_ACROSS := 0.75


func _pond_across_at(global: Vector2i) -> float:
	for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var neighbour: Vector2i = global + step
		if not is_pond_at_global(neighbour.x, neighbour.y):
			return POND_RIM_ACROSS
	return 0.0


func _collect_flow_boulder(global: Vector2i) -> void:
	var diameter_cm := flow_boulder_diameter_cm_at_global(global.x, global.y)
	if diameter_cm > 0.0:
		_river_flow_boulder_tiles[global] = diameter_cm
	else:
		_river_flow_boulder_tiles.erase(global)


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
			# A dug pond is the ONE water the generator cannot know about --
			# it is a village/player MODIFICATION, and everything below asks
			# the generated world -- so it is answered before the probe.
			# Without this a pond fell through to "nothing is water here"
			# and had its overlay cell erased, leaving the flat `pond_water`
			# tile as the only blue on screen: reported live as "it's a
			# procedural entity layn over and not properly dug / built
			# pond". It rides the one water surface now, like every lake and
			# every sea pocket, so it gets the same waterline, ink edge,
			# shore feather and ripples.
			if is_pond_at_global(global.x, global.y):
				_write_flow_across_texel(
					global, _pond_across_at(global), 0.0, 0.0,
					RiverCatalog.RIVER_HALF_WIDTH_TILES, 0.0
				)
				_collect_flow_boulder(global)
				_river_flow_layer.set_cell(
					global, 0, _terrain_renderer.atlas_coords_for_river_flow(0.0, false)
				)
				continue
			var probe := generator.hydrology_at_global(global.x, global.y)
			var still_across: float = probe["lake_across"]
			# The SAME still-water rule is_water_at_global reads (see
			# is_still_water_probe) -- what is painted here is, by
			# construction, exactly what nothing may be built on.
			if is_still_water_probe(probe):
				# A river mouth's current runs on into the still water and
				# fades (HydrologyField.mouth_plume): the texel carries the
				# mouth's bearing and a fading speed, so the flow lines
				# continue out of the mouth and settle into ripples.
				var plume_speed: float = HydrologyField.PLUME_SPEED_M_S * probe["plume_factor"]
				_write_flow_across_texel(
					global, still_across, probe["plume_bearing_deg"], plume_speed,
					RiverCatalog.RIVER_HALF_WIDTH_TILES,
					generator.drift_speed_m_s_for_discharge_units(probe.get("plume_reach_discharge", 0.0))
				)
				_collect_flow_boulder(global)
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
			#
			# A SECOND, wider ring past the apron is still PAINTED, not
			# erased (RiverFlowShader.SHORE_BLEED_TILES): the apron alone
			# is just wide enough for the bank feather itself, so a wader's
			# wake or a boulder's shore band reaching even slightly past it
			# had no tile left to draw on and simply vanished -- reported live
			# as a player's own splash trail cutting off mid-stride on the
			# way out of the water. This ring stays fully transparent by
			# construction (its baseline |across| sits well past the
			# feather) unless something genuinely reaches it.
			var bleed := apron + RiverFlowShader.SHORE_BLEED_TILES
			if nearest.distance_tiles > bleed:
				_river_flow_layer.erase_cell(global)
				# Still write the texel: a dry cell one tile past the bleed
				# is a bilinear NEIGHBOUR of a wet one, and an unwritten
				# texel there would bleed garbage into the waterline.
				var far_hydraulics := generator.river_hydraulics_at_global(
					global.x, global.y
				)
				_write_flow_across_texel(
					global,
					nearest.signed_across_tiles / half_width,
					nearest.course_bearing_deg,
					far_hydraulics.velocity_m_s,
					half_width,
					nearest.get("drift_speed_m_s", 0.0)
				)
				# Past the bleed nothing is drawn as water, so no rock here
				# can be a flow boulder. A plain erase, never the predicate:
				# this is the far majority of a chunk's tiles and it must
				# stay free.
				_river_flow_boulder_tiles.erase(global)
				continue
			if nearest.distance_tiles > apron:
				var apron_hydraulics := generator.river_hydraulics_at_global(
					global.x, global.y
				)
				_write_flow_across_texel(
					global,
					nearest.signed_across_tiles / half_width,
					nearest.course_bearing_deg,
					apron_hydraulics.velocity_m_s,
					half_width,
					nearest.get("drift_speed_m_s", 0.0)
				)
				_collect_flow_boulder(global)
				_river_flow_layer.set_cell(
					global, 0,
					_terrain_renderer.atlas_coords_for_river_flow(
						nearest.course_bearing_deg,
						RiverFlowShader.is_fast_flow(apron_hydraulics.velocity_m_s)
					)
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
				nearest.course_bearing_deg, hydraulics.velocity_m_s, half_width,
				nearest.get("drift_speed_m_s", 0.0)
			)
			_collect_flow_boulder(global)
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
## Whether precipitation is actively falling as snow RIGHT NOW, as of the
## last step_snow call -- distinct from _snow_depth, which is how much has
## already piled up. Cached here (rather than recomputed by each reader) so
## every reader agrees with what the ground is accumulating against; see
## is_snowing.
var _snowing := false
## The last tile tread_snow_at was called with -- the trail mask window (see
## _refresh_snow_trail_mask) is centred here, since SnowTrail's own
## dictionary carries no notion of "where the player is" by itself.
var _snow_trail_center_tile := Vector2i.ZERO

## The last tile the PLAYER's own tread call (move_trail_window=true) landed
## on -- see tread_snow_at's own doc comment for why only the player's call
## is debounced by tile entry here. Sentinel far outside any reachable tile,
## so the first real call always counts as "newly entered" (mirrors World.
## _last_scar_step_tile's identical convention for PathScarring).
var _last_player_snow_tile := Vector2i(-2147483648, -2147483648)

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


## Whether it is actively snowing right now, as of the last step_snow call --
## see docs/concept/weather.md's "Weather feeds creature behaviour". The same
## boolean World already computes each frame to accumulate _snow_depth
## against (see step_snow below); a second reader (CreatureMarker) reads
## THIS rather than deriving its own answer, so an animal can never disagree
## with the ground about whether it's snowing right now.
func is_snowing() -> bool:
	return _snowing


## Marks a tile as walked on, packing the snow down (see SnowTrail). The
## actual GPU-facing mask texture is rebuilt once per step_snow call, not
## here -- see _refresh_snow_trail_mask.
##
## move_trail_window controls whether THIS call also re-centres the trail
## mask window (see _snow_trail_center_tile's own doc comment) -- true by
## default, which is what the player's own per-frame call wants: the window
## has to follow wherever the player is standing. World.gd calls this for
## every individually-simulated CreatureMarker too (see docs/concept/
## snow_cover.md's "Footprints" section) with move_trail_window = false, so a
## creature packs down the exact same SnowTrail data and reaches the exact
## same shared mask the player's own tread does, WITHOUT relocating the
## window to wherever the last-processed creature happens to be -- which
## would risk carrying the player's own nearby tracks right out of the
## window the instant a creature updates after them in the same frame.
##
## The PLAYER's own call (move_trail_window=true) only steps on a genuinely
## NEW tile -- mirrors World._last_scar_step_tile's identical debounce for
## PathScarring. Reported live: "should also remove snow gradually when
## walking back and forth". This used to fire every single RENDERED FRAME
## with no gate at all, so a tile saturated to SnowTrail.MAX_TREAD within
## about three frames of first entry (TREAD_PER_STEP=0.34) regardless of
## whether the player kept walking -- reading as an instant flat clearing,
## not a gradual one, and making repeated visits pointless since the tile
## was already maxed out after the very first pass. A creature's own call
## (move_trail_window=false) is deliberately NOT debounced here -- doing so
## would need a per-creature "last tile" (a field on every CreatureMarker,
## or a Dictionary keyed by instance here), and the reported complaint is
## specifically about the player's own repeated walking.
func tread_snow_at(pixel_position: Vector2, move_trail_window: bool = true) -> void:
	if _snow_depth <= 0.0:
		return
	var tile := _world_tile_for_pixel(pixel_position)
	if move_trail_window:
		if tile == _last_player_snow_tile:
			return
		_last_player_snow_tile = tile
		_snow_trail_center_tile = tile
	_snow_trail.step_on(tile)


## Above this, two consecutive record_footstep calls are treated as a
## teleport/respawn (dev command, save load, spawn) rather than real
## continuous walking -- re-baselines without stamping a stray print
## bridging the gap. Comfortably larger than any plausible single real
## frame's movement even sprinting (Player.BASE_SPEED is 80px/s; even a
## generously slow 10fps frame only covers ~40px at a hypothetical 5x
## speed multiplier), small enough to still catch a genuine teleport,
## which is typically hundreds to thousands of pixels.
const _FOOTSTEP_TELEPORT_GAP_PX := 200.0

## Which surface (see FootprintRenderer.SURFACES) a footstep on ground
## whose real biome is `biome` should stamp, given whether snow currently
## lies -- "" means no footprint at all. Pure and directly testable
## independent of a real loaded chunk; record_footstep is the thin
## integration wrapper that resolves the real biome/snow_depth and calls
## this. Precedence mirrors PathScarring's own identical snow gate
## exactly: snow_depth() is a single GLOBAL scalar, not per-tile (see
## Snowfall/step_snow), so snow lying at all means every step everywhere
## is a snow print regardless of biome; otherwise the same PATH_SCAR_
## BIOMES-shaped list (grassland/forest only -- reported live: "proper
## pathscarring for grass and forest tiles") gates grass/forest, exactly
## like World._step_path_scarring's own gate already does for its wear
## tracking. Any other biome (desert, mountain, tundra, rainforest,
## ocean) gets no footprint at all -- this feature's own explicit scope.
##
## `underwater` (asked directly: "underwater footprints should be
## tinted") is a pure OVERRIDE on top of whatever biome would otherwise
## give a real footprint -- a river or lake never changes biome_at_
## global's own result (see docs/concept/rivers.md), so a river crossing
## grassland/forest still reads as that same dry biome underneath; this
## is what actually distinguishes "stepping in the river" from "stepping
## on the bank" for a footprint's own look. It does NOT invent a
## footprint anywhere a dry biome wouldn't already have one -- a true
## "ocean" biome tile still gets none at all, underwater flag or not.
## Snow still wins over it (frozen water is not open water), matching
## snow's existing top priority exactly. Defaults to false so every
## pre-existing 2-arg call site across the whole project is unaffected.
const _SURFACE_BY_FOOTSTEP_BIOME := {"grassland": "grass", "forest": "forest"}

static func footstep_surface_for(biome: String, snow_lying: bool, underwater: bool = false) -> String:
	if snow_lying:
		return "snow"
	var surface := String(_SURFACE_BY_FOOTSTEP_BIOME.get(biome, ""))
	if surface.is_empty():
		return ""
	return "underwater" if underwater else surface


## Real per-step footfall placement (see FootstepGait, FootprintField --
## reported live: "real footstep prints with left/right footprints spaced
## apart and stamped into the snow with displacement (snow amount should
## still be reduced)... also implement proper pathscarring for grass and
## forest tiles"). Called every frame with the walker's own continuous
## position and real travel heading -- mirrors tread_snow_at/World.
## _step_path_scarring's own "read the walker's continuous state every
## frame, let the underlying mechanism decide whether anything actually
## happens" shape, just driven by real distance (FootstepGait) rather
## than tile-entry debounce, since an individual foot-fall is a finer
## grain than either of those. `heading` orients the print (see
## FootstepGait.print_offset) -- Player.facing_direction() for the real
## player.
##
## Deliberately does NOT touch SnowTrail/PathScarring's own existing
## snow-depth-reduction/wear tracking at all -- those keep working exactly
## as before (see snow_depth()/tread_snow_at, PathScarring.step_on); this
## is a purely additive VISUAL layer stamped on top of whatever those
## mechanisms already do underneath.
## Returns the raw biome/snow/underwater/ground-material facts behind a
## real step (empty Dictionary when nothing happened this call --
## baseline, teleport, or no stride due yet) so a caller can trigger a
## footstep SOUND at the exact same real per-step cadence the visual print
## already uses, without re-deriving FootstepGait's own accumulator a
## second time. `ground_material` is what the foot actually touches (see
## GroundImprint.material_underfoot) -- a laid street is stone even though
## the biome under it still reads grassland, exactly as a river leaves the
## biome under it alone, so the sound needs it as its own fact rather than
## inferring it from the biome.
##
## Deliberately NOT an audio surface key -- EarthChunkManager (world
## state) must not
## depend on FootstepSound (audio); that dependency runs the other way,
## the same direction NatureSoundscapePlayer already reads real world
## state rather than World reading audio state. The caller feeds these
## facts into FootstepSound.surface_for itself -- which is also why
## `ground_material` is the raw material ("stone"), not the sound it maps
## to ("rock").
##
## Populated even when the VISUAL footprint has no art for this biome
## (see footstep_surface_for's own narrower `_SURFACE_BY_FOOTSTEP_BIOME`)
## -- FootstepSound's own surface coverage is deliberately wider than the
## footprint sprite's, so audio must not silently inherit the narrower
## visual gap (reported live: "we need footsteps", a general ask, not
## just for the biomes that already draw a print).
##
## `gait`/`mass_kg` (added for real per-CreatureMarker footprints, see
## docs/concept/snow_cover.md's "Footprints depend on real mass, not just
## surface") default to the PLAYER's own existing single continuous
## accumulator and real mass -- every pre-existing 2-arg call site across
## the whole project keeps resolving to EXACTLY today's behavior and print
## size. A caller with its own walker (a CreatureMarker's own lazily-built
## FootstepGait, see that class's own footstep_gait() doc comment) passes
## both explicitly instead, so this one function serves every walker in
## the game, not a player-only special case duplicated elsewhere.
func record_footstep(
	pixel_position: Vector2, heading: Vector2,
	gait: FootstepGait = null, mass_kg: float = CreatureMass.PLAYER_MASS_KG
) -> Dictionary:
	var walker_gait := gait if gait != null else _player_footstep_gait
	var side := walker_gait.step_at(pixel_position, _FOOTSTEP_TELEPORT_GAP_PX)
	if side.is_empty():
		return {}
	var tile := _world_tile_for_pixel(pixel_position)
	var underwater := is_river_at_global(tile.x, tile.y) or is_lake_at_global(tile.x, tile.y)
	var snow_lying := _snow_depth > 0.0
	# What the foot actually touches here -- the biome's own soil, the snow
	# lying on top of it, or something LAID (see GroundImprint.
	# material_underfoot). Resolved ONCE, for both consumers: the print gate
	# below reads it to decide whether this ground can be indented at all,
	# and the returned facts carry it out to FootstepSound so a laid street
	# stops sounding like the grass beside it. One step, one ground -- the
	# print and the sound cannot disagree about what was underfoot.
	var ground_material := GroundImprint.material_underfoot(modification_at_global(tile.x, tile.y), snow_lying)
	# biome_at_global(tile.x, tile.y) stays INLINE in the footstep_surface_for
	# call below (not hoisted into a shared variable) -- test_record_
	# footstep_passes_a_third_argument_to_footstep_surface_for's own source-
	# text assertion counts commas across exactly that call expression,
	# nested call included; hoisting would silently drop it below the
	# comma count that test pins. A second, cheap lookup call here (for the
	# returned Dictionary) is a small, deliberate price for not weakening
	# that existing regression check.
	var result := {
		"side": side,
		"biome": biome_at_global(tile.x, tile.y),
		"snow_lying": snow_lying,
		"underwater": underwater,
		"ground_material": ground_material,
	}
	var surface := footstep_surface_for(biome_at_global(tile.x, tile.y), snow_lying, underwater)
	if surface.is_empty():
		return result
	# Whether that ground gives way at all is a real indentation-hardness
	# question rather than a biome one -- see GroundImprint, which compares
	# a real footfall's own pressure against the material's own published
	# one. A laid cobbled street is granite setts, orders of magnitude past
	# anything a foot can press with, so it keeps no mark at all (reported
	# live: "walking over cobblestone streets should not leave
	# footprints").
	#
	# Deliberately AFTER `result` is fully populated and returned intact:
	# a step on a street really did happen, so FootstepSound still hears it
	# (see this function's own doc comment on why the returned facts are
	# wider than the visual print's own coverage). Only the MARK is absent.
	if not GroundImprint.yields_to_footfall(ground_material):
		return result
	var print_position := pixel_position + FootstepGait.print_offset(heading, side)
	var chunk_coord := _chunk_coord_for_tile(_world_tile_for_pixel(print_position))
	var field: FootprintField = _footprint_fields.get(chunk_coord)
	if field == null:
		return result
	var size_scale := CreatureMass.linear_scale_for_mass_ratio(mass_kg, CreatureMass.PLAYER_MASS_KG)
	field.add_print(print_position, side, surface, heading, _world_age_seconds, size_scale)
	return result


## Ages/prunes every loaded chunk's FootprintField and refreshes its
## MultiMeshes -- mirrors step_leaf_litter's own dirty-tracking shape
## exactly (compare generation() against the last-pushed record, skip the
## MultiMesh rebuild entirely once a chunk's prints have stopped changing
## -- see docs/concept/soil_fauna.md's "FPS regression round 4" for why
## that comparison matters, not a periodic throttle).
func step_footprints() -> void:
	for chunk_coord in _footprint_fields:
		var field: FootprintField = _footprint_fields[chunk_coord]
		var visible := _decorates(chunk_coord)
		# Far-chunk gate (see FAR_CHUNK_ADVANCE_SECONDS): advance() takes the
		# absolute world clock, so a chunk nobody can see loses nothing by
		# advancing once per interval instead of every frame.
		if visible or _world_age_seconds - float(_footprint_far_advanced_at.get(chunk_coord, -INF)) >= FAR_CHUNK_ADVANCE_SECONDS:
			# Rain hurries a print away (docs/concept/snow_cover.md's
			# "Footprints"): the wetness is sampled per step rather than
			# stored per print, because a print cannot know what weather is
			# coming.
			field.advance(_world_age_seconds, _rain_wetness)
			_footprint_far_advanced_at[chunk_coord] = _world_age_seconds
		# A typed Dictionary cannot hold the Nil a missing entry returns --
		# every real chunk has its renderers, but a field injected on its own
		# (tests) does not, and the old `= .get(chunk_coord)` blew up on it.
		var mmis: Dictionary = _footprint_mmis.get(chunk_coord, {})
		if mmis.is_empty():
			continue
		for surface in FootprintRenderer.SURFACES:
			if mmis.has(surface):
				mmis[surface].visible = visible
		if visible and _footprint_filled_generation.get(chunk_coord, -1) != field.generation():
			_footprint_renderer.fill(mmis, field.prints())
			_footprint_filled_generation[chunk_coord] = field.generation()


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
	_snowing = snowing
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
##
## River and lake tiles are DELIBERATELY left painted, not excluded like
## ocean -- see docs/concept/snow_cover.md#snow-under-a-river-reads-as-a-
## staircase. Excluding them (as this used to) meant a whole tile lost its
## snow at the coarse, binary, RIVER_HALF_WIDTH_TILES-distance granularity
## Chunk.is_river/is_lake are baked at, while the river-flow overlay's own
## visible edge is a smooth, continuous, sub-tile curve -- the two
## boundaries don't coincide except by accident, and the mismatch reported
## as a staircase along any curved or diagonal reach. SnowFx is an EARLIER
## sibling than RiverFlowFx (test_world_ground_layer_order.gd), so the
## river already draws on top of this layer every frame; a painted river
## cell is simply hidden by it, seamlessly, at the river's own real edge --
## unlike GroundDecor (grass/trees), which draws OVER the river and so
## still needs its own placement exclusion (tall_grass.gd/tree_renderer.gd)
## to avoid standing visibly in the water.
func _paint_snow_presence(chunk_coord: Vector2i, chunk: Chunk) -> void:
	if _snow_layer == null:
		return
	var origin: Vector2i = chunk_coord * CHUNK_SIZE
	for y in chunk.height:
		for x in chunk.width:
			var global := origin + Vector2i(x, y)
			# Ocean does not take snow -- it freezes or it does not, which is
			# a different thing and not this one. Ocean has no analogous
			# on-top overlay to hide a painted cell (WaterFx is a coarser
			# shore-distance tile approach, not the river's continuous
			# field), so it stays a real exclusion, not just a paint-under.
			if chunk.biome[y * chunk.width + x] == "ocean":
				continue
			_snow_layer.set_cell(global, 0, SnowBombShader.PRESENCE_ATLAS_COORD)


## How hard it is raining right now, 0 dry and 1 a downpour -- pushed in by
## set_rain below and read by step_footprints, because a footprint field
## knows how to weather faster when it is wet but cannot know THAT it is
## wet. Starts dry: a world nobody has told about the weather must not age
## its prints as though it had rained.
var _rain_wetness := 0.0


func set_rain(raining: bool) -> void:
	var intensity := 1.0 if raining else 0.0
	_rain_wetness = intensity
	if _water_material != null:
		_water_material.set_shader_parameter("rain_intensity", intensity)
	# Rivers/lakes/the sea all render on the ONE river flow overlay in real
	# gameplay (see _paint_water_overlay's own doc comment) -- the OLD
	# ocean-only _water_material above never actually paints a cell once a
	# river flow layer exists, so without this, rain-driven ripples were
	# invisible everywhere, not just on rivers (reported: "rain don't
	# produce ripples in the new river water"). Unconditional, matching
	# _mirror_disturbances_to_the_river's own convention: _river_flow_shader
	# always exists, and pushing a uniform to a material no layer is
	# currently using yet is harmless.
	_river_flow_shader.set_rain_intensity(intensity)


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
	IllustratedWheatPatch.set_wind_strength(strength)


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
	_current_sun_elevation_deg = elevation_deg


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
	_mirror_disturbances_to_the_river()


## Ages every live water disturbance so its ring actually expands/fades on
## screen (see WaterShader.advance_disturbances) -- must run every frame,
## not just when a new disturbance is recorded. The flow overlay's rings
## age on the shader's own clock; here they are only pruned once faded.
func step_water_disturbances(delta: float) -> void:
	_water_shader.advance_disturbances(delta)
	_mirror_disturbances_to_the_river()


## Whether the river surface currently holds any live ripple -- so a river
## with nothing moving in it costs nothing per frame, while the frame that
## empties the buffer still gets pushed (otherwise the last wake would
## hang there forever).
var _river_disturbances_live := false


## Hands the river surface the SAME buffer the sea's is drawing. Rivers are
## no longer painted by the ocean overlay at all (see _paint_water_overlay:
## the flow overlay is the river's entire water surface now), so without
## this a fish's wake is recorded, aged, and drawn into a layer that river
## tiles do not have -- reported as ripples having disappeared from the
## river entirely. RiverFlowShader keeps no buffer of its own on purpose:
## one lifetime, one cap, one distance cull, two surfaces.
func _mirror_disturbances_to_the_river() -> void:
	var count := _water_shader.disturbance_count()
	if count == 0 and not _river_disturbances_live:
		return
	_river_disturbances_live = count > 0
	_river_flow_shader.set_disturbances(
		_water_shader.padded_disturbance_positions(),
		_water_shader.padded_disturbance_ages(),
		count
	)


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
			# A felled tree stays in the registry after it frees itself, and
			# reading .position off the corpse does not merely log -- it
			# ABORTS this walk, so every tree after it goes unreported and
			# the caller is told the forest is empty.
			if not is_instance_valid(tree):
				continue
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


## Narrows `positions` (candidate seed sources for TreeSpread.propose_
## saplings, i.e. step_tree_spread's own dominant reproduction path -- see
## docs/concept/flora.md#where-a-forest-comes-from) to ones actually
## eligible to spread this cycle.
##
## TreeMaturity.mature_positions/TreeSpread.propose_saplings carry bare
## Vector2 positions with no species or pollination awareness at all, by
## design (see tree_maturity.gd's own doc comment) -- gating happens HERE,
## a filter step ahead of both, rather than changing either pure, already-
## tested signature. An insect-pollinated tree (TreeSpecies.
## needs_pollinators_for) only counts as a seed source if it was actually
## visited at least once this bearing cycle -- an unvisited one set no real
## fruit (see FruitingModel.pollination_factor's own hard gate), so it has
## nothing real to spread from. Every wind-pollinated species passes
## through untouched. A position with no resolvable tree node in
## `_loaded_trees` fails OPEN (spreads) rather than being silently dropped
## for a data gap this filter has no way to judge.
##
## Does not change what a NEW sapling becomes: a spread tree's own species
## is still derived purely from ITS OWN landing position (see
## TreeMaturity's own doc comment), never inherited from whichever parent
## seeded it -- this only decides which existing trees are allowed to seed
## at all.
func _pollination_eligible_tree_positions(positions: Array) -> Array:
	var tree_at := {}
	for trees in _loaded_trees.values():
		for tree in trees:
			if is_instance_valid(tree):
				tree_at[tree.position] = tree

	var eligible: Array = []
	for position in positions:
		var tree = tree_at.get(position)
		if tree == null:
			eligible.append(position)
			continue
		var species_id := TreeSpecies.species_for_bias(tree.species_bias)
		if not TreeSpecies.needs_pollinators_for(species_id):
			eligible.append(position)
			continue
		if tree.pollination_visits_in_cycle(FruitingModel.BEARING_CYCLE_SECONDS, _world_age_seconds) > 0.0:
			eligible.append(position)
	return eligible


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
	sync_grass_season()


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

	var mature_positions := _pollination_eligible_tree_positions(_mature_tree_positions())
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
	if BuildingPiece.touches_piece(chunk.modifications, local) or BuildingCatalog.touches_building(chunk.modifications, local):
		return false  # ...and nothing takes root on a house's own one-cell apron either (its doorstep stays clear)
	if TerrainRenderer.is_road_tile(chunk.modifications.get(local, "")):
		return false  # a laid road is a built surface too (docs/concept/infrastructure.md's Road tier)
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
	for chunk_coord in _loaded_trees:
		var trees: Array = _loaded_trees[chunk_coord]
		var survivors: Array = []
		for tree in trees:
			if not is_instance_valid(tree):
				continue
			survivors.append(tree)
			if not ("planted_at" in tree) or tree.planted_at <= 0.0:
				continue
			if not tree.has_method("set_age"):
				continue
			tree.set_age(_world_age_seconds - tree.planted_at)
		# This walk visits every loaded tree every tick anyway, so it is the
		# one place that can drop the corpses for free. Without it a chunk
		# that is never unloaded accumulates one dead entry per tree ever
		# felled, and every other walk pays a validity check for each.
		if survivors.size() != trees.size():
			_loaded_trees[chunk_coord] = survivors


## How often the tall-grass sprite layer re-syncs to the simulation (and
## nearby herbivores get a chance to graze a patch). The sims themselves
## advance every call; only the node churn is throttled.
const GRASS_REFRESH_INTERVAL := 5.0

## How often wild mushroom patches re-check for a flush and re-sync their
## markers -- same order of magnitude as GRASS_REFRESH_INTERVAL immediately
## above (a real fruiting event is not something that needs checking every
## frame either).
const MUSHROOM_REFRESH_INTERVAL := 5.0

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


## Mirrors step_tall_grass's own batched-refresh shape exactly (real growth
## every call is unnecessary work at 60fps to resolve 0.01/second of
## change -- see that function's own doc comment) -- reuses the identical
## GRASS_REFRESH_INTERVAL throttle rather than a redundant third constant
## for the identical "plant growth/sprite refresh" concept
## step_worms/step_ants already reuse WORM_REFRESH_INTERVAL for in their
## own turn.
func step_aquatic_vegetation(delta_seconds: float) -> void:
	_aquatic_vegetation_refresh_accumulator += delta_seconds
	if _aquatic_vegetation_refresh_accumulator < GRASS_REFRESH_INTERVAL:
		return
	var elapsed := _aquatic_vegetation_refresh_accumulator
	_aquatic_vegetation_refresh_accumulator = 0.0

	var growth_modifier := _season_cycle.growth_modifier(_world_age_seconds)
	for veg in _aquatic_vegetation.values():
		veg.advance(elapsed, growth_modifier)

	for chunk_coord in _aquatic_vegetation.keys():
		_sync_aquatic_vegetation_sprites(chunk_coord)


## Mirrors step_aquatic_vegetation's own exact shape (see AquaticInvertebrates,
## docs/concept/aquatic_foraging.md's "Revised (2026-09-07)").
func step_aquatic_invertebrates(delta_seconds: float) -> void:
	_aquatic_invertebrates_refresh_accumulator += delta_seconds
	if _aquatic_invertebrates_refresh_accumulator < GRASS_REFRESH_INTERVAL:
		return
	var elapsed := _aquatic_invertebrates_refresh_accumulator
	_aquatic_invertebrates_refresh_accumulator = 0.0

	var growth_modifier := _season_cycle.growth_modifier(_world_age_seconds)
	for inverts in _aquatic_invertebrates.values():
		inverts.advance(elapsed, growth_modifier)

	for chunk_coord in _aquatic_invertebrates.keys():
		_sync_aquatic_invertebrate_sprites(chunk_coord)


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


## Wild mushroom fruiting sync (see docs/concept/mushrooms.md). Same
## throttled-accumulator shape as step_wild_crops immediately above:
## flush_drive is a pure function of real, regional conditions
## (WeatherModel.soil_moisture, SeasonCycle.season_at) sampled per CHUNK
## the same way step_worms already samples moisture per chunk, never a
## global figure -- so a rain shower over one loaded neighbourhood doesn't
## flush mushrooms three chunks away under clear sky.
func step_wild_mushrooms(delta_seconds: float) -> void:
	_mushroom_refresh_accumulator += delta_seconds
	if _mushroom_refresh_accumulator < MUSHROOM_REFRESH_INTERVAL:
		return
	var elapsed := _mushroom_refresh_accumulator
	_mushroom_refresh_accumulator = 0.0

	var season := current_season()
	# Real per-species timing within autumn (see docs/concept/mushrooms.md
	# "Fruiting times, aligned to real species") -- progress_through_season
	# is what actually distinguishes an early-loaded species (already
	# tapering off) from a late-loaded one (not yet started) at the SAME
	# season name and moisture; see MushroomFlush.species_multiplier/
	# WildMushroomPatch.advance for where this is actually applied.
	var progress := _season_cycle.progress_through_season(_world_age_seconds)
	for chunk_coord in _mushroom_sims.keys():
		var sim: WildMushroomPatch = _mushroom_sims[chunk_coord]
		var centre_tile: Vector2i = chunk_coord * CHUNK_SIZE + Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2)
		var centre_pixel := Vector2(
			float(centre_tile.x) + 0.5, float(centre_tile.y) + 0.5
		) * float(TerrainRenderer.TILE_SIZE)
		var moisture := _weather_model.soil_moisture(current_weather(centre_pixel))
		var flush_drive := MushroomFlush.flush_drive(moisture, season)
		sim.advance(elapsed, flush_drive, season, progress)
		_mushroom_renderer.sync_markers(
			_entities_parent, sim, chunk_coord * CHUNK_SIZE, TerrainRenderer.TILE_SIZE,
			_mushroom_markers[chunk_coord]
		)


## Debug/dev-console entry point (see World._handle_mushroom_command):
## forces the nearest real mushroom site in `global_tile`'s own chunk to
## fruit immediately (see WildMushroomPatch.force_fruit_near for why) and
## spawns its marker right away, rather than waiting for
## step_wild_mushrooms's own throttled cadence. Returns the species that
## fruited, or "" if that chunk isn't loaded or has no mushroom sites at
## all (a genuinely site-less biome, e.g. desert).
func force_mushroom_near(global_tile: Vector2i) -> String:
	var chunk_coord := _chunk_coord_for_tile(global_tile)
	if not _mushroom_sims.has(chunk_coord):
		return ""
	var sim: WildMushroomPatch = _mushroom_sims[chunk_coord]
	var local_cell := global_tile - chunk_coord * CHUNK_SIZE
	var fruited_cell := sim.force_fruit_near(local_cell)
	if fruited_cell == Vector2i(-1, -1):
		return ""
	_mushroom_renderer.sync_markers(
		_entities_parent, sim, chunk_coord * CHUNK_SIZE, TerrainRenderer.TILE_SIZE,
		_mushroom_markers[chunk_coord]
	)
	return sim.species_at(fruited_cell)


## Crushed underfoot (see docs/concept/soil_fauna.md "Crushed underfoot",
## CrushMechanic) -- mirrors crush_worm_at's own shape exactly (same real
## pixel-position -> tile -> chunk/sim lookup, same immediate re-sync so a
## crushed mushroom doesn't visibly linger until step_wild_mushrooms's own
## next throttled tick), but resolves through WildMushroomPatch.crush
## instead of pick: an insufficient `momentum_kg_m_s` leaves a fruiting
## mushroom exactly where it was, the same as never having been stepped on
## at all. No Karma penalty applies here (unlike crush_worm_at/
## crush_caterpillars_near) -- a mushroom is a fungus, not an animal (see
## docs/concept/mushrooms.md).
func crush_mushroom_at(pixel_position: Vector2, momentum_kg_m_s: float) -> bool:
	var tile := _world_tile_for_pixel(pixel_position)
	var chunk_coord := _chunk_coord_for_tile(tile)
	var sim: WildMushroomPatch = _mushroom_sims.get(chunk_coord)
	if sim == null:
		return false
	if not sim.crush(tile - chunk_coord * CHUNK_SIZE, momentum_kg_m_s):
		return false
	_mushroom_renderer.sync_markers(
		_entities_parent, sim, chunk_coord * CHUNK_SIZE, TerrainRenderer.TILE_SIZE,
		_mushroom_markers[chunk_coord]
	)
	return true


## Every real, currently-fruiting wild mushroom within `radius_tiles` of
## `pixel_position` (see WildMushroomPatch), in the shape fruit_near
## already uses ({position, species}) so GrazerForaging's FOOD_MUSHROOM
## kind slots into CreatureMarker._visible_food identically to FOOD_FRUIT
## (see docs/concept/mushrooms.md "Animals can find and eat wild
## mushrooms"). Scans the same 3x3 chunk neighbourhood nearest_leaf_
## litter_near/leaf_litter_near already do -- a WildMushroomPatch, like a
## LeafLitterField, is bucketed per chunk, not one flat list. A fruiting
## cell has no pixel position of its own (see WildMushroomPatch's
## own local-cell-only API), so this converts it the same way a mound's
## own cell already becomes a pixel elsewhere in this file: the tile's
## centre, not its corner.
func mushrooms_near(pixel_position: Vector2, radius_tiles: int = 8) -> Array:
	var out: Array = []
	var center_chunk := _chunk_coord_for_tile(_world_tile_for_pixel(pixel_position))
	var radius_px := float(radius_tiles) * TerrainRenderer.TILE_SIZE
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var chunk_coord := center_chunk + Vector2i(dx, dy)
			var sim: WildMushroomPatch = _mushroom_sims.get(chunk_coord)
			if sim == null:
				continue
			for cell in sim.get_fruiting_cells():
				var global_tile: Vector2i = chunk_coord * CHUNK_SIZE + cell
				var cell_pixel := Vector2(
					float(global_tile.x) + 0.5, float(global_tile.y) + 0.5
				) * TerrainRenderer.TILE_SIZE
				if cell_pixel.distance_to(pixel_position) > radius_px:
					continue
				out.append({"position": cell_pixel, "species": sim.species_at(cell)})
	return out


## Eats the wild mushroom fruiting at `pixel_position`, if there is one (see
## mushrooms_near) -- the mutation counterpart, mirroring take_fruit_at's
## own "return what was actually swallowed, or empty" contract. Resolves
## through the live MushroomMarker's own take_mushroom_bite() -- NOT
## sim.bite directly, and NOT pick_up -- pick_up is specifically the
## player's own "add to inventory" action; an animal eats a mushroom in
## place, the same real take-bite-shaped primitive the decomposer's own
## bite already uses (see docs/concept/mushrooms.md "Bitten by a
## decomposer"), so a boar's bite shows the identical real bitten-look art
## with no new rendering work. A bitten mushroom stays fruiting and
## pickable (unlike a crushed one, see WildMushroomPatch.bite's own doc
## comment) -- there is no marker to rebuild here, only the existing one
## to mark, which is exactly what going through the marker itself (rather
## than the sim) gets for free: take_mushroom_bite() updates its own
## sprite/bitten flag immediately, no separate re-sync needed.
##
## `bite_stages` (default 1) is how many of MushroomBiting.MAX_BITE_STAGES
## this one bite event advances -- the caller's own real, mass-scaled bite
## count (see docs/concept/soil_fauna.md's "Progressive, mass-scaled
## bites, and real toxic effects", MushroomBiting.bites_per_visit_for), so
## a boar's own bigger bite can visibly reduce a mushroom further than a
## bug's single nibble in one visit.
## Returns `{"species": String, "stages_applied": int}` -- `species` ""
## (with `stages_applied` 0) on any failure, the same "empty means nothing
## happened" convention the old bare-String return used. `stages_applied`
## is the REAL count that actually landed, which can be clamped below the
## requested `bite_stages` near MushroomBiting.MAX_BITE_STAGES (see
## WildMushroomPatch.bite's own doc comment) -- see docs/concept/
## metabolism.md's "the two named mushroom gaps": the caller (CreatureMarker)
## needs this real applied count, not just the request, to scale nutrition
## by how much was actually eaten this one visit.
func take_mushroom_at(pixel_position: Vector2, bite_stages: int = 1) -> Dictionary:
	var tile := _world_tile_for_pixel(pixel_position)
	var chunk_coord := _chunk_coord_for_tile(tile)
	var sim: WildMushroomPatch = _mushroom_sims.get(chunk_coord)
	if sim == null:
		return {"species": "", "stages_applied": 0}
	var cell := tile - chunk_coord * CHUNK_SIZE
	var species := sim.species_at(cell)
	var marker = _mushroom_markers.get(chunk_coord, {}).get(cell)
	if marker == null:
		return {"species": "", "stages_applied": 0}
	var stage_before: int = marker.bite_stage
	if not marker.take_mushroom_bite(bite_stages):
		return {"species": "", "stages_applied": 0}
	return {"species": species, "stages_applied": marker.bite_stage - stage_before}


## The walnut-shaped sibling of crush_mushroom_at (see docs/concept/
## soil_fauna.md "Crushed underfoot", CrushMechanic) -- "crack open" a
## fallen walnut underfoot. Unlike a worm/caterpillar/mushroom, a walnut
## is a plain DroppedItem with no per-chunk sim of its own, so detection
## scans DroppedItem.GROUP_NAME directly, filtered to real walnut item
## stacks, matched by exact tile -- the same tile-exact-match
## crush_caterpillars_near already uses for a real Node2D rather than
## per-cell sim state. Cracking one destroys it outright, the same "gone,
## not transformed into a different item" outcome a crushed worm/
## caterpillar already gets -- nothing in this project models a separate
## cracked-kernel item.
func crush_walnut_near(pixel_position: Vector2, momentum_kg_m_s: float) -> bool:
	if not CrushMechanic.is_crushed_by(momentum_kg_m_s):
		return false
	if _entities_parent == null or not _entities_parent.is_inside_tree():
		return false
	var tile := _world_tile_for_pixel(pixel_position)
	for item in _entities_parent.get_tree().get_nodes_in_group(DroppedItem.GROUP_NAME):
		# DroppedItem.GROUP_NAME is shared by every ground-pickable thing in
		# this game -- LiftableStone/PickableSeed very much included (see
		# DroppedItem's own doc comment) -- and neither has an item_stack
		# field at all. Duck-check the same safe way Player.
		# nearest_kickable_dropped_item_near already does; a direct
		# item.item_stack dot-access crashes the instant one of those
		# exists anywhere near a step.
		if not ("item_stack" in item) or item.item_stack == null or item.item_stack.item.id != "walnut":
			continue
		if _world_tile_for_pixel(item.position) != tile:
			continue
		item.queue_free()
		return true
	return false


## Tills and plants `crop_id` at a global tile (see docs/concept/farming.md,
## FarmPlot, FarmPlotMarker, Player._plant_step) -- lazily creates the
## plot's marker the first time this tile is farmed. Same "chunk must be
## loaded" gate build_at_global already uses: farming far outside the
## streamed area isn't meaningful since nothing there is rendered or
## simulated either. Refuses to disturb a plot that already holds a live
## crop (growing or ready) -- see FarmPlotMarker.till_and_plant -- so a
## stray press can never destroy an unharvested crop; only an empty or
## withered plot is (re)planted. Returns whether planting happened.
func till_and_plant_farm_plot_at_global(global_x: int, global_y: int, crop_id: String) -> bool:
	var tile := Vector2i(global_x, global_y)
	var chunk_coord := _chunk_coord_for_tile(tile)
	if _loaded_chunks.get(chunk_coord) == null:
		return false
	if not _farm_plots.has(tile):
		_farm_plots[tile] = _build_farm_plot_marker(tile)
	var seed_value := hash("%d_%d_farm_plot" % [tile.x, tile.y])
	if not _farm_plots[tile].till_and_plant(crop_id, seed_value):
		return false
	# Asked for directly: "long grass should be cleared before planting".
	# TILLING is what clears it, so the clearing happens only when the till
	# really took -- a bed refused because a live crop is already standing on
	# it was never worked, and must not scythe the ground anyway.
	#
	# Exactly the rule a building's own floor already has (docs/concept/
	# building.md "Placement rules": "grass must be cut before and can't grow
	# back inside a house"), through the same seam: whatever tall grass,
	# flowers, scrub or lichen stood here is gone, and none of them seeds,
	# spreads or falls back into worked ground while the bed stands.
	_block_ground_cover_on_cells(chunk_coord, [tile - chunk_coord * CHUNK_SIZE])
	return true


## Tends (re-waters) the growing plot at a global tile, resetting its
## neglect clock -- see FarmPlot.water. False if there is no plot there, or
## it isn't currently growing.
func water_farm_plot_at_global(global_x: int, global_y: int) -> bool:
	var marker: FarmPlotMarker = _farm_plots.get(Vector2i(global_x, global_y))
	return marker != null and marker.water()


## Harvests the ready plot at a global tile -- see FarmPlot.harvest.
## Returns {"crop_id": "", "count": 0} (the same shape FarmPlot.harvest's
## own no-op returns) if there is no plot there, or it isn't ready yet. The
## plot's soil stays -- see FarmPlotMarker.harvest -- so the same tile can
## be planted again without re-tilling.
func harvest_farm_plot_at_global(global_x: int, global_y: int) -> Dictionary:
	var marker: FarmPlotMarker = _farm_plots.get(Vector2i(global_x, global_y))
	if marker == null:
		return {"crop_id": "", "count": 0}
	return marker.harvest()


## The real FarmPlot at a global tile, or null where nobody has ever
## tilled -- which VillageFarm.action_for reads as "plant this first"
## rather than as an error. The plot ITSELF, not a copy: a village farmer
## decides what their field needs by looking at it (docs/concept/
## village_farms.md, NpcMarker._field_states), and a snapshot would go
## stale between one frame and the next as the crop grows.
func farm_plot_at_global(global_x: int, global_y: int):
	var marker: FarmPlotMarker = _farm_plots.get(Vector2i(global_x, global_y))
	return marker.plot if marker != null else null


## The world-clock tick hook for the farming loop (see
## World._step_ecology_batch, docs/concept/farming.md) -- advances every
## farm plot's own growth simulation by `delta_seconds`. Mirrors
## step_worms' identical "for x in _sims.values(): x.advance(delta)" shape;
## unlike step_wild_crops/step_tall_grass, this deliberately does NOT scale
## by SeasonCycle's growth_modifier -- farming.md frames a tilled, tended
## plot as the player's own override of the ambient vegetation model, not a
## wild population subject to the same seasonal modulation. Also forwards
## current_season() to every plot -- only a WHEAT crop's own art actually
## reads it (FarmPlotMarker._redraw_wheat picks which of its three real
## sheets to sample from), but it costs nothing to pass unconditionally,
## the same way delta_seconds itself is.
## Every village pond's own fish stock, keyed by chunk then by the pond's
## own ANCHOR cell -- the top-left cell of that body of water, found by
## flooding it (see _pond_anchor). One pond is one stock however many cells
## it has, which is what makes "a pond" a thing rather than six buckets.
##
## Not persisted, like the farm plots beside it and for the same reason: a
## revisited village re-stocks rather than remembering
## (docs/concept/village_ponds.md's own status list).
var _pond_fish: Dictionary = {}


## Puts a fisher's stocking of fish into the pond this cell belongs to (see
## docs/concept/village_ponds.md). A no-op on dry ground, and on a pond that
## already holds fish -- a fisher stocks a pond, they do not keep stocking
## it.
func stock_pond_at(global_x: int, global_y: int) -> void:
	var anchor = _pond_anchor(global_x, global_y)
	if anchor == null:
		return
	var chunk_coord := _chunk_coord_for_tile(anchor)
	var by_anchor: Dictionary = _pond_fish.get(chunk_coord, {})
	if by_anchor.has(anchor):
		return
	by_anchor[anchor] = float(VillagePond.STOCKING_FISH)
	_pond_fish[chunk_coord] = by_anchor
	_sync_pond_fish_markers(chunk_coord, anchor)


## How many fish the pond this cell belongs to is holding -- 0.0 for dry
## ground, and for water nobody has stocked.
func pond_fish_at(global_x: int, global_y: int) -> float:
	var anchor = _pond_anchor(global_x, global_y)
	if anchor == null:
		return 0.0
	return float(_pond_fish.get(_chunk_coord_for_tile(anchor), {}).get(anchor, 0.0))


## The real FishMarkers swimming in each pond, keyed the same way the stock
## is: chunk, then the pond's own anchor cell. Kept OUT of _loaded_fish on
## purpose -- that list is respawned wholesale whenever a chunk's aggregate
## fish population is reconciled, which would wipe a pond's own fish every
## time the region's did anything.
var _pond_fish_markers: Dictionary = {}

## At most one fish per tile of water. Six tiles is a pond, not a shoal, and
## a marker per unit of a population that can exceed its own cell count
## would pile fish on top of each other.
const _POND_FISH_PER_CELL := 1


## The fish really swimming in the pond this cell belongs to.
func pond_fish_markers_at(global_x: int, global_y: int) -> Array:
	var anchor = _pond_anchor(global_x, global_y)
	if anchor == null:
		return []
	return _pond_fish_markers.get(_chunk_coord_for_tile(anchor), {}).get(anchor, [])


func pond_fish_marker_count_at(global_x: int, global_y: int) -> int:
	return pond_fish_markers_at(global_x, global_y).size()


## Brings the fish you can SEE in one pond into line with the stock it
## holds: one marker per whole fish, capped at one per tile of water, each
## standing on a real cell of that pond.
##
## Spawn and free rather than reposition -- a pond gains or loses a fish
## rarely (a breeding tick, a catch), and FishMarker owns its own swimming
## from wherever it is put down.
func _sync_pond_fish_markers(chunk_coord: Vector2i, anchor: Vector2i) -> void:
	var cells := _pond_cells_from(anchor)
	var by_anchor: Dictionary = _pond_fish_markers.get(chunk_coord, {})
	var markers: Array = by_anchor.get(anchor, [])
	var stock: float = float(_pond_fish.get(chunk_coord, {}).get(anchor, 0.0))
	var wanted: int = mini(int(floor(stock)), cells.size() * _POND_FISH_PER_CELL)
	while markers.size() > wanted:
		var extra = markers.pop_back()
		if is_instance_valid(extra):
			extra.free()
	while markers.size() < wanted and not cells.is_empty():
		var cell: Vector2i = cells[markers.size() % cells.size()]
		var centre := (Vector2(cell) + Vector2(0.5, 0.5)) * TerrainRenderer.TILE_SIZE
		var seed_value := hash("%d_%d_pond_fish_%d" % [cell.x, cell.y, markers.size()])
		var species: String = FishRenderer.SPECIES_POOL[
			absi(seed_value) % FishRenderer.SPECIES_POOL.size()
		]
		markers.append(_fish_renderer.spawn_fish_at(_creatures_parent, species, centre, seed_value))
	by_anchor[anchor] = markers
	_pond_fish_markers[chunk_coord] = by_anchor


## Frees every pond fish of a chunk that is going away.
func _free_pond_fish_markers(chunk_coord: Vector2i) -> void:
	for markers in _pond_fish_markers.get(chunk_coord, {}).values():
		for fish in markers:
			if is_instance_valid(fish):
				fish.free()
	_pond_fish_markers.erase(chunk_coord)


## Takes one fish out of the pond this cell belongs to: one off the stock,
## and one fewer swimming in it. False when there is not a whole fish left
## to take, or when this is not a pond at all.
##
## All-or-nothing on a WHOLE fish, mirroring withdraw_from_structure_at:
## half a fish is not a catch, and a pond fished down to a fraction breeds
## back from what is left rather than from nothing.
func catch_pond_fish_at(global_x: int, global_y: int) -> bool:
	var anchor = _pond_anchor(global_x, global_y)
	if anchor == null:
		return false
	var chunk_coord := _chunk_coord_for_tile(anchor)
	var by_anchor: Dictionary = _pond_fish.get(chunk_coord, {})
	var stock: float = float(by_anchor.get(anchor, 0.0))
	if stock < 1.0:
		return false
	by_anchor[anchor] = stock - 1.0
	_pond_fish[chunk_coord] = by_anchor
	_sync_pond_fish_markers(chunk_coord, anchor)
	return true


## Breeds every stocked pond toward what its own water can feed, on the
## world's own ecology tick (scenes/world.gd's tick table).
func step_ponds(delta_seconds: float) -> void:
	if _pond_fish.is_empty():
		return
	var days := delta_seconds / ChunkEcologyCatchup.SECONDS_PER_DAY
	if days <= 0.0:
		return
	for chunk_coord in _pond_fish:
		var by_anchor: Dictionary = _pond_fish[chunk_coord]
		for anchor in by_anchor:
			var cells := _pond_cells_from(anchor)
			if cells.is_empty():
				continue  # filled in since it was stocked
			by_anchor[anchor] = VillagePond.step(
				float(by_anchor[anchor]), cells.size(),
				_pond_temperature(anchor), days
			)
			_sync_pond_fish_markers(chunk_coord, anchor)


## The water temperature a pond's fish live at -- its own chunk's, the same
## normalized [0, 1] value every other aquatic population reads.
func _pond_temperature(anchor: Vector2i) -> float:
	var chunk: Chunk = _loaded_chunks.get(_chunk_coord_for_tile(anchor))
	if chunk == null:
		return AquaticPopulationModel.OPTIMAL_TEMPERATURE
	return float(chunk.temperature[_local_index(anchor.x, anchor.y)])


## Every cell of the body of water this one belongs to, flood-filled over
## pond tiles. Bounded in practice -- a village pond is six cells -- and
## bounded in code by _POND_FLOOD_LIMIT so a hand-dug lake cannot make this
## walk the world.
const _POND_FLOOD_LIMIT := 256


func _pond_cells_from(start: Vector2i) -> Array:
	if not is_pond_at_global(start.x, start.y):
		return []
	var seen: Dictionary = {start: true}
	var queue: Array = [start]
	var out: Array = []
	while not queue.is_empty() and out.size() < _POND_FLOOD_LIMIT:
		var cell: Vector2i = queue.pop_back()
		out.append(cell)
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if seen.has(next) or not is_pond_at_global(next.x, next.y):
				continue
			seen[next] = true
			queue.append(next)
	return out


## The one cell that stands for a whole pond: its top-left, so every cell of
## the same water agrees on which stock is theirs however the flood happened
## to walk it. Null for dry ground.
func _pond_anchor(global_x: int, global_y: int):
	var cells := _pond_cells_from(Vector2i(global_x, global_y))
	if cells.is_empty():
		return null
	var anchor: Vector2i = cells[0]
	for cell in cells:
		var c: Vector2i = cell
		if c.y < anchor.y or (c.y == anchor.y and c.x < anchor.x):
			anchor = c
	return anchor


func step_farm_plots(delta_seconds: float) -> void:
	var season := current_season()
	for marker in _farm_plots.values():
		marker.advance(delta_seconds, season)


func _build_farm_plot_marker(tile: Vector2i) -> FarmPlotMarker:
	var marker := FarmPlotMarker.new()
	marker.position = Vector2(
		(tile.x + 0.5) * TerrainRenderer.TILE_SIZE, (tile.y + 0.5) * TerrainRenderer.TILE_SIZE
	)
	_entities_parent.add_child(marker)
	return marker


## One shared shader-uniform write per frame makes nearby blades yield to a
## walker; individual cards intentionally have no process callbacks. Also
## pushes to IllustratedWheatPatch's own shared material (see docs/concept/
## long_grass.md's "A second atlas family: farmed wheat") -- one write here
## updates every wheat crop on every farm at once, the same "one shared
## uniform" shape grass's own single call already uses.
func set_grass_walker_position(world_position: Vector2) -> void:
	_illustrated_grass.set_walker_position(world_position)
	IllustratedWheatPatch.set_walker_position(world_position)


## How grown the tall-grass patch at `pixel_position` is (0..1, 1 mature), or
## a negative number if there is no patch there. Grass has no per-tuft
## Node2D of its own (see _sync_grass_sprites), so it cannot join
## HoverTargetFinder's group like every other hoverable entity -- World reads
## this directly instead to special-case the mouse-hover tooltip over grass.
## Names the blooming flower drawn nearest `pixel_position`, or "" when none
## is close enough -- the hover tooltip's flower lookup (see
## World._update_hover_tooltip).
##
## Reported live: flowers "still don't [show] hover tooltips". Every other
## hoverable thing in the world is a Node2D that joins
## HoverTargetFinder.GROUP_NAME and answers get_display_name(). Flowers are
## not, and should not be: they are ground decoration, a bare Sprite2D per
## cell with no script and no group (see _sync_flower_sprites), precisely so a
## loaded meadow costs a handful of shared textures instead of a thousand
## scripted nodes -- and that group is scanned every frame, so joining it is
## not free (see World's own note on the cost of that scan). So flowers are
## answered the way tall grass already is: a cheap query the hover scan falls
## through to when nothing in the group claimed the cursor.
##
## Measured against the BLOSSOM, not the cell: the sprite is anchored at the
## stem's foot and drawn upward from there, so a player pointing at the bloom
## they can actually see is pointing well above the cell the plant stands in.
## Uses the very same landing point a pollinator settles on (see flowers_near
## / ProceduralFlowerSprite.blossom_height_world), so the tooltip and the bees
## agree about where a flower is.
##
## Only what is IN BLOOM answers, matching exactly what is drawn -- naming a
## rose over what the player sees as bare grass is the same sim-and-picture
## disagreement concept/flora.md forbids, with the lie on the other foot.
func flower_name_at(
	pixel_position: Vector2, radius_px: float = HoverTargetFinder.HOVER_RADIUS_PX
) -> String:
	var season := current_season()
	var center := _world_tile_for_pixel(pixel_position)
	# Enough rows to cover the tallest stem the art can draw plus the search
	# radius itself, so a sunflower's head is still traced back to the foot it
	# grows from. Bounded from the art's own numbers, not a guessed row count.
	var reach := 1 + ceili(
		(radius_px + ProceduralFlowerSprite.max_blossom_height_world())
		/ float(TerrainRenderer.TILE_SIZE)
	)
	var best_name := ""
	var best_distance := radius_px
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var tile := center + Vector2i(dx, dy)
			var patch: FlowerPatch = _flower_patches.get(_chunk_coord_for_tile(tile))
			if patch == null:
				continue
			var cell := _local_coord(tile.x, tile.y)
			var label := patch.label_at(cell, season)
			if label == "":
				continue
			var foot := Vector2(
				(tile.x + 0.5) * TerrainRenderer.TILE_SIZE,
				(tile.y + 0.5) * TerrainRenderer.TILE_SIZE
			)
			var sprite_seed := hash("%d_%d_flower" % [tile.x, tile.y])
			var blossom := foot - Vector2(
				0.0,
				ProceduralFlowerSprite.blossom_height_world(
					sprite_seed,
					_flower_scale_for(
						patch.species_at(cell), patch.growth_at(cell), sprite_seed
					).y
				)
			)
			var distance := pixel_position.distance_to(blossom)
			if distance <= best_distance:
				best_distance = distance
				best_name = label
	return best_name


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
	# into SeedEndozoochory.seed_is_consumed. current_growth_modifier() (see
	# docs/concept/seasonal_behavior.md, "Squirrel/mouse cache-preference")
	# pushes a real scarce season toward eating now over caching for later --
	# the same signal phase 5's herbivore forage-realism fix already reuses.
	if not SquirrelNutCaching.nut_is_consumed(
		creature.wander_seed, creature.wander_seed, current_growth_modifier()
	):
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


## Trees and stones follow the same gate (FPS regression round 15,
## docs/concept/soil_fauna.md). They are direct children of the y-sorted
## Entities layer, and every one of ~25 loaded chunks' worth stayed visible
## for a camera that frames less than one chunk -- the renderer gathered and
## sorted all of them every frame. A hidden canvas item is skipped before
## that walk, so hiding the far ones is what makes render CPU scale with
## what is on screen. Nothing else changes: the nodes stay loaded, in their
## registries, chopped and lifted and simulated exactly as before -- only
## `visible` follows DecorationLod, the way grass, flowers, worms, leaf
## litter and footprints already do. Whole-registry pass on every chunk
## crossing (rare, a walking pace); the per-chunk form runs once at load so
## a chunk that loads while the player stands still spawns already hidden.
func _sync_static_entity_visibility() -> void:
	for chunk_coord in _loaded_trees:
		_apply_static_visibility(chunk_coord)
	for chunk_coord in _loaded_stones:
		if not _loaded_trees.has(chunk_coord):
			_apply_static_visibility(chunk_coord)


func _apply_static_visibility(chunk_coord: Vector2i) -> void:
	var visible := _decorates(chunk_coord)
	for registry in [_loaded_trees, _loaded_stones]:
		for node in registry.get(chunk_coord, []):
			if is_instance_valid(node):
				node.visible = visible


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

## Leaf litter's own tile-precise view buffer -- reuses GRASS_VIEW_BUFFER_
## TILES' own exact value (the SAME camera-buffer convention, not a third
## independently-tuned number -- mirrors LEAF_SPRING_TRICKLE_CHANCE reusing
## LEAF_SUMMER_TRICKLE_CHANCE's own value for the identical reason). Fed to
## LeafLitterRenderer.leaves_in_view by step_leaf_litter, answering the
## live report this closes for leaf litter specifically ("make it so that
## it only computes leaf litter ... to the current visible area") the same
## way GRASS_VIEW_BUFFER_TILES already answered it for grass blades.
const LEAF_LITTER_VIEW_BUFFER_TILES := GRASS_VIEW_BUFFER_TILES

## Shared by both real reasons a band needs a SECOND MultiMeshInstance2D
## (the calendar turn and the snow overlay, mutually exclusive -- see
## _sync_grass_sprites' own doc comment): fetches the existing one for this
## band or lazily creates it at the primary mesh's own position.
func _get_or_create_turning_mmi(turning_bands: Dictionary, band: int, mmi_position: Vector2) -> MultiMeshInstance2D:
	var turning_mmi: MultiMeshInstance2D = turning_bands.get(band)
	if turning_mmi == null:
		turning_mmi = MultiMeshInstance2D.new()
		turning_mmi.position = mmi_position
		_entities_parent.add_child(turning_mmi)
		turning_bands[band] = turning_mmi
	return turning_mmi


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
		_drop_decoration(_grass_sprites_turning, chunk_coord)
		return
	var sim: TallGrass = _grass_sims.get(chunk_coord)
	if sim == null:
		return
	var bands: Dictionary = _grass_sprites.get(chunk_coord, {})
	var turning_bands: Dictionary = _grass_sprites_turning.get(chunk_coord, {})

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
	for band in turning_bands.keys().duplicate():
		if not cards_by_band.has(band):
			turning_bands[band].queue_free()
			turning_bands.erase(band)

	# A band whose cards straddle two seasons (see IllustratedGrassPatch.
	# split_cards_by_turn/docs/concept/long_grass.md's "Seasonal art") needs
	# a SECOND MultiMeshInstance2D so each half can sample its own season's
	# texture -- MultiMeshInstance2D has exactly one `texture`, shared by
	# every instance in it. Collapses back to a single mesh, freeing the
	# second one, the instant the transition settles (progress reaches 0 or
	# 1, or turning_into names the same season) -- matching every prior
	# season's own single-mesh-per-band cost exactly.
	var transitioning := (
		_grass_turning_into != "" and _grass_turning_into != _grass_season_name
		and _grass_turn_progress > 0.0 and _grass_turn_progress < 1.0
	)
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

		if transitioning:
			# An active calendar transition wins outright over the snow
			# overlay below -- see docs/concept/long_grass.md's "Scoped
			# deliberately, not silently": both reuse this SAME turning-mesh
			# slot, so they are mutually exclusive, not composed.
			var split := IllustratedGrassPatch.split_cards_by_turn(cards_by_band[band], _grass_turn_progress)
			_illustrated_grass.fill_band(mmi, mmi.position, split.from, _grass_season_name)
			var turning_mmi := _get_or_create_turning_mmi(turning_bands, band, mmi.position)
			_illustrated_grass.fill_band(turning_mmi, turning_mmi.position, split.to, _grass_turning_into)
		elif _snow_depth > 0.0:
			# Winter's own dedicated sheet is a snow-triggered overlay, not a
			# calendar destination -- see docs/concept/long_grass.md's
			# "Winter's own sheet is a snow overlay, not a calendar
			# destination". _grass_season_name is already autumn-remapped
			# through a real calendar winter (see sync_grass_season), so
			# "base" here never means the dedicated winter sheet by accident.
			var split := IllustratedGrassPatch.split_cards_by_snow_overlay(cards_by_band[band], _snow_depth)
			_illustrated_grass.fill_band(mmi, mmi.position, split.base, _grass_season_name)
			var overlay_mmi := _get_or_create_turning_mmi(turning_bands, band, mmi.position)
			_illustrated_grass.fill_band(overlay_mmi, overlay_mmi.position, split.winter, "winter")
		else:
			_illustrated_grass.fill_band(mmi, mmi.position, cards_by_band[band], _grass_season_name)
			var stale_turning_mmi: MultiMeshInstance2D = turning_bands.get(band)
			if stale_turning_mmi != null:
				stale_turning_mmi.queue_free()
				turning_bands.erase(band)

	_grass_sprites[chunk_coord] = bands
	_grass_sprites_turning[chunk_coord] = turning_bands


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

## The one region seed the world's PREVAILING wind is drawn from (see
## WeatherModel.prevailing_wind_direction), used only to bake meadows.
##
## Deliberately NOT per-chunk, the way current_weather's region seed is. A
## founder's lineage has to be computed identically by every chunk that can
## see it, or the meadows either side of a boundary disagree and the seam
## shows -- and two chunks each using their own prevailing wind is exactly
## that disagreement. One climate for the world is also the honest reading:
## real prevailing winds are consistent over far more ground than this world
## covers. The DAY's wind still varies by region and by day (see
## step_flowers), so live shedding is regional even though the baked meadow
## is not.
const PREVAILING_WIND_REGION_SEED := 4177


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
			#
			# Round 8 FPS fix: this is called once per pollinator's own
			# ~0.5s sniff, up to 300+ times independently for the identical
			# per-chunk answer -- passing the real clock lets FlowerPatch.
			# blooming_cells share one computation across every asker within
			# its own refresh window instead of redoing the full per-cell
			# scan every single time (see that method's own doc comment).
			for cell in patch.blooming_cells(season_name, Time.get_ticks_msec()):
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


## record_birth_at's bird sibling -- see EcosystemSimulation.record_bird_
## birth for why this needs to be species-routed rather than one
## hardcoded population. Called by AmbientFlyerMarker._finish_bird_court
## exactly like spawn_flyer_offspring is, through the same `courtship_
## world` reference.
func record_bird_birth_at(position: Vector2, species: String, count: float = 1.0) -> void:
	_ecosystem.record_bird_birth(_chunk_coord_for_tile(_world_tile_for_pixel(position)), species, count)


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
		>= AmbientFlyerRenderer.max_flyers_per_chunk(_pollinator_multiplier_for(chunk_coord), _population_density["pollinators"])
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
					# ScentField.concentration_at reads this key FIRST, ahead
					# of its own FlowerSpecies-keyed lookup -- species_id
					# here is a TreeSpecies id, which FlowerSpecies has never
					# heard of and never will (see docs/concept/flora.md
					# #tree-blossoms-emit-real-scent-too). Without this, a
					# blossom silently rode FlowerSpecies' own _FALLBACK
					# profile's unrelated 0.4 default for an unrecognized
					# species id.
					"scent_strength": TreeSpecies.blossom_scent_for(species_id),
				})
	return out


## Any real, standing tree near `pixel_position` -- unlike blossoms_near
## (spring-only, insect-pollinated species only) or harvest_peak_fruit_near
## (one specific tree's own ripeness), this asks nothing about species or
## season: it is "is there somewhere to land nearby" for AmbientFlyerMarker's
## idle-rest perch (requested live: "birds should sit down on trees to
## tweet / dance" -- until now idle rest just froze the bird in mid-air
## wherever the rest happened to begin). Same scan shape and Euclidean
## radius_px convention as blossoms_near (same _loaded_trees bucket walk),
## with the species/season gate dropped and a felled-tree filter added -- a
## stump is not a perch, and is_felled() is the same check
## solid_obstacles_near already trusts for exactly this reason.
func trees_near(pixel_position: Vector2, radius_tiles: int = 8) -> Array:
	var out: Array = []
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
				if not is_instance_valid(tree) or tree.is_felled():
					continue
				if tree.position.distance_to(pixel_position) > radius_px:
					continue
				out.append({
					"position": tree.position,
					"species": TreeSpecies.species_for_bias(tree.species_bias),
				})
	return out


## Rolls, once per real tree this chunk just loaded, whether it hosts a
## calling cicada right now (see CicadaPopulation's own doc comment for
## why a fresh roll per load -- not a persisted, growing/starving
## population like AntColony/BeeColony -- is an honest match for a real
## adult cicada's own short calling window). One roll per tree, same index
## order _loaded_trees[chunk_coord] already uses.
func _dispatch_cicadas(chunk_coord: Vector2i) -> void:
	var trees: Array = _loaded_trees.get(chunk_coord, [])
	var rolls: Array[float] = []
	for i in trees.size():
		rolls.append(randf())
	_spawn_cicadas_for_indices(
		chunk_coord, trees, CicadaPopulation.cicada_tree_indices(trees.size(), current_season(), rolls)
	)


## The real spawn glue -- separated from _dispatch_cicadas so a test can
## drive it with a deterministic index list, bypassing the roll entirely
## (mirrors test_earth_chunk_manager_bees.gd's own direct-injection
## precedent for hive/nest placement's identical real-probabilism problem).
## Skips a felled tree (a stump is not a perch, the same real distinction
## trees_near's own felled-tree filter already draws) rather than anchoring
## a cicada to one.
func _spawn_cicadas_for_indices(chunk_coord: Vector2i, trees: Array, indices: Array[int]) -> void:
	var markers: Array = []
	for i in indices:
		var tree = trees[i]
		if not is_instance_valid(tree) or tree.is_felled():
			continue
		var marker := CicadaMarker.new()
		marker.position = tree.position
		_entities_parent.add_child(marker)
		markers.append(marker)
	_cicada_markers[chunk_coord] = markers


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
	# Which way, and how hard, it is blowing RIGHT NOW -- the day's wind, not
	# the prevailing one worldgen used, so live shedding varies with the
	# weather and by region the way everything else does.
	#
	# This loop is the fix for a real defect: FlowerPatch.set_wind was fully
	# built and fully tested and its only caller anywhere was its own test
	# file, so every meadow in the running game shed seed at strength 0.0 --
	# a permanent dead calm -- and the downwind drift the model computes was
	# never once applied outside a test. Same bug class as the dead
	# Pollination wiring recorded in docs/progress.md.
	var weather_day := int(_world_age_seconds / WEATHER_PERIOD_SECONDS)
	for chunk_coord in _flower_patches:
		var patch: FlowerPatch = _flower_patches[chunk_coord]
		# Per-chunk region seed, exactly as current_weather derives it -- so a
		# meadow sheds on the same wind the sky over it is showing.
		var region_seed := hash("%d_%d" % [chunk_coord.x, chunk_coord.y])
		patch.set_wind(
			_weather_model.wind_direction_for(weather_day, region_seed),
			_weather_model.dispersal_strength_for(
				_weather_model.weather_at(weather_day, region_seed)
			)
		)
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
			# has_method on a freed node does not log and carry on -- it
			# takes the process down. A felled tree is still in the registry
			# until step_tree_growth drops it.
			if not is_instance_valid(tree):
				continue
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


## Mirrors sync_tree_season's own shape exactly, at grass-blade granularity:
## a shared, quantised SeasonTransition state, guarded by a string signature
## so the (comparatively rare) grass resync only fires a handful of times
## per in-game year, not every frame. No player_pixel gate the way trees
## take one -- _sync_grass_sprites is already gated per-chunk by _decorates/
## the tile-precise view cutoff (see its own doc comment), so re-running it
## for every currently-tracked grass chunk on a season change costs no more
## than the ordinary per-chunk decoration sync already would. See
## docs/concept/long_grass.md's "Seasonal art".
func sync_grass_season() -> void:
	var transition := SeasonalFoliage.transition_for_world_age(_world_age_seconds)
	# base_render_season maps the calendar's own "winter" to "autumn" -- see
	# docs/concept/long_grass.md's "Winter's own sheet is a snow overlay, not
	# a calendar destination". Applied here, at the one point the raw
	# calendar names are captured, so every downstream consumer (fill_band,
	# atlas_region_for, split_cards_by_turn) already only ever sees "autumn"
	# for what the calendar calls winter -- no second code path to keep in
	# sync. A real autumn->winter turn collapses to season_name==turning_into
	# as a direct consequence (nothing to visually cross over once both ends
	# render the same sheet), which is what makes _sync_grass_sprites'
	# existing "transitioning" guard skip a turning mesh for it automatically.
	var season_name: String = IllustratedGrassPatch.base_render_season(transition.from)
	var turning_into: String = IllustratedGrassPatch.base_render_season(transition.to)
	var turn_progress: float = transition.progress
	var signature := "%s/%s/%.2f" % [season_name, turning_into, turn_progress]
	if signature == _last_grass_season:
		return
	_last_grass_season = signature
	_grass_season_name = season_name
	_grass_turning_into = turning_into
	_grass_turn_progress = turn_progress
	for chunk_coord in _grass_sprites.keys():
		_sync_grass_sprites(chunk_coord)


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


## Every real, currently-tracked CaterpillarMarker within radius_tiles of
## pixel_position, in the shape a caterpillar-eating bird expects (see
## docs/concept/soil_fauna.md's own bird-diet follow-up: "some birds eat
## caterpillars too"). Mirrors worms_near's own shape exactly, including its
## Chebyshev-in-tiles radius check and 3x3-chunk-neighborhood scan (a
## caterpillar just across a chunk boundary from the querying position is
## exactly as real as one on the same side of it).
func caterpillars_near(pixel_position: Vector2, radius_tiles: int = 8) -> Array:
	var out: Array = []
	var center := _world_tile_for_pixel(pixel_position)
	var center_chunk := _chunk_coord_for_tile(center)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var chunk_coord := center_chunk + Vector2i(dx, dy)
			var markers: Array = _caterpillar_markers.get(chunk_coord, [])
			for marker in markers:
				var tile := _world_tile_for_pixel(marker.position)
				if maxi(absi(tile.x - center.x), absi(tile.y - center.y)) > radius_tiles:
					continue
				out.append({"position": marker.position})
	return out


## Removes the real CaterpillarMarker standing on the same tile as
## pixel_position -- mirrors take_worm_at's own "eaten on real arrival,
## re-checked here, not guaranteed by having been sensed at all" contract.
## Calls queue_free() directly rather than crush(): a bird's meal is an
## entirely different event from being crushed underfoot (see
## crush_caterpillars_near below), with no death animation of its own to
## play through first -- the same instant-disappear outcome take_worm_at
## already gives an eaten worm.
func take_caterpillar_near(pixel_position: Vector2) -> bool:
	var tile := _world_tile_for_pixel(pixel_position)
	var chunk_coord := _chunk_coord_for_tile(tile)
	var markers: Array = _caterpillar_markers.get(chunk_coord, [])
	for marker in markers.duplicate():
		if _world_tile_for_pixel(marker.position) == tile:
			markers.erase(marker)
			marker.queue_free()
			return true
	return false


## Every real aquatic vegetation patch within `radius_tiles` of
## `pixel_position` -- mirrors worms_near's own exact shape (a 3x3
## chunk-neighbourhood scan, the same margin every other per-chunk
## near-query in this file already uses so a query near a chunk boundary
## still sees patches just across it).
func aquatic_vegetation_near(pixel_position: Vector2, radius_tiles: int = 8) -> Array:
	var out: Array = []
	var center := _world_tile_for_pixel(pixel_position)
	var center_chunk := _chunk_coord_for_tile(center)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var chunk_coord := center_chunk + Vector2i(dx, dy)
			var veg: AquaticVegetation = _aquatic_vegetation.get(chunk_coord)
			if veg == null:
				continue
			var origin := chunk_coord * CHUNK_SIZE
			for cell in veg.get_patch_cells():
				var tile: Vector2i = origin + cell
				if maxi(absi(tile.x - center.x), absi(tile.y - center.y)) > radius_tiles:
					continue
				out.append({
					"position": Vector2(
						float(tile.x) + 0.5, float(tile.y) + 0.5
					) * float(TerrainRenderer.TILE_SIZE),
				})
	return out


## Grazes the vegetation patch at `pixel_position`, if there is one --
## mirrors take_worm_at's own exact shape (same tile/chunk/sim lookup,
## same immediate _sync re-sync so a grazed patch doesn't visibly linger
## for up to GRASS_REFRESH_INTERVAL more seconds after the fish that ate
## it already moved on).
func graze_aquatic_vegetation_at(pixel_position: Vector2) -> bool:
	var tile := _world_tile_for_pixel(pixel_position)
	var chunk_coord := _chunk_coord_for_tile(tile)
	var veg: AquaticVegetation = _aquatic_vegetation.get(chunk_coord)
	if veg == null:
		return false
	if not veg.graze(tile - chunk_coord * CHUNK_SIZE):
		return false
	_sync_aquatic_vegetation_sprites(chunk_coord)
	return true


## Every real aquatic invertebrate patch within `radius_tiles` of
## `pixel_position` -- mirrors aquatic_vegetation_near's own exact shape
## (see AquaticInvertebrates, docs/concept/aquatic_foraging.md's "Revised
## (2026-09-07)").
func aquatic_invertebrates_near(pixel_position: Vector2, radius_tiles: int = 8) -> Array:
	var out: Array = []
	var center := _world_tile_for_pixel(pixel_position)
	var center_chunk := _chunk_coord_for_tile(center)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var chunk_coord := center_chunk + Vector2i(dx, dy)
			var inverts: AquaticInvertebrates = _aquatic_invertebrates.get(chunk_coord)
			if inverts == null:
				continue
			var origin := chunk_coord * CHUNK_SIZE
			for cell in inverts.get_patch_cells():
				var tile: Vector2i = origin + cell
				if maxi(absi(tile.x - center.x), absi(tile.y - center.y)) > radius_tiles:
					continue
				out.append({
					"position": Vector2(
						float(tile.x) + 0.5, float(tile.y) + 0.5
					) * float(TerrainRenderer.TILE_SIZE),
				})
	return out


## Grazes the invertebrate patch at `pixel_position`, if there is one --
## mirrors graze_aquatic_vegetation_at's own exact shape.
func graze_aquatic_invertebrates_at(pixel_position: Vector2) -> bool:
	var tile := _world_tile_for_pixel(pixel_position)
	var chunk_coord := _chunk_coord_for_tile(tile)
	var inverts: AquaticInvertebrates = _aquatic_invertebrates.get(chunk_coord)
	if inverts == null:
		return false
	if not inverts.graze(tile - chunk_coord * CHUNK_SIZE):
		return false
	_sync_aquatic_invertebrate_sprites(chunk_coord)
	return true


## Crushed underfoot (see docs/concept/soil_fauna.md "Crushed underfoot:
## weight-emergent worm mortality") -- mirrors take_worm_at's own shape
## exactly (same tile/chunk/patch lookup, same immediate re-sync so a
## crushed worm doesn't visibly linger for up to WORM_REFRESH_INTERVAL
## more seconds after the step that killed it), but resolves through
## EarthwormPatch.crush instead of take: an insufficient `momentum_kg_m_s`
## leaves a surfaced worm exactly where it was, the same as never having
## been stepped on at all.
func crush_worm_at(pixel_position: Vector2, momentum_kg_m_s: float) -> bool:
	var tile := _world_tile_for_pixel(pixel_position)
	var chunk_coord := _chunk_coord_for_tile(tile)
	var patch: EarthwormPatch = _worm_patches.get(chunk_coord)
	if patch == null:
		return false
	if not patch.crush(tile - chunk_coord * CHUNK_SIZE, momentum_kg_m_s):
		return false
	_sync_worm_sprites(chunk_coord)
	return true


## The caterpillar-shaped sibling of crush_worm_at (see docs/concept/
## soil_fauna.md "Generalized to caterpillars too") -- same
## CrushMechanic.is_crushed_by physics, same "insufficient momentum is a
## no-op" contract, but a caterpillar is a real Node2D with its own
## position rather than per-tile cell state, so this scans the stepped-on
## chunk's own tracked markers by real position instead of looking up one
## patch/cell. No corpse/recovery state to set (see the doc's own "No
## corpse state" note) -- a crushed caterpillar simply queue_free()s and
## drops out of _caterpillar_markers, the same removal chunk-unload already
## performs. Returns whether anything was actually crushed.
func crush_caterpillars_near(pixel_position: Vector2, momentum_kg_m_s: float) -> bool:
	return _crush_markers_near(_caterpillar_markers, pixel_position, momentum_kg_m_s)


## The millipede-shaped sibling of crush_caterpillars_near (see
## docs/concept/soil_fauna.md "Generalized to millipedes too") -- a
## millipede is the identical SHAPE of victim a caterpillar already is (a
## real, independently-positioned Node2D, not per-tile cell state like a
## worm), so this shares crush_caterpillars_near's own body via
## _crush_markers_near rather than a third hand-copied implementation of
## the same "resolve the stepped-on tile, scan this chunk's own tracked
## markers by real position, free anything that clears the threshold"
## logic. Returns whether anything was actually crushed.
func crush_millipedes_near(pixel_position: Vector2, momentum_kg_m_s: float) -> bool:
	return _crush_markers_near(_millipede_markers, pixel_position, momentum_kg_m_s)


## The decomposer/bug-shaped sibling of crush_caterpillars_near/
## crush_millipedes_near (see docs/concept/soil_fauna.md "Generalized to
## bugs too" -- asked directly: "a bug should count as a small creature
## too"). A DecomposerMarker is the identical SHAPE of victim a
## caterpillar/millipede already is (a real, independently-positioned
## Node2D), tracked chunk-keyed in _decomposer_markers exactly like
## _caterpillar_markers/_millipede_markers, so this shares
## _crush_markers_near's own body directly. Returns whether anything was
## actually crushed.
func crush_decomposers_near(pixel_position: Vector2, momentum_kg_m_s: float) -> bool:
	return _crush_markers_near(_decomposer_markers, pixel_position, momentum_kg_m_s)


## Every grass frog standing on `pixel_position`'s own tile, crushed by a
## stepper of `stepper_mass_kg` (see docs/concept/soil_fauna.md "Generalized
## to ANY animal", CrushMechanic.crushes_underfoot). Reported in play:
## "Stepping on a frog doesn't kill it? ... A boar walking over a frog should
## kill it as well."
##
## Takes the stepper's own MASS rather than its momentum, unlike every crush
## call above it: an animal victim is decided by two terms, and the second one
## (does this whole body fit under that foot) is a question about the foot's
## mass, which a momentum has already thrown away. A frog is otherwise exactly
## the caterpillar-shaped victim this manager already knows -- a real Node2D
## in a chunk-keyed array, dying by its own crush() -- so it shares that
## walk. Every frog weighs the same, so its victim mass is its species' own
## tabulated figure, asked once rather than per marker.
func crush_grass_frogs_near(pixel_position: Vector2, stepper_mass_kg: float) -> bool:
	if not CrushMechanic.crushes_underfoot(stepper_mass_kg, CreatureMass.mass_kg_for(GrassFrogMarker.SPECIES)):
		return false
	return _crush_tracked_markers_on_tile(_grass_frog_markers, pixel_position)


## Every real ANIMAL in `creature_markers` standing on `pixel_position`'s own
## tile and light enough to go under the foot of a stepper of
## `stepper_mass_kg` (see CrushMechanic.crushes_underfoot) -- a mouse under a
## horse, a frog-sized thing under a boar -- crushed through its own crush(),
## which kills it the way every other death in this game happens rather than
## freeing it where it stands.
##
## The ONE crush entry point that is handed its victims instead of finding
## them: creature markers are not tracked by this manager at all (they live
## in the scene tree, and this class is a RefCounted with no access to it),
## and World's own crush pass already holds a cached group list of them for
## the several other loops it runs over the same list. Taking that list is
## both honest about where the truth lives and free -- the alternative is a
## second full group scan per stepper per frame, in the function this file's
## own FPS history says is the most expensive one in the game.
##
## `excluding` is the stepper itself when the stepper is a creature. The mass
## rule already rules self-crushing out (a body always outweighs its own
## foot), so this is a second, explicit guard on the thing that must never
## happen rather than the only thing preventing it.
func crush_creatures_near(
	creature_markers: Array, pixel_position: Vector2, stepper_mass_kg: float, excluding: Node2D = null
) -> bool:
	# The cheap term first: a stepper too light to crush anything at all
	# never walks the list (see CrushMechanic.crushes_underfoot's own first
	# term), which is most of the creatures in a loaded world.
	if not CrushMechanic.is_crushed_by(stepper_mass_kg * PebbleDispersion.FOOTSTEP_SPEED_MPS):
		return false
	var tile := _world_tile_for_pixel(pixel_position)
	var crushed_any := false
	for marker in creature_markers:
		if marker == excluding:
			continue
		# Defensive, the same contract _crush_tracked_markers_on_tile
		# documents: a creature freed earlier this frame must not crash the
		# scan of a creature that is still alive.
		if not is_instance_valid(marker) or marker.is_queued_for_deletion():
			continue
		# Tile before mass: almost nothing in a loaded world is standing on
		# the exact tile being stepped on, and a tile compare is pure
		# arithmetic on a position already in hand, where the mass term has
		# to reach into each creature's own metabolism for its live weight.
		if _world_tile_for_pixel(marker.position) != tile:
			continue
		if not CrushMechanic.crushes_underfoot(stepper_mass_kg, marker.current_mass_kg()):
			continue
		marker.crush()
		crushed_any = true
	return crushed_any


## The ant-shaped sibling of crush_caterpillars_near/crush_millipedes_near
## (see docs/concept/soil_fauna.md "Generalized to ants too" -- reported
## live: "ants are also not crushed when a player is walking over them").
## An ant forager is the identical SHAPE of victim a caterpillar/millipede
## already is (a real, independently-positioned Node2D), but tracked in
## _active_ant_foragers, keyed by each MOUND's own global tile rather than
## by chunk_coord the way _caterpillar_markers/_millipede_markers are (a
## single chunk can hold up to AntColony.MAX_MOUNDS mounds, each its own
## key -- see _dispatch_forager) -- so this cannot share
## _crush_markers_near's own chunk-keyed lookup directly. Scans every
## currently-active forager across every loaded mound instead (a small,
## already-capped-per-mound number -- active_forager_cap_at tops out at
## AntColony.MAX_CONCURRENT_FORAGERS -- the same bounded scale every other
## per-frame crush check already works at). Returns whether anything was
## actually crushed.
func crush_ants_near(pixel_position: Vector2, momentum_kg_m_s: float) -> bool:
	if not CrushMechanic.is_crushed_by(momentum_kg_m_s):
		return false
	var tile := _world_tile_for_pixel(pixel_position)
	var center_chunk := _chunk_coord_for_tile(tile)
	var crushed_any := false
	for global_tile in _active_ant_foragers.keys():
		var mound_chunk_coord := _chunk_coord_for_tile(global_tile)
		# Round-4 FPS regression (docs/concept/soil_fauna.md): a forager can
		# only ever wander AntColony.FORAGE_RADIUS_TILES (2.0) from its own
		# mound -- far inside a single CHUNK_SIZE=32 chunk -- so a real crush
		# can never reach a mound outside the immediate 3x3 chunk
		# neighbourhood around it, the exact same bound nearest_leaf_litter_
		# near/leaf_litter_near/disperse_leaf_litter_near already use for an
		# identical reason. Skipping every OTHER mound's key here (a cheap
		# Vector2i comparison) is what keeps this function from paying for
		# `markers.duplicate()` plus a full inner scan of EVERY mound in the
		# WHOLE LOADED WORLD, unconditionally, on every single crush check,
		# for every creature, every frame -- confirmed via PerfProbe as the
		# round-4 regression's own dominant cost (crush.creature_loop alone
		# measured 25-31ms per frame with the old unscoped scan).
		var chunk_offset := mound_chunk_coord - center_chunk
		if absi(chunk_offset.x) > 1 or absi(chunk_offset.y) > 1:
			continue
		var markers: Array = _active_ant_foragers[global_tile]
		for marker in markers.duplicate():
			# _active_ant_foragers is only pruned LAZILY, at the next
			# dispatch (see _dispatch_forager's own doc comment) -- a
			# forager that already completed its round trip and
			# queue_free()'d itself can sit here as a stale, by-then-
			# actually-freed reference for a while. Reported live, real
			# crash: "Invalid access to property or key 'position' on a
			# base object of type 'previously freed'" -- direct dot-access
			# on every entry assumed every one was still real.
			if not is_instance_valid(marker) or marker.is_queued_for_deletion():
				markers.erase(marker)
				continue
			if _world_tile_for_pixel(marker.position) == tile:
				markers.erase(marker)
				# crush(), not queue_free(): dies visibly (see
				# AntForagerMarker.crush()/SquashCrushEffect) instead of
				# instantly vanishing -- see docs/concept/soil_fauna.md's own
				# "no timed death animation either" scope cut, now closed.
				marker.crush()
				crushed_any = true
				# Registers as a future corpse immediately, chunk-keyed by
				# wherever it died -- see _ant_corpses' own doc comment.
				# ant_corpses_near/take_ant_corpse_near both still gate on
				# marker.is_corpse() (not yet true this frame -- it only
				# settles once SquashCrushEffect's own death-animation
				# linger finishes), so nothing can sense or forage it a
				# moment before its death animation has actually played out.
				var corpse_chunk := _chunk_coord_for_tile(tile)
				var corpses: Array = _ant_corpses.get(corpse_chunk, [])
				corpses.append(marker)
				_ant_corpses[corpse_chunk] = corpses
				# One real forager belonging to this mound is now gone --
				# also closes "no effect on the mound's own population/food
				# economy beyond the one forager actually lost" (same
				# section). _active_ant_foragers' own outer key IS the
				# mound's GLOBAL tile (see this function's own class-level
				# doc comment); AntColony's own _population dict is keyed by
				# LOCAL cell within its owning chunk, so the global tile is
				# converted back to local before reaching it. Silently a
				# no-op when no real colony is registered for this chunk
				# (e.g. a marker built standalone in a test) -- the same
				# "optional, narrows rather than breaks" contract every
				# other duck-typed world query in this file already has.
				var colony: AntColony = _ant_colonies.get(mound_chunk_coord)
				if colony != null:
					colony.forager_crushed(global_tile - mound_chunk_coord * CHUNK_SIZE)
	return crushed_any


## How close a query position has to be to a corpse's own position to
## count as "the same corpse" for take_ant_corpse_near -- mirrors
## LeafLitterField.CONSUME_TOLERANCE_PX's identical reasoning and value:
## a corpse never moves once settled, so an exact-enough match is all a
## caller handing back a position it already got from ant_corpses_near
## ever needs.
const ANT_CORPSE_TAKE_TOLERANCE_PX := 1.0


## Every SETTLED ant corpse (see AntForagerMarker.is_corpse) within
## `radius_px` of `pixel_position` -- the plural sensing query
## AntForagerMarker._sense_food_nearby uses to find real corpses to
## forage. Mirrors leaf_litter_near's identical shape (a 3x3 chunk-
## neighbourhood scan, chunk-keyed, radius checked in real pixels): a
## corpse, like a fallen leaf, belongs to no one mound any more (see
## _ant_corpses' own doc comment), so this is the same free-for-all
## sensing shape, not crush_ants_near's mound-keyed one. Each result is
## {"position": Vector2} -- a corpse carries no species/season the way a
## leaf does. A still-dying forager (crushed moments ago, mid
## SquashCrushEffect linger) is real but not yet a settled corpse --
## filtered out here via is_corpse(), not left to the caller, so nothing
## can sense (or take) a corpse before its own death animation has
## actually finished playing. Stale/already-freed entries are pruned
## lazily here, the same contract _active_ant_foragers' own readers use.
func ant_corpses_near(pixel_position: Vector2, radius_px: float) -> Array:
	var found: Array = []
	var center_chunk := _chunk_coord_for_tile(_world_tile_for_pixel(pixel_position))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var chunk_coord := center_chunk + Vector2i(dx, dy)
			var corpses: Array = _ant_corpses.get(chunk_coord, [])
			for corpse in corpses.duplicate():
				if not is_instance_valid(corpse) or corpse.is_queued_for_deletion():
					corpses.erase(corpse)
					continue
				if not corpse.is_corpse():
					continue
				if corpse.position.distance_to(pixel_position) <= radius_px:
					found.append({"position": corpse.position})
	return found


## Removes the settled ant corpse standing at `pixel_position` (see
## ANT_CORPSE_TAKE_TOLERANCE_PX), returning whether one was actually
## there -- the mutation counterpart of ant_corpses_near, mirroring
## consume_leaf_litter_at's identical "best-effort, no-op on a miss"
## contract. A caller is expected to have just learned this exact
## position FROM ant_corpses_near -- a corpse someone else already
## foraged in between is correctly reported as a miss, not an error.
## Frees the corpse marker directly: a forager taking it home IS the
## corpse's own real removal from the world, the same "the take itself is
## the world mutation" shape every other forage kind's take API already
## has (take_fruit_at, consume_leaf_litter_at, take_grass_seed_at).
func take_ant_corpse_near(pixel_position: Vector2) -> bool:
	var center_chunk := _chunk_coord_for_tile(_world_tile_for_pixel(pixel_position))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var chunk_coord := center_chunk + Vector2i(dx, dy)
			var corpses: Array = _ant_corpses.get(chunk_coord, [])
			for corpse in corpses.duplicate():
				if not is_instance_valid(corpse) or corpse.is_queued_for_deletion():
					corpses.erase(corpse)
					continue
				if not corpse.is_corpse():
					continue
				if corpse.position.distance_to(pixel_position) <= ANT_CORPSE_TAKE_TOLERANCE_PX:
					corpses.erase(corpse)
					corpse.queue_free()
					return true
	return false


## Every LIVE forager (currently SCOUTING/APPROACHING/RETURNING -- never a
## settled corpse, see is_corpse()) within `radius_px` of `pixel_position`
## -- real prey for a bird hunting live ants (see docs/concept/
## soil_fauna.md's own "Ants are not bird prey" scope cut, now closed).
## Mirrors crush_ants_near's own mound-keyed 3x3-chunk-neighbourhood scan
## exactly, NOT ant_corpses_near's simpler chunk-keyed shape: a live
## forager is tracked in _active_ant_foragers (mound-keyed, since it can
## only ever wander AntColony.FORAGE_RADIUS_TILES from its own mound --
## the identical bound that scan already exploits), not _ant_corpses
## (chunk-keyed, no owning mound once dead). Each result is
## {"position": Vector2}. Stale/already-freed entries are pruned lazily
## here, the same contract crush_ants_near's own readers already use.
func ants_near(pixel_position: Vector2, radius_px: float) -> Array:
	var found: Array = []
	var center_chunk := _chunk_coord_for_tile(_world_tile_for_pixel(pixel_position))
	for global_tile in _active_ant_foragers.keys():
		var mound_chunk_coord := _chunk_coord_for_tile(global_tile)
		var chunk_offset := mound_chunk_coord - center_chunk
		if absi(chunk_offset.x) > 1 or absi(chunk_offset.y) > 1:
			continue
		var markers: Array = _active_ant_foragers[global_tile]
		for marker in markers.duplicate():
			if not is_instance_valid(marker) or marker.is_queued_for_deletion():
				markers.erase(marker)
				continue
			if marker.is_corpse():
				continue  # dead -- not live prey, see ant_corpses_near instead
			if marker.position.distance_to(pixel_position) <= radius_px:
				found.append({"position": marker.position})
	return found


## Removes the live forager standing at `pixel_position`, returning
## whether one was actually there -- the mutation counterpart of
## ants_near, mirroring take_caterpillar_near's own "no death animation"
## contract exactly: a bird's meal is an entirely different event from
## being crushed underfoot (see that function's own doc comment), so this
## never calls crush() and never registers a corpse -- there is no body
## left for another ant to forage. Reduces the eaten forager's own
## mound's population (see AntColony.forager_eaten's own doc comment for
## why this is a distinctly-named sibling of forager_crushed, not a
## reuse of it -- Karma applies to a player-caused crush, never to
## natural predation).
func take_ant_near(pixel_position: Vector2) -> bool:
	var tile := _world_tile_for_pixel(pixel_position)
	var center_chunk := _chunk_coord_for_tile(tile)
	for global_tile in _active_ant_foragers.keys():
		var mound_chunk_coord := _chunk_coord_for_tile(global_tile)
		var chunk_offset := mound_chunk_coord - center_chunk
		if absi(chunk_offset.x) > 1 or absi(chunk_offset.y) > 1:
			continue
		var markers: Array = _active_ant_foragers[global_tile]
		for marker in markers.duplicate():
			if not is_instance_valid(marker) or marker.is_queued_for_deletion():
				markers.erase(marker)
				continue
			if marker.is_corpse():
				continue
			if _world_tile_for_pixel(marker.position) == tile:
				markers.erase(marker)
				marker.queue_free()
				var colony: AntColony = _ant_colonies.get(mound_chunk_coord)
				if colony != null:
					colony.forager_eaten(global_tile - mound_chunk_coord * CHUNK_SIZE)
				return true
	return false


## Shared body for crush_caterpillars_near/crush_millipedes_near -- both
## victims are a real Node2D tracked in a chunk_coord -> Array dictionary,
## crushed identically (see either caller's own doc comment for the
## reasoning); the ONLY thing that differs between them is which
## dictionary to scan, so that is the one thing passed in. `markers_by_
## chunk` is mutated in place (an Array is a reference type in GDScript),
## the same "erase from the caller's own tracking dict directly" contract
## crush_caterpillars_near's own pre-refactor body already had.
func _crush_markers_near(markers_by_chunk: Dictionary, pixel_position: Vector2, momentum_kg_m_s: float) -> bool:
	if not CrushMechanic.is_crushed_by(momentum_kg_m_s):
		return false
	return _crush_tracked_markers_on_tile(markers_by_chunk, pixel_position)


## _crush_markers_near's own walk, with the GATE lifted out (2026-09-19, see
## docs/concept/soil_fauna.md "Generalized to ANY animal"): an invertebrate
## victim's gate is a momentum threshold, a frog's is CrushMechanic.crushes_
## underfoot at a frog's own real mass, and the walk they share afterwards --
## "everything of this kind standing on exactly this tile dies and leaves
## tracking at once" -- is identical either way. Split rather than given a
## second momentum parameter so neither caller has to express its own gate in
## the other's terms.
func _crush_tracked_markers_on_tile(markers_by_chunk: Dictionary, pixel_position: Vector2) -> bool:
	var tile := _world_tile_for_pixel(pixel_position)
	var chunk_coord := _chunk_coord_for_tile(tile)
	var markers: Array = markers_by_chunk.get(chunk_coord, [])
	var crushed_any := false
	for marker in markers.duplicate():
		# Defensive, mirroring crush_ants_near's own real, reported crash
		# fix -- this dict is not guaranteed pruned eagerly the moment a
		# marker frees itself either, so a stale reference here must not
		# crash a direct .position access.
		if not is_instance_valid(marker) or marker.is_queued_for_deletion():
			markers.erase(marker)
			continue
		if _world_tile_for_pixel(marker.position) == tile:
			markers.erase(marker)
			# crush() when the marker has one (every real caterpillar/
			# millipede/decomposer does -- see MillipedeMarker.crush()/
			# CaterpillarMarker.crush()/DecomposerMarker.crush(), the real
			# death animation or squash-and-tint fallback each plays before
			# actually freeing itself) -- falls back to queue_free() so a
			# lightweight test double with no crush() of its own still
			# behaves exactly as it did before this method existed.
			if marker.has_method("crush"):
				marker.crush()
			else:
				marker.queue_free()
			crushed_any = true
	return crushed_any


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


## The single nearest fallen leaf to `pixel_position` within `radius_px`
## world pixels, as {position, species, season} (see LeafLitterField's own
## doc comment), or {} if none -- the concrete "is there litter nearby" query
## both DecomposerMarker's forage rewire and the player/animal dispersal
## entrypoints use. Scans only the 3x3 CHUNK NEIGHBOURHOOD around the query
## point, not every loaded chunk -- same bound (and the same reason) as
## worms_near/seeds_near: a leaf's own DecomposerMarker.SEARCH_RADIUS_PX (60)
## is far smaller than a chunk, so the neighbourhood is a strict superset of
## what can be in range.
func nearest_leaf_litter_near(pixel_position: Vector2, radius_px: float) -> Dictionary:
	var center_chunk := _chunk_coord_for_tile(_world_tile_for_pixel(pixel_position))
	var best := {}
	var best_distance := radius_px
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var field: LeafLitterField = _leaf_litter_fields.get(center_chunk + Vector2i(dx, dy))
			if field == null:
				continue
			var found := field.nearest_leaf_near(pixel_position, best_distance)
			if found.is_empty():
				continue
			var distance: float = found.position.distance_to(pixel_position)
			if distance <= best_distance:
				best = found
				best_distance = distance
	return best


## Plural counterpart of nearest_leaf_litter_near -- every leaf within
## `radius_px` across the same 3x3 chunk neighbourhood, not just the single
## closest one. Used by AntForagerMarker._sense_food_nearby with a SMALL,
## local SENSE_RADIUS_TILES around a scout's own current position (see
## docs/concept/soil_fauna.md "Scouting: real search, not omniscient
## dispatch") -- a caller cannot sense more than one real candidate at
## once without a plural query to run in the first place.
func leaf_litter_near(pixel_position: Vector2, radius_px: float) -> Array:
	var found: Array = []
	var center_chunk := _chunk_coord_for_tile(_world_tile_for_pixel(pixel_position))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var field: LeafLitterField = _leaf_litter_fields.get(center_chunk + Vector2i(dx, dy))
			if field == null:
				continue
			found.append_array(field.leaves_near(pixel_position, radius_px))
	return found


## Removes the fallen leaf standing at `pixel_position`, if there is one
## close enough (see LeafLitterField.CONSUME_TOLERANCE_PX) -- the mutation
## counterpart of nearest_leaf_litter_near, mirroring take_fruit_at/
## take_seed_at's identical best-effort contract. Same 3x3 chunk-neighbourhood
## scan as nearest_leaf_litter_near, since a leaf just reported by that query
## can be sitting in a neighbouring chunk's own field rather than the exact
## chunk `pixel_position` resolves to.
func consume_leaf_litter_at(pixel_position: Vector2) -> bool:
	var center_chunk := _chunk_coord_for_tile(_world_tile_for_pixel(pixel_position))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var field: LeafLitterField = _leaf_litter_fields.get(center_chunk + Vector2i(dx, dy))
			if field == null:
				continue
			if field.consume_leaf_at(pixel_position):
				return true
	return false


## Player/animal contact dispersion (see docs/concept/leaf_litter.md) --
## finds the single nearest leaf within PebbleDispersion.TRIGGER_RADIUS_PX
## of `walker_position` (across the same 3x3 chunk neighbourhood
## nearest_leaf_litter_near scans) and gives IT a chance to be nudged (see
## LeafLitterField.try_disperse_near). Relocation stays within the leaf's
## own originating chunk's field -- no cross-chunk hand-off bookkeeping, the
## same "not worth the complexity for a cosmetic scatter" reasoning
## relocate_leaf_near's own doc comment gives. Returns whether a leaf was
## actually found and nudged.
func disperse_leaf_litter_near(walker_position: Vector2) -> bool:
	var center_chunk := _chunk_coord_for_tile(_world_tile_for_pixel(walker_position))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var field: LeafLitterField = _leaf_litter_fields.get(center_chunk + Vector2i(dx, dy))
			if field == null:
				continue
			if field.try_disperse_near(
				walker_position, PebbleDispersion.TRIGGER_RADIUS_PX, _world_age_seconds
			):
				return true
	return false


## Every ambient flyer within `radius_px` of `pixel_position`, across the
## same 3x3 chunk neighbourhood every other "near" query in this file already
## scans (see nearest_leaf_litter_near/leaf_litter_near's own doc comments).
## The scoped counterpart of the FLOCK_GROUP-wide `get_tree().get_nodes_in_
## group` walk AmbientFlyerMarker._scan_for_partners used to do (see
## docs/concept/soil_fauna.md, round-4 FPS regression): a real courtship/
## bird-court/whirl partner is only ever within Courtship/BirdCourtship/
## SpiralFlight's own (small, tens-of-pixels) NOTICE_RADIUS_PX, so walking
## every flyer in the WHOLE LOADED WORLD, for every single flyer that wants
## a partner, every time its own PARTNER_SEARCH_INTERVAL cooldown expires,
## was pure work that grows with total world population rather than with
## anything actually local -- confirmed via PerfProbe as the round-4
## regression's own single largest cost (ambient_flyer._process measured
## 700-730ms per ~3s window against a population in the thousands).
## Reads _loaded_ambient_flyers directly -- the same per-chunk bucket
## EarthChunkManager itself already maintains (spawn_ambient_flyers/
## reconcile_bird_markers), so this needs no new bookkeeping.
func flyers_near(pixel_position: Vector2, radius_px: float) -> Array:
	var found: Array = []
	var center_chunk := _chunk_coord_for_tile(_world_tile_for_pixel(pixel_position))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var flyers: Array = _loaded_ambient_flyers.get(center_chunk + Vector2i(dx, dy), [])
			for flyer in flyers:
				if not is_instance_valid(flyer):
					continue
				if flyer.position.distance_to(pixel_position) <= radius_px:
					found.append(flyer)
	return found


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
			# Composes pollination_factor exactly like step_fruiting does --
			# this used to skip it entirely, so an unpollinated apple's
			# canopy correctly showed no fruit via step_fruiting, yet a
			# player (or an NPC gather instruction, see
			# NpcInstructionEffects) could still walk up and harvest one
			# anyway (see docs/concept/flora.md's "Pollination feedback").
			var pollination_factor := 1.0
			if TreeSpecies.needs_pollinators_for(species_id):
				pollination_factor = FruitingModel.pollination_factor(
					tree.pollination_visits_in_cycle(FruitingModel.BEARING_CYCLE_SECONDS, _world_age_seconds)
				)
			var yield_multiplier := TreeSpecies.yield_multiplier_for(species_id) * pollination_factor
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
## Reported live: "the mound should send out multiple scouts in random
## directs... then when the scouts return the mound dispatches more ants
## which follow / resolve the pheromone trails" -- per mound, per real
## forage opportunity, dispatches a whole WAVE of resolvers if a real
## cluster trail is already known (see AntColony.has_active_pheromone_
## trail), or a wave of blind scouts otherwise (see docs/concept/
## soil_fauna.md "Scouting: real search, not omniscient dispatch").
##
## Also checks colony.should_bud per mound (see docs/concept/soil_fauna.md
## "Colony budding") -- independent of the forage roll just below it, a
## genuinely overpopulated mound can bud on the same tick it also sends a
## forage wave out, the two are unrelated events.
func step_ants(delta_seconds: float) -> void:
	for chunk_coord in _ant_colonies:
		var colony: AntColony = _ant_colonies[chunk_coord]
		colony.advance(delta_seconds)
		var origin: Vector2i = chunk_coord * CHUNK_SIZE
		for cell in colony.mound_cells():
			if colony.should_bud(cell):
				_maybe_bud_ant_colony(chunk_coord, colony, cell)
			if not colony.should_forage(cell):
				continue
			if colony.has_active_pheromone_trail(cell):
				_dispatch_ant_resolver_wave(colony, origin, cell)
			else:
				_dispatch_ant_scout_wave(colony, origin, cell)

	_ant_moisture_refresh_accumulator += delta_seconds
	if _ant_moisture_refresh_accumulator < WORM_REFRESH_INTERVAL:
		return
	_ant_moisture_refresh_accumulator = 0.0
	_refresh_ant_moisture()


## The visible half of colony budding: real site selection (distance +
## food), the pure colony-side split, and a real new AntMoundMarker, in
## that order. A no-op if no real site qualifies this attempt (see
## _find_bud_site) -- should_bud's own small per-step chance means this is
## simply tried again on some future tick, the same "spread across many
## attempts" reasoning FORAGE_CHANCE's own dispatch already relies on.
func _maybe_bud_ant_colony(chunk_coord: Vector2i, colony: AntColony, from_cell: Vector2i) -> void:
	var to_cell := _find_bud_site(chunk_coord, colony, from_cell)
	if to_cell == Vector2i(-1, -1):
		return
	colony.bud_new_mound(from_cell, to_cell)
	var markers: Array = _ant_mound_markers.get(chunk_coord, [])
	markers.append(_spawn_ant_mound_marker(colony, chunk_coord, to_cell))
	_ant_mound_markers[chunk_coord] = markers


## The real site-selection half of colony budding (reported live: "they
## should found based on minimum distance to original mound and food
## availability within scout radius") -- AntColony.is_valid_mound_site
## only knows biome/occupancy (pure, world-blind), so the real distance
## sort and real food check both live here, EarthChunkManager's own job
## (see is_valid_mound_site's doc comment on the split). Every real
## candidate cell in the chunk is collected, sorted NEAREST first, then
## checked for real food in that order, returning the first (so nearest)
## one that actually has some -- Vector2i(-1, -1) if nothing in the whole
## chunk qualifies this attempt.
func _find_bud_site(chunk_coord: Vector2i, colony: AntColony, from_cell: Vector2i) -> Vector2i:
	var candidates: Array = []
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			var candidate := Vector2i(x, y)
			if colony.is_valid_mound_site(candidate):
				candidates.append(candidate)
	candidates.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return (a - from_cell).length_squared() < (b - from_cell).length_squared()
	)
	for candidate in candidates:
		var pixel := (
			Vector2(chunk_coord * CHUNK_SIZE + candidate) + Vector2(0.5, 0.5)
		) * float(TerrainRenderer.TILE_SIZE)
		if _has_food_near(pixel):
			return candidate
	return Vector2i(-1, -1)


## Whether ANY real, forageable food (leaf litter, grass seed, or a real
## windfall nut) sits within AntColony.SENSE_RADIUS_TILES of
## `pixel_position` -- the same "scout radius" a real scout would need to
## physically wander into range of to notice anything at all (see
## AntForagerMarker._sense_food_nearby's own identical leaf-then-seed-
## then-windfall priority query, which this mirrors at the SITE-SELECTION
## level rather than a live forager's own position). Only whether
## something is there, not which kind -- a bud site's own future scouts
## discover that for themselves exactly as any other scout does.
func _has_food_near(pixel_position: Vector2) -> bool:
	var sense_radius_px := AntColony.SENSE_RADIUS_TILES * float(TerrainRenderer.TILE_SIZE)
	if not leaf_litter_near(pixel_position, sense_radius_px).is_empty():
		return true
	var sense_radius_tiles := int(ceil(AntColony.SENSE_RADIUS_TILES))
	var seeds := grass_seeds_near(pixel_position, sense_radius_tiles)
	seeds = seeds.filter(func(s): return pixel_position.distance_to(s["position"]) <= sense_radius_px)
	if not seeds.is_empty():
		return true
	var fruit := fruit_near(pixel_position, sense_radius_tiles)
	fruit = fruit.filter(func(f): return pixel_position.distance_to(f["position"]) <= sense_radius_px)
	fruit = fruit.filter(func(f): return TreeSpecies.is_nut(String(f.get("species", ""))))
	return not fruit.is_empty()


## Shared by _load_chunk's own initial-mound loop and _maybe_bud_ant_
## colony's single new one -- one real, visible AntMoundMarker per mound
## cell, positioned at its own tile centre, its illustrated variant seeded
## from the GLOBAL cell (not the chunk-local one alone, or two different
## chunks' own local (0,0)-ish mounds would always pick the identical
## variant -- see IllustratedAntMoundSprite.frame_for), wired to the real
## colony/cell pair so its own visible size actually grows with the real
## population living there (see docs/concept/soil_fauna.md "Mound size
## grows with the colony"). Extracted rather than hand-copied a second
## time once budding needed the identical construction outside the
## chunk-load loop.
func _spawn_ant_mound_marker(colony: AntColony, chunk_coord: Vector2i, mound_cell: Vector2i) -> AntMoundMarker:
	var marker := AntMoundMarker.new()
	var global_cell := Vector2i(
		chunk_coord.x * CHUNK_SIZE + mound_cell.x, chunk_coord.y * CHUNK_SIZE + mound_cell.y
	)
	marker.mound_seed = hash(global_cell)
	marker.position = (Vector2(global_cell) + Vector2(0.5, 0.5)) * float(TerrainRenderer.TILE_SIZE)
	marker.setup(colony, mound_cell)
	_entities_parent.add_child(marker)
	return marker


## Water, not just food (see docs/concept/soil_fauna.md's own section by
## that name): pushes each loaded chunk's own live weather-derived soil
## moisture AND soil warmth into every mound it holds. Sampled per CHUNK's
## own centre tile, the identical "weather is already a per-region roll,
## sample the centre rather than the player's own tile" reasoning
## step_worms already uses for EarthwormPatch -- both are slow,
## day-timescale conditions, not something worth a per-mound lookup.
##
## Warmth reuses EarthwormPatch.soil_warmth(climate, season_warmth)
## directly -- the SAME real climate+season computation step_worms
## already runs for the identical soil, not a second, independent
## reading (see AntColony.record_warmth's own doc comment on why this
## particular fix exists: real winter, with nothing left for a mound to
## forage, was starving every colony to a literal, permanent population
## 0.0 within 180 real seconds -- reported live: "now i don't see any ant
## mounds at all anymore (fresh start, winter)").
func _refresh_ant_moisture() -> void:
	var season_warmth := _season_cycle.warmth_modifier(_world_age_seconds)
	for chunk_coord in _ant_colonies:
		var colony: AntColony = _ant_colonies[chunk_coord]
		var centre_tile: Vector2i = chunk_coord * CHUNK_SIZE + Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2)
		var centre_pixel := Vector2(
			float(centre_tile.x) + 0.5, float(centre_tile.y) + 0.5
		) * float(TerrainRenderer.TILE_SIZE)
		var moisture := _weather_model.soil_moisture(current_weather(centre_pixel))
		var climate := clampf(
			generator.temperature_at_global(centre_tile.x, centre_tile.y), 0.0, 1.0
		)
		var warmth := EarthwormPatch.soil_warmth(climate, season_warmth)
		for cell in colony.mound_cells():
			colony.record_moisture(cell, moisture)
			colony.record_warmth(cell, warmth)


## Central fallen-leaf-litter step (see LeafLitterField,
## docs/concept/leaf_litter.md): every loaded chunk's field ages/prunes past
## its own LIFETIME, and (for chunks actually in decoration range -- see
## _decorates) its visible MultiMesh is refilled from the field's own
## current leaves so a freshly-fallen leaf's fall animation is never delayed
## behind a slow periodic sprite-refresh cadence the way _sync_flower_
## sprites' own GRASS_REFRESH_INTERVAL is (a leaf's whole fall is over in
## under a second -- see LeafLitterField.TRANSITION_DURATION -- so unlike a
## flower's own many-minute growth, ANY multi-second sync lag here would
## hide the animation entirely, not just delay it). Refilling a chunk's own
## small, LIFETIME-bounded leaf count every tick is real, deliberate,
## bounded-by-decoration-radius work -- cheap relative to the per-NODE
## per-frame script/collision cost this whole rewrite exists to remove (see
## docs/concept/leaf_litter.md), not the same kind of cost at all.
##
## The day's live per-chunk wind (see set_wind) is read the SAME way
## step_flowers already reads it for seed dispersal -- no new weather state.
## Dirty-tracked (docs/concept/soil_fauna.md "FPS regression round 4"):
## _leaf_litter_renderer.fill used to run unconditionally here, every
## single frame, for every decorating chunk -- rebuilding that chunk's
## ENTIRE MultiMesh instance buffer (two engine calls per leaf, plus a
## fresh instance-dictionary allocation per leaf via instances_for_leaves)
## even for leaves that are fully settled and doing nothing at all.
## Measured live on the user's own long-played save: step_leaf_litter's own
## per-window cost climbed from ~20ms to ~578ms over ~19 real minutes as
## accumulated leaf count climbed to 2,361 -- real, and growing with real
## session length, because leaf litter is never persisted across save/load
## so a short session never sees it.
##
## LeafLitterField.generation() (bumped only when something about that
## field's rendering-relevant state actually changes -- see that method's
## own doc comment for the exact trigger list, including the subtle floating-
## leaf and transition-settle-snap cases) now lets this skip the call
## entirely once a chunk goes idle, compared each time against
## _leaf_litter_filled_generation's own last-pushed record for that chunk.
## Deliberately NOT a periodic throttle: unlike a flower's own many-minute
## growth, ANY multi-second sync lag here would hide the leaf-fall animation
## entirely, not just delay it (see this function's own header comment
## above) -- a chunk that IS changing still refills the very same frame it
## changes, exactly as before this fix.
##
## Visible-area filtering, on top of the dirty-tracking above (reported live:
## "make it so that it only computes leaf litter ... to the current visible
## area"): the dirty-tracking fix only ever gated WHETHER a chunk refills --
## it still rebuilt EVERY leaf that chunk held, however far from the camera,
## docs/concept/soil_fauna.md's own "architecturally unavoidable ...
## without a finer-grained per-leaf ... update" finding. When a refill does
## happen, only the leaves LeafLitterRenderer.leaves_in_view keeps (the same
## tile-precise camera cutoff/buffer grass's own GRASS_VIEW_BUFFER_TILES
## already established, see LEAF_LITTER_VIEW_BUFFER_TILES) are actually
## pushed -- bounding fill()'s own rebuild cost by nearby litter instead of
## by a chunk's total accumulated count, which is what a chunk with one
## far-off, perpetually-dirty floating leaf (the case that must always look
## dirty -- see LeafLitterField.generation()'s own doc comment) needed all
## along.
##
## This adds a SECOND, independent reason to refill beyond generation():
## "what counts as nearby" can change even when no leaf itself does, the
## moment the player's own tile moves (_disturbance_center_tile). Comparing
## it against _leaf_litter_view_synced_tile (that field's own doc comment)
## mirrors _leaf_litter_filled_generation's identical compare-act-sync
## shape, and stays cheap for the same reason a chunk-boundary crossing is
## cheap to check for grass: a player's TILE changes at a walking pace (a
## few times a second at most), nowhere near the 60/sec this function itself
## runs at.
func step_leaf_litter(delta_seconds: float) -> void:
	_leaf_litter_renderer.set_current_time(_world_age_seconds)
	var weather_day := int(_world_age_seconds / WEATHER_PERIOD_SECONDS)
	var half_span := _visible_half_span_tiles()
	var view_moved := _disturbance_center_tile != _leaf_litter_view_synced_tile
	for chunk_coord in _leaf_litter_fields:
		var field: LeafLitterField = _leaf_litter_fields[chunk_coord]
		var decorating := _decorates(chunk_coord)
		# Far-chunk gate (see FAR_CHUNK_ADVANCE_SECONDS): a chunk nobody can
		# see advances only once its pending time reaches the interval, and
		# hands all of it over; one back in range flushes on this very frame.
		var pending: float = float(_leaf_litter_far_pending.get(chunk_coord, 0.0)) + delta_seconds
		if decorating or pending >= FAR_CHUNK_ADVANCE_SECONDS:
			var region_seed := hash("%d_%d" % [chunk_coord.x, chunk_coord.y])
			field.set_wind(
				_weather_model.wind_direction_for(weather_day, region_seed),
				_weather_model.dispersal_strength_for(
					_weather_model.weather_at(weather_day, region_seed)
				)
			)
			field.advance(pending, _world_age_seconds)
			pending = 0.0
		_leaf_litter_far_pending[chunk_coord] = pending
		var mmi: MultiMeshInstance2D = _leaf_litter_mmis.get(chunk_coord)
		if mmi == null:
			continue
		mmi.visible = decorating
		# Explicitly typed, not := -- Dictionary.get's Variant return compared
		# against field.generation()'s int makes static := inference bail
		# ("cannot infer the type... doesn't have a set type"), the same
		# reason every sibling dirty-check in this file (see
		# _footprint_filled_generation's identical comparison) always inlines
		# this comparison into the if rather than naming it first.
		var data_changed: bool = _leaf_litter_filled_generation.get(chunk_coord, -1) != field.generation()
		if mmi.visible and (data_changed or view_moved):
			var visible_leaves := LeafLitterRenderer.leaves_in_view(
				field.leaves(), _disturbance_center_tile, half_span, LEAF_LITTER_VIEW_BUFFER_TILES
			)
			_leaf_litter_renderer.fill(mmi, visible_leaves)
			_leaf_litter_filled_generation[chunk_coord] = field.generation()
	_leaf_litter_view_synced_tile = _disturbance_center_tile


## Real per-mound SCOUT dispatch (see docs/concept/soil_fauna.md "Scouting:
## real search, not omniscient dispatch"). Replaces the three separate
## _forage_seed_near_mound/_forage_windfall_near_mound/_forage_leaf_near_
## mound functions this used to be (each ran its own omniscient "every
## candidate within the mound's whole forage reach, from this stationary
## point" query and picked the best-scored one before ever dispatching
## anyone -- exactly the pattern reported live as a problem: "ants go
## straight to the next leaf... no omniscience please"). A dispatched
## scout starts with NO known target or forage_kind at all -- it discovers
## both itself, via its own local sensing as it wanders (see
## AntForagerMarker._sense_food_nearby/_step_scouting), which is also why
## no biome pre-check is needed here any more: seed/windfall queries
## simply come back empty wherever the world itself does not place that
## kind of food, the same way they always have.
##
## Capped at colony.active_forager_cap_at(cell) CONCURRENT foragers per
## mound, not a hardcoded one -- that cap scales with the mound's own
## queen-driven population (see AntColony/AntPopulationModel), so a
## thriving colony visibly has more than one worker out at once. Stale
## (freed) entries in _active_ant_foragers are pruned here, lazily, rather
## than eagerly elsewhere.
## A single, un-spread scout -- kept for existing direct-dispatch callers
## (chiefly tests exercising ordinary cap-limiting/dispatch bookkeeping in
## isolation, unrelated to wave-spreading itself). Real production
## dispatch (step_ants) always goes through _dispatch_ant_scout_wave/
## _dispatch_ant_resolver_wave instead -- see those functions' own doc
## comments.
func _dispatch_ant_scout(colony: AntColony, origin: Vector2i, cell: Vector2i) -> void:
	_dispatch_forager(colony, origin, cell, Vector2.ZERO, false)


## Real per-mound scout dispatch when no cluster trail is known yet (see
## AntColony.SCOUT_WAVE_SIZE's own doc comment) -- several scouts at once,
## each assigned a DIFFERENT sector spread evenly around a circle (see
## AntScoutWander.spread_heading, which gently nudges each one's own
## wander toward its assigned sector without ever overriding a REAL
## sensed trail) rather than one scout's own independent wander_seed
## alone, which could coincidentally correlate across several dispatched
## close together and read as one wandering ant with others following in
## a line -- reported live, exactly that: "the mound should send out
## multiple scouts in random directs".
func _dispatch_ant_scout_wave(colony: AntColony, origin: Vector2i, cell: Vector2i) -> void:
	for i in AntColony.SCOUT_WAVE_SIZE:
		var angle := TAU * float(i) / float(AntColony.SCOUT_WAVE_SIZE)
		_dispatch_forager(colony, origin, cell, Vector2.from_angle(angle), false)


## Real per-mound resolver dispatch once a scout has already reported a
## real cluster (see AntColony.RESOLVER_WAVE_SIZE's own doc comment) --
## reported live: "then when the scouts return the mound dispatches more
## ants which follow / resolve the pheromone trails". No assigned sector
## at all: a resolver does not explore, it follows the one real trail it
## senses (see AntForagerMarker._step_scouting's own resolver branch).
func _dispatch_ant_resolver_wave(colony: AntColony, origin: Vector2i, cell: Vector2i) -> void:
	for i in AntColony.RESOLVER_WAVE_SIZE:
		_dispatch_forager(colony, origin, cell, Vector2.ZERO, true)


## Real per-mound forager dispatch (see docs/concept/soil_fauna.md "Real
## foraging: a round trip, not an instant resolve" and "Scouting: real
## search, not omniscient dispatch") -- the actual node creation both
## _dispatch_ant_scout/_dispatch_ant_scout_wave/_dispatch_ant_resolver_
## wave delegate to. Capped at colony.active_forager_cap_at(cell)
## CONCURRENT foragers per mound, not a hardcoded one -- that cap scales
## with the mound's own queen-driven population (see AntColony/
## AntPopulationModel), so a thriving colony visibly has more than one
## worker out at once, wave or not. Stale (freed) entries in
## _active_ant_foragers are pruned here, lazily, rather than eagerly
## elsewhere.
func _dispatch_forager(
	colony: AntColony, origin: Vector2i, cell: Vector2i, assigned_heading_bias: Vector2, is_resolver: bool
) -> void:
	if _entities_parent == null:
		return
	var global_tile: Vector2i = origin + cell
	var active: Array = _active_ant_foragers.get(global_tile, [])
	active = active.filter(func(f): return is_instance_valid(f) and not f.is_queued_for_deletion())
	# The colony's own cap, scaled by the player's ant-forager density knob
	# (never below the colony's floor of one -- see SimulationSettings).
	if active.size() >= SimulationSettings.scaled_cap(colony.active_forager_cap_at(cell), _population_density["ant_foragers"], 1):
		_active_ant_foragers[global_tile] = active
		return
	var mound_pixel := Vector2(
		float(global_tile.x) + 0.5, float(global_tile.y) + 0.5
	) * float(TerrainRenderer.TILE_SIZE)
	var forager := AntForagerMarker.new()
	forager.mound_position = mound_pixel
	forager.position = mound_pixel
	forager.scout = not is_resolver
	forager.resolver = is_resolver
	forager.assigned_heading_bias = assigned_heading_bias
	forager.setup(self, colony, cell)
	_entities_parent.add_child(forager)
	active.append(forager)
	_active_ant_foragers[global_tile] = active


## Real per-chunk bee stepping (see docs/concept/bees.md) -- mirrors
## step_ants' own shape: advances every loaded BeeColony/WildBeePatch,
## checks swarming (colonies only -- see BeeColony.should_bud) and
## absconding/relocation (both -- see BeeColony.should_abscond_at/
## WildBeePatch.should_relocate_at, the one mechanism with no ant
## precedent at all) per cell, and dispatches a real forager wherever
## conditions allow.
func step_bees(delta_seconds: float) -> void:
	for chunk_coord in _bee_colonies:
		var colony: BeeColony = _bee_colonies[chunk_coord]
		colony.advance(delta_seconds)
		var origin: Vector2i = chunk_coord * CHUNK_SIZE
		for cell in colony.hive_cells():
			if colony.should_abscond_at(cell):
				_maybe_abscond_bee_colony(chunk_coord, colony, cell)
				continue
			if colony.should_bud(cell):
				_maybe_bud_bee_colony(chunk_coord, colony, cell)
			if not colony.should_forage(cell):
				continue
			_dispatch_bee_forager(colony, origin, cell)

	for chunk_coord in _wild_bee_patches:
		var patch: WildBeePatch = _wild_bee_patches[chunk_coord]
		patch.advance(delta_seconds)
		var wild_origin: Vector2i = chunk_coord * CHUNK_SIZE
		for cell in patch.nest_cells():
			if patch.should_relocate_at(cell):
				_maybe_relocate_wild_bee_nest(chunk_coord, patch, cell)
				continue
			if not patch.should_forage(cell):
				continue
			_dispatch_wild_bee_forager(patch, wild_origin, cell)

	_bee_warmth_refresh_accumulator += delta_seconds
	if _bee_warmth_refresh_accumulator < WORM_REFRESH_INTERVAL:
		return
	_bee_warmth_refresh_accumulator = 0.0
	_refresh_bee_warmth()


## Swarming (see BeeColony.bud_new_hive's own doc comment: the real
## biological mechanism a honeybee colony reproduces by). A no-op if no
## real site qualifies this attempt (see _find_bee_hive_site) --
## should_bud's own small per-step chance means this is simply tried
## again on some future tick, the same "spread across many attempts"
## reasoning FORAGE_CHANCE's own dispatch already relies on. The
## ORIGINAL hive's own marker is untouched -- budding only ever adds a
## new one.
func _maybe_bud_bee_colony(chunk_coord: Vector2i, colony: BeeColony, from_cell: Vector2i) -> void:
	var to_cell := _find_bee_hive_site(chunk_coord, colony, from_cell)
	if to_cell == Vector2i(-1, -1):
		return
	colony.bud_new_hive(from_cell, to_cell)
	var markers: Dictionary = _bee_hive_markers.get(chunk_coord, {})
	markers[to_cell] = _spawn_bee_hive_marker(colony, chunk_coord, to_cell)
	_bee_hive_markers[chunk_coord] = markers


## Absconding triggered from INSIDE step_bees's own economic checks (see
## BeeColony.should_abscond_at: population collapsed to zero, or forage
## has genuinely dried up) -- as opposed to relocate_bee_hive_after_
## harvest below, triggered externally by the harvest mechanic itself. A
## no-op if nowhere real qualifies (see _find_bee_hive_site) -- the
## colony simply tries again next tick, same as budding's identical
## "spread across many attempts" shape.
func _maybe_abscond_bee_colony(chunk_coord: Vector2i, colony: BeeColony, from_cell: Vector2i) -> void:
	var to_cell := _find_bee_hive_site(chunk_coord, colony, from_cell)
	if to_cell == Vector2i(-1, -1):
		return
	colony.abscond_to(from_cell, to_cell)
	_replace_bee_hive_marker(chunk_coord, colony, from_cell, to_cell)
	_retarget_active_bee_foragers(chunk_coord, from_cell, to_cell)


## Called by BeeHiveMarker.harvest's own final hit (see that method's own
## doc comment) -- the harvest mechanic's real hand-off back into the
## world once a hive has been broken down to structural collapse.
## Finds which chunk owns `colony` by identity: colonies are rare enough
## per loaded region that a linear scan costs nothing real, and this only
## ever runs on a genuine player-triggered harvest event, never a hot
## per-frame path. A no-op for a colony this manager does not actually
## know about (the same defensive "narrows, doesn't break" contract every
## other optional-world accessor in this codebase already has) -- and,
## separately, a no-op if no real site qualifies (see
## _find_bee_hive_site): the colony is genuinely lost, an honest real
## consequence of "no food anywhere nearby" (see docs/concept/bees.md),
## not something papered over with a guaranteed-success relocation.
func relocate_bee_hive_after_harvest(colony: BeeColony, cell: Vector2i) -> void:
	var chunk_coord := Vector2i(-1, -1)
	for candidate in _bee_colonies:
		if _bee_colonies[candidate] == colony:
			chunk_coord = candidate
			break
	if chunk_coord == Vector2i(-1, -1):
		return
	var to_cell := _find_bee_hive_site(chunk_coord, colony, cell)
	if to_cell == Vector2i(-1, -1):
		return
	colony.abscond_to(cell, to_cell)
	_replace_bee_hive_marker(chunk_coord, colony, cell, to_cell)
	_retarget_active_bee_foragers(chunk_coord, cell, to_cell)


## The real site-selection half of both swarming and absconding (see
## BeeColony.is_valid_hive_site's own doc comment on the split: that
## method only knows biome/occupancy, pure and world-blind -- the real
## distance sort and real nearby-forage check both live here,
## EarthChunkManager's own job). Mirrors _find_bud_site's own shape
## exactly: every real candidate cell in the chunk, sorted NEAREST first,
## checked for real nearby forage AND a real physical anchor in that
## order, returning the first (so nearest) that has both -- Vector2i(-1,
## -1) if nothing in the whole chunk qualifies this attempt.
func _find_bee_hive_site(chunk_coord: Vector2i, colony: BeeColony, from_cell: Vector2i) -> Vector2i:
	var candidates: Array = []
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			var candidate := Vector2i(x, y)
			if colony.is_valid_hive_site(candidate):
				candidates.append(candidate)
	candidates.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return (a - from_cell).length_squared() < (b - from_cell).length_squared()
	)
	for candidate in candidates:
		var global_tile: Vector2i = chunk_coord * CHUNK_SIZE + candidate
		var pixel := (Vector2(global_tile) + Vector2(0.5, 0.5)) * float(TerrainRenderer.TILE_SIZE)
		if not _has_bee_food_near(pixel):
			continue
		if _has_real_hive_anchor(global_tile):
			return candidate
	return Vector2i(-1, -1)


## Requested live: "Beehives should only be able to build on trees or
## structures like houses .. not free floating over a river or ground."
## A real hive hangs from a real tree branch, or (a beekeeper's own
## manmade hive) is fixed to a real structure -- never bare open ground,
## and never open water. Two gates: never a river/lake tile (mirrors
## TreeRenderer.spawn_trees's own river exclusion -- a hive floating over
## open water is exactly the same bug class real trees already got fixed
## for), then a real standing tree OR a real building piece ON THE HIVE'S
## OWN TILE.
##
## Tightened from "within HIVE_ANCHOR_RADIUS_TILES (2.0)" after the same
## thing was reported again: *"Beehives should not be built on grass...
## they need a tree branch to build it please"*. A radius admits the tile
## NEXT TO a trunk, which is bare grass with a tree visible from it -- the
## hive stood on the ground between, which is exactly what a radius can
## never express. What holds a hive up is not nearby scenery; it is the
## branch it hangs off, and that is a property of one tile. The radius, and
## the `pixel_position` argument only its tree query needed, are both gone
## rather than left at 0.0, so there is no dial left to widen this back
## into the same bug.
func _has_real_hive_anchor(global_tile: Vector2i) -> bool:
	if is_river_at_global(global_tile.x, global_tile.y):
		return false
	if is_lake_at_global(global_tile.x, global_tile.y):
		return false
	return _has_standing_tree_at(global_tile) or _has_building_piece_at(global_tile)


## A real, standing tree whose OWN tile is `global_tile` -- the branch a
## hive hangs from. Only that tile's own chunk is searched, because a tree
## is spawned into the chunk its position falls in, so no other chunk's
## list can hold a tree standing here.
##
## Skips a felled tree for the same reason trees_near does: a stump is not
## a perch, and it is not a branch either.
func _has_standing_tree_at(global_tile: Vector2i) -> bool:
	var chunk_coord := _chunk_coord_for_tile(global_tile)
	for tree in _loaded_trees.get(chunk_coord, []):
		if not is_instance_valid(tree) or tree.is_felled():
			continue
		var tile := Vector2i(
			floori(tree.position.x / float(TerrainRenderer.TILE_SIZE)),
			floori(tree.position.y / float(TerrainRenderer.TILE_SIZE))
		)
		if tile == global_tile:
			return true
	return false


## A real BuildingPiece stands ON `global_tile` -- the same
## chunk.modifications + BuildingPiece.has_piece idiom TreeRenderer.
## spawn_trees already uses to keep a tree from rooting in a house's own
## floor, read here instead of written (a hive does not uproot the
## structure, it hangs on it). One tile, so one chunk: the square this
## used to walk existed only to cover HIVE_ANCHOR_RADIUS_TILES spilling
## across a chunk edge, and there is no radius any more. An unloaded chunk
## contributes nothing (fails closed toward "no building there", the same
## honest "only sees what's currently loaded" limit _has_bee_food_near and
## trees_near already accept).
func _has_building_piece_at(global_tile: Vector2i) -> bool:
	var chunk_coord := _chunk_coord_for_tile(global_tile)
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk == null:
		return false
	var local := global_tile - chunk_coord * CHUNK_SIZE
	return BuildingPiece.has_piece(chunk.modifications.get(local, ""))


## The one absconding trigger a wild nest keeps (see WildBeePatch.
## should_relocate_at's own doc comment) -- mirrors _maybe_abscond_bee_
## colony's own shape, minus the honey/swarm halves a wild nest has
## none of.
func _maybe_relocate_wild_bee_nest(chunk_coord: Vector2i, patch: WildBeePatch, from_cell: Vector2i) -> void:
	var to_cell := _find_wild_bee_nest_site(chunk_coord, patch, from_cell)
	if to_cell == Vector2i(-1, -1):
		return
	patch.relocate_to(from_cell, to_cell)
	_replace_wild_bee_nest_marker(chunk_coord, patch, from_cell, to_cell)


## Mirrors _find_bee_hive_site exactly, against WildBeePatch's own
## is_valid_nest_site.
func _find_wild_bee_nest_site(chunk_coord: Vector2i, patch: WildBeePatch, from_cell: Vector2i) -> Vector2i:
	var candidates: Array = []
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			var candidate := Vector2i(x, y)
			if patch.is_valid_nest_site(candidate):
				candidates.append(candidate)
	candidates.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return (a - from_cell).length_squared() < (b - from_cell).length_squared()
	)
	for candidate in candidates:
		var pixel := (
			Vector2(chunk_coord * CHUNK_SIZE + candidate) + Vector2(0.5, 0.5)
		) * float(TerrainRenderer.TILE_SIZE)
		if _has_bee_food_near(pixel):
			return candidate
	return Vector2i(-1, -1)


## Whether any real, in-bloom flower with real nectar sits within
## BeeColony.SENSE_RADIUS_TILES of `pixel_position` -- the real "scout
## radius" a bee forager would need to physically wander into range of
## to notice anything at all (see BeeForagerMarker._sense_food_nearby's
## own identical query, mirrored here at the SITE-SELECTION level rather
## than a live forager's own position -- the same relationship
## _has_food_near already has to AntForagerMarker._sense_food_nearby).
## Shared by both honeybee-hive and wild-bee-nest site search: the real
## forage check is identical for both real animals, only WHICH kind of
## home is being searched for differs.
func _has_bee_food_near(pixel_position: Vector2) -> bool:
	var sense_radius_px := BeeColony.SENSE_RADIUS_TILES * float(TerrainRenderer.TILE_SIZE)
	var sense_radius_tiles := int(ceil(BeeColony.SENSE_RADIUS_TILES))
	var flowers := flowers_near(pixel_position, sense_radius_tiles)
	flowers = flowers.filter(func(f): return pixel_position.distance_to(f["position"]) <= sense_radius_px)
	flowers = flowers.filter(func(f): return float(f.get("nectar", 0.0)) > 0.0)
	return not flowers.is_empty()


## Shared by _load_chunk's own initial-hive loop and both swarming/
## absconding's own single new one -- one real, visible BeeHiveMarker
## per hive cell, mirrors _spawn_ant_mound_marker's own shape exactly.
func _spawn_bee_hive_marker(colony: BeeColony, chunk_coord: Vector2i, hive_cell: Vector2i) -> BeeHiveMarker:
	var marker := BeeHiveMarker.new()
	var global_cell := Vector2i(
		chunk_coord.x * CHUNK_SIZE + hive_cell.x, chunk_coord.y * CHUNK_SIZE + hive_cell.y
	)
	marker.position = (Vector2(global_cell) + Vector2(0.5, 0.5)) * float(TerrainRenderer.TILE_SIZE)
	marker.setup(self, colony, hive_cell)
	_entities_parent.add_child(marker)
	return marker


## Mirrors _spawn_bee_hive_marker exactly, for WildBeeNestMarker -- no
## `self`/world reference at all (see that marker's own doc comment: a
## wild nest is never player-interactive, so it never needs to call
## back into the world the way a harvested hive does).
func _spawn_wild_bee_nest_marker(patch: WildBeePatch, chunk_coord: Vector2i, nest_cell: Vector2i) -> WildBeeNestMarker:
	var marker := WildBeeNestMarker.new()
	var global_cell := Vector2i(
		chunk_coord.x * CHUNK_SIZE + nest_cell.x, chunk_coord.y * CHUNK_SIZE + nest_cell.y
	)
	marker.position = (Vector2(global_cell) + Vector2(0.5, 0.5)) * float(TerrainRenderer.TILE_SIZE)
	marker.setup(patch, nest_cell)
	_entities_parent.add_child(marker)
	return marker


## Relocation (absconding, or a harvest hand-off): the OLD marker at
## `from_cell` is torn down -- defensively (a harvest-triggered call has
## already freed itself before ever calling in here, an absconding-
## triggered one has not; checking is_queued_for_deletion covers both
## without a separate branch for which caller this was) -- and a brand
## new one spawned at `to_cell`.
func _replace_bee_hive_marker(chunk_coord: Vector2i, colony: BeeColony, from_cell: Vector2i, to_cell: Vector2i) -> void:
	var markers: Dictionary = _bee_hive_markers.get(chunk_coord, {})
	if markers.has(from_cell):
		var old_marker = markers[from_cell]
		if is_instance_valid(old_marker) and not old_marker.is_queued_for_deletion():
			old_marker.queue_free()
		markers.erase(from_cell)
	markers[to_cell] = _spawn_bee_hive_marker(colony, chunk_coord, to_cell)
	_bee_hive_markers[chunk_coord] = markers


## Called by both real relocation call sites (_maybe_abscond_bee_colony,
## relocate_bee_hive_after_harvest), right alongside _replace_bee_hive_
## marker -- the real forager-side half of relocation _replace_bee_hive_
## marker alone never covered (confirmed bug): a forager already
## scouting/approaching/returning for `from_cell`'s hive at the moment it
## relocates otherwise keeps flying toward the OLD site's now-torn-down
## marker forever (see BeeForagerMarker.retarget_hive's own doc comment),
## and _active_bee_foragers' own dictionary key never migrates off the
## old global tile, silently letting the per-hive concurrent-forager cap
## (colony.active_forager_cap_at, checked by _dispatch_bee_forager) go
## uncounted against the real, current site.
##
## Merges into whatever the new global tile already tracks rather than
## overwriting it -- defensive, not reachable in ordinary play today
## (`to_cell` was, by construction, not a hive a moment ago, so nothing
## could have been dispatched there yet), but cheap and matches the
## "narrows, doesn't break" contract every other optional-world accessor
## in this codebase already keeps.
func _retarget_active_bee_foragers(chunk_coord: Vector2i, from_cell: Vector2i, to_cell: Vector2i) -> void:
	var origin: Vector2i = chunk_coord * CHUNK_SIZE
	var old_global_tile: Vector2i = origin + from_cell
	var relocating: Array = _active_bee_foragers.get(old_global_tile, [])
	_active_bee_foragers.erase(old_global_tile)
	if relocating.is_empty():
		return
	var new_global_tile: Vector2i = origin + to_cell
	var new_hive_pixel := (
		Vector2(new_global_tile) + Vector2(0.5, 0.5)
	) * float(TerrainRenderer.TILE_SIZE)
	var still_active: Array = _active_bee_foragers.get(new_global_tile, [])
	for forager in relocating:
		if not is_instance_valid(forager) or forager.is_queued_for_deletion():
			continue
		forager.retarget_hive(new_hive_pixel, to_cell)
		still_active.append(forager)
	_active_bee_foragers[new_global_tile] = still_active


## Mirrors _replace_bee_hive_marker exactly, for WildBeeNestMarker.
func _replace_wild_bee_nest_marker(chunk_coord: Vector2i, patch: WildBeePatch, from_cell: Vector2i, to_cell: Vector2i) -> void:
	var markers: Dictionary = _wild_bee_nest_markers.get(chunk_coord, {})
	if markers.has(from_cell):
		var old_marker = markers[from_cell]
		if is_instance_valid(old_marker) and not old_marker.is_queued_for_deletion():
			old_marker.queue_free()
		markers.erase(from_cell)
	markers[to_cell] = _spawn_wild_bee_nest_marker(patch, chunk_coord, to_cell)
	_wild_bee_nest_markers[chunk_coord] = markers


## Mirrors _dispatch_forager's own shape exactly, against BeeColony
## instead of AntColony -- one bee at a time, no wave dispatch (see
## docs/concept/bees.md's own "What's reused verbatim, what's a
## deliberate new duplicate, and why": no pheromone-trail recruitment
## for bees this pass), still capped at colony.active_forager_cap_at(cell)
## CONCURRENT foragers, still scaling with the hive's own queen-driven
## population.
func _dispatch_bee_forager(colony: BeeColony, origin: Vector2i, cell: Vector2i) -> void:
	if _entities_parent == null:
		return
	var global_tile: Vector2i = origin + cell
	var active: Array = _active_bee_foragers.get(global_tile, [])
	active = active.filter(func(f): return is_instance_valid(f) and not f.is_queued_for_deletion())
	# The hive's own cap, scaled by the player's bee-forager density knob
	# (never below the hive's floor of one -- see SimulationSettings).
	if active.size() >= SimulationSettings.scaled_cap(colony.active_forager_cap_at(cell), _population_density["bee_foragers"], 1):
		_active_bee_foragers[global_tile] = active
		return
	var hive_pixel := (Vector2(global_tile) + Vector2(0.5, 0.5)) * float(TerrainRenderer.TILE_SIZE)
	var forager := BeeForagerMarker.new()
	forager.hive_position = hive_pixel
	forager.position = hive_pixel
	forager.scout = true
	forager.setup(self, colony, cell)
	_entities_parent.add_child(forager)
	active.append(forager)
	_active_bee_foragers[global_tile] = active


## Mirrors _dispatch_bee_forager exactly, against WildBeePatch -- capped
## at exactly ONE concurrent forager per nest: a solitary nest has one
## resident female per real "worker," not a population-scaled cap the
## way a hive has.
func _dispatch_wild_bee_forager(patch: WildBeePatch, origin: Vector2i, cell: Vector2i) -> void:
	if _entities_parent == null:
		return
	var global_tile: Vector2i = origin + cell
	var active: Array = _active_wild_bee_foragers.get(global_tile, [])
	active = active.filter(func(f): return is_instance_valid(f) and not f.is_queued_for_deletion())
	if active.size() >= 1:
		_active_wild_bee_foragers[global_tile] = active
		return
	var nest_pixel := (Vector2(global_tile) + Vector2(0.5, 0.5)) * float(TerrainRenderer.TILE_SIZE)
	var forager := BeeForagerMarker.new()
	forager.hive_position = nest_pixel
	forager.position = nest_pixel
	forager.scout = true
	forager.is_wild_bee = true
	forager.setup(self, patch, cell)
	_entities_parent.add_child(forager)
	active.append(forager)
	_active_wild_bee_foragers[global_tile] = active


## Winter dormancy (see BeeColony.dormancy_multiplier_at) -- mirrors
## _refresh_ant_moisture's own warmth half exactly, reusing
## EarthwormPatch.soil_warmth's identical real climate+season
## computation (same soil, same real signal) -- minus the moisture half:
## bees have no water-driven capacity bonus at all (see docs/concept/
## bees.md's own doc comment on why).
func _refresh_bee_warmth() -> void:
	var season_warmth := _season_cycle.warmth_modifier(_world_age_seconds)
	for chunk_coord in _bee_colonies:
		var colony: BeeColony = _bee_colonies[chunk_coord]
		var centre_tile: Vector2i = chunk_coord * CHUNK_SIZE + Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2)
		var climate := clampf(
			generator.temperature_at_global(centre_tile.x, centre_tile.y), 0.0, 1.0
		)
		var warmth := EarthwormPatch.soil_warmth(climate, season_warmth)
		for cell in colony.hive_cells():
			colony.record_warmth(cell, warmth)
	# Wild bee nests get the identical real climate+season warmth signal --
	# same soil, same real mechanism -- driving WildBeePatch's own
	# die-off/re-hatch transition (see docs/concept/seasonal_behavior.md,
	# "Wild bee die-off / re-hatch"). A separate loop rather than folding
	# into the one above: _bee_colonies and _wild_bee_patches are two
	# independently-keyed dictionaries, a chunk can hold either, both, or
	# neither.
	for chunk_coord in _wild_bee_patches:
		var patch: WildBeePatch = _wild_bee_patches[chunk_coord]
		var centre_tile: Vector2i = chunk_coord * CHUNK_SIZE + Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2)
		var climate := clampf(
			generator.temperature_at_global(centre_tile.x, centre_tile.y), 0.0, 1.0
		)
		var warmth := EarthwormPatch.soil_warmth(climate, season_warmth)
		for cell in patch.nest_cells():
			patch.record_warmth(cell, warmth)


## Inches every surfaced worm along, every frame, and keeps its animation
## current -- a worm at the surface is not a decal, it crawls slowly
## within its own cell (see EarthwormPatch.crawl_offset for why the CELL
## never changes) and its own BODY plays one of four real animations (see
## _worm_texture_for, docs/concept/soil_fauna.md "Illustrated worm
## sprite"). Cheap by construction: one sine pair, one texture lookup and
## one assignment per visible worm, no allocation and no queries.
##
## A corpse (see EarthwormPatch.is_corpse) does not crawl -- it lies
## exactly where it died, so it skips the positional wobble entirely and
## only its texture (the die row, advancing then holding) is kept current.
func _crawl_worm_sprites() -> void:
	for chunk_coord in _worm_sprites:
		var origin: Vector2i = chunk_coord * CHUNK_SIZE
		var sprites: Dictionary = _worm_sprites[chunk_coord]
		var patch: EarthwormPatch = _worm_patches.get(chunk_coord)
		if patch == null:
			continue
		for cell in sprites.keys().duplicate():
			# This runs every step_worms call, far more often than
			# _sync_worm_sprites reconciles the dict -- a corpse picked up
			# via WormMarker.pick_up frees itself immediately, so a stale
			# entry can sit here for up to WORM_REFRESH_INTERVAL before the
			# next sync would otherwise catch it. See _sync_worm_sprites'
			# own matching guard for the full reasoning.
			if not is_instance_valid(sprites[cell]):
				sprites.erase(cell)
				continue
			if not patch.is_corpse(cell):
				var base := Vector2(
					(origin.x + cell.x + 0.5) * TerrainRenderer.TILE_SIZE,
					(origin.y + cell.y + 0.5) * TerrainRenderer.TILE_SIZE
				)
				sprites[cell].position = base + EarthwormPatch.crawl_offset(
					hash("%d_%d_crawl" % [origin.x + cell.x, origin.y + cell.y]),
					_world_age_seconds
				)
			sprites[cell].texture = _worm_texture_for(patch, cell, origin)


## Which of the four illustrated animations -- and which frame within it --
## a worm's sprite should currently show. See "Illustrated worm sprite:
## crawl, emerge, retreat, die" in docs/concept/soil_fauna.md for the full
## state-machine spec this implements.
func _worm_texture_for(patch: EarthwormPatch, cell: Vector2i, chunk_origin: Vector2i) -> ImageTexture:
	if patch.is_corpse(cell):
		var frames := _worm_sprite_generator.generate_textures("die")
		var index := int(patch.corpse_age_seconds(cell) / WORM_DEATH_FRAME_SECONDS)
		return frames[clampi(index, 0, frames.size() - 1)]

	var emergence := EarthwormPatch.emergence_for(patch.surfacing_at(cell))
	if emergence >= 1.0:
		var frames := _worm_sprite_generator.generate_textures("crawl")
		# Per-worm phase so a lawn full of worms doesn't crawl in lockstep --
		# the identical hash seed crawl_offset's own wobble already uses for
		# this cell, reused rather than a second one.
		var phase: int = hash("%d_%d_crawl" % [chunk_origin.x + cell.x, chunk_origin.y + cell.y])
		var index := int(_world_age_seconds / WORM_CRAWL_FRAME_SECONDS) + phase
		return frames[posmod(index, frames.size())]

	if patch.is_rising(cell):
		var frames := _worm_sprite_generator.generate_textures("emerge")
		return frames[clampi(int(emergence * frames.size()), 0, frames.size() - 1)]

	# Falling: retreat's own art is drawn in the "going in" direction (frame
	# 0 fully out, frame 7 nearly gone), the opposite mapping from emerge --
	# see "Direction, not just amount" in docs/concept/soil_fauna.md.
	var frames := _worm_sprite_generator.generate_textures("retreat")
	return frames[clampi(int((1.0 - emergence) * frames.size()), 0, frames.size() - 1)]


## Adds/removes a Sprite2D per SURFACED-or-CORPSED worm so what is rendered
## matches the chunk's EarthwormPatch. A corpse's sprite survives the diff
## that would otherwise free it the instant is_surfaced goes false --
## crush_worm_at zeroes surfacing on the very call that also forces this
## sync, so without the is_corpse check a crushed worm's sprite would be
## deleted before the die animation ever had a chance to show a single
## frame (see "A corpse is new ground" in docs/concept/soil_fauna.md).
## Otherwise the same diff-against-the-sim shape as _sync_flower_sprites.
func _sync_worm_sprites(chunk_coord: Vector2i) -> void:
	if not _decorates(chunk_coord):
		_drop_decoration(_worm_sprites, chunk_coord)
		return
	var patch: EarthwormPatch = _worm_patches.get(chunk_coord)
	var sprites: Dictionary = _worm_sprites.get(chunk_coord, {})
	if patch == null:
		return

	var origin := chunk_coord * CHUNK_SIZE
	for cell in sprites.keys().duplicate():
		# A corpse's marker can now free ITSELF, from WormMarker.pick_up --
		# something no sprite here could ever do to itself before pickup
		# existed. A stale entry left behind by that must be dropped before
		# anything below touches it (mirrors crush_ants_near's own
		# is_instance_valid guard, same reasoning: whatever freed it already
		# won -- this loop just needs to not crash on the leftover record).
		if not is_instance_valid(sprites[cell]):
			sprites.erase(cell)
			continue
		if not patch.is_surfaced(cell) and not patch.is_corpse(cell):
			sprites[cell].free()
			sprites.erase(cell)
		elif patch.is_corpse(cell):
			# Refreshed HERE, not left for the next _crawl_worm_sprites
			# frame: crush_worm_at forces this exact sync so the player
			# never sees a stale (still-alive-looking) worm for even one
			# frame after the step that killed it, the same reasoning
			# take_worm_at's own immediate re-sync already established --
			# a corpse that keeps the frame it had the instant BEFORE it
			# died would undermine that by one frame every time.
			sprites[cell].texture = _worm_texture_for(patch, cell, origin)

	for cell in patch.worm_cells():
		if not patch.is_surfaced(cell) or sprites.has(cell):
			continue
		# WormMarker, not a bare Sprite2D: a corpse's OWN sprite is what the
		# player ends up picking up (see WormMarker.pick_up) -- it is never
		# recreated between here and corpse state, so it must already be the
		# pickable class from the moment a worm first surfaces.
		var sprite := WormMarker.new()
		sprite.cell = cell
		sprite.worm_world = patch
		sprite.texture = _worm_texture_for(patch, cell, origin)
		# World scale from a world-space constant, never re-derived from the
		# art canvas -- raising SIZE for detail must not change how big a worm
		# looks (a trap this project has hit twice).
		sprite.scale = Vector2.ONE * _worm_sprite_generator.world_scale()
		# Anchored at the worm's own footprint like flowers are, rather than
		# sorting from its middle (not for Y-sorting -- ground decor never
		# Y-sorts, see _ground_decor_parent's own doc comment).
		sprite.offset.y = -float(IllustratedWormSprite.CANVAS_SIZE.y) * 0.5
		sprite.position = Vector2(
			(origin.x + cell.x + 0.5) * TerrainRenderer.TILE_SIZE,
			(origin.y + cell.y + 0.5) * TerrainRenderer.TILE_SIZE
		)
		_ground_decor_parent.add_child(sprite)
		sprites[cell] = sprite


## Mirrors _sync_worm_sprites' own exact shape -- a real vegetation patch
## has no "surfacing" state to gate on (see AquaticVegetation's own doc
## comment: initial seeding starts every patch already mature), so the
## only diff here is has_vegetation itself, not a threshold.
func _sync_aquatic_vegetation_sprites(chunk_coord: Vector2i) -> void:
	if not _decorates(chunk_coord):
		_drop_decoration(_aquatic_vegetation_sprites, chunk_coord)
		return
	var veg: AquaticVegetation = _aquatic_vegetation.get(chunk_coord)
	var sprites: Dictionary = _aquatic_vegetation_sprites.get(chunk_coord, {})
	if veg == null:
		return

	for cell in sprites.keys().duplicate():
		if not veg.has_vegetation(cell):
			sprites[cell].free()
			sprites.erase(cell)

	var origin := chunk_coord * CHUNK_SIZE
	for cell in veg.get_patch_cells():
		if sprites.has(cell):
			continue
		var sprite := Sprite2D.new()
		sprite.texture = _aquatic_vegetation_sprite_generator.generate_texture(
			hash("%d_%d_aquatic_vegetation" % [origin.x + cell.x, origin.y + cell.y])
		)
		# World scale from a world-space constant, never re-derived from
		# the art canvas -- the same "raising SIZE for detail must not
		# change how big it looks" trap this project has already hit
		# twice (see ProceduralWormSprite's own identical doc comment).
		sprite.scale = Vector2.ONE * ProceduralAquaticVegetationSprite.world_scale()
		sprite.position = Vector2(
			(origin.x + cell.x + 0.5) * TerrainRenderer.TILE_SIZE,
			(origin.y + cell.y + 0.5) * TerrainRenderer.TILE_SIZE
		)
		_ground_decor_parent.add_child(sprite)
		sprites[cell] = sprite
	_aquatic_vegetation_sprites[chunk_coord] = sprites


## Mirrors _sync_aquatic_vegetation_sprites' own exact shape (see
## AquaticInvertebrates, docs/concept/aquatic_foraging.md's "Revised
## (2026-09-07)") -- a real invertebrate patch has no "surfacing" state to
## gate on either, the same reason vegetation's own sync doesn't.
func _sync_aquatic_invertebrate_sprites(chunk_coord: Vector2i) -> void:
	if not _decorates(chunk_coord):
		_drop_decoration(_aquatic_invertebrates_sprites, chunk_coord)
		return
	var inverts: AquaticInvertebrates = _aquatic_invertebrates.get(chunk_coord)
	var sprites: Dictionary = _aquatic_invertebrates_sprites.get(chunk_coord, {})
	if inverts == null:
		return

	for cell in sprites.keys().duplicate():
		if not inverts.has_invertebrates(cell):
			sprites[cell].free()
			sprites.erase(cell)

	var origin := chunk_coord * CHUNK_SIZE
	for cell in inverts.get_patch_cells():
		if sprites.has(cell):
			continue
		var sprite := Sprite2D.new()
		sprite.texture = _aquatic_invertebrates_sprite_generator.generate_texture(
			hash("%d_%d_aquatic_invertebrates" % [origin.x + cell.x, origin.y + cell.y])
		)
		# World scale from a world-space constant, never re-derived from
		# the art canvas -- the same "raising SIZE for detail must not
		# change how big it looks" trap this project has already hit
		# twice (see ProceduralWormSprite's own identical doc comment).
		sprite.scale = Vector2.ONE * ProceduralAquaticInvertebrateSprite.world_scale()
		sprite.position = Vector2(
			(origin.x + cell.x + 0.5) * TerrainRenderer.TILE_SIZE,
			(origin.y + cell.y + 0.5) * TerrainRenderer.TILE_SIZE
		)
		_ground_decor_parent.add_child(sprite)
		sprites[cell] = sprite
	_aquatic_invertebrates_sprites[chunk_coord] = sprites


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


## Refreshes creature, fish AND ambient-flyer-bird markers to match the
## ecosystem's current aggregate populations -- a fished-down or recovering
## water chunk visibly shows fewer/more fish on the next periodic refresh,
## not just on reload; same now for a chunk whose sparrow/robin population
## has moved since it was spawned in.
func _refresh_creatures() -> void:
	for chunk_coord in _loaded_chunks.keys():
		_reconcile_chunk_creatures(chunk_coord)
		_reconcile_chunk_ambient_flyers(chunk_coord)

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


## Brings one chunk's robin/sparrow markers in line with their CURRENT
## aggregate populations, the ambient-flyer sibling of
## _reconcile_chunk_creatures immediately above -- see
## AmbientFlyerRenderer.reconcile_bird_markers's own doc comment for why this
## exists: sparrow's food signal (ground-seed cells) is always exactly zero
## the instant a chunk loads and only rises over real elapsed time, so
## without this, its markers could never appear for the rest of that chunk's
## loaded lifetime once the one-time load-time spawn had already run.
func _reconcile_chunk_ambient_flyers(chunk_coord: Vector2i) -> void:
	var chunk: Chunk = _loaded_chunks[chunk_coord]
	_loaded_ambient_flyers[chunk_coord] = _ambient_flyer_renderer.reconcile_bird_markers(
		_creatures_parent,
		chunk,
		chunk_coord * CHUNK_SIZE,
		TerrainRenderer.TILE_SIZE,
		_biome_classifier.dominant_biome(chunk.biome),
		_loaded_ambient_flyers.get(chunk_coord, []),
		_ecosystem.robin_population(chunk_coord),
		_ecosystem.sparrow_population(chunk_coord),
		self,
		_ecosystem.blackbird_population(chunk_coord)
	)


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
	if is_pond_at_global(global_x, global_y):
		return true
	return generator.is_river_at_global(global_x, global_y)


## Whether a village's own dug pond stands on this tile (docs/concept/
## village_ponds.md, VillagePond). An ordinary chunk modification, like a
## rail -- the id is the only thing stored about it, which is what lets a
## pond survive a reload with no record of the fisher who dug it.
## Whether this tile is STILL water the surface paints -- a lake, a sea
## pocket, a pond, or a dry-by-elevation cell inside a gentle shore's own
## feather. The public, global-tile form of is_still_water_probe, which
## _paint_river_flow_overlay and is_water_at_global already share; exposed
## so placement can tell the two KINDS of water apart, because a rock
## standing in a stream is a feature and a rock standing on a lake is not
## (see StoneRenderer.spawn_stones).
func is_still_water_at_global(global_x: int, global_y: int) -> bool:
	if is_pond_at_global(global_x, global_y):
		return true
	return is_still_water_probe(generator.hydrology_at_global(global_x, global_y))


## How deep the dug pond on this tile is, in metres -- 0.0 where there is
## none. The pond's counterpart to river_depth_meters_at_global and
## lake_depth_meters_at_global, and asked alongside them by the player's own
## water state (Player._resolve_water_state).
##
## A flat depth, not a solved one: a dug pond is a hole somebody dug to a
## depth they chose, not a water body whose level is solved from discharge
## or a spill point. VillagePond.DEPTH_METERS is that choice.
func pond_depth_meters_at_global(global_x: int, global_y: int) -> float:
	return VillagePond.DEPTH_METERS if is_pond_at_global(global_x, global_y) else 0.0


func is_pond_at_global(global_x: int, global_y: int) -> bool:
	return VillagePond.is_pond_tile(modification_at_global(global_x, global_y))


## A tile under a baked lake's surface (docs/concept/hydrology.md) -- an
## overlay flag on land biome exactly like is_river_at_global.
func is_lake_at_global(global_x: int, global_y: int) -> bool:
	return generator.is_lake_at_global(global_x, global_y)


## How far (tiles) the ambient river-proximity layer scans outward before
## giving up on finding any river/lake at all -- see docs/concept/
## soundscape.md's "Proximity layers" gap this closes. 24 tiles is a real,
## deliberate compromise, not a precise citation: TILE_SIZE (16px) and
## GroundSlide.PX_PER_METER put it around 34 real metres, the same order
## of magnitude as CreatureCallSound.AUDIBLE_RADIUS_PX's own ~35m "nearby"
## scope for creature calls -- flowing water is a louder, more constant
## real-world sound than a bird chirp and could real-world-honestly carry
## further, but this stays consistent with the sibling system's own
## "nearby, not the whole loaded chunk radius" scope rather than
## introducing a second, unrelated distance convention.
const WATER_PROXIMITY_SCAN_RADIUS_TILES := 24

## The real tile-distance to the nearest river/lake tile, or INF if
## nothing qualifies within WATER_PROXIMITY_SCAN_RADIUS_TILES -- a raw
## geometric fact for NatureSoundscape to turn into a volume, not an audio
## decision itself (see docs/concept/creature_and_footstep_audio.md's own
## design pillar 4: world state must never depend on audio, only the other
## way around). Delegates the actual ring-scan geometry to WaterProximity
## (pure, tested against synthetic coordinates in test_water_proximity.gd
## rather than unpredictable real generated terrain).
func nearest_water_distance_tiles(global_x: int, global_y: int) -> float:
	return WaterProximity.nearest_distance_tiles(
		global_x, global_y, WATER_PROXIMITY_SCAN_RADIUS_TILES,
		func(x: int, y: int) -> bool: return is_river_at_global(x, y) or is_lake_at_global(x, y)
	)


## The water current at a tile, as {direction: Vector2 (tile-space unit
## vector pointing downstream), speed_m_s}: the river's solved current on
## a river tile, a mouth's fading plume in the still water it empties
## into, zero elsewhere. What a fish swims against (FishMarker.
## current_speed_factor) -- the same bearing and speed the flow overlay
## draws, so the fish and the strokes agree.
func river_current_at_global(global_x: int, global_y: int) -> Dictionary:
	var probe := generator.hydrology_at_global(global_x, global_y)
	var bearing_deg := 0.0
	var speed := 0.0
	if generator.is_river_at_global(global_x, global_y):
		bearing_deg = generator.nearest_river_at(global_x, global_y).course_bearing_deg
		speed = generator.river_hydraulics_at_global(global_x, global_y).velocity_m_s
	elif probe["plume_factor"] > 0.0:
		bearing_deg = probe["plume_bearing_deg"]
		speed = HydrologyField.PLUME_SPEED_M_S * probe["plume_factor"]
	if speed <= 0.0:
		return {"direction": Vector2.ZERO, "speed_m_s": 0.0}
	var radians := deg_to_rad(bearing_deg)
	return {"direction": Vector2(sin(radians), -cos(radians)), "speed_m_s": speed}


## river_current_at_global wrapped to take a world PIXEL position rather
## than a global tile -- the shape LeafLitterField.set_current_probe wants
## (see docs/concept/leaf_litter.md's "Floating on water" section), so a
## floating leaf's own current lookup mirrors FishMarker._current_at's
## identical pixel -> tile conversion exactly.
func _leaf_current_probe(pixel_position: Vector2) -> Dictionary:
	var tile_px := float(TerrainRenderer.TILE_SIZE)
	var tile := Vector2i(floori(pixel_position.x / tile_px), floori(pixel_position.y / tile_px))
	return river_current_at_global(tile.x, tile.y)


## Real metres of lake water over a tile, 0.0 off a lake. Unlike river
## depth this delegates directly: nothing a player builds ponds a lake.
func lake_depth_meters_at_global(global_x: int, global_y: int) -> float:
	return generator.lake_depth_meters_at_global(global_x, global_y)


## One byte per cell, 1 where a river or lake covers the ground -- the
## Reads is_water_at_global, NOT Chunk.blocks_ground_cover. The narrow
## is_river/is_lake mask misses everything the flow overlay paints beyond
## them -- the river bank apron, the shore feather, a dug pond, a sea
## pocket the biome array calls land -- which is the whole reason
## is_water_at_global exists ("so a house could be sited on a cell drawn
## blue"). Building placement was moved onto it and ground cover was not:
## measured at the Dreisam, 1,840 cells per loaded span are drawn as water
## without being blocked, and 474 grass patches were standing in them
## (reported live: "there are still patches of grass"). At a LAKE the two
## agree exactly, which is why this stayed invisible there.
##
## per-chunk form of the water mask, for consumers that take a
## whole flag array (TallGrass) rather than a Chunk.
## Every cell of this chunk that is drawn as WATER, as local Vector2i --
## the cells form of _ground_cover_blockers, for the sims whose blocking
## API takes a cell list rather than a mask (FlowerPatch.block_cells, which
## also clears anything already seeded there and refuses every later
## rooting and seed-fall).
## The water mask with every BUILT cell folded in -- what may not grow
## anything at all, as opposed to `_ground_cover_blockers`, which is water
## alone and stays that way because the aquatic sims use it as an
## INCLUSION filter.
##
## Reported live with two screenshots: "TherE's a shroom growing on a
## house ... should be cleared before placing" and "Also potatoes growing
## on pavement". _built_local_cells has always named exactly the ground
## nothing may grow on -- a real building piece, a laid road, a village
## farm's own rail -- and TallGrass and FlowerPatch were handed it through
## block_cells at chunk load. The sims that only ever learned about water
## were not, so a roof and a market square read as plain "grassland" to
## them. Measured on a build-then-reload: 82 mushrooms and crops seeded
## straight back onto paved ground.
func _ground_cover_and_built_blockers(
	water_blockers: PackedByteArray, built_cells: Array, width: int
) -> PackedByteArray:
	var blockers := water_blockers.duplicate()
	for cell in built_cells:
		var local: Vector2i = cell
		var index := local.y * width + local.x
		if index >= 0 and index < blockers.size():
			blockers[index] = 1
	return blockers


func _water_cells_from(blockers: PackedByteArray, width: int) -> Array:
	var cells: Array = []
	for index in blockers.size():
		if blockers[index] == 1:
			cells.append(Vector2i(index % width, index / width))
	return cells


func _ground_cover_blockers(chunk: Chunk, chunk_coord: Vector2i) -> PackedByteArray:
	var origin := chunk_coord * CHUNK_SIZE
	var blockers := PackedByteArray()
	blockers.resize(chunk.width * chunk.height)
	for index in blockers.size():
		var global_x := origin.x + index % chunk.width
		var global_y := origin.y + index / chunk.width
		blockers[index] = 1 if is_water_at_global(global_x, global_y) else 0
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
	return flow_boulder_diameter_cm_at_global(global_x, global_y) > 0.0


## The flow boulder on this tile as a rock of a real SIZE: its diameter in
## cm (the same StoneSize roll that draws it; the dropped piece and an ore
## rock at DROPPED_BOULDER_DIAMETER_CM), or 0.0 where there is no flow
## boulder at all. Everything the water does around the rock -- the push
## reach, the eyot, the shoal, the foam, the wake, and the force balance
## (river_boulder_load_at_global) -- is sized from this.
func flow_boulder_diameter_cm_at_global(global_x: int, global_y: int) -> float:
	var piece := modification_at_global(global_x, global_y)
	if piece == BOULDER_PIECE_ID:
		return DROPPED_BOULDER_DIAMETER_CM
	if BuildingPiece.has_piece(piece):
		return 0.0
	# On the river OR on its bank apron: a rock at the water's edge must
	# part the waterline around itself too ("wrap shorelines around edge
	# boulders"), not only a rock standing mid-stream.
	if not generator.is_within_river_apron(global_x, global_y):
		return 0.0
	var biome := biome_at_global(global_x, global_y)
	if not StonePlacement.STONE_BIOMES.has(biome):
		return 0.0
	if not _flow_stone_placement.has_stone_at(global_x, global_y, biome):
		return 0.0
	# An ore deposit rides the same stone roll (OrePlacement.is_ore_at) and
	# spawns a chunky minable rock -- it bends the water exactly like a
	# boulder ("ore should also bend the water").
	if _flow_ore_placement.is_ore_at(global_x, global_y, biome):
		return DROPPED_BOULDER_DIAMETER_CM
	var diameter := StoneSize.diameter_for(_flow_stone_placement.seed_at(global_x, global_y))
	if StoneSize.class_for(diameter) == StoneSize.CLASS_BOULDER:
		return diameter
	return 0.0


## The force balance on the flow boulder at this tile: the water's drag
## over the rock's friction-held submerged weight (BoulderHydraulics), from
## the reach's own solved current and its real depth (ponding included).
## Under 1 the rock holds and the water bends around it; 0 where there is
## no flow boulder.
func river_boulder_load_at_global(global_x: int, global_y: int) -> float:
	var diameter_cm := flow_boulder_diameter_cm_at_global(global_x, global_y)
	if diameter_cm <= 0.0:
		return 0.0
	var hydraulics := generator.river_hydraulics_at_global(global_x, global_y)
	var velocity: float = hydraulics.get("velocity_m_s", 0.0)
	var depth: float = river_depth_meters_at_global(global_x, global_y)
	return BoulderHydraulics.current_load(velocity, diameter_cm, depth)


## Whether the flow boulder here holds its ground against the current.
func river_boulder_holds_at_global(global_x: int, global_y: int) -> bool:
	return river_boulder_load_at_global(global_x, global_y) < 1.0


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
	var nearest := generator.nearest_river_at(global_x, global_y)
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
			var tile_nearest := generator.nearest_river_at(tile.x, tile.y)
			var across: float = absf(
				tile_nearest.signed_across_tiles / RiverCatalog.RIVER_HALF_WIDTH_TILES
			)
			if across < 0.97:
				row.append(tile)
	return row


func _row_crest_verdict(global_x: int, global_y: int) -> Dictionary:
	var verdict := {"dam_piece": false, "boulders_closed": false}
	var nearest := generator.nearest_river_at(global_x, global_y)
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
				var dam_nearest := generator.nearest_river_at(tile.x, tile.y)
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
	var tile_nearest := generator.nearest_river_at(tile.x, tile.y)
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
	var here := generator.nearest_river_at(from.x, from.y)
	if here.name == "":
		return from
	var polylines := RiverCatalog.tile_polylines(
		EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	var points: Array = polylines[here.name]
	var total := _course_length(points)
	if total <= 0.0:
		return from
	# A real tile distance along the course, expressed as the fraction of
	# the whole river that distance represents.
	var target_fraction := clampf(here.course_fraction - tiles_upstream / total, 0.0, 1.0)
	return _tile_at_course_fraction(points, target_fraction, total)


## Total length of a course polyline, in tiles -- shared by
## _course_tile_offset and _tile_at_course_fraction so the same walk is
## never paid twice for one call (measured: this ran twice per
## _course_tile_offset call, itself called up to
## DamImpoundment.MAX_BACKWATER_TILES * 2 + 1 times per _impounded_depth_at
## walk -- see that function's own doc comment on why fps at any river tile
## depended on it).
static func _course_length(points: Array) -> float:
	var total := 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	return total


## The tile sitting `fraction` of the way along a course polyline.
## `total_length`, when the caller already has it (see _course_tile_offset),
## skips re-walking the same polyline to re-derive it.
func _tile_at_course_fraction(points: Array, fraction: float, total_length: float = -1.0) -> Vector2i:
	var total := total_length if total_length >= 0.0 else _course_length(points)
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


## How close a wading player or animal has to come before nearby fish bolt
## away from it -- what "the water's edge just got scary" looks like from a
## fish's side, the same kind of alarm/flush response every other sensed
## creature in this project already has to an approaching threat (see
## FlyerPersonality.SHYEST_FLUSH_DISTANCE_M, AmbientFlyerMarker.
## SONGBIRD_FLUSH_DISTANCE_M). Real shallow-water fish (minnows, trout fry)
## show a measurable alarm response to a wading disturbance in roughly this
## same few-metre band -- one shared threshold, not an inherited trait,
## deliberately following the songbird's own precedent rather than building
## fish their own boldness system (see docs/concept/
## ecosystem_dynamics.md#a-shoal-finds-its-shape).
const FISH_WADER_FLUSH_DISTANCE_M := 2.0
const FISH_WADER_FLUSH_DISTANCE_PX := FISH_WADER_FLUSH_DISTANCE_M * GroundSlide.PX_PER_METER


## Startles every fish within FISH_WADER_FLUSH_DISTANCE_PX of any position in
## `waders` -- what a player or animal wading into the shallows looks like
## from the water's side. `waders` is expected to already be filtered to
## positions genuinely standing in water (see river_wader_positions above) --
## this method does no water-checking of its own, only distance + bolt_from,
## the same single-threat shape startle_fish_near above already has,
## generalized to several candidate threats at once (docs/concept/
## ecosystem_dynamics.md#a-shoal-finds-its-shape).
func startle_fish_near_waders(waders: PackedVector2Array) -> void:
	if waders.is_empty():
		return
	for fish_list in _loaded_fish.values():
		for fish in fish_list:
			if not is_instance_valid(fish) or not fish.has_method("bolt_from"):
				continue
			for wader in waders:
				if fish.position.distance_to(wader) <= FISH_WADER_FLUSH_DISTANCE_PX:
					fish.bolt_from(wader)
					break


## Revised (2026-09-07, see docs/concept/fishing.md's own "Revised
## (2026-09-07)" section): returns {"species": String, "mass_kg": float}
## instead of a bare species String -- {"": 0.0} sentinel (empty species,
## zero mass) for "nothing real nearby", the same shape the old empty-
## string return already used, just carrying one more real fact. Real
## per-species catch items (see ItemCatalog.make_with_mass) need the
## actual caught individual's own forage-coupled mass (FishGrowth), which
## only the live marker itself -- freed by this same call -- ever knew.
func catch_nearest_fish(pixel_position: Vector2, max_distance: float) -> Dictionary:
	var nearest: Node2D = null
	var nearest_distance := max_distance
	for fish_list in _loaded_fish.values():
		for fish in fish_list:
			var distance: float = pixel_position.distance_to(fish.position)
			if distance <= nearest_distance:
				nearest = fish
				nearest_distance = distance
	if nearest == null:
		return {"species": "", "mass_kg": 0.0}
	var species: String = nearest.species
	var mass_kg: float = nearest.mass_kg
	var chunk_coord := _chunk_coord_for_tile(_world_tile_for_pixel(nearest.position))
	for chunk_key in _loaded_fish.keys():
		_loaded_fish[chunk_key].erase(nearest)
	nearest.free()
	_ecosystem.record_catch(chunk_coord, 1.0)
	return {"species": species, "mass_kg": mass_kg}


## "Give it back" (docs/concept/capture_dsl.md's release section, answering
## its own former Open Question): a net's `free(from: bag)` effect only ever
## cleared Item.captive_species -- the individual that went in was already
## gone (Player._attempt_net_catch queue_frees a non-fish catch the moment it
## is confined), so emptying the net alone put nothing back into the world.
## This is Player._release_net's other half: a REAL, NEW individual re-enters
## the world at the release point, branching on the same two species rosters
## every other spawn path in this file already keys off
## (FishRenderer.SPECIES_POOL vs AmbientFlyerRenderer's bird/butterfly
## pools) rather than a third, invented species list.
##
## A fish goes back into water it actually fits in, or nowhere: releasing a
## goldfish onto dry land does nothing, silently, the same "no water here, no
## crash" contract fish_capacity_at's own doc comment already holds catch-up
## to. A flyer/bird has no such physical gate here (there is no "no air"
## case) -- it only refuses if this position's chunk has no ambient-flyer
## bucket loaded at all, mirroring spawn_flyer_offspring's own identical
## guard immediately above.
##
## The released individual is not the one that was caught -- it is a NEW one
## wearing the same species, warier for having just been handled
## (FlyerPersonality.boldness_after_release; see docs/concept/capture_dsl.md
## and FlyerPersonality's own doc comment for the real-world grounding). A
## fish has no personality to sour, so only the flyer branch touches it.
func release_captive(species: String, pixel_position: Vector2) -> void:
	if species.is_empty():
		return
	var chunk_coord := _chunk_coord_for_tile(_world_tile_for_pixel(pixel_position))
	if FishRenderer.SPECIES_POOL.has(species):
		if _ecosystem.fish_capacity_at(chunk_coord) <= 0.0:
			return  # dry land (or an unsurveyed region) -- nowhere to put a fish back
		var fish := _fish_renderer.spawn_fish_at(
			_entities_parent, species, pixel_position,
			hash("%d_%d_released_fish" % [int(pixel_position.x), int(pixel_position.y)])
		)
		if not _loaded_fish.has(chunk_coord):
			_loaded_fish[chunk_coord] = []
		_loaded_fish[chunk_coord].append(fish)
		# The exact inverse of record_catch above -- a released fish restores
		# the region's aggregate by one, the same population it was
		# subtracted from at the moment it was caught.
		_ecosystem.seed_fish_population(chunk_coord, _ecosystem.fish_population(chunk_coord) + 1.0)
		return
	if not _loaded_ambient_flyers.has(chunk_coord):
		return  # no flyer bucket loaded here -- nothing to add this individual to
	var seed_value := hash("%d_%d_released_flyer" % [int(pixel_position.x), int(pixel_position.y)])
	var flyer
	if AmbientFlyerRenderer.BIRD_SPECIES_POOL.has(species):
		flyer = _ambient_flyer_renderer.build_bird(_creatures_parent, species, pixel_position, seed_value)
	else:
		flyer = _ambient_flyer_renderer.build_flyer(_creatures_parent, species, pixel_position, seed_value)
	# personality() lazily rolls this individual's seed-derived boldness the
	# first time it is read (see AmbientFlyerMarker.personality) -- reading it
	# here, once, at spawn is what lets the release penalty be applied to the
	# real rolled value rather than to the middling default.
	var rolled_boldness := FlyerPersonality.boldness_of(flyer.personality())
	flyer.traits[FlyerPersonality.TRAIT_BOLDNESS] = FlyerPersonality.boldness_after_release(rolled_boldness)
	_loaded_ambient_flyers[chunk_coord].append(flyer)


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


## The real, live density at this exact global TILE -- unlike
## vegetation_density_near's own whole-chunk average, lets a caller (see
## CreaturePerception's food-sensing) tell a freshly grazed-bare cell apart
## from a lush one right next to it, both possibly the same biome. Mirrors
## biome_at_global's own exact "" -> not-loaded contract, just with -1.0
## (0.0 is itself a real, valid density) as the sentinel instead.
func vegetation_density_at_global(global_x: int, global_y: int) -> float:
	var chunk_coord := _chunk_coord_for_tile(Vector2i(global_x, global_y))
	if not _loaded_chunks.has(chunk_coord):
		return -1.0
	return _ecosystem.vegetation_density_at(chunk_coord, _local_index(global_x, global_y))


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
## `excluding` drops one marker from the search. A villager looking for
## COMPANY asks this same question from their OWN position (docs/concept/
## npc_social_life.md) and would otherwise always find themselves standing
## zero pixels away -- one lookup serves both the player's talk prompt and a
## villager's own search rather than two walks of the same chunk lists.
func nearest_npc_near(
	pixel_position: Vector2, max_distance: float, excluding: NpcMarker = null
) -> NpcMarker:
	var nearest: NpcMarker = null
	var nearest_distance := max_distance
	# Only the chunks a max_distance square can touch (FPS regression round
	# 11, see chunk_coords_within) -- not every loaded chunk's village nodes.
	for chunk_coord in chunk_coords_within(pixel_position, max_distance):
		var node_list: Array = _loaded_villages.get(chunk_coord, [])
		for node in node_list:
			if not (node is NpcMarker):
				continue
			# A villager who is home is INSIDE their house (docs/concept/
			# building.md "Residents inside"), not standing on the doorstep
			# their marker happens to rest on -- reported: "Talk" won over
			# "Enter" at a doorstep and greeted the villager through the wall.
			if node.is_at_home():
				continue
			if node == excluding:
				continue
			var distance: float = pixel_position.distance_to(node.position)
			if distance <= nearest_distance:
				nearest = node
				nearest_distance = distance
	return nearest


## The villager whose house `record` (a building_at_global/building_door_
## near record: chunk_coord, resident_seed, doorstep_global) is -- found by
## the NpcIdentity seed the record carries since place_building learned
## who lives there, or, for an older record not yet healed by its village
## reload (resident_seed 0), by whoever's home_position IS this doorstep.
## Null for a house nobody lives in (a player's own, an empty record).
func resident_marker_for(record: Dictionary) -> NpcMarker:
	var chunk_coord: Vector2i = record.get("chunk_coord", Vector2i.ZERO)
	var resident_seed: int = record.get("resident_seed", 0)
	var doorstep_global: Vector2i = record.get("doorstep_global", Vector2i.ZERO)
	var doorstep_pixel := (Vector2(doorstep_global) + Vector2(0.5, 0.5)) * TerrainRenderer.TILE_SIZE
	var by_doorstep: NpcMarker = null
	for node in _loaded_villages.get(chunk_coord, []):
		if not (node is NpcMarker) or node.identity == null:
			continue
		if resident_seed != 0 and node.identity.seed_value == resident_seed:
			return node
		if node.home_position.distance_to(doorstep_pixel) < TerrainRenderer.TILE_SIZE * 0.5:
			by_doorstep = node
	return by_doorstep


## Every OTHER villager within `max_distance` of `pixel_position` -- the
## "who else is standing here" DialogueContext's own `co_present_identities`
## source wants (see that module's doc comment), so NpcVoice/DialogueTopic's
## neighbour/contradiction topics have real people to be about rather than
## an always-empty list. Same scan as nearest_npc_near, plural and
## identity-only: a dialogue topic reads identities, never markers.
##
## `exclude` drops one marker from the result (the villager the player is
## actually talking to, so a conversation never lists its own speaker as
## their own neighbour).
func npc_identities_near(pixel_position: Vector2, max_distance: float, exclude: NpcMarker = null) -> Array:
	var identities: Array = []
	for node_list in _loaded_villages.values():
		for node in node_list:
			if not (node is NpcMarker) or node == exclude:
				continue
			if pixel_position.distance_to(node.position) <= max_distance:
				identities.append(node.identity)
	return identities


## The chunk coords a square of `radius_px` around `pixel_position` can touch
## -- the pure heart of every "nearest X within reach" scan, so a reach of a
## few tiles visits one to four chunks instead of every loaded one (FPS
## regression round 11: nearest_npc_near and nearest_liftable_stone_near
## walked all 30 loaded chunks' lists, ~4 ms per interaction-prompt refresh,
## every frame at low fps). The same min/max-chunk math trees_near and
## flyers_near already inline. Pinned by
## test_earth_chunk_manager_prompt_scans.gd.
static func chunk_coords_within(pixel_position: Vector2, radius_px: float) -> Array[Vector2i]:
	var chunk_px := float(CHUNK_SIZE) * TerrainRenderer.TILE_SIZE
	var min_chunk := Vector2i(
		floori((pixel_position.x - radius_px) / chunk_px),
		floori((pixel_position.y - radius_px) / chunk_px)
	)
	var max_chunk := Vector2i(
		floori((pixel_position.x + radius_px) / chunk_px),
		floori((pixel_position.y + radius_px) / chunk_px)
	)
	var out: Array[Vector2i] = []
	for chunk_y in range(min_chunk.y, max_chunk.y + 1):
		for chunk_x in range(min_chunk.x, max_chunk.x + 1):
			out.append(Vector2i(chunk_x, chunk_y))
	return out


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
	# Only the chunks a max_distance square can touch -- one to four for a
	# few-tile reach, not every loaded chunk's stones (FPS regression round
	# 11, see chunk_coords_within).
	for chunk_coord in chunk_coords_within(pixel_position, max_distance):
		var node_list: Array = _loaded_stones.get(chunk_coord, [])
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


## The upper-storey twin of modification_at_global -- mirrors upper_floor_
## at_global's exact shape, one layer further: the roof piece (if any) at a
## global tile. `""` for an unloaded chunk or a cell with no roof.
func roof_at_global(global_x: int, global_y: int) -> String:
	var chunk: Chunk = _loaded_chunks.get(_chunk_coord_for_tile(Vector2i(global_x, global_y)))
	if chunk == null:
		return ""
	return chunk.roof_modifications.get(_local_coord(global_x, global_y), "")


## True if a real, currently-standing tree occupies this exact tile --
## reported directly ("the NPCs / Player must first fell all trees to make
## space for the building"): a house may not be sited where a tree still
## stands, only where the ground is already genuinely clear. Mirrors
## _clear_vegetation_on_cells' own tree-to-tile reverse lookup exactly (see
## that function for why _world_tile_for_pixel is the right mapping) --
## false for an unloaded chunk, the same as every other real-tile query
## here (nothing is tracked there to find).
func tree_at_global(global_x: int, global_y: int) -> bool:
	var chunk_coord := _chunk_coord_for_tile(Vector2i(global_x, global_y))
	var target := Vector2i(global_x, global_y)
	for tree in _loaded_trees.get(chunk_coord, []):
		if is_instance_valid(tree) and _world_tile_for_pixel(tree.position) == target:
			return true
	return false


## The real, single answer to "may a house be sited on this exact tile" --
## reported directly: "houses / buildings cannot be built on river / water;
## also not in the forest... must first fell all trees to make space".
## A thin aggregator over four already-real, independently-tested
## primitives (biome_at_global, is_river_at_global, is_lake_at_global,
## tree_at_global) -- deliberately not a fifth parallel terrain model.
## "The forest" resolves to the FOREST biome specifically (matching
## SettlementGenerator's own _UNINHABITABLE_BIOMES, which a real settlement
## already avoids sitting a whole village in for the same reason) -- a
## single standing tree elsewhere is a per-cell obstacle (fell it and the
## cell opens up), not a biome-wide ban.
func is_buildable_terrain_at(global_x: int, global_y: int) -> bool:
	if not is_buildable_ground_at(global_x, global_y):
		return false
	if tree_at_global(global_x, global_y):
		return false
	return true


## The village's own siting rule (docs/concept/building.md "Village
## layout"): the ground itself, trees or not -- a village fells what stands
## on its plots and its square (place_building and a road stamp both clear
## the vegetation there), so a standing tree is never what stops a village,
## only ground that can never carry a building (water, the forest biome).
## The player's own rule stays is_buildable_terrain_at: fell the trees
## first. Found live: one tree on the 8x6 plaza square vetoed the whole
## plaza -- and with it the town hall -- in most real settlement chunks.
func is_buildable_ground_at(global_x: int, global_y: int) -> bool:
	if biome_at_global(global_x, global_y) == "forest":
		return false
	if is_pond_at_global(global_x, global_y):
		return false  # the fisher's own water is not somewhere to put a house
	if is_water_at_global(global_x, global_y):
		return false
	return true


## The one rule for "is this cell water" (docs/concept/building.md
## "Placement rules") -- exactly what the live water surface paints, no
## narrower: the ocean biome, a river tile, a river's bank apron (the
## overlay paints the whole apron as river), and still water by
## is_still_water_probe. Reported directly, with a screenshot of a stone
## house standing in a pond: is_buildable_terrain_at used to ask only
## is_river_at_global/is_lake_at_global/"ocean", while _paint_river_flow_
## overlay painted a lake's gentle shore feather, a sea pocket the biome
## array calls land, and the river banks as water too -- so a house could
## be sited on a cell drawn blue. Both now read this one function
## (test_earth_chunk_manager_buildable_terrain.gd pins it cell by cell
## against the overlay's own decision over the real Berlin radius).
func is_water_at_global(global_x: int, global_y: int) -> bool:
	# A dug pond is water the moment it is dug, and is the ONLY water the
	# generator knows nothing about -- everything below asks the generated
	# world (docs/concept/village_ponds.md, "Built water"). Answering it
	# here is what gives a pond the whole stack for free: creatures refuse
	# it, the surface paints it, and is_river_at_global above carries its
	# flow to anything that floats.
	if is_pond_at_global(global_x, global_y):
		return true
	if biome_at_global(global_x, global_y) == "ocean":
		return true
	if is_river_at_global(global_x, global_y):
		return true
	if is_still_water_probe(generator.hydrology_at_global(global_x, global_y)):
		return true
	var nearest: Dictionary = generator.nearest_river_at(global_x, global_y)
	var half_width: float = float(nearest.get("half_width_tiles", RiverCatalog.RIVER_HALF_WIDTH_TILES))
	return float(nearest.get("distance_tiles", INF)) <= half_width + RiverCatalog.RIVER_BANK_APRON_TILES


## Whether a hydrology probe (EarthChunkGenerator.hydrology_at_global) is
## STILL water the surface paints: a lake, a sea pocket, or a dry-by-
## elevation tile inside a gentle shore's own feather (lake_across below
## LAKE_PAINT_ACROSS -- see that constant). A river probe is flowing water
## and belongs to the river branch instead, never to this one. Pure, so the
## rule is pinned as data (test_earth_chunk_manager_water_reclaims.gd) and
## _paint_river_flow_overlay and is_water_at_global cannot drift apart.
static func is_still_water_probe(probe: Dictionary) -> bool:
	if probe.get("kind", "") == "river":
		return false
	return (
		probe.get("kind", "") == "lake" or bool(probe.get("sea", false))
		or float(probe.get("lake_across", INF)) < LAKE_PAINT_ACROSS
	)


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
## Whether a village farm's rail stands on this tile (docs/concept/
## village_farms.md, "The fence around the beds"). False for an unloaded
## chunk, like every other per-tile modification query here.
##
## Deliberately the same O(1) dictionary lookup modification_at_global
## already is, with the rail test owned by VillageFarm so nothing here
## re-lists the four facings. NOT what a creature asks before it steps --
## a rail is a line on one edge of this tile, not a tile an animal may not
## stand on, so movement asks fence_blocks_step_global below.
func is_fenced_at_global(global_x: int, global_y: int) -> bool:
	return VillageFarm.is_fence_tile(modification_at_global(global_x, global_y))


## Whether stepping from one global tile to the next CROSSES a rail's inner
## edge -- the one question a creature's movement asks of the world before
## it steps (CreatureMarker._fence_blocks_movement).
##
## Asked for directly, with two sides of a real ring arrowed in a
## screenshot: *"move the fences to the inner edge of the enclosure and
## treat the rest of the tile as street"*. A rail's own tile is ordinary
## walkable ground -- an animal may stand on the ring and walk along it --
## and only the edge the rails are drawn on is shut, on both sides of it
## (see VillageFarm.rails_block_step, which owns the rule).
##
## Two O(1) lookups per creature per movement decision rather than one: the
## cell it stands on and the cell it is heading for, because an EDGE is a
## fact about a pair of cells and cannot be read off either alone.
func fence_blocks_step_global(from_x: int, from_y: int, to_x: int, to_y: int) -> bool:
	return VillageFarm.rails_block_step(
		modification_at_global(from_x, from_y),
		modification_at_global(to_x, to_y),
		Vector2i(to_x - from_x, to_y - from_y)
	)


func build_at_global(global_x: int, global_y: int, tile_id: String) -> bool:
	var chunk_coord := _chunk_coord_for_tile(Vector2i(global_x, global_y))
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk == null:
		return false
	var local := _local_coord(global_x, global_y)
	var previous_tile_id: String = chunk.modifications.get(local, "")
	chunk.modifications[local] = tile_id
	if _is_built_surface(tile_id):
		_block_ground_cover_on_cells(chunk_coord, [local])
	elif _is_built_surface(previous_tile_id):
		_unblock_ground_cover_on_cells(chunk_coord, [local])
	if TerrainRenderer.is_road_tile(tile_id):
		# A laid road is cleared like a building footprint (see
		# place_building): a tree standing on a street cell is felled by
		# laying the street, rather than left growing out of the cobbles.
		_clear_vegetation_on_cells(chunk_coord, chunk, {Vector2i(global_x, global_y): true})
	_terrain_renderer.paint(_tile_map_layer, chunk, chunk_coord * CHUNK_SIZE, generator.biome_at_global)
	_sync_piece_collision(Vector2i(global_x, global_y), tile_id)
	_sync_sagewerk_lumberjack(chunk_coord, local, previous_tile_id, tile_id)
	_sync_farm_farmer(chunk_coord, local, previous_tile_id, tile_id)
	_sync_conversion_worker(chunk_coord, local, previous_tile_id, tile_id)
	_sync_logistics_workers(chunk_coord, local, previous_tile_id, tile_id)
	_sync_structure_art(chunk_coord, local, previous_tile_id, tile_id)
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
	if _is_built_surface(previous_tile_id):
		_unblock_ground_cover_on_cells(chunk_coord, [local])
	_terrain_renderer.paint(_tile_map_layer, chunk, chunk_coord * CHUNK_SIZE, generator.biome_at_global)
	_remove_piece_collision(Vector2i(global_x, global_y))
	_sync_sagewerk_lumberjack(chunk_coord, local, previous_tile_id, "")
	_sync_farm_farmer(chunk_coord, local, previous_tile_id, "")
	_sync_conversion_worker(chunk_coord, local, previous_tile_id, "")
	_sync_logistics_workers(chunk_coord, local, previous_tile_id, "")
	_sync_structure_art(chunk_coord, local, previous_tile_id, "")
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
	# The one-cell apron around the house too -- trees and stones only (the
	# ground cover may grow right up to the wall): a village clears the ground
	# around what it builds, so no tree ever stands on a doorstep (docs/
	# concept/building.md "Placement rules"; BuildingPiece.touches_piece is
	# the same rule the tree seams read so none grows back there).
	var apron := {}
	for global_cell in occupied_cells:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var neighbour: Vector2i = global_cell + Vector2i(dx, dy)
				if not occupied_cells.has(neighbour) and _chunk_coord_for_tile(neighbour) == chunk_coord:
					apron[neighbour] = true
	_clear_vegetation_on_cells(chunk_coord, chunk, apron)
	var occupied_local: Array = []
	for global_cell in occupied_cells:
		occupied_local.append(_local_coord(global_cell.x, global_cell.y))
	_block_ground_cover_on_cells(chunk_coord, occupied_local)
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


# -- whole-building entities (docs/concept/building.md "Buildings are -------
# -- entities; interiors are scenes") ----------------------------------------

## Places a real BuildingCatalog `building_id` with its footprint's
## top-left at `origin_local` (chunk-local) -- the anchor cell gets the
## building id itself in `modifications` (so has_structure_near/
## nearest_structure_position/every existing "is structure X here" scan
## keeps working with no changes), every other footprint cell gets
## BuildingCatalog.FOOTPRINT_TILE_ID, `chunk.buildings[origin_local]`
## records the rest of its state, and the node (sprite + collision) spawns
## immediately -- unlike stamp_structure_at_global's own pieces, a building
## has no "wait for the next chunk load" gap to close. False (no-op) when
## the chunk isn't loaded, `building_id` isn't real, or ANY footprint cell
## (the door and doorstep included -- see BuildingCatalog.footprint_cells/
## doorstep_of) is already occupied; a caller (VillageLayout, the player's
## own blueprint build) is expected to have validated the site already,
## this is the same defensive re-check build_at_global's own siblings all
## make. `occupation`/`resident_seed`: who lives here (docs/concept/
## building.md "Entering" -- the resident's real occupation drives the
## interior, and "Residents inside" has to find the villager whose house
## this is); NPCs are regenerated on every load and only the building
## persists, so the building itself remembers its villager. "" / 0 for a
## house nobody was placed for (a player's own, or any pre-resident save).
func place_building(
	chunk_coord: Vector2i, origin_local: Vector2i, building_id: String,
	facing: Vector2i = Vector2i(0, 1), seed_value: int = 0, owner_household_id: String = "",
	occupation: String = "", resident_seed: int = 0
) -> bool:
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk == null or not BuildingCatalog.has_building(building_id):
		return false
	var footprint_cells: Array = BuildingCatalog.footprint_cells(building_id, origin_local)
	var required_cells: Array = footprint_cells.duplicate()
	required_cells.append(origin_local + BuildingCatalog.doorstep_of(building_id))
	for local in required_cells:
		if chunk.modifications.get(local, "") != "":
			return false
		# Nothing built stands in water -- the SAME rule
		# _reclaim_pieces_standing_in_water already keeps for every wall,
		# floor and roof, kept here too. Reported live with the screenshot:
		# "Buildings are placed in rivers". Measured first
		# (tools/probe_buildings_in_water.gd): every siting path already
		# asks is_buildable_ground_at and not one of 16 real villages put a
		# building in water -- but this function had no check of its own at
		# all, so any caller that forgets is free to, and a village whose
		# river moved under it keeps the ones it has.
		var global_cell: Vector2i = chunk_coord * CHUNK_SIZE + local
		if is_water_at_global(global_cell.x, global_cell.y):
			return false
	for local in footprint_cells:
		chunk.modifications[local] = building_id if local == origin_local else BuildingCatalog.FOOTPRINT_TILE_ID
	chunk.buildings[origin_local] = {
		"id": building_id, "facing": facing, "seed": seed_value,
		"condition": 1.0, "progress": 1.0, "owner_household_id": owner_household_id,
		"occupation": occupation, "resident_seed": resident_seed,
	}
	var occupied_global := {}
	for local in footprint_cells:
		occupied_global[chunk_coord * CHUNK_SIZE + local] = true
	_clear_vegetation_on_cells(chunk_coord, chunk, occupied_global)
	_block_ground_cover_on_cells(chunk_coord, footprint_cells)
	_terrain_renderer.paint(_tile_map_layer, chunk, chunk_coord * CHUNK_SIZE, generator.biome_at_global)
	_spawn_building_node(chunk_coord, origin_local, chunk.buildings[origin_local])
	return true


## Which building id a village's store is. Kept because the growth ladder
## and the capacity rule both name it; the round that fills it is a
## carter's, not this manager's (docs/concept/village_warehouse.md,
## Mechanism 4 -- "It should be a real NPC pulling the cart, not an
## additional sprite").
const WAREHOUSE_BUILDING_ID := "warehouse"


## Writes who lives in an already-placed building (see place_building's
## own occupation/resident_seed) -- the backfill hook for a record
## persisted before those fields existed (VillageRenderer._recover_
## existing_village heals an old save's houses on their next reload), so
## it persists at once rather than waiting for the chunk to unload. False
## when nothing is placed at `origin_local`.
func set_building_resident(chunk_coord: Vector2i, origin_local: Vector2i, occupation: String, resident_seed: int) -> bool:
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk == null or not chunk.buildings.has(origin_local):
		return false
	chunk.buildings[origin_local]["occupation"] = occupation
	chunk.buildings[origin_local]["resident_seed"] = resident_seed
	_persist_modifications_now(chunk_coord, chunk)
	return true


## Furniture the player placed inside a building (docs/concept/housing.md
## "Decorating an entered interior"): the building record's own
## "interior" (local interior cell -> furniture id), persisted with the
## building -- a house keeps what you put in it. Gated by the SAME
## FurniturePlacement rule the legacy floor plan used (a real furniture
## piece, on a real floor cell, inside an enclosed room, nothing already
## there), judged against the interior template's own piece grid
## (InteriorTemplates.piece_grid for the building's family + seed -- the
## exact shape HouseInteriorView builds). Persists at once, the same way
## set_building_resident does. False, nothing written, when no building
## stands at `origin_local` or the placement is refused. A record from
## before "interior" existed simply starts empty -- no migration.
func place_interior_furniture(
	chunk_coord: Vector2i, origin_local: Vector2i, cell: Vector2i, piece_id: String
) -> bool:
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk == null or not chunk.buildings.has(origin_local):
		return false
	var record: Dictionary = chunk.buildings[origin_local]
	var family := BuildingCatalog.interior_family_of(record["id"])
	var ground_grid: Dictionary = InteriorTemplates.piece_grid(family, int(record.get("seed", 0)))
	var placed: Dictionary = record.get("interior", {})
	if not FurniturePlacement.new().can_place(piece_id, cell, ground_grid, placed):
		return false
	placed[cell] = piece_id
	record["interior"] = placed
	_persist_modifications_now(chunk_coord, chunk)
	return true


## Takes a placed piece back out of a building's interior -- the piece id
## it held (so the caller can refund it), or "" when nothing was there.
func remove_interior_furniture(chunk_coord: Vector2i, origin_local: Vector2i, cell: Vector2i) -> String:
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk == null or not chunk.buildings.has(origin_local):
		return ""
	var record: Dictionary = chunk.buildings[origin_local]
	var placed: Dictionary = record.get("interior", {})
	if not placed.has(cell):
		return ""
	var piece_id: String = placed[cell]
	placed.erase(cell)
	record["interior"] = placed
	_persist_modifications_now(chunk_coord, chunk)
	return piece_id


## Everything placed inside the building at `origin_local` (a copy -- local
## interior cell -> furniture id), {} for an unknown building or one nobody
## has furnished.
func interior_furniture_of(chunk_coord: Vector2i, origin_local: Vector2i) -> Dictionary:
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk == null or not chunk.buildings.has(origin_local):
		return {}
	return chunk.buildings[origin_local].get("interior", {}).duplicate()


## Reverses place_building: clears the anchor id and every footprint
## marker, forgets the record, unblocks ground cover, frees the node.
## False when nothing is actually placed at `origin_local`.
func remove_building(chunk_coord: Vector2i, origin_local: Vector2i) -> bool:
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk == null or not chunk.buildings.has(origin_local):
		return false
	var building_id: String = chunk.buildings[origin_local]["id"]
	var footprint_cells: Array = BuildingCatalog.footprint_cells(building_id, origin_local)
	for local in footprint_cells:
		chunk.modifications.erase(local)
	chunk.buildings.erase(origin_local)
	_unblock_ground_cover_on_cells(chunk_coord, footprint_cells)
	_terrain_renderer.paint(_tile_map_layer, chunk, chunk_coord * CHUNK_SIZE, generator.biome_at_global)
	_despawn_building_node(chunk_coord, origin_local)
	return true


## The full building record standing on `(global_x, global_y)` -- ANY
## footprint cell answers, not just the anchor -- with `chunk_coord` and
## `origin_local` merged in so a caller can act on it (remove it, compute
## its doorstep) without a second lookup. {} when no building covers that
## cell or the chunk isn't loaded.
func building_at_global(global_x: int, global_y: int) -> Dictionary:
	var chunk_coord := _chunk_coord_for_tile(Vector2i(global_x, global_y))
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk == null:
		return {}
	var local := _local_coord(global_x, global_y)
	var tile_id: String = chunk.modifications.get(local, "")
	var origin_local: Vector2i
	if BuildingCatalog.has_building(tile_id):
		origin_local = local
	elif tile_id == BuildingCatalog.FOOTPRINT_TILE_ID:
		var found = _building_origin_owning(chunk, local)
		if found == null:
			return {}
		origin_local = found
	else:
		return {}
	if not chunk.buildings.has(origin_local):
		return {}
	var record: Dictionary = chunk.buildings[origin_local].duplicate()
	record["chunk_coord"] = chunk_coord
	record["origin_local"] = origin_local
	return record


## Which recorded building's footprint actually contains a
## FOOTPRINT_TILE_ID cell -- a building's own footprint size varies, so a
## marker cell cannot derive its anchor by arithmetic alone; scanning the
## (small, real) set of buildings this chunk actually has is direct and
## needs no second index.
func _building_origin_owning(chunk: Chunk, local: Vector2i):
	for origin_local in chunk.buildings:
		var building_id: String = chunk.buildings[origin_local]["id"]
		if BuildingCatalog.footprint_cells(building_id, origin_local).has(local):
			return origin_local
	return null


## Every building placed in `chunk_coord`, each the same record shape
## building_at_global returns (chunk_coord/origin_local included). [] for
## an unloaded chunk.
func buildings_in_chunk(chunk_coord: Vector2i) -> Array:
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk == null:
		return []
	var out: Array = []
	for origin_local in chunk.buildings:
		var record: Dictionary = chunk.buildings[origin_local].duplicate()
		record["chunk_coord"] = chunk_coord
		record["origin_local"] = origin_local
		out.append(record)
	return out


## The nearest building whose DOORSTEP (not its footprint generally -- see
## docs/concept/building.md "Buildings are entities") lies within
## `radius_tiles` of `pixel_position` -- World's own "Enter" interaction
## prompt reads this, the same chunk_coords_within-bounded scan style
## nearest_structure_position/nearest_npc_near already use. {} when
## nothing qualifies; otherwise the building record plus
## "doorstep_global" (Vector2i).
func building_door_near(pixel_position: Vector2, radius_tiles: float) -> Dictionary:
	var radius_px := radius_tiles * TerrainRenderer.TILE_SIZE
	var nearest_distance := radius_px
	var nearest: Dictionary = {}
	for chunk_coord in chunk_coords_within(pixel_position, radius_px):
		var chunk: Chunk = _loaded_chunks.get(chunk_coord)
		if chunk == null:
			continue
		for origin_local in chunk.buildings:
			var record: Dictionary = chunk.buildings[origin_local]
			var doorstep_global: Vector2i = (
				chunk_coord * CHUNK_SIZE + origin_local + BuildingCatalog.doorstep_of(record["id"])
			)
			var doorstep_pixel := (
				Vector2(doorstep_global) + Vector2(0.5, 0.5)
			) * TerrainRenderer.TILE_SIZE
			var distance := pixel_position.distance_to(doorstep_pixel)
			if distance <= nearest_distance:
				nearest_distance = distance
				nearest = record.duplicate()
				nearest["chunk_coord"] = chunk_coord
				nearest["origin_local"] = origin_local
				nearest["doorstep_global"] = doorstep_global
	return nearest


## The real, already-built TerrainRenderer this manager paints the whole
## world with -- HouseInteriorView's own real need (docs/concept/
## building.md "Entering"): its interior TileMapLayer must share the
## SAME illustrated wall/floor/furniture art the rest of the world
## already uses, and atlas_coords_for_modification is an instance method,
## not static. Returning the SAME instance (not a fresh one) matters --
## TerrainRenderer.build_tile_set() caches its own bake, so a caller that
## calls .build_tile_set() on THIS instance gets the world's own
## already-built TileSet back rather than paying to rebuild one from
## scratch on every single Enter.
func terrain_renderer() -> TerrainRenderer:
	return _terrain_renderer


## The building node: a Node2D at the footprint's BOTTOM-CENTRE (so
## Y-sorting reads against the building's own base, not its geometric
## centre the way _spawn_structure_art_for's single-tile sprites do today
## -- the bug this whole-building model fixes), a Sprite2D child from the
## real sheet if BuildingCatalog.sheet_of resolves to a loadable file, else
## ProceduralBuildingPlaceholderSprite, and a StaticBody2D covering the
## whole footprint on the ground collision layer. The door itself is never
## part of the collision shape's own footprint rect being walked into --
## entry is the doorstep Enter-prompt (building_door_near), never a gap in
## the wall.
func _spawn_building_node(chunk_coord: Vector2i, origin_local: Vector2i, record: Dictionary) -> void:
	var building_id: String = record["id"]
	var footprint := BuildingCatalog.footprint_of(building_id)
	var origin_global: Vector2i = chunk_coord * CHUNK_SIZE + origin_local
	var footprint_px := Vector2(footprint) * TerrainRenderer.TILE_SIZE
	var top_left_px := Vector2(origin_global) * TerrainRenderer.TILE_SIZE
	var bottom_centre := top_left_px + Vector2(footprint_px.x * 0.5, footprint_px.y)

	var node := Node2D.new()
	node.name = "Building"
	node.position = bottom_centre

	var sprite := Sprite2D.new()
	# Which picture a FINISHED building has is BuildingCatalog's call (see
	# finished_sheet_for): a building with a real variant sheet draws its
	# own seeded variant, so a street of cottages is a street of DIFFERENT
	# cottages; everything else draws the lifecycle sheet's idle row as
	# before. A missing file falls through to the placeholder either way,
	# so a variant sheet that has not been dropped in yet changes nothing.
	var seed_value := int(record["seed"])
	# ART_TILE_SIZE, not TILE_SIZE, and scaled back by SPRITE_SCALE (see
	# docs/concept/art_resolution.md): the WORLD footprint is identical
	# either way, but the art carries DETAIL_MULTIPLIER pixels per world
	# unit -- the same detail per world unit the ground it stands on
	# already paints at. Drawn at TILE_SIZE, a building carried HALF the
	# resolution of its own terrain, which is exactly what a finely drawn
	# variant sheet would be thrown away at.
	# Best art first, falling back down the chain: a house's own lifecycle
	# variation (which is the same house it rose as), then the flat
	# 25-cottage variant sheet, then the old 8x5 sheet's idle row. Art that
	# has been declared but not dropped in yet simply does not stop the
	# chain, so nothing ever regresses to a box for want of one file.
	var texture := _first_texture_of(
		BuildingCatalog.finished_sheet_chain(building_id, seed_value), footprint.x
	)
	if texture == null:
		texture = _building_placeholder_sprite.footprint_texture(
			footprint, seed_value, TerrainRenderer.ART_TILE_SIZE
		)
	sprite.texture = texture
	sprite.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE
	sprite.position = Vector2(0, -float(texture.get_height()) * 0.5 * ArtResolution.SPRITE_SCALE)
	node.add_child(sprite)

	var body := StaticBody2D.new()
	body.name = "BuildingCollision"
	body.collision_layer = GROUND_FLOOR_COLLISION_LAYER
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = footprint_px
	shape.shape = rect
	shape.position = Vector2(0, -footprint_px.y * 0.5)
	body.add_child(shape)
	node.add_child(body)

	_entities_parent.add_child(node)
	if not _building_nodes.has(chunk_coord):
		_building_nodes[chunk_coord] = {}
	_building_nodes[chunk_coord][origin_local] = node


func _despawn_building_node(chunk_coord: Vector2i, origin_local: Vector2i) -> void:
	var by_origin: Dictionary = _building_nodes.get(chunk_coord, {})
	var node: Node = by_origin.get(origin_local)
	if node == null:
		return
	node.free()
	by_origin.erase(origin_local)


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
## The floor of a real building piece grows nothing (docs/concept/building.md
## "Placement rules"; reported directly: "grass must be cut before and can't
## grow back inside a house"): every ground-cover sim of the chunk -- tall
## grass, flowers, desert scrub, tundra lichen -- blocks these local cells
## (TallGrass.block_cells and its twins: whatever stands there is cleared,
## and nothing plants, spreads or roots there again), and their sprites are
## re-synced so the cleared growth disappears in the same frame the
## structure appears. Trees have their own three seams already (see
## _clear_vegetation_on_cells); this is the same rule for the ground cover.
func _block_ground_cover_on_cells(chunk_coord: Vector2i, local_cells: Array) -> void:
	if local_cells.is_empty():
		return
	for sims in [_grass_sims, _flower_patches, _scrub_sims, _lichen_sims]:
		var sim = sims.get(chunk_coord)
		if sim != null:
			sim.block_cells(local_cells)
	_resync_ground_cover_sprites(chunk_coord)


## The reverse, for a destroyed piece: bare ground again, open to the next
## seed like any other cell.
func _unblock_ground_cover_on_cells(chunk_coord: Vector2i, local_cells: Array) -> void:
	for sims in [_grass_sims, _flower_patches, _scrub_sims, _lichen_sims]:
		var sim = sims.get(chunk_coord)
		if sim != null:
			sim.unblock_cells(local_cells)


func _resync_ground_cover_sprites(chunk_coord: Vector2i) -> void:
	if _grass_sims.has(chunk_coord):
		_sync_grass_sprites(chunk_coord)
	if _flower_patches.has(chunk_coord):
		_sync_flower_sprites(chunk_coord)
	if _scrub_sims.has(chunk_coord):
		_sync_scrub_sprites(chunk_coord)
	if _lichen_sims.has(chunk_coord):
		_sync_lichen_sprites(chunk_coord)


## Every local cell of `chunk` a real building piece stands on -- what a
## fresh ground-cover sim blocks on load, so a persisted house is never
## briefly full of grass.
func _built_local_cells(chunk: Chunk) -> Array:
	var cells: Array = []
	for local in chunk.modifications:
		var tile_id: String = chunk.modifications[local]
		if _is_built_surface(tile_id) or BuildingCatalog.occupies(tile_id):
			cells.append(local)
	return cells


## A cell nothing grows on: a real building piece, a laid road (docs/
## concept/infrastructure.md's Road tier -- a placed surface, unlike the
## worn path/trail tiers, which stay open ground), or a village farm's own
## rail. The one predicate build_at_global/destroy_at_global/
## _built_local_cells share for ground cover; buildings
## (BuildingCatalog.occupies) are checked alongside it where footprints
## matter.
##
## The rails are here because of a direct report: *"the grass should be
## cleared on the fence tiles as well"*. A frame was being raised straight
## through standing long grass, so a fence line read as a row of posts lost
## in a meadow -- the same thing tilling a bed already fixes for the ground
## inside the frame (see till_and_plant_farm_plot_at_global). Unlike a bed,
## a rail gives its ground back when it is pulled out: destroy_at_global
## shares this predicate, so a torn-out fence line is ordinary ground again
## rather than a permanent scar.
func _is_built_surface(tile_id: String) -> bool:
	return (
		BuildingPiece.has_piece(tile_id)
		or TerrainRenderer.is_road_tile(tile_id)
		or VillageFarm.is_fence_tile(tile_id)
	)


## Fells whatever is standing on these GLOBAL cells -- trees, boulders and
## ore veins alike (docs/concept/village_farms.md, "A farmstead clears its
## own ground").
##
## The public door onto _clear_vegetation_on_cells, which every real
## placement path already goes through for the cells it writes
## (place_building, build_at_global). A farmstead's BEDS are not written
## tiles, so nothing ever cleared them, and a farmer tilling one can clear
## the ground cover but has no axe -- reported in play with the fence in
## shot: *"the Farmhouse should clear trees in its bed enclosure"*.
##
## Grouped by chunk so a field spanning two of them is one sweep each rather
## than one per cell, and silent about cells in chunks that are not loaded:
## a village only ever clears ground it is standing on.
##
## Nothing is credited for the timber. A village clearing its own founding
## site is scene setting, not a harvest -- exactly as it already is for a
## house's footprint.
func clear_vegetation_at_global(cells: Array) -> void:
	if cells.is_empty():
		return
	var by_chunk: Dictionary = {}
	for cell in cells:
		var global_cell: Vector2i = cell
		var chunk_coord := _chunk_coord_for_tile(global_cell)
		if not by_chunk.has(chunk_coord):
			by_chunk[chunk_coord] = {}
		by_chunk[chunk_coord][global_cell] = true
	for chunk_coord in by_chunk:
		var chunk: Chunk = _loaded_chunks.get(chunk_coord)
		if chunk == null:
			continue
		_clear_vegetation_on_cells(chunk_coord, chunk, by_chunk[chunk_coord])


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
## Whether a real building piece on this tile stops something walking onto
## it -- a wall or a window, but never a door or a floor.
##
## The SAME question _sync_piece_collision asks before it spawns the tile's
## StaticBody2D, from the same two BuildingPiece facts, so what stops the
## PLAYER (physics) and what stops an NPC or an animal (this query) can
## never disagree about a given piece.
##
## It exists because a marker is a Sprite2D that moves by setting
## `position`: no collision body in the world has ever had the slightest
## effect on one, so the walls a player cannot pass were walked straight
## through by every animal in the village. Reported live: "Horses still
## aren't blocked by houses".
func piece_blocks_movement_at_global(global_x: int, global_y: int) -> bool:
	var tile_id := modification_at_global(global_x, global_y)
	return BuildingPiece.has_piece(tile_id) and not BuildingPiece.is_walkable(tile_id)


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
	body.collision_layer = GROUND_FLOOR_COLLISION_LAYER
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


## The upper-storey twin of _sync_piece_collision, one layer up -- see
## UPPER_FLOOR_COLLISION_LAYER's own doc comment for why this needs its own
## physics layer rather than reusing the ground body mechanism verbatim.
func _sync_upper_piece_collision(global_cell: Vector2i, tile_id: String) -> void:
	_remove_upper_piece_collision(global_cell)
	if BuildingPiece.has_piece(tile_id) and not BuildingPiece.is_walkable(tile_id):
		_spawn_upper_piece_collision(global_cell, tile_id)


func _spawn_upper_piece_collision(global_cell: Vector2i, piece_id: String) -> void:
	var body := StaticBody2D.new()
	body.name = "UpperPieceCollision"
	body.position = Vector2(
		(global_cell.x + 0.5) * TerrainRenderer.TILE_SIZE, (global_cell.y + 0.5) * TerrainRenderer.TILE_SIZE
	)
	body.collision_layer = UPPER_FLOOR_COLLISION_LAYER
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2.ONE * TerrainRenderer.TILE_SIZE
	shape.shape = rect
	body.add_child(shape)
	_entities_parent.add_child(body)
	var chunk_coord := _chunk_coord_for_tile(global_cell)
	if not _upper_piece_collision_bodies.has(chunk_coord):
		_upper_piece_collision_bodies[chunk_coord] = {}
	_upper_piece_collision_bodies[chunk_coord][global_cell] = body


func _remove_upper_piece_collision(global_cell: Vector2i) -> void:
	var chunk_coord := _chunk_coord_for_tile(global_cell)
	var bodies: Dictionary = _upper_piece_collision_bodies.get(chunk_coord, {})
	var body: Node = bodies.get(global_cell)
	if body == null:
		return
	body.free()
	bodies.erase(global_cell)


## The upper-storey twin of build_at_global, one layer up: a Builder's own
## per-piece placement hook (see BuilderMarker.target_upper_pieces) and this
## test suite's own direct entry point, mirroring build_at_global's exact
## "write the cell, repaint, sync collision" shape. Returns false (no-op) if
## global_x/global_y isn't in a currently-loaded chunk.
func build_upper_floor_at_global(global_x: int, global_y: int, tile_id: String) -> bool:
	var chunk_coord := _chunk_coord_for_tile(Vector2i(global_x, global_y))
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk == null:
		return false
	var local := _local_coord(global_x, global_y)
	chunk.upper_floor_modifications[local] = tile_id
	_paint_upper_floor(chunk_coord, chunk, _upper_view_cells_for(chunk_coord))
	_sync_upper_piece_collision(Vector2i(global_x, global_y), tile_id)
	return true


## The roof's own per-cell twin of build_upper_floor_at_global -- a
## Builder's own roof-placement hook (see BuilderMarker.target_roof_
## pieces, docs/concept/timber_construction.md's own long-named "a hired
## house gets no roof" gap, closed here). Roof pieces are always walkable
## (BuildingPiece._PIECES' own "encloses"/"walkable" rows), so unlike
## build_at_global/build_upper_floor_at_global this never needs to sync a
## collision body. Returns false (no-op) if global_x/global_y isn't in a
## currently-loaded chunk.
func build_roof_at_global(global_x: int, global_y: int, tile_id: String) -> bool:
	var chunk_coord := _chunk_coord_for_tile(Vector2i(global_x, global_y))
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk == null:
		return false
	var local := _local_coord(global_x, global_y)
	chunk.roof_modifications[local] = tile_id
	if _roof_layer != null:
		_terrain_renderer.paint_roofs(_roof_layer, chunk, chunk_coord * CHUNK_SIZE, _hidden_cells_for(chunk_coord))
	return true


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
			var distance := _chebyshev_distance(tile_global, query_tile)
			# A whole-building entity (docs/concept/building.md) is its
			# footprint, not just its anchor cell: "near the City Hall" is
			# measured to the nearest cell of the hall, the same way a
			# player standing beside its east wall is beside it.
			if chunk.buildings.has(local_coord) and BuildingCatalog.has_building(structure_id):
				distance = _chebyshev_distance_to_footprint(
					query_tile, tile_global, BuildingCatalog.footprint_of(structure_id)
				)
			if distance <= radius:
				return true
	return false


## Chebyshev distance from `point` to the nearest cell of the rectangle
## with its top-left at `origin` and `size` cells -- zero inside it.
func _chebyshev_distance_to_footprint(point: Vector2i, origin: Vector2i, size: Vector2i) -> int:
	var nearest := Vector2i(
		clampi(point.x, origin.x, origin.x + size.x - 1), clampi(point.y, origin.y, origin.y + size.y - 1)
	)
	return _chebyshev_distance(point, nearest)


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
## The distinct BUILDING ids standing in this chunk, read straight off its
## own building records.
##
## Deliberately NOT _present_structure_ids_for_settlement_chunk below, which
## asks has_structure_near once per placeable id in the catalog -- and
## has_structure_near walks every modification of NINE chunks, which means
## every road tile, rail and wall a village has ever laid. That is affordable
## for a build decision taken occasionally. It is not affordable for every
## settlement on every step, which is where the stock ceiling runs, and it
## gets steadily worse as a world fills in and villages pave more of
## themselves. Reported live as the frame rate decaying over time.
func _standing_building_ids_in_chunk(chunk_coord: Vector2i) -> Array:
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk == null:
		return []
	var seen := {}
	for origin_local in chunk.buildings:
		var building_id: String = chunk.buildings[origin_local].get("id", "")
		if building_id != "":
			seen[building_id] = true
	return seen.keys()


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
	# Wired to the world it shapes logs for, exactly like _spawn_farmer_for
	# below -- without this, _step_production bails every frame and every
	# beam/plank is silently discarded (test_earth_chunk_manager_structure_
	# workers.gd pins it, found while building the bread chain on this
	# template).
	marker.earth = self
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


## Keeps `_farm_farmers` in sync with a modification change at `local_cell`
## (see docs/concept/npc_farm_production.md). Two independent triggers
## matter, mirroring _sync_logistics_workers' own shape: the tile itself
## becoming/stopping being a Farm (re-decide staffing for exactly this
## cell), or a wooden_fence appearing/disappearing anywhere nearby
## (re-decide staffing for EVERY known real farm tile, since any one of
## them might have just gained or lost its gating fence).
func _sync_farm_farmer(
	chunk_coord: Vector2i, local_cell: Vector2i, previous_tile_id: String, new_tile_id: String
) -> void:
	if previous_tile_id == "farm" and new_tile_id != "farm":
		_despawn_farmer_at(chunk_coord, local_cell)
	elif new_tile_id == "farm":
		_reconcile_farmer_at(chunk_coord, local_cell)
	if previous_tile_id == "wooden_fence" or new_tile_id == "wooden_fence":
		_reconcile_all_known_farmers()


## Re-decides whether the Farm at (chunk_coord, local_cell) should have a
## Farmer right now: staffed if and only if a real "wooden_fence" stands
## within FARM_FENCE_GATE_RADIUS_TILES. Safe to call redundantly (a no-op
## once already in the correct state either way), so callers don't need to
## know which trigger applies -- mirrors _resync_logistics_for_sagewerk's
## own reconcile-rather-than-blindly-spawn shape.
func _reconcile_farmer_at(chunk_coord: Vector2i, local_cell: Vector2i) -> void:
	var global_cell: Vector2i = chunk_coord * CHUNK_SIZE + local_cell
	var fenced := has_structure_near(
		global_cell.x, global_cell.y, "wooden_fence", FARM_FENCE_GATE_RADIUS_TILES
	)
	var already_staffed: bool = _farm_farmers.get(chunk_coord, {}).has(local_cell)
	if fenced and not already_staffed:
		_spawn_farmer_for(chunk_coord, local_cell)
	elif not fenced and already_staffed:
		_despawn_farmer_at(chunk_coord, local_cell)


## Re-decides staffing for EVERY real "farm" tile in every currently loaded
## chunk -- the broad resync a wooden_fence appearing/disappearing anywhere
## needs, since a farm with no Farmer yet (never fenced) must also become
## reachable, not just already-staffed ones (unlike _sync_logistics_
## workers' own "storage changed" trigger, which only ever re-pairs
## ALREADY-staffed Sägewerks).
func _reconcile_all_known_farmers() -> void:
	for chunk_coord in _loaded_chunks:
		var chunk: Chunk = _loaded_chunks[chunk_coord]
		for local_cell in chunk.modifications:
			if chunk.modifications[local_cell] == "farm":
				_reconcile_farmer_at(chunk_coord, local_cell)


## Spawns exactly one FarmerMarker for the Farm at `local_cell`, or does
## nothing if one already exists there -- "an NPC moves in", once, per
## fenced Farm instance.
func _spawn_farmer_for(chunk_coord: Vector2i, local_cell: Vector2i) -> void:
	if not _farm_farmers.has(chunk_coord):
		_farm_farmers[chunk_coord] = {}
	var by_cell: Dictionary = _farm_farmers[chunk_coord]
	if by_cell.has(local_cell):
		return
	var global_cell: Vector2i = chunk_coord * CHUNK_SIZE + local_cell
	var home := (Vector2(global_cell) + Vector2(0.5, 0.5)) * TerrainRenderer.TILE_SIZE
	var marker := FarmerMarker.new()
	marker.earth = self
	marker.home = home
	marker.position = home
	_entities_parent.add_child(marker)
	by_cell[local_cell] = marker


func _despawn_farmer_at(chunk_coord: Vector2i, local_cell: Vector2i) -> void:
	var by_cell: Dictionary = _farm_farmers.get(chunk_coord, {})
	var marker: Node = by_cell.get(local_cell)
	if marker == null:
		return
	marker.free()
	by_cell.erase(local_cell)


## Keeps `_conversion_workers` in sync with a modification change at
## `local_cell` -- _sync_sagewerk_lumberjack's exact shape, for every
## structure id in CONVERSION_WORKER_BY_STRUCTURE: a tile that just BECAME
## a mill/bakery gets its worker (never double-spawned), a tile that just
## STOPPED being one has it despawned, and a mill overwritten by a bakery
## swaps workers.
func _sync_conversion_worker(
	chunk_coord: Vector2i, local_cell: Vector2i, previous_tile_id: String, new_tile_id: String
) -> void:
	if CONVERSION_WORKER_BY_STRUCTURE.has(previous_tile_id) and new_tile_id != previous_tile_id:
		_despawn_conversion_worker_at(chunk_coord, local_cell)
	if CONVERSION_WORKER_BY_STRUCTURE.has(new_tile_id):
		_spawn_conversion_worker_for(chunk_coord, local_cell, new_tile_id)


## Spawns exactly one worker for the mill/bakery at `local_cell`, or does
## nothing if one already exists there -- wired to this world (`earth`)
## exactly like the Farmer, so what it grinds or bakes actually lands in
## the building's real StructureStock.
func _spawn_conversion_worker_for(chunk_coord: Vector2i, local_cell: Vector2i, structure_id: String) -> void:
	if not _conversion_workers.has(chunk_coord):
		_conversion_workers[chunk_coord] = {}
	var by_cell: Dictionary = _conversion_workers[chunk_coord]
	if by_cell.has(local_cell):
		return
	var global_cell: Vector2i = chunk_coord * CHUNK_SIZE + local_cell
	var home := (Vector2(global_cell) + Vector2(0.5, 0.5)) * TerrainRenderer.TILE_SIZE
	var marker = CONVERSION_WORKER_BY_STRUCTURE[structure_id].new()
	marker.earth = self
	marker.home = home
	marker.position = home
	_entities_parent.add_child(marker)
	by_cell[local_cell] = marker


func _despawn_conversion_worker_at(chunk_coord: Vector2i, local_cell: Vector2i) -> void:
	var by_cell: Dictionary = _conversion_workers.get(chunk_coord, {})
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
	if previous_tile_id == "farm" or new_tile_id == "farm":
		_resync_logistics_for_farm(chunk_coord, local_cell)
	if previous_tile_id == "storage" or new_tile_id == "storage":
		for sagewerk_chunk_coord in _sagewerk_lumberjacks:
			for sagewerk_local_cell in _sagewerk_lumberjacks[sagewerk_chunk_coord]:
				_resync_logistics_for_sagewerk(sagewerk_chunk_coord, sagewerk_local_cell)
		for farm_chunk_coord in _farm_farmers:
			for farm_local_cell in _farm_farmers[farm_chunk_coord]:
				_resync_logistics_for_farm(farm_chunk_coord, farm_local_cell)
	# A wooden_fence appearing/disappearing (re)staffs Farms without any
	# farm tile changing (see _sync_farm_farmer) -- their own Storage
	# pairing has to follow the Farmer, the same as every other trigger.
	if previous_tile_id == "wooden_fence" or new_tile_id == "wooden_fence":
		for farm_chunk_coord in _farm_farmers:
			for farm_local_cell in _farm_farmers[farm_chunk_coord]:
				_resync_logistics_for_farm(farm_chunk_coord, farm_local_cell)
	_sync_chain_legs(chunk_coord, local_cell, previous_tile_id, new_tile_id)


## The bread chain's own trigger (see CHAIN_LOGISTICS_LEGS): a tile that
## stopped being a leg source drops every leg it had, then -- for ANY
## change to a source, a destination, or the fence that staffs a Farm --
## every known source's legs are re-decided, the same broad, idempotent
## reconcile _sync_logistics_workers' own "storage changed" trigger uses.
func _sync_chain_legs(
	chunk_coord: Vector2i, local_cell: Vector2i, previous_tile_id: String, new_tile_id: String
) -> void:
	var relevant := {"wooden_fence": true}
	for leg in CHAIN_LOGISTICS_LEGS:
		relevant[leg["source"]] = true
		relevant[leg["destination"]] = true
	if not relevant.has(previous_tile_id) and not relevant.has(new_tile_id):
		return
	if previous_tile_id != new_tile_id and relevant.has(previous_tile_id):
		_despawn_chain_legs_at(chunk_coord, local_cell)
	_resync_all_chain_legs()


## Re-decides every leg of every currently-known source in every loaded
## chunk -- safe to call redundantly (a no-op for an already-correct pair).
func _resync_all_chain_legs() -> void:
	for chunk_coord in _loaded_chunks:
		var chunk: Chunk = _loaded_chunks[chunk_coord]
		for local_cell in chunk.modifications:
			var tile_id: String = chunk.modifications[local_cell]
			for leg in CHAIN_LOGISTICS_LEGS:
				if leg["source"] == tile_id:
					_resync_chain_leg_for(chunk_coord, local_cell, leg)


## Whether the leg's source at this cell has anything to give: a Farm only
## while a Farmer works it, a Mill/Bakery while its worker stands there, a
## Storage by existing at all.
func _is_chain_source_staffed(chunk_coord: Vector2i, local_cell: Vector2i, source_id: String) -> bool:
	match source_id:
		"farm":
			return _farm_farmers.get(chunk_coord, {}).has(local_cell)
		"storage":
			return true
		_:
			return _conversion_workers.get(chunk_coord, {}).has(local_cell)


## _resync_logistics_for_sagewerk's exact reconcile, for one chain leg of
## one source: one hauler per item per real destination currently within
## SAGEWERK_STORAGE_PAIR_RADIUS_TILES, a destination that dropped out of
## range (or was destroyed) losing its own haulers, an already-paired one
## left alone.
func _resync_chain_leg_for(chunk_coord: Vector2i, local_cell: Vector2i, leg: Dictionary) -> void:
	var destination_id: String = leg["destination"]
	if not _is_chain_source_staffed(chunk_coord, local_cell, leg["source"]):
		_despawn_chain_legs_at(chunk_coord, local_cell, destination_id)
		return

	var global_cell: Vector2i = chunk_coord * CHUNK_SIZE + local_cell
	var source_pixel := (Vector2(global_cell) + Vector2(0.5, 0.5)) * TerrainRenderer.TILE_SIZE
	var destinations_found: Array[Vector2] = nearby_structure_positions(
		source_pixel, destination_id, float(SAGEWERK_STORAGE_PAIR_RADIUS_TILES) * TerrainRenderer.TILE_SIZE
	)
	if destinations_found.is_empty():
		_despawn_chain_legs_at(chunk_coord, local_cell, destination_id)
		return

	var by_destination: Dictionary = (
		_chain_logistics_workers.get(chunk_coord, {}).get(local_cell, {}).get(destination_id, {})
	)
	var in_range_keys := {}
	for destination_pixel in destinations_found:
		var key := _storage_pairing_key(destination_pixel)
		in_range_keys[key] = true
		if by_destination.has(key):
			continue  # already staffed for this specific destination -- no double-spawn
		var by_item: Dictionary = {}
		for item_id in leg["items"]:
			var marker := LogisticsMarker.new()
			marker.earth = self
			marker.item_id = item_id
			marker.source_structure_id = leg["source"]
			marker.storage_structure_id = destination_id
			marker.search_radius_tiles = SAGEWERK_STORAGE_PAIR_RADIUS_TILES
			marker.position = source_pixel
			marker.preferred_storage_position = destination_pixel
			_entities_parent.add_child(marker)
			by_item[item_id] = marker
		by_destination[key] = by_item

	for key in by_destination.keys().duplicate():
		if not in_range_keys.has(key):
			for marker in by_destination[key].values():
				marker.free()
			by_destination.erase(key)

	if not _chain_logistics_workers.has(chunk_coord):
		_chain_logistics_workers[chunk_coord] = {}
	if not _chain_logistics_workers[chunk_coord].has(local_cell):
		_chain_logistics_workers[chunk_coord][local_cell] = {}
	_chain_logistics_workers[chunk_coord][local_cell][destination_id] = by_destination


## Frees the chain haulers of one source cell -- for one destination kind,
## or (destination_id "") every leg it has.
func _despawn_chain_legs_at(chunk_coord: Vector2i, local_cell: Vector2i, destination_id: String = "") -> void:
	var by_cell: Dictionary = _chain_logistics_workers.get(chunk_coord, {})
	var by_leg = by_cell.get(local_cell)
	if by_leg == null:
		return
	for leg_destination in by_leg.keys().duplicate():
		if destination_id != "" and leg_destination != destination_id:
			continue
		for by_item in by_leg[leg_destination].values():
			for marker in by_item.values():
				marker.free()
		by_leg.erase(leg_destination)
	if by_leg.is_empty():
		by_cell.erase(local_cell)


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


## Re-decides whether the Farm at (chunk_coord, local_cell) -- if one is
## actually staffed right now, per `_farm_farmers` -- should have Logistics
## workers: one full worker-pair (one per `_FARM_LOGISTICS_ITEM_IDS` entry,
## today just "wheat") per real Storage currently within
## SAGEWERK_STORAGE_PAIR_RADIUS_TILES. Mirrors _resync_logistics_for_
## sagewerk exactly (see that function's own doc comment), just against
## `_farm_farmers`/`_FARM_LOGISTICS_ITEM_IDS`/`"farm"` instead of their
## Sägewerk counterparts -- the SAME `_logistics_workers` dict holds both
## (a farm's own local_cell never collides with a sagewerk's, so they
## coexist with no key-scheme change needed).
func _resync_logistics_for_farm(chunk_coord: Vector2i, local_cell: Vector2i) -> void:
	if not _farm_farmers.get(chunk_coord, {}).has(local_cell):
		_despawn_logistics_workers_at(chunk_coord, local_cell)
		return

	var global_cell: Vector2i = chunk_coord * CHUNK_SIZE + local_cell
	var farm_pixel := (Vector2(global_cell) + Vector2(0.5, 0.5)) * TerrainRenderer.TILE_SIZE
	var storages_found: Array[Vector2] = nearby_structure_positions(
		farm_pixel, "storage", float(SAGEWERK_STORAGE_PAIR_RADIUS_TILES) * TerrainRenderer.TILE_SIZE
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
		for item_id in _FARM_LOGISTICS_ITEM_IDS:
			var marker := LogisticsMarker.new()
			marker.earth = self
			marker.item_id = item_id
			marker.source_structure_id = "farm"
			marker.storage_structure_id = "storage"
			marker.search_radius_tiles = SAGEWERK_STORAGE_PAIR_RADIUS_TILES
			marker.position = farm_pixel
			marker.preferred_storage_position = storage_pixel
			_entities_parent.add_child(marker)
			by_item[item_id] = marker
		by_storage[key] = by_item

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


## Keeps `_structure_art_sprites` in sync with a modification change at
## `local_cell` (see IllustratedStructureSprite, docs/concept/
## npc_farm_production.md): a tile that just became a real-art subject
## (farm/sagewerk/storage/wooden_fence) gets a real overlay Sprite2D
## standing on it; a tile that just stopped being one (overwritten by
## something else, or destroyed -- `new_tile_id` is "" for a destroy) has
## its overlay freed. A tile going from one non-art id to another, or
## staying the SAME art id (a redundant build_at_global call on an already-
## built tile), is a no-op either way.
func _sync_structure_art(
	chunk_coord: Vector2i, local_cell: Vector2i, previous_tile_id: String, new_tile_id: String
) -> void:
	if previous_tile_id != new_tile_id and _illustrated_structure_sprite.has_subject(previous_tile_id):
		_despawn_structure_art_at(chunk_coord, local_cell)
	if previous_tile_id != new_tile_id and _illustrated_structure_sprite.has_subject(new_tile_id):
		_spawn_structure_art_for(chunk_coord, local_cell, new_tile_id)


## Spawns exactly one real-art overlay Sprite2D for `subject` at
## `local_cell`, or does nothing if one already exists there. Sized via
## IllustratedStructureSprite.footprint_texture (width matches the tile,
## height scales by the same factor) and bottom-anchored: the sprite's own
## bottom edge sits at the tile's bottom edge, the same way any
## bottom-anchored placed-art sprite already would (see
## IllustratedArtLoader's own "footprint" anchor doc comment).
##
## Then shifted by the subject's own footprint_offset, which is zero for
## everything that stands on its whole tile and non-zero only for a farm
## rail -- a LINE on the edge facing the beds it encloses rather than a
## thing standing in the middle of its own tile (see that function, and
## docs/concept/village_farms.md, "The rail stands on the inner edge").
func _spawn_structure_art_for(chunk_coord: Vector2i, local_cell: Vector2i, subject: String) -> void:
	if not _structure_art_sprites.has(chunk_coord):
		_structure_art_sprites[chunk_coord] = {}
	var by_cell: Dictionary = _structure_art_sprites[chunk_coord]
	if by_cell.has(local_cell):
		return
	var texture := _illustrated_structure_sprite.footprint_texture(subject, TerrainRenderer.TILE_SIZE)
	if texture == null:
		return
	var global_cell: Vector2i = chunk_coord * CHUNK_SIZE + local_cell
	var tile_center := (Vector2(global_cell) + Vector2(0.5, 0.5)) * TerrainRenderer.TILE_SIZE
	var tile_bottom := tile_center.y + TerrainRenderer.TILE_SIZE * 0.5
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = (
		Vector2(tile_center.x, tile_bottom - float(texture.get_height()) * 0.5)
		+ _illustrated_structure_sprite.footprint_offset(subject, TerrainRenderer.TILE_SIZE)
	)
	_entities_parent.add_child(sprite)
	by_cell[local_cell] = sprite


func _despawn_structure_art_at(chunk_coord: Vector2i, local_cell: Vector2i) -> void:
	var by_cell: Dictionary = _structure_art_sprites.get(chunk_coord, {})
	var sprite: Node = by_cell.get(local_cell)
	if sprite == null:
		return
	sprite.free()
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


## Every lit fire's pixel-space tile center within `radius_tiles` of
## `pixel_position` -- "campfire" and "furnace" both, the two real
## fire-producing placeable structures (see ItemCatalog), so a creature's
## nose doesn't need to know there are two kinds of fire, just that
## something is burning nearby (docs/concept/olfaction.md's smoke molecule).
## `radius_tiles` matches every other olfaction range (Olfaction.
## MAX_RANGE_TILES), unlike nearby_structure_positions' own pixel-space
## `max_distance` -- converted here so a caller never has to multiply by
## TILE_SIZE itself. Reuses nearby_structure_positions' own chunk-Chebyshev-
## radius-1 scan for each structure id and concatenates the two results.
func campfires_near(pixel_position: Vector2, radius_tiles: float) -> Array[Vector2]:
	var radius_pixels := radius_tiles * TerrainRenderer.TILE_SIZE
	var found: Array[Vector2] = []
	found.append_array(nearby_structure_positions(pixel_position, "campfire", radius_pixels))
	found.append_array(nearby_structure_positions(pixel_position, "furnace", radius_pixels))
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


## Everything waiting on the shelf of the structure at (global_x, global_y),
## item_id -> count. A COPY, so a caller reading it cannot move the real
## stock by writing to what it was shown.
##
## What a porter with no named item asks (LogisticsMarker._largest_load_
## waiting_at): a village producer's shelf is not a fixed list, so a caller
## that named its goods in advance would be inventing a catalogue that
## drifts from what the buildings really hold.
func structure_stock_contents_at(global_x: int, global_y: int) -> Dictionary:
	return _structure_stocks.stock_for(_structure_stock_key(global_x, global_y)).stock.duplicate()


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


## -- a BUILDING's own stock (docs/concept/building_storage.md) --------------
##
## The same StructureStock the tile-scale economy above already uses, at a
## third scale -- which is exactly what StructureStock's own doc comment says
## it is for ("there is exactly one stock shape in this codebase"). Keyed by
## the BUILDING's own origin tile rather than whichever cell the caller
## named, so every cell of a 3x2 farmhouse answers with the same stock; a
## barn does not have six separate corners of grain.


## The key a building's stock lives under, or "" for open ground.
func _building_stock_key(global_x: int, global_y: int) -> String:
	var record := building_at_global(global_x, global_y)
	if record.is_empty():
		return ""
	var origin: Vector2i = record["chunk_coord"] * CHUNK_SIZE + record["origin_local"]
	return _structure_stock_key(origin.x, origin.y)


## `item_id`'s count in the stock of the building covering this tile. 0 for
## open ground and for a building nothing has been put into.
func building_stock_at(global_x: int, global_y: int, item_id: String) -> int:
	var key := _building_stock_key(global_x, global_y)
	return 0 if key == "" else _structure_stocks.stock_for(key).stock_of(item_id)


## Everything the building covering this tile is holding, as item_id -> int
## -- what the click-a-building readout draws as its Inventory. Empty for
## open ground.
func building_inventory_at(global_x: int, global_y: int) -> Dictionary:
	var key := _building_stock_key(global_x, global_y)
	return {} if key == "" else (_structure_stocks.stock_for(key).stock as Dictionary).duplicate()


## How much room is left in the building covering this tile, across ALL item
## ids together: a barn is full when it is full, whatever is in it.
func building_room_at(global_x: int, global_y: int) -> int:
	var record := building_at_global(global_x, global_y)
	if record.is_empty():
		return 0
	var capacity := BuildingCatalog.storage_capacity_of(String(record["id"]))
	var held := 0
	for count in building_inventory_at(global_x, global_y).values():
		held += int(count)
	return maxi(capacity - held, 0)


## Puts goods into the building covering this tile and returns HOW MANY IT
## TOOK -- what fits, never more. A partial deposit is the honest answer for
## a barn with room for three of the five you are carrying, and a full
## building taking none of it is the pressure that makes hauling matter
## (docs/concept/building_storage.md pillar 3).
func deposit_to_building_at(global_x: int, global_y: int, item_id: String, count: int) -> int:
	if count <= 0 or item_id == "":
		return 0
	var key := _building_stock_key(global_x, global_y)
	if key == "":
		return 0
	var taken := mini(count, building_room_at(global_x, global_y))
	if taken <= 0:
		return 0
	_structure_stocks.stock_for(key).add_stock(item_id, taken)
	return taken


## Takes goods out of the building covering this tile. All-or-nothing,
## mirroring StructureStock.remove_stock itself.
func withdraw_from_building_at(global_x: int, global_y: int, item_id: String, count: int) -> bool:
	var key := _building_stock_key(global_x, global_y)
	return false if key == "" else _structure_stocks.stock_for(key).remove_stock(item_id, count)


## A meal from the village's own stores (docs/concept/milling_and_
## baking.md): how far a hungry villager "walks" to eat from a Storage's or
## Bakery's own shelf -- their own village, one chunk across, not a
## specific radius invented here.
const STRUCTURE_MEAL_RADIUS_TILES := CHUNK_SIZE

## The structures whose own stock a villager may eat from: where baked
## bread ends up (see CHAIN_LOGISTICS_LEGS) -- a Bakery's shelf and any
## Storage it was hauled into.
const STRUCTURE_MEAL_SOURCE_IDS: Array[String] = ["bakery", "storage"]


## Whether the village's own stores hold a whole meal near `pixel_position`
## -- its persisted Market (where the merchant stocks and the granary/trade
## fill: the food SettlementState has always counted as the settlement's
## own, and that nobody ever ate before this), or a Bakery/Storage shelf
## within STRUCTURE_MEAL_RADIUS_TILES. NpcEconomy's duck-typed "is there a
## meal to buy" read (its subsistence wage is gated on it, so nobody
## starves next to a stocked stall or a full bakehouse just because the
## day's gathering is bare).
func has_village_meal_near(pixel_position: Vector2) -> bool:
	return _market_meal_item_near(pixel_position) != "" or _structure_meal_tile_near(pixel_position) != null


## Buys one meal from the village's stores -- the settlement's own Market
## first, then the nearest food-holding shelf: VillageMarket.buy_meal's
## exact contract against those containers -- the same flat VILLAGE_LOCAL_
## FOOD_PRICE (the merchant sells to locals at the local price; scarcity
## pricing is what the PLAYER pays at the shop), all-or-nothing (a wallet
## that cannot pay leaves everything untouched), returning the item_id
## eaten or "" if nothing was. Reported directly: "the food should be
## actually consumed and not stay at 20 cooked meat" -- this is what
## consumes it.
func buy_village_meal_near(pixel_position: Vector2, wallet) -> String:
	var market_item := _market_meal_item_near(pixel_position)
	if market_item != "":
		if not wallet.spend(VillageMarket.VILLAGE_LOCAL_FOOD_PRICE):
			return ""
		var market := _market_store.market_for(_settlement_id_at(pixel_position))
		if not market.remove_stock(market_item, 1):
			return ""
		return market_item
	var found = _structure_meal_tile_near(pixel_position)
	if found == null:
		return ""
	var tile: Vector2i = found["tile"]
	var item_id: String = found["item_id"]
	if not wallet.spend(VillageMarket.VILLAGE_LOCAL_FOOD_PRICE):
		return ""
	if not withdraw_from_structure_at(tile.x, tile.y, item_id, 1):
		return ""
	return item_id


## The settlement whose stores a villager standing at `pixel_position`
## eats from -- the chunk they are in (a settlement IS its chunk, see
## EntityRef.for_settlement).
func _settlement_id_at(pixel_position: Vector2) -> String:
	var tile := Vector2i(
		floori(pixel_position.x / TerrainRenderer.TILE_SIZE), floori(pixel_position.y / TerrainRenderer.TILE_SIZE)
	)
	return EntityRef.for_settlement(_chunk_coord_for_tile(tile))


## The first real food item with a whole unit in the settlement's own
## persisted Market, or "" -- in stock order, deterministic like
## VillageMarket.buy_meal's own pick.
func _market_meal_item_near(pixel_position: Vector2) -> String:
	var market := _market_store.market_for(_settlement_id_at(pixel_position))
	for item_id in market.stock:
		if market.stock_of(item_id) >= 1 and _item_catalog.kind_of(item_id) == "food":
			return item_id
	return ""


## {tile, item_id} of the nearest meal-holding structure, or null. Nearest
## first so a villager eats from their own street's bakehouse before the
## far end of the village's; the first food-typed item on that shelf (in
## stock order, deterministic like buy_meal's own pick).
func _structure_meal_tile_near(pixel_position: Vector2):
	var max_distance := float(STRUCTURE_MEAL_RADIUS_TILES) * TerrainRenderer.TILE_SIZE
	var best = null
	var best_distance := INF
	for structure_id in STRUCTURE_MEAL_SOURCE_IDS:
		for structure_pixel in nearby_structure_positions(pixel_position, structure_id, max_distance):
			var distance := pixel_position.distance_to(structure_pixel)
			if distance >= best_distance:
				continue
			var tile := Vector2i(
				floori(structure_pixel.x / TerrainRenderer.TILE_SIZE), floori(structure_pixel.y / TerrainRenderer.TILE_SIZE)
			)
			var stock = _structure_stocks.stock_for(_structure_stock_key(tile.x, tile.y))
			for item_id in stock.stock:
				if stock.stock[item_id] >= 1 and _item_catalog.kind_of(item_id) == "food":
					best = {"tile": tile, "item_id": item_id}
					best_distance = distance
					break
	return best


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
	chunk.furniture_modifications = _chunk_serializer.load_modifications(_furniture_modifications_path(chunk_coord))
	chunk.upper_floor_modifications = _chunk_serializer.load_modifications(_upper_floor_modifications_path(chunk_coord))
	chunk.upper_floor_furniture_modifications = _chunk_serializer.load_modifications(
		_upper_floor_furniture_modifications_path(chunk_coord)
	)
	chunk.buildings = _chunk_serializer.load_modifications(_buildings_path(chunk_coord))
	# A record persisted before place_building carried its resident (see
	# its own occupation/resident_seed) is normalised here once, so no
	# reader ever has to guard against a missing key -- the backfill of the
	# real values is VillageRenderer._recover_existing_village's job.
	for origin_local in chunk.buildings:
		var record: Dictionary = chunk.buildings[origin_local]
		if not record.has("occupation"):
			record["occupation"] = ""
		if not record.has("resident_seed"):
			record["resident_seed"] = 0
	chunk.planted_trees = _chunk_serializer.load_planted_trees(_planted_trees_path(chunk_coord))
	_loaded_chunks[chunk_coord] = chunk
	# Nothing built stands in water -- including what an older save persisted
	# before the water rule existed (see _reclaim_pieces_standing_in_water).
	# BEFORE the withering catch-up and every paint/collision pass below, for
	# the same reason that catch-up runs first: a piece that is gone must be
	# gone before anything paints or spawns collision for it.
	_reclaim_pieces_standing_in_water(chunk_coord, chunk)
	_reclaim_buildings_standing_in_water(chunk_coord, chunk)
	# Old-save migration (see _migrate_piece_village_to_buildings_if_stale's
	# own doc comment) -- also BEFORE the first paint/collision pass, for the
	# same reason as the two reclaim calls above: a piece about to be wiped
	# must already be gone before anything paints or spawns collision for
	# it, and spawn_village (much later in this function) needs the space
	# genuinely clear to regenerate the village as real buildings.
	_migrate_piece_village_to_buildings_if_stale(chunk_coord, chunk)
	_migrate_village_trails_to_roads(chunk)
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
	# Restores the node (sprite + collision) for every whole-building entity
	# PERSISTED from a previous session -- freshly placed buildings get
	# their node immediately inside place_building instead, the same
	# "fresh vs. restored" split _sync_piece_collision's own comment above
	# draws for pieces.
	for origin_local in chunk.buildings:
		_spawn_building_node(chunk_coord, origin_local, chunk.buildings[origin_local])
	if _roof_layer != null:
		_terrain_renderer.paint_roofs(_roof_layer, chunk, chunk_coord * CHUNK_SIZE, _hidden_cells_for(chunk_coord))
	_paint_furniture(chunk_coord, chunk)
	_paint_upper_floor(chunk_coord, chunk, _upper_view_cells_for(chunk_coord))
	_paint_upper_floor_furniture(chunk_coord, chunk, _upper_view_cells_for(chunk_coord))
	# The upper-storey twin of the ground restore loop just above, for the
	# exact same reason: a persisted upper wall/window needs its collision
	# body back too, not just its paint.
	for local_cell in _upper_floor_piece_grid_for(chunk):
		var global_cell: Vector2i = chunk_coord * CHUNK_SIZE + local_cell
		_sync_upper_piece_collision(global_cell, chunk.upper_floor_modifications[local_cell])
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
	_dispatch_cicadas(chunk_coord)

	_loaded_stones[chunk_coord] = _stone_renderer.spawn_stones(
		_entities_parent, chunk, chunk_coord * CHUNK_SIZE, TerrainRenderer.TILE_SIZE, self
	) + _stone_renderer.spawn_mountain_veins(
		_entities_parent, chunk, chunk_coord * CHUNK_SIZE, TerrainRenderer.TILE_SIZE, self
	)
	# A chunk loading two out from a standing player spawns hidden, not
	# visible until the next chunk crossing (see _sync_static_entity_visibility).
	_apply_static_visibility(chunk_coord)

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

	# Every cell a persisted building piece stands on grows nothing (docs/
	# concept/building.md "Placement rules") -- each fresh ground-cover sim
	# below blocks them before its first sprite sync, so a reloaded house is
	# never briefly full of grass.
	var built_cells := _built_local_cells(chunk)
	# ONE water mask per chunk load, reused by every ground-cover sim below.
	# It is 1024 is_water_at_global reads (see _ground_cover_blockers); six
	# sims each building their own was six times that for an identical
	# answer, on the chunk-load path this project has already spent fifteen
	# FPS rounds defending.
	var water_blockers := _ground_cover_blockers(chunk, chunk_coord)
	# Water OR built, for everything that GROWS. The aquatic sims below keep
	# water_blockers itself, since for them it is an inclusion filter.
	var growth_blockers := _ground_cover_and_built_blockers(
		water_blockers, built_cells, chunk.width
	)
	_grass_sims[chunk_coord] = TallGrass.new(
		hash("%d_%d_tall_grass" % [chunk_coord.x, chunk_coord.y]), chunk.width, chunk.height, chunk.biome,
		growth_blockers
	)
	_grass_sims[chunk_coord].block_cells(built_cells)
	_grass_sprites[chunk_coord] = {}
	_grass_sprites_turning[chunk_coord] = {}
	_sync_grass_sprites(chunk_coord)

	# Aquatic vegetation (see AquaticVegetation, docs/concept/
	# aquatic_foraging.md "Aquatic Foraging") -- only chunks that actually
	# contain water get a real sim, the same "don't allocate a sim for a
	# chunk with nothing for it to do" discipline EarthwormPatch's own
	# soil-biome gate already uses. Reuses the IDENTICAL is_river-OR-is_lake
	# mask TallGrass reads just above to keep grass OUT of the water, as an
	# INCLUSION filter instead.
	var water_mask := water_blockers
	if water_mask.has(1):
		_aquatic_vegetation[chunk_coord] = AquaticVegetation.new(
			hash("%d_%d_aquatic_vegetation" % [chunk_coord.x, chunk_coord.y]), chunk.width, chunk.height, water_mask
		)
		_aquatic_vegetation_sprites[chunk_coord] = {}
		_sync_aquatic_vegetation_sprites(chunk_coord)

		# The second real aquatic food layer (see AquaticInvertebrates,
		# docs/concept/aquatic_foraging.md's "Revised (2026-09-07)") -- same
		# water_mask, same chunk, real ponds host both plants and insect
		# life together. A different hash seed (the "aquatic_invertebrates"
		# literal instead of "aquatic_vegetation") so the two layers don't
		# seed onto the identical cells every time.
		_aquatic_invertebrates[chunk_coord] = AquaticInvertebrates.new(
			hash("%d_%d_aquatic_invertebrates" % [chunk_coord.x, chunk_coord.y]), chunk.width, chunk.height, water_mask
		)
		_aquatic_invertebrates_sprites[chunk_coord] = {}
		_sync_aquatic_invertebrate_sprites(chunk_coord)

	var crop_sims := {}
	var crop_markers := {}
	for crop_id in WILD_CROP_IDS:
		var sim := WildCropPatch.new(
			crop_id, hash("%d_%d_wild_crop" % [chunk_coord.x, chunk_coord.y]),
			chunk.width, chunk.height, chunk.biome, growth_blockers
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

	# Wild mushrooms (see docs/concept/mushrooms.md): one sim covering all 6
	# species for this chunk, already carrying whatever it seeded/was
	# already fruiting on arrival.
	var mushroom_sim := WildMushroomPatch.new(
		hash("%d_%d_mushroom" % [chunk_coord.x, chunk_coord.y]), chunk.width, chunk.height, chunk.biome,
		growth_blockers
	)
	_mushroom_sims[chunk_coord] = mushroom_sim
	_mushroom_markers[chunk_coord] = _mushroom_renderer.spawn_markers(
		_entities_parent, mushroom_sim, chunk_coord * CHUNK_SIZE, TerrainRenderer.TILE_SIZE
	)

	_decomposer_markers[chunk_coord] = _decomposer_renderer.spawn_decomposers(
		_entities_parent, _biome_classifier.dominant_biome(chunk.biome), chunk_coord * CHUNK_SIZE,
		CHUNK_SIZE, TerrainRenderer.TILE_SIZE, hash("%d_%d_decomposers" % [chunk_coord.x, chunk_coord.y])
	)
	# Gives each freshly-spawned decomposer this manager as its optional
	# `_world` (see DecomposerMarker.setup) -- the one thing it needs an
	# injected world for at all: finding chunk-specific leaf litter (see
	# docs/concept/leaf_litter.md).
	for decomposer_marker in _decomposer_markers[chunk_coord]:
		decomposer_marker.setup(self)

	# Requested live: "wire caterpillars which live on trees and on the
	# ground around them; they should also do groundforaging and eat green
	# leaves (spring, summer only)". Season is read once, at spawn time
	# (see CaterpillarRenderer's own doc comment for why that -- not a
	# continuous per-frame check -- is the right place for it).
	_caterpillar_markers[chunk_coord] = _caterpillar_renderer.spawn_caterpillars(
		_entities_parent, _biome_classifier.dominant_biome(chunk.biome), current_season(),
		chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TerrainRenderer.TILE_SIZE,
		hash("%d_%d_caterpillars" % [chunk_coord.x, chunk_coord.y])
	)
	# Gives each freshly-spawned caterpillar this manager as its optional
	# `_world` (see CaterpillarMarker.setup) -- real nearby trees
	# (trees_near) and real leaf litter (nearest_leaf_litter_near/
	# consume_leaf_litter_at), the same two ports AmbientFlyerMarker's own
	# bird idle-rest and DecomposerMarker's own leaf foraging already use.
	for caterpillar_marker in _caterpillar_markers[chunk_coord]:
		caterpillar_marker.setup(self)

	# Seasonal-behavior epic, phase 10 (docs/concept/seasonal_behavior.md):
	# a grass frog needs real water nearby, not just the right land biome --
	# see GrassFrogRenderer's own doc comment for the water-presence gate
	# (WaterAreaSurvey.interior_water_cell_count) -- and brumates through
	# winter, the same "season read once, at spawn time" shape caterpillar
	# immediately above already established.
	_grass_frog_markers[chunk_coord] = _grass_frog_renderer.spawn_grass_frogs(
		_entities_parent, chunk, _biome_classifier.dominant_biome(chunk.biome), current_season(),
		chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TerrainRenderer.TILE_SIZE,
		hash("%d_%d_grass_frogs" % [chunk_coord.x, chunk_coord.y])
	)

	# Requested live, after a screenshot of an autumn floor carpeted in
	# leaves: "what else decomposes leaves I could add into the ecosystem
	# to increase decomposition rate?" (see docs/concept/soil_fauna.md
	# "Millipedes: a dedicated autumn leaf-litter decomposer"). No season
	# read at all, unlike caterpillars just above -- a millipede spawns
	# year-round, since the entire point is being present for the autumn
	# pile a caterpillar structurally cannot touch.
	_millipede_markers[chunk_coord] = _millipede_renderer.spawn_millipedes(
		_entities_parent, _biome_classifier.dominant_biome(chunk.biome),
		chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TerrainRenderer.TILE_SIZE,
		hash("%d_%d_millipedes" % [chunk_coord.x, chunk_coord.y])
	)
	# Gives each freshly-spawned millipede this manager as its optional
	# `_world` (see MillipedeMarker.setup) -- the one thing it needs an
	# injected world for at all: finding chunk-specific leaf litter (see
	# nearest_leaf_litter_near/consume_leaf_litter_at, the same ports
	# DecomposerMarker/CaterpillarMarker already share).
	for millipede_marker in _millipede_markers[chunk_coord]:
		millipede_marker.setup(self)

	# Re-staff every Sägewerk this chunk already had persisted, before this
	# load, with a fresh Lumberjack -- "an NPC moves in" applies just as much
	# to a revisited worksite as a freshly-placed one (see
	# _spawn_lumberjack_for's own doc comment).
	for local_cell in chunk.modifications:
		if chunk.modifications[local_cell] == "sagewerk":
			_spawn_lumberjack_for(chunk_coord, local_cell)

	# Re-stage every Farm this chunk already had persisted, before this
	# load -- staffed only if a real wooden_fence is (still) within reach,
	# the same real gate a freshly-placed Farm gets (see
	# _reconcile_farmer_at).
	for local_cell in chunk.modifications:
		if chunk.modifications[local_cell] == "farm":
			_reconcile_farmer_at(chunk_coord, local_cell)

	# Re-staff every persisted Mill/Bakery (docs/concept/milling_and_
	# baking.md) -- unconditional like the Sägewerk's own respawn above.
	for local_cell in chunk.modifications:
		var tile_id: String = chunk.modifications[local_cell]
		if CONVERSION_WORKER_BY_STRUCTURE.has(tile_id):
			_spawn_conversion_worker_for(chunk_coord, local_cell, tile_id)

	# Re-spawn every real-art overlay sprite this chunk already had
	# persisted, before this load -- a revisited farm/sagewerk/storage/
	# wooden_fence looks the same as a freshly-placed one, the same
	# "re-staffing applies just as much to a revisited worksite" reasoning
	# as the Lumberjack loop just above.
	for local_cell in chunk.modifications:
		var subject: String = chunk.modifications[local_cell]
		# A whole-building entity's anchor carries the same id a legacy
		# single-tile placeable did (a City Hall raised on the plaza, see
		# _place_completed_construction_project) but draws itself through
		# its own building node -- never a second, single-tile overlay on
		# top of it.
		if _illustrated_structure_sprite.has_subject(subject) and not chunk.buildings.has(local_cell):
			_spawn_structure_art_for(chunk_coord, local_cell, subject)

	# A freshly (re)loaded chunk can bring either a Sägewerk or a Storage
	# into range of a Sägewerk that was already staffed -- re-decide every
	# currently-known Sägewerk's (and Farm's) Logistics staffing, the same
	# broad resync _sync_logistics_workers' own "storage changed" trigger
	# uses.
	for sagewerk_chunk_coord in _sagewerk_lumberjacks:
		for sagewerk_local_cell in _sagewerk_lumberjacks[sagewerk_chunk_coord]:
			_resync_logistics_for_sagewerk(sagewerk_chunk_coord, sagewerk_local_cell)
	for farm_chunk_coord in _farm_farmers:
		for farm_local_cell in _farm_farmers[farm_chunk_coord]:
			_resync_logistics_for_farm(farm_chunk_coord, farm_local_cell)
	_resync_all_chain_legs()

	# The meadow that was already here is what the wind already did (see
	# MeadowSpread). Two things it needs that a chunk seed cannot give it: the
	# chunk's WORLD origin, because founders live in world space so a meadow
	# crosses chunk lines instead of stopping dead at every seam; and the
	# PREVAILING wind, because a baked meadow is the product of a climate
	# rather than of whatever the sky happens to be doing right now.
	_flower_patches[chunk_coord] = FlowerPatch.new(
		hash("%d_%d_flowers" % [chunk_coord.x, chunk_coord.y]),
		chunk.width,
		chunk.height,
		chunk.biome,
		chunk_coord * CHUNK_SIZE,
		_weather_model.prevailing_wind_direction(PREVAILING_WIND_REGION_SEED),
		_weather_model.prevailing_wind_strength(PREVAILING_WIND_REGION_SEED)
	)
	_flower_patches[chunk_coord].block_cells(built_cells)
	# ...and every cell drawn as water. FlowerPatch already owns the right
	# API for this (block_cells clears what is there AND refuses every
	# later rooting and seed-fall); it had simply never been handed the
	# water. Reported live: bushes and flowers standing in open lake.
	_flower_patches[chunk_coord].block_cells(_water_cells_from(water_blockers, chunk.width))
	_flower_sprites[chunk_coord] = {}
	_seed_sprites[chunk_coord] = {}
	_sync_flower_sprites(chunk_coord)

	_scrub_sims[chunk_coord] = DesertScrub.new(
		hash("%d_%d_desert_scrub" % [chunk_coord.x, chunk_coord.y]), chunk.width, chunk.height, chunk.biome
	)
	_scrub_sims[chunk_coord].block_cells(built_cells)
	_scrub_sprites[chunk_coord] = {}
	_sync_scrub_sprites(chunk_coord)

	_lichen_sims[chunk_coord] = TundraLichen.new(
		hash("%d_%d_tundra_lichen" % [chunk_coord.x, chunk_coord.y]), chunk.width, chunk.height, chunk.biome
	)
	_lichen_sims[chunk_coord].block_cells(built_cells)
	_lichen_sprites[chunk_coord] = {}
	_sync_lichen_sprites(chunk_coord)

	# Earthworms in the soil (see docs/concept/soil_fauna.md). No sprites yet:
	# every worm starts underground and surfaces over the next step_worms
	# ticks according to the live weather, rather than popping onto the grass
	# the instant a chunk loads.
	_worm_patches[chunk_coord] = EarthwormPatch.new(
		hash("%d_%d_earthworms" % [chunk_coord.x, chunk_coord.y]), chunk.width, chunk.height, chunk.biome,
		growth_blockers
	)
	_worm_sprites[chunk_coord] = {}

	# Ant mounds in the soil (see docs/concept/soil_fauna.md "Ants"). Placed
	# once at chunk creation -- mound_cells() never changes for a loaded
	# chunk's lifetime, exactly like the earthworm burrows just above.
	_ant_colonies[chunk_coord] = AntColony.new(
		hash("%d_%d_ants" % [chunk_coord.x, chunk_coord.y]), chunk.width, chunk.height, chunk.biome,
		growth_blockers
	)
	# The visible counterpart: one static AntMoundMarker per mound cell, so a
	# colony is actually somewhere a player can SEE rather than a pure
	# background number (reported live: ants "should be a real gear in the
	# ecosystem"). Placed at the mound's own tile centre, the same
	# cell-to-pixel convention _forage_seed_near_mound uses for its own
	# mound_pixel -- see _spawn_ant_mound_marker, shared with colony
	# budding's own later, single new mound.
	var mound_markers: Array = []
	for mound_cell in _ant_colonies[chunk_coord].mound_cells():
		mound_markers.append(_spawn_ant_mound_marker(_ant_colonies[chunk_coord], chunk_coord, mound_cell))
	_ant_mound_markers[chunk_coord] = mound_markers

	# Honeybee hives (see docs/concept/bees.md). Placed once at chunk
	# creation like the ant mounds just above -- but see BeeColony.
	# bud_new_hive/abscond_to for why hive_cells() CAN change later over
	# this loaded chunk's own life, unlike a mound's fixed placement.
	#
	# The extra_site_check Callable is the ONLY thing standing between a
	# freshly-generated world and a free-floating hive: unlike swarming/
	# absconding/harvest-relocation (all routed through _find_bee_hive_
	# site, which already applies _has_real_hive_anchor), initial seeding
	# has no post-seed filter pass, so the real check has to be injected
	# HERE, at construction, or it never runs at all for a hive placed
	# this way (see BeeColony._seed_initial_hives's own doc comment).
	# Real trees are already spawned into _loaded_trees for this chunk by
	# this point (see TreeRenderer.spawn_trees above), so trees_near
	# (inside _has_real_hive_anchor) sees real data, not an empty chunk.
	_bee_colonies[chunk_coord] = BeeColony.new(
		hash("%d_%d_bees" % [chunk_coord.x, chunk_coord.y]), chunk.width, chunk.height, chunk.biome,
		func(local_cell: Vector2i) -> bool:
			return _has_real_hive_anchor(chunk_coord * CHUNK_SIZE + local_cell)
	)
	var hive_markers: Dictionary = {}
	for hive_cell in _bee_colonies[chunk_coord].hive_cells():
		hive_markers[hive_cell] = _spawn_bee_hive_marker(_bee_colonies[chunk_coord], chunk_coord, hive_cell)
	_bee_hive_markers[chunk_coord] = hive_markers

	# Solitary wild bee nests (see docs/concept/bees.md's own "Wild bee
	# nests") -- a separate, much lighter population from the honeybee
	# hives just above.
	_wild_bee_patches[chunk_coord] = WildBeePatch.new(
		hash("%d_%d_wild_bees" % [chunk_coord.x, chunk_coord.y]), chunk.width, chunk.height, chunk.biome
	)
	var nest_markers: Dictionary = {}
	for nest_cell in _wild_bee_patches[chunk_coord].nest_cells():
		nest_markers[nest_cell] = _spawn_wild_bee_nest_marker(_wild_bee_patches[chunk_coord], chunk_coord, nest_cell)
	_wild_bee_nest_markers[chunk_coord] = nest_markers

	# Fallen-leaf litter (see docs/concept/leaf_litter.md). Empty at
	# creation -- unlike the ant mounds/earthworm burrows above, litter is
	# never seeded up front; step_fruiting's own leaf-fall block populates it
	# over time as trees actually shed.
	_leaf_litter_fields[chunk_coord] = LeafLitterField.new()
	# Wired ONCE, here, rather than every step_leaf_litter tick the way
	# set_wind is: unlike the day's ambient wind, river_current_at_global's
	# own live hydraulics need no periodic refresh -- the SAME bound method,
	# called later, already reads whatever is current then. Set at creation
	# (not lazily on first use) so a leaf falling in this chunk's very first
	# frame -- before step_leaf_litter has run for it even once -- still
	# gets a real on-water check at add_leaf time instead of a stale "no
	# probe yet" false negative (see docs/concept/leaf_litter.md's "Floating
	# on water" section).
	_leaf_litter_fields[chunk_coord].set_current_probe(_leaf_current_probe)
	# Its visible counterpart: one MultiMeshInstance2D, empty until
	# step_leaf_litter's own fill() call gives it real leaves to draw.
	var leaf_litter_mmi := MultiMeshInstance2D.new()
	_ground_decor_parent.add_child(leaf_litter_mmi)
	_leaf_litter_mmis[chunk_coord] = leaf_litter_mmi

	# Footprint stamps (see FootstepGait/FootprintField). Empty at
	# creation, same reasoning as leaf litter just above -- populated only
	# as the player actually walks through, by record_footstep.
	_footprint_fields[chunk_coord] = FootprintField.new()
	_footprint_mmis[chunk_coord] = _footprint_renderer.build_multimeshes(_ground_decor_parent)

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
	# Before the village is read: a village recorded as founded under an
	# older, smaller roster takes the missing households in first, so what
	# spawns is the village it would be founded as today (see
	# settle_up_to_founding_roster).
	settle_up_to_founding_roster(chunk_coord)
	_loaded_villages[chunk_coord] = _village_renderer.spawn_village(
		_creatures_parent,
		chunk_coord,
		chunk_coord * CHUNK_SIZE,
		CHUNK_SIZE,
		TerrainRenderer.TILE_SIZE,
		_biome_classifier.dominant_biome(chunk.biome),
		self,
		_current_sun_elevation_deg
	)
	_loaded_ambient_flyers[chunk_coord] = _ambient_flyer_renderer.spawn_ambient_flyers(
		_creatures_parent, chunk, chunk_coord * CHUNK_SIZE, TerrainRenderer.TILE_SIZE,
		_biome_classifier.dominant_biome(chunk.biome),
		_pollinator_multiplier_for(chunk_coord),
		self,
		_ecosystem.robin_population(chunk_coord),
		_ecosystem.sparrow_population(chunk_coord),
		current_season(),
		_ecosystem.blackbird_population(chunk_coord),
		_population_density["pollinators"]
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
	_apply_civic_build_decision(chunk_coord)
	_apply_village_growth_decision(chunk_coord)

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
		"blackbird_capacity": _ecosystem.blackbird_capacity_at(chunk_coord),
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
	_ecosystem.seed_blackbird_population(chunk_coord, float(advanced.get("blackbirds", 0.0)))


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
	_advance_construction_labor(chunk_coord, elapsed)


## Advances every IN_PROGRESS project sited at `chunk_coord` by `elapsed`
## seconds of real spare-capacity labor and places whatever completes --
## the one body both the reload catch-up above and the loaded-settlement
## step (_step_settlement_construction) share.
## `seconds_per_day` is how long a builder's day is in real seconds, and the
## two callers of this one body genuinely disagree about it. The offscreen
## catch-up integrates an ABSENCE at ChunkEcologyCatchup's own deliberately
## conservative LOD rate (one in-game hour away is one day of progress); the
## LIVE settlement step is a village the player is standing in front of, and
## runs on the day the player lives in (SECONDS_PER_SIMULATED_DAY -- what
## the ecosystem step, the day/night cycle and every colony already use).
##
## Measured with the old shared rate (tools/probe_village_growth.gd): a real
## village grew from 10 households to 31 and raised TWO houses in the same
## hour, so its people lived thirty-one to twelve roofs and the growth
## ladder was a ladder nothing could climb. See docs/concept/village_growth.md's
## "What a village is saving for" for the other half of that measurement.
func _advance_construction_labor(
	chunk_coord: Vector2i, elapsed: float,
	seconds_per_day: float = REAL_SECONDS_PER_ECOLOGICAL_DAY
) -> void:
	if elapsed <= 0.0:
		return
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	var household_occupations := _household_occupations_for_settlement(settlement_id)
	var spare_capacity := SettlementSpareCapacity.for_settlement(
		household_count_for_settlement(settlement_id), household_occupations
	)
	# Productivity is not decoration (docs/concept/village_growth.md
	# mechanism 4): an unhappy village visibly BUILDS slower, which closes
	# the loop the whole system is about -- buildings raise happiness,
	# happiness raises productivity, productivity raises the rate at which
	# the next building goes up. Applied to the builder count rather than
	# to the elapsed time so the SAME scale reaches both this live step and
	# the offline catch-up that shares this body, and because labour hours
	# are floats: a scaled crew never rounds itself down to no crew at all.
	var capacity := {"builder_count": float(spare_capacity) * settlement_productivity(settlement_id)}
	for project in _construction_project_store.in_progress_projects_in_chunk(chunk_coord):
		# A whole-building project (the town hall on its civic plot, see
		# _apply_civic_build_decision) is built ON its site: while
		# something else stands on the plot the crew waits, labour neither
		# accrues nor completes into a hall with nowhere to stand.
		var is_building := BuildingCatalog.has_building(project.blueprint_id)
		if is_building and not _civic_site_is_clear(chunk_coord, project.origin, project.blueprint_id):
			continue
		var result: Dictionary = _construction_project_store.advance_project_labor(
			project.id, elapsed, capacity, _recipe_book, _household_store, seconds_per_day
		)
		if result.get("action", "") == "completed":
			_place_completed_construction_project(project)
		elif is_building:
			_sync_construction_site(chunk_coord, project)


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
	# The second source of shortfall (docs/concept/milling_and_baking.md,
	# "The emergent need"): a DECLINING settlement is short of bread -- the
	# one food it can raise by construction -- and says so in the SAME shape
	# the occupation shortfalls already use, so the decision below reasons
	# bread -> bakery -> flour -> mill -> wheat -> farm with no new code.
	var food_shortfall := SettlementFood.food_shortfall_for(
		household_ids.size(), market, SettlementFood.village_market_for(settlement_id, _loaded_villages),
		_item_catalog, _settlement_structure_stocks(settlement_id)
	)
	if not food_shortfall.is_empty():
		shortfalls.append(food_shortfall)

	# A real site, not Vector2i.ZERO: the first free, buildable, clear cell
	# spiralling out from the settlement's own centre (see _settlement_build_
	# origin_for) -- a settlement with nowhere left to build decides nothing.
	var origin = _settlement_build_origin_for(chunk_coord)
	if origin == null:
		return

	SettlementBuildDecision.decide_and_advance(
		_construction_project_store, market, chunk_coord, origin, household_ids[0],
		present_structure_ids, _recipe_book, shortfalls, spare_capacity
	)


## The village raises its town hall (docs/concept/civic_construction.md
## "Meeting Hall"; building.md "City Hall over time"): CivicBuildDecision
## on the plaza's reserved civic plot, right after the ordinary build
## decision at both of its call sites (the loaded-settlement step and the
## chunk-load catch-up), from the SAME settlement state -- households,
## spare hands, the village market (which SettlementGathering stocks with
## wood and stone over time), the structures present. No-ops for a chunk
## with no households or no plaza (a village whose square was never clear
## enough to pave has nowhere to put a hall -- honest, not forced).
func _apply_civic_build_decision(chunk_coord: Vector2i) -> void:
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	var household_ids := _households_in_settlement(settlement_id)
	if household_ids.is_empty():
		return
	var origin = _civic_plot_origin_for(chunk_coord)
	if origin == null:
		return
	var spare_capacity := SettlementSpareCapacity.for_settlement(
		household_ids.size(), _household_occupations_for_settlement(settlement_id)
	)
	CivicBuildDecision.decide_and_advance(
		_construction_project_store, _market_store.market_for(settlement_id), chunk_coord, origin, settlement_id,
		_present_structure_ids_for_settlement_chunk(chunk_coord), _recipe_book, household_ids.size(), spare_capacity
	)


## The village grows (docs/concept/village_growth.md mechanism 2): whatever
## VillageGrowth's ladder says this settlement owes itself next is queued
## as a real ConstructionProject on the settlement ledger, at a real site,
## paid for out of the village's own market by the same
## SettlementConstruction.try_start the hall already uses -- so a growth
## building rises visibly on its plot over real labour hours, never stamps
## itself into existence.
##
## Runs alongside _apply_civic_build_decision rather than replacing it: the
## hall keeps its own live decision (its plaza plot, its already_standing/
## too_small/no_spare_capacity branches, all tested), so this function
## deliberately RETURNS when the ladder names the hall rather than queuing
## a second, differently-sited project for the same building.
##
## A HOUSE is credited to the first household still waiting for one
## (VillageCensus's sorted waiting list) -- so completing it grants that
## real household its real roof through the existing property scheme.
## Everything else is a commons, owned by the settlement itself, exactly
## as CivicBuildDecision already owns the hall.
func _apply_village_growth_decision(chunk_coord: Vector2i) -> void:
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	var household_ids := _households_in_settlement(settlement_id)
	if household_ids.is_empty():
		return
	var census := _village_census_for(chunk_coord, household_ids)
	var next_building: String = VillageGrowth.next_building(
		household_ids.size(), int(census["housed_count"]),
		_present_structure_ids_for_settlement_chunk(chunk_coord)
	)
	if next_building == "" or next_building == CivicBuildDecision.CITY_HALL_BUILDING_ID:
		return  # nothing owed, or the hall -- which has its own live decision

	# The same subsistence rule every other settlement build obeys: a
	# village whose whole population works a survival occupation builds
	# nothing, however entitled to it the ladder says it is.
	var spare_capacity := SettlementSpareCapacity.for_settlement(
		household_ids.size(), _household_occupations_for_settlement(settlement_id)
	)
	if spare_capacity <= 0:
		return

	var owner_id := settlement_id
	if BuildingCatalog.BUILDING_IDS.has(next_building):
		var waiting: Array = census["unhoused_household_ids"]
		if waiting.is_empty():
			return
		owner_id = waiting[0]

	var origin = _growth_site_for(chunk_coord, next_building)
	if origin == null:
		return  # nowhere left to put it -- the village simply waits
	SettlementConstruction.try_start(
		_construction_project_store, _market_store.market_for(settlement_id),
		chunk_coord, origin, next_building, owner_id, _recipe_book
	)


## Where a growth building actually goes: the sawmill at the village's own
## timber (VillageLayout.industry_plot -- the same siting VillageRenderer
## uses at founding, so a village that lost its mill rebuilds it where a
## mill belongs), everything else on the next free frontage of the street
## (VillageLayout.next_street_plot). null when the village has nowhere left.
##
## Deterministic and deliberately NOT skipping the site of a live project,
## for exactly the reason _settlement_build_origin_for gives: a repeated
## decision lands on the same still-empty plot, finds its own earlier
## project there, and never queues a second copy somewhere else.
func _growth_site_for(chunk_coord: Vector2i, building_id: String):
	if not _loaded_chunks.has(chunk_coord):
		return null
	var is_buildable := func(cell: Vector2i) -> bool:
		var g: Vector2i = chunk_coord * CHUNK_SIZE + cell
		return is_buildable_ground_at(g.x, g.y)
	# Ground another whole-building project is already rising on counts as
	# occupied even though nothing is modified there yet -- the same
	# reservation _is_clear_settlement_site reads, from the same source, so
	# the two sitings cannot claim the same cells (see
	# _cells_reserved_by_building_projects). A project for THIS SAME
	# building is deliberately not excluded: a repeated decision must land
	# on its own earlier site and find its own project, not queue a second
	# copy somewhere else.
	var reserved := _cells_reserved_by_building_projects(chunk_coord)
	for project in _construction_project_store.active_projects_in_chunk(chunk_coord):
		if project.blueprint_id != building_id:
			continue
		for cell in BuildingCatalog.footprint_cells(building_id, project.origin):
			reserved.erase(cell)
		reserved.erase(project.origin + BuildingCatalog.doorstep_of(building_id))
	var is_occupied := func(cell: Vector2i) -> bool:
		if reserved.has(cell):
			return true
		var g: Vector2i = chunk_coord * CHUNK_SIZE + cell
		return modification_at_global(g.x, g.y) != ""
	var seed_value := VillageLayout.seed_for(chunk_coord)

	if building_id == VillageRenderer.INDUSTRY_BUILDING_ID:
		var is_forest := func(cell: Vector2i) -> bool:
			var g: Vector2i = chunk_coord * CHUNK_SIZE + cell
			return biome_at_global(g.x, g.y) == VillageRenderer.FOREST_BIOME
		var industry: Dictionary = VillageLayout.industry_plot(
			building_id, CHUNK_SIZE, seed_value, is_buildable, is_forest, is_occupied,
			_is_dry_local(chunk_coord)
		)
		return null if industry.is_empty() else industry["origin"]

	# is_paved lets the plot's own tie-back cross the paving this village
	# has ALREADY laid -- another street's row, an earlier plot's doorstep,
	# the square. Without it every junction reads as blocked ground and the
	# ladder runs out of frontage the moment the second street exists (see
	# VillageLayout._frontage_spur).
	var is_paved := func(cell: Vector2i) -> bool:
		var g: Vector2i = chunk_coord * CHUNK_SIZE + cell
		return TerrainRenderer.is_road_tile(modification_at_global(g.x, g.y))
	var plot: Dictionary = VillageLayout.next_street_plot(
		building_id, CHUNK_SIZE, seed_value, is_buildable, is_occupied,
		_is_dry_local(chunk_coord), Callable(), is_paved
	)
	return null if plot.is_empty() else plot["origin"]


## This settlement's real census (VillageCensus) -- who has a roof, how
## much spare room stands, who is waiting. Reads the buildings really
## standing in the chunk, so it is only meaningful for a LOADED one; an
## unloaded settlement reports an empty village rather than guessing, and
## every caller here already no-ops on that.
func _village_census_for(chunk_coord: Vector2i, household_ids: Array) -> Dictionary:
	return VillageCensus.of(household_ids, buildings_in_chunk(chunk_coord), _household_store)


## The square's own siting predicate (VillageLayout.plaza_x0_for): dry
## ground, and nothing else. A village's square slides clear of water
## rather than not existing, and EVERY consumer of that square -- the
## founding layout, the reload's re-paving, the civic plot, the growth
## ladder's next plot, the well/stall/gate props -- has to derive the same
## rectangle from the same input, with nothing persisted. Water is the one
## input that never changes once the world is seeded: trees get felled and
## ground gets built on, rivers do not move.
##
## One narrow caveat, deliberately accepted: is_water_at_global's OCEAN
## branch reads the chunk's own biome array and so answers "not ocean" for
## an unloaded chunk, while its river/lake/sea-probe branches are pure
## generator. A settlement whose square is ocean would fail the founding
## gate anyway (VillageRenderer.spawn_village); what this can cost is a
## slightly different square for an UNLOADED coastal settlement asked only
## for its well position.
func _is_dry_local(chunk_coord: Vector2i) -> Callable:
	return func(cell: Vector2i) -> bool:
		var g: Vector2i = chunk_coord * CHUNK_SIZE + cell
		return not is_water_at_global(g.x, g.y)


## The civic plot's LOCAL origin (VillageLayout.skeleton -- re-derived from
## the chunk's own seed, nothing persisted, so the reservation self-heals
## on every load), or null when the plaza was never laid -- the plot is
## the paved square itself, so every footprint cell must BE a road cell
## (the main street alone runs under the doorstep whether or not there is
## a plaza, so the doorstep is no proof; a village whose square was water
## or forest, its houses standing where the square would have been, has
## nowhere to put a hall) -- or the plot is no longer clear (see
## _civic_site_is_clear). Also null while the hall already stands there:
## the plot is the hall's own footprint then, and CivicBuildDecision's
## already_standing branch is what answers a second ask.
func _civic_plot_origin_for(chunk_coord: Vector2i):
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk == null:
		return null
	var plot: Dictionary = VillageLayout.skeleton(
		CHUNK_SIZE, VillageLayout.seed_for(chunk_coord), _is_dry_local(chunk_coord)
	)["civic_plot"]
	var origin_local: Vector2i = plot["origin"]
	var building_id: String = plot["building_id"]
	for local in BuildingCatalog.footprint_cells(building_id, origin_local) + [plot["doorstep"]]:
		if not TerrainRenderer.is_road_tile(chunk.modifications.get(local, "")):
			return null
	if not _civic_site_is_clear(chunk_coord, origin_local, building_id):
		return null
	return origin_local


## Whether `building_id` can rise at LOCAL `origin_local` right now: every
## footprint cell and the doorstep inside this chunk, real buildable
## terrain, and either unmodified or paved (the plaza IS paved -- a road
## cell is exactly what the plot is made of, lifted for the placement and
## the doorstep laid again after, see _place_building_over_roads).
func _civic_site_is_clear(chunk_coord: Vector2i, origin_local: Vector2i, building_id: String) -> bool:
	var cells: Array = BuildingCatalog.footprint_cells(building_id, origin_local)
	cells.append(origin_local + BuildingCatalog.doorstep_of(building_id))
	for local in cells:
		if not _house_site_cell_is_clear(chunk_coord, chunk_coord * CHUNK_SIZE + local, true):
			return false
	return true


## Where a settlement raises its next structure: the first LOCAL cell,
## spiralling outward from the chunk's own centre (where SettlementGenerator
## lays its ring of houses), that is real buildable terrain (the SAME
## is_buildable_terrain_at rule every house obeys: no water, no forest, no
## standing tree) and unmodified, with all eight of its neighbours buildable
## and unmodified too -- a lane of clear ground around every structure, so
## a Farm's own fence always has somewhere to stand and a hauler's path is
## never boxed in (a one-cell hole in a forest is not a building site).
## null when the whole chunk offers nowhere -- the decision then simply
## waits. Deterministic, and deliberately NOT skipping the site of a live
## project: a repeated decision lands on the same still-empty cell, finds
## its own earlier project there (SettlementConstruction's find_project),
## and never queues a second copy somewhere else; a placed structure
## modifies its cell, so the next link goes to the next clear site.
func _settlement_build_origin_for(chunk_coord: Vector2i):
	var centre := Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2)
	for radius in range(0, CHUNK_SIZE / 2):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue  # only the ring at this radius -- inner rings were already tried
				var local := centre + Vector2i(dx, dy)
				if _is_clear_settlement_site(chunk_coord, local):
					return local
	return null


## The site rule _settlement_build_origin_for applies to one local cell:
## inside the chunk with a one-cell margin, and -- for the cell AND all
## eight neighbours -- real buildable terrain carrying no modification.
func _is_clear_settlement_site(chunk_coord: Vector2i, local: Vector2i) -> bool:
	if local.x < 1 or local.y < 1 or local.x >= CHUNK_SIZE - 1 or local.y >= CHUNK_SIZE - 1:
		return false
	var global_cell: Vector2i = chunk_coord * CHUNK_SIZE + local
	var reserved := _cells_reserved_by_building_projects(chunk_coord)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x := global_cell.x + dx
			var y := global_cell.y + dy
			if not is_buildable_terrain_at(x, y) or modification_at_global(x, y) != "":
				return false
			# Ground a whole-building project is already RISING on is
			# unmodified until the moment it completes, so "no modification
			# here" is not the same as "free" (see _cells_reserved_by_
			# building_projects).
			if reserved.has(local + Vector2i(dx, dy)):
				return false
	return true


## Every LOCAL cell a live (PLANNED/IN_PROGRESS) whole-building project in
## this chunk has spoken for -- its footprint and its doorstep.
##
## Two siting algorithms look for UNMODIFIED ground in the same chunk:
## _settlement_build_origin_for's spiral (single-tile structures -- a farm,
## a mill, a bakery) and VillageLayout.next_street_plot (docs/concept/
## village_growth.md's growth ladder). A building project that is merely
## rising has modified NOTHING yet, so without this each would happily site
## on top of the other's plot -- and the second to complete would find its
## own site taken and silently place nothing, leaving a COMPLETE ledger
## entry with no building anywhere. Each siting sees the other's
## reservations instead.
func _cells_reserved_by_building_projects(chunk_coord: Vector2i) -> Dictionary:
	var reserved := {}
	for project in _construction_project_store.active_projects_in_chunk(chunk_coord):
		if not BuildingCatalog.has_building(project.blueprint_id):
			continue
		for cell in BuildingCatalog.footprint_cells(project.blueprint_id, project.origin):
			reserved[cell] = true
		reserved[project.origin + BuildingCatalog.doorstep_of(project.blueprint_id)] = true
	return reserved


## A City Hall's own real "compute demands" step (see docs/concept/
## npc_role_consensus.md's "City Hall" section): [] if no real "city_hall"
## structure stands within CITY_HALL_DEMAND_RADIUS_TILES of
## (global_x, global_y) -- a silent, discoverable "nothing to convene
## about" absence, not an invented placeholder demand. Otherwise reads the
## SAME real settlement state _apply_settlement_build_decision already
## does (market.stock, _present_structure_ids_for_settlement_chunk) and
## hands it to SettlementDemand.demands_for -- no second, parallel needs
## computation.
func city_hall_demands_near(global_x: int, global_y: int) -> Array:
	if not has_structure_near(global_x, global_y, "city_hall", CITY_HALL_DEMAND_RADIUS_TILES):
		return []
	var chunk_coord := _chunk_coord_for_tile(Vector2i(global_x, global_y))
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	var market := _market_store.market_for(settlement_id)
	var present_structure_ids := _present_structure_ids_for_settlement_chunk(chunk_coord)
	return SettlementDemand.demands_for(market.stock, present_structure_ids, _recipe_book)


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
	# A whole-building entity (the town hall, docs/concept/building.md
	# "City Hall over time") -- checked BEFORE the placeable branch: its id
	# is also a legacy single-tile placeable item, and a completed hall is
	# the real catalog building on its own plot, never that tile.
	if BuildingCatalog.has_building(project.blueprint_id):
		_place_completed_building_project(project)
		return
	# Pavement is a laid SURFACE, not a structure (docs/concept/
	# planner_mode.md's "What can be planned"): the same road tile a village
	# lays for its streets, through the same build_at_global that lays them,
	# so anything already true of a street is true of a paved plan.
	if TerrainRenderer.is_road_tile(project.blueprint_id):
		var road_cell: Vector2i = project.chunk_coord * CHUNK_SIZE + project.origin
		build_at_global(road_cell.x, road_cell.y, project.blueprint_id)
		return
	var output: Dictionary = _recipe_book.recipe_output(project.blueprint_id)
	if output.is_empty():
		return
	var output_item_id: String = output["item_id"]
	if _item_catalog.kind_of(output_item_id) != "placeable":
		return
	# The site chosen when the project started (see _settlement_build_
	# origin_for) is re-checked now that the work is done: if something was
	# built there in the meantime (the player, another project), the
	# structure goes to the next clear site instead of stamping over it.
	var origin: Vector2i = project.origin
	if not _is_clear_settlement_site(project.chunk_coord, origin):
		var resited = _settlement_build_origin_for(project.chunk_coord)
		if resited == null:
			return
		origin = resited
	var global_cell: Vector2i = project.chunk_coord * CHUNK_SIZE + origin
	build_at_global(global_cell.x, global_cell.y, output_item_id)
	# A settlement raises a fenced plot in one go (docs/concept/milling_and_
	# baking.md): the Farm's own gate rule (_reconcile_farmer_at) admits no
	# Farmer until a real wooden_fence stands near, and the Farm recipe's own
	# stated cost already IS the fence -- "wood (6) for fence rails/posts and
	# plant_fibre (4) lashing them" (npc_farm_production.md) -- so the fence
	# is placed on the first clear neighbouring cell at no further charge.
	if output_item_id == "farm":
		for offset in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
			var fence_cell: Vector2i = global_cell + offset
			if (
				is_buildable_terrain_at(fence_cell.x, fence_cell.y)
				and modification_at_global(fence_cell.x, fence_cell.y) == ""
			):
				build_at_global(fence_cell.x, fence_cell.y, "wooden_fence")
				break


## A completed whole-building project lands as the real catalog building
## on its own plot (place_building, owned by the project's own household
## -- the settlement itself for a hall), the plaza's road lifted from under
## the footprint and the doorstep laid again so the hall's door still opens
## onto the street; its construction site (see _sync_construction_site) is
## gone the same moment. The site was re-checked clear on the very tick
## that completed it (_advance_construction_labor); if it is taken after
## all, nothing is placed -- the ledger still reads COMPLETE, an honest
## edge this pass does not paper over with a second placement algorithm.
func _place_completed_building_project(project) -> void:
	_free_construction_site(project.chunk_coord, project.origin)
	var building_id: String = project.blueprint_id
	if not _civic_site_is_clear(project.chunk_coord, project.origin, building_id):
		return
	var origin_tile: Vector2i = project.chunk_coord * CHUNK_SIZE + project.origin
	var seed_value := _house_site_seed(project.chunk_coord, origin_tile, building_id)
	_place_building_over_roads(
		project.chunk_coord, project.origin, building_id, seed_value, project.household_id, true
	)


## Construction sites: chunk_coord -> {origin_local -> Node2D}, one per
## in-progress whole-building project, drawn from the building sheet's
## own construction row (BuildingCatalog.ROW_CONSTRUCTION, eight stages
## scaffold -> shell -> roof) at the stage the project's own labour has
## reached -- the same footprint-anchored node a finished building uses,
## so the hall visibly rises where it will stand. Freed on completion and
## on chunk unload; rebuilt by the next labour tick after a reload.
var _construction_site_nodes: Dictionary = {}


func _sync_construction_site(chunk_coord: Vector2i, project) -> void:
	var building_id: String = project.blueprint_id
	var required := ConstructionLabor.labor_hours_required(building_id, _recipe_book)
	var progress := 0.0 if required <= 0.0 else clampf(project.labor_hours_accumulated / required, 0.0, 1.0)
	# A house rises through its OWN variation's 24 real build frames --
	# foundation, frames, construction -- so the site is visibly the house
	# it is going to be. Everything else keeps the 8x5 sheet's single
	# construction row. See BuildingCatalog.construction_sheet_chain.
	var seed_value := _house_site_seed(chunk_coord, chunk_coord * CHUNK_SIZE + project.origin, building_id)
	var chain: Array = BuildingCatalog.construction_sheet_chain(building_id, seed_value, progress)
	var cell := Vector2i(int(chain[0]["column"]), int(chain[0]["row"]))
	var footprint := BuildingCatalog.footprint_of(building_id)

	var node: Node2D = _construction_site_node_at(chunk_coord, project.origin)
	if node == null:
		node = Node2D.new()
		node.name = "ConstructionSite"
		var footprint_px := Vector2(footprint) * TerrainRenderer.TILE_SIZE
		var top_left_px := Vector2(chunk_coord * CHUNK_SIZE + project.origin) * TerrainRenderer.TILE_SIZE
		node.position = top_left_px + Vector2(footprint_px.x * 0.5, footprint_px.y)
		var sprite := Sprite2D.new()
		sprite.name = "Stage"
		node.add_child(sprite)
		_entities_parent.add_child(node)
		if not _construction_site_nodes.has(chunk_coord):
			_construction_site_nodes[chunk_coord] = {}
		_construction_site_nodes[chunk_coord][project.origin] = node
		node.set_meta("stage", Vector2i(-1, -1))

	if node.get_meta("stage") == cell:
		return
	node.set_meta("stage", cell)
	var sprite: Sprite2D = node.get_node("Stage")
	# The same art resolution the FINISHED building uses (see
	# _spawn_building_node): a site drawn at a different pixels-per-world-
	# unit would visibly jump the moment it completed.
	var texture := _first_texture_of(chain, footprint.x)
	if texture == null:
		# No sheet yet: the finished placeholder, faded -- a ghost of what
		# is coming, growing solid with the work.
		texture = _building_placeholder_sprite.footprint_texture(footprint, 0, TerrainRenderer.ART_TILE_SIZE)
		sprite.modulate = Color(1.0, 1.0, 1.0, 0.35 + 0.65 * progress)
	sprite.texture = texture
	sprite.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE
	sprite.position = Vector2(0, -float(texture.get_height()) * 0.5 * ArtResolution.SPRITE_SCALE)


## The first sheet of `chain` (BuildingCatalog.finished_sheet_chain /
## construction_sheet_chain) whose file is really on disk, as a texture
## scaled to a `footprint_width_tiles`-wide footprint -- null when none of
## them is, which is the caller's cue to draw the procedural placeholder.
##
## ART_TILE_SIZE, not TILE_SIZE, and scaled back by SPRITE_SCALE (see
## docs/concept/art_resolution.md): the WORLD footprint is identical either
## way, but the art then carries DETAIL_MULTIPLIER pixels per world unit --
## the same detail per world unit the ground it stands on already paints
## at. A finely drawn sheet at TILE_SIZE would be thrown away.
func _first_texture_of(chain: Array, footprint_width_tiles: int) -> ImageTexture:
	for entry in chain:
		var texture := _illustrated_structure_sprite.footprint_frame_texture(
			entry["path"], entry["columns"], entry["rows"], entry["row"], entry["column"],
			TerrainRenderer.ART_TILE_SIZE, footprint_width_tiles, entry["grid"]
		)
		if texture != null:
			return texture
	return null


func _construction_site_node_at(chunk_coord: Vector2i, origin_local: Vector2i) -> Node2D:
	var node = _construction_site_nodes.get(chunk_coord, {}).get(origin_local)
	return node if node != null and is_instance_valid(node) else null


func _free_construction_site(chunk_coord: Vector2i, origin_local: Vector2i) -> void:
	var by_origin: Dictionary = _construction_site_nodes.get(chunk_coord, {})
	var node = by_origin.get(origin_local)
	if node != null and is_instance_valid(node):
		node.free()
	by_origin.erase(origin_local)


func _free_construction_sites_in_chunk(chunk_coord: Vector2i) -> void:
	var by_origin: Dictionary = _construction_site_nodes.get(chunk_coord, {})
	for origin_local in by_origin.keys():
		_free_construction_site(chunk_coord, origin_local)
	_construction_site_nodes.erase(chunk_coord)


## The house pieces the water reclaims (see _reclaim_pieces_standing_in_
## water): everything a house is made of, on either storey. A dam belongs
## in water and a boulder IS the river's -- both CATEGORY_DAM, both left
## alone.
const _WATER_RECLAIMS_CATEGORIES := {
	BuildingPiece.CATEGORY_WALL: true, BuildingPiece.CATEGORY_FLOOR: true,
	BuildingPiece.CATEGORY_DOOR: true, BuildingPiece.CATEGORY_WINDOW: true,
	BuildingPiece.CATEGORY_ROOF: true, BuildingPiece.CATEGORY_FURNITURE: true,
	BuildingPiece.CATEGORY_STAIRS: true,
}


## Nothing built stands in water (docs/concept/building.md "Placement
## rules") -- including what an older save persisted before the water rule
## existed. Reported directly with a screenshot of a stone house standing in
## a pond: every house piece on a cell the water surface paints (see
## is_water_at_global) is removed on load, on every layer -- floor, roof,
## furniture, both storeys -- and the save rewritten so it stays gone, the
## way nothing anyone builds in a pond survives the pond. A dam or a
## boulder belongs in water and is left alone (_WATER_RECLAIMS_CATEGORIES).
## No-op for a chunk with nothing in water, which is every chunk once the
## rule holds at build time.
## The whole-building twin of _reclaim_pieces_standing_in_water: a building
## whose door or doorstep cell has become water (the layout algorithm
## validates dry ground at placement time, but terrain rules can still
## move -- and this is what protects a save made before a hydrology fix
## the same way the piece reclaim already does) is removed on load rather
## than left standing over/against a pond. Checking the door/doorstep
## rather than every footprint cell: a building whose own walls happen to
## graze a newly-wet corner but whose entrance is still dry stays --
## unlike a piece structure, a building's interior is never actually the
## painted ground under it (see HouseInteriorView), so only the ground the
## player would actually stand on to reach it matters here.
func _reclaim_buildings_standing_in_water(chunk_coord: Vector2i, chunk: Chunk) -> void:
	var origin := chunk_coord * CHUNK_SIZE
	var removed := false
	for origin_local in chunk.buildings.keys().duplicate():
		var record: Dictionary = chunk.buildings[origin_local]
		var building_id: String = record["id"]
		var door_global: Vector2i = origin + origin_local + BuildingCatalog.door_of(building_id)
		var doorstep_global: Vector2i = origin + origin_local + BuildingCatalog.doorstep_of(building_id)
		if not is_water_at_global(door_global.x, door_global.y) and not is_water_at_global(doorstep_global.x, doorstep_global.y):
			continue
		for local in BuildingCatalog.footprint_cells(building_id, origin_local):
			chunk.modifications.erase(local)
		chunk.buildings.erase(origin_local)
		removed = true
	if removed:
		_persist_modifications_now(chunk_coord, chunk)


func _reclaim_pieces_standing_in_water(chunk_coord: Vector2i, chunk: Chunk) -> void:
	var origin := chunk_coord * CHUNK_SIZE
	var removed := false
	for local in chunk.modifications.keys().duplicate():
		var tile_id: String = chunk.modifications[local]
		if not BuildingPiece.has_piece(tile_id) or not _WATER_RECLAIMS_CATEGORIES.has(BuildingPiece.category_of(tile_id)):
			continue
		var global: Vector2i = origin + local
		if not is_water_at_global(global.x, global.y):
			continue
		chunk.modifications.erase(local)
		chunk.piece_condition.erase(local)
		removed = true
	for layer in [
		chunk.roof_modifications, chunk.furniture_modifications,
		chunk.upper_floor_modifications, chunk.upper_floor_furniture_modifications,
	]:
		for local in layer.keys().duplicate():
			var global: Vector2i = origin + local
			if is_water_at_global(global.x, global.y):
				layer.erase(local)
				removed = true
	if removed:
		_persist_modifications_now(chunk_coord, chunk)


## Old-save migration (docs/concept/building.md "Older saves"): a
## settlement chunk that still carries OLD-STYLE piece-built houses -- real
## house-piece cells in chunk.modifications (and their roof/furniture/
## upper-floor siblings), from before whole-building village houses
## existed -- has them wiped ONCE on load, so spawn_village (called much
## later in _load_chunk) regenerates the same settlement as real
## whole-building entities instead. Detected the same way every other
## "stale persisted state" pass in this file is: chunk.buildings (the new
## registry) is still empty. A chunk whose chunk.buildings is already
## populated -- whether from a genuinely fresh load under the new code, or
## an earlier visit that already migrated it -- is untouched; this only
## ever does real work once per settlement's own lifetime, the same
## "detect + fix, then it's simply true from then on" shape
## _reclaim_pieces_standing_in_water already has.
##
## A player-built piece structure at the SAME site -- a real, separate
## mechanism this pass must never touch (docs/concept/building.md
## "Legacy") -- is protected: every local cell inside a COMPLETE
## ConstructionProject owned by the player's own household is excluded,
## the same way _reclaim_pieces_standing_in_water already excludes
## CATEGORY_DAM from a universal rule. Only COMPLETE projects are
## checked -- today the only reachable state for a player's own piece
## house is started-and-completed at once
## (stamp_house_and_grant_ownership), so there is no real PLANNED/
## IN_PROGRESS gap where pieces exist without a COMPLETE project backing
## them yet; the ghost-planning system that would introduce one
## (docs/concept/civic_construction.md) is design-only, not implemented.
func _migrate_piece_village_to_buildings_if_stale(chunk_coord: Vector2i, chunk: Chunk) -> void:
	if not chunk.buildings.is_empty():
		return
	if not _settlement_generator.has_settlement_at(chunk_coord, _biome_classifier.dominant_biome(chunk.biome)):
		return

	var protected_cells := _player_owned_piece_cells_in_chunk(chunk_coord)
	var removed := false
	for local in chunk.modifications.keys().duplicate():
		if protected_cells.has(local):
			continue
		var tile_id: String = chunk.modifications[local]
		if not BuildingPiece.has_piece(tile_id) or not _WATER_RECLAIMS_CATEGORIES.has(BuildingPiece.category_of(tile_id)):
			continue
		chunk.modifications.erase(local)
		chunk.piece_condition.erase(local)
		removed = true
	for layer in [
		chunk.roof_modifications, chunk.furniture_modifications,
		chunk.upper_floor_modifications, chunk.upper_floor_furniture_modifications,
	]:
		for local in layer.keys().duplicate():
			if protected_cells.has(local):
				continue
			layer.erase(local)
			removed = true
	if removed:
		_persist_modifications_now(chunk_coord, chunk)


## Older saves' village streets (docs/concept/infrastructure.md's Road
## tier): before the tier existed, VillageRenderer laid every street as
## the worn TRAIL tile. A chunk with real buildings is a laid-out village,
## and a laid-out village's only trails ARE its streets -- so they are
## repaved as the real road tile here, before the first paint/ground-cover
## pass, the same "heal an old save on its next load" shape the migration
## just above has. A chunk with no buildings keeps its trails: those are
## genuinely worn ground, not a street. Nothing persists here -- the chunk
## saves its modifications on unload as always.
func _migrate_village_trails_to_roads(chunk: Chunk) -> void:
	if chunk.buildings.is_empty():
		return
	for local in chunk.modifications:
		if chunk.modifications[local] == TerrainRenderer.TRAIL_TILE_ID:
			chunk.modifications[local] = TerrainRenderer.ROAD_TILE_ID


## Every local cell covered by a COMPLETE ConstructionProject the player's
## own household owns, in `chunk_coord` -- the migration pass above must
## never touch these. household_for (not form_household) so a chunk with
## no player activity at all never spuriously creates a player household
## just by loading it. Mirrors _house_furniture_count's own established
## "recipe -> HouseBlueprint shape -> footprint" derivation exactly, rather
## than inventing a second way to size a piece house's footprint.
func _player_owned_piece_cells_in_chunk(chunk_coord: Vector2i) -> Dictionary:
	var cells := {}
	var household = _household_store.household_for(PlayerIdentity.PLAYER_ENTITY_ID)
	if household == null:
		return cells
	for project in _construction_project_store.projects_owned_by(household.id):
		if project.chunk_coord != chunk_coord:
			continue
		var shape_id: String = HOUSE_BLUEPRINT_SHAPE_BY_RECIPE_ID.get(project.blueprint_id, "")
		if shape_id == "":
			continue  # a non-house project (e.g. a future civic building) -- no piece footprint to protect here
		var footprint := HouseBlueprint.new().footprint_for(shape_id)
		for x in footprint.x:
			for y in footprint.y:
				cells[project.origin + Vector2i(x, y)] = true
	return cells


## Writes every modification layer of `chunk` to disk right now -- the same
## per-layer files _unload_chunk writes on eviction, plus the one thing it
## does not do: a layer that is now EMPTY has its file removed, so a wash
## that emptied a chunk does not leave the old file behind to be reloaded
## and washed again on every visit.
func _persist_modifications_now(chunk_coord: Vector2i, chunk: Chunk) -> void:
	var layers := [
		[chunk.modifications, MODIFICATIONS_DIR, _modifications_path(chunk_coord)],
		[chunk.roof_modifications, ROOF_MODIFICATIONS_DIR, _roof_modifications_path(chunk_coord)],
		[chunk.furniture_modifications, FURNITURE_MODIFICATIONS_DIR, _furniture_modifications_path(chunk_coord)],
		[chunk.upper_floor_modifications, UPPER_FLOOR_MODIFICATIONS_DIR, _upper_floor_modifications_path(chunk_coord)],
		[
			chunk.upper_floor_furniture_modifications, UPPER_FLOOR_FURNITURE_MODIFICATIONS_DIR,
			_upper_floor_furniture_modifications_path(chunk_coord),
		],
		[chunk.buildings, BUILDINGS_DIR, _buildings_path(chunk_coord)],
	]
	for layer in layers:
		var data: Dictionary = layer[0]
		var path: String = layer[2]
		if data.is_empty():
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
			continue
		DirAccess.make_dir_recursive_absolute(layer[1])
		_chunk_serializer.save_modifications(data, path)


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
	if chunk != null and not chunk.furniture_modifications.is_empty():
		DirAccess.make_dir_recursive_absolute(FURNITURE_MODIFICATIONS_DIR)
		_chunk_serializer.save_modifications(chunk.furniture_modifications, _furniture_modifications_path(chunk_coord))
	if chunk != null and not chunk.upper_floor_modifications.is_empty():
		DirAccess.make_dir_recursive_absolute(UPPER_FLOOR_MODIFICATIONS_DIR)
		_chunk_serializer.save_modifications(chunk.upper_floor_modifications, _upper_floor_modifications_path(chunk_coord))
	if chunk != null and not chunk.upper_floor_furniture_modifications.is_empty():
		DirAccess.make_dir_recursive_absolute(UPPER_FLOOR_FURNITURE_MODIFICATIONS_DIR)
		_chunk_serializer.save_modifications(
			chunk.upper_floor_furniture_modifications, _upper_floor_furniture_modifications_path(chunk_coord)
		)
	if chunk != null and not chunk.buildings.is_empty():
		DirAccess.make_dir_recursive_absolute(BUILDINGS_DIR)
		_chunk_serializer.save_modifications(chunk.buildings, _buildings_path(chunk_coord))

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
	if _furniture_layer != null:
		_terrain_renderer.erase(_furniture_layer, CHUNK_SIZE, chunk_coord * CHUNK_SIZE)
	if _upper_floor_layer != null:
		_terrain_renderer.erase(_upper_floor_layer, CHUNK_SIZE, chunk_coord * CHUNK_SIZE)
	if _upper_floor_furniture_layer != null:
		_terrain_renderer.erase(_upper_floor_furniture_layer, CHUNK_SIZE, chunk_coord * CHUNK_SIZE)
	_upper_floor_painted.erase(chunk_coord)
	_upper_floor_furniture_painted.erase(chunk_coord)
	if _hidden_roof_chunk_coord == chunk_coord:
		_hidden_roof_chunk_coord = null
		_hidden_roof_room_cells = []
	if _upper_view_chunk_coord == chunk_coord:
		_upper_view_chunk_coord = null
		_upper_view_house_cells = []
	_loaded_chunks.erase(chunk_coord)

	for body in _piece_collision_bodies.get(chunk_coord, {}).values():
		body.free()
	_piece_collision_bodies.erase(chunk_coord)

	for body in _upper_piece_collision_bodies.get(chunk_coord, {}).values():
		body.free()
	_upper_piece_collision_bodies.erase(chunk_coord)

	for node in _building_nodes.get(chunk_coord, {}).values():
		node.free()
	_building_nodes.erase(chunk_coord)
	_free_construction_sites_in_chunk(chunk_coord)

	for tree in _loaded_trees.get(chunk_coord, []):
		tree.free()
	_loaded_trees.erase(chunk_coord)

	for marker in _cicada_markers.get(chunk_coord, []):
		marker.free()
	_cicada_markers.erase(chunk_coord)

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
	for mmi in _grass_sprites_turning.get(chunk_coord, {}).values():
		mmi.free()
	_grass_sprites_turning.erase(chunk_coord)
	_grass_sims.erase(chunk_coord)

	for markers_by_crop in _wild_crop_markers.get(chunk_coord, {}).values():
		for marker in markers_by_crop.values():
			marker.free()
	_wild_crop_markers.erase(chunk_coord)
	_wild_crop_sims.erase(chunk_coord)

	for marker in _mushroom_markers.get(chunk_coord, {}).values():
		marker.free()
	_mushroom_markers.erase(chunk_coord)
	_mushroom_sims.erase(chunk_coord)

	for marker in _decomposer_markers.get(chunk_coord, []):
		marker.free()
	_decomposer_markers.erase(chunk_coord)

	for marker in _caterpillar_markers.get(chunk_coord, []):
		marker.free()
	_caterpillar_markers.erase(chunk_coord)

	for marker in _millipede_markers.get(chunk_coord, []):
		marker.free()
	_millipede_markers.erase(chunk_coord)

	for marker in _grass_frog_markers.get(chunk_coord, []):
		marker.free()
	_grass_frog_markers.erase(chunk_coord)

	for marker in _sagewerk_lumberjacks.get(chunk_coord, {}).values():
		marker.free()
	_sagewerk_lumberjacks.erase(chunk_coord)

	for marker in _farm_farmers.get(chunk_coord, {}).values():
		marker.free()
	_farm_farmers.erase(chunk_coord)

	for marker in _conversion_workers.get(chunk_coord, {}).values():
		marker.free()
	_conversion_workers.erase(chunk_coord)

	for by_storage in _logistics_workers.get(chunk_coord, {}).values():
		for by_item in by_storage.values():
			for marker in by_item.values():
				marker.free()
	_logistics_workers.erase(chunk_coord)
	for by_leg in _chain_logistics_workers.get(chunk_coord, {}).values():
		for by_destination in by_leg.values():
			for by_item in by_destination.values():
				for marker in by_item.values():
					marker.free()
	_chain_logistics_workers.erase(chunk_coord)
	# This chunk may have held the Storage (or Sägewerk/Farm) a worker
	# elsewhere was paired against -- re-decide every REMAINING known
	# Sägewerk's (and Farm's) Logistics staffing now that this chunk's own
	# structures are gone, mirroring _load_chunk's own identical broad
	# resync on the way in. Also may have held the wooden_fence gating a
	# REMAINING known Farm elsewhere -- re-decide every one of those too.
	for sagewerk_chunk_coord in _sagewerk_lumberjacks:
		for sagewerk_local_cell in _sagewerk_lumberjacks[sagewerk_chunk_coord]:
			_resync_logistics_for_sagewerk(sagewerk_chunk_coord, sagewerk_local_cell)
	_reconcile_all_known_farmers()
	for farm_chunk_coord in _farm_farmers:
		for farm_local_cell in _farm_farmers[farm_chunk_coord]:
			_resync_logistics_for_farm(farm_chunk_coord, farm_local_cell)
	_resync_all_chain_legs()

	for art_sprite in _structure_art_sprites.get(chunk_coord, {}).values():
		art_sprite.free()
	_structure_art_sprites.erase(chunk_coord)

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

	for sprite in _aquatic_vegetation_sprites.get(chunk_coord, {}).values():
		sprite.free()
	_aquatic_vegetation_sprites.erase(chunk_coord)
	_aquatic_vegetation.erase(chunk_coord)

	for sprite in _aquatic_invertebrates_sprites.get(chunk_coord, {}).values():
		sprite.free()
	_aquatic_invertebrates_sprites.erase(chunk_coord)
	_aquatic_invertebrates.erase(chunk_coord)

	# An AntForagerMarker already in flight for one of this chunk's mounds
	# holds a direct reference to this exact AntColony (see that class's
	# own _colony doc comment) -- it is parented on the persistent
	# _entities_parent node, not chunk-scoped, so unloading correctly does
	# NOT free it (the world keeps living while nobody's watching -- see
	# _loaded_ambient_flyers/etc. just above for the chunk-scoped things
	# that DO get freed here). Erasing this dictionary's own entry alone
	# cannot free an object the forager itself still references, so it
	# must be explicitly retired -- see AntColony.mark_retired's own doc
	# comment, docs/concept/soil_fauna.md's "In-flight foragers survive an
	# unload; their trip's outcome does not" (mirrors BeeColony's own
	# identical fix just below, see docs/concept/bees.md's own section of
	# that name -- this is the ant side of the same fix).
	var retiring_ant_colony: AntColony = _ant_colonies.get(chunk_coord)
	if retiring_ant_colony != null:
		retiring_ant_colony.mark_retired()
	_ant_colonies.erase(chunk_coord)
	for marker in _ant_mound_markers.get(chunk_coord, []):
		marker.free()
	_ant_mound_markers.erase(chunk_coord)

	# A BeeForagerMarker already in flight for one of this chunk's hives
	# holds a direct reference to this exact BeeColony (see that class's
	# own _colony doc comment) -- it is parented on the persistent
	# _entities_parent node, not chunk-scoped, so unloading correctly does
	# NOT free it (the world keeps living while nobody's watching -- see
	# _loaded_ambient_flyers/etc. just above for the chunk-scoped things
	# that DO get freed here). Erasing this dictionary's own entry alone
	# cannot free an object the forager itself still references, so it
	# must be explicitly retired -- see BeeColony.mark_retired's own doc
	# comment, docs/concept/bees.md's "In-flight foragers survive an
	# unload; their trip's outcome does not".
	var retiring_bee_colony: BeeColony = _bee_colonies.get(chunk_coord)
	if retiring_bee_colony != null:
		retiring_bee_colony.mark_retired()
	_bee_colonies.erase(chunk_coord)
	for marker in _bee_hive_markers.get(chunk_coord, {}).values():
		marker.free()
	_bee_hive_markers.erase(chunk_coord)

	# Mirrors the honeybee-hive retirement immediately above, for the
	# OTHER role BeeForagerMarker serves (a solitary WildBeePatch
	# resident's own trip) -- see WildBeePatch.mark_retired's own doc
	# comment.
	var retiring_wild_bee_patch: WildBeePatch = _wild_bee_patches.get(chunk_coord)
	if retiring_wild_bee_patch != null:
		retiring_wild_bee_patch.mark_retired()
	_wild_bee_patches.erase(chunk_coord)
	for marker in _wild_bee_nest_markers.get(chunk_coord, {}).values():
		marker.free()
	_wild_bee_nest_markers.erase(chunk_coord)

	_leaf_litter_fields.erase(chunk_coord)
	if _leaf_litter_mmis.has(chunk_coord):
		_leaf_litter_mmis[chunk_coord].free()
		_leaf_litter_mmis.erase(chunk_coord)
	_leaf_litter_filled_generation.erase(chunk_coord)
	_leaf_litter_far_pending.erase(chunk_coord)

	_footprint_fields.erase(chunk_coord)
	for mmi in _footprint_mmis.get(chunk_coord, {}).values():
		mmi.free()
	_footprint_mmis.erase(chunk_coord)
	_footprint_filled_generation.erase(chunk_coord)
	_footprint_far_advanced_at.erase(chunk_coord)

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
				"blackbirds": _ecosystem.blackbird_population(chunk_coord),
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
				"blackbirds": _ecosystem.blackbird_population(chunk_coord),
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
		if not _rehome_wandered_creature(creature, chunk_coord):
			creature.free()
	_loaded_creatures.erase(chunk_coord)

	_free_pond_fish_markers(chunk_coord)
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


## Whether a wild creature that has physically wandered away from the chunk
## it is filed under should be re-homed to wherever it now stands rather
## than freed outright with the rest of that chunk. Reported live: "animals
## (like a boar chasing or a deer being hunted) don't survive chunk borders
## and just disappear" (see docs/concept/ecosystem_dynamics.md "An
## individually-rendered creature crossing a chunk border").
##
## _loaded_creatures tracks chunk membership by bookkeeping only, set once
## when a creature spawns/reconciles and never updated as it actually
## moves -- so a predator mid-hunt or prey mid-flee (CreatureMarker's
## FLEE_SPEED/HUNT_SPEED, with no maximum chase distance) can cross into a
## neighbouring chunk that is very much still loaded while still being
## filed under the chunk it started in. Without this check, the moment that
## original chunk falls outside UNLOAD_RADIUS, the still-visible creature
## the player was watching would be deleted out from under them.
##
## Deliberately excludes anything _save_kept_animals/_save_growing_juveniles
## already cover (tamed, tied, or an immature juvenile) -- those are already
## serialized to THIS chunk's own save file (just above, in _unload_chunk)
## and respawned fresh on its next load. Re-homing the same live instance
## too would leave both a serialized record and a still-alive wandered
## instance, producing a duplicate the moment the original chunk reloads. An
## ordinary wild adult -- exactly the boar or deer in the report -- has no
## such record, so this is the only protection it gets.
func _rehome_wandered_creature(creature: Node2D, stale_chunk_coord: Vector2i) -> bool:
	if not is_instance_valid(creature) or creature.info == null:
		return false
	if KeptAnimals.is_worth_keeping(float(creature.trust), creature.is_tied_up()):
		return false
	if GrowingJuveniles.is_worth_persisting(creature.age_seconds, creature.info.species):
		return false
	var current_chunk := _chunk_coord_for_tile(_world_tile_for_pixel(creature.position))
	if current_chunk == stale_chunk_coord:
		return false
	# Only a chunk this manager still actually considers loaded is a real
	# destination -- a creature that outran even that (more than one chunk
	# crossed between two update() calls, or genuinely wandered off into the
	# unloaded distance) is not any more "still here" than before this fix,
	# and is freed exactly as it always was.
	if not _loaded_chunks.has(current_chunk):
		return false
	if not _loaded_creatures.has(current_chunk):
		_loaded_creatures[current_chunk] = []
	_loaded_creatures[current_chunk].append(creature)
	return true


func _modifications_path(chunk_coord: Vector2i) -> String:
	return "%s/%d_%d.bin" % [MODIFICATIONS_DIR, chunk_coord.x, chunk_coord.y]


func _roof_modifications_path(chunk_coord: Vector2i) -> String:
	return "%s/%d_%d.bin" % [ROOF_MODIFICATIONS_DIR, chunk_coord.x, chunk_coord.y]


func _furniture_modifications_path(chunk_coord: Vector2i) -> String:
	return "%s/%d_%d.bin" % [FURNITURE_MODIFICATIONS_DIR, chunk_coord.x, chunk_coord.y]


func _upper_floor_modifications_path(chunk_coord: Vector2i) -> String:
	return "%s/%d_%d.bin" % [UPPER_FLOOR_MODIFICATIONS_DIR, chunk_coord.x, chunk_coord.y]


func _upper_floor_furniture_modifications_path(chunk_coord: Vector2i) -> String:
	return "%s/%d_%d.bin" % [UPPER_FLOOR_FURNITURE_MODIFICATIONS_DIR, chunk_coord.x, chunk_coord.y]


func _buildings_path(chunk_coord: Vector2i) -> String:
	return "%s/%d_%d.bin" % [BUILDINGS_DIR, chunk_coord.x, chunk_coord.y]


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
			"blackbirds": float(saved.get("blackbirds", 0.0)),
		},
		elapsed,
		{
			"herbivore_capacity": _ecosystem.herbivore_capacity_at(chunk_coord),
			"fruit_growth_rate": 0.0,
			"fish_capacity": _ecosystem.fish_capacity_at(chunk_coord),
			"robin_capacity": _ecosystem.robin_capacity_at(chunk_coord),
			"sparrow_capacity": _ecosystem.sparrow_capacity_at(chunk_coord),
			"blackbird_capacity": _ecosystem.blackbird_capacity_at(chunk_coord),
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
	_ecosystem.seed_blackbird_population(chunk_coord, float(caught_up.get("blackbirds", 0.0)))
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


## The chunk a global tile falls in. A public wrapper over the private
## helper below rather than a second copy of the same floor division --
## planner mode needs it to turn a clicked world cell into a
## chunk+local-origin site (see BuildPlan), and duplicating the arithmetic
## in World is exactly how two answers to one question drift apart.
## Advances a player-commissioned build by real elapsed time, and completes
## it when the hours are in.
##
## `builder_count` is how many people are working it -- the same capacity
## shape ConstructionCatchup reads everywhere else (8 hours per builder per
## in-game day), so a hired villager earns exactly what a settlement's own
## spare hand does rather than on a private schedule.
##
## Worked in the GAME's own day (SECONDS_PER_SIMULATED_DAY), not the ecology
## catch-up's LOD day. Measured (tools/probe_raised_build.gd): at the
## catch-up rate a small house is 2.25 * 3600 = 8100 real seconds of one
## builder's work, so a player standing at their own site, or one who has
## just paid a villager's wage, watches nothing happen for two and a
## quarter hours -- which is how "hiring a builder does not work" was
## reported. A raised build is a thing the player is WATCHING, so it runs
## on the clock the player lives in; the settlement's own construction and
## the offscreen catch-up keep the rate they were tuned at (see
## docs/concept/planner_mode.md for that divergence, stated rather than
## silently reconciled).
##
## This is what docs/concept/building.md means by retiring the instant hire
## fork: "a build the player cannot do themselves says that hiring returns
## with construction-over-time". A hired house is not spawned; it is worked.
##
## And what the hours PRODUCE is the settlement ledger's own answer, not a
## second one (docs/concept/planner_mode.md's "From raised to raised"): the
## site rises through the same construction-row sprite a village's own
## project draws, and finishing places the real building through the same
## _place_completed_construction_project. Marking a row COMPLETE in a
## ledger is bookkeeping, not construction -- this used to do only that,
## so a raised build that "finished" left nothing standing.
func advance_hired_build(project_id: String, elapsed_seconds: float, builder_count: float) -> Dictionary:
	var project = _construction_project_store.get_project(project_id)
	if project == null:
		return {"action": "no_op"}
	var result: Dictionary = _construction_project_store.advance_project_labor(
		project_id, elapsed_seconds, {"builder_count": builder_count}, _recipe_book, _household_store,
		SECONDS_PER_SIMULATED_DAY
	)
	match result.get("action", ""):
		"completed":
			_place_completed_construction_project(project)
		"advanced":
			if BuildingCatalog.has_building(project.blueprint_id):
				_sync_construction_site(project.chunk_coord, project)
	return result


## Finishes a raised build outright, and places what it built.
##
## For work that asks for no labour hours at all (PlanRaising.is_laid_by_
## hand -- pavement is not a recipe, so its requirement is genuinely zero):
## advance_project_labor deliberately never completes a zero-hour
## requirement, because otherwise an unknown blueprint id would complete
## instantly and for free. So a zero-hour build is finished HERE instead,
## the moment it is begun -- laid by hand, exactly like the earth tile the
## player already places (docs/concept/planner_mode.md's "Work that is laid
## by hand").
##
## Deliberately not a shortcut past the hours for anything else: the caller
## is the one that asked is_laid_by_hand, and it only ever asks about work
## that has none. False, no mutation, for an unknown project_id -- the same
## contract complete_project itself carries.
func finish_build_project(project_id: String) -> bool:
	var project = _construction_project_store.get_project(project_id)
	if project == null:
		return false
	if not _construction_project_store.complete_project(project_id, _household_store):
		return false
	_place_completed_construction_project(project)
	return true


## Opens (or returns) a real construction project for a site the PLAYER
## chose, rather than one a settlement decided on its own.
##
## The same ConstructionProjectStore.start_project every village build
## already goes through -- idempotent by site+blueprint, so raising a
## wireframe twice does not reset the progress of the first. Exposed
## because planner mode (docs/concept/planner_mode.md) lets a player raise
## a plan, and a player-raised building must be the same kind of project a
## villager-raised one is, not a parallel one.
func start_build_project(
	chunk_coord: Vector2i, origin: Vector2i, blueprint_id: String, household_id: String
) -> ConstructionProject:
	return _construction_project_store.start_project(chunk_coord, origin, blueprint_id, household_id)


## The same project, already under way -- what RAISING a wireframe opens,
## either way somebody pays for it (docs/concept/planner_mode.md's "From
## raised to raised"): somebody is working it from the moment it is raised.
## advance_project_labor only advances an IN_PROGRESS project, so a raised
## build that stayed PLANNED would silently never progress -- which is
## exactly what building it yourself used to do.
func begin_build_project(
	chunk_coord: Vector2i, origin: Vector2i, blueprint_id: String, household_id: String
) -> ConstructionProject:
	var project := start_build_project(chunk_coord, origin, blueprint_id, household_id)
	project.status = ConstructionProject.Status.IN_PROGRESS
	return project


## The real labour hours a build of `blueprint_id` asks for -- off the SAME
## recipe book the ledger derives its own requirement from, so a caller
## deciding whether work is laid by hand (PlanRaising.is_laid_by_hand) and
## the ledger deciding when it is finished can never disagree about how big
## the job is.
func build_labor_hours_for(blueprint_id: String) -> float:
	return ConstructionLabor.labor_hours_required(blueprint_id, _recipe_book)


func chunk_coord_for_tile(global_tile: Vector2i) -> Vector2i:
	return _chunk_coord_for_tile(global_tile)


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
