extends RefCounted

const ProceduralRiverFlowSprite = preload("res://src/rendering/procedural_river_flow_sprite.gd")
const RiverCatalog = preload("res://src/world/river_catalog.gd")
const WaterShader = preload("res://src/rendering/water_shader.gd")
const StoneSize = preload("res://src/world/stone_size.gd")

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
// The half width, in NOISE CELLS, that line_wobble was tuned at. The
// wobble is scaled down in proportion for anything wider -- see the
// s_field line for why.
uniform float wobble_reference_cells = 2.56;
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
// How much of the across map's reconstruction is the CUBIC filter rather
// than plain hardware bilinear. 1 is the cubic; 0 is exactly what shipped
// before, for comparison in game.
uniform float map_smoothing = 1.0;
// DIAGNOSTIC, off by default. Draws the contours of frag_across alone --
// no noise, no advection, no cel shading, no strokes, no lighting -- so
// the field the whole picture is built from can be looked at directly
// instead of inferred from what it produces. Toggled live by /flowdebug.
// How much of an obstacle's core is softened, as a fraction of its own
// radius. Outside this band the push is EXACTLY the untouched round-core
// displacement; inside it the sign ramps smoothly through zero instead of
// flipping. 0.35 confines the change to 3.9px for a boulder and 2.1px for
// a wader, leaving the bulge itself alone.
uniform float obstacle_side_softness = 0.35;
uniform float debug_across = 0.0;
uniform float debug_across_bands = 8.0;
// How far the smear is allowed to follow the course's curve. 1 reads the
// flow at both ends of the smear and bends the taps between them; 0
// collapses both ends onto the fragment's own direction, which is exactly
// the straight smear this replaced -- so the two can be compared in game
// at one uniform rather than by rebuilding.
uniform float smear_curvature = 1.0;
uniform float smear_gain = 2.0;
uniform float turbulence_strength = 1.6;
uniform float eddy_scale = 0.16;
uniform float eddy_detail_weight = 0.7;
uniform float eddy_detail_frequency = 2.6;
uniform float eddy_swirl = 0.0;
uniform float bank_shear = 0.25;
uniform sampler2D flow_across_map : filter_linear, repeat_enable;
uniform sampler2D flow_scale_map : filter_linear, repeat_enable;
// The SAME texture as flow_scale_map, bound a second time with NEAREST
// filtering: its G channel is the reach's drift speed (constant between
// confluences, see EarthChunkGenerator.drift_speed_m_s_for_discharge_units),
// and a linear ramp between two reaches' speeds, times TIME, would be the
// far-time shredding again along that one-texel band.
uniform sampler2D flow_drift_map : filter_nearest, repeat_enable;
uniform float flow_map_tiles = 256.0;
// No longer read inside fragment(): every per-fragment normalization now
// decodes the tile's REAL local half-width from the direction vector's own
// magnitude (see map_data's own comment below). Kept declared, with its
// default still set from _apply_defaults, only so nothing external
// resolving this material's parameters by name breaks; harmless as an
// unused uniform.
uniform float half_width_tiles = 2.0;
uniform float tile_px = 16.0;
uniform float bank_feather = 0.03;
uniform float across_jitter = 0.045;
uniform float jitter_scale = 2.0;
uniform int boulder_count = 0;
uniform vec2 boulders[24];
// Every rock is a rock of its own size: one radius per slot, in world
// px, from the stone's real diameter (RiverFlowShader.boulder_radius_px_
// for); the push reach is that radius times boulder_reach_ratio.
uniform float boulder_radius[24];
uniform float boulder_reach_ratio = 3.6;
// The rock is a rise in the bed: the water shallows toward it over this
// many radii past its edge (its SHOAL), and shallow water is light here
// for the same reason the banks are. No painted ring.
uniform float boulder_shoal_ratio = 1.5;
// FOAM IN FRONT: the current stagnates on the rock's upstream face and,
// fast enough, breaks white there. Window off the face in radii, the
// speeds between which the reach goes from parting cleanly to foaming,
// and how the foam prints.
uniform float boulder_foam_reach_ratio = 0.9;
uniform float foam_min_m_s = 0.3;
uniform float foam_full_m_s = 1.0;
uniform float foam_alpha = 0.85;
uniform vec3 foam_color : source_color = vec3(0.93, 0.97, 1.0);
// WHIRLS BEHIND: the wake lobe, in radii, and how much harder the
// standing-turbulence bend whirls inside it.
uniform float boulder_wake_length_ratio = 6.0;
uniform float boulder_wake_width_ratio = 1.5;
uniform float boulder_wake_gain = 0.15;
// ...and the foam the face sheds streams down the wake at this fraction
// of the face's own.
uniform float wake_foam = 0.35;

// The waders -- the player and any creatures standing in river water,
// fed per frame by EarthChunkManager.set_river_flow_waders. Soft moving
// obstacles that never dry the water.
uniform int wader_count = 0;
uniform vec2 waders[16];
uniform float wader_reach_px = 26.0;
uniform float wader_radius_px = 6.0;
uniform float wader_wake_trail = 0.8;

// MOVEMENT RIPPLES -- a fish darting past, the player or an animal moving
// through the water. Recorded and aged by the SAME buffer the sea's
// surface draws from (WaterShader.add_disturbance/advance_disturbances,
// fanned out by EarthChunkManager): one ring buffer, one lifetime, one
// distance cull, two surfaces. disturbance_age is CPU-driven seconds since
// the event, NOT TIME minus a stored stamp -- the shader clock and
// Time.get_ticks_msec() have no shared epoch, and comparing them is what
// once made every ripple permanently out of range and invisible.
uniform vec2 disturbance_pos[16];
uniform float disturbance_age[16];
uniform int disturbance_count = 0;
uniform float ripple_speed = 14.0;
uniform float ripple_lifetime = 2.2;
uniform float ripple_wavelength = 6.0;
uniform float ripple_packet_width = 7.0;
uniform float ripple_spread_decay = 0.02;
// How the packet reaches the drawn surface: how far a crest bends the
// contour field the current lines trace, and the crest amplitudes between
// which the ring inks in its own right.
uniform float ripple_line_gain = 0.18;
uniform float ripple_crest_min = 0.10;
uniform float ripple_crest_full = 0.40;
// The ring's own ink band: where on the crest's sine a pixel must sit to
// print (its WIDTH, in px, is one number independent of age), and the
// ceiling it prints at -- below a full stroke, so it reads lighter than a
// current line.
uniform float ripple_ring_edge = 0.85;
uniform float ripple_ink_max = 0.6;

// RAIN RIPPLES -- the other ripple source, same idea as WaterShader.
// raindrop_ripples: while it's raining (rain_intensity, driven by
// EarthChunkManager.set_rain), a hash-seeded grid of drop points
// continuously spawns small, quick splashes. A genuinely different
// (shorter, tighter) packet than a passing creature's wake above -- see
// RiverFlowShader.RAIN_RIPPLE_LINE_GAIN's own doc comment for why reusing
// the wake's packet for rain was already tried on the ocean and reported
// as "every drop a multi-tile bullseye".
uniform float rain_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float rain_ripple_speed = 10.0;
uniform float rain_ripple_lifetime = 1.2;
uniform float rain_ripple_wavelength = 4.0;
uniform float rain_ripple_packet_width = 4.5;
uniform float rain_ripple_line_gain = 0.072;

// Continuous downstream travel, px/s per m/s of real current.
uniform float drift_px_per_mps = 20.0;
// The period, in noise cells (and in eddy units for the eddy field), the
// translated noise TILES at and both drifts wrap modulo -- what keeps the
// direction-scaled translations bounded (see the drift lines in fragment()).
uniform float drift_period = 20.0;
// How wide a window either drift's crossfade blends across, either side
// of its own wrap, in noise cells -- see the crossfade lines in
// fragment() and RiverFlowShader.WRAP_CROSSFADE_CELLS for why a wrap
// needs one at all (the noise tiling only hides a wrap at an exactly
// axis-aligned flow direction).
uniform float wrap_crossfade_cells = 1.0;
// The dim end of the brightness pulse that streams along every stroke.
// Deep enough that a bright segment travelling down a line is obvious,
// never zero, so a dim segment is still a stroke.
uniform float pulse_floor = 0.35;
// How fast the standing eddies migrate downstream, as a fraction of the
// surface's own drift. 0 is the old fully bed-anchored bend.
uniform float bend_drift_fraction = 0.4;
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

// The same noise on a lattice that wraps every `period` cells, so a
// translation by exactly one period ALONG X OR Y ALONE is the identity --
// x and y wrap separately. Every TIME-translated sample reads this: the
// translation wraps at the same period, so the wrap stays bounded (the
// far-time shredding -- see the drift lines in fragment()). That bound
// alone does not make the wrap INSTANT invisible for a direction-scaled
// shift (dir * period): that shift is only a multiple of the period on
// BOTH axes when dir itself is exactly axis-aligned. See
// wrap_crossfade_weight for what actually hides the instant.
float value_noise_tiled(vec2 p, float period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	vec2 i0 = mod(i, period);
	vec2 i1 = mod(i + 1.0, period);
	return mix(
		mix(value_hash(i0), value_hash(vec2(i1.x, i0.y)), f.x),
		mix(value_hash(vec2(i0.x, i1.y)), value_hash(i1), f.x),
		f.y
	);
}

// Fades from 1 (fully blend toward a drift's crossfade twin) to 0 as
// `distance` (cells to the nearest wrap point) grows past
// wrap_crossfade_cells. Mirrored on the CPU by
// RiverFlowShader.wrap_crossfade_weight -- see the drift and bend_drift
// lines in fragment() for what this actually hides.
float wrap_crossfade_weight(float distance_to_wrap) {
	float t = clamp(distance_to_wrap / wrap_crossfade_cells, 0.0, 1.0);
	return 1.0 - t * t * (3.0 - 2.0 * t);
}

// ONE expanding wave packet -- character for character the sea's own
// (WaterShader's ripple_packet), because a fish's wake must read the same
// in a river as in the ocean. Not a hard ring but a travelling packet of
// concentric crests and troughs behind the front, decaying with age and
// with the circumference it spreads its energy around.
//
// SIGNED -- crests positive, troughs negative -- which is the whole point:
// overlapping wakes then genuinely interfere, destructively as well as
// constructively, instead of only ever piling up. Mirrored on the CPU by
// RiverFlowShader.ripple_packet, which is what pins it under test.
float ripple_packet(float dist, float age) {
	if (age < 0.0 || age > ripple_lifetime) {
		return 0.0;
	}
	float front = age * ripple_speed;
	float phase = front - dist;  // > 0 = inside the advancing front
	float packet = exp(-abs(phase) / ripple_packet_width);
	float rings = sin(phase * 6.28318530718 / ripple_wavelength);
	float age_fade = 1.0 - age / ripple_lifetime;
	float spread_fade = 1.0 / (1.0 + front * ripple_spread_decay);
	return rings * packet * age_fade * spread_fade;
}

// The same packet WITHOUT its sine: how strong the wake is here, now,
// regardless of whether this pixel sits on a crest or a trough. Dividing
// the signed packet by this leaves the pure sine, which is what the ring's
// ink band is cut from -- so the band's width is a threshold on the sine
// (one number in px) and the envelope alone decides how hard it prints.
// Mirrored by RiverFlowShader.ripple_envelope.
float ripple_envelope(float dist, float age) {
	if (age < 0.0 || age > ripple_lifetime) {
		return 0.0;
	}
	float front = age * ripple_speed;
	float phase = front - dist;
	float packet = exp(-abs(phase) / ripple_packet_width);
	float age_fade = 1.0 - age / ripple_lifetime;
	float spread_fade = 1.0 / (1.0 + front * ripple_spread_decay);
	return packet * age_fade * spread_fade;
}

// THE WATER'S VISIBLE SPEED, in world px/s downstream. TWO things move the
// drawn surface: the two-phase drag, which translates the field
// advect_strength cells every 1/advect_rate seconds no matter how fast
// the reach runs, and the linear drift keyed to the real current. So
// anything that has to "move with the water" -- the ring centre below,
// the eddy field the guide lines are bent by -- must ride the SUM.
// Carried by the drift alone, at a typical 0.5 m/s reach a wake moved at
// a third of the water and the whirls at a fifth, and both read as
// standing still while the pulses streamed past ("make the river ripples
// move downstream at water speed", "a wobble stays in place instead of
// flowing with the river", "the lines should move at the same speed").
// Gated by the same hard still step the strokes use: a lake breathes
// sideways and never drifts, so nothing on it is carried either. Mirrored
// on the CPU by RiverFlowShader.surface_px_per_s.
float surface_px_per_s(float speed_mps, float moving) {
	return moving * (advect_strength * advect_rate / noise_scale + drift_px_per_mps * speed_mps);
}

// THE river adaptation. In still water a ring stays concentric about a
// fixed point; in a current it is concentric about a point that MOVES WITH
// THE WATER -- so the centre is carried downstream at the surface's whole
// visible speed (surface_velocity: surface_px_per_s along the flow), and a
// wake sits in the river instead of the river sliding out from under it.
//
// The age bound is checked BEFORE the centre and the distance, not left to
// ripple_packet's own guard: the padded tail of the buffer carries a
// sentinel age, and this is the loop the rain-ripple perf lesson applies
// to (do the cheap rejection first, never the expensive half and then a
// discard).
float movement_ripples(vec2 pos, vec2 surface_velocity, out float envelope) {
	float total = 0.0;
	envelope = 0.0;
	for (int i = 0; i < disturbance_count; i++) {
		float age = disturbance_age[i];
		if (age < 0.0 || age > ripple_lifetime) {
			continue;
		}
		vec2 center = disturbance_pos[i] + surface_velocity * age;
		float d = distance(pos, center);
		total += ripple_packet(d, age);
		envelope += ripple_envelope(d, age);
	}
	return total;
}

// A raindrop's own, genuinely smaller/quicker packet -- see rain_ripple_
// speed/lifetime/wavelength/packet_width's own comment above for why this
// is NOT ripple_packet reused with different numbers.
float rain_ripple_packet(float dist, float age) {
	if (age < 0.0 || age > rain_ripple_lifetime) {
		return 0.0;
	}
	float front = age * rain_ripple_speed;
	float phase = front - dist;
	float packet = exp(-abs(phase) / rain_ripple_packet_width);
	float rings = sin(phase * 6.28318530718 / rain_ripple_wavelength);
	float age_fade = 1.0 - age / rain_ripple_lifetime;
	float spread_fade = 1.0 / (1.0 + front * ripple_spread_decay);
	return rings * packet * age_fade * spread_fade;
}

// Cellular raindrop ripples on the river surface -- the SAME hash-grid
// technique as WaterShader.raindrop_ripples (each cell spawns one splash
// per cycle at a hash-derived point and time offset; neighbouring cells
// are sampled too, so a splash that originated next door still renders as
// it expands across the cell boundary). Deliberately NOT anchored to the
// river's own advecting field -- rain falls on the water from outside it,
// the same reason WaterShader's own version is anchored to world position
// rather than to anything that moves with the current.
float raindrop_ripples(vec2 pos) {
	if (rain_intensity <= 0.001) {
		return 0.0;
	}
	float cell_size = 14.0;
	float interval = 1.6;
	float total = 0.0;
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			vec2 cell = floor(pos / cell_size) + vec2(float(ox), float(oy));
			float seed = value_hash(cell);
			float age = mod(TIME + seed * interval * 7.0, interval);
			if (age > rain_ripple_lifetime) {
				continue;
			}
			vec2 drop_pos = (cell + vec2(value_hash(cell + 7.3), value_hash(cell + 41.7))) * cell_size;
			total += rain_ripple_packet(distance(pos, drop_pos), age);
		}
	}
	return total * rain_intensity;
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
// CUBIC B-SPLINE RECONSTRUCTION of a map texel grid.
//
// This is the zigzag. The flow map holds one texel per TILE, and every
// stroke, the waterline, the ink line and the shore highlight is a CONTOUR
// of that field. Hardware bilinear filtering makes the field's gradient
// CONSTANT inside each texel cell and JUMP at the boundary, so its contours
// are polygons -- straight segments meeting at a kink, one kink per tile.
// A sawtooth, by construction, no matter how smooth the baked data is.
//
// Measured with tools/probe_bilinear.gd, walking the course at a bend the
// artefact appears at every time, in degrees of contour-normal turn per
// eighth of a tile: bilinear median 0.000 / peak 22.547, this filter
// median 0.024 / peak 4.870. The median of exactly ZERO is the signature --
// bilinear does not turn at all inside a cell, then turns all at once.
//
// An earlier attempt warped the sample COORDINATE with a smoothstep and
// left hardware bilinear underneath. The polygon survived that and gained
// plateaus at the texel centres, which is why it read as "much worse ...
// artificial" while the artefact stayed. The FILTER has to change.
//
// Four bilinear taps rather than sixteen point taps (Sigg & Hadwiger): each
// tap is placed off-centre so the hardware's own linear blend does half the
// work. Three extra samples, not fifteen.
vec4 cubic_weights(float v) {
	vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
	vec4 s = n * n * n;
	float x = s.x;
	float y = s.y - 4.0 * s.x;
	float z = s.z - 4.0 * s.y + 6.0 * s.x;
	float w = 6.0 - x - y - z;
	return vec4(x, y, z, w) / 6.0;
}

vec4 texture_bicubic(sampler2D tex, vec2 uv, float texels) {
	vec2 texel_uv = uv * texels - 0.5;
	vec2 f = fract(texel_uv);
	texel_uv -= f;
	vec4 wx = cubic_weights(f.x);
	vec4 wy = cubic_weights(f.y);
	vec4 c = texel_uv.xxyy + vec2(-0.5, 1.5).xyxy;
	vec4 sums = vec4(wx.xz + wx.yw, wy.xz + wy.yw);
	vec4 offset = (c + vec4(wx.yw, wy.yw) / sums) / texels;
	vec4 s0 = texture(tex, offset.xz);
	vec4 s1 = texture(tex, offset.yz);
	vec4 s2 = texture(tex, offset.xw);
	vec4 s3 = texture(tex, offset.yw);
	float mx = sums.x / (sums.x + sums.y);
	float my = sums.z / (sums.z + sums.w);
	return mix(mix(s3, s2, mx), mix(s1, s0, mx), my);
}

// The course direction the flow map carries at a world position. Past the
// painted band the map's GB channels are zero, and normalizing that is a
// NaN that would poison every tap downstream, so a dead sample hands back
// the caller's own direction instead.
vec2 flow_dir_at(vec2 world_position, vec2 fallback) {
	// The CUBIC reconstruction, not plain bilinear. dir_start and dir_end
	// set every stroke's ORIENTATION, so a bilinear lookup here gives the
	// stroke tangent field a piecewise-constant gradient on the texel
	// lattice: polygonal STROKES over a perfectly smooth across field,
	// which is exactly what /flowdebug showed -- the field's own contours
	// sweep cleanly through a bend while the drawn strokes do not.
	//
	// Sampling the direction more coarsely than the field it steers puts
	// the lattice straight back into the picture. This regressed when the
	// curved smear was added: before it, the taps rode swirl_dir, which
	// comes from the map_data sample and became cubic with the across map.
	vec2 raw = texture_bicubic(
		flow_across_map, (world_position / tile_px) / flow_map_tiles, flow_map_tiles
	).gb;
	if (dot(raw, raw) < 1e-8) {
		return fallback;
	}
	return normalize(raw);
}

float line_field(vec2 q, vec2 dir_start, vec2 dir_end) {
	// THE SMEAR FOLLOWS THE COURSE'S CURVE, not one straight line.
	//
	// Measured with tools/probe_smear.gd over 1,997 wet tiles around the
	// spawn: this smear spans 5.31 tiles, and the course turns up to
	// 45.12 deg across that span -- 12.17 at the 75th percentile, 19.47 at
	// the 90th, 30 or more on 1.6% of wet tiles, which is where the bends
	// are. Smearing all nine taps along ONE direction read at the fragment
	// makes two neighbouring fragments smear along diverging lines, and
	// the strokes tear apart instead of lining up. That is the zigzag.
	//
	// dir_start and dir_end are the flow read at the two ENDS of this
	// smear; each tap steps along the direction interpolated between them.
	// A bend has roughly constant curvature and a tangent rotates linearly
	// with arc length along an arc, so the straight line between the ends
	// is very nearly the right model: the same probe puts the residual at
	// 2.49 deg at the 75th percentile and 5.38 at the 90th, for TWO extra
	// texture samples instead of the eight a per-tap resample would cost.
	//
	// The walk is CUMULATIVE -- each step continues from the last tap's
	// position, tracing a real polyline arc. Stepping k * spacing from the
	// centre along an interpolated heading would fan out from q instead,
	// which is not a curve.
	//
	// Triangle-weighted taps, as before: the outer taps sit furthest along
	// the arc, so they pay the most wherever the frame still changes, and
	// weighting the centre keeps the stroke shape.
	float total = value_noise_tiled(q, drift_period) * 5.0;
	vec2 forward = q;
	vec2 backward = q;
	for (int k = 1; k <= 4; k++) {
		float w = 5.0 - float(k);
		float t = float(k) / 8.0;
		forward += normalize(mix(dir_start, dir_end, 0.5 + t) + vec2(1e-6, 0.0)) * smear_spacing;
		backward -= normalize(mix(dir_start, dir_end, 0.5 - t) + vec2(1e-6, 0.0)) * smear_spacing;
		total += (value_noise_tiled(forward, drift_period) + value_noise_tiled(backward, drift_period)) * w;
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
	// course's downstream UNIT direction (GB) and the real solved current
	// speed in m/s (A) -- so direction and speed interpolate between tiles
	// exactly like across does. Per-tile direction bins and the binary
	// fast flag were the last square-tile artefacts ("there are still
	// individual square river tiles visible").
	vec4 map_data = mix(texture(flow_across_map, map_uv), texture_bicubic(flow_across_map, map_uv, flow_map_tiles), map_smoothing);
	float frag_across = map_data.r;
	vec2 flow_dir = normalize(map_data.gb + vec2(1e-6, 0.0));
	vec2 flow_perp = vec2(-flow_dir.y, flow_dir.x);
	float speed_mps = map_data.a;
	// The tile's REAL local half-width, from its OWN scalar map -- never
	// packed into the direction vector above. Bilinear filtering blends a
	// vector by ordinary addition, and two texels whose BEARINGS differ
	// (exactly what neighbouring texels do on a bend) partially CANCEL
	// when summed, so a magnitude riding that vector collapses toward
	// zero independent of either texel's real width -- corrupting both
	// the decoded width and (dividing a near-zero vector to normalize it)
	// the decoded direction, worst exactly on curves ("this huge zigzag
	// still persists"). A lone scalar has no such failure: bilinearly
	// blending two widths always lands between them. Every
	// boulder/wader/ripple push below divides by THIS, not a single fixed
	// guess -- a fixed divisor (the curated rivers' constant 2.0 tiles)
	// understated a wide hydrology reach's true half-width by up to 3x, so
	// the same push landed up to 3x stronger, relative to that reach, than
	// intended.
	// The SAME cubic reconstruction as the across map above. Left on plain
	// bilinear this kinks on the texel lattice exactly as across did, and
	// every boulder, wader and ripple push below divides by it -- so their
	// displacement inherited the sawtooth even once across itself was
	// smooth ("also behind a few boulders").
	float half_width_local = max(mix(
		texture(flow_scale_map, map_uv),
		texture_bicubic(flow_scale_map, map_uv, flow_map_tiles),
		map_smoothing
	).r, 0.05);
	// THE REACH'S DRIFT SPEED, nearest-filtered: what the two TIME-scaled
	// translations below multiply. Never speed_mps -- that is interpolated
	// per fragment and varies along a reach, and TIME times a per-fragment
	// speed diverged between neighbours without bound (the second half of
	// the far-time shredding). One value per reach, stepping only at a
	// confluence, so "the Rhine travels, a lower course crawls" survives.
	float drift_speed = texture(flow_drift_map, map_uv).g;
	float is_fast = step(fast_flow_m_s, speed_mps);
	// STILL WATER: a lake is painted through this same overlay (its
	// shoreline is the real elevation contour, written as an across field
	// exactly like a river bank) with zero current. It must not DRIFT --
	// a lake never creeps -- but it still RIPPLES: the two-phase morph
	// keeps running at a fraction of its strength, so the contour strokes
	// breathe in place instead of freezing. The gate is a hard step.
	float moving = step(still_flow_m_s, speed_mps);
	float advect_gate = mix(still_ripple, 1.0, moving);
	// The one speed everything carried by the water rides -- see
	// surface_px_per_s.
	vec2 surface_velocity = flow_dir * surface_px_per_s(speed_mps, moving);
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
	// THE ROCK IS HYDROLOGY, not a painted thing. It stands above the
	// waterline, so the bed rises to meet it, so the water shallows toward
	// it: boulder_shoal is that rise, 1 at the rock's edge falling to 0
	// over boulder_shoal_ratio radii, and it SHALLOWS depth_frac below --
	// the field the cel body is cut from. The light bands around a rock
	// are then exactly the light bands along a bank, drawn by the same
	// quantisation and the same dither in the same palette, with no
	// boulder colour code at all. This replaces the painted shore band
	// ("the boulders halo should not be computed by the boulder, but
	// rather be part of the river's hydrology... the lighter color bands
	// should come from elevation (rock is above waterline)"). A rock on
	// dry bank ground is dry ground with a rock on it.
	//
	// Every rock is a rock of its own size (boulder_radius[b], from its
	// real diameter) and the reach, the eyot and the shoal scale with it.
	//
	// FOAM IN FRONT, WHIRLS BEHIND ("...and produce foam in front and
	// whirls behind it"): the current stagnates on the upstream face --
	// nose is the squared cosine from the stagnation line, zero at and
	// behind the shoulders -- in a window just off the rock's face; and
	// the rock sheds eddies into a lobe behind it, which amplifies the
	// standing-turbulence bend below. Both are geometry here; the speed
	// gates them where they are used. Computed BEFORE the reach cull: the
	// wake is longer than the push reaches.
	float eyot_dry = 1.0;
	float boulder_shoal = 0.0;
	float boulder_foam = 0.0;
	float boulder_wake = 0.0;
	for (int b = 0; b < boulder_count; b++) {
		vec2 to_frag = wp - boulders[b];
		float R = boulder_radius[b];
		float reach = R * boulder_reach_ratio;
		float lateral = dot(to_frag, flow_perp);
		float along = dot(to_frag, flow_dir);
		float d = length(to_frag);
		float shoal = 1.0 - smoothstep(R, R + R * boulder_shoal_ratio, d);
		boulder_shoal = max(boulder_shoal, shoal);
		float nose = clamp(-along / max(d, 0.001), 0.0, 1.0);
		nose *= nose;
		float foam_window = smoothstep(R * 0.7, R, d)
			* (1.0 - smoothstep(R, R + R * boulder_foam_reach_ratio, d));
		boulder_foam = max(boulder_foam, nose * foam_window);
		float wake = smoothstep(0.0, R, along)
			* (1.0 - smoothstep(R, R * boulder_wake_length_ratio, along))
			* (1.0 - smoothstep(R, R * boulder_wake_width_ratio, abs(lateral)));
		boulder_wake = max(boulder_wake, wake);
		if (d >= reach) {
			continue;
		}
		// The REAL midplane streamline displacement around a cylinder of
		// this radius: sqrt(lateral^2 + R^2) - |lateral|. Exactly R on the
		// stagnation line -- the parting streamline clears the actual rock
		// -- decaying smoothly to the sides. The old falloff-squared kick
		// peaked at a POINT ("boulders behave like a singularity and don't
		// have a radius around which the water flows").
		float displaced = sqrt(lateral * lateral + R * R)
			- abs(lateral);
		float envelope = 1.0 - clamp(
			(d - R) / max(reach - R, 0.001),
			0.0, 1.0);
		envelope *= envelope;
		// A SMOOTH odd factor, not a sign flip.
		//
		// sign(lateral) leaves the magnitude at exactly R on the
		// stagnation line while the sign jumps across it, so frag_across --
		// the field every stroke, the waterline, the ink line and the shore
		// highlight is a CONTOUR of -- tore by 2R along a straight line
		// running through the rock with the current. Measured: 21.95px for
		// this radius, which against a 32px half-width is 0.69 of the whole
		// channel, discontinuously. Every contour crossing it was cut.
		//
		// lateral / sqrt(lateral^2 + R^2) vanishes on the line, is odd
		// about it, and is within a few percent of 1 everywhere the push is
		// actually visible -- so the round-core profile above is unchanged
		// where it reads, and merely stops tearing where it did not.
		float side = clamp(lateral / (R * obstacle_side_softness), -1.0, 1.0);
		frag_across += side * displaced * envelope / (half_width_local * tile_px);
		eyot_dry = min(eyot_dry, smoothstep(R * 0.6, R, d));
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
		// The same smooth odd factor the boulder loop uses. A wader tore by
		// 11.95px, 0.37 of a channel, along a straight line through the
		// player running with the current -- reported as "a hard edge ... a
		// straight line which moves with him", seen only while standing in
		// water, which is exactly when the player is fed here as a wader.
		float side = clamp(lateral / (wader_radius_px * obstacle_side_softness), -1.0, 1.0);
		frag_across += side * displaced * envelope / (half_width_local * tile_px);
	}
	// Movement ripples (fish/player/animal wakes) deliberately do NOT
	// perturb frag_across here -- that field is the channel's geometry,
	// and a passing fish must not narrow the river or bulge the waterline
	// (see "a wake must not displace the channel geometry", tested by
	// test_a_ripple_never_moves_the_waterline). They instead bend the
	// stroke field directly, below, via movement_ripples().
	float rr = abs(frag_across);
	float depth_frac = clamp(1.0 - rr * rr, 0.0, 1.0);
	// The rock's shoal: the bed rises to the rock, the water shallows, the
	// cel body lightens -- the bank's own mechanism, around a rock.
	depth_frac *= 1.0 - boulder_shoal;

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
	// THE EDDIES MIGRATE DOWNSTREAM WITH THE WATER. A bed-anchored bend
	// was the right call while the whirl only reached the strokes through
	// the noise; with the whirl now IN the guide, a static bend left the
	// lines standing still and only the small wobble texture moved over
	// them ("make the water move with the flow so it looks like a flowing
	// stream"). It then migrated at a fraction of the linear drift alone,
	// which at a typical reach is a fifth of the water's visible speed --
	// "a wobble stays in place instead of flowing with the river". So the
	// eddy sample coordinate now translates at bend_drift_fraction of
	// surface_px_per_s, the SAME speed the ring centre is carried at
	// ("the lines should move at the same speed"), in still water not at
	// all. Real boils lag the surface (Jackson 1976) and the fraction is
	// still the knob for that, but at 1.0 the art direction is that the
	// lines ARE the water.
	//
	// This is a steady TRANSLATION of the bend field, never the phase
	// drag's stretch-and-reset, so it cannot change the fold Jacobian:
	// test_the_fold_margin_survives_the_eddy_drift holds the 0.35 margin
	// at a real drifted offset. And the wobble still deforms relative to
	// the whirls -- each phase stretches away from this translation and
	// resets -- so the picture does not slide as one sheet.
	// WRAPPED at drift_period in EDDY units, and the eddy noise tiles at
	// that period (its detail octave at period x frequency), so the wrap is
	// invisible. Unbounded, this was flow_dir times a magnitude that grew
	// for the whole session, and flow_dir differs by a fraction of a degree
	// between neighbouring fragments on a bend: the far-time shredding (see
	// the drift line below).
	float bend_drift = mod(TIME * surface_px_per_s(drift_speed, moving) * noise_scale * bend_drift_fraction * eddy_scale, drift_period);
	vec2 eddy_p = p * eddy_scale - flow_dir * bend_drift;
	// Shear lives at the banks: real eddies shed where the fast core
	// meets the slow margin, so the standing turbulence grows from the
	// centreline (|across| 0) toward the waterline (|across| 1) by
	// bank_shear -- bends, whose outer banks are where |across| sweeps
	// through the water, come out whirlier than straight reaches.
	float shear = 1.0 + bank_shear * clamp(abs(frag_across), 0.0, 1.0);
	// ...and harder still in a rock's wake, where the eddies it sheds
	// live (boulder_wake, the lobe behind each boulder above), gated by
	// the current: a rock in a lake sheds nothing.
	float bend = (value_noise_tiled(eddy_p, drift_period) - 0.5
		+ (value_noise_tiled(eddy_p * eddy_detail_frequency + vec2(19.7, 7.3), drift_period * eddy_detail_frequency) - 0.5) * eddy_detail_weight)
		* turbulence_strength * shear * (1.0 + boulder_wake * boulder_wake_gain * moving);
	// THE WRAP INSTANT ITSELF -- distinct from the far-time shredding above:
	// bend_drift's wrap is a genuine jump of one whole drift_period, and
	// multiplying it by flow_dir only leaves value_noise_tiled unchanged
	// when flow_dir is exactly axis-aligned (see value_noise_tiled's own
	// comment) -- every other bearing pops eddy_p onto an unrelated point
	// in the tile. Crossfaded toward a half-period-offset twin, exactly the
	// way the two ADVECT phases already hide each other's own reset, but
	// only within wrap_crossfade_cells of the actual wrap: the weight is 0
	// everywhere else, so the everyday bend is untouched.
	float bend_drift_weight = wrap_crossfade_weight(min(bend_drift, drift_period - bend_drift));
	if (bend_drift_weight > 0.0) {
		float bend_drift_alt = mod(
			TIME * surface_px_per_s(drift_speed, moving) * noise_scale * bend_drift_fraction * eddy_scale
				+ drift_period * 0.5,
			drift_period
		);
		vec2 eddy_p_alt = p * eddy_scale - flow_dir * bend_drift_alt;
		float bend_alt = (value_noise_tiled(eddy_p_alt, drift_period) - 0.5
			+ (value_noise_tiled(eddy_p_alt * eddy_detail_frequency + vec2(19.7, 7.3), drift_period * eddy_detail_frequency) - 0.5) * eddy_detail_weight)
			* turbulence_strength * shear * (1.0 + boulder_wake * boulder_wake_gain * moving);
		bend = mix(bend, bend_alt, bend_drift_weight);
	}
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
	// WRAPPED at drift_period, and the smear taps read the noise that tiles at
	// that period, so the wrap is invisible. Unbounded it was NOT safe,
	// whatever the hash: the translation is flow_dir times a magnitude, and
	// flow_dir is reconstructed continuously between texels -- on a bend two
	// neighbouring fragments differ by a fraction of a degree, which times
	// thousands of cells is many cells: unrelated noise at neighbouring
	// pixels. Found live after ~25 minutes on the Loire: every curved reach
	// dissolved into speckle while the straight reach beside it kept its
	// lines. The same angle-times-distance trap as the world origin,
	// re-entered through TIME.
	// ...and at the REACH'S drift speed (drift_speed above), never the
	// fragment's own: TIME times a speed that varies along the reach is
	// the same unbounded divergence again, direction or no direction.
	float drift = mod(TIME * drift_px_per_mps * drift_speed * moving * noise_scale, drift_period);
	// THE WRAP INSTANT ITSELF -- same caveat as bend_drift above (see
	// value_noise_tiled's own comment): crossfaded toward a half-period-
	// offset twin within wrap_crossfade_cells of the actual wrap, weight 0
	// (today's plain drift, untouched) everywhere else.
	float drift_weight = wrap_crossfade_weight(min(drift, drift_period - drift));
	float drift_alt = mod(
		TIME * drift_px_per_mps * drift_speed * moving * noise_scale + drift_period * 0.5, drift_period
	);
	// Triangular weight: 1 at a phase's birth, 0 at its death.
	float blend = abs(1.0 - 2.0 * phase_a);
	float n;
	if (moving > 0.5) {
		// The two ends of this smear, in world space: the outermost tap
		// sits four steps of smear_spacing away in NOISE units, and a
		// noise unit is noise_scale world pixels.
		vec2 smear_end_offset = swirl_dir * (4.0 * smear_spacing / noise_scale);
		vec2 dir_start = normalize(mix(
			swirl_dir, flow_dir_at(wp - smear_end_offset, swirl_dir), smear_curvature
		) + vec2(1e-6, 0.0));
		vec2 dir_end = normalize(mix(
			swirl_dir, flow_dir_at(wp + smear_end_offset, swirl_dir), smear_curvature
		) + vec2(1e-6, 0.0));
		float sample_a = line_field(q - flow_dir * (advect_strength * phase_a * advect_gate + drift), dir_start, dir_end);
		float sample_b = line_field(q - flow_dir * (advect_strength * phase_b * advect_gate + drift), dir_start, dir_end);
		if (drift_weight > 0.0) {
			float sample_a_alt = line_field(q - flow_dir * (advect_strength * phase_a * advect_gate + drift_alt), dir_start, dir_end);
			float sample_b_alt = line_field(q - flow_dir * (advect_strength * phase_b * advect_gate + drift_alt), dir_start, dir_end);
			sample_a = mix(sample_a, sample_a_alt, drift_weight);
			sample_b = mix(sample_b, sample_b_alt, drift_weight);
		}
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
	// THE WOBBLE IS SCALED BY THE CHANNEL'S OWN WIDTH.
	//
	// This field has to stay MONOTONE bank to bank: a monotone field's
	// level sets are open curves running along the river, and once it
	// folds back they close into rings -- the "perlin noise cells" this
	// design exists to avoid.
	//
	// Whether it stays monotone is a question about GRADIENTS, not
	// amplitudes, and the two terms live on different scales. `across`
	// runs 0 to 1 over the channel's half width; `n` runs 0 to 1 over ONE
	// noise cell. So the whole thing turns on how many noise cells fit
	// across the water -- and that is not a constant, because the half
	// width comes from discharge. Measured with tools/probe_monotone.gd,
	// as the fraction of bank-to-bank steps that fold back:
	//
	//   1.0 tiles (1.28 cells)   0.1%
	//   2.0 tiles (2.56 cells)   2.8%   <- where line_wobble was tuned
	//   3.5 tiles (4.48 cells)  10.1%
	//   6.0 tiles (7.68 cells)  18.2%   <- cells, and the map goes here
	//
	// Which is exactly "only around bends and where the water is deeper
	// at the edge": wide water folds, narrow water does not.
	//
	// Scaling the wobble by reference/actual holds the RATIO of the two
	// gradients constant, so every width folds as little as the tuned one
	// did. Clamped at 1 so it only ever tames wide water -- a narrow
	// reach keeps exactly the look it has now.
	float wobble_cells = max(half_width_local * tile_px * noise_scale, 0.01);
	float wobble_local = line_wobble * min(wobble_reference_cells / wobble_cells, 1.0);
	// THE EDDIES BEND THE GUIDE, NOT JUST THE NOISE.
	//
	// The bend field used to reach the strokes only by displacing where
	// the NOISE was sampled -- so every bit of whirl the water had came
	// through the wobble term, and the wobble had to be big to show it.
	// Big enough that its gradient was 2.3x the guide's at every width
	// (test_the_wobble_gradient_stays_well_under_the_across_gradient...),
	// which is the field folding into cells: the strokes were short
	// angular fragments of closed loops, not lines along the river.
	//
	// Now the bend displaces the ACROSS coordinate itself, in across
	// units (one noise cell is 1/wobble_cells of the half width). The
	// guide lines whirl with the eddies directly, and this cannot fold:
	// d(across + bend/cells)/d(across) is 1 + d(bend)/d(p), the exact
	// Jacobian test_the_bend_never_folds_or_pinches_the_surface holds
	// above 0.35. The wobble is then free to be a small texture on top
	// instead of the thing the lines are made of.
	float guide = frag_across + bend / wobble_cells;
	// MOVEMENT RIPPLES, drawn rather than glowed (merged alongside the
	// eddy-bent guide above -- two independent, additive effects on the
	// same field, not a choice between them). This surface is illustrated
	// water -- a static cel body with every bit of motion carried by drawn
	// strokes -- so a wake composited on top as a bright ring would read
	// as a sticker. Instead the packet enters the field whose LEVEL SETS
	// are the current lines, so the lines themselves bow into arcs around
	// the fish, closing into rings where the disturbance is strongest and
	// merging back into the flow at its edges. Two overlapping wakes sum
	// HERE, before any of it is drawn, so they genuinely interfere.
	//
	// Deliberately NOT added to frag_across/guide: that field is the
	// channel's geometry, and a passing fish must not narrow the river or
	// bend its eddies. Boulders and waders displace it because they are
	// solid things standing in the current; a wake is only the surface.
	float ripple_envelope_sum = 0.0;
	float ripple = movement_ripples(wp, surface_velocity, ripple_envelope_sum);
	// Rain bends the SAME guide-line field a passing creature's wake does
	// (see raindrop_ripples' own doc comment) -- a much smaller gain, since
	// many overlapping small splashes should read as a gentle overall
	// texture, not individually as clear as one creature's own ring. It
	// does NOT also get the separate crest-ink ring treatment below
	// (ripple_crest/ripple_ink) -- a raindrop's splash is a much smaller,
	// subtler disturbance than a wake and doesn't need its own inked ring
	// the way a fish's does.
	float rain_ripple = raindrop_ripples(wp);
	float s_field = guide * across_line_scale + (n - 0.5) * wobble_local
		+ ripple * ripple_line_gain + rain_ripple * rain_ripple_line_gain;
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
		* mix(pulse_floor, 1.0, pulse);
	// The crest also inks in its OWN right, so the ring reads as concentric
	// arcs and not merely as wobbled current lines. Entered through `wave`
	// -- the existing "how hard is a stroke drawn here" -- so it inherits
	// the adaptive ink, the moonlight lift and the alpha clamp for free.
	// max, not sum: a strong crest takes over the mark, a weak one leaves
	// the flow line alone, and neither can push the stroke past full.
	//
	// The band is cut from the pure SINE (packet over envelope): a pixel
	// prints only near the crest's peak, so the ring is a thin line of a
	// fixed width in px -- no wider than a current line -- however strong
	// or faded the wake is. The ENVELOPE alone decides how hard it prints,
	// through the same graduated crest curve, under a ceiling below a full
	// stroke ("stroke width smaller and a bit more transparent").
	float ripple_crest = ripple / max(ripple_envelope_sum, 1e-4);
	float ripple_ink = smoothstep(ripple_ring_edge, 1.0, ripple_crest) * smoothstep(ripple_crest_min, ripple_crest_full, ripple_envelope_sum) * ripple_ink_max;
	wave = max(wave, ripple_ink);
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

	// FOAM on a rock's upstream face: the geometric window from the
	// boulder loop, driven by how fast the reach runs (a slow one parts
	// cleanly, a fast one foams), broken up by the channel's own advected
	// field n so it streams and flickers with the water instead of sitting
	// as a pale cap. Near-white, over the body and the strokes.
	float foam_drive = smoothstep(foam_min_m_s, foam_full_m_s, speed_mps) * moving;
	// The foam the face sheds streams down the wake too, thinner: the
	// bend's gain is bounded by the no-fold margin, so a wake reads as
	// disturbed water mostly through these streaks.
	float foam = (boulder_foam + boulder_wake * wake_foam) * foam_drive * smoothstep(0.3, 0.7, n);
	body = mix(body, foam_color, foam * foam_alpha);

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
	// The eyot only ever REMOVES water: a rock on dry bank ground is dry
	// ground with a rock on it, and the light water around a rock in the
	// river is the shoal in the depth field above, not painted alpha.
	float wet = (1.0 - smoothstep(1.0 - bank_feather, 1.0 + bank_feather, rr)) * eyot_dry;
	if (debug_across > 0.5) {
		// The across field's OWN level sets. Polygonal bands mean the
		// field or its reconstruction filter; smooth bands mean the
		// artefact lives in the stroke layer above and the field is fine.
		// Full alpha over every painted tile, deliberately: it also shows
		// the painted band's own outline, which is where a clipped wake
		// or halo would show itself.
		// Mode 2 shows s_field -- the field the STROKES are contours of,
		// which is frag_across plus the smeared noise. Mode 1 shows
		// frag_across alone. Comparing the two says whether an artefact
		// in the strokes comes from the channel geometry or from the
		// noise term, which is the one thing left after the field itself
		// was shown smooth.
		float debug_source = debug_across > 1.5 ? s_field : frag_across;
		float debug_band = fract(debug_source * debug_across_bands);
		float debug_edge = 1.0 - smoothstep(0.0, 0.08, abs(debug_band - 0.5));
		COLOR = vec4(vec3(debug_edge), 1.0);
	} else {
		COLOR = vec4(body, wet);
	}
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

## How far each phase drags the surface along the flow over its life, in
## noise CELLS. This is DEFORMATION, not travel -- reversed from the
## earlier reading ("that is what reads as the water speed", sized to
## cover most of a line per phase). 7.2 -> 1.2, and the reason is what the
## real GPU showed (tools/probe_river_motion.gd): the two phases are copies
## of the field offset by HALF the drag, and at 3.6 cells (45 world px)
## apart the copies are uncorrelated, so the crossfade is a dissolve
## between two unrelated patterns -- a kink fades out where it is and a
## different one fades in elsewhere, "a wobble stays at place" no matter
## how far each copy is being stretched. At 0.6 cells apart the copies
## stay correlated: a kink survives the fade and rides the linear drift,
## which is now what carries the water and everything on it, coherently.
## Pinned by test_the_drag_is_a_small_deformation_so_kinks_survive_the_
## crossfade; its translation share of the visible speed is pinned minor
## by test_the_water_travels_at_a_calm_speed.
##
## The animation is still an exact half-cycle loop in its DEFORMATION
## (n(t + T/2) == n(t) with the drift removed); the drift makes the whole
## thing travel on top.
const ADVECT_STRENGTH := 1.2

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
## Turns the raw-across diagnostic on or off on the shared material, so
## the two views are one console command apart rather than a rebuild.
func set_debug_across(mode: float) -> void:
	shared_material().set_shader_parameter("debug_across", clampf(mode, 0.0, 2.0))


## How much of an obstacle's core is softened, as a fraction of its own
## radius -- the band inside which the push ramps through zero instead of
## flipping sign. Outside it the round-core displacement is exactly what
## it always was, so the bulge a player pushes walking in and out of the
## water is unchanged; inside it, 3.9px for a boulder and 2.1px for a
## wader, the field stops tearing. Pinned by
## test_the_obstacle_push_keeps_a_real_peak_so_the_bulge_survives.
const OBSTACLE_SIDE_SOFTNESS := 0.35

## The raw-field diagnostic, OFF. 1 draws frag_across (the channel
## geometry), 2 draws s_field (that plus the smeared noise -- the field
## the strokes actually trace). A tool for answering "is the artefact
## in the field or in the strokes drawn from it" in one screenshot rather
## than another headless probe. Toggled at runtime by /flowdebug; this is
## only its default, and a diagnostic must never ship on.
const DEBUG_ACROSS := 0.0

## How much of the across map's reconstruction is the cubic B-spline
## rather than plain hardware bilinear. 1 is the cubic. 0 is exactly what
## shipped before, kept reachable because this is the third attempt at this
## artefact and the comparison should cost a keystroke, not a rebuild.
const MAP_SMOOTHING := 1.0

## How far the smear follows the course's curve: 1 bends the taps between
## the flow read at each END of the smear, 0 is the straight smear this
## replaced. Kept as a real uniform so the two are one keystroke apart in
## game, since the straight version is what every earlier screenshot shows.
const SMEAR_CURVATURE := 1.0

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
const TURBULENCE_STRENGTH := 1.4
const EDDY_SCALE := 0.16

## The bend's second, finer octave (2.6x the eddy scale). The coarse octave
## alone was measurably correct and visually invisible: it shifts
## neighbouring lines TOGETHER, which locally reads as translation. Kinks a
## viewer can see need bend variation WITHIN a line's own length -- pinned
## by test_a_streakline_visibly_curves_within_its_own_length.
## How many times finer the bend's second octave is than its first.
##
## RAISED from 2.6, and TURBULENCE_STRENGTH cut to match, because the two
## things this field has to deliver trade off against each other in a
## fixed way. Curvature within a line's own length goes as
## amplitude * frequency^2; the risk of the domain warp FOLDING (see
## test_the_bend_never_folds_or_pinches_the_surface) goes as
## amplitude * frequency. So for a fixed fold budget, curvature is
## proportional to frequency alone -- a finer, weaker eddy buys strictly
## more visible curl per unit of fold risk than a coarse, strong one.
##
## Measured: at 2.6 and strength 1.6 the warp pinched to 0.0988, which is
## a 10:1 compression and the cusp reported as a zigzag. At 4.0 and 0.85
## the margin is comfortable AND a streakline curves more than it did
## before, rather than less.
const EDDY_DETAIL_FREQUENCY := 2.6

const EDDY_DETAIL_WEIGHT := 0.5

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
## SPRITE rather than any tile. Every rock now carries ITS OWN radius
## (boulder_radius_px_for, from its real diameter -- "the rock should as
## entity have a mass"), and the push reach, the dry eyot, the shoal, the
## foam and the wake all scale with it. BOULDER_RADIUS_PX is the REFERENCE
## radius (the size the generic obstacle mirrors and tests speak of, and
## the old one-size-fits-all value), not what the shader draws every rock
## with; BOULDER_REACH_RATIO is how far the push reaches in radii (the old
## 40 px reach over the old 11 px radius, kept).
const BOULDER_RADIUS_PX := 11.0
const BOULDER_REACH_RATIO := 3.6
const BOULDER_REACH_PX := BOULDER_RADIUS_PX * BOULDER_REACH_RATIO
## No rock parts less water than this, however small: the smallest
## Wentworth boulder still has to read as an obstacle at play distance.
const MIN_BOULDER_RADIUS_PX := 6.0
## The rock's SHOAL: how far past its edge, in radii, the bed rises toward
## it and the water shallows. This is what replaced the painted shore band
## (BOULDER_BAND_*): the light water around a rock is the same shallow
## water the banks show, drawn by the same cel quantisation and dither in
## the channel's own palette -- "the lighter color bands should come from
## elevation (rock is above waterline)". One to a couple of radii by test;
## 1.5 puts three cel steps around a reference rock.
const BOULDER_SHOAL_RATIO := 1.5

## FOAM IN FRONT: the window off the rock's upstream face where the
## stagnating current foams, in radii past the edge; the reach speeds
## between which a rock goes from parting the water cleanly (nothing at
## or under FOAM_MIN_M_S -- an ordinary 0.5 m/s reach foams a little) to
## foaming fully; how the foam prints. Real whitewater is deceleration,
## not speed, which is why it lives on the face where the water is
## brought to rest and follows dynamic pressure (BoulderHydraulics).
const BOULDER_FOAM_REACH_RATIO := 0.9
const FOAM_MIN_M_S := 0.3
const FOAM_FULL_M_S := 1.0
const FOAM_ALPHA := 0.85
const FOAM_COLOR := Color(0.93, 0.97, 1.0)

## WHIRLS BEHIND: the wake lobe a rock sheds eddies into -- how far
## downstream it reaches and how wide it is, in radii -- and how much
## harder the standing-turbulence bend whirls inside it. The gain is
## bounded by the same no-fold sweep the bend itself passes
## (test_the_wake_whirls_harder_but_never_folds_the_surface): wilder,
## never folded -- and that bound is tight (0.5 pinched the warp to 0.17
## against the 0.35 margin; 0.15 holds it), so the wake reads as
## disturbed water mostly through WAKE_FOAM, the fraction of the face's
## foam that streams down the lobe, which is what a real wake carries.
const BOULDER_WAKE_LENGTH_RATIO := 6.0
const BOULDER_WAKE_WIDTH_RATIO := 1.5
const BOULDER_WAKE_GAIN := 0.15
const WAKE_FOAM := 0.35

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

## Movement-ripple tuning, taken from the SEA by import rather than copied:
## a fish's wake has to read the same in a river as in the ocean, and a
## second set of literals is a second thing to re-tune and drift apart.
## Same slot count too, because both surfaces draw the one shared buffer
## (WaterShader.add_disturbance, fanned out by EarthChunkManager).
const RIPPLE_SPEED := WaterShader.RIPPLE_SPEED
const RIPPLE_LIFETIME := WaterShader.RIPPLE_LIFETIME
const RIPPLE_WAVELENGTH := WaterShader.RIPPLE_WAVELENGTH
const RIPPLE_PACKET_WIDTH := WaterShader.RIPPLE_PACKET_WIDTH
const RIPPLE_SPREAD_DECAY := WaterShader.RIPPLE_SPREAD_DECAY
const DISTURBANCE_SLOTS := WaterShader.MAX_DISTURBANCES

## How far a crest bends the contour field the current lines trace, in
## s_field units. Bounded from BOTH sides by test rather than eyeballed:
## below ~a third of one contour spacing (1 / LINE_COUNT) a crest moves the
## lines too little to draw anything, and above half the wobble's own swing
## the ripple stops being a local disturbance and starts restructuring the
## channel-wide line family into the closed "perlin noise cells" the across
## ramp exists to prevent. Rings closing around the fish ITSELF are wanted
## -- that is the ripple -- which is exactly why the ceiling is set against
## the wobble rather than against zero.
##
## Expressed as a FRACTION of LINE_WOBBLE (0.3 -- the same ratio the
## original 0.18 sat at against wobble's own pre-tuning value of 0.6)
## rather than a hardcoded absolute. LINE_WOBBLE has already moved twice
## since for independent eddy-folding reasons (0.6 -> 0.12 -> 0.17, see its
## own doc comment) -- a gain tuned against one specific wobble value
## silently drifts out of its own "stays under half the wobble" bound the
## moment wobble is retuned out from under it without anyone touching this
## constant at all. Caught merging claude/hydrology-spec's own further
## wobble tuning against this ripple work, developed independently on a
## separate branch: bend measured 0.136 against a 0.085 ceiling once wobble
## reached 0.17 (test_a_ripple_cannot_restructure_the_whole_channel).
## Deriving it here means a future wobble retune keeps this ceiling
## satisfied automatically instead of silently drifting again.
const RIPPLE_LINE_GAIN := LINE_WOBBLE * 0.3

## Rain, the other ripple source (see WaterShader.raindrop_ripples) --
## imported the SAME way movement ripples are just above, and for the same
## reason: a raindrop's splash has to read as the same phenomenon on a
## river as on the sea, not a second, independently-tuned one. Genuinely
## DIFFERENT tuning from the movement ripple above, not a duplicate --
## WaterShader's own history ("sharing the wake's packet made every drop a
## multi-tile bullseye") is exactly why rain needs its own, much smaller,
## quicker packet (short lifetime, short wavelength) rather than reusing
## RIPPLE_SPEED/LIFETIME/WAVELENGTH/PACKET_WIDTH above.
const RAIN_RIPPLE_SPEED := WaterShader.RAIN_RIPPLE_SPEED
const RAIN_RIPPLE_LIFETIME := WaterShader.RAIN_RIPPLE_LIFETIME
const RAIN_RIPPLE_WAVELENGTH := WaterShader.RAIN_RIPPLE_WAVELENGTH
const RAIN_RIPPLE_PACKET_WIDTH := WaterShader.RAIN_RIPPLE_PACKET_WIDTH

## A raindrop's bend on the guide lines, a fraction of RIPPLE_LINE_GAIN
## above rather than a second hand-picked absolute -- many overlapping
## raindrops should read as a gentle overall texture, not as many strong
## individual bends the way one passing creature's wake reads as one clear
## ring. Being strictly SMALLER than RIPPLE_LINE_GAIN, it inherits that
## constant's own tested ceiling (test_a_ripple_cannot_restructure_the_
## whole_channel) automatically -- it can never restructure the channel
## line family if the larger movement gain already can't.
const RAIN_RIPPLE_LINE_GAIN := RIPPLE_LINE_GAIN * 0.4

## The crest amplitudes between which the ring inks in its own right: below
## MIN nothing draws (troughs and spent tails stay clean), at FULL the mark
## is a full-strength stroke. FULL must stay reachable by a real packet
## crest or it is ink that never prints; MIN is the threshold WaterShader
## already paid for once -- set against a FRESH ripple it made the ring
## visible only in its first moments ("a mini ripple appears but nothing
## looks natural"), so it is pinned low enough that a crest still inks
## three quarters of the way through the ring's life.
##
## FULL 0.40 -> 0.60, MIN 0.10 -> 0.12 ("a little less pronounced ...
## smoother"): at half the packet's ~0.82 peak, FULL printed the ring at
## full stroke strength for most of its life -- as dark as a current line,
## a stamp. Near the peak, only a fresh crest prints full and the ring
## GRADUATES down through its life (about 0.4 at half life, fading out
## past three quarters) instead of switching off. Both ends pinned by
## test_the_ring_inks_at_full_strength_only_while_fresh and
## test_the_ring_graduates_through_its_life_instead_of_switching_off,
## against the packet's own scanned peak, so re-tuning the packet re-tunes
## these bounds.
const RIPPLE_CREST_MIN := 0.12
const RIPPLE_CREST_FULL := 0.60

## Where on the crest's sine a pixel must sit to print: the ring's ink
## band is the arc of the sine above this, so its width in world px is
## RIPPLE_WAVELENGTH / TAU * (PI - 2 asin EDGE) -- ~1.4 px at 0.85, no
## wider than a current line (ripple_ring_width_px / line_width_px), and
## the same at every age because the envelope is divided out first.
## "Stroke width smaller": the old amplitude-threshold band was ~3 px and
## widened and narrowed with the ring's strength.
const RIPPLE_RING_EDGE := 0.85

## The ceiling the ring prints at, as a fraction of a full stroke: "a bit
## more transparent" than the current lines it sits among. The graduation
## through the ring's life (RIPPLE_CREST_MIN/FULL) scales under it.
const RIPPLE_INK_MAX := 0.6

## px of world width per unit of across-fraction -- the channel half-width,
## pinned against RiverCatalog.RIVER_HALF_WIDTH_TILES by test.
const HALF_WIDTH_PX := 32.0

## Continuous downstream pattern travel, px/s per m/s of real current --
## linear in the reach's solved speed, pinned by drift tests. This is THE
## carrier now: the ring centre, the eddy field, the kinks and the pulses
## all ride it (see surface_px_per_s), so it is what "the water's speed"
## means on screen.
## RAISED 9 -> 20 once ("the lines are not flowing forward": the strokes are
## contours of across, lines PARALLEL to the flow, so forward motion only
## reads through what travels ON them, and at 9 that took three and a half
## seconds to cross a tile). Then 20 -> 16 with the drag cut to a
## deformation: with everything moving together coherently, 8 world px/s
## at a typical 0.5 m/s reach reads as a calm, unmistakable current -- and
## 30 read as "everything is faster". Pinned by
## test_a_typical_reach_streams_fast_enough_to_read_as_flowing (floor) and
## test_the_water_travels_at_a_calm_speed (ceiling).
const DRIFT_PX_PER_MPS := 16.0

## The period, in noise cells, the smeared field tiles at and the drift wraps
## modulo -- and, in eddy units, the period the eddy field tiles at and the
## eddy drift wraps modulo. Bounds both direction-scaled translations for
## ever: on a bend the reconstructed flow_dir differs by a fraction of a
## degree between neighbouring fragments, and that angle times the
## translation is how far apart their samples land -- at 20 cells a
## quarter-degree is a twentieth of a cell, invisible; unbounded it reached
## tens of cells after twenty minutes of play and shredded every curved
## reach (found live on the Loire; GPU-measured 0.056 of the water pixels
## as isolated specks at ~2000 s against 0.003 fresh). The drifting texture
## repeats every period / rate seconds on a reach, out of step with the
## half-cycle morph, so no loop reads as one. The detail octave's period is
## EDDY_DETAIL_FREQUENCY times this and must be a whole number of cells.
## Pinned by test_the_drift_translations_are_bounded_by_the_noise_period
## and test_a_long_session_does_not_shred_the_field_on_a_bend.
const DRIFT_PERIOD_CELLS := 20.0

## The dim end of the pulse that streams along a stroke. 0.55 was a 45%
## modulation, a shimmer; 0.35 is the depth at which a bright segment
## visibly travels down a line. Never zero. Pinned by
## test_the_pulse_is_deep_enough_to_see_streaming.
const PULSE_FLOOR := 0.35

## How fast the standing eddies migrate downstream, as a fraction of the
## water's VISIBLE speed (surface_px_per_s -- the phase drag's translation
## plus the drift, not the drift alone). 0.4 and then 0.6 of the drift alone
## were tried first: at a typical 0.5 m/s reach that is 4-6 world px/s
## against a surface streaming at ~30, and it was reported as "a wobble
## stays in place instead of flowing with the river". With the wobble small
## the whirls are most of what there is ON a line to see moving -- they are
## the lines' shape -- and once the ripples were carried at the water's
## visible speed the report was "the lines should move at the same speed".
## So 1.0: the lines move at exactly the speed the ring is carried at. The
## surface still deforms through them because the phase drag stretches
## away from this steady translation and resets. Pinned by
## test_the_bend_drifts_downstream_with_the_current and
## test_the_lines_and_the_ripples_move_at_the_same_speed.
const BEND_DRIFT_FRACTION := 1.0

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
## The half width, in NOISE CELLS, that LINE_WOBBLE was tuned at -- a
## 2.0-tile half width, which is also the only width the old monotonicity
## test ever exercised. Wider reaches scale the wobble down in proportion
## so they fold no more than this one does.
const WOBBLE_REFERENCE_CELLS := 2.56

## CUT from 0.6. At 0.6 the wobble's gradient was 2.3x the guide's at every
## width from two tiles up -- the field folded into cells and the strokes
## were their fragments. 0.12 puts the ratio at 0.46 (bar 0.5). The whirl
## that 0.6 was carrying now enters through the guide instead, where it
## cannot fold; see the s_field line.
const LINE_WOBBLE := 0.17
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
	material.set_shader_parameter("smear_curvature", SMEAR_CURVATURE)
	material.set_shader_parameter("map_smoothing", MAP_SMOOTHING)
	material.set_shader_parameter("obstacle_side_softness", OBSTACLE_SIDE_SOFTNESS)
	material.set_shader_parameter("debug_across", DEBUG_ACROSS)
	material.set_shader_parameter("smear_gain", SMEAR_GAIN)
	material.set_shader_parameter("turbulence_strength", TURBULENCE_STRENGTH)
	material.set_shader_parameter("eddy_scale", EDDY_SCALE)
	material.set_shader_parameter("eddy_detail_weight", EDDY_DETAIL_WEIGHT)
	material.set_shader_parameter("eddy_detail_frequency", EDDY_DETAIL_FREQUENCY)
	material.set_shader_parameter("flow_map_tiles", float(FLOW_MAP_TILES))
	material.set_shader_parameter("half_width_tiles", RiverCatalog.RIVER_HALF_WIDTH_TILES)
	material.set_shader_parameter("tile_px", TILE_PX)
	material.set_shader_parameter("still_flow_m_s", STILL_FLOW_M_S)
	material.set_shader_parameter("still_ripple", STILL_RIPPLE)
	material.set_shader_parameter("eddy_swirl", EDDY_SWIRL)
	material.set_shader_parameter("bank_shear", BANK_SHEAR)
	material.set_shader_parameter("bank_feather", BANK_FEATHER)
	material.set_shader_parameter("across_jitter", ACROSS_JITTER)
	material.set_shader_parameter("jitter_scale", JITTER_SCALE)
	material.set_shader_parameter("boulder_count", 0)
	var empty_radii := PackedFloat32Array()
	empty_radii.resize(24)
	material.set_shader_parameter("boulder_radius", empty_radii)
	material.set_shader_parameter("boulder_reach_ratio", BOULDER_REACH_RATIO)
	material.set_shader_parameter("boulder_shoal_ratio", BOULDER_SHOAL_RATIO)
	material.set_shader_parameter("boulder_foam_reach_ratio", BOULDER_FOAM_REACH_RATIO)
	material.set_shader_parameter("foam_min_m_s", FOAM_MIN_M_S)
	material.set_shader_parameter("foam_full_m_s", FOAM_FULL_M_S)
	material.set_shader_parameter("foam_alpha", FOAM_ALPHA)
	material.set_shader_parameter("foam_color", FOAM_COLOR)
	material.set_shader_parameter("boulder_wake_length_ratio", BOULDER_WAKE_LENGTH_RATIO)
	material.set_shader_parameter("boulder_wake_width_ratio", BOULDER_WAKE_WIDTH_RATIO)
	material.set_shader_parameter("boulder_wake_gain", BOULDER_WAKE_GAIN)
	material.set_shader_parameter("wake_foam", WAKE_FOAM)
	material.set_shader_parameter("wader_count", 0)
	material.set_shader_parameter("wader_reach_px", WADER_REACH_PX)
	material.set_shader_parameter("wader_radius_px", WADER_RADIUS_PX)
	material.set_shader_parameter("wader_wake_trail", WADER_WAKE_TRAIL)
	material.set_shader_parameter("drift_px_per_mps", DRIFT_PX_PER_MPS)
	material.set_shader_parameter("drift_period", DRIFT_PERIOD_CELLS)
	material.set_shader_parameter("wrap_crossfade_cells", WRAP_CROSSFADE_CELLS)
	material.set_shader_parameter("fast_flow_m_s", FAST_FLOW_M_S)
	material.set_shader_parameter("line_count", LINE_COUNT)
	material.set_shader_parameter("across_line_scale", ACROSS_LINE_SCALE)
	material.set_shader_parameter("line_wobble", LINE_WOBBLE)
	material.set_shader_parameter("bend_drift_fraction", BEND_DRIFT_FRACTION)
	material.set_shader_parameter("pulse_floor", PULSE_FLOOR)
	material.set_shader_parameter("wobble_reference_cells", WOBBLE_REFERENCE_CELLS)
	material.set_shader_parameter("line_width", LINE_WIDTH)
	material.set_shader_parameter("line_strength", LINE_STRENGTH)
	material.set_shader_parameter("line_color", LINE_COLOR)
	material.set_shader_parameter("line_color_deep", LINE_COLOR_DEEP)
	material.set_shader_parameter("night_lift", 0.0)
	material.set_shader_parameter("night_stroke_boost", NIGHT_STROKE_BOOST)
	material.set_shader_parameter("moonlight_ink", MOONLIGHT_INK)
	material.set_shader_parameter("shore_pos", SHORE_POS)
	material.set_shader_parameter("shore_width", SHORE_WIDTH)
	material.set_shader_parameter("disturbance_count", 0)
	material.set_shader_parameter("ripple_speed", RIPPLE_SPEED)
	material.set_shader_parameter("ripple_lifetime", RIPPLE_LIFETIME)
	material.set_shader_parameter("ripple_wavelength", RIPPLE_WAVELENGTH)
	material.set_shader_parameter("ripple_packet_width", RIPPLE_PACKET_WIDTH)
	material.set_shader_parameter("ripple_spread_decay", RIPPLE_SPREAD_DECAY)
	material.set_shader_parameter("ripple_line_gain", RIPPLE_LINE_GAIN)
	material.set_shader_parameter("ripple_crest_min", RIPPLE_CREST_MIN)
	material.set_shader_parameter("ripple_crest_full", RIPPLE_CREST_FULL)
	material.set_shader_parameter("ripple_ring_edge", RIPPLE_RING_EDGE)
	material.set_shader_parameter("ripple_ink_max", RIPPLE_INK_MAX)
	material.set_shader_parameter("rain_intensity", 0.0)  # off by default: no rain until told
	material.set_shader_parameter("rain_ripple_speed", RAIN_RIPPLE_SPEED)
	material.set_shader_parameter("rain_ripple_lifetime", RAIN_RIPPLE_LIFETIME)
	material.set_shader_parameter("rain_ripple_wavelength", RAIN_RIPPLE_WAVELENGTH)
	material.set_shader_parameter("rain_ripple_packet_width", RAIN_RIPPLE_PACKET_WIDTH)
	material.set_shader_parameter("rain_ripple_line_gain", RAIN_RIPPLE_LINE_GAIN)
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


## Directly sets the movement-ripple uniforms. `positions`/`ages` come
## padded to DISTURBANCE_SLOTS and `count` says how many slots are live --
## this surface deliberately owns no buffer of its own: EarthChunkManager
## hands it the very same one WaterShader ages for the sea, so a wake can
## never expand in one surface and sit frozen in the other.
func set_disturbances(
	positions: PackedVector2Array, ages: PackedFloat32Array, count: int
) -> void:
	var material := shared_material()
	material.set_shader_parameter("disturbance_pos", positions)
	material.set_shader_parameter("disturbance_age", ages)
	material.set_shader_parameter("disturbance_count", count)


## Mirrors WaterShader.set_rain_intensity -- see EarthChunkManager.set_rain,
## which now pushes to BOTH surfaces (rivers/lakes/the sea all render on
## this one flow overlay in real gameplay; see _paint_water_overlay's own
## doc comment for why the OLD ocean-only water_layer this used to be the
## only receiver of never actually paints a cell any more).
func set_rain_intensity(intensity: float) -> void:
	shared_material().set_shader_parameter("rain_intensity", intensity)


## The exact math the shader's ripple_packet runs, mirrored on the CPU for
## the same reason every other mirror here exists -- a fragment shader
## cannot be asserted headlessly. Written out rather than delegated to
## WaterShader.ripple_amplitude ON PURPOSE: the GLSL above is a genuine
## second copy, so the mirror has to be one too, and the test that asserts
## the two agree is then a real pin on the two shaders rather than a
## tautology.
##
## Returns a SIGNED displacement -- positive on a crest, negative in a
## trough, zero once the ring has died or ahead of its advancing front.
static func ripple_packet(distance_units: float, age_seconds: float) -> float:
	if age_seconds < 0.0 or age_seconds > RIPPLE_LIFETIME:
		return 0.0
	var front := age_seconds * RIPPLE_SPEED
	var phase := front - distance_units
	var packet := exp(-absf(phase) / RIPPLE_PACKET_WIDTH)
	var rings := sin(phase * TAU / RIPPLE_WAVELENGTH)
	var age_fade := 1.0 - age_seconds / RIPPLE_LIFETIME
	var spread_fade := 1.0 / (1.0 + front * RIPPLE_SPREAD_DECAY)
	return rings * packet * age_fade * spread_fade


## The exact math the shader's OWN rain_ripple_packet runs -- a genuine
## second copy of ripple_packet's formula shape above, on purpose, for the
## same reason ripple_packet itself is a second copy of WaterShader's: the
## test that pins this against the GLSL is a real agreement between two
## independently-written implementations, not a tautology. Uses the
## RAIN_RIPPLE_* tuning above instead of the movement one -- a genuinely
## different (shorter, tighter) packet, not the same formula called with
## different numbers through some shared helper.
static func rain_ripple_packet(distance_units: float, age_seconds: float) -> float:
	if age_seconds < 0.0 or age_seconds > RAIN_RIPPLE_LIFETIME:
		return 0.0
	var front := age_seconds * RAIN_RIPPLE_SPEED
	var phase := front - distance_units
	var packet := exp(-absf(phase) / RAIN_RIPPLE_PACKET_WIDTH)
	var rings := sin(phase * TAU / RAIN_RIPPLE_WAVELENGTH)
	var age_fade := 1.0 - age_seconds / RAIN_RIPPLE_LIFETIME
	var spread_fade := 1.0 / (1.0 + front * RIPPLE_SPREAD_DECAY)
	return rings * packet * age_fade * spread_fade


## How hard the ring inks at a crest whose envelope is `amplitude` -- the
## CPU mirror of the shader's strength term, `smoothstep(ripple_crest_min,
## ripple_crest_full, envelope) * ripple_ink_max`, so the ring's graduation
## through its life is a tested curve rather than a pair of eyeballed
## thresholds. 0 for flat water and the spent tail; RIPPLE_INK_MAX for a
## fresh crest. (At a crest the signed packet equals its envelope, so the
## packet's scanned peak is the right thing to feed this.)
static func ripple_ink(amplitude: float) -> float:
	return smoothstep(RIPPLE_CREST_MIN, RIPPLE_CREST_FULL, amplitude) * RIPPLE_INK_MAX


## The packet without its sine -- the CPU mirror of the shader's
## ripple_envelope: never under |ripple_packet|, equal to it at a crest.
static func ripple_envelope(distance_units: float, age_seconds: float) -> float:
	if age_seconds < 0.0 or age_seconds > RIPPLE_LIFETIME:
		return 0.0
	var front := age_seconds * RIPPLE_SPEED
	var phase := front - distance_units
	var packet := exp(-absf(phase) / RIPPLE_PACKET_WIDTH)
	var age_fade := 1.0 - age_seconds / RIPPLE_LIFETIME
	var spread_fade := 1.0 / (1.0 + front * RIPPLE_SPREAD_DECAY)
	return packet * age_fade * spread_fade


## The ring's ink band, in world px: the arc of the crest's sine above
## RIPPLE_RING_EDGE, one number at every age.
static func ripple_ring_width_px() -> float:
	return RIPPLE_WAVELENGTH / TAU * (PI - 2.0 * asin(RIPPLE_RING_EDGE))


## A current line's full extent in world px: the stroke fades to nothing at
## LINE_WIDTH either side of its contour, in across units of HALF_WIDTH_PX.
static func line_width_px() -> float:
	return 2.0 * LINE_WIDTH * HALF_WIDTH_PX


## Where a ripple recorded at `origin` is centred `age_seconds` later --
## the CPU mirror of the shader's own carried centre. A ring in a current
## is concentric about a point that travels WITH the water, at the water's
## whole visible speed (surface_px_per_s); only in still water does it stay
## put.
static func ripple_center(
	origin: Vector2, flow_dir: Vector2, speed_m_s: float, age_seconds: float
) -> Vector2:
	return origin + flow_dir * (surface_px_per_s(speed_m_s) * age_seconds)


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
	# Smooth and odd about the stagnation line, and CLAMPED so only the
	# core is affected. A hard sign flip left the magnitude at exactly R
	# there while the sign jumped, tearing the field by 2R (21.95px for a
	# boulder, 11.95px for a wader).
	#
	# The clamp is the whole point. An unclamped lateral/sqrt(lateral^2 +
	# R^2) removes the tear but scales the push down EVERYWHERE, dropping
	# its peak from R to 0.30R -- which took the bulge with it, reported
	# immediately: "the straight line is gone, but with it the bulge
	# walking in and out of water which was what i wanted to be kept".
	# Clamped, the push is untouched beyond OBSTACLE_SIDE_SOFTNESS * R and
	# still peaks at about 0.71R.
	var side := clampf(lateral / (radius_px * OBSTACLE_SIDE_SOFTNESS), -1.0, 1.0)
	return side * displaced * envelope


## A rock's radius on the water, in world px, from its real diameter: half
## its drawn height (StoneSize.world_height_px -- the water parts around
## the rock the player sees), floored at MIN_BOULDER_RADIUS_PX.
static func boulder_radius_px_for(diameter_cm: float) -> float:
	return maxf(StoneSize.world_height_px(diameter_cm) * 0.5, MIN_BOULDER_RADIUS_PX)


## How far a rock of this radius pushes the water, in world px.
static func boulder_reach_px_for(radius_px: float) -> float:
	return radius_px * BOULDER_REACH_RATIO


## A boulder's across-push at a fragment `offset_px` from the rock, given
## the flow perpendicular -- the round core in across-fraction units, for a
## rock of `radius_px` (the reference rock when unspecified).
static func boulder_across_push(
	offset_px: Vector2, flow_perp: Vector2, radius_px: float = BOULDER_RADIUS_PX
) -> float:
	return obstacle_lateral_shift_px(
		offset_px, flow_perp, radius_px, boulder_reach_px_for(radius_px), 0.0
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


## How dry the eyot leaves a fragment `distance_px` from the centre of a
## rock of `radius_px`: 0 under the rock, 1 outside its radius, soft-edged
## and ROUND.
static func eyot_dry_factor(distance_px: float, radius_px: float = BOULDER_RADIUS_PX) -> float:
	return smoothstep(radius_px * 0.6, radius_px, distance_px)


## The rock's shoal at `distance_px` from the centre of a rock of
## `radius_px`: 1 at and under the rock's edge (the bed IS the rock),
## falling to 0 BOULDER_SHOAL_RATIO radii past it. The CPU mirror of the
## shader's per-boulder shoal term. A function of distance alone: the
## shoal is geometry, like the banks, and never reads the moving field.
static func boulder_shoal(distance_px: float, radius_px: float) -> float:
	return 1.0 - smoothstep(radius_px, radius_px + radius_px * BOULDER_SHOAL_RATIO, distance_px)


## The channel's depth fraction after the rock's shoal has shallowed it --
## what the cel body is cut from near a rock. At the rock's edge it is 0,
## the bank's own value, so depth_color paints the same lightest tone.
static func shoaled_depth_fraction(
	channel_depth_fraction: float, distance_px: float, radius_px: float
) -> float:
	return channel_depth_fraction * (1.0 - boulder_shoal(distance_px, radius_px))


## The foam window on a rock's upstream face at `offset_px` from a rock of
## `radius_px` in a current running along `flow_dir` -- the CPU mirror of
## the shader's nose * foam_window: the squared cosine from the stagnation
## line (zero at and behind the shoulders) inside a window just off the
## face. Geometry only; foam_drive gates it by speed.
static func boulder_foam(offset_px: Vector2, flow_dir: Vector2, radius_px: float) -> float:
	var d := offset_px.length()
	var along := offset_px.dot(flow_dir)
	var nose := clampf(-along / maxf(d, 0.001), 0.0, 1.0)
	nose *= nose
	var window := smoothstep(radius_px * 0.7, radius_px, d) \
		* (1.0 - smoothstep(radius_px, radius_px + radius_px * BOULDER_FOAM_REACH_RATIO, d))
	return nose * window


## How hard a reach of this speed foams at a rock: nothing at or under
## FOAM_MIN_M_S, full at FOAM_FULL_M_S, still-water gated like the shader.
static func foam_drive(speed_m_s: float) -> float:
	if is_still_water(speed_m_s):
		return 0.0
	return smoothstep(FOAM_MIN_M_S, FOAM_FULL_M_S, speed_m_s)


## The wake lobe behind a rock at `offset_px` -- the CPU mirror of the
## shader's per-boulder wake: rising over the first radius downstream,
## dying out by BOULDER_WAKE_LENGTH_RATIO radii, within
## BOULDER_WAKE_WIDTH_RATIO radii to either side. Zero upstream.
static func boulder_wake(offset_px: Vector2, flow_dir: Vector2, radius_px: float) -> float:
	var perp := Vector2(-flow_dir.y, flow_dir.x)
	var along := offset_px.dot(flow_dir)
	var lateral := offset_px.dot(perp)
	return smoothstep(0.0, radius_px, along) \
		* (1.0 - smoothstep(radius_px, radius_px * BOULDER_WAKE_LENGTH_RATIO, along)) \
		* (1.0 - smoothstep(radius_px, radius_px * BOULDER_WAKE_WIDTH_RATIO, absf(lateral)))


## The waterline: 1 inside the channel, 0 past the bank curve, feathered
## over BANK_FEATHER either side of |across| == 1.
static func bank_alpha(across_magnitude: float) -> float:
	return 1.0 - smoothstep(1.0 - BANK_FEATHER, 1.0 + BANK_FEATHER, across_magnitude)


## The stroke mask, mirroring the shader: how strongly a field value n
## lands inside either contour family. What the coverage, morphing and
## fast-reach tests all measure.
## The guided stroke field for one fragment: signed across-fraction plus
## the advected wobble -- the thing whose level sets ARE the current lines.
static func stroke_field(
	across_fraction: float, n: float, half_width_cells := WOBBLE_REFERENCE_CELLS,
	bend_cells := 0.0
) -> float:
	# `bend_cells` is the eddy displacement in NOISE cells, as
	# bend_displacement returns it; divided by the half width in cells it
	# becomes an across-fraction shift of the guide, exactly as the shader
	# does it.
	var guide := across_fraction + bend_cells / maxf(half_width_cells, 0.01)
	return (
		guide * ACROSS_LINE_SCALE
		+ (n - 0.5) * LINE_WOBBLE * wobble_scale_for(half_width_cells)
	)


## How far the wobble is turned down for a channel this many noise cells
## wide. Never above 1: this only ever tames water wider than the width
## LINE_WOBBLE was tuned at, so narrow reaches are untouched.
static func wobble_scale_for(half_width_cells: float) -> float:
	return minf(WOBBLE_REFERENCE_CELLS / maxf(half_width_cells, 0.01), 1.0)


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
## river's full morph, by test. 0.25 -> 0.45 when ADVECT_STRENGTH dropped
## 7.2 -> 1.2, so a lake's sideways breathing goes 1.8 -> 0.54 cells (22
## -> 7 world px): calmer, as asked, but not frozen.
const STILL_RIPPLE := 0.45


## Whirl (third playtest, "more natural whirly turbulences in curves"):
## BOTH attempts at it broke the base rendering and are reverted to
## zero, the same way and for the same class of reason.
##
## EDDY_SWIRL rotated the stroke smear by the eddy field: it sawed every
## stroke into a regular zig-zag with the eddy noise's own period
## (smearing along a direction that oscillates every few tiles folds the
## level sets). Pinned at zero by
## test_the_smear_follows_the_flow_and_never_the_eddies.
##
## BANK_SHEAR grew the turbulence displacement itself by up to 25% near
## the waterline. TURBULENCE_STRENGTH alone is calibrated right up against
## a real, TESTED fold threshold (test_the_bend_never_folds_the_surface_
## over_itself: past it, displacement does not bend the noise pattern, it
## tears it) -- but that test's CPU mirror (bend_displacement/
## warped_across) never multiplied by any shear factor, so it kept passing
## while the LIVE shader, with shear applied, silently crossed the real
## threshold across the wide band near a hydrology river's bank (a
## channel several tiles wide has a lot of "near the bank"). The result
## was a sharp, chunky, torn-looking zigzag -- reported as "this huge
## zigzag still persists" through two rounds of an unrelated fix, because
## it was never the width-texture bug at all. Reverted to zero so the
## live formula and its tested CPU mirror agree exactly again.
const EDDY_SWIRL := 0.0
const BANK_SHEAR := 0.0


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


## The cubic B-spline basis at a fractional position between texels: the
## four weights applied to the texels at -1, 0, +1 and +2. Partitions
## unity (a reconstruction that did not would move the waterline) and is
## everywhere non-negative (a negative lobe rings at a step edge, which on
## a distance field is a false bank).
static func bspline_weights(t: float) -> PackedFloat32Array:
	var t2 := t * t
	var t3 := t2 * t
	return PackedFloat32Array([
		(1.0 - 3.0 * t + 3.0 * t2 - t3) / 6.0,
		(4.0 - 6.0 * t2 + 3.0 * t3) / 6.0,
		(1.0 + 3.0 * t + 3.0 * t2 - 3.0 * t3) / 6.0,
		t3 / 6.0,
	])


## Plain bilinear over a square grid, exactly as filter_linear does it:
## texel centres at +0.5, linear weights. The CPU mirror of what the map
## sampling used to be, kept so the two filters can be compared in a test
## and by tools/probe_bilinear.gd rather than only by eye.
static func sample_grid_bilinear(values: PackedFloat32Array, span: int, at: Vector2) -> float:
	var fx := at.x - 0.5
	var fy := at.y - 0.5
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var x1 := clampi(x0 + 1, 0, span - 1)
	var y1 := clampi(y0 + 1, 0, span - 1)
	x0 = clampi(x0, 0, span - 1)
	y0 = clampi(y0, 0, span - 1)
	var top: float = lerp(values[y0 * span + x0], values[y0 * span + x1], tx)
	var bottom: float = lerp(values[y1 * span + x0], values[y1 * span + x1], tx)
	return lerp(top, bottom, ty)


## Cubic B-spline over the same grid: the CPU mirror of texture_bicubic.
## Approximating rather than interpolating -- it smooths the samples
## slightly, which on a distance field is a feature, and unlike warping the
## sample coordinate it does not bunch contours toward the texel centres.
static func sample_grid_bspline(values: PackedFloat32Array, span: int, at: Vector2) -> float:
	var fx := at.x - 0.5
	var fy := at.y - 0.5
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var wx := bspline_weights(fx - float(x0))
	var wy := bspline_weights(fy - float(y0))
	var total := 0.0
	for j in 4:
		var sy := clampi(y0 - 1 + j, 0, span - 1)
		var row := 0.0
		for i in 4:
			var sx := clampi(x0 - 1 + i, 0, span - 1)
			row += values[sy * span + sx] * wx[i]
		total += row * wy[j]
	return total


## How far, in WORLD PIXELS, one end of the smear sits from its centre.
## The outermost tap is (SMEAR_TAPS - 1) / 2 steps of SMEAR_SPACING away
## in noise units, and a noise unit is NOISE_SCALE world pixels. About
## 2.66 tiles, which is the number tools/probe_smear.gd measures against.
static func smear_half_span_px() -> float:
	return float((SMEAR_TAPS - 1) / 2) * SMEAR_SPACING / NOISE_SCALE


## The heading tap `k` steps along, interpolated between the flow read at
## each END of the smear. Always a UNIT vector: a tap chooses a heading
## only, never a step length, and a short interpolated vector would
## quietly shorten the stroke through the middle of a bend.
static func smear_tap_direction(dir_start: Vector2, dir_end: Vector2, k: int) -> Vector2:
	var half := float((SMEAR_TAPS - 1) / 2)
	var mixed := dir_start.lerp(dir_end, (float(k) + half) / (2.0 * half))
	if mixed.length() < 1e-6:
		return dir_start.normalized()
	return mixed.normalized()


## The CPU mirror of the shader's value_noise_tiled: the same noise on a
## lattice that wraps every `period` cells.
static func value_noise_tiled(x: float, y: float, period: float = DRIFT_PERIOD_CELLS) -> float:
	var ix: float = floor(x)
	var iy: float = floor(y)
	var fx: float = x - ix
	var fy: float = y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var x0 := fposmod(ix, period)
	var y0 := fposmod(iy, period)
	var x1 := fposmod(ix + 1.0, period)
	var y1 := fposmod(iy + 1.0, period)
	return lerpf(
		lerpf(value_hash(x0, y0), value_hash(x1, y0), fx),
		lerpf(value_hash(x0, y1), value_hash(x1, y1), fx),
		fy
	)


## The CPU mirror of the shader's line_field: the LIC smear along an
## arbitrary direction plus the unsmeared detail octave, world-anchored.
static func line_field_value(px: float, py: float, dir: Vector2) -> float:
	var total := 0.0
	for k in range(-4, 5):
		var offset := dir * (float(k) * SMEAR_SPACING)
		var weight := 5.0 - absf(float(k))
		total += value_noise_tiled(px + offset.x, py + offset.y) * weight
	return clampf((total / 25.0 - 0.5) * SMEAR_GAIN + 0.5, 0.0, 1.0)


## The field flowing east -- the direction-free convenience the coverage
## and swing measurements sample (the distribution is direction-invariant;
## the seam test is where direction sensitivity is measured).
static func surface_value(px: float, py: float) -> float:
	return line_field_value(px, py, Vector2(1, 0))


## The whole animated pipeline at one world point (in noise cells): the
## standing bend, both advected phases, the crossfade. What the seam test
## compares across a direction-bin change.
##
## Both drift_cells and bend_drift_cells wrap at DRIFT_PERIOD_CELLS so a
## long session never shreds (see "bounded drift" below) -- but a wrap is
## only invisible to value_noise_tiled when the shift it produces lands on
## an exact integer MULTIPLE of the period on both axes, which for a
## direction-scaled shift (dir * period) only happens at an exactly
## axis-aligned dir. At any other bearing the wrapped translation lands on
## an unrelated point in the tile and the field pops (see "the wrap
## instant itself" in test_river_flow_shader.gd). Both wraps are therefore
## crossfaded here against their own half-period-offset twin, exactly the
## way the two ADVECT phases already hide EACH OTHER's reset -- but only
## within WRAP_CROSSFADE_CELLS of the actual wrap (see that constant),
## since the twin sits a HALF PERIOD away and is otherwise nothing like a
## continuation of the trajectory being crossfaded away from.
static func animated_field_value(
	px: float, py: float, dir: Vector2, time_seconds: float, speed_mps := 0.0
) -> float:
	var perp := Vector2(-dir.y, dir.x)
	# The eddies drift downstream at a fraction of the surface's drift --
	# a translation of where the bend is read, exactly as the shader does.
	var bend_shift := bend_drift_cells(speed_mps, time_seconds)
	var b := bend_displacement(
		(px - dir.x * bend_shift) * EDDY_SCALE, (py - dir.y * bend_shift) * EDDY_SCALE
	)
	var bend_weight := bend_drift_crossfade_weight(speed_mps, time_seconds)
	if bend_weight > 0.0:
		var bend_shift_alt := bend_drift_cells_alternate(speed_mps, time_seconds)
		var b_alt := bend_displacement(
			(px - dir.x * bend_shift_alt) * EDDY_SCALE, (py - dir.y * bend_shift_alt) * EDDY_SCALE
		)
		b = lerpf(b, b_alt, bend_weight)
	var qx := px + perp.x * b
	var qy := py + perp.y * b
	var phase_a := fposmod(time_seconds * ADVECT_RATE, 1.0)
	var phase_b := fposmod(time_seconds * ADVECT_RATE + 0.5, 1.0)
	var drift := drift_cells(speed_mps, time_seconds)
	var shift_a := ADVECT_STRENGTH * phase_a + drift
	var shift_b := ADVECT_STRENGTH * phase_b + drift
	var sample_a := line_field_value(qx - dir.x * shift_a, qy - dir.y * shift_a, dir)
	var sample_b := line_field_value(qx - dir.x * shift_b, qy - dir.y * shift_b, dir)
	var drift_weight := drift_crossfade_weight(speed_mps, time_seconds)
	if drift_weight > 0.0:
		var drift_alt := drift_cells_alternate(speed_mps, time_seconds)
		var shift_a_alt := ADVECT_STRENGTH * phase_a + drift_alt
		var shift_b_alt := ADVECT_STRENGTH * phase_b + drift_alt
		var sample_a_alt := line_field_value(qx - dir.x * shift_a_alt, qy - dir.y * shift_a_alt, dir)
		var sample_b_alt := line_field_value(qx - dir.x * shift_b_alt, qy - dir.y * shift_b_alt, dir)
		sample_a = lerpf(sample_a, sample_a_alt, drift_weight)
		sample_b = lerpf(sample_b, sample_b_alt, drift_weight)
	return lerpf(sample_a, sample_b, absf(1.0 - 2.0 * phase_a))


## How wide a window either drift's crossfade blends across, either side of
## its own wrap, in noise cells. Small enough that the everyday, mid-cycle
## trajectory is untouched (the crossfade weight is exactly 0 outside it,
## so the field matches the plain wrapped value bit for bit); wide enough
## that no single frame's step is still much bigger than an ordinary
## frame of flow evolution, even at a fast reach's short period. Pinned
## empirically (tools/probe_river_drift_wrap.gd): at 0.6 cells the worst
## frame at a fast reach (2.2 m/s, ~7s smear period) still popped several
## times the ordinary step; at 1.0 cells it does not.
const WRAP_CROSSFADE_CELLS := 1.0


## Fades from 1 (fully blend toward the crossfade twin) to 0 as `distance`
## (cells to the nearest wrap point) grows past WRAP_CROSSFADE_CELLS. The
## shared shape both drift_crossfade_weight and bend_drift_crossfade_weight
## use.
static func wrap_crossfade_weight(distance_to_wrap_cells: float) -> float:
	var t := clampf(distance_to_wrap_cells / WRAP_CROSSFADE_CELLS, 0.0, 1.0)
	return 1.0 - t * t * (3.0 - 2.0 * t)


## How far the pattern has travelled downstream, in noise cells: linear in
## time at the REACH'S drift speed (one constant between confluences --
## see EarthChunkGenerator.drift_speed_m_s_for_discharge_units; zero below
## the still gate), wrapped at DRIFT_PERIOD_CELLS -- the noise it
## translates tiles at that period, so a LONG SESSION never drifts into
## speckle and the direction-scaled offset stays bounded. This alone does
## NOT make the wrap instant itself invisible for a non-axis-aligned dir
## (see animated_field_value) -- that is what drift_cells_alternate and
## drift_crossfade_weight are for.
static func drift_cells(reach_speed_m_s: float, seconds: float) -> float:
	if reach_speed_m_s < STILL_FLOW_M_S:
		return 0.0
	return fposmod(DRIFT_PX_PER_MPS * reach_speed_m_s * seconds * NOISE_SCALE, DRIFT_PERIOD_CELLS)


## drift_cells's own half-period-offset twin: wraps exactly when drift_cells
## is at ITS safest (mid-cycle), and vice versa -- crossfading toward this
## exactly when drift_cells nears its own wrap is what hides the pop,
## mirroring how the two ADVECT phases already hide each other's reset.
static func drift_cells_alternate(reach_speed_m_s: float, seconds: float) -> float:
	if reach_speed_m_s < STILL_FLOW_M_S:
		return 0.0
	return fposmod(
		DRIFT_PX_PER_MPS * reach_speed_m_s * seconds * NOISE_SCALE + DRIFT_PERIOD_CELLS * 0.5,
		DRIFT_PERIOD_CELLS
	)


## How much of drift_cells_alternate to blend into drift_cells right now:
## 0 (today's plain behaviour, bit for bit) away from any wrap, ramping to
## 1 exactly at the wrap so the raw discontinuity is never actually shown.
static func drift_crossfade_weight(reach_speed_m_s: float, seconds: float) -> float:
	if reach_speed_m_s < STILL_FLOW_M_S:
		return 0.0
	var wrapped := drift_cells(reach_speed_m_s, seconds)
	return wrap_crossfade_weight(minf(wrapped, DRIFT_PERIOD_CELLS - wrapped))


## The water's VISIBLE downstream speed in world px/s -- the CPU mirror of
## the shader's surface_px_per_s. The drawn surface is moved by two terms:
## the two-phase drag translates the field ADVECT_STRENGTH cells every
## 1/ADVECT_RATE seconds regardless of the reach, and the linear drift adds
## DRIFT_PX_PER_MPS per m/s of real current. Everything that has to move
## WITH the water (the ring centre, the eddy field) rides this sum. The
## drift is most of it by design: it is the coherent translation kinks,
## whirls and rings can all follow, while the drag is a small deformation
## (when the drag was 7.2 cells it was two thirds of this number, and its
## crossfade dissolved every kink in place). Gated by the same hard
## STILL_FLOW_M_S step the shader's still path uses, so a lake's surface
## speed is exactly zero.
static func surface_px_per_s(speed_mps: float) -> float:
	if speed_mps < STILL_FLOW_M_S:
		return 0.0
	return ADVECT_STRENGTH * ADVECT_RATE / NOISE_SCALE + DRIFT_PX_PER_MPS * speed_mps


## The same visible speed, as a distance in noise cells over `seconds`.
static func surface_cells(speed_mps: float, seconds: float) -> float:
	return surface_px_per_s(speed_mps) * seconds * NOISE_SCALE


## How far the standing eddies have migrated downstream, in noise cells:
## BEND_DRIFT_FRACTION of the water's visible travel. Zero in still water.
## Wrapped at DRIFT_PERIOD_CELLS in EDDY units (the eddy field tiles at
## that period), reported back in noise cells. Same wrap-instant caveat as
## drift_cells -- see bend_drift_cells_alternate/bend_drift_crossfade_weight.
static func bend_drift_cells(reach_speed_m_s: float, seconds: float) -> float:
	return fposmod(
		surface_cells(reach_speed_m_s, seconds) * BEND_DRIFT_FRACTION * EDDY_SCALE, DRIFT_PERIOD_CELLS
	) / EDDY_SCALE


## bend_drift_cells's own half-period-offset twin, in EDDY units -- the
## crossfade partner for bend_drift_crossfade_weight, exactly as
## drift_cells_alternate is for drift_cells.
static func bend_drift_cells_alternate(reach_speed_m_s: float, seconds: float) -> float:
	return fposmod(
		surface_cells(reach_speed_m_s, seconds) * BEND_DRIFT_FRACTION * EDDY_SCALE
			+ DRIFT_PERIOD_CELLS * 0.5,
		DRIFT_PERIOD_CELLS
	) / EDDY_SCALE


## How much of bend_drift_cells_alternate to blend into bend_drift_cells
## right now -- the eddy-drift counterpart of drift_crossfade_weight.
static func bend_drift_crossfade_weight(reach_speed_m_s: float, seconds: float) -> float:
	var wrapped := bend_drift_cells(reach_speed_m_s, seconds) * EDDY_SCALE
	return wrap_crossfade_weight(minf(wrapped, DRIFT_PERIOD_CELLS - wrapped))


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
	var coarse := value_noise_tiled(eddy_x, eddy_y, DRIFT_PERIOD_CELLS) - 0.5
	var fine := value_noise_tiled(
		eddy_x * EDDY_DETAIL_FREQUENCY + 19.7, eddy_y * EDDY_DETAIL_FREQUENCY + 7.3,
		DRIFT_PERIOD_CELLS * EDDY_DETAIL_FREQUENCY
	) - 0.5
	return (coarse + fine * EDDY_DETAIL_WEIGHT) * TURBULENCE_STRENGTH


## Where a point lands, on the axis the bend pushes along, after the bend
## -- the no-fold sweep runs on this: if it ever decreases while the input
## increases, the warp has folded the surface over itself.
static func warped_across(world_x: float, world_y: float) -> float:
	return world_y + bend_displacement(world_x * EDDY_SCALE, world_y * EDDY_SCALE)


## The same, at the bend's full strength inside a rock's wake (the gain
## at its maximum) -- what the no-fold sweep has to hold there too.
static func warped_across_in_wake(world_x: float, world_y: float) -> float:
	return world_y + bend_displacement(world_x * EDDY_SCALE, world_y * EDDY_SCALE) * (1.0 + BOULDER_WAKE_GAIN)


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
