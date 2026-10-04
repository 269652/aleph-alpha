extends GutTest

## Pure flight math for a homing projectile cast (docs/concept/
## spell_runtime.md, "Projectile flight: a cast that truly homes") -- mirrors
## spell_targeting.gd's own pure, instance-based shape. position_after takes
## a FRESH aim point every call rather than a stored heading, which is the
## whole mechanism: recomputing from scratch each frame against wherever the
## target currently is produces a path that curves to follow it, with no
## separate steering/turn-rate model needed.

const SpellProjectileFlight = preload("res://src/gameplay/spell_projectile_flight.gd")
const SpellTargeting = preload("res://src/gameplay/spell_targeting.gd")
const SpeciesBite = preload("res://src/gameplay/species_bite.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var flight := SpellProjectileFlight.new()


func test_position_after_steps_toward_the_aim_point():
	var result := flight.position_after(Vector2.ZERO, Vector2(100, 0), 0.01)
	assert_gt(result.x, 0.0, "must have moved toward the aim point")
	assert_lt(result.x, 100.0, "must not have arrived in one small step")
	assert_almost_eq(result.y, 0.0, 0.001, "aim point is due east -- no vertical drift")


func test_position_after_moves_exactly_travel_speed_times_delta():
	var delta := 0.01
	var result := flight.position_after(Vector2.ZERO, Vector2(1000, 0), delta)
	assert_almost_eq(
		result.x, SpellProjectileFlight.TRAVEL_SPEED_PX_PER_SEC * delta, 0.01
	)


func test_position_after_snaps_exactly_to_the_aim_point_within_one_steps_reach():
	# Closer to the aim point than one frame's travel distance -- must land
	# exactly on it, never overshoot past it.
	var aim_at := Vector2(2.0, 0.0)
	var result := flight.position_after(Vector2.ZERO, aim_at, 1.0)
	assert_eq(result, aim_at)


func test_position_after_never_overshoots_even_with_a_huge_delta():
	var aim_at := Vector2(50, 50)
	var result := flight.position_after(Vector2.ZERO, aim_at, 10.0)
	assert_eq(result, aim_at, "a huge delta must still land exactly on the aim point, not beyond it")


func test_has_arrived_is_false_before_reaching_the_aim_point():
	assert_false(flight.has_arrived(Vector2(5, 0), Vector2(100, 0)))


func test_has_arrived_is_true_exactly_at_the_aim_point():
	assert_true(flight.has_arrived(Vector2(100, 0), Vector2(100, 0)))


## The homing claim itself: aiming at a DIFFERENT point on the second call
## (simulating a target that moved between frames) bends the path rather
## than continuing the first call's original heading in a straight line.
func test_homing_recomputes_heading_toward_a_moved_aim_point():
	var after_first_step := flight.position_after(Vector2.ZERO, Vector2(100, 0), 0.01)
	var straight_line_continuation := after_first_step + Vector2(
		SpellProjectileFlight.TRAVEL_SPEED_PX_PER_SEC * 0.01, 0.0
	)
	var after_target_moved := flight.position_after(after_first_step, Vector2(100, 100), 0.01)
	assert_ne(
		after_target_moved, straight_line_continuation,
		"a target that moved must bend the bolt's path, not get ignored"
	)
	assert_gt(after_target_moved.y, 0.0, "the bolt must have turned toward the target's new position")


# -- the speed itself: grounded, not eyeballed, both ends pinned -----------

## The real ceiling on "how fast could the thing this bolt is chasing be
## going" -- SpeciesBite's own fastest roster entry, already itself pinned
## faster than player sprint. A bolt slower than this could lose a fleeing
## target to raw speed, which would make "homing" a lie.
func test_travel_speed_outruns_the_fastest_creature_in_the_game():
	var fastest_creature_px_per_sec := (
		SpeciesBite.FASTEST_PURSUIT_TILES_PER_SECOND * TerrainRenderer.TILE_SIZE
	)
	assert_gt(SpellProjectileFlight.TRAVEL_SPEED_PX_PER_SEC, fastest_creature_px_per_sec)


## The other end: a bolt that technically outruns anything but takes
## forever to do it still reads as slow. Crossing the full max range must
## stay snappy -- under half of Player.ATTACK_COOLDOWN's own 0.5s pace.
func test_crossing_the_full_projectile_range_takes_well_under_the_attack_cooldown():
	var seconds_to_cross_max_range: float = (
		SpellTargeting.PROJECTILE_RANGE / SpellProjectileFlight.TRAVEL_SPEED_PX_PER_SEC
	)
	assert_lt(seconds_to_cross_max_range, 0.25)
