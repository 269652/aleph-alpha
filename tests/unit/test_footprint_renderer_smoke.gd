extends GutTest

## A live-render smoke check for FootprintRenderer's own actual
## per-instance transform math (position/rotation/mirror) -- everything
## else about this renderer (multimesh creation, grouping by surface,
## fallback, refilling) already has dedicated headless-safe coverage in
## test_footprint_renderer.gd; this test needs a REAL GPU readback
## instead, since MultiMesh.get_instance_transform_2d does not round-trip
## under --headless (confirmed directly: a minimal isolated probe
## returned a zeroed transform under --headless and the correct one
## under --rendering-driver opengl3). Mirrors
## test_leaf_litter_renderer_smoke.gd's own established pattern for this
## exact limitation.
##
## Run for real with (no GPU readback under --headless):
##   <godot> --rendering-driver opengl3 -s addons/gut/gut_cmdln.gd \
##     -gconfig= -gtest=res://tests/unit/test_footprint_renderer_smoke.gd -gexit

const FootprintRenderer = preload("res://src/rendering/footprint_renderer.gd")

var renderer: FootprintRenderer
var parent: Node2D


func before_each():
	renderer = FootprintRenderer.new()
	parent = Node2D.new()
	add_child_autofree(parent)


func _print(position: Vector2, side: String, surface: String, heading: Vector2) -> Dictionary:
	return {"position": position, "side": side, "surface": surface, "heading": heading, "spawned_at": 0.0}


func _no_real_gpu() -> bool:
	if DisplayServer.get_name() != "headless":
		return false
	pending("no GPU readback under --headless; run with --rendering-driver opengl3")
	return true


func test_each_instances_position_matches_its_own_print():
	if _no_real_gpu():
		return
	var mmis := renderer.build_multimeshes(parent)
	renderer.fill(mmis, [_print(Vector2(37, -12), "right", "snow", Vector2.UP)])
	var xform: Transform2D = mmis["snow"].multimesh.get_instance_transform_2d(0)
	assert_almost_eq(xform.origin.x, 37.0, 0.01)
	assert_almost_eq(xform.origin.y, -12.0, 0.01)


## The print's own authored "forward" is Vector2.UP (see
## ProceduralFootprintSprite's own doc comment: the ball/toe sits near
## the top of the canvas) -- with that exact heading, no rotation should
## be applied at all.
func test_walking_up_applies_no_rotation():
	if _no_real_gpu():
		return
	var mmis := renderer.build_multimeshes(parent)
	renderer.fill(mmis, [_print(Vector2.ZERO, "right", "snow", Vector2.UP)])
	var xform: Transform2D = mmis["snow"].multimesh.get_instance_transform_2d(0)
	var toe_direction := xform.basis_xform(Vector2.UP).normalized()
	assert_almost_eq(toe_direction.x, 0.0, 0.01)
	assert_almost_eq(toe_direction.y, -1.0, 0.01)


## A print's own toe should point along whatever real heading it was
## stamped with, whichever direction that is -- not just the special
## Vector2.UP case above.
func test_the_toe_points_along_the_real_heading_it_was_stamped_with():
	if _no_real_gpu():
		return
	var mmis := renderer.build_multimeshes(parent)
	renderer.fill(mmis, [_print(Vector2.ZERO, "right", "snow", Vector2.RIGHT)])
	var xform: Transform2D = mmis["snow"].multimesh.get_instance_transform_2d(0)
	var toe_direction := xform.basis_xform(Vector2.UP).normalized()
	assert_almost_eq(toe_direction.x, 1.0, 0.01)
	assert_almost_eq(toe_direction.y, 0.0, 0.01)


## "Left" and "right" are the SAME source shape, mirrored -- see
## ProceduralFootprintSprite's own doc comment. A mirrored transform's
## basis has a negative determinant; an unmirrored one's is positive.
func test_a_left_print_is_mirrored_relative_to_a_right_one():
	if _no_real_gpu():
		return
	var mmis := renderer.build_multimeshes(parent)
	renderer.fill(mmis, [
		_print(Vector2.ZERO, "right", "snow", Vector2.UP),
		_print(Vector2.ZERO, "left", "snow", Vector2.UP),
	])
	var right_xform: Transform2D = mmis["snow"].multimesh.get_instance_transform_2d(0)
	var left_xform: Transform2D = mmis["snow"].multimesh.get_instance_transform_2d(1)
	assert_gt(right_xform.determinant(), 0.0, "an unmirrored print's transform should have a positive determinant")
	assert_lt(left_xform.determinant(), 0.0, "a mirrored print's transform should have a negative determinant")


func test_a_zero_heading_falls_back_to_a_stable_rotation_not_nan():
	if _no_real_gpu():
		return
	var mmis := renderer.build_multimeshes(parent)
	renderer.fill(mmis, [_print(Vector2.ZERO, "right", "snow", Vector2.ZERO)])
	var xform: Transform2D = mmis["snow"].multimesh.get_instance_transform_2d(0)
	assert_false(is_nan(xform.origin.x))
	assert_false(is_nan(xform.get_rotation()))
