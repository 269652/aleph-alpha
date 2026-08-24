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


# -- root_reveal_rect / root_reveal_offset ------------------------------
#
# Reported live: "carrots/potatoes render a huge blob behind the leaves."
# The root's crown (canvas y=0, where it attaches to the leaves) was
# shifted upward by the FULL revealed height every frame (offset.y =
# -revealed_height), so at high progress the crown climbed far above the
# leaf cluster instead of staying anchored where the leaves meet the
# ground -- a real pulled root should hang BELOW the leaves it's still
# attached to, not drift away from them.

func test_root_reveal_rect_is_empty_at_zero_progress():
	var canvas := Vector2i(40, 56)
	assert_eq(CropPull.root_reveal_rect(canvas, 0.0), Rect2(Vector2.ZERO, Vector2(40, 0)))


func test_root_reveal_rect_covers_the_whole_canvas_at_full_progress():
	var canvas := Vector2i(40, 56)
	assert_eq(CropPull.root_reveal_rect(canvas, 1.0), Rect2(Vector2.ZERO, Vector2(40, 56)))


func test_root_reveal_rect_grows_from_the_top_down():
	var canvas := Vector2i(40, 56)
	var rect := CropPull.root_reveal_rect(canvas, 0.5)
	assert_eq(rect.position, Vector2.ZERO)
	assert_almost_eq(rect.size.y, 28.0, 0.001)


## The crown's own drawn position must NOT depend on progress -- the exact
## bug: an offset that grows with revealed height pushes the crown further
## from the leaves the more of the root is revealed, rather than keeping
## it anchored where the leaves are.
func test_root_reveal_offset_does_not_depend_on_progress():
	var canvas := Vector2i(40, 56)
	var offset_at_start := CropPull.root_reveal_offset(canvas)
	assert_eq(offset_at_start.y, 0.0)
	# There is deliberately no `progress` parameter to root_reveal_offset --
	# its only job is horizontal centering, pinned once, not recomputed
	# every frame the way the buggy version's vertical shift was.
	assert_eq(offset_at_start.x, -20.0)
