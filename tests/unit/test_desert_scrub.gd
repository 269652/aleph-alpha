extends GutTest

const DesertScrub = preload("res://src/world/desert_scrub.gd")
const TallGrass = preload("res://src/world/tall_grass.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")

const WIDTH := 8
const HEIGHT := 8


func _biome_all(name: String) -> PackedStringArray:
	var biome := PackedStringArray()
	biome.resize(WIDTH * HEIGHT)
	biome.fill(name)
	return biome


func _biome_half_desert() -> PackedStringArray:
	# Left half desert, right half grassland.
	var biome := PackedStringArray()
	biome.resize(WIDTH * HEIGHT)
	for y in HEIGHT:
		for x in WIDTH:
			biome[y * WIDTH + x] = "desert" if x < WIDTH / 2 else "grassland"
	return biome


func test_seeds_no_patches_when_there_is_no_desert():
	var scrub := DesertScrub.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	assert_eq(scrub.get_patch_cells().size(), 0)


func test_seeds_patches_only_on_desert_cells():
	var scrub := DesertScrub.new(1, WIDTH, HEIGHT, _biome_half_desert())
	assert_gt(scrub.get_patch_cells().size(), 0)
	for cell in scrub.get_patch_cells():
		assert_lt(cell.x, WIDTH / 2)


func test_seeding_is_deterministic_for_the_same_seed():
	var a := DesertScrub.new(7, WIDTH, HEIGHT, _biome_all("desert"))
	var b := DesertScrub.new(7, WIDTH, HEIGHT, _biome_all("desert"))
	assert_eq(a.get_patch_cells(), b.get_patch_cells())


func test_different_seeds_produce_different_patch_layouts():
	var a := DesertScrub.new(1, WIDTH, HEIGHT, _biome_all("desert"))
	var b := DesertScrub.new(2, WIDTH, HEIGHT, _biome_all("desert"))
	assert_ne(a.get_patch_cells(), b.get_patch_cells())


func test_patch_count_stays_within_the_per_chunk_bound():
	var scrub := DesertScrub.new(3, WIDTH, HEIGHT, _biome_all("desert"))
	for i in 200:
		scrub.advance(DesertScrub.SPREAD_INTERVAL, 1.0)
	assert_lte(scrub.get_patch_cells().size(), DesertScrub.MAX_PATCHES)


func test_advance_grows_immature_patches_toward_maturity():
	var scrub := DesertScrub.new(1, WIDTH, HEIGHT, _biome_all("desert"))
	scrub.advance(DesertScrub.SPREAD_INTERVAL, 1.0)  # spread creates an immature patch
	var immature := Vector2i(-1, -1)
	for cell in scrub.get_patch_cells():
		if scrub.get_growth(cell) < 1.0:
			immature = cell
	assert_ne(immature, Vector2i(-1, -1))
	var before: float = scrub.get_growth(immature)
	scrub.advance(1.0, 1.0)
	assert_gt(scrub.get_growth(immature), before)


func test_growth_is_capped_at_one():
	var scrub := DesertScrub.new(1, WIDTH, HEIGHT, _biome_all("desert"))
	var cell: Vector2i = scrub.get_patch_cells()[0]
	scrub.advance(100000.0, 1.0)
	assert_eq(scrub.get_growth(cell), 1.0)


func test_no_spread_before_the_spread_interval_elapses():
	var scrub := DesertScrub.new(1, WIDTH, HEIGHT, _biome_all("desert"))
	scrub.advance(100000.0, 1.0)  # everything mature; also one spread tick happens
	var count := scrub.get_patch_cells().size()
	scrub.advance(DesertScrub.SPREAD_INTERVAL * 0.5, 1.0)
	assert_eq(scrub.get_patch_cells().size(), count)


func test_mature_patches_spread_to_adjacent_desert_over_time():
	var scrub := DesertScrub.new(1, WIDTH, HEIGHT, _biome_all("desert"))
	var initial := scrub.get_patch_cells().size()
	for i in 100:
		scrub.advance(DesertScrub.SPREAD_INTERVAL, 1.0)
	assert_gt(scrub.get_patch_cells().size(), initial)


func test_spread_never_lands_on_non_desert_cells():
	var scrub := DesertScrub.new(1, WIDTH, HEIGHT, _biome_half_desert())
	for i in 200:
		scrub.advance(DesertScrub.SPREAD_INTERVAL, 1.0)
	for cell in scrub.get_patch_cells():
		assert_lt(cell.x, WIDTH / 2)


func test_new_spread_patches_start_immature():
	var scrub := DesertScrub.new(1, WIDTH, HEIGHT, _biome_all("desert"))
	scrub.advance(100000.0, 1.0)  # mature everything, trigger a spread tick
	var found_immature := false
	for cell in scrub.get_patch_cells():
		if scrub.get_growth(cell) < 1.0:
			found_immature = true
	assert_true(found_immature)


func test_graze_removes_an_existing_patch_and_returns_true():
	var scrub := DesertScrub.new(1, WIDTH, HEIGHT, _biome_all("desert"))
	var cell: Vector2i = scrub.get_patch_cells()[0]
	assert_true(scrub.graze(cell))
	assert_false(scrub.has_scrub(cell))


func test_graze_on_an_empty_cell_returns_false():
	var scrub := DesertScrub.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	assert_false(scrub.graze(Vector2i(0, 0)))


func test_grazing_twice_on_the_same_cell_only_succeeds_once():
	var scrub := DesertScrub.new(1, WIDTH, HEIGHT, _biome_all("desert"))
	var cell: Vector2i = scrub.get_patch_cells()[0]
	assert_true(scrub.graze(cell))
	assert_false(scrub.graze(cell))


## Tuned-value gradient: scrub must read as visibly sparser and slower-growing
## than tall grass (see desert_scrub.gd's doc comment) -- pinned here instead
## of trusting an eyeballed comment, per this repo's no-manual-tuning rule.
func test_seed_chance_is_sparser_than_tall_grass():
	assert_lt(DesertScrub.SEED_CHANCE, TallGrass.SEED_CHANCE)


func test_growth_rate_is_slower_than_tall_grass():
	assert_lt(DesertScrub.GROWTH_RATE, TallGrass.GROWTH_RATE)


## Lighter regression pin of the seasonal-growth contract test_tall_grass.gd
## proves thoroughly (see its test_advance_grows_slower_in_winter_than_in_
## summer_for_the_same_elapsed_time): growth_modifier must scale DesertScrub's
## own growth increment too, not just TallGrass's.
##
## One identical spread tick at full modifier for both first -- every
## pre-existing patch starts already mature (capped at 1.0), so which cell
## spreads into is unaffected by the modifier -- gives both instances an
## immature patch on the SAME cell to compare growth on next.
func test_advance_grows_slower_in_winter_than_in_summer_for_the_same_elapsed_time():
	var cycle := SeasonCycle.new()
	var summer_modifier: float = cycle.growth_modifier(SeasonCycle.SECONDS_PER_YEAR * 0.375)
	var winter_modifier: float = cycle.growth_modifier(SeasonCycle.SECONDS_PER_YEAR * 0.875)

	var summer := DesertScrub.new(1, WIDTH, HEIGHT, _biome_all("desert"))
	var winter := DesertScrub.new(1, WIDTH, HEIGHT, _biome_all("desert"))
	summer.advance(DesertScrub.SPREAD_INTERVAL, 1.0)
	winter.advance(DesertScrub.SPREAD_INTERVAL, 1.0)
	var immature := Vector2i(-1, -1)
	for cell in summer.get_patch_cells():
		if summer.get_growth(cell) < 1.0:
			immature = cell
			break
	assert_ne(immature, Vector2i(-1, -1), "precondition: the spread tick created an immature patch")
	assert_almost_eq(
		summer.get_growth(immature), winter.get_growth(immature), 0.0001,
		"precondition: both instances start from the same immature growth"
	)

	summer.advance(1.0, summer_modifier)
	winter.advance(1.0, winter_modifier)

	assert_gt(summer.get_growth(immature), winter.get_growth(immature))
