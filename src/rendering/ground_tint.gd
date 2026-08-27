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

const SeasonalFoliage = preload("res://src/rendering/seasonal_foliage.gd")

## Built rather than a plain literal so SeasonalFoliage.GREENNESS_GAIN is the
## ONE definition of the greenness gate and the GDScript the tests exercise
## cannot drift from the GLSL the GPU runs. Same shape
## IllustratedGrassPatch.SHADER_CODE already uses.
static var SHADER_CODE: String = _build_shader_code()


static func _build_shader_code() -> String:
	return """
shader_type canvas_item;

uniform float tint_strength = 0.09;
uniform float noise_scale = 0.006;
// The season's multiplier on living green (see SeasonalFoliage), pushed in
// live from the world clock the same way wind_strength is pushed onto the
// grass shader. Identity by default, so a caller that never sets it renders
// exactly today's high-summer picture.
uniform vec3 season_tint = vec3(1.0);

// The finished multiplier, computed ONCE PER VERTEX and interpolated across
// the tile (see the note in ground_tint.gd on why that is safe here).
varying float tint;

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

void vertex() {
	vec2 world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	float n = value_noise(world_pos * noise_scale) * 0.65
		+ value_noise(world_pos * noise_scale * 3.7) * 0.35;
	tint = (1.0 - tint_strength) + n * tint_strength * 2.0;
}

void fragment() {
	COLOR.rgb *= tint;
	// Only what is actually GREEN takes the season. This one material covers
	// the WHOLE terrain layer, water included (see this file's header), so an
	// unweighted multiply would turn the ocean and the sand brown in autumn.
	// Same expression as SeasonalFoliage.greenness_of, with the same gain
	// interpolated in below -- one constant, two languages.
	float greenness = clamp((COLOR.g - max(COLOR.r, COLOR.b)) * %s, 0.0, 1.0);
	COLOR.rgb = mix(COLOR.rgb, COLOR.rgb * season_tint, greenness);
}
""" % [SeasonalFoliage.GREENNESS_GAIN]

## Max brightness drift either way (+-9%): a soft meadow shift, never camo
## blotches. Pinned <= 0.2 by test_tint_strength_is_subtle_and_pinned.
const TINT_STRENGTH := 0.09

## World-space noise frequency. 0.006 -> wavelength ~166px, i.e. patches
## spanning ~10 tiles -- variation BIGGER than any tile, which is exactly
## what per-tile art can never provide. Pinned to span >= 4 tiles by
## test_noise_wavelength_spans_multiple_tiles.
## Why the noise is evaluated per VERTEX rather than per pixel.
##
## Both octaves used to run in the fragment shader: eight sin-based hashes for
## every pixel of ground on screen, which at 1920x1080 is roughly 16 million
## sin operations per frame. On integrated graphics that was one of the three
## most expensive things in the frame -- removing the tint entirely measured
## +81% fps.
##
## It does not need to be per-pixel. This is a broad, slowly-varying wash: at
## NOISE_SCALE 0.006 one world tile spans about a tenth of a noise cell, so
## sampling at tile corners and letting the hardware interpolate between them
## is very nearly the same field, for a ninth-strength tint nobody is looking
## at directly. The cost drops by roughly the number of pixels in a tile.
const NOISE_SCALE := 0.006

## STATIC, and that is the point: the terrain TileMapLayer is handed
## `GroundTint.new().shared_material()` once by whatever builds it, which does
## not keep the instance. If this were per-instance, pushing the live season
## from anywhere else would set a uniform on a material nothing renders -- a
## silent no-op. One terrain layer, one shared material. Pinned by
## test_the_shared_material_is_the_same_one_for_every_instance.
static var _shared_material: ShaderMaterial

## Last season tint pushed in (see set_season_tint) -- applied in
## make_material() too, so a caller that sets the season before the material
## has been built doesn't silently lose it. Mirrors
## IllustratedGrassPatch._wind_strength's own reasoning.
static var _season_tint := Color(1.0, 1.0, 1.0)


func make_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("tint_strength", TINT_STRENGTH)
	material.set_shader_parameter("noise_scale", NOISE_SCALE)
	material.set_shader_parameter("season_tint", _as_vector(_season_tint))
	return material


func shared_material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = make_material()
	return _shared_material


## Pushes the season's tint on living green (see SeasonalFoliage, forwarded
## from the per-frame world clock) onto the shared terrain material. The
## GROUND carries the season too, not just the canopy above it: forcing winter
## used to give bare trees standing on a bright summer lawn.
func set_season_tint(tint: Color) -> void:
	_season_tint = tint
	shared_material().set_shader_parameter("season_tint", _as_vector(tint))


static func _as_vector(tint: Color) -> Vector3:
	return Vector3(tint.r, tint.g, tint.b)
