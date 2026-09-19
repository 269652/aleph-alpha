extends SceneTree

## Which trades does a real village still have, now that `carter` is one of
## them and one villager is conscripted into it?
##
## Reported in play: *"The sawmill also doesn't produce beams or plangs or
## logs"*. A mill with nobody whose trade is timber produces nothing, which
## is exactly the shape of the original "the sawmill never produces any
## beams and doesn't even have a dedicated worker" report.

const SettlementGenerator = preload("res://src/world/settlement_generator.gd")

const CHUNK_SIZE := 64
const TILE_SIZE := 16


func _init() -> void:
	var generator := SettlementGenerator.new()
	var villages := 0
	var without_lumberjack := 0
	var without_farmer := 0
	var trade_counts: Dictionary = {}
	for row in range(0, 6):
		for x in range(0, 400):
			var coord := Vector2i(x, row)
			if not generator.has_settlement_at(coord, "grassland"):
				continue
			var settlement = generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
			villages += 1
			var here: Dictionary = {}
			for npc in settlement.npcs:
				here[npc.occupation] = int(here.get(npc.occupation, 0)) + 1
				trade_counts[npc.occupation] = int(trade_counts.get(npc.occupation, 0)) + 1
			if not here.has("lumberjack"):
				without_lumberjack += 1
			if not here.has("farmer") and not here.has("herbalist"):
				without_farmer += 1
	print("RESULT villages=%d  no lumberjack=%d (%.1f%%)  no farmer/herbalist=%d" % [
		villages, without_lumberjack,
		100.0 * float(without_lumberjack) / maxf(float(villages), 1.0), without_farmer
	])
	var trades: Array = trade_counts.keys()
	trades.sort()
	for trade in trades:
		print("RESULT   %-12s %d" % [trade, trade_counts[trade]])
	quit()
