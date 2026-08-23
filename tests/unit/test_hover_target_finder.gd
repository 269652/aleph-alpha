extends GutTest

## Pure "what's under the mouse" lookup for the animal-name hover tooltip
## (see World._update_hover_tooltip). Kept pure/testable; the actual Node2D
## group-scanning and Label positioning live in World.gd (untested scene
## glue, same as this project's other top-level scene scripts).

const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")

var finder: HoverTargetFinder


func before_each():
	finder = HoverTargetFinder.new()


func test_returns_empty_string_when_nothing_is_near():
	var found := finder.name_under(Vector2(1000, 1000), [{"position": Vector2.ZERO, "name": "Deer"}])
	assert_eq(found, "")


func test_returns_the_name_of_a_candidate_within_radius():
	var found := finder.name_under(Vector2(5, 5), [{"position": Vector2.ZERO, "name": "Deer"}])
	assert_eq(found, "Deer")


func test_returns_the_closest_candidate_when_multiple_are_in_range():
	var candidates := [
		{"position": Vector2(15, 0), "name": "Far"},
		{"position": Vector2(3, 0), "name": "Near"},
	]
	assert_eq(finder.name_under(Vector2.ZERO, candidates), "Near")


func test_respects_the_hover_radius_boundary():
	var just_inside := finder.name_under(
		Vector2.ZERO, [{"position": Vector2(HoverTargetFinder.HOVER_RADIUS_PX - 1.0, 0), "name": "In"}]
	)
	var just_outside := finder.name_under(
		Vector2.ZERO, [{"position": Vector2(HoverTargetFinder.HOVER_RADIUS_PX + 1.0, 0), "name": "Out"}]
	)
	assert_eq(just_inside, "In")
	assert_eq(just_outside, "")


func test_returns_empty_string_for_an_empty_candidate_list():
	assert_eq(finder.name_under(Vector2.ZERO, []), "")
