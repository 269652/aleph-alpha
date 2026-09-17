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


## The offered wage must clear the minimum any villager will take, or
## hiring refuses for a reason the player can neither see nor fix. Both are
## tuned values, so the relationship between them is pinned rather than
## asserted in a comment (CLAUDE.md).
func test_the_offered_wage_clears_the_minimum():
	var source := _source()
	var offered := _constant_value(source, "BUILDER_WAGE")
	var minimum := _constant_value(source, "BUILDER_MINIMUM_WAGE")
	assert_gt(minimum, 0.0, "a minimum of zero would make the wage check meaningless")
	assert_gte(offered, minimum, "the player's own offer must be one a villager would take")


func _constant_value(source: String, name: String) -> float:
	var marker := "const %s := " % name
	var start := source.find(marker)
	assert_gt(start, -1, "%s must still exist" % name)
	var line_end := source.find("\n", start)
	return float(source.substr(start + marker.length(), line_end - start - marker.length()))


## Raising a wireframe must open the SAME kind of project a village build
## opens, not a parallel one -- and must take the plan down, or a blueprint
## would be drawn over its own building.
func test_raising_opens_a_real_project_and_clears_the_plan():
	var body := _function_body("_open_raising_project")
	assert_true(body.contains("start_build_project("), "a real ConstructionProject, not a parallel record")
	assert_true(body.contains("_build_plans.cancel("), "the wireframe is done once it is a project")
	assert_true(body.contains("_build_plan_store.save("), "and that must survive a reload")


## Hiring reads the live trust value, which is the whole point of
## NpcTrustStore existing -- a hard-coded trust would make the gate
## decorative.
func test_hiring_reads_the_live_trust_value():
	var body := _function_body("_raise_plan_within_reach")
	assert_true(body.contains("_npc_trust.trust_of("), "the villager's own opinion of the player")
	assert_true(body.contains("PlanRaising.can_hire_builder("), "through the shared gate")


## Trust is earned by talking, which is the only thing that raises it --
## otherwise nobody would ever become hireable and the gate would refuse
## forever.
func test_talking_is_what_earns_trust():
	assert_true(_function_body("_on_talk_pressed").contains("_npc_trust.record_conversation("))


## The wage really moves before the job is taken. A villager who was never
## paid must not end up working, and a player who cannot afford the wage
## must be told rather than quietly getting free labour.
func test_the_wage_is_paid_before_the_job_is_taken():
	var body := _function_body("_raise_plan_within_reach")
	assert_true(body.contains("WagePayment.pay("), "gold really moves")
	assert_true(
		body.contains("household_wallet_for_villager("),
		"into the villager's own household purse, not nowhere"
	)
	var paid_at := body.find("WagePayment.pay(")
	var hired_at := body.find("_open_raising_project(plan, PlanRaising.Labour.HIRED)")
	assert_gt(hired_at, -1, "the premise: hiring still opens a project")
	assert_lt(paid_at, hired_at, "payment must come before the job is taken, not after")


## docs/concept/building.md retired the instant hire fork on purpose: "a
## build the player cannot do themselves says that hiring returns with
## construction-over-time". A hired build must therefore accrue labour,
## never spawn a finished building.
func test_a_hired_build_accrues_labour_rather_than_being_spawned():
	var body := _function_body("_step_hired_builds")
	assert_true(body.contains("advance_hired_build("), "hours are added over time")
	assert_false(body.contains("stamp_"), "nothing is stamped into existence")
	assert_true(body.contains("world_age_seconds()"), "measured against the world clock")


## One clock, read -- never a second one accumulated per frame that has to
## be kept in step with it. It is why a /season leap does not leave a
## half-built house frozen.
func test_hired_builds_are_advanced_from_the_world_clock_not_a_frame_delta():
	var body := _function_body("_step_hired_builds")
	assert_false(body.contains("delta"), "a frame delta would be a second clock: %s" % body)


func test_hired_builds_are_stepped_with_the_other_slow_world_systems():
	assert_true(_function_body("_step_ecology_batch").contains("_step_hired_builds()"))
