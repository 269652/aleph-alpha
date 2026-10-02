extends GutTest

## Explicit spell target selection (docs/concept/spell_runtime.md, "Explicit
## target selection") -- pure index/identity math only, the same shape
## SpellTargeting/HoverTargetFinder already establish. The scene-tree work
## (which creatures qualify, their live positions, Tab/click/Escape input)
## lives in Player/World, untested glue over this.

const SpellTargetSelection = preload("res://src/gameplay/spell_target_selection.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")

var selection: SpellTargetSelection


func before_each():
	selection = SpellTargetSelection.new()


# -- next_target: cycling ----------------------------------------------------

func test_cycling_an_empty_list_returns_null():
	assert_null(selection.next_target([], null))


## No current selection starts the cycle at the nearest candidate -- callers
## pass candidates already sorted nearest-first (see TARGET_RADIUS's own doc
## comment), so index 0 IS "nearest".
func test_no_current_selection_starts_at_the_first_candidate():
	var a := "a"
	var b := "b"
	assert_eq(selection.next_target([a, b], null), a)


func test_advances_to_the_next_candidate():
	var a := "a"
	var b := "b"
	var c := "c"
	assert_eq(selection.next_target([a, b, c], a), b)
	assert_eq(selection.next_target([a, b, c], b), c)


func test_wraps_from_the_last_candidate_back_to_the_first():
	var a := "a"
	var b := "b"
	assert_eq(selection.next_target([a, b], b), a)


## The one real-world case this exists for: the previously-selected creature
## died or walked out of CAUTION_RADIUS between presses, so it is no longer
## anywhere in the fresh candidate list. Restarting at the nearest is the
## only answer that does not depend on a position that no longer exists.
func test_a_current_target_no_longer_in_the_list_restarts_at_the_first():
	var a := "a"
	var b := "b"
	var gone := "gone"
	assert_eq(selection.next_target([a, b], gone), a)


func test_a_single_candidate_cycles_back_to_itself():
	var only := "only"
	assert_eq(selection.next_target([only], only), only)


func test_cycling_from_null_current_with_an_empty_list_is_still_null():
	assert_null(selection.next_target([], null))


# -- index_at_point: click-to-target -----------------------------------------

func test_click_radius_is_the_same_tolerance_the_hover_tooltip_already_uses():
	# Named directly in spell_runtime.md: "not a second tuned radius" --
	# pinned here so the two can never silently drift apart.
	assert_eq(SpellTargetSelection.CLICK_RADIUS, HoverTargetFinder.HOVER_RADIUS_PX)


func test_target_radius_is_the_same_awareness_radius_creatures_already_use():
	assert_eq(SpellTargetSelection.TARGET_RADIUS, CreatureMarker.CAUTION_RADIUS)


func test_click_on_nothing_returns_negative_one():
	assert_eq(selection.index_at_point(Vector2(1000, 1000), [Vector2.ZERO]), -1)


func test_click_within_radius_returns_its_index():
	var positions := [Vector2(500, 500), Vector2(5, 5)]
	assert_eq(selection.index_at_point(Vector2.ZERO, positions), 1)


func test_click_picks_the_nearest_of_several_candidates_in_range():
	var positions := [Vector2(15, 0), Vector2(3, 0)]
	assert_eq(selection.index_at_point(Vector2.ZERO, positions), 1)


func test_click_respects_the_radius_boundary():
	var just_inside := [Vector2(SpellTargetSelection.CLICK_RADIUS - 1.0, 0)]
	var just_outside := [Vector2(SpellTargetSelection.CLICK_RADIUS + 1.0, 0)]
	assert_eq(selection.index_at_point(Vector2.ZERO, just_inside), 0)
	assert_eq(selection.index_at_point(Vector2.ZERO, just_outside), -1)


func test_click_on_an_empty_candidate_list_returns_negative_one():
	assert_eq(selection.index_at_point(Vector2.ZERO, []), -1)


## A wider radius can be passed explicitly, the same optional-override shape
## HoverTargetFinder.info_under already uses.
func test_an_explicit_radius_overrides_the_default():
	var far := [Vector2(SpellTargetSelection.CLICK_RADIUS * 3.0, 0)]
	assert_eq(selection.index_at_point(Vector2.ZERO, far), -1, "default radius should not reach this far")
	assert_eq(selection.index_at_point(Vector2.ZERO, far, SpellTargetSelection.CLICK_RADIUS * 4.0), 0)
