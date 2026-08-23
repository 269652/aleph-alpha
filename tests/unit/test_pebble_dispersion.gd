extends GutTest

## Pebble dispersion (see docs/concept/stone.md): walking close enough to a
## loose stone kicks it a small, one-time distance out of the way -- like
## real kicked gravel, it stays wherever it lands rather than settling back.
## Pure positional math only; "is a walker now near this pebble" detection
## and "has this one already been kicked" state both live at the wiring edge
## (LiftableStone.try_disperse, World._step_pebble_dispersion) -- mirrors
## PathScarring's own split between pure wear math and the tile-detection
## loop in world.gd.

const PebbleDispersion = preload("res://src/rendering/pebble_dispersion.gd")
const StoneSize = preload("res://src/world/stone_size.gd")


func test_is_within_trigger_true_when_close():
	assert_true(PebbleDispersion.is_within_trigger(Vector2(100, 100), Vector2(102, 100)))


func test_is_within_trigger_false_when_far():
	assert_false(PebbleDispersion.is_within_trigger(Vector2(100, 100), Vector2(500, 500)))


func test_is_within_trigger_boundary():
	var walker := Vector2(0, 0)
	var just_inside := Vector2(PebbleDispersion.TRIGGER_RADIUS_PX - 0.5, 0)
	var just_outside := Vector2(PebbleDispersion.TRIGGER_RADIUS_PX + 0.5, 0)
	assert_true(PebbleDispersion.is_within_trigger(walker, just_inside))
	assert_false(PebbleDispersion.is_within_trigger(walker, just_outside))


## A kick pushes the pebble directly AWAY from the walker, by exactly
## NUDGE_DISTANCE_PX -- reads as "shoved out from underfoot" regardless of
## which direction the walker approached from.
func test_nudge_pushes_the_pebble_directly_away_from_the_walker():
	var walker := Vector2(0, 0)
	var pebble := Vector2(2, 0)
	var nudged: Vector2 = PebbleDispersion.nudge(walker, pebble)
	assert_almost_eq(nudged.x, 2.0 + PebbleDispersion.NUDGE_DISTANCE_PX, 0.01)
	assert_almost_eq(nudged.y, 0.0, 0.01)


func test_nudge_distance_is_always_exactly_the_configured_amount():
	var walker := Vector2(50, 80)
	var pebble := Vector2(53, 84)  # 5,3 offset from walker, not axis-aligned
	var nudged: Vector2 = PebbleDispersion.nudge(walker, pebble)
	assert_almost_eq(nudged.distance_to(pebble), PebbleDispersion.NUDGE_DISTANCE_PX, 0.01)


## No NaN/undefined direction when the walker is exactly on top of the
## pebble -- it still has to go SOMEWHERE.
func test_nudge_handles_the_walker_standing_exactly_on_the_pebble():
	var same_point := Vector2(10, 10)
	var nudged: Vector2 = PebbleDispersion.nudge(same_point, same_point)
	assert_almost_eq(nudged.distance_to(same_point), PebbleDispersion.NUDGE_DISTANCE_PX, 0.01)


func test_nudge_is_deterministic():
	var walker := Vector2(10, 20)
	var pebble := Vector2(13, 24)
	assert_eq(PebbleDispersion.nudge(walker, pebble), PebbleDispersion.nudge(walker, pebble))


# -- mass-weighted dispersion chance ------------------------------------------
#
# "Make nudging small pebbles a higher probability": an incidental footstep
# reliably disturbs a light pebble but only occasionally nudges a heavy
# cobble -- same momentum-vs-own-mass logic as the (much bigger) deliberate
# Kick action, just at footstep scale. Rolled fresh on every contact (see
# LiftableStone.try_disperse) rather than gating a one-shot lifetime flag.

## A near-weightless stone should land at the chance's own upper cap.
func test_dispersion_chance_is_at_the_max_for_a_near_weightless_stone():
	assert_almost_eq(
		PebbleDispersion.dispersion_chance(0.0001),
		PebbleDispersion.MAX_DISPERSION_CHANCE_PER_CONTACT,
		0.01
	)


## A very heavy stone should bottom out at the chance's own floor -- never
## exactly zero (a footstep's force still varies), but close to it.
func test_dispersion_chance_is_at_the_floor_for_a_very_heavy_stone():
	assert_almost_eq(
		PebbleDispersion.dispersion_chance(10000.0),
		PebbleDispersion.MIN_DISPERSION_CHANCE_PER_CONTACT,
		0.001
	)


## The chance must never go up as mass goes up -- the entire point of the
## mass-weighting.
func test_dispersion_chance_never_increases_as_mass_grows():
	var previous := PebbleDispersion.MAX_DISPERSION_CHANCE_PER_CONTACT
	var diameter := StoneSize.SMALLEST_CM
	while diameter <= StoneSize.COBBLE_MAX_CM:
		var chance := PebbleDispersion.dispersion_chance(StoneSize.mass_kg_for(diameter))
		assert_lte(chance, previous + 0.0001, "a %.1fcm stone had a higher dispersion chance than a lighter one" % diameter)
		previous = chance
		diameter += 1.0


## Stays within its own documented bounds across the whole liftable range.
func test_dispersion_chance_always_stays_within_its_bounds():
	var diameter := StoneSize.SMALLEST_CM
	while diameter <= StoneSize.COBBLE_MAX_CM:
		var chance := PebbleDispersion.dispersion_chance(StoneSize.mass_kg_for(diameter))
		assert_between(
			chance, PebbleDispersion.MIN_DISPERSION_CHANCE_PER_CONTACT, PebbleDispersion.MAX_DISPERSION_CHANCE_PER_CONTACT
		)
		diameter += 1.0


## A typical pebble should be noticeably more likely to disperse per contact
## than a large cobble near the liftable ceiling.
func test_a_pebble_has_a_much_higher_dispersion_chance_than_a_large_cobble():
	var pebble_chance := PebbleDispersion.dispersion_chance(StoneSize.mass_kg_for(3.0))
	var cobble_chance := PebbleDispersion.dispersion_chance(StoneSize.mass_kg_for(StoneSize.COBBLE_MAX_CM))
	assert_gt(pebble_chance, cobble_chance * 2.0, "a pebble should disperse much more readily than a big cobble")
