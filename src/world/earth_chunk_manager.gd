extends RefCounted

const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const TreeRenderer = preload("res://src/rendering/tree_renderer.gd")
const StoneRenderer = preload("res://src/rendering/stone_renderer.gd")
const TallGrass = preload("res://src/world/tall_grass.gd")
const ProceduralGrassSprite = preload("res://src/rendering/procedural_grass_sprite.gd")
const CreatureRenderer = preload("res://src/rendering/creature_renderer.gd")
const EcosystemSimulation = preload("res://src/world/ecosystem_simulation.gd")
const ChunkSerializer = preload("res://src/world/chunk_serializer.gd")
const ForageScheduler = preload("res://src/gameplay/forage_scheduler.gd")
const TreeSpread = preload("res://src/gameplay/tree_spread.gd")
const FruitingModel = preload("res://src/world/fruiting_model.gd")
const ChunkEcologyCatchup = preload("res://src/world/chunk_ecology_catchup.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")
const WeatherModel = preload("res://src/world/weather_model.gd")
const TreeMaturity = preload("res://src/gameplay/tree_maturity.gd")
const Item = preload("res://src/gameplay/item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")
const Chunk = preload("res://src/world/chunk.gd")

## Where player-made tile modifications (Phase 3 building) are persisted,
## keyed per chunk -- terrain itself is deterministically regenerable (see
## update()'s doc comment), so only modifications need saving.
const MODIFICATIONS_DIR := "user://chunk_modifications"

## Where trees that have spread since a chunk was generated (see
## step_tree_spread) are persisted -- the original forest is deterministically
## regenerable like terrain, so only spread-in trees need saving.
const PLANTED_TREES_DIR := "user://chunk_planted_trees"

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
var _creature_renderer := CreatureRenderer.new()
var _ecosystem := EcosystemSimulation.new()
var _chunk_serializer := ChunkSerializer.new()
var _forage_scheduler := ForageScheduler.new()
var _tree_spread := TreeSpread.new()
var _tree_maturity := TreeMaturity.new()
var _tile_map_layer: TileMapLayer
var _entities_parent: Node2D
var _creatures_parent: Node2D
var _loaded_chunks: Dictionary = {}  # Vector2i chunk_coord -> Chunk
var _loaded_trees: Dictionary = {}  # Vector2i chunk_coord -> Array[Node2D]
var _loaded_stones: Dictionary = {}  # Vector2i chunk_coord -> Array[Node2D]
var _grass_sims: Dictionary = {}  # Vector2i chunk_coord -> TallGrass
var _grass_sprites: Dictionary = {}  # Vector2i chunk_coord -> {local cell Vector2i -> Sprite2D}
var _grass_refresh_accumulator := 0.0
var _loaded_creatures: Dictionary = {}  # Vector2i chunk_coord -> Array[Node2D]
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
	var center_chunk := _chunk_coord_for_tile(player_global_tile)

	for chunk_coord in chunks_in_radius(center_chunk, LOAD_RADIUS):
		if not _loaded_chunks.has(chunk_coord):
			_load_chunk(chunk_coord)

	for chunk_coord in _loaded_chunks.keys().duplicate():
		if _chebyshev_distance(chunk_coord, center_chunk) > UNLOAD_RADIUS:
			_unload_chunk(chunk_coord)


func is_chunk_loaded(chunk_coord: Vector2i) -> bool:
	return _loaded_chunks.has(chunk_coord)


func has_ecosystem_region(chunk_coord: Vector2i) -> bool:
	return _ecosystem.has_region(chunk_coord)


func herbivore_population_at_chunk(chunk_coord: Vector2i) -> float:
	return _ecosystem.herbivore_population(chunk_coord)


func predator_population_at_chunk(chunk_coord: Vector2i) -> float:
	return _ecosystem.predator_population(chunk_coord)


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
	_forage_accumulator -= FORAGE_INTERVAL

	var tree_positions := _mature_tree_positions()
	for drop in _forage_scheduler.drops(tree_positions, _forage_tick, FORAGE_DROPS_PER_TICK):
		var spec: Array = _FORAGE_ITEMS[drop.id]
		var stack := ItemStack.new(Item.new(drop.id, spec[0], spec[1], spec[2]))
		WorldItemBus.item_dropped.emit(stack, drop.position + Vector2(0, 6))
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
	for trees in _loaded_trees.values():
		for tree in trees:
			if not tree.has_method("set_ripe_fruit"):
				continue
			if player_pixel.distance_to(tree.position) > FRUITING_DETAIL_RADIUS:
				continue
			var genome := _forage_scheduler.genome_for(tree.position)
			var state: Dictionary = _fruiting_model.state_at(genome, now, warmth)
			tree.set_ripe_fruit(int(state.get("ripe", 0)))

			var fallen: int = _fruiting_model.fallen_between(genome, _last_fruiting_time, now, warmth)
			if fallen > 0:
				var id := "fruit" if genome.species_bias >= 0.5 else "nut"
				var spec: Array = _FORAGE_ITEMS[id]
				var stack := ItemStack.new(Item.new(id, spec[0], spec[1], spec[2]), fallen)
				WorldItemBus.item_dropped.emit(stack, tree.position + Vector2(0, 8))
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
func current_weather(player_pixel: Vector2) -> String:
	var chunk_coord := _chunk_coord_for_tile(_world_tile_for_pixel(player_pixel))
	var day := int(_world_age_seconds / SeasonCycle.SECONDS_PER_YEAR * 48.0)  # ~48 weather-days/year
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


## Central, throttled tree spread: every SPREAD_INTERVAL of real time, a
## small bounded number of mature trees each attempt to plant a mutated-child
## sapling nearby (see TreeSpread) -- an immature sapling can't seed yet. A
## sapling that lands in a currently-loaded chunk is spawned immediately and
## recorded on that chunk's planted_trees (persisted across unload/reload,
## see _unload_chunk/_load_chunk) with the world-age it was planted at; one
## that lands outside any loaded chunk is simply not planted.
func step_tree_spread(delta_seconds: float) -> void:
	_world_age_seconds += delta_seconds

	_spread_accumulator += delta_seconds
	if _spread_accumulator < SPREAD_INTERVAL:
		return
	_spread_accumulator -= SPREAD_INTERVAL

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

		chunk.planted_trees.append({"position": position, "planted_at": _world_age_seconds})
		var tree := _tree_renderer.spawn_tree_at(_entities_parent, position)
		_loaded_trees[chunk_coord].append(tree)
	_spread_tick += 1


## How often the tall-grass sprite layer re-syncs to the simulation (and
## nearby herbivores get a chance to graze a patch). The sims themselves
## advance every call; only the node churn is throttled.
const GRASS_REFRESH_INTERVAL := 5.0

## Central tall-grass step (see TallGrass): every loaded chunk's grass sim
## grows/spreads, and on a throttled interval (1) any herbivore-role creature
## standing on a mature patch eats it, and (2) the tuft sprites are re-synced
## to the sim's patch set.
func step_tall_grass(delta_seconds: float) -> void:
	for sim in _grass_sims.values():
		sim.advance(delta_seconds)

	_grass_refresh_accumulator += delta_seconds
	if _grass_refresh_accumulator < GRASS_REFRESH_INTERVAL:
		return
	_grass_refresh_accumulator = 0.0

	_graze_by_herbivores()
	for chunk_coord in _grass_sims.keys():
		_sync_grass_sprites(chunk_coord)


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
				var fibre := ItemStack.new(
					Item.new("plant_fibre", "Plant Fibre", "material", 40), 2
				)
				WorldItemBus.item_dropped.emit(
					fibre,
					Vector2((tile.x + 0.5) * TerrainRenderer.TILE_SIZE, (tile.y + 0.5) * TerrainRenderer.TILE_SIZE)
				)
				_sync_grass_sprites(chunk_coord)
				return true
	return false


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


## Adds/removes tuft sprites so the rendered layer matches the sim's patch
## set; a growing patch is scaled by its growth so grass visibly rises.
func _sync_grass_sprites(chunk_coord: Vector2i) -> void:
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
		if not sprites.has(cell):
			var sprite := Sprite2D.new()
			sprite.texture = _grass_sprite_generator.generate_texture(
				hash("%d_%d_grass_tuft" % [origin.x + cell.x, origin.y + cell.y])
			)
			sprite.position = Vector2(
				(origin.x + cell.x + 0.5) * TerrainRenderer.TILE_SIZE,
				(origin.y + cell.y + 0.5) * TerrainRenderer.TILE_SIZE
			)
			_entities_parent.add_child(sprite)
			sprites[cell] = sprite
		sprites[cell].scale = Vector2.ONE * maxf(0.3, sim.get_growth(cell))


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


func _refresh_creatures() -> void:
	for chunk_coord in _loaded_chunks.keys():
		for creature in _loaded_creatures.get(chunk_coord, []):
			creature.free()
		_loaded_creatures[chunk_coord] = _creature_renderer.spawn_creatures(
			_creatures_parent,
			chunk_coord,
			chunk_coord * CHUNK_SIZE,
			CHUNK_SIZE,
			TerrainRenderer.TILE_SIZE,
			_ecosystem.herbivore_population(chunk_coord),
			_ecosystem.predator_population(chunk_coord),
			self
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
	return true


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
	chunk.planted_trees = _chunk_serializer.load_planted_trees(_planted_trees_path(chunk_coord))
	_loaded_chunks[chunk_coord] = chunk
	_terrain_renderer.paint(_tile_map_layer, chunk, chunk_coord * CHUNK_SIZE, generator.biome_at_global)
	_loaded_trees[chunk_coord] = _tree_renderer.spawn_trees(
		_entities_parent, chunk, chunk_coord * CHUNK_SIZE, TerrainRenderer.TILE_SIZE
	)
	for record in chunk.planted_trees:
		_loaded_trees[chunk_coord].append(_tree_renderer.spawn_tree_at(_entities_parent, record.position))

	_loaded_stones[chunk_coord] = _stone_renderer.spawn_stones(
		_entities_parent, chunk, chunk_coord * CHUNK_SIZE, TerrainRenderer.TILE_SIZE
	)

	_grass_sims[chunk_coord] = TallGrass.new(
		hash("%d_%d_tall_grass" % [chunk_coord.x, chunk_coord.y]), chunk.width, chunk.height, chunk.biome
	)
	_grass_sprites[chunk_coord] = {}
	_sync_grass_sprites(chunk_coord)

	_ecosystem.add_region(chunk_coord, chunk)
	_apply_ecology_catchup(chunk_coord)
	_loaded_creatures[chunk_coord] = _creature_renderer.spawn_creatures(
		_creatures_parent,
		chunk_coord,
		chunk_coord * CHUNK_SIZE,
		CHUNK_SIZE,
		TerrainRenderer.TILE_SIZE,
		_ecosystem.herbivore_population(chunk_coord),
		_ecosystem.predator_population(chunk_coord),
		self
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
	}
	var advanced: Dictionary = _ecology_catchup.advance(record["state"], elapsed, capacity)
	_ecosystem.seed_populations(chunk_coord, advanced["herbivores"], advanced["predators"])


func _unload_chunk(chunk_coord: Vector2i) -> void:
	var chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if chunk != null and not chunk.modifications.is_empty():
		DirAccess.make_dir_recursive_absolute(MODIFICATIONS_DIR)
		_chunk_serializer.save_modifications(chunk.modifications, _modifications_path(chunk_coord))
	if chunk != null and not chunk.planted_trees.is_empty():
		DirAccess.make_dir_recursive_absolute(PLANTED_TREES_DIR)
		_chunk_serializer.save_planted_trees(chunk.planted_trees, _planted_trees_path(chunk_coord))

	_terrain_renderer.erase(_tile_map_layer, CHUNK_SIZE, chunk_coord * CHUNK_SIZE)
	_loaded_chunks.erase(chunk_coord)

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

	# Snapshot the aggregate ecology before dropping the region, so revisiting
	# this chunk catch-up integrates from where it left off (see
	# _apply_ecology_catchup).
	if _ecosystem.has_region(chunk_coord):
		_unloaded_ecology[chunk_coord] = {
			"unloaded_at": _world_age_seconds,
			"state": {
				"herbivores": _ecosystem.herbivore_population(chunk_coord),
				"predators": _ecosystem.predator_population(chunk_coord),
				"fruit_stock": 0.0,
				"vegetation": _ecosystem.average_vegetation_density(chunk_coord),
			},
		}

	_ecosystem.remove_region(chunk_coord)
	for creature in _loaded_creatures.get(chunk_coord, []):
		creature.free()
	_loaded_creatures.erase(chunk_coord)


func _modifications_path(chunk_coord: Vector2i) -> String:
	return "%s/%d_%d.bin" % [MODIFICATIONS_DIR, chunk_coord.x, chunk_coord.y]


func _planted_trees_path(chunk_coord: Vector2i) -> String:
	return "%s/%d_%d.bin" % [PLANTED_TREES_DIR, chunk_coord.x, chunk_coord.y]


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
