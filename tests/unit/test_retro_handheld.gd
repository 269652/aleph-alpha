extends GutTest

## RetroHandheldProp (docs/concept/easter_eggs.md's "hidden retro handheld"
## entry): the location + interaction gate for the battered handheld prop
## itself, mirroring AncientTerminal/SeaCaveGuardian's own established
## real-coordinate + "talk" interaction shape. This module only tracks
## WHERE the prop is and WHETHER its mini-game screen is currently open --
## the battle/catch/collection rules live entirely in HandheldBattle/
## HandheldCatch/HandheldCollection (each covered by their own test file);
## the actual playable screen lives in HandheldBattleView.
##
## Repeatable by design, like SeaCaveGuardian (not a one-shot
## has_been_found() latch like AncientTerminal/SignedSecretRoom): a handheld
## you can pick back up and keep playing/catching on is more in the spirit
## of a real found prop than a one-time cutscene. is_open() alone gates
## re-triggering while the mini-game is already showing.
##
## flavor_line(already_found) is the one place this module DOES distinguish
## first discovery from every visit after -- a quieter "you found it" beat
## the first time, a plain "it's on again" beat every time after, without
## needing two separate one-shot/repeatable systems layered on each other.

const RetroHandheld = preload("res://src/gameplay/retro_handheld.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")

var prop: RetroHandheld
var world_width: int
var world_height: int


func before_each():
	prop = RetroHandheld.new()
	world_width = EarthChunkGenerator.WORLD_WIDTH_TILES
	world_height = EarthChunkGenerator.WORLD_HEIGHT_TILES


func test_is_in_range_true_at_the_props_own_tile():
	var tile := prop.tile(world_width, world_height)
	assert_true(prop.is_in_range(tile.x, tile.y, world_width, world_height))


func test_is_in_range_false_far_from_the_prop():
	var far_tile := Vector2i(world_width / 2, world_height / 2)
	assert_false(prop.is_in_range(far_tile.x, far_tile.y, world_width, world_height))


func test_not_open_initially():
	assert_false(prop.is_open())


func test_can_open_true_when_in_range_and_not_already_open():
	var tile := prop.tile(world_width, world_height)
	assert_true(prop.can_open(tile.x, tile.y, world_width, world_height))


func test_can_open_false_when_out_of_range():
	var far_tile := Vector2i(world_width / 2, world_height / 2)
	assert_false(prop.can_open(far_tile.x, far_tile.y, world_width, world_height))


func test_can_open_false_while_already_open():
	var tile := prop.tile(world_width, world_height)
	prop.open()
	assert_false(prop.can_open(tile.x, tile.y, world_width, world_height))


func test_open_sets_is_open_true():
	prop.open()
	assert_true(prop.is_open())


func test_close_clears_is_open():
	prop.open()
	prop.close()
	assert_false(prop.is_open())


func test_can_open_true_again_after_closing():
	var tile := prop.tile(world_width, world_height)
	prop.open()
	prop.close()
	assert_true(prop.can_open(tile.x, tile.y, world_width, world_height))


## --- found latch: only gates which flavor_line plays, never can_open ---


func test_not_found_initially():
	assert_false(prop.has_been_found())


func test_mark_found_sets_has_been_found_true():
	prop.mark_found()
	assert_true(prop.has_been_found())


func test_flavor_line_differs_for_first_find_vs_a_later_visit():
	assert_ne(prop.flavor_line(false), prop.flavor_line(true))


func test_flavor_lines_are_both_non_empty():
	assert_true(prop.flavor_line(false).length() > 0)
	assert_true(prop.flavor_line(true).length() > 0)


func test_flavor_line_never_names_a_trademarked_handheld_brand():
	# Pillar 4/the doc's own explicit ask: "generic, undescribed hardware --
	# no trademarked shape or logo".
	var lowered_found := prop.flavor_line(false).to_lower()
	var lowered_again := prop.flavor_line(true).to_lower()
	for banned in ["nintendo", "game boy", "gameboy", "pokémon", "pokemon"]:
		assert_false(lowered_found.contains(banned), banned)
		assert_false(lowered_again.contains(banned), banned)
