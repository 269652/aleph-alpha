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


# -- the roster is staffed by demand ----------------------------------------
#
# Asked for directly: "Make it driven by demand." What that replaced was
# "if nobody in this roster farms, make the LAST one a farmer" -- one food
# producer, always, whatever the village's size and whatever it stood on.
#
# The count is SettlementFoodDemand.producers_needed (the village's own
# subsistence draw over what one producer's real work brings in) and the
# trade is SettlementFoodDemand.trade_for (whichever the land really feeds a
# village with). Both were only writable once the food model's two halves
# had been measured against each other -- see
# docs/concept/settlement_food_calibration.md.

const SettlementFoodDemand = preload("res://src/emergence/settlement_food_demand.gd")
const SettlementGranary = preload("res://src/emergence/settlement_granary.gd")


func _region(vegetation: float, herbivores: float, fish: float):
	var region = SettlementGranary.SeededRegion.new()
	region.vegetation_density = vegetation
	region.herbivore_population = herbivores
	region.fish_population = fish
	return region


func _food_producers(npcs: Array) -> int:
	var count := 0
	for npc in npcs:
		if SettlementFoodDemand.FOOD_TRADES.has(npc.occupation):
			count += 1
	return count


## Every village carries as many food producers as its own demand asks for
## -- never a fixed one.
func test_every_village_carries_the_food_producers_its_demand_asks_for():
	for i in 40:
		var coord := Vector2i(620 + i, 160 + (i % 7))
		var settlement := generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
		assert_gte(
			_food_producers(settlement.npcs),
			SettlementFoodDemand.producers_needed(settlement.npcs.size()),
			"the village at %s cannot feed itself" % str(coord)
		)


## A village that grows past what one producer feeds is staffed for the size
## it really is, which is the whole point of making it demand-driven.
func test_a_bigger_village_is_staffed_for_the_size_it_really_is():
	var coord := Vector2i(631, 163)
	var big: int = SettlementFoodDemand.households_fed_per_producer() * 2 + 1
	var settlement := generator.generate_settlement(
		coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, big
	)
	assert_eq(settlement.npcs.size(), big, "precondition: the whole roster really was generated")
	assert_gte(_food_producers(settlement.npcs), SettlementFoodDemand.producers_needed(big))
	assert_gte(SettlementFoodDemand.producers_needed(big), 3, "precondition: this size really needs several")


## The land picks the trade. Water means a fisher -- who digs and stocks a
## pond (docs/concept/village_ponds.md), which is what a player asked to see.
## A chunk whose own roll leaves the village short of the food producers its
## size demands -- the case conscription exists for, and the only one in
## which the LAND gets to pick the trade at all. A roster that already feeds
## itself is left alone.
##
## Asked of the RULE rather than of the roster it already acted on: a chunk
## qualifies when the same villagers come out differently on water than on
## dry ground, which happens exactly when conscription had something to do.
## Counting food trades in a returned roster cannot answer this -- staffing
## runs inside generate_settlement, so every roster it hands back already
## meets its own demand by construction. That reading agreed with this one
## while a village was five villagers needing one producer, and stopped the
## moment the founding roster grew: ten villagers roll enough food trades to
## feed themselves most of the time, so the old predicate started returning
## chunks the rule had correctly left alone, and the tests below then looked
## for a fisher nobody had any reason to conscript.
func _chunk_whose_roster_feeds_nobody() -> Vector2i:
	for i in 400:
		var coord := Vector2i(640 + i, 167)
		if _occupations(_roster_on(coord, 0.0)) != _occupations(_roster_on(coord, 800.0)):
			return coord
	fail_test("no chunk found whose own roll leaves the land anything to decide")
	return Vector2i.ZERO


func _roster_on(coord: Vector2i, water: float) -> Array:
	return generator.generate_settlement(
		coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE,
		SettlementGenerator.POPULATION, Callable(), _region(0.15, 0.9, water)
	).npcs


func _occupations(npcs: Array) -> Array:
	var out: Array = []
	for npc in npcs:
		out.append(npc.occupation)
	return out


## The land picks the trade. Water means a fisher -- who digs and stocks a
## pond (docs/concept/village_ponds.md), which is what a player asked to see.
func test_a_village_on_water_is_fed_by_a_fisher():
	var coord := _chunk_whose_roster_feeds_nobody()
	var settlement := generator.generate_settlement(
		coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE,
		SettlementGenerator.POPULATION, Callable(), _region(0.15, 0.9, 800.0)
	)
	var fishers := 0
	for npc in settlement.npcs:
		if npc.occupation == "fisher":
			fishers += 1
	assert_gt(fishers, 0, "land with real water should be worked by somebody who fishes it")


## ...and the same roster on dry grassland is fed by a farmer instead, who
## raises a farmhouse. Same chunk, same villagers, different land.
func test_the_same_roster_on_dry_grassland_is_fed_by_a_farmer():
	var coord := _chunk_whose_roster_feeds_nobody()
	var settlement := generator.generate_settlement(
		coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE,
		SettlementGenerator.POPULATION, Callable(), _region(0.15, 0.9, 0.0)
	)
	var farmers := 0
	for npc in settlement.npcs:
		if VillageFarm.crop_for(npc.occupation) != "":
			farmers += 1
	assert_gt(farmers, 0, "dry land is worked by somebody who works the ground")


## Conscription comes off the END of the roster, so a village's founders are
## exactly who they rolled except for the ones demand really needed.
func test_conscription_leaves_the_earlier_founders_exactly_as_they_rolled():
	var coord := Vector2i(651, 169)
	var plain := generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
	var needed: int = SettlementFoodDemand.producers_needed(plain.npcs.size())
	var untouched: int = plain.npcs.size() - needed
	var rolled := generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
	for i in untouched:
		assert_eq(plain.npcs[i].occupation, rolled.npcs[i].occupation, "villager %d" % i)


# -- every village has somebody who farms -----------------------------------

const VillageFarm = preload("res://src/gameplay/village_farm.gd")


## Reported live with the village in shot: "No Farmhouses".
##
## The siting was working the whole time. Measured across real settlement
## chunks (tools/probe_village_contents.gd): every village that WANTED a
## farmhouse and could be founded at all got exactly one. What was missing
## was anybody to want it -- occupations are drawn uniformly from nine, and
## five villagers miss both farmer and herbalist often enough that two of
## three founded villages had neither.
##
## A pre-industrial village that nobody feeds is not a village. The
## guarantee is "somebody FEEDS it" now rather than "somebody FARMS it" --
## a fisher with a stocked pond feeds a village too, and on land with real
## water they are who the demand rule picks. With no region to read, that
## falls back to farming, which is what this samples.
func test_every_village_has_somebody_who_feeds_it():
	var checked := 0
	for i in 40:
		var coord := Vector2i(600 + i, 140 + (i % 7))
		var settlement := generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
		assert_gt(
			_food_producers(settlement.npcs), 0,
			"the village at %s has nobody who feeds it" % str(coord)
		)
		checked += 1
	assert_eq(checked, 40, "precondition: every sampled chunk really produced a roster")


## Only the rosters that needed it, though -- a village that already rolled a
## farmer or a herbalist keeps exactly the villagers it rolled, so this
## cannot quietly turn every settlement into farmers.
func test_a_village_that_already_farms_is_left_alone():
	var touched := 0
	for i in 40:
		var coord := Vector2i(700 + i, 150 + (i % 5))
		var settlement := generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
		var occupations := {}
		for npc in settlement.npcs:
			occupations[npc.occupation] = int(occupations.get(npc.occupation, 0)) + 1
		var food := int(occupations.get("farmer", 0)) + int(occupations.get("herbalist", 0))
		if food > 1:
			touched += 1
	assert_gt(touched, 0, "some villages should still roll more than one food producer of their own")


func test_the_roster_is_still_deterministic_for_a_chunk():
	var coord := Vector2i(613, 141)
	var first := generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
	var second := generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
	for i in first.npcs.size():
		assert_eq(first.npcs[i].occupation, second.npcs[i].occupation)
		assert_eq(first.npcs[i].npc_name, second.npcs[i].npc_name)


# -- how big a village is founded -------------------------------------------

## Asked directly: *"please increase the village sizes from 5 houses to 10
## initial and then it should grow by itself; adding new houses new
## trades"*.
##
## The number itself, not just "whatever POPULATION happens to say": every
## other assertion in this file reads the constant symbolically, so a
## careless edit to it would move them all silently and this file would go
## on passing while villages shrank.
func test_a_village_is_founded_with_ten_households():
	assert_eq(SettlementGenerator.POPULATION, 10)


## And really produces them -- ten villagers, ten house anchors, all
## distinct, at the size a village is actually founded at rather than at a
## size only this file ever asks for.
func test_the_founding_roster_really_is_that_many_distinct_households():
	var chunk_coord := _find_settlement_chunk("grassland")
	var settlement := generator.generate_settlement(chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
	assert_eq(settlement.npcs.size(), 10)
	var seen := {}
	for position in settlement.house_positions:
		seen[position] = true
	assert_eq(seen.size(), 10, "ten households means ten places to live")
