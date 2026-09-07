extends GutTest

## Per-chunk honeybee colony population -- see docs/concept/bees.md. Mirrors
## test_ant_colony.gd's own shape wherever the mechanism is genuinely the
## same (seeding, population/capacity, food economy, swarming), and departs
## from it deliberately where bees are a real, different animal (no water/
## moisture capacity input, absconding replaces same-site refounding, real
## honey withdrawal for the harvest mechanic) -- see bees.md's own "What's
## reused verbatim, what's a deliberate new duplicate, and why".

const BeeColony = preload("res://src/world/bee_colony.gd")
const BeePopulationModel = preload("res://src/world/bee_population_model.gd")

const WIDTH := 16
const HEIGHT := 16


func _all_grassland() -> PackedStringArray:
	var biome := PackedStringArray()
	biome.resize(WIDTH * HEIGHT)
	for i in biome.size():
		biome[i] = "grassland"
	return biome


func _all_desert() -> PackedStringArray:
	var biome := PackedStringArray()
	biome.resize(WIDTH * HEIGHT)
	for i in biome.size():
		biome[i] = "desert"
	return biome


## HIVE_CHANCE is deliberately far sparser than an ant mound's own (see
## test_hives_are_sparser_than_ant_mounds below), so a single arbitrary
## seed is not reliably guaranteed to land one on a real roll -- the same
## reason test_ant_colony.gd's own suite reaches for a guaranteed-mound
## helper rather than trusting a fixed seed to get lucky. This is a fixed,
## deterministic search over pure, seed-derived placement (PixelNoise, not
## RNG) -- the same seed value always either does or doesn't place a hive,
## so this converges to the identical answer every run, never flaky.
func _colony_with_one_hive() -> BeeColony:
	for seed_value in range(1, 200):
		var colony := BeeColony.new(seed_value, WIDTH, HEIGHT, _all_grassland())
		if colony.hive_cells().size() > 0:
			return colony
	fail_test("no seed in [1, 200) placed a single hive on an all-grassland chunk")
	return null


func _a_free_cell(colony: BeeColony) -> Vector2i:
	for y in HEIGHT:
		for x in WIDTH:
			var cell := Vector2i(x, y)
			if not colony.has_hive(cell):
				return cell
	fail_test("expected at least one free cell")
	return Vector2i(-1, -1)


# -- placement / seeding -----------------------------------------------------

func test_seeds_at_least_one_hive_across_a_reasonable_search_of_seeds():
	# Not "on any given seed" -- HIVE_CHANCE is intentionally low (see
	# test_hives_are_sparser_than_ant_mounds) -- but placement must not be
	# so rare that NO seed in a generous range ever succeeds, or the whole
	# mechanism would never surface for a real player either.
	assert_gt(_colony_with_one_hive().hive_cells().size(), 0)


func test_never_seeds_a_hive_on_a_biome_with_no_trees():
	var colony := BeeColony.new(1, WIDTH, HEIGHT, _all_desert())
	assert_eq(colony.hive_cells().size(), 0)


func test_placement_is_deterministic_for_the_same_seed():
	var a := BeeColony.new(42, WIDTH, HEIGHT, _all_grassland())
	var b := BeeColony.new(42, WIDTH, HEIGHT, _all_grassland())
	assert_eq(a.hive_cells(), b.hive_cells())


func test_different_seeds_can_place_hives_differently():
	var placements := {}
	for seed_value in range(30):
		var colony := BeeColony.new(seed_value, WIDTH, HEIGHT, _all_grassland())
		placements[colony.hive_cells()] = true
	assert_gt(placements.size(), 1, "30 different seeds should not all place identically")


## A real wild honeybee colony forages over a MUCH larger real territory
## than a single ant nest's tiny local patch -- far fewer hives per unit
## area is the correct real-world shape, not an arbitrary aesthetic choice.
func test_hives_are_sparser_than_ant_mounds():
	const AntColony = preload("res://src/world/ant_colony.gd")
	assert_lt(BeeColony.HIVE_CHANCE, AntColony.MOUND_CHANCE)


func test_never_exceeds_the_hard_per_chunk_cap():
	for seed_value in range(20):
		var colony := BeeColony.new(seed_value, WIDTH, HEIGHT, _all_grassland())
		assert_lte(colony.hive_cells().size(), BeeColony.MAX_HIVES)


func test_has_hive_is_true_only_for_a_real_seeded_cell():
	var colony := _colony_with_one_hive()
	for cell in colony.hive_cells():
		assert_true(colony.has_hive(cell))
	assert_false(colony.has_hive(Vector2i(-1, -1)))


# -- constants cross-checked against their own real source of truth --------

## FORAGE_RADIUS_TILES is restated locally rather than imported (avoiding
## a needless cross-module dependency for one float) -- this is what keeps
## the restatement from silently drifting off PollinatorForaging's own
## real, already-tuned "how far a bee/butterfly searches for a flower"
## distance.
func test_forage_radius_matches_pollinator_foragings_own_search_distance():
	const PollinatorForaging = preload("res://src/gameplay/pollinator_foraging.gd")
	assert_almost_eq(BeeColony.FORAGE_RADIUS_TILES, PollinatorForaging.FORAGE_SEARCH_TILES, 0.001)


## Mirrors AntColony's own identical cross-check against
## EarthChunkManager.SECONDS_PER_SIMULATED_DAY, for the identical reason:
## EarthChunkManager already preloads BeeColony, so the reverse import
## would be circular.
func test_seconds_per_simulated_day_matches_earth_chunk_managers_own_constant():
	const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
	assert_almost_eq(BeeColony.SECONDS_PER_SIMULATED_DAY, EarthChunkManager.SECONDS_PER_SIMULATED_DAY, 0.001)


# -- population / honey economy ----------------------------------------------

func test_a_freshly_seeded_hive_starts_at_the_starting_population():
	var colony := _colony_with_one_hive()
	for cell in colony.hive_cells():
		assert_almost_eq(colony.population_at(cell), BeePopulationModel.STARTING_POPULATION, 0.01)


func test_a_freshly_seeded_hive_starts_with_a_full_honey_buffer():
	var colony := _colony_with_one_hive()
	var expected := (
		BeePopulationModel.STARTING_POPULATION
		* BeePopulationModel.HONEY_PER_BEE_PER_DAY
		* BeePopulationModel.HONEY_BUFFER_DAYS
	)
	for cell in colony.hive_cells():
		assert_almost_eq(colony.honey_stored_at(cell), expected, 0.01)


func test_population_at_an_unrelated_cell_reads_the_starting_population_default():
	var colony := _colony_with_one_hive()
	assert_almost_eq(
		colony.population_at(Vector2i(-5, -5)), BeePopulationModel.STARTING_POPULATION, 0.01
	)


func test_record_forage_result_moves_the_recent_success_signal_up_on_success():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	var before := colony.capacity_at(cell)
	for i in 10:
		colony.record_forage_result(cell, true)
	assert_gt(colony.capacity_at(cell), before)


func test_record_forage_result_deposits_real_honey_only_on_success():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	var before := colony.honey_stored_at(cell)
	colony.record_forage_result(cell, false)
	assert_almost_eq(colony.honey_stored_at(cell), before, 0.001, "a failed trip deposits nothing")
	colony.record_forage_result(cell, true)
	assert_gt(colony.honey_stored_at(cell), before, "a successful trip deposits real honey")


func test_deposit_food_adds_to_the_real_reserve():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	var before := colony.honey_stored_at(cell)
	colony.deposit_food(cell, 5.0)
	assert_almost_eq(colony.honey_stored_at(cell), before + 5.0, 0.001)


func test_capacity_is_gated_by_real_honey_on_hand():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	for i in 20:
		colony.record_forage_result(cell, true)
	var well_stocked := colony.capacity_at(cell)
	# Drain the reserve directly and confirm capacity actually drops even
	# though the recent-success EMA above is still maxed -- the real
	# stockpile is a genuine, independent constraint, not cosmetic.
	colony.withdraw_honey(cell, colony.honey_stored_at(cell))
	assert_lt(colony.capacity_at(cell), well_stocked)


func test_advance_grows_population_toward_capacity_when_well_fed():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	var before := colony.population_at(cell)
	# A real "well fed" hive keeps finding nectar continuously across the
	# whole window, not once up front and never again.
	for i in 200:
		colony.record_forage_result(cell, true)
		colony.advance(1.0)
	assert_gt(colony.population_at(cell), before, "a consistently well-fed hive should grow")


func test_advance_shrinks_population_once_honey_runs_out_with_no_restock():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	colony.withdraw_honey(cell, colony.honey_stored_at(cell))
	var before := colony.population_at(cell)
	for i in 400:
		colony.advance(1.0)
	assert_lt(colony.population_at(cell), before, "a hive with nothing stored and nothing coming in should shrink")


# -- honey withdrawal (the harvest mechanic's own hook) ----------------------

func test_withdraw_honey_removes_up_to_the_requested_amount():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	var on_hand := colony.honey_stored_at(cell)
	var taken := colony.withdraw_honey(cell, 3.0)
	assert_almost_eq(taken, 3.0, 0.001)
	assert_almost_eq(colony.honey_stored_at(cell), on_hand - 3.0, 0.001)


func test_withdraw_honey_never_takes_more_than_is_actually_stored():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	var on_hand := colony.honey_stored_at(cell)
	var taken := colony.withdraw_honey(cell, on_hand + 1000.0)
	assert_almost_eq(taken, on_hand, 0.001)
	assert_almost_eq(colony.honey_stored_at(cell), 0.0, 0.001)


func test_withdraw_honey_from_an_empty_hive_yields_nothing_and_never_goes_negative():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	colony.withdraw_honey(cell, colony.honey_stored_at(cell))
	var taken := colony.withdraw_honey(cell, 5.0)
	assert_almost_eq(taken, 0.0, 0.001)
	assert_almost_eq(colony.honey_stored_at(cell), 0.0, 0.001)


# -- winter dormancy ----------------------------------------------------------

func test_cold_soil_depletes_honey_slower_than_mild_soil():
	const EarthwormPatch = preload("res://src/world/earthworm_patch.gd")
	# _colony_with_one_hive's own seed search is a fixed, deterministic
	# function of its inputs -- calling it twice yields two SEPARATE but
	# identically-placed colonies (same seed, same hive cell), exactly
	# what this comparison needs, with no internal-field poking required.
	var cold := _colony_with_one_hive()
	var warm := _colony_with_one_hive()
	var cold_cell: Vector2i = cold.hive_cells()[0]
	var warm_cell: Vector2i = warm.hive_cells()[0]
	# record_warmth is an EMA (see FORAGE_SUCCESS_EMA_RATE/WARMTH_EMA_RATE) --
	# one call only moves 30% of the way from the 1.0 default toward the
	# target, so this converges it close enough that the two cases actually
	# land on opposite sides of the real cold_gate ramp.
	for i in 20:
		cold.record_warmth(cold_cell, 0.0)
		warm.record_warmth(warm_cell, EarthwormPatch.MILD_WARMTH)
	for i in 50:
		cold.advance(1.0)
		warm.advance(1.0)
	assert_gt(
		cold.honey_stored_at(cold_cell), warm.honey_stored_at(warm_cell),
		"a dormant, cold-clustered hive should burn through its stores slower than an active one"
	)


func test_dormancy_never_reaches_a_hard_zero():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	colony.record_warmth(cell, 0.0)
	assert_gt(colony.dormancy_multiplier_at(cell), 0.0)


# -- absconding: destroyed, harvested-to-collapse, or starved ---------------

func test_should_abscond_is_false_for_a_healthy_freshly_seeded_hive():
	var colony := _colony_with_one_hive()
	assert_false(colony.should_abscond_at(colony.hive_cells()[0]))


func test_should_abscond_becomes_true_once_population_hits_zero():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	colony.withdraw_honey(cell, colony.honey_stored_at(cell))
	for i in 400:
		colony.advance(1.0)
	assert_almost_eq(colony.population_at(cell), 0.0, 0.01)
	assert_true(colony.should_abscond_at(cell))


func test_should_abscond_is_false_at_an_unrelated_cell():
	var colony := _colony_with_one_hive()
	assert_false(colony.should_abscond_at(Vector2i(-9, -9)))


## Unlike an ant mound (which refounds at the SAME cell -- see AntColony.
## _maybe_refound), a starved hive's population is never quietly revived
## in place by advance() alone: a real colony that has run its home into
## the ground moves ON. Confirmed directly: it stays at exactly 0.0
## forever under ordinary advance(), even once real honey piles back up
## (mirroring test_ant_colony.gd's own "a starved colony does not recover
## through growth alone" contract, but WITHOUT AntColony's own
## _maybe_refound escape hatch, since here that escape is abscond_to
## instead -- see below).
func test_a_collapsed_hive_never_revives_in_place_on_its_own():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	colony.withdraw_honey(cell, colony.honey_stored_at(cell))
	for i in 400:
		colony.advance(1.0)
	colony.deposit_food(cell, 500.0)
	for i in 400:
		colony.advance(1.0)
	assert_almost_eq(colony.population_at(cell), 0.0, 0.01)


func test_is_valid_hive_site_rejects_an_occupied_cell():
	var colony := _colony_with_one_hive()
	assert_false(colony.is_valid_hive_site(colony.hive_cells()[0]))


func test_is_valid_hive_site_rejects_a_biome_with_no_trees():
	var colony := BeeColony.new(1, WIDTH, HEIGHT, _all_desert())
	assert_false(colony.is_valid_hive_site(Vector2i(3, 3)))


func test_is_valid_hive_site_rejects_out_of_bounds():
	var colony := _colony_with_one_hive()
	assert_false(colony.is_valid_hive_site(Vector2i(-1, 0)))
	assert_false(colony.is_valid_hive_site(Vector2i(WIDTH, 0)))


func test_is_valid_hive_site_accepts_a_real_free_tree_bearing_cell():
	var colony := _colony_with_one_hive()
	assert_true(colony.is_valid_hive_site(_a_free_cell(colony)))


## The colony's own pure half of relocation: carries the FULL population
## and FULL remaining honey across to the new site (unlike bud_new_hive's
## 50/50 swarm split) -- absconding is the whole colony moving house, not
## reproducing.
func test_abscond_to_moves_the_full_population_and_honey_to_the_new_site():
	var colony := _colony_with_one_hive()
	var from_cell: Vector2i = colony.hive_cells()[0]
	var to_cell := _a_free_cell(colony)
	var population := colony.population_at(from_cell)
	var honey := colony.honey_stored_at(from_cell)
	colony.abscond_to(from_cell, to_cell)
	assert_false(colony.has_hive(from_cell), "the old site is abandoned")
	assert_true(colony.has_hive(to_cell))
	assert_almost_eq(colony.population_at(to_cell), population, 0.01)
	assert_almost_eq(colony.honey_stored_at(to_cell), honey, 0.01)


func test_abscond_to_is_a_no_op_at_an_invalid_destination():
	var colony := _colony_with_one_hive()
	var from_cell: Vector2i = colony.hive_cells()[0]
	var before := colony.population_at(from_cell)
	colony.abscond_to(from_cell, from_cell)
	assert_true(colony.has_hive(from_cell))
	assert_almost_eq(colony.population_at(from_cell), before, 0.01)


# -- swarming: overpopulation buds a new hive, mirroring AntColony ----------

func test_is_overpopulated_is_false_for_a_freshly_seeded_hive():
	var colony := _colony_with_one_hive()
	assert_false(colony.is_overpopulated_at(colony.hive_cells()[0]))


func test_is_overpopulated_becomes_true_at_the_reference_population():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	colony._population[cell] = BeePopulationModel.MAX_REFERENCE_POPULATION
	assert_true(colony.is_overpopulated_at(cell))


func test_should_bud_is_false_when_not_overpopulated():
	var colony := _colony_with_one_hive()
	assert_false(colony.should_bud(colony.hive_cells()[0]))


func test_bud_new_hive_halves_both_population_and_honey():
	var colony := _colony_with_one_hive()
	var from_cell: Vector2i = colony.hive_cells()[0]
	var to_cell := _a_free_cell(colony)
	var population := colony.population_at(from_cell)
	var honey := colony.honey_stored_at(from_cell)
	colony.bud_new_hive(from_cell, to_cell)
	assert_almost_eq(colony.population_at(from_cell), population * 0.5, 0.01)
	assert_almost_eq(colony.honey_stored_at(from_cell), honey * 0.5, 0.01)
	assert_almost_eq(colony.population_at(to_cell), population * 0.5, 0.01)
	assert_almost_eq(colony.honey_stored_at(to_cell), honey * 0.5, 0.01)
	assert_true(colony.has_hive(to_cell))


func test_bud_new_hive_is_a_no_op_at_an_invalid_site():
	var colony := _colony_with_one_hive()
	var from_cell: Vector2i = colony.hive_cells()[0]
	var before := colony.population_at(from_cell)
	colony.bud_new_hive(from_cell, from_cell)
	assert_almost_eq(colony.population_at(from_cell), before, 0.01)


# -- dispatch / growth-fraction ----------------------------------------------

func test_growth_fraction_is_zero_to_one():
	var colony := _colony_with_one_hive()
	var fraction := colony.growth_fraction_at(colony.hive_cells()[0])
	assert_gte(fraction, 0.0)
	assert_lte(fraction, 1.0)


func test_growth_fraction_rises_toward_one_for_a_thriving_hive():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	var before := colony.growth_fraction_at(cell)
	# A real "thriving" hive keeps finding nectar continuously, not once
	# and then never again -- record_forage_result alongside every
	# advance(), the same ongoing restock a real dispatched forager
	# stream would provide via EarthChunkManager.step_bees.
	for i in 400:
		colony.record_forage_result(cell, true)
		colony.advance(1.0)
	assert_gt(colony.growth_fraction_at(cell), before)


func test_active_forager_cap_is_at_least_one_even_for_a_collapsed_hive():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	colony.withdraw_honey(cell, colony.honey_stored_at(cell))
	for i in 400:
		colony.advance(1.0)
	assert_gte(colony.active_forager_cap_at(cell), 1)


## NOT a before/after-over-time comparison: a freshly-seeded hive already
## STARTS at the maximum cap (population == BASE_CAPACITY exactly, by
## design -- see test_starting_population_matches_the_unfed_baseline_
## capacity), the identical "already at its own unfed ceiling" property
## AntColony's own STARTING_POPULATION == BASE_CAPACITY has, so there is
## nowhere for a fresh hive's own cap to rise FROM. What actually matters
## is the structural relationship: a hive whose population lags well
## behind what its current conditions could support gets a smaller cap
## than one that isn't.
func test_active_forager_cap_scales_down_for_a_population_lagging_its_capacity():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	var healthy := colony.active_forager_cap_at(cell)
	colony._population[cell] = 1.0
	var lagging := colony.active_forager_cap_at(cell)
	assert_lt(lagging, healthy)


func test_should_forage_rolls_both_outcomes_across_many_hives():
	var results := {true: 0, false: 0}
	for seed_value in range(400):
		var colony := BeeColony.new(seed_value, WIDTH, HEIGHT, _all_grassland())
		for cell in colony.hive_cells():
			results[colony.should_forage(cell)] += 1
	assert_gt(results[true], 0)
	assert_gt(results[false], 0)
