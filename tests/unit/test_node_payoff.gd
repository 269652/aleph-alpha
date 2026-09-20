extends GutTest

## docs/concept/skill_payoff.md: a node is rendered by running the REAL
## consumer function twice -- once at the character's current bonus, once at
## the bonus this node would grant -- and showing both. Pure: no world, no
## player, no scene tree, in the spirit of test_errand_delivery.gd and
## test_spell_cost.gd.
##
## Every "before"/"after" this file asserts is recomputed here by calling the
## same real function the module is supposed to be calling. If NodePayoff ever
## starts restating `bonus_amount` in prettier words instead of asking the
## game, these tests go red.

const NodePayoff = preload("res://src/gameplay/node_payoff.gd")
const SkillWeb = preload("res://src/gameplay/skill_web.gd")
const Taming = preload("res://src/gameplay/taming.gd")
const Butchering = preload("res://src/gameplay/butchering.gd")
const SpeciesBite = preload("res://src/gameplay/species_bite.gd")
const MeleeAttack = preload("res://src/gameplay/melee_attack.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const SpellBook = preload("res://src/gameplay/spell_book.gd")
const SpellExecutor = preload("res://src/gameplay/spell_executor.gd")

## The character the previews below are rendered for: a hundred-health
## bare-handed hero with a fresh wolf on the rope and Fire Bolt prepared.
## Every value is a real number from the live game (Player.max_health's own
## export default, Player.UNARMED_DAMAGE, SpellBook's own fire_bolt source),
## so a preview asserted here is a preview somebody could actually see.
func _facts() -> Dictionary:
	var executor := SpellExecutor.new()
	var ast = SpellBook.new().ast_for("fire_bolt")
	return {
		"base_max_health": 100.0,
		"threat_species": "wolf",
		"unarmed_damage": 5.0,
		"held_weapon": null,
		"class_attack_bonus": 0.0,
		"restrained_condition": 0.8,
		"restrained_is_predator": false,
		"luck": 0.0,
		"carcass_mass_ratio": 1.0,
		"spell_rule": executor.cast_rule(ast),
		"spell_name": "Fire Bolt",
	}


func _stat(stat_name: String, bonus: float) -> Array:
	return [{"stat_name": stat_name, "bonus_amount": bonus}]


func _row_for(stat_name: String, rows: Array) -> Dictionary:
	for row in rows:
		if row["stat"] == stat_name:
			return row
	return {}


# -- the centrepiece: the real function, run twice -----------------------

func test_a_taming_node_is_rendered_by_running_the_real_break_free_curve():
	var facts := _facts()
	var rows: Array = NodePayoff.preview_for(
		_stat("taming_affinity", 4.0),
		{"taming_affinity": 2.0},
		NodePayoff.default_consumers(facts)
	)
	assert_eq(rows.size(), 1, "one stat granted, one row")
	var row: Dictionary = rows[0]
	assert_almost_eq(
		float(row["before"]), Taming.break_free_chance(0.8, false, 2.0, 0.0), 0.0001,
		"before is the live curve at what the character already has"
	)
	assert_almost_eq(
		float(row["after"]), Taming.break_free_chance(0.8, false, 6.0, 0.0), 0.0001,
		"after is the SAME curve at current + this node"
	)
	assert_almost_eq(float(row["delta"]), float(row["after"]) - float(row["before"]), 0.0001)
	assert_eq(row["better"], "lower", "an escape chance going down is good news")
	assert_true(bool(row["wired"]), "Player really passes taming_affinity into this curve")


func test_the_rendered_delta_is_not_the_nodes_own_number():
	var facts := _facts()
	var rows: Array = NodePayoff.preview_for(
		_stat("taming_affinity", 4.0), {"taming_affinity": 2.0},
		NodePayoff.default_consumers(facts)
	)
	var delta := absf(float(rows[0]["delta"]))
	assert_true(
		delta > 0.0 and delta < 4.0,
		"a +4 node does not move an escape CHANCE by 4 -- restating the bonus is the bug"
	)


func test_a_health_node_is_rendered_as_bites_survived():
	var facts := _facts()
	var bite := SpeciesBite.bite_damage_for("wolf")
	var rows: Array = NodePayoff.preview_for(
		_stat("max_health", 35.0), {"max_health": 0.0}, NodePayoff.default_consumers(facts)
	)
	var row: Dictionary = rows[0]
	assert_almost_eq(float(row["before"]), floorf(100.0 / bite), 0.0001)
	assert_almost_eq(float(row["after"]), floorf(135.0 / bite), 0.0001)
	assert_true(float(row["after"]) > float(row["before"]), "the juggernaut keystone buys real bites")


func test_an_attack_node_is_rendered_as_swings_to_fell_the_thing_in_front_of_you():
	var facts := _facts()
	var melee := MeleeAttack.new()
	var wolf_health: float = CreatureInfo.MAX_HEALTH_BY_SPECIES["wolf"]
	var bare := melee.attack_damage(null, 5.0)
	var rows: Array = NodePayoff.preview_for(
		_stat("attack_damage", 7.0), {"attack_damage": 0.0}, NodePayoff.default_consumers(facts)
	)
	var row: Dictionary = rows[0]
	assert_almost_eq(float(row["before"]), ceilf(wolf_health / bare), 0.0001,
		"before is the real swing count at the real unarmed damage")
	assert_almost_eq(float(row["after"]), ceilf(wolf_health / (bare + 7.0)), 0.0001)
	assert_eq(row["better"], "lower", "fewer swings is better")


func test_a_meat_node_is_rendered_through_the_butchering_function_itself():
	var facts := _facts()
	var rows: Array = NodePayoff.preview_for(
		_stat("meat_yield", 2.0), {"meat_yield": 1.0}, NodePayoff.default_consumers(facts)
	)
	var row: Dictionary = rows[0]
	assert_almost_eq(float(row["before"]), float(Butchering.meat_count(1.0, 1.0)), 0.0001)
	assert_almost_eq(float(row["after"]), float(Butchering.meat_count(3.0, 1.0)), 0.0001)


func test_a_spell_node_is_rendered_as_the_mana_the_spell_costs():
	var facts := _facts()
	var executor := SpellExecutor.new()
	var rule: Dictionary = facts["spell_rule"]
	var rows: Array = NodePayoff.preview_for(
		_stat("spell_efficiency", 8.0), {"spell_efficiency": 0.0},
		NodePayoff.default_consumers(facts)
	)
	var row: Dictionary = rows[0]
	assert_almost_eq(float(row["before"]), executor.cost_for(rule, 0.0), 0.0001)
	assert_almost_eq(float(row["after"]), executor.cost_for(rule, 8.0), 0.0001)
	assert_eq(row["better"], "lower", "mana spent going down is good news")
	assert_false(
		bool(row["wired"]),
		"the function takes the stat but Player's cast site passes 0.0 -- say so, do not pretend"
	)


func test_the_consumer_is_asked_exactly_twice_and_at_exactly_the_two_bonus_levels():
	var calls: Array = []
	var evaluate := func(value: float) -> float:
		calls.append(value)
		return value * 2.0
	var consumers := {
		"made_up": {"label": "Made Up", "unit": "widgets", "evaluate": evaluate},
	}
	var rows: Array = NodePayoff.preview_for(_stat("made_up", 5.0), {"made_up": 3.0}, consumers)
	assert_eq(calls, [3.0, 8.0], "current, then current + the node -- no third call, no other value")
	assert_almost_eq(float(rows[0]["before"]), 6.0, 0.0001)
	assert_almost_eq(float(rows[0]["after"]), 16.0, 0.0001)


func test_a_node_granting_the_same_stat_twice_is_one_row_evaluated_once_at_the_sum():
	var calls: Array = []
	var evaluate := func(value: float) -> float:
		calls.append(value)
		return value
	var consumers := {"made_up": {"label": "Made Up", "unit": "widgets", "evaluate": evaluate}}
	var node_stats := [
		{"stat_name": "made_up", "bonus_amount": 2.0},
		{"stat_name": "made_up", "bonus_amount": 3.0},
	]
	var rows: Array = NodePayoff.preview_for(node_stats, {"made_up": 1.0}, consumers)
	assert_eq(rows.size(), 1, "one stat key, one row -- a variant list never double-counts")
	assert_eq(calls, [1.0, 6.0])


# -- honesty about what is not built ------------------------------------

func test_a_stat_nothing_reads_is_marked_declared_rather_than_given_an_invented_effect():
	var rows: Array = NodePayoff.preview_for(
		_stat("trade_margin", 2.0), {"trade_margin": 1.0}, NodePayoff.default_consumers(_facts())
	)
	var row: Dictionary = rows[0]
	assert_eq(row["unit"], NodePayoff.UNIT_DECLARED)
	assert_almost_eq(float(row["before"]), 1.0, 0.0001, "the raw total, which is all there is")
	assert_almost_eq(float(row["after"]), 3.0, 0.0001)
	assert_false(bool(row["wired"]))
	assert_eq(row["label"], "Trade Margin", "the stat's own name, humanised, and nothing more")


func test_a_consumer_whose_fact_is_missing_is_not_registered_at_all():
	var consumers: Dictionary = NodePayoff.default_consumers({})
	assert_false(
		consumers.has("spell_efficiency"),
		"no spell equipped means no spell to price -- inventing one would be a fabricated effect"
	)
	var rows: Array = NodePayoff.preview_for(_stat("spell_efficiency", 8.0), {}, consumers)
	assert_eq(rows[0]["unit"], NodePayoff.UNIT_DECLARED)


func test_every_registered_consumer_really_moves_when_the_stat_moves():
	var consumers: Dictionary = NodePayoff.default_consumers(_facts())
	assert_gt(consumers.size(), 0, "the registry is not empty")
	for stat_key in consumers:
		var evaluate: Callable = consumers[stat_key]["evaluate"]
		var low := float(evaluate.call(0.0))
		var high := float(evaluate.call(20.0))
		assert_ne(low, high, "%s's consumer ignores the stat -- it is a stub, not a consumer" % stat_key)


func test_the_registry_cannot_grow_past_the_stats_this_project_has_declared():
	var consumers: Dictionary = NodePayoff.default_consumers(_facts())
	var registered := consumers.keys()
	registered.sort()
	var declared: Array = NodePayoff.CONSUMER_STATS.duplicate()
	declared.sort()
	assert_eq(registered, declared, "with every fact supplied, the registry IS the declared list")
	for stat_key in NodePayoff.WIRED_STATS:
		assert_true(consumers[stat_key]["wired"], "%s is claimed wired" % stat_key)


func test_the_stats_claimed_wired_are_really_read_by_the_live_game():
	var source := FileAccess.get_file_as_string("res://scenes/player.gd")
	assert_gt(source.length(), 0, "player.gd is readable")
	for stat_key in NodePayoff.WIRED_STATS:
		var read_via_bonus := source.contains('skill_bonus("%s")' % stat_key)
		var read_via_apply := source.contains('stat_name == "%s"' % stat_key)
		assert_true(
			read_via_bonus or read_via_apply,
			"%s is claimed wired but nothing in player.gd reads it" % stat_key
		)
	assert_false(
		source.contains("spell_efficiency"),
		"player.gd now mentions spell_efficiency -- if it is wired, move it into WIRED_STATS "
		+ "and correct docs/concept/skill_payoff.md's count"
	)


func test_the_measured_inert_count_is_recomputed_from_the_live_web():
	var web = SkillWeb.shared()
	var granted := {}
	var node_stats: Array = []
	for node_id in web.node_ids():
		var info: Dictionary = web.node_info(node_id)
		var stat_name := String(info.get("stat_name", ""))
		if stat_name != "":
			granted[stat_name] = true
		for variant in info.get("variants", []):
			granted[String(variant["stat_name"])] = true
	for stat_name in granted:
		node_stats.append({"stat_name": stat_name, "bonus_amount": 1.0})
	assert_eq(
		granted.size(), NodePayoff.WEB_STAT_COUNT_AT_AUDIT,
		"the web grants a different number of stats than the audit pinned"
	)
	assert_eq(
		NodePayoff.stats_without_consumers(node_stats).size(),
		NodePayoff.INERT_STAT_COUNT_AT_AUDIT,
		"wiring a stat up is good news -- correct the constant and the doc's count with it"
	)
	assert_eq(
		NodePayoff.WEB_STAT_COUNT_AT_AUDIT - NodePayoff.CONSUMER_STATS.size(),
		NodePayoff.INERT_STAT_COUNT_AT_AUDIT,
		"granted - consumed == inert, by arithmetic rather than by two claims"
	)


func test_stats_without_consumers_names_the_inert_ones_and_only_those():
	var asked := [
		{"stat_name": "taming_affinity", "bonus_amount": 1.0},
		{"stat_name": "trade_margin", "bonus_amount": 1.0},
		{"stat_name": "pet_loyalty", "bonus_amount": 1.0},
	]
	var inert: Array = NodePayoff.stats_without_consumers(asked)
	inert.sort()
	assert_eq(inert, ["pet_loyalty", "trade_margin"])


# -- relevance: what this node is worth to THIS character ----------------

func test_a_spell_node_matters_more_to_a_character_who_owns_spells():
	var node := _stat("spell_efficiency", 2.0)
	var with_spells: float = NodePayoff.relevance_for(node, {"spell_count": 3})
	var without: float = NodePayoff.relevance_for(node, {"spell_count": 0})
	assert_gt(with_spells, without, "a cheaper spell is worth more to somebody who has one")


func test_a_taming_node_matters_more_to_a_character_with_a_companion():
	var node := _stat("taming_affinity", 4.0)
	assert_gt(
		NodePayoff.relevance_for(node, {"companion_count": 1}),
		NodePayoff.relevance_for(node, {"companion_count": 0})
	)


func test_evidence_of_one_system_does_not_leak_into_another():
	var node := _stat("taming_affinity", 4.0)
	assert_eq(
		NodePayoff.relevance_for(node, {"spell_count": 9}),
		NodePayoff.relevance_for(node, {}),
		"owning nine spells says nothing about whether a taming node matters"
	)


func test_a_stat_nothing_reads_is_worth_nothing_to_anybody():
	assert_eq(
		NodePayoff.relevance_for(_stat("trade_margin", 10.0), {"gold": 9999, "spell_count": 9}),
		0.0,
		"a number no code reads cannot matter -- pillar 1, stated as arithmetic"
	)


func test_relevance_is_capped_at_one_and_a_single_evidenced_live_stat_reaches_it():
	var evidenced := {"companion_count": 2, "spell_count": 2, "damage_taken": 30.0}
	assert_almost_eq(
		NodePayoff.relevance_for(_stat("taming_affinity", 4.0), evidenced), 1.0, 0.0001,
		"one live stat the character has evidence for IS a maximally relevant node"
	)
	var three := [
		{"stat_name": "taming_affinity", "bonus_amount": 1.0},
		{"stat_name": "spell_efficiency", "bonus_amount": 1.0},
		{"stat_name": "max_health", "bonus_amount": 1.0},
	]
	assert_almost_eq(NodePayoff.relevance_for(three, evidenced), 1.0, 0.0001, "clamped, never above 1")


func test_the_relevance_weights_define_their_own_ceiling():
	assert_almost_eq(
		NodePayoff.LIVE_STAT_SCORE + NodePayoff.EVIDENCE_SCORE, 1.0, 0.0001,
		"the ceiling is the two weights, not a third constant that could drift from them"
	)
	assert_eq(NodePayoff.INERT_STAT_SCORE, 0.0)


func test_a_live_stat_with_no_evidence_still_beats_an_inert_one():
	var live: float = NodePayoff.relevance_for(_stat("taming_affinity", 4.0), {})
	assert_almost_eq(live, NodePayoff.LIVE_STAT_SCORE, 0.0001)
	assert_gt(live, NodePayoff.relevance_for(_stat("trade_margin", 4.0), {}))


# -- the copied numbers, held to the files they were copied from ---------

func test_the_restated_unarmed_damage_is_the_players_own():
	var source := FileAccess.get_file_as_string("res://scenes/player.gd")
	var pattern := RegEx.new()
	pattern.compile("const UNARMED_DAMAGE := ([0-9.]+)")
	var found: RegExMatch = pattern.search(source)
	assert_not_null(found, "Player.UNARMED_DAMAGE moved or was renamed")
	if found == null:
		return
	assert_almost_eq(
		float(found.get_string(1)), NodePayoff.PLAYER_UNARMED_DAMAGE, 0.0001,
		"the fallback unarmed damage drifted from the one the game really swings"
	)


func test_a_fresh_animals_condition_is_the_taming_functions_own():
	assert_almost_eq(
		NodePayoff.FRESH_ANIMAL_CONDITION, Taming.effective_condition(1.0, 0.0), 0.0001,
		"an unhurt, unfatigued animal -- not an invented 1.0"
	)


func test_the_module_stays_pure():
	var source := FileAccess.get_file_as_string("res://src/gameplay/node_payoff.gd")
	assert_gt(source.length(), 0)
	for forbidden in ["get_tree()", "FileAccess", "Engine.get_singleton", "get_node("]:
		assert_false(
			source.contains(forbidden),
			"%s in a module that is supposed to be a pure RefCounted of static functions" % forbidden
		)


# -- more honesty branches -----------------------------------------------

func test_an_unknown_species_leaves_the_swing_count_declared_rather_than_guessed():
	var facts := _facts()
	facts["threat_species"] = "chimera"
	var consumers: Dictionary = NodePayoff.default_consumers(facts)
	assert_false(
		consumers.has("attack_damage"),
		"nothing knows a chimera's health, so nothing can honestly count swings against one"
	)
	var rows: Array = NodePayoff.preview_for(_stat("attack_damage", 7.0), {}, consumers)
	assert_eq(rows[0]["unit"], NodePayoff.UNIT_DECLARED)


func test_stats_without_consumers_answers_for_the_registry_it_is_given():
	var asked := [
		{"stat_name": "attack_damage", "bonus_amount": 1.0},
		{"stat_name": "taming_affinity", "bonus_amount": 1.0},
	]
	var facts := _facts()
	facts["threat_species"] = "chimera"
	assert_eq(
		NodePayoff.stats_without_consumers(asked, NodePayoff.default_consumers(facts)),
		["attack_damage"],
		"asked of THIS character's registry, a stat whose fact is missing is inert for them"
	)
	assert_eq(
		NodePayoff.stats_without_consumers(asked), [],
		"asked of the project as a whole, both stats have a real consumer"
	)


func test_an_empty_node_grants_nothing_and_is_worth_nothing():
	assert_eq(NodePayoff.preview_for([], {"max_health": 10.0}, NodePayoff.default_consumers(_facts())), [])
	assert_eq(NodePayoff.stats_without_consumers([]), [])
	assert_eq(NodePayoff.relevance_for([], {"companion_count": 5}), 0.0)
	var gateway := [{"stat_name": "", "bonus_amount": 0.0}]
	assert_eq(
		NodePayoff.preview_for(gateway, {}, NodePayoff.default_consumers(_facts())), [],
		"a gateway grants no stat, so it has no rows -- not a row about nothing"
	)
