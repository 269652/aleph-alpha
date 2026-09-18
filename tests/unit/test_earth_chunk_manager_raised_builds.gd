extends GutTest

## What a RAISED wireframe actually produces (docs/concept/planner_mode.md's
## "From raised to raised" and "Work that is laid by hand").
##
## Planner mode's own raise path does not go through the settlement step: it
## opens a project itself and advances it itself (EarthChunkManager.
## advance_hired_build). So everything the settlement's own
## _advance_construction_labor does for a village's build -- draw the
## construction site while it rises, place the real building when the hours
## are in -- has to happen on this path too, or a raised plan is a ledger row
## and nothing else.
##
## Drives the REAL EarthChunkManager on a real chunk near Berlin, loaded via
## _load_chunk (see test_earth_chunk_manager.gd's own known-slow-file note);
## persisted files scrubbed before and after, since tests share one real
## user:// dir.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const ConstructionProject = preload("res://src/emergence/construction_project.gd")
const ConstructionLabor = preload("res://src/emergence/construction_labor.gd")
const ConstructionCatchup = preload("res://src/world/construction_catchup.gd")
const PlanRaising = preload("res://src/gameplay/plan_raising.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")

const CHUNK_SIZE := EarthChunkManager.CHUNK_SIZE
const BLUEPRINT := "house_small"

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _chunk_coord: Vector2i
var _origin: Vector2i  # LOCAL
## The same real recipe book the manager derives its own labour requirement
## from -- read here so a test's expectation comes from the recipe rather
## than from a number typed into the test.
var _recipe_book := CraftingRecipeBook.new()


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	var geo := GeoCoordinates.new()
	_chunk_coord = Vector2i(
		floori(float(geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES)) / float(CHUNK_SIZE)),
		floori(float(geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)) / float(CHUNK_SIZE)),
	)
	_scrub()
	manager._load_chunk(_chunk_coord)
	# The same clear-site rule a settlement's own build uses, asked of an
	# ordinary chunk: this file plans on open ground, not on a plaza.
	var found = manager._settlement_build_origin_for(_chunk_coord)
	assert_not_null(found, "precondition: this chunk offers a clear building site")
	_origin = found if found != null else Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2)


func after_each():
	_scrub()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _scrub() -> void:
	for path in [
		manager._modifications_path(_chunk_coord), manager._buildings_path(_chunk_coord),
		manager._roof_modifications_path(_chunk_coord), manager._furniture_modifications_path(_chunk_coord),
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _global(local: Vector2i) -> Vector2i:
	return _chunk_coord * CHUNK_SIZE + local


## Real seconds of ONE builder's work that comfortably clear this
## blueprint's own real requirement -- derived from the requirement and the
## catch-up's own hours-per-builder-per-day rate rather than an eyeballed
## big number, so it cannot drift out of step with either.
func _seconds_to_finish() -> float:
	var hours := ConstructionLabor.labor_hours_required(BLUEPRINT, _recipe_book)
	return hours / ConstructionCatchup.HOURS_PER_BUILDER_PER_DAY * ConstructionCatchup.SECONDS_PER_DAY * 1.2


func _raise() -> ConstructionProject:
	return manager.begin_hired_build_project(_chunk_coord, _origin, BLUEPRINT, "")


# -- the site rises while it is worked -------------------------------------

func test_a_raised_build_shows_a_construction_site_while_it_rises():
	var project := _raise()

	manager.advance_hired_build(project.id, 1.0, PlanRaising.HIRED_BUILDER_COUNT)

	var site: Node2D = manager._construction_site_node_at(_chunk_coord, _origin)
	assert_not_null(site, "a construction site stands on the plot while a raised build rises")
	assert_true(site.is_inside_tree())
	assert_gt(project.labor_hours_accumulated, 0.0, "and real hours went into it")


# -- completing places the building ----------------------------------------

func test_enough_hours_places_the_real_building_and_takes_the_site_down():
	var project := _raise()

	var outcome: Dictionary = manager.advance_hired_build(
		project.id, _seconds_to_finish(), PlanRaising.HIRED_BUILDER_COUNT
	)

	assert_eq(outcome.get("action", ""), "completed")
	assert_eq(project.status, ConstructionProject.Status.COMPLETE)
	var g := _global(_origin)
	assert_eq(
		manager.building_at_global(g.x, g.y).get("id", ""), BLUEPRINT,
		"a raised build that finished must really stand there, not just read COMPLETE in a ledger"
	)
	assert_null(manager._construction_site_node_at(_chunk_coord, _origin), "the site sprite is gone")


func test_a_raised_build_that_is_not_finished_yet_places_nothing():
	var project := _raise()

	manager.advance_hired_build(project.id, 1.0, PlanRaising.HIRED_BUILDER_COUNT)

	var g := _global(_origin)
	assert_true(manager.building_at_global(g.x, g.y).is_empty(), "not a real building yet")
	assert_eq(project.status, ConstructionProject.Status.IN_PROGRESS)


func test_advancing_a_build_that_was_never_opened_is_a_no_op():
	assert_eq(
		manager.advance_hired_build("construction_project:nothing", 1.0, 1.0).get("action", ""),
		"no_op"
	)


# -- work that is laid by hand ---------------------------------------------
# (planner_mode.md: pavement asks for zero labour hours, and
# advance_project_labor deliberately never completes a zero-hour
# requirement, so it is laid at once instead.)

func test_pavement_asks_for_no_labour_hours_at_all():
	assert_true(PlanRaising.is_laid_by_hand(
		ConstructionLabor.labor_hours_required(TerrainRenderer.ROAD_TILE_ID, _recipe_book)
	), "the premise: pavement is not a recipe, so its requirement is genuinely zero")


func test_finishing_a_pavement_build_really_lays_the_road():
	var project := manager.begin_hired_build_project(
		_chunk_coord, _origin, TerrainRenderer.ROAD_TILE_ID, ""
	)

	assert_true(manager.finish_build_project(project.id))

	var g := _global(_origin)
	assert_eq(manager.modification_at_global(g.x, g.y), TerrainRenderer.ROAD_TILE_ID)
	assert_eq(project.status, ConstructionProject.Status.COMPLETE)


func test_finishing_a_build_that_was_never_opened_is_a_no_op():
	assert_false(manager.finish_build_project("construction_project:nothing"))
