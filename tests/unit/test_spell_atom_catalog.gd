extends GutTest

## Red-first spec for the magic DSL's atom catalog: the data table of the
## fine-grained primitive effects (docs/concept/magic.md) that every spell,
## enchantment, and NPC instruction is composed from. Pure lookup, same shape
## as item_catalog.gd / class_archetype.gd -- the cost model reads from here.

const SpellAtomCatalog = preload("res://src/gameplay/spell_atom_catalog.gd")

const _SPEC_KEYS := ["category", "tier", "base_cost", "mag_ref", "dur_ref"]
const _CATEGORIES := [
	"damage", "heal", "control", "movement", "defense", "summon", "utility",
	# 2026-07-15 brainstorm domains (docs/concept/magic.md "primitive domains
	# go beyond the physical"): biological/genetic, perceptual/mental, spatial.
	"biological", "perceptual", "spatial",
]

var catalog: SpellAtomCatalog


func before_each():
	catalog = SpellAtomCatalog.new()


func test_has_returns_true_for_a_known_atom():
	assert_true(catalog.has("fire_damage"))


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


func test_every_atom_has_a_positive_base_cost():
	# Cost is *derived*, never authored (magic.md constraint layer 1): the
	# cheapest possible spell still costs something, so no atom is free.
	for atom_id in catalog.known_ids():
		assert_gt(catalog.base_cost(atom_id), 0.0, "atom '%s' must have a positive base cost" % atom_id)


func test_every_atom_tier_is_between_one_and_three():
	for atom_id in catalog.known_ids():
		var tier: int = catalog.tier(atom_id)
		assert_between(tier, 1, 3, "atom '%s' tier out of range" % atom_id)


func test_scales_with_magnitude_matches_a_positive_mag_ref():
	for atom_id in catalog.known_ids():
		var expected := catalog.mag_ref(atom_id) > 0.0
		assert_eq(catalog.scales_with_magnitude(atom_id), expected,
			"scales_with_magnitude disagrees with mag_ref for '%s'" % atom_id)


func test_scales_with_duration_matches_a_positive_dur_ref():
	for atom_id in catalog.known_ids():
		var expected := catalog.dur_ref(atom_id) > 0.0
		assert_eq(catalog.scales_with_duration(atom_id), expected,
			"scales_with_duration disagrees with dur_ref for '%s'" % atom_id)


func test_a_damage_atom_scales_with_magnitude_not_duration():
	# fire_damage does an amount of damage on hit -> magnitude, no duration.
	assert_true(catalog.scales_with_magnitude("fire_damage"))
	assert_false(catalog.scales_with_duration("fire_damage"))


func test_a_control_atom_scales_with_duration_not_magnitude():
	# ignite is a lingering status -> duration, no magnitude.
	assert_true(catalog.scales_with_duration("ignite"))
	assert_false(catalog.scales_with_magnitude("ignite"))


func test_major_heal_costs_more_at_the_base_than_minor_heal():
	assert_gt(catalog.base_cost("major_heal"), catalog.base_cost("minor_heal"))


func test_a_summon_atom_is_the_priciest_tier():
	assert_eq(catalog.tier("summon_wisp"), 3)


func test_ids_in_category_returns_only_that_category():
	var damage_ids: Array = catalog.ids_in_category("damage")
	assert_gt(damage_ids.size(), 0, "expected at least one damage atom")
	for atom_id in damage_ids:
		assert_eq(catalog.category(atom_id), "damage")


func test_spec_returns_a_defensive_copy():
	# Mutating a returned spec must not corrupt the shared catalog (same
	# duplicate() discipline as class_archetype.stats_for / item_catalog).
	var spec: Dictionary = catalog.spec("fire_damage")
	spec["base_cost"] = 9999.0
	assert_eq(catalog.base_cost("fire_damage"), catalog.spec("fire_damage")["base_cost"])
	assert_ne(catalog.base_cost("fire_damage"), 9999.0)


# --- 2026-07-15 brainstorm: atom domains beyond the physical ----------------
# (docs/concept/magic.md "The primitive domains go beyond the physical":
# biological/genetic, perceptual/mental, spatial atoms.)

func test_biological_domain_has_atoms():
	var ids: Array = catalog.ids_in_category("biological")
	assert_gt(ids.size(), 0, "expected at least one biological atom")


func test_perceptual_domain_has_atoms():
	var ids: Array = catalog.ids_in_category("perceptual")
	assert_gt(ids.size(), 0, "expected at least one perceptual atom")


func test_spatial_domain_has_atoms():
	var ids: Array = catalog.ids_in_category("spatial")
	assert_gt(ids.size(), 0, "expected at least one spatial atom")


func test_accelerate_growth_is_a_biological_instantaneous_magnitude_atom():
	assert_true(catalog.has("accelerate_growth"))
	assert_eq(catalog.category("accelerate_growth"), "biological")
	assert_true(catalog.scales_with_magnitude("accelerate_growth"))
	assert_false(catalog.scales_with_duration("accelerate_growth"))


func test_induce_mutation_is_a_biological_tier_three_atom():
	# Mutation is the highest-power biological verb -- ties directly into
	# dna.md/evolution.md, gated at the priciest tier like summon_wisp.
	assert_true(catalog.has("induce_mutation"))
	assert_eq(catalog.category("induce_mutation"), "biological")
	assert_eq(catalog.tier("induce_mutation"), 3)


func test_suppress_mutation_is_a_biological_duration_atom():
	assert_true(catalog.has("suppress_mutation"))
	assert_eq(catalog.category("suppress_mutation"), "biological")
	assert_true(catalog.scales_with_duration("suppress_mutation"))
	assert_false(catalog.scales_with_magnitude("suppress_mutation"))


func test_blight_is_a_biological_lingering_duration_atom():
	assert_true(catalog.has("blight"))
	assert_eq(catalog.category("blight"), "biological")
	assert_true(catalog.scales_with_duration("blight"))
	assert_false(catalog.scales_with_magnitude("blight"))


func test_illuminate_is_a_perceptual_duration_atom():
	assert_true(catalog.has("illuminate"))
	assert_eq(catalog.category("illuminate"), "perceptual")
	assert_true(catalog.scales_with_duration("illuminate"))


func test_calm_is_a_perceptual_duration_atom():
	# Hooks into creature temperament / taming (pets.md), same lingering-
	# status shape as the existing control atoms.
	assert_true(catalog.has("calm"))
	assert_eq(catalog.category("calm"), "perceptual")
	assert_true(catalog.scales_with_duration("calm"))
	assert_false(catalog.scales_with_magnitude("calm"))


func test_fear_is_a_perceptual_duration_atom():
	assert_true(catalog.has("fear"))
	assert_eq(catalog.category("fear"), "perceptual")
	assert_true(catalog.scales_with_duration("fear"))
	assert_false(catalog.scales_with_magnitude("fear"))


func test_teleport_is_a_spatial_instantaneous_magnitude_atom():
	assert_true(catalog.has("teleport"))
	assert_eq(catalog.category("teleport"), "spatial")
	assert_true(catalog.scales_with_magnitude("teleport"))
	assert_false(catalog.scales_with_duration("teleport"))


func test_portal_is_a_spatial_tier_three_duration_atom():
	# A held-open portal is a timed entity like summon_wisp -- highest tier.
	assert_true(catalog.has("portal"))
	assert_eq(catalog.category("portal"), "spatial")
	assert_eq(catalog.tier("portal"), 3)
	assert_true(catalog.scales_with_duration("portal"))


func test_gravity_shift_is_a_spatial_magnitude_and_duration_atom():
	# A lingering field of a given strength -- both dimensions, like shield.
	assert_true(catalog.has("gravity_shift"))
	assert_eq(catalog.category("gravity_shift"), "spatial")
	assert_true(catalog.scales_with_magnitude("gravity_shift"))
	assert_true(catalog.scales_with_duration("gravity_shift"))
