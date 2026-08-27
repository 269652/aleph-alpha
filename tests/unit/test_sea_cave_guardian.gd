extends GutTest

## SeaCaveGuardian (docs/concept/easter_eggs.md's "hidden sea cave...
## dueling-birds cabinet" entry): location + interaction gate for an
## ORIGINAL guardian (never RP1's own character -- see the module's own
## doc comment for the invented name) who challenges the player to a
## best-of-three aerial joust the instant a nearby stone seat visibly
## reconfigures into an arcade cabinet. This module only tracks WHERE the
## cave is and WHETHER a challenge is active -- the joust's own rules live
## entirely in JoustMatch (test_joust_match.gd covers that separately).
##
## Also pins that this cave sits at the exact same coordinate Squallmaw
## itself uses (EasterEggCreatures.SIGHTINGS["squallmaw"]) -- "alongside
## Squallmaw above" per the doc's own words -- so the two locations can
## never silently drift apart.

const SeaCaveGuardian = preload("res://src/gameplay/sea_cave_guardian.gd")
const EasterEggCreatures = preload("res://src/gameplay/easter_egg_creatures.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")

var guardian: SeaCaveGuardian
var world_width: int
var world_height: int


func before_each():
	guardian = SeaCaveGuardian.new()
	world_width = EarthChunkGenerator.WORLD_WIDTH_TILES
	world_height = EarthChunkGenerator.WORLD_HEIGHT_TILES


func test_location_matches_squallmaws_own_bermuda_triangle_coordinate():
	var squallmaw_def: Dictionary = EasterEggCreatures.SIGHTINGS["squallmaw"]
	assert_eq(SeaCaveGuardian.LATITUDE, squallmaw_def["latitude"])
	assert_eq(SeaCaveGuardian.LONGITUDE, squallmaw_def["longitude"])


func test_is_in_range_true_at_the_caves_own_tile():
	var tile := guardian.tile(world_width, world_height)
	assert_true(guardian.is_in_range(tile.x, tile.y, world_width, world_height))


func test_is_in_range_false_far_from_the_cave():
	var far_tile := Vector2i(world_width / 2, world_height / 2)
	assert_false(guardian.is_in_range(far_tile.x, far_tile.y, world_width, world_height))


func test_not_challenge_active_initially():
	assert_false(guardian.is_challenge_active())


func test_can_begin_challenge_true_when_in_range_and_no_challenge_active():
	var tile := guardian.tile(world_width, world_height)
	assert_true(guardian.can_begin_challenge(tile.x, tile.y, world_width, world_height))


func test_can_begin_challenge_false_when_out_of_range():
	var far_tile := Vector2i(world_width / 2, world_height / 2)
	assert_false(guardian.can_begin_challenge(far_tile.x, far_tile.y, world_width, world_height))


func test_can_begin_challenge_false_while_a_challenge_is_already_active():
	var tile := guardian.tile(world_width, world_height)
	guardian.begin_challenge()
	assert_false(guardian.can_begin_challenge(tile.x, tile.y, world_width, world_height))


func test_begin_challenge_sets_is_challenge_active_true():
	guardian.begin_challenge()
	assert_true(guardian.is_challenge_active())


func test_end_challenge_clears_is_challenge_active():
	guardian.begin_challenge()
	guardian.end_challenge()
	assert_false(guardian.is_challenge_active())


func test_can_begin_challenge_true_again_after_a_challenge_ends():
	# Deliberately repeatable, unlike AncientTerminal/SignedSecretRoom's
	# one-shot has_been_found -- zero mechanical weight (pillar 2) means
	# there's no reason to block a rematch.
	var tile := guardian.tile(world_width, world_height)
	guardian.begin_challenge()
	guardian.end_challenge()
	assert_true(guardian.can_begin_challenge(tile.x, tile.y, world_width, world_height))


func test_challenge_line_is_non_empty():
	assert_true(guardian.challenge_line().length() > 0)


func test_transform_line_is_non_empty():
	assert_true(guardian.transform_line().length() > 0)


func test_outcome_line_differs_for_a_player_win_vs_an_ai_win():
	assert_ne(guardian.outcome_line("player"), guardian.outcome_line("ai"))


func test_outcome_lines_are_both_non_empty():
	assert_true(guardian.outcome_line("player").length() > 0)
	assert_true(guardian.outcome_line("ai").length() > 0)
