extends GutTest

## A butterfly/songbird ambient wildlife marker -- pure decorative presence
## (see docs/concept/ecosystem_dynamics.md's Species roster), no
## needs/perception/behavior AI and no population simulation, unlike
## CreatureMarker/FishMarker.

const AmbientFlyerMarker = preload("res://src/rendering/ambient_flyer_marker.gd")
const AmbientFlyerMovement = preload("res://src/rendering/ambient_flyer_movement.gd")

var marker: AmbientFlyerMarker


func before_each():
	marker = AmbientFlyerMarker.new()


func after_each():
	marker.free()


func test_does_nothing_without_setup():
	marker.home = Vector2(10, 10)
	marker.position = Vector2(10, 10)
	marker._process(1.0)
	assert_eq(marker.position, Vector2(10, 10))


func test_moves_when_set_up_with_a_movement_model():
	marker.home = Vector2.ZERO
	marker.position = Vector2.ZERO
	marker.wander_seed = 7
	marker.setup(AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	marker._process(1.0)
	assert_ne(marker.position, Vector2.ZERO)


## See World's mouse-hover animal-name tooltip (docs feature request).
func test_get_display_name_capitalizes_the_species():
	marker.species = "monarch"
	assert_eq(marker.get_display_name(), "Monarch")


## This used to assert `rotation == moved.angle()`, which is exactly the
## bug: a flyer whose wander reversed span 180 degrees and rendered
## upside-down. Facing is now a mirror, so the claim is that travelling
## left mirrors the sprite and travelling right does not.
func test_faces_the_direction_it_is_moving():
	marker.home = Vector2.ZERO
	marker.position = Vector2.ZERO
	marker.wander_seed = 7
	marker.setup(AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	var before := marker.position
	marker._process(1.0)
	var moved := marker.position - before
	# Facing lags travel on purpose (see FACING_TURN_DELAY): a real bird
	# banks slowly while its wings beat fast, and mirroring the instant the
	# wander's horizontal component crosses zero made the sprite strobe and
	# read as two overlapping birds. So the facing is asserted only after
	# the flyer has held that heading past the turn delay.
	if absf(moved.x) >= marker.FACING_DEADZONE:
		for i in 30:
			marker.face_travel(moved, 0.1)
		assert_eq(marker.flip_h, moved.x < 0.0)
	assert_almost_eq(marker.rotation, 0.0, 0.0001, "a flyer must never spin")


# -- facing: flip, never spin ----------------------------------------------
#
# The marker used to set `rotation = moved.angle()`, so a flyer whose wander
# reversed direction span a full 180 degrees and rendered upside-down --
# reported as "birds appear doubled as they rotate 180 degree with every
# wing flap". A top-down sprite drawn facing right should MIRROR to face
# left, not rotate.

func test_a_flyer_never_rotates():
	for i in 40:
		marker._process(0.1)
		assert_almost_eq(marker.rotation, 0.0, 0.0001, "a flyer must never spin")


func test_a_flyer_mirrors_to_face_the_way_it_travels():
	marker.face_travel(Vector2(-1, 0))
	assert_true(marker.flip_h, "moving left should mirror the sprite")
	marker.face_travel(Vector2(1, 0))
	assert_false(marker.flip_h, "moving right should face the sprite forward")


## Near-vertical drift must not flip the sprite back and forth: tiny
## horizontal jitter either side of zero would strobe the mirror.
func test_near_vertical_travel_keeps_the_current_facing():
	marker.face_travel(Vector2(-1, 0))
	marker.face_travel(Vector2(0.001, 1.0))
	assert_true(marker.flip_h, "a hair of horizontal drift should not flip the bird")


## The wings must actually beat -- and far faster than the bird turns.
func test_wings_cycle_through_their_frames_while_flying():
	marker.flap_frames = [ImageTexture.new(), ImageTexture.new(), ImageTexture.new()]
	marker.home = Vector2.ZERO
	marker.position = Vector2.ZERO
	marker.wander_seed = 3
	marker.setup(AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	var seen := {}
	for i in 20:
		marker._process(marker.FLAP_SECONDS_PER_FRAME)
		seen[marker.texture] = true
	assert_gt(seen.size(), 1, "the wing frames should cycle")


func test_wings_beat_much_faster_than_the_bird_turns():
	assert_lt(
		marker.FLAP_SECONDS_PER_FRAME * 4.0, marker.FACING_TURN_DELAY,
		"a full wing-beat should be far quicker than a change of heading"
	)
