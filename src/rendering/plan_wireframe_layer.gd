extends Node2D

## Draws the standing wireframes and the footprint under the cursor -- the
## thin Node half of PlanWireframe (see docs/concept/planner_mode.md).
##
## Deliberately holds no logic worth testing: every rectangle and every
## colour comes from PlanWireframe, which is pure and tested. All this does
## is iterate and call draw_rect, so there is nothing here a headless test
## could check that the model does not already pin.
##
## Sits on the ground-effects tier (z_index -1, the same tier GroundDecor,
## HillshadeFx and SnowFx already share): a blueprint outline lies flush
## with the floor like a chalk mark, and has no business interleaving with
## trees and creatures in Entities' own y-sort.

const PlanWireframe = preload("res://src/rendering/plan_wireframe.gd")

const GROUND_EFFECTS_Z_INDEX := -1

var _ledger
var _chunk_size := 32
var _tile_size := 16
var _cursor_rect := Rect2()
var _cursor_refusal := ""


func _init() -> void:
	z_index = GROUND_EFFECTS_Z_INDEX


func configure(ledger, chunk_size: int, tile_size: int) -> void:
	_ledger = ledger
	_chunk_size = chunk_size
	_tile_size = tile_size
	queue_redraw()


## The footprint under the cursor, and why it may not go there ("" when it
## may). Both arrive together because the colour is derived from the reason
## (see PlanWireframe.cursor_color) -- passing them separately would let
## the drawn colour and the shown message disagree.
func set_cursor(rect: Rect2, refusal_reason: String) -> void:
	_cursor_rect = rect
	_cursor_refusal = refusal_reason
	queue_redraw()


func clear_cursor() -> void:
	_cursor_rect = Rect2()
	_cursor_refusal = ""
	queue_redraw()


## Call whenever the ledger changed. A redraw request, not a redraw: Godot
## coalesces several in one frame, so planning a row of pavement costs one
## draw rather than one per cell.
func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	if _ledger != null:
		for plan in _ledger.plans():
			_draw_frame(PlanWireframe.plan_rect(plan, _chunk_size, _tile_size), PlanWireframe.PLANNED_COLOR)
	if _cursor_rect.has_area():
		_draw_frame(_cursor_rect, PlanWireframe.cursor_color(_cursor_refusal))


func _draw_frame(rect: Rect2, color: Color) -> void:
	if not rect.has_area():
		return
	draw_rect(rect, PlanWireframe.fill_of(color), true)
	draw_rect(rect, color, false, PlanWireframe.OUTLINE_WIDTH)
