extends SceneTree

## How many real founded villages have nobody to cart at all?
##
## A store nobody fills is exactly the reported bug ("the warehouse stays
## empty"), and hauling is now a trade -- so a roster that rolled no carter
## is a village whose producers keep their own output for ever.

const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const VillageCart = preload("res://src/gameplay/village_cart.gd")

const CHUNK_SIZE := 64
const TILE_SIZE := 16


func _init() -> void:
	var generator := SettlementGenerator.new()
	var villages := 0
	var without := 0
	var carters_total := 0
	for row in range(0, 6):
		for x in range(0, 400):
			var coord := Vector2i(x, row)
			if not generator.has_settlement_at(coord, "grassland"):
				continue
			var settlement = generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
			villages += 1
			var carters := 0
			for npc in settlement.npcs:
				if npc.occupation == VillageCart.OCCUPATION:
					carters += 1
			carters_total += carters
			if carters == 0:
				without += 1
	print("villages=%d  without a carter=%d (%.1f%%)  carters total=%d" % [
		villages, without, 100.0 * float(without) / maxf(float(villages), 1.0), carters_total
	])
	quit()
