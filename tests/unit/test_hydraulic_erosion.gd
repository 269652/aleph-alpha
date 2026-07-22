extends GutTest

const HydraulicErosion = preload("res://src/world/hydraulic_erosion.gd")

var erosion: HydraulicErosion


func before_each():
	erosion = HydraulicErosion.new()


func _flat_heights(width: int, height: int, value: float) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(width * height)
	heights.fill(value)
	return heights


func _sloped_heights() -> PackedFloat32Array:
	# 5 wide, 3 tall; strictly decreasing left-to-right, constant down each column.
	var width := 5
	var height := 3
	var heights := PackedFloat32Array()
	heights.resize(width * height)
	for y in height:
		for x in width:
			heights[y * width + x] = 1.0 - x * 0.2
	return heights


func test_erosion_preserves_heightmap_size():
	var heights := _sloped_heights()
	var eroded := erosion.erode(heights, 5, 3, 10, 1)
	assert_eq(eroded.size(), heights.size())


func test_flat_terrain_is_unchanged_by_erosion():
	var heights := _flat_heights(4, 4, 0.5)
	var eroded := erosion.erode(heights, 4, 4, 50, 1)
	assert_eq(eroded, heights)


func test_erosion_never_raises_elevation_above_the_original():
	var heights := _sloped_heights()
	var eroded := erosion.erode(heights, 5, 3, 50, 7)
	for i in heights.size():
		assert_lte(eroded[i], heights[i])


func test_erosion_removes_material_from_sloped_terrain_overall():
	var heights := _sloped_heights()
	var eroded := erosion.erode(heights, 5, 3, 50, 7)
	var original_sum := 0.0
	var eroded_sum := 0.0
	for i in heights.size():
		original_sum += heights[i]
		eroded_sum += eroded[i]
	assert_lt(eroded_sum, original_sum)


func test_erosion_is_deterministic_for_the_same_seed():
	var heights := _sloped_heights()
	var first := erosion.erode(heights, 5, 3, 50, 42)
	var second := erosion.erode(heights, 5, 3, 50, 42)
	assert_eq(first, second)


func test_erosion_keeps_values_within_zero_and_one():
	var heights := _sloped_heights()
	var eroded := erosion.erode(heights, 5, 3, 200, 42)
	for h in eroded:
		assert_between(h, 0.0, 1.0)
