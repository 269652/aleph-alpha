extends GutTest

## SettlementGenerator: procedural village placement (docs/concept/npc.md
## "Similar to minecraft there should be procedural generated NPC
## populations; villages and so"). Sparse, deterministic per chunk (so a
## revisited region's village looks the same every time, like trees/
## creatures), gated to habitable biomes, with a small fixed roster of
## NpcIdentities and non-overlapping house anchor positions.

const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const VillageLayout = preload("res://src/world/village_layout.gd")

const TILE_SIZE := 16
const CHUNK_SIZE := 32

var generator: SettlementGenerator


func before_each():
	generator = SettlementGenerator.new()


## "forest" joined ocean/mountain directly per report: "houses / buildings
## cannot be built on river / water; also not in the forest" -- a real
## village would spend its whole existence fighting real, standing trees
## rather than ever finishing a house (see EarthChunkManager.
## is_buildable_terrain_at for the per-tile version of this same rule).
func test_settlements_only_appear_on_habitable_biomes():
	for biome in ["ocean", "mountain", "forest"]:
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


## The bigger multi-size houses (see ProceduralHouseSprite.SIZES) need real
## breathing room: every house must stand well clear of the village square
## (the well), even at its jittered innermost radius.
func test_houses_stand_clear_of_the_village_square():
	var chunk_coord := _find_settlement_chunk("grassland")
	var settlement := generator.generate_settlement(chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
	var well: Vector2 = settlement.landmarks["well"]
	var min_distance := (SettlementGenerator._HOUSE_RING_RADIUS_TILES - SettlementGenerator._HOUSE_RADIUS_JITTER_TILES) * TILE_SIZE
	for house in settlement.house_positions:
		assert_gte(house.distance_to(well), min_distance - 0.01, "house %s crowds the village square" % house)


## The well, stall and gate stand where VillageLayout's own skeleton puts
## them -- ON the paved plaza / at the street's entrance -- not at fixed
## offsets from the chunk centre that ignore where the street actually is.
func test_landmarks_stand_where_the_village_layout_skeleton_puts_them():
	var chunk_coord := _find_settlement_chunk("grassland")
	var origin := chunk_coord * CHUNK_SIZE
	var settlement := generator.generate_settlement(chunk_coord, origin, CHUNK_SIZE, TILE_SIZE)
	var skeleton: Dictionary = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(chunk_coord))
	for landmark in ["well", "stall", "gate"]:
		var cell: Vector2i = skeleton["landmarks"][landmark]
		var expected := Vector2(origin + cell) * TILE_SIZE + Vector2(TILE_SIZE, TILE_SIZE) * 0.5
		assert_eq(settlement.landmarks[landmark], expected, landmark)


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


# -- a village that grew (docs/concept/village_growth.md mechanism 3) ------
#
# POPULATION is the FOUNDING roster, not a ceiling: once households have
# moved in (EarthChunkManager.admit_household), the settlement has more
# villagers than it was founded with, and they have to be generated too.

func test_a_village_generates_exactly_the_population_it_is_asked_for():
	var coord := _find_settlement_chunk("grassland")
	var grown: Dictionary = generator.generate_settlement(coord, coord * 32, 32, 16, SettlementGenerator.POPULATION + 3)
	assert_eq(grown.npcs.size(), SettlementGenerator.POPULATION + 3)
	assert_eq(grown.house_positions.size(), grown.npcs.size(), "every villager still gets an anchor")


## A newcomer is exactly as reproducible as a founder: the same per-index
## seed, continued past the founding roster, so nobody's identity shifts
## when the village grows.
func test_growing_never_changes_who_the_founders_are():
	var coord := _find_settlement_chunk("grassland")
	var founded: Dictionary = generator.generate_settlement(coord, coord * 32, 32, 16)
	var grown: Dictionary = generator.generate_settlement(coord, coord * 32, 32, 16, SettlementGenerator.POPULATION + 2)
	for i in founded.npcs.size():
		assert_eq(grown.npcs[i].seed_value, founded.npcs[i].seed_value, "founder %d changed identity" % i)
		assert_eq(grown.npcs[i].occupation, founded.npcs[i].occupation)


func test_omitting_the_population_still_founds_the_original_roster():
	var coord := _find_settlement_chunk("grassland")
	assert_eq(
		generator.generate_settlement(coord, coord * 32, 32, 16).npcs.size(), SettlementGenerator.POPULATION
	)
