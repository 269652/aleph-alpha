extends RefCounted

## Additive glow around a carried light source (currently: an equipped,
## lit torch) -- see docs/concept/lighting.md. Renders AFTER the day/night
## `CanvasModulate` tint, additively, so it reads correctly over every
## existing shader (grass/water/terrain) with zero changes to any of them
## -- none of those shaders define a `light()` callback, so a real Godot
## `Light2D` would not affect them consistently even on this project's
## `gl_compatibility` renderer, which otherwise supports one fine.

## Real-world grounding: a torch/campfire realistically throws useful
## light roughly 6-9 metres before fading into the surrounding dark. Mid-
## range of that real span, converted to world pixels by whoever builds
## the actual quad (see `GroundSlide.PX_PER_METER`, this codebase's one
## real-world-scale-to-pixel conversion).
const GLOW_RADIUS_METERS := 7.5

## How much of the glow's own radius is a soft, fading edge rather than a
## flat, hard-edged disc -- see `glow_intensity`'s own doc comment.
const EDGE_SOFTNESS_FRACTION := 0.5

## The warm, firelit color the glow adds -- not a neutral white brightening,
## a real torch's own light is warm orange.
const GLOW_COLOR := Color(1.0, 0.7, 0.35)

static var SHADER_CODE: String = _build_shader_code()

## Pure CPU mirror of the shader's own radial falloff -- a fragment shader
## cannot be asserted headless, so the tuned math is mirrored here, the
## same relationship `SnowSparkleShader`/`WaterShader` already have to
## their own shaders (see docs/concept/lighting.md).
##
## `normalized_distance`: 0.0 at the light's own center, 1.0 at the outer
## edge of its radius. Returns 1.0 (full intensity) out to a flat core --
## `1.0 - EDGE_SOFTNESS_FRACTION` of the radius -- then fades smoothly to
## 0.0 at the very edge, so a lit area reads as a real pool of light
## rather than dimming from the first pixel outward. Clamped both ends: a
## negative distance (should never happen from a real caller) reads as the
## center, and anything past the edge reads as fully faded.
static func glow_intensity(normalized_distance: float) -> float:
	var t := clampf(normalized_distance, 0.0, 1.0)
	var edge_start := 1.0 - EDGE_SOFTNESS_FRACTION
	if t <= edge_start:
		return 1.0
	return 1.0 - smoothstep(edge_start, 1.0, t)


static func _build_shader_code() -> String:
	return """
shader_type canvas_item;
render_mode blend_add;

uniform vec3 glow_color = vec3(%s, %s, %s);
uniform float edge_softness_fraction = %s;

void fragment() {
	// UV is this quad's own local [0,1]; recenter to [-1,1] so distance
	// from the middle maps to a true circle (the quad itself must be
	// square for this to read as round rather than elliptical).
	vec2 centered = UV * 2.0 - 1.0;
	float t = clamp(length(centered), 0.0, 1.0);
	float edge_start = 1.0 - edge_softness_fraction;
	float intensity = t <= edge_start ? 1.0 : 1.0 - smoothstep(edge_start, 1.0, t);
	COLOR = vec4(glow_color, intensity);
}
""" % [GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, EDGE_SOFTNESS_FRACTION]
