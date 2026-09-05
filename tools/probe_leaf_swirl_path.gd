extends SceneTree

## Dev tool: plots the ACTUAL ground-plane path a falling/relocating leaf
## traces, sampling LeafLitterRenderer's own GDScript mirror (byte-for-byte
## the same math the GLSL vertex shader computes) at many points across one
## full transition -- reported directly: "the leaves and blossoms have a
## lot of left/right movements where they end up on the same place where
## they started and it doesn't look natural as it's a straight line ...
## move them a bit with a left right swirl / spiral motion or tumbles or
## so ... varying". Renders several different leaves' own paths side by
## side (each a different position, hence a different phase/swirl_seed) so
## the actual SHAPE -- and how much it VARIES between leaves -- can be
## judged by eye rather than assumed from the formula alone.
##
## Headless-safe: pure math against the GDScript mirror, no GPU/viewport.
## Usage: godot --headless --path . -s tools/probe_leaf_swirl_path.gd

const LeafLitterRenderer = preload("res://src/rendering/leaf_litter_renderer.gd")
const LeafLitterField = preload("res://src/world/leaf_litter_field.gd")

const OUT_DIR := "C:/Users/morrossl/AppData/Local/Temp/claude/C--Users-morrossl-Documents-Private-aleph-alpha/fdf9d3de-194d-4352-8dba-9f7af0306ad4/scratchpad/"
const SAMPLES := 240
const CANVAS := 260
const SCALE := 3.0  # world pixels -> canvas pixels, so a small path is legible


func _plot_dot(image: Image, p: Vector2, color: Color) -> void:
	var px := int(round(p.x))
	var py := int(round(p.y))
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var x := px + ox
			var y := py + oy
			if x >= 0 and x < image.get_width() and y >= 0 and y < image.get_height():
				image.set_pixel(x, y, color)


## The exact path the shader traces for one (fall_origin -> target) journey,
## reusing LeafLitterRenderer's OWN mirror functions end to end -- not a
## re-derivation that could quietly drift from what the GPU actually draws.
func _path_for(target: Vector2, fall_origin: Vector2) -> PackedVector2Array:
	var raw_offset := fall_origin - target
	var direction := raw_offset.normalized() if raw_offset.length() > 0.001 else Vector2.UP
	var perpendicular := Vector2(-direction.y, direction.x)
	var phase := LeafLitterRenderer.phase_for_position(target)
	var swirl_seed := LeafLitterRenderer.swirl_seed_for_position(target)
	var path := PackedVector2Array()
	for i in SAMPLES + 1:
		var t := float(i) / float(SAMPLES)
		var eased := LeafLitterRenderer.eased_progress(t)
		var remaining := 1.0 - eased
		var swirl := LeafLitterRenderer.instance_swirl_offset(t, phase, swirl_seed, direction, perpendicular)
		var offset := raw_offset * remaining + swirl
		path.append(target + offset)
	return path


func _render_one(target: Vector2, fall_origin: Vector2, out_name: String) -> void:
	var image := Image.create(CANVAS, CANVAS, false, Image.FORMAT_RGB8)
	image.fill(Color(0.15, 0.15, 0.17))
	var path := _path_for(target, fall_origin)
	var origin_canvas := Vector2(CANVAS / 2.0, CANVAS / 2.0)
	for i in path.size():
		var p := (path[i] - target) * SCALE + origin_canvas
		# Colour ramps from cool (start) to warm (end) along the path so
		# direction of travel is legible from a single static image.
		var t := float(i) / float(path.size() - 1)
		var color := Color(0.2 + 0.7 * t, 0.5, 0.9 - 0.7 * t)
		_plot_dot(image, p, color)
	# Mark the real logical target with a bright dot -- the path must
	# actually converge there, not just somewhere nearby.
	_plot_dot(image, origin_canvas, Color(1.0, 1.0, 0.2))
	_plot_dot(image, origin_canvas, Color(1.0, 1.0, 0.2))
	var err: Error = image.save_png(OUT_DIR + out_name)
	print("%s: saved err=%s (swirl_seed=%.3f turns=%.2f radius_frac=%.2f)" % [
		out_name, err,
		LeafLitterRenderer.swirl_seed_for_position(target),
		LeafLitterRenderer.swirl_turns_for_seed(LeafLitterRenderer.swirl_seed_for_position(target)),
		LeafLitterRenderer.swirl_radius_fraction_for_seed(LeafLitterRenderer.swirl_seed_for_position(target)),
	])


func _initialize() -> void:
	# Several different leaves (different settled positions -> different
	# phase/swirl_seed), all falling the same real distance
	# (LeafLitterField.FALL_HEIGHT, straight down) -- isolates how much the
	# PATH SHAPE varies between leaves under an otherwise-identical journey.
	for i in 6:
		var target := Vector2(1000.0 + i * 137.0, 2000.0 + i * 53.0)
		var fall_origin := target - Vector2(0.0, LeafLitterField.FALL_HEIGHT)
		_render_one(target, fall_origin, "swirl_path_fall_%d.png" % i)

	# A long, real wind-blown relocation journey (near MAX_TRANSITION_OFFSET)
	# -- the case tumble_rotation already spins hardest for; checks the
	# swirl still reads sensibly (not lost in a much bigger straight-line
	# displacement) at that scale too.
	var far_target := Vector2(3000.0, 3000.0)
	var far_origin := far_target + Vector2(LeafLitterRenderer.MAX_TRANSITION_OFFSET * 0.8, 0.0)
	_render_one(far_target, far_origin, "swirl_path_long_journey.png")

	quit()
