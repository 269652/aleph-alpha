extends GutTest

## The pannable/zoomable graph view of the passive web (docs/concept/skills.md).
## Everything the player can misread -- which node is under the cursor, what a
## node costs THIS character, whether it is takeable -- is pure logic here rather
## than something only _draw() knows.

const SkillWebView = preload("res://scenes/skill_web_view.gd")
const SkillWeb = preload("res://src/gameplay/skill_web.gd")
const GenomeSkillNet = preload("res://src/gameplay/genome_skill_net.gd")
const HeroDna = preload("res://src/gameplay/hero_dna.gd")

var view: SkillWebView
var web: SkillWeb


func before_each():
	web = SkillWeb.new()
	view = SkillWebView.new()
	add_child_autofree(view)
	view.size = Vector2(800, 600)
	view.configure(web, "mage", {}, 0)
	view.set_allocation({}, 99)


# --- projection -----------------------------------------------------------

func test_the_pan_point_lands_in_the_middle_of_the_view():
	view.pan = Vector2(50, -30)
	assert_almost_eq(view.world_to_view(Vector2(50, -30)).x, view.size.x * 0.5, 0.001)
	assert_almost_eq(view.world_to_view(Vector2(50, -30)).y, view.size.y * 0.5, 0.001)


func test_view_to_world_inverts_world_to_view():
	view.pan = Vector2(17, 42)
	view.zoom = 1.7
	var world := Vector2(-233, 91)
	var round_tripped := view.view_to_world(view.world_to_view(world))
	assert_almost_eq(round_tripped.x, world.x, 0.001)
	assert_almost_eq(round_tripped.y, world.y, 0.001)


func test_zoom_is_clamped_to_its_declared_range():
	view.set_zoom_at(999.0, view.size * 0.5)
	assert_almost_eq(view.zoom, SkillWebView.MAX_ZOOM, 0.001)
	view.set_zoom_at(0.0001, view.size * 0.5)
	assert_almost_eq(view.zoom, SkillWebView.MIN_ZOOM, 0.001)


## Zooming has to feel like the map moving under a fixed finger, not the map
## teleporting -- whatever was under the cursor stays under the cursor.
func test_zooming_keeps_the_world_point_under_the_cursor_fixed():
	var cursor := Vector2(620, 130)
	var before := view.view_to_world(cursor)
	view.set_zoom_at(view.zoom * 1.8, cursor)
	var after := view.view_to_world(cursor)
	assert_almost_eq(after.x, before.x, 0.01)
	assert_almost_eq(after.y, before.y, 0.01)


func test_focusing_a_node_brings_it_to_the_middle_of_the_view():
	var node_id := web.start_node_for("mage")
	view.pan = Vector2(4000, 4000)
	view.focus_on(node_id)
	var centre := view.world_to_view(web.position_of(node_id))
	assert_almost_eq(centre.x, view.size.x * 0.5, 0.001)
	assert_almost_eq(centre.y, view.size.y * 0.5, 0.001)


# --- hit testing ----------------------------------------------------------

func test_a_click_on_a_node_finds_that_node():
	var node_id := web.start_node_for("mage")
	view.focus_on(node_id)
	assert_eq(view.node_at(view.size * 0.5), node_id)


func test_a_click_on_open_space_finds_nothing():
	view.pan = Vector2.ZERO
	view.zoom = 1.0
	# The centre of the web is deliberately empty -- every start node sits out
	# on START_RADIUS, so nothing is drawn at the origin.
	assert_eq(view.node_at(view.size * 0.5), "")


func test_hit_testing_follows_the_view_when_it_pans():
	var node_id := web.start_node_for("warrior")
	view.focus_on(node_id)
	assert_eq(view.node_at(view.size * 0.5), node_id)
	view.pan += Vector2(10000, 0)
	assert_eq(view.node_at(view.size * 0.5), "")


func test_a_click_picks_the_nearer_of_two_close_nodes():
	var start := web.start_node_for("warrior")
	var neighbour: String = web.nodes_in_ring("warrior", 1)[0]
	view.focus_on(start)
	var nudged: Vector2 = view.world_to_view(web.position_of(neighbour))
	assert_eq(view.node_at(nudged), neighbour)


# --- state ----------------------------------------------------------------

func test_your_own_start_node_reads_as_takeable_on_a_fresh_character():
	assert_eq(view.state_of(web.start_node_for("mage")), SkillWebView.STATE_TAKEABLE)


func test_a_node_across_the_web_reads_as_locked():
	assert_eq(view.state_of(web.start_node_for("beastmaster")), SkillWebView.STATE_LOCKED)


func test_an_allocated_node_reads_as_allocated():
	var start := web.start_node_for("mage")
	view.set_allocation({start: true}, 99)
	assert_eq(view.state_of(start), SkillWebView.STATE_ALLOCATED)


## Cannot-afford has to look different from cannot-reach: one is "come back next
## level", the other is "walk over there first".
func test_a_reachable_node_you_cannot_pay_for_reads_as_unaffordable_not_locked():
	var start := web.start_node_for("mage")
	view.set_allocation({start: true}, 0)
	var neighbour: String = web.nodes_in_ring("mage", 1)[0]
	assert_eq(view.state_of(neighbour), SkillWebView.STATE_UNAFFORDABLE)
	assert_eq(view.state_of(web.start_node_for("beastmaster")), SkillWebView.STATE_LOCKED)


func test_state_of_an_unknown_node_is_locked():
	assert_eq(view.state_of("not_a_node"), SkillWebView.STATE_LOCKED)


# --- labelling ------------------------------------------------------------

## The cost shown has to be the cost this genome actually pays, or a dissonant
## player budgets against a number that is not theirs.
func test_a_node_is_labelled_with_the_cost_this_genome_really_pays():
	var keystone: String = web.nodes_in_ring("mage", SkillWeb.OUTER_RING)[0]
	view.configure(web, "mage", {"mage": 0.0}, 0)
	var dissonant := view.node_label(keystone)
	view.configure(web, "mage", {"mage": 1.0}, 0)
	var resonant := view.node_label(keystone)
	assert_ne(dissonant, resonant, "the label ignored resonance")
	assert_string_contains(dissonant, "%d pt" % web.point_cost(keystone, {"mage": 0.0}))
	assert_string_contains(resonant, "%d pt" % web.point_cost(keystone, {"mage": 1.0}))


func test_a_node_label_names_the_stat_in_words_not_as_an_identifier():
	var label := view.node_label("vitality_1")
	assert_eq(label.findn("max_health"), -1, "raw stat key leaked into the label")
	assert_string_contains(label, "Vitality")


func test_a_dna_flavoured_node_is_labelled_with_the_variant_this_genome_gets():
	var flavoured: String = web.flavored_node_ids()[0]
	var seeds_seen := {}
	for dna_seed in range(0, 200):
		view.configure(web, "mage", {}, dna_seed)
		seeds_seen[view.node_label(flavoured)] = true
	assert_gt(seeds_seen.size(), 1, "the label ignored DNA flavour")


func test_a_reveal_node_is_labelled_with_its_description_not_a_zero_bonus():
	var label := view.node_label("land_sense")
	assert_eq(label.findn("+0"), -1, "reveal node advertised a +0 bonus")
	assert_string_contains(label, "land health")


func test_a_grafted_signature_node_is_labelled_with_its_generated_name():
	var net := GenomeSkillNet.new().generate({
		"seed_value": 31, "rarity": HeroDna.RARITY_RARE, "resonance": {"mage": 0.9}})
	web.graft(net)
	var core: String = net["node_ids"][0]
	assert_string_contains(view.node_label(core), String(net["nodes"][core]["title"]))


func test_an_unknown_node_has_an_empty_label():
	assert_eq(view.node_label("not_a_node"), "")


# --- colour ---------------------------------------------------------------

func test_each_wedge_gets_its_own_colour():
	var hues := {}
	for wedge_index in SkillWeb.WEDGE_COUNT:
		hues[view.wedge_color(wedge_index).h] = true
	assert_eq(hues.size(), SkillWeb.WEDGE_COUNT, "two wedges share a hue")


func test_an_allocated_node_is_drawn_brighter_than_a_locked_one():
	var start := web.start_node_for("mage")
	var locked := web.start_node_for("beastmaster")
	view.set_allocation({start: true}, 99)
	assert_gt(view.node_color(start).a, view.node_color(locked).a)


# --- interaction ----------------------------------------------------------

func test_clicking_a_takeable_node_emits_it():
	var node_id := web.start_node_for("mage")
	view.focus_on(node_id)
	watch_signals(view)
	view.click_at(view.size * 0.5)
	assert_signal_emitted_with_parameters(view, "node_clicked", [node_id])


func test_clicking_open_space_emits_nothing():
	view.pan = Vector2.ZERO
	watch_signals(view)
	view.click_at(view.size * 0.5)
	assert_signal_not_emitted(view, "node_clicked")


## A locked node is still worth clicking -- the view answers "what is this and
## what would it cost", which is how a player plans a route in the first place.
func test_clicking_a_locked_node_still_selects_it_for_inspection():
	var node_id := web.start_node_for("beastmaster")
	view.focus_on(node_id)
	view.click_at(view.size * 0.5)
	assert_eq(view.selected_node_id, node_id)


# --- refunding ------------------------------------------------------------

## Free respec (docs/concept/classes.md) needs a gesture on the map itself, and
## right-click is the one that cannot be confused with "take this".
func test_right_clicking_an_allocated_node_asks_to_refund_it():
	var node_id := web.start_node_for("mage")
	view.set_allocation({node_id: true}, 99)
	view.focus_on(node_id)
	watch_signals(view)
	view.right_click_at(view.size * 0.5)
	assert_signal_emitted_with_parameters(view, "node_refund_requested", [node_id])


func test_right_clicking_a_node_you_do_not_own_asks_nothing():
	var node_id := web.start_node_for("mage")
	view.focus_on(node_id)
	watch_signals(view)
	view.right_click_at(view.size * 0.5)
	assert_signal_not_emitted(view, "node_refund_requested")


# --- hover ----------------------------------------------------------------
#
# Reported live against the first web view: "the skills have no hover tooltip
# and it's pretty unclear what paths do what". Both are answered here -- a real
# tooltip on hover, and a previewed ROUTE to anything you cannot yet reach.

func test_hovering_a_node_records_it():
	var node_id := web.start_node_for("mage")
	view.focus_on(node_id)
	view.hover_at(view.size * 0.5)
	assert_eq(view.hovered_node_id, node_id)


func test_hovering_open_space_clears_the_hover():
	var node_id := web.start_node_for("mage")
	view.focus_on(node_id)
	view.hover_at(view.size * 0.5)
	view.hover_at(Vector2.ZERO)
	assert_eq(view.hovered_node_id, "")


func _tooltip(node_id: String) -> String:
	return "\n".join(view.node_tooltip(node_id))


func test_the_tooltip_names_the_node_and_says_which_wedge_it_is_in():
	var text := _tooltip("berserkers_fury")
	assert_string_contains(text, "Berserker's Fury")
	assert_string_contains(text, "Warrior")
	assert_string_contains(text, "keystone")


func test_the_tooltip_states_what_it_grants_this_character():
	view.configure(web, "warrior", {"warrior": 1.0}, 0)
	var text := _tooltip("vitality_1")
	assert_string_contains(text, "Maximum Health")
	assert_string_contains(text, "%s" % String.num(web.effective_bonus("vitality_1", {"warrior": 1.0}), 1).trim_suffix(".0"))


func test_the_tooltip_quotes_this_characters_own_price():
	var keystone := "archmage"
	view.configure(web, "mage", {"mage": 0.0}, 0)
	assert_string_contains(_tooltip(keystone), str(web.point_cost(keystone, {"mage": 0.0})))


func test_a_reveal_nodes_tooltip_describes_it_instead_of_a_zero_bonus():
	var text := _tooltip("land_sense")
	assert_eq(text.findn("+0"), -1, "reveal node advertised a +0 bonus")
	assert_string_contains(text, "land health")


func test_an_owned_nodes_tooltip_says_so_and_how_to_give_it_back():
	view.set_allocation({"vitality_1": true}, 9)
	var text := _tooltip("vitality_1")
	assert_string_contains(text.to_lower(), "owned")
	assert_string_contains(text.to_lower(), "right-click")


func test_a_signature_nodes_tooltip_says_it_came_from_your_own_genome():
	var net := GenomeSkillNet.new().generate({
		"seed_value": 88, "rarity": HeroDna.RARITY_RARE, "resonance": {"mage": 0.9}})
	web.graft(net)
	var text := _tooltip(String(net["node_ids"][0]))
	assert_string_contains(text, String(net["nodes"][net["node_ids"][0]]["title"]))
	assert_string_contains(text.to_lower(), "genome")


func test_a_flavoured_nodes_tooltip_says_its_variant_was_chosen_by_dna():
	var flavoured: String = web.flavored_node_ids()[0]
	assert_string_contains(_tooltip(flavoured).to_lower(), "dna")


func test_a_gateways_tooltip_explains_what_crossing_one_is_for():
	var gateway := ""
	for node_id in web.node_ids():
		if web.node_info(node_id)["kind"] == SkillWeb.KIND_GATEWAY:
			gateway = node_id
			break
	assert_string_contains(_tooltip(gateway).to_lower(), "wedge")


func test_an_unknown_node_has_an_empty_tooltip():
	assert_eq(view.node_tooltip("not_a_node"), [])


# --- route preview --------------------------------------------------------

func test_hovering_an_unreachable_node_previews_the_whole_route_to_it():
	var target := web.start_node_for("beastmaster")
	view.set_allocation({web.start_node_for("mage"): true}, 99)
	view.focus_on(target)
	view.hover_at(view.size * 0.5)
	assert_gt(view.preview_path.size(), 1, "no route was previewed")
	assert_eq(view.preview_path[view.preview_path.size() - 1], target)


func test_the_route_preview_is_empty_for_a_node_you_already_own():
	var owned := web.start_node_for("mage")
	view.set_allocation({owned: true}, 99)
	view.focus_on(owned)
	view.hover_at(view.size * 0.5)
	assert_eq(view.preview_path, [])


func test_moving_off_a_node_clears_the_route_preview():
	view.set_allocation({web.start_node_for("mage"): true}, 99)
	view.focus_on(web.start_node_for("beastmaster"))
	view.hover_at(view.size * 0.5)
	view.hover_at(Vector2.ZERO)
	assert_eq(view.preview_path, [])


func test_an_unreachable_nodes_tooltip_quotes_the_cost_of_the_whole_route():
	var target := web.start_node_for("beastmaster")
	view.set_allocation({web.start_node_for("mage"): true}, 99)
	var route := web.cheapest_path(target, {web.start_node_for("mage"): true}, "mage", {})
	assert_string_contains(_tooltip(target), str(web.route_cost(route, {})))


# --- naming on the map ----------------------------------------------------

func test_a_wedge_is_named_on_the_map_in_words():
	assert_eq(view.wedge_label(0), "Warrior")


func test_the_big_nodes_carry_their_name_on_the_map_at_any_zoom():
	view.zoom = SkillWebView.MIN_ZOOM
	for node_id in ["berserkers_fury", "juggernaut", web.start_node_for("warrior")]:
		assert_true(view.shows_label(node_id), "%s should stay named when zoomed out" % node_id)
		assert_ne(view.map_label(node_id), "")


## Naming all 84 at once would be an unreadable thicket; they appear as you lean
## in, which is also when there is room for them.
func test_minor_nodes_are_only_named_once_you_zoom_in():
	view.zoom = SkillWebView.MIN_ZOOM
	assert_false(view.shows_label("vitality_1"))
	view.zoom = SkillWebView.MAX_ZOOM
	assert_true(view.shows_label("vitality_1"))


func test_a_gateway_is_never_named_on_the_map():
	var gateway := ""
	for node_id in web.node_ids():
		if web.node_info(node_id)["kind"] == SkillWeb.KIND_GATEWAY:
			gateway = node_id
			break
	view.zoom = SkillWebView.MAX_ZOOM
	assert_false(view.shows_label(gateway), "a gateway has no name worth crowding the map with")
