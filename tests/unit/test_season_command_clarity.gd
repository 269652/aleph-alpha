extends GutTest

## `/season [name] [progress]` -- the progress argument layered on top of the
## existing forward-jump command. EarthChunkManager.jump_to_season and
## SeasonCycle.seconds_until_season already own the real math and clamp any
## float defensively (see their own doc comments); this file pins the
## CONSOLE COMMAND's own argument-parsing decisions -- what counts as valid
## typed input and what the command says about it when it is not, so a typo
## like `/season autumn 50` (meant as "50%", typed where a 0-1 fraction was
## wanted) is refused with a clear reason rather than silently clamped to 1.0
## and read back as if that was what was asked for. Same "silent wrong
## behavior is worse than a refusal" concern test_weather_command_clarity.gd
## already guards for the weather command's own "off" branch.
##
## Pinned from source text rather than by driving a real World node (needs a
## full chunk manager, see test_earth_chunk_manager.gd's runtime), the same
## shape as test_weather_command_clarity.gd.


func _season_command_body() -> String:
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find("func _handle_season_command(")
	assert_gt(start, -1, "World._handle_season_command should still exist")
	var end := source.find("\nfunc ", start + 1)
	if end == -1:
		end = source.length()
	return source.substr(start, end - start)


## A non-numeric second argument must be refused with a clear message, not
## silently treated as 0.0 the way String.to_float() would on garbage input.
func test_a_non_numeric_progress_is_refused_with_a_clear_message():
	var body := _season_command_body()
	assert_string_contains(body, "is_valid_float()")
	assert_gt(
		body.find("must be a number"), -1,
		"a non-numeric progress should say so rather than defaulting silently"
	)


## An out-of-range number (someone typing "50" meaning "50%" where a 0-1
## fraction was wanted) must be refused too, rather than silently clamped and
## read back as if 1.0 (the far end of the season) was what was asked for.
func test_an_out_of_range_progress_is_refused_with_a_clear_message():
	var body := _season_command_body()
	assert_gt(
		body.find("must be between 0 and 1"), -1,
		"an out-of-range progress should say so rather than clamping silently"
	)


## The happy path must actually thread the parsed float through to
## jump_to_season, not just validate it and then call the old signature.
func test_a_valid_progress_is_passed_through_to_jump_to_season():
	var body := _season_command_body()
	assert_string_contains(body, "jump_to_season(wanted, progress)")


## The new argument is optional -- `/season <name>` alone must still work
## exactly as before, landing at the season's own start.
func test_omitting_the_progress_argument_still_works_as_before():
	var body := _season_command_body()
	assert_gt(
		body.find("args.size() > 1"), -1,
		"a second argument should be optional, not required"
	)


## The in-console help listing should mention the new optional argument, not
## just the season name, so a player discovers it without reading the source.
func test_the_help_text_mentions_the_progress_argument():
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var season_help := source.find("/season [name]")
	assert_gt(season_help, -1, "the help text should still list /season")
	var line_end := source.find("\n", season_help)
	var line := source.substr(season_help, line_end - season_help)
	assert_string_contains(line, "progress")
