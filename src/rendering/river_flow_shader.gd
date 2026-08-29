extends RefCounted

## GPU river flow: a translucent, directional streak pattern scrolling
## downstream over river cells only -- rivers previously looked exactly
## like still ocean water (reported: "rivers should flow"). Layered the
## same way hillshade is layered over land (see hillshade_shader.gd): the
## base water overlay (water_shader.gd, ocean's shore-blend/ripple physics)
## is completely untouched, this is purely an ADDITIONAL sparse overlay
## painted only where EarthChunkGenerator.is_river_at_global is true (see
## EarthChunkManager._paint_river_flow_overlay).
##
## Flow DIRECTION is real: the same downhill direction
## TerrainRelief.aspect_degrees_from_gradient already computes for
## hillshading -- "the direction water would actually flow", by that
## function's own doc comment -- which is exactly
## docs/concept/electromagnetism.md's own long-standing, previously-
## unvalidated water-wheel proposal ("flow speed is derived from the water
## tile's own local elevation gradient"), now actually built (for direction;
## see below for why speed stays uniform).
##
## Flow SPEED is deliberately uniform (FLOW_SPEED below), not derived from
## the real gradient magnitude: every curated/procedural river in this pass
## carries the same nominal depth (river_depth.gd) rather than a real
## per-river discharge/velocity figure, so a magnitude-accurate flow speed
## would be precision this system doesn't actually have data for. A real
## flow-RATE model is a further, not-attempted refinement.
##
## The overlay tile's own texture carries real per-tile flow-direction DATA
## (see procedural_river_flow_sprite.gd), sampled here exactly the way
## hillshade_shader.gd samples slope/aspect -- this shader reads a channel,
## not art.
##
## streak_intensity() below is the CPU mirror of exactly what the shader's
## fragment() computes, kept in sync by hand -- the same relationship
## water_shader.gd's ripple_amplitude has to ripple_packet, and for the
## same reason: a fragment shader can't be asserted headless.

const SHADER_CODE := """
shader_type canvas_item;

uniform float flow_speed = 18.0;
uniform float streak_frequency = 0.12;
uniform float streak_sharpness = 4.0;
uniform float streak_alpha = 0.35;
uniform vec3 streak_color : source_color = vec3(0.75, 0.88, 1.0);

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// Compass bearing (0=north, 90=east, clockwise), red channel [0,1] ->
	// [0,360) degrees -- the same encoding/convention hillshade_shader.gd's
	// aspect channel already uses (see
	// TerrainRelief.aspect_degrees_from_gradient).
	float angle_deg = texture(TEXTURE, UV).r * 360.0;
	float angle_rad = radians(angle_deg);
	// Godot 2D: +X east, +Y DOWN (screen space) -- "north" is -Y.
	vec2 flow_dir = vec2(sin(angle_rad), -cos(angle_rad));

	float along = dot(world_pos, flow_dir);
	float phase = along * streak_frequency - TIME * flow_speed * streak_frequency;
	// A clamped sine raised to a power: cheap, crisp, periodic bright bands
	// (streaks) separated by near-zero troughs -- not constant brightness,
	// which would just read as a flat tint, not motion.
	float wave = sin(phase * 6.28318530718);
	float streak = pow(max(wave, 0.0), streak_sharpness);

	COLOR = vec4(streak_color, streak * streak_alpha);
}
"""

## World units/second the streak pattern advances along the flow direction.
const FLOW_SPEED := 18.0
## Spatial frequency of streaks along the flow axis (cycles per world unit).
const STREAK_FREQUENCY := 0.12
## Raising the clamped sine to this power narrows the bright band into a
## crisp streak rather than a broad, soft glow -- higher = thinner streaks.
const STREAK_SHARPNESS := 4.0
## Overlay opacity ceiling: translucent enough that the base water
## color/ripples beneath always stay visible -- the same "never opaque"
## bound WaterShader.WATER_ALPHA/HillshadeShader.MAX_SHADOW_ALPHA already
## keep for their own overlays.
const STREAK_ALPHA := 0.35
## Pale, glinting -- a highlight riding on the water's own blue, not a
## competing hue.
const STREAK_COLOR := Color(0.75, 0.88, 1.0)

var _shared_material: ShaderMaterial


func make_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("flow_speed", FLOW_SPEED)
	material.set_shader_parameter("streak_frequency", STREAK_FREQUENCY)
	material.set_shader_parameter("streak_sharpness", STREAK_SHARPNESS)
	material.set_shader_parameter("streak_alpha", STREAK_ALPHA)
	material.set_shader_parameter("streak_color", STREAK_COLOR)
	return material


func shared_material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = make_material()
	return _shared_material


## The exact math the shader's fragment() runs to shape a streak, mirrored
## on the CPU for headless testing. `along_world_units` is the signed
## distance along the flow direction; `time_seconds` is the shader's TIME.
static func streak_intensity(along_world_units: float, time_seconds: float) -> float:
	var phase := along_world_units * STREAK_FREQUENCY - time_seconds * FLOW_SPEED * STREAK_FREQUENCY
	var wave := sin(phase * TAU)
	return pow(maxf(wave, 0.0), STREAK_SHARPNESS)
