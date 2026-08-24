extends GutTest

## Pure "what's under the mouse" lookup for the hover tooltip (see
## World._update_hover_tooltip). Covers every hoverable entity now, not
## just animals -- dropped items, stones, ore, trees, tall grass -- so the
## group is named generically (GROUP_NAME) rather than animal-specific.
## Kept pure/testable; the actual Node2D group-scanning, action-label
## formatting, and Label positioning live in World.gd (untested scene glue,
## same as this project's other top-level scene scripts).

const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")

var finder: HoverTargetFinder


func before_each():
	finder = HoverTargetFinder.new()


func test_returns_empty_dict_when_nothing_is_near():
	var found := finder.info_under(Vector2(1000, 1000), [{"position": Vector2.ZERO, "name": "Deer", "actions": []}])
	assert_eq(found, {})


func test_returns_the_full_info_of_a_candidate_within_radius():
	var candidate := {"position": Vector2.ZERO, "name": "Deer", "actions": []}
	var found := finder.info_under(Vector2(5, 5), [candidate])
	assert_eq(found["name"], "Deer")
	assert_eq(found["actions"], [])


func test_returns_the_closest_candidate_when_multiple_are_in_range():
	var candidates := [
		{"position": Vector2(15, 0), "name": "Far", "actions": []},
		{"position": Vector2(3, 0), "name": "Near", "actions": []},
	]
	assert_eq(finder.info_under(Vector2.ZERO, candidates)["name"], "Near")


func test_respects_the_hover_radius_boundary():
	var just_inside := finder.info_under(
		Vector2.ZERO, [{"position": Vector2(HoverTargetFinder.HOVER_RADIUS_PX - 1.0, 0), "name": "In", "actions": []}]
	)
	var just_outside := finder.info_under(
		Vector2.ZERO, [{"position": Vector2(HoverTargetFinder.HOVER_RADIUS_PX + 1.0, 0), "name": "Out", "actions": []}]
	)
	assert_eq(just_inside["name"], "In")
	assert_eq(just_outside, {})


func test_returns_empty_dict_for_an_empty_candidate_list():
	assert_eq(finder.info_under(Vector2.ZERO, []), {})


## Carries the candidate's actions through untouched -- formatting them into
## display strings (verb + live keybinding) is World's job, not the
## finder's, so it stays a plain data pass-through here.
func test_carries_actions_through_for_the_winning_candidate():
	var candidate := {
		"position": Vector2.ZERO, "name": "Pebble",
		"actions": [{"verb": "Pick Up", "action": "pickup"}, {"verb": "Kick", "action": "kick"}],
	}
	var found := finder.info_under(Vector2.ZERO, [candidate])
	assert_eq(found["actions"].size(), 2)
	assert_eq(found["actions"][0]["verb"], "Pick Up")
