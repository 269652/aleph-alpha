extends RefCounted

## An additive halo around a resolving spell atom (docs/concept/spell_vfx.md,
## "SpellGlowShader") -- light spilling onto the scene from whatever just
## discharged, every atom, not gated by shape family.
##
## Mirrors TorchGlow's own shape (a dedicated `canvas_item`/`blend_add`
## shader, a CPU-mirrored tuned curve, GLSL that restates it rather than a
## second untested copy) with two real differences, both deliberate:
##
## - TorchGlow is static (one light, on for as long as a torch is
##   equipped); this animates a grow/hold/fade ENVELOPE timed off
##   `SpellEffectMarker`'s own beat, since a cast is a moment, not a
##   standing light.
## - TorchGlow's `material()` is a cached singleton, correct because there
##   is only ever one torch glow live at a time. Two spell casts can be
##   mid-flight together, and a SHARED `ShaderMaterial` would make the
##   second marker's own `progress` write stomp the first's (it is a
##   Resource, mutated by reference) -- so `material_for` hands back a
##   fresh instance every call, sharing only the compiled `Shader` itself.

const ProceduralSpellEffectSprite = preload("res://src/rendering/procedural_spell_effect_sprite.gd")

## How much of the halo's own radius is a soft, fading edge rather than a
## flat core -- same shape as TorchGlow.EDGE_SOFTNESS_FRACTION, a
## DELIBERATELY independent constant: a magic halo is meant to read as
## diffuse light spilling outward, not a torch's practical usable-light
## pool, so it is softer, and retuning one must never silently retune the
## other.
const EDGE_SOFTNESS_FRACTION := 0.7

## The halo's own quad, sized against `ProceduralSpellEffectSprite.SIZE`.
## Must be genuinely bigger than 1.0 -- a halo that matches the sprite's own
## silhouette reads as a coloured outline, not light spilling outward
## (spell_vfx.md) -- and comfortably short of reading as a full-screen
## flash.
const HALO_SIZE_MULTIPLIER := 2.6

## How bright the halo gets at the peak of its hold window. Never fully
## opaque -- this sits ON TOP of the effect sprite and the world behind it;
## a peak alpha of 1.0 would wash out whatever it is layered over.
const PEAK_ALPHA := 0.55

static var SHADER_CODE: String = _build_shader_code()
static var _shader: Shader = _build_shader()


## Pure spatial falloff: 1.0 at the halo's own center, fading through a
## smoothstep edge to 0.0 at its outer radius. Identical shape to
## TorchGlow.glow_intensity, independently owned (see EDGE_SOFTNESS_FRACTION's
## own doc comment for why).
static func radial_intensity(normalized_distance: float) -> float:
	var t := clampf(normalized_distance, 0.0, 1.0)
	var edge_start := 1.0 - EDGE_SOFTNESS_FRACTION
	if t <= edge_start:
		return 1.0
	return 1.0 - smoothstep(edge_start, 1.0, t)


## Pure temporal envelope: 0 at the very start, rising to `peak_alpha`
## across the grow window, held flat through the hold window, falling back
## to 0 across whatever's left. `grow_fraction`/`hold_fraction` are 0..1
## FRACTIONS OF THE TOTAL BEAT -- the caller derives them from
## `SpellEffectMarker.GROW_DURATION`/`HOLD_DURATION` against its own total
## duration, never restated as a second set of numbers here, so retuning the
## marker's timing retunes this for free.
##
## Both window boundaries are guarded against a zero-length span (no
## division by zero): a zero grow window is already at peak from progress
## 0, and a zero fade window drops straight to 0 at progress 1.
static func alpha_for_progress(
	progress: float, grow_fraction: float, hold_fraction: float, peak_alpha: float
) -> float:
	var p := clampf(progress, 0.0, 1.0)
	var hold_end := grow_fraction + hold_fraction
	if p < grow_fraction:
		if grow_fraction <= 0.0:
			return peak_alpha
		return peak_alpha * smoothstep(0.0, grow_fraction, p)
	if p < hold_end:
		return peak_alpha
	var fade_span := 1.0 - hold_end
	if fade_span <= 0.0:
		return 0.0
	return peak_alpha * (1.0 - smoothstep(hold_end, 1.0, p))


## A fresh `ShaderMaterial` tinted for `atom_id`, sharing the one compiled
## `Shader` every call reuses. The caller owns driving `progress` on its own
## instance (typically via `Tween.tween_method`, alongside the marker's
## existing scale/alpha tween) -- see this file's own doc comment for why
## instances are never cached/shared across casts.
static func material_for(atom_id: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _shader
	var color: Color = ProceduralSpellEffectSprite.color_for(atom_id)
	material.set_shader_parameter("glow_color", Vector3(color.r, color.g, color.b))
	material.set_shader_parameter("edge_softness_fraction", EDGE_SOFTNESS_FRACTION)
	material.set_shader_parameter("progress", 0.0)
	return material


static func _build_shader() -> Shader:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	return shader


static func _build_shader_code() -> String:
	return """
shader_type canvas_item;
render_mode blend_add;

uniform vec3 glow_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float edge_softness_fraction = %s;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float grow_fraction = 0.2;
uniform float hold_fraction = 0.25;
uniform float peak_alpha = %s;

void fragment() {
	// Same recentring TorchGlow's own shader uses: UV is this quad's local
	// [0,1], recentred to [-1,1] so distance from the middle maps to a true
	// circle (the quad itself must be square).
	vec2 centered = UV * 2.0 - 1.0;
	float dist = clamp(length(centered), 0.0, 1.0);
	float edge_start = 1.0 - edge_softness_fraction;
	float radial = dist <= edge_start ? 1.0 : 1.0 - smoothstep(edge_start, 1.0, dist);

	float hold_end = grow_fraction + hold_fraction;
	float temporal;
	if (progress < grow_fraction) {
		temporal = grow_fraction <= 0.0 ? peak_alpha : peak_alpha * smoothstep(0.0, grow_fraction, progress);
	} else if (progress < hold_end) {
		temporal = peak_alpha;
	} else {
		float fade_span = 1.0 - hold_end;
		temporal = fade_span <= 0.0 ? 0.0 : peak_alpha * (1.0 - smoothstep(hold_end, 1.0, progress));
	}

	COLOR = vec4(glow_color, radial * temporal);
}
""" % [EDGE_SOFTNESS_FRACTION, PEAK_ALPHA]
