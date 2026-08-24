extends GutTest

## Pure motion/timing math for the wild-crop pull animation (see
## WildCropMarker, docs/concept/wild_crops.md) -- the same "runtime tween
## over static parts, driven by a pure function of elapsed time" idiom
## Knockback.step already established, so the curve itself is headlessly
## testable instead of living inside an opaque Godot Tween.

const CropPull = preload("res://src/gameplay/crop_pull.gd")


func test_progress_starts_at_zero():
	assert_eq(CropPull.progress_at(0.0), 0.0)


func test_progress_reaches_one_at_duration():
	assert_almost_eq(CropPull.progress_at(CropPull.DURATION_SECONDS), 1.0, 0.0001)


func test_progress_never_exceeds_one_past_duration():
	assert_almost_eq(CropPull.progress_at(CropPull.DURATION_SECONDS * 10.0), 1.0, 0.0001)


func test_progress_is_monotonically_non_decreasing():
	var previous := 0.0
	for step in 20:
		var elapsed: float = float(step) / 19.0 * CropPull.DURATION_SECONDS
		var progress := CropPull.progress_at(elapsed)
		assert_gte(progress, previous)
		previous = progress


## Ease-OUT: a real yank starts fast and settles, rather than a linear
## slide -- progress at the halfway POINT IN TIME should already be past
## the halfway point of the motion.
func test_eases_out_rather_than_linear():
	assert_gt(CropPull.progress_at(CropPull.DURATION_SECONDS * 0.5), 0.5)


func test_rise_offset_is_zero_at_the_start():
	assert_eq(CropPull.rise_offset_at(0.0), Vector2.ZERO)


func test_rise_offset_moves_upward_by_rise_px_once_complete():
	assert_almost_eq(CropPull.rise_offset_at(CropPull.DURATION_SECONDS).y, -CropPull.RISE_PX, 0.001)
	assert_eq(CropPull.rise_offset_at(CropPull.DURATION_SECONDS).x, 0.0)


func test_is_complete_true_at_and_past_duration():
	assert_false(CropPull.is_complete(CropPull.DURATION_SECONDS * 0.5))
	assert_true(CropPull.is_complete(CropPull.DURATION_SECONDS))
	assert_true(CropPull.is_complete(CropPull.DURATION_SECONDS * 2.0))
