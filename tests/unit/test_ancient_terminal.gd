extends GutTest

## AncientTerminal (docs/concept/easter_eggs.md's "A found ancient terminal
## (Zork homage, not reproduction)"): a fixed real-world location (reusing
## GeoCoordinates' reverse lookup + radius exactly like every other real-
## coordinate cameo in this project -- RushAmbientCue/EasterEggSightings)
## plus a few lines of fully original, old-school-parser-style prose. Zork's
## own prose is Infocom/Activision's copyrighted text (pillar 4, "homage
## over reproduction") -- these tests pin both "there are real lines" and
## "those lines are not a transcript of Zork's own famous text", the same
## discipline test_wargames_response.gd already applies to the WarGames egg.
##
## Also pins the has_been_found()/mark_found() signal this module exposes
## for the eventual "Three Fragments" hunt (docs/concept/easter_eggs.md) to
## check against later -- this stage only builds the clean, testable signal,
## not the fragment-drop/aggregation logic itself.

const AncientTerminal = preload("res://src/gameplay/ancient_terminal.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")

var terminal: AncientTerminal
var world_width: int
var world_height: int


func before_each():
	terminal = AncientTerminal.new()
	world_width = EarthChunkGenerator.WORLD_WIDTH_TILES
	world_height = EarthChunkGenerator.WORLD_HEIGHT_TILES


func test_terminal_lines_are_a_real_multi_line_sequence():
	assert_true(terminal.terminal_lines().size() > 1)


func test_terminal_lines_do_not_quote_zorks_own_famous_text():
	var joined := "\n".join(terminal.terminal_lines()).to_lower()
	var forbidden_phrases := [
		"west of house",
		"you are likely to be eaten by a grue",
		"there is a small mailbox here",
		"it is pitch black",
	]
	for phrase in forbidden_phrases:
		assert_false(joined.contains(phrase), "should not quote: %s" % phrase)


func test_is_in_range_true_at_the_terminals_own_tile():
	var tile := terminal.tile(world_width, world_height)
	assert_true(terminal.is_in_range(tile.x, tile.y, world_width, world_height))


func test_is_in_range_false_far_from_the_terminal():
	var far_tile := Vector2i(world_width / 2, world_height / 2)
	assert_false(terminal.is_in_range(far_tile.x, far_tile.y, world_width, world_height))


func test_not_found_until_marked():
	assert_false(terminal.has_been_found())


func test_mark_found_latches_true():
	terminal.mark_found()
	assert_true(terminal.has_been_found())
