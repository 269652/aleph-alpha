extends SceneTree

## Dev tool: reproduces the reported "hard back-forth motion" in wind-blown
## leaf litter by simulating many real WIND_DISPERSAL_INTERVAL ticks against
## a real LeafLitterField and logging every actual relocation -- position,
## offset vector, offset angle relative to the wind, and the gap in real
## seconds since the leaf started (or last) transitioning -- to see the true
## shape of the motion rather than reasoning about it from the formula alone.
##
## Headless-safe: LeafLitterField/WindDispersal are pure data/CPU, no GPU.
##
## Usage: godot --headless --path . -s tools/probe_wind_leaf_path.gd

const LeafLitterField = preload("res://src/world/leaf_litter_field.gd")

const TICKS := 60


func _initialize() -> void:
	var field := LeafLitterField.new()
	field.add_leaf(Vector2(1000, 1000), "cherry", "autumn", 0.0)
	# Strong, steady wind blowing due east, so any deviation from "roughly
	# east, drifting further east over time" is the scatter term, not the
	# wind itself changing.
	field.set_wind(Vector2.RIGHT, 1.0)

	# Let the fall-in transition settle first.
	field.advance(LeafLitterField.TRANSITION_DURATION + 0.1, LeafLitterField.TRANSITION_DURATION + 0.1)

	var now := LeafLitterField.TRANSITION_DURATION + 0.1
	var last_position: Vector2 = field.leaves()[0].position
	var last_relocation_time := now
	print("start position: %s" % last_position)
	for i in TICKS:
		now += LeafLitterField.WIND_DISPERSAL_INTERVAL
		field.advance(LeafLitterField.WIND_DISPERSAL_INTERVAL, now)
		var leaf: Dictionary = field.leaves()[0]
		if leaf.position != last_position:
			var offset: Vector2 = leaf.position - last_position
			var angle_deg := rad_to_deg(offset.angle())
			var gap := now - last_relocation_time
			print(
				"tick=%d t=%.1fs gap_since_last_move=%.1fs offset=%s angle_from_east=%.1f length=%.1f"
				% [i, now, gap, offset, angle_deg, offset.length()]
			)
			last_position = leaf.position
			last_relocation_time = now
	print("end position: %s (net displacement: %s)" % [last_position, last_position - Vector2(1000, 1000)])
	quit()
