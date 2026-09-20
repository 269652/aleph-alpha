extends GutTest

## A village raises its own town hall over time (docs/concept/
## civic_construction.md "Meeting Hall", building.md "City Hall over
## time"): the plaza reserved at founding (VillageLayout.skeleton's civic
## plot) is where EarthChunkManager._apply_civic_build_decision starts a
## real "city_hall" ConstructionProject on the settlement ledger once the
## village is big enough, has spare hands and has gathered the wood and
## stone; _advance_construction_labor grows it (a construction-site sprite
## from the sheet's row 0) and, complete, places the real whole-building
## City Hall on the plot with its doorstep still the street.
##
## Drives the REAL EarthChunkManager end to end on a real, hash-confirmed
## settlement chunk near Berlin (test_earth_chunk_manager_village_
## migration.gd's own finder, verbatim), loaded via _load_chunk (see
## test_earth_chunk_manager.gd's own known-slow-file note); persisted
## files scrubbed before and after, since tests share one real user:// dir.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const VillageLayout = preload("res://src/world/village_layout.gd")
const ConstructionProject = preload("res://src/emergence/construction_project.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")
const CivicBuildDecision = preload("res://src/emergence/civic_build_decision.gd")

const CHUNK_SIZE := EarthChunkManager.CHUNK_SIZE

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _chunk_coord: Vector2i
var _settlement_id: String
var _civic_origin: Vector2i  # LOCAL
var _civic_doorstep: Vector2i  # LOCAL

static var _cached_chunk_coord: Vector2i
static var _cached_chunk_coord_found := false

var _generator := SettlementGenerator.new()
var _biome_classifier := BiomeClassifier.new()


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	if not _cached_chunk_coord_found:
		_cached_chunk_coord = _find_settlement_chunk()
		_cached_chunk_coord_found = true
	_chunk_coord = _cached_chunk_coord
	_settlement_id = EntityRef.for_settlement(_chunk_coord)
	var plot: Dictionary = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(_chunk_coord))["civic_plot"]
	_civic_origin = plot["origin"]
	_civic_doorstep = plot["doorstep"]
	_scrub()
	manager._load_chunk(_chunk_coord)
	_clear_the_founded_hall(_chunk_coord)


## Founding now gives a village its civic seat outright
## (VillageRenderer._place_civic_if_missing): a village the player
## discovers has been standing for years. THIS file is about the other
## case -- a village that does not have one yet and raises it over real
## labour -- so it puts the plot back the way founding found it: lifts the
## hall and re-lays the square's paving underneath, which is exactly the
## state the plaza is in before any hall exists.
func _clear_the_founded_hall(coord: Vector2i) -> void:
	var origin: Vector2i = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(coord))["civic_plot"]["origin"]
	if not manager.remove_building(coord, origin):
		return
	var cells: Array = BuildingCatalog.footprint_cells("city_hall", origin)
	cells.append(origin + BuildingCatalog.doorstep_of("city_hall"))
	for local in cells:
		var g: Vector2i = coord * CHUNK_SIZE + local
		manager.build_at_global(g.x, g.y, TerrainRenderer.ROAD_TILE_ID)


func after_each():
	_scrub()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _scrub() -> void:
	_scrub_chunk(_chunk_coord)


## A real settlement chunk whose village actually laid its plaza -- a
## village whose square is water or forest gets no plaza and so no hall
## (honest, tested in test_village_layout.gd), and near Berlin's lakes that
## is most of them, so this file loads hash-confirmed candidates for real
## and keeps the first whose civic plot is reserved after the load
## (_civic_plot_origin_for), unloading and scrubbing every one that is
## not. A pre-load terrain scan (biome + water only; trees are not loaded
## yet) skips the hopeless candidates before paying for a real load.
func _find_settlement_chunk() -> Vector2i:
	var geo := GeoCoordinates.new()
	var center := Vector2i(
		floori(float(geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES)) / float(CHUNK_SIZE)),
		floori(float(geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)) / float(CHUNK_SIZE)),
	)
	var radius := 15
	var loads := 0
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var coord := center + Vector2i(dx, dy)
			if not _generator.has_settlement_at(coord, "grassland"):
				continue
			var chunk := manager.generator.generate_chunk(coord, CHUNK_SIZE)
			var dominant_biome: String = _biome_classifier.dominant_biome(chunk.biome)
			if not _generator.has_settlement_at(coord, dominant_biome):
				continue
			if not _plaza_terrain_is_open(coord):
				continue
			loads += 1
			_scrub_chunk(coord)
			manager._load_chunk(coord)
			_clear_the_founded_hall(coord)
			var plot_origin = manager._civic_plot_origin_for(coord)
			manager._unload_chunk(coord)
			_scrub_chunk(coord)
			if plot_origin != null:
				return coord
			if loads >= 12:
				break
	fail_test("no real settlement chunk that laid its plaza found within the scanned neighborhood")
	return Vector2i.ZERO


func _plaza_terrain_is_open(coord: Vector2i) -> bool:
	var plaza: Rect2i = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(coord))["plaza"]
	for y in range(plaza.position.y, plaza.end.y):
		for x in range(plaza.position.x, plaza.end.x):
			var g := coord * CHUNK_SIZE + Vector2i(x, y)
			if not manager.is_buildable_terrain_at(g.x, g.y):
				return false
	return true


func _scrub_chunk(coord: Vector2i) -> void:
	for path in [
		manager._modifications_path(coord), manager._buildings_path(coord),
		manager._roof_modifications_path(coord), manager._furniture_modifications_path(coord),
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _global(local: Vector2i) -> Vector2i:
	return _chunk_coord * CHUNK_SIZE + local


func _tile(local: Vector2i) -> String:
	var g := _global(local)
	return manager.modification_at_global(g.x, g.y)


func _stock_the_hall() -> void:
	var market = manager.market_store().market_for(_settlement_id)
	market.add_stock("wood", 40.0)
	market.add_stock("stone", 20.0)


func _hall_project():
	return manager.construction_project_store().find_project(_chunk_coord, _civic_origin, "city_hall")


# -- the reserved plot ---------------------------------------------------------

func test_the_founded_village_laid_its_plaza_and_reserved_the_civic_plot():
	assert_false(manager.buildings_in_chunk(_chunk_coord).is_empty(), "precondition: a real village")
	assert_eq(_tile(_civic_doorstep), TerrainRenderer.ROAD_TILE_ID, "the hall's doorstep is the street")
	for cell in BuildingCatalog.footprint_cells("city_hall", _civic_origin):
		assert_eq(_tile(cell), TerrainRenderer.ROAD_TILE_ID, "the plot is the paved square itself: %s" % cell)
	assert_eq(manager._civic_plot_origin_for(_chunk_coord), _civic_origin)


func test_the_civic_plot_is_not_offered_once_something_else_stands_on_it():
	var g := _global(_civic_origin + Vector2i(1, 1))
	manager._loaded_chunks[_chunk_coord].modifications.erase(_civic_origin + Vector2i(1, 1))
	manager.build_at_global(g.x, g.y, "campfire")
	assert_null(manager._civic_plot_origin_for(_chunk_coord))


## A founded village is big enough (SettlementGenerator.POPULATION
## villagers, each a household) -- the threshold itself is pinned in
## test_civic_build_decision.gd; here the wiring: with nothing gathered
## yet the plan waits, nothing starts and nothing is drawn.
func test_an_unstocked_village_plans_but_does_not_start():
	assert_gte(
		manager.household_count_for_settlement(_settlement_id), CivicBuildDecision.CITY_HALL_MIN_HOUSEHOLDS,
		"precondition: a founded village is big enough (POPULATION %d)" % SettlementGenerator.POPULATION
	)
	manager._apply_civic_build_decision(_chunk_coord)
	var project = _hall_project()
	assert_true(project == null or project.status == ConstructionProject.Status.PLANNED, "no stock, no start")
	assert_true(manager.building_at_global(_global(_civic_origin).x, _global(_civic_origin).y).is_empty())


# -- the hall rises on the settlement ledger ----------------------------------

func test_a_stocked_village_starts_the_hall_on_its_civic_plot():
	_stock_the_hall()

	manager._apply_civic_build_decision(_chunk_coord)

	var project = _hall_project()
	assert_not_null(project, "a real project on the civic plot")
	assert_eq(project.status, ConstructionProject.Status.IN_PROGRESS)
	assert_eq(project.household_id, _settlement_id, "the settlement's own commons")
	var market = manager.market_store().market_for(_settlement_id)
	assert_almost_eq(market.stock.get("wood", 0.0), 20.0, 0.001, "wood drawn from the village market")
	assert_almost_eq(market.stock.get("stone", 0.0), 10.0, 0.001)


func test_the_settlement_step_is_what_starts_it():
	_stock_the_hall()
	var household_ids := manager._households_in_settlement(_settlement_id)

	manager._step_settlement_construction(_settlement_id, household_ids)

	var project = _hall_project()
	assert_not_null(project)
	assert_eq(project.status, ConstructionProject.Status.IN_PROGRESS)


func test_a_started_hall_shows_a_construction_site_that_advances_with_labour():
	_stock_the_hall()
	manager._apply_civic_build_decision(_chunk_coord)

	manager._advance_construction_labor(_chunk_coord, 1.0)

	var site: Node2D = manager._construction_site_node_at(_chunk_coord, _civic_origin)
	assert_not_null(site, "a construction site stands on the plot while the hall is built")
	assert_true(site.is_inside_tree())
	var footprint_px := Vector2(BuildingCatalog.footprint_of("city_hall")) * TerrainRenderer.TILE_SIZE
	var expected := Vector2(_global(_civic_origin)) * TerrainRenderer.TILE_SIZE + Vector2(footprint_px.x * 0.5, footprint_px.y)
	assert_almost_eq(site.position.x, expected.x, 0.01)
	assert_almost_eq(site.position.y, expected.y, 0.01, "anchored at the footprint's bottom centre like a building")
	assert_true(manager.building_at_global(_global(_civic_origin).x, _global(_civic_origin).y).is_empty(), "not a real hall yet")


func test_enough_labour_places_the_real_hall_with_its_doorstep_still_paved():
	_stock_the_hall()
	manager._apply_civic_build_decision(_chunk_coord)

	manager._advance_construction_labor(_chunk_coord, 1.0e6)

	var record := manager.building_at_global(_global(_civic_origin).x, _global(_civic_origin).y)
	assert_eq(record.get("id", ""), "city_hall", "a real whole-building City Hall stands on the plaza")
	assert_eq(record.get("origin_local", Vector2i(-1, -1)), _civic_origin)
	assert_eq(_tile(_civic_doorstep), TerrainRenderer.ROAD_TILE_ID, "the doorstep is still the street")
	assert_eq(_hall_project().status, ConstructionProject.Status.COMPLETE)
	assert_null(manager._construction_site_node_at(_chunk_coord, _civic_origin), "the site sprite is gone")


func test_a_standing_hall_is_found_by_the_demands_query_and_never_started_twice():
	_stock_the_hall()
	manager._apply_civic_build_decision(_chunk_coord)
	manager._advance_construction_labor(_chunk_coord, 1.0e6)
	var centre := _global(Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2))

	assert_false(manager.city_hall_demands_near(centre.x, centre.y).is_empty(), "the hall convenes")
	_stock_the_hall()
	manager._apply_civic_build_decision(_chunk_coord)
	var market = manager.market_store().market_for(_settlement_id)
	assert_almost_eq(market.stock.get("wood", 0.0), 60.0, 0.001, "nothing drawn for a second hall")


func test_labour_waits_while_the_plot_is_blocked():
	_stock_the_hall()
	manager._apply_civic_build_decision(_chunk_coord)
	var blocker := _global(_civic_origin + Vector2i(1, 1))
	manager._loaded_chunks[_chunk_coord].modifications.erase(_civic_origin + Vector2i(1, 1))
	manager.build_at_global(blocker.x, blocker.y, "campfire")

	manager._advance_construction_labor(_chunk_coord, 1.0e6)

	assert_eq(_hall_project().status, ConstructionProject.Status.IN_PROGRESS, "the crew waits for the plot")
	assert_true(manager.building_at_global(_global(_civic_origin).x, _global(_civic_origin).y).is_empty())


func test_the_placed_hall_survives_a_reload_without_a_second_overlay_sprite():
	_stock_the_hall()
	manager._apply_civic_build_decision(_chunk_coord)
	manager._advance_construction_labor(_chunk_coord, 1.0e6)

	manager._unload_chunk(_chunk_coord)
	manager._load_chunk(_chunk_coord)

	var g := _global(_civic_origin)
	assert_eq(manager.building_at_global(g.x, g.y).get("id", ""), "city_hall")
	var by_cell: Dictionary = manager._structure_art_sprites.get(_chunk_coord, {})
	assert_false(by_cell.has(_civic_origin), "no legacy single-tile overlay art on top of the real building node")


func test_the_direct_builder_gate_measures_to_the_halls_footprint():
	_stock_the_hall()
	manager._apply_civic_build_decision(_chunk_coord)
	manager._advance_construction_labor(_chunk_coord, 1.0e6)
	# One cell past the footprint's far (east) edge: 4 tiles from the anchor,
	# 1 tile from the nearest footprint cell.
	var beside := _global(_civic_origin + Vector2i(BuildingCatalog.footprint_of("city_hall").x, 1))
	assert_true(manager.has_structure_near(beside.x, beside.y, "city_hall", 1))
	var far := _global(_civic_origin + Vector2i(BuildingCatalog.footprint_of("city_hall").x + 2, 1))
	assert_false(manager.has_structure_near(far.x, far.y, "city_hall", 1))


# -- a village the player is watching builds on the clock they live in ------
# Measured (tools/probe_village_growth.gd): a real village grew from 10
# households to 31 while raising two houses, because its LIVE construction
# was integrated in ConstructionCatchup's own day -- the deliberately
# conservative rate for advancing an UNLOADED chunk across an absence, and
# sixty times the day the player actually lives in. A village standing in
# front of the player is not an absence.

const ConstructionCatchup = preload("res://src/world/construction_catchup.gd")
const ConstructionLabor = preload("res://src/emergence/construction_labor.gd")


func test_a_loaded_village_builds_on_the_games_own_day():
	_stock_the_hall()
	manager._apply_civic_build_decision(_chunk_coord)
	var project = _hall_project()
	assert_not_null(project, "precondition: the hall really was started")

	manager._step_settlement_construction(
		_settlement_id, manager._households_in_settlement(_settlement_id)
	)

	# One settlement step of one builder is this many hours on each clock.
	# Read off both rates rather than typed in, so neither can drift.
	var step: float = EarthChunkManager.SETTLEMENT_STEP_INTERVAL
	var on_the_games_day := step / EarthChunkManager.SECONDS_PER_SIMULATED_DAY * ConstructionCatchup.HOURS_PER_BUILDER_PER_DAY
	var on_the_catchup_day := step / ConstructionCatchup.SECONDS_PER_DAY * ConstructionCatchup.HOURS_PER_BUILDER_PER_DAY
	# At least ONE builder's worth on the game's day. The village's real crew
	# is several, so on the catch-up day the same step earns a small fraction
	# of one builder-day and lands far below this -- which is exactly the
	# difference being pinned, and why the comparison is against one builder
	# rather than against the crew (whose size these tests do not fix).
	assert_gte(
		project.labor_hours_accumulated, on_the_games_day,
		"a village in front of the player is not an absence to be integrated over"
	)
	assert_gt(on_the_games_day, on_the_catchup_day, "the premise: the two clocks really differ")
	assert_lte(
		project.labor_hours_accumulated,
		on_the_games_day * float(maxi(manager._households_in_settlement(_settlement_id).size(), 1)) + 0.001,
		"and no faster than its own real crew on that day"
	)


# -- somebody is working on it (docs/concept/building.md) -------------------
#
# Asked for directly, watching a village raise a cottage: *"the
# construction site should show a builder working on it"*. The labour is
# real -- a settlement spends its own spare hands against the project's
# required hours -- so the builder is that number made visible, present
# exactly while the work is.

const ConstructionWorkerMarker = preload("res://src/rendering/construction_worker_marker.gd")


func _builder_at(origin_local: Vector2i):
	return manager._construction_site_workers.get(_chunk_coord, {}).get(origin_local)


func test_a_site_being_worked_shows_a_builder_on_it():
	_stock_the_hall()
	manager._apply_civic_build_decision(_chunk_coord)

	manager._advance_construction_labor(_chunk_coord, 1.0)

	var builder = _builder_at(_civic_origin)
	assert_not_null(builder, "a hall going up has somebody building it")
	if builder == null:
		return
	assert_true(builder is ConstructionWorkerMarker)
	assert_true(builder.is_inside_tree(), "and he is really in the world")
	var footprint := BuildingCatalog.footprint_of("city_hall")
	var plot := Rect2(
		Vector2(_global(_civic_origin)) * TerrainRenderer.TILE_SIZE,
		Vector2(footprint) * TerrainRenderer.TILE_SIZE
	)
	assert_true(plot.has_point(builder.position), "he stands on the site itself, not beside it")
	assert_eq(builder.plot, plot, "and the plot he works is the footprint")


## The other half: a site nobody has hands for shows nobody. A figure
## standing over a project that has not moved in a week is a lie.
func test_a_site_nobody_has_hands_for_shows_no_builder():
	_stock_the_hall()
	manager._apply_civic_build_decision(_chunk_coord)
	manager._advance_construction_labor(_chunk_coord, 1.0)
	assert_not_null(_builder_at(_civic_origin), "precondition: somebody was working")

	manager._sync_construction_worker(_chunk_coord, _hall_project(), 0.0)

	assert_null(_builder_at(_civic_origin), "no spare hands, no builder")


func test_the_builder_goes_when_the_hall_is_finished():
	_stock_the_hall()
	manager._apply_civic_build_decision(_chunk_coord)
	manager._advance_construction_labor(_chunk_coord, 1.0)
	assert_not_null(_builder_at(_civic_origin), "precondition: somebody was working")

	manager._advance_construction_labor(_chunk_coord, 1.0e6)

	assert_null(_builder_at(_civic_origin), "a finished hall has no site and no builder")


func test_unloading_the_chunk_takes_the_builder_with_it():
	_stock_the_hall()
	manager._apply_civic_build_decision(_chunk_coord)
	manager._advance_construction_labor(_chunk_coord, 1.0)
	assert_not_null(_builder_at(_civic_origin), "precondition: somebody was working")

	manager._unload_chunk(_chunk_coord)

	assert_null(_builder_at(_civic_origin), "a worker cannot outlive the chunk he works in")
