extends RefCounted

const RiverPhaseField = preload("res://src/world/river_phase_field.gd")
const WaterMovementModel = preload("res://src/gameplay/water_movement_model.gd")
const ProceduralRiverFlowSprite = preload("res://src/rendering/procedural_river_flow_sprite.gd")

## Stylized cartoon river water: the channel's CROSS-SECTION drawn as five
## flat colour bands (light at the shallow edge, dark at the deep
## centreline) with hard-edged white dashes scrolling downstream. See
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
##   * the channel's real parabolic cross-section, in flat bands
##   * short crisp white dashes scrolling downstream, offset row to row
##
## The cross-section is what took this from "a flat slab of colour" to
## something that reads as a channel -- and it is real, not decorative: a
## natural riverbed genuinely IS roughly parabolic, deepest mid-stream (see
## OpenChannelFlow.cross_channel_depth_fraction). Because the bands follow
## distance from the centreline, they curve with the river.
##
## A separate dark BANK OUTLINE was tried and removed. Bank-ness is decided
## per TILE, and one tile is tens of screen pixels at this camera zoom, so a
## near-black outline colour did not draw a line -- it filled whole tiles,
## ate half a four-tile channel and turned the river into a navy staircase.
## The outermost cross-section band is the edge now, which cannot block up.
##
## The real physics still drives all of it -- this is a restyle of the
## OUTPUT, not a retreat from the simulation. The bands come from the real
## solved depth through the real bed profile, the dashes follow the real
## flow direction along the real course phase, and genuinely fast reaches
## get a second mark.
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
uniform vec3 band0_color : source_color = vec3(0.46, 0.78, 0.80);
uniform vec3 band1_color : source_color = vec3(0.32, 0.64, 0.74);
uniform vec3 band2_color : source_color = vec3(0.21, 0.50, 0.66);
uniform vec3 band3_color : source_color = vec3(0.14, 0.37, 0.56);
uniform vec3 band4_color : source_color = vec3(0.09, 0.26, 0.45);
uniform vec3 wave_color : source_color = vec3(0.93, 0.98, 1.0);
uniform float packed_levels = 12.0;
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
	float is_fast = mod(combined, speed_levels);
	float depth_band = floor(combined / speed_levels);

	// The channel's CROSS-SECTION, in five flat bands: light at the shallow
	// edge, darkening to the deep centreline. This is what makes a river
	// read as a channel rather than a flat slab -- and it is real, not
	// decorative, coming from the parabolic bed profile
	// (OpenChannelFlow.cross_channel_depth_fraction). Because the bands
	// follow distance from the centreline, they curve with the river.
	//
	// Hard-selected, never mixed between: a gradient here is exactly what
	// the art direction excludes.
	vec3 body = band0_color;
	body = mix(body, band1_color, step(0.5, depth_band));
	body = mix(body, band2_color, step(1.5, depth_band));
	body = mix(body, band3_color, step(2.5, depth_band));
	body = mix(body, band4_color, step(3.5, depth_band));


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

## Where the fast-water second line sits within the cycle -- half a cycle
## on, so the two lines are evenly spaced rather than crowding.
const FAST_LINE_OFFSET := 0.5

## The flat palette. Deliberately few colours, in EVEN, clearly-separated
## steps (HSV value 0.76 / 0.62 / 0.48 -- 0.14 apart) so the bands read as
## distinct choices rather than as a gradient someone forgot to smooth. Blue-teal throughout, darkening with depth, with the bank
## outline darker still than any water band so it reads as an outline.
## Five flat bands drawing the channel's cross-section, light at the
## shallow edge through to dark at the deep centreline. Even steps in
## brightness so the section reads as deliberate banding rather than a
## gradient someone forgot to smooth.
const BAND_COLORS: Array[Color] = [
	Color(0.46, 0.78, 0.80),
	Color(0.32, 0.64, 0.74),
	Color(0.21, 0.50, 0.66),
	Color(0.14, 0.37, 0.56),
	Color(0.09, 0.26, 0.45),
]
const WAVE_COLOR := Color(0.93, 0.98, 1.0)

## Real current speed at or above which a reach gets its second wave line.
## Anchored to a real figure rather than eyeballed: NIWA/Jowett's instream
## habitat guidance calls 0.3-0.5 m/s "good" flow for stream life, so 0.6
## is comfortably a visibly-moving river rather than a pond.
const FAST_FLOW_M_S := 0.6

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
	material.set_shader_parameter("fast_line_offset", FAST_LINE_OFFSET)
	for i in BAND_COLORS.size():
		material.set_shader_parameter("band%d_color" % i, BAND_COLORS[i])
	material.set_shader_parameter("wave_color", WAVE_COLOR)
	material.set_shader_parameter("packed_levels", float(ProceduralRiverFlowSprite.PACKED_LEVELS))
	material.set_shader_parameter("speed_levels", float(ProceduralRiverFlowSprite.SPEED_LEVELS))
	return material


func shared_material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = make_material()
	return _shared_material


## Which cross-section band a point across the channel falls in: 0 at the
## shallow edge, DEPTH_BANDS-1 at the deep centreline.
##
## Banded by the cross-channel depth FRACTION rather than absolute metres,
## so every river shows a real cross-section -- an absolute scale would
## paint the whole Dreisam (0.31 m mean) a single colour and put the look
## straight back to the flat slab this replaced.
static func cross_section_band_for(depth_fraction: float) -> int:
	var bands := ProceduralRiverFlowSprite.DEPTH_BANDS
	return clampi(int(clampf(depth_fraction, 0.0, 0.999999) * bands), 0, bands - 1)


## Whether a real current is quick enough to earn the second wave line.
static func is_fast_flow(velocity_m_s: float) -> bool:
	return velocity_m_s >= FAST_FLOW_M_S


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
