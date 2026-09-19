extends SceneTree

## How often does counting a hunter as a food producer actually change a
## village's roster? Over the RAW rolls, before any conscription.
##
## Measured because a claim was made without it: the village at (657,145)
## was cited as evidence that counting hunters left a farmhouse unworked,
## and it was not -- its producer is a FISHER, who works a pond rather than
## a farmhouse, which is correct behaviour. The hunter rule stands on its own
## measurement (a hunter yields ~0.02 food an assessment against a draw of
## 6, see docs/concept/settlement_food_calibration.md), and this is how far
## that reaches.
##
## Run: godot --headless -s tools/probe_roster_food_trades.gd

func _initialize() -> void:
	var NpcIdentity = load("res://src/world/npc_identity.gd")
	var rosters := 4000
	var population := 5
	var hunter_only := 0
	var already_fed := 0
	var nobody := 0
	for r in rosters:
		var trades := {}
		for i in population:
			var seed_value := hash("%d_%d_villager_%d" % [r, 7, i])
			trades[NpcIdentity.new(seed_value).occupation] = true
		var real_food: bool = trades.has("farmer") or trades.has("herbalist") or trades.has("fisher")
		var has_hunter: bool = trades.has("hunter")
		if real_food:
			already_fed += 1
		elif has_hunter:
			hunter_only += 1
		else:
			nobody += 1
	print("ROSTERS %d  already_fed=%d (%.1f%%)  hunter_only=%d (%.1f%%)  nobody=%d (%.1f%%)" % [
		rosters, already_fed, 100.0 * already_fed / rosters,
		hunter_only, 100.0 * hunter_only / rosters,
		nobody, 100.0 * nobody / rosters
	])
	quit()
