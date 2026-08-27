extends GutTest

## See docs/concept/wild_crops.md. WildCropPatch is deliberately a near-
## clone of TallGrass's own contract (seed/grow/spread on grassland), just
## rarer and slower -- these tests mirror test_tall_grass.gd's shape.

const WildCropPatch = preload("res://src/world/wild_crop_patch.gd")
const TallGrass = preload("res://src/world/tall_grass.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")

const WIDTH := 16
const HEIGHT := 16


func _biome_all(name: String) -> PackedStringArray:
	var biome := PackedStringArray()
	biome.resize(WIDTH * HEIGHT)
	biome.fill(name)
	return biome


func _biome_half_grassland() -> PackedStringArray:
	var biome := PackedStringArray()
	biome.resize(WIDTH * HEIGHT)
	for y in HEIGHT:
		for x in WIDTH:
			biome[y * WIDTH + x] = "grassland" if x < WIDTH / 2 else "desert"
	return biome


func test_seeds_no_patches_when_there_is_no_grassland():
	var crop := WildCropPatch.new("carrot", 1, WIDTH, HEIGHT, _biome_all("desert"))
	assert_eq(crop.get_patch_cells().size(), 0)


func test_seeds_patches_only_on_grassland_cells():
	# A big enough sample that "some grassland cell got seeded" isn't luck --
	# SEED_CHANCE is deliberately low (see below), so a small grid could
	# easily land at zero patches by chance alone.
	var crop := WildCropPatch.new("carrot", 1, WIDTH, HEIGHT, _biome_half_grassland())
	for cell in crop.get_patch_cells():
		assert_lt(cell.x, WIDTH / 2)


## A wild crop population reads as scattered finds, not a field -- far
## rarer per-cell than tall grass, and capped lower per chunk.
func test_seed_chance_and_cap_are_far_rarer_than_grass():
	assert_lt(WildCropPatch.SEED_CHANCE, TallGrass.SEED_CHANCE)
	assert_lt(WildCropPatch.MAX_PATCHES, TallGrass.MAX_PATCHES)


## A root crop's real growing season is meaningfully longer than a grazed
## grass tuft's regrowth -- pinned as an explicit tested ratio, not an
## independent eyeballed number (CLAUDE.md).
func test_growth_rate_is_a_pinned_multiple_slower_than_grass():
	assert_almost_eq(WildCropPatch.GROWTH_RATE, TallGrass.GROWTH_RATE / WildCropPatch.GROWTH_RATE_SLOWDOWN, 0.0001)
	assert_gt(WildCropPatch.GROWTH_RATE_SLOWDOWN, 1.0)


func test_seeding_is_deterministic_for_the_same_seed():
	var a := WildCropPatch.new("carrot", 7, WIDTH, HEIGHT, _biome_all("grassland"))
	var b := WildCropPatch.new("carrot", 7, WIDTH, HEIGHT, _biome_all("grassland"))
	assert_eq(a.get_patch_cells(), b.get_patch_cells())


func test_different_seeds_produce_different_patch_layouts():
	var a := WildCropPatch.new("carrot", 1, WIDTH, HEIGHT, _biome_all("grassland"))
	var b := WildCropPatch.new("carrot", 2, WIDTH, HEIGHT, _biome_all("grassland"))
	assert_ne(a.get_patch_cells(), b.get_patch_cells())


## Two crops sharing a chunk (and therefore the same base seed) must not
## seed identically, or a chunk's carrot and potato patches would sit on
## the exact same cells.
func test_different_crop_ids_produce_different_patch_layouts_for_the_same_seed():
	var carrot := WildCropPatch.new("carrot", 5, WIDTH, HEIGHT, _biome_all("grassland"))
	var potato := WildCropPatch.new("potato", 5, WIDTH, HEIGHT, _biome_all("grassland"))
	assert_ne(carrot.get_patch_cells(), potato.get_patch_cells())


func test_patch_count_stays_within_the_per_chunk_bound():
	var crop := WildCropPatch.new("carrot", 3, WIDTH, HEIGHT, _biome_all("grassland"))
	for i in 400:
		crop.advance(WildCropPatch.SPREAD_INTERVAL, 1.0)
	assert_lte(crop.get_patch_cells().size(), WildCropPatch.MAX_PATCHES)


func test_advance_grows_immature_patches_toward_maturity():
	var crop := WildCropPatch.new("carrot", 1, WIDTH, HEIGHT, _biome_all("grassland"))
	# Territory partitioning (see _in_this_crops_territory) roughly halves
	# which cells a given crop can even spread into, so a single tick's one
	# attempt (SPREAD_PER_TICK == 1) can land on an ineligible/occupied
	# neighbor and do nothing that round -- retry rather than assume one
	# tick suffices.
	var immature := Vector2i(-1, -1)
	for i in 50:
		crop.advance(WildCropPatch.SPREAD_INTERVAL, 1.0)
		for cell in crop.get_patch_cells():
			if crop.get_growth(cell) < 1.0:
				immature = cell
		if immature != Vector2i(-1, -1):
			break
	assert_ne(immature, Vector2i(-1, -1), "precondition: a spread tick produced an immature patch")
	var before: float = crop.get_growth(immature)
	crop.advance(1.0, 1.0)
	assert_gt(crop.get_growth(immature), before)


func test_growth_is_capped_at_one():
	var crop := WildCropPatch.new("carrot", 1, WIDTH, HEIGHT, _biome_all("grassland"))
	assert_gt(crop.get_patch_cells().size(), 0, "precondition: at least one initial patch")
	var cell: Vector2i = crop.get_patch_cells()[0]
	crop.advance(1000000.0, 1.0)
	assert_eq(crop.get_growth(cell), 1.0)


func test_no_spread_before_the_spread_interval_elapses():
	var crop := WildCropPatch.new("carrot", 1, WIDTH, HEIGHT, _biome_all("grassland"))
	crop.advance(1000000.0, 1.0)  # everything mature; some spread ticks happen too
	var count := crop.get_patch_cells().size()
	crop.advance(WildCropPatch.SPREAD_INTERVAL * 0.5, 1.0)
	assert_eq(crop.get_patch_cells().size(), count)


func test_graze_removes_the_patch_and_reports_success():
	var crop := WildCropPatch.new("carrot", 1, WIDTH, HEIGHT, _biome_all("grassland"))
	var cell: Vector2i = crop.get_patch_cells()[0]
	assert_true(crop.graze(cell))
	assert_false(crop.has_crop(cell))


func test_graze_on_an_empty_cell_reports_failure():
	var crop := WildCropPatch.new("carrot", 1, WIDTH, HEIGHT, _biome_all("desert"))
	assert_false(crop.graze(Vector2i(0, 0)))


# -- disjoint territory: two crops sharing a chunk must never claim the same
# cell -- reported live: "carrots render potatoes as crop" -- two markers
# stacked on the exact same tile (one carrot, one potato, each independently
# seeded with no knowledge of the other) read as one confused/wrong plant.

## Direct, exhaustive proof of the partition itself, not dependent on any
## particular seed/grid getting statistically lucky (a small grid at
## SEED_CHANCE's low rate can easily show zero collisions by chance alone
## even with the bug present, and zero collisions by construction once
## fixed -- this checks the actual eligibility rule over a wide sample).
func test_territory_partition_is_exhaustively_disjoint():
	for x in 200:
		for y in 200:
			var carrot_owns: bool = WildCropPatch._in_this_crops_territory("carrot", x, y)
			var potato_owns: bool = WildCropPatch._in_this_crops_territory("potato", x, y)
			assert_false(carrot_owns and potato_owns, "cell (%d, %d) claimed by both" % [x, y])


func test_territory_partition_actually_gives_each_crop_some_cells():
	var carrot_count := 0
	var potato_count := 0
	for x in 50:
		for y in 50:
			if WildCropPatch._in_this_crops_territory("carrot", x, y):
				carrot_count += 1
			if WildCropPatch._in_this_crops_territory("potato", x, y):
				potato_count += 1
	assert_gt(carrot_count, 0)
	assert_gt(potato_count, 0)


func test_two_crops_never_seed_onto_the_same_cell():
	var carrot := WildCropPatch.new("carrot", 9, WIDTH, HEIGHT, _biome_all("grassland"))
	var potato := WildCropPatch.new("potato", 9, WIDTH, HEIGHT, _biome_all("grassland"))
	var carrot_cells := {}
	for cell in carrot.get_patch_cells():
		carrot_cells[cell] = true
	for cell in potato.get_patch_cells():
		assert_false(carrot_cells.has(cell), "cell %s claimed by both crops" % cell)


## Spread must respect the same partition -- a patch must never spread INTO
## a cell the other crop already occupies, at any point over time, not just
## at initial seeding.
func test_spread_never_crosses_into_the_other_crops_territory():
	var carrot := WildCropPatch.new("carrot", 4, WIDTH, HEIGHT, _biome_all("grassland"))
	var potato := WildCropPatch.new("potato", 4, WIDTH, HEIGHT, _biome_all("grassland"))
	for i in 100:
		carrot.advance(WildCropPatch.SPREAD_INTERVAL, 1.0)
		potato.advance(WildCropPatch.SPREAD_INTERVAL, 1.0)
	var carrot_cells := {}
	for cell in carrot.get_patch_cells():
		carrot_cells[cell] = true
	for cell in potato.get_patch_cells():
		assert_false(carrot_cells.has(cell), "cell %s claimed by both crops after spreading" % cell)


## Lighter regression pin of the seasonal-growth contract test_tall_grass.gd
## proves thoroughly (see its test_advance_grows_slower_in_winter_than_in_
## summer_for_the_same_elapsed_time): growth_modifier must scale
## WildCropPatch's own growth increment too, not just TallGrass's -- keeping
## its deliberately-pinned ratio to TallGrass.GROWTH_RATE intact rather than
## bypassing the seasonal gate.
##
## Retries spread ticks in lockstep on both instances (same seed/crop_id ->
## an identical, deterministic outcome each tick, so they never diverge)
## until one produces an immature patch -- territory partitioning (see
## _in_this_crops_territory) can make a single tick land on an
## ineligible/occupied neighbor and do nothing, same reason
## test_advance_grows_immature_patches_toward_maturity above retries. Every
## pre-existing patch starts already mature (capped at 1.0), so which cell
## spreads into is unaffected by the modifier either way.
func test_advance_grows_slower_in_winter_than_in_summer_for_the_same_elapsed_time():
	var cycle := SeasonCycle.new()
	var summer_modifier: float = cycle.growth_modifier(SeasonCycle.SECONDS_PER_YEAR * 0.375)
	var winter_modifier: float = cycle.growth_modifier(SeasonCycle.SECONDS_PER_YEAR * 0.875)

	var summer := WildCropPatch.new("carrot", 1, WIDTH, HEIGHT, _biome_all("grassland"))
	var winter := WildCropPatch.new("carrot", 1, WIDTH, HEIGHT, _biome_all("grassland"))
	var immature := Vector2i(-1, -1)
	for i in 50:
		summer.advance(WildCropPatch.SPREAD_INTERVAL, 1.0)
		winter.advance(WildCropPatch.SPREAD_INTERVAL, 1.0)
		for cell in summer.get_patch_cells():
			if summer.get_growth(cell) < 1.0:
				immature = cell
				break
		if immature != Vector2i(-1, -1):
			break
	assert_ne(immature, Vector2i(-1, -1), "precondition: a spread tick produced an immature patch")
	assert_almost_eq(
		summer.get_growth(immature), winter.get_growth(immature), 0.0001,
		"precondition: both instances start from the same immature growth"
	)

	summer.advance(1.0, summer_modifier)
	winter.advance(1.0, winter_modifier)

	assert_gt(summer.get_growth(immature), winter.get_growth(immature))
