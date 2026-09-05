extends SceneTree

## Dev tool: checks whether newly-"caught" snow lattice sites (see
## SnowBombShader.site_has_caught) cluster together spatially at a single
## depth step, or scatter independently.
##
## Built for a reported complaint: "snow grows by some sort of line scan...
## it should crossfade random and uniformly." The hypothesis this checks is
## a POPPING-IN front -- sites near each other catching within the same
## depth step more than chance would predict. It did NOT hold up (see
## docs/progress.md, 2026-09-05): the ratios below sit at or above 1.0 at
## every depth step, meaning newly-caught sites do not cluster more than a
## uniform-random scatter would. The real cause turned out to be a
## different statistic entirely -- how much the field's own local coverage
## FRACTION varies across a single screen's worth of view, not whether
## individual pop-ins cluster -- see probe_onset_drift_scale.gd, which
## found and this codebase's fix (ONSET_DRIFT_TILES 12 -> 48) addressed.
##
## Kept anyway: this is still the right tool for the NEXT time a "sites pop
## in together" hypothesis needs checking, for this shader or any future one
## built the same way.
##
## Metric: mean nearest-OTHER-newly-caught-site distance, compared to the
## expected mean nearest-neighbour distance for the same number of points
## scattered uniform-randomly over the same area (the standard Clark-Evans
## estimate, 1 / (2*sqrt(density)) for a 2D Poisson process). Ratio << 1
## means newly-caught sites cluster together (a visible front); ratio ~= 1
## means they scatter independently.
##
## Headless-safe: only calls the CPU-mirror statics (lying_at,
## site_has_caught), no GPU/material/viewport involved.
##
## Usage: godot --headless --path . -s tools/probe_snow_onset_pattern.gd -- [area_tiles]

const SnowBombShader = preload("res://src/rendering/snow_bomb_shader.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const DEPTH_STEPS := [0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.40, 0.55, 0.75, 1.0]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var area_tiles := int(args[0]) if args.size() > 0 else 96  # ~a large on-screen area

	var previous_caught: Array = []
	previous_caught.resize(area_tiles * area_tiles)
	previous_caught.fill(false)

	for depth in DEPTH_STEPS:
		var newly_caught_positions: Array[Vector2i] = []
		var caught_count := 0
		for sy in area_tiles:
			for sx in area_tiles:
				var world_x := float(sx) * SnowBombShader.STAMP_LATTICE_WORLD
				var world_y := float(sy) * SnowBombShader.STAMP_LATTICE_WORLD
				var cell_x := int(floor(world_x / SnowBombShader.STAMP_LATTICE_WORLD))
				var cell_y := int(floor(world_y / SnowBombShader.STAMP_LATTICE_WORLD))
				var lying: float = SnowBombShader.lying_at(depth, world_x, world_y, 0.0)
				var caught: bool = SnowBombShader.site_has_caught(lying, cell_x, cell_y)
				var idx := sy * area_tiles + sx
				var was_caught: bool = previous_caught[idx]
				if caught:
					caught_count += 1
				if caught and not was_caught:
					newly_caught_positions.append(Vector2i(sx, sy))
				previous_caught[idx] = caught

		var mean_nn_distance := _mean_nearest_neighbor_distance(newly_caught_positions)
		var expected_random_nn := _expected_nn_distance_if_uniform_random(
			newly_caught_positions.size(), area_tiles
		)
		print(
			(
				"depth=%.2f caught=%d/%d newly_caught=%d mean_nn_dist=%.2f "
				+ "expected_if_uniform_random=%.2f ratio=%.2f"
			) % [
				depth, caught_count, area_tiles * area_tiles, newly_caught_positions.size(),
				mean_nn_distance, expected_random_nn,
				(mean_nn_distance / expected_random_nn) if expected_random_nn > 0.0 else -1.0
			]
		)
	print("")
	print("Interpretation: ratio << 1.0 means newly-caught sites cluster TOGETHER")
	print("(a visible front/band/scan); ratio ~= 1.0 means they scatter independently,")
	print("as random uniform popping should.")
	quit()


func _mean_nearest_neighbor_distance(points: Array) -> float:
	if points.size() < 2:
		return -1.0
	var total := 0.0
	for i in points.size():
		var best := INF
		var p: Vector2i = points[i]
		for j in points.size():
			if i == j:
				continue
			var q: Vector2i = points[j]
			var d := Vector2(p - q).length()
			if d < best:
				best = d
		total += best
	return total / float(points.size())


## Expected mean nearest-neighbour distance for `n` points uniform-randomly
## scattered over a `side`x`side` area -- the standard Clark-Evans estimate
## (mean NN distance for a 2D Poisson process of density n/area is
## 1 / (2*sqrt(density))).
func _expected_nn_distance_if_uniform_random(n: int, side: int) -> float:
	if n < 2:
		return -1.0
	var density := float(n) / float(side * side)
	return 1.0 / (2.0 * sqrt(density))
