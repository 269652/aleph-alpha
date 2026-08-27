extends GutTest

## An assembly compiles to a RULE PROGRAM -- docs/concept/emergent_crafting.md.
##
## The headline is test_a_saw_emits_rip_and_not_chop_and_an_axe_emits_chop_and
## _not_rip, and the thing that makes it worth writing is that the two absences
## are INDEPENDENT physical failures rather than one flag read two ways: the saw
## fails on MASS and the axe fails on EDGE GEOMETRY.

var ItemCompiler: GDScript = preload("res://src/gameplay/item_compiler.gd")
var Assemblies: GDScript = preload("res://tests/fixtures/assembly_fixtures.gd")
var ImpactResolver: GDScript = preload("res://src/gameplay/impact_resolver.gd")
var MaterialProperties: GDScript = preload("res://src/gameplay/material_properties.gd")
var SpellParser: GDScript = preload("res://src/gameplay/spell_parser.gd")
var PartGraph: GDScript = preload("res://src/gameplay/part_graph.gd")
var ItemPart: GDScript = preload("res://src/gameplay/item_part.gd")

## Skill 1.0 throughout except where a test is about skill: a compiler test
## should not be accidentally about a novice's grind.
const MASTER := 1.0


func _affordances(graph: RefCounted) -> Array:
	return ItemCompiler.compile(graph, MASTER)["affordances"]


# -- THE HEADLINE ----------------------------------------------------------

func test_a_saw_emits_rip_and_not_chop_and_an_axe_emits_chop_and_not_rip() -> void:
	var saw: Array = _affordances(Assemblies.rip_saw())
	var axe: Array = _affordances(Assemblies.felling_axe())

	assert_has(saw, "rip", "a saw rips")
	assert_does_not_have(saw, "chop", "and a saw cannot chop")
	assert_has(axe, "chop", "an axe chops")
	assert_does_not_have(axe, "rip", "and an axe cannot rip")


## The two absences must come from two different pieces of physics. If the saw's
## missing chop and the axe's missing rip ever collapse into one shared flag,
## these two assertions are what notices.
func test_the_saw_and_the_axe_fail_for_two_independent_reasons() -> void:
	var saw_reason: String = ItemCompiler.compile(
		Assemblies.rip_saw(), MASTER
	)["absences"]["chop"]
	var axe_reason: String = ItemCompiler.compile(
		Assemblies.felling_axe(), MASTER
	)["absences"]["rip"]

	assert_string_contains(saw_reason, "momentum",
		"the saw's plate is too light to carry a chop -- a MASS failure")
	assert_false(saw_reason.contains("tooth"),
		"the saw has perfectly good teeth; they are not why it cannot chop")

	assert_string_contains(axe_reason, "tooth",
		"the axe's bit is transverse with no tooth pitch -- a GEOMETRY failure")
	assert_false(axe_reason.contains("momentum"),
		"the axe has momentum to spare; it is not why it cannot rip")


## And the set, not the sharpness, is what makes teeth work: a saw filed with
## every tooth it needs and no set still cannot rip, because it jams.
func test_a_saw_with_no_set_names_binding_rather_than_missing_teeth() -> void:
	var reason: String = ItemCompiler.compile(
		Assemblies.unset_saw(), MASTER
	)["absences"]["rip"]
	assert_string_contains(reason, "bind")
	assert_false(reason.contains("no tooth pitch"),
		"it has teeth -- what it has not got is somewhere for the plate to run")


# -- the guards read the shipped symbols -----------------------------------

## The rule's threshold must BE ImpactResolver's constant, not a copy of the
## number it happens to hold today. Asserted against the live symbol so that
## editing impact_resolver.gd moves both sides together and a hardcoded 3.0
## would be left behind.
func test_a_cut_rule_guard_reads_the_impact_resolver_symbol_not_a_copy() -> void:
	var guard: Dictionary = _rule_for(Assemblies.sword(), "cut_damage")["guard"]
	assert_eq(guard["op"], ">=")
	assert_eq(guard["lhs"], "impact.momentum")
	assert_eq(guard["rhs"], ImpactResolver.T_CUT)


func test_every_emitted_guard_reads_a_shipped_impact_threshold() -> void:
	var shipped := [
		ImpactResolver.T_CUT, ImpactResolver.T_PIERCE, ImpactResolver.T_CRUSH,
		ImpactResolver.BOUNCE_MOMENTUM_THRESHOLD,
	]
	for graph in [Assemblies.sword(), Assemblies.felling_axe(), Assemblies.rip_saw()]:
		for rule in ItemCompiler.compile(graph, MASTER)["rules"]:
			assert_has(shipped, (rule["guard"] as Dictionary)["rhs"],
				"every threshold must come from impact_resolver.gd")


# -- obsidian: an exception nobody wrote -----------------------------------

## Obsidian takes the keenest edge in the game AND shatters. Both fall out of
## its own property vector: the cut rule is emitted and the parry rule simply is
## not, because its guard is statically false. Nothing anywhere says "obsidian
## cannot parry".
func test_an_obsidian_blade_emits_no_parry_rule() -> void:
	var compiled: Dictionary = ItemCompiler.compile(Assemblies.obsidian_sword(), MASTER)
	assert_does_not_have(compiled["affordances"], "parry")
	assert_has(compiled["affordances"], "cut",
		"and it still cuts -- obsidian is the keenest thing there is")
	assert_string_contains(compiled["absences"]["parry"], "obsidian")
	for rule in compiled["rules"]:
		assert_ne((rule["pipeline"][0] as Dictionary)["atom"], "parry")


## The control: the same sword in iron does parry, so the absence above is about
## the material and not about swords.
func test_the_same_sword_in_iron_does_emit_a_parry_rule() -> void:
	assert_has(_affordances(Assemblies.sword()), "parry")


# -- malformed input errors, never crashes ---------------------------------

func test_a_headless_edge_does_not_compile() -> void:
	var compiled: Dictionary = ItemCompiler.compile(Assemblies.headless_edge(), MASTER)
	assert_false(compiled["ok"])
	assert_eq(compiled["rules"], [])
	assert_eq(compiled["affordances"], [])
	assert_eq(compiled["errors"].size(), 1)
	assert_string_contains(compiled["errors"][0], "grip")
	# It still has a mass. An offcut with no handle is a real lump of iron, and
	# refusing to say what it weighs would be a worse answer than the true one.
	assert_gt(compiled["mass_kg"], 0.0)


func test_a_bag_of_unjoined_parts_does_not_compile() -> void:
	var bag: RefCounted = PartGraph.new()
	bag.add_part("grip", ItemPart.new(
		"wood", ItemPart.GEOMETRY_HAFT, ItemPart.ROLE_GRIP,
		{"length_cm": 12.0, "diameter_cm": 3.0}
	))
	bag.add_part("blade", ItemPart.new(
		"iron", ItemPart.GEOMETRY_EDGE, ItemPart.ROLE_WORKING,
		{"length_cm": 20.0, "width_cm": 3.0, "thickness_cm": 0.3, "angle_deg": 18.0}
	))
	var compiled: Dictionary = ItemCompiler.compile(bag, MASTER)
	assert_false(compiled["ok"])
	assert_string_contains(compiled["errors"][0], "not joined")


func test_a_null_assembly_errors_rather_than_crashing() -> void:
	var compiled: Dictionary = ItemCompiler.compile(null, MASTER)
	assert_false(compiled["ok"])
	assert_eq(compiled["errors"].size(), 1)


# -- the AST is spell_parser's AST -----------------------------------------

## The claim the whole design rests on: a rule this compiler derives from steel
## and a rule a player wrote in the magic DSL are the SAME SHAPE, so they can
## live in one list on one item. Compared key-for-key against a rule the shipped
## parser actually produced, not against a remembered description of one.
func test_a_compiled_rule_has_the_same_shape_as_a_parsed_spell_rule() -> void:
	var parsed: Dictionary = SpellParser.new().parse(
		"enchant \"Flame Brand\" {\n" +
		"  on hit when impact.momentum >= 3:\n" +
		"    fire_damage(magnitude: 8)\n" +
		"}"
	)
	assert_true(parsed["ok"], str(parsed["errors"]))
	var authored: Dictionary = (parsed["ast"] as Dictionary)["rules"][0]
	var derived: Dictionary = _rule_for(Assemblies.sword(), "cut_damage")

	var authored_keys: Array = authored.keys()
	var derived_keys: Array = derived.keys()
	authored_keys.sort()
	derived_keys.sort()
	assert_eq(derived_keys, authored_keys, "a rule is a rule, whoever wrote it")

	var authored_guard: Dictionary = authored["guard"]
	var derived_guard: Dictionary = derived["guard"]
	var authored_guard_keys: Array = authored_guard.keys()
	var derived_guard_keys: Array = derived_guard.keys()
	authored_guard_keys.sort()
	derived_guard_keys.sort()
	assert_eq(derived_guard_keys, authored_guard_keys)

	var authored_step: Dictionary = (authored["pipeline"] as Array)[0]
	var derived_step: Dictionary = (derived["pipeline"] as Array)[0]
	var authored_step_keys: Array = authored_step.keys()
	var derived_step_keys: Array = derived_step.keys()
	authored_step_keys.sort()
	derived_step_keys.sort()
	assert_eq(derived_step_keys, authored_step_keys)


## Guards stay SINGLE comparisons, because spell_parser's `_parse_guard` has no
## `and`. Every conjunction is resolved statically instead -- which is the thing
## that makes the absence reasons possible at all.
func test_no_emitted_guard_is_a_conjunction() -> void:
	for graph in [Assemblies.sword(), Assemblies.felling_axe(), Assemblies.rip_saw()]:
		for rule in ItemCompiler.compile(graph, MASTER)["rules"]:
			var guard: Dictionary = rule["guard"]
			assert_eq(guard.keys().size(), 3, "op, lhs, rhs -- and nothing else")


# -- the cut line ----------------------------------------------------------

func test_the_cut_line_sits_between_the_shipped_razor_and_wedge_angles() -> void:
	assert_gt(ItemCompiler.CUTTING_GRIND_ANGLE_DEG, ItemPart.KEEN_ANGLE_DEG)
	assert_lt(ItemCompiler.CUTTING_GRIND_ANGLE_DEG, ItemPart.WEDGE_ANGLE_DEG)


## The threshold is DERIVED from two shipped symbols, not written down: it is
## the benchmark blade material (the one KEEN_SHARPNESS was itself set from)
## ground at the cutting line.
func test_the_cut_threshold_is_the_benchmark_blade_material_at_the_cutting_line() -> void:
	var materials: RefCounted = MaterialProperties.new()
	assert_eq(
		materials.property_value(ItemCompiler.BENCHMARK_BLADE_MATERIAL, "sharpness_capacity"),
		MaterialProperties.KEEN_SHARPNESS,
		"the benchmark blade must be the material KEEN_SHARPNESS came from"
	)
	var grind: float = (ItemPart.WEDGE_ANGLE_DEG - ItemCompiler.CUTTING_GRIND_ANGLE_DEG) \
		/ (ItemPart.WEDGE_ANGLE_DEG - ItemPart.KEEN_ANGLE_DEG)
	assert_almost_eq(
		ItemCompiler.cut_keenness_min(), MaterialProperties.KEEN_SHARPNESS * grind, 0.0001
	)


# -- crafter skill ---------------------------------------------------------

## A novice cannot put a severing edge on steel -- what they grind is a wedge.
## Same blade, same steel, same dimensions; only the hand that ground it differs.
func test_a_novice_grind_costs_the_blade_its_cut_rule() -> void:
	assert_has(_affordances(Assemblies.sword()), "cut")
	assert_does_not_have(ItemCompiler.compile(Assemblies.sword(), 0.3)["affordances"], "cut")


## And skill touches only the grind. Chopping is a question about mass, so a
## novice's sword still chops -- the two clauses stay independent.
func test_a_novice_grind_does_not_cost_the_blade_its_chop_rule() -> void:
	assert_has(ItemCompiler.compile(Assemblies.sword(), 0.3)["affordances"], "chop")


# -- the sword, end to end -------------------------------------------------

## The regression pin, on the SAME fixture test_part_graph.gd already asserts is
## a real arming sword at 1.0-1.5 kg. One sword in the repo, not two.
func test_the_compiled_sword_masses_what_the_part_graph_fixture_masses() -> void:
	assert_almost_eq(ItemCompiler.compile(Assemblies.sword(), MASTER)["mass_kg"], 1.3768, 0.0005)


func test_the_sword_compiles_to_the_verbs_a_sword_has() -> void:
	var sword: Array = _affordances(Assemblies.sword())
	assert_eq(sword, ["cut", "chop", "parry"],
		"a sword cuts, chops and blocks -- it does not rip, stab or crush,"
		+ " because it has no teeth, no point and no working head"
	)


## An invariant over every fixture: a verb is either afforded with a rule behind
## it or absent with a reason behind it, never both and never neither. The
## affordance list is a projection over the rules, so it cannot drift from them.
func test_every_verb_is_either_a_rule_or_a_reason() -> void:
	for graph in [
		Assemblies.sword(), Assemblies.felling_axe(), Assemblies.rip_saw(),
		Assemblies.obsidian_sword(), Assemblies.unset_saw(),
	]:
		var compiled: Dictionary = ItemCompiler.compile(graph, MASTER)
		var affordances: Array = compiled["affordances"]
		var absences: Dictionary = compiled["absences"]
		assert_eq(affordances.size(), (compiled["rules"] as Array).size(),
			"one rule per affordance")
		assert_eq(affordances.size() + absences.size(), ItemCompiler.VERBS.size())
		for verb in ItemCompiler.VERBS:
			assert_ne(affordances.has(verb), absences.has(verb),
				"'%s' must be exactly one of afforded or explained" % verb)
			if absences.has(verb):
				assert_ne(String(absences[verb]), "", "an absence with no reason is a black box")


func _rule_for(graph: RefCounted, atom: String) -> Dictionary:
	for rule in ItemCompiler.compile(graph, MASTER)["rules"]:
		if ((rule["pipeline"] as Array)[0] as Dictionary)["atom"] == atom:
			return rule
	return {}
