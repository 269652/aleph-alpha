extends RefCounted

## Shared specular-glint mechanism for lying snow -- see docs/concept/
## snow_cover.md, "Sparkle: specular glints on lying snow".
##
## Ground (SnowBombShader) and tree canopy (WindSway's shared tree material)
## each splice GLSL_SNIPPET into their own fragment() and call its
## sparkle_intensity(world_pos, TIME); this module owns only that shared
## WHERE/WHEN twinkle pattern -- a pure function of world position and time,
## knowing nothing about coverage -- plus the canopy colour gate. Each host
## supplies its own GATE deciding which of its own pixels are eligible at
## all (ground: its own already-computed `lying`; canopy: `snow_coverage`
## plus this file's colour gate) -- see test_snow_bomb_shader.gd/
## test_wind_sway.gd for those "no snow -> no sparkle" integration tests.
##
## Pure per-fragment GPU math: no new node, no new draw call, no per-tree or
## per-tile CPU work. sparkle_intensity takes only (x, y, time) -- there is
## no slot in its signature for a tree/tile list or count, which is the
## structural half of "cost cannot scale with world population" (see
## test_sparkle_intensity_is_a_pure_function_of_position_and_time_only).

## -- the shared twinkle pattern ----------------------------------------------

## Candidate sparkle sites sit on their own world-space lattice, deliberately
## FINER than the snow stamp lattice (SnowBombShader.STAMP_LATTICE_WORLD =
## 16.0 world units = one tile) -- ice-crystal glints are a much
## smaller-scale phenomenon than the lumps of snow they sit on.
const SPARKLE_CELL_WORLD := 5.0

## Fraction of lattice sites that are EVER eligible to sparkle at all, each
## decided once by a hash of its own cell (never by world position directly,
## so eligibility doesn't drift as a site's jittered point is computed).
## Measured (test_sparkle_lattice_is_spatially_sparse): combined with the
## point-radius geometry below, well under half of all cells can ever
## sparkle -- most candidate points are simply never eligible, which is what
## keeps the effect reading as scattered points rather than a texture.
const SPARKLE_DENSITY := 0.16

## How far an eligible site's own point may sit from its cell's centre
## (SPARKLE_JITTER_WORLD) and how big the point itself is
## (SPARKLE_POINT_RADIUS_WORLD), both in world units -- a point of light, not
## a patch. Bounded from above by SPARKLE_CELL_WORLD: see
## test_sparkle_point_never_reaches_a_neighbouring_cell, the same "does the
## tuning stay inside its own search" shape SnowBombShader's own
## STAMP_JITTER_WORLD doc comment pins -- nothing here searches neighbouring
## cells (unlike the stamp bombing's 3x3), so a point that could wander past
## its own cell's edge would be silently clipped rather than found.
const SPARKLE_JITTER_WORLD := 1.6
const SPARKLE_POINT_RADIUS_WORLD := 0.55

## Twinkle cycles per second for an eligible site, and how sharply peaked one
## cycle is (a higher exponent means a briefer, brighter flash rather than a
## slow fade -- see test_a_single_eligible_site_mostly_reads_dark_between_
## flashes). Together with the site's own hashed phase offset below, this is
## what makes sparkle TEMPORALLY sparse and desynchronized, on top of being
## spatially sparse.
const SPARKLE_HZ := 0.55
const SPARKLE_DUTY_EXPONENT := 7.0

## Peak additive brightness a flashing site contributes to the colour it
## sits on. Small on purpose: a glint added on top of existing snow colour,
## never a replacement for it (design pillar 1 -- sparkle decorates coverage,
## it never implies it).
const SPARKLE_BRIGHTNESS := 0.55

## -- the canopy colour gate, measured against the real art -------------------

## A canopy pixel must be at least this bright (max channel, i.e. HSV value)
## and at most this saturated to be eligible for sparkle at all. Picked from
## tools/probe_snow_sparkle_colors.gd's real measurement over every
## illustrated species' actual snow frame vs. cherry/apple's actual blossom
## frame (the one colour a snow sparkle must never fire on) -- see
## test_the_colour_gate_separates_real_snow_from_real_blossom for the pinned
## separation this was chosen from. Measured at this threshold: cherry's own
## snow frame passes it 35.7% of its own opaque pixels; cherry's blossom
## frame passes it 0.6% of its own -- a ~57x separation, not a coin flip.
const SPARKLE_MIN_VALUE := 0.85
const SPARKLE_MAX_SATURATION := 0.18


## The trig-free lattice hash -- mirrors SnowBombShader.value_hash exactly
## (see that file's own doc comment for why sine-based hashing is banned at
## this world's real coordinate magnitudes). Duplicated rather than shared by
## reference: GLSL has no cross-file include in how this codebase embeds
## shader source, and the GDScript mirror needs to stand alone for the same
## reason SnowBombShader's own mirror does -- a fragment shader cannot be
## asserted headless.
static func value_hash(x: float, y: float) -> float:
	var p3x := fposmod(x * 0.1031, 1.0)
	var p3y := fposmod(y * 0.1031, 1.0)
	var p3z := p3x
	var shift := p3x * (p3y + 33.33) + p3y * (p3z + 33.33) + p3z * (p3x + 33.33)
	p3x += shift
	p3y += shift
	p3z += shift
	return fposmod((p3x + p3y) * p3z, 1.0)


## The shared twinkle: 0..1, how bright a glint is at this world point right
## now. A pure function of position and time alone -- see this file's own
## header for why that shape matters.
static func sparkle_intensity(world_x: float, world_y: float, time: float) -> float:
	var cell_x := floorf(world_x / SPARKLE_CELL_WORLD)
	var cell_y := floorf(world_y / SPARKLE_CELL_WORLD)
	var site_h := value_hash(cell_x + 5.1, cell_y + 9.7)
	if site_h > SPARKLE_DENSITY:
		return 0.0
	var jitter_x := (value_hash(cell_x + 1.3, cell_y + 2.9) * 2.0 - 1.0) * SPARKLE_JITTER_WORLD
	var jitter_y := (value_hash(cell_x + 4.7, cell_y + 8.3) * 2.0 - 1.0) * SPARKLE_JITTER_WORLD
	var centre_x := (cell_x + 0.5) * SPARKLE_CELL_WORLD + jitter_x
	var centre_y := (cell_y + 0.5) * SPARKLE_CELL_WORLD + jitter_y
	var dist := Vector2(world_x - centre_x, world_y - centre_y).length()
	if dist > SPARKLE_POINT_RADIUS_WORLD:
		return 0.0
	# Phase comes from the SITE's own hash, not world position or time, so
	# neighbouring sites flash at different moments -- the same "hash the
	# site for anything that must desynchronize its neighbours" idea
	# SnowBombShader already uses for stamp variant/level/orientation.
	var phase := value_hash(cell_x + 7.7, cell_y + 3.3) * TAU
	# sin(TIME * ...) for the OSCILLATION itself, not for hashing world
	# position, is the same safe, already-shipped shape WindSway's own
	# vertex() uses (`sin(TIME * wind_speed + phase)`) -- TIME is bounded by
	# Godot's own shader time-rollover, unlike a world coordinate, so this is
	# not the large-coordinate sine-hash failure SnowBombShader's hash was
	# written to avoid (that ban is specifically about hashing *position*
	# with sin, not animating with it).
	var wave := sin(time * SPARKLE_HZ * TAU + phase)
	return pow(maxf(wave, 0.0), SPARKLE_DUTY_EXPONENT)


## HSV value (max channel) -- how bright a colour reads regardless of hue.
static func value_of(color: Color) -> float:
	return maxf(color.r, maxf(color.g, color.b))


## HSV saturation -- how far a colour sits from neutral grey/white, 0..1.
static func saturation_of(color: Color) -> float:
	var mx := value_of(color)
	if mx <= 0.0001:
		return 0.0
	var mn := minf(color.r, minf(color.g, color.b))
	return (mx - mn) / mx


## Whether a canopy pixel's own already-composited colour is eligible for
## sparkle at all -- see SPARKLE_MIN_VALUE/SPARKLE_MAX_SATURATION's own doc
## comment for where these numbers came from and what they were measured
## against.
static func passes_colour_gate(color: Color) -> bool:
	return value_of(color) >= SPARKLE_MIN_VALUE and saturation_of(color) <= SPARKLE_MAX_SATURATION


## -- the GLSL mirror, spliced into each host's own SHADER_CODE --------------
##
## Textually duplicated into two host shaders rather than a runtime #include
## (this codebase embeds shader source as GDScript string constants, with no
## cross-file GLSL include mechanism) -- but every NUMBER in it is a uniform,
## pushed from this file's own consts by each host's make_material(), so the
## tuning itself has exactly one source of truth even though the GLSL text
## exists twice. test_snow_bomb_shader.gd and test_wind_sway.gd each assert
## their own copy is byte-identical to this one, so the two can never
## silently drift apart.
const GLSL_SNIPPET := """
// -- sparkle (see docs/concept/snow_cover.md, "Sparkle") --------------------
uniform float sparkle_cell_world = 5.0;
uniform float sparkle_density = 0.16;
uniform float sparkle_jitter_world = 1.6;
uniform float sparkle_point_radius_world = 0.55;
uniform float sparkle_hz = 0.55;
uniform float sparkle_duty_exponent = 7.0;
uniform float sparkle_brightness = 0.55;

float sparkle_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float sparkle_intensity(vec2 wp, float time) {
	vec2 cell = floor(wp / sparkle_cell_world);
	float site_h = sparkle_hash(cell + vec2(5.1, 9.7));
	if (site_h > sparkle_density) {
		return 0.0;
	}
	vec2 jitter = vec2(
		sparkle_hash(cell + vec2(1.3, 2.9)),
		sparkle_hash(cell + vec2(4.7, 8.3))
	) * 2.0 - 1.0;
	vec2 centre = (cell + vec2(0.5)) * sparkle_cell_world + jitter * sparkle_jitter_world;
	float dist = length(wp - centre);
	if (dist > sparkle_point_radius_world) {
		return 0.0;
	}
	float phase = sparkle_hash(cell + vec2(7.7, 3.3)) * 6.283185307;
	float wave = sin(time * sparkle_hz * 6.283185307 + phase);
	return pow(max(wave, 0.0), sparkle_duty_exponent);
}

float sparkle_value(vec3 rgb) {
	return max(rgb.r, max(rgb.g, rgb.b));
}

float sparkle_saturation(vec3 rgb) {
	float mx = sparkle_value(rgb);
	if (mx <= 0.0001) {
		return 0.0;
	}
	float mn = min(rgb.r, min(rgb.g, rgb.b));
	return (mx - mn) / mx;
}
"""


## Pushes every uniform GLSL_SNIPPET declares, from this file's own consts,
## onto `material` -- called by each host's make_material() so the two can
## never silently disagree about a tuned number. Does NOT push
## `snow_coverage`/gate uniforms specific to one host (e.g. WindSway's own),
## only the shared twinkle pattern's own parameters.
static func push_shared_uniforms(material: ShaderMaterial) -> void:
	material.set_shader_parameter("sparkle_cell_world", SPARKLE_CELL_WORLD)
	material.set_shader_parameter("sparkle_density", SPARKLE_DENSITY)
	material.set_shader_parameter("sparkle_jitter_world", SPARKLE_JITTER_WORLD)
	material.set_shader_parameter("sparkle_point_radius_world", SPARKLE_POINT_RADIUS_WORLD)
	material.set_shader_parameter("sparkle_hz", SPARKLE_HZ)
	material.set_shader_parameter("sparkle_duty_exponent", SPARKLE_DUTY_EXPONENT)
	material.set_shader_parameter("sparkle_brightness", SPARKLE_BRIGHTNESS)
