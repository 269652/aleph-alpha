extends RefCounted

## GPU relief shading: a translucent black overlay, painted over land the
## same way WaterFx is painted over ocean (see water_shader.gd), whose
## alpha rises where terrain is shadowed and falls to zero where a slope
## directly faces the real sun (see docs/concept/terrain_relief.md's
## "Hillshading" section).
##
## The overlay tile's own texture carries real per-tile slope/aspect DATA
## (see procedural_hillshade_sprite.gd), sampled here exactly the way
## water_shader.gd samples shore-distance -- this shader reads a channel,
## not art. sun_elevation_deg/sun_azimuth_deg are pushed continuously as
## the in-game clock advances (see solar_position.gd's elevation_degrees/
## azimuth_degrees, the same sun already driving day/night tinting), the
## same "live weather value pushed into a shared uniform" shape
## EarthChunkManager.set_wind_strength/set_rain already use.
##
## shadow_alpha() below is the CPU mirror of exactly what the shader's
## fragment() computes, kept in sync by hand -- the same relationship
## water_shader.gd's ripple_amplitude has to ripple_packet, and for the
## same reason: a fragment shader can't be asserted headless.

const Hillshade = preload("res://src/rendering/hillshade.gd")
const TerrainPassability = preload("res://src/gameplay/terrain_passability.gd")

const SHADER_CODE := """
shader_type canvas_item;

uniform float sun_elevation_deg = 45.0;
uniform float sun_azimuth_deg = 180.0;
uniform float max_shadow_alpha = 0.55;

void fragment() {
	// Sun below the horizon: contribute NOTHING. The existing day/night
	// CanvasModulate darkening already handles nighttime globally --
	// hillshade only expresses the RELATIVE shading a directional sun
	// creates between slopes, so it must stay silent at night rather than
	// double-darkening an already-dark scene. Godot's shader language
	// rejects an early `return` inside fragment(), so this is a branch
	// around the whole body rather than an early exit.
	if (sun_elevation_deg <= 0.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
	} else {
		// Slope in red [0,1] -> degrees, aspect in green [0,1] -> degrees
		// (see procedural_hillshade_sprite.gd's exact encoding).
		vec2 data = texture(TEXTURE, UV).rg;
		float slope_deg = data.r * 90.0;
		float aspect_deg = data.g * 360.0;

		// The same real hillshade formula as Hillshade.illumination
		// (GDScript) -- kept in sync by hand, mirrored on the CPU for
		// headless testing.
		float zenith_rad = radians(90.0 - sun_elevation_deg);
		float slope_rad = radians(slope_deg);
		float relative_azimuth_rad = radians(sun_azimuth_deg - aspect_deg);

		float illumination = cos(zenith_rad) * cos(slope_rad)
			+ sin(zenith_rad) * sin(slope_rad) * cos(relative_azimuth_rad);
		illumination = clamp(illumination, 0.0, 1.0);

		// How much of max_shadow_alpha this slope is even entitled to --
		// mirrors slope_darkening_weight (GDScript) by hand, same as the
		// illumination formula above. Ordinary ground (real-world river
		// valleys measure 1-5 degrees) must not read as a self-shadowed
		// cliff just because it faces away from a low dawn/dusk sun --
		// reported live as "near-black... diamond/blob-shaped patches...
		// on grass near a riverbank". 18.0/45.0 are
		// TerrainPassability.SOFT_THRESHOLD_DEG/HARD_THRESHOLD_DEG.
		float slope_weight = clamp((slope_deg - 18.0) / (45.0 - 18.0), 0.0, 1.0);

		COLOR = vec4(0.0, 0.0, 0.0, (1.0 - illumination) * max_shadow_alpha * slope_weight);
	}
}
"""

## Overlay opacity ceiling: high enough that a genuinely shadowed cliff
## face reads as real shade, low enough that the baked ground art beneath
## always stays visible -- the exact same "translucent, never opaque"
## bound WaterShader.WATER_ALPHA already keeps for the water overlay.
const MAX_SHADOW_ALPHA := 0.55

## Overcast-noon-ish default -- a plausible sun position for a material
## constructed before any real clock has pushed a live value in.
const DEFAULT_SUN_ELEVATION_DEG := 45.0
const DEFAULT_SUN_AZIMUTH_DEG := 180.0

var _shared_material: ShaderMaterial


func make_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("max_shadow_alpha", MAX_SHADOW_ALPHA)
	material.set_shader_parameter("sun_elevation_deg", DEFAULT_SUN_ELEVATION_DEG)
	material.set_shader_parameter("sun_azimuth_deg", DEFAULT_SUN_AZIMUTH_DEG)
	return material


func shared_material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = make_material()
	return _shared_material


## Pushes the real, live sun position (see solar_position.gd) into the
## shared material -- called as the in-game clock advances, the same
## "live value pushed into a shared uniform every tick" shape
## EarthChunkManager.set_wind_strength/set_rain already use for weather.
func set_sun_position(elevation_deg: float, azimuth_deg: float) -> void:
	var material := shared_material()
	material.set_shader_parameter("sun_elevation_deg", elevation_deg)
	material.set_shader_parameter("sun_azimuth_deg", azimuth_deg)


## How much of MAX_SHADOW_ALPHA a slope is even entitled to, regardless of
## aspect/sun angle -- ordinary ground gets NONE, no matter how directly it
## faces away from the sun.
##
## Root cause of a live report ("distinctly odd, near-black... diamond/blob-
## shaped patches lying flat on grass near a riverbank"): a headless scan of
## every curated river's REAL course (see tools/scan_riverbank_hillshade.gd)
## measured real riverbank slopes of only 1-5 degrees everywhere -- nowhere
## near a cliff -- yet Hillshade.illumination's clamp-to-zero self-shadow
## case is trivially reached by a slope that shallow whenever the sun is low
## (measured: every one of those rivers hit alpha >= 0.53, effectively the
## full 0.55 ceiling, at a sun_elevation_deg of just 1-2 -- ordinary dawn/
## dusk, not a rare or extreme sun angle). The formula was applying a genuine
## CLIFF's full darkening ceiling to plain grass merely for facing away from
## a low sun.
##
## Scaled by how far past TerrainPassability.SOFT_THRESHOLD_DEG ("ordinary
## ground -- no penalty at all", the same real-world-grounded threshold
## BiomeClassifier.SLOPE_MOUNTAIN_THRESHOLD_DEG and the river-flow shader's
## own speed mapping already reuse) a slope is, ramping to full strength at
## HARD_THRESHOLD_DEG ("genuine scrambling/technical-climbing terrain" --
## exactly where dramatic relief shading is real and expected). Not a fresh
## eyeballed cutoff: the same linear-ramp shape TerrainPassability.
## speed_multiplier already established for the identical two thresholds.
## Pinned by test_slope_darkening_weight_is_zero_on_ordinary_ground and
## siblings.
static func slope_darkening_weight(slope_deg: float) -> float:
	return clampf(
		(
			(slope_deg - TerrainPassability.SOFT_THRESHOLD_DEG)
			/ (TerrainPassability.HARD_THRESHOLD_DEG - TerrainPassability.SOFT_THRESHOLD_DEG)
		),
		0.0, 1.0
	)


## The CPU mirror of exactly what the shader's fragment() draws -- see that
## function's own comments for why night contributes zero rather than
## MAX_SHADOW_ALPHA, and Hillshade.illumination for the shared formula
## itself (reused here rather than reimplemented, so this file owns only
## the rendering-specific alpha mapping/night policy, not the physics).
static func shadow_alpha(
	slope_deg: float, aspect_deg: float, sun_elevation_deg: float, sun_azimuth_deg: float
) -> float:
	if sun_elevation_deg <= 0.0:
		return 0.0
	var illumination := Hillshade.illumination(slope_deg, aspect_deg, sun_elevation_deg, sun_azimuth_deg)
	return (1.0 - illumination) * MAX_SHADOW_ALPHA * slope_darkening_weight(slope_deg)
