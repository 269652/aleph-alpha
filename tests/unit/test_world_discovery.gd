extends GutTest

## docs/concept/discovery.md: the wiring, not the rule. `Discovery` is pinned
## by test_discovery.gd and the footfall itself by
## test_earth_chunk_manager_discovery.gd; what is asserted here is that World
## really takes a footfall every frame, really pays the player what the ring
## asked, and really says it out loud.
##
## The pattern (and the reason it is source-level) is
## test_world_first_light.gd's: World is an 8500-line scene script with a
## dozen autoloads behind it, and a pure rule nothing calls is exactly the
## failure this whole overhaul was diagnosing -- dodge, corpse and wounds are
## all real, tested and have zero callers. These tests are what stop
## Discovery joining them.

const World = preload("res://scenes/world.gd")
const Discovery = preload("res://src/gameplay/discovery.gd")


func _world_source() -> String:
	return FileAccess.get_file_as_string("res://scenes/world.gd")


## The body of `func <name>` up to the next top-level `func`, so an assertion
## about one step cannot be satisfied by an unrelated line elsewhere in a
## file this size.
func _function_body(name: String) -> String:
	var source := _world_source()
	var start := source.find("func %s(" % name)
	if start < 0:
		return ""
	var rest := source.substr(start)
	var next := rest.find("\nfunc ")
	return rest if next < 0 else rest.substr(0, next)


func test_the_world_has_a_discovery_step_at_all():
	assert_false(_function_body("_discovery_step").is_empty(), "the step must exist")


## Every frame, for the local player -- the same place every other per-frame
## read of the local player lives.
func test_the_discovery_step_really_runs_every_client_frame():
	assert_true(
		_function_body("_client_process").contains("_discovery_step"),
		"a step nothing calls is the exact pattern this overhaul was diagnosing"
	)


func test_the_step_takes_a_real_footfall_on_the_live_explored_record():
	assert_true(
		_function_body("_discovery_step").contains("record_footfall"),
		"the manager's own footfall, so the map that fills is the one /map reads"
	)


func test_new_ground_really_pays_the_player():
	assert_true(
		_function_body("_discovery_step").contains("gain_experience"),
		"the XP the ring asked for has to reach the character"
	)


## The receipt is the same rising label every other act in the game answers
## with (docs/concept/feedback.md), not a second feedback channel.
func test_the_receipt_floats_the_way_every_other_act_answers():
	assert_true(_function_body("_discovery_step").contains("_float_answer_text"))


## And the card goes on the shared message stack, not a banner of its own
## pinned to a hand-picked offset -- the mistake _build_message_stack exists
## to have fixed.
func test_the_crossing_card_goes_on_the_shared_message_stack():
	var step := _function_body("_discovery_step")
	assert_true(step.contains("_set_message_banner"), "one stack, one x/y")
	assert_true(
		_function_body("_build_message_stack").contains("_discovery_banner"),
		"and its card is built with all the others, in the fixed order"
	)


## The whole step is decided by the pure module; World performs it. A second
## opinion about what new ground is worth, computed here, is exactly the
## drift every restated constant in this codebase is pinned against.
func test_the_world_never_decides_what_new_ground_is_worth():
	var step := _function_body("_discovery_step")
	assert_false(step.contains("XP_PER_KILL"), "the payoff is Discovery's, not World's")
	assert_false(step.contains("demands_at"), "and so is the price it reads")


## Nothing happened is the ordinary answer on all but a handful of frames.
func test_the_step_returns_early_when_nothing_happened():
	assert_true(
		_function_body("_discovery_step").contains("is_empty()"),
		"a footfall inside the chunk already underfoot must cost nothing"
	)


## Discovery restates the HUD's own longest passage as its ceiling rather
## than preloading this scene script. A restated number is a number that can
## drift, and this is what stops it.
func test_the_restated_card_ceiling_is_the_huds_own_longest_passage():
	assert_eq(Discovery.MAX_CARD_SECONDS, World.ANCIENT_TERMINAL_MESSAGE_DURATION)


## A card that never clears is furniture. It has to decay on every frame,
## not only on the frames a chunk edge happens to be crossed -- a player who
## stops walking would otherwise keep it until they moved again.
func test_the_card_decays_on_every_frame_rather_than_only_on_a_crossing():
	var step := _function_body("_discovery_step")
	assert_true(step.contains("_expire_discovery_card"), "the decay runs before the early-out")
	var decay := _function_body("_expire_discovery_card")
	assert_false(decay.is_empty())
	assert_true(decay.contains("delta"), "and it is real time, not a frame count")


## Each card is shown for its own length, never a constant somebody picked.
func test_the_dwell_is_the_cards_own_reading_time():
	assert_true(_function_body("_discovery_step").contains("Discovery.seconds_to_read"))
