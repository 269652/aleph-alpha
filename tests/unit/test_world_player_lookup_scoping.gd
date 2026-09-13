extends GutTest

## Players are spawned directly into $Entities so they Y-sort against
## trees and grass (see World's own _players doc comment) -- which makes
## `_players.get_children()` a walk over EVERY entity in the loaded world:
## thousands of trees, stones and creature markers, cast one by one to
## Player, to find the one or two players among them. _client_process did
## that walk every frame just to hand a chunk manager to any not-yet-set-up
## player; FPS regression round 15's sub-step timers measured update()'s
## own work at ~0.1 ms while the section around it read 2.2 ms -- the
## difference was this loop. Players already join the "player" group in
## Player._ready, so that group (one or two nodes) is the right list.
##
## A source-contract test, the same shape as test_world_perf_report_wiring
## (World resolves its state internally; standing one up headlessly to
## drive _client_process is not worth the fight).


func _body_of(function_name: String) -> String:
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find("func %s(" % function_name)
	assert_gt(start, -1, "the premise: %s must still exist" % function_name)
	var body_end := source.find("\nfunc ", start + 1)
	return source.substr(start, body_end - start)


func test_client_process_finds_players_through_their_group_not_by_walking_every_entity():
	var body := _body_of("_client_process")
	assert_false(body.contains("_players.get_children()"),
		"$Entities holds every tree, stone and marker in the loaded world -- never walk it per frame for players")
	assert_true(body.contains("get_tree().get_nodes_in_group(\"player\")"),
		"players are the handful of nodes in the \"player\" group")


func test_server_process_finds_players_through_their_group_too():
	var body := _body_of("_server_process")
	assert_false(body.contains("_players.get_children()"))
	assert_true(body.contains("get_tree().get_nodes_in_group(\"player\")"))
