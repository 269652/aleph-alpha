extends GutTest

## World._client_process's "crushed underfoot" wiring (see docs/concept/
## soil_fauna.md "Crushed underfoot: weight-emergent worm mortality" and
## its "Generalized to caterpillars too" follow-up) -- a source-contract
## test on the function body rather than a live one, the same shape and
## reasoning test_world_path_scarring_trail_wiring.gd already uses:
## _client_process resolves multiplayer internally rather than taking an
## already-resolved player, so standing up a whole World node headlessly to
## drive it live is not worth the fight.
##
## Formerly test_world_worm_crush_wiring.gd, renamed here (2026-09-06) once
## crush_caterpillars_near joined crush_worm_at as a second call sharing
## the identical wiring shape -- every test below now has a worm half and
## a caterpillar half, asserting the same structural property against
## each call. crush_millipedes_near joined as a third call the same day
## (see docs/concept/soil_fauna.md "Generalized to millipedes too") -- a
## millipede is the identical shape of victim a caterpillar already is.
## crush_ants_near joined as a fourth call (reported live: "ants are also
## not crushed when a player is walking over them") -- an ant forager is
## the same shape of victim again (a real, independently-positioned
## Node2D), so it shares the identical wiring shape and Karma treatment,
## even though EarthChunkManager.crush_ants_near itself cannot share
## _crush_markers_near's own body (see that function's own doc comment).
## crush_decomposers_near joined as a fifth call (asked directly: "a bug
## should count as a small creature too") -- a DecomposerMarker is the
## same shape of victim as a caterpillar/millipede (a real,
## independently-positioned Node2D, chunk-keyed exactly like those two),
## so it shares _crush_markers_near's own body and the identical Karma
## treatment.

const World = preload("res://scenes/world.gd")


func _client_process_body() -> String:
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find("func _client_process")
	assert_gt(start, -1, "the premise: this function must still exist and be named that")
	var body_end := source.find("\nfunc ", start + 1)
	return source.substr(start, body_end - start)


func test_the_premise_the_other_tests_rely_on():
	var body := _client_process_body()
	assert_true(body.contains("crush_worm_at"), "must still call the worm crush mechanism at all")
	assert_true(body.contains("crush_caterpillars_near"), "must also call the caterpillar crush mechanism")
	assert_true(body.contains("crush_millipedes_near"), "must also call the millipede crush mechanism")
	assert_true(body.contains("crush_ants_near"), "must also call the ant crush mechanism")
	assert_true(body.contains("crush_decomposers_near"), "must also call the decomposer/bug crush mechanism")


## The player's own step must use a real mass-derived momentum, not a
## placeholder. Corrected (2026-09-07, see docs/concept/metabolism.md's
## "one real mass per creature" pillar): a fixed, precomputed-once constant
## would freeze the player's momentum at their SEED mass forever, exactly
## the two-competing-mass-concepts shape that doc's own live correction
## rejected -- so this is now a live per-frame read of the player's own
## real, unified current_mass_kg(), computed once per _client_process call
## (_player_step_momentum_kg_m_s) and reused for every crush call, still
## one shared physics value per stepper, not a placeholder or a
## per-call-site guess.
func test_the_players_own_step_uses_a_real_mass_derived_momentum():
	var body := _client_process_body()
	assert_true(body.contains("player_step_momentum_kg_m_s"))
	assert_true(body.contains("local_player.position"))
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	assert_true(
		source.contains("player.current_mass_kg() * PebbleDispersion.FOOTSTEP_SPEED_MPS"),
		"the player's own step momentum must read their real, live, unified mass, not a fixed guess"
	)


## The whole point of the mechanic: a creature's own real mass, not a flat
## shared number, decides whether its step crushes anything underfoot.
## Corrected (2026-09-07, see docs/concept/metabolism.md): this now reads
## each creature's own real, live, unified current_mass_kg() -- seeded
## from CreatureMass.mass_kg_for(species) but updated afterward by that
## creature's own real metabolism -- rather than re-deriving a flat
## species-average momentum from CreatureMass every frame.
func test_each_creatures_own_species_drives_its_own_momentum():
	var body := _client_process_body()
	assert_true(body.contains("marker.current_mass_kg()"))


## Both the player and every creature must actually reach crush_worm_at --
## a wiring that computed momentum but never called through would
## silently do nothing.
func test_crush_worm_at_is_called_for_both_the_player_and_creatures():
	var body := _client_process_body()
	assert_eq(_count_occurrences(body, "crush_worm_at("), 2, "expected exactly one call for the player and one inside the creature loop")


## The caterpillar-shaped mirror of the test above: crush_caterpillars_near
## must reach exactly the same two call sites, not just one of them -- a
## wiring that only crushed caterpillars for the player, say, would leave
## a wolf or deer able to crush worms but not caterpillars, an
## inconsistency nothing else here would catch.
func test_crush_caterpillars_near_is_called_for_both_the_player_and_creatures():
	var body := _client_process_body()
	assert_eq(_count_occurrences(body, "crush_caterpillars_near("), 2, "expected exactly one call for the player and one inside the creature loop")


## The millipede-shaped mirror of the two tests above.
func test_crush_millipedes_near_is_called_for_both_the_player_and_creatures():
	var body := _client_process_body()
	assert_eq(_count_occurrences(body, "crush_millipedes_near("), 2, "expected exactly one call for the player and one inside the creature loop")


## The ant-shaped mirror of the three tests above.
func test_crush_ants_near_is_called_for_both_the_player_and_creatures():
	var body := _client_process_body()
	assert_eq(_count_occurrences(body, "crush_ants_near("), 2, "expected exactly one call for the player and one inside the creature loop")


## The decomposer/bug-shaped mirror of the four tests above.
func test_crush_decomposers_near_is_called_for_both_the_player_and_creatures():
	var body := _client_process_body()
	assert_eq(_count_occurrences(body, "crush_decomposers_near("), 2, "expected exactly one call for the player and one inside the creature loop")


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


## Mirrors tread_snow_at's own "player position, then every CreatureMarker
## in the group" shape -- BOTH creature crush calls must sit inside a real
## loop over CreatureMarker.GROUP_NAME, not just be textually present
## somewhere in the function.
func test_the_creature_crush_calls_are_inside_a_creaturemarker_group_loop():
	var body := _client_process_body()
	var group_loop_at := body.find("get_nodes_in_group(CreatureMarker.GROUP_NAME)")
	var worm_crush_at := body.rfind("crush_worm_at(")
	var caterpillar_crush_at := body.rfind("crush_caterpillars_near(")
	var millipede_crush_at := body.rfind("crush_millipedes_near(")
	var ant_crush_at := body.rfind("crush_ants_near(")
	var decomposer_crush_at := body.rfind("crush_decomposers_near(")
	assert_gt(group_loop_at, -1)
	assert_gt(worm_crush_at, -1)
	assert_gt(caterpillar_crush_at, -1)
	assert_gt(millipede_crush_at, -1)
	assert_gt(ant_crush_at, -1)
	assert_gt(decomposer_crush_at, -1)
	assert_lt(group_loop_at, worm_crush_at, "the creature worm-crush call must come after entering the group loop")
	assert_lt(group_loop_at, caterpillar_crush_at, "the creature caterpillar-crush call must come after entering the group loop")
	assert_lt(group_loop_at, millipede_crush_at, "the creature millipede-crush call must come after entering the group loop")
	assert_lt(group_loop_at, ant_crush_at, "the creature ant-crush call must come after entering the group loop")
	assert_lt(group_loop_at, decomposer_crush_at, "the creature decomposer-crush call must come after entering the group loop")


# -- Karma (see docs/concept/karma_and_luck.md) ------------------------------
#
# Reported live: "Karma is constantly decreasing when wild animals step on
# worms... it should only decrease when the player itself steps on
# something... the player must do it." Reverses the earlier "every crush
# counts, player's own step OR any creature's" design (see karma_and_luck.md's
# own 2026-09-07 reversal note) -- only the PLAYER's own step now applies
# the penalty; a wild creature's own step still crushes what's underfoot
# (a real ecosystem effect), it just never touches Karma, the same as
# crush_walnut_near (never Karma-eligible for anyone) already didn't.
# Millipedes (docs/concept/soil_fauna.md "Generalized to millipedes too"),
# ants (docs/concept/soil_fauna.md "Generalized to ants too") and bugs
# (docs/concept/soil_fauna.md "Generalized to bugs too") charge the SAME
# constant a worm/caterpillar crush already does -- the name predates all
# three, but the event it represents ("a small, harmless invertebrate died
# underfoot") is identical (see karma.gd's own doc comment).


func test_only_the_players_own_crush_calls_apply_the_karma_penalty():
	var body := _client_process_body()
	assert_eq(
		_count_occurrences(body, "apply_karma_delta(-Karma.WORM_OR_CATERPILLAR_CRUSH_PENALTY)"),
		6,
		"expected the penalty applied at exactly the 6 player-only crush call sites (worm+caterpillar+millipede+ant+decomposer+mushroom)"
	)


## The player's own 6 Karma-eligible crush calls -- the ones before the
## CreatureMarker loop -- must each still be gated behind their own `if`,
## charged only when a crush actually happened.
func test_the_players_own_karma_penalty_is_only_charged_when_a_crush_actually_happens():
	var body := _client_process_body()
	# rfind, not find: an EARLIER, unrelated CreatureMarker.GROUP_NAME loop
	# (snow-treading, see the tread_snow_at pairing this block's own doc
	# comment mirrors) sits before the crush block entirely -- the crush
	# pass's own creature loop is the LAST such loop in this function.
	var group_loop_at := body.rfind("get_nodes_in_group(CreatureMarker.GROUP_NAME)")
	assert_gt(group_loop_at, -1)
	for call_name in ["crush_worm_at(", "crush_caterpillars_near(", "crush_millipedes_near(", "crush_ants_near(", "crush_decomposers_near(", "crush_mushroom_at("]:
		var at := body.find(call_name)
		assert_gt(at, -1, "%s should still have a player call site" % call_name)
		assert_lt(at, group_loop_at, "%s's player call site must come before the creature loop" % call_name)
		var line_start := body.rfind("\n", at) + 1
		var line := body.substr(line_start, at - line_start).strip_edges()
		assert_true(line.begins_with("if "), "%s's player call must be an if's condition, found: %s" % [call_name, line])


## The reversal itself: a wild creature's own crush (inside the
## CreatureMarker loop) is now a bare statement, never gated behind an
## `if` and never followed by apply_karma_delta -- the exact shape
## crush_walnut_near (never Karma-eligible for anyone) has always used.
## The crush mechanic still runs (a deer's own step still kills the worm
## underfoot); only the Karma side effect is gone.
func test_a_creatures_own_crush_never_applies_the_karma_penalty():
	var body := _client_process_body()
	# rfind, not find -- see the sibling test above's own comment on why.
	var group_loop_at := body.rfind("get_nodes_in_group(CreatureMarker.GROUP_NAME)")
	assert_gt(group_loop_at, -1)
	for call_name in ["crush_worm_at(", "crush_caterpillars_near(", "crush_millipedes_near(", "crush_ants_near(", "crush_decomposers_near(", "crush_mushroom_at(", "crush_walnut_near("]:
		var at := body.rfind(call_name)
		assert_gt(at, -1, "%s should still have a creature call site" % call_name)
		assert_gt(at, group_loop_at, "%s's creature call site must come after entering the group loop" % call_name)
		var line_start := body.rfind("\n", at) + 1
		var line_end := body.find("\n", at)
		var line := body.substr(line_start, line_end - line_start).strip_edges()
		assert_false(
			line.begins_with("if "),
			"%s's creature call should be a bare statement, not if-guarded, found: %s" % [call_name, line]
		)
		assert_false(
			body.substr(at, line_end - at).contains("apply_karma_delta"),
			"%s's creature call site should never apply a Karma penalty" % call_name
		)


# -- mushrooms (see docs/concept/mushrooms.md, WildMushroomPatch.crush) -----
#
# Reported live: "A mushroom is a physical entity... when you walk over
# one it should be crushed because of the player weight." Mirrors the
# worm/caterpillar wiring's exact shape (same momentum per stepper, same
# player-then-creature-loop structure).
#
# Originally shipped WITHOUT a Karma penalty -- "a mushroom is a fungus,
# not an animal" -- but asked directly, as part of "instant karma
# feedback": a mushroom should cost Karma the same as a bug/ant/
# caterpillar. Reversed here (see docs/concept/mushrooms.md's own Status
# note on the reversal): crush_mushroom_at's bool return now feeds Karma
# for the PLAYER's own step exactly like every other crush call above, so
# test_only_the_players_own_crush_calls_apply_the_karma_penalty's count
# includes it too (its creature-loop call site is covered by
# test_a_creatures_own_crush_never_applies_the_karma_penalty instead --
# see that section's own reversal note).

func test_crush_mushroom_at_is_called_for_both_the_player_and_creatures():
	var body := _client_process_body()
	assert_eq(
		_count_occurrences(body, "crush_mushroom_at("), 2,
		"expected exactly one call for the player and one inside the creature loop"
	)


func test_the_creature_mushroom_crush_call_is_inside_a_creaturemarker_group_loop():
	var body := _client_process_body()
	var group_loop_at := body.find("get_nodes_in_group(CreatureMarker.GROUP_NAME)")
	var mushroom_crush_at := body.rfind("crush_mushroom_at(")
	assert_gt(group_loop_at, -1)
	assert_gt(mushroom_crush_at, -1)
	assert_lt(group_loop_at, mushroom_crush_at, "the creature mushroom-crush call must come after entering the group loop")


# -- walnuts (see docs/concept/soil_fauna.md, EarthChunkManager.
# crush_walnut_near) -- reported live: "Same for walnuts (crack open)."
# Same wiring shape as mushrooms: player + creature loop, no Karma.

func test_crush_walnut_near_is_called_for_both_the_player_and_creatures():
	var body := _client_process_body()
	assert_eq(
		_count_occurrences(body, "crush_walnut_near("), 2,
		"expected exactly one call for the player and one inside the creature loop"
	)


func test_the_creature_walnut_crush_call_is_inside_a_creaturemarker_group_loop():
	var body := _client_process_body()
	var group_loop_at := body.find("get_nodes_in_group(CreatureMarker.GROUP_NAME)")
	var walnut_crush_at := body.rfind("crush_walnut_near(")
	assert_gt(group_loop_at, -1)
	assert_gt(walnut_crush_at, -1)
	assert_lt(group_loop_at, walnut_crush_at, "the creature walnut-crush call must come after entering the group loop")


func test_crushing_a_walnut_never_applies_a_karma_penalty():
	var body := _client_process_body()
	var search_from := 0
	var checked := 0
	while true:
		var at := body.find("crush_walnut_near(", search_from)
		if at == -1:
			break
		var line_start := body.rfind("\n", at) + 1
		var line_end := body.find("\n", at)
		var line := body.substr(line_start, line_end - line_start).strip_edges()
		assert_false(
			line.begins_with("if "),
			"crush_walnut_near should be a bare call, not gated behind an if (found: %s)" % line
		)
		assert_false(
			body.substr(at, line_end - at).contains("apply_karma_delta"),
			"crush_walnut_near's own line should never apply a Karma penalty"
		)
		checked += 1
		search_from = at + 1
	assert_eq(checked, 2, "should still have exactly 2 call sites")
