extends GutTest

## The release half of hold-E-to-charge-then-release (see docs/concept/
## stone.md): whatever power the ChargeMeter was at on release maps to a
## real throw speed, which feeds the SAME momentum model
## (Throwable.impact_knockback, docs/concept/materials.md) and the SAME
## real sliding kinematics (GroundSlide) that Kick already uses -- not a
## parallel physics system.
##
## Judgment call, documented here rather than guessed at silently: flight
## DISTANCE is modeled from release speed alone (how hard the charge/throw
## was), not divided by the thrown stone's own mass the way Kick's
## foot-delivers-a-fixed-momentum model is. A thrown item is actively
## swung by the player at whatever speed the meter dictates, not a passive
## object receiving an external momentum transfer the way a kicked stone
## is -- so speed, not momentum-vs-mass, is what determines how far the
## arm sends it. Momentum (mass x release speed) is still what should feed
## impact/damage on landing, through the SAME Throwable.impact_knockback
## used everywhere else.

const HeldItemThrow = preload("res://src/gameplay/held_item_throw.gd")
const Throwable = preload("res://src/gameplay/throwable.gd")


func test_release_speed_at_zero_power_is_the_minimum():
	assert_almost_eq(HeldItemThrow.release_speed_mps(0.0), HeldItemThrow.MIN_THROW_SPEED_MPS, 0.001)


func test_release_speed_at_full_power_is_the_maximum():
	assert_almost_eq(HeldItemThrow.release_speed_mps(1.0), HeldItemThrow.MAX_THROW_SPEED_MPS, 0.001)


func test_release_speed_increases_with_power():
	assert_gt(HeldItemThrow.release_speed_mps(0.8), HeldItemThrow.release_speed_mps(0.2))


func test_release_speed_stays_within_bounds_for_out_of_range_power():
	assert_almost_eq(HeldItemThrow.release_speed_mps(-1.0), HeldItemThrow.MIN_THROW_SPEED_MPS, 0.001)
	assert_almost_eq(HeldItemThrow.release_speed_mps(2.0), HeldItemThrow.MAX_THROW_SPEED_MPS, 0.001)


func test_throw_distance_px_never_exceeds_the_max():
	assert_lte(HeldItemThrow.throw_distance_px(1.0), HeldItemThrow.MAX_THROW_DISTANCE_PX)


func test_throw_distance_px_increases_with_power():
	assert_gt(HeldItemThrow.throw_distance_px(1.0), HeldItemThrow.throw_distance_px(0.1))


func test_throw_distance_px_is_never_negative():
	assert_gte(HeldItemThrow.throw_distance_px(0.0), 0.0)


## A heavier stone thrown at the same power should still deliver more
## momentum on impact -- momentum, not distance, is where mass matters (see
## the module's own doc comment on this judgment call).
func test_a_heavier_stone_delivers_more_impact_momentum_at_the_same_power():
	var throwable := Throwable.new()
	var light_momentum := throwable.impact_knockback(0.05, HeldItemThrow.release_speed_mps(0.5))
	var heavy_momentum := throwable.impact_knockback(2.0, HeldItemThrow.release_speed_mps(0.5))
	assert_gt(heavy_momentum, light_momentum)
