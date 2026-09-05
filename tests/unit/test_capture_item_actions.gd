extends GutTest

## Red-first spec for capture_item_actions.gd (docs/concept/capture_dsl.md):
## what a held capture device's own secondary action is, independent of
## whatever (if anything) is under the player. A sibling of
## animal_actions.gd, not an extension of it -- that scorer's whole contract
## is keyed off a live animal's animal_state(), which "Put into bottle" has
## nothing to do with (it needs no hover target at all).

const CaptureItemActions = preload("res://src/gameplay/capture_item_actions.gd")
const Item = preload("res://src/gameplay/item.gd")


func _net(loaded: bool = false) -> Item:
	var net := Item.new("butterfly_net", "Butterfly Net", "tool", 1)
	if loaded:
		net.captive_species = "monarch"
	return net


func test_score_is_zero_for_an_empty_tool_even_with_a_bottle():
	assert_eq(CaptureItemActions.score_of(_net(false), true), 0.0)


func test_score_is_zero_for_a_loaded_tool_without_a_bottle():
	assert_eq(CaptureItemActions.score_of(_net(true), false), 0.0)


func test_score_is_positive_for_a_loaded_tool_with_a_bottle():
	assert_gt(CaptureItemActions.score_of(_net(true), true), 0.0)


func test_score_is_zero_for_a_null_tool():
	assert_eq(CaptureItemActions.score_of(null, true), 0.0)


func test_for_tool_offers_put_into_bottle_when_loaded_and_a_bottle_is_on_hand():
	var action := CaptureItemActions.for_tool(_net(true), true)
	assert_eq(action.get("verb"), "Put into bottle")
	assert_eq(action.get("action"), CaptureItemActions.SLOT_ACTION)


func test_for_tool_is_empty_when_not_offered():
	assert_eq(CaptureItemActions.for_tool(_net(false), true), {})
	assert_eq(CaptureItemActions.for_tool(_net(true), false), {})


func test_the_slot_action_is_the_secondary_action_key():
	# So this can only ever surface on the SAME key the hover-verb path
	# already uses for its secondary slot, never a new keybind.
	assert_eq(CaptureItemActions.SLOT_ACTION, "secondary_action")
