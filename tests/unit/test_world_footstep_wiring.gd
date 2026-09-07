extends GutTest

## World's real footprint wiring (see FootstepGait, EarthChunkManager.
## record_footstep/step_footprints) -- a source-contract test on the
## function bodies rather than a live one, the same shape and reasoning
## test_world_crush_wiring.gd/test_world_path_scarring_trail_wiring.gd
## already use: _client_process resolves multiplayer internally rather
## than taking an already-resolved player, so standing up a whole World
## node headlessly to drive it live is not worth the fight.

const World = preload("res://scenes/world.gd")


func _function_body(function_name: String) -> String:
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find("func %s" % function_name)
	assert_gt(start, -1, "the premise: %s must still exist" % function_name)
	var body_end := source.find("\nfunc ", start + 1)
	return source.substr(start, body_end - start)


func test_the_premise_the_other_tests_rely_on():
	var body := _function_body("_client_process")
	assert_true(body.contains("record_footstep"), "must still call the real footstep placement at all")


## record_footstep needs the player's own real position and travel
## heading -- reported live: "left/right footprints spaced apart", which
## needs a real heading to orient perpendicular to, not just a position.
func test_record_footstep_is_called_with_the_players_own_position_and_facing():
	var body := _function_body("_client_process")
	var call_index := body.find("record_footstep(")
	assert_gt(call_index, -1)
	# To end of statement (a newline), not the first ")" -- facing_
	# direction() has its own closing paren nested inside the call, which
	# a naive first-")" search would stop at before reaching the real one.
	var call_end := body.find("\n", call_index)
	var call_text := body.substr(call_index, call_end - call_index)
	assert_true(call_text.contains("local_player.position"))
	assert_true(call_text.contains("local_player.facing_direction()"))


## Player-only (reported live scope: "real footstep prints"), unlike
## tread_snow_at/the crush pass in the same function, which both also
## run per-CreatureMarker in a loop -- record_footstep must appear
## exactly once, not once per creature too.
func test_record_footstep_is_called_exactly_once_not_per_creature():
	var body := _function_body("_client_process")
	var count := 0
	var search_from := 0
	while true:
		var index := body.find("record_footstep(", search_from)
		if index == -1:
			break
		count += 1
		search_from = index + 1
	assert_eq(count, 1)


## Purely additive on top of the existing snow-depth-reduction/wear
## tracking (reported live: "snow amount should still be reduced") --
## tread_snow_at (the existing mechanism) must still be called too, not
## replaced by record_footstep.
func test_tread_snow_at_is_still_called_alongside_record_footstep():
	var body := _function_body("_client_process")
	assert_true(body.contains("tread_snow_at"), "the existing snow-depth reduction must be untouched")
	assert_true(body.contains("record_footstep"))
	assert_lt(
		body.find("tread_snow_at"), body.find("record_footstep"),
		"record_footstep should sit right alongside tread_snow_at, after it"
	)


func test_step_footprints_is_called_alongside_step_leaf_litter():
	var body := _function_body("_step_ecology_batch")
	assert_true(body.contains("step_leaf_litter"), "the premise: this is still where leaf litter batches")
	assert_true(body.contains("step_footprints"))
