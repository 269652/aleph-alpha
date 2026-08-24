extends GutTest

const DroppedItem = preload("res://src/rendering/dropped_item.gd")
const Item = preload("res://src/gameplay/item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")
const Inventory = preload("res://src/gameplay/inventory.gd")
const IllustratedCropSprite = preload("res://src/rendering/illustrated_crop_sprite.gd")
const Kick = preload("res://src/gameplay/kick.gd")
const StoneSize = preload("res://src/world/stone_size.gd")


class StubPicker:
	extends Node2D
	var inventory


var item: DroppedItem
var _extra: Array = []


func before_each():
	item = DroppedItem.new()
	item.item_stack = ItemStack.new(Item.new("hide", "Hide", "material", 40), 3)
	item.position = Vector2(100, 100)
	add_child(item)


func after_each():
	if is_instance_valid(item):
		item.free()
	for node in _extra:
		if is_instance_valid(node):
			node.free()
	_extra = []


func _make_picker(at: Vector2, slots: int = 10) -> StubPicker:
	var picker := StubPicker.new()
	picker.position = at
	picker.inventory = Inventory.new(slots)
	add_child(picker)
	_extra.append(picker)
	return picker


func test_has_a_sprite_texture():
	assert_not_null(item.texture, "a dropped item should render a sprite")


func test_despawns_after_its_lifetime_elapses():
	item._process(DroppedItem.LIFETIME + 1.0)
	assert_true(item.is_queued_for_deletion(), "un-picked-up items should eventually despawn")


func test_does_not_despawn_before_its_lifetime():
	item._process(DroppedItem.LIFETIME * 0.5)
	assert_false(item.is_queued_for_deletion())


func test_click_pickup_adds_the_stack_to_the_picker_and_frees_the_node():
	var picker := _make_picker(Vector2(500, 500))  # far away; a click grabs regardless

	var picked := item.pick_up(picker)

	assert_true(picked)
	assert_eq(picker.inventory.count_of("hide"), 3)
	assert_true(item.is_queued_for_deletion())


func test_standing_next_to_an_item_does_not_auto_pick_it_up():
	# Deliberately no proximity auto-pickup -- only an explicit click (see
	# test_click_pickup_adds_the_stack_to_the_picker_and_frees_the_node)
	# should ever move it into an inventory.
	var picker := _make_picker(Vector2(101, 100))  # right on top of the item
	for i in 30:
		item._process(0.1)
	assert_eq(picker.inventory.count_of("hide"), 0)
	assert_false(item.is_queued_for_deletion())


## The label above a dropped item used to be always-on (Path-of-Exile
## style); it now only shows via World's hover tooltip (see
## HoverTargetFinder.GROUP_NAME/get_display_name), so the count-aware
## formatting is now something get_display_name computes on demand rather
## than a persistent Label's cached text.
func test_get_display_name_includes_the_count():
	assert_eq(item.get_display_name(), "Hide x3")


func test_get_display_name_omits_the_count_when_it_is_one():
	item.item_stack.count = 1
	assert_eq(item.get_display_name(), "Hide")


func test_get_display_name_shows_the_remaining_count_after_a_partial_pickup():
	# Single slot, already 1/2 full of "hide" -- only 1 more can merge in, so
	# 2 of the dropped stack's 3 stay behind on the ground.
	var picker := _make_picker(Vector2(500, 500), 1)
	picker.inventory.add(Item.new("hide", "Hide", "material", 2), 1)
	item.pick_up(picker)
	assert_eq(item.get_display_name(), "Hide x2")


func test_get_hover_actions_offers_pickup():
	var actions: Array = item.get_hover_actions()
	assert_eq(actions.size(), 1)
	assert_eq(actions[0]["action"], "pickup")


## A dropped carrot/potato uses the real illustrated root art (see
## IllustratedCropSprite, docs/concept/wild_crops.md) rather than the
## generic procedural fallback every other item still uses -- the same
## texture the player just watched rise out of the ground during the pull,
## not a different sprite once it lands.
func test_a_dropped_carrot_uses_the_illustrated_root_texture():
	var carrot_item := DroppedItem.new()
	carrot_item.item_stack = ItemStack.new(Item.new("carrot", "Carrot", "food", 20), 1)
	add_child_autofree(carrot_item)
	var expected := IllustratedCropSprite.new().root_texture("carrot", 0)
	assert_eq(carrot_item.texture.get_image().get_data(), expected.get_image().get_data())


func test_a_dropped_carrot_is_sized_at_its_own_illustrated_world_width():
	var carrot_item := DroppedItem.new()
	carrot_item.item_stack = ItemStack.new(Item.new("carrot", "Carrot", "food", 20), 1)
	add_child_autofree(carrot_item)
	var expected_scale := IllustratedCropSprite.new().root_world_scale("carrot")
	assert_almost_eq(carrot_item.scale.x, expected_scale, 0.0001)


# -- a physical entity, not just an inventory grant (docs/concept/ ----------
# -- wild_crops.md) --  a dropped item with a real, modeled mass (item.gd's --
# -- own "0.0 = not modeled" convention) light enough to kick offers Kick, --
# -- the same way LiftableStone already does; one with no modeled mass -------
# -- (every OTHER food/material today) does not, so test_get_hover_actions_ --
# -- offers_pickup's plain "hide" item stays exactly as it was. -------------

func test_a_dropped_item_with_a_real_kickable_mass_offers_kick():
	var carrot_item := DroppedItem.new()
	carrot_item.item_stack = ItemStack.new(Item.new("carrot", "Carrot", "food", 20, 0.0, "", 0.0, 0.07), 1)
	add_child_autofree(carrot_item)
	var actions: Array = carrot_item.get_hover_actions()
	assert_eq(actions.size(), 2)
	assert_eq(actions[0]["action"], "pickup")
	assert_eq(actions[1]["action"], "kick")


func test_a_dropped_item_with_no_modeled_mass_does_not_offer_kick():
	# "hide" (see before_each) carries the default, un-modeled mass_kg=0.0 --
	# same as every other food/material item today.
	var actions: Array = item.get_hover_actions()
	assert_eq(actions.size(), 1, "an item with no real mass modeled yet should not offer Kick")


func test_a_dropped_item_too_heavy_to_kick_does_not_offer_kick():
	var heavy_item := DroppedItem.new()
	heavy_item.item_stack = ItemStack.new(
		Item.new("anvil", "Anvil", "material", 1, 0.0, "", 0.0, StoneSize.LEG_MASS_KG), 1
	)
	add_child_autofree(heavy_item)
	var actions: Array = heavy_item.get_hover_actions()
	assert_eq(actions.size(), 1, "too heavy to kick, same cutoff as a stone at/above leg mass")


func test_a_full_inventory_leaves_the_item_on_the_ground_with_the_remainder():
	# 1-slot inventory already holding a different full-ish item -> no room.
	var picker := _make_picker(Vector2(100, 100), 1)
	picker.inventory.add(Item.new("rock", "Rock", "material", 1), 1)  # fills the only slot

	var picked := item.pick_up(picker)

	assert_false(picked, "nothing fit, so it's not a successful pickup")
	assert_eq(picker.inventory.count_of("hide"), 0)
	assert_eq(item.item_stack.count, 3, "the stack stays on the ground")
	assert_false(item.is_queued_for_deletion())
