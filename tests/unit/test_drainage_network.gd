extends GutTest

## docs/concept/hydrology.md#layer-0-the-drainage-bake-static-shipped-as-data
## -- priority-flood depression filling, D8 flow direction, accumulation.
## Pure and engine-free: small synthetic height grids in, packed arrays out.

const DrainageNetwork = preload("res://src/world/drainage_network.gd")

const SEA_LEVEL := 0.5


func _grid(width: int, height: int, value: float) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(width * height)
	heights.fill(value)
	return heights


## 5x5: land everywhere at 0.8 except one sea cell in the top-left corner.
func _bowl_with_corner_sea() -> PackedFloat32Array:
	var heights := _grid(5, 5, 0.8)
	heights[0] = 0.2
	return heights


## 7x7: the top row is sea, the rest a 0.8 plateau with a 3x3 crater at
## 0.3 in the middle. A channel at 0.6 runs from the crater's north rim
## (rows 1-2, column 3) to the sea -- the crater's lowest way out, and
## therefore where it must spill. The channel is NOT enclosed (a lone 0.6
## notch inside 0.8 plateau would itself be a basin, spilling at 0.8).
func _crater_with_north_notch() -> PackedFloat32Array:
	var heights := _grid(7, 7, 0.8)
	for x in 7:
		heights[x] = 0.2
	for y in range(3, 6):
		for x in range(2, 5):
			heights[y * 7 + x] = 0.3
	heights[1 * 7 + 3] = 0.6
	heights[2 * 7 + 3] = 0.6
	return heights


## Follows flow_direction from `start` until a sea cell is reached, returning
## the path as indices. Fails the test (and stops) if the walk exceeds the
## cell count, which can only happen on a cycle or a dead end.
func _walk_to_sea(network, start: int) -> Array[int]:
	var path: Array[int] = [start]
	var index := start
	var steps := 0
	while not network.is_sea(index):
		index = network.downstream_index(index)
		if index < 0 or steps > network.width * network.height:
			fail_test("flow from %d dead-ends or cycles at %d" % [start, index])
			return path
		path.append(index)
		steps += 1
	return path


func test_every_land_cell_in_a_bowl_drains_to_the_sea():
	var network = DrainageNetwork.new().build(_bowl_with_corner_sea(), 5, 5, SEA_LEVEL)
	for index in 25:
		if network.is_sea(index):
			continue
		var path := _walk_to_sea(network, index)
		assert_true(network.is_sea(path[-1]), "cell %d must reach the sea" % index)


func test_filled_surface_is_never_below_the_original():
	var heights := _bowl_with_corner_sea()
	var network = DrainageNetwork.new().build(heights, 5, 5, SEA_LEVEL)
	for index in 25:
		assert_gte(network.filled[index], heights[index])


func test_flow_descends_strictly_along_the_filled_surface():
	# The bowl is a perfectly flat plateau: the raw data has no gradient at
	# all, exactly the 75m coastal-plain case hydrology.md measured. The
	# epsilon fill is what gives it one.
	var network = DrainageNetwork.new().build(_bowl_with_corner_sea(), 5, 5, SEA_LEVEL)
	for index in 25:
		if network.is_sea(index):
			continue
		var downstream: int = network.downstream_index(index)
		assert_lt(network.filled[downstream], network.filled[index], "cell %d must drain downhill" % index)


func test_a_flat_plateau_beside_the_sea_is_not_a_depression():
	var network = DrainageNetwork.new().build(_bowl_with_corner_sea(), 5, 5, SEA_LEVEL)
	assert_eq(network.depressions.size(), 0)
	for index in 25:
		assert_eq(network.depression_id[index], DrainageNetwork.NO_DEPRESSION)


func test_a_crater_becomes_exactly_one_depression():
	var network = DrainageNetwork.new().build(_crater_with_north_notch(), 7, 7, SEA_LEVEL)
	assert_eq(network.depressions.size(), 1)
	assert_eq(network.depressions[0]["cell_count"], 9)
	assert_eq(network.depression_id[4 * 7 + 3], 0, "crater centre belongs to the depression")
	assert_eq(network.depression_id[4 * 7 + 6], DrainageNetwork.NO_DEPRESSION, "plateau does not")


func test_a_crater_spills_at_its_lowest_rim():
	var network = DrainageNetwork.new().build(_crater_with_north_notch(), 7, 7, SEA_LEVEL)
	var depression: Dictionary = network.depressions[0]
	assert_almost_eq(depression["spill_elevation"], 0.6, 1e-4)
	assert_almost_eq(depression["floor_elevation"], 0.3, 1e-6)
	# The spill cell is the crater cell directly below the notch.
	assert_eq(depression["spill_index"], 3 * 7 + 3)


func test_crater_cells_are_filled_to_the_spill_and_still_reach_the_sea():
	var network = DrainageNetwork.new().build(_crater_with_north_notch(), 7, 7, SEA_LEVEL)
	for y in range(3, 6):
		for x in range(2, 5):
			var index := y * 7 + x
			assert_almost_eq(network.filled[index], 0.6, 1e-4)
			var path := _walk_to_sea(network, index)
			assert_true(network.is_sea(path[-1]))


func test_accumulation_at_the_sea_equals_the_land_cell_count():
	var network = DrainageNetwork.new().build(_bowl_with_corner_sea(), 5, 5, SEA_LEVEL)
	var into_sea := 0
	for index in 25:
		if network.is_sea(index):
			into_sea += network.accumulation[index]
	assert_eq(into_sea, 24)


func test_accumulation_grows_downstream_along_a_single_slope():
	# One column, five rows, sea at the top, land rising away from it.
	var heights := PackedFloat32Array([0.2, 0.6, 0.7, 0.8, 0.9])
	var network = DrainageNetwork.new().build(heights, 1, 5, SEA_LEVEL)
	assert_eq(network.accumulation[4], 1)
	assert_eq(network.accumulation[3], 2)
	assert_eq(network.accumulation[2], 3)
	assert_eq(network.accumulation[1], 4)
	assert_eq(network.accumulation[0], 4)


func test_east_edge_drains_west_across_the_seam_only_when_wrapping():
	# One row: sea at x=0, land rising eastward. The east-most cell's
	# lowest neighbour is the sea across the date line -- reachable only
	# when the grid wraps, as the real equirectangular asset does.
	var heights := PackedFloat32Array([0.2, 0.6, 0.7, 0.8, 0.9])
	var wrapped = DrainageNetwork.new().build(heights, 5, 1, SEA_LEVEL, true)
	assert_eq(wrapped.downstream_index(4), 0)
	var clamped = DrainageNetwork.new().build(heights, 5, 1, SEA_LEVEL, false)
	assert_eq(clamped.downstream_index(4), 3)


func test_depressions_smaller_than_the_minimum_area_are_filled_through():
	# The 9-cell crater is data noise when the minimum is 10: no lake
	# candidate, but its cells still drain (the fill is unchanged).
	var network = DrainageNetwork.new().build(
		_crater_with_north_notch(), 7, 7, SEA_LEVEL, false,
		DrainageNetwork.DEFAULT_MIN_DEPRESSION_DEPTH, 10
	)
	assert_eq(network.depressions.size(), 0)
	assert_eq(network.depression_id[4 * 7 + 3], DrainageNetwork.NO_DEPRESSION)
	assert_almost_eq(network.filled[4 * 7 + 3], 0.6, 1e-4)
	var path := _walk_to_sea(network, 4 * 7 + 3)
	assert_true(network.is_sea(path[-1]))


func test_weighted_accumulation_with_unit_weights_matches_the_cell_count():
	var network = DrainageNetwork.new().build(_crater_with_north_notch(), 7, 7, SEA_LEVEL)
	var weights := _grid(7, 7, 1.0)
	var weighted: PackedFloat32Array = network.accumulate_weighted(weights)
	for index in 49:
		assert_almost_eq(weighted[index], float(network.accumulation[index]), 1e-5)


func test_weighted_accumulation_carries_upstream_runoff_through_a_dry_cell():
	# One column, sea at the top: rain only on the two headwater cells. The
	# dry cell just above the sea still carries their runoff -- a river
	# leaving wet mountains does not stop at the first desert cell.
	var heights := PackedFloat32Array([0.2, 0.6, 0.7, 0.8, 0.9])
	var network = DrainageNetwork.new().build(heights, 1, 5, SEA_LEVEL)
	var weights := PackedFloat32Array([0.0, 0.0, 0.0, 0.5, 0.5])
	var weighted: PackedFloat32Array = network.accumulate_weighted(weights)
	assert_almost_eq(weighted[4], 0.5, 1e-6)
	assert_almost_eq(weighted[3], 1.0, 1e-6)
	assert_almost_eq(weighted[1], 1.0, 1e-6, "dry cell carries what arrives from upstream")
	assert_almost_eq(weighted[0], 1.0, 1e-6, "sea receives it all")


func test_build_is_deterministic():
	var first = DrainageNetwork.new().build(_crater_with_north_notch(), 7, 7, SEA_LEVEL)
	var second = DrainageNetwork.new().build(_crater_with_north_notch(), 7, 7, SEA_LEVEL)
	assert_eq(first.filled, second.filled)
	assert_eq(first.flow_direction, second.flow_direction)
	assert_eq(first.accumulation, second.accumulation)
	assert_eq(first.depression_id, second.depression_id)
