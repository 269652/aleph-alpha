extends GutTest

## Red-first spec for the NPC instruction DSL's complexity-budget cost model
## (docs/concept/npc_instructions.md, "Complexity budget"). Cost is a
## DETERMINISTIC function of a parsed script's rule count and the
## condition/action primitives (and their resource rarity) each rule uses --
## nothing in the grammar can set this number directly. Every tuned constant
## in npc_instruction_cost.gd is pinned here rather than eyeballed
## (CLAUDE.md: tuned values must be a tested function, never an eyeballed
## comment).
##
## No cap/reject enforcement is tested here -- this file only pins the
## deterministic cost derivation itself. Checking the number against a
## trust-derived ceiling is hiring_gate.gd, a later step (concept doc,
## "What the number gates against is not a per-cast resource").

const NpcInstructionParser = preload("res://src/world/npc_instruction_parser.gd")
const NpcInstructionCost = preload("res://src/world/npc_instruction_cost.gd")


## Parses real DSL source text and returns the AST, same convention
## test_npc_instruction_primitives.gd already uses -- pins this module
## against the parser's actual emitted contract, not an assumption about it.
func _ast_for(source: String) -> Dictionary:
	var parser := NpcInstructionParser.new()
	var result: Dictionary = parser.parse(source)
	assert_true(result["ok"], "expected parse to succeed, errors: %s" % [result["errors"]])
	return result["ast"]


# --- action primitives cost more than condition primitives -----------------

func test_action_weight_is_higher_than_condition_weight():
	assert_gt(NpcInstructionCost.ACTION_WEIGHT, NpcInstructionCost.CONDITION_WEIGHT)


# --- rarity multiplier -------------------------------------------------------

func test_unknown_resource_reads_as_the_default_rarity():
	assert_eq(NpcInstructionCost.resource_rarity("unobtainium"), NpcInstructionCost.DEFAULT_RESOURCE_RARITY)


func test_gold_is_rarer_than_wood():
	assert_gt(NpcInstructionCost.resource_rarity("gold"), NpcInstructionCost.resource_rarity("wood"))


func test_hauling_a_rarer_item_costs_more_than_hauling_a_common_one():
	var common: float = NpcInstructionCost.action_cost({"fn": "haul", "args": {"item": "wood", "destination_tag": "base"}})
	var rare: float = NpcInstructionCost.action_cost({"fn": "haul", "args": {"item": "gold", "destination_tag": "base"}})
	assert_gt(rare, common)


func test_need_above_never_carries_a_rarity_multiplier():
	# A need name (hunger, ...) is not a resource/item/tag -- always the
	# default multiplier, whatever the need happens to be called.
	var call := {"fn": "need_above", "args": {"need": "hunger", "threshold": 0.7}}
	assert_almost_eq(
		NpcInstructionCost.condition_cost(call),
		NpcInstructionCost.CONDITION_WEIGHT * NpcInstructionCost.DEFAULT_RESOURCE_RARITY,
		0.0001
	)


# --- condition_cost / action_cost / rule_cost --------------------------------

func test_a_null_condition_costs_nothing():
	# The "otherwise" catch-all checks no fact.
	assert_eq(NpcInstructionCost.condition_cost(null), 0.0)


func test_rule_cost_is_the_flat_weight_plus_condition_plus_action():
	var rule := {
		"condition": {"fn": "inventory_at_least", "args": {"item": "wood", "count": 20}},
		"action": {"fn": "haul", "args": {"item": "wood", "destination_tag": "base"}},
	}
	var expected: float = (
		NpcInstructionCost.RULE_WEIGHT
		+ NpcInstructionCost.condition_cost(rule["condition"])
		+ NpcInstructionCost.action_cost(rule["action"])
	)
	assert_almost_eq(NpcInstructionCost.rule_cost(rule), expected, 0.0001)


func test_an_otherwise_rule_costs_the_flat_weight_plus_only_its_action():
	var rule := {"condition": null, "action": {"fn": "gather", "args": {"resource_tag": "wood"}}}
	var expected: float = NpcInstructionCost.RULE_WEIGHT + NpcInstructionCost.action_cost(rule["action"])
	assert_almost_eq(NpcInstructionCost.rule_cost(rule), expected, 0.0001)


# --- more rules costs more ---------------------------------------------------

func test_a_longer_script_costs_more_than_a_shorter_one_using_the_same_primitives():
	var shorter := _ast_for("instruct \"a\" { otherwise: gather(wood) }")
	var longer := _ast_for(
		"instruct \"b\" { if inventory_at_least(wood, 1): gather(wood)\n otherwise: gather(wood) }"
	)
	assert_gt(NpcInstructionCost.script_cost(longer), NpcInstructionCost.script_cost(shorter))


# --- pinned totals for concrete scripts --------------------------------------
#
# Fed real parser output (parsed from DSL source text), not hand-built AST
# literals -- pins the cost model against the parser's actual emitted
# contract. Both totals fail if RULE_WEIGHT, CONDITION_WEIGHT, ACTION_WEIGHT,
# or the resource rarity table silently drift.

func test_the_concept_docs_own_worked_example_costs_exactly_8_5():
	var ast := _ast_for(
		"instruct \"haul_and_forage\" {\n"
		+ "    if inventory_at_least(wood, 20): haul(wood, base)\n"
		+ "    if need_above(hunger, 0.7): gather(berries)\n"
		+ "    otherwise: gather(wood)\n"
		+ "}"
	)
	assert_almost_eq(NpcInstructionCost.script_cost(ast), 8.5, 0.0001)


func test_a_script_hauling_a_rare_resource_costs_exactly_7_8():
	var ast := _ast_for(
		"instruct \"haul_gold\" {\n"
		+ "    if inventory_at_least(gold, 5): haul(gold, base)\n"
		+ "    otherwise: gather(stone)\n"
		+ "}"
	)
	assert_almost_eq(NpcInstructionCost.script_cost(ast), 7.8, 0.0001)
