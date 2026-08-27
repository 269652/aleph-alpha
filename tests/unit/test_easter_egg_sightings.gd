extends GutTest

## EasterEggSightings (docs/concept/easter_eggs.md's Starter collection):
## Mothman, the Jersey Devil, and the Roswell/Area 51 crashed-saucer +
## "little grey" pair -- the doc's own "pure atmosphere, no stats, no
## fight" real-coordinate cameos. Pure decision logic only: given a tile
## position, world size, and a caller-supplied roll (so this stays
## deterministic/testable instead of calling randf() itself), decide
## whether a sighting message should show.

const EasterEggSightings = preload("res://src/gameplay/easter_egg_sightings.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")

var sightings: EasterEggSightings
var world_width: int
var world_height: int


func before_each():
	sightings = EasterEggSightings.new()
	world_width = EarthChunkGenerator.WORLD_WIDTH_TILES
	world_height = EarthChunkGenerator.WORLD_HEIGHT_TILES


func test_this_stages_four_sighting_ids_are_registered():
	var ids := sightings.sighting_ids()
	for expected in ["mothman", "jersey_devil", "roswell_saucer", "roswell_grey", "area51_saucer", "area51_grey"]:
		assert_true(ids.has(expected), "missing sighting id: %s" % expected)


func _tile_at(id: String) -> Vector2i:
	var def: Dictionary = EasterEggSightings.SIGHTINGS[id]
	return sightings.tile_for(id, world_width, world_height)


func test_is_in_range_true_at_the_sightings_own_tile():
	for id in sightings.sighting_ids():
		var tile := _tile_at(id)
		assert_true(
			sightings.is_in_range(id, tile.x, tile.y, world_width, world_height),
			"%s should be in range of its own coordinate" % id
		)


func test_is_in_range_false_far_from_every_sighting():
	# Mid-Pacific, nowhere near any of this stage's coordinates.
	var far_tile := Vector2i(world_width / 2, world_height / 2)
	for id in sightings.sighting_ids():
		assert_false(
			sightings.is_in_range(id, far_tile.x, far_tile.y, world_width, world_height),
			"%s should not be in range of the far tile" % id
		)


func test_check_one_empty_when_out_of_range_even_with_a_guaranteed_roll():
	var far_tile := Vector2i(world_width / 2, world_height / 2)
	var message := sightings.check_one("mothman", far_tile.x, far_tile.y, world_width, world_height, 0.0)
	assert_eq(message, "")


func test_check_one_empty_when_roll_does_not_clear_the_chance_threshold():
	var tile := _tile_at("mothman")
	# A roll of exactly 1.0 clears no threshold in [0, 1).
	var message := sightings.check_one("mothman", tile.x, tile.y, world_width, world_height, 1.0)
	assert_eq(message, "")


func test_check_one_returns_a_message_when_in_range_and_roll_clears_threshold():
	var tile := _tile_at("mothman")
	var message := sightings.check_one("mothman", tile.x, tile.y, world_width, world_height, 0.0)
	assert_ne(message, "")


func test_check_one_unknown_id_returns_empty_string_not_a_crash():
	var message := sightings.check_one("bigfoot", 0, 0, world_width, world_height, 0.0)
	assert_eq(message, "")


func test_jersey_devil_night_message_differs_from_day_message():
	var tile := _tile_at("jersey_devil")
	var day_message := sightings.check_one(
		"jersey_devil", tile.x, tile.y, world_width, world_height, 0.0, false
	)
	var night_message := sightings.check_one(
		"jersey_devil", tile.x, tile.y, world_width, world_height, 0.0, true
	)
	assert_ne(day_message, "")
	assert_ne(night_message, "")
	assert_ne(day_message, night_message)


## Design pillar: the crashed-saucer landmarks read as "basically always
## there" once you're near the coordinate, while the wandering cryptids/
## greys are genuinely rare glimpses -- pinned as a relative property (per
## this project's "no eyeballed thresholds" rule) rather than two
## independent literal numbers that could quietly drift apart.
func test_saucer_landmarks_trigger_far_more_often_than_fleeting_sightings():
	var saucer_chance: float = EasterEggSightings.SIGHTINGS["roswell_saucer"]["chance_per_check"]
	var grey_chance: float = EasterEggSightings.SIGHTINGS["roswell_grey"]["chance_per_check"]
	var mothman_chance: float = EasterEggSightings.SIGHTINGS["mothman"]["chance_per_check"]
	assert_gt(saucer_chance, grey_chance * 10.0)
	assert_gt(saucer_chance, mothman_chance * 10.0)


## Roswell and Area 51 are an explicit matched pair in the doc -- their
## saucer/grey chances should match each other, not drift into two
## independently-tuned numbers for what's meant to be one symmetric joke.
func test_roswell_and_area51_are_tuned_as_a_matched_pair():
	assert_eq(
		EasterEggSightings.SIGHTINGS["roswell_saucer"]["chance_per_check"],
		EasterEggSightings.SIGHTINGS["area51_saucer"]["chance_per_check"]
	)
	assert_eq(
		EasterEggSightings.SIGHTINGS["roswell_grey"]["chance_per_check"],
		EasterEggSightings.SIGHTINGS["area51_grey"]["chance_per_check"]
	)


func test_mothman_never_reachable_by_approach_has_no_persistent_state():
	# Zero mechanical presence (docs/concept/easter_eggs.md): a sighting is a
	# single decision from a tile+roll, not an object the player can walk up
	# to -- calling check_one twice in a row with the same inputs is exactly
	# as valid as calling it once, there is nothing to "already be there".
	var tile := _tile_at("mothman")
	var first := sightings.check_one("mothman", tile.x, tile.y, world_width, world_height, 0.0)
	var second := sightings.check_one("mothman", tile.x, tile.y, world_width, world_height, 0.0)
	assert_eq(first, second)
