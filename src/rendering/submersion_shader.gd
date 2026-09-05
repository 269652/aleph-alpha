extends RefCounted

## Tints whatever part of a sprite is physically below a world-space water
## line -- shared by the player (see character_view.gd) and, eventually,
## anything else that should look partly underwater rather than either fully
## visible or hard-clipped away.
##
## The player's torso previously had NO submersion visual at all while
## swimming: legs were simply hidden and the torso rendered exactly as it
## does on dry land, floating at full height with nothing showing it was in
## water (reported: "half the torso should be under water"). Animals had the
## opposite problem -- a flat rectangle painted across the whole tile width
## (see ProceduralAnimalAnimation._swim_frame's rewrite). Neither is
## "water covering part of a body"; this is the shared mechanism that
## actually is.
##
## Uses WORLD-space Y, not texture UV: the same `world_pos` vertex technique
## WaterShader and WindSway already use in this codebase. That's deliberate
## -- it lets ONE material be applied to several different Sprite2D parts of
## different sizes/offsets (a player's Body, Head, arms as separate nodes)
## and have them all agree on the same waterline, which a per-texture UV
## approach cannot: each part's UV space has no relationship to any other
## part's, or to how tall the assembled character actually is.

const SHADER_CODE := """
shader_type canvas_item;

uniform float water_world_y = 999999.0;
uniform vec4 water_tint : source_color = vec4(0.2, 0.4, 0.85, 1.0);
uniform float tint_strength = 0.5;
uniform float alpha_fade = 0.22;
uniform float edge_softness_px = 1.5;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// Fraction submerged: 0 above the line, 1 comfortably below it, with a
	// soft edge so the waterline doesn't cut across the body as a hard,
	// aliased step.
	float underwater = smoothstep(
		water_world_y - edge_softness_px, water_world_y + edge_softness_px, world_pos.y
	);
	vec3 color = mix(tex.rgb, water_tint.rgb, underwater * tint_strength);
	float alpha = tex.a * (1.0 - underwater * alpha_fade);
	COLOR = vec4(color, alpha);
}
"""

## Matches ProceduralAnimalAnimation's swim tint exactly, so a submerged
## player and a submerged animal read as the same phenomenon rather than two
## different-looking effects.
const WATER_COLOR := Color(0.2, 0.4, 0.85)
const TINT_STRENGTH := 0.5
const ALPHA_FADE := 0.22

## How far a rig visually sinks (in local pixels, before any of its own
## node scale) at full wade depth -- shared by the player (character_view.gd)
## and animals (creature_marker.gd) for the same reason WATER_COLOR/
## TINT_STRENGTH/ALPHA_FADE above already are: one shared visual language
## for "partly underwater" rather than two independently-tuned numbers that
## could silently drift apart. Modest -- in the same tuned register as
## CharacterView.LEG_SWING_AMPLITUDE (3.0) -- legible without reading as
## sinking into quicksand. Pinned by each consumer's own test (see
## test_character_view.gd's test_full_wade_depth_sinks_the_body_by_the_
## full_constant) rather than left as an eyeballed comment.
const MAX_SINK_PX := 3.0

var _shared_material: ShaderMaterial

## ONE compiled Shader shared by every material instance -- each
## SubmersionShader used to build its own Shader from the same source, so
## every creature's first wade recompiled an identical shader from scratch
## (a visible hitch, and pure waste: materials differ only in uniforms).
static var _shared_shader: Shader


func make_material() -> ShaderMaterial:
	if _shared_shader == null:
		_shared_shader = Shader.new()
		_shared_shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = _shared_shader
	material.set_shader_parameter("water_world_y", 999999.0)  # off by default: nothing is underwater
	material.set_shader_parameter("water_tint", WATER_COLOR)
	material.set_shader_parameter("tint_strength", TINT_STRENGTH)
	material.set_shader_parameter("alpha_fade", ALPHA_FADE)
	return material


## One material instance shared by every submerged sprite -- same reasoning
## as WindSway.shared_material(): many sprites, one shader, one uniform
## update per frame rather than per-node.
func shared_material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = make_material()
	return _shared_material


## Sets the world Y below which pixels tint as underwater. Pass a very large
## value (or call clear_waterline) to submerge nothing.
func set_waterline(world_y: float) -> void:
	shared_material().set_shader_parameter("water_world_y", world_y)


func clear_waterline() -> void:
	set_waterline(999999.0)
