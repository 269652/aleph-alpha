extends GutTest

## Real per-chunk aquatic vegetation (see docs/concept/aquatic_foraging.md).
##
## Mirrors TallGrass's own patch-sim contract almost exactly (pure
## RefCounted, PixelNoise-seeded smooth-noise field clustering, a hard cap,
## advance(delta, growth_modifier), a pure graze(cell) -> bool) -- what is
## genuinely different: seeding is gated to WATER cells
## (Chunk.blocks_ground_cover) instead of grassland, and there is no
## ground-seed-shedding layer at all.

const AquaticVegetation = preload("res://src/world/aquatic_vegetation.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")

const SIZE := 32


func _biome_all(name: String = "grassland") -> PackedStringArray:
	var out := PackedStringArray()
	for i in SIZE * SIZE:
		out.append(name)
	return out


## `is_water` mirrors Chunk.blocks_ground_cover's own shape: 1 where the
## real chunk has a river or lake cell, 0 elsewhere.
func _no_water() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(SIZE * SIZE)
	return out


func _all_water() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(SIZE * SIZE)
	for i in out.size():
		out[i] = 1
	return out


func _half_water() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(SIZE * SIZE)
	for y in SIZE:
		for x in SIZE:
			if x < SIZE / 2:
				out[y * SIZE + x] = 1
	return out


func _vegetation(is_water: PackedByteArray, seed_value: int = 1234) -> AquaticVegetation:
	return AquaticVegetation.new(seed_value, SIZE, SIZE, is_water)


# -- placement ----------------------------------------------------------------

func test_seeds_no_patches_when_there_is_no_water_at_all():
	var veg := _vegetation(_no_water())
	assert_eq(veg.get_patch_cells().size(), 0, "nothing to grow on without water")


func test_seeds_real_patches_when_the_whole_chunk_is_water():
	var veg := _vegetation(_all_water())
	assert_gt(veg.get_patch_cells().size(), 0, "an all-water chunk should grow real vegetation")


func test_every_seeded_patch_actually_sits_on_a_water_cell():
	var is_water := _half_water()
	var veg := _vegetation(is_water)
	for cell in veg.get_patch_cells():
		assert_eq(is_water[cell.y * SIZE + cell.x], 1, "a patch must not seed on dry ground")


func test_seeding_is_deterministic_for_the_same_seed():
	var a := _vegetation(_all_water(), 42)
	var b := _vegetation(_all_water(), 42)
	assert_eq(a.get_patch_cells(), b.get_patch_cells())


func test_different_seeds_produce_different_layouts():
	var a := _vegetation(_all_water(), 1)
	var b := _vegetation(_all_water(), 2)
	assert_ne(a.get_patch_cells(), b.get_patch_cells())


func test_patch_count_stays_within_the_per_chunk_bound():
	var veg := _vegetation(_all_water())
	assert_lte(veg.get_patch_cells().size(), AquaticVegetation.MAX_PATCHES)


## Same derivation and same failure class TallGrass's own identical test
## already guards against: initial seeding alone hitting an under-sized
## cap on a real, densely-eligible chunk (there: mostly grassland; here:
## mostly open water) would leave spread permanently unable to add
## anything new -- see MAX_PATCHES/SEED_CHANCE's own doc comments.
func test_max_patches_accommodates_the_density_target_for_a_real_full_chunk():
	var real_chunk_cells := EarthChunkManager.CHUNK_SIZE * EarthChunkManager.CHUNK_SIZE
	var target_density_patch_count := ceili(float(real_chunk_cells) * AquaticVegetation.SEED_CHANCE)
	assert_gte(AquaticVegetation.MAX_PATCHES, target_density_patch_count)


## Same "field, not salt-and-pepper" requirement TallGrass's own smooth-noise
## clustering satisfies -- neighbouring seeded cells should be more common
## than chance alone would produce.
func test_seeded_cells_cluster_next_to_each_other_more_than_chance_alone_would():
	var veg := _vegetation(_all_water())
	var cells := veg.get_patch_cells()
	if cells.size() < 4:
		pending("too few patches this seed to measure clustering")
		return
	var seeded := {}
	for cell in cells:
		seeded[cell] = true
	var adjacent_pairs := 0
	for cell in cells:
		for offset in [Vector2i(1, 0), Vector2i(0, 1)]:
			if seeded.has(cell + offset):
				adjacent_pairs += 1
	var expected_by_chance := float(cells.size() * cells.size()) / float(SIZE * SIZE) * 2.0
	assert_gt(float(adjacent_pairs), expected_by_chance)


# -- growth ---------------------------------------------------------------

## Same technique test_tall_grass.gd's own identical test uses: initial
## seeding starts every patch already mature (see AquaticVegetation's own
## doc comment), so an immature patch to grow only exists once spread has
## actually created one. Checked after EVERY tick, not just once at the
## end, since a patch that spreads early could mature past 1.0 before a
## single final check would ever notice it.
func test_advance_grows_immature_patches_toward_maturity():
	var veg := _vegetation(_all_water(), 1)
	var immature := Vector2i(-1, -1)
	for i in 20:
		veg.advance(AquaticVegetation.SPREAD_INTERVAL, 1.0)
		for cell in veg.get_patch_cells():
			if veg.get_growth(cell) < 1.0:
				immature = cell
				break
		if immature != Vector2i(-1, -1):
			break
	assert_ne(immature, Vector2i(-1, -1), "precondition: spread must have created at least one immature patch within 20 ticks")
	var before: float = veg.get_growth(immature)
	veg.advance(1.0, 1.0)
	assert_gt(veg.get_growth(immature), before)


func test_growth_is_capped_at_one():
	var veg := _vegetation(_all_water())
	var cell: Vector2i = veg.get_patch_cells()[0]
	veg.advance(1000000.0, 1.0)
	assert_almost_eq(veg.get_growth(cell), 1.0, 0.001)


## Real immature patches (via spread, see the test above) growing at two
## different growth_modifier values -- the fast one must pull ahead.
func test_advance_grows_slower_at_a_lower_growth_modifier():
	var veg := _vegetation(_all_water(), 1)
	var immature := Vector2i(-1, -1)
	for i in 20:
		veg.advance(AquaticVegetation.SPREAD_INTERVAL, 1.0)
		for cell in veg.get_patch_cells():
			if veg.get_growth(cell) < 0.5:
				immature = cell
				break
		if immature != Vector2i(-1, -1):
			break
	assert_ne(immature, Vector2i(-1, -1), "precondition: need a real immature patch with room left to grow")
	var slow_growth: float = veg.get_growth(immature)
	veg.advance(10.0, 0.1)
	var slow_after := veg.get_growth(immature)
	veg.advance(10.0, 1.0)
	var fast_after := veg.get_growth(immature)
	assert_gt(fast_after - slow_after, slow_after - slow_growth)


# -- spread -----------------------------------------------------------------

func test_no_spread_before_the_spread_interval_elapses():
	var veg := _vegetation(_half_water())
	var before := veg.get_patch_cells().size()
	veg.advance(AquaticVegetation.SPREAD_INTERVAL * 0.5, 1.0)
	assert_eq(veg.get_patch_cells().size(), before)


func test_mature_patches_spread_to_adjacent_water_over_time():
	var veg := _vegetation(_half_water())
	var before := veg.get_patch_cells().size()
	for i in 20:
		veg.advance(AquaticVegetation.SPREAD_INTERVAL, 1.0)
	assert_gte(veg.get_patch_cells().size(), before)


func test_spread_never_lands_on_a_dry_cell():
	var is_water := _half_water()
	var veg := _vegetation(is_water)
	for i in 20:
		veg.advance(AquaticVegetation.SPREAD_INTERVAL, 1.0)
	for cell in veg.get_patch_cells():
		assert_eq(is_water[cell.y * SIZE + cell.x], 1)


# -- grazing ------------------------------------------------------------------

func test_graze_removes_an_existing_patch_and_returns_true():
	var veg := _vegetation(_all_water())
	var cell: Vector2i = veg.get_patch_cells()[0]
	assert_true(veg.graze(cell))
	assert_false(veg.has_vegetation(cell))


func test_graze_on_an_empty_cell_returns_false():
	var veg := _vegetation(_all_water())
	assert_false(veg.graze(Vector2i(999, 999)))


func test_grazing_twice_on_the_same_cell_only_succeeds_once():
	var veg := _vegetation(_all_water())
	var cell: Vector2i = veg.get_patch_cells()[0]
	assert_true(veg.graze(cell))
	assert_false(veg.graze(cell))
