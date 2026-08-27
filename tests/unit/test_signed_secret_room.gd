extends GutTest

## SignedSecretRoom (docs/concept/easter_eggs.md's "A signed secret room
## (Atari Adventure homage -- the deepest cut)"): repeats Warren Robinett's
## actual 1980 gesture -- a small, genuinely hard-to-reach room reachable
## only via an obscure action sequence (not a coordinate alone, per the
## doc's own wording), containing nothing but a quiet signature/credit.
##
## Pure logic only -- matches_sequence is a plain "does this exact ordered
## list of recently-pressed action names equal the required sequence"
## check, so it's testable with plain Arrays, no Input/scene-tree
## dependency, the same shape every other pure decision module in this
## project family uses (EasterEggSightings.check_one, RushAmbientCue.
## is_in_range).

const SignedSecretRoom = preload("res://src/gameplay/signed_secret_room.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")

var room: SignedSecretRoom
var world_width: int
var world_height: int


func before_each():
	room = SignedSecretRoom.new()
	world_width = EarthChunkGenerator.WORLD_WIDTH_TILES
	world_height = EarthChunkGenerator.WORLD_HEIGHT_TILES


func test_is_in_range_true_at_the_rooms_own_tile():
	var tile := room.tile(world_width, world_height)
	assert_true(room.is_in_range(tile.x, tile.y, world_width, world_height))


func test_is_in_range_false_far_from_the_room():
	var far_tile := Vector2i(world_width / 2, world_height / 2)
	assert_false(room.is_in_range(far_tile.x, far_tile.y, world_width, world_height))


func test_matches_sequence_true_for_the_exact_required_order():
	assert_true(room.matches_sequence(SignedSecretRoom.ACTION_SEQUENCE))


func test_matches_sequence_false_for_wrong_order():
	var reversed_sequence := SignedSecretRoom.ACTION_SEQUENCE.duplicate()
	reversed_sequence.reverse()
	assert_false(room.matches_sequence(reversed_sequence))


func test_matches_sequence_false_for_a_shorter_prefix():
	var prefix: Array = SignedSecretRoom.ACTION_SEQUENCE.slice(0, SignedSecretRoom.ACTION_SEQUENCE.size() - 1)
	assert_false(room.matches_sequence(prefix))


func test_matches_sequence_false_for_unrelated_actions():
	assert_false(room.matches_sequence(["attack", "attack", "attack", "attack"]))


func test_matches_sequence_ignores_anything_before_the_tail():
	var padded: Array = ["attack", "attack"] + SignedSecretRoom.ACTION_SEQUENCE
	assert_true(room.matches_sequence(padded))


func test_credit_text_is_a_real_nonempty_line():
	assert_true(room.credit_text().length() > 0)


func test_not_found_until_marked():
	assert_false(room.has_been_found())


func test_mark_found_latches_true():
	room.mark_found()
	assert_true(room.has_been_found())
