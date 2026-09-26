extends GutTest

## Screen shake for a blow the player just landed (docs/concept/
## feedback.md's own shape, extended: HitFlash/HurtFlash answer "something
## was hit"/"you were hit", this answers "you hit something HARD"). Pure:
## a RefCounted of static functions over pinned constants -- Player owns
## the Camera2D and the per-frame clock, this owns the rule (mirrors
## HitFlash's exact split, see test_hit_flash.gd's own shape).

const CameraShake = preload("res://src/rendering/camera_shake.gd")


func test_offset_is_zero_before_any_time_has_elapsed_at_zero_severity():
	assert_eq(CameraShake.offset_at(0.0, 0.0), Vector2.ZERO)


func test_offset_is_zero_once_the_shake_has_fully_decayed():
	assert_eq(CameraShake.offset_at(CameraShake.SECONDS, 1.0), Vector2.ZERO)
	assert_eq(CameraShake.offset_at(CameraShake.SECONDS + 1.0, 1.0), Vector2.ZERO)


func test_offset_is_zero_for_negative_elapsed_time():
	assert_eq(CameraShake.offset_at(-0.01, 1.0), Vector2.ZERO)


func test_a_harder_hit_shakes_more_than_a_softer_one_at_the_same_instant():
	var soft := CameraShake.offset_at(0.01, 0.2)
	var hard := CameraShake.offset_at(0.01, 1.0)
	assert_gt(hard.length(), soft.length())


func test_severity_is_clamped_to_one_even_if_a_caller_passes_more():
	var capped := CameraShake.offset_at(0.01, 1.0)
	var overdriven := CameraShake.offset_at(0.01, 5.0)
	assert_almost_eq(capped.length(), overdriven.length(), 0.001)


func test_offset_decays_toward_zero_as_time_passes():
	var early := CameraShake.offset_at(0.01, 1.0)
	var late := CameraShake.offset_at(CameraShake.SECONDS * 0.9, 1.0)
	assert_gt(early.length(), late.length())


## Deterministic in elapsed time, not seeded randomness: the same inputs
## always give the same offset, so a caller (and this test) never has to
## stub an RNG.
func test_offset_is_deterministic_for_the_same_inputs():
	assert_eq(CameraShake.offset_at(0.05, 0.7), CameraShake.offset_at(0.05, 0.7))
