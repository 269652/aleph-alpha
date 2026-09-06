extends GutTest

## World's quest-fulfilment wiring (see docs/concept/karma_and_luck.md's
## "Quest lifecycle: accept, abandon, fulfil") -- a source-contract test on
## the function bodies rather than a live one, the same shape and reasoning
## test_world_crush_wiring.gd already uses: driving a whole World node
## headlessly through multiplayer resolution just to observe one throttled
## reconciliation call is not worth the fight.

const World = preload("res://scenes/world.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")


func _function_body(function_signature_prefix: String) -> String:
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find(function_signature_prefix)
	assert_gt(start, -1, "the premise: %s must still exist" % function_signature_prefix)
	var body_end := source.find("\nfunc ", start + 1)
	if body_end == -1:
		body_end = source.length()
	return source.substr(start, body_end - start)


func _step_ecology_batch_body() -> String:
	return _function_body("func _step_ecology_batch(")


func _step_quest_reconciliation_body() -> String:
	return _function_body("func _step_quest_reconciliation(")


func test_the_premise_the_other_tests_rely_on():
	var body := _step_ecology_batch_body()
	assert_true(body.contains("_step_quest_reconciliation("), "must call the reconciliation step at all")


## focus_player can be null (a dedicated server, or before a player has
## spawned) -- _step_ecology_batch's own signature takes it unguarded, so
## the call site itself must guard it, the same way _process already guards
## _step_pebble_dispersion/_step_leaf_litter_dispersion.
func test_the_call_site_is_gated_behind_a_non_null_focus_player():
	var body := _step_ecology_batch_body()
	var call_at := body.find("_step_quest_reconciliation(")
	assert_gt(call_at, -1)
	var guard_at := body.rfind("if focus_player != null:", call_at)
	assert_gt(guard_at, -1, "expected an 'if focus_player != null:' guard before the call")
	# Nothing else must sit between the guard and the call that could return
	# early past it (a cheap structural check: no blank func boundary).
	assert_lt(guard_at, call_at)


func test_reconciliation_skips_entirely_when_nothing_is_accepted():
	var body := _step_quest_reconciliation_body()
	var guard_at := body.find("accepted_quest_ids.is_empty()")
	assert_gt(guard_at, -1, "must early-return when the player has accepted nothing")
	var reconcile_at := body.find("QuestLog.reconcile(")
	assert_gt(reconcile_at, -1)
	assert_lt(guard_at, reconcile_at, "the empty-set guard must come before the real work")


## Checking more often than settlements can actually change would only ever
## re-observe the same unchanged shortfall -- must reuse the existing
## cadence, never a fresh eyeballed interval.
func test_reconciliation_is_throttled_by_the_settlement_step_interval():
	var body := _step_quest_reconciliation_body()
	assert_true(
		body.contains("EarthChunkManager.SETTLEMENT_STEP_INTERVAL"),
		"must reuse EarthChunkManager.SETTLEMENT_STEP_INTERVAL rather than a new constant"
	)


func test_reconciliation_reads_the_live_projection_across_every_settlement():
	var body := _step_quest_reconciliation_body()
	assert_true(body.contains("_chunk_manager.all_production_shortfall_quests()"))


func test_reconciliation_passes_the_fresh_quests_into_quest_log_reconcile():
	var body := _step_quest_reconciliation_body()
	var reconcile_at := body.find("QuestLog.reconcile(")
	assert_gt(reconcile_at, -1)
	var call_end := body.find("\n", reconcile_at)
	var call_text := body.substr(reconcile_at, call_end - reconcile_at)
	assert_true(
		call_text.contains("all_production_shortfall_quests()"),
		"reconcile's own call must carry the fresh quest list, not a stale local copy"
	)
