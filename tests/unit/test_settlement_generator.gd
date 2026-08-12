extends GutTest

## SettlementGenerator: procedural village placement (docs/concept/npc.md
## "Similar to minecraft there should be procedural generated NPC
## populations; villages and so"). Sparse, deterministic per chunk (so a
## revisited region's village looks the same every time, like trees/
## creatures), gated to habitable biomes, with a small fixed roster of
## NpcIdentities and non-overlapping house anchor positions.

const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")

const TILE_SIZE := 16
const CHUNK_SIZE := 32

var generator: SettlementGenerator


func before_each():
	generator = SettlementGenerator.new()


func test_settlements_only_appear_on_habitable_biomes():
	for biome in ["ocean", "mountain"]:
		var found := false
		for x in 200:
			if generator.has_settlement_at(Vector2i(x, 0), biome):
				found = true
				break
		assert_false(found, "%s should never host a settlement" % biome)


func test_settlements_appear_somewhere_across_enough_habitable_chunks():
	var found := false
	for x in 400:
		if generator.has_settlement_at(Vector2i(x, 0), "grassland"):
			found = true
			break
	assert_true(found, "expected at least one settlement across 400 grassland chunks")


func test_settlements_are_sparse_not_every_chunk():
	var count := 0
	for x in 400:
		if generator.has_settlement_at(Vector2i(x, 0), "grassland"):
			count += 1
	assert_lt(count, 400)


func test_has_settlement_at_is_deterministic():
	var chunk_coord := Vector2i(5, 5)
	assert_eq(
		generator.has_settlement_at(chunk_coord, "grassland"),
		generator.has_settlement_at(chunk_coord, "grassland")
	)


func _find_settlement_chunk(biome: String) -> Vector2i:
	for x in 400:
		var coord := Vector2i(x, 0)
		if generator.has_settlement_at(coord, biome):
			return coord
	fail_test("no settlement chunk found for %s within 400 chunks" % biome)
	return Vector2i.ZERO


func test_generate_settlement_returns_a_fixed_small_roster():
	var chunk_coord := _find_settlement_chunk("grassland")
	var settlement := generator.generate_settlement(chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
	assert_eq(settlement.npcs.size(), SettlementGenerator.POPULATION)
	assert_eq(settlement.house_positions.size(), SettlementGenerator.POPULATION)
	for npc in settlement.npcs:
		assert_true(npc is NpcIdentity)


func test_generate_settlement_includes_the_three_shared_landmarks():
	var chunk_coord := _find_settlement_chunk("grassland")
	var settlement := generator.generate_settlement(chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
	for landmark in ["well", "stall", "gate"]:
		assert_true(settlement.landmarks.has(landmark), "missing landmark: %s" % landmark)


func test_generate_settlement_house_positions_are_distinct():
	var chunk_coord := _find_settlement_chunk("grassland")
	var settlement := generator.generate_settlement(chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
	var seen := {}
	for pos in settlement.house_positions:
		assert_false(seen.has(pos), "duplicate house position: %s" % pos)
		seen[pos] = true


func test_generate_settlement_is_deterministic_for_the_same_chunk():
	var chunk_coord := _find_settlement_chunk("grassland")
	var origin := chunk_coord * CHUNK_SIZE
	var first := generator.generate_settlement(chunk_coord, origin, CHUNK_SIZE, TILE_SIZE)
	var second := generator.generate_settlement(chunk_coord, origin, CHUNK_SIZE, TILE_SIZE)
	assert_eq(first.house_positions, second.house_positions)
	for i in first.npcs.size():
		assert_eq(first.npcs[i].npc_name, second.npcs[i].npc_name)


func test_generate_settlement_positions_are_within_the_chunk_bounds():
	var chunk_coord := _find_settlement_chunk("grassland")
	var origin := chunk_coord * CHUNK_SIZE
	var settlement := generator.generate_settlement(chunk_coord, origin, CHUNK_SIZE, TILE_SIZE)
	for pos in settlement.house_positions:
		assert_between(pos.x, float(origin.x * TILE_SIZE), float((origin.x + CHUNK_SIZE) * TILE_SIZE))
		assert_between(pos.y, float(origin.y * TILE_SIZE), float((origin.y + CHUNK_SIZE) * TILE_SIZE))
	for landmark_pos in settlement.landmarks.values():
		assert_between(landmark_pos.x, float(origin.x * TILE_SIZE), float((origin.x + CHUNK_SIZE) * TILE_SIZE))
		assert_between(landmark_pos.y, float(origin.y * TILE_SIZE), float((origin.y + CHUNK_SIZE) * TILE_SIZE))
