extends GutTest

## VillageFinder: pure outward-ring search for the nearest settlement chunk
## (see SettlementGenerator.has_settlement_at) to a starting chunk -- the
## discovery half of the /village dev-console command (teleporting there is
## World's job, since that's where the local player lives).

const VillageFinder = preload("res://src/world/village_finder.gd")

var finder: VillageFinder


## A settlement exists at exactly the listed chunk coords; every biome
## lookup returns "grassland" (habitable) unless overridden per test.
class StubSettlementGenerator:
	var settlement_chunks: Dictionary = {}  # Vector2i -> true
	func has_settlement_at(chunk_coord: Vector2i, _dominant_biome: String) -> bool:
		return settlement_chunks.has(chunk_coord)


func before_each():
	finder = VillageFinder.new()


func _grassland(_chunk_coord: Vector2i) -> String:
	return "grassland"


func test_returns_the_start_chunk_when_it_already_has_a_settlement():
	var stub := StubSettlementGenerator.new()
	stub.settlement_chunks[Vector2i(5, 5)] = true
	var found: Variant = finder.find_nearest(Vector2i(5, 5), 10, stub, _grassland)
	assert_eq(found, Vector2i(5, 5))


func test_finds_the_nearest_settlement_in_an_expanding_ring():
	var stub := StubSettlementGenerator.new()
	# One at distance 2 (Chebyshev), one at distance 5 -- must return the closer one.
	stub.settlement_chunks[Vector2i(2, 0)] = true
	stub.settlement_chunks[Vector2i(5, 0)] = true
	var found: Variant = finder.find_nearest(Vector2i(0, 0), 10, stub, _grassland)
	assert_eq(found, Vector2i(2, 0))


func test_returns_null_when_nothing_is_found_within_the_radius():
	var stub := StubSettlementGenerator.new()
	stub.settlement_chunks[Vector2i(50, 50)] = true
	var found: Variant = finder.find_nearest(Vector2i(0, 0), 3, stub, _grassland)
	assert_null(found)


func test_a_settlement_just_outside_the_radius_is_not_found():
	var stub := StubSettlementGenerator.new()
	stub.settlement_chunks[Vector2i(4, 0)] = true
	var found: Variant = finder.find_nearest(Vector2i(0, 0), 3, stub, _grassland)
	assert_null(found)


func test_passes_each_candidate_chunks_own_biome_to_the_settlement_check():
	var stub := StubSettlementGenerator.new()
	stub.settlement_chunks[Vector2i(1, 0)] = true
	var seen_biomes: Array = []
	var biome_for := func(chunk_coord: Vector2i) -> String:
		seen_biomes.append(chunk_coord)
		return "grassland"
	finder.find_nearest(Vector2i(0, 0), 1, stub, biome_for)
	assert_true(seen_biomes.has(Vector2i(1, 0)), "the settlement check must see the real per-chunk biome")


# -- a settlement the world will not actually build is not a destination ---
#
# Reported in play: "It teleports me to where no village is".
# has_settlement_at is the procedural roll -- whether a settlement is meant
# to be here -- and it knows nothing about whether the ground can house
# one. Since a village only settles where there is room for all of it
# (VillageRenderer, docs/concept/building.md), the two can disagree, and
# the finder was sending the player to the chunks where they do.


func test_a_settlement_the_ground_cannot_take_is_passed_over():
	var stub := StubSettlementGenerator.new()
	stub.settlement_chunks[Vector2i(1, 0)] = true  # nearer, but unbuildable
	stub.settlement_chunks[Vector2i(4, 0)] = true
	var would_settle := func(chunk_coord: Vector2i) -> bool: return chunk_coord != Vector2i(1, 0)
	var found: Variant = finder.find_nearest(Vector2i.ZERO, 10, stub, _grassland, would_settle)
	assert_eq(found, Vector2i(4, 0), "the nearest village that is really there, not the nearest roll")


func test_nothing_is_found_when_no_settlement_can_be_built():
	var stub := StubSettlementGenerator.new()
	stub.settlement_chunks[Vector2i(2, 0)] = true
	stub.settlement_chunks[Vector2i(3, 3)] = true
	var never := func(_chunk_coord: Vector2i) -> bool: return false
	assert_null(finder.find_nearest(Vector2i.ZERO, 6, stub, _grassland, never))


func test_without_the_extra_condition_it_searches_exactly_as_before():
	var stub := StubSettlementGenerator.new()
	stub.settlement_chunks[Vector2i(2, 0)] = true
	assert_eq(finder.find_nearest(Vector2i.ZERO, 10, stub, _grassland), Vector2i(2, 0))
