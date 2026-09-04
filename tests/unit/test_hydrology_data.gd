extends GutTest

## docs/concept/hydrology.md#layer-0 "Shipped outputs": the baked drainage
## network as compact rasters plus one JSON, and the in-memory reader every
## tile read goes through. Encode/decode are pure; save/load round-trip
## through user:// so the file layout the bake tool writes is the one the
## game reads.

const HydrologyData = preload("res://src/world/hydrology_data.gd")
const DrainageNetwork = preload("res://src/world/drainage_network.gd")

## Must sit BETWEEN the fixture sea row (0.2) and its lowest LAND cell
## (the crater floor, 0.3). At 0.5 the crater was itself sub-sea, and
## once the largest sea component started counting as the ocean the
## 9-cell crater outvoted the 7-cell row and swapped their roles.
const SEA_LEVEL := 0.25
const TEST_DIRECTORY := "user://test_hydrology_data"


func after_each():
	var dir := DirAccess.open("user://")
	if dir != null and dir.dir_exists(TEST_DIRECTORY):
		for file_name in DirAccess.get_files_at(TEST_DIRECTORY):
			DirAccess.remove_absolute(TEST_DIRECTORY.path_join(file_name))
		DirAccess.remove_absolute(TEST_DIRECTORY)


func _crater() -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(49)
	heights.fill(0.8)
	for x in 7:
		heights[x] = 0.2
	for y in range(3, 6):
		for x in range(2, 5):
			heights[y * 7 + x] = 0.3
	heights[1 * 7 + 3] = 0.6
	heights[2 * 7 + 3] = 0.6
	return heights


func _baked_crater() -> HydrologyData:
	var network = DrainageNetwork.new().build(_crater(), 7, 7, SEA_LEVEL)
	var weights := PackedFloat32Array()
	weights.resize(49)
	weights.fill(0.5)
	var discharge: PackedFloat32Array = network.accumulate_weighted(weights)
	var data := HydrologyData.new()
	data.build_from_network(network, discharge)
	return data


func test_discharge_encoding_maps_zero_to_zero():
	assert_eq(HydrologyData.encode_discharge(0.0), 0)
	assert_eq(HydrologyData.decode_discharge(0), 0.0)


func test_discharge_encoding_round_trips_within_one_log_step():
	# Log-encoded to a byte: coarse in absolute terms, fine in the ratio a
	# river's width actually reads (hydrology.md's width is log2 of Q).
	for q in [0.5, 1.0, 3.0, 40.0, 1000.0, 250000.0, 3.0e6]:
		var decoded: float = HydrologyData.decode_discharge(HydrologyData.encode_discharge(q))
		# q comes from an untyped literal array, so the division is Variant
		# and needs the annotation -- without it this whole script failed to
		# parse and GUT skipped it silently.
		var ratio: float = decoded / float(q)
		assert_between(ratio, 0.9, 1.1, "q=%f decoded to %f" % [q, decoded])


func test_discharge_encoding_is_monotone_and_never_overflows_a_byte():
	var previous := -1
	for exponent in range(0, 31):
		var code: int = HydrologyData.encode_discharge(pow(2.0, exponent))
		assert_gte(code, previous)
		assert_lte(code, 255)
		previous = code


func test_built_data_mirrors_the_network():
	var network = DrainageNetwork.new().build(_crater(), 7, 7, SEA_LEVEL)
	var data := _baked_crater()
	assert_eq(data.width, 7)
	assert_eq(data.height, 7)
	for index in 49:
		assert_eq(data.flow_direction_at(index), network.flow_direction[index])
		assert_eq(data.depression_at(index), network.depression_id[index])
	assert_eq(data.depressions.size(), 1)
	assert_almost_eq(data.depressions[0]["spill_elevation"], 0.6, 1e-4)


func test_built_discharge_survives_encoding_at_the_sea():
	var data := _baked_crater()
	# 42 land cells at weight 0.5 all reach the single sea row.
	var into_sea := 0.0
	for index in 7:
		into_sea += data.discharge_at(index)
	assert_between(into_sea, 21.0 * 0.9, 21.0 * 1.1)


func test_save_then_load_reproduces_every_field():
	var data := _baked_crater()
	data.save_to(TEST_DIRECTORY)
	var loaded := HydrologyData.new()
	assert_true(loaded.load_from(TEST_DIRECTORY), "bake files must load back")
	assert_eq(loaded.width, 7)
	assert_eq(loaded.height, 7)
	assert_eq(loaded.flow_direction, data.flow_direction)
	assert_eq(loaded.discharge_log, data.discharge_log)
	assert_eq(loaded.depression_id, data.depression_id)
	assert_eq(loaded.depressions.size(), 1)
	assert_eq(loaded.depressions[0]["spill_index"], data.depressions[0]["spill_index"])
	assert_almost_eq(loaded.depressions[0]["spill_elevation"], data.depressions[0]["spill_elevation"], 1e-9)
	assert_false(loaded.depressions[0]["inland_sea"], "a crater is not an inland sea, and the key survives the round trip")


func test_loading_a_missing_bake_returns_false_without_erroring():
	var loaded := HydrologyData.new()
	assert_false(loaded.load_from("user://definitely_not_baked"))
