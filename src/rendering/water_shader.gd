extends RefCounted

## GPU water: continuous, noise-driven waves rendered in world space over
## every ocean cell -- the fluid motion 4-frame tile art fundamentally can't
## express. A dedicated overlay TileMapLayer (see EarthChunkManager.
## set_water_layer) holds one marker cell per loaded ocean cell and carries
## this fragment shader, which IGNORES the marker texture entirely and paints
## procedural water instead: two octaves of value noise scrolling at
## different speeds/directions (the surface shears naturally rather than
## sliding as one sheet), a deep-to-crest blue ramp, and sparse moving
## specular glints.
##
## Rendered at partial alpha (WATER_ALPHA) so the baked tile layer beneath
## stays part of the look: the shoreline waterline band and the rain-ripple
## tiles show through, and the weather system keeps working unchanged.
## World-space coordinates (MODEL_MATRIX) glue the waves to the map, and
## everything runs on TIME -- fully fluid at any frame rate, zero per-frame
## script. Contract pinned by test_water_shader.gd.

const SHADER_CODE := """
shader_type canvas_item;

uniform float alpha_strength = 0.5;
uniform float noise_scale = 0.045;
uniform float scroll_speed = 0.55;

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
	vec2 p = world_pos * noise_scale;
	// Two octaves drifting at different speeds and directions: the surface
	// shears like wind-driven water instead of scrolling as one sheet.
	float swell = value_noise(p + vec2(TIME * scroll_speed, TIME * scroll_speed * 0.35));
	float chop = value_noise(p * 2.3 - vec2(TIME * scroll_speed * 0.7, TIME * scroll_speed * 0.2));
	float wave = swell * 0.65 + chop * 0.35;

	vec3 deep = vec3(0.05, 0.24, 0.58);
	vec3 crest = vec3(0.4, 0.72, 0.98);
	vec3 water = mix(deep, crest, smoothstep(0.3, 0.85, wave));

	// Sparse specular glints skating across the surface.
	float glint = smoothstep(0.965, 1.0, value_noise(p * 3.7 + vec2(TIME * 0.9, -TIME * 0.5)));
	water += vec3(glint * 0.55);

	COLOR = vec4(water, alpha_strength);
}
"""

## Overlay opacity: high enough to own the water's look, low enough that the
## baked shoreline waterline and rain-ripple tiles beneath remain visible
## (pinned 0.2..0.75 by test_overlay_is_translucent...).
const WATER_ALPHA := 0.55

var _shared_material: ShaderMaterial


func make_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("alpha_strength", WATER_ALPHA)
	return material


func shared_material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = make_material()
	return _shared_material
