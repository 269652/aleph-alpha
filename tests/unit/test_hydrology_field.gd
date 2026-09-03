extends GutTest

## docs/concept/hydrology.md#layer-5-the-tile-read-what-a-chunk-actually-gets:
## a game tile asks the baked network three questions (in a lake? on a
## channel, how wide, how deep? how much valley?) and gets answers computed
## from its own global coordinates alone. Synthetic bake: the 7x7 crater
## from test_drainage_network, read as a 70x70-tile world (10 tiles per
## asset cell).

const HydrologyField = preload("res://src/world/hydrology_field.gd")
const HydrologyData = preload("res://src/world/hydrology_data.gd")
const DrainageNetwork = preload("res://src/world/drainage_network.gd")
const TerrainRelief = preload("res://src/world/terrain_relief.gd")

const SEA_LEVEL := 0.5
const WORLD_TILES := 70
## Low enough that the crater's outlet (a dozen cells of unit rain) is a
## river; the shipped constant is calibrated for the real asset, not 7x7.
const TEST_MIN_DISCHARGE := 5.0

var field: HydrologyField


func before_each():
	field = _field_for(TEST_MIN_DISCHARGE)


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


func _field_for(min_discharge: float) -> HydrologyField:
	var network = DrainageNetwork.new().build(_crater(), 7, 7, SEA_LEVEL)
	var weights := PackedFloat32Array()
	weights.resize(49)
	weights.fill(1.0)
	var data := HydrologyData.new()
	data.build_from_network(network, network.accumulate_weighted(weights))
	var built := HydrologyField.new(data, WORLD_TILES, WORLD_TILES)
	built.river_min_discharge = min_discharge
	return built


## --- coordinate mapping ---


func test_tile_origin_maps_to_pixel_origin_and_the_seam_wraps():
	assert_eq(field.pixel_of_tile(0, 0), Vector2(0.0, 0.0))
	assert_eq(field.cell_index_at(-1, 0), 6, "one cell west of x=0 is the east edge")
	assert_eq(field.cell_index_at(7, 2), 2 * 7, "one cell east of the edge is x=0")
	assert_eq(field.cell_index_at(3, -1), 3, "north of the pole clamps, never wraps")


func test_ten_tiles_span_one_asset_cell():
	var pixel := field.pixel_of_tile(35, 45)
	assert_eq(floori(pixel.x), 3)
	assert_eq(floori(pixel.y), 4)


## --- lakes ---


func test_a_tile_on_the_crater_floor_is_a_lake_filled_to_the_spill():
	var probe: Dictionary = field.probe(35, 45, 0.3)
	assert_eq(probe["kind"], "lake")
	var expected_depth := 0.3 * (TerrainRelief.ELEVATION_MAX_M - TerrainRelief.ELEVATION_MIN_M)
	assert_almost_eq(probe["depth_m"], expected_depth, 2.0, "depth is spill minus the tile's own elevation, in metres")


func test_a_tile_above_the_spill_inside_the_basin_footprint_is_dry():
	# A crater cell (2,4), but the tile's own (bilinear) elevation sits
	# above the spill: the shoreline follows the real contour, not the cell
	# edge. (Cell (3,4) is avoided here: the crater's own inflow channel
	# through (3,3) reaches into it, which is a river question, not a lake one.)
	assert_eq(field.probe(25, 45, 0.65)["kind"], "")


## --- rivers ---


func test_a_tile_on_the_outlet_channel_is_a_river():
	# Cell (3,1) is the crater's outlet channel; its centreline runs down
	# tile column x=35. Both tiles straddling it are within half a width.
	assert_eq(field.probe(34, 14, 0.6)["kind"], "river")
	assert_eq(field.probe(35, 14, 0.6)["kind"], "river")


func test_the_channel_continues_to_the_sea_cell_centre():
	# The mouth segment runs from the channel cell's centre into the sea
	# cell's centre, so the river does not stop one cell short of the coast.
	assert_eq(field.probe(35, 8, 0.6)["kind"], "river")


func test_a_plateau_tile_far_from_any_channel_is_dry_ground():
	var probe: Dictionary = field.probe(65, 45, 0.8)
	assert_eq(probe["kind"], "")
	assert_eq(probe["depth_m"], 0.0)
	assert_eq(probe["fine_detail_scale"], 1.0)
	assert_eq(probe["carve"], 0.0)


func test_a_channel_below_the_discharge_threshold_is_a_dry_bed_not_a_river():
	var dry := _field_for(1000.0)
	assert_eq(dry.probe(35, 14, 0.6)["kind"], "")


func test_a_river_tile_has_a_real_depth_and_a_lake_tile_does_not_use_it():
	var river: Dictionary = field.probe(35, 14, 0.6)
	assert_gt(river["depth_m"], 0.0)
	assert_almost_eq(river["depth_m"], field.depth_meters_for_discharge(river["discharge"]), 1e-6)


## --- hydraulic geometry ---


func test_width_is_at_least_one_tile_and_grows_with_discharge():
	var at_threshold := field.width_tiles_for_discharge(TEST_MIN_DISCHARGE)
	assert_almost_eq(at_threshold, HydrologyField.MIN_LEGIBLE_WIDTH_TILES, 1e-9)
	assert_gt(field.width_tiles_for_discharge(TEST_MIN_DISCHARGE * 2.0), at_threshold)
	assert_gt(field.width_tiles_for_discharge(TEST_MIN_DISCHARGE * 64.0), field.width_tiles_for_discharge(TEST_MIN_DISCHARGE * 8.0))
	assert_lte(field.width_tiles_for_discharge(1.0e12), HydrologyField.MAX_WIDTH_TILES)


func test_below_threshold_discharge_has_no_width():
	assert_eq(field.width_tiles_for_discharge(TEST_MIN_DISCHARGE * 0.5), 0.0)


func test_depth_follows_the_leopold_maddock_exponent():
	# d ~ Q^0.4: sixteen times the discharge is 16^0.4 = 3.03x the depth.
	var ratio := field.depth_meters_for_discharge(1600.0) / field.depth_meters_for_discharge(100.0)
	assert_almost_eq(ratio, pow(16.0, HydrologyField.DEPTH_EXPONENT), 1e-6)


## --- valleys ---


func test_the_channel_suppresses_fine_detail_and_carves():
	var probe: Dictionary = field.probe(35, 14, 0.6)
	assert_eq(probe["fine_detail_scale"], 0.0)
	assert_gt(probe["carve"], 0.0)


func test_fine_detail_ramps_back_beside_the_channel():
	# Two tiles east of the centreline is inside the valley shoulder but
	# outside the channel: partly suppressed, partly carved.
	var shoulder: Dictionary = field.probe(37, 14, 0.7)
	assert_eq(shoulder["kind"], "")
	assert_between(shoulder["fine_detail_scale"], 0.01, 0.99)
	assert_gt(shoulder["carve"], 0.0)
	assert_lt(shoulder["carve"], field.probe(35, 14, 0.6)["carve"])


func test_a_lake_bed_has_no_fine_detail_and_no_carve():
	var probe: Dictionary = field.probe(35, 45, 0.3)
	assert_eq(probe["fine_detail_scale"], 0.0)
	assert_eq(probe["carve"], 0.0)


func test_probe_is_a_pure_function_of_the_tile():
	assert_eq(field.probe(35, 14, 0.6), field.probe(35, 14, 0.6))
	assert_eq(field.probe(35, 45, 0.3), _field_for(TEST_MIN_DISCHARGE).probe(35, 45, 0.3))


## --- geometry for the river flow overlay (RiverCatalog.nearest_river_at's shape) ---


func test_channel_geometry_reports_distance_side_and_downstream_bearing():
	# The outlet channel runs north (toward the sea row) down column x=35.
	var west: Dictionary = field.nearest_channel_geometry(34, 14)
	var east: Dictionary = field.nearest_channel_geometry(35, 14)
	assert_almost_eq(west["distance_tiles"], 0.5, 1e-6)
	assert_almost_eq(east["distance_tiles"], 0.5, 1e-6)
	assert_almost_eq(west["course_bearing_deg"], 0.0, 1e-6, "flow is due north")
	# Same convention as the catalog: tangent.cross(point - closest), so the
	# two banks have opposite signs and equal magnitude.
	assert_almost_eq(west["signed_across_tiles"], -east["signed_across_tiles"], 1e-6)
	assert_almost_eq(absf(east["signed_across_tiles"]), 0.5, 1e-6)
	assert_gt(east["discharge"], 0.0)


func test_channel_geometry_is_empty_away_from_any_channel():
	assert_true(field.nearest_channel_geometry(65, 45).is_empty())


func test_a_channel_is_exactly_as_wide_as_a_curated_river():
	# rivers.md's uniform half-width, so the overlay and the read agree.
	assert_eq(field.probe(36, 14, 0.6)["kind"], "river", "inside the half-width")
	assert_eq(field.probe(38, 14, 0.6)["kind"], "", "outside it")
	assert_almost_eq(HydrologyField.CHANNEL_HALF_WIDTH_TILES, 2.0, 1e-9)
