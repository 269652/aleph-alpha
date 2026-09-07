extends RefCounted

## Live GPU dissolve from a tree's sapling art into its real mature texture,
## per leaf/clump rather than swept from any one point (reported: "use real
## gpu shading techniques similar to the season transitions per leaf and
## not bottom up" -- a CPU-composited trunk-outward geodesic reveal, the
## same technique growth/season-turn/snow already share (see Procedural
## TreeSprite._trace_order), was tried first and read as a wave sweeping up
## from the ground, not individual branches/leaves coming in).
##
## Composed into WindSway's own shared canopy shader (see that file's own
## header) rather than a standalone material: a tree's canopy sprite
## already carries ONE shader for wind sway + snow sparkle, and this
## project's own precedent for "another live effect on that same sprite" is
## splicing a second GLSL snippet into it (SnowSparkleShader.GLSL_SNIPPET),
## not swapping materials in and out -- which would also fight over the
## single `material` slot a Sprite2D has.
##
## A stochastic per-clump reveal: each small (morph_clump_px) block of the
## canopy independently "flips" from sapling to mature once its own hashed
## roll falls at or below morph_progress, scattered across the whole tree
## rather than advancing outward from any one point -- individual leaves
## and apples switching in, the way this was reported to want to look.

const GLSL_SNIPPET := """
uniform sampler2D morph_sapling_texture : filter_nearest;
// 1.0 (the default) means fully mature -- no sapling texture involved at
// all, and morph_canopy below is a single cheap comparison away from a
// no-op, the same "off by default, near-free when unused" shape
// snow_coverage already has on this same shared shader.
uniform float morph_progress : hint_range(0.0, 1.0) = 1.0;
// Per-tree variance (see ProceduralTreeSprite.tree_variant_for) -- two
// trees at the same morph_progress reveal a DIFFERENT scatter of clumps,
// the same "no two trees look identical while growing" property the
// trunk-outward trace already gave growth/season-turn/snow.
uniform float morph_variant_seed = 0.0;
uniform float morph_clump_px = 2.0;

// Trig-free lattice hash (Hoskins-style), mirroring river_flow_shader.gd's
// own -- see that file's own comment on why sine-based hashing is banned
// in this codebase (a float32 landmine at large inputs). Named without the
// literal formula for the same reason as there: greppable.
float morph_value_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// `mature` is a fragment already sampled at `uv` (COLOR, the canvas_item
// default, already texture(TEXTURE, UV) * modulate) -- reveals it per
// clump once that clump's own hashed roll falls at or below morph_
// progress; the un-revealed sapling picture shows through everywhere
// else. `mature.a` standing at effectively zero (trunk gaps, the canopy's
// own silhouette edge) always shows the sapling regardless of the roll --
// there is nothing "mature" there yet to reveal. `mature_texture_size` is
// taken as an explicit vec2 (not textureSize(TEXTURE, 0) computed in
// here) because Godot's shader compiler cannot pass a built-in sampler
// (TEXTURE) as a function argument -- callers compute it once in
// fragment() itself, the one place TEXTURE is guaranteed valid, exactly
// the same reason WindSway's own fragment() reads COLOR instead of
// re-sampling TEXTURE a second time.
vec4 morph_canopy(vec4 mature, vec2 uv, vec2 mature_texture_size) {
	if (morph_progress >= 1.0) {
		return mature;
	}
	vec4 sapling = texture(morph_sapling_texture, uv);
	// A truly fresh sapling (progress <= 0.0) must show ZERO mature pixels,
	// full stop -- but some clump's hashed roll can land close enough to 0.0
	// that float32 GPU arithmetic (unlike this file's own float64 CPU
	// mirror) rounds it down to exactly 0.0, tripping `roll <= morph_
	// progress` even at progress 0.0 (confirmed live: a 64x64/2px-clump
	// grid's minimum roll sits at ~0.0008 in float64, and the real GPU
	// render smoke test caught it revealing anyway). Short-circuiting here,
	// the same way the >= 1.0 branch above already skips the hash entirely
	// at the opposite end, makes "nothing revealed yet" true by
	// construction instead of by the hash's own low odds.
	if (morph_progress <= 0.0 || mature.a < 0.05) {
		return sapling;
	}
	vec2 texel = uv * mature_texture_size;
	vec2 clump_cell = floor(texel / morph_clump_px);
	float roll = morph_value_hash(clump_cell + vec2(morph_variant_seed));
	if (roll <= morph_progress) {
		return mature;
	}
	return sapling.a > 0.05 ? sapling : vec4(mature.rgb, 0.0);
}
"""

## How large a scattered "clump" of leaves/apples is, in texture pixels --
## matches ProceduralTreeSprite.CLUMP_PX, the same granularity the CPU-
## composited season-turn/growth clump noise already uses, so a tree drawn
## with real clumps of leaves turning together (not a per-pixel sand-storm)
## looks like the same phenomenon whichever mechanism is driving it.
const CLUMP_PX := 2.0


## The exact math morph_value_hash runs, mirrored on the CPU for the same
## reason every other GLSL hash in this codebase is (RiverFlowShader.
## value_hash, WaterShader's own noise) -- a fragment shader cannot be
## asserted headlessly.
static func value_hash(x: float, y: float) -> float:
	var p3x := fposmod(x * 0.1031, 1.0)
	var p3y := fposmod(y * 0.1031, 1.0)
	var p3z := p3x
	var shift := p3x * (p3y + 33.33) + p3y * (p3z + 33.33) + p3z * (p3x + 33.33)
	p3x += shift
	p3y += shift
	p3z += shift
	return fposmod((p3x + p3y) * p3z, 1.0)


## Whether the clump at `(clump_x, clump_y)` (already divided by CLUMP_PX --
## see clump_of) has revealed as mature at `progress`, for `variant_seed`.
## Mirrors morph_canopy's own roll <= morph_progress check exactly, INCLUDING
## its explicit progress <= 0.0 short-circuit -- see that branch's own
## comment for why "nothing revealed yet" must not depend on the hash ever
## landing above zero.
static func clump_is_revealed(
	clump_x: int, clump_y: int, variant_seed: float, progress: float
) -> bool:
	if progress <= 0.0:
		return false
	var roll := value_hash(float(clump_x) + variant_seed, float(clump_y) + variant_seed)
	return roll <= progress


## Which clump cell a texel at `(x, y)` belongs to -- mirrors morph_canopy's
## own `floor(texel / morph_clump_px)`.
static func clump_of(x: int, y: int) -> Vector2i:
	return Vector2i(floori(float(x) / CLUMP_PX), floori(float(y) / CLUMP_PX))


## Pushes the per-tree uniforms morph_canopy needs onto an already-built
## WindSway material -- the sapling texture, this tree's own variant seed
## (see ProceduralTreeSprite.tree_variant_for), and how far through the
## morph it is. Called once per canopy redraw (see ChoppableTree.
## _redraw_canopy), not per frame -- morph_progress moves on the same
## age-driven clock growth/season already redraw on, not a live shader
## clock.
static func apply(
	material: ShaderMaterial, sapling_texture: Texture2D, variant_seed: int, progress: float
) -> void:
	material.set_shader_parameter("morph_sapling_texture", sapling_texture)
	material.set_shader_parameter("morph_variant_seed", float(variant_seed))
	material.set_shader_parameter("morph_progress", progress)
	material.set_shader_parameter("morph_clump_px", CLUMP_PX)


## The material's rest state -- no sapling texture involved, matching a
## fully mature tree that never needed this shown at all (a fresh WindSway
## material has never called apply() and so is already here by the GLSL
## uniform's own default, but callers that stop needing the morph -- a
## tree that reaches full maturity -- call this explicitly, mirroring
## SubmersionShader.clear_waterline's own "explicit off" contract).
static func clear(material: ShaderMaterial) -> void:
	material.set_shader_parameter("morph_progress", 1.0)
