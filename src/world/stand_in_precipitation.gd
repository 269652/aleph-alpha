extends RefCounted

## Placeholder precipitation over latitude alone, for hydrology.md's phase 1
## (rivers and lakes visible before the climate grid exists). Deleted in
## phase 3, when climate_dynamics.md's real precipitation field replaces it.
##
## Shape: the three-cell circulation flattened to one curve. Air rises at
## the equator (wet), sinks near 30 degrees (the subtropical highs -- the
## real reason the world's deserts cluster there), rises again near 60
## (wet mid-latitudes), sinks at the poles (dry). Symmetric across the
## equator; normalized to [0, 1].

## Where the subtropical minimum sits, in degrees. Real deserts cluster
## at 25-30 on every continent; pinned by test_the_subtropical_minimum_
## sits_in_the_desert_belt.
const SUBTROPICAL_DRY_LATITUDE := 27.0
## Where the mid-latitude maximum sits, in degrees (the polar front).
const MID_LATITUDE_WET_LATITUDE := 55.0

## Peak values of each band, so the curve reads as real relative wetness:
## the equatorial belt is the wettest place on the planet, the mid-latitude
## belt clearly wet, the subtropics and poles both dry (the poles are
## deserts by precipitation, only cold ones).
const EQUATOR_RAIN := 1.0
const SUBTROPICAL_RAIN := 0.08
const MID_LATITUDE_RAIN := 0.6
const POLAR_RAIN := 0.1


## Precipitation proxy in [0, 1] at a latitude in degrees (either sign).
## Piecewise cosine between the four anchors above: smooth, no overshoot.
static func at_latitude(latitude_deg: float) -> float:
	var lat := absf(latitude_deg)
	if lat <= SUBTROPICAL_DRY_LATITUDE:
		return _blend(EQUATOR_RAIN, SUBTROPICAL_RAIN, lat / SUBTROPICAL_DRY_LATITUDE)
	if lat <= MID_LATITUDE_WET_LATITUDE:
		var t := (lat - SUBTROPICAL_DRY_LATITUDE) / (MID_LATITUDE_WET_LATITUDE - SUBTROPICAL_DRY_LATITUDE)
		return _blend(SUBTROPICAL_RAIN, MID_LATITUDE_RAIN, t)
	var t := (lat - MID_LATITUDE_WET_LATITUDE) / (90.0 - MID_LATITUDE_WET_LATITUDE)
	return _blend(MID_LATITUDE_RAIN, POLAR_RAIN, minf(t, 1.0))


## Cosine ease from `a` (t=0) to `b` (t=1): flat at both ends, so the
## anchors are genuine extrema and the curve is continuous in slope.
static func _blend(a: float, b: float, t: float) -> float:
	var eased := (1.0 - cos(clampf(t, 0.0, 1.0) * PI)) / 2.0
	return lerpf(a, b, eased)
