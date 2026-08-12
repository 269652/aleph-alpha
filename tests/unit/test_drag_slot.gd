extends GutTest

## DragSlot: the one Control subclass that participates in Godot's
## virtual-method drag-and-drop (see src/ui/drag_slot.gd), with behavior
## injected as Callables so the inventory grid and the HUD hotbar share it.

const DragSlot = preload("res://src/ui/drag_slot.gd")

var slot: DragSlot


func before_each():
	slot = DragSlot.new()
	add_child(slot)


func after_each():
	slot.free()


func test_offers_no_drag_data_without_a_payload():
	assert_null(slot._get_drag_data(Vector2.ZERO))


func test_offers_its_payload_when_dragged():
	slot.drag_payload = {"source": "inventory", "item_id": "fishing_rod"}
	assert_eq(slot._get_drag_data(Vector2.ZERO)["item_id"], "fishing_rod")


func test_accepts_nothing_when_no_can_accept_is_wired():
	assert_false(slot._can_drop_data(Vector2.ZERO, {"source": "inventory"}))


func test_delegates_the_accept_decision_to_can_accept():
	slot.can_accept = func(payload): return payload.get("source", "") == "inventory"
	assert_true(slot._can_drop_data(Vector2.ZERO, {"source": "inventory"}))
	assert_false(slot._can_drop_data(Vector2.ZERO, {"source": "somewhere_else"}))


func test_drop_invokes_the_dropped_callback_with_the_payload():
	var received := []
	slot.dropped = func(payload): received.append(payload["item_id"])

	slot._drop_data(Vector2.ZERO, {"item_id": "fishing_rod"})

	assert_eq(received, ["fishing_rod"])


func test_drop_without_a_dropped_callback_is_a_no_op_rather_than_crashing():
	slot._drop_data(Vector2.ZERO, {"item_id": "fishing_rod"})
	pass_test("dropping on a slot with no handler should not error")
