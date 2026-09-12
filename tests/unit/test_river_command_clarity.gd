extends GutTest

## `/river` -- teleports the local player to a random point on a random
## curated river (reusing SpawnRiverPicker + RiverCatalog + World's own
## _spawn_candidate_acceptable/_find_dry_land_spawn, the exact machinery
## a new game's own spawn already uses -- see docs/concept/rivers.md
## "Spawn: a random curated river"). Pinned from source text rather than
## by driving a real World node (needs a full generator with hydrology
## loaded, see test_earth_chunk_manager.gd's runtime), the same shape as
## test_mushroom_command_clarity.gd/test_season_command_clarity.gd.


func _source() -> String:
	return FileAccess.get_file_as_string("res://scenes/world.gd")


func _river_command_body() -> String:
	var source := _source()
	var start := source.find("func _handle_river_command(")
	assert_gt(start, -1, "World._handle_river_command should still exist")
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
	assert_string_contains(dispatch, "\"river\":")
	assert_string_contains(dispatch, "_handle_river_command(local_player)")


func test_the_help_text_mentions_the_command():
	var source := _source()
	var help_start := source.find("Commands: /day")
	assert_gt(help_start, -1, "the help text should still start with /day")
	var help_end := source.find(")", help_start)
	var help := source.substr(help_start, help_end - help_start)
	assert_string_contains(help, "/river")


func test_a_null_player_is_a_clear_message_not_a_crash():
	var body := _river_command_body()
	var null_check_at := body.find("local_player == null")
	assert_gt(null_check_at, -1, "must guard the null-player case, the same shape /village uses")
	assert_lt(null_check_at, body.find("SpawnRiverPicker.pick("), "the guard must come before any picking")


## The real logic lives in SpawnRiverPicker (its own tests pin the random
## draw, the never-source-or-mouth rule, and the empty-pick fallback) and
## RiverCatalog (the real curated courses) -- this command must actually
## call through to both, not reimplement or shortcut either.
func test_the_command_calls_the_real_picker_and_catalog():
	var body := _river_command_body()
	assert_string_contains(body, "SpawnRiverPicker.pick(")
	assert_string_contains(body, "RiverCatalog.tile_polylines(")
	assert_string_contains(body, "_spawn_candidate_acceptable")


## Landing on the actual water tile the picker names would drop the player
## straight into the current -- the same dry-bank nudge a new game's own
## spawn already applies (_find_dry_land_spawn) puts them on the bank
## beside it instead.
func test_the_landing_spot_uses_the_existing_dry_bank_nudge():
	var body := _river_command_body()
	assert_string_contains(body, "_find_dry_land_spawn(")


## No curated river bank qualifying (every candidate rejected within
## SpawnRiverPicker's attempt budget) must say so clearly, the same
## "silent wrong behavior is worse than a refusal" concern
## test_weather_command_clarity.gd already guards for.
func test_an_empty_pick_is_a_clear_message_not_silence():
	var body := _river_command_body()
	assert_string_contains(body, "pick.is_empty()")
	assert_gt(
		body.find("No river"), -1,
		"an empty pick should log something starting 'No river...', not fail silently"
	)


## A successful teleport should actually move the player and say which
## river -- not just log a generic "done".
func test_a_successful_teleport_sets_position_and_names_the_river():
	var body := _river_command_body()
	assert_string_contains(body, "local_player.position")
	assert_string_contains(body, "pick[\"river\"]")
