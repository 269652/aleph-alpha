extends GutTest

## ScentField + FlowerSpecies (see docs/concept/flora.md#flowering-plants-
## scent-and-pollinators).
##
## The design claim these tests exist to protect: scent SUPERPOSES. A dense
## clump of flowers must be a genuinely stronger signal than the same number
## of flowers scattered thinly -- that is what makes clumping mechanically
## meaningful, and what gives butterflies and bees a reason to gather at
## meadows rather than wander uniformly.

const FlowerSpecies = preload("res://src/world/flower_species.gd")
const ScentField = preload("res://src/world/scent_field.gd")

const TILE := 16.0


func _flower(position: Vector2, species: String = "rose") -> Dictionary:
	return {"position": position, "species": species}


# -- species catalog ---------------------------------------------------------

func test_every_listed_species_has_a_full_profile():
	for id in FlowerSpecies.IDS:
		var profile := FlowerSpecies.profile_for(id)
		assert_true(profile.has("bloom"), "%s needs bloom seasons" % id)
		assert_true(profile.has("color"), "%s needs a color" % id)
		assert_gt(float(profile["scent"]), 0.0, "%s should emit some scent" % id)


func test_an_unknown_species_falls_back_instead_of_crashing():
	assert_gt(FlowerSpecies.profile_for("triffid").size(), 0)


## Colour and scent are deliberately INDEPENDENT axes -- a showy flower is
## not automatically the most fragrant one (a tulip is loud but faint; a rose
## is the strongest scent in the roster). If these ever collapse into one
## axis, the meadow stops having interesting composition.
func test_scent_strength_is_not_merely_a_restatement_of_brightness():
	var rose := FlowerSpecies.profile_for("rose")
	var tulip := FlowerSpecies.profile_for("tulip")
	assert_gt(float(rose["scent"]), float(tulip["scent"]), "a rose out-scents a tulip")


func test_species_only_emit_scent_while_actually_in_bloom():
	assert_gt(FlowerSpecies.scent_strength("rose", "summer"), 0.0)
	assert_eq(FlowerSpecies.scent_strength("rose", "winter"), 0.0)


## Something has to be blooming in every season a pollinator could be active,
## or the meadow goes silent for a whole quarter of the year.
func test_at_least_one_species_blooms_in_each_growing_season():
	for season in ["spring", "summer", "autumn"]:
		var blooming := 0
		for id in FlowerSpecies.IDS:
			if FlowerSpecies.is_in_bloom(id, season):
				blooming += 1
		assert_gt(blooming, 0, "nothing blooms in %s" % season)


# -- the field itself --------------------------------------------------------

func test_bare_ground_has_no_scent():
	assert_eq(ScentField.concentration_at(Vector2.ZERO, [], "summer", TILE), 0.0)


func test_scent_falls_off_with_distance():
	var flowers := [_flower(Vector2.ZERO)]
	var near := ScentField.concentration_at(Vector2(TILE, 0), flowers, "summer", TILE)
	var far := ScentField.concentration_at(Vector2(TILE * 4.0, 0), flowers, "summer", TILE)
	assert_gt(near, far)
	assert_gt(far, 0.0, "still within reach, just fainter")


func test_a_flower_beyond_the_scent_radius_contributes_nothing():
	var beyond: float = (ScentField.RADIUS_TILES + 1.0) * TILE
	assert_eq(
		ScentField.concentration_at(Vector2(beyond, 0), [_flower(Vector2.ZERO)], "summer", TILE), 0.0
	)


## THE point of the system: contributions add up.
func test_scent_superposes_so_a_clump_is_stronger_than_one_flower():
	var one := ScentField.concentration_at(Vector2.ZERO, [_flower(Vector2.ZERO)], "summer", TILE)
	var clump: Array = []
	for i in 5:
		clump.append(_flower(Vector2(float(i) * 2.0, 0.0)))
	var many := ScentField.concentration_at(Vector2.ZERO, clump, "summer", TILE)
	assert_gt(many, one * 2.0, "five neighbouring flowers should read far stronger than one")


## ...and the same flowers spread thin must NOT reach the same peak, or
## clumping carries no mechanical meaning at all.
func test_the_same_flowers_scattered_thinly_peak_lower_than_when_clumped():
	var clumped: Array = []
	var scattered: Array = []
	for i in 5:
		clumped.append(_flower(Vector2(float(i) * 2.0, 0.0)))
		scattered.append(_flower(Vector2(float(i) * ScentField.RADIUS_TILES * TILE, 0.0)))
	assert_gt(
		ScentField.concentration_at(Vector2.ZERO, clumped, "summer", TILE),
		ScentField.concentration_at(Vector2.ZERO, scattered, "summer", TILE)
	)


func test_out_of_season_flowers_add_nothing_to_the_field():
	var flowers := [_flower(Vector2.ZERO, "rose")]
	assert_eq(ScentField.concentration_at(Vector2.ZERO, flowers, "winter", TILE), 0.0)


# -- what pollinators do with it --------------------------------------------

## Movement biases UP the gradient, so flyers drift toward dense patches
## instead of wandering uniformly.
func test_pollinators_are_steered_toward_a_nearby_patch():
	var patch: Array = []
	for i in 4:
		patch.append(_flower(Vector2(TILE * 3.0 + float(i) * 2.0, 0.0)))
	var direction := ScentField.gradient_direction(Vector2.ZERO, patch, "summer", TILE)
	assert_gt(direction.x, 0.5, "should steer toward the patch, which lies east")
	assert_almost_eq(direction.length(), 1.0, 0.01, "a steering direction should be normalized")


func test_steering_is_neutral_where_there_is_nothing_to_smell():
	assert_eq(ScentField.gradient_direction(Vector2.ZERO, [], "summer", TILE), Vector2.ZERO)


## Spawn rate scales with concentration, so a flowered meadow is visibly
## busier than bare grass -- but bounded, so a huge meadow can't spawn an
## unbounded swarm.
func test_spawn_rate_rises_with_concentration_but_stays_bounded():
	assert_almost_eq(ScentField.pollinator_spawn_multiplier(0.0), 1.0, 0.001)
	assert_gt(ScentField.pollinator_spawn_multiplier(1.0), 1.0)
	assert_gt(
		ScentField.pollinator_spawn_multiplier(4.0), ScentField.pollinator_spawn_multiplier(1.0)
	)
	assert_lte(ScentField.pollinator_spawn_multiplier(9999.0), ScentField.MAX_SPAWN_MULTIPLIER)


func test_the_field_is_deterministic():
	var flowers := [_flower(Vector2(3, 4)), _flower(Vector2(9, 1), "lavender")]
	assert_eq(
		ScentField.concentration_at(Vector2.ZERO, flowers, "summer", TILE),
		ScentField.concentration_at(Vector2.ZERO, flowers, "summer", TILE)
	)


# -- a single bloom still attracts, just weakly ------------------------------
#
# The spawn multiplier is sampled at the strongest bloom rather than at a
# fixed point, so attraction scales continuously with how much is growing.
# A lone flower must give a real (if small) boost -- not nothing.

func test_a_single_flower_attracts_more_than_bare_ground():
	var lone := ScentField.concentration_at(Vector2.ZERO, [_flower(Vector2.ZERO)], "summer", TILE)
	assert_gt(
		ScentField.pollinator_spawn_multiplier(lone), 1.0,
		"one bloom should still draw something, just faintly"
	)


## ...but a whole field must clearly out-pull it, or clumping stops mattering.
func test_a_field_out_pulls_a_single_flower():
	var field: Array = []
	for i in 12:
		field.append(_flower(Vector2(float(i % 4) * 8.0, float(i / 4) * 8.0)))
	var lone := ScentField.concentration_at(Vector2.ZERO, [_flower(Vector2.ZERO)], "summer", TILE)
	var dense := ScentField.concentration_at(Vector2(8, 8), field, "summer", TILE)
	assert_gt(
		ScentField.pollinator_spawn_multiplier(dense),
		ScentField.pollinator_spawn_multiplier(lone) * 1.5,
		"a meadow should pull far harder than a single bloom"
	)
