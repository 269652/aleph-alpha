extends RefCounted

const TerrainPassability = preload("res://src/gameplay/terrain_passability.gd")

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
## tile's own local elevation gradient"), now actually built.
##
## Flow SPEED is now real too (reported: "more natural water flow" -- a
## uniform speed everywhere read as mechanical, not like water actually
## responding to the terrain it's running through). speed_fraction_for_
## slope_deg maps the SAME real gradient's magnitude
## (TerrainRelief.slope_degrees_from_gradient) to a [0,1] fraction between
## MIN_FLOW_SPEED and MAX_FLOW_SPEED, anchored at
## TerrainPassability.HARD_THRESHOLD_DEG -- the same real "genuine
## scrambling/technical-climbing" steepness BiomeClassifier's own
## SLOPE_MOUNTAIN_THRESHOLD_DEG already reuses for a different purpose,
## rather than inventing a second, independently-eyeballed cap. Discharge/
## channel-width data still isn't curated, so this is real GRADIENT-driven
## variation, not a claim of hydraulically exact current speed.
##
## Turbulence is new too: two octaves of scrolling value noise (the exact
## technique water_shader.gd's own wind-shimmer already proves) perturb the
## streak phase itself, so bands waver and drift rather than reading as a
## perfectly rigid scrolling barcode. Purely cosmetic, so -- like
## water_shader.gd's own wind-shimmer -- it has no CPU mirror; only the
## periodic-streak physics another caller might reason about does.
##
## The overlay tile's own texture carries real per-tile (direction, speed)
## DATA (see procedural_river_flow_sprite.gd), sampled here exactly the way
## hillshade_shader.gd samples (slope, aspect) -- this shader reads a
## channel, not art.
##
## streak_intensity() below is the CPU mirror of exactly what the shader's
## periodic-streak math computes, kept in sync by hand -- the same
## relationship water_shader.gd's ripple_amplitude has to ripple_packet,
## and for the same reason: a fragment shader can't be asserted headless.

const SHADER_CODE := """
shader_type canvas_item;

uniform float min_flow_speed = 8.0;
uniform float max_flow_speed = 32.0;
uniform float streak_frequency = 0.12;
uniform float streak_sharpness = 2.0;
uniform float streak_alpha = 0.5;
uniform vec3 streak_color : source_color = vec3(0.85, 0.94, 1.0);
uniform float turbulence_strength = 30.0;
uniform float turbulence_scale = 0.035;
uniform float turbulence_speed = 0.6;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float value_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = value_hash(i);
	float b = value_hash(i + vec2(1.0, 0.0));
	float c = value_hash(i + vec2(0.0, 1.0));
	float d = value_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	// Red = compass bearing [0,1] -> [0,360), green = real local slope
	// magnitude mapped to a [0,1] speed fraction (see
	// speed_fraction_for_slope_deg, procedural_river_flow_sprite.gd) -- the
	// same encoding/convention hillshade_shader.gd's (slope, aspect)
	// channels already use.
	vec2 data = texture(TEXTURE, UV).rg;
	float angle_deg = data.r * 360.0;
	float angle_rad = radians(angle_deg);
	// Godot 2D: +X east, +Y DOWN (screen space) -- "north" is -Y.
	vec2 flow_dir = vec2(sin(angle_rad), -cos(angle_rad));
	float flow_speed = mix(min_flow_speed, max_flow_speed, data.g);

	float along = dot(world_pos, flow_dir);
	float across = dot(world_pos, vec2(-flow_dir.y, flow_dir.x));

	// Turbulence: two octaves of scrolling value noise perturb the ALONG
	// position itself (in world units) before the periodic streak phase is
	// computed, so streak bands waver and bend rather than reading as
	// perfectly straight, rigid lines -- real flowing water is never that
	// regular. Sampled in (along, across) space, not world_pos directly, so
	// the wobble is consistent along the flow's own axis regardless of the
	// river's real-world orientation.
	float turb_a = value_noise(vec2(along, across) * turbulence_scale + vec2(TIME * turbulence_speed, 0.0));
	float turb_b = value_noise(vec2(along, across) * turbulence_scale * 2.3 - vec2(0.0, TIME * turbulence_speed * 0.7));
	float turbulence = (turb_a * 0.65 + turb_b * 0.35 - 0.5) * turbulence_strength;

	float phase = (along + turbulence) * streak_frequency - TIME * flow_speed * streak_frequency;
	// A clamped sine raised to a power: cheap, crisp, periodic bright bands
	// (streaks) separated by near-zero troughs -- not constant brightness,
	// which would just read as a flat tint, not motion.
	float wave = sin(phase * 6.28318530718);
	float streak = pow(max(wave, 0.0), streak_sharpness);

	COLOR = vec4(streak_color, streak * streak_alpha);
}
"""

## Slowest a river flows visually -- a gentle lowland stretch.
const MIN_FLOW_SPEED := 8.0
## Fastest a river flows visually -- a steep mountain stretch, at/beyond
## TerrainPassability.HARD_THRESHOLD_DEG.
const MAX_FLOW_SPEED := 32.0
## Spatial frequency of streaks along the flow axis (cycles per world unit).
const STREAK_FREQUENCY := 0.12
## Raising the clamped sine to this power narrows the bright band into a
## crisp streak rather than a broad, soft glow -- higher = thinner streaks.
## Reported "make the flow effect more visible" (2026-08-30): the prior
## 4.0 kept the bright (>0.5 intensity) part of each cycle to only ~18.2%
## of the period (see test_river_flow_shader.gd's own derivation from
## pow(max(sin(phase*TAU),0), n) -- bright fraction is
## (pi - 2*asin(0.5^(1/n))) / (2*pi)), reading as a thin, sparse glint
## rather than a current that visibly covers the water. Halving it to 2.0
## broadens that to a measured 25% of the period -- comfortably clear of
## the 22% floor the regression test pins, while staying well short of a
## flat, motionless-looking tint (a duty fraction near 50%).
const STREAK_SHARPNESS := 2.0
## Overlay opacity ceiling: translucent enough that the base water
## color/ripples beneath always stay visible -- the same "never opaque"
## bound WaterShader.WATER_ALPHA/HillshadeShader.MAX_SHADOW_ALPHA already
## keep for their own overlays. Reported "make the flow effect more
## visible" (2026-08-30): the prior 0.35 read as an easy-to-miss glint,
## particularly once layered under HillshadeShader's own overlay (up to
## MAX_SHADOW_ALPHA=0.55 of near-black on the same tile, per the z-order
## fix in eae510d) -- the streak needs enough contrast to punch through
## that darkening, not just be visible in isolation. Raised to 0.5: a real
## step up from 0.35, but still genuinely translucent and placed below
## BOTH of this codebase's own overlay-alpha precedents -- under
## HillshadeShader.MAX_SHADOW_ALPHA (0.55) so the flow highlight never
## outweighs the shading it sits on top of, and under WaterShader.
## WATER_ALPHA (0.6) so the sparse, pulsing streak never becomes as
## dominant as the base water tile it's decorating.
const STREAK_ALPHA := 0.5
## Pale, glinting -- a highlight riding on the water's own blue, not a
## competing hue. Reported "make the flow effect more visible"
## (2026-08-30): brightened red and green toward the already-maxed blue
## channel (0.75->0.85, 0.88->0.94) as a second, alpha-independent lever --
## COLOR = vec4(streak_color, streak*streak_alpha) blends toward whatever
## sits underneath, so a brighter source color lands lighter at the same
## alpha, which matters most on top of a near-black hillshade tile. Still
## every channel within [0.7, 1.0] (pale, not saturated/neon) and blue
## stays the highest channel -- a water highlight, not a warm tint.
const STREAK_COLOR := Color(0.85, 0.94, 1.0)
## How far (in world units) the turbulence noise can shift the streak
## phase's effective position -- large enough to visibly bend/waver a
## band, small enough that streaks still read as flowing roughly downstream
## rather than dissolving into pure noise.
const TURBULENCE_STRENGTH := 30.0
## Spatial scale of the turbulence noise field -- lower than a ripple's own
## noise_scale (WaterShader.SHADER_CODE's 0.045), since turbulence should
## read as broad, slow-shifting waver, not fine chop.
const TURBULENCE_SCALE := 0.035
## How fast the turbulence noise field itself drifts over time.
const TURBULENCE_SPEED := 0.6

var _shared_material: ShaderMaterial


func make_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("min_flow_speed", MIN_FLOW_SPEED)
	material.set_shader_parameter("max_flow_speed", MAX_FLOW_SPEED)
	material.set_shader_parameter("streak_frequency", STREAK_FREQUENCY)
	material.set_shader_parameter("streak_sharpness", STREAK_SHARPNESS)
	material.set_shader_parameter("streak_alpha", STREAK_ALPHA)
	material.set_shader_parameter("streak_color", STREAK_COLOR)
	material.set_shader_parameter("turbulence_strength", TURBULENCE_STRENGTH)
	material.set_shader_parameter("turbulence_scale", TURBULENCE_SCALE)
	material.set_shader_parameter("turbulence_speed", TURBULENCE_SPEED)
	return material


func shared_material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = make_material()
	return _shared_material


## Maps a real local slope magnitude (TerrainRelief.slope_degrees_from_
## gradient) to a [0,1] visual flow-speed fraction: 0.0 on flat ground,
## 1.0 at or beyond TerrainPassability.HARD_THRESHOLD_DEG (real "genuine
## scrambling/technical-climbing" steepness -- reused here as "about as
## dramatic as this world's terrain scale gets" rather than an
## independently-eyeballed cap), linear in between.
static func speed_fraction_for_slope_deg(slope_deg: float) -> float:
	return clampf(slope_deg / TerrainPassability.HARD_THRESHOLD_DEG, 0.0, 1.0)


## The exact math the shader's fragment() runs to shape a streak, mirrored
## on the CPU for headless testing. `along_world_units` is the signed
## distance along the flow direction; `time_seconds` is the shader's TIME;
## `flow_speed` is the real per-cell speed (mix(MIN_FLOW_SPEED,
## MAX_FLOW_SPEED, speed_fraction), computed by the caller). Turbulence is
## NOT mirrored -- see this file's own doc comment for why.
static func streak_intensity(along_world_units: float, time_seconds: float, flow_speed: float) -> float:
	var phase := along_world_units * STREAK_FREQUENCY - time_seconds * flow_speed * STREAK_FREQUENCY
	var wave := sin(phase * TAU)
	return pow(maxf(wave, 0.0), STREAK_SHARPNESS)
