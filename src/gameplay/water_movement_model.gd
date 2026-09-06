extends RefCounted

## Depth, in real meters (see BiomeClassifier.depth_meters_at), up to which a
## character can still stand and wade rather than needing to swim. Meters, not
## a normalized fraction: a fraction of the full ocean-depth range would make
## realistic shallow coastal water (a few meters) round down to a barely
## perceptible sliver of "wading slowdown" -- exactly the bug this once was.
const WADE_DEPTH_METERS := 1.5
## Fraction of walking speed lost at the deepest wadeable depth.
const WADE_SPEED_LOSS := 0.5

## The gameplay-calibrated scale Player._resolve_water_state converts real
## OCEAN elevation into metres of depth with (BiomeClassifier.depth_meters_
## at's own `max_depth_meters` argument) -- DELIBERATELY separate from
## EarthChunkGenerator.EARTH_OCEAN_DEPTH_RANGE_METERS (8000.0), which is
## correct as "the real bathymetric depth this world's bundled elevation
## data encodes at its lowest point" but is the wrong number to convert
## with for gameplay/visual purposes, the same "recalibrate to what
## gameplay actually needs, not the real physical range" reasoning
## WADE_DEPTH_METERS's own doc comment above already applies, and
## RiverDepth's MAX_CURATED_RIVER_DEPTH_METERS/PROCEDURAL_RIVER_DEPTH_
## METERS (2.5m/1.0m) already apply to river depth.
##
## Reported directly: "the players submerged tint should gradually fill
## from the feet upwards as he walks down the shore into deeper water
## based on the elevation and slope" -- already true for river/lake, but
## not ocean: at the real 8000.0 scale, measured directly across 28 real
## generated shorelines (tools/probe_ocean_shore_gradient2.gd), the MEDIAN
## near-shore slope reached the full WADE_DEPTH_METERS threshold within
## ~0.03 tiles -- a small fraction of a single tile, an instant on/off
## switch regardless of how gradually the underlying elevation itself
## actually changes.
##
## 50.0 is picked from that SAME measured sample: at this scale, the
## median real slope reaches wade depth in ~5.4 tiles (a believable
## multi-step walk into the water), while five real, genuinely deep
## open-ocean points (mid-Pacific, mid-Atlantic, the Mariana Trench area,
## the Indian Ocean) still resolve to 22-41m of depth -- comfortably past
## the wade threshold, not accidentally shallow.
const OCEAN_DEPTH_RANGE_METERS := 50.0
## Swimming speed relative to normal walking speed, for an unweighted swimmer.
const BASE_SWIM_SPEED := 0.6


## Resolves a character's movement mode and speed multiplier from water depth
## (in real meters) and carried weight. total_weight is the character's
## current total weight including soaked equipment (see
## EquipmentMaterial.effective_weight); max_swimmable_weight is the heaviest a
## character can carry and still swim. Returns a Dictionary:
## {mode: "walking"|"wading"|"swimming"|"drowning", speed_multiplier: float}.
func resolve(water_depth_meters: float, total_weight: float, max_swimmable_weight: float) -> Dictionary:
	if water_depth_meters <= 0.0:
		return {"mode": "walking", "speed_multiplier": 1.0}

	if water_depth_meters <= WADE_DEPTH_METERS:
		var depth_fraction := water_depth_meters / WADE_DEPTH_METERS
		return {"mode": "wading", "speed_multiplier": 1.0 - depth_fraction * WADE_SPEED_LOSS}

	if total_weight > max_swimmable_weight:
		return {"mode": "drowning", "speed_multiplier": 0.0}

	var weight_fraction := total_weight / max_swimmable_weight
	return {"mode": "swimming", "speed_multiplier": BASE_SWIM_SPEED * (1.0 - weight_fraction)}
