extends GutTest

## Pure aquatic-foraging target-finding -- see docs/concept/aquatic_foraging.md.
## Mirrors FishSchooling's own shape exactly: a handful of pure static
## functions FishMarker calls into each frame, not an instantiated
## behaviour object (the fish system's own established pattern, not the
## land-animal XForageBehavior state-machine convention this file has
## never used).

const FishForaging = preload("res://src/gameplay/fish_foraging.gd")


func test_nearest_target_is_null_with_no_candidates():
	assert_null(FishForaging.nearest_target(Vector2.ZERO, []))


func test_nearest_target_finds_the_only_candidate():
	var candidates := [{"position": Vector2(10, 0)}]
	assert_eq(FishForaging.nearest_target(Vector2.ZERO, candidates), Vector2(10, 0))


func test_nearest_target_picks_the_closest_of_several():
	var candidates := [
		{"position": Vector2(100, 0)},
		{"position": Vector2(5, 0)},
		{"position": Vector2(50, 0)},
	]
	assert_eq(FishForaging.nearest_target(Vector2.ZERO, candidates), Vector2(5, 0))


func test_nearest_target_is_order_independent():
	var position := Vector2(20, 20)
	var candidates := [
		{"position": Vector2(0, 0)},
		{"position": Vector2(21, 21)},
		{"position": Vector2(100, 100)},
	]
	var forward = FishForaging.nearest_target(position, candidates)
	candidates.reverse()
	var reversed = FishForaging.nearest_target(position, candidates)
	assert_eq(forward, reversed)


func test_detection_radius_is_positive():
	assert_gt(FishForaging.DETECTION_RADIUS_TILES, 0.0)


func test_graze_arrive_distance_is_positive_and_small():
	assert_gt(FishForaging.GRAZE_ARRIVE_DISTANCE_PX, 0.0)
	# Comfortably smaller than one tile's own worth of detection range --
	# "arrived" should mean genuinely at the patch, not merely nearby.
	const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
	assert_lt(FishForaging.GRAZE_ARRIVE_DISTANCE_PX, float(TerrainRenderer.TILE_SIZE))


func test_scan_interval_is_positive():
	assert_gt(FishForaging.SCAN_INTERVAL, 0.0)
