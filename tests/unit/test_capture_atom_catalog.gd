extends GutTest

## Red-first spec for the capture DSL's atom catalog (docs/concept/
## capture_dsl.md): the small, fully-wired v1 set of primitive effects a
## capture device's pipeline is composed from. Pure lookup, same shape as
## spell_atom_catalog.gd -- but deliberately smaller: unlike magic's catalog,
## every atom here already has a real dispatcher (capture_atom_effects.gd)
## and a real caller, so nothing is catalogued ahead of having somewhere to
## run.

const CaptureAtomCatalog = preload("res://src/gameplay/capture_atom_catalog.gd")

const _SPEC_KEYS := ["category", "can_fail"]
const _CATEGORIES := ["roll", "effect"]

var catalog: CaptureAtomCatalog


func before_each():
	catalog = CaptureAtomCatalog.new()


func test_has_returns_true_for_a_known_atom():
	assert_true(catalog.has("catch_roll"))


func test_has_returns_false_for_an_unknown_atom():
	assert_false(catalog.has("not_a_real_atom"))


func test_known_ids_is_non_empty():
	assert_gt(catalog.known_ids().size(), 0)


func test_every_atom_spec_has_the_full_key_set():
	for atom_id in catalog.known_ids():
		var spec: Dictionary = catalog.spec(atom_id)
		for key in _SPEC_KEYS:
			assert_true(spec.has(key), "atom '%s' is missing spec key '%s'" % [atom_id, key])


func test_every_atom_category_is_one_of_the_known_categories():
	for atom_id in catalog.known_ids():
		var category: String = catalog.category(atom_id)
		assert_true(_CATEGORIES.has(category), "atom '%s' has unknown category '%s'" % [atom_id, category])


func test_spec_returns_a_defensive_copy():
	# Mutating a returned spec must not corrupt the shared catalog (same
	# duplicate() discipline as spell_atom_catalog.spec).
	var spec: Dictionary = catalog.spec("catch_roll")
	spec["can_fail"] = false
	assert_true(catalog.can_fail("catch_roll"))


func test_ids_in_category_returns_only_that_category():
	var effect_ids: Array = catalog.ids_in_category("effect")
	assert_gt(effect_ids.size(), 0, "expected at least one effect atom")
	for atom_id in effect_ids:
		assert_eq(catalog.category(atom_id), "effect")


# --- the roll/effect split: capture's own constraint layer ------------------
# (docs/concept/capture_dsl.md: unlike magic's unconditional pipeline, a
# capture pipeline can fail partway -- catch_roll is the only atom that can,
# and it is what stands between "attempted" and "happened".)

func test_catch_roll_is_the_roll_category_and_can_fail():
	assert_true(catalog.has("catch_roll"))
	assert_eq(catalog.category("catch_roll"), "roll")
	assert_true(catalog.can_fail("catch_roll"))


func test_hold_captive_is_an_effect_that_cannot_fail():
	assert_true(catalog.has("hold_captive"))
	assert_eq(catalog.category("hold_captive"), "effect")
	assert_false(catalog.can_fail("hold_captive"))


func test_release_captive_is_an_effect_that_cannot_fail():
	assert_true(catalog.has("release_captive"))
	assert_eq(catalog.category("release_captive"), "effect")
	assert_false(catalog.can_fail("release_captive"))


func test_move_captive_is_an_effect_that_cannot_fail():
	assert_true(catalog.has("move_captive"))
	assert_eq(catalog.category("move_captive"), "effect")
	assert_false(catalog.can_fail("move_captive"))


func test_exactly_one_atom_can_fail():
	# If a second roll-shaped atom is ever added (docs/concept/capture_dsl.md's
	# "Open questions" -- a future struggle_roll), this pins the count so
	# adding it is a deliberate edit here, not a silent catalog drift.
	var failing: Array = []
	for atom_id in catalog.known_ids():
		if catalog.can_fail(atom_id):
			failing.append(atom_id)
	assert_eq(failing, ["catch_roll"])
