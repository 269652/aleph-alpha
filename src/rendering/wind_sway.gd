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
// Live wind conditions (see WeatherModel.wind_strength_for, forwarded via
// EarthChunkManager.set_wind_strength) -- amplitude_px is the BASE sway at
// wind_strength == 1.0 (WeatherModel's own "clear" baseline), multiplied up
// for rougher weather and down for none, rather than swaying at a fixed
// amount regardless of what the sky is actually doing.
uniform float wind_strength = 1.0;

void vertex() {
	float phase = MODEL_MATRIX[3].x * 0.045 + MODEL_MATRIX[3].y * 0.031;
	float top_weight = pow(1.0 - UV.y, bend_exponent);
	float gust = sin(TIME * wind_speed + phase) * 0.7
		+ sin(TIME * wind_speed * 2.7 + phase * 1.7) * 0.3;
	VERTEX.x += gust * amplitude_px * wind_strength * top_weight;
}
"""

## Max sideways bend of a sprite's very top, in pixels. Small on purpose: at
## 16px sprites, 1-2px of lean reads as living wind; more reads as a storm.
const DEFAULT_AMPLITUDE_PX := 1.4
## Sway oscillation speed (radians/sec into sin) -- a lazy breeze, not a flag
## in a gale.
const DEFAULT_SPEED := 1.2

## Trees bend with a squared falloff (a canopy sways atop a stiff trunk).
## Grass/scrub tuft sprites need the opposite: their blade pixels sit in the
## LOWER half of the quad, where a squared falloff leaves under half a pixel
## of motion -- visually static (the reported "streaks don't sway" bug). The
## tuft preset bends linearly and harder, so blades visibly whip.
const TUFT_AMPLITUDE_PX := 3.0
const TUFT_SPEED := 1.6
const TUFT_BEND_EXPONENT := 1.0

## The shader's own wind_strength default: calibrated to
## WeatherModel.wind_strength_for("clear") == 1.0 (see weather_model.gd),
## the majority weather state (CLEAR_THRESHOLD), so a freshly built material
## reproduces today's fixed-amplitude look exactly until a live value is
## pushed in via set_wind_strength.
const DEFAULT_WIND_STRENGTH := 1.0

var _shared_material: ShaderMaterial
var _tuft_material: ShaderMaterial
## Last live wind strength pushed in (see set_wind_strength) -- applied to
## shared_material()/tuft_material() at BUILD time too, so a caller that sets
## the live wind before either material has been lazily built yet (spawn
## order isn't guaranteed) doesn't lose it.
var _wind_strength := DEFAULT_WIND_STRENGTH


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
	material.set_shader_parameter("wind_strength", _wind_strength)
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


## Pushes the live wind strength (see WeatherModel.wind_strength_for, via
## EarthChunkManager.set_wind_strength) onto whichever of shared_material()/
## tuft_material() have already been built, and remembers it for whichever
## get built later -- so trees, grass/scrub tufts, and (via tuft_material,
## see earth_chunk_manager.gd's bloom-sprite spawning) flower blooms all
## sway harder in a storm and calmer on a clear day, all through this one
## shared value.
func set_wind_strength(strength: float) -> void:
	_wind_strength = strength
	if _shared_material != null:
		_shared_material.set_shader_parameter("wind_strength", strength)
	if _tuft_material != null:
		_tuft_material.set_shader_parameter("wind_strength", strength)
