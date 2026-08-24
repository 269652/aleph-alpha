extends GutTest

## BridgekeeperEncounter (docs/concept/easter_eggs.md's "Monty Python's
## Bridgekeeper (three-riddle NPC)"): a rarely-encountered wandering NPC
## blocking a narrow crossing who asks three short ORIGINAL riddles before
## letting the player pass either way -- "failing a riddle is harmless, just
## a silly non-consequence rather than a real penalty" (the doc's own
## words), unlike the film's own rather more dramatic outcome. The film's
## own three questions are its own script; RIDDLES below are original
## wordplay riddles instead, pinned by test_riddle_lines_do_not_quote_the_
## films_own_questions below the same way test_wargames_response.gd already
## pins WarGamesResponse against that film's own dialogue.
##
## Reuses GeoCoordinates + chance_per_check exactly like EasterEggSightings
## (see that module's own doc comment for the shared rationale) for the rare
## encounter trigger; riddle_text/is_correct_answer/passage_message are
## pure lookups a caller (scenes/world.gd's /answer console command) drives
## with real player-typed text, the same "caller supplies the real input,
## module only decides" shape every sibling module in this family uses.

const BridgekeeperEncounter = preload("res://src/gameplay/bridgekeeper_encounter.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")

var bridgekeeper: BridgekeeperEncounter
var world_width: int
var world_height: int


func before_each():
	bridgekeeper = BridgekeeperEncounter.new()
	world_width = EarthChunkGenerator.WORLD_WIDTH_TILES
	world_height = EarthChunkGenerator.WORLD_HEIGHT_TILES


func test_riddle_count_is_three():
	assert_eq(bridgekeeper.riddle_count(), 3)


func test_every_riddle_text_is_a_real_nonempty_line():
	for i in range(bridgekeeper.riddle_count()):
		assert_true(bridgekeeper.riddle_text(i).length() > 0, "riddle %d" % i)


func test_riddle_lines_do_not_quote_the_films_own_questions():
	var all_text := ""
	for i in range(bridgekeeper.riddle_count()):
		all_text += bridgekeeper.riddle_text(i).to_lower() + "\n"
	var forbidden_phrases := [
		"what is your name",
		"what is your quest",
		"what is your favorite colour",
		"what is your favorite color",
		"african or european swallow",
	]
	for phrase in forbidden_phrases:
		assert_false(all_text.contains(phrase), "should not quote: %s" % phrase)


func test_is_correct_answer_true_for_the_pinned_answer_case_insensitively():
	assert_true(bridgekeeper.is_correct_answer(0, "RIVER"))


func test_is_correct_answer_true_with_surrounding_whitespace():
	assert_true(bridgekeeper.is_correct_answer(0, "  river  "))


func test_is_correct_answer_false_for_a_wrong_guess():
	assert_false(bridgekeeper.is_correct_answer(0, "a hamburger"))


func test_is_correct_answer_false_for_an_out_of_range_index():
	assert_false(bridgekeeper.is_correct_answer(99, "river"))


func test_passage_message_always_lets_the_player_pass_regardless_of_score():
	for correct_count in range(0, 4):
		var message := bridgekeeper.passage_message(correct_count)
		assert_true(message.length() > 0, "correct_count %d" % correct_count)


func test_is_in_range_true_at_the_bridgekeepers_own_tile():
	var tile := bridgekeeper.tile(world_width, world_height)
	assert_true(bridgekeeper.is_in_range(tile.x, tile.y, world_width, world_height))


func test_is_in_range_false_far_from_the_crossing():
	var far_tile := Vector2i(world_width / 2, world_height / 2)
	assert_false(bridgekeeper.is_in_range(far_tile.x, far_tile.y, world_width, world_height))


## Relative property test (same discipline as EasterEggSightings' own
## rarity-comparison tests): rare enough that a single check almost always
## misses, pinned as a relative bound rather than an eyeballed inline
## number -- see CHANCE_PER_CHECK's own comment for why this is a first-pass
## placeholder.
func test_chance_per_check_is_rare():
	assert_true(BridgekeeperEncounter.CHANCE_PER_CHECK < 0.05)


func test_check_returns_false_when_roll_does_not_clear_the_chance():
	var tile := bridgekeeper.tile(world_width, world_height)
	assert_false(bridgekeeper.check(tile.x, tile.y, world_width, world_height, 0.999))


func test_check_returns_true_when_in_range_and_roll_clears_the_chance():
	var tile := bridgekeeper.tile(world_width, world_height)
	assert_true(bridgekeeper.check(tile.x, tile.y, world_width, world_height, 0.0))


func test_check_returns_false_out_of_range_even_with_a_guaranteed_roll():
	assert_false(bridgekeeper.check(0, 0, world_width, world_height, 0.0))
