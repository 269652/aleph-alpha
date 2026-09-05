extends SceneTree

## The tool that found the real cause behind a reported complaint ("snow
## grows by some sort of line scan... should crossfade random and
## uniformly"), after probe_snow_onset_pattern.gd's nearest-neighbour check
## on newly-caught SITES came back inconclusive. The right statistic turned
## out to be different: not whether individual pop-ins cluster, but whether
## the LOCAL COVERAGE FRACTION varies a lot across the area a player can
## actually see at once, so that one part of the screen visibly lags
## another as depth rises.
##
## The real viewport is DisplayScaling-independent of window size by design
## (see its own doc comment): 1280x720 design resolution at TILE_SCREEN_PX=64
## is always ~20 tiles wide, ~11.25 tall, on any monitor. At the time this
## was written, ONSET_DRIFT_TILES's broad octave swung from its local min to
## its local max over just 12 tiles -- SMALLER than one screen's own width --
## so a single viewport could contain more than a full swing of the field,
## which is exactly what reads as a visible gradient/wave sweeping across
## what the player is looking at, even though the field is perfectly smooth
## and was correctly tuned (per its own doc comment) to avoid a checkerboard
## or a flat plateau. Fixed by raising ONSET_DRIFT_TILES to 48 -- see
## docs/progress.md (2026-09-05) and snow_bomb_shader.gd's own comment on
## the constant.
##
## Kept as a permanent tool for re-checking this trade-off if either number
## moves again: (a) the existing 80-tile-square spread test's own statistic
## (must stay above ONSET_VARIANCE), and (b) the onset spread visible inside
## many real viewport-sized windows scattered across a big area -- (b) is
## what actually predicts "does the player see one half of their screen
## catch up to the other as snow falls", which (a) alone does not.
##
## Headless-safe: only calls SnowBombShader.value_noise directly (no GPU).
## Run: <godot> --headless --path . -s tools/probe_onset_drift_scale.gd

const SnowBombShader = preload("res://src/rendering/snow_bomb_shader.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const DisplayScaling = preload("res://src/rendering/display_scaling.gd")

const CANDIDATES := [12.0, 24.0, 36.0, 48.0, 60.0, 80.0, 100.0]
const BROAD_VARIANCE := SnowBombShader.ONSET_BROAD_VARIANCE
const FINE_VARIANCE := SnowBombShader.ONSET_FINE_VARIANCE
const FINE_DRIFT_TILES := SnowBombShader.ONSET_FINE_DRIFT_TILES


func _initialize() -> void:
	var viewport_w := DisplayScaling.visible_tiles_across(
		DisplayScaling.DESIGN_WIDTH, DisplayScaling.DESIGN_HEIGHT
	)
	var viewport_h := DisplayScaling.visible_tiles_across(
		DisplayScaling.DESIGN_HEIGHT, DisplayScaling.DESIGN_HEIGHT
	)
	print("Real visible viewport: %.2f x %.2f tiles" % [viewport_w, viewport_h])
	print(
		"Live ONSET_DRIFT_TILES = %.1f -- marked '<== live' in the table below"
		% SnowBombShader.ONSET_DRIFT_TILES
	)
	print("")

	var candidates := CANDIDATES.duplicate()
	if not candidates.has(SnowBombShader.ONSET_DRIFT_TILES):
		candidates.append(SnowBombShader.ONSET_DRIFT_TILES)
		candidates.sort()

	for drift_tiles in candidates:
		var big_spread := _sample_spread(drift_tiles, -40, 40, -40, 40, 1)
		var viewport_spreads := []
		var rng := RandomNumberGenerator.new()
		rng.seed = 1234
		for _trial in 40:
			var ox := rng.randi_range(-2000, 2000)
			var oy := rng.randi_range(-2000, 2000)
			var vw := int(ceil(viewport_w)) + 1
			var vh := int(ceil(viewport_h)) + 1
			viewport_spreads.append(_sample_spread(drift_tiles, ox, ox + vw, oy, oy + vh, 1))
		var mean_viewport_spread := 0.0
		var worst_viewport_spread := 0.0
		for s in viewport_spreads:
			mean_viewport_spread += s
			worst_viewport_spread = maxf(worst_viewport_spread, s)
		mean_viewport_spread /= viewport_spreads.size()
		var live_marker := "  <== live" if is_equal_approx(drift_tiles, SnowBombShader.ONSET_DRIFT_TILES) else ""
		print(
			(
				"drift_tiles=%6.1f  80x80-tile spread=%.4f (needs > %.2f)  "
				+ "mean 20x11-viewport spread=%.4f  worst=%.4f%s"
			) % [
				drift_tiles, big_spread, SnowBombShader.ONSET_VARIANCE,
				mean_viewport_spread, worst_viewport_spread, live_marker
			]
		)
	print("")
	print("Interpretation: the 80x80 spread must stay comfortably above the")
	print("current ONSET_VARIANCE floor (unchanged field range, existing test).")
	print("The viewport spread is the NEW number that matters: the smaller it")
	print("gets, the less of a visible 'one side of the screen is ahead of the")
	print("other' gradient the player can see at once.")
	quit()


func _onset_with_drift(world_x: float, world_y: float, drift_tiles: float) -> float:
	var tile := float(TerrainRenderer.TILE_SIZE)
	var tile_x := world_x / tile
	var tile_y := world_y / tile
	var broad := SnowBombShader.value_noise(
		tile_x / drift_tiles + 11.7, tile_y / drift_tiles + 3.1
	)
	var fine := SnowBombShader.value_noise(
		tile_x / FINE_DRIFT_TILES + 71.3, tile_y / FINE_DRIFT_TILES + 41.9
	)
	return (
		lerpf(-BROAD_VARIANCE, BROAD_VARIANCE, broad)
		+ lerpf(-FINE_VARIANCE, FINE_VARIANCE, fine)
	)


func _sample_spread(
	drift_tiles: float, tile_x0: int, tile_x1: int, tile_y0: int, tile_y1: int, step: int
) -> float:
	var tile := float(TerrainRenderer.TILE_SIZE)
	var low := 1.0
	var high := -1.0
	var tx := tile_x0
	while tx < tile_x1:
		var ty := tile_y0
		while ty < tile_y1:
			var onset := _onset_with_drift(float(tx) * tile, float(ty) * tile, drift_tiles)
			low = minf(low, onset)
			high = maxf(high, onset)
			ty += step
		tx += step
	return high - low
