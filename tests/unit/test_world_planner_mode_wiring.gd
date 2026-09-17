extends GutTest

## World's own planner-mode wiring (see ViewMode, BuildPlanLedger,
## docs/concept/planner_mode.md). A source-contract test on the function
## bodies rather than a live one -- the same shape and reasoning
## test_world_footstep_wiring.gd/test_world_crush_wiring.gd already use:
## _ready()/_client_process resolve multiplayer and the license gate
## internally, so standing up a whole World node headlessly to drive it is
## not worth the fight.

const ViewMode = preload("res://src/gameplay/view_mode.gd")


func _source() -> String:
	return FileAccess.get_file_as_string("res://scenes/world.gd")


func _function_body(function_name: String) -> String:
	var source := _source()
	var start := source.find("func %s" % function_name)
	assert_gt(start, -1, "the premise: %s must still exist" % function_name)
	var body_end := source.find("\nfunc ", start + 1)
	return source.substr(start, body_end - start)


func test_the_toggle_is_built_during_ready():
	assert_true(_function_body("_ready").contains("_build_view_mode_toggle()"))


## Asked directly: "a view toggle to the top besides the minimap". The
## minimap owns offset_left -170 .. -8 of the top-right corner (see
## world.tscn), so a toggle BESIDE it sits further left than its own left
## edge rather than under it -- under is where the karma card already is.
func test_the_toggle_sits_beside_the_minimap_not_under_it():
	var body := _function_body("_build_view_mode_toggle")
	assert_true(body.contains("PRESET_TOP_RIGHT"), "it belongs to the top-right corner column")
	assert_true(
		body.contains("offset_right = -178.0"),
		"its right edge must clear the minimap's own left edge (-170), i.e. beside it: %s" % body
	)


## The mode decides what is shown, and ViewMode is where that decision
## lives -- World must ASK it rather than carrying its own `if` over the
## same two cases, or the tested model and the real HUD can disagree.
func test_what_each_mode_shows_is_read_from_view_mode_not_reimplemented():
	var body := _function_body("_apply_view_mode")
	assert_true(body.contains("ViewMode.shows_hotbar("), "the hotbar's visibility comes from the model")
	assert_true(body.contains("ViewMode.shows_palette("), "and so does the palette's")
	assert_true(body.contains("ViewMode.toggle_label("), "and the button's own label")


## Pillar 4: the toggle changes what the player COMMANDS, never what the
## world DOES. Setting get_tree().paused here would make planner mode a
## pause screen, which it explicitly is not.
func test_toggling_the_mode_never_pauses_the_world():
	var body := _function_body("_toggle_view_mode")
	assert_false(body.contains("paused"), "planner mode is not a pause screen: %s" % body)


## Every placement goes through the ledger, which is what refuses
## overlapping and unbuildable ground -- a placement path that wrote
## straight to the world would bypass every refusal the model exists for.
func test_placing_a_blueprint_goes_through_the_ledger():
	var body := _function_body("_plan_blueprint_at")
	assert_true(body.contains("_build_plans.plan("), "the ledger owns what may be planned")
	assert_true(
		body.contains("is_buildable_terrain_at") or body.contains("_plan_ground_is_buildable"),
		"and it must be handed the world's own real buildability, not a stub"
	)


## Pillar 1: planning is not building. World must not lay terrain or spend
## anything on the placement path -- the whole design rests on this.
func test_planning_does_not_build_or_spend_anything():
	var body := _function_body("_plan_blueprint_at")
	for forbidden in ["build_at_global", "place_building", "spend", "remove_item"]:
		assert_false(
			body.contains(forbidden),
			"planning must not %s -- the cost falls when somebody raises it" % forbidden
		)


## A click on the map plants a blueprint -- but ONLY while planner mode has
## armed the cursor. The gate is the point: a stray left-click while
## swinging a sword in rpg mode must never plan a house, which is exactly
## why ViewMode.arms_build_cursor exists rather than the mode being checked
## ad hoc.
func test_a_click_plans_only_while_the_build_cursor_is_armed():
	var body := _function_body("_unhandled_input")
	assert_true(body.contains("_plan_blueprint_at("), "a click must reach the placement path")
	assert_true(
		body.contains("ViewMode.arms_build_cursor("),
		"and must be gated on the mode arming the cursor, not on the mode id directly"
	)
