extends RefCounted

## Pure motion math for a leaf/blossom currently floating on a river surface
## (see docs/concept/leaf_litter.md's "Floating on water" section).
## LeafLitterField.advance() calls velocity_px_s every frame for any leaf its
## injected current probe reports real speed at -- a genuinely continuous
## per-frame integrator, deliberately NOT the same mechanism as this
## codebase's throttled, discrete ground-wind-relocation model
## (WindDispersal.leaf_ground_drift): a leaf gliding smoothly downstream
## every frame and a leaf occasionally hopping every couple of seconds are
## different enough MOTIONS that forcing one mechanism to serve both would
## read as the leaf fighting itself.

const RiverFlowShader = preload("res://src/rendering/river_flow_shader.gd")

## A floating leaf still catches SOME wind off the water's own surface, but
## nowhere near as much as one tumbling loose on dry ground -- water's own
## adhesion (surface tension against a wet leaf) resists a gust far more
## than blade-to-blade grass friction resists a dry one. Expressed relative
## to the water's OWN visible speed at the leaf's exact position (rather
## than a separate flat px/s constant) so wind's relative influence tracks
## whatever that reach's current happens to be, and automatically stays in
## proportion if the underlying river-speed tuning (RiverFlowShader.
## DRIFT_PX_PER_MPS etc.) is ever retuned -- at this fraction, even a full
## gale (wind_strength == 1.0) blowing exactly downstream contributes at
## most a fifth of that same frame's current-driven motion, comfortably
## secondary to it, and a full gale blowing exactly upstream can slow the
## leaf but never reverse or outrun the current.
const WATER_WIND_DAMPING := 0.2


## The full velocity (world px/s) a floating leaf/blossom moves at this
## frame: the water's own current (the dominant, and with everything else
## at zero the ONLY, term -- this alone IS "flow at the same speed"), a
## damped push from the day's ambient wind (see WATER_WIND_DAMPING), and
## turbulence from any nearby wader/fish (see turbulence_velocity_px_s).
## `current_direction`/`current_speed_m_s` and `wind_direction`/
## `wind_strength` share EarthChunkManager.river_current_at_global's and
## LeafLitterField.set_wind's own shapes exactly -- this never reads either
## itself, both are handed in already resolved for the leaf's own position.
static func velocity_px_s(
	current_direction: Vector2, current_speed_m_s: float,
	wind_direction: Vector2, wind_strength: float,
	wader_positions: PackedVector2Array, leaf_position: Vector2
) -> Vector2:
	var surface_speed := RiverFlowShader.surface_px_per_s(current_speed_m_s)
	var current_velocity := current_direction * surface_speed
	var wind_velocity := wind_direction * (clampf(wind_strength, 0.0, 1.0) * WATER_WIND_DAMPING * surface_speed)
	var turbulence := turbulence_velocity_px_s(leaf_position, wader_positions, current_direction)
	return current_velocity + wind_velocity + turbulence


## The sideways push (world px/s) on a leaf at `leaf_position` from every
## wader/fish in `wader_positions`, summed. Reuses RiverFlowShader.
## obstacle_lateral_shift_px directly -- the SAME pure math the visual
## current-line art already bends around a wading player/creature/fish
## (WADER_RADIUS_PX/WADER_REACH_PX/WADER_WAKE_TRAIL included) -- so a real
## leaf's own wobble near a wader visually agrees with how the water's
## surface art bends there, rather than inventing a second, disagreeing
## obstacle shape. Its raw "px of lateral shift" is reinterpreted here as a
## px/s VELOCITY rather than a one-shot offset: the source function was
## never specified as either (the shader re-samples it fresh, purely
## spatially, every frame), and treating it as a continuous push is what
## lets a leaf drift smoothly past a wader instead of popping to a new spot.
## Zero beyond WADER_REACH_PX of every wader (obstacle_lateral_shift_px's own
## floor), so summing the whole (small, capped) wader list needs no distance
## pre-filter here.
static func turbulence_velocity_px_s(
	leaf_position: Vector2, wader_positions: PackedVector2Array, flow_direction: Vector2
) -> Vector2:
	if flow_direction.is_zero_approx():
		return Vector2.ZERO
	var perp := Vector2(-flow_direction.y, flow_direction.x)
	var total := Vector2.ZERO
	for wader_position in wader_positions:
		var offset: Vector2 = leaf_position - wader_position
		var shift := RiverFlowShader.obstacle_lateral_shift_px(
			offset, perp,
			RiverFlowShader.WADER_RADIUS_PX, RiverFlowShader.WADER_REACH_PX, RiverFlowShader.WADER_WAKE_TRAIL
		)
		total += perp * shift
	return total
