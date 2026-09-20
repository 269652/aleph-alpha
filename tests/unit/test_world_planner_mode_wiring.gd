extends GutTest

## World's own planner-mode wiring (see ViewMode, BuildPlanLedger,
## docs/concept/planner_mode.md). A source-contract test on the function
## bodies rather than a live one -- the same shape and reasoning
## test_world_footstep_wiring.gd/test_world_crush_wiring.gd already use:
## _ready()/_client_process resolve multiplayer and the license gate
## internally, so standing up a whole World node headlessly to drive it is
## not worth the fight.

const ViewMode = preload("res://src/gameplay/view_mode.gd")
const World = preload("res://scenes/world.gd")
const Keybindings = preload("res://src/gameplay/keybindings.gd")


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
	# The premise changed with the switch (docs/concept/hud.md "The planner
	# toggle is a switch"): the caption used to be derived from the mode
	# (ViewMode.toggle_label, reading "Planner Mode" while you were in RPG
	# mode). It is a CONSTANT now, because the switch carries the state -- so
	# what _apply_view_mode must read from the model is the switch's POSITION,
	# and shows_palette above is that same read.
	assert_true(
		body.contains("ViewMode.SWITCH_LABEL"),
		"the caption is the model's constant, not a second copy of the word"
	)
	assert_false(
		body.contains("ViewMode.toggle_label("),
		"a switch's caption must not change with the mode -- the switch shows it"
	)
	assert_true(
		body.contains("_view_mode_switch.set_on("),
		"the switch has to follow a mode flipped by a keypress, not only by a click"
	)


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
	# begin_build_project IS start_build_project with the status a raised
	# build opens at (see EarthChunkManager) -- the same idempotent-by-site
	# ConstructionProjectStore.start_project every village build goes
	# through, never a parallel record.
	assert_true(body.contains("begin_build_project("), "a real ConstructionProject, not a parallel record")
	assert_true(body.contains("_build_plans.cancel("), "the wireframe is done once it is a project")
	assert_true(body.contains("_build_plan_store.save("), "and that must survive a reload")


## Hiring reads the live trust value, which is the whole point of
## NpcTrustStore existing -- a hard-coded trust would make the gate
## decorative.
func test_hiring_reads_the_live_trust_value():
	var body := _function_body("_hire_builder_for_plan")
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
	var body := _function_body("_hire_builder_for_plan")
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


# -- building it yourself ---------------------------------------------------
# (docs/concept/planner_mode.md's "Who supplies the hours". The player path
# used to open a PLANNED project, which advance_project_labor no-ops on, and
# nothing advanced it -- so "Raising it yourself" took the wireframe down and
# then nothing ever happened.)

## Both ways open the project already under way, because
## advance_project_labor only advances an IN_PROGRESS one -- a build that
## says it started and then silently never happens is worse than one that
## refuses.
func test_both_ways_open_a_project_that_is_already_under_way():
	var body := _function_body("_open_raising_project")
	assert_true(body.contains("begin_build_project("), "opened IN_PROGRESS, whoever is paying")
	assert_false(
		body.contains("PlanRaising.Labour.HIRED"),
		"nothing about the two ways differs here any more: %s" % body
	)


## Pillar 5: the player's hours are their own time AT THE SITE, so they
## accrue only while the player stands within the same reach that offered
## them the wireframe. Walk away and the work stops where it stands.
func test_your_own_hours_only_accrue_while_you_stand_at_the_site():
	var body := _function_body("_step_player_builds")
	assert_true(body.contains("PlanRaising.builders_at_site("), "the site decides, not a flat rate")
	assert_true(body.contains("advance_hired_build("), "through the same labour the ledger already runs")
	assert_true(body.contains("world_age_seconds()"), "measured against the world clock")
	assert_false(body.contains("delta"), "a frame delta would be a second clock: %s" % body)


func test_your_own_builds_are_stepped_with_the_other_slow_world_systems():
	assert_true(_function_body("_step_ecology_batch").contains("_step_player_builds()"))


## Pillar 1: "every material... still happens at the moment somebody builds
## it". Checking that they are carried and then not taking them would make
## building by hand the cheapest path in the game.
func test_raising_it_yourself_really_takes_the_materials():
	var body := _function_body("_raise_plan_yourself")
	assert_true(body.contains("_spend_carried_materials("), "the cost is really paid")
	var spent_at := body.find("_spend_carried_materials(")
	var raised_at := body.find("PlanRaising.Labour.PLAYER")
	assert_gt(raised_at, -1, "the premise: building it yourself still opens a project")
	assert_lt(spent_at, raised_at, "the materials go before the work starts, not after")


## Hiring does NOT take them -- the wage is what the player pays, and the
## villager brings the material, which is the whole reason hiring is worth
## gold. Now that the two are separate functions this is the plainest form
## of the claim there is: the hiring one does not mention materials at all.
func test_hiring_does_not_also_take_the_players_materials():
	var body := _function_body("_hire_builder_for_plan")
	assert_false(body.contains("_spend_carried_materials("), "hiring never touches the player's pack")
	assert_true(
		body.contains("_open_raising_project(plan, PlanRaising.Labour.HIRED)"),
		"the premise: hiring still opens a project"
	)


## Pavement asks for no labour hours, and advance_project_labor never
## completes a zero-hour requirement -- so a raised pavement plan must be
## laid at once instead of opening a project that can never finish.
func test_work_that_asks_for_no_hours_is_finished_on_the_spot():
	var body := _function_body("_open_raising_project")
	assert_true(body.contains("PlanRaising.is_laid_by_hand("), "the size of the work decides")
	assert_true(body.contains("finish_build_project("), "and it is laid the moment it is begun")


# -- two keys, and a prompt that names them ---------------------------------
#
# Reported a third time: *"Planned nodes (e.g. pavement) still can't be
# actually built by the player or hired NPCs... there should be tooltips with
# hotkeys for both actions"*. Driving the path directly had always worked
# (test_world_raising_a_plan.gd), so what was missing was the player's side
# of it: one overloaded key that did one of three things, and a floating
# prompt that said "Talk (G)" over a wireframe they had just drawn.


func test_both_plan_actions_are_real_bound_keys():
	var bindings := Keybindings.new()
	for action_name in [World.RAISE_PLAN_ACTION, World.HIRE_BUILDER_ACTION]:
		assert_true(
			bindings.action_names().has(action_name),
			"%s must be a rebindable key, not a hardcoded one" % action_name
		)
	assert_ne(
		World.RAISE_PLAN_ACTION, World.HIRE_BUILDER_ACTION,
		"two actions the player chooses between cannot share one key"
	)


func test_each_plan_action_is_handled_on_its_own_key():
	var body := _function_body("_unhandled_input")
	for pair in [
		[World.RAISE_PLAN_ACTION, "_raise_plan_yourself("],
		[World.HIRE_BUILDER_ACTION, "_hire_builder_for_plan("],
	]:
		var pressed_at := body.find('is_action_pressed(%s)' % _action_constant_for(pair[0]))
		assert_gt(pressed_at, -1, "%s is never read" % pair[0])
		var called_at := body.find(pair[1], pressed_at)
		assert_gt(called_at, -1, "%s does not reach %s" % [pair[0], pair[1]])


## Which World constant names this action -- the input handler reads the
## constants, not the strings, so this is what the assertion above looks for.
func _action_constant_for(action_name: String) -> String:
	return "RAISE_PLAN_ACTION" if action_name == World.RAISE_PLAN_ACTION else "HIRE_BUILDER_ACTION"


## The talk key talks. It used to try the wireframe first and fall through,
## which is why standing in a village -- where wireframes are raised and a
## villager is nearly always in range -- one press did one of three things.
func test_the_talk_key_only_talks_now():
	var body := _function_body("_unhandled_input")
	var talk_at := body.find("is_action_pressed(TALK_ACTION)")
	assert_gt(talk_at, -1, "the premise")
	var next_branch := body.find("elif ", talk_at)
	var talk_branch := body.substr(talk_at, next_branch - talk_at)
	assert_false(talk_branch.contains("_raise_plan_yourself("), "raising is its own key")
	assert_false(talk_branch.contains("_hire_builder_for_plan("), "and so is hiring")
	assert_true(talk_branch.contains("_on_talk_pressed("))


## The prompt offers the wireframe BEFORE the villager beside you: it is the
## least ambiguous thing in reach (you walked onto it), and it is the one
## whose keys the player had no other way to discover.
func test_a_wireframe_is_prompted_before_the_villager_beside_you():
	var body := _function_body("_update_interaction_prompt")
	var plan_at := body.find("_plan_prompt_for(")
	var npc_at := body.find("nearest_npc_near(")
	assert_gt(plan_at, -1, "a wireframe in reach must be offered at all")
	assert_gt(npc_at, -1, "the premise: the villager prompt is still there")
	assert_lt(plan_at, npc_at, "the wireframe comes first")


## And both keys are read live from the keybindings, like every other prompt
## here -- a rebind must be reflected, never a stale hardcoded letter.
func test_the_wireframe_prompt_reads_both_keys_live():
	var body := _function_body("_plan_prompt_for")
	assert_true(body.contains('keycode_for("primary_action")'))
	assert_true(body.contains('keycode_for("secondary_action")'))
	assert_true(body.contains("display_name_of("), "and it names what is planned there")
