extends SceneTree

## Dev tool: does the stroke field stay MONOTONE bank to bank, at the
## channel widths the game actually has?
##
## The strokes are contours of
##
##     s_field = frag_across * ACROSS_LINE_SCALE + (n - 0.5) * LINE_WOBBLE
##
## and the whole design rests on that being monotone across the channel:
## a monotone field's level sets are OPEN curves running along the river.
## Once it folds back, the level sets close into rings -- the "perlin noise
## cells" the shader's own comment says this replaced.
##
## test_the_channel_guide_dominates_the_wobble guards it by asserting
## ACROSS_LINE_SCALE >= LINE_WOBBLE, which compares AMPLITUDES. Monotonicity
## is about GRADIENTS, and the two terms live on completely different
## scales: across runs 0 to 1 over the channel's half width, while n runs
## 0 to 1 over one noise cell. How many noise cells fit in a half width is
## therefore the whole question -- and it is not a constant, because the
## half width comes from discharge (1 to 6 tiles).
##
##     narrow reach, 1 tile:   1 * 16 * 0.08 = 1.28 noise cells
##     the test's fixture:                     2.56
##     typical reach, 2.6:     2.6 * 16 * 0.08 = 3.33
##     widest reach, 6 tiles:  6 * 16 * 0.08 = 7.68
##
## The wider the water, the more the noise oscillates across it and the
## worse the folding -- which is what "only around bends and where the
## water is deeper at the edge" describes.
##
## Usage: godot --headless --path . -s tools/probe_monotone.gd

const RiverFlowShader = preload("res://src/rendering/river_flow_shader.gd")


func _initialize() -> void:
	print("ACROSS_LINE_SCALE %.2f, LINE_WOBBLE %.2f, NOISE_SCALE %.3f, TILE_PX %.0f\n" % [
		RiverFlowShader.ACROSS_LINE_SCALE, RiverFlowShader.LINE_WOBBLE,
		RiverFlowShader.NOISE_SCALE, RiverFlowShader.TILE_PX
	])
	print("half width   noise cells   across-steps folding back   verdict")
	for half_tiles in [1.0, 1.6, 2.0, 2.6, 3.5, 4.5, 6.0]:
		var cells: float = half_tiles * RiverFlowShader.TILE_PX * RiverFlowShader.NOISE_SCALE
		var rate := _violation_rate(cells)
		var verdict := "open lines"
		if rate >= 0.15:
			verdict = "CELLS -- past what the test allows"
		elif rate >= 0.08:
			verdict = "folding"
		print("%6.1f tiles %10.2f %20.1f%%        %s" % [
			half_tiles, cells, rate * 100.0, verdict
		])
	print("")
	print("The test fixture walks across * 2.56 -- a 2.0-tile half width.")
	print("Anything wider than that is never exercised, and the map's own")
	print("reaches go to 6.")
	quit()


## The fraction of bank-to-bank steps where the stroke field falls instead
## of rising -- the same measurement test_the_stroke_field_is_monotone_
## across_with_rare_pinches makes, but at a chosen channel width.
static func _violation_rate(half_width_cells: float) -> float:
	var violations := 0
	var steps := 0
	for column in 48:
		var x := float(column) * 3.7
		var previous := -99.0
		for row in 160:
			var across := -1.0 + float(row) / 159.0 * 2.0
			var n: float = RiverFlowShader.animated_field_value(
				x, across * half_width_cells, Vector2(1, 0), 0.9
			)
			var bend: float = RiverFlowShader.bend_displacement(
				x * RiverFlowShader.EDDY_SCALE, across * half_width_cells * RiverFlowShader.EDDY_SCALE
			)
			var s_value: float = RiverFlowShader.stroke_field(across, n, half_width_cells, bend)
			if previous > -99.0:
				steps += 1
				if s_value <= previous:
					violations += 1
			previous = s_value
	return float(violations) / float(steps)
