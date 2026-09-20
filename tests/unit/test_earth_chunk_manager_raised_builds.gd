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
const ChunkEcologyCatchup = preload("res://src/world/chunk_ecology_catchup.gd")
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


## Real seconds of ONE builder's work this blueprint's own requirement asks
## for -- derived from the requirement and the rate rather than an eyeballed
## big number, so it cannot drift out of step with either.
func _builder_days() -> float:
	return ConstructionLabor.labor_hours_required(BLUEPRINT, _recipe_book) / ConstructionCatchup.HOURS_PER_BUILDER_PER_DAY


func _seconds_to_finish() -> float:
	return _builder_days() * EarthChunkManager.SECONDS_PER_SIMULATED_DAY


func _raise() -> ConstructionProject:
	return manager.begin_build_project(_chunk_coord, _origin, BLUEPRINT, "")


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
	var project := manager.begin_build_project(
		_chunk_coord, _origin, TerrainRenderer.ROAD_TILE_ID, ""
	)

	assert_true(manager.finish_build_project(project.id))

	var g := _global(_origin)
	assert_eq(manager.modification_at_global(g.x, g.y), TerrainRenderer.ROAD_TILE_ID)
	assert_eq(project.status, ConstructionProject.Status.COMPLETE)


func test_finishing_a_build_that_was_never_opened_is_a_no_op():
	assert_false(manager.finish_build_project("construction_project:nothing"))


# -- a raised build runs on the game's own clock ---------------------------
# Measured (tools/probe_raised_build.gd): a raised build inherited the
# ecology catch-up's own day/second rate, where one in-game HOUR of absence
# is one ecological day -- deliberate LOD for integrating vegetation and
# herds over an unloaded chunk, and 60x the day the player actually lives
# in. A small house is 2.25 builder-days, so at that rate the player stands
# at their own site for 8100 real seconds before anything finishes, and
# somebody who just paid a villager's wage watches nothing happen for two
# and a quarter hours. That is indistinguishable from the build being
# broken, which is exactly how it was reported.

func test_a_raised_build_is_worked_in_the_games_own_days():
	var project := _raise()

	manager.advance_hired_build(
		project.id, _builder_days() * EarthChunkManager.SECONDS_PER_SIMULATED_DAY,
		PlanRaising.HIRED_BUILDER_COUNT
	)

	assert_eq(
		project.status, ConstructionProject.Status.COMPLETE,
		"a builder's day is the game's own day -- the one the ecosystem step, the settlement step and the day/night cycle all already run on"
	)


## And not faster than that: the requirement is a real minimum-build-time
## floor, so most of a build's days must still leave it unfinished.
func test_most_of_the_work_still_leaves_it_unfinished():
	var project := _raise()

	manager.advance_hired_build(
		project.id, _builder_days() * EarthChunkManager.SECONDS_PER_SIMULATED_DAY * 0.5,
		PlanRaising.HIRED_BUILDER_COUNT
	)

	assert_eq(project.status, ConstructionProject.Status.IN_PROGRESS, "half the hours is half a house")


## A village's own construction and the offscreen catch-up keep the ecology
## rate they were tuned at -- the honest divergence named in
## docs/concept/planner_mode.md. Pinned so it is a decision rather than a
## drift: if the two ever have to agree, this test is what says so.
func test_the_settlements_own_construction_keeps_the_catchup_rate():
	assert_ne(
		ConstructionCatchup.SECONDS_PER_DAY, EarthChunkManager.SECONDS_PER_SIMULATED_DAY,
		"the premise: the two rates really are different"
	)
	assert_eq(ConstructionCatchup.SECONDS_PER_DAY, ChunkEcologyCatchup.SECONDS_PER_DAY)


# -- nothing stands in water -------------------------------------------------
# Reported live with the screenshot: "Buildings are placed in rivers".
#
# Measured first (tools/probe_buildings_in_water.gd): across 16 real villages
# founded near the reported spot, not ONE building stands in water -- every
# siting path already asks is_buildable_ground_at. What has no such check at
# all is place_building itself, which only refuses cells that are already
# modified, so any caller that forgets is free to put a house in a river, and
# a village whose river moved under it keeps the ones it has.

func test_a_building_cannot_be_placed_in_water():
	var wet = _first_water_cell()
	assert_not_null(wet, "precondition: this chunk really has water in it")
	var origin: Vector2i = wet - _chunk_coord * CHUNK_SIZE

	assert_false(
		manager.place_building(_chunk_coord, origin, "house_small"),
		"nothing built stands in water -- the rule the pieces already keep"
	)
	assert_true(manager.building_at_global(wet.x, wet.y).is_empty())


## And a building already standing in water is reclaimed, the same way a
## piece standing in water already is: a village whose river moved under it
## heals on its next visit rather than keeping a house in the current.
##
## Measured against its DOOR, which is the rule
## _reclaim_buildings_standing_in_water keeps: a house whose walls graze a
## newly-wet corner but whose entrance is still dry stays, because unlike a
## piece structure a building's interior is never the painted ground under
## it. A house in the middle of a river has its door in the river.
func test_a_building_already_standing_in_water_is_reclaimed_on_load():
	var wet = _first_water_cell()
	assert_not_null(wet, "precondition")
	var origin: Vector2i = wet - _chunk_coord * CHUNK_SIZE - BuildingCatalog.door_of("house_small")
	var chunk = manager._loaded_chunks[_chunk_coord]
	# Put one there the way an older save has one: written straight into the
	# chunk, past every siting rule.
	chunk.buildings[origin] = {
		"id": "house_small", "facing": Vector2i(0, 1), "seed": 1, "condition": 1.0,
		"progress": 1.0, "owner_household_id": "", "occupation": "", "resident_seed": 0,
	}
	chunk.modifications[origin] = "house_small"

	manager._unload_chunk(_chunk_coord)
	manager._load_chunk(_chunk_coord)

	assert_false(
		manager._loaded_chunks[_chunk_coord].buildings.has(origin),
		"a house the river took back is not still standing in it"
	)


## The first real water cell in this chunk, or null when it has none.
func _first_water_cell():
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			var g: Vector2i = _chunk_coord * CHUNK_SIZE + Vector2i(x, y)
			if manager.is_water_at_global(g.x, g.y):
				return g
	return null


# -- the site stands in the plot the house will stand in --------------------
#
# Reported live: *"The construction phase places the cottage at a different
# position than the finished cottage ... please align it so it doesn't jump
# that much"*.
#
# The house does NOT move, and that was measured before anything was
# changed. tools/probe_construction_alignment.gd: every stage and the
# finished sheet are bottom-anchored on the plot line and centred on it
# (content bottom 0.0 for all of them, 21x21 world units against 21x22).
# tools/probe_construction_jump.gd drove a real project to completion in a
# real village: "sites whose building landed exactly where the site stood:
# 1, sites whose building MOVED: 0".
#
# What jumps is the PLOT. A cottage now stands in one of nine drawn gardens
# (BuildingCatalog._BACKGROUND_SHEETS' cottage_bg_overlay) inside a drawn
# kerb, and a construction site had neither -- so the moment the roof went
# on, a whole 2x2 garden and its kerb appeared at once, and the thing's
# visible extent changed shape under the player's eye.
#
# The ground a building stands on belongs to the PLOT, not to the house: it
# is staked out before the walls go up and does not arrive with the roof.


func _site_children(node: Node2D) -> Array:
	var names: Array = []
	for child in node.get_children():
		names.append(child.name)
	return names


func test_a_construction_site_stands_in_the_same_plot_the_house_will():
	var project := _raise()
	manager.advance_hired_build(project.id, 1.0, PlanRaising.HIRED_BUILDER_COUNT)
	var site: Node2D = manager._construction_site_node_at(_chunk_coord, _origin)
	assert_not_null(site, "precondition: a site stands while the build rises")

	assert_true(
		_site_children(site).has("FootprintKerb"),
		"the plot is marked out from the start: %s" % str(_site_children(site))
	)
	assert_true(
		_site_children(site).has("Yard"),
		"a cottage's garden is its plot's, not its roof's: %s" % str(_site_children(site))
	)


## ...and the same plot, not merely a plot: the kerb and the yard sit where
## the finished building's own do, so nothing shifts when the roof goes on.
func test_the_sites_plot_is_where_the_finished_buildings_plot_is():
	var project := _raise()
	manager.advance_hired_build(project.id, 1.0, PlanRaising.HIRED_BUILDER_COUNT)
	var site: Node2D = manager._construction_site_node_at(_chunk_coord, _origin)
	assert_not_null(site)
	# Read off BEFORE the build completes: completing frees the site node,
	# and a reference held across it is a freed object, not a comparison.
	var site_position: Vector2 = site.position
	var site_kerb_position: Vector2 = (site.get_node("FootprintKerb") as Sprite2D).position
	var site_kerb_size: Vector2 = (site.get_node("FootprintKerb") as Sprite2D).texture.get_size()
	var site_yard_position: Vector2 = (site.get_node("Yard") as Sprite2D).position
	var site_yard_size: Vector2 = (site.get_node("Yard") as Sprite2D).texture.get_size()

	manager.advance_hired_build(
		project.id, _seconds_to_finish(), PlanRaising.HIRED_BUILDER_COUNT
	)
	var built: Node2D = _building_node_at(_origin)
	assert_not_null(built, "precondition: the building really stands there now")

	assert_eq(built.position, site_position, "the plot itself moved")
	var built_kerb: Sprite2D = built.get_node("FootprintKerb")
	assert_eq(built_kerb.position, site_kerb_position, "the kerb moved")
	assert_eq(built_kerb.texture.get_size(), site_kerb_size, "the kerb changed size")
	var built_yard: Sprite2D = built.get_node("Yard")
	assert_eq(built_yard.position, site_yard_position, "the yard moved")
	assert_eq(built_yard.texture.get_size(), site_yard_size, "the yard changed size")


## The same garden, not just the same size one -- a cottage whose garden
## changed the moment it was finished would jump just as visibly.
func test_the_site_and_the_finished_house_stand_in_the_same_garden():
	var project := _raise()
	manager.advance_hired_build(project.id, 1.0, PlanRaising.HIRED_BUILDER_COUNT)
	var site: Node2D = manager._construction_site_node_at(_chunk_coord, _origin)
	var site_yard: PackedByteArray = (
		(site.get_node("Yard") as Sprite2D).texture.get_image().get_data()
	)

	manager.advance_hired_build(
		project.id, _seconds_to_finish(), PlanRaising.HIRED_BUILDER_COUNT
	)
	var built: Node2D = _building_node_at(_origin)
	var built_yard: PackedByteArray = (
		(built.get_node("Yard") as Sprite2D).texture.get_image().get_data()
	)

	assert_true(site_yard == built_yard, "the garden changed when the roof went on")


## The node standing for a finished building at `origin_local`, or null.
func _building_node_at(origin_local: Vector2i) -> Node2D:
	var g: Vector2i = _global(origin_local)
	var expected := Vector2(g) * float(TerrainRenderer.TILE_SIZE)
	for child in entities_parent.get_children():
		if child.name != "Building":
			continue
		var footprint: Vector2i = BuildingCatalog.footprint_of(BLUEPRINT)
		var bottom_centre := expected + Vector2(
			float(footprint.x) * TerrainRenderer.TILE_SIZE * 0.5,
			float(footprint.y) * TerrainRenderer.TILE_SIZE
		)
		if (child as Node2D).position.is_equal_approx(bottom_centre):
			return child
	return null
