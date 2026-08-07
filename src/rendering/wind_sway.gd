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
uniform float bend_exponent = 2.0;

void vertex() {
	float phase = MODEL_MATRIX[3].x * 0.045 + MODEL_MATRIX[3].y * 0.031;
	float top_weight = pow(1.0 - UV.y, bend_exponent);
	VERTEX.x += sin(TIME * wind_speed + phase) * amplitude_px * top_weight;
}
"""

## Max sideways bend of a sprite's very top, in pixels. Small on purpose: at
## 16px sprites, 1-2px of lean reads as living wind; more reads as a storm.
const DEFAULT_AMPLITUDE_PX := 1.4
## Sway oscillation speed (radians/sec into sin) -- a lazy breeze, not a flag
## in a gale.
const DEFAULT_SPEED := 1.8

## Trees bend with a squared falloff (a canopy sways atop a stiff trunk).
## Grass/scrub tuft sprites need the opposite: their blade pixels sit in the
## LOWER half of the quad, where a squared falloff leaves under half a pixel
## of motion -- visually static (the reported "streaks don't sway" bug). The
## tuft preset bends linearly and harder, so blades visibly whip.
const TUFT_AMPLITUDE_PX := 6.0
const TUFT_SPEED := 3.0
const TUFT_BEND_EXPONENT := 1.0

var _shared_material: ShaderMaterial
var _tuft_material: ShaderMaterial


## A fresh sway material with explicit parameters -- callers that want a
## distinct wind feel (e.g. stiffer trees vs. floppy grass) can build their
## own; everything else should use shared_material()/tuft_material().
func make_material(
	amplitude_px: float = DEFAULT_AMPLITUDE_PX,
	speed: float = DEFAULT_SPEED,
	bend_exponent: float = 2.0
) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("amplitude_px", amplitude_px)
	material.set_shader_parameter("wind_speed", speed)
	material.set_shader_parameter("bend_exponent", bend_exponent)
	return material


## The default-parameter material (trees), built once and shared.
func shared_material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = make_material()
	return _shared_material


## The grass/scrub tuft preset (see TUFT_* consts), built once and shared.
func tuft_material() -> ShaderMaterial:
	if _tuft_material == null:
		_tuft_material = make_material(TUFT_AMPLITUDE_PX, TUFT_SPEED, TUFT_BEND_EXPONENT)
	return _tuft_material
