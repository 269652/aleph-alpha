extends RefCounted

## How a planned site is drawn -- see docs/concept/planner_mode.md.
##
## Pure geometry and colour, with no Node2D of its own: PlanWireframeLayer
## is the thin node that actually draws, the same "pure model, thin Node"
## split this codebase uses everywhere a _draw/_process has real logic
## worth testing headlessly.
##
## ONE colour vocabulary serves both the footprint that follows the cursor
## and the wireframe it becomes once placed. They are the same thing a
## moment apart, and two palettes would make them read as different
## features.

## A laid-out site that is already placed and already legal. Deliberately
## neither of the cursor colours below: it is not a question being asked,
## it is an intention standing there -- so it reads as its own state
## rather than as a permanent "you may build here".
##
## Blueprint cyan, on the drafting-paper tradition the whole mode is named
## for.
const BuildPlan = preload("res://src/world/build_plan.gd")

const PLANNED_COLOR := Color(0.35, 0.75, 0.95, 0.70)

## The cursor's two answers. Different HUES, not one hue light and dark
## (pinned by test_allowed_and_refused_differ_in_hue_not_just_brightness):
## this is the only feedback the cursor gives, and a player who cannot
## tell the two apart gets none of it.
const ALLOWED_COLOR := Color(0.40, 0.90, 0.45, 0.70)
const REFUSED_COLOR := Color(0.95, 0.35, 0.30, 0.70)

## How much of the outline's own alpha the fill inside it keeps. The
## outline carries the shape; the fill only tints the ground enough to
## read as a region, because a wireframe you cannot see the ground through
## defeats the point of planning against the terrain.
const FILL_ALPHA_FRACTION := 0.28

## Pixels. Thin enough to sit on the tile grid it follows without
## swallowing it.
const OUTLINE_WIDTH := 1.5


## The world-space rectangle a footprint covers. Every footprint this game
## can plan is a rectangle of cells (BuildingCatalog.footprint_of is a
## Vector2i, and pavement is one cell), so the bounding rect is exact
## rather than an approximation of an irregular shape.
##
## An empty footprint -- what an unknown blueprint returns -- gives an
## empty Rect2 rather than a crash or a guessed tile.
static func world_rect(footprint_cells: Array, tile_size: int) -> Rect2:
	if footprint_cells.is_empty():
		return Rect2()
	var min_cell: Vector2i = footprint_cells[0]
	var max_cell: Vector2i = footprint_cells[0]
	for cell in footprint_cells:
		min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
		max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))
	var span := max_cell - min_cell + Vector2i.ONE
	return Rect2(Vector2(min_cell * tile_size), Vector2(span * tile_size))


## What the cursor's footprint should be drawn in, given the ledger's own
## refusal reason for that site.
##
## Takes the REASON rather than a bool on purpose: the ledger already
## computed it to show the player, so colouring from the same answer means
## the colour and the message can never disagree about whether a site is
## legal.
static func cursor_color(refusal_reason: String) -> Color:
	return ALLOWED_COLOR if refusal_reason.is_empty() else REFUSED_COLOR


## The fill that goes inside an outline of this colour.
static func fill_of(outline_color: Color) -> Color:
	return Color(outline_color.r, outline_color.g, outline_color.b, outline_color.a * FILL_ALPHA_FRACTION)


## Where a plan is drawn, in world pixels. A plan records a CHUNK and a
## local origin inside it (see BuildPlan), because that is what survives a
## chunk unload; turning that into world space is the one piece of real
## logic the drawing node would otherwise carry, so it lives here where a
## test can reach it without a viewport.
##
## An unknown blueprint draws nothing rather than a guessed tile, for the
## same reason BuildPlan.footprint_cells refuses to guess one.
static func plan_rect(plan, chunk_size: int, tile_size: int) -> Rect2:
	var global_origin: Vector2i = plan.chunk_coord * chunk_size + plan.origin
	return world_rect(BuildPlan.footprint_cells(plan.blueprint_id, global_origin), tile_size)
