extends GutTest

## The compass-window wiring, as the RUNNING GAME actually gets it -- same
## reasoning and the same "read World._client_process straight from source"
## technique as test_world_torch_glow_fanout.gd: CompassWindow's own pure
## logic is green in test_compass_window.gd, and a feature green in its own
## unit test while invisible while playing is not done (see that file's own
## doc comment for the full argument).
##
## Kept as its own tiny file, not folded into test_world_torch_glow_fanout.gd,
## since it is a wholly separate mechanism (docs/concept/wayfinding.md) that
## happens to update on the same per-frame cadence.

const World = preload("res://scenes/world.gd")


## The body of World._client_process, read straight from source. Same
## technique as test_world_season_fanout.gd's own _client_process_body().
func _client_process_body() -> String:
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find("func _client_process(")
	assert_gt(start, -1, "World._client_process should still exist")
	var body_end := source.find("\nfunc ", start + 1)
	if body_end == -1:
		body_end = source.length()
	return source.substr(start, body_end - start)


## The body of one named function, read straight from source -- for
## _update_compass_window itself, once _client_process's own body confirms
## it is actually called.
func _function_body(function_name: String) -> String:
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var needle := "func %s(" % function_name
	var start := source.find(needle)
	assert_gt(start, -1, "World.%s should exist" % function_name)
	var body_end := source.find("\nfunc ", start + 1)
	if body_end == -1:
		body_end = source.length()
	return source.substr(start, body_end - start)


## The line that makes the whole mechanism visible while playing. Without
## it, CompassWindow's own real, tested logic is dead code and equipping a
## compass shows nothing.
func test_the_client_frame_updates_the_compass_window():
	assert_string_contains(
		_client_process_body(),
		"_update_compass_window(local_player)",
		"the compass window never learns whether a compass is actually equipped"
	)


## The gate itself must go through Compass's own named, tested function
## (is_compass_item_id) -- not a second, inline comparison that could
## silently drift from it if a future third compass tier is added there but
## not here.
func test_the_compass_window_update_uses_the_shared_is_compass_check():
	assert_string_contains(
		_function_body("_update_compass_window"),
		"Compass.is_compass_item_id(",
		"the wiring re-implements its own compass check instead of using Compass's"
	)


## The rough/fine dispatch must also go through Compass's own named function
## (is_fine_item_id), the same reasoning as the check above -- a compass
## window that hardcodes item id comparisons in two different places is
## exactly the drift this seam exists to prevent.
func test_the_compass_window_update_uses_the_shared_is_fine_check():
	assert_string_contains(
		_function_body("_update_compass_window"),
		"Compass.is_fine_item_id(",
		"the wiring never asks Compass which quality tier is equipped"
	)


## The reading has to actually follow the player, or it renders a bearing
## from the wrong place (or the last place a compass was ever equipped) as
## soon as anyone moves.
func test_the_compass_window_update_reads_the_local_players_own_position():
	assert_string_contains(
		_function_body("_update_compass_window"),
		"local_player.global_position",
		"the bearing is never computed from the player's own real position"
	)
