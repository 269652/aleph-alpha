extends SceneTree

## Throwaway probe: drive a RAISED wireframe the whole way through, the way
## World's own _step_player_builds does (docs/concept/planner_mode.md), and
## print what really happens tick by tick -- so "building it yourself works"
## is a measurement rather than a claim.
##
## Mirrors the step's arithmetic exactly, including the global-cell reach
## test, because that conversion (plan.chunk_coord * CHUNK_SIZE + origin) is
## the part a unit test on the pure rule cannot catch getting wrong.

const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const PlanRaising = preload("res://src/gameplay/plan_raising.gd")
const BuildPlan = preload("res://src/world/build_plan.gd")
const BuildPlanLedger = preload("res://src/world/build_plan_ledger.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const ConstructionProject = preload("res://src/emergence/construction_project.gd")

const BLUEPRINT := "house_small"
const TICK_SECONDS := 5.0
const TICKS := 60


func _initialize() -> void:
	var EarthChunkManager = load("res://src/world/earth_chunk_manager.gd")
	var tile_map_layer := TileMapLayer.new()
	var entities := Node2D.new()
	var creatures := Node2D.new()
	root.add_child(tile_map_layer)
	root.add_child(entities)
	root.add_child(creatures)
	var manager = EarthChunkManager.new(tile_map_layer, entities, creatures)

	var geo := GeoCoordinates.new()
	var size: int = EarthChunkManager.CHUNK_SIZE
	var coord := Vector2i(
		floori(float(geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES)) / float(size)),
		floori(float(geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)) / float(size)),
	)
	manager._load_chunk(coord)
	var origin = manager._settlement_build_origin_for(coord)
	if origin == null:
		print("no clear site in this chunk")
		quit(1)
		return

	var ledger := BuildPlanLedger.new()
	var buildable := func(cell: Vector2i) -> bool:
		return manager.is_buildable_terrain_at(cell.x, cell.y)
	print("PLAN house reason=%s" % ledger.plan(coord, origin, BLUEPRINT, 0.0, buildable))
	var road_origin: Vector2i = origin + Vector2i(0, 6)
	print("PLAN road  reason=%s" % ledger.plan(
		coord, road_origin, BuildPlan.PAVEMENT_BLUEPRINT_ID, 0.0, buildable
	))

	# -- pavement: raised, and laid on the spot --------------------------------
	var road = manager.begin_build_project(coord, road_origin, BuildPlan.PAVEMENT_BLUEPRINT_ID, "")
	var road_hours: float = manager.build_labor_hours_for(BuildPlan.PAVEMENT_BLUEPRINT_ID)
	print("ROAD hours=%.1f laid_by_hand=%s" % [road_hours, PlanRaising.is_laid_by_hand(road_hours)])
	if PlanRaising.is_laid_by_hand(road_hours):
		manager.finish_build_project(road.id)
	var road_global: Vector2i = coord * size + road_origin
	print("ROAD tile=%s status=%d" % [
		manager.modification_at_global(road_global.x, road_global.y), road.status
	])

	# -- the house: the player's own hours, and only at the site ----------------
	var project = manager.begin_build_project(coord, origin, BLUEPRINT, "")
	var required: float = manager.build_labor_hours_for(BLUEPRINT)
	var site_cells: Array = BuildPlan.footprint_cells(BLUEPRINT, coord * size + origin)
	var at_site: Vector2i = site_cells[0]
	var far_away: Vector2i = at_site + Vector2i(40, 40)
	print("HOUSE required_hours=%.1f site=%s" % [required, at_site])

	var away_ticks := 10
	for tick in TICKS:
		var standing: Vector2i = far_away if tick < away_ticks else at_site
		var builders: float = PlanRaising.builders_at_site(standing, site_cells)
		var outcome: Dictionary = manager.advance_hired_build(project.id, TICK_SECONDS, builders)
		var site_node = manager._construction_site_node_at(coord, origin)
		if tick == away_ticks - 1 or tick % 10 == 0 or outcome.get("action", "") == "completed":
			print("  t=%3d standing=%s builders=%.1f hours=%6.2f action=%s site=%s" % [
				tick, "away" if standing == far_away else "at site", builders,
				project.labor_hours_accumulated, outcome.get("action", ""),
				"up" if site_node != null else "-"
			])
		if outcome.get("action", "") == "completed":
			break

	var g: Vector2i = coord * size + origin
	print("HOUSE status=%d building=%s site=%s" % [
		project.status, manager.building_at_global(g.x, g.y).get("id", ""),
		"up" if manager._construction_site_node_at(coord, origin) != null else "-"
	])
	quit(0)
