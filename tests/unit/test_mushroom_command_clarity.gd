extends GutTest

## `/mushroom` -- forces the nearest real mushroom site in the local
## player's own chunk to fruit right now (see WildMushroomPatch.
## force_fruit_near / EarthChunkManager.force_mushroom_near for the real
## logic those own tests already pin). Pinned from source text rather than
## by driving a real World node (needs a full chunk manager, see
## test_earth_chunk_manager.gd's runtime), the same shape as
## test_season_command_clarity.gd/test_weather_command_clarity.gd.


func _source() -> String:
	return FileAccess.get_file_as_string("res://scenes/world.gd")


func _mushroom_command_body() -> String:
	var source := _source()
	var start := source.find("func _handle_mushroom_command(")
	assert_gt(start, -1, "World._handle_mushroom_command should still exist")
	var end := source.find("\nfunc ", start + 1)
	if end == -1:
		end = source.length()
	return source.substr(start, end - start)


func test_the_command_is_registered_in_the_dispatch_table():
	var source := _source()
	var match_start := source.find("func _on_console_command(")
	assert_gt(match_start, -1, "World._on_console_command should still exist")
	var match_end := source.find("\nfunc ", match_start + 1)
	var dispatch := source.substr(match_start, match_end - match_start)
	assert_string_contains(dispatch, "\"mushroom\":")
	assert_string_contains(dispatch, "_handle_mushroom_command(args)")


func test_the_help_text_mentions_the_command():
	var source := _source()
	var help_start := source.find("Commands: /day")
	assert_gt(help_start, -1, "the help text should still start with /day")
	var help_end := source.find(")", help_start)
	var help := source.substr(help_start, help_end - help_start)
	assert_string_contains(help, "/mushroom")


## The real logic lives in EarthChunkManager.force_mushroom_near (its own
## tests pin nearest-site selection and the sentinel case) -- this command
## must actually call through to it, not duplicate or shortcut that logic.
func test_the_command_calls_the_real_force_mushroom_near():
	var body := _mushroom_command_body()
	assert_string_contains(body, "force_mushroom_near(")


## A chunk with no eligible mushroom site (force_mushroom_near returning
## "") must say so clearly, the same "silent wrong behavior is worse than
## a refusal" concern test_weather_command_clarity.gd already guards for.
func test_a_site_less_chunk_gets_a_clear_message_not_silence():
	var body := _mushroom_command_body()
	assert_string_contains(body, "is_empty()")
	assert_gt(
		body.find("No mushroom site"), -1,
		"a chunk with no eligible site should say so rather than doing nothing silently"
	)


## The happy path should actually name the real species that fruited, not
## just a generic "something happened" line.
func test_the_happy_path_names_the_real_species():
	var body := _mushroom_command_body()
	assert_string_contains(body, "display_name_for(species)")
