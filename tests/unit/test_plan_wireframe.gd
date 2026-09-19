extends GutTest

## How a planned site is drawn -- both the standing wireframe and the
## footprint that follows the cursor (see PlanWireframe,
## docs/concept/planner_mode.md). Pure geometry and colour: no Node2D, no
## viewport, so every branch is reachable headlessly.
##
## One colour vocabulary deliberately serves both: the ghost under the
## cursor and the wireframe it becomes are the same thing a moment apart,
## and two palettes would make them look like different features.

const PlanWireframe = preload("res://src/rendering/plan_wireframe.gd")
const BuildPlan = preload("res://src/world/build_plan.gd")

const TILE := 16


func test_a_single_cell_covers_exactly_its_own_tile():
	var rect: Rect2 = PlanWireframe.world_rect([Vector2i(3, 5)], TILE)
	assert_eq(rect.position, Vector2(48, 80))
	assert_eq(rect.size, Vector2(16, 16))


## A real building footprint is a rectangle of cells, so its wireframe is
## the rectangle that bounds them -- exact, not an approximation.
func test_a_footprint_covers_all_of_its_cells():
	var cells := BuildPlan.footprint_cells("house_small", Vector2i(2, 2))
	var rect: Rect2 = PlanWireframe.world_rect(cells, TILE)
	for cell in cells:
		assert_true(
			rect.has_point(Vector2(cell.x * TILE + 1, cell.y * TILE + 1)),
			"cell %s must be inside the wireframe" % cell
		)
	assert_eq(rect.position, Vector2(32, 32), "anchored at the origin cell")


func test_an_empty_footprint_is_an_empty_rect_not_a_crash():
	assert_eq(PlanWireframe.world_rect([], TILE), Rect2())


# -- the colour vocabulary -------------------------------------------------

## The cursor says whether the thing under it may be placed, which is the
## entire feedback Anno's build cursor gives -- and the refusal REASON is
## already computed by the ledger, so the cursor colours itself from the
## same answer rather than asking a second question.
func test_the_cursor_is_allowed_when_there_is_no_refusal_and_refused_otherwise():
	assert_eq(PlanWireframe.cursor_color(""), PlanWireframe.ALLOWED_COLOR)
	assert_eq(
		PlanWireframe.cursor_color("The ground at 1,1 cannot be built on."),
		PlanWireframe.REFUSED_COLOR
	)


## Allowed and refused must not be told apart by brightness alone -- a
## player who cannot distinguish the two hues gets no feedback at all, and
## this is the one signal the whole cursor exists to give.
func test_allowed_and_refused_differ_in_hue_not_just_brightness():
	assert_gt(
		absf(PlanWireframe.ALLOWED_COLOR.h - PlanWireframe.REFUSED_COLOR.h), 0.15,
		"the two states must be different colours, not light and dark of one"
	)


## A standing wireframe is not a cursor state: it is already placed and
## already legal, so it reads as neither "you may" nor "you may not".
func test_a_standing_wireframe_has_its_own_colour():
	assert_ne(PlanWireframe.PLANNED_COLOR, PlanWireframe.ALLOWED_COLOR)
	assert_ne(PlanWireframe.PLANNED_COLOR, PlanWireframe.REFUSED_COLOR)


## Every colour here is drawn OVER the world, so none may be opaque -- a
## wireframe that hides the ground it stands on defeats the purpose of
## planning against the terrain.
func test_every_colour_lets_the_ground_show_through():
	for color in [PlanWireframe.PLANNED_COLOR, PlanWireframe.ALLOWED_COLOR, PlanWireframe.REFUSED_COLOR]:
		assert_lt(color.a, 1.0, "a wireframe you cannot see the ground through is not a wireframe")
		assert_gt(color.a, 0.0, "nor is an invisible one")


func test_the_fill_is_fainter_than_the_outline_it_sits_inside():
	assert_lt(
		PlanWireframe.fill_of(PlanWireframe.PLANNED_COLOR).a, PlanWireframe.PLANNED_COLOR.a,
		"the outline carries the shape; the fill only tints the ground"
	)


## A plan records a chunk and a LOCAL origin within it (see BuildPlan), but
## it is drawn in world space -- so this is the one piece of real logic the
## drawing node would otherwise carry, and it lives here where it can be
## tested without a viewport.
func test_a_plans_rect_is_placed_by_its_chunk_and_its_local_origin():
	var plan := BuildPlan.new(Vector2i(2, 0), Vector2i(3, 4), BuildPlan.PAVEMENT_BLUEPRINT_ID, 0.0)
	var rect: Rect2 = PlanWireframe.plan_rect(plan, 32, TILE)
	# chunk 2 starts at global cell 64, so the cell is 64+3 = 67 across.
	assert_eq(rect.position, Vector2(67 * TILE, 4 * TILE))
	assert_eq(rect.size, Vector2(TILE, TILE))


func test_a_plan_of_an_unknown_blueprint_draws_nothing():
	var plan := BuildPlan.new(Vector2i.ZERO, Vector2i.ZERO, "no_such_thing", 0.0)
	assert_eq(PlanWireframe.plan_rect(plan, 32, TILE), Rect2())
