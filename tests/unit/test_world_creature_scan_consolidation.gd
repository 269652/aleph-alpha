extends GutTest

## World._client_process's CreatureMarker.GROUP_NAME lookup -- a source-
## contract test on the function body, the same shape and reasoning
## test_world_footstep_wiring.gd/test_world_crush_wiring.gd already use:
## _client_process resolves multiplayer internally rather than taking an
## already-resolved player, so standing up a whole World node headlessly
## to drive it live is not worth the fight.
##
## Reported live: "Can you fix the 10fps issue and bring it back to 30+?"
## Root cause, found by reading _client_process directly rather than
## guessed: FOUR separate, un-throttled, every-single-frame calls to
## `get_tree().get_nodes_in_group(CreatureMarker.GROUP_NAME)` -- one each
## for the river-wader position scan, the per-creature snow-tread pass,
## the per-creature footstep pass (added in an earlier session), and the
## per-creature crush pass. `get_nodes_in_group` itself allocates and
## copies the group's member list on every call -- O(loaded creature
## count) just to FETCH the list, paid four times a frame for the exact
## same list, before any of the per-creature work inside each loop even
## starts. This is exactly the shape of bug that already caused a
## previously-measured, previously-fixed 25-31ms/frame regression in
## EarthChunkManager.crush_ants_near (see that function's own doc
## comment) -- the same "redundant per-frame full-population work,
## accumulated one small addition at a time across many sessions" root
## cause, just spread across FOUR call sites instead of hiding inside
## one.
##
## Fix: the group is fetched exactly ONCE per frame now (`loaded_creature_
## markers`), and every one of the four loops iterates that same cached
## list instead of re-fetching it. The two loops that were already
## textually adjacent with nothing between them (snow-tread, footstep)
## are merged into one loop body -- zero reordering risk, since neither
## reads the other's output and nothing sits between them today. The
## crush loop's own POSITION is deliberately left untouched (still after
## the player-only crush block) -- merging it in too would mean
## reordering across that block, which the Karma-charging tests in
## test_world_crush_wiring.gd depend on staying exactly where it is.

const World = preload("res://scenes/world.gd")


func _function_body(function_name: String) -> String:
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find("func %s" % function_name)
	assert_gt(start, -1, "the premise: %s must still exist" % function_name)
	var body_end := source.find("\nfunc ", start + 1)
	return source.substr(start, body_end - start)


func _count_occurrences(haystack: String, needle: String) -> int:
	var count := 0
	var search_from := 0
	while true:
		var found := haystack.find(needle, search_from)
		if found == -1:
			break
		count += 1
		search_from = found + 1
	return count


## The direct regression guard for the actual fix: the real, live
## `get_tree().get_nodes_in_group(CreatureMarker.GROUP_NAME)` call must
## appear exactly once in _client_process -- every other consumer must
## reuse the cached result rather than re-fetching it. Before this fix,
## this failed at 4.
func test_creature_marker_group_is_fetched_from_the_scene_tree_exactly_once():
	var body := _function_body("_client_process")
	assert_eq(
		_count_occurrences(body, "get_tree().get_nodes_in_group(CreatureMarker.GROUP_NAME)"),
		1,
		"the live scene-tree group lookup must happen once per frame, cached, not once per consumer"
	)


## The cached list must actually be USED -- a lone unused cache variable
## would technically satisfy the test above while changing nothing real.
## Three real consumers today: the wader-position scan, the merged snow-
## tread/footstep loop, and the crush loop.
func test_the_cached_creature_list_is_reused_by_all_three_consumers():
	var body := _function_body("_client_process")
	assert_eq(
		_count_occurrences(body, "for creature in loaded_creature_markers:"),
		3,
		"expected exactly 3 loops over the cached list: wader positions, snow-tread+footstep, crush"
	)


## The snow-tread and footstep passes were already textually adjacent
## with nothing between them -- merging them is zero-reordering-risk, and
## this pins that both calls now live inside the SAME loop body (the
## first `for creature in loaded_creature_markers:` occurrence that
## contains a `tread_snow_at` call also contains `record_footstep`).
func test_snow_tread_and_footstep_are_merged_into_one_creature_loop():
	var body := _function_body("_client_process")
	var loop_at := body.find("for creature in loaded_creature_markers:")
	assert_gt(loop_at, -1)
	var next_loop_at := body.find("for creature in loaded_creature_markers:", loop_at + 1)
	var loop_body := body.substr(loop_at, next_loop_at - loop_at) if next_loop_at != -1 else body.substr(loop_at)
	# This is the WADER loop (the first occurrence) if it doesn't contain
	# tread_snow_at -- skip to the merged loop in that case, the same
	# "search forward for the real one" shape test_world_footstep_wiring.gd
	# already uses for record_footstep's own two occurrences.
	if not loop_body.contains("tread_snow_at"):
		loop_at = next_loop_at
		assert_gt(loop_at, -1, "expected a second loop over the cached list")
		var third_loop_at := body.find("for creature in loaded_creature_markers:", loop_at + 1)
		loop_body = body.substr(loop_at, third_loop_at - loop_at) if third_loop_at != -1 else body.substr(loop_at)
	assert_true(loop_body.contains("tread_snow_at("), "the merged loop must still tread snow per creature")
	assert_true(loop_body.contains("record_footstep("), "the merged loop must still record a footstep per creature")


## The crush loop's own POSITION relative to the player-only crush block
## must be completely unchanged by this consolidation -- see this file's
## own class doc comment for why (the Karma-charging tests in
## test_world_crush_wiring.gd depend on it). The LAST
## "for creature in loaded_creature_markers:" occurrence is the crush
## loop (the merge above only touches the first two consumers), and the
## player's own (Karma-eligible) crush calls must all still precede it.
func test_the_crush_loop_still_runs_after_the_players_own_karma_eligible_crush_calls():
	var body := _function_body("_client_process")
	var crush_loop_at := body.rfind("for creature in loaded_creature_markers:")
	assert_gt(crush_loop_at, -1)
	for call_name in ["crush_worm_at(", "crush_caterpillars_near(", "crush_millipedes_near(", "crush_ants_near(", "crush_decomposers_near(", "crush_mushroom_at("]:
		var player_call_at := body.find(call_name)
		assert_gt(player_call_at, -1, "%s should still have a player call site" % call_name)
		assert_lt(
			player_call_at, crush_loop_at,
			"%s's player call site must still precede the crush loop" % call_name
		)
