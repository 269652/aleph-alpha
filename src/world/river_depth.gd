extends RefCounted

## How deep a river reads for player/creature wading-vs-swimming purposes,
## in real meters -- deliberately not survey-accurate per-river data (none
## is curated), but chosen so a wide curated river offers both a wadeable
## bank and a swimmable middle, and a narrower procedural stream stays
## wadeable throughout. See docs/concept/rivers.md.
##
## Before this, EarthChunkGenerator.is_river_at_global existed purely for
## rendering (EarthChunkManager's water overlay) -- Player._resolve_water_state
## never consulted it at all, only real elevation-below-sea-level (see
## BiomeClassifier.depth_at), which every river tile fails by construction
## (a river never changes biome_at_global's own elevation-derived result,
## per rivers.md's "Rendering" section) -- so a player could walk straight
## through a river with no wading/swimming, no submersion tint
## (SubmersionShader, already fully wired for ocean), and no water ripples
## at all. This is the depth half of closing that gap.

## Curated rivers deepen toward their own centerline (RiverCatalog's
## distance_to_nearest_river_tiles), 0 at RIVER_HALF_WIDTH_TILES and this
## maximum at the exact line. Set above WaterMovementModel.WADE_DEPTH_METERS
## (1.5m) so the range genuinely spans both modes -- pinned by
## test_curated_depth_range_spans_both_wading_and_swimming.
const MAX_CURATED_RIVER_DEPTH_METERS := 2.5

## Procedural (uncurated) rivers stay a flat, shallower depth throughout --
## "a minor stream," distinct from a real named river's deep centerline,
## and never reaching WADE_DEPTH_METERS's swim threshold.
const PROCEDURAL_RIVER_DEPTH_METERS := 1.0


## Real meters of depth for a tile a known `distance_to_centerline_tiles`
## from the nearest curated river's course (RiverCatalog.
## distance_to_nearest_river_tiles), given that river's `half_width_tiles`
## (RiverCatalog.RIVER_HALF_WIDTH_TILES). Linear falloff from the maximum at
## the centerline to 0.0 at/beyond the half-width.
static func curated_depth_meters(distance_to_centerline_tiles: float, half_width_tiles: float) -> float:
	if distance_to_centerline_tiles >= half_width_tiles:
		return 0.0
	var depth_fraction := 1.0 - (distance_to_centerline_tiles / half_width_tiles)
	return depth_fraction * MAX_CURATED_RIVER_DEPTH_METERS
