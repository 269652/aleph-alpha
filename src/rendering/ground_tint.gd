extends RefCounted

## World-space low-frequency color drift for the terrain TileMapLayer. Every
## tile of a biome shares one average color, so no matter how good the
## per-tile art is, a large field reads as a uniform printed carpet -- the
## classic "procedural but artificial" tell. Real ground shifts between
## lusher and drier patches over spans much larger than any single tile.
##
## This fragment shader multiplies terrain brightness by two octaves of
## hash-based value noise sampled in WORLD space (via MODEL_MATRIX, so the
## pattern is glued to the ground and doesn't swim as the camera moves), with
## a wavelength spanning many tiles. Applied once to the whole layer -- water
## included, where the same drift reads as natural depth variation. Zero
## per-frame script cost; contract pinned by test_ground_tint.gd.

const SHADER_CODE := """
shader_type canvas_item;

uniform float tint_strength = 0.09;
uniform float noise_scale = 0.006;

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
	float n = value_noise(world_pos * noise_scale) * 0.65
		+ value_noise(world_pos * noise_scale * 3.7) * 0.35;
	COLOR.rgb *= (1.0 - tint_strength) + n * tint_strength * 2.0;
}
"""

## Max brightness drift either way (+-9%): a soft meadow shift, never camo
## blotches. Pinned <= 0.2 by test_tint_strength_is_subtle_and_pinned.
const TINT_STRENGTH := 0.09

## World-space noise frequency. 0.006 -> wavelength ~166px, i.e. patches
## spanning ~10 tiles -- variation BIGGER than any tile, which is exactly
## what per-tile art can never provide. Pinned to span >= 4 tiles by
## test_noise_wavelength_spans_multiple_tiles.
const NOISE_SCALE := 0.006

var _shared_material: ShaderMaterial


func make_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("tint_strength", TINT_STRENGTH)
	material.set_shader_parameter("noise_scale", NOISE_SCALE)
	return material


func shared_material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = make_material()
	return _shared_material
