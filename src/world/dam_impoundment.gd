extends RefCounted

## A player-built stone check dam's real hydraulics: how high the water
## stands behind it, how far back that pooling reaches, how much water it
## holds, and when the stone gives way. See docs/concept/rivers.md's "Dams"
## section.
##
## Pure functions over real quantities -- no world knowledge, no state. The
## dam's own existence lives in `chunk.modifications` like every other
## placed piece; everything hydraulic about it is DERIVED from that plus the
## river's real discharge and the real terrain, so nothing here has to be
## stored, persisted, caught up after an unload, or synchronised across
## chunk seams. That is what makes a dam affordable on this world.

const OpenChannelFlow = preload("res://src/world/open_channel_flow.gd")

## How high one placed dam stands above the riverbed, in real metres.
##
## Real hand-stacked loose-stone check dams -- the erosion-control kind
## built without engineering -- are waist-to-chest high; taller than that
## and dry-stacked rubble stops being viable without cement or gabions.
## 1.2 m is a realistic hand-built height and deliberately NOT a
## tile-derived number: like real channel width (see RiverDischarge), a
## dam's real dimensions have nothing to do with this world's ~1 km tiles,
## which are the map representation, not the structure.
const CREST_HEIGHT_M := 1.2

## Bulk density of placed loose stone (kg/m3). Real riprap/gabion figures
## run ~1.5-1.7 t/m3 placed (FHWA HEC-15 gives 1.5 ton/yd3; NRCS 1.2-1.7),
## well below solid rock's ~2.65 because 20-40% of a rubble stack is voids.
const STONE_BULK_DENSITY_KG_M3 := 1600.0

## Coefficient of friction for stone sliding on a streambed. 0.6 is the
## standard masonry/rock-on-rock design value (tan of a ~31 degree friction
## angle).
const STONE_FRICTION_COEFFICIENT := 0.6

## How thick the stacked stone is, front to back, in real metres. A
## hand-built check dam is roughly as thick at the base as it is tall --
## which is what gives it enough weight to stay put at all.
const DAM_THICKNESS_M := 1.2

## How far upstream the pool is REPRESENTED as reaching, in tiles.
##
## This is a deliberate real-scale compression, and the honest reason is
## worth stating plainly. A real 1.2 m check dam ponds water some tens of
## metres upstream. At this world's ~1 km/tile that is a few HUNDREDTHS of
## one tile -- and on the Dreisam's real 4% gradient at the spawn point, one
## tile upstream is already ~40 m higher than the dam, so a physically
## literal pool would be invisible: it could never reach even the next cell.
##
## Compressing it is the same trade rivers.md pillar 4 already makes for
## channel width (a real ~15 m Dreisam is drawn 4 km wide, because a
## survey-accurate river would be sub-pixel). The DEPTH of the pool stays
## real -- it comes from the weir equation and the river's real discharge --
## and only its upstream EXTENT is represented rather than simulated.
##
## Small on purpose: a check dam makes a pond, not a reservoir.
const MAX_BACKWATER_TILES := 4


## How much of the dam's full pool depth survives `tiles_upstream` tiles
## back, tapering linearly to nothing at MAX_BACKWATER_TILES.
##
## A real impoundment is deepest at the dam face and thins to nothing where
## the natural water surface meets the pool's -- the backwater curve. This
## is that shape at the compressed scale above: linear rather than the real
## curve's asymptote, which is the honest simplification for something
## spanning four tiles.
static func backwater_falloff(tiles_upstream: float) -> float:
	if tiles_upstream < 0.0 or tiles_upstream > float(MAX_BACKWATER_TILES):
		return 0.0
	return 1.0 - tiles_upstream / float(MAX_BACKWATER_TILES)


## The water-surface elevation (m) a dam holds behind it at steady state:
## the bed it stands on, plus its own crest height, plus the head needed for
## the river's own discharge to spill over that crest.
##
## Steady state is closed-form (see OpenChannelFlow.equilibrium_weir_head_m)
## rather than a filling simulation -- the pool rises until outflow equals
## inflow, and that balance point is solvable directly. A transient fill
## would need per-dam stored volume, unloaded-chunk catch-up, and cross-seam
## bookkeeping for a few seconds of one-off animation; deliberately not
## attempted (see rivers.md).
static func pool_surface_elevation_m(
	bed_elevation_m: float, discharge_m3_s: float, crest_width_m: float
) -> float:
	var head := OpenChannelFlow.equilibrium_weir_head_m(discharge_m3_s, crest_width_m)
	return bed_elevation_m + CREST_HEIGHT_M + head


## How deep the water stands over a bed at `bed_elevation_m` when the pool
## surface is at `pool_surface_elevation_m`. Zero where the bed is at or
## above the surface -- that is where the impoundment ends.
static func pooled_depth_m(bed_elevation_m: float, pool_surface_elevation_m: float) -> float:
	return maxf(pool_surface_elevation_m - bed_elevation_m, 0.0)


## The real depth at a cell inside a dam's backwater: the deeper of what the
## river naturally ran at and what the pool now holds.
##
## A dam raises water; it never lowers it. Taking the max rather than
## replacing the natural depth is what guarantees that, including at the
## upstream fringe where the pool is shallower than the channel already was.
static func impounded_depth_m(
	natural_depth_m: float, bed_elevation_m: float, pool_surface_elevation_m: float
) -> float:
	return maxf(natural_depth_m, pooled_depth_m(bed_elevation_m, pool_surface_elevation_m))


## The pooled depth at which dry-stacked stone slides out of the way, in
## real metres of water standing against it.
##
## Derived, not chosen. A dam slides when the water's horizontal push beats
## the friction holding the stone down:
##     push       = 0.5 * rho_water * g * h^2 * b      (hydrostatic force)
##     resistance = mu * rho_stone * g * H * t * b     (friction * weight)
## The dam's own width b appears on both sides and cancels, so the limit is
## a pure depth:
##     h_max = sqrt( 2 * mu * rho_stone * H * t / rho_water )
##
## Because the push goes as depth SQUARED while the resistance is fixed,
## this is a genuine threshold rather than a gradual weakening -- which is
## why a dam that has held for ages fails suddenly when the water rises a
## little further.
static func failure_depth_m() -> float:
	var numerator := (
		2.0 * STONE_FRICTION_COEFFICIENT * STONE_BULK_DENSITY_KG_M3
		* CREST_HEIGHT_M * DAM_THICKNESS_M
	)
	return sqrt(numerator / OpenChannelFlow.WATER_DENSITY_KG_M3)


## Whether water this deep against the dam face bursts it (see
## failure_depth_m for the derivation).
static func exceeds_structural_limit(depth_against_face_m: float) -> bool:
	return depth_against_face_m > failure_depth_m()


## Real water volume (m3) held over an area at a given mean depth -- the
## "volume" half of the reservoir, for a caller that has summed the flooded
## area itself.
static func impounded_volume_m3(mean_depth_m: float, flooded_area_m2: float) -> float:
	if mean_depth_m <= 0.0 or flooded_area_m2 <= 0.0:
		return 0.0
	return mean_depth_m * flooded_area_m2
