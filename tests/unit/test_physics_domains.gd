extends GutTest

## Red-first spec for the energy-domain catalog -- docs/concept/standard_model.md
## "The formal model / 1. Quantities". Every domain is an (effort, flow) pair
## whose product is power, except the thermal pseudo-bond whose flow already IS
## a power. The catalog is CLOSED: adding a sixth domain is a deliberate
## decision this file notices.

const PhysicsDomains = preload("res://src/gameplay/physics_domains.gd")

var domains: PhysicsDomains


func before_each():
	domains = PhysicsDomains.new()


# --- the closed catalog -------------------------------------------------------

func test_the_catalog_is_exactly_the_five_named_domains_in_a_fixed_order():
	assert_eq(domains.known_ids(), [
		"rotation", "translation", "electrical", "hydraulic", "thermal",
	])


func test_has_answers_only_for_catalogued_domains():
	assert_true(domains.has("rotation"))
	assert_true(domains.has("thermal"))
	assert_false(domains.has("magic"))
	assert_false(domains.has(""))


# --- every domain names its effort and flow with real SI units ---------------

func test_every_domain_names_its_effort_and_flow_variables_and_units():
	for domain_id in domains.known_ids():
		var spec: Dictionary = domains.spec(domain_id)
		for key in ["effort_name", "effort_unit", "flow_name", "flow_unit"]:
			assert_true(spec.has(key), "%s is missing %s" % [domain_id, key])
			assert_ne(String(spec[key]), "", "%s has an empty %s" % [domain_id, key])


func test_the_bond_graph_pairs_are_the_real_ones():
	assert_eq(domains.effort_name("rotation"), "torque")
	assert_eq(domains.effort_unit("rotation"), "N*m")
	assert_eq(domains.flow_name("rotation"), "angular_velocity")
	assert_eq(domains.flow_unit("rotation"), "rad/s")
	assert_eq(domains.effort_name("translation"), "force")
	assert_eq(domains.flow_name("translation"), "velocity")
	assert_eq(domains.effort_name("electrical"), "voltage")
	assert_eq(domains.flow_name("electrical"), "current")
	assert_eq(domains.effort_name("hydraulic"), "pressure")
	assert_eq(domains.flow_name("hydraulic"), "volumetric_flow")
	assert_eq(domains.effort_name("thermal"), "temperature")
	assert_eq(domains.flow_name("thermal"), "heat_flow")


# --- power -------------------------------------------------------------------

func test_effort_times_flow_is_power_in_every_true_power_domain():
	for domain_id in ["rotation", "translation", "electrical", "hydraulic"]:
		assert_true(domains.is_power_domain(domain_id), domain_id)
		assert_almost_eq(domains.power(domain_id, 3.0, 4.0), 12.0, 1e-9, domain_id)


func test_thermal_is_a_pseudo_bond_whose_flow_already_is_the_power():
	# Temperature x heat flow is NOT a power; the heat flow alone is one (W).
	assert_false(domains.is_power_domain("thermal"))
	assert_almost_eq(domains.power("thermal", 300.0, 4.0), 4.0, 1e-9)


func test_the_spec_is_a_defensive_copy():
	var spec: Dictionary = domains.spec("rotation")
	spec["effort_name"] = "vibes"
	assert_eq(domains.effort_name("rotation"), "torque")


func test_an_unknown_domain_carries_no_power():
	# The compiler rejects unknown domains before anything is solved; if one
	# ever slipped through, "nothing" is the honest answer, not a crash.
	assert_eq(domains.power("magic", 3.0, 4.0), 0.0)
	assert_false(domains.is_power_domain("magic"))
