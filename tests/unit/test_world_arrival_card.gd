extends GutTest

## docs/concept/arrival.md: the three facts a new character needs in their
## first ten seconds, actually on screen.
##
## `ArrivalBriefing` is pinned by test_arrival_briefing.gd. What is asserted
## here is the wiring its own status list called out as missing: that World
## really assembles the facts from live state, really raises the card, and
## really leaves a loaded save alone -- the same rule the dawn clause
## follows, and for the same reason. A character old enough to have been
## saved has already had a first morning.
##
## Source-level for the same reason test_world_first_light.gd is: World is
## an 8500-line scene script, and a pure module nothing calls is exactly the
## failure this overhaul was diagnosing.

const World = preload("res://scenes/world.gd")
const ArrivalBriefing = preload("res://src/gameplay/arrival_briefing.gd")
const Answerback = preload("res://src/gameplay/answerback.gd")


func _world_source() -> String:
	return FileAccess.get_file_as_string("res://scenes/world.gd")


func _function_body(name: String) -> String:
	var source := _world_source()
	var start := source.find("func %s(" % name)
	if start < 0:
		return ""
	var rest := source.substr(start)
	var next := rest.find("\nfunc ")
	return rest if next < 0 else rest.substr(0, next)


func test_the_world_raises_an_arrival_briefing_at_all():
	assert_false(_function_body("_show_arrival_briefing").is_empty())


## Through the real module, not three sentences written again in World.
func test_the_card_is_the_briefings_own_lines():
	var step := _function_body("_show_arrival_briefing")
	assert_true(step.contains("ArrivalBriefing.briefing_for"), "the facts go through the module")
	assert_true(step.contains("ArrivalBriefing.card_text"), "and so does the join")


# -- the facts are read off live state -----------------------------------

## The river the spawn picker really drew. Before this it was printed to
## stdout at spawn and thrown away.
func test_the_spawned_rivers_name_is_kept_rather_than_printed_and_dropped():
	var source := _world_source()
	assert_true(source.contains("_spawn_river_name"), "the river a character woke up on")
	assert_true(
		_function_body("_compute_dry_land_spawn_tile").contains("_spawn_river_name"),
		"captured where the pick really happens"
	)


func test_the_season_is_the_worlds_own_clock():
	assert_true(
		_function_body("_show_arrival_briefing").contains("current_season"),
		"the season the world is really in, never a literal"
	)


## The errand line is a projection of a real shortage, never authored
## content -- docs/concept/quests.md's own house rule.
func test_the_errand_is_the_live_shortfall_projection():
	assert_true(
		_function_body("_show_arrival_briefing").contains("production_shortfall_quests_for_settlement")
	)


# -- and a loaded save is left alone -------------------------------------

func test_a_new_game_gets_the_briefing():
	assert_true(
		_function_body("_spawn_local_singleplayer").contains("_show_arrival_briefing"),
		"the one moment a new player is listening"
	)


## The same rule the dawn clause keeps: the clause is keyed to ARRIVAL, not
## to session start, and so is this.
func test_a_loaded_save_is_never_greeted_as_a_newcomer():
	assert_false(
		_function_body("_spawn_local_singleplayer_from_save").contains("_show_arrival_briefing"),
		"a character who has been living here does not need to be told where they are"
	)


# -- and it is readable --------------------------------------------------

func test_the_card_goes_on_the_shared_message_stack():
	assert_true(_function_body("_show_arrival_briefing").contains("_set_message_banner"))
	assert_true(
		_function_body("_build_message_stack").contains("_arrival_banner"),
		"built with the others, in the fixed order"
	)


## Three sentences is a passage, and it stays up for its own reading time --
## the same rule the crossing card follows.
func test_the_card_stays_up_for_its_own_reading_time():
	assert_true(_function_body("_show_arrival_briefing").contains("Answerback.seconds_to_read"))


func test_the_card_really_clears_itself():
	var decay := _function_body("_expire_arrival_card")
	assert_false(decay.is_empty(), "a card that never clears is furniture")
	assert_true(decay.contains("delta"), "real time, not a frame count")
	assert_true(
		_function_body("_client_process").contains("_expire_arrival_card"),
		"and it has to tick every frame, not only while the player walks"
	)


## An arrival that knew nothing shows nothing, rather than an empty panel to
## a character who just opened their eyes.
func test_an_empty_briefing_raises_no_card():
	assert_true(
		_function_body("_show_arrival_briefing").contains('== ""'),
		"nothing known is nothing shown"
	)
	assert_eq(ArrivalBriefing.card_text({}), "", "and the module agrees")
