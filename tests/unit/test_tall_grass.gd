extends GutTest

const TallGrass = preload("res://src/world/tall_grass.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")

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
## SEED_CHANCE itself is no longer read as a literal per-cell roll (see its
## own doc comment in tall_grass.gd), but it stays the reference commonality
## other systems compare their own rarity against (DesertScrub,
## EarthwormPatch, WildCropPatch, TundraLichen all pin themselves rarer than
## this in their own tests), so it stays put at the same value.
func test_grassland_starts_with_a_visible_field_density():
	assert_gte(TallGrass.SEED_CHANCE, 0.20)
	assert_gte(TallGrass.MAX_PATCHES, 128)


## Pinned to the exact values measured empirically (see the constants' own
## doc comments in tall_grass.gd) rather than left an eyeballed guess -- a
## future "just nudge it a bit" edit becomes a deliberate, tested change
## instead of silent drift (CLAUDE.md).
func test_field_noise_scale_and_threshold_are_pinned_to_their_measured_values():
	assert_eq(TallGrass.FIELD_NOISE_SCALE, 0.12)
	assert_eq(TallGrass.FIELD_NOISE_THRESHOLD, 0.65)


## MAX_PATCHES must actually accommodate FIELD_NOISE_THRESHOLD's own
## documented target density (~SEED_CHANCE fraction) of a REAL, full
## CHUNK_SIZE-square chunk (see EarthChunkManager.CHUNK_SIZE) -- not just some
## number that happens to be bigger than an earlier, arbitrary one.
## tall_grass.gd cannot import EarthChunkManager itself to check this
## (EarthChunkManager already imports TallGrass -- a circular import), so this
## test recomputes the same derivation independently here, from THIS file
## (which can import EarthChunkManager freely), so a future change to
## CHUNK_SIZE or SEED_CHANCE re-verifies the relationship automatically
## instead of silently drifting back out of sync -- see
## test_plant_succeeds_on_an_empty_cell_in_a_full_chunk_sized_dense_field
## above for exactly what happens when it does.
func test_max_patches_accommodates_the_density_target_for_a_real_full_chunk():
	var real_chunk_cells := EarthChunkManager.CHUNK_SIZE * EarthChunkManager.CHUNK_SIZE
	var target_density_patch_count := ceili(float(real_chunk_cells) * TallGrass.SEED_CHANCE)
	assert_gte(TallGrass.MAX_PATCHES, target_density_patch_count)


## Reported live: "remove the percentage of overall grass blades instead
## make them stick more together forming fields using perlin noise /
## voronoi" -- the whole point of noise-thresholded seeding over the old
## independent per-cell chance. An independent roll makes a seeded cell's
## own neighbour no likelier to also be seeded than the overall density
## alone would predict; smooth noise makes adjacent samples correlated, so
## seeded cells should cluster well above that baseline. Averaged over many
## seeds/cells so one unlucky blob placement can't make this flaky (measured
## empirically: neighbour density landed at over 3x the overall density, so
## 1.5x is a comfortable, non-flaky margin, not a coin flip).
func test_seeded_cells_cluster_next_to_each_other_more_than_chance_alone_would():
	var total_cells := 0
	var total_patches := 0
	var total_neighbor_checks := 0
	var seeded_neighbor_checks := 0
	for seed_value in range(20):
		var grass := TallGrass.new(seed_value, WIDTH, HEIGHT, _biome_all("grassland"))
		var cells: Dictionary = {}
		for cell in grass.get_patch_cells():
			cells[cell] = true
		total_cells += WIDTH * HEIGHT
		total_patches += cells.size()
		for cell: Vector2i in cells:
			var right: Vector2i = cell + Vector2i(1, 0)
			if right.x < WIDTH:
				total_neighbor_checks += 1
				if cells.has(right):
					seeded_neighbor_checks += 1
	assert_gt(total_neighbor_checks, 0, "precondition: at least some seeded cells have an in-bounds right neighbour to check")
	var overall_density: float = float(total_patches) / float(total_cells)
	var neighbor_density: float = float(seeded_neighbor_checks) / float(total_neighbor_checks)
	assert_gt(neighbor_density, overall_density * 1.5, "a seeded cell's own neighbour must be seeded notably more often than chance alone -- otherwise this still scatters instead of clustering into fields")


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
		grass.advance(TallGrass.SPREAD_INTERVAL, 1.0)
	assert_lte(grass.get_patch_cells().size(), TallGrass.MAX_PATCHES)


func test_advance_grows_immature_patches_toward_maturity():
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	# Several ticks, not just one: noise-clustered seeding (see the
	# FIELD_NOISE_* tests) packs a mature cell's own neighbours with OTHER
	# mature cells far more often than the old scattered mechanism did, so a
	# randomly chosen spread parent can land with no free neighbour on any
	# single tick, purely by chance of interior-vs-edge placement. Checked
	# after EVERY tick (not just once at the end) so a patch that spreads
	# early doesn't have time to mature past 1.0 before this notices it.
	var immature := Vector2i(-1, -1)
	for i in 20:
		grass.advance(TallGrass.SPREAD_INTERVAL, 1.0)
		for cell in grass.get_patch_cells():
			if grass.get_growth(cell) < 1.0:
				immature = cell
				break
		if immature != Vector2i(-1, -1):
			break
	assert_ne(immature, Vector2i(-1, -1), "precondition: spread must have created at least one immature patch within 20 ticks")
	var before: float = grass.get_growth(immature)
	grass.advance(1.0, 1.0)
	assert_gt(grass.get_growth(immature), before)


func test_growth_is_capped_at_one():
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	var cell: Vector2i = grass.get_patch_cells()[0]
	grass.advance(10000.0, 1.0)
	assert_eq(grass.get_growth(cell), 1.0)


func test_no_spread_before_the_spread_interval_elapses():
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	grass.advance(10000.0, 1.0)  # everything mature; also one spread tick happens
	var count := grass.get_patch_cells().size()
	grass.advance(TallGrass.SPREAD_INTERVAL * 0.5, 1.0)
	assert_eq(grass.get_patch_cells().size(), count)


func test_mature_patches_spread_to_adjacent_grassland_over_time():
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	var initial := grass.get_patch_cells().size()
	for i in 50:
		grass.advance(TallGrass.SPREAD_INTERVAL, 1.0)
	assert_gt(grass.get_patch_cells().size(), initial)


func test_spread_never_lands_on_non_grassland_cells():
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_half_grassland())
	for i in 200:
		grass.advance(TallGrass.SPREAD_INTERVAL, 1.0)
	for cell in grass.get_patch_cells():
		assert_lt(cell.x, WIDTH / 2)


func test_new_spread_patches_start_immature():
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	grass.advance(10000.0, 1.0)  # mature everything, trigger a spread tick
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
		stepped.advance(1.0 / 60.0, 1.0)
	batched.advance(300.0 / 60.0, 1.0)
	assert_eq(stepped.get_patch_cells().size(), batched.get_patch_cells().size())
	for cell in batched.get_patch_cells():
		assert_almost_eq(stepped.get_growth(cell), batched.get_growth(cell), 0.0001)


func test_spread_still_happens_across_a_batched_advance():
	var batched := TallGrass.new(99, 12, 12, _grassland(12, 12))
	var before := batched.get_patch_cells().size()
	batched.advance(TallGrass.SPREAD_INTERVAL * 3.0, 1.0)
	assert_gt(batched.get_patch_cells().size(), before, "a batched step still spreads")


func _grassland(width: int, height: int) -> PackedStringArray:
	var biome := PackedStringArray()
	biome.resize(width * height)
	biome.fill("grassland")
	return biome


# -- seed: a mature patch sheds its own ground entity, mirroring FlowerPatch -
#
# _step_spread (above) is CONTIGUOUS: it only ever grows into the four cells
# touching a mature patch. Seed is the OTHER reproduction path -- a mature
# patch drops seed nearby on its own, independent of any animal, and that
# seed then sits on the ground until something (a bird, a mouse, or the
# player) takes it -- see docs/concept/long_grass.md's "Reproduction" section.

func test_a_fresh_field_has_not_shed_any_seed_yet():
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	assert_eq(grass.ground_seed_cells().size(), 0, "seed has to fall before it is there")


## Map-seeded patches start mature, so a standing field sheds without any
## animal or pollination step required -- unlike FlowerPatch, grass has no
## bloom cycle to gate shedding on.
func test_mature_patches_shed_seed_onto_the_ground_over_time():
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	for i in 400:
		grass.shed_seed(1.0)
	assert_gt(grass.ground_seed_cells().size(), 0, "a standing field should drop seed around itself")


## Seed lands NEAR the patch it fell from, not anywhere in the chunk -- the
## same "seed accumulates around the parent" rule FlowerPatch uses.
func test_shed_seed_lands_next_to_a_patch():
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	for i in 400:
		grass.shed_seed(1.0)
	var patches := grass.get_patch_cells()
	for cell in grass.ground_seed_cells():
		var nearest := 9999
		for patch_cell in patches:
			nearest = mini(nearest, maxi(absi(cell.x - patch_cell.x), absi(cell.y - patch_cell.y)))
		assert_lte(nearest, TallGrass.SEED_FALL_RADIUS, "seed should lie around the patch that dropped it")


func test_taking_a_ground_seed_removes_it():
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	for i in 400:
		grass.shed_seed(1.0)
	assert_gt(grass.ground_seed_cells().size(), 0, "precondition: something shed")
	var cell = grass.ground_seed_cells()[0]

	assert_true(grass.take_ground_seed(cell), "taking returns whether a seed was actually there")
	assert_false(grass.ground_seed_cells().has(cell))
	assert_false(grass.take_ground_seed(cell), "nothing left to take twice")


## Bounded, like every other per-chunk population here -- an unattended field
## must not carpet itself in seed over a long session.
func test_ground_seed_is_capped():
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	for i in 20000:
		grass.shed_seed(1.0)
	assert_lte(grass.ground_seed_cells().size(), TallGrass.MAX_GROUND_SEEDS)


# -- plant: the sink an animal's carried seed lands in ----------------------
#
# The counterpart of FlowerPatch.plant: establishes a brand-new, immature
# patch at a distant position, which is what lets a bird or mouse found a
# genuinely NEW field _step_spread's contiguous growth could never reach.

func test_planting_establishes_a_new_immature_patch():
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	# Scans the whole grid for an empty cell rather than guessing two fixed,
	# nearby candidates: noise-clustered seeding (see the FIELD_NOISE_* tests)
	# makes NEARBY cells' occupancy highly correlated (if one is grass, an
	# adjacent one very likely is too), so two adjacent-ish guesses are no
	# longer good odds of finding an empty one the way independent per-cell
	# rolls made them under the old mechanism.
	var cell := Vector2i(-1, -1)
	for y in HEIGHT:
		for x in WIDTH:
			if not grass.has_grass(Vector2i(x, y)):
				cell = Vector2i(x, y)
				break
		if cell != Vector2i(-1, -1):
			break
	assert_ne(cell, Vector2i(-1, -1), "precondition: an empty cell to plant into")

	assert_true(grass.plant(cell))

	assert_true(grass.has_grass(cell))
	assert_lt(grass.get_growth(cell), 1.0, "a planted seed is not already mature")


func test_planting_fails_outside_grassland():
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("desert"))
	assert_false(grass.plant(Vector2i(0, 0)))


func test_planting_fails_on_a_cell_that_already_has_grass():
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	var cell: Vector2i = grass.get_patch_cells()[0]
	assert_false(grass.plant(cell))


## Regression reproduction for a real, deterministically-observed bug: a full
## CHUNK_SIZE-square (see EarthChunkManager.CHUNK_SIZE), entirely-grassland
## chunk seeds so densely under FIELD_NOISE_THRESHOLD's own documented ~20%
## target coverage that INITIAL SEEDING ALONE already reaches the old
## MAX_PATCHES=128 before any spread or planting happens (32*32 cells *
## SEED_CHANCE 0.20 ~= 205 > 128) -- leaving plant() permanently unable to
## succeed on ANY empty cell in a chunk this dense, no matter which one a
## caller finds. This is exactly what made
## test_earth_chunk_manager.gd's test_plant_grass_at_establishes_a_new_patch
## fail against Berlin's own real (densely-grassland) chunk. MAX_PATCHES must
## actually accommodate the density target for a full real chunk, not an
## arbitrary smaller number.
func test_plant_succeeds_on_an_empty_cell_in_a_full_chunk_sized_dense_field():
	var size := EarthChunkManager.CHUNK_SIZE
	var grass := TallGrass.new(1, size, size, _grassland(size, size))
	var cell := Vector2i(-1, -1)
	for y in size:
		for x in size:
			if not grass.has_grass(Vector2i(x, y)):
				cell = Vector2i(x, y)
				break
		if cell != Vector2i(-1, -1):
			break
	assert_ne(cell, Vector2i(-1, -1), "precondition: an empty cell exists even in a dense field")
	assert_true(
		grass.plant(cell),
		"planting into a genuinely empty grassland cell must succeed regardless of how dense initial seeding already made this chunk"
	)


## A grid sized so the cap is actually reachable via plant() calls alone --
## MAX_PATCHES is well over WIDTH*HEIGHT (8*8=64), so the old 8x8 grid could
## never actually hit the cap-enforcement branch (`_patches.size() >=
## MAX_PATCHES`) inside this loop, meaning that branch never really executed.
## A CHUNK_SIZE-square grid (matching the real chunk size the cap is derived
## from) is guaranteed to exceed MAX_PATCHES-many grassland cells, so the
## guard genuinely fires here.
func test_planting_respects_the_per_chunk_cap():
	var size := EarthChunkManager.CHUNK_SIZE
	var grass := TallGrass.new(1, size, size, _grassland(size, size))
	var planted_any_beyond_cap := false
	for y in size:
		for x in size:
			if grass.get_patch_cells().size() >= TallGrass.MAX_PATCHES:
				if grass.plant(Vector2i(x, y)):
					planted_any_beyond_cap = true
	assert_false(planted_any_beyond_cap)
	assert_lte(grass.get_patch_cells().size(), TallGrass.MAX_PATCHES)


# -- seasonal growth (see SeasonCycle.growth_modifier) -----------------------
#
# advance() used to grow every patch at a flat GROWTH_RATE regardless of the
# season -- SeasonCycle.growth_modifier existed with zero live callers. The
# same real-time advance must now grow a patch measurably less in winter than
# in summer, with a raised floor so a dormant patch never fully stops.

## A cell TallGrass has not already map-seeded, so a test can plant a
## deliberately fresh, growth-0 shoot onto it (mirrors the scan
## test_planting_establishes_a_new_immature_patch already does).
func _an_unseeded_cell(grass: TallGrass) -> Vector2i:
	for y in HEIGHT:
		for x in WIDTH:
			if not grass.has_grass(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func test_advance_grows_slower_in_winter_than_in_summer_for_the_same_elapsed_time():
	var cycle := SeasonCycle.new()
	var summer_modifier: float = cycle.growth_modifier(SeasonCycle.SECONDS_PER_YEAR * 0.375)
	var winter_modifier: float = cycle.growth_modifier(SeasonCycle.SECONDS_PER_YEAR * 0.875)
	assert_almost_eq(summer_modifier, 1.0, 0.0001, "precondition: mid-summer is full growth")
	assert_almost_eq(winter_modifier, 0.2, 0.0001, "precondition: mid-winter is the raised floor")

	var summer := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	var winter := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	var cell := _an_unseeded_cell(summer)
	assert_ne(cell, Vector2i(-1, -1), "precondition: an empty cell to plant a fresh shoot into")
	assert_true(summer.plant(cell))
	assert_true(winter.plant(cell))

	summer.advance(10.0, summer_modifier)
	winter.advance(10.0, winter_modifier)

	assert_gt(
		summer.get_growth(cell), winter.get_growth(cell),
		"the same 10 real seconds should grow a shoot less in winter than in summer"
	)


## The "raised floor" contract (see growth_modifier's own doc comment):
## dormancy, not death -- even at winter's coldest point growth must still
## creep forward rather than stall at zero. Pinned here at the call site too,
## not just inside season_cycle.gd's own test.
func test_growth_never_fully_stops_even_at_winters_seasonal_floor():
	var winter_modifier: float = SeasonCycle.new().growth_modifier(SeasonCycle.SECONDS_PER_YEAR * 0.875)
	var grass := TallGrass.new(1, WIDTH, HEIGHT, _biome_all("grassland"))
	var cell := _an_unseeded_cell(grass)
	assert_ne(cell, Vector2i(-1, -1), "precondition: an empty cell to plant a fresh shoot into")
	assert_true(grass.plant(cell))

	grass.advance(10.0, winter_modifier)

	assert_gt(grass.get_growth(cell), 0.0, "a dormant plant still grows a little, it does not stop")
