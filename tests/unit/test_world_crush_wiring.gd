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


## The player's own step must use a real mass-derived momentum, not a
## placeholder -- _PLAYER_STEP_MOMENTUM_KG_M_S (precomputed once from
## CreatureMass.PLAYER_MASS_KG * PebbleDispersion.FOOTSTEP_SPEED_MPS,
## rather than recomputed every frame for two constants that never change
## at runtime) is the one place that real number lives, reused for both
## crush calls -- a worm and a caterpillar are crushed by the same
## physics, not two independently-tuned numbers.
func test_the_players_own_step_uses_a_real_mass_derived_momentum():
	var body := _client_process_body()
	assert_true(body.contains("_PLAYER_STEP_MOMENTUM_KG_M_S"))
	assert_true(body.contains("local_player.position"))
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	assert_true(
		source.contains("_PLAYER_STEP_MOMENTUM_KG_M_S := CreatureMass.PLAYER_MASS_KG"),
		"the constant itself must actually derive from CreatureMass.PLAYER_MASS_KG, not an independent guess"
	)


## The whole point of the mechanic: a creature's own species, not a flat
## shared number, decides whether its step crushes anything underfoot --
## so the wiring must read info.species and pass it through
## CreatureMass.mass_kg_for per creature, not compute one momentum value
## for every species alike.
func test_each_creatures_own_species_drives_its_own_momentum():
	var body := _client_process_body()
	assert_true(body.contains("CreatureMass.mass_kg_for"))
	assert_true(body.contains("marker.info.species") or body.contains(".info.species"))


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
	assert_gt(group_loop_at, -1)
	assert_gt(worm_crush_at, -1)
	assert_gt(caterpillar_crush_at, -1)
	assert_gt(millipede_crush_at, -1)
	assert_lt(group_loop_at, worm_crush_at, "the creature worm-crush call must come after entering the group loop")
	assert_lt(group_loop_at, caterpillar_crush_at, "the creature caterpillar-crush call must come after entering the group loop")
	assert_lt(group_loop_at, millipede_crush_at, "the creature millipede-crush call must come after entering the group loop")


# -- Karma (see docs/concept/karma_and_luck.md) ------------------------------
#
# "Stepping on a worm should give -1 Karma", asked for every crush -- the
# player's own step OR any creature's -- not just the player's deliberate
# ones. A crush call that ran but never fed Karma would defeat the entire
# point of threading CrushMechanic's bool return value through at all.
# Millipedes (docs/concept/soil_fauna.md "Generalized to millipedes too")
# charge the SAME constant a worm/caterpillar crush already does -- the
# name predates the third species, but the event it represents ("a small,
# harmless decomposer died underfoot") is identical (see karma.gd's own
# doc comment).


func test_every_crush_call_site_applies_the_karma_penalty():
	var body := _client_process_body()
	assert_eq(
		_count_occurrences(body, "apply_karma_delta(-Karma.WORM_OR_CATERPILLAR_CRUSH_PENALTY)"),
		6,
		"expected the penalty applied at all 6 crush call sites (worm+caterpillar+millipede, player+creature loop)"
	)


## Each penalty must be gated behind its own crush call actually succeeding
## -- an `if <crush call>:` guard, not a bare statement charged every frame
## regardless of whether anything was actually crushed.
func test_the_karma_penalty_is_only_charged_when_a_crush_actually_happens():
	var body := _client_process_body()
	for call_name in ["crush_worm_at(", "crush_caterpillars_near(", "crush_millipedes_near("]:
		var search_from := 0
		var checked := 0
		while true:
			var at := body.find(call_name, search_from)
			if at == -1:
				break
			var line_start := body.rfind("\n", at) + 1
			var line := body.substr(line_start, at - line_start).strip_edges()
			assert_true(line.begins_with("if "), "%s call must be an if's condition, found: %s" % [call_name, line])
			checked += 1
			search_from = at + 1
		assert_eq(checked, 2, "%s should still have exactly 2 call sites" % call_name)


# -- mushrooms (see docs/concept/mushrooms.md, WildMushroomPatch.crush) -----
#
# Reported live: "A mushroom is a physical entity... when you walk over
# one it should be crushed because of the player weight." Mirrors the
# worm/caterpillar wiring's exact shape (same momentum per stepper, same
# player-then-creature-loop structure) but deliberately does NOT feed
# Karma the way crush_worm_at/crush_caterpillars_near do -- a mushroom is
# a fungus, not an animal, so the existing
# test_every_crush_call_site_applies_the_karma_penalty's count staying at
# 4 (not 6) is the real regression guard for that; the test below pins it
# explicitly rather than relying only on that count not changing.

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


## The deliberate divergence from the worm/caterpillar shape: neither
## crush_mushroom_at call site may be wrapped in an `if ...: apply_karma_
## delta(...)` guard -- crushing a mushroom costs no Karma.
func test_crushing_a_mushroom_never_applies_a_karma_penalty():
	var body := _client_process_body()
	var search_from := 0
	var checked := 0
	while true:
		var at := body.find("crush_mushroom_at(", search_from)
		if at == -1:
			break
		var line_start := body.rfind("\n", at) + 1
		var line_end := body.find("\n", at)
		var line := body.substr(line_start, line_end - line_start).strip_edges()
		assert_false(
			line.begins_with("if "),
			"crush_mushroom_at should be a bare call, not gated behind an if (found: %s)" % line
		)
		assert_false(
			body.substr(at, line_end - at).contains("apply_karma_delta"),
			"crush_mushroom_at's own line should never apply a Karma penalty"
		)
		checked += 1
		search_from = at + 1
	assert_eq(checked, 2, "should still have exactly 2 call sites")


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
