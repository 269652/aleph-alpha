extends GutTest

const MountainOrePlacement = preload("res://src/world/mountain_ore_placement.gd")
const TerrainPassability = preload("res://src/gameplay/terrain_passability.gd")
const OrePlacement = preload("res://src/world/ore_placement.gd")

var placement: MountainOrePlacement


func before_each():
	placement = MountainOrePlacement.new()


# -- vein_chance_for_slope: steepness exposes it (see terrain_relief.md) --------

func test_vein_chance_is_zero_below_the_minimum_slope():
	assert_eq(placement.vein_chance_for_slope(0.0), 0.0)
	assert_eq(placement.vein_chance_for_slope(MountainOrePlacement.MIN_SLOPE_FOR_VEINS_DEG), 0.0)


func test_vein_chance_grows_with_slope():
	var gentle := placement.vein_chance_for_slope(MountainOrePlacement.MIN_SLOPE_FOR_VEINS_DEG + 5.0)
	var steep := placement.vein_chance_for_slope(MountainOrePlacement.MAX_SLOPE_FOR_SCALING_DEG - 5.0)
	assert_gt(steep, gentle)
	assert_gt(gentle, 0.0)


func test_vein_chance_reaches_its_ceiling_at_the_max_scaling_slope():
	assert_almost_eq(
		placement.vein_chance_for_slope(MountainOrePlacement.MAX_SLOPE_FOR_SCALING_DEG),
		MountainOrePlacement.MAX_VEIN_CHANCE,
		0.001
	)


func test_vein_chance_never_exceeds_its_ceiling_beyond_the_max_scaling_slope():
	assert_almost_eq(
		placement.vein_chance_for_slope(89.0), MountainOrePlacement.MAX_VEIN_CHANCE, 0.001
	)


## The same slope that gates whether the player can even cross a face is
## what this reuses as the "steepest realistic scaling point" -- a real,
## deliberate coupling (see docs/concept/terrain_relief.md: "the same
## steepness that makes a face hard to cross is what makes it worth
## crossing"), not a coincidence.
func test_max_scaling_slope_matches_the_roped_passability_ceiling():
	assert_eq(
		MountainOrePlacement.MAX_SLOPE_FOR_SCALING_DEG, TerrainPassability.HARD_THRESHOLD_WITH_ROPE_DEG
	)


func test_min_slope_for_veins_matches_the_soft_passability_threshold():
	assert_eq(MountainOrePlacement.MIN_SLOPE_FOR_VEINS_DEG, TerrainPassability.SOFT_THRESHOLD_DEG)


# -- has_vein_at: deterministic per-position roll against that chance -----------

func test_has_vein_at_is_always_false_when_the_slope_is_too_gentle():
	for trial in 20:
		assert_false(placement.has_vein_at(trial * 7, trial * 13, 5.0))


func test_has_vein_at_is_deterministic_for_the_same_position_and_slope():
	var a := placement.has_vein_at(1000, 2000, 60.0)
	var b := placement.has_vein_at(1000, 2000, 60.0)
	assert_eq(a, b)


func test_has_vein_at_varies_across_positions_at_a_steep_slope():
	var seen := {true: false, false: false}
	for trial in 200:
		seen[placement.has_vein_at(trial * 31, trial * 53, 60.0)] = true
	assert_true(seen[true], "expected at least one vein to roll true across 200 steep-slope samples")
	assert_true(seen[false], "expected at least one vein to roll false across 200 steep-slope samples")


func test_a_steeper_slope_produces_more_veins_across_the_same_sample_of_positions():
	var gentle_count := 0
	var steep_count := 0
	for trial in 300:
		if placement.has_vein_at(trial * 17, trial * 29, MountainOrePlacement.MIN_SLOPE_FOR_VEINS_DEG + 2.0):
			gentle_count += 1
		if placement.has_vein_at(trial * 17, trial * 29, MountainOrePlacement.MAX_SLOPE_FOR_SCALING_DEG):
			steep_count += 1
	assert_gt(steep_count, gentle_count)


# -- ore type/seed: reuses OrePlacement's own derivation, not a duplicate ------

func test_ore_type_at_reuses_ore_placements_own_types():
	var ore_type := placement.ore_type_at(123, 456)
	assert_true(OrePlacement.ORE_TYPES.has(ore_type))


func test_ore_type_at_is_deterministic():
	assert_eq(placement.ore_type_at(10, 20), placement.ore_type_at(10, 20))


func test_seed_at_is_deterministic():
	assert_eq(placement.seed_at(10, 20), placement.seed_at(10, 20))


## Genuine reuse, not a reimplementation with its own hash formula: mountain
## and flat-ground ore cells are mutually exclusive biomes (a tile is never
## both), so there's no real collision risk to guard against by rolling a
## separate channel -- sharing OrePlacement's exact derivation is simpler
## and just as correct.
func test_ore_type_at_matches_ore_placements_own_derivation_exactly():
	var direct := OrePlacement.new()
	assert_eq(placement.ore_type_at(777, 888), direct.ore_type_at(777, 888))


func test_seed_at_matches_ore_placements_own_derivation_exactly():
	var direct := OrePlacement.new()
	assert_eq(placement.seed_at(777, 888), direct.seed_at(777, 888))
