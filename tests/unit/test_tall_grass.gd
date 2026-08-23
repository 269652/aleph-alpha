extends GutTest

const TallGrass = preload("res://src/world/tall_grass.gd")

const WIDTH := 8
const HEIGHT := 8


func _biome_all(name: String) -> PackedStringArray:
	var biome := PackedStringArray()
	biome.resize(WIDTH * HEIGHT)
	biome.fill(name)
	return biome


func _biome_half_grassland() -> PackedStringArray:
	# Left half grassland, right half desert.
	var biome := PackedStringArray()
	biome.resize(WIDTH * HEIGHT)
	for y in HEIGHT:
		for x in WIDTH:
			biome[y * WIDTH + x] = "grassland" if x < WIDTH / 2 else "desert"
	return biome


func test_seeds_no_patches_when_there_is_no_grassland():
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("desert"))
	assert_eq(grass.get_patch_cells().size(), 0)


func test_seeds_patches_only_on_grassland_cells():
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_half_grassland())
	assert_gt(grass.get_patch_cells().size(), 0)
	for cell in grass.get_patch_cells():
		assert_lt(cell.x, WIDTH / 2)


## Long grass is a field the player can enter, not isolated decorations.
## Pin the initial density so future visual work cannot silently revert it.
func test_grassland_starts_with_a_visible_field_density():
	assert_gte(TallGrass.SEED_CHANCE, 0.20)
	assert_gte(TallGrass.MAX_PATCHES, 128)


func test_seeding_is_deterministic_for_the_same_seed():
	var a := TallGrass.new(7, WIDTH, HEIGHT, _biome_all("grassland"))
	var b := TallGrass.new(7, WIDTH, HEIGHT, _biome_all("grassland"))
	assert_eq(a.get_patch_cells(), b.get_patch_cells())


func test_different_seeds_produce_different_patch_layouts():
	var a := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	var b := TallGrass.new(2, WIDTH, HEIGHT, _biome_all("grassland"))
	assert_ne(a.get_patch_cells(), b.get_patch_cells())


func test_patch_count_stays_within_the_per_chunk_bound():
	var grass := TallGrass.new(3, WIDTH, HEIGHT, _biome_all("grassland"))
	for i in 200:
		grass.advance(TallGrass.SPREAD_INTERVAL)
	assert_lte(grass.get_patch_cells().size(), TallGrass.MAX_PATCHES)


func test_advance_grows_immature_patches_toward_maturity():
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	grass.advance(TallGrass.SPREAD_INTERVAL)  # spread creates an immature patch
	var immature := Vector2i(-1, -1)
	for cell in grass.get_patch_cells():
		if grass.get_growth(cell) < 1.0:
			immature = cell
	assert_ne(immature, Vector2i(-1, -1))
	var before: float = grass.get_growth(immature)
	grass.advance(1.0)
	assert_gt(grass.get_growth(immature), before)


func test_growth_is_capped_at_one():
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	var cell: Vector2i = grass.get_patch_cells()[0]
	grass.advance(10000.0)
	assert_eq(grass.get_growth(cell), 1.0)


func test_no_spread_before_the_spread_interval_elapses():
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	grass.advance(10000.0)  # everything mature; also one spread tick happens
	var count := grass.get_patch_cells().size()
	grass.advance(TallGrass.SPREAD_INTERVAL * 0.5)
	assert_eq(grass.get_patch_cells().size(), count)


func test_mature_patches_spread_to_adjacent_grassland_over_time():
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	var initial := grass.get_patch_cells().size()
	for i in 50:
		grass.advance(TallGrass.SPREAD_INTERVAL)
	assert_gt(grass.get_patch_cells().size(), initial)


func test_spread_never_lands_on_non_grassland_cells():
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_half_grassland())
	for i in 200:
		grass.advance(TallGrass.SPREAD_INTERVAL)
	for cell in grass.get_patch_cells():
		assert_lt(cell.x, WIDTH / 2)


func test_new_spread_patches_start_immature():
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	grass.advance(10000.0)  # mature everything, trigger a spread tick
	var found_immature := false
	for cell in grass.get_patch_cells():
		if grass.get_growth(cell) < 1.0:
			found_immature = true
	assert_true(found_immature)


func test_graze_removes_an_existing_patch_and_returns_true():
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	var cell: Vector2i = grass.get_patch_cells()[0]
	assert_true(grass.graze(cell))
	assert_false(grass.has_grass(cell))


func test_graze_on_an_empty_cell_returns_false():
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("desert"))
	assert_false(grass.graze(Vector2i(0, 0)))


func test_grazing_twice_on_the_same_cell_only_succeeds_once():
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	var cell: Vector2i = grass.get_patch_cells()[0]
	assert_true(grass.graze(cell))
	assert_false(grass.graze(cell))


# -- growth in one throttled batch -------------------------------------------
#
# EarthChunkManager used to advance every loaded chunk's sim EVERY FRAME --
# roughly 25 chunks x up to MAX_PATCHES cells of dictionary writes 60 times a
# second, measured at ~5ms per frame of the budget. Grass grows at
# GROWTH_RATE 0.01 per second; resolving that sixty times a second buys
# nothing. Growth is linear in delta and spread carries its own accumulator,
# so one batched call has to land in exactly the same state as many small ones.

func test_growth_lands_in_the_same_place_whether_batched_or_per_frame():
	var stepped := TallGrass.new(4242, 8, 8, _grassland(8, 8))
	var batched := TallGrass.new(4242, 8, 8, _grassland(8, 8))
	for _i in 300:
		stepped.advance(1.0 / 60.0)
	batched.advance(300.0 / 60.0)
	assert_eq(stepped.get_patch_cells().size(), batched.get_patch_cells().size())
	for cell in batched.get_patch_cells():
		assert_almost_eq(stepped.get_growth(cell), batched.get_growth(cell), 0.0001)


func test_spread_still_happens_across_a_batched_advance():
	var batched := TallGrass.new(99, 12, 12, _grassland(12, 12))
	var before := batched.get_patch_cells().size()
	batched.advance(TallGrass.SPREAD_INTERVAL * 3.0)
	assert_gt(batched.get_patch_cells().size(), before, "a batched step still spreads")


func _grassland(width: int, height: int) -> PackedStringArray:
	var biome := PackedStringArray()
	biome.resize(width * height)
	biome.fill("grassland")
	return biome
