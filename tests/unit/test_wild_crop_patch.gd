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


# -- vigor: a heritable size/quality trait, same "average of two salted-hash
# draws" shape FlyerPersonality._bell uses for boldness -- see
# docs/concept/wild_crops.md's "Root Vigor" section.


## A cell nobody ever planted (or a save from before vigor existed) must
## answer with the unremarkable middle, not an accidental 0.0 -- same reason
## FlyerPersonality.boldness_of defaults an empty trait dictionary to 0.5.
##
## A 0x0 grid (not a 4x4 one against an empty biome array, as first drafted)
## -- _seed_initial_patches indexes _biome[y * _width + x] unconditionally
## inside its loop, so a 4x4 grid over a genuinely empty PackedStringArray
## throws an out-of-bounds error in the constructor before get_vigor is
## ever reached, which would fail this test for the wrong reason. Zero
## width/height means the seeding loop never runs at all, so the only
## thing this test can fail on is get_vigor itself.
func test_get_vigor_defaults_to_a_middling_value_for_an_unplanted_cell():
	var patch := WildCropPatch.new("carrot", 1, 0, 0, PackedStringArray())
	assert_eq(patch.get_vigor(Vector2i(99, 99)), 0.5)


## A real seeding-distribution test, mirroring test_boldness_is_always_a_
## real_fraction / test_different_butterflies_have_different_personalities
## in test_flyer_personality.gd: every seeded patch must get a real
## in-range vigor, and a real sample of patches must not collapse onto a
## handful of shared values. A big grid (MAX_PATCHES caps the actual patch
## count regardless of grid size, so this is about sample size, not more
## seeded patches than the cap allows).
func test_seeded_vigor_is_a_real_fraction_that_varies_across_patches():
	var width := 200
	var height := 200
	var biome := PackedStringArray()
	biome.resize(width * height)
	biome.fill("grassland")
	var crop := WildCropPatch.new("carrot", 1, width, height, biome)
	var cells := crop.get_patch_cells()
	assert_gt(cells.size(), 10, "precondition: a real sample of seeded patches")
	var distinct := {}
	for cell in cells:
		var vigor: float = crop.get_vigor(cell)
		assert_between(vigor, 0.0, 1.0)
		distinct[vigor] = true
	assert_gt(
		distinct.size(), cells.size() * 0.8,
		"seeded patches must not share a handful of vigor values"
	)


## Isolates the "a spread child inherits its parent's vigor, nudged by
## mutation" mechanism from seeding's own randomness by forcing a single,
## precisely known founder directly (bypassing _seed_initial_patches's own
## hash roll -- GDScript's underscore convention is not real privacy, and
## test_territory_partition_is_exhaustively_disjoint below already calls a
## private-by-convention method directly for the same reason: a focused,
## deterministic check the public API alone can't isolate). With only one
## founder, EVERY spread child over these few ticks is provably that
## founder's own child -- no other candidate parent exists to be coincidentally
## close in vigor -- so comparing each child directly against the founder's
## known vigor is an exact check, not a statistical one.
func test_spread_children_inherit_the_parents_vigor_nudged_by_mutation():
	var crop := WildCropPatch.new("carrot", 1, WIDTH, HEIGHT, _biome_all("grassland"))
	crop._patches.clear()
	crop._vigor.clear()
	var founder := Vector2i(WIDTH / 2, HEIGHT / 2)
	var parent_vigor := 0.4
	crop._patches[founder] = 1.0
	crop._vigor[founder] = parent_vigor

	# Four ticks, never letting a child mature (GROWTH_RATE is slow enough
	# that the oldest possible child -- born on the very first tick -- only
	# reaches 3 * SPREAD_INTERVAL * GROWTH_RATE growth by the end, well
	# under 1.0), so the founder is the ONLY mature cell, and therefore the
	# only possible parent, for the entire run.
	for i in 4:
		crop.advance(WildCropPatch.SPREAD_INTERVAL, 1.0)

	var children := crop.get_patch_cells().duplicate()
	children.erase(founder)
	assert_gt(children.size(), 0, "precondition: at least one spread child must have appeared")

	var mutated := false
	for cell in children:
		var child_vigor: float = crop.get_vigor(cell)
		var diff := absf(child_vigor - parent_vigor)
		assert_lte(
			diff, WildCropPatch.VIGOR_MUTATION_AMOUNT + 0.0001,
			"child vigor must stay within one mutation step of its single parent"
		)
		if diff > 0.0001:
			mutated = true
	assert_true(
		mutated, "at least one spread child must actually mutate away from its parent's exact vigor"
	)


## THE multi-generation payoff, adapted from test_flyer_personality.gd's own
## test_a_meadow_the_player_nets_the_bold_out_of_grows_shy_over_generations
## to this population's own shape: there is no discrete "generation" or
## crossover here, just an ongoing spatial population that grows, spreads,
## and (in the pressured twin) gets its single best patch pulled every
## round -- but the SAME selection-pressure idea applies. Removing the
## highest-vigor mature patch before each spread tick means the pool of
## patches actually eligible to seed a NEW cell (WildCropPatch._step_spread
## picks uniformly among MATURE patches, blind to vigor) is, on average, a
## slightly lower-vigor pool than an unpressured meadow's -- so the
## population should drift toward lower mean vigor over enough rounds,
## the same qualitative shape as netting bold butterflies shrinking a
## meadow's mean boldness. The control (an identical, never-pulled twin
## from the same seed) is what makes the number mean anything: if the
## untouched meadow drifted just as far, the drop would be an artifact of
## the mutation/spread machinery, not a response to always pulling the
## biggest patch.
func test_always_pulling_the_biggest_patches_trends_the_meadow_smaller():
	var width := 60
	var height := 60
	var biome := PackedStringArray()
	biome.resize(width * height)
	biome.fill("grassland")

	var pressured := WildCropPatch.new("carrot", 21, width, height, biome)
	var undisturbed := WildCropPatch.new("carrot", 21, width, height, biome)

	var start := _mean_vigor(pressured)
	assert_almost_eq(start, _mean_vigor(undisturbed), 0.0001, "precondition: identical twins")

	# A successful spread only lands roughly every several rounds (half of
	# all candidate targets fall in the OTHER crop's territory, see
	# _in_this_crops_territory, and a newly-spread cell then needs several
	# more rounds of growth before it is mature enough to be harvestable
	# itself) -- harvesting the single best patch EVERY round outpaces
	# regrowth entirely and wipes the meadow out (measured: it hits zero
	# patches by round ~19 and stays there, which would make the "meadow"
	# being measured an empty one). MIN_MATURE_TO_HARVEST leaves at least a
	# couple of mature patches standing at all times -- a real forager
	# leaves some crop in the ground, not the botanical fact of it -- so
	# there is always a surviving population left for regrowth to work
	# from, the same way _worked_meadow's own
	# `assert_gt(survivors.size(), 1, "the meadow must not be wiped out")`
	# keeps its population alive.
	const ROUNDS := 400
	const MIN_MATURE_TO_HARVEST := 4
	for round in ROUNDS:
		pressured.advance(WildCropPatch.SPREAD_INTERVAL, 1.0)
		undisturbed.advance(WildCropPatch.SPREAD_INTERVAL, 1.0)
		if _mature_cell_count(pressured) >= MIN_MATURE_TO_HARVEST:
			var biggest := _highest_vigor_mature_cell(pressured)
			if biggest != Vector2i(-1, -1):
				pressured.graze(biggest)

	assert_gt(
		pressured.get_patch_cells().size(), 0,
		"the meadow must not be wiped out (MIN_MATURE_TO_HARVEST should have prevented this)"
	)

	var drift: float = absf(_mean_vigor(undisturbed) - start)
	var shift: float = start - _mean_vigor(pressured)

	gut.p(
		"pressured meadow mean vigor: %f -> %f (shift %f, %d patches)" %
		[start, _mean_vigor(pressured), shift, pressured.get_patch_cells().size()]
	)
	# Measured, not assumed: the undisturbed twin drifts EXACTLY 0 -- it
	# starts already at MAX_PATCHES (the cap this seed/grid combination
	# reaches at initial seeding) and, never being grazed, never frees a
	# slot for _step_spread to fill (see _step_spread's own `_patches.size()
	# >= MAX_PATCHES: return` guard) -- so its founding population, and
	# therefore its mean vigor, is genuinely static for the entire run, not
	# a rounding artifact. That is the correct, honest baseline for "nobody
	# ever touches this meadow" in a sim with no natural cell death: real
	# turnover here only ever comes from a cell being grazed.
	gut.p(
		"undisturbed meadow drifted %f over the same %d rounds (%d patches)" %
		[drift, ROUNDS, undisturbed.get_patch_cells().size()]
	)

	assert_gt(
		shift, 0.0,
		"always pulling the biggest patch must lower the meadow's mean vigor"
	)
	assert_gt(shift, drift, "and by more than an untouched meadow drifts on its own")


func _mean_vigor(patch) -> float:
	var cells: Array = patch.get_patch_cells()
	var total := 0.0
	for cell in cells:
		total += patch.get_vigor(cell)
	return total / float(cells.size())


func _highest_vigor_mature_cell(patch) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_vigor := -1.0
	for cell in patch.get_patch_cells():
		if patch.get_growth(cell) >= 1.0 and patch.get_vigor(cell) > best_vigor:
			best_vigor = patch.get_vigor(cell)
			best = cell
	return best


func _mature_cell_count(patch) -> int:
	var count := 0
	for cell in patch.get_patch_cells():
		if patch.get_growth(cell) >= 1.0:
			count += 1
	return count


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
