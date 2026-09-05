extends SceneTree

## Dev tool: does the surface's DOMAIN WARP fold?
##
## river_flow_shader draws its strokes as contours of a noise field sampled
## at a warped coordinate:
##
##     vec2 q = p + flow_perp * bend;
##
## That is a domain warp. A warp is invertible only while its Jacobian
## stays positive; once d(q)/d(p) crosses zero the map FOLDS, two different
## places map to the same sample, and the contours of the result develop
## cusps -- sharp V kinks. Which is what a zigzag is.
##
## Crucially a fold is invisible to every fix aimed at the FIELD: the field
## can be perfectly smooth and the warp still folds it. That matches an
## artefact which did not move when the across map, the width map, the
## smear direction and the obstacle push were all corrected.
##
## The shader's own comment records the sibling failure: rotating the smear
## by this same eddy field "sawed every stroke into a regular zig-zag with
## the eddy noise's own period".
##
## test_the_bend_never_folds_the_surface_over_itself samples 40 x 160
## points on a coarse grid. This sweeps far denser and reports the actual
## minimum of the derivative, so "does not fold on the points we happened
## to check" and "cannot fold" stop being the same answer.
##
## Usage: godot --headless --path . -s tools/probe_fold.gd [-- turbulence]

const RiverFlowShader = preload("res://src/rendering/river_flow_shader.gd")

## Step for the numeric derivative, in the same units warped_across takes.
const H := 0.002


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var override := float(args[0]) if args.size() > 0 else -1.0

	print("EDDY_SCALE          %.3f" % RiverFlowShader.EDDY_SCALE)
	print("TURBULENCE_STRENGTH %.3f" % RiverFlowShader.TURBULENCE_STRENGTH)
	print("EDDY_DETAIL_WEIGHT  %.3f" % RiverFlowShader.EDDY_DETAIL_WEIGHT)
	if override > 0.0:
		print("(scaling the bend by %.3f / %.3f to model a different strength)" % [
			override, RiverFlowShader.TURBULENCE_STRENGTH
		])
	print("")

	var scale := 1.0 if override <= 0.0 else override / RiverFlowShader.TURBULENCE_STRENGTH
	var worst := INF
	var worst_at := Vector2.ZERO
	var folds := 0
	var samples := 0
	# A wide, dense sweep -- the eddy field repeats on its own scale, so a
	# few hundred units in each axis covers many whole features.
	for i in 400:
		var along := float(i) * 0.31
		for j in 600:
			var across := float(j) * 0.05
			var derivative := _derivative(along, across, scale)
			samples += 1
			if derivative < worst:
				worst = derivative
				worst_at = Vector2(along, across)
			if derivative <= 0.0:
				folds += 1

	print("samples: %d" % samples)
	print("minimum d(warped_across)/d(across): %+.4f at %s" % [worst, worst_at])
	print("samples where it is <= 0 (folded): %d (%.3f%%)" % [
		folds, 100.0 * float(folds) / float(samples)
	])
	print("")
	if worst <= 0.0:
		print("FOLDS. The warp is not invertible everywhere, so the contours it")
		print("produces have cusps no amount of smoothing the field can remove.")
	elif worst < 0.25:
		print("Does not fold, but the margin is %.3f -- contours still compress" % worst)
		print("hard where the derivative dips, which reads as a kink.")
	else:
		print("Comfortable margin: the warp cannot fold or pinch.")
	quit()


## d(p + bend)/d(p) along the warped axis, by central difference on the
## same CPU mirror the fold test uses.
static func _derivative(along: float, across: float, scale: float) -> float:
	var high := _warped(along, across + H, scale)
	var low := _warped(along, across - H, scale)
	return (high - low) / (2.0 * H)


## RiverFlowShader.warped_across, with the bend scaled so a different
## turbulence strength can be modelled without editing the constant.
static func _warped(along: float, across: float, scale: float) -> float:
	var displacement := RiverFlowShader.bend_displacement(
		along * RiverFlowShader.EDDY_SCALE, across * RiverFlowShader.EDDY_SCALE
	)
	return across + displacement * scale
