extends SceneTree

## Dev tool: measures the real angular spread of WindDispersal.landing_offset
## for WEIGHT_LEAF under a strong, steady due-east wind, across many
## different seeds -- to see directly whether a leaf's own relocation
## direction stays close to the wind (smooth, continuous-reading drift) or
## scatters widely regardless of wind direction (which would read as
## "hard back and forth" between consecutive wind-triggered hops even
## though each individual hop's own tumble animation is smooth).
##
## Headless-safe: WindDispersal is pure Image-free static math, no GPU.
##
## Usage: godot --headless --path . -s tools/probe_wind_offset_spread.gd

const WindDispersal = preload("res://src/world/wind_dispersal.gd")

const SAMPLES := 30


func _initialize() -> void:
	var angles: Array = []
	var lengths: Array = []
	for seed_value in SAMPLES:
		var offset := WindDispersal.landing_offset(
			seed_value * 9973, WindDispersal.WEIGHT_LEAF, Vector2.RIGHT, 1.0
		)
		var angle_deg := rad_to_deg(offset.angle())
		angles.append(angle_deg)
		lengths.append(offset.length())
		print("seed=%d angle_from_wind=%.1f length=%.1f" % [seed_value, angle_deg, offset.length()])

	var within_30 := 0
	var within_60 := 0
	var backwards := 0
	for angle in angles:
		var a: float = absf(angle)
		if a <= 30.0:
			within_30 += 1
		if a <= 60.0:
			within_60 += 1
		if a > 90.0:
			backwards += 1
	print("")
	print(
		"of %d samples: within 30 deg of wind=%d, within 60 deg=%d, actually BACKWARDS (>90 deg off)=%d"
		% [SAMPLES, within_30, within_60, backwards]
	)
	lengths.sort()
	print("length range: min=%.1f median=%.1f max=%.1f" % [lengths[0], lengths[lengths.size() / 2], lengths[-1]])
	quit()
