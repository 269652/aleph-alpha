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


# -- move_captive: reports WHICH species moved, not a generic item id -------
# (a first version of this granted a flat, genericized jarred_insect/
# caged_songbird curiosity item -- but the bottle needs to remember WHICH
# species it holds so it can be rendered live, see docs/concept/
# capture_dsl.md's "Rendering a bottled catch" -- so this reports the
# species itself, and the CALLER (Player) is the one who puts it on a fresh
# container item, the same relocation hold_captive already does the other
# direction.)

func test_move_captive_reports_the_species_it_moved():
	net.captive_species = "monarch"
	var species = effects.apply_to_target("move_captive", {}, net, {})
	assert_eq(species, "monarch")
	assert_eq(net.captive_species, "", "the tool empties once its catch moves into a container")


func test_move_captive_reports_a_bird_species_the_same_way():
	net.captive_species = "sparrow"
	var species = effects.apply_to_target("move_captive", {}, net, {})
	assert_eq(species, "sparrow")


func test_move_captive_on_an_empty_tool_reports_nothing_and_stays_empty():
	var species = effects.apply_to_target("move_captive", {}, net, {})
	assert_eq(species, "")
	assert_eq(net.captive_species, "")


func test_an_unknown_atom_id_does_nothing_and_reports_false():
	var applied = effects.apply_to_target("bogus_atom", {}, net, {})
	assert_false(applied)
	assert_eq(net.captive_species, "")
