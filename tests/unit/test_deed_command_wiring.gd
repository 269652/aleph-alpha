extends GutTest

## The Deed is the player-facing verb for becoming a member of the settlement
## you claim land in (see concept/player_citizenship.md's "Residency", and
## EarthChunkManager.record_player_settled_if_new).
##
## `claim_property_with_deed` takes the settlement as an OPTIONAL second
## argument, which is what keeps claiming land in open wilderness working --
## and is also exactly how the whole feature can end up unreachable while every
## one of its own unit tests stays green, because those tests pass a settlement
## themselves. This file pins the call site instead: if `/deed` stops naming a
## settlement, residency silently stops happening in the running game.
##
## Its own tiny file (reads one source file, builds no nodes) so it runs in
## about a second rather than living in test_earth_chunk_manager.gd, which
## takes ten-plus minutes. Same shape as test_world_backup_paths.gd.


## The body of World._handle_deed_command, straight from source.
func _deed_body() -> String:
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find("func _handle_deed_command(")
	assert_gt(start, -1, "World._handle_deed_command should still exist")
	var end := source.find("\nfunc ", start + 1)
	if end == -1:
		end = source.length()
	return source.substr(start, end - start)


func test_the_deed_command_passes_a_settlement_to_the_claim():
	var body := _deed_body()
	var call_start := body.find("claim_property_with_deed(")
	assert_gt(call_start, -1, "the deed command should still claim the property")
	var call_end := body.find(")", call_start)
	var call_text := body.substr(call_start, call_end - call_start)
	assert_string_contains(call_text, "settlement")


## The settlement is named from the chunk the player is standing in -- the same
## chunk the property id is already derived from, so the deed cannot claim land
## in one place and make you a citizen of another.
func test_the_settlement_comes_from_the_chunk_the_player_stands_in():
	var body := _deed_body()
	assert_string_contains(body, "EntityRef.for_settlement(")
	var chunk_read := body.find("var chunk")
	var settlement := body.find("EntityRef.for_settlement(")
	assert_gt(chunk_read, -1, "the deed command should still resolve the player's chunk")
	assert_lt(chunk_read, settlement, "the settlement must be derived from that chunk")


## The claim itself must still be unconditional. Residency is guarded inside
## record_player_settled_if_new (a settlement with no history is not a
## settlement), NOT by the caller refusing to claim -- otherwise claiming land
## in open wilderness, which is legitimate, would stop working.
func test_claiming_is_not_gated_on_a_settlement_existing():
	var body := _deed_body()
	var claim := body.find("claim_property_with_deed(")
	var guard := body.find("if ", body.find("var property_id"))
	if guard != -1:
		assert_lt(
			claim, guard,
			"no new guard may sit between deriving the property and claiming it"
		)
	assert_string_contains(body, "Claimed %s for household %s.")
