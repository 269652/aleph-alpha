extends GutTest

## Red-first spec for capture_atom_effects.gd (docs/concept/capture_dsl.md):
## applies one resolved pipeline step onto the tool Item it's about. Tested
## against a real Item, the same "test against the real receiver, not a
## mock" choice test_spell_atom_effects.gd already makes for Player.
##
## Never decides whether an atom runs -- capture_executor.gd already
## resolved that. This only carries out effects it's handed.

const CaptureAtomEffects = preload("res://src/gameplay/capture_atom_effects.gd")
const Item = preload("res://src/gameplay/item.gd")

var effects: CaptureAtomEffects
var net: Item


func before_each():
	effects = CaptureAtomEffects.new()
	net = Item.new("butterfly_net", "Butterfly Net", "tool", 1)


func test_hold_captive_sets_the_tools_captive_species():
	var applied = effects.apply_to_target("hold_captive", {}, net, {"target": {"species": "monarch"}})
	assert_true(applied)
	assert_eq(net.captive_species, "monarch")


func test_release_captive_clears_the_tools_captive_species():
	net.captive_species = "monarch"
	var applied = effects.apply_to_target("release_captive", {}, net, {})
	assert_true(applied)
	assert_eq(net.captive_species, "")


# -- move_captive: reuses the EXISTING jarred_insect/caged_songbird split ----
# (scenes/player.gd's own _capture_flyer already keys this exact split off
# AmbientFlyerRenderer.BIRD_SPECIES_POOL -- a glass bottle is what you need
# to jar the catch, not a new kind of catch, so this reuses those item ids
# rather than inventing new ones.)

func test_move_captive_reports_jarred_insect_for_a_non_bird_species():
	net.captive_species = "monarch"
	var result_item_id = effects.apply_to_target("move_captive", {}, net, {})
	assert_eq(result_item_id, "jarred_insect")
	assert_eq(net.captive_species, "", "the tool empties once its catch moves into a container")


func test_move_captive_reports_caged_songbird_for_a_bird_species():
	net.captive_species = "sparrow"
	var result_item_id = effects.apply_to_target("move_captive", {}, net, {})
	assert_eq(result_item_id, "caged_songbird")


func test_move_captive_on_an_empty_tool_reports_nothing_and_stays_empty():
	var result_item_id = effects.apply_to_target("move_captive", {}, net, {})
	assert_eq(result_item_id, "")
	assert_eq(net.captive_species, "")


func test_an_unknown_atom_id_does_nothing_and_reports_false():
	var applied = effects.apply_to_target("bogus_atom", {}, net, {})
	assert_false(applied)
	assert_eq(net.captive_species, "")
