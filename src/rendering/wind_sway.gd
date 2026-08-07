extends RefCounted

## Real-time wind sway for vegetation sprites (trees, grass/scrub tufts): a
## shared canvas_item vertex shader that bends the TOP of a sprite side to
## side over TIME while its base stays pinned to the ground -- a tree's trunk
## doesn't slide around, its canopy sways; a grass blade bends from its root.
##
## Design notes (each pinned by test_wind_sway.gd):
## - Displacement is weighted by (1 - UV.y)^2, so the sprite's bottom edge
##   (UV.y = 1) moves zero pixels and the sway eases in toward the top.
## - Phase comes from the node's world position (MODEL_MATRIX origin), so
##   neighboring plants sway with natural offsets instead of robotic lockstep
##   -- a gust reads as rolling across a meadow.
## - One material instance is shared by every swaying sprite (see
##   shared_material) -- hundreds of tufts with per-node materials would
##   defeat batching for zero visual gain.
##
## The shader runs entirely on the GPU: no per-frame script cost anywhere,
## which keeps ChoppableTree's deliberate no-_process constraint intact.

const SHADER_CODE := """
shader_type canvas_item;

uniform float amplitude_px = 1.4;
uniform float wind_speed = 1.8;

void vertex() {
	float phase = MODEL_MATRIX[3].x * 0.045 + MODEL_MATRIX[3].y * 0.031;
	float top_weight = 1.0 - UV.y;
	VERTEX.x += sin(TIME * wind_speed + phase) * amplitude_px * top_weight * top_weight;
}
"""

## Max sideways bend of a sprite's very top, in pixels. Small on purpose: at
## 16px sprites, 1-2px of lean reads as living wind; more reads as a storm.
const DEFAULT_AMPLITUDE_PX := 1.4
## Sway oscillation speed (radians/sec into sin) -- a lazy breeze, not a flag
## in a gale.
const DEFAULT_SPEED := 1.8

var _shared_material: ShaderMaterial


## A fresh sway material with explicit parameters -- callers that want a
## distinct wind feel (e.g. stiffer trees vs. floppy grass) can build their
## own; everything else should use shared_material().
func make_material(
	amplitude_px: float = DEFAULT_AMPLITUDE_PX, speed: float = DEFAULT_SPEED
) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("amplitude_px", amplitude_px)
	material.set_shader_parameter("wind_speed", speed)
	return material


## The default-parameter material, built once and reused across every caller
## of this instance -- assign this to each swaying sprite.
func shared_material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = make_material()
	return _shared_material
