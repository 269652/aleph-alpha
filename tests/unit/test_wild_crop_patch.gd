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
		crop.advance(WildCropPatch.SPREAD_INTERVAL)
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
		crop.advance(WildCropPatch.SPREAD_INTERVAL)
		for cell in crop.get_patch_cells():
			if crop.get_growth(cell) < 1.0:
				immature = cell
		if immature != Vector2i(-1, -1):
			break
	assert_ne(immature, Vector2i(-1, -1), "precondition: a spread tick produced an immature patch")
	var before: float = crop.get_growth(immature)
	crop.advance(1.0)
	assert_gt(crop.get_growth(immature), before)


func test_growth_is_capped_at_one():
	var crop := WildCropPatch.new("carrot", 1, WIDTH, HEIGHT, _biome_all("grassland"))
	assert_gt(crop.get_patch_cells().size(), 0, "precondition: at least one initial patch")
	var cell: Vector2i = crop.get_patch_cells()[0]
	crop.advance(1000000.0)
	assert_eq(crop.get_growth(cell), 1.0)


func test_no_spread_before_the_spread_interval_elapses():
	var crop := WildCropPatch.new("carrot", 1, WIDTH, HEIGHT, _biome_all("grassland"))
	crop.advance(1000000.0)  # everything mature; some spread ticks happen too
	var count := crop.get_patch_cells().size()
	crop.advance(WildCropPatch.SPREAD_INTERVAL * 0.5)
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
		carrot.advance(WildCropPatch.SPREAD_INTERVAL)
		potato.advance(WildCropPatch.SPREAD_INTERVAL)
	var carrot_cells := {}
	for cell in carrot.get_patch_cells():
		carrot_cells[cell] = true
	for cell in potato.get_patch_cells():
		assert_false(carrot_cells.has(cell), "cell %s claimed by both crops after spreading" % cell)


# -- the season (senescence, not dieback -- see concept/wild_crops.md) -------

## An immature carrot must nearly stop through winter and pick back up in
## spring, but never fully freeze: SeasonCycle.growth_modifier's floor is
## 0.2, documented as "dormancy, not death", which is seasons.md's
## "modulates, doesn't gate" pillar stated as a number.
func test_growth_slows_in_winter_and_never_fully_stops():
	var summer := WildCropPatch.new("carrot", 1, WIDTH, HEIGHT, _biome_all("grassland"))
	var winter := WildCropPatch.new("carrot", 1, WIDTH, HEIGHT, _biome_all("grassland"))
	var cell := Vector2i(-1, -1)
	for candidate in summer.get_patch_cells():
		cell = candidate
		break
	assert_ne(cell, Vector2i(-1, -1), "precondition: at least one initial patch")
	# Initial patches seed mature, so knock one back down to observe growth.
	summer.graze(cell)
	winter.graze(cell)

	var cycle := SeasonCycle.new()
	var winter_growth := cycle.growth_modifier(0.875 * SeasonCycle.SECONDS_PER_YEAR)
	assert_gt(winter_growth, 0.0, "the premise: dormancy, not death")
	assert_lt(winter_growth, 0.5, "the premise: winter really is slow")

	var seconds := 200.0
	var in_summer := _gained_after(summer, seconds, 1.0)
	var in_winter := _gained_after(winter, seconds, winter_growth)
	assert_gt(in_winter, 0.0, "a dormant crop still creeps forward")
	assert_lt(in_winter, in_summer, "but far slower than in high summer")
	assert_almost_eq(in_winter / in_summer, winter_growth, 0.0001)


## The regression guard for the whole signature change: every caller that
## has not been taught about the season yet must see exactly the numbers it
## saw before (the "defaults to 1.0" convention this codebase already uses
## for VegetationGrowthModel's land_health).
func test_advance_defaults_to_the_pre_season_behaviour_for_untaught_callers():
	var taught := WildCropPatch.new("carrot", 4, WIDTH, HEIGHT, _biome_all("grassland"))
	var untaught := WildCropPatch.new("carrot", 4, WIDTH, HEIGHT, _biome_all("grassland"))
	var cell: Vector2i = taught.get_patch_cells()[0]
	taught.graze(cell)
	untaught.graze(cell)
	assert_almost_eq(_gained_after(untaught, 300.0, -1.0), _gained_after(taught, 300.0, 1.0), 0.0001)


## A patch colonising new ground through a frozen January is the same
## mistake as one ripening through it, so spread rides the season clock too.
##
## Stated as an exact equivalence rather than "winter spreads less": spread
## attempts are throttled AND territory-partitioned (a tick can legitimately
## land on an ineligible neighbour and do nothing), so counting colonisations
## over a fixed span is lumpy. Five times as long at the 0.2 winter floor is
## exactly one summer's worth of season-scaled time, and must therefore
## produce exactly the summer world -- which is only true if the spread
## accumulator advances on scaled time and not on raw seconds.
func test_spread_runs_on_the_same_season_clock_as_growth():
	var summer := WildCropPatch.new("carrot", 9, WIDTH, HEIGHT, _biome_all("grassland"))
	var winter := WildCropPatch.new("carrot", 9, WIDTH, HEIGHT, _biome_all("grassland"))
	var slow := WildCropPatch.new("carrot", 9, WIDTH, HEIGHT, _biome_all("grassland"))
	var started := summer.get_patch_cells().size()
	assert_gt(started, 0, "precondition: something mature to spread from")

	var seconds := WildCropPatch.SPREAD_INTERVAL * 60.0
	summer.advance(seconds)
	winter.advance(seconds * 5.0, 0.2)
	slow.advance(seconds, 0.2)

	assert_gt(summer.get_patch_cells().size(), started, "precondition: summer spreads")
	assert_eq(
		winter.get_patch_cells(), summer.get_patch_cells(),
		"five winters' seconds at the 0.2 floor is exactly one summer's growing time"
	)
	for cell in summer.get_patch_cells():
		assert_almost_eq(winter.get_growth(cell), summer.get_growth(cell), 0.0001)
	assert_lte(
		slow.get_patch_cells().size(), summer.get_patch_cells().size(),
		"and the same RAW seconds in winter can never colonise more than summer did"
	)


## The season scales TIME, so a season_growth of 0 must stall rather than run
## backwards or divide by anything.
func test_a_fully_stalled_season_neither_grows_nor_spreads():
	var crop := WildCropPatch.new("carrot", 11, WIDTH, HEIGHT, _biome_all("grassland"))
	# Reach a genuinely immature cell FIRST (that setup runs at full speed),
	# then freeze the season and assert nothing at all moves after that.
	var immature := _first_immature(crop)
	assert_ne(immature, Vector2i(-1, -1), "precondition: an immature spread cell exists")
	var growth_before: float = crop.get_growth(immature)
	var count_before := crop.get_patch_cells().size()

	crop.advance(100000.0, 0.0)
	assert_eq(crop.get_growth(immature), growth_before, "a frozen season grows nothing")
	assert_eq(crop.get_patch_cells().size(), count_before, "and colonises nothing")


## Advances `crop` and reports the growth a freshly spread (0.0) cell gained.
## `season_growth` below zero means "call the old one-argument form".
func _gained_after(crop, seconds: float, season_growth: float) -> float:
	# Force a known immature cell rather than hunting for one: spread is
	# throttled and territory-partitioned, so a deterministic seed is easier
	# to reason about than a search.
	var immature := _first_immature(crop)
	if immature == Vector2i(-1, -1):
		return -1.0
	var before: float = crop.get_growth(immature)
	if season_growth < 0.0:
		crop.advance(seconds)
	else:
		crop.advance(seconds, season_growth)
	return crop.get_growth(immature) - before


## Runs spread ticks until some cell is genuinely immature, at a season
## scaling of 1.0 so the setup itself is season-independent.
func _first_immature(crop) -> Vector2i:
	for i in 50:
		for cell in crop.get_patch_cells():
			if crop.get_growth(cell) < 1.0:
				return cell
		crop.advance(WildCropPatch.SPREAD_INTERVAL)
	return Vector2i(-1, -1)
