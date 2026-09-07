extends GutTest

## The torch-glow wiring, as the RUNNING GAME actually gets it -- same
## reasoning and the same "read World._client_process straight from source"
## technique as test_world_season_fanout.gd: TorchGlow's own pure logic is
## green in test_torch_glow.gd, and a feature green in its own unit test
## while invisible while playing is not done (see that file's own doc
## comment for the full argument).
##
## Kept as its own tiny file, not folded into test_world_season_fanout.gd,
## since it is a wholly separate mechanism (docs/concept/lighting.md) that
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
## _update_torch_glow itself, once _client_process's own body confirms it
## is actually called.
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
## it, TorchGlow's own real, tested logic is dead code and equipping a
## torch does nothing at night.
func test_the_client_frame_updates_the_torch_glow():
	assert_string_contains(
		_client_process_body(),
		"_update_torch_glow(local_player)",
		"the torch glow never learns whether a torch is actually equipped"
	)


## The gate itself must go through TorchGlow's own named, tested function
## (is_lit_item_id) -- not a second, inline "== \"torch\"" comparison that
## could silently drift from it if a future light source is added there but
## not here.
func test_the_torch_glow_update_uses_the_shared_is_lit_check():
	assert_string_contains(
		_function_body("_update_torch_glow"),
		"TorchGlow.is_lit_item_id(",
		"the wiring re-implements its own lit check instead of using TorchGlow's"
	)


## The glow has to actually follow the player, or it renders in the wrong
## place (or the last place a torch was ever equipped) as soon as anyone
## moves.
func test_the_torch_glow_update_follows_the_local_players_own_position():
	assert_string_contains(
		_function_body("_update_torch_glow"),
		"local_player.global_position",
		"the glow's position is never set from the player's own real position"
	)
