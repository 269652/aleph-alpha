extends RefCounted

const ProceduralRiverFlowSprite = preload("res://src/rendering/procedural_river_flow_sprite.gd")

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
uniform float surface_contrast = 0.50;
uniform float line_stretch = 0.13;
uniform float band_dither = 1.9;
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
uniform float packed_levels = 10.0;
uniform float speed_levels = 2.0;

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

// The surface field, sampled in the channel's OWN frame: `along` runs
// downstream, `across` runs bank to bank.
//
// ANISOTROPIC on purpose, and this is what makes the water read as flowing
// LINES rather than as drifting blobs. Compressing the along-flow axis by
// line_stretch makes every feature roughly 1/line_stretch times longer
// downstream than it is wide, so the field is naturally filamentary --
// streaklines, the way a real current shows itself.
//
// Two octaves, because real water has structure at several scales at once;
// a single octave reads as a lava lamp.
float line_field(float along, float across) {
	vec2 q = vec2(along, across);
	return value_noise(q) * 0.65 + value_noise(q * detail_scale) * 0.35;
}

void fragment() {
	vec4 data = texture(TEXTURE, UV);
	vec2 flow_dir = normalize(data.gb * 2.0 - 1.0 + vec2(1e-6, 0.0));
	vec2 flow_perp = vec2(-flow_dir.y, flow_dir.x);
	float combined = floor(data.a * packed_levels);
	float is_fast = mod(combined, speed_levels);
	float depth_band = floor(combined / speed_levels);

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

	// Keyed to WORLD POSITION alone. A per-tile offset here -- which is
	// what the old baked phase channel was -- would make the noise jump at
	// every tile boundary, a grid of seams across the river. World position
	// already decorrelates every reach continuously and for free.
	// The channel's own frame, with the along-axis ALREADY compressed by
	// line_stretch. Doing the stretch here rather than inside line_field
	// matters more than it looks: it puts `along` in the field's own
	// feature units, so advect_strength below means "how many line-lengths
	// the water travels per phase". Applied the other way round, a drag of
	// 1.15 came out as 0.18 of a feature and the river looked still.
	vec2 world = world_pos * noise_scale;
	float along = dot(world, flow_dir) * line_stretch;
	float across = dot(world, flow_perp);

	// The drag is purely DOWNSTREAM -- water is carried along the channel,
	// never sideways across it.
	float sample_a = line_field(along - advect_strength * phase_a, across);
	float sample_b = line_field(along - advect_strength * phase_b, across);
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
	float band = depth_band + (n - 0.5) * band_dither;
	vec3 body = band0_color;
	body = mix(body, band1_color, step(0.5, band));
	body = mix(body, band2_color, step(1.5, band));
	body = mix(body, band3_color, step(2.5, band));
	body = mix(body, band4_color, step(3.5, band));

	// The advecting surface modulates brightness -- this is the moving
	// water itself, not a mark drawn on top of it.
	float contrast = surface_contrast * mix(0.7, 1.35, is_fast);
	body += vec3((n - 0.5) * contrast);

	// Specular glints on the crests. They appear and vanish with the
	// surface rather than sliding across it, which is what real moving
	// water does to reflected light.
	float glint = smoothstep(glint_threshold, glint_threshold + 0.10, n);
	body = mix(body, glint_color, glint * glint_strength);

	// Whitewater at the shallow bank, where a real river breaks over its
	// own edge -- driven by the SAME advecting field, so the foam travels
	// with the water instead of sitting still.
	float at_edge = 1.0 - step(0.5, band);
	float foam = smoothstep(foam_threshold, foam_threshold + 0.12, n) * at_edge;
	body = mix(body, foam_color, foam);

	COLOR = vec4(body, 1.0);
}
"""

## How fast the advection phase cycles, in Hz. Deliberately slow: this is
## the rate at which the surface renews, not the speed water appears to
## travel (that comes from ADVECT_STRENGTH). It also has to stay well clear
## of aliasing -- at this game's measured ~7 fps floor, 0.35 Hz is 0.05
## cycles/frame, far inside the 0.5 Nyquist limit.
const ADVECT_RATE := 0.35

## How far the surface travels along the flow over one phase, measured in
## the field's OWN feature lengths -- so 1.15 means each line moves a little
## over its own length before its phase resets. This is what reads as the
## water's speed. Above ~1.5 the stretch becomes a visible smear within a
## single phase.
const ADVECT_STRENGTH := 1.15

## Spatial scale of the surface field, and the second octave's multiplier.
##
## Sized so a flow line comes out about four tenths of a tile wide (a tile
## is 32 world px here, NOT 16 -- getting that wrong is what made the first
## correction land at half the intended length). That puts roughly ten lines
## across a four-to-six-tile river. The first attempt used 0.028 -- features
## two tiles wide and fourteen long -- and
## the result read as vast soft gradients sweeping over the water rather
## than as the water itself. A correct technique at the wrong scale looks
## nothing like what it is modelling.
##
## Pinned in TILES rather than as a raw constant, because tiles are the only
## scale that means anything here: see
## test_flow_lines_are_narrow_enough_that_several_fit_across_a_channel.
const NOISE_SCALE := 0.08
const DETAIL_SCALE := 2.7

## How strongly the advecting field brightens and darkens the water.
##
## Sized by a MEASURED RELATION, not by eye: the moving surface must swing
## at least as far in brightness as the whole bank-to-centreline depth
## profile does. Below that parity the static, per-tile depth colour
## dominates any still frame and the river reads as a flat blocky mosaic --
## which is exactly what the first screenshot of this shader showed, with
## the surface at 0.070 against the profile's 0.26. See
## test_the_moving_surface_is_at_least_as_strong_as_the_depth_profile.
const SURFACE_CONTRAST := 0.50

## How far the surface field is stretched ALONG the flow relative to across
## it -- 0.13 makes every feature about eight times longer downstream than it
## is wide, so the field is filamentary and reads as flowing LINES rather
## than as drifting blobs. Requested in exactly those terms ("can you
## flowing lines that morph"): the lines come from this, the morphing from
## the two-phase advection.
const LINE_STRETCH := 0.13

## How far the surface field perturbs the depth-band lookup, in bands.
##
## Also a measured relation rather than a taste: wide enough that a band
## edge can wander at least half a band, which is what stops it lying along
## a straight tile boundary and drawing the tilemap grid. See
## test_band_edges_are_dithered_enough_to_break_the_tile_grid.
const BAND_DITHER := 1.9

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

## Five bands drawing the channel's real parabolic cross-section, light at
## the shallow bank through to dark at the deep centreline. Closer together
## than the stylized pass used them: here they are a depth CUE under a
## moving surface, not the whole look, so hard banding would fight the
## water rather than support it.
const BAND_COLORS: Array[Color] = [
	Color(0.30, 0.60, 0.66),
	Color(0.22, 0.50, 0.62),
	Color(0.16, 0.40, 0.56),
	Color(0.11, 0.31, 0.48),
	Color(0.07, 0.23, 0.40),
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
	material.set_shader_parameter("line_stretch", LINE_STRETCH)
	material.set_shader_parameter("band_dither", BAND_DITHER)
	material.set_shader_parameter("glint_threshold", GLINT_THRESHOLD)
	material.set_shader_parameter("glint_strength", GLINT_STRENGTH)
	material.set_shader_parameter("glint_color", GLINT_COLOR)
	material.set_shader_parameter("foam_threshold", FOAM_THRESHOLD)
	material.set_shader_parameter("foam_color", FOAM_COLOR)
	material.set_shader_parameter("packed_levels", float(ProceduralRiverFlowSprite.PACKED_LEVELS))
	material.set_shader_parameter("speed_levels", float(ProceduralRiverFlowSprite.SPEED_LEVELS))
	for i in BAND_COLORS.size():
		material.set_shader_parameter("band%d_color" % i, BAND_COLORS[i])
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


## Two octaves in the channel's own frame, exactly as the shader mixes
## them: `along` runs downstream, `across` runs bank to bank.
static func surface_value(along: float, across: float) -> float:
	var qx := along * LINE_STRETCH
	return (
		value_noise(qx, across) * 0.65
		+ value_noise(qx * DETAIL_SCALE, across * DETAIL_SCALE) * 0.35
	)


## Mean absolute change in the field over a step of `distance`, taken either
## downstream or bank-to-bank. A filamentary field changes far more slowly
## along the flow than across it -- which is the measurable difference
## between flowing lines and drifting blobs.
static func field_roughness(distance: float, downstream: bool) -> float:
	var total := 0.0
	var count := 0
	for i in range(90):
		for j in range(90):
			var a := float(i) * 0.37
			var c := float(j) * 0.41
			var b := (
				surface_value(a + distance, c) if downstream
				else surface_value(a, c + distance)
			)
			total += absf(b - surface_value(a, c))
			count += 1
	return total / float(count)


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
## channel. This and the length below are what the feature-size tests hold
## to a real number of tiles.
static func feature_width_px() -> float:
	return 1.0 / NOISE_SCALE


## And how long, downstream: the same cell stretched by 1/LINE_STRETCH.
static func feature_length_px() -> float:
	return 1.0 / (NOISE_SCALE * LINE_STRETCH)


## How far the water travels per phase, in its own line lengths. The number
## that decides whether the river reads as moving or as still -- and the one
## that silently came out 6x too small when the anisotropic stretch was
## applied after the drag instead of before it.
static func drag_in_feature_lengths() -> float:
	return ADVECT_STRENGTH
