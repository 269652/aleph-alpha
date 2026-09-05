extends RefCounted

## GPU snow: illustrated snow stamps bombed across world space by a fragment
## shader (see docs/concept/snow_cover.md).
##
## Snow used to be a TileMapLayer of baked per-(band, variant) tiles that
## EarthChunkManager repainted by sweeping every loaded tile every two seconds
## -- measured at ~40-50ms per sweep over the real ~22,700-tile loaded field,
## after an onset cache had already cut it from ~200ms. Snow covers everything
## in view by definition, so per-ground-unit CPU work is per-EVERYTHING work.
##
## This does the whole thing per PIXEL instead. For each fragment it asks
## which illustrated stamps overlap this world point: stamp sites sit on a
## virtual world-space lattice, and everything about a site's stamp -- jitter,
## which of the ten shape variants, which coverage level, orientation, size,
## whether it has caught snow at all yet -- is a hash of that site's own
## lattice coordinates. Nothing is stored, and the CPU's whole per-frame job
## becomes pushing one float.
##
## The tuned math is mirrored by the static funcs below, kept in sync with the
## GLSL by hand -- the same relationship water_shader.gd's ripple_amplitude
## and hillshade_shader.gd's shadow_alpha have to their own shaders, and for
## the same reason: a fragment shader cannot be asserted headless. Contract
## pinned by test_snow_bomb_shader.gd, plus test_snow_render_smoke.gd for the
## one class of failure a float64 mirror can never catch (see value_hash).

const SnowStampAtlas = preload("res://src/rendering/snow_stamp_atlas.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const SHADER_CODE := """
shader_type canvas_item;

uniform sampler2D stamp_atlas : filter_linear, repeat_disable;
uniform int atlas_columns = 10;
uniform int atlas_rows = 3;
uniform vec2 atlas_size_px = vec2(680.0, 204.0);
uniform float atlas_cell_px = 68.0;
uniform float atlas_stamp_px = 64.0;
uniform float atlas_padding_px = 2.0;

// How much snow is lying overall, 0 bare to 1 covered -- ONE float, pushed
// per frame by EarthChunkManager.step_snow. This replacing a per-tile sweep
// is the entire performance point of this shader.
uniform float snow_depth : hint_range(0.0, 1.0) = 0.0;

// The bombing lattice, in WORLD units (see the GDScript constants of the
// same names, which is where these are actually tuned and tested).
uniform float stamp_lattice_world = 16.0;
uniform float stamp_world_size = 26.0;
uniform float stamp_jitter_world = 4.0;
uniform float stamp_size_jitter = 0.15;
uniform float stamp_min_size_fraction = 0.42;
uniform float site_onset_spread = 0.55;
uniform float level_dither = 1.1;
uniform float stamp_edge_fade_uv = 0.05;
uniform float tread_depth = 0.5;
uniform float tread_alpha_factor = 0.55;

// The two-octave drift field, carried over unchanged from the tile
// implementation where it was measured and tuned across three separate
// reported bugs. Periods are in TILES; the shader converts using
// world_units_per_tile.
uniform float onset_broad_variance = 0.13;
uniform float onset_fine_variance = 0.05;
uniform float onset_drift_tiles = 12.0;
uniform float onset_fine_drift_tiles = 2.0;
uniform float world_units_per_tile = 16.0;

// Footprints: a small world-space window that follows the player, written
// only when a footstep actually lands (see SnowTrail, set_trail_mask).
uniform sampler2D trail_mask : filter_linear, repeat_disable;
uniform vec2 trail_origin = vec2(0.0, 0.0);
uniform float trail_world_size = 1024.0;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// Trig-free lattice hash (Hoskins-style). NOT the classic
// sine-times-large-constant hash -- that one is a float32 landmine at this
// game's world coordinates: a real position reaches the hundreds of
// thousands of world units, which feeds the sine millions of radians,
// float32 range reduction collapses, and the hash goes regionally
// near-constant. Snow would simply not render across whole regions while
// every float64 CPU-mirror statistic still passed. That exact failure was
// found live in this codebase's river shader. Taking the fractional part
// FIRST keeps every intermediate small, so this stays healthy at any
// coordinate the world can produce.
// (Named without the literal formula on purpose: the trig-free pin greps
// this source, and a comment must not be what trips it.)
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

// Snow drifts and shelters in patches many metres across -- a hollow, a lee
// side, the shade of a tree line catch and hold it while exposed ground
// beside them stays bare far longer. So this is low-frequency by
// construction: neighbours nearly identical, tens of tiles apart fully
// different. The fine octave adds texture WITHIN whatever broad patch the
// first one chose, with its own independent salt (two octaves of one salt can
// share zero-crossings, which would undercut the point).
float onset_at(vec2 wp) {
	vec2 tiles = wp / world_units_per_tile;
	float broad = value_noise(tiles / onset_drift_tiles + vec2(11.7, 3.1));
	float fine = value_noise(tiles / onset_fine_drift_tiles + vec2(71.3, 41.9));
	return mix(-onset_broad_variance, onset_broad_variance, broad)
		+ mix(-onset_fine_variance, onset_fine_variance, fine);
}

float tread_at(vec2 wp) {
	vec2 uv = (wp - trail_origin) / trail_world_size;
	// Outside the window reads as UNTRODDEN rather than clamping to the
	// window's edge value, which would smear its last row of footprints
	// across the rest of the world.
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return 0.0;
	}
	return texture(trail_mask, uv).r;
}

// How deep the snow lies at one point: the field's shared depth, offset by
// this point's own drift lead/lag, then packed down by whatever has walked
// here.
float lying_at(vec2 wp, float tread) {
	float base;
	if (snow_depth >= 1.0) {
		// Once the field is GENUINELY fully snowed over, onset (a lead/lag
		// on the CLIMB toward full coverage) has nothing left to lead or
		// lag -- without this, a maximally-lagging point would sit short of
		// full forever rather than the lag being a transient of an ongoing
		// snowfall.
		base = 1.0;
	} else {
		base = clamp(snow_depth + onset_at(wp), 0.0, 1.0);
	}
	// Walking PACKS snow rather than clearing it, so a trail reads as tracks
	// through a field rather than a trench dug to the soil -- and only where
	// the cover was thin to begin with does a boot reach the ground.
	return clamp(base - tread * tread_depth, 0.0, 1.0);
}

// The 8-fold dihedral group, applied to a stamp's own local UV: four
// rotations times a mirror. Trig-free and exact -- rotating the SAMPLE
// coordinate costs three compares, where rotating a world coordinate would
// need a matrix and would move far-from-origin points by thousands of units.
vec2 orient(vec2 uv, float h) {
	int o = int(h * 8.0);
	if ((o & 1) == 1) {
		uv.x = 1.0 - uv.x;
	}
	if ((o & 2) == 2) {
		uv.y = 1.0 - uv.y;
	}
	if ((o & 4) == 4) {
		uv = vec2(uv.y, uv.x);
	}
	return uv;
}

// The continuous ramp position a site's level choice sits at -- e.g. 1.35
// means "35% of the way from level 1 to level 2". The dither is what keeps a
// level transition from drawing as a contour line: neighbouring sites near a
// boundary disagree about which side they are on. It TAPERS to zero at both
// ends of the ramp (4x(1-x)), so genuinely bare ground is uniformly bare and
// genuinely full cover is uniformly full -- dithering there would leave
// thinner stamps punched into deep snow as holes.
float level_f(float lying, vec2 cell) {
	float h = value_hash(cell + vec2(29.3, 83.7));
	float taper = 4.0 * lying * (1.0 - lying);
	float f = lying * float(atlas_rows - 1) + (h - 0.5) * level_dither * taper;
	return clamp(f, 0.0, float(atlas_rows - 1));
}

// The single nearest level, for anything that wants one definite level
// rather than the crossfade bombed_snow itself uses -- nothing in this
// shader calls it today, kept for parity with the GDScript mirror's own
// level_for_site, which spatial-dither tests do call directly.
int level_for_site(float lying, vec2 cell) {
	return clamp(int(round(level_f(lying, cell))), 0, atlas_rows - 1);
}

vec2 atlas_uv(int level, int variant, vec2 local) {
	vec2 cell = vec2(float(variant), float(level)) * atlas_cell_px;
	return (cell + vec2(atlas_padding_px) + local * atlas_stamp_px) / atlas_size_px;
}

// The full 3x3 bombing accumulate. `lying` (the TREADED value) decides only
// WHETHER a site is present at all; every other part of a caught site's
// appearance -- size, level, position, orientation, variant -- reads
// `natural_lying` (the UNTREADED value) instead, so a site that stays
// caught renders identically regardless of tread. That is what makes tread
// provably unable to ADD snow anywhere, for any art -- see the GDScript
// mirror's _coverage_for_lying, which this matches exactly, for the two
// more expensive designs tried and reverted first (measured, in git
// history) before landing on this one.
vec4 bombed_snow(vec2 wp, float lying, float natural_lying) {
	vec2 base_cell = floor(wp / stamp_lattice_world);
	float best_alpha = 0.0;
	vec3 best_rgb = vec3(1.0);
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			vec2 cell = base_cell + vec2(float(ox), float(oy));

			// Has this site caught snow yet? Each holds its own
			// hashed threshold, so sites pop in one at a time as the
			// field deepens -- the same idea as the old per-tile
			// onset, at a far finer grain than a tile, which is why
			// this mechanism no longer has rungs the player can see.
			//
			// Checked FIRST, before any jitter, size or texture
			// work: a site between onsets skips all of it. The same
			// early-exit shape water_shader.gd's raindrop loop
			// documents as the fix for a measured 30fps -> 6fps
			// collapse.
			if (lying < value_hash(cell + vec2(3.7, 19.1)) * site_onset_spread) {
				continue;
			}

			vec2 jitter = vec2(
				value_hash(cell + vec2(7.3, 13.9)),
				value_hash(cell + vec2(53.1, 5.7))
			) * 2.0 - 1.0;
			vec2 centre = (cell + vec2(0.5)) * stamp_lattice_world
				+ jitter * stamp_jitter_world;

			// A dusting draws small specks; deep snow draws large
			// overlapping puffs. Both of those, plus the level climb
			// above, come from the same `lying` -- which is what
			// makes three real art levels read as a continuous ramp. Reads
			// natural_lying, not lying -- see bombed_snow's own doc comment.
			float size = stamp_world_size
				* mix(stamp_min_size_fraction, 1.0, natural_lying)
				* mix(
					1.0 - stamp_size_jitter, 1.0 + stamp_size_jitter,
					value_hash(cell + vec2(97.3, 61.1))
				);

			vec2 local = (wp - centre) / size + vec2(0.5);
			if (local.x < 0.0 || local.x > 1.0 || local.y < 0.0 || local.y > 1.0) {
				continue;
			}

			// The art is cropped to its own tightest content bbox, so the
			// outermost pixel of a stamp can legitimately be near-opaque --
			// right where the hard in-or-out cutoff above would otherwise
			// draw a real step. Fading to 0 continuously as local UV
			// approaches the boundary closes that gap structurally, for
			// every stamp, not just a sampled worst case.
			float edge_dist = min(min(local.x, 1.0 - local.x), min(local.y, 1.0 - local.y));
			float edge_fade = smoothstep(0.0, stamp_edge_fade_uv, edge_dist);
			if (edge_fade <= 0.0) {
				continue;
			}
			local = orient(local, value_hash(cell + vec2(41.7, 71.9)));

			int variant = clamp(
				int(value_hash(cell + vec2(17.9, 37.3)) * float(atlas_columns)),
				0, atlas_columns - 1
			);

			// ONE texture read per stamp, not two: this used to crossfade
			// the two levels level_f falls between (mix of two texture()
			// calls), closing the last of test_coverage_is_continuous_
			// across_a_tile_boundary's own gap. Reverted -- it doubled
			// atlas reads for every stamp, everywhere, all the time snow
			// is on screen, measured live as the difference between 60fps
			// and single digits on integrated graphics. edge_fade above
			// already closes that test's gap to within its pinned 0.07
			// bound (measured 0.058) on its own, for a fraction of the
			// cost -- see level_f's own doc comment in the GDScript
			// mirror for the real numbers. Reads natural_lying, not lying
			// -- see bombed_snow's own doc comment.
			vec4 stamp = texture(stamp_atlas, atlas_uv(level_for_site(natural_lying, cell), variant, local));
			stamp.a *= edge_fade;

			// Accumulate by MAXIMUM alpha, taking the colour of
			// whichever stamp is most opaque here -- "the topmost
			// puff wins". Summing would saturate to flat white mush
			// and lose the illustrated shading; alpha-compositing
			// would need an ordering this loop does not have.
			if (stamp.a > best_alpha) {
				best_alpha = stamp.a;
				best_rgb = stamp.rgb;
			}
		}
	}
	return vec4(best_rgb, best_alpha);
}

void fragment() {
	// Nothing lying anywhere: contribute nothing, and skip the whole 3x3
	// search. Most of the year is this branch.
	if (snow_depth <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		float tread = tread_at(world_pos);
		float lying = lying_at(world_pos, tread);
		if (lying <= 0.0) {
			COLOR = vec4(0.0);
		} else {
			// natural_lying (untreaded) drives every part of a caught
			// site's appearance; lying (treaded) only ever decides whether
			// a site is caught at all -- see bombed_snow's own doc comment
			// for why that single split is what makes tread provably
			// unable to add snow anywhere, for one extra scalar
			// lying_at call, not a second full 3x3 search (see git history
			// for two costlier designs tried and reverted first).
			float natural_lying = tread > 0.0 ? lying_at(world_pos, 0.0) : lying;
			vec4 result = bombed_snow(world_pos, lying, natural_lying);
			// See the GDScript mirror's TREAD_ALPHA_FACTOR for why this
			// flat multiply is what makes "packed down, not cleared" read
			// as a real visual change, on top of site removal alone.
			if (tread > 0.0) {
				result.a *= 1.0 - clamp(tread, 0.0, 1.0) * tread_alpha_factor;
			}
			COLOR = result;
		}
	}
}
"""

## The bombing lattice: how far apart stamp SITES sit, in world units.
##
## One tile (TerrainRenderer.TILE_SIZE). Not because the mechanism cares
## about tiles -- nothing here is tile-aligned and coverage is continuous
## across every tile boundary (see
## test_coverage_is_continuous_across_a_tile_boundary) -- but because it is
## the right physical scale: snow lumps and drifts at a scale of tens of
## centimetres to a metre, and a tile is this game's metre-ish unit.
const STAMP_LATTICE_WORLD := float(TerrainRenderer.TILE_SIZE)

## How wide one stamp is drawn, in world units.
##
## Deliberately LARGER than the lattice, so stamps overlap and full cover has
## no gaps between them (pinned by test_stamps_overlap_their_own_lattice_cell).
## Bounded from above by the 3x3 search's own completeness constraint -- see
## STAMP_JITTER_WORLD.
const STAMP_WORLD_SIZE := 26.0

## Per-stamp size variation, as a fraction. Real snow lumps are not one size,
## and identical sizes on a regular lattice is exactly the periodicity the
## bombing exists to break (see
## test_coverage_has_no_lattice_period_artifact).
const STAMP_SIZE_JITTER := 0.15

## How close, in local UV, a sample must be to a stamp's own footprint edge
## before its alpha starts fading toward 0 (symmetric on all 4 sides;
## 0.05 = the inner 90% of the square draws at full strength).
##
## The illustrated stamps are cropped to their own tightest content bbox, so
## the outermost row/column of a stamp's art can legitimately be near-opaque
## -- right where the hard `local_x/y` in-or-out cutoff would otherwise draw
## a real step from "just outside, contributes 0" to "just inside, contributes
## a near-opaque pixel". Fading alpha to 0 continuously as local UV approaches
## the boundary closes that gap for every stamp, structurally, rather than
## only the specific point a test happens to sample.
##
## Measured against the real atlas (see test_coverage_is_continuous_across_a_
## tile_boundary): 0.05 already captures the improvement -- 0.08, 0.1 and
## 0.15 measure the identical worst-case jump, because past this width the
## remaining discontinuity is level_for_site switching to a different image
## entirely (see _level_f's crossfade below), which a wider edge fade cannot
## touch. Going wider only softens every stamp's silhouette for no gain.
const STAMP_EDGE_FADE_UV := 0.05

## How far a stamp's centre may wander from its own site, in world units.
##
## This and STAMP_WORLD_SIZE are jointly bounded by the fixed 3x3 search: a
## stamp that could reach further than 1.5 lattice cells from its site would
## be found by some fragments and missed by others, clipping stamps along
## invisible lines one lattice apart -- a grid artifact produced by the very
## code meant to hide the grid. At the largest a stamp can be:
##
##   26.0 * 1.15 / 2 + 4.0 = 18.95  <=  1.5 * 16.0 = 24.0
##
## Pinned by test_a_three_by_three_search_reaches_every_stamp_that_can_
## overlap_a_point, which recomputes that inequality from the constants
## rather than restating the numbers -- so raising the stamp size without
## widening the search fails the suite instead of shipping a grid.
const STAMP_JITTER_WORLD := 4.0

## How many lattice cells out the search reaches, per axis. 1 means the 3x3
## neighbourhood; see STAMP_JITTER_WORLD for why this is a real constraint
## and not just a cost knob.
const SEARCH_RADIUS_CELLS := 1

## How big a stamp is at the very start of the ramp, as a fraction of
## STAMP_WORLD_SIZE. A first dusting is small specks, not full-size puffs
## turned translucent.
const STAMP_MIN_SIZE_FRACTION := 0.42

## Over how much of the depth ramp sites pop in.
##
## A site is drawn once `lying` passes its own hashed threshold times this, so
## by `lying` = 0.55 every site has caught and the rest of the ramp is spent
## growing stamps and climbing levels. That two-stage shape is what makes the
## ramp read continuously: bare ground fills in with scattered specks, then
## the specks thicken into cover, rather than everything appearing at once at
## one opacity.
const SITE_ONSET_SPREAD := 0.55

## How far a site's level choice may stray from the ramp's own, in levels.
## Under one whole level, so the dither blurs a boundary rather than scrambling
## the ladder (never straying 2 levels from the ramp). Tapers to zero at both
## ends of the ramp -- see the shader's level_for_site.
##
## Must be >= 1.0 or the dither can never actually reach a neighbouring
## level: at the taper's own peak (lying = 0.5) the offset is
## `(h - 0.5) * LEVEL_DITHER`, whose largest magnitude is `LEVEL_DITHER / 2`
## -- under 0.9's old value that tops out at 0.45, short of the 0.5 a
## round() needs to cross into level 0 or 2 at all, which is why neighbouring
## sites drew the SAME level 100% of the time (test_neighbouring_stamp_sites_
## draw_different_pictures, 0% level changes) even though the mechanism
## looked designed to dither.
##
## Measured at the real hash, over the same 20x20 neighbour grid the test
## uses, at lying = 0.5 (the taper's peak, so the worst case for staying
## put): 0.9 and 1.0 both still measure 0% -- 1.0 only reaches the boundary
## at the hash's unreachable supremum. 1.1 measures 17.0% neighbour-level
## changes (68/400), comfortably past the test's 5% floor, and never strays
## more than 1 level from the ramp.
const LEVEL_DITHER := 1.1

## How much of the depth range a fully trodden point loses, for deciding
## whether a SITE stays present at all (site_has_caught) -- see
## _coverage_for_lying's own doc comment for why tread reads no further
## than that: every other part of a caught site's appearance is deliberately
## tread-invariant now, the fix for test_treading_never_adds_snow's real
## violations. Half, mirroring the old implementation's TREAD_BANDS
## (DEPTH_BANDS / 2.0).
const TREAD_DEPTH := 0.5

## How much a fully trodden point's own alpha fades, ON TOP OF whatever
## sites TREAD_DEPTH above already turned off -- site removal alone was
## measured too weak to read as "packed down" at all (mean coverage barely
## moved, test_treading_packs_snow_down_without_clearing_it's own real
## failure): dense overlapping stamps mean losing a few sites rarely costs
## the winning MAX-alpha contributor at any given point. A flat multiply
## applied to the search's own already tread-safe result, not a second
## search or a geometry change -- see coverage_at's own doc comment for why
## that keeps the "tread can only remove" guarantee trivial: multiplying a
## non-increasing-in-tread quantity by another non-increasing-in-tread
## factor is still non-increasing in tread, for any art, provably.
##
## Measured against both behavioural tests at their own real bounds: 0.55
## -- deep snow (depth 1.0) at full tread lands at a real measured mean
## 0.4307 (untrodden 0.9888, a real 0.5581 drop), comfortably clearing
## test_treading_packs_snow_down_without_clearing_it's floor of 0.3 and its
## "changed by at least 0.05" floor; a dusting (depth 0.1) at full tread
## leaves 100% of 300 sampled points under 0.02
## (test_a_footprint_in_a_dusting_shows_the_ground's own 80% floor), since
## thin cover was already mostly zero before this factor even applies.
const TREAD_ALPHA_FACTOR := 0.55

## The two-octave drift field, carried over UNCHANGED from snow_layer.gd,
## where these were measured and re-measured across three separately reported
## bugs (a per-tile white-noise checkerboard, a flat plateau over a realistic
## on-screen view, and the neighbour-step re-derivation each asset change
## forced). The field itself was never the problem -- only that it was
## evaluated per tile. It is now evaluated per pixel.
##
## ONSET_BROAD_VARIANCE is derived from the total and the fine share, so the
## two can never drift out of sync and silently blow the overall bound the
## neighbour-step test depends on.
const ONSET_VARIANCE := 0.18
const ONSET_FINE_VARIANCE := 0.05
const ONSET_BROAD_VARIANCE := ONSET_VARIANCE - ONSET_FINE_VARIANCE
const ONSET_DRIFT_TILES := 12.0
const ONSET_FINE_DRIFT_TILES := 2.0

## The most two edge-adjacent tiles' onsets may differ.
##
## Kept at the tile-implementation's own pinned value even though this field
## is no longer sampled per tile: the property it guards is unchanged and
## still exactly the right one -- that the drift field is much COARSER than
## the things it decides, so a snow line reads as a meandering edge rather
## than a grid. Re-measured against this shader's own hash (a different hash
## from PixelNoise's, so the number genuinely had to be re-measured rather
## than inherited) -- see test_neighbouring_tiles_have_nearly_the_same_onset,
## which reports the real worst case it finds.
const MAX_NEIGHBOUR_ONSET_STEP := 0.07


## The trig-free lattice hash, mirroring the shader's own exactly -- see the
## GLSL comment for why a sine-based hash is banned here, and why that ban is
## pinned structurally by test_the_lattice_hash_is_trig_free.
##
## `fposmod(v, 1.0)` is GLSL `fract`: both return a non-negative fractional
## part for negative inputs, which matters because world coordinates go
## negative in three of the four quadrants.
static func value_hash(x: float, y: float) -> float:
	var p3x := fposmod(x * 0.1031, 1.0)
	var p3y := fposmod(y * 0.1031, 1.0)
	var p3z := p3x
	var shift := p3x * (p3y + 33.33) + p3y * (p3z + 33.33) + p3z * (p3x + 33.33)
	p3x += shift
	p3y += shift
	p3z += shift
	return fposmod((p3x + p3y) * p3z, 1.0)


## Smooth value noise, mirroring the shader's own: bilinear between integer
## lattice points with a smoothstep fade.
static func value_noise(x: float, y: float) -> float:
	var ix := floorf(x)
	var iy := floorf(y)
	var fx := x - ix
	var fy := y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var top: float = lerpf(value_hash(ix, iy), value_hash(ix + 1.0, iy), fx)
	var bottom: float = lerpf(value_hash(ix, iy + 1.0), value_hash(ix + 1.0, iy + 1.0), fx)
	return lerpf(top, bottom, fy)


## This point's own drift lead/lag on the field's shared coverage.
static func onset_at(world_x: float, world_y: float) -> float:
	var tile := float(TerrainRenderer.TILE_SIZE)
	var tile_x := world_x / tile
	var tile_y := world_y / tile
	var broad := value_noise(
		tile_x / ONSET_DRIFT_TILES + 11.7, tile_y / ONSET_DRIFT_TILES + 3.1
	)
	var fine := value_noise(
		tile_x / ONSET_FINE_DRIFT_TILES + 71.3, tile_y / ONSET_FINE_DRIFT_TILES + 41.9
	)
	return (
		lerpf(-ONSET_BROAD_VARIANCE, ONSET_BROAD_VARIANCE, broad)
		+ lerpf(-ONSET_FINE_VARIANCE, ONSET_FINE_VARIANCE, fine)
	)


## How deep the snow lies at one point -- the shared depth, plus this point's
## drift lead/lag, minus whatever has walked here. Mirrors the shader's
## lying_at, including both end guards (see the GLSL).
static func lying_at(depth: float, world_x: float, world_y: float, tread: float) -> float:
	if depth <= 0.0:
		return 0.0
	var base: float
	if depth >= 1.0:
		base = 1.0
	else:
		base = clampf(depth + onset_at(world_x, world_y), 0.0, 1.0)
	return clampf(base - clampf(tread, 0.0, 1.0) * TREAD_DEPTH, 0.0, 1.0)


## Which of the ten illustrated shape variants a site draws.
static func variant_for_site(cell_x: int, cell_y: int) -> int:
	return clampi(
		int(
			value_hash(float(cell_x) + 17.9, float(cell_y) + 37.3)
			* float(SnowStampAtlas.VARIANTS_PER_LEVEL)
		),
		0, SnowStampAtlas.VARIANTS_PER_LEVEL - 1
	)


## How many coverage levels the art actually provides -- the atlas's row
## count, so adding snow_2/3/4.png lengthens the ladder with no code change.
static func level_count() -> int:
	return SnowStampAtlas.levels().size()


## The continuous ramp position behind level_for_site -- e.g. f=1.35 means
## "35% of the way from level 1 to level 2". Only level_for_site itself
## reads this today (rounded to the single level a SPATIAL dither test
## cares about).
##
## _coverage_for_lying/bombed_snow used to crossfade the two neighbouring
## levels this falls between, so a site's OWN transition faded rather than
## popped as `lying` climbed. Reverted: it doubled the atlas texture reads
## for every stamp evaluated, everywhere, all the time snow is on screen --
## measured live, this cost enough on integrated graphics to be the
## difference between 60fps and single digits. The edge fade this shares a
## site with already closes test_coverage_is_continuous_across_a_tile_
## boundary's own gap to within its pinned 0.07 bound (measured 0.058) on
## its own, at a fraction of the cost -- the crossfade's own marginal
## improvement on top of that (0.058 -> 0.055) was not worth doubling a
## per-pixel, per-site cost for.
static func _level_f(lying: float, cell_x: int, cell_y: int) -> float:
	var levels := level_count()
	var h := value_hash(float(cell_x) + 29.3, float(cell_y) + 83.7)
	var taper := 4.0 * lying * (1.0 - lying)
	return clampf(
		lying * float(levels - 1) + (h - 0.5) * LEVEL_DITHER * taper, 0.0, float(levels - 1)
	)


## Which coverage level a site draws at a given lying depth, with the
## end-tapered per-site dither -- see the shader's level_for_site. Rounds
## _level_f to the single nearest level; test_neighbouring_stamp_sites_draw_
## different_pictures and test_a_three_by_three_search_reaches... want one
## definite level per site, not the blend _coverage_for_lying itself uses.
static func level_for_site(lying: float, cell_x: int, cell_y: int) -> int:
	return clampi(int(round(_level_f(lying, cell_x, cell_y))), 0, level_count() - 1)


## Whether a site has caught snow yet at this depth -- see the shader's own
## gate, and SITE_ONSET_SPREAD.
static func site_has_caught(lying: float, cell_x: int, cell_y: int) -> bool:
	return lying >= value_hash(float(cell_x) + 3.7, float(cell_y) + 19.1) * SITE_ONSET_SPREAD


## How opaque the snow is at one world point: the full 3x3 bombing accumulate,
## mirroring the shader's fragment() body.
##
## _stamp_alpha samples the atlas bilinearly, matching the GPU's own
## filter_linear exactly -- deliberately, not incidentally. Continuity across
## a tile boundary (test_coverage_is_continuous_across_a_tile_boundary) DOES
## turn on sub-pixel interpolation: nearest-neighbour sampling is a step
## function by construction, so a query a hair either side of a source
## pixel's own boundary can cross a hard texel edge in the illustrated art
## and read as a real discontinuity that was never in the design, only in
## the mirror's own sampling. The other properties this asserts --
## monotonicity in depth, the absence of a lattice period -- don't care
## either way, so matching the GPU exactly costs them nothing.
## Used to clamp to a SECOND full bombing search at the untreaded lying,
## whenever tread > 0, to structurally guarantee tread can never add snow
## (see test_treading_never_adds_snow) -- correct, but a real fragment
## shader cost, doubled, across every fragment with ANY nonzero tread.
## Footprints decay slowly (SnowTrail.SECONDS_TO_FILL), so that is not a
## small area: it is most of wherever the player has recently walked,
## continuously, for as long as the trail lasts. Measured live: this was
## the dominant cause of a 60fps -> single-digit collapse the instant the
## player actually walked on lying snow, far more than the level-crossfade
## _level_f's own doc comment describes (that one only doubled ONE site's
## texture reads; this one doubled the ENTIRE 3x3 search, everywhere tread
## was nonzero). Reverted to a single search -- see
## test_treading_never_adds_snow's own doc comment for the real, honest,
## re-measured worst-case overshoot this now accepts instead.
func coverage_at(depth: float, world_x: float, world_y: float, tread: float = 0.0) -> float:
	if depth <= 0.0:
		return 0.0
	var lying := lying_at(depth, world_x, world_y, tread)
	if lying <= 0.0:
		return 0.0
	# The UNTREADED lying, used for every part of a site's own appearance
	# once it's present (see _coverage_for_lying's own doc comment) -- only
	# computed when tread is actually nonzero, one extra lying_at call (no
	# texture sampling), not a second full bombing search.
	var natural_lying := lying_at(depth, world_x, world_y, 0.0) if tread > 0.0 else lying
	var raw := _coverage_for_lying(lying, natural_lying, world_x, world_y)
	if tread <= 0.0:
		return raw
	# See TREAD_ALPHA_FACTOR's own doc comment for why this preserves
	# "tread can only remove" exactly, and why it's needed at all.
	return raw * (1.0 - clampf(tread, 0.0, 1.0) * TREAD_ALPHA_FACTOR)


## `lying` (the TREADED value) decides only WHETHER a site is present at
## all, via site_has_caught -- reducing it can only make that inequality
## harder to satisfy, so tread can only ever turn sites OFF, never on.
## Every other part of a caught site's appearance -- size, level, position,
## orientation, variant -- reads `natural_lying` (the UNTREADED value)
## instead, so a site that stays caught renders BYTE-IDENTICAL regardless
## of tread. That makes coverage_at(..., tread) provably unable to exceed
## coverage_at(..., 0) for ANY world point: it evaluates the exact same set
## of possible contributions, only ever a subset of them still active --
## not a property that happens to hold for this art, true by construction
## for any art.
##
## Went through two more expensive designs first, both reverted after real
## measurement: a second full bombing search at the untreaded lying (see
## git history) doubled the ENTIRE per-fragment cost everywhere tread was
## nonzero -- measured as the dominant cause of a real 60fps -> single-digit
## collapse; then keying ONLY the level off natural_lying while size still
## read the treaded value (see git history) closed the catastrophic
## LEVEL-switch case but not a second, independent one -- shrinking a
## stamp's SIZE can push the very same sampled UV right up against a hard
## ink-outline edge inside the art, which the edge fade does not reach in
## time (measured: up to a 0.89 alpha jump from that alone, same order as
## the level-switch case it was meant to replace). Keying ALL of a site's
## appearance off natural_lying, not just its level, is what actually
## closes both at once, for the same one extra scalar lying_at call.
func _coverage_for_lying(lying: float, natural_lying: float, world_x: float, world_y: float) -> float:
	var base_cell_x := floori(world_x / STAMP_LATTICE_WORLD)
	var base_cell_y := floori(world_y / STAMP_LATTICE_WORLD)
	var best := 0.0
	for offset_y in range(-SEARCH_RADIUS_CELLS, SEARCH_RADIUS_CELLS + 1):
		for offset_x in range(-SEARCH_RADIUS_CELLS, SEARCH_RADIUS_CELLS + 1):
			var cell_x := base_cell_x + offset_x
			var cell_y := base_cell_y + offset_y
			if not site_has_caught(lying, cell_x, cell_y):
				continue
			var jitter_x := value_hash(float(cell_x) + 7.3, float(cell_y) + 13.9) * 2.0 - 1.0
			var jitter_y := value_hash(float(cell_x) + 53.1, float(cell_y) + 5.7) * 2.0 - 1.0
			var centre_x := (float(cell_x) + 0.5) * STAMP_LATTICE_WORLD \
				+ jitter_x * STAMP_JITTER_WORLD
			var centre_y := (float(cell_y) + 0.5) * STAMP_LATTICE_WORLD \
				+ jitter_y * STAMP_JITTER_WORLD
			var size := STAMP_WORLD_SIZE \
				* lerpf(STAMP_MIN_SIZE_FRACTION, 1.0, natural_lying) \
				* lerpf(
					1.0 - STAMP_SIZE_JITTER, 1.0 + STAMP_SIZE_JITTER,
					value_hash(float(cell_x) + 97.3, float(cell_y) + 61.1)
				)
			var local_x := (world_x - centre_x) / size + 0.5
			var local_y := (world_y - centre_y) / size + 0.5
			if local_x < 0.0 or local_x > 1.0 or local_y < 0.0 or local_y > 1.0:
				continue
			var edge_dist := minf(minf(local_x, 1.0 - local_x), minf(local_y, 1.0 - local_y))
			var edge_fade := smoothstep(0.0, STAMP_EDGE_FADE_UV, edge_dist)
			if edge_fade <= 0.0:
				continue
			var oriented := _orient(
				local_x, local_y, value_hash(float(cell_x) + 41.7, float(cell_y) + 71.9)
			)
			var variant := variant_for_site(cell_x, cell_y)
			best = maxf(best, _stamp_alpha(
				level_for_site(natural_lying, cell_x, cell_y), variant, oriented.x, oriented.y
			) * edge_fade)
	return best


## The 8-fold dihedral group on a stamp's local UV, mirroring the shader's
## own orient().
static func _orient(u: float, v: float, h: float) -> Vector2:
	var o := int(h * 8.0)
	var x := u
	var y := v
	if o & 1 == 1:
		x = 1.0 - x
	if o & 2 == 2:
		y = 1.0 - y
	if o & 4 == 4:
		return Vector2(y, x)
	return Vector2(x, y)


## One stamp's alpha at a local UV, read out of the same packed atlas image
## the GPU samples -- so the mirror is reading the real art, not a model of it.
var _atlas := SnowStampAtlas.new()
static var _atlas_image_cache: Image = null


func _stamp_alpha(level: int, variant: int, u: float, v: float) -> float:
	if _atlas_image_cache == null:
		_atlas_image_cache = _atlas.build_atlas_image()
	var stamp := float(SnowStampAtlas.STAMP_SIZE)
	var cell_x := variant * SnowStampAtlas.CELL_SIZE + SnowStampAtlas.STAMP_PADDING
	var cell_y := level * SnowStampAtlas.CELL_SIZE + SnowStampAtlas.STAMP_PADDING
	# Bilinear, mirroring GL_LINEAR exactly: texel-space coordinate is
	# uv * size - 0.5, blended across the 4 nearest texels. The 2px
	# transparent gutter (STAMP_PADDING) is why this never needs to clamp
	# INTO a neighbouring stamp's real content -- the 1-texel reach past a
	# stamp's own [0, stamp) range always lands in the gutter instead (see
	# SnowStampAtlas's own padding comment), so clamping here is only ever
	# against the whole atlas image's own outer edge, matching the shader's
	# repeat_disable.
	var px := u * stamp - 0.5
	var py := v * stamp - 0.5
	var x0 := floori(px)
	var y0 := floori(py)
	var fx := px - float(x0)
	var fy := py - float(y0)
	var w := _atlas_image_cache.get_width()
	var h := _atlas_image_cache.get_height()
	var a00 := _atlas_image_cache.get_pixel(clampi(cell_x + x0, 0, w - 1), clampi(cell_y + y0, 0, h - 1)).a
	var a10 := _atlas_image_cache.get_pixel(clampi(cell_x + x0 + 1, 0, w - 1), clampi(cell_y + y0, 0, h - 1)).a
	var a01 := _atlas_image_cache.get_pixel(clampi(cell_x + x0, 0, w - 1), clampi(cell_y + y0 + 1, 0, h - 1)).a
	var a11 := _atlas_image_cache.get_pixel(clampi(cell_x + x0 + 1, 0, w - 1), clampi(cell_y + y0 + 1, 0, h - 1)).a
	return lerpf(lerpf(a00, a10, fx), lerpf(a01, a11, fx), fy)


## A fresh material carrying the real atlas and every tuned constant.
##
## Every uniform the mirror pins is pushed from the GDScript constant of the
## same name rather than left to the GLSL default, so the two can only ever
## disagree by a name typo -- which
## test_every_mirrored_constant_reaches_the_shader catches.
func make_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	var texture := _atlas.atlas_texture()
	material.set_shader_parameter("stamp_atlas", texture)
	material.set_shader_parameter("atlas_columns", SnowStampAtlas.VARIANTS_PER_LEVEL)
	material.set_shader_parameter("atlas_rows", level_count())
	material.set_shader_parameter(
		"atlas_size_px", Vector2(texture.get_width(), texture.get_height())
	)
	material.set_shader_parameter("atlas_cell_px", float(SnowStampAtlas.CELL_SIZE))
	material.set_shader_parameter("atlas_stamp_px", float(SnowStampAtlas.STAMP_SIZE))
	material.set_shader_parameter("atlas_padding_px", float(SnowStampAtlas.STAMP_PADDING))
	material.set_shader_parameter("stamp_lattice_world", STAMP_LATTICE_WORLD)
	material.set_shader_parameter("stamp_world_size", STAMP_WORLD_SIZE)
	material.set_shader_parameter("stamp_jitter_world", STAMP_JITTER_WORLD)
	material.set_shader_parameter("stamp_size_jitter", STAMP_SIZE_JITTER)
	material.set_shader_parameter("stamp_min_size_fraction", STAMP_MIN_SIZE_FRACTION)
	material.set_shader_parameter("site_onset_spread", SITE_ONSET_SPREAD)
	material.set_shader_parameter("level_dither", LEVEL_DITHER)
	material.set_shader_parameter("stamp_edge_fade_uv", STAMP_EDGE_FADE_UV)
	material.set_shader_parameter("tread_depth", TREAD_DEPTH)
	material.set_shader_parameter("tread_alpha_factor", TREAD_ALPHA_FACTOR)
	material.set_shader_parameter("onset_broad_variance", ONSET_BROAD_VARIANCE)
	material.set_shader_parameter("onset_fine_variance", ONSET_FINE_VARIANCE)
	material.set_shader_parameter("onset_drift_tiles", ONSET_DRIFT_TILES)
	material.set_shader_parameter("onset_fine_drift_tiles", ONSET_FINE_DRIFT_TILES)
	material.set_shader_parameter("world_units_per_tile", float(TerrainRenderer.TILE_SIZE))
	material.set_shader_parameter("snow_depth", 0.0)
	material.set_shader_parameter("trail_mask", _empty_trail_mask())
	material.set_shader_parameter("trail_origin", Vector2.ZERO)
	material.set_shader_parameter("trail_world_size", 1024.0)
	return material


## The one material the snow layer actually renders with. Shared, so pushing
## depth once re-draws every painted cell at once rather than needing any
## repaint -- the same shape water_shader.gd/hillshade_shader.gd already use.
var _material: ShaderMaterial = null


func shared_material() -> ShaderMaterial:
	if _material == null:
		_material = make_material()
	return _material


## How much snow is lying, 0 bare to 1 covered (see Snowfall). THE per-frame
## call: one float, no repaint.
func set_snow_depth(depth: float) -> void:
	shared_material().set_shader_parameter("snow_depth", clampf(depth, 0.0, 1.0))


## Registers the world-space footprint window (see SnowTrail). `origin` is the
## world position of the mask's top-left corner and `world_size` how much
## world it spans, both of which the shader needs to turn a world position
## into a mask UV.
func set_trail_mask(mask: Texture2D, origin: Vector2, world_size: float) -> void:
	var material := shared_material()
	material.set_shader_parameter(
		"trail_mask", mask if mask != null else _empty_trail_mask()
	)
	material.set_shader_parameter("trail_origin", origin)
	material.set_shader_parameter("trail_world_size", maxf(world_size, 1.0))


## A 1x1 black texture, so an unregistered trail mask reads as "nothing has
## been walked on" rather than sampling an unbound sampler.
static var _empty_mask: ImageTexture = null


static func _empty_trail_mask() -> ImageTexture:
	if _empty_mask == null:
		var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.set_pixel(0, 0, Color(0.0, 0.0, 0.0, 1.0))
		_empty_mask = ImageTexture.create_from_image(image)
	return _empty_mask


# -- hosting on a TileMapLayer ------------------------------------------------

## The single tile build_presence_tile_set paints -- there is only ever one,
## since presence is a binary "may snow render here" bit, not art.
const PRESENCE_ATLAS_COORD := Vector2i(0, 0)

static var _presence_tile_set: TileSet = null


## A one-tile TileSet whose only job is to give a TileMapLayer real painted
## cells to gate this shader over -- see fragment(): it never reads TEXTURE,
## it writes COLOR unconditionally from stamp_atlas/trail_mask, so the tile's
## own pixels are never seen. What DOES matter is which cells are painted at
## all: an erased cell draws no quad and never runs fragment(), which is how
## ocean staying erased keeps snow off water without the shader needing to
## know what a biome is.
##
## Cached in a static var, the same "the art never changes" convention this
## file's own _atlas_image_cache and SnowStampAtlas's caches use.
static func build_presence_tile_set() -> TileSet:
	if _presence_tile_set != null:
		return _presence_tile_set
	var art := TerrainRenderer.ART_TILE_SIZE
	var image := Image.create(art, art, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 1.0))
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(art, art)
	source.create_tile(PRESENCE_ATLAS_COORD)
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(art, art)
	tile_set.add_source(source, 0)
	_presence_tile_set = tile_set
	return _presence_tile_set
