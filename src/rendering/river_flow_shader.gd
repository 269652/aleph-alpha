extends RefCounted

const RiverPhaseField = preload("res://src/world/river_phase_field.gd")
const WaterMovementModel = preload("res://src/gameplay/water_movement_model.gd")
const ProceduralRiverFlowSprite = preload("res://src/rendering/procedural_river_flow_sprite.gd")

## Stylized cartoon river water: flat colour bands, a bold darker bank
## outline, and hard-edged white wave lines scrolling downstream. See
## docs/concept/rivers.md's "Flow rendering" section.
##
## ART DIRECTION, and why it changed. Earlier passes chased photoreal water
## -- noise-driven turbulence, soft power-curve streaks, alpha gradients,
## speckled foam -- and it kept disappointing, because realism is the wrong
## target for a 16 px top-down pixel-art canvas: every soft gradient and
## noise field fights the chunky, high-contrast, hard-outlined look the rest
## of this game's art already commits to. Requested directly: make it read
## like the flat cel-animated water of a cartoon instead.
##
## So the rules here are deliberate NEGATIVES as much as positives:
##   * NO gradients      -- colour is chosen from a small set of flat bands
##   * NO noise          -- there is not a single hash or value_noise call
##   * NO soft edges     -- every boundary is a step(), never a smoothstep()
## and positively:
##   * flat body colour, quantised by real depth
##   * one bold darker outline colour at the bank
##   * two or three crisp white wave lines that scroll downstream
##
## The real physics still drives all of it -- this is a restyle of the
## OUTPUT, not a retreat from the simulation. The colour band comes from the
## real solved depth (so damming a river visibly darkens it), the wave lines
## follow the real flow direction along the real course phase, and fast
## reaches get an extra line.
##
## OPAQUE, unlike this project's other overlays. WaterShader/HillshadeShader
## deliberately stay translucent so what is underneath shows through, and
## that is right for a decoration -- but this layer IS the river's surface,
## not a decoration on it, and the base water layer beneath is full of the
## very noise and gradients the art direction excludes. A translucent
## stylized layer over a noisy realistic one would read as neither.
##
## The continuous phase field is retained from the previous pass and is
## still load-bearing: hard-edged lines make a phase discontinuity MORE
## obvious, not less, so the wave lines would visibly break at every tile
## edge without it (see RiverPhaseField for the arithmetic).

const SHADER_CODE := """
shader_type canvas_item;

uniform float wavelength_px = 8.8;
uniform float streak_rate_hz = 0.75;
uniform float line_thickness = 0.16;
uniform float fast_line_offset = 0.5;
uniform float dash_row_px = 13.0;
uniform float dash_coverage = 0.55;
uniform float bank_darkening = 0.35;
uniform vec3 shallow_color : source_color = vec3(0.35, 0.71, 0.76);
uniform vec3 mid_color : source_color = vec3(0.18, 0.46, 0.62);
uniform vec3 deep_color : source_color = vec3(0.10, 0.29, 0.48);
uniform vec3 bank_color : source_color = vec3(0.09, 0.27, 0.44);
uniform vec3 wave_color : source_color = vec3(0.93, 0.98, 1.0);
uniform float packed_levels = 12.0;
uniform float bank_levels = 2.0;
uniform float speed_levels = 2.0;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// R = wrapped course phase, G/B = flow direction as a unit vector
	// mapped from [-1,1], A = packed style (depth band, fast flag, bank
	// flag). Style has to travel per-cell, and a TileMapLayer cell can only
	// select an atlas tile -- so it is an atlas dimension, baked into alpha
	// here for the shader to read back.
	vec4 data = texture(TEXTURE, UV);
	float baked_phase = data.r;
	vec2 flow_dir = normalize(data.gb * 2.0 - 1.0 + vec2(1e-6, 0.0));

	float combined = floor(data.a * packed_levels);
	float at_bank = mod(combined, bank_levels);
	float is_fast = mod(floor(combined / bank_levels), speed_levels);
	float depth_band = floor(combined / (bank_levels * speed_levels));

	// Flat body colour by real depth -- three bands, hard-selected. No
	// mixing between them: a gradient here is exactly what the art
	// direction excludes.
	vec3 body = shallow_color;
	body = mix(body, mid_color, step(0.5, depth_band));
	body = mix(body, deep_color, step(1.5, depth_band));

	// The bank cell is drawn slightly darker -- but only slightly. An
	// earlier pass used a near-black outline here and it was the single
	// worst thing on screen: bank-ness is decided PER TILE, and one tile is
	// tens of screen pixels at this camera zoom, so a "thin outline" became
	// a solid dark block eating half the channel and turning the river into
	// a staircase. A real thin outline needs per-PIXEL bank distance, which
	// this layer does not carry (the water overlay beneath does -- see
	// rivers.md). Until then it is a gentle darkening, not an outline.
	body = mix(body, bank_color, at_bank * bank_darkening);

	// Short DASHES, not continuous bands. The first attempt drew an
	// unbroken line across the whole channel wherever the phase came round,
	// which at this camera zoom read as diagonal hazard tape rather than
	// water -- real cartoon water is made of short ticks with gaps, never
	// full-width stripes.
	//
	// So the mark is bounded on BOTH axes: thin along the flow (the line's
	// thickness) and short across it (the dash's length), with alternate
	// rows offset half a step like brickwork so the marks never line up
	// into a visible grid. Brick offset rather than a random jitter keeps
	// this entirely noise-free.
	vec2 across_dir = vec2(-flow_dir.y, flow_dir.x);
	float along = dot(world_pos, flow_dir);
	float across = dot(world_pos, across_dir);

	float row = floor(across / dash_row_px);
	float row_offset = mod(row, 2.0) * 0.5;

	float phase = baked_phase + along / wavelength_px + row_offset - TIME * streak_rate_hz;
	float cycle = fract(phase);
	float along_hit = step(cycle, line_thickness);
	// A second mark half a cycle on, only where the flow is genuinely fast.
	float second = step(cycle, fast_line_offset + line_thickness) * step(fast_line_offset, cycle);
	along_hit = max(along_hit, second * is_fast);

	// The gap across the flow is what turns a stripe into a dash.
	float across_hit = step(fract(across / dash_row_px), dash_coverage);

	float line = along_hit * across_hit;

	COLOR = vec4(mix(body, wave_color, line), 1.0);
}
"""

## Streak wavelength in WORLD PIXELS, derived from the course-space
## wavelength the phase field is built on rather than picked independently
## -- the two must agree or the pattern would advance at one scale and
## repeat at another.
const TILE_SIZE_PX := 16.0
const WAVELENGTH_PX := RiverPhaseField.STREAK_WAVELENGTH_TILES * TILE_SIZE_PX

## What fraction of each cycle is drawn as a wave mark, ALONG the flow.
## Thin enough to read as a drawn tick rather than a band.
const LINE_THICKNESS := 0.13

## How far apart the dash rows sit ACROSS the flow, in world pixels, and how
## much of each row is mark rather than gap. Together these are what make a
## short dash instead of a stripe running the full width of the channel --
## the single worst problem with the first stylized attempt.
const DASH_ROW_PX := 13.0
const DASH_COVERAGE := 0.55

## How strongly a bank cell darkens. Deliberately partial: bank-ness is a
## PER-TILE flag and a tile is tens of screen pixels at the game's camera
## zoom, so a full-strength dark outline reads as a solid block rather than
## a line (it was the worst artefact of the first attempt). See the
## shader's own note.
const BANK_DARKENING := 0.35

## Where the fast-water second line sits within the cycle -- half a cycle
## on, so the two lines are evenly spaced rather than crowding.
const FAST_LINE_OFFSET := 0.5

## The flat palette. Deliberately few colours, in EVEN, clearly-separated
## steps (HSV value 0.76 / 0.62 / 0.48 -- 0.14 apart) so the bands read as
## distinct choices rather than as a gradient someone forgot to smooth. Blue-teal throughout, darkening with depth, with the bank
## outline darker still than any water band so it reads as an outline.
const SHALLOW_COLOR := Color(0.35, 0.71, 0.76)
const MID_COLOR := Color(0.18, 0.46, 0.62)
const DEEP_COLOR := Color(0.10, 0.29, 0.48)
const BANK_COLOR := Color(0.09, 0.27, 0.44)
const WAVE_COLOR := Color(0.93, 0.98, 1.0)

## Real current speed at or above which a reach gets its second wave line.
## Anchored to a real figure rather than eyeballed: NIWA/Jowett's instream
## habitat guidance calls 0.3-0.5 m/s "good" flow for stream life, so 0.6
## is comfortably a visibly-moving river rather than a pond.
const FAST_FLOW_M_S := 0.6

## Depth band thresholds, in real metres -- and these carry real gameplay
## meaning rather than being decorative. The first is
## WaterMovementModel.WADE_DEPTH_METERS itself, so the colour tells you
## whether you can wade across or must swim; the second is simply deeper
## again. Reusing the existing movement threshold rather than inventing a
## second one keeps what the player SEES and what the player CAN DO from
## ever disagreeing.
const MID_BAND_DEPTH_M := WaterMovementModel.WADE_DEPTH_METERS
const DEEP_BAND_DEPTH_M := 3.0

var _shared_material: ShaderMaterial


func make_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("wavelength_px", WAVELENGTH_PX)
	material.set_shader_parameter("streak_rate_hz", RiverPhaseField.STREAK_RATE_HZ)
	material.set_shader_parameter("line_thickness", LINE_THICKNESS)
	material.set_shader_parameter("dash_row_px", DASH_ROW_PX)
	material.set_shader_parameter("dash_coverage", DASH_COVERAGE)
	material.set_shader_parameter("bank_darkening", BANK_DARKENING)
	material.set_shader_parameter("fast_line_offset", FAST_LINE_OFFSET)
	material.set_shader_parameter("shallow_color", SHALLOW_COLOR)
	material.set_shader_parameter("mid_color", MID_COLOR)
	material.set_shader_parameter("deep_color", DEEP_COLOR)
	material.set_shader_parameter("bank_color", BANK_COLOR)
	material.set_shader_parameter("wave_color", WAVE_COLOR)
	material.set_shader_parameter("packed_levels", float(ProceduralRiverFlowSprite.PACKED_LEVELS))
	material.set_shader_parameter("bank_levels", float(ProceduralRiverFlowSprite.BANK_LEVELS))
	material.set_shader_parameter("speed_levels", float(ProceduralRiverFlowSprite.SPEED_LEVELS))
	return material


func shared_material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = make_material()
	return _shared_material


## Which flat colour band a real depth falls in: 0 wadeable, 1 swimmable,
## 2 deep. See MID_BAND_DEPTH_M for why these are the movement thresholds
## rather than decorative ones.
static func depth_band_for(depth_m: float) -> int:
	if depth_m >= DEEP_BAND_DEPTH_M:
		return 2
	if depth_m >= MID_BAND_DEPTH_M:
		return 1
	return 0


## Whether a real current is quick enough to earn the second wave line.
static func is_fast_flow(velocity_m_s: float) -> bool:
	return velocity_m_s >= FAST_FLOW_M_S


## Whether a cell sits on the river's outer edge and should be drawn as the
## bank outline. Derived from the cross-channel distance
## RiverCatalog.nearest_river_at already computes and previously discarded,
## so the outline costs no new geometry work at all.
##
## A hard boundary rather than a falloff, matching the art direction: the
## outermost BANK_OUTLINE_FRACTION of the channel's half-width is outline,
## everything inside it is water.
const BANK_OUTLINE_FRACTION := 0.62


static func is_bank_cell(distance_tiles: float, half_width_tiles: float) -> bool:
	if half_width_tiles <= 0.0:
		return false
	return (distance_tiles / half_width_tiles) >= BANK_OUTLINE_FRACTION


## The CPU mirror of the shader's wave-line test, for headless testing:
## true where a wave line is drawn. Hard-edged by construction -- this
## returns a bool, not an intensity, because the stylized look has no
## partial coverage anywhere.
static func is_wave_line(
	baked_phase: float, along_px: float, time_seconds: float, across_px: float = 0.0
) -> bool:
	var row: float = floor(across_px / DASH_ROW_PX)
	var row_offset: float = fmod(row, 2.0) * 0.5
	var phase := (
		baked_phase + along_px / WAVELENGTH_PX + row_offset
		- time_seconds * RiverPhaseField.STREAK_RATE_HZ
	)
	if fposmod(phase, 1.0) > LINE_THICKNESS:
		return false
	# Bounded ACROSS the flow too -- this is what makes it a dash rather
	# than a stripe spanning the whole channel.
	return fposmod(across_px / DASH_ROW_PX, 1.0) <= DASH_COVERAGE
