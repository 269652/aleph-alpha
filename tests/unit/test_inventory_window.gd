extends GutTest

## Covers InventoryWindow's layout contract (the off-screen/overflow bug class)
## and its fixed slot grid. The window is given a fixed anchor box by
## World._build_inventory_window -- if the window's real minimum size exceeds
## that box, Godot expands the control past its offsets and the bottom of the
## paperdoll (Feet slot, armor total) runs off-screen, which is exactly the
## reported bug this file pins against regressing.

const InventoryWindow = preload("res://scenes/inventory_window.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")

## Keep in sync with World._build_inventory_window's offsets (±300 x ±230).
const WORLD_ANCHOR_BOX := Vector2(600, 460)

var window: InventoryWindow
var catalog := ItemCatalog.new()


func before_each():
	window = InventoryWindow.new()
	add_child(window)


func after_each():
	window.free()


func test_window_minimum_size_fits_the_anchor_box_world_gives_it():
	# refresh() with a full paperdoll + full grid first, so the measured
	# minimum reflects the fullest layout the window ever shows.
	var stacks := []
	for i in 12:
		stacks.append(ItemStack.new(catalog.make("rock"), 1))
	window.refresh(stacks, {}, 0.0, 12)

	var min_size := window.get_combined_minimum_size()
	assert_lte(min_size.x, WORLD_ANCHOR_BOX.x, "window min width must fit World's anchor box")
	assert_lte(min_size.y, WORLD_ANCHOR_BOX.y, "window min height must fit World's anchor box or the bottom clips off-screen")


func test_refresh_builds_a_fixed_slot_grid_including_empty_slots():
	window.refresh([], {}, 0.0, 12)
	assert_eq(window._grid.get_child_count(), 12, "an empty inventory should still show all 12 slot frames, like real game inventories")


func test_refresh_fills_leading_slots_and_keeps_the_rest_as_empty_frames():
	var stacks := [ItemStack.new(catalog.make("campfire"), 2)]
	window.refresh(stacks, {}, 0.0, 12)
	assert_eq(window._grid.get_child_count(), 12)


func test_item_tooltip_shows_name_kind_and_stack_count():
	var stack := ItemStack.new(catalog.make("campfire"), 3)
	var tooltip: String = window._item_tooltip_text(stack)
	assert_string_contains(tooltip, "Campfire")
	assert_string_contains(tooltip, "Placeable")
	assert_string_contains(tooltip, "3")


# -- refresh() must be a no-op when called repeatedly with unchanged data ----
#
# World calls refresh() every frame while the window is visible (see
## World._update_inventory_window), not just on an actual inventory change.
# Before this, refresh() unconditionally destroyed and recreated every slot's
# Control each call -- no Control instance survived more than one frame, so
# Godot's native hover tooltip (which needs the mouse over the SAME instance
# continuously) could never complete its timer. Reported as "no info on
# hover" even though the tooltip text itself was always correct.

func test_repeated_identical_refresh_keeps_the_same_slot_control_instance():
	var stacks := [ItemStack.new(catalog.make("campfire"), 2)]
	window.refresh(stacks, {}, 0.0, 12)
	var first_slot := window._grid.get_child(0)

	window.refresh(stacks, {}, 0.0, 12)  # identical inputs, e.g. next frame's poll

	assert_eq(window._grid.get_child(0), first_slot, "an unchanged refresh should not recreate slot Controls")


func test_refresh_with_actually_different_stacks_does_rebuild():
	window.refresh([ItemStack.new(catalog.make("campfire"), 2)], {}, 0.0, 12)
	var first_slot := window._grid.get_child(0)

	window.refresh([ItemStack.new(catalog.make("rock"), 1)], {}, 0.0, 12)

	assert_ne(window._grid.get_child(0), first_slot, "a real inventory change must still rebuild the grid")


## Reproduces the reported live bug (Godot log: "Attempted to free a locked
## object (calling or emitting)" from inside refresh()): clicking an item
## slot synchronously triggers World -> Player -> InventoryWindow.refresh()
## again (see _on_item_gui_input/World._on_inventory_item_clicked), all
## still on that very slot Control's own gui_input call stack. The slot is
## "locked" (mid-signal-emission on itself) for that whole chain --
## Object.free() refuses to free a locked object, which used to abort the
## rebuild partway through and leave the grid showing only some items
## ("hides all other items in inventory").
func test_refresh_survives_being_called_from_within_a_slots_own_click_handler():
	var stacks := [
		ItemStack.new(catalog.make("iron_sword"), 1),
		ItemStack.new(catalog.make("fishing_rod"), 1),
		ItemStack.new(catalog.make("rock"), 5),
	]
	window.refresh(stacks, {}, 0.0, 12)

	window.item_clicked.connect(func(_item_id):
		window.refresh(stacks, {"weapon": catalog.make("fishing_rod")}, 0.0, 12)
	)

	var fishing_rod_slot: Control = window._grid.get_child(1)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	fishing_rod_slot.gui_input.emit(event)  # what a real right-click ultimately does

	assert_eq(window._grid.get_child_count(), 12, "the grid should still show every slot, not just the one clicked")


# -- drag and drop (reorder within the grid / drag out to the hotbar) --------

func test_item_slots_carry_a_drag_payload_naming_their_item_and_index():
	window.refresh([
		ItemStack.new(catalog.make("iron_sword"), 1),
		ItemStack.new(catalog.make("fishing_rod"), 1),
	], {}, 0.0, 12)

	var payload = window._grid.get_child(1).drag_payload
	assert_eq(payload["item_id"], "fishing_rod")
	assert_eq(payload["index"], 1)
	assert_eq(payload["source"], InventoryWindow.DRAG_SOURCE_INVENTORY)


func test_item_slots_accept_an_inventory_drag_but_not_a_foreign_one():
	window.refresh([ItemStack.new(catalog.make("iron_sword"), 1)], {}, 0.0, 12)
	var slot = window._grid.get_child(0)

	assert_true(slot._can_drop_data(Vector2.ZERO, {"source": InventoryWindow.DRAG_SOURCE_INVENTORY, "index": 1}))
	assert_false(slot._can_drop_data(Vector2.ZERO, {"source": "somewhere_else"}))


func test_dropping_one_item_onto_another_emits_items_reordered():
	window.refresh([
		ItemStack.new(catalog.make("iron_sword"), 1),
		ItemStack.new(catalog.make("fishing_rod"), 1),
	], {}, 0.0, 12)

	var received := []
	window.items_reordered.connect(func(from_index, to_index): received.append([from_index, to_index]))

	# Drag slot 1 (rod) onto slot 0 (sword).
	window._grid.get_child(0)._drop_data(Vector2.ZERO, window._grid.get_child(1).drag_payload)

	assert_eq(received, [[1, 0]])


## Empty trailing slots take drops too (drag an item into empty space), so a
## reorder isn't limited to swapping with another occupied slot.
func test_dropping_onto_an_empty_slot_also_emits_items_reordered():
	window.refresh([ItemStack.new(catalog.make("iron_sword"), 1)], {}, 0.0, 12)

	var received := []
	window.items_reordered.connect(func(from_index, to_index): received.append([from_index, to_index]))

	window._grid.get_child(5)._drop_data(Vector2.ZERO, window._grid.get_child(0).drag_payload)

	assert_eq(received, [[0, 5]])


func test_empty_slots_are_not_themselves_draggable():
	window.refresh([], {}, 0.0, 12)
	assert_null(window._grid.get_child(0)._get_drag_data(Vector2.ZERO))


func test_refresh_rebuilds_when_only_the_equipped_paperdoll_changes():
	var sword := catalog.make("iron_sword")
	window.refresh([], {}, 0.0, 12)
	var icon: TextureRect = window._paperdoll_icons["weapon"]
	assert_null(icon.texture)

	window.refresh([], {"weapon": sword}, 0.0, 12)

	assert_not_null(icon.texture)


# -- right-click to use/equip/unequip, left reserved for dragging -----------
#
# Reported live bug: "a click on a carrot makes it vanish". Left-click was
# wired to BOTH start-a-drag (DragSlot/Godot's built-in drag-and-drop, which
# only ever triggers off the left button) AND fire item_clicked immediately
# on press -- so simply pressing down to pick an item up for a drag also
# instantly used/equipped/ate it, before the drag even had a chance to
# happen. The fix separates the two gestures onto different buttons
# entirely: left drags, right uses.

func _left_click_event() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


func _right_click_event() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	return event


func test_left_click_on_an_item_does_not_use_or_equip_it():
	window.refresh([ItemStack.new(catalog.make("iron_sword"), 1)], {}, 0.0, 12)
	watch_signals(window)

	window._grid.get_child(0).gui_input.emit(_left_click_event())

	assert_signal_not_emitted(window, "item_clicked")


func test_right_click_on_an_item_uses_or_equips_it():
	window.refresh([ItemStack.new(catalog.make("iron_sword"), 1)], {}, 0.0, 12)
	watch_signals(window)

	window._grid.get_child(0).gui_input.emit(_right_click_event())

	assert_signal_emitted_with_parameters(window, "item_clicked", ["iron_sword"])


func test_left_click_on_a_worn_slot_does_not_unequip_it():
	window.refresh([], {"weapon": catalog.make("iron_sword")}, 0.0, 12)
	watch_signals(window)

	var weapon_row: Control = window._paperdoll_icons["weapon"].get_parent()
	weapon_row.gui_input.emit(_left_click_event())

	assert_signal_not_emitted(window, "unequip_requested")


func test_right_click_on_a_worn_slot_unequips_it():
	window.refresh([], {"weapon": catalog.make("iron_sword")}, 0.0, 12)
	watch_signals(window)

	var weapon_row: Control = window._paperdoll_icons["weapon"].get_parent()
	weapon_row.gui_input.emit(_right_click_event())

	assert_signal_emitted_with_parameters(window, "unequip_requested", ["weapon"])


# -- the tooltip surfaces the stats an item REALLY models -------------------
#
# docs/concept/materials.md's whole pitch is that an item's numbers emerge
# from its material and geometry rather than being authored per recipe --
# mass_kg is literally MaterialProperties.mass_kg_for(material, volume_cm3),
# real density x real volume -- and none of it reached the player while the
# tooltip said only "Raw Meat / Food / x5".
#
# Every line is CONDITIONAL on item.gd's own "0.0 means not modeled yet"
# convention: a tooltip printing "0.00 kg" would be stating a measurement the
# game has never made, so an unmodeled stat is OMITTED.

func test_item_tooltip_shows_a_weapons_real_derived_mass_in_kilograms():
	var stack := ItemStack.new(catalog.make("iron_sword"), 1)
	# iron's real density (7.8 g/cm^3) x ItemCatalog.IRON_SWORD_VOLUME_CM3
	# (154) = 1.2012 kg, derived -- not authored on the item.
	assert_string_contains(window._item_tooltip_text(stack), "1.20 kg")


func test_item_tooltip_shows_weapon_damage_for_a_weapon():
	var stack := ItemStack.new(catalog.make("iron_sword"), 1)
	var tooltip: String = window._item_tooltip_text(stack)
	assert_string_contains(tooltip, "Damage: 15")
	assert_eq(tooltip.find("15.0"), -1, "a whole-number stat should not read as 15.0")


func test_item_tooltip_shows_armor_value_and_the_slot_it_protects():
	var stack := ItemStack.new(catalog.make("leather_chest"), 1)
	assert_string_contains(window._item_tooltip_text(stack), "Armor: 4 (Chest)")


## The omit-never-zero rule: raw meat models no mass, no damage and no armor,
## so its tooltip must stay silent about all three rather than claiming it
## weighs nothing and deals nothing.
func test_item_tooltip_omits_unmodeled_stats_rather_than_printing_zero():
	var tooltip: String = window._item_tooltip_text(ItemStack.new(catalog.make("meat"), 5))
	assert_eq(tooltip.find("kg"), -1, "an item with no modeled mass must show no weight line")
	assert_eq(tooltip.find("Damage"), -1, "food deals no damage; say nothing rather than 0")
	assert_eq(tooltip.find("Armor"), -1, "food is not armor; say nothing rather than 0")


# -- the material an item is made of, in WORDS ------------------------------
#
# docs/concept/materials.md's "Learning an emergent system" specifies
# descriptors + discovery as the player-facing default and explicitly defers
# a raw-number spreadsheet ("a deeper inspect surfacing raw numbers for
# min-maxers is a possible later affordance"). So the tooltip names the
# material and describes it (MaterialProperties.descriptors_for), and never
# dumps the property vector's scalars.

func test_item_tooltip_names_a_weapons_material_and_describes_it_in_words():
	var tooltip: String = window._item_tooltip_text(ItemStack.new(catalog.make("iron_sword"), 1))
	assert_string_contains(tooltip, "Iron")
	assert_string_contains(tooltip, "hard")
	assert_string_contains(tooltip, "keen")


func test_item_tooltip_never_prints_the_raw_material_property_scalars():
	var tooltip: String = window._item_tooltip_text(ItemStack.new(catalog.make("iron_sword"), 1))
	assert_eq(tooltip.find("7.8"), -1, "density belongs in words (buoyant), not as a raw scalar")
	assert_eq(tooltip.findn("hardness"), -1, "the property vector's key names are internal")


func test_item_tooltip_omits_the_material_line_for_an_item_with_no_modeled_material():
	var tooltip: String = window._item_tooltip_text(ItemStack.new(catalog.make("rock"), 1))
	assert_eq(tooltip.findn("stone"), -1, "rock has no material modeled; don't invent one")


# -- per-item, per-season freshness -----------------------------------------
#
# Food really does go off in your pack (Inventory ages every stack; see
# ItemStack.freshness / FruitSpoilage), off a real per-item keeping multiplier
# (cherry 0.6x, walnut 8.0x) times a real seasonal factor (summer 0.6x, winter
# 3.0x). A cherry in summer keeps 1.8 in-game days and a walnut in summer
# keeps 24 -- a spread the player was told nothing about anywhere in the game,
# which made "cache the nuts, eat the cherries first" unplayable.
#
# Freshness is season-dependent by construction, so refresh() has to be TOLD
# the season; with no season supplied both lines are omitted rather than
# resolved against a guessed one.

const FruitSpoilage = preload("res://src/gameplay/fruit_spoilage.gd")


func test_item_tooltip_shows_a_foods_real_freshness_for_the_current_season():
	var stack := ItemStack.new(catalog.make("cherry"), 1)
	stack.age(FruitSpoilage.edible_seconds("cherry", "summer") * 0.5)

	window.refresh([stack], {}, 0.0, 12, "summer")

	assert_string_contains(window._grid.get_child(0).tooltip_text, "Freshness: 50%")


func test_item_tooltip_shows_the_seasonal_shelf_life_and_a_nut_keeps_far_longer_than_a_cherry():
	window.refresh([ItemStack.new(catalog.make("cherry"), 1)], {}, 0.0, 12, "summer")
	var cherry_tooltip: String = window._grid.get_child(0).tooltip_text
	window.refresh([ItemStack.new(catalog.make("walnut"), 1)], {}, 0.0, 12, "summer")
	var walnut_tooltip: String = window._grid.get_child(0).tooltip_text

	# 5 base days x 0.6 (cherry) x 0.6 (summer) = 1.8; x 8.0 (walnut) = 24.0.
	assert_string_contains(cherry_tooltip, "1.8 days")
	assert_string_contains(walnut_tooltip, "24.0 days")
	assert_string_contains(walnut_tooltip, "summer")


## The same nut, in the season that really preserves it.
func test_the_shelf_life_line_follows_the_season_it_was_given():
	window.refresh([ItemStack.new(catalog.make("walnut"), 1)], {}, 0.0, 12, "winter")
	# 5 x 8.0 x 3.0 (winter) = 120 days.
	assert_string_contains(window._grid.get_child(0).tooltip_text, "120.0 days")


func test_item_tooltip_omits_freshness_when_no_season_was_supplied():
	window.refresh([ItemStack.new(catalog.make("cherry"), 1)], {}, 0.0, 12)
	var tooltip: String = window._grid.get_child(0).tooltip_text
	assert_eq(tooltip.findn("freshness"), -1, "with no season there is nothing honest to resolve freshness against")
	assert_eq(tooltip.findn("keeps"), -1, "shelf life is season-dependent too")


func test_a_non_food_item_never_shows_freshness():
	window.refresh([ItemStack.new(catalog.make("rock"), 1)], {}, 0.0, 12, "summer")
	assert_eq(window._grid.get_child(0).tooltip_text.findn("freshness"), -1,
		"a rock is not spoiled, it is just a rock")


## THE QUANTIZATION GUARD. Freshness is CONTINUOUS, so it may only enter the
## rebuild signature as the whole percent the tooltip actually displays. Fed
## in raw, the signature would change every single frame an aging food stack
## is held -- rebuilding every slot Control every frame and re-breaking
## Godot's native hover tooltip, which is the exact "no info on hover" bug
## _last_refresh_signature exists to prevent (see its doc comment).
func test_an_aging_food_stack_does_not_rebuild_the_grid_on_every_refresh():
	var stack := ItemStack.new(catalog.make("walnut"), 1)
	window.refresh([stack], {}, 0.0, 12, "autumn")
	var first_slot := window._grid.get_child(0)

	stack.age(1.0)  # one world second -- far too little to move the shown percent
	window.refresh([stack], {}, 0.0, 12, "autumn")

	assert_eq(window._grid.get_child(0), first_slot,
		"an aging stack whose DISPLAYED freshness has not changed must not recreate slot Controls")


## ...but a change the player can actually see must still rebuild.
func test_a_food_stack_that_has_visibly_aged_does_rebuild_the_grid():
	var stack := ItemStack.new(catalog.make("cherry"), 1)
	window.refresh([stack], {}, 0.0, 12, "summer")
	var first_slot := window._grid.get_child(0)

	stack.age(FruitSpoilage.edible_seconds("cherry", "summer") * 0.5)
	window.refresh([stack], {}, 0.0, 12, "summer")

	assert_ne(window._grid.get_child(0), first_slot, "a visible freshness change must rebuild")


# -- the paperdoll shows the REAL character rig -----------------------------
#
# It used to be a 36x36 head TextureRect stacked on a 36x44 flat blue
# rectangle -- no torso art, no arms, no legs, and no relationship whatsoever
# to the look the player authored in the character creator (reported as "a
# floating head above a blue box", while the same character rendered correctly
# two feet away in the live world). CharacterView is the ONE rig the player,
# every NPC and the character creator's preview already share (see
# CharacterPreviewStage's own doc comment on why one rig, not a second that
# can silently drift).

const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")


func _find_character_view(node: Node) -> CharacterView:
	if node is CharacterView:
		return node
	for child in node.get_children():
		var found := _find_character_view(child)
		if found != null:
			return found
	return null


func test_the_paperdoll_renders_the_same_character_view_rig_the_world_uses():
	assert_not_null(_find_character_view(window),
		"the equipment preview must be the real CharacterView rig, not hand-built TextureRects")


## CharacterView.apply_appearance REGENERATES every part texture, and World
## calls refresh()/apply_appearance every frame while this window is open, so
## an unchanged look must be a genuine no-op.
func test_repeating_the_same_appearance_does_not_re_dress_the_paperdoll_every_frame():
	var view := _find_character_view(window)
	var look: Dictionary = HeroAppearance.new().appearance_for("mage", 3)

	window.apply_appearance(look)
	var head_texture := view._head.texture

	window.apply_appearance(look.duplicate(true))  # same look, next frame

	assert_eq(view._head.texture, head_texture,
		"an unchanged appearance must not regenerate the rig's part textures")


func test_a_changed_appearance_really_does_re_dress_the_paperdoll():
	var view := _find_character_view(window)
	var maker := HeroAppearance.new()

	window.apply_appearance(maker.appearance_for("mage", 3))
	var head_texture := view._head.texture

	window.apply_appearance(maker.appearance_for("warrior", 11))

	assert_ne(view._head.texture, head_texture, "a different look must actually be applied")


func test_the_paperdoll_character_holds_the_equipped_weapon_and_drops_it_when_unequipped():
	var view := _find_character_view(window)

	window.refresh([], {"weapon": catalog.make("iron_sword")}, 0.0, 12)
	assert_true(view.is_slot_equipped("tool"), "the paperdoll should hold the equipped weapon")
	assert_not_null(view.tool_slot_texture())

	window.refresh([], {}, 0.0, 12)
	assert_false(view.is_slot_equipped("tool"), "unequipping must empty the paperdoll's hand too")
