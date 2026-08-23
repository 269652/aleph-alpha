extends GutTest

## Kick (see docs/concept/stone.md): a deliberate one-time momentum delivered
## to the nearest liftable stone in reach, bound to K (Keybindings). Reuses
## the SAME momentum model as impact_resolver.gd/throwable.gd
## (momentum = mass * velocity) rather than a parallel physics system: the
## "leg" (StoneSize.LEG_MASS_KG) delivers momentum at a real kick-swing
## speed, and how far a stone flies falls out of momentum vs. its OWN mass,
## exactly like Throwable.impact_knockback's reasoning. A stone at or above
## leg mass is too heavy for a kick to meaningfully move at all.

const Kick = preload("res://src/gameplay/kick.gd")
const StoneSize = preload("res://src/world/stone_size.gd")


# -- kickable or not ----------------------------------------------------------

func test_a_light_pebble_is_kickable():
	assert_true(Kick.is_kickable(StoneSize.mass_kg_for(3.0)))


## The user's explicit design: a stone AT OR ABOVE leg mass simply doesn't
## move -- too heavy for a kick's delivered momentum to matter.
func test_a_stone_at_or_above_leg_mass_is_not_kickable():
	assert_false(Kick.is_kickable(StoneSize.LEG_MASS_KG))
	assert_false(Kick.is_kickable(StoneSize.LEG_MASS_KG + 0.01))


func test_a_stone_just_under_leg_mass_is_kickable():
	assert_true(Kick.is_kickable(StoneSize.LEG_MASS_KG - 0.01))


## Most boulders (and most cobbles) sit far above leg mass and should never
## be kickable -- kick only meaningfully affects pebbles and the lightest
## cobbles, by design (see the module's own doc comment).
func test_a_typical_boulder_is_not_kickable():
	assert_false(Kick.is_kickable(StoneSize.mass_kg_for(100.0)))


# -- kick distance scales with momentum vs. the stone's own mass ------------

## Pins the exact formula (kinematics: v = p/m, then d = v^2 / (2 * mu * g),
## the real "sliding stopping distance under kinetic friction" equation) so
## the constants and the formula can't silently drift apart.
func test_kick_distance_px_matches_the_kinematics_formula_below_the_cap():
	var mass_kg := StoneSize.LEG_MASS_KG  # velocity_after == KICK_SPEED_MPS exactly here
	var velocity_after := Kick.KICK_MOMENTUM_KG_M_S / mass_kg
	var distance_m := (velocity_after * velocity_after) / (2.0 * Kick.GROUND_FRICTION_COEFFICIENT * Kick.GRAVITY_MPS2)
	var expected_px := distance_m * Kick.PX_PER_METER
	assert_almost_eq(Kick.kick_distance_px(mass_kg), minf(expected_px, Kick.MAX_KICK_DISTANCE_PX), 0.01)


func test_kick_distance_px_never_exceeds_the_max():
	var diameter := StoneSize.SMALLEST_CM
	while diameter <= StoneSize.COBBLE_MAX_CM:
		var distance := Kick.kick_distance_px(StoneSize.mass_kg_for(diameter))
		assert_lte(distance, Kick.MAX_KICK_DISTANCE_PX)
		diameter += 1.0


func test_kick_distance_px_is_never_negative():
	assert_gte(Kick.kick_distance_px(0.0001), 0.0)
	assert_gte(Kick.kick_distance_px(1000.0), 0.0)


## Heavier stone = shorter kick distance for the same delivered momentum --
## exactly Throwable.impact_knockback's own reasoning.
func test_a_heavier_stone_flies_a_shorter_distance():
	var light_distance := Kick.kick_distance_px(StoneSize.mass_kg_for(2.0))
	var heavy_distance := Kick.kick_distance_px(StoneSize.mass_kg_for(20.0))
	assert_gt(light_distance, heavy_distance)


func test_kick_distance_never_increases_as_mass_grows():
	var previous := Kick.MAX_KICK_DISTANCE_PX + 1.0
	var diameter := StoneSize.SMALLEST_CM
	while diameter <= StoneSize.COBBLE_MAX_CM:
		var distance := Kick.kick_distance_px(StoneSize.mass_kg_for(diameter))
		assert_lte(distance, previous + 0.001, "a %.1fcm stone flew further than a lighter one" % diameter)
		previous = distance
		diameter += 1.0


# -- landing position: pushed directly away from the kicker -----------------

func test_landing_position_pushes_directly_away_from_the_kicker():
	var kicker := Vector2(0, 0)
	var stone := Vector2(2, 0)
	var mass := StoneSize.mass_kg_for(2.0)
	var landing: Vector2 = Kick.landing_position(kicker, stone, mass)
	assert_almost_eq(landing.distance_to(stone), Kick.kick_distance_px(mass), 0.01)
	# Same direction as (stone - kicker), i.e. strictly further along +X.
	assert_gt(landing.x, stone.x)
	assert_almost_eq(landing.y, 0.0, 0.01)


func test_landing_position_handles_the_kicker_standing_exactly_on_the_stone():
	var same_point := Vector2(10, 10)
	var mass := StoneSize.mass_kg_for(2.0)
	var landing: Vector2 = Kick.landing_position(same_point, same_point, mass)
	assert_almost_eq(landing.distance_to(same_point), Kick.kick_distance_px(mass), 0.01)


func test_landing_position_is_deterministic():
	var kicker := Vector2(10, 20)
	var stone := Vector2(13, 24)
	var mass := StoneSize.mass_kg_for(5.0)
	assert_eq(Kick.landing_position(kicker, stone, mass), Kick.landing_position(kicker, stone, mass))
