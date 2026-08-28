extends GutTest

## SkillTreeWindow's web view (docs/concept/skills.md): the graph is the primary
## way to spend a point; the old flat list stays reachable behind a tab as a
## keyboard/screen-reader-friendly fallback.

const SkillTreeWindow = preload("res://scenes/skill_tree_window.gd")
const SkillWebView = preload("res://scenes/skill_web_view.gd")
const SkillWeb = preload("res://src/gameplay/skill_web.gd")

var window: SkillTreeWindow
var web := SkillWeb.new()


func before_each():
	window = SkillTreeWindow.new()
	add_child(window)
	window.configure_web(web, "mage", {}, 0)


func after_each():
	window.free()


func test_the_window_opens_on_the_web_not_the_list():
	assert_eq(window.mode, SkillTreeWindow.MODE_WEB)
	assert_true(window.web_view.visible)


func test_switching_to_the_list_hides_the_web_and_back_again():
	window.set_mode(SkillTreeWindow.MODE_LIST)
	assert_false(window.web_view.visible)
	window.set_mode(SkillTreeWindow.MODE_WEB)
	assert_true(window.web_view.visible)


func test_the_list_tab_still_builds_its_rows():
	window.set_mode(SkillTreeWindow.MODE_LIST)
	window.refresh(10, {}, {})
	assert_gt(window._list.get_child_count(), 0)


func test_refresh_hands_the_players_allocation_to_the_web_view():
	var start := web.start_node_for("mage")
	window.refresh(7, {start: true}, {})
	assert_eq(window.web_view.state_of(start), SkillWebView.STATE_ALLOCATED)


func test_refresh_hands_the_players_unlocked_keystones_to_the_web_view():
	# Keystones live on the web as ordinary nodes, so one the player unlocked
	# before keystones moved onto the web still has to read as allocated.
	window.refresh(7, {}, {"archmage": true})
	assert_eq(window.web_view.state_of("archmage"), SkillWebView.STATE_ALLOCATED)


func test_the_view_opens_centred_on_the_players_own_class_start():
	assert_eq(window.web_view.pan, web.position_of(web.start_node_for("mage")))


func test_configuring_a_different_class_recentres_the_view():
	window.configure_web(web, "artisan", {}, 0)
	assert_eq(window.web_view.pan, web.position_of(web.start_node_for("artisan")))


func test_clicking_a_takeable_stat_node_in_the_web_is_forwarded_as_an_allocation():
	var start := web.start_node_for("mage")
	window.refresh(99, {}, {})
	watch_signals(window)
	window.web_view.click_at(window.web_view.world_to_view(web.position_of(start)))
	assert_signal_emitted_with_parameters(window, "node_allocated", [start])


## World routes keystones through Player.unlock_keystone (their node-count gate
## lives there), so the web has to tell the two apart rather than emitting one
## signal for everything on the map.
func test_clicking_a_keystone_in_the_web_is_forwarded_as_a_keystone_unlock():
	var keystone := "archmage"
	var owned := {}
	for node_id in web.node_ids():
		owned[node_id] = true
	owned.erase(keystone)
	window.refresh(99, owned, {})
	watch_signals(window)
	window.web_view.click_at(window.web_view.world_to_view(web.position_of(keystone)))
	assert_signal_emitted_with_parameters(window, "keystone_unlocked", [keystone])


func test_right_clicking_an_owned_node_in_the_web_is_forwarded_as_a_refund():
	var start := web.start_node_for("mage")
	window.refresh(99, {start: true}, {})
	watch_signals(window)
	window.web_view.right_click_at(window.web_view.world_to_view(web.position_of(start)))
	assert_signal_emitted_with_parameters(window, "node_refunded", [start])


func test_selecting_a_node_shows_what_it_is_and_what_it_would_cost():
	var keystone := "archmage"
	window.refresh(0, {}, {})
	window.web_view.click_at(window.web_view.world_to_view(web.position_of(keystone)))
	window.refresh(0, {}, {})
	assert_string_contains(window._detail_label.text, "Archmage")
	assert_string_contains(window._detail_label.text, "pt")


## World calls refresh() every frame while this window is open, so refresh()
## skips its work when the skill-state fingerprint is unchanged (see
## _last_refresh_signature). The SELECTION is deliberately not in that
## fingerprint -- it moves on a click, not on an allocation -- so a skipped
## refresh still has to refresh the detail line, or the line under the map
## stays stuck on whatever the last real state change left there. That is the
## ordinary case rather than an edge one: inspecting a node changes the
## allocation and the point total not at all.
func test_the_detail_line_follows_the_selection_on_an_otherwise_identical_refresh():
	var start := web.start_node_for("mage")
	window.refresh(0, {}, {})
	window.web_view.click_at(window.web_view.world_to_view(web.position_of(start)))
	assert_eq(window.web_view.selected_node_id, start, "the click has to select something")
	window.refresh(0, {}, {})
	assert_string_contains(window._detail_label.text, window.web_view.node_label(start))


func test_the_detail_line_says_something_useful_before_anything_is_selected():
	window.refresh(0, {}, {})
	assert_ne(window._detail_label.text, "")


## The web needs real canvas to be readable; World anchors this window centred,
## so the room it has is the viewport less a margin, not the old left-edge strip.
func test_the_window_still_fits_the_room_world_actually_gives_it():
	window.refresh(1000, {}, {})
	var min_size := window.get_combined_minimum_size()
	assert_lte(min_size.x, SkillTreeWindow.WORLD_AVAILABLE_BOX.x)
	assert_lte(min_size.y, SkillTreeWindow.WORLD_AVAILABLE_BOX.y)


## The window was first sized against a 960x540 viewport copied out of a stale
## comment in world.gd. The project's real design viewport is bigger, so the
## window had been giving the map barely half the room it could -- reported live
## as "can you make the skill window bigger so the web is better visible". Read
## from ProjectSettings so it can never quietly drift again.
func test_the_windows_design_viewport_is_the_projects_own():
	assert_eq(SkillTreeWindow.DESIGN_VIEWPORT, Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height"))))


func test_the_window_fills_the_design_viewport_less_a_margin():
	assert_eq(window.custom_minimum_size, SkillTreeWindow.DESIGN_VIEWPORT
		- Vector2(SkillTreeWindow.SCREEN_MARGIN, SkillTreeWindow.SCREEN_MARGIN) * 2.0)


## CHROME_HEIGHT is the room reserved for the title, points line, tabs and
## detail line, with everything else going to the canvas. Pinned by measuring
## the window's REAL minimum rather than by trusting the reserve.
func test_the_reserved_chrome_really_does_hold_the_windows_own_chrome():
	window.refresh(1000, {}, {})
	assert_lte(window.get_combined_minimum_size().y, SkillTreeWindow.WINDOW_SIZE.y)


## The point of the whole resize: the entire web, its wedge names included, has
## to be visible at once when the player zooms out, or the map is a keyhole.
func test_the_whole_web_fits_the_canvas_when_zoomed_out():
	var span := 2.0 * web.wedge_label_position(0).length() * SkillWebView.MIN_ZOOM
	assert_gte(window.web_view.custom_minimum_size.x, span,
		"the web is wider than the canvas even fully zoomed out")
	assert_gte(window.web_view.custom_minimum_size.y, span,
		"the web is taller than the canvas even fully zoomed out")


## ...and the node names have to be legible at the zoom the window OPENS at,
## not only after the player thinks to zoom in.
func test_small_nodes_are_already_named_at_the_zoom_the_window_opens_on():
	assert_gte(window.web_view.zoom, SkillWebView.MINOR_LABEL_ZOOM)
