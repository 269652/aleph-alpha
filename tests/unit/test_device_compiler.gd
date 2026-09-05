extends GutTest

## Red-first spec for docs/concept/standard_model.md's compile step
## ("5. Resolution order", step 1): a parsed `device` AST becomes a REAL
## PartGraph (the shipped one, validated by its own rules) plus the element
## chain device_network.gd solves -- every parameter either authored or
## derived from a named part, every domain checked along the loop, every
## refusal naming what actually bit.
##
## Nothing here branches on what a device IS. A mill and a lamp compile
## through the same clauses; what differs is what the physics says about
## them afterwards.

const DeviceParser = preload("res://src/gameplay/device_parser.gd")
const DeviceCompiler = preload("res://src/gameplay/device_compiler.gd")
const DevicePhysics = preload("res://src/gameplay/device_physics.gd")

var parser: DeviceParser


func before_each():
	parser = DeviceParser.new()


func _compiled(source: String) -> Dictionary:
	var parsed: Dictionary = parser.parse(source)
	assert_true(parsed["ok"], "fixture must parse, errors: %s" % [parsed["errors"]])
	var result: Dictionary = DeviceCompiler.compile(parsed["ast"])
	assert_true(result["ok"], "expected a compile, errors: %s" % [result["errors"]])
	return result


func _refused(source: String, mentioning: String) -> Dictionary:
	var parsed: Dictionary = parser.parse(source)
	assert_true(parsed["ok"], "fixture must parse, errors: %s" % [parsed["errors"]])
	var result: Dictionary = DeviceCompiler.compile(parsed["ast"])
	assert_false(result["ok"], "expected a refusal for: %s" % source)
	assert_gt(result["errors"].size(), 0)
	var joined := " | ".join(PackedStringArray(result["errors"]))
	assert_true(joined.contains(mentioning), "expected '%s' in: %s" % [mentioning, joined])
	return result


const MILL_RACE_LIGHT := """
	device "Mill Race Light" {
	  part wheel: wood face working (width_cm: 200, height_cm: 200, thickness_cm: 4)
	  part axle: iron haft structure (length_cm: 60, diameter_cm: 4)
	  part wire: copper haft structure (length_cm: 1000, diameter_cm: 0.3)
	  part filament: carbon haft working (length_cm: 2, diameter_cm: 0.01)
	  joint hub: wheel to axle rigid fit iron

	  law river: source(domain: translation, fluid: water, area_m2: 0.5, velocity: 1.5)
	  law wheel: transform(in: translation, out: rotation, part: wheel)
	  law dynamo: gyrate(in: rotation, out: electrical, magnet_tesla: 0.5, turns: 200, area_m2: 0.02)
	  law wire: resist(domain: electrical, part: wire)
	  law filament: resist(domain: electrical, part: filament)

	  loop river |> wheel |> dynamo |> wire |> filament

	  on step when filament.power >= 1: shine(target: filament)
	}
"""


# --- result shape ---------------------------------------------------------------

func test_result_always_has_every_key_whether_or_not_it_compiled():
	for source in ['device "X" { }', 'device "X" { part p: unobtainium haft grip }']:
		var result: Dictionary = DeviceCompiler.compile(parser.parse(source)["ast"])
		for key in ["ok", "errors", "graph", "mass_kg", "chain", "elements", "loop"]:
			assert_true(result.has(key), "missing %s" % key)


func test_a_null_ast_is_refused_rather_than_crashing():
	var result: Dictionary = DeviceCompiler.compile({})
	assert_false(result["ok"])
	assert_gt(result["errors"].size(), 0)


# --- structures: parts and joints become the shipped part graph ------------

func test_a_structure_compiles_to_a_real_part_graph_with_a_real_mass():
	var result := _compiled("""
		device "Frame" {
		  part rail_a: wood haft structure (length_cm: 30, diameter_cm: 2)
		  part rail_b: wood haft structure (length_cm: 30, diameter_cm: 2)
		  joint corner: rail_a to rail_b rigid pin wood
		}
	""")
	var graph: RefCounted = result["graph"]
	assert_true(graph.is_well_formed(), str(graph.validation_errors()))
	assert_eq(graph.part_ids(), ["rail_a", "rail_b"])
	assert_eq(graph.joint_ids(), ["corner"])
	assert_almost_eq(result["mass_kg"], graph.total_mass_kg(), 1e-12)
	assert_gt(result["mass_kg"], 0.0)
	assert_eq(result["chain"], [])
	assert_eq(result["loop"], [])


func test_part_validation_reasons_come_from_the_graph_itself():
	_refused('device "X" { part p: unobtainium haft grip (length_cm: 1, diameter_cm: 1) }',
		"unmodeled material 'unobtainium'")
	_refused('device "X" { part p: iron haft grip (length_cm: 1) }', "needs dimension 'diameter_cm'")
	_refused('device "X" { part p: iron blob grip }', "unknown geometry 'blob'")


func test_a_joint_naming_a_part_that_is_not_there_is_refused_by_the_graph():
	_refused("""
		device "X" {
		  part a: iron haft grip (length_cm: 1, diameter_cm: 1)
		  joint j: a to ghost rigid fit iron
		}
	""", "ghost")


func test_a_pivot_axis_word_becomes_a_real_axis():
	var result := _compiled("""
		device "Shears" {
		  part a: iron haft grip (length_cm: 8, diameter_cm: 0.6)
		  part b: iron haft grip (length_cm: 8, diameter_cm: 0.6)
		  joint pin: a to b pivot pin iron (axis: z)
		}
	""")
	var graph: RefCounted = result["graph"]
	assert_eq(graph.joint("pin").motion_axis(), Vector3.FORWARD)
	assert_false(graph.is_rigid_body())


func test_an_unknown_axis_word_is_refused_by_name():
	_refused("""
		device "X" {
		  part a: iron haft grip (length_cm: 8, diameter_cm: 0.6)
		  part b: iron haft grip (length_cm: 8, diameter_cm: 0.6)
		  joint pin: a to b pivot pin iron (axis: sideways)
		}
	""", "sideways")


func test_a_pivot_with_no_axis_gets_the_joints_own_reason():
	_refused("""
		device "X" {
		  part a: iron haft grip (length_cm: 8, diameter_cm: 0.6)
		  part b: iron haft grip (length_cm: 8, diameter_cm: 0.6)
		  joint pin: a to b pivot pin iron
		}
	""", "axis")


# --- laws: elements with resolved parameters -----------------------------------

func test_the_mill_race_light_compiles_to_the_derived_chain():
	var result := _compiled(MILL_RACE_LIGHT)
	assert_eq(result["loop"], ["river", "wheel", "dynamo", "wire", "filament"])
	var chain: Array = result["chain"]
	assert_eq(chain.size(), 5)
	# The river: momentum flux on half a square metre at 1.5 m/s.
	assert_eq(chain[0]["id"], "river")
	assert_eq(chain[0]["kind"], "source")
	assert_almost_eq(chain[0]["params"]["effort"], 720.0, 1e-6)
	assert_almost_eq(chain[0]["params"]["resistance"], 480.0, 1e-6)
	# The wheel: its own metre of radius.
	assert_almost_eq(chain[1]["params"]["ratio"], 1.0, 1e-9)
	# The dynamo: B A N.
	assert_almost_eq(chain[2]["params"]["ratio"], 2.0, 1e-9)
	# The wire and the filament: Pouillet's law over their own geometry.
	assert_almost_eq(chain[3]["params"]["resistance"], DevicePhysics.wire_resistance_ohms("copper", 1000.0, 0.3), 1e-12)
	assert_almost_eq(chain[4]["params"]["resistance"], DevicePhysics.wire_resistance_ohms("carbon", 2.0, 0.01), 1e-12)
	assert_between(chain[4]["params"]["resistance"], 12.0, 13.5)


func test_the_chain_carries_only_the_canonical_parameters_the_solver_consumes():
	var result := _compiled(MILL_RACE_LIGHT)
	assert_eq(result["chain"][3]["params"].keys(), ["resistance"])
	assert_eq(result["chain"][0]["params"].keys(), ["effort", "resistance"])
	# ...while the elements table keeps the domains for inspection.
	assert_eq(result["elements"]["wheel"]["domain_in"], "translation")
	assert_eq(result["elements"]["wheel"]["domain_out"], "rotation")
	assert_eq(result["elements"]["wire"]["domain_in"], "electrical")
	assert_eq(result["elements"]["wire"]["domain_out"], "electrical")


func test_compiling_twice_gives_the_same_chain():
	var ast: Dictionary = parser.parse(MILL_RACE_LIGHT)["ast"]
	assert_eq(DeviceCompiler.compile(ast)["chain"], DeviceCompiler.compile(ast)["chain"])


func test_an_authored_source_and_a_plain_resistor_need_no_parts_at_all():
	var result := _compiled("""
		device "Heater" {
		  law cell: source(domain: electrical, effort: 12, resistance: 0.5)
		  law coil: resist(domain: electrical, resistance: 6)
		  loop cell |> coil
		}
	""")
	assert_eq(result["chain"].size(), 2)
	assert_almost_eq(result["chain"][1]["params"]["resistance"], 6.0, 1e-9)


func test_an_unknown_element_kind_is_refused_by_name():
	_refused('device "X" { law x: levitate(altitude: 3) }', "levitate")


func test_duplicate_law_ids_are_refused():
	_refused("""
		device "X" {
		  law x: resist(domain: electrical, resistance: 1)
		  law x: resist(domain: electrical, resistance: 2)
		}
	""", "x")


func test_a_missing_canonical_parameter_is_named():
	_refused('device "X" { law x: resist(domain: electrical) }', "resistance")
	_refused('device "X" { law x: store(domain: electrical, capacity: 10) }', "full_effort")


# --- domains -------------------------------------------------------------------------

func test_a_one_port_law_needs_a_known_power_domain():
	_refused('device "X" { law x: resist(resistance: 1) }', "domain")
	_refused('device "X" { law x: resist(domain: magic, resistance: 1) }', "magic")
	# Thermal is a pseudo-bond: catalogued, honestly not solvable this slice.
	_refused('device "X" { law x: resist(domain: thermal, resistance: 1) }', "thermal")


func test_a_two_port_law_needs_in_and_out_power_domains():
	_refused('device "X" { law x: transform(ratio: 2) }', "in")
	_refused('device "X" { law x: transform(in: rotation, ratio: 2) }', "out")
	_refused('device "X" { law x: transform(in: rotation, out: magic, ratio: 2) }', "magic")


# --- derivations: derived wins, and only where a derivation exists -------------

func test_a_derived_parameter_may_not_also_be_authored():
	_refused("""
		device "X" {
		  part wire: copper haft structure (length_cm: 100, diameter_cm: 0.3)
		  law wire: resist(domain: electrical, part: wire, resistance: 5)
		}
	""", "derived")


func test_a_law_naming_a_missing_part_is_refused():
	_refused('device "X" { law wire: resist(domain: electrical, part: ghost) }', "ghost")


func test_a_resistance_is_derived_only_from_a_haft():
	_refused("""
		device "X" {
		  part blade: copper edge working (length_cm: 10, width_cm: 2, thickness_cm: 0.3, angle_deg: 20)
		  law blade: resist(domain: electrical, part: blade)
		}
	""", "haft")


func test_a_resistance_is_derived_only_in_the_electrical_domain():
	_refused("""
		device "X" {
		  part shaft: iron haft structure (length_cm: 100, diameter_cm: 3)
		  law shaft: resist(domain: rotation, part: shaft)
		}
	""", "electrical")


func test_a_wheel_ratio_is_derived_only_between_translation_and_rotation():
	_refused("""
		device "X" {
		  part wheel: wood face working (width_cm: 100, height_cm: 100, thickness_cm: 4)
		  law wheel: transform(in: rotation, out: rotation, part: wheel)
		}
	""", "translation")


func test_a_source_from_a_fluid_needs_a_known_fluid_and_its_two_figures():
	_refused('device "X" { law river: source(domain: translation, fluid: aether, area_m2: 1, velocity: 1) }', "aether")
	_refused('device "X" { law river: source(domain: translation, fluid: water, velocity: 1) }', "area_m2")
	_refused('device "X" { law river: source(domain: translation, fluid: water, area_m2: 1) }', "velocity")
	_refused('device "X" { law river: source(domain: translation, fluid: water, area_m2: 1, velocity: 1, effort: 3) }', "derived")


func test_a_windmill_source_is_the_same_law_with_air():
	var result := _compiled("""
		device "Windmill" {
		  law wind: source(domain: translation, fluid: air, area_m2: 10, velocity: 8)
		  law sails: transform(in: translation, out: rotation, ratio: 4)
		  law stone: resist(domain: rotation, resistance: 20)
		  loop wind |> sails |> stone
		}
	""")
	var expected: Dictionary = DevicePhysics.paddle_source(DevicePhysics.AIR_DENSITY_KG_M3, 10.0, 8.0)
	assert_almost_eq(result["chain"][0]["params"]["effort"], expected["effort"], 1e-9)
	assert_almost_eq(result["chain"][0]["params"]["resistance"], expected["resistance"], 1e-9)


func test_a_gyrator_from_faraday_needs_all_three_figures_and_not_also_a_ratio():
	_refused('device "X" { law g: gyrate(in: rotation, out: electrical, magnet_tesla: 0.5, turns: 200) }', "area_m2")
	_refused('device "X" { law g: gyrate(in: rotation, out: electrical, magnet_tesla: 0.5, turns: 200, area_m2: 0.02, ratio: 2) }', "derived")


# --- the loop -------------------------------------------------------------------------

func test_a_loop_must_name_laws():
	_refused("""
		device "X" {
		  law s: source(domain: electrical, effort: 1, resistance: 1)
		  loop s |> ghost
		}
	""", "ghost")


func test_a_loop_must_start_with_a_source():
	_refused("""
		device "X" {
		  law s: source(domain: electrical, effort: 1, resistance: 1)
		  law r: resist(domain: electrical, resistance: 1)
		  loop r |> s
		}
	""", "source")


func test_a_domain_mismatch_along_the_loop_names_both_ports():
	var result := _refused("""
		device "X" {
		  law river: source(domain: translation, effort: 1, resistance: 1)
		  law wire: resist(domain: electrical, resistance: 1)
		  loop river |> wire
		}
	""", "translation")
	var joined := " | ".join(PackedStringArray(result["errors"]))
	assert_true(joined.contains("electrical"), joined)
	assert_true(joined.contains("river"), joined)
	assert_true(joined.contains("wire"), joined)


func test_two_loops_are_refused_in_this_slice():
	_refused("""
		device "X" {
		  law s: source(domain: electrical, effort: 1, resistance: 1)
		  law r: resist(domain: electrical, resistance: 1)
		  loop s |> r
		  loop s
		}
	""", "one loop")


func test_laws_outside_the_loop_compile_but_are_not_in_the_chain():
	var result := _compiled("""
		device "X" {
		  law s: source(domain: electrical, effort: 1, resistance: 1)
		  law r: resist(domain: electrical, resistance: 1)
		  law spare: resist(domain: electrical, resistance: 7)
		  loop s |> r
		}
	""")
	assert_eq(result["loop"], ["s", "r"])
	assert_true(result["elements"].has("spare"))
	assert_eq(result["chain"].size(), 2)
