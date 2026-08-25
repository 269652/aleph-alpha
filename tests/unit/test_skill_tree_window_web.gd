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


func test_the_web_canvas_is_big_enough_to_show_more_than_one_wedge():
	# Two wedges span 2/7 of the circle at the outer ring; if the canvas cannot
	# hold that at minimum zoom the map is a keyhole, not a map.
	var span := 2.0 * (SkillWeb.START_RADIUS + SkillWeb.RING_STEP * SkillWeb.OUTER_RING) \
		* SkillWebView.MIN_ZOOM * (2.0 / float(SkillWeb.WEDGE_COUNT))
	assert_gte(window.web_view.custom_minimum_size.x, span)
