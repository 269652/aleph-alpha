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

uniform float advect_rate = 0.22;
uniform float advect_strength = 7.2;
uniform float noise_scale = 0.08;
uniform float pixel_snap = 0.5;
uniform float cel_levels = 6.0;
uniform float dither_strength = 0.5;
uniform float ink_width = 0.06;
uniform vec3 ink_color : source_color = vec3(0.05, 0.13, 0.25);
uniform float line_count = 3.0;
uniform float across_line_scale = 1.0;
uniform float line_wobble = 0.6;
uniform float line_width = 0.03;
uniform float line_strength = 0.7;
uniform vec3 line_color : source_color = vec3(0.85, 0.97, 1.0);
uniform vec3 line_color_deep : source_color = vec3(0.07, 0.26, 0.48);
uniform float night_lift = 0.0;
uniform float night_stroke_boost = 2.2;
uniform vec3 moonlight_ink : source_color = vec3(0.92, 0.96, 1.0);
uniform float shore_pos = 0.88;
uniform float shore_width = 0.025;
uniform float smear_spacing = 0.8;
uniform float smear_gain = 2.0;
uniform float turbulence_strength = 1.6;
uniform float eddy_scale = 0.16;
uniform float eddy_detail_weight = 0.7;
uniform float eddy_swirl = 0.0;
uniform float bank_shear = 0.25;
uniform sampler2D flow_across_map : filter_linear, repeat_enable;
uniform float flow_map_tiles = 256.0;
## No longer read inside fragment(): every per-fragment normalization now
## decodes the tile's REAL local half-width from the direction vector's own
## magnitude (see map_data's doc comment below). Kept declared, with its
## default still set from _apply_defaults, only so nothing external
## resolving this material's parameters by name breaks; harmless as an
## unused uniform.
uniform float half_width_tiles = 2.0;
uniform float tile_px = 16.0;
uniform float bank_feather = 0.03;
uniform float across_jitter = 0.045;
uniform float jitter_scale = 2.0;
uniform int boulder_count = 0;
uniform vec2 boulders[24];
uniform float boulder_reach_px = 40.0;
uniform float boulder_radius_px = 11.0;
uniform float boulder_halo_width_px = 6.0;
uniform float boulder_halo_alpha = 0.6;

// The waders -- the player and any creatures standing in river water,
// fed per frame by EarthChunkManager.set_river_flow_waders. Soft moving
// obstacles that never dry the water.
uniform int wader_count = 0;
uniform vec2 waders[16];
// Expanding rings from water disturbances (a fish's tail flap, the
// player's stroke -- EarthChunkManager.record_water_disturbance), each
// (x, y, birth time): a travelling bulge in the across field, so the
// contour strokes ring outward from the source and fade.
uniform int ripple_count = 0;
uniform vec3 ripples[24];
uniform float ripple_speed_px = 18.0;
uniform float ripple_width_px = 10.0;
uniform float ripple_amplitude_px = 1.5;
uniform float ripple_lifetime = 2.5;
uniform float wader_reach_px = 26.0;
uniform float wader_radius_px = 6.0;
uniform float wader_wake_trail = 0.8;

// Continuous downstream travel, px/s per m/s of real current.
uniform float drift_px_per_mps = 9.0;
// The real-speed threshold above which strokes brighten (m/s).
uniform float fast_flow_m_s = 0.6;
uniform float still_flow_m_s = 0.02;
uniform float still_ripple = 0.25;
uniform vec3 band0_color : source_color = vec3(0.30, 0.60, 0.66);
uniform vec3 band1_color : source_color = vec3(0.22, 0.50, 0.62);
uniform vec3 band2_color : source_color = vec3(0.16, 0.40, 0.56);
uniform vec3 band3_color : source_color = vec3(0.11, 0.31, 0.48);
uniform vec3 band4_color : source_color = vec3(0.07, 0.23, 0.40);

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// Trig-free lattice hash (Hoskins-style). NOT the classic
// sine-times-large-constant hash -- that one is a float32 landmine at
// this game's world coordinates: near Basel, world_pos feeds the sine
// ~4.6 MILLION radians, float32 range-reduction collapses, and the hash
// goes regionally near-constant -- the field rails, and whole reaches
// render with no current strokes at all (found live, reproduced by the
// far-world GPU test). Taking the fractional part first keeps every
// intermediate small, so this stays healthy at any world coordinate.
// (Named without the literal formula on purpose: the no-sine pin greps
// the shader source, and a comment must not trip it -- the same
// comment-vs-code trap the old no-smoothstep test once fell into.)
float value_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
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
	// Triangle-weighted taps: the outer taps sit furthest along the
	// direction vector, so they pay the most at a direction-bin change --
	// weighting the centre keeps the stroke shape while cutting the seam
	// budget roughly in half.
	float total = 0.0;
	for (int k = -4; k <= 4; k++) {
		float w = 5.0 - abs(float(k));
		total += value_noise(q + flow_dir * (float(k) * smear_spacing)) * w;
	}
	// ONE smooth scale, deliberately: the strokes below are contours of
	// this field, and a level set is only as smooth as the field it cuts.
	// The fine detail octave an earlier pass mixed in here is exactly what
	// made stroke edges ragged.
	return clamp((total / 25.0 - 0.5) * smear_gain + 0.5, 0.0, 1.0);
}

void fragment() {
	// PIXEL ART renders on the art-pixel grid: every sample below starts
	// from the snapped position, so no gradient is ever smoother than one
	// art pixel -- sub-pixel shading is what makes shader water look
	// painted-on next to chunky sprite terrain. pixel_snap is one ART
	// pixel derived from the real tile sizes, not an invented chunkiness.
	vec2 wp = floor(world_pos / pixel_snap) * pixel_snap + vec2(pixel_snap * 0.5);

	// THE ACROSS MAP -- the final form of the cross-channel field, after
	// three rounds of quantization artefacts ("individual squares ...
	// misalignment"). Across used to ride the atlas, and an atlas
	// dimension must be quantized; now the manager writes each tile's
	// EXACT catalog across into this float texture and bilinear filtering
	// interpolates between tiles natively. No bins, no per-tile
	// reconstruction, no seams -- by construction. Addressed toroidally
	// (repeat wrapping) so chunk streaming never re-anchors the map: a
	// loaded chunk overwrites the stale block its coordinates alias to.
	vec2 map_uv = (wp / tile_px) / flow_map_tiles;
	// The texel carries the WHOLE reconstruction frame -- across (R), the
	// course's downstream direction (GB) and the real solved current speed
	// in m/s (A) -- so direction and speed interpolate between tiles
	// exactly like across does. Per-tile direction bins and the binary
	// fast flag were the last square-tile artefacts ("there are still
	// individual square river tiles visible").
	//
	// GB is NOT a unit vector: a direction's own length carries no
	// information, so its magnitude is spent carrying the tile's REAL
	// local half-width in tiles instead of a fifth channel. Every
	// boulder/wader/ripple push below is computed in real pixels and must
	// divide by THIS local width, not a single fixed guess -- a fixed
	// divisor (the curated rivers' constant 2.0 tiles) understated a wide
	// hydrology reach's true half-width by up to 3x, so the same push
	// landed 3x stronger, relative to that reach, than intended ("artifacts
	// in curves": a wide bend is exactly where a river slows, gathers
	// fish, and racks up overlapping ripples).
	vec4 map_data = texture(flow_across_map, map_uv);
	float frag_across = map_data.r;
	float half_width_local = max(length(map_data.gb), 0.05);
	vec2 flow_dir = map_data.gb / half_width_local;
	vec2 flow_perp = vec2(-flow_dir.y, flow_dir.x);
	float speed_mps = map_data.a;
	float is_fast = step(fast_flow_m_s, speed_mps);
	// STILL WATER: a lake is painted through this same overlay (its
	// shoreline is the real elevation contour, written as an across field
	// exactly like a river bank) with zero current. It must not DRIFT --
	// a lake never creeps -- but it still RIPPLES: the two-phase morph
	// keeps running at a fraction of its strength, so the contour strokes
	// breathe in place instead of freezing. The gate is a hard step.
	float moving = step(still_flow_m_s, speed_mps);
	float advect_gate = mix(still_ripple, 1.0, moving);
	// THE SMOOTHING PASS ("it's still visible that the base are square
	// tiles"): the baked across is quantized per tile, so lines, cel
	// boundaries and the waterline all side-step together on the same
	// straight lattice edges. This jitter is WORLD-anchored -- continuous
	// across every tile boundary -- so it owes nothing to the grid and
	// turns each systematic step into organic raggedness, for every
	// consumer of frag_across at once. Its swing is capped near one
	// quantisation step by test: a mask, never a reshaping.
	frag_across += (value_noise(wp * noise_scale * jitter_scale) - 0.5) * across_jitter;

	// BOULDERS BEND THE WATER -- per fragment, around the rock's actual
	// world position, never through baked tiles: a tile is far too coarse
	// a brush for a bump the size of a rock, and the tile-baked attempt
	// painted exactly the square artefacts it was meant to prevent. Each
	// boulder pushes the across-field away from its own side with a
	// smooth radial falloff, so the current lines and the waterline part
	// around it; eyot_dry below then cuts a ROUND dry patch under the
	// rock itself.
	//
	// boulder_halo is a SEPARATE ring just outside that dry patch, purely
	// a function of distance to the rock -- unlike eyot_dry (which only
	// ever REMOVES wet alpha, so it can darken already-wet water but can
	// never light up already-dry land), the halo can boost wet alpha and
	// tint toward the shore colour on its own, independent of the
	// channel's own across value. A boulder only ever reaches this array
	// when EarthChunkManager.flow_boulder_at_global found it within the
	// river or its bank apron, so lighting up a halo around it never
	// happens for a rock genuinely out in a field -- it always sits on
	// real bank ground ("boulders on a grass field inside the river
	// should be surrounded by the light blue shore band as well").
	float eyot_dry = 1.0;
	float boulder_halo = 0.0;
	for (int b = 0; b < boulder_count; b++) {
		vec2 to_frag = wp - boulders[b];
		float lateral = dot(to_frag, flow_perp);
		float d = length(to_frag);
		boulder_halo = max(
			boulder_halo,
			1.0 - smoothstep(boulder_radius_px, boulder_radius_px + boulder_halo_width_px, d)
		);
		if (d >= boulder_reach_px) {
			continue;
		}
		// The REAL midplane streamline displacement around a cylinder of
		// this radius: sqrt(lateral^2 + R^2) - |lateral|. Exactly R on the
		// stagnation line -- the parting streamline clears the actual rock
		// -- decaying smoothly to the sides. The old falloff-squared kick
		// peaked at a POINT ("boulders behave like a singularity and don't
		// have a radius around which the water flows").
		float displaced = sqrt(lateral * lateral + boulder_radius_px * boulder_radius_px)
			- abs(lateral);
		float envelope = 1.0 - clamp(
			(d - boulder_radius_px) / max(boulder_reach_px - boulder_radius_px, 0.001),
			0.0, 1.0);
		envelope *= envelope;
		float side = lateral >= 0.0 ? 1.0 : -1.0;
		frag_across += side * displaced * envelope / (half_width_local * tile_px);
		eyot_dry = min(eyot_dry, smoothstep(boulder_radius_px * 0.6, boulder_radius_px, d));
	}
	// The waders -- player AND creatures: the same round-core displacement
	// as a boulder, softer and smaller (legs, not a rock face), stretched
	// DOWNSTREAM -- displaced water is carried off by the current, so the
	// wake trails behind the legs instead of ringing them symmetrically.
	for (int w = 0; w < wader_count; w++) {
		vec2 to_frag = wp - waders[w];
		float lateral = dot(to_frag, flow_perp);
		float along = dot(to_frag, flow_dir);
		// In STILL water there is no current to carry the wake, so the
		// push rings the wader symmetrically -- a fish or a swimmer in a
		// lake makes a ripple, not a trail.
		float reach = wader_reach_px
			* (1.0 + wader_wake_trail * moving * clamp(along / wader_reach_px, 0.0, 1.0));
		float d = length(to_frag);
		if (d >= reach) {
			continue;
		}
		float displaced = sqrt(lateral * lateral + wader_radius_px * wader_radius_px)
			- abs(lateral);
		float envelope = 1.0 - clamp(
			(d - wader_radius_px) / max(reach - wader_radius_px, 0.001), 0.0, 1.0);
		envelope *= envelope;
		float side = lateral >= 0.0 ? 1.0 : -1.0;
		frag_across += side * displaced * envelope / (half_width_local * tile_px);
	}
	// RIPPLE RINGS -- the reimplementation of the old overlay's disturbance
	// rings inside the contour system: each ring is a Gaussian band of
	// across-displacement travelling outward at ripple_speed_px and fading
	// over ripple_lifetime, so every stroke it crosses bulges away from the
	// source and the same push that bends a river's lines rings a pond.
	//
	// A dozen fish flapping near one bend land a dozen rings on the same
	// few fragments; summed and added straight into frag_across the way a
	// single ring is, they blew well past the channel's own gradient and
	// filled the bend with dense fanned contour lines, and a ring reaching
	// the bank bulged the WATERLINE itself into a round bump with no
	// visible cause -- reported as "artifacts in curves" and "semispheres
	// on the edge". Fixed two ways: every ring's push is summed in its own
	// accumulator and the SUM is clamped to one ring's own amplitude
	// (many overlapping rings still cap at what one ring alone can do),
	// and the whole clamped push fades to zero as the fragment nears the
	// bank (gated on frag_across BEFORE any ripple, so a ring can perturb
	// open water but can never itself be what pushes a fragment out past
	// the real waterline).
	float ripple_push_px = 0.0;
	for (int i = 0; i < ripple_count; i++) {
		vec2 to_frag = wp - ripples[i].xy;
		float age = TIME - ripples[i].z;
		if (age < 0.0 || age > ripple_lifetime) {
			continue;
		}
		float radius = age * ripple_speed_px;
		float d = length(to_frag);
		float band = (d - radius) / ripple_width_px;
		float push = exp(-band * band) * (1.0 - age / ripple_lifetime) * ripple_amplitude_px;
		float side = dot(to_frag, flow_perp) >= 0.0 ? 1.0 : -1.0;
		ripple_push_px += side * push;
	}
	ripple_push_px = clamp(ripple_push_px, -ripple_amplitude_px, ripple_amplitude_px);
	float bank_fade = 1.0 - smoothstep(0.7, 1.0, abs(frag_across));
	frag_across += ripple_push_px * bank_fade / (half_width_local * tile_px);
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
	// Shear lives at the banks: real eddies shed where the fast core
	// meets the slow margin, so the standing turbulence grows from the
	// centreline (|across| 0) toward the waterline (|across| 1) by
	// bank_shear -- bends, whose outer banks are where |across| sweeps
	// through the water, come out whirlier than straight reaches.
	float shear = 1.0 + bank_shear * clamp(abs(frag_across), 0.0, 1.0);
	float bend = (value_noise(eddy_p) - 0.5
		+ (value_noise(eddy_p * 2.6 + vec2(19.7, 7.3)) - 0.5) * eddy_detail_weight)
		* turbulence_strength * shear;
	vec2 q = p + flow_perp * bend;
	// The smear direction is the FLOW direction and nothing else. Rotating
	// it by the eddy field (an attempt at whirlier bends) sawed every
	// stroke into a regular zig-zag with the eddy noise's own period,
	// because a smear along a direction that oscillates every few tiles
	// folds the level sets; eddy_swirl is kept at zero and the taps below
	// follow flow_dir.
	vec2 swirl_dir = normalize(flow_dir + flow_perp * (bend * eddy_swirl));

	// The drag is purely DOWNSTREAM -- water is carried along the channel,
	// never sideways across it. On top of the bounded two-phase morph, a
	// LINEAR drift keyed to the reach's real current speed makes the whole
	// pattern genuinely TRAVEL ("there should be more of a forward
	// motion") -- unbounded translation is safe because the value noise is
	// homogeneous and its hash is fract-first at any coordinate. The bend
	// field above deliberately does NOT drift: boils hold station over the
	// bed while the surface pours through them.
	float drift = TIME * drift_px_per_mps * speed_mps * noise_scale;
	// Triangular weight: 1 at a phase's birth, 0 at its death.
	float blend = abs(1.0 - 2.0 * phase_a);
	float n;
	if (moving > 0.5) {
		float sample_a = line_field(q - flow_dir * (advect_strength * phase_a * advect_gate + drift), swirl_dir);
		float sample_b = line_field(q - flow_dir * (advect_strength * phase_b * advect_gate + drift), swirl_dir);
		n = mix(sample_a, sample_b, blend);
	} else {
		// STILL WATER'S CHEAP PATH: the sea and every lake are most of
		// the water on screen, and the eighteen smeared taps above are
		// what a river's flowing strokes need, not a pond's breathing
		// ripple. Two unsmeared samples of the same world-anchored field,
		// nudged by the two phases, give the strokes their slow ripple
		// at a ninth of the cost (found live: a screen mostly water ran
		// at a few frames per second).
		float ripple_a = value_noise(q + flow_perp * (advect_strength * still_ripple * phase_a));
		float ripple_b = value_noise(q + flow_perp * (advect_strength * still_ripple * phase_b));
		n = clamp((mix(ripple_a, ripple_b, blend) - 0.5) * smear_gain + 0.5, 0.0, 1.0);
	}

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
	// THE COMIC / 16-BIT BODY: static flat cels of pure reconstructed
	// depth. Deliberately NOT shaded by the moving field -- that was tried
	// and read as "a gas animation": when every fragment shades with the
	// field, the picture is amorphous drifting patches. Illustrated water
	// keeps its body still and lets the drawn strokes below carry ALL the
	// motion.
	float shade = depth_frac;

	// Dither: a WORLD-ANCHORED per-art-pixel hash shifts the quantization
	// threshold, so band boundaries dissolve into grain. This replaced the
	// classic 2x2 checkerboard: on a DIAGONAL depth gradient (every bend
	// of an emergent river) the checker's phases lined up into vertical
	// dashes across the whole dither band, read in play as a sawtooth on
	// every stroke. A hash has no lattice to line up with.
	float checker = value_hash(floor(wp / pixel_snap));
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

	// WAVE STROKES -- the motion, drawn rather than shaded. Each stroke is
	// a CONTOUR (level set) of the smooth advected field: a level set of a
	// smooth field is by construction a smooth curve, and because the
	// field underneath advects, crossfades and bends through the standing
	// eddies, the strokes snake, merge and split -- morphing illustrated
	// wave lines.
	//
	// PERIODIC contours -- a line at every one of line_count evenly spaced
	// levels, a topographic map of the moving surface. Two fixed levels
	// were tried first and most of the channel simply never crossed them:
	// long blank stretches, reported as "most of the stream doesnt show
	// any currents". Level parity alternates the ink strength for a
	// hand-drawn unevenness.
	// Levels at HALF-steps -- (m + 0.5) / count -- never at whole steps:
	// whole steps include 0 and 1, exactly where the gain clamp pegs
	// saturated field regions, and every such plateau rendered as one
	// SOLID stroke-coloured fill (the reported pale structureless wash on
	// straight reaches). At half-steps a saturated plateau simply draws
	// no stroke: quiet water. Fast reaches brighten the strokes rather
	// than widening them -- widening nearly doubled coverage on big
	// rivers, where almost every cell is genuinely fast.
	// FLOW-GUIDED LINES -- the field whose contours the strokes trace is
	// the channel's own across-position plus advected wobble. Because the
	// across ramp dominates (across_line_scale >= line_wobble, by test),
	// the field is monotone bank-to-bank and every level set is an OPEN
	// curve running along the river: long flowing lines by construction,
	// wobbling, pinching together and separating as the noise underneath
	// advects -- and they can NEVER close into a cell, which is exactly
	// what contours of the raw noise always eventually did ("more like
	// perlin noise cells"): level sets of any healthy scalar field close
	// around its extrema. The guide also survives a railed field -- a
	// dead-flat n still draws the full family of lines.
	float s_field = frag_across * across_line_scale + (n - 0.5) * line_wobble;
	float level_frac = fract(s_field * line_count) - 0.5;
	float dist_n = abs(level_frac) / line_count;
	float stroke = 1.0 - smoothstep(line_width * 0.5, line_width, dist_n);
	float parity = mod(floor(s_field * line_count), 2.0);
	// STREAMING PULSES -- the downstream-travel cue. The guided lines only
	// SWAY as the wobble advects ("still looks like still water"); the
	// pulse rides the same advected field, so bright and dim segments
	// visibly stream ALONG every line at the advection speed. Free: n is
	// already computed.
	float pulse = smoothstep(0.35, 0.75, n);
	float wave = stroke * mix(0.75, 1.0, parity) * mix(0.8, 1.1, is_fast)
		* mix(0.55, 1.0, pulse);
	// ADAPTIVE INK: pale strokes vanish on the bright shallow cels
	// (reported from the Rhine straight: "no current lines at all"), so
	// the ink snaps DEEP over light water and pale over dark. A hard
	// step, never a blend -- halfway between the two inks lies the body
	// colour itself, and a stroke drawn in the body colour is invisible.
	vec3 stroke_ink = mix(line_color_deep, line_color, step(0.28, cel_t));

	// MOONLIT AT NIGHT. The night CanvasModulate multiplies every canvas
	// pixel, so nothing here can exceed it -- the ceiling is the play: as
	// the sky darkens (night_lift, fed each frame from the same sunlight
	// that drives the tint), the ink lifts to moonlight white and the
	// stroke alpha boosts to saturation. A full stroke at full night IS
	// the modulate ceiling: the gleam of a real river reflecting skylight,
	// the brightest thing the night allows.
	stroke_ink = mix(stroke_ink, moonlight_ink, night_lift);
	float wave_alpha = min(
		wave * line_strength * mix(1.0, night_stroke_boost, night_lift) * mix(0.35, 1.0, moving), 1.0);
	body = mix(body, stroke_ink, wave_alpha);

	// The SHORE HIGHLIGHT: one constant pale line tracing the bank just
	// inside the ink -- pinned to the reconstructed geometry, not to any
	// field, so it is exactly as smooth as the shoreline itself. The most
	// illustrated mark of all.
	float shore = 1.0 - smoothstep(shore_width * 0.5, shore_width, abs(rr - shore_pos));
	body = mix(body, line_color, shore * mix(0.5, 0.85, night_lift));
	// A boulder's own shore ring, same tint, same night lift -- painted
	// whether the rock sits in open water or on the bank's dry ground.
	body = mix(body, line_color, boulder_halo * boulder_halo_alpha * mix(0.5, 0.85, night_lift));

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
	// The halo also lights its own alpha, independent of the channel's own
	// wet/dry verdict -- a boulder halo ring must show through even where
	// the tile's baseline is dry ground past the bled shore (see
	// EarthChunkManager._paint_river_flow_overlay's SHORE_BLEED_TILES).
	float wet = max(
		(1.0 - smoothstep(1.0 - bank_feather, 1.0 + bank_feather, rr)) * eyot_dry,
		boulder_halo * boulder_halo_alpha
	);
	COLOR = vec4(body, wet);
}
"""

## How fast the advection phase cycles, in Hz. Deliberately slow: this is
## the rate at which the surface renews, not the speed water appears to
## travel (that comes from ADVECT_STRENGTH; the product is pinned by
## test_the_water_still_travels_at_a_real_speed). Lowered from 0.35 so the
## exact half-cycle animation loop stretches to ~2.3 s -- at 0.35 the
## repeat was short enough to read as shimmering in place. Still far
## inside Nyquist at the measured fps floor.
const ADVECT_RATE := 0.22

## How far the surface travels along the flow over one phase, in noise
## CELLS. Sized against the smear length so each line travels a real
## fraction of its own length per phase (see drag_in_feature_lengths) --
## that is what reads as the water speed. Also bounded above by the seam
## budget: the drag is one of the few direction-steered offsets, so a
## bigger drag costs more at every direction-bin change.
##
## NOTE the animation is an EXACT half-cycle loop: the two triangular
## crossfade weights swap symmetrically, so n(t + T/2) == n(t) by
## construction. Deliberate and embraced -- 16-bit water animation WAS a
## short loop -- and within every half cycle each phase's drag grows
## monotonically DOWNSTREAM, which is why it still reads as flow, not as
## oscillation. Pinned by test_the_animation_loops_exactly_each_half_cycle.
const ADVECT_STRENGTH := 7.2

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

## The line-integral-convolution stroke: how many world-anchored taps are
## averaged along the flow, and how far apart (in noise cells). Taps closer
## than a cell overlap into one continuous streak; the smear length,
## (SMEAR_TAPS - 1) * SMEAR_SPACING + 1 cells, is what feature_length_px
## reports. Averaging compresses the value distribution, so SMEAR_GAIN
## re-stretches it -- held to the measured coverage and swing bands by the
## same tests that pinned the old field.
const SMEAR_TAPS := 9
const SMEAR_SPACING := 0.85
const SMEAR_GAIN := 2.0

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
const TURBULENCE_STRENGTH := 1.6
const EDDY_SCALE := 0.16

## The bend's second, finer octave (2.6x the eddy scale). The coarse octave
## alone was measurably correct and visually invisible: it shifts
## neighbouring lines TOGETHER, which locally reads as translation. Kinks a
## viewer can see need bend variation WITHIN a line's own length -- pinned
## by test_a_streakline_visibly_curves_within_its_own_length.
const EDDY_DETAIL_WEIGHT := 0.7

## The across map's side length in tiles -- one texel per world tile,
## addressed toroidally. STRICTLY larger than the widest tile span the
## manager can transiently hold (six chunk rows during a row transition =
## 192): at exactly one loaded-span the freshly loaded row aliased onto a
## still-rendered row 160 tiles away and overwrote its across data with
## another reach entirely ("the parts of the stream are mirrored and
## connect wrongly"). 256 gives two spare rows of headroom and wraps on a
## power of two.
const FLOW_MAP_TILES := 256

## The world tile size the map lookup divides by -- the layer is
## scaled by TerrainRenderer.LAYER_SCALE, so world_pos in the shader is in
## FINAL world pixels where a tile is TerrainRenderer.TILE_SIZE (16), NOT
## the 32 px art tile. Pinned against TerrainRenderer by test; getting it
## wrong doubles or halves every reconstructed offset.
const TILE_PX := 16.0

## How boulders bend the water, all in world px so the bump hugs the
## SPRITE rather than any tile: the push reach (2.5 tiles), the maximum
## across-push at the rock face (falloff-squared to zero at the reach),
## and the dry-eyot radius under the rock itself.
const BOULDER_REACH_PX := 40.0
const BOULDER_RADIUS_PX := 11.0
## The shore-tint ring just outside the dry eyot, and how strongly it
## tints and lights alpha -- deliberately WIDER than the water's own bank
## feather (BANK_FEATHER, ~1% of a channel width) so a boulder's own
## halo, unlike the water's edge, reads clearly from a normal play
## distance regardless of the local channel's width. Not bounded by
## boulder_reach_px: the halo is a ring right at the rock, not part of
## the flow-bending falloff.
const BOULDER_HALO_WIDTH_PX := 6.0
const BOULDER_HALO_ALPHA := 0.6

## A wader as a flow obstacle: a smaller round core than a boulder (legs,
## not a rock face), with the displacement stretched downstream by the
## current -- WAKE_TRAIL is how much farther the reach extends directly
## downstream (0.8 = nearly double). No eyot: a wader never dries the
## water. Up to WADER_SLOTS waders (player + creatures) displace at once.
const WADER_REACH_PX := 26.0
const WADER_RADIUS_PX := 6.0
const WADER_WAKE_TRAIL := 0.8
const WADER_SLOTS := 16

## How far past the true bank curve EarthChunkManager keeps painting a
## cell at all, on top of RiverCatalog's own apron -- not a visual
## softness (BANK_FEATHER already feathers the waterline itself over a
## fraction of a tile) but the DIFFERENCE between a tile existing to draw
## on and a tile being erased outright. A cell beyond the plain apron used
## to be erased, so a wader's wake or a boulder's halo had nowhere to
## render the moment either reached past it -- a player wading out of the
## river watched their own splash trail cut off mid-stride. Sized to
## comfortably clear the widest of the boulder/wader reaches above (2.5
## tiles) plus the wake's own downstream stretch, so an exiting wader's
## trailing wake, or a boulder sitting right at the apron's edge, always
## has ground to draw its fade on. The newly-included band is otherwise
## fully transparent by construction (its baseline |across| sits well past
## the feather) -- it only ever shows anything where a real wader, boulder
## or ripple actually reaches it.
const SHORE_BLEED_TILES := 3.0

## px of world width per unit of across-fraction -- the channel half-width,
## pinned against RiverCatalog.RIVER_HALF_WIDTH_TILES by test.
const HALF_WIDTH_PX := 32.0

## Continuous downstream pattern travel, px/s per m/s of real current --
## linear in the reach's solved speed, pinned by drift tests.
const DRIFT_PX_PER_MPS := 9.0

## The organic smoothing jitter: swing (in across-fraction units, capped
## near one across-bin step by test -- it masks the per-tile quantisation,
## never reshapes the channel) and the wavelength of the world-anchored
## noise that drives it (in multiples of the base field scale; a few
## pixels -- finer than a current line, coarser than an art pixel).
const ACROSS_JITTER := 0.045
const JITTER_SCALE := 2.0

## Half-width of the waterline's feather, in across-fraction units. Small
## since the comic pass: the ink line lives right at the bank, and a wide
## feather rendered it at half opacity -- a washed-out outline instead of
## a drawn one. 0.03 of a 2-tile half-width is ~1 world px (2 art px) of
## soft edge, so the ink prints at effectively full strength and the
## pixel-snap keeps the line crisp. Must stay inside the painter's apron
## (test_the_feather_fits_inside_the_painted_apron) or the fade gets
## clipped by the last painted cell and the straight edge returns.
const BANK_FEATHER := 0.03

## The flow-guided current lines: contours of (across ramp + advected
## wobble). The guide/wobble ratio is the whole design -- the ramp
## dominating is what makes every line an OPEN curve along the river (the
## noise-contour design always closed into "perlin noise cells" around the
## field extrema, because level sets of any healthy field do); the wobble
## is what makes the lines wander, pinch together and separate as the
## field advects. LINE_COUNT lines per unit of the guided field; width in
## field units.
const LINE_COUNT := 3.0
const ACROSS_LINE_SCALE := 1.0
const LINE_WOBBLE := 0.6
const LINE_WIDTH := 0.03
const LINE_STRENGTH := 0.7
const LINE_COLOR := Color(0.85, 0.97, 1.0)

## The dark half of the adaptive stroke ink -- drawn over the light shallow
## cels, where the pale ink was invisible. Deeper than every light cel by
## the contrast test; the switch between the two inks is a hard step at
## mid-depth, because any smooth blend passes through the body colour.
const LINE_COLOR_DEEP := Color(0.07, 0.26, 0.48)

## The moonlit night gleam. The night CanvasModulate multiplies every
## canvas pixel, so at night nothing can exceed the modulate itself -- the
## strokes therefore lift toward near-white at boosted alpha, saturating a
## full stroke at full night (LINE_STRENGTH x NIGHT_STROKE_BOOST >= 1, by
## test). Physically honest: a real river at night reads BRIGHTER than the
## land, because it reflects the sky.
const NIGHT_STROKE_BOOST := 2.2
const MOONLIGHT_INK := Color(0.92, 0.96, 1.0)

## The constant shore highlight, in across-fraction units: where it sits
## (inside the ink line, by test) and how wide it draws. Dimmed to half
## strength after the first live look -- at full strength it stacked with
## the ink, the lightest cel and the strokes into one glowing bank margin.
const SHORE_POS := 0.88
const SHORE_WIDTH := 0.025

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
	material.set_shader_parameter("flow_map_tiles", float(FLOW_MAP_TILES))
	material.set_shader_parameter("half_width_tiles", RiverCatalog.RIVER_HALF_WIDTH_TILES)
	material.set_shader_parameter("tile_px", TILE_PX)
	material.set_shader_parameter("still_flow_m_s", STILL_FLOW_M_S)
	material.set_shader_parameter("still_ripple", STILL_RIPPLE)
	material.set_shader_parameter("ripple_speed_px", RIPPLE_SPEED_PX)
	material.set_shader_parameter("ripple_width_px", RIPPLE_WIDTH_PX)
	material.set_shader_parameter("ripple_amplitude_px", RIPPLE_AMPLITUDE_PX)
	material.set_shader_parameter("ripple_lifetime", RIPPLE_LIFETIME)
	material.set_shader_parameter("eddy_swirl", EDDY_SWIRL)
	material.set_shader_parameter("bank_shear", BANK_SHEAR)
	material.set_shader_parameter("bank_feather", BANK_FEATHER)
	material.set_shader_parameter("across_jitter", ACROSS_JITTER)
	material.set_shader_parameter("jitter_scale", JITTER_SCALE)
	material.set_shader_parameter("boulder_count", 0)
	material.set_shader_parameter("boulder_reach_px", BOULDER_REACH_PX)
	material.set_shader_parameter("boulder_radius_px", BOULDER_RADIUS_PX)
	material.set_shader_parameter("boulder_halo_width_px", BOULDER_HALO_WIDTH_PX)
	material.set_shader_parameter("boulder_halo_alpha", BOULDER_HALO_ALPHA)
	material.set_shader_parameter("wader_count", 0)
	material.set_shader_parameter("wader_reach_px", WADER_REACH_PX)
	material.set_shader_parameter("wader_radius_px", WADER_RADIUS_PX)
	material.set_shader_parameter("wader_wake_trail", WADER_WAKE_TRAIL)
	material.set_shader_parameter("drift_px_per_mps", DRIFT_PX_PER_MPS)
	material.set_shader_parameter("fast_flow_m_s", FAST_FLOW_M_S)
	material.set_shader_parameter("line_count", LINE_COUNT)
	material.set_shader_parameter("across_line_scale", ACROSS_LINE_SCALE)
	material.set_shader_parameter("line_wobble", LINE_WOBBLE)
	material.set_shader_parameter("line_width", LINE_WIDTH)
	material.set_shader_parameter("line_strength", LINE_STRENGTH)
	material.set_shader_parameter("line_color", LINE_COLOR)
	material.set_shader_parameter("line_color_deep", LINE_COLOR_DEEP)
	material.set_shader_parameter("night_lift", 0.0)
	material.set_shader_parameter("night_stroke_boost", NIGHT_STROKE_BOOST)
	material.set_shader_parameter("moonlight_ink", MOONLIGHT_INK)
	material.set_shader_parameter("shore_pos", SHORE_POS)
	material.set_shader_parameter("shore_width", SHORE_WIDTH)
	for i in BAND_COLORS.size():
		material.set_shader_parameter("band%d_color" % i, BAND_COLORS[i])
	return material


func shared_material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = make_material()
	return _shared_material


## The continuous depth ramp -- the five palette stops blended by the
## reconstructed depth fraction, exactly as the shader mixes them. No band
## index exists any more, which is precisely the point.
static func depth_color(depth_fraction: float) -> Color:
	var sramp := clampf(depth_fraction, 0.0, 1.0) * 4.0
	var body := BAND_COLORS[0].lerp(BAND_COLORS[1], clampf(sramp, 0.0, 1.0))
	body = body.lerp(BAND_COLORS[2], clampf(sramp - 1.0, 0.0, 1.0))
	body = body.lerp(BAND_COLORS[3], clampf(sramp - 2.0, 0.0, 1.0))
	return body.lerp(BAND_COLORS[4], clampf(sramp - 3.0, 0.0, 1.0))


## The round-core obstacle displacement, in px of lateral shift -- the CPU
## mirror of both the boulder and wader shader loops. The magnitude is the
## REAL midplane streamline displacement around a cylinder of radius R
## (sqrt(lateral^2 + R^2) - |lateral|): exactly R on the stagnation line,
## decaying smoothly to the sides, nonzero everywhere inside the reach --
## an obstacle with a genuine radius, never a point spike. `wake_trail`
## stretches the reach downstream (0 for boulders; waders trail a wake).
static func obstacle_lateral_shift_px(
	offset_px: Vector2, flow_perp: Vector2,
	radius_px: float, reach_px: float, wake_trail: float
) -> float:
	var flow_dir := Vector2(flow_perp.y, -flow_perp.x)
	var lateral := offset_px.dot(flow_perp)
	var along := offset_px.dot(flow_dir)
	var reach := reach_px * (1.0 + wake_trail * clampf(along / reach_px, 0.0, 1.0))
	var d := offset_px.length()
	if d >= reach:
		return 0.0
	var displaced := sqrt(lateral * lateral + radius_px * radius_px) - absf(lateral)
	var envelope := 1.0 - clampf((d - radius_px) / maxf(reach - radius_px, 0.001), 0.0, 1.0)
	envelope *= envelope
	var side := 1.0 if lateral >= 0.0 else -1.0
	return side * displaced * envelope


## A boulder's across-push at a fragment `offset_px` from the rock, given
## the flow perpendicular -- the round core in across-fraction units.
static func boulder_across_push(offset_px: Vector2, flow_perp: Vector2) -> float:
	return obstacle_lateral_shift_px(
		offset_px, flow_perp, BOULDER_RADIUS_PX, BOULDER_REACH_PX, 0.0
	) / HALF_WIDTH_PX


## The wading player's across-push at a fragment `offset_px` from the
## wader, given the flow direction -- the CPU mirror of the shader block.
## The reach stretches downstream (positive along-flow offsets) so the
## wake trails behind the legs; directly upstream it is just the base
## radial falloff, and beyond it, nothing.
static func wader_across_push(offset_px: Vector2, flow_dir: Vector2) -> float:
	var perp := Vector2(-flow_dir.y, flow_dir.x)
	return obstacle_lateral_shift_px(
		offset_px, perp, WADER_RADIUS_PX, WADER_REACH_PX, WADER_WAKE_TRAIL
	) / HALF_WIDTH_PX


## How dry the eyot leaves a fragment `distance_px` from the rock centre:
## 0 under the rock, 1 outside its radius, soft-edged and ROUND.
static func eyot_dry_factor(distance_px: float) -> float:
	return smoothstep(BOULDER_RADIUS_PX * 0.6, BOULDER_RADIUS_PX, distance_px)


## The boulder's own shore-ring strength `distance_px` from its centre: 0
## at and inside the rock's own radius (that ground is the eyot, not the
## ring), rising through the halo band, 0 again beyond it. Independent of
## eyot_dry and of the channel's own wet/dry verdict -- this is what lets
## a rock sitting on ordinary dry bank ground still show a ring.
static func boulder_halo_factor(distance_px: float) -> float:
	return 1.0 - smoothstep(BOULDER_RADIUS_PX, BOULDER_RADIUS_PX + BOULDER_HALO_WIDTH_PX, distance_px)


## The waterline: 1 inside the channel, 0 past the bank curve, feathered
## over BANK_FEATHER either side of |across| == 1.
static func bank_alpha(across_magnitude: float) -> float:
	return 1.0 - smoothstep(1.0 - BANK_FEATHER, 1.0 + BANK_FEATHER, across_magnitude)


## The stroke mask, mirroring the shader: how strongly a field value n
## lands inside either contour family. What the coverage, morphing and
## fast-reach tests all measure.
## The guided stroke field for one fragment: signed across-fraction plus
## the advected wobble -- the thing whose level sets ARE the current lines.
static func stroke_field(across_fraction: float, n: float) -> float:
	return across_fraction * ACROSS_LINE_SCALE + (n - 0.5) * LINE_WOBBLE


## Full stroke brightness at a point: the mask times the streaming pulse
## riding the advected field -- what actually travels down the lines.
static func stroke_intensity(s_value: float, n: float, is_fast: bool) -> float:
	return stroke_mask(s_value, is_fast) * lerpf(0.55, 1.0, smoothstep(0.35, 0.75, n))


static func stroke_mask(s_value: float, is_fast: bool) -> float:
	var level_frac := fposmod(s_value * LINE_COUNT, 1.0) - 0.5
	var dist_s := absf(level_frac) / LINE_COUNT
	var stroke := 1.0 - smoothstep(LINE_WIDTH * 0.5, LINE_WIDTH, dist_s)
	var parity := fposmod(floor(s_value * LINE_COUNT), 2.0)
	return stroke * lerpf(0.75, 1.0, parity) * (1.1 if is_fast else 0.8)


## How far the strokes lift toward moonlight for a given sunlight
## intensity (SolarPosition.sunlight_intensity, 0 below the horizon).
## Fully off through daylight, fully on in darkness, fading in through the
## low-sun band so the gleam arrives with dusk instead of snapping.
static func night_lift_for_sunlight(sunlight: float) -> float:
	return 1.0 - smoothstep(0.0, 0.25, clampf(sunlight, 0.0, 1.0))


## The stroke ink at a given night lift -- moonlight overrides the adaptive
## day ink as the sky darkens, on every cel: at night even the deep rim ink
## would vanish under the dimming.
static func stroke_ink_at(cel_t: float, lift: float) -> Color:
	return stroke_ink_for(cel_t).lerp(MOONLIGHT_INK, clampf(lift, 0.0, 1.0))


## The adaptive stroke ink for a body cel: deep over light water, pale
## over dark, snapped hard at mid-depth.
static func stroke_ink_for(cel_t: float) -> Color:
	# Deep ink ONLY on the two lightest shallow cels -- everywhere else the
	# pale ink wins, because the night modulate dims everything
	# multiplicatively and dark strokes lose their absolute contrast first.
	return LINE_COLOR if cel_t >= 0.28 else LINE_COLOR_DEEP


## The cel quantizer, mirroring the shader exactly: shade in [0, 1],
## checker 0.0 or 1.0 (the 2x2 dither phase), out comes the flat level.
static func cel_level(shade: float, checker: float) -> int:
	return clampi(
		int(floor(clampf(shade, 0.0, 1.0) * float(CEL_LEVELS) + (checker - 0.5) * DITHER_STRENGTH)),
		0, CEL_LEVELS - 1
	)



## Whether a real current is quick enough to read as fast-moving -- such a
## reach gets a higher-contrast surface, which is how speed shows now that
## nothing translates across the screen.
static func is_fast_flow(velocity_m_s: float) -> bool:
	return velocity_m_s >= FAST_FLOW_M_S


## Below this current the overlay draws STILL water: no advection, no
## drift, quiet strokes -- a lake (docs/concept/hydrology.md), painted
## through this shader with zero velocity so its shoreline gets the same
## smooth contour, ink and feather a river bank does. Two centimetres a
## second is below any current the Manning solve returns for a real
## channel (the slowest reach the model admits is ~0.4 m/s), so no river
## ever reads as still. Pinned by test_still_water_neither_advects_nor_drifts.
const STILL_FLOW_M_S := 0.02


static func is_still_water(velocity_m_s: float) -> bool:
	return velocity_m_s < STILL_FLOW_M_S


## How much of the two-phase surface morph still water keeps: enough for
## the contour strokes to visibly breathe (real ponds ripple under wind),
## far too little to read as a current. Strictly between none and a
## river's full morph, by test.
const STILL_RIPPLE := 0.25


## Disturbance rings (docs/concept/hydrology.md, "fish ripples reimplemented
## with the river contour system"): a ring born at a fish's flap or a
## swimmer's stroke travels outward at RIPPLE_SPEED_PX, is RIPPLE_WIDTH_PX
## wide, displaces the across field by up to RIPPLE_AMPLITUDE_PX at birth
## and is gone after RIPPLE_LIFETIME seconds -- about three tiles of
## travel, a pond ring, not a wave. RIPPLE_SLOTS rings live at once; the
## oldest is dropped first.
##
## A ring must BEND the existing strokes, never spawn new ones: the strokes
## are contours of the across field, so a bump steeper than the channel's
## own cross-gradient (one across unit over a half-width, ~0.03 per px on
## a two-tile river) crowds extra contour lines into the band. The first
## values (5 px over a 4 px band) did exactly that -- with dozens of fish
## flapping, the channel filled with dense concentric arcs, seen in play as
## "all zig zags and artifacts". 1.5 px over a 10 px band is a visible
## bulge and no new lines. Pinned by
## test_a_ring_bends_strokes_without_adding_any.
const RIPPLE_SLOTS := 24
const RIPPLE_SPEED_PX := 18.0
const RIPPLE_WIDTH_PX := 10.0
const RIPPLE_AMPLITUDE_PX := 1.5
const RIPPLE_LIFETIME := 2.5
## The across field's own cross-gradient on a two-tile-half-width river,
## in across units per pixel: one unit over 32 px.
const CHANNEL_ACROSS_GRADIENT_PER_PX := 1.0 / (2.0 * 16.0)

## Whirl (third playtest, "more natural whirly turbulences in curves"):
## turbulence grows by BANK_SHEAR from the centreline to the waterline,
## where real shear sheds eddies. EDDY_SWIRL, which rotated the stroke
## smear by the eddy field, is ZERO: it sawed every stroke into a regular
## zig-zag with the eddy noise's period ("both artifacts still exist"),
## because smearing along a direction that oscillates every few tiles
## folds the level sets. Pinned at zero by
## test_the_smear_follows_the_flow_and_never_the_eddies.
const EDDY_SWIRL := 0.0
const BANK_SHEAR := 0.25


## CPU mirror of one ring's across-displacement (pixels) at `distance_px`
## from its source, `age` seconds after birth -- the exact shader formula,
## for tests and any caller reasoning about where a ring is.
static func ripple_push_px(distance_px: float, age: float) -> float:
	if age < 0.0 or age > RIPPLE_LIFETIME:
		return 0.0
	var band := (distance_px - age * RIPPLE_SPEED_PX) / RIPPLE_WIDTH_PX
	return exp(-band * band) * (1.0 - age / RIPPLE_LIFETIME) * RIPPLE_AMPLITUDE_PX


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
	# The trig-free Hoskins-style hash, mirroring the shader exactly -- see
	# the GLSL comment for why sin-based hashing is banned here.
	var p3x := fposmod(x * 0.1031, 1.0)
	var p3y := fposmod(y * 0.1031, 1.0)
	var p3z := p3x
	var shift := p3x * (p3y + 33.33) + p3y * (p3z + 33.33) + p3z * (p3x + 33.33)
	p3x += shift
	p3y += shift
	p3z += shift
	return fposmod((p3x + p3y) * p3z, 1.0)


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
		var weight := 5.0 - absf(float(k))
		total += value_noise(px + offset.x, py + offset.y) * weight
	return clampf((total / 25.0 - 0.5) * SMEAR_GAIN + 0.5, 0.0, 1.0)


## The field flowing east -- the direction-free convenience the coverage
## and swing measurements sample (the distribution is direction-invariant;
## the seam test is where direction sensitivity is measured).
static func surface_value(px: float, py: float) -> float:
	return line_field_value(px, py, Vector2(1, 0))


## The whole animated pipeline at one world point (in noise cells): the
## standing bend, both advected phases, the crossfade. What the seam test
## compares across a direction-bin change.
static func animated_field_value(
	px: float, py: float, dir: Vector2, time_seconds: float, speed_mps := 0.0
) -> float:
	var perp := Vector2(-dir.y, dir.x)
	var b := bend_displacement(px * EDDY_SCALE, py * EDDY_SCALE)
	var qx := px + perp.x * b
	var qy := py + perp.y * b
	var phase_a := fposmod(time_seconds * ADVECT_RATE, 1.0)
	var phase_b := fposmod(time_seconds * ADVECT_RATE + 0.5, 1.0)
	var drift := drift_cells(speed_mps, time_seconds)
	var shift_a := ADVECT_STRENGTH * phase_a + drift
	var shift_b := ADVECT_STRENGTH * phase_b + drift
	var sample_a := line_field_value(qx - dir.x * shift_a, qy - dir.y * shift_a, dir)
	var sample_b := line_field_value(qx - dir.x * shift_b, qy - dir.y * shift_b, dir)
	return lerpf(sample_a, sample_b, absf(1.0 - 2.0 * phase_a))


## How far the pattern has travelled downstream, in noise cells: linear in
## the reach's real current speed and in time -- unbounded, because the
## water does not loop back.
static func drift_cells(speed_mps: float, seconds: float) -> float:
	return DRIFT_PX_PER_MPS * speed_mps * seconds * NOISE_SCALE


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
