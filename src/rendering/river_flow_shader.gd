extends RefCounted

const ProceduralRiverFlowSprite = preload("res://src/rendering/procedural_river_flow_sprite.gd")
const RiverCatalog = preload("res://src/world/river_catalog.gd")

## Realistic flowing river water: a surface field advected downstream in
## two crossfaded phases, over the channel's real parabolic cross-section,
## with moving glints and bank whitewater. See docs/concept/rivers.md's
## "Flow rendering" section.
##
## ART DIRECTION, and its history -- worth recording because it went the
## wrong way once and came back.
##
## An earlier pass took this fully stylized: flat cel bands, hard edges, no
## noise, crisp drawn dashes. That was tried on a recommendation of mine and
## was reported plainly as "just some moving strokes, not realistic water
## flow" -- an accurate description, and the fault was structural rather
## than a matter of tuning. A periodic shape TRANSLATED downstream can only
## ever read as marks sliding past, because real water does not translate:
## it continuously DEFORMS.
##
## So the core technique here is two-phase flow-map advection, the standard
## solution to exactly that problem:
##   * the surface field is dragged backward along the flow by an amount
##     growing with each phase's age, so water genuinely stretches as it
##     moves
##   * two phases run half a cycle apart and are crossfaded, so distortion
##     never accumulates past half a cycle
##   * the fade weight peaks exactly when a phase resets, which is what
##     hides the reset -- no repeating period is ever visible
##
## What survived from the stylized pass, because it was right on its own
## merits: the channel's real parabolic CROSS-SECTION (light at the shallow
## bank, dark down the deep centreline). That is genuine physics -- a
## natural riverbed is deepest mid-stream -- and it is what makes a river
## read as a channel rather than a slab, in any style.
##
## What did NOT survive: the "no noise, no gradients, no soft edges" rules.
## Those are exactly what a stylized look needs and exactly what realistic
## moving water cannot do without.
##
## OPAQUE, unlike this project's other overlays. WaterShader/HillshadeShader
## stay translucent because they decorate what is beneath, but this layer IS
## the river's surface.

const SHADER_CODE := """
shader_type canvas_item;

uniform float advect_rate = 0.35;
uniform float advect_strength = 1.15;
uniform float noise_scale = 0.08;
uniform float detail_scale = 2.7;
uniform float surface_contrast = 1.9;
uniform float pixel_snap = 0.5;
uniform float cel_levels = 6.0;
uniform float dither_strength = 0.5;
uniform float ink_width = 0.06;
uniform vec3 ink_color : source_color = vec3(0.05, 0.13, 0.25);
uniform float smear_spacing = 0.8;
uniform float smear_gain = 2.1;
uniform float turbulence_strength = 1.4;
uniform float eddy_scale = 0.16;
uniform float eddy_detail_weight = 0.5;
uniform float across_range = 1.4;
uniform float half_width_tiles = 2.0;
uniform float tile_px = 16.0;
uniform float bank_feather = 0.08;
uniform float glint_threshold = 0.70;
uniform float glint_strength = 0.55;
uniform float foam_threshold = 0.62;
uniform vec3 glint_color : source_color = vec3(0.88, 0.96, 1.0);
uniform vec3 foam_color : source_color = vec3(0.95, 0.99, 1.0);
uniform vec3 band0_color : source_color = vec3(0.30, 0.60, 0.66);
uniform vec3 band1_color : source_color = vec3(0.22, 0.50, 0.62);
uniform vec3 band2_color : source_color = vec3(0.16, 0.40, 0.56);
uniform vec3 band3_color : source_color = vec3(0.11, 0.31, 0.48);
uniform vec3 band4_color : source_color = vec3(0.07, 0.23, 0.40);

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float value_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(value_hash(i), value_hash(i + vec2(1.0, 0.0)), f.x),
		mix(value_hash(i + vec2(0.0, 1.0)), value_hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

// The surface field: an isotropic, WORLD-ANCHORED noise smeared along the
// local flow direction -- a line-integral-convolution stroke.
//
// The smear is what makes the water read as flowing LINES rather than as
// drifting blobs, and doing it by averaging taps (instead of compressing a
// rotated frame axis, as an earlier version did) is what keeps the field
// CONTINUOUS when the direction changes between tiles: direction only
// steers offsets a fraction of a cell long, never a rotation of a
// world-sized coordinate. Averaging squeezes the value distribution toward
// the middle, so smear_gain re-stretches it -- the contrast, glint and
// foam thresholds all assume the field genuinely spans its range.
//
// Two scales, because real water has structure at several at once; the
// fine octave stays unsmeared -- isotropic sparkle riding on the streaks.
float line_field(vec2 q, vec2 flow_dir) {
	float total = 0.0;
	for (int k = -4; k <= 4; k++) {
		total += value_noise(q + flow_dir * (float(k) * smear_spacing));
	}
	float streak = clamp((total / 9.0 - 0.5) * smear_gain + 0.5, 0.0, 1.0);
	// The fine octave gets its own short stroke -- fully isotropic detail
	// would dilute the anisotropy the main smear just built.
	float detail = (
		value_noise(q * detail_scale)
		+ value_noise(q * detail_scale + flow_dir * (smear_spacing * detail_scale))
		+ value_noise(q * detail_scale - flow_dir * (smear_spacing * detail_scale))
	) / 3.0;
	return streak * 0.8 + detail * 0.2;
}

void fragment() {
	vec4 data = texture(TEXTURE, UV);
	vec2 flow_dir = normalize(data.gb * 2.0 - 1.0 + vec2(1e-6, 0.0));
	vec2 flow_perp = vec2(-flow_dir.y, flow_dir.x);
	float is_fast = step(0.5, data.a);

	// PIXEL ART renders on the art-pixel grid: every sample below starts
	// from the snapped position, so no gradient is ever smoother than one
	// art pixel -- sub-pixel shading is what makes shader water look
	// painted-on next to chunky sprite terrain. pixel_snap is one ART
	// pixel derived from the real tile sizes, not an invented chunkiness.
	vec2 wp = floor(world_pos / pixel_snap) * pixel_snap + vec2(pixel_snap * 0.5);

	// CONTINUOUS CROSS-SECTION -- the fix for "still a lot of individual
	// squares". The tile bakes only its CENTRE's signed cross-channel
	// offset (R); every fragment reconstructs its own by adding where it
	// sits WITHIN the tile, projected on the flow perpendicular. Depth is
	// then a per-pixel quantity: the parabola glides straight through tile
	// boundaries instead of jumping a whole quantized band at each edge.
	vec2 cell_center = (floor(wp / tile_px) + vec2(0.5)) * tile_px;
	vec2 delta_tiles = (wp - cell_center) / tile_px;
	float frag_across = (data.r * 2.0 - 1.0) * across_range
		+ dot(delta_tiles, flow_perp) / half_width_tiles;
	float rr = abs(frag_across);
	float depth_frac = clamp(1.0 - rr * rr, 0.0, 1.0);

	// TWO-PHASE FLOW-MAP ADVECTION -- the technique that makes this read as
	// water rather than as a pattern sliding past.
	//
	// The previous version translated a periodic shape downstream, which is
	// exactly what "just some moving strokes" describes: real water does not
	// TRANSLATE, it continuously DEFORMS. Here the surface field is dragged
	// backward along the flow by an amount that grows with each phase's age,
	// so the water genuinely stretches as it moves. Left alone that
	// distortion would smear without bound, so two phases run half a cycle
	// apart and are crossfaded, each resetting while the other carries the
	// image -- distortion never exceeds half a cycle, and because the fade
	// weight peaks exactly when a phase resets, the reset itself is
	// invisible. No repeating period is ever visible.
	float t = TIME * advect_rate;
	float phase_a = fract(t);
	float phase_b = fract(t + 0.5);

	// Keyed to WORLD POSITION alone -- per-tile offsets would seam the
	// noise at every tile boundary, and (the harder-won lesson) so would
	// any coordinate built by PROJECTING the world position onto the flow
	// frame: a rotation about the world origin moves a point by angle
	// times its distance from the origin, which out here is thousands of
	// tiles per direction bin. Every sample below starts from p itself;
	// direction only steers offsets a fraction of a cell long.
	vec2 p = wp * noise_scale;

	// STANDING TURBULENCE -- what makes this fluid rather than a conveyor.
	//
	// Real turbulence over a rough riverbed organises into quasi-stationary
	// structures: boils and standing eddies shed from bedforms hold their
	// station while the water pours through them (Jackson 1976). So the
	// bend field is anchored to the BED -- unadvected world coordinates --
	// not carried with the water. The surface streams past and is
	// continuously re-bent as it goes, so the lines visibly snake, curl
	// and deform WHILE they travel.
	//
	// Two octaves: the coarse one swings whole bundles of lines, the fine
	// one puts kinks WITHIN a line's own length.
	vec2 eddy_p = p * eddy_scale;
	float bend = (value_noise(eddy_p) - 0.5
		+ (value_noise(eddy_p * 2.6 + vec2(19.7, 7.3)) - 0.5) * eddy_detail_weight)
		* turbulence_strength;
	vec2 q = p + flow_perp * bend;

	// The drag is purely DOWNSTREAM -- water is carried along the channel,
	// never sideways across it.
	float sample_a = line_field(q - flow_dir * (advect_strength * phase_a), flow_dir);
	float sample_b = line_field(q - flow_dir * (advect_strength * phase_b), flow_dir);
	// Triangular weight: 1 at a phase's birth, 0 at its death.
	float blend = abs(1.0 - 2.0 * phase_a);
	float n = mix(sample_a, sample_b, blend);

	// Depth colour: the channel's real parabolic cross-section (see
	// OpenChannelFlow.cross_channel_depth_fraction), light at the shallow
	// bank, dark down the deep centreline.
	//
	// DITHERED by the same advecting field, and that is not decoration. The
	// depth band is decided per TILE, so undithered band edges fall exactly
	// on tile boundaries -- and a tile is tens of screen pixels here, so
	// they draw the tilemap grid straight across the river. Perturbing the
	// index lets each edge wander over half a band, breaking it into a
	// ragged, moving line that no longer coincides with the lattice.
	// THE COMIC / 16-BIT PASS. One continuous shade -- the reconstructed
	// depth pushed around by the advecting surface -- quantized into a
	// handful of flat cel levels. Because the shade rides the moving
	// field, the cel boundaries wobble, flow and morph like hand-animated
	// water; because everything upstream of the quantizer is continuous
	// and world-anchored, no boundary can ever fall along the tile grid.
	// (The first stylized attempt died of a translating pattern UNDER the
	// flat colours -- the flat colours were never the problem.)
	float contrast = surface_contrast * mix(0.7, 1.35, is_fast);
	float shade = clamp(depth_frac - (n - 0.5) * contrast * 0.5, 0.0, 1.0);

	// Classic ordered dither: the checkerboard's other phase shifts the
	// quantization threshold half a step, so band boundaries interleave in
	// a 2x2 weave -- the 16-bit way to suggest a gradient with flat inks.
	float checker = mod(floor(wp.x / pixel_snap) + floor(wp.y / pixel_snap), 2.0);
	float level = clamp(
		floor(shade * cel_levels + (checker - 0.5) * dither_strength),
		0.0, cel_levels - 1.0
	);
	float cel_t = level / (cel_levels - 1.0);

	float sramp = cel_t * 4.0;
	vec3 body = mix(band0_color, band1_color, clamp(sramp, 0.0, 1.0));
	body = mix(body, band2_color, clamp(sramp - 1.0, 0.0, 1.0));
	body = mix(body, band3_color, clamp(sramp - 2.0, 0.0, 1.0));
	body = mix(body, band4_color, clamp(sramp - 3.0, 0.0, 1.0));

	// Specular glints on the crests. They appear and vanish with the
	// surface rather than sliding across it, which is what real moving
	// water does to reflected light.
	float glint = smoothstep(glint_threshold, glint_threshold + 0.10, n);
	body = mix(body, glint_color, glint * glint_strength);

	// Whitewater hugging the real reconstructed bank, where a river breaks
	// over its own edge -- driven by the SAME advecting field, so the foam
	// travels with the water instead of sitting still.
	float at_edge = smoothstep(0.72, 0.96, rr);
	float foam = smoothstep(foam_threshold, foam_threshold + 0.12, n) * at_edge;
	body = mix(body, foam_color, foam);

	// The comic INK line: a dark outline hugging the real bank curve, just
	// inside the waterline. The old stylized attempt drew its outline per
	// TILE and it became a black block eating half the channel; this one
	// is a function of the reconstructed |across|, so it is exactly as
	// smooth as the shoreline itself.
	float ink = smoothstep(1.0 - ink_width, 1.0 - ink_width * 0.4, rr);
	body = mix(body, ink_color, ink);

	// The SHORELINE: opaque water inside the channel, a short feather at
	// the bank curve, nothing past it -- the ground simply shows through.
	// This is what frees the water's outline from the tile grid: the edge
	// is |across| == 1, a smooth curve through the middle of tiles, not
	// the rectangle of whichever cells happened to be painted.
	float wet = 1.0 - smoothstep(1.0 - bank_feather, 1.0 + bank_feather, rr);
	COLOR = vec4(body, wet);
}
"""

## How fast the advection phase cycles, in Hz. Deliberately slow: this is
## the rate at which the surface renews, not the speed water appears to
## travel (that comes from ADVECT_STRENGTH). It also has to stay well clear
## of aliasing -- at this game's measured ~7 fps floor, 0.35 Hz is 0.05
## cycles/frame, far inside the 0.5 Nyquist limit.
const ADVECT_RATE := 0.35

## How far the surface travels along the flow over one phase, in noise
## CELLS. Sized against the smear length so each line travels a bit over
## its own length per phase (see drag_in_feature_lengths) -- that is what
## reads as the water speed.
const ADVECT_STRENGTH := 5.5

## Spatial scale of the surface field, and the second octave's multiplier.
##
## Sized so a flow line comes out under a world tile wide, which puts
## several lines across a four-to-six-tile river. The first attempt used
## 0.028 -- features two tiles wide and fourteen long -- and
## the result read as vast soft gradients sweeping over the water rather
## than as the water itself. A correct technique at the wrong scale looks
## nothing like what it is modelling.
##
## Pinned in TILES rather than as a raw constant, because tiles are the only
## scale that means anything here: see
## test_flow_lines_are_narrow_enough_that_several_fit_across_a_channel.
const NOISE_SCALE := 0.08
const DETAIL_SCALE := 2.7

## The line-integral-convolution stroke: how many world-anchored taps are
## averaged along the flow, and how far apart (in noise cells). Taps closer
## than a cell overlap into one continuous streak; the smear length,
## (SMEAR_TAPS - 1) * SMEAR_SPACING + 1 cells, is what feature_length_px
## reports. Averaging compresses the value distribution, so SMEAR_GAIN
## re-stretches it -- held to the measured coverage and swing bands by the
## same tests that pinned the old field.
const SMEAR_TAPS := 9
const SMEAR_SPACING := 0.7
const SMEAR_GAIN := 2.6

## How strongly the advecting field pushes the cel shade around, in SHADE
## units (the quantizer input, 0 lightest to 1 darkest).
##
## Sized by a MEASURED RELATION, not by eye: the surface's real p05..p95
## swing times this must reach 1.0 -- the surface can drive the shade
## across the WHOLE palette. Anything less and static depth colour
## dominates every still frame, which is the "blocky, not water" failure
## this shader crawled out of. See
## test_the_moving_surface_can_span_the_whole_palette.
const SURFACE_CONTRAST := 1.9

## One ART pixel, in world px -- TILE_SIZE world px carry ART_TILE_SIZE art
## px, so this is their ratio, pinned against TerrainRenderer rather than
## invented. All sampling snaps to this grid: sub-pixel gradients are what
## make shader water look painted-on next to chunky sprite terrain.
const PIXEL_SNAP := 0.5

## The 16-bit palette: how many flat cel levels the shade quantizes into,
## and how far the 2x2 checker phase shifts the threshold (the classic
## ordered-dither weave at every band boundary).
const CEL_LEVELS := 6
const DITHER_STRENGTH := 0.5

## The comic ink outline at the waterline: width as a fraction of the
## half-width (bounded in ART pixels by test -- too thin reads as noise,
## too fat becomes the old per-tile black block), and its colour, darker
## than the deepest water so it reads as a drawn line.
const INK_WIDTH := 0.06
const INK_COLOR := Color(0.05, 0.13, 0.25)

## How hard the standing eddies bend the streaklines, in line widths of
## across-displacement at full noise swing, and how coarse the eddies are
## relative to the lines (0.16 = one eddy spans about six line widths, so
## neighbouring lines bend TOGETHER -- curling, not shredding).
##
## Bounded from both sides by measurement: RMS displacement is held to a
## band (test_streaklines_are_bent_by_a_real_measured_amount), the warp is
## verified never to fold the surface over itself -- the re-applied
## defect-3 lesson: past the fold threshold displacement does not bend a
## pattern, it destroys it -- and the bent field must still read as lines
## (test_the_warped_field_still_forms_lines).
const TURBULENCE_STRENGTH := 1.4
const EDDY_SCALE := 0.16

## The bend's second, finer octave (2.6x the eddy scale). The coarse octave
## alone was measurably correct and visually invisible: it shifts
## neighbouring lines TOGETHER, which locally reads as translation. Kinks a
## viewer can see need bend variation WITHIN a line's own length -- pinned
## by test_a_streakline_visibly_curves_within_its_own_length.
const EDDY_DETAIL_WEIGHT := 0.5

## The world tile size the reconstruction divides by -- the layer is
## scaled by TerrainRenderer.LAYER_SCALE, so world_pos in the shader is in
## FINAL world pixels where a tile is TerrainRenderer.TILE_SIZE (16), NOT
## the 32 px art tile. Pinned against TerrainRenderer by test; getting it
## wrong doubles or halves every reconstructed offset.
const TILE_PX := 16.0

## Half-width of the waterline's feather, in across-fraction units --
## 0.08 of a 2-tile half-width is ~2.5 world px of soft edge. Must stay
## inside the painter's apron (test_the_feather_fits_inside_the_painted_
## apron) or the fade gets clipped by the last painted cell and the
## straight edge returns.
const BANK_FEATHER := 0.08

## Where crest glints begin, and how bright they get. Glints appear and
## vanish with the surface rather than sliding across it, which is what
## moving water does to reflected light.
const GLINT_THRESHOLD := 0.70
const GLINT_STRENGTH := 0.55
const GLINT_COLOR := Color(0.88, 0.96, 1.0)

## Where bank whitewater begins. Driven by the same advecting field as the
## surface, so foam travels WITH the water instead of sitting still -- a
## static foam texture is one of the clearest tells of fake water.
const FOAM_THRESHOLD := 0.62
const FOAM_COLOR := Color(0.95, 0.99, 1.0)

## Five RAMP STOPS -- no longer bands -- drawing the channel's real
## parabolic cross-section as one continuous gradient, light at the shallow
## bank through to dark at the deep centreline. The last banded version
## still read as per-tile rectangles, because the band INDEX was a per-tile
## quantity; the ramp is evaluated per fragment from the reconstructed
## depth, so there is no index left to jump at a tile edge.
## Punchier than the realistic pass used -- comic water is saturated inks,
## not atmospheric greys -- while keeping the same shallow-to-deep order
## the darken test pins.
const BAND_COLORS: Array[Color] = [
	Color(0.42, 0.76, 0.80),
	Color(0.28, 0.62, 0.74),
	Color(0.18, 0.47, 0.66),
	Color(0.12, 0.34, 0.56),
	Color(0.08, 0.23, 0.44),
]

## Real current speed at or above which a reach reads as fast -- it gets a
## stronger, higher-contrast surface. Anchored to a real figure rather than
## eyeballed: NIWA/Jowett instream-habitat guidance calls 0.3-0.5 m/s "good"
## flow, so 0.6 is comfortably a visibly-moving river rather than a pond.
const FAST_FLOW_M_S := 0.6

var _shared_material: ShaderMaterial


func make_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("advect_rate", ADVECT_RATE)
	material.set_shader_parameter("advect_strength", ADVECT_STRENGTH)
	material.set_shader_parameter("noise_scale", NOISE_SCALE)
	material.set_shader_parameter("detail_scale", DETAIL_SCALE)
	material.set_shader_parameter("surface_contrast", SURFACE_CONTRAST)
	material.set_shader_parameter("pixel_snap", PIXEL_SNAP)
	material.set_shader_parameter("cel_levels", float(CEL_LEVELS))
	material.set_shader_parameter("dither_strength", DITHER_STRENGTH)
	material.set_shader_parameter("ink_width", INK_WIDTH)
	material.set_shader_parameter("ink_color", INK_COLOR)
	material.set_shader_parameter("smear_spacing", SMEAR_SPACING)
	material.set_shader_parameter("smear_gain", SMEAR_GAIN)
	material.set_shader_parameter("turbulence_strength", TURBULENCE_STRENGTH)
	material.set_shader_parameter("eddy_scale", EDDY_SCALE)
	material.set_shader_parameter("eddy_detail_weight", EDDY_DETAIL_WEIGHT)
	material.set_shader_parameter("across_range", ProceduralRiverFlowSprite.ACROSS_RANGE)
	material.set_shader_parameter("half_width_tiles", RiverCatalog.RIVER_HALF_WIDTH_TILES)
	material.set_shader_parameter("tile_px", TILE_PX)
	material.set_shader_parameter("bank_feather", BANK_FEATHER)
	material.set_shader_parameter("glint_threshold", GLINT_THRESHOLD)
	material.set_shader_parameter("glint_strength", GLINT_STRENGTH)
	material.set_shader_parameter("glint_color", GLINT_COLOR)
	material.set_shader_parameter("foam_threshold", FOAM_THRESHOLD)
	material.set_shader_parameter("foam_color", FOAM_COLOR)
	for i in BAND_COLORS.size():
		material.set_shader_parameter("band%d_color" % i, BAND_COLORS[i])
	return material


func shared_material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = make_material()
	return _shared_material


## A fragment's reconstructed signed across-offset: the tile centre's baked
## value plus the fragment's own within-tile delta (in tiles, along the
## flow perpendicular) over the half-width. The CPU mirror of the shader's
## reconstruction, and what the tile-edge continuity test sweeps.
static func reconstructed_across(center_fraction: float, delta_perp_tiles: float) -> float:
	return center_fraction + delta_perp_tiles / RiverCatalog.RIVER_HALF_WIDTH_TILES


## The continuous depth ramp -- the five palette stops blended by the
## reconstructed depth fraction, exactly as the shader mixes them. No band
## index exists any more, which is precisely the point.
static func depth_color(depth_fraction: float) -> Color:
	var sramp := clampf(depth_fraction, 0.0, 1.0) * 4.0
	var body := BAND_COLORS[0].lerp(BAND_COLORS[1], clampf(sramp, 0.0, 1.0))
	body = body.lerp(BAND_COLORS[2], clampf(sramp - 1.0, 0.0, 1.0))
	body = body.lerp(BAND_COLORS[3], clampf(sramp - 2.0, 0.0, 1.0))
	return body.lerp(BAND_COLORS[4], clampf(sramp - 3.0, 0.0, 1.0))


## The waterline: 1 inside the channel, 0 past the bank curve, feathered
## over BANK_FEATHER either side of |across| == 1.
static func bank_alpha(across_magnitude: float) -> float:
	return 1.0 - smoothstep(1.0 - BANK_FEATHER, 1.0 + BANK_FEATHER, across_magnitude)


## The cel quantizer, mirroring the shader exactly: shade in [0, 1],
## checker 0.0 or 1.0 (the 2x2 dither phase), out comes the flat level.
static func cel_level(shade: float, checker: float) -> int:
	return clampi(
		int(floor(clampf(shade, 0.0, 1.0) * float(CEL_LEVELS) + (checker - 0.5) * DITHER_STRENGTH)),
		0, CEL_LEVELS - 1
	)


## The full shade pipeline for one (depth, surface) pair -- what the cel
## boundary tests sweep to prove the bands follow the MOVING field.
static func cel_level_for(depth_fraction: float, n: float, checker: float) -> int:
	return cel_level(depth_fraction - (n - 0.5) * SURFACE_CONTRAST * 0.5, checker)


## Whether a real current is quick enough to read as fast-moving -- such a
## reach gets a higher-contrast surface, which is how speed shows now that
## nothing translates across the screen.
static func is_fast_flow(velocity_m_s: float) -> bool:
	return velocity_m_s >= FAST_FLOW_M_S


## The CPU mirror of the shader's two-phase crossfade, for headless testing.
##
## Returns the weight given to PHASE B -- the one running half a cycle ahead
## -- with phase A taking 1.0 minus it. Read the direction carefully: this
## is 1.0 at the moment phase A resets, which is precisely when phase A must
## contribute NOTHING.
##
## That is the property the whole technique rests on. A phase resetting
## snaps back to zero drag, a discontinuity in the image it carries; the
## triangular weight lands a zero on whichever phase is resetting, so the
## discontinuity is multiplied out and the reset is invisible. It is why
## the water has no visible period at all, which a scrolling pattern cannot
## manage by construction.
static func crossfade_weight(time_seconds: float) -> float:
	return absf(1.0 - 2.0 * fposmod(time_seconds * ADVECT_RATE, 1.0))


## How far the surface has been dragged along the flow at a given time, in
## noise-space units -- bounded by ADVECT_STRENGTH by construction, which
## is what stops distortion accumulating into a smear.
static func advection_offset(time_seconds: float) -> float:
	return fposmod(time_seconds * ADVECT_RATE, 1.0) * ADVECT_STRENGTH


## The CPU mirror of the shader's `value_hash`/`value_noise`/`surface`, so
## the glint and foam thresholds can be MEASURED rather than eyeballed.
##
## Those two thresholds decide what fraction of the water sparkles and what
## fraction of the bank breaks white, and a threshold picked by eye can be
## wrong in a way that is invisible in a still frame and ruinous in motion:
## set too high nothing ever fires and the surface goes flat again, too low
## and the whole river whites out. `surface_coverage_above` turns that into
## a number a test can hold to a range.
##
## GDScript runs 64-bit floats where the shader runs 32-bit, so individual
## samples can differ in the last places -- this mirrors the DISTRIBUTION,
## which is what the coverage bounds are about, not any single pixel.
static func value_hash(x: float, y: float) -> float:
	return fposmod(sin(x * 127.1 + y * 311.7) * 43758.5453, 1.0)


static func value_noise(x: float, y: float) -> float:
	var ix: float = floor(x)
	var iy: float = floor(y)
	var fx: float = x - ix
	var fy: float = y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	return lerpf(
		lerpf(value_hash(ix, iy), value_hash(ix + 1.0, iy), fx),
		lerpf(value_hash(ix, iy + 1.0), value_hash(ix + 1.0, iy + 1.0), fx),
		fy
	)


## The CPU mirror of the shader's line_field: the LIC smear along an
## arbitrary direction plus the unsmeared detail octave, world-anchored.
static func line_field_value(px: float, py: float, dir: Vector2) -> float:
	var total := 0.0
	for k in range(-4, 5):
		var offset := dir * (float(k) * SMEAR_SPACING)
		total += value_noise(px + offset.x, py + offset.y)
	var streak := clampf((total / float(SMEAR_TAPS) - 0.5) * SMEAR_GAIN + 0.5, 0.0, 1.0)
	var dx := px * DETAIL_SCALE
	var dy := py * DETAIL_SCALE
	var stroke := dir * (SMEAR_SPACING * DETAIL_SCALE)
	var detail := (
		value_noise(dx, dy)
		+ value_noise(dx + stroke.x, dy + stroke.y)
		+ value_noise(dx - stroke.x, dy - stroke.y)
	) / 3.0
	return streak * 0.8 + detail * 0.2


## The field flowing east -- the direction-free convenience the coverage
## and swing measurements sample (the distribution is direction-invariant;
## the seam test is where direction sensitivity is measured).
static func surface_value(px: float, py: float) -> float:
	return line_field_value(px, py, Vector2(1, 0))


## The whole animated pipeline at one world point (in noise cells): the
## standing bend, both advected phases, the crossfade. What the seam test
## compares across a direction-bin change.
static func animated_field_value(px: float, py: float, dir: Vector2, time_seconds: float) -> float:
	var perp := Vector2(-dir.y, dir.x)
	var b := bend_displacement(px * EDDY_SCALE, py * EDDY_SCALE)
	var qx := px + perp.x * b
	var qy := py + perp.y * b
	var phase_a := fposmod(time_seconds * ADVECT_RATE, 1.0)
	var phase_b := fposmod(time_seconds * ADVECT_RATE + 0.5, 1.0)
	var sample_a := line_field_value(
		qx - dir.x * ADVECT_STRENGTH * phase_a, qy - dir.y * ADVECT_STRENGTH * phase_a, dir
	)
	var sample_b := line_field_value(
		qx - dir.x * ADVECT_STRENGTH * phase_b, qy - dir.y * ADVECT_STRENGTH * phase_b, dir
	)
	return lerpf(sample_a, sample_b, absf(1.0 - 2.0 * phase_a))


## Mean absolute change in the field over a step of `distance`, taken either
## along `dir` or perpendicular to it. A filamentary field changes far more
## slowly along the flow than across it -- the measurable difference
## between flowing lines and drifting blobs, for ANY bearing.
static func field_roughness(distance: float, dir: Vector2, downstream: bool) -> float:
	var perp := Vector2(-dir.y, dir.x)
	var step := (dir if downstream else perp) * distance
	var total := 0.0
	var count := 0
	for i in range(90):
		for j in range(90):
			var a := float(i) * 0.37
			var c := float(j) * 0.41
			total += absf(
				line_field_value(a + step.x, c + step.y, dir) - line_field_value(a, c, dir)
			)
			count += 1
	return total / float(count)


## The standing-eddy bend at a point, in line widths -- the CPU mirror of
## the shader's `bend * turbulence_strength`. Anchored to unadvected
## coordinates, exactly as the shader anchors it to the bed.
static func bend_displacement(eddy_x: float, eddy_y: float) -> float:
	var coarse := value_noise(eddy_x, eddy_y) - 0.5
	var fine := value_noise(eddy_x * 2.6 + 19.7, eddy_y * 2.6 + 7.3) - 0.5
	return (coarse + fine * EDDY_DETAIL_WEIGHT) * TURBULENCE_STRENGTH


## Where a point lands, on the axis the bend pushes along, after the bend
## -- the no-fold sweep runs on this: if it ever decreases while the input
## increases, the warp has folded the surface over itself.
static func warped_across(world_x: float, world_y: float) -> float:
	return world_y + bend_displacement(world_x * EDDY_SCALE, world_y * EDDY_SCALE)


## The full at-rest pipeline: bend, then the smeared line field -- what a
## fragment shows for an eastward flow at time zero.
static func warped_surface_value(world_x: float, world_y: float) -> float:
	return surface_value(world_x, warped_across(world_x, world_y))


## Fraction of the water surface whose field exceeds `threshold` -- i.e. how
## much of the river a threshold at that level actually lights up.
static func surface_coverage_above(threshold: float, samples: int = 120) -> float:
	var hits := 0
	for i in samples:
		for j in samples:
			# Spread over many noise cells so this measures the field's own
			# distribution rather than one lucky patch of it.
			var x := float(i) * 0.37
			var y := float(j) * 0.41
			if surface_value(x, y) > threshold:
				hits += 1
	return float(hits) / float(samples * samples)


## The surface field's real p05..p95 swing -- how much of a brightness range
## the moving water actually covers in practice.
##
## NOT its 0..1 theoretical range, which is what makes this worth measuring:
## two averaged octaves cluster hard around the middle, so the field only
## spans about half its nominal range. Sizing the contrast against 0..1
## instead is exactly how the moving surface ended up 3.7x weaker than the
## static banding and the river rendered as a flat mosaic.
static func surface_swing(samples: int = 140) -> float:
	var values: Array[float] = []
	for i in samples:
		for j in samples:
			values.append(surface_value(float(i) * 0.37, float(j) * 0.41))
	values.sort()
	return values[int(values.size() * 0.95)] - values[int(values.size() * 0.05)]


## Brightness span of the depth profile, bank to centreline -- the static,
## per-tile signal the moving surface has to compete with.
static func depth_profile_span() -> float:
	return BAND_COLORS[0].v - BAND_COLORS[BAND_COLORS.size() - 1].v


## How wide one flow line is, in world pixels -- one noise cell across the
## channel (the smear elongates along the flow only). This and the length
## below are what the feature-size tests hold to a real number of tiles.
static func feature_width_px() -> float:
	return 1.0 / NOISE_SCALE


## And how long, downstream: the base cell plus the smear stroke.
static func feature_length_px() -> float:
	return (1.0 + float(SMEAR_TAPS - 1) * SMEAR_SPACING) / NOISE_SCALE


## How far the water travels per phase, in its own line lengths. The number
## that decides whether the river reads as moving or as still.
static func drag_in_feature_lengths() -> float:
	return ADVECT_STRENGTH / (1.0 + float(SMEAR_TAPS - 1) * SMEAR_SPACING)
