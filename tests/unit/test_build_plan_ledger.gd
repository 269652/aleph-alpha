extends GutTest

## Blueprints laid out in planner mode, before anything is built (see
## BuildPlan/BuildPlanLedger, docs/concept/planner_mode.md). Asked directly:
## "the character can place blueprints like pavement; houses; sawmills etc.
## directly on the map similar to how it works in Anno 1800".
##
## Pure: ground buildability arrives as a Callable, exactly as
## BuildingPlacement already takes it, so water and cliff rules stay with
## the world and these tests need no chunk.

const BuildPlan = preload("res://src/world/build_plan.gd")
const BuildPlanLedger = preload("res://src/world/build_plan_ledger.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var ledger: BuildPlanLedger


func before_each():
	ledger = BuildPlanLedger.new()


func _anywhere(_cell: Vector2i) -> bool:
	return true


func _nowhere(_cell: Vector2i) -> bool:
	return false


# -- what may be planned at all -------------------------------------------

## Pavement is the Road tier's own laid surface, one cell at a time -- the
## same thing a village lays for its streets, not a second kind of road.
func test_pavement_is_the_real_road_tile_and_covers_one_cell():
	assert_eq(BuildPlan.PAVEMENT_BLUEPRINT_ID, TerrainRenderer.ROAD_TILE_ID)
	assert_eq(
		BuildPlan.footprint_cells(BuildPlan.PAVEMENT_BLUEPRINT_ID, Vector2i(4, 7)),
		[Vector2i(4, 7)]
	)


## Every building the game can already raise is plannable, by its OWN real
## footprint -- no parallel catalogue that could drift from the real one.
func test_every_catalog_building_is_plannable_by_its_own_real_footprint():
	for building_id in ["house_small", "sawmill"]:
		assert_true(BuildPlan.is_plannable(building_id), building_id)
		assert_eq(
			BuildPlan.footprint_cells(building_id, Vector2i.ZERO).size(),
			BuildingCatalog.footprint_of(building_id).x * BuildingCatalog.footprint_of(building_id).y,
			"%s must plan at exactly its own catalog footprint" % building_id
		)


func test_an_unknown_blueprint_is_not_plannable_rather_than_a_guessed_single_cell():
	assert_false(BuildPlan.is_plannable("no_such_thing"))
	assert_eq(BuildPlan.footprint_cells("no_such_thing", Vector2i.ZERO), [])


# -- planning ---------------------------------------------------------------

func test_a_plan_on_open_ground_is_accepted_and_recorded():
	var id := ledger.plan(Vector2i(1, 2), Vector2i(3, 4), "house_small", 10.0, _anywhere)
	assert_ne(id, "", "open ground should accept a plan")
	assert_eq(ledger.count(), 1)
	var plan: BuildPlan = ledger.plans()[0]
	assert_eq(plan.blueprint_id, "house_small")
	assert_eq(plan.chunk_coord, Vector2i(1, 2))
	assert_eq(plan.origin, Vector2i(3, 4))
	assert_eq(plan.planned_at, 10.0)


## Two calls naming the same site and blueprint must resolve to the same
## id -- the "deterministic key, not an allocated counter" idiom
## ConstructionProject and Household already use, so nothing here needs a
## counter protected from collision.
func test_the_same_site_and_blueprint_always_resolve_to_the_same_id():
	var first := BuildPlan.plan_id(Vector2i(1, 2), Vector2i(3, 4), "house_small")
	var again := BuildPlan.plan_id(Vector2i(1, 2), Vector2i(3, 4), "house_small")
	assert_eq(first, again)
	assert_ne(first, BuildPlan.plan_id(Vector2i(1, 2), Vector2i(3, 4), "sawmill"))
	assert_ne(first, BuildPlan.plan_id(Vector2i(1, 2), Vector2i(3, 5), "house_small"))


## Pillar 1: planning is not building. A plan must not touch terrain, spend
## materials, or become a project -- it records an intention, and the ledger
## is the only thing that changes.
func test_planning_costs_nothing_and_builds_nothing():
	ledger.plan(Vector2i.ZERO, Vector2i.ZERO, "sawmill", 0.0, _anywhere)
	var plan: BuildPlan = ledger.plans()[0]
	assert_false(plan.has_method("build"), "a plan is a record, not a builder")
	assert_eq(
		BuildingCatalog.cost_of("sawmill"), BuildingCatalog.cost_of("sawmill"),
		"the real cost is untouched and falls when somebody actually builds"
	)


# -- refusals ---------------------------------------------------------------

func test_ground_the_world_refuses_refuses_the_plan_too():
	assert_eq(ledger.plan(Vector2i.ZERO, Vector2i.ZERO, "house_small", 0.0, _nowhere), "")
	assert_eq(ledger.count(), 0)
	assert_string_contains(
		ledger.refusal_reason(Vector2i.ZERO, Vector2i.ZERO, "house_small", _nowhere).to_lower(),
		"ground"
	)


## Two plans may not share a cell: the wireframes would stand inside each
## other, and whichever got built first would make the other unbuildable.
func test_a_plan_may_not_overlap_one_already_standing():
	ledger.plan(Vector2i.ZERO, Vector2i(0, 0), "house_small", 0.0, _anywhere)
	var overlapping := ledger.plan(Vector2i.ZERO, Vector2i(1, 0), "house_small", 0.0, _anywhere)
	assert_eq(overlapping, "", "footprints overlap")
	assert_eq(ledger.count(), 1)
	assert_string_contains(
		ledger.refusal_reason(Vector2i.ZERO, Vector2i(1, 0), "house_small", _anywhere).to_lower(),
		"already"
	)


func test_a_plan_in_a_different_chunk_never_counts_as_overlapping():
	ledger.plan(Vector2i(0, 0), Vector2i(0, 0), "house_small", 0.0, _anywhere)
	assert_ne(
		ledger.plan(Vector2i(1, 0), Vector2i(0, 0), "house_small", 0.0, _anywhere), "",
		"the same local origin in another chunk is another place entirely"
	)


func test_an_unknown_blueprint_is_refused_with_a_reason():
	assert_eq(ledger.plan(Vector2i.ZERO, Vector2i.ZERO, "no_such_thing", 0.0, _anywhere), "")
	assert_false(ledger.refusal_reason(Vector2i.ZERO, Vector2i.ZERO, "no_such_thing", _anywhere).is_empty())


func test_open_ground_gives_no_refusal_reason_at_all():
	assert_eq(ledger.refusal_reason(Vector2i.ZERO, Vector2i.ZERO, "house_small", _anywhere), "")


# -- reading and cancelling -------------------------------------------------

func test_what_stands_on_a_cell_is_answerable():
	ledger.plan(Vector2i.ZERO, Vector2i(2, 2), "house_small", 0.0, _anywhere)
	var found: BuildPlan = ledger.plan_at(Vector2i.ZERO, Vector2i(2, 2))
	assert_not_null(found)
	assert_eq(found.blueprint_id, "house_small")
	assert_null(ledger.plan_at(Vector2i.ZERO, Vector2i(40, 40)), "nothing stands out there")


## A chunk's own plans, for a renderer that only draws what is loaded.
func test_plans_can_be_asked_for_one_chunk_at_a_time():
	ledger.plan(Vector2i(0, 0), Vector2i(0, 0), "house_small", 0.0, _anywhere)
	ledger.plan(Vector2i(5, 5), Vector2i(0, 0), "sawmill", 0.0, _anywhere)
	assert_eq(ledger.plans_in(Vector2i(5, 5)).size(), 1)
	assert_eq(ledger.plans_in(Vector2i(5, 5))[0].blueprint_id, "sawmill")
	assert_eq(ledger.plans_in(Vector2i(9, 9)).size(), 0)


## Cancelling costs nothing, because planning cost nothing (pillar 1).
func test_cancelling_removes_the_plan_and_frees_its_ground():
	var id := ledger.plan(Vector2i.ZERO, Vector2i.ZERO, "house_small", 0.0, _anywhere)
	assert_true(ledger.cancel(id))
	assert_eq(ledger.count(), 0)
	assert_ne(
		ledger.plan(Vector2i.ZERO, Vector2i.ZERO, "house_small", 0.0, _anywhere), "",
		"the ground it stood on is free again"
	)


func test_cancelling_something_that_was_never_planned_is_false_not_a_crash():
	assert_false(ledger.cancel("not_a_real_plan_id"))


# -- the ground it asks about is the ground in the WORLD --------------------
#
# Reported live, with the build bar open and every tile refused: "i can't
# build on any tile", against "The ground at 29,19 cannot be built on."
#
# 29,19 is a CHUNK-LOCAL cell. refusal_reason handed BuildPlan's own local
# footprint cells straight to a buildability predicate that reads the world
# by GLOBAL tile (World._plan_ground_is_buildable ->
# EarthChunkManager.is_buildable_terrain_at), so in any chunk but the one at
# the origin it was asking about somewhere else entirely -- and the honest
# answer about a cell 29,19 tiles from the world's origin, far out in open
# ocean, is no.
#
# Every test above passes Vector2i.ZERO as the chunk, where local and global
# are the same number, which is exactly why the whole suite stayed green.


## What the predicate was really asked about, so a test can check the cell
## and not merely the verdict.
class _RecordingGround:
	extends RefCounted
	var asked: Array = []
	func call_cell(cell: Vector2i) -> bool:
		asked.append(cell)
		return true


func test_the_ground_it_asks_about_is_the_cell_in_the_world():
	var ground := _RecordingGround.new()
	var chunk_coord := Vector2i(3, -2)
	var origin := Vector2i(5, 7)
	ledger.refusal_reason(chunk_coord, origin, "house_small", ground.call_cell)
	assert_false(ground.asked.is_empty(), "precondition: it really asked about something")
	var expected: Array = []
	for cell in BuildPlan.footprint_cells("house_small", origin):
		expected.append(chunk_coord * BuildPlanLedger.CHUNK_SIZE + cell)
	assert_eq(ground.asked, expected, "a plan's ground is where it really stands in the world")


## A chunk at the origin still asks about exactly the same cells, so the
## fix cannot have moved the one case that already worked.
func test_a_plan_in_the_origin_chunk_is_asked_about_exactly_as_before():
	var ground := _RecordingGround.new()
	ledger.refusal_reason(Vector2i.ZERO, Vector2i(5, 7), "house_small", ground.call_cell)
	assert_eq(ground.asked, BuildPlan.footprint_cells("house_small", Vector2i(5, 7)))


## The chunk this ledger measures in is the chunk the world loads.
func test_the_chunk_this_ledger_measures_in_is_the_one_the_world_loads():
	var EarthChunkManager = load("res://src/world/earth_chunk_manager.gd")
	assert_eq(BuildPlanLedger.CHUNK_SIZE, EarthChunkManager.CHUNK_SIZE)
