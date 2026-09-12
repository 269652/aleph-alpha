extends GutTest

## SpawnRiverPicker (src/world/spawn_river_picker.gd): where a new game
## begins -- a random point along a random curated river (docs/concept/
## rivers.md "Spawn: a random curated river"), never the river's source or
## mouth, and only where the caller's acceptance check says a person could
## stand (World checks elevation, climate and that the tile really is a
## river tile). Pure: hands in the courses, a seeded RandomNumberGenerator
## and a Callable, gets back {"river": name, "tile": Vector2i} or {}.

const SpawnRiverPicker = preload("res://src/world/spawn_river_picker.gd")

const COURSES := {
	"Alpha": [Vector2(0, 0), Vector2(10, 0), Vector2(20, 0), Vector2(30, 0), Vector2(40, 0)],
	"Beta": [Vector2(0, 100), Vector2(10, 100), Vector2(20, 100), Vector2(30, 100)],
	"Gamma": [Vector2(0, 200), Vector2(10, 200), Vector2(20, 200)],
}


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _accept_all(_tile: Vector2i) -> bool:
	return true


func test_a_pick_names_a_river_and_a_tile_on_its_course():
	var pick: Dictionary = SpawnRiverPicker.pick(COURSES, _rng(1), _accept_all, 8)
	assert_true(COURSES.has(pick["river"]), "a river from the courses handed in")
	var on_course := false
	for point in COURSES[pick["river"]]:
		if Vector2i(point) == pick["tile"]:
			on_course = true
	assert_true(on_course, "the tile is one of that river's own course points")


func test_the_same_seed_always_picks_the_same_place():
	var first: Dictionary = SpawnRiverPicker.pick(COURSES, _rng(42), _accept_all, 8)
	var second: Dictionary = SpawnRiverPicker.pick(COURSES, _rng(42), _accept_all, 8)
	assert_eq(first, second, "a dev launch with a fixed seed must land in the same place every time")


func test_different_seeds_reach_every_river_and_more_than_one_point_per_river():
	var rivers_seen := {}
	var tiles_seen := {}
	for seed_value in 60:
		var pick: Dictionary = SpawnRiverPicker.pick(COURSES, _rng(seed_value), _accept_all, 8)
		rivers_seen[pick["river"]] = true
		tiles_seen[pick["tile"]] = true
	assert_eq(rivers_seen.size(), COURSES.size(), "over many games every curated river comes up")
	assert_gt(tiles_seen.size(), COURSES.size(), "and not always the same point on it")


func test_the_source_and_the_mouth_are_never_picked():
	for seed_value in 60:
		var pick: Dictionary = SpawnRiverPicker.pick(COURSES, _rng(seed_value), _accept_all, 8)
		var course: Array = COURSES[pick["river"]]
		assert_ne(pick["tile"], Vector2i(course[0]), "%s: a spring is a mountain, not a bank" % pick["river"])
		assert_ne(pick["tile"], Vector2i(course[course.size() - 1]), "%s: a mouth is the sea" % pick["river"])


func test_a_rejected_point_is_never_returned():
	var reject_alpha := func(tile: Vector2i) -> bool: return tile.y != 0  # every Alpha point
	for seed_value in 60:
		var pick: Dictionary = SpawnRiverPicker.pick(COURSES, _rng(seed_value), reject_alpha, 16)
		assert_ne(pick["river"], "Alpha", "a river with no acceptable point is skipped for another")


func test_nothing_acceptable_within_the_attempts_gives_an_empty_pick():
	var reject_all := func(_tile: Vector2i) -> bool: return false
	assert_eq(SpawnRiverPicker.pick(COURSES, _rng(3), reject_all, 8), {}, "the caller falls back to its fixed spawn")


func test_a_course_too_short_to_have_an_interior_point_is_skipped():
	var courses := {"Stub": [Vector2(0, 0), Vector2(5, 0)], "Real": [Vector2(0, 9), Vector2(5, 9), Vector2(10, 9)]}
	for seed_value in 20:
		var pick: Dictionary = SpawnRiverPicker.pick(courses, _rng(seed_value), _accept_all, 8)
		assert_eq(pick["river"], "Real")


func test_no_courses_at_all_gives_an_empty_pick():
	assert_eq(SpawnRiverPicker.pick({}, _rng(3), _accept_all, 8), {})
