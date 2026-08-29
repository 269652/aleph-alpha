extends GutTest

## How deep a river reads for wading-vs-swimming purposes -- see
## docs/concept/rivers.md and WaterMovementModel.WADE_DEPTH_METERS (1.5m).

const RiverDepth = preload("res://src/world/river_depth.gd")
const RiverCatalog = preload("res://src/world/river_catalog.gd")
const WaterMovementModel = preload("res://src/gameplay/water_movement_model.gd")


func test_at_the_exact_centerline_depth_is_the_curated_maximum():
	assert_almost_eq(
		RiverDepth.curated_depth_meters(0.0, RiverCatalog.RIVER_HALF_WIDTH_TILES),
		RiverDepth.MAX_CURATED_RIVER_DEPTH_METERS,
		0.0001
	)


func test_at_or_beyond_the_half_width_depth_is_zero():
	assert_eq(RiverDepth.curated_depth_meters(RiverCatalog.RIVER_HALF_WIDTH_TILES, RiverCatalog.RIVER_HALF_WIDTH_TILES), 0.0)
	assert_eq(RiverDepth.curated_depth_meters(RiverCatalog.RIVER_HALF_WIDTH_TILES + 1.0, RiverCatalog.RIVER_HALF_WIDTH_TILES), 0.0)


func test_depth_decreases_monotonically_toward_the_bank():
	var half_width := RiverCatalog.RIVER_HALF_WIDTH_TILES
	var previous := RiverDepth.curated_depth_meters(0.0, half_width)
	for i in range(1, 10):
		var distance := half_width * (float(i) / 10.0)
		var depth := RiverDepth.curated_depth_meters(distance, half_width)
		assert_lt(depth, previous, "depth must strictly decrease moving away from the centerline")
		previous = depth


## The whole point of a curated river's depth range: it must actually cross
## WADE_DEPTH_METERS somewhere inside the band, so a wide enough curated
## river offers a wadeable bank AND a swimmable middle -- not just one or
## the other for its entire width.
func test_curated_depth_range_spans_both_wading_and_swimming():
	var half_width := RiverCatalog.RIVER_HALF_WIDTH_TILES
	assert_gt(
		RiverDepth.curated_depth_meters(0.0, half_width), WaterMovementModel.WADE_DEPTH_METERS,
		"the centerline should be deep enough to swim"
	)
	assert_between(
		RiverDepth.curated_depth_meters(half_width * 0.9, half_width), 0.0, WaterMovementModel.WADE_DEPTH_METERS
	)


## Procedural rivers are deliberately shallower throughout -- "a minor
## stream," never quite reaching the swim threshold.
func test_procedural_river_depth_stays_wadeable_not_swimmable():
	assert_gt(RiverDepth.PROCEDURAL_RIVER_DEPTH_METERS, 0.0)
	assert_lt(RiverDepth.PROCEDURAL_RIVER_DEPTH_METERS, WaterMovementModel.WADE_DEPTH_METERS)
