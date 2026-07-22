extends GutTest

## Red-first spec for the magic DSL cost model (docs/concept/magic.md,
## "Constraint layer 1"). Cost is a DETERMINISTIC function of the atoms and
## parameters chosen -- there is no way to author "large effect for free". The
## character's stats change only what you *pay* (efficiency), never the derived
## power price. Every tuned constant in spell_cost.gd is pinned by a property
## test here rather than eyeballed (project memory: tuned values must be a
## tested function).
##
## The `atoms` argument shape matches the AST the parser will later emit:
##   [ {atom: "fire_damage", params: {magnitude: 8}}, ... ]

const SpellCost = preload("res://src/gameplay/spell_cost.gd")

var cost: SpellCost


func before_each():
	cost = SpellCost.new()


func _atom(atom_id: String, params: Dictionary = {}) -> Dictionary:
	return {"atom": atom_id, "params": params}


# --- derived, never free ---------------------------------------------------

func test_an_empty_spell_costs_nothing():
	assert_eq(cost.derived_base([], "self"), 0.0)


func test_any_non_empty_spell_has_a_positive_base():
	var base := cost.derived_base([_atom("fire_damage", {"magnitude": 6})], "touch")
	assert_gt(base, 0.0)


# --- diminishing returns on magnitude (superlinear) ------------------------

func test_magnitude_increases_atom_cost_monotonically():
	var small := cost.atom_cost("fire_damage", {"magnitude": 6})
	var big := cost.atom_cost("fire_damage", {"magnitude": 12})
	assert_gt(big, small)


func test_doubling_magnitude_more_than_doubles_cost():
	# Superlinear (MAG_EXP > 1): min-maxing a single atom's magnitude is
	# deliberately mana-inefficient, so varied compositions stay competitive.
	var single := cost.atom_cost("fire_damage", {"magnitude": 6})
	var doubled := cost.atom_cost("fire_damage", {"magnitude": 12})
	assert_gt(doubled, 2.0 * single)


# --- variety beats single-atom spam ----------------------------------------

func test_two_distinct_atoms_cost_less_than_the_same_atom_twice():
	# Same total magnitude, same base atoms; the repeated-atom spam penalty
	# makes the varied composition strictly cheaper.
	var varied := cost.composition_cost([
		_atom("fire_damage", {"magnitude": 6}),
		_atom("frost_damage", {"magnitude": 6}),
	])
	var spam := cost.composition_cost([
		_atom("fire_damage", {"magnitude": 6}),
		_atom("fire_damage", {"magnitude": 6}),
	])
	assert_lt(varied, spam)


# --- delivery method pricing -----------------------------------------------

func test_delivery_multiplier_orders_self_below_touch_below_area():
	assert_lt(cost.delivery_multiplier("self"), cost.delivery_multiplier("touch"))
	assert_lt(cost.delivery_multiplier("touch"), cost.delivery_multiplier("projectile"))
	assert_lt(cost.delivery_multiplier("projectile"), cost.delivery_multiplier("area"))


func test_area_delivery_costs_more_than_self_for_the_same_atoms():
	var atoms := [_atom("fire_damage", {"magnitude": 6})]
	assert_gt(cost.derived_base(atoms, "area"), cost.derived_base(atoms, "self"))


# --- duration-scaled atoms -------------------------------------------------

func test_duration_atom_at_reference_duration_costs_its_base():
	# ignite has dur_ref 3.0 and base_cost 1.5; at exactly the reference
	# duration the multiplier is 1.0.
	assert_almost_eq(cost.atom_cost("ignite", {"duration": 3.0}), 1.5, 0.0001)


func test_longer_duration_costs_more():
	assert_gt(cost.atom_cost("ignite", {"duration": 6.0}), cost.atom_cost("ignite", {"duration": 3.0}))


# --- area radius adds cost --------------------------------------------------

func test_a_burst_radius_increases_cost():
	var point := cost.atom_cost("fire_damage", {"magnitude": 6})
	var burst := cost.atom_cost("fire_damage", {"magnitude": 6, "radius": 4.0})
	assert_gt(burst, point)


# --- stat-driven efficiency (affordability, not power) ---------------------

func test_efficiency_is_one_at_zero_governing_stat():
	assert_almost_eq(cost.efficiency(0.0), 1.0, 0.0001)


func test_efficiency_rises_with_the_governing_stat():
	assert_gt(cost.efficiency(50.0), cost.efficiency(0.0))


func test_paid_mana_at_zero_stat_equals_the_derived_base():
	# Stats only discount; with no governing stat you pay the full derived
	# price and nothing cheaper.
	var atoms := [_atom("fire_damage", {"magnitude": 8}), _atom("ignite", {"duration": 3})]
	assert_almost_eq(cost.paid_mana(atoms, "touch", 0.0), cost.derived_base(atoms, "touch"), 0.0001)


func test_higher_governing_stat_reduces_paid_mana():
	var atoms := [_atom("fire_damage", {"magnitude": 8})]
	var novice := cost.paid_mana(atoms, "projectile", 0.0)
	var adept := cost.paid_mana(atoms, "projectile", 50.0)
	assert_lt(adept, novice)


func test_paid_mana_stays_positive_however_high_the_stat():
	var atoms := [_atom("fire_damage", {"magnitude": 8})]
	assert_gt(cost.paid_mana(atoms, "projectile", 100000.0), 0.0)


func test_stats_do_not_change_the_derived_base():
	# The power price is structural: derived_base takes no stats at all, so a
	# strong caster cannot make a spell hit harder, only cost less.
	var atoms := [_atom("frost_damage", {"magnitude": 10})]
	var base := cost.derived_base(atoms, "projectile")
	assert_almost_eq(cost.paid_mana(atoms, "projectile", 0.0), base, 0.0001)


# --- cast time --------------------------------------------------------------

func test_bigger_spells_take_longer_to_cast():
	var small := [_atom("fire_damage", {"magnitude": 6})]
	var big := [_atom("fire_damage", {"magnitude": 20})]
	assert_gt(cost.cast_time(big, "touch", 0.0), cost.cast_time(small, "touch", 0.0))


func test_haste_stat_shortens_cast_time():
	var atoms := [_atom("fire_damage", {"magnitude": 12})]
	assert_lt(cost.cast_time(atoms, "touch", 40.0), cost.cast_time(atoms, "touch", 0.0))


# --- material-component cost (2026-07-15 brainstorm: "a third power axis") --
# (docs/concept/magic.md: "spells can consume material components -- genetic
# or mined mats (a fire gem, a frost hide) -- so casting draws on the same
# economy crafting does." Materials are declared per-atom via a "materials"
# params key, the same way magnitude/duration/radius already are.)

func test_material_cost_of_atoms_with_no_materials_declared_is_empty():
	var atoms := [_atom("fire_damage", {"magnitude": 6})]
	assert_eq(cost.material_cost(atoms), {})


func test_material_cost_reads_the_declared_material_and_quantity():
	var atoms := [_atom("fire_damage", {"magnitude": 6, "materials": {"fire_gem": 1}})]
	assert_eq(cost.material_cost(atoms), {"fire_gem": 1.0})


func test_material_cost_sums_the_same_material_across_atoms():
	var atoms := [
		_atom("fire_damage", {"magnitude": 6, "materials": {"fire_gem": 1}}),
		_atom("ignite", {"duration": 3, "materials": {"fire_gem": 2}}),
	]
	assert_eq(cost.material_cost(atoms), {"fire_gem": 3.0})


func test_material_cost_keeps_distinct_materials_separate():
	var atoms := [
		_atom("frost_damage", {"magnitude": 6, "materials": {"frost_hide": 1}}),
		_atom("fire_damage", {"magnitude": 6, "materials": {"fire_gem": 2}}),
	]
	var result: Dictionary = cost.material_cost(atoms)
	assert_eq(result["frost_hide"], 1.0)
	assert_eq(result["fire_gem"], 2.0)


func test_breakdown_includes_the_material_cost():
	var atoms := [_atom("fire_damage", {"magnitude": 6, "materials": {"fire_gem": 1}})]
	var result := cost.breakdown(atoms, "touch", 0.0, 0.0)
	assert_eq(result["materials"], {"fire_gem": 1.0})


# --- caster self-danger (2026-07-15 brainstorm: "physical honesty cuts both
# ways") -------------------------------------------------------------------
# A spell is a force the sim resolves and does not spare the one who cast it
# (docs/concept/magic.md). "self" delivery always reaches the caster by
# design; any other delivery only blows back if the caster's standoff
# distance is within the effect's own radius.

func test_self_delivery_always_affects_the_caster():
	assert_true(cost.does_affect_caster("self", 0.0, 0.0))
	assert_true(cost.does_affect_caster("self", 0.0, 100.0))


func test_non_self_delivery_with_no_radius_never_affects_a_distant_caster():
	assert_false(cost.does_affect_caster("touch", 0.0, 1.0))
	assert_false(cost.does_affect_caster("projectile", 0.0, 1.0))


func test_area_delivery_affects_a_caster_standing_inside_the_radius():
	assert_true(cost.does_affect_caster("area", 5.0, 3.0))


func test_area_delivery_does_not_affect_a_caster_standing_outside_the_radius():
	assert_false(cost.does_affect_caster("area", 5.0, 10.0))


func test_caster_exactly_at_the_radius_boundary_is_affected():
	assert_true(cost.does_affect_caster("area", 5.0, 5.0))
