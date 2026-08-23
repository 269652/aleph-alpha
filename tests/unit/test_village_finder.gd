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
