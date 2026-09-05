extends GutTest

## World._client_process's worm-crush wiring (see docs/concept/soil_fauna.md
## "Crushed underfoot: weight-emergent worm mortality") -- a source-contract
## test on the function body rather than a live one, the same shape and
## reasoning test_world_path_scarring_trail_wiring.gd already uses:
## _client_process resolves multiplayer internally rather than taking an
## already-resolved player, so standing up a whole World node headlessly to
## drive it live is not worth the fight.

const World = preload("res://scenes/world.gd")


func _client_process_body() -> String:
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find("func _client_process")
	assert_gt(start, -1, "the premise: this function must still exist and be named that")
	var body_end := source.find("\nfunc ", start + 1)
	return source.substr(start, body_end - start)


func test_the_premise_the_other_tests_rely_on():
	var body := _client_process_body()
	assert_true(body.contains("crush_worm_at"), "must still call the crush mechanism at all")


## The player's own step must use a real mass-derived momentum, not a
## placeholder -- _PLAYER_STEP_MOMENTUM_KG_M_S (precomputed once from
## CreatureMass.PLAYER_MASS_KG * PebbleDispersion.FOOTSTEP_SPEED_MPS,
## rather than recomputed every frame for two constants that never
## change at runtime) is the one place that real number lives.
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
## shared number, decides whether its step crushes a worm -- so the wiring
## must read info.species and pass it through CreatureMass.mass_kg_for per
## creature, not compute one momentum value for every species alike.
func test_each_creatures_own_species_drives_its_own_momentum():
	var body := _client_process_body()
	assert_true(body.contains("CreatureMass.mass_kg_for"))
	assert_true(body.contains("marker.info.species") or body.contains(".info.species"))


## Both the player and every creature must actually reach crush_worm_at --
## a wiring that computed momentum but never called through would silently
## do nothing.
func test_crush_worm_at_is_called_for_both_the_player_and_creatures():
	var body := _client_process_body()
	var crush_calls := 0
	var search_from := 0
	while true:
		var found := body.find("crush_worm_at(", search_from)
		if found == -1:
			break
		crush_calls += 1
		search_from = found + 1
	assert_eq(crush_calls, 2, "expected exactly one call for the player and one inside the creature loop")


## Mirrors tread_snow_at's own "player position, then every CreatureMarker
## in the group" shape -- the creature crush call must sit inside a real
## loop over CreatureMarker.GROUP_NAME, not just be textually present
## somewhere in the function.
func test_the_creature_crush_call_is_inside_a_creaturemarker_group_loop():
	var body := _client_process_body()
	var group_loop_at := body.find("get_nodes_in_group(CreatureMarker.GROUP_NAME)")
	var creature_crush_at := body.rfind("crush_worm_at(")
	assert_gt(group_loop_at, -1)
	assert_gt(creature_crush_at, -1)
	assert_lt(group_loop_at, creature_crush_at, "the creature crush call must come after entering the group loop")
