extends SceneTree

## Dev tool: plots the ACTUAL ground-plane path a falling/relocating leaf
## traces, sampling LeafLitterRenderer's own GDScript mirror (byte-for-byte
## the same math the GLSL vertex shader computes) at many points across one
## full transition. Two rounds of report on this same motion: first "the
## leaves and blossoms have a lot of left/right movements where they end up
## on the same place where they started ... move them a bit with a left
## right swirl / spiral motion or tumbles or so ... varying" (answered with
## a 2D curl, see git history), then immediately "now they ONLY swirl ...
## restore the behavior from before which looked much better and natural,
## just the left right jitter should be eliminated and changed into a
## random motion instead". This renders several different leaves' own
## paths side by side (each a different position, hence a different
## phase/wander_seed) so the actual SHAPE -- back to the original straight-
## line-plus-perpendicular-sway structure, but no longer sharing one fixed
## frequency ratio across every leaf -- can be judged by eye, not assumed
## from the formula alone.
##
## Headless-safe: pure math against the GDScript mirror, no GPU/viewport.
## Usage: godot --headless --path . -s tools/probe_leaf_wander_path.gd

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
	var wander_seed := LeafLitterRenderer.wander_seed_for_position(target)
	var path := PackedVector2Array()
	for i in SAMPLES + 1:
		var t := float(i) / float(SAMPLES)
		var eased := LeafLitterRenderer.eased_progress(t)
		var remaining := 1.0 - eased
		var wander_mag := LeafLitterRenderer.transition_wander_world(t, wander_seed)
		var offset := raw_offset * remaining + perpendicular * wander_mag
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
	var wander_seed := LeafLitterRenderer.wander_seed_for_position(target)
	var freqs := []
	for term_index in LeafLitterRenderer.WANDER_TERM_COUNT:
		freqs.append(LeafLitterRenderer.wander_frequency_for_seed(wander_seed, term_index))
	print("%s: saved err=%s (wander_seed=%.3f freqs=%s)" % [out_name, err, wander_seed, freqs])


func _initialize() -> void:
	# Several different leaves (different settled positions -> different
	# phase/wander_seed), all falling the same real distance
	# (LeafLitterField.FALL_HEIGHT, straight down) -- isolates how much the
	# PATH SHAPE varies between leaves under an otherwise-identical journey.
	for i in 6:
		var target := Vector2(1000.0 + i * 137.0, 2000.0 + i * 53.0)
		var fall_origin := target - Vector2(0.0, LeafLitterField.FALL_HEIGHT)
		_render_one(target, fall_origin, "wander_path_fall_%d.png" % i)

	# A long, real wind-blown relocation journey (near MAX_TRANSITION_OFFSET)
	# -- checks the wander still reads sensibly (a small perturbation, not
	# lost or exaggerated) at that much larger scale too.
	var far_target := Vector2(3000.0, 3000.0)
	var far_origin := far_target + Vector2(LeafLitterRenderer.MAX_TRANSITION_OFFSET * 0.8, 0.0)
	_render_one(far_target, far_origin, "wander_path_long_journey.png")

	quit()
