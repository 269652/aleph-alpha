extends GutTest

## World's real wiring for footstep/mushroom-crush/creature-call SFX (see
## docs/concept/creature_and_footstep_audio.md) -- a source-contract test on
## the function bodies rather than a live one, the same shape and reasoning
## test_world_footstep_wiring.gd/test_world_crush_wiring.gd already use:
## _client_process resolves multiplayer internally rather than taking an
## already-resolved player, so standing up a whole World node headlessly to
## drive it live is not worth the fight.

const World = preload("res://scenes/world.gd")


func _function_body(function_name: String) -> String:
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find("func %s" % function_name)
	assert_gt(start, -1, "the premise: %s must still exist" % function_name)
	var body_end := source.find("\nfunc ", start + 1)
	return source.substr(start, body_end - start)


func test_interaction_sfx_is_built_and_added_alongside_the_nature_soundscape():
	var body := _function_body("_ready")
	var soundscape_index := body.find("_nature_soundscape.build()")
	var sfx_index := body.find("_interaction_sfx.build()")
	assert_gt(soundscape_index, -1, "the premise: the existing ambient player must still be built here")
	assert_gt(sfx_index, -1, "InteractionSfxPlayer must also be built and added in _ready")


## Footstep SOUND must react to record_footstep's own returned facts, not
## re-derive the surface a second time (see that function's own doc
## comment on why it returns raw facts rather than an audio key).
func test_footstep_sound_reacts_to_record_footsteps_own_return_value():
	var body := _function_body("_client_process")
	assert_true(body.contains("_chunk_manager.record_footstep("))
	assert_true(
		body.contains("FootstepSound.surface_for("),
		"must convert the raw facts to an audio surface via FootstepSound, not EarthChunkManager"
	)
	assert_true(body.contains("_interaction_sfx.play_footstep("))


## "Walking over a mushroom should produce a correct sound" -- must sit
## inside the SAME crush_mushroom_at branch Karma already reacts to, not a
## second, independent check.
func test_mushroom_crush_sound_is_wired_alongside_the_karma_penalty():
	var body := _function_body("_client_process")
	var crush_index := body.find("_chunk_manager.crush_mushroom_at(")
	assert_gt(crush_index, -1, "the premise: the existing mushroom-crush call must still exist")
	var karma_index := body.find("Karma.WORM_OR_CATERPILLAR_CRUSH_PENALTY", crush_index)
	var sfx_index := body.find("_interaction_sfx.play_mushroom_crush()", crush_index)
	assert_gt(karma_index, -1, "the premise: the existing Karma penalty must still fire")
	assert_gt(sfx_index, -1, "play_mushroom_crush must be called in the same branch")


func test_creature_calls_are_driven_from_client_process():
	var body := _function_body("_client_process")
	assert_true(body.contains("_maybe_play_creature_calls("))


## "each animal should have an individual sound.. (horse, robin, boar,
## sparrow) etc." -- must scan BOTH real species-bearing populations
## (land creatures AND ambient flyers/birds), not just one.
func test_creature_call_scan_covers_both_creature_and_flyer_populations():
	var body := _function_body("_maybe_play_creature_calls")
	assert_true(body.contains("CreatureMarker.GROUP_NAME"), "land creatures must be scanned")
	assert_true(body.contains("AmbientFlyerMarker.FLOCK_GROUP"), "birds must be scanned too")
	assert_true(body.contains("CreatureCallSound.check_call("))
	assert_true(body.contains("_interaction_sfx.play_creature_call("))


## "you can hear cicadas in the environment which don't exist... add them
## please as real ecosystem member and produce cicada sounds for each
## individual" -- a third real, species-bearing population (tree-anchored
## cicadas, see CicadaMarker/CicadaPopulation) must be scanned exactly like
## the two that already exist, not a decorative loop bolted on separately.
func test_creature_call_scan_covers_cicadas_too():
	var body := _function_body("_maybe_play_creature_calls")
	assert_true(body.contains("CicadaMarker.GROUP_NAME"), "cicadas must be scanned too")


func test_creature_call_scan_is_throttled_not_run_every_frame():
	var body := _function_body("_maybe_play_creature_calls")
	assert_true(body.contains("CREATURE_CALL_REFRESH_INTERVAL"))


## "you hear a lot of birds even though there aren't any... compose the
## sound from what's actually around you" -- reported live a second time.
## The scan must measure a REAL distance to the player and hand it to
## check_call (which does the actual eligibility compare -- see
## CreatureCallSound.AUDIBLE_RADIUS_PX), not just roll for every creature
## in every loaded chunk regardless of how far away it is.
func test_creature_call_scan_measures_real_distance_to_the_player():
	var body := _function_body("_maybe_play_creature_calls")
	assert_true(
		body.contains("local_player.position.distance_to("),
		"must measure a real distance from the player, not skip straight to check_call"
	)
	assert_true(
		body.contains("check_call(creature.info.species, randf(), distance)")
		or body.contains("check_call(flyer.species, randf(), distance)"),
		"the measured distance must actually reach check_call, not be computed and discarded"
	)


## Reported live: "Still at 1fps." Real, severe regression found by
## reading the source, not guessing: `_nature_soundscape.update(...)`'s
## own call in `_client_process` passed `_chunk_manager.
## nearest_water_distance_tiles(...)` (EarthChunkManager.
## WATER_PROXIMITY_SCAN_RADIUS_TILES's own real ring-scan, see
## WaterProximity) as a plain function ARGUMENT -- GDScript evaluates
## call arguments eagerly, BEFORE the callee ever runs, so this expensive
## scan fired every single frame regardless of whatever throttle
## `_nature_soundscape.update` might apply internally to what it actually
## DOES with the value. Worse than a typical unthrottled scan: the
## per-tile `is_river_at_global`/`is_lake_at_global` cache barely helps
## here, since the scanned window is centred on the player and shifts
## with every step -- most of the ~2,000+ tile checks per call are cache
## MISSES, not hits, on any frame the player is moving.
##
## Must be throttled the same shape CREATURE_CALL_REFRESH_INTERVAL already
## uses: a dedicated accumulator, recomputed only every WATER_PROXIMITY_
## REFRESH_INTERVAL seconds and cached, with the CACHED value (never a
## live call) reaching `_nature_soundscape.update`.
func test_water_proximity_scan_is_throttled_not_run_every_frame():
	var body := _function_body("_client_process")
	assert_true(body.contains("WATER_PROXIMITY_REFRESH_INTERVAL"))
	var update_call := _full_call_text(body, "_nature_soundscape.update(")
	assert_false(
		update_call.contains("nearest_water_distance_tiles("),
		"nearest_water_distance_tiles must never be evaluated as a live call argument: %s" % update_call
	)


## Returns the full text of a call starting at `needle` (an opening-paren-
## terminated prefix, e.g. "foo(") through its OWN matching closing paren
## -- real paren-depth tracking, not a naive find(")") that would stop at
## the first nested call's own close-paren instead of the outer call's,
## since the real call this test cares about spans several lines and
## multiple arguments.
func _full_call_text(body: String, needle: String) -> String:
	var start := body.find(needle)
	assert_gt(start, -1, "the premise: %s must still be called here" % needle)
	var depth := 0
	var i := start + needle.length() - 1  # the opening "(" itself
	while i < body.length():
		var c := body[i]
		if c == "(":
			depth += 1
		elif c == ")":
			depth -= 1
			if depth == 0:
				return body.substr(start, i - start + 1)
		i += 1
	fail_test("never found a matching close-paren for %s" % needle)
	return ""
