extends SceneTree

## What each spell in the fixed book actually COSTS in SpellCost's own
## terms, and what a mage guild therefore charges to teach it, next to the
## shop's own real prices.
##
## This is how MEALS_PER_POWER_UNIT stopped being a number that felt about
## right and became a claim that could be written down and asserted: put
## every spell's derived_base beside what the merchant charges for a sword,
## a meal and a house blueprint, and the weight class a lesson belongs in
## is something you can read off rather than argue about. The band it
## produced is pinned in tests/unit/test_spell_tuition.gd.
##
## Usage: godot --headless -s tools/probe_spell_tuition.gd

const SpellBook = preload("res://src/gameplay/spell_book.gd")
const SpellCost = preload("res://src/gameplay/spell_cost.gd")
const SpellExecutor = preload("res://src/gameplay/spell_executor.gd")
const Shop = preload("res://src/gameplay/shop.gd")
const SpellTuition = preload("res://src/gameplay/spell_tuition.gd")


func _initialize() -> void:
	var book := SpellBook.new()
	var cost := SpellCost.new()
	var executor := SpellExecutor.new()
	var tuition := SpellTuition.new()
	print("-- what the merchant charges --")
	for item_id in Shop.CATALOG:
		print("  %-24s %4d" % [item_id, int(Shop.CATALOG[item_id])])
	print("-- gold per point of spell power: %.1f (%s meals at %d each) --" % [
		SpellTuition.gold_per_power_unit(),
		str(SpellTuition.MEALS_PER_POWER_UNIT),
		int(Shop.CATALOG.get(SpellTuition.MEAL_ITEM_ID, 0)),
	])
	for spell_id in book.known_ids():
		var ast = book.ast_for(spell_id)
		var rule = executor.cast_rule(ast)
		if rule == null:
			print("%s -> no cast rule" % spell_id)
			continue
		var atoms: Array = rule.get("pipeline", [])
		var delivery: String = executor.delivery_for(rule)
		var born := SpellTuition.STARTING_SPELL_IDS.has(spell_id)
		print("%-12s atoms=%d delivery=%-10s derived_base=%6.3f tier=%-9s tuition=%4d%s" % [
			spell_id, atoms.size(), delivery, cost.derived_base(atoms, delivery),
			tuition.tier_of(book, spell_id), tuition.tuition_for(book, spell_id),
			"  (known at birth -- never sold)" if born else "",
		])
	quit()
