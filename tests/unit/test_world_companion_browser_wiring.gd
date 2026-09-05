extends GutTest

## The companion-browser overlay (docs/concept/companion_server.md's
## "In-game overlay" section) has to share the same "a modal is open"
## plumbing every other gameplay window already does -- World's own
## _any_gameplay_window_open (read by Escape's priority order and by every
## world-space hint's visibility) and _close_gameplay_windows (what Escape's
## "close windows" branch actually does). Neither of those two functions has
## its own dedicated test elsewhere (they're only exercised indirectly, as
## plumbing, by test_world_interaction_prompt_throttle.gd's throttle-timing
## tests) -- this is that direct coverage, following
## test_world_inventory_wiring.gd's own stated philosophy: a feature that
## is correct in isolation but not actually reachable through the real
## caller is not done.
##
## Deliberately NOT add_child()'d, same convention
## test_world_interaction_prompt_throttle.gd already uses: only the plain
## fields these two functions actually read are wired by hand.

const World = preload("res://scenes/world.gd")
const CraftingWindow = preload("res://scenes/crafting_window.gd")
const SkillTreeWindow = preload("res://scenes/skill_tree_window.gd")
const Keybindings = preload("res://src/gameplay/keybindings.gd")

var world: World
var inventory_window: PanelContainer
var companion_browser_overlay: PanelContainer
var crafting_window: CraftingWindow
var skill_window: SkillTreeWindow


func before_each():
	world = World.new()
	inventory_window = PanelContainer.new()
	inventory_window.visible = false
	world._inventory_window = inventory_window
	companion_browser_overlay = PanelContainer.new()
	companion_browser_overlay.visible = false
	world._companion_browser_overlay = companion_browser_overlay
	crafting_window = CraftingWindow.new()
	crafting_window.visible = false
	world._crafting_window = crafting_window
	skill_window = SkillTreeWindow.new()
	skill_window.visible = false
	world._skill_window = skill_window


func after_each():
	world.free()
	inventory_window.free()
	companion_browser_overlay.free()
	crafting_window.free()
	skill_window.free()


func test_no_window_open_reports_nothing_open():
	assert_false(world._any_gameplay_window_open())


func test_the_companion_browser_being_open_counts_as_a_window_open():
	companion_browser_overlay.visible = true
	assert_true(
		world._any_gameplay_window_open(),
		"an open companion browser should count the same as an open inventory/crafting/skill window"
	)


func test_closing_gameplay_windows_also_closes_the_companion_browser():
	companion_browser_overlay.visible = true
	world._close_gameplay_windows()
	assert_false(
		companion_browser_overlay.visible,
		"Escape's 'close every open window at once' should reach the companion browser too"
	)


## The rebindable action itself, registered the same way every other
## gameplay-window toggle is (Keybindings.ACTIONS, applied centrally by
## World._apply_keybindings -- see that function's own doc comment).
func test_toggle_companion_browser_is_a_real_rebindable_action_defaulting_to_tab():
	var bindings := Keybindings.new()
	assert_true(bindings.is_rebindable("toggle_companion_browser"))
	assert_eq(bindings.default_keycode_for("toggle_companion_browser"), KEY_TAB)
