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
##
## Also carries canopy SPARKLE (see docs/concept/snow_cover.md, "Sparkle:
## specular glints on lying snow") -- a live per-fragment glint on top of the
## baked snow-covered canopy composite, sharing SnowSparkleShader's own
## tuned twinkle pattern with the ground (SnowBombShader). Gated on
## `snow_coverage` (pushed ONLY onto shared_material(), i.e. trees -- never
## tuft_material(), i.e. grass/scrub/blooms, which stays at its fixed 0.0
## default and is therefore structurally incapable of sparkling: this
## feature was asked for on trees and ground, not grass) plus a conservative
## near-white/low-saturation colour gate on the sprite's own already-
## composited colour, measured against the real art (see
## tools/probe_snow_sparkle_colors.gd and test_snow_sparkle_shader.gd) so it
## can never fire on e.g. cherry's illustrated pink blossom.
const SnowSparkleShader = preload("res://src/rendering/snow_sparkle_shader.gd")

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

// Live weather snow coverage (see EarthChunkManager._snow_depth, the exact
// same value the ground's own SnowBombShader.snow_depth uniform reads) --
// pushed ONLY onto the tree material (see this file's own header). 0.0 on
// every tuft, always, which is what keeps grass sparkle-free by
// construction rather than by convention.
uniform float snow_coverage : hint_range(0.0, 1.0) = 0.0;
uniform float sparkle_min_value = 0.85;
uniform float sparkle_max_saturation = 0.18;
""" + SnowSparkleShader.GLSL_SNIPPET + """

varying vec2 world_pos;

void vertex() {
	float phase = MODEL_MATRIX[3].x * 0.045 + MODEL_MATRIX[3].y * 0.031;
	float top_weight = pow(1.0 - UV.y, bend_exponent);
	float gust = sin(TIME * wind_speed + phase) * 0.7
		+ sin(TIME * wind_speed * 2.7 + phase * 1.7) * 0.3;
	VERTEX.x += gust * amplitude_px * wind_strength * top_weight;
	// AFTER the sway, deliberately: a glint sits on a physical twig, so it
	// should ride along with the twig's own sway rather than floating
	// independently of it (see test_world_pos_is_computed_after_the_sway_
	// displacement).
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// COLOR already equals texture(TEXTURE, UV) * (this node's own modulate)
	// -- Godot's own canvas_item default before fragment() runs. Reusing it
	// (rather than sampling TEXTURE again here) is what keeps a tree/tuft's
	// modulate working exactly as it did before this shader gained a
	// fragment() at all.
	vec4 base = COLOR;
	if (snow_coverage > 0.0 && base.a > 0.5) {
		float v = sparkle_value(base.rgb);
		float s = sparkle_saturation(base.rgb);
		if (v >= sparkle_min_value && s <= sparkle_max_saturation) {
			float twinkle = sparkle_intensity(world_pos, TIME) * snow_coverage;
			base.rgb += vec3(twinkle * sparkle_brightness);
		}
	}
	COLOR = base;
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

## Last live snow coverage pushed in (see set_snow_coverage) -- deliberately
## NOT the same shape as _wind_strength: it is remembered and re-applied to
## shared_material() (trees) at build time so a caller that pushes it before
## a tree has spawned yet doesn't lose it, but is NEVER applied to
## tuft_material() (grass/scrub/blooms) at any time -- see this file's own
## header and set_snow_coverage's own doc comment for why that isolation is
## load-bearing, not incidental.
var _snow_coverage := 0.0


## A fresh sway material with explicit parameters -- callers that want a
## distinct wind feel (e.g. stiffer trees vs. floppy grass) can build their
## own; everything else should use shared_material()/tuft_material().
##
## snow_coverage always starts at 0.0 here, regardless of the live
## _snow_coverage value -- shared_material() re-applies the live value right
## after calling this (see its own doc comment); tuft_material() deliberately
## never does, which is the entire mechanism keeping grass sparkle-free.
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
	material.set_shader_parameter("snow_coverage", 0.0)
	material.set_shader_parameter("sparkle_min_value", SnowSparkleShader.SPARKLE_MIN_VALUE)
	material.set_shader_parameter("sparkle_max_saturation", SnowSparkleShader.SPARKLE_MAX_SATURATION)
	SnowSparkleShader.push_shared_uniforms(material)
	return material


## The default-parameter material (trees), built once and shared.
func shared_material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = make_material()
		# Re-apply the live snow coverage a caller may have pushed before any
		# tree existed yet -- see _snow_coverage's own doc comment.
		_shared_material.set_shader_parameter("snow_coverage", _snow_coverage)
	return _shared_material


## The grass/scrub tuft preset (see TUFT_* consts), built once and shared.
##
## Deliberately does NOT re-apply _snow_coverage the way shared_material()
## does -- grass/scrub/blooms stay sparkle-free by construction, always at
## the 0.0 make_material() already set, regardless of build order relative
## to set_snow_coverage. See this file's own header.
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


## Pushes the live weather snow coverage (see EarthChunkManager._snow_depth,
## forwarded via TreeRenderer.set_snow_coverage -- the exact same value the
## ground's own SnowBombShader.snow_depth uniform reads, at the exact same
## call sites) onto shared_material() ONLY -- see this file's own header for
## why tuft_material() must never receive it. Clamped the same way
## SnowBombShader.set_snow_depth clamps its own uniform of the same meaning.
func set_snow_coverage(coverage: float) -> void:
	_snow_coverage = clampf(coverage, 0.0, 1.0)
	if _shared_material != null:
		_shared_material.set_shader_parameter("snow_coverage", _snow_coverage)
