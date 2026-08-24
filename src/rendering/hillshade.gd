extends RefCounted

## Real Lambertian hillshading (see docs/concept/terrain_relief.md's
## "Hillshading" section) -- the standard real GIS shaded-relief formula,
## illuminating terrain by the dot product of its surface normal against a
## real light direction.
##
## Pure formula, engine-free, and deliberately a seam between two domains
## that don't need to know about each other: callers supply real slope/
## aspect (see terrain_relief.gd) and real sun elevation/azimuth (see
## solar_position.gd) rather than this module computing either itself.
## Static, no state, matching TerrainPassability's own namespace-style
## calling convention.


## Illumination in [0, 1] for a slope/aspect lit from a given real sun
## elevation/azimuth. 0 when the sun is at or below the horizon (night),
## regardless of slope -- a mountain doesn't catch light the sun isn't
## casting.
##
## Standard real hillshade formula:
##   illumination = cos(zenith)*cos(slope)
##                + sin(zenith)*sin(slope)*cos(sun_azimuth - aspect)
##   zenith = 90 - sun_elevation
##
## On perfectly flat ground (slope 0), the second term vanishes regardless
## of `aspect_deg`'s value -- this is what makes it safe to pass
## terrain_relief.gd's -1 "undefined aspect" sentinel straight through with
## no special-casing here: it gets multiplied by sin(0) = 0 either way.
## Clamped to [0, 1]: a slope tilted far enough away from the sun produces a
## raw value below zero (self-shadowed), reported as fully dark rather than
## a physically meaningless negative brightness.
static func illumination(
	slope_deg: float, aspect_deg: float, sun_elevation_deg: float, sun_azimuth_deg: float
) -> float:
	if sun_elevation_deg <= 0.0:
		return 0.0

	var zenith_rad := deg_to_rad(90.0 - sun_elevation_deg)
	var slope_rad := deg_to_rad(slope_deg)
	var relative_azimuth_rad := deg_to_rad(sun_azimuth_deg - aspect_deg)

	var raw := (
		cos(zenith_rad) * cos(slope_rad)
		+ sin(zenith_rad) * sin(slope_rad) * cos(relative_azimuth_rad)
	)
	return clampf(raw, 0.0, 1.0)
