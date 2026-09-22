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
const Answerback = preload("res://src/gameplay/answerback.gd")


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
	assert_eq(Answerback.MAX_CARD_SECONDS, World.ANCIENT_TERMINAL_MESSAGE_DURATION)


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
	assert_true(_function_body("_discovery_step").contains("Answerback.seconds_to_read"))


# -- and a loaded save explores too --------------------------------------
#
# Found by playing it. `set_spawn_tile` had exactly one call site --
# `_compute_dry_land_spawn_tile`, which only the NEW-game path runs -- so a
# loaded character left `_spawn_configured` false, `record_footfall`
# returned `{}` on every frame, and the entire discovery layer was dark:
# no ground recorded, no XP, no crossing card. (The same flag also gates
# `_difficulty_tier_at`, which answers HARD when it is unset.)

## The real CALL, never a mention of the name: the first draft of this test
## matched the explanatory comment above the call and would have passed
## against a file that only talked about setting a spawn.
const SPAWN_CALL := "_chunk_manager.set_spawn_tile("
const CHUNK_LOAD_CALL := "_chunk_manager.update_with_progress("


func test_a_loaded_save_still_knows_where_home_is():
	assert_true(
		_function_body("_spawn_local_singleplayer_from_save").contains(SPAWN_CALL),
		"a resumed character must still have a spawn to measure distance from"
	)


## From the character's OWN saved home, not from wherever they happened to
## log out -- otherwise every load would re-centre the world's rings on the
## player and the far country would become the hearth.
func test_the_resumed_spawn_is_the_saved_home_not_the_logout_spot():
	var body := _function_body("_spawn_local_singleplayer_from_save")
	var call_index := body.find(SPAWN_CALL)
	assert_gt(call_index, -1, "precondition")
	var call_line := body.substr(call_index, body.find("\n", call_index) - call_index)
	assert_true(
		call_line.contains("respawn_position"),
		"the ring centre is the character's own home: %s" % call_line
	)


## Before the first chunk load: chunk loading reads the difficulty tier, and
## an unset spawn answers HARD for every chunk on the planet.
func test_home_is_known_before_the_first_chunk_is_loaded():
	var body := _function_body("_spawn_local_singleplayer_from_save")
	var spawn_index := body.find(SPAWN_CALL)
	var load_index := body.find(CHUNK_LOAD_CALL)
	assert_gt(spawn_index, -1, "precondition: the call is really there")
	assert_gt(load_index, -1, "precondition: the load is really there")
	assert_lt(
		spawn_index, load_index,
		"an unset spawn makes every chunk HARD while the world streams in"
	)


# -- the permanent reading -----------------------------------------------
#
# Reported after the first build: "no card or XP visible". Instrumenting a
# --solo launch showed the wiring was fine and the FEEDBACK was the problem
# -- one ~1 s float on frame one, then nothing for 512 px of walking. A
# journey needs something that is simply always on screen.

func test_the_hud_carries_a_permanent_place_card():
	assert_false(_function_body("_build_place_card").is_empty(), "the card must exist")
	assert_true(
		_function_body("_build_hud").contains("_build_place_card")
		or _function_body("_ready").contains("_build_place_card"),
		"and be built with the rest of the HUD"
	)


func test_the_place_card_is_refreshed_every_client_frame():
	assert_true(
		_function_body("_client_process").contains("_update_place_card"),
		"a readout that stops updating is worse than no readout"
	)


func test_the_place_card_reads_the_shared_rule_rather_than_composing_its_own():
	var body := _function_body("_update_place_card")
	assert_true(body.contains("Discovery.place_chip"), "one wording, in the pure module")
	assert_false(body.contains("JourneyRing.ring_at"), "World does not name rings itself")


## The count is the live explored record -- the same one /map reads -- so
## the number ticking up IS the proof that walking records ground.
func test_the_place_card_counts_the_live_explored_record():
	assert_true(_function_body("_update_place_card").contains("explored_chunks"))


## Before the world knows where home is there is no distance to report, and
## a chip claiming one would be claiming the origin is home.
func test_the_place_card_says_nothing_until_home_is_known():
	var body := _function_body("_update_place_card")
	assert_true(
		body.contains("< 0") or body.contains("<= -1") or body.contains("== -1"),
		"an unknown distance hides the card rather than guessing"
	)
