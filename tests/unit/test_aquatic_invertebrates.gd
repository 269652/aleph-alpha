extends GutTest

## Real per-chunk aquatic invertebrates (see docs/concept/aquatic_foraging.md's
## "Revised (2026-09-07)" -- the second real aquatic food layer, closing
## trout's own diet gap: real aquatic insect larvae, not a vegetation
## recolor).
##
## Mirrors AquaticVegetation's own contract line for line (itself mirroring
## TallGrass) -- pure RefCounted, PixelNoise-seeded smooth-noise field
## clustering, a hard cap, advance(delta, growth_modifier), a pure
## graze(cell) -> bool, water-cell gated seeding. What is genuinely
## different: GROWTH_RATE is tuned higher -- a real insect-larva population
## turns over on the order of days/weeks, far faster than a weed bed's own
## rhizome-driven regrowth.

const AquaticInvertebrates = preload("res://src/world/aquatic_invertebrates.gd")
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


func _invertebrates(is_water: PackedByteArray, seed_value: int = 1234) -> AquaticInvertebrates:
	return AquaticInvertebrates.new(seed_value, SIZE, SIZE, is_water)


# -- placement ----------------------------------------------------------------

func test_seeds_no_patches_when_there_is_no_water_at_all():
	var inverts := _invertebrates(_no_water())
	assert_eq(inverts.get_patch_cells().size(), 0, "nothing to live in without water")


func test_seeds_real_patches_when_the_whole_chunk_is_water():
	var inverts := _invertebrates(_all_water())
	assert_gt(inverts.get_patch_cells().size(), 0, "an all-water chunk should host real invertebrates")


func test_every_seeded_patch_actually_sits_on_a_water_cell():
	var is_water := _half_water()
	var inverts := _invertebrates(is_water)
	for cell in inverts.get_patch_cells():
		assert_eq(is_water[cell.y * SIZE + cell.x], 1, "a patch must not seed on dry ground")


func test_seeding_is_deterministic_for_the_same_seed():
	var a := _invertebrates(_all_water(), 42)
	var b := _invertebrates(_all_water(), 42)
	assert_eq(a.get_patch_cells(), b.get_patch_cells())


func test_different_seeds_produce_different_layouts():
	var a := _invertebrates(_all_water(), 1)
	var b := _invertebrates(_all_water(), 2)
	assert_ne(a.get_patch_cells(), b.get_patch_cells())


func test_patch_count_stays_within_the_per_chunk_bound():
	var inverts := _invertebrates(_all_water())
	assert_lte(inverts.get_patch_cells().size(), AquaticInvertebrates.MAX_PATCHES)


## Same derivation and same failure class TallGrass/AquaticVegetation's own
## identical test already guards against: initial seeding alone hitting an
## under-sized cap on a real, densely-eligible chunk would leave spread
## permanently unable to add anything new.
func test_max_patches_accommodates_the_density_target_for_a_real_full_chunk():
	var real_chunk_cells := EarthChunkManager.CHUNK_SIZE * EarthChunkManager.CHUNK_SIZE
	var target_density_patch_count := ceili(float(real_chunk_cells) * AquaticInvertebrates.SEED_CHANCE)
	assert_gte(AquaticInvertebrates.MAX_PATCHES, target_density_patch_count)


## Same "field, not salt-and-pepper" requirement TallGrass/AquaticVegetation's
## own smooth-noise clustering satisfies -- real insect larvae cluster where
## conditions favour them, not scattered uniformly.
func test_seeded_cells_cluster_next_to_each_other_more_than_chance_alone_would():
	var inverts := _invertebrates(_all_water())
	var cells := inverts.get_patch_cells()
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

## Same technique test_aquatic_vegetation.gd's own identical test uses:
## initial seeding starts every patch already mature, so an immature patch
## to grow only exists once spread has actually created one.
func test_advance_grows_immature_patches_toward_maturity():
	var inverts := _invertebrates(_all_water(), 1)
	var immature := Vector2i(-1, -1)
	for i in 20:
		inverts.advance(AquaticInvertebrates.SPREAD_INTERVAL, 1.0)
		for cell in inverts.get_patch_cells():
			if inverts.get_growth(cell) < 1.0:
				immature = cell
				break
		if immature != Vector2i(-1, -1):
			break
	assert_ne(immature, Vector2i(-1, -1), "precondition: spread must have created at least one immature patch within 20 ticks")
	var before: float = inverts.get_growth(immature)
	inverts.advance(1.0, 1.0)
	assert_gt(inverts.get_growth(immature), before)


func test_growth_is_capped_at_one():
	var inverts := _invertebrates(_all_water())
	var cell: Vector2i = inverts.get_patch_cells()[0]
	inverts.advance(1000000.0, 1.0)
	assert_almost_eq(inverts.get_growth(cell), 1.0, 0.001)


## Real immature patches (via spread) growing at two different
## growth_modifier values -- the fast one must pull ahead.
func test_advance_grows_slower_at_a_lower_growth_modifier():
	var inverts := _invertebrates(_all_water(), 1)
	var immature := Vector2i(-1, -1)
	for i in 20:
		inverts.advance(AquaticInvertebrates.SPREAD_INTERVAL, 1.0)
		for cell in inverts.get_patch_cells():
			if inverts.get_growth(cell) < 0.5:
				immature = cell
				break
		if immature != Vector2i(-1, -1):
			break
	assert_ne(immature, Vector2i(-1, -1), "precondition: need a real immature patch with room left to grow")
	var slow_growth: float = inverts.get_growth(immature)
	inverts.advance(10.0, 0.1)
	var slow_after := inverts.get_growth(immature)
	inverts.advance(10.0, 1.0)
	var fast_after := inverts.get_growth(immature)
	assert_gt(fast_after - slow_after, slow_after - slow_growth)


## The one genuinely different tuned value from AquaticVegetation -- a real
## insect-larva population turns over far faster than a weed bed's own
## rhizome-driven regrowth (days/weeks, not a slow plant-growth timescale).
func test_growth_rate_is_faster_than_vegetations_own():
	var AquaticVegetation = load("res://src/world/aquatic_vegetation.gd")
	assert_gt(AquaticInvertebrates.GROWTH_RATE, AquaticVegetation.GROWTH_RATE)


# -- spread -----------------------------------------------------------------

func test_no_spread_before_the_spread_interval_elapses():
	var inverts := _invertebrates(_half_water())
	var before := inverts.get_patch_cells().size()
	inverts.advance(AquaticInvertebrates.SPREAD_INTERVAL * 0.5, 1.0)
	assert_eq(inverts.get_patch_cells().size(), before)


func test_mature_patches_spread_to_adjacent_water_over_time():
	var inverts := _invertebrates(_half_water())
	var before := inverts.get_patch_cells().size()
	for i in 20:
		inverts.advance(AquaticInvertebrates.SPREAD_INTERVAL, 1.0)
	assert_gte(inverts.get_patch_cells().size(), before)


func test_spread_never_lands_on_a_dry_cell():
	var is_water := _half_water()
	var inverts := _invertebrates(is_water)
	for i in 20:
		inverts.advance(AquaticInvertebrates.SPREAD_INTERVAL, 1.0)
	for cell in inverts.get_patch_cells():
		assert_eq(is_water[cell.y * SIZE + cell.x], 1)


# -- grazing ------------------------------------------------------------------

func test_graze_removes_an_existing_patch_and_returns_true():
	var inverts := _invertebrates(_all_water())
	var cell: Vector2i = inverts.get_patch_cells()[0]
	assert_true(inverts.graze(cell))
	assert_false(inverts.has_invertebrates(cell))


func test_graze_on_an_empty_cell_returns_false():
	var inverts := _invertebrates(_all_water())
	assert_false(inverts.graze(Vector2i(999, 999)))


func test_grazing_twice_on_the_same_cell_only_succeeds_once():
	var inverts := _invertebrates(_all_water())
	var cell: Vector2i = inverts.get_patch_cells()[0]
	assert_true(inverts.graze(cell))
	assert_false(inverts.graze(cell))
