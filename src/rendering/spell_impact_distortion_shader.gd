extends RefCounted

## Screen-space warp at the instant a burst-family atom releases
## (docs/concept/spell_vfx.md, "SpellImpactDistortionShader") -- the real
## optical distinction the doc's "Real-world grounding" section draws: heat
## visibly bends the air near a sudden release of energy, which a coloured
## sprite alone cannot show however it is drawn. `SpellGlowShader` is the
## other half of that distinction (light spilling onto the scene, every
## atom); this is the burst-only warp of the scene itself.
##
## Same conventions as SpellGlowShader (a fragment shader cannot be
## asserted headless, so the tuned curve is CPU-mirrored first; a fresh
## `ShaderMaterial` per call, since two casts can be mid-flight together and
## a shared instance would make one marker's `progress` write stomp the
## other's). The one real difference: the TEMPORAL shape has no hold
## plateau. A shockwave strikes and dissipates; it does not linger the way
## ambient light does.

const ProceduralSpellEffectSprite = preload("res://src/rendering/procedural_spell_effect_sprite.gd")

## Own constant, independent of SpellGlowShader.EDGE_SOFTNESS_FRACTION --
## a shockwave reads as a punchier, less diffuse edge than ambient light
## spilling outward, a real design difference worth tuning separately
## rather than one shared number doing two jobs.
const EDGE_SOFTNESS_FRACTION := 0.4

## How far pixels behind the effect are displaced, in normalized screen UV,
## at full strength. Bounded (test_max_displacement_is_a_small_but_real_
## fraction_of_the_screen): large enough to read as a real heat-shimmer,
## far short of a disorienting funhouse warp.
const MAX_DISPLACEMENT_UV := 0.018

static var SHADER_CODE: String = _build_shader_code()
static var _shader: Shader = _build_shader()


## Whether `atom_id` gets this shader at all -- read from
## `ProceduralSpellEffectSprite.shape_for`, the one authoritative atom ->
## family map, never a second list here that could drift from it. Only the
## burst family (a sudden, instantaneous release) warrants a warp; a ring
## settling into place or a cloud drifting onto a target should not visibly
## disturb the world around it.
static func atom_gets_distortion(atom_id: String) -> bool:
	return ProceduralSpellEffectSprite.shape_for(atom_id) == "burst"


## Pure spatial falloff: 1.0 at the effect's own center, fading through a
## smoothstep edge to 0.0 at its outer radius. Same idiom as
## SpellGlowShader.radial_intensity, independently owned (see
## EDGE_SOFTNESS_FRACTION's own doc comment).
static func radial_strength(normalized_distance: float) -> float:
	var t := clampf(normalized_distance, 0.0, 1.0)
	var edge_start := 1.0 - EDGE_SOFTNESS_FRACTION
	if t <= edge_start:
		return 1.0
	return 1.0 - smoothstep(edge_start, 1.0, t)


## Pure temporal shape: rises from 0 to 1 across `[0, peak_fraction]`, falls
## back to 0 across `[peak_fraction, 1]` -- a single strike, not a hold.
## `peak_fraction` is the same kind of caller-derived value
## SpellGlowShader.alpha_for_progress takes: the marker's own beat decides
## when the burst actually peaks, this never restates that timing.
##
## Both extremes of `peak_fraction` (0.0 or 1.0) are guarded against
## dividing by a zero-length rise or fall span.
static func temporal_strength(progress: float, peak_fraction: float) -> float:
	var p := clampf(progress, 0.0, 1.0)
	var peak := clampf(peak_fraction, 0.0, 1.0)
	if p <= peak:
		if peak <= 0.0:
			return 1.0
		return smoothstep(0.0, peak, p)
	if peak >= 1.0:
		return 1.0
	return 1.0 - smoothstep(peak, 1.0, p)


## The combined 0..1 strength this shader multiplies `MAX_DISPLACEMENT_UV`
## by -- spatial reach times temporal timing, so a pixel far from the burst
## or well outside its peak moment is never displaced.
static func displacement_for(
	normalized_distance: float, progress: float, peak_fraction: float
) -> float:
	return radial_strength(normalized_distance) * temporal_strength(progress, peak_fraction)


## A fresh `ShaderMaterial`, sharing the one compiled `Shader` every call
## reuses. Not atom-tinted (a warp has no colour of its own) and not
## cached, for the same concurrent-casts reason `SpellGlowShader.material_for`
## is not.
static func material_for() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("edge_softness_fraction", EDGE_SOFTNESS_FRACTION)
	material.set_shader_parameter("max_displacement", MAX_DISPLACEMENT_UV)
	material.set_shader_parameter("progress", 0.0)
	material.set_shader_parameter("peak_fraction", 0.2)
	return material


static func _build_shader() -> Shader:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	return shader


static func _build_shader_code() -> String:
	return """
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float edge_softness_fraction = %s;
uniform float max_displacement = %s;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float peak_fraction : hint_range(0.0, 1.0) = 0.2;

void fragment() {
	// Same recentring SpellGlowShader's own shader uses: UV is this quad's
	// local [0,1], recentred to [-1,1] so distance from the middle maps to
	// a true circle (the quad itself must be square).
	vec2 centered = UV * 2.0 - 1.0;
	float dist = clamp(length(centered), 0.0, 1.0);
	float edge_start = 1.0 - edge_softness_fraction;
	float radial = dist <= edge_start ? 1.0 : 1.0 - smoothstep(edge_start, 1.0, dist);

	float temporal;
	if (progress <= peak_fraction) {
		temporal = peak_fraction <= 0.0 ? 1.0 : smoothstep(0.0, peak_fraction, progress);
	} else if (peak_fraction >= 1.0) {
		temporal = 1.0;
	} else {
		temporal = 1.0 - smoothstep(peak_fraction, 1.0, progress);
	}

	float strength = radial * temporal;
	vec2 direction = length(centered) > 0.0001 ? normalize(centered) : vec2(0.0);
	vec2 offset = direction * max_displacement * strength;
	COLOR = texture(screen_texture, SCREEN_UV + offset);
}
""" % [EDGE_SOFTNESS_FRACTION, MAX_DISPLACEMENT_UV]
