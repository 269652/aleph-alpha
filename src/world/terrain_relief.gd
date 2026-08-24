extends RefCounted

## Real slope and aspect derived from this project's existing real elevation
## data (see docs/concept/terrain_relief.md) -- the one shared field that
## doc's passability/hillshading/mountain-ore mechanisms all read, and the
## same field docs/concept/climate_dynamics.md's orographic lift needs for
## rain-shadow precipitation. No new data source: everything here is either
## real geodesy (meters per degree) or a real central-difference gradient
## over EarthElevationSource's existing `elevation_at`.
##
## Pure and engine-free like the rest of this project's world modules --
## `slope_at`/`aspect_at` take any object with an `elevation_at(lat, lon)`
## method (real EarthElevationSource, or a fake with no PNG to load in a
## test -- see test_terrain_relief.gd's _FakeElevationSource), so this
## never touches FileAccess/Image itself.

## Real geodetic constant: one degree of latitude is very close to this
## everywhere on Earth (it varies slightly with the planet's actual
## ellipsoid shape, ignored here as an honest simplification -- the same
## "close enough, real, not painted" standard this project's elevation data
## itself already meets).
const METERS_PER_DEGREE_LATITUDE := 111320.0

## EarthElevationSource's own documented encoding: 0.0 = -8000m (deepest
## trench), 1.0 = +6400m (highest peak), linear. Kept here rather than
## re-deriving it at each call site, and pinned by
## test_elevation_meters_at_zero_is_the_deepest_trench/_one_is_the_highest_peak.
const ELEVATION_MIN_M := -8000.0
const ELEVATION_MAX_M := 6400.0

## How far apart (in degrees) the four neighbor samples that build a
## gradient are taken -- roughly 1.1km at the equator, the same order of
## magnitude as this project's own real-Earth tile scale (~1km/tile, see
## docs/progress.md's Phase 0 entry). Small enough to be a genuinely LOCAL
## slope reading, large enough to be a real, distinct sample rather than
## noise in EarthElevationSource's own bilinear interpolation.
const SAMPLE_OFFSET_DEG := 0.01


## Converts EarthElevationSource's normalized [0,1] encoding to real meters.
## Linear, so the doc's own reference points (0.0 -> -8000m, 1.0 -> +6400m,
## sea level near 0.5556) all fall out of one formula rather than three.
func elevation_meters(normalized: float) -> float:
	return ELEVATION_MIN_M + normalized * (ELEVATION_MAX_M - ELEVATION_MIN_M)


## Real meters per degree of LONGITUDE at a given latitude -- shrinks toward
## the poles (a degree of longitude is a shrinking real distance as
## meridians converge) while meters per degree of LATITUDE stays constant
## (see METERS_PER_DEGREE_LATITUDE). Standard geodetic approximation:
## meters_per_degree_latitude * cos(latitude).
func meters_per_degree_longitude(latitude_deg: float) -> float:
	return METERS_PER_DEGREE_LATITUDE * cos(deg_to_rad(latitude_deg))


## How steep a gradient is, in real degrees, from its two axis components
## (elevation change per meter, east-west and north-south) -- the magnitude
## of the gradient vector, mapped through atan the same way any real slope
## angle is derived from rise/run. Direction-agnostic (a slope down is
## exactly as steep as the same slope up) and combines both axes by
## Pythagorean magnitude, not by summing them, which is what makes a
## diagonal slope correctly steeper than either axis alone without being
## double-counted.
func slope_degrees_from_gradient(dzdx: float, dzdy: float) -> float:
	var magnitude := sqrt(dzdx * dzdx + dzdy * dzdy)
	return rad_to_deg(atan(magnitude))


## Real GIS convention: aspect is the compass bearing (0=north, 90=east,
## 180=south, 270=west, clockwise) of the direction the slope FACES -- the
## direction water would actually flow, i.e. the negative of the uphill
## gradient. `dzdx`/`dzdy` are d(elevation)/d(east) and d(elevation)/d(north)
## respectively, matching _gradient_at's own convention.
##
## Undefined on perfectly flat ground (there is no "downhill" with no
## slope) -- returns -1.0 rather than an arbitrary angle, so a caller can
## tell "flat" apart from "faces north" instead of the two being silently
## indistinguishable.
func aspect_degrees_from_gradient(dzdx: float, dzdy: float) -> float:
	if dzdx == 0.0 and dzdy == 0.0:
		return -1.0
	var downhill_east := -dzdx
	var downhill_north := -dzdy
	# atan2(y, x) with the EAST component passed as y and the NORTH
	# component as x is the standard trick that turns atan2's usual
	# counterclockwise-from-east angle into a clockwise-from-north compass
	# bearing directly, with no separate remapping step afterward.
	var bearing := rad_to_deg(atan2(downhill_east, downhill_north))
	return fposmod(bearing, 360.0)


## Real slope in degrees at a latitude/longitude, sampled from `source`
## (anything with an `elevation_at(lat, lon)` method -- real
## EarthElevationSource, or a test fake). See docs/concept/terrain_relief.md
## for what this feeds: passability, hillshading, and mountain ore exposure
## all read this one field.
func slope_at(source, latitude_deg: float, longitude_deg: float) -> float:
	var gradient := _gradient_at(source, latitude_deg, longitude_deg)
	return slope_degrees_from_gradient(gradient.x, gradient.y)


## Real aspect (compass bearing the slope faces) at a latitude/longitude,
## same sampling as slope_at -- see that function and
## aspect_degrees_from_gradient's own doc comments.
func aspect_at(source, latitude_deg: float, longitude_deg: float) -> float:
	var gradient := _gradient_at(source, latitude_deg, longitude_deg)
	return aspect_degrees_from_gradient(gradient.x, gradient.y)


## The real elevation gradient (d(elevation)/d(east), d(elevation)/d(north),
## both in meters-per-meter) at a point, from four real-meter-converted
## neighbor samples -- a standard central-difference derivative: the
## difference between the two samples either side of the point, divided by
## the real distance between them (not from the point to one neighbor,
## which would be a one-sided and noisier estimate).
##
## Longitude's real distance depends on latitude (see
## meters_per_degree_longitude) and can reach zero at the poles; guarded so
## a caller sampling near a pole gets a flat east-west reading rather than a
## divide-by-zero.
func _gradient_at(source, latitude_deg: float, longitude_deg: float) -> Vector2:
	var north_m := elevation_meters(source.elevation_at(latitude_deg + SAMPLE_OFFSET_DEG, longitude_deg))
	var south_m := elevation_meters(source.elevation_at(latitude_deg - SAMPLE_OFFSET_DEG, longitude_deg))
	var east_m := elevation_meters(source.elevation_at(latitude_deg, longitude_deg + SAMPLE_OFFSET_DEG))
	var west_m := elevation_meters(source.elevation_at(latitude_deg, longitude_deg - SAMPLE_OFFSET_DEG))

	var run_ns := SAMPLE_OFFSET_DEG * 2.0 * METERS_PER_DEGREE_LATITUDE
	var run_ew := SAMPLE_OFFSET_DEG * 2.0 * meters_per_degree_longitude(latitude_deg)

	var dzdy := (north_m - south_m) / run_ns
	var dzdx := (east_m - west_m) / run_ew if run_ew > 0.0 else 0.0
	return Vector2(dzdx, dzdy)
