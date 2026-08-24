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

		COLOR = vec4(0.0, 0.0, 0.0, (1.0 - illumination) * max_shadow_alpha);
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
	return (1.0 - illumination) * MAX_SHADOW_ALPHA
