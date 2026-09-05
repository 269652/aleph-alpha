extends GutTest

## docs/concept/hydrology.md#layer-5-the-tile-read-what-a-chunk-actually-gets:
## a game tile asks the baked network three questions (in a lake? on a
## channel, how wide, how deep? how much valley?) and gets answers computed
## from its own global coordinates alone. Synthetic bake: the 7x7 crater
## from test_drainage_network, read as a 70x70-tile world (10 tiles per
## asset cell).

const HydrologyField = preload("res://src/world/hydrology_field.gd")
const RiverCatalog = preload("res://src/world/river_catalog.gd")
const RiverFlowShader = preload("res://src/rendering/river_flow_shader.gd")
const HydrologyData = preload("res://src/world/hydrology_data.gd")
const DrainageNetwork = preload("res://src/world/drainage_network.gd")
const TerrainRelief = preload("res://src/world/terrain_relief.gd")

## Must sit BETWEEN the fixtures' sea row (0.2) and their lowest LAND
## cell (the crater floor, 0.3). At 0.5 the crater was itself sub-sea, so
## once the largest sea component started counting as the ocean the
## 9-cell crater outvoted the 7-cell row and the two swapped roles.
const SEA_LEVEL := 0.25
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
	assert_false(probe["sea"])
	var expected_depth := 0.3 * (TerrainRelief.ELEVATION_MAX_M - TerrainRelief.ELEVATION_MIN_M)
	assert_almost_eq(probe["depth_m"], expected_depth, 2.0, "depth is spill minus the tile's own elevation, in metres")


func test_a_tile_just_outside_the_footprint_is_dry():
	# Cell (1,4) is plateau beside the crater: well inside it, the lake
	# coverage is below half whatever the tile's own elevation says.
	assert_eq(field.probe(12, 45, 0.55)["kind"], "")


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
	# Two and a half tiles east of the centreline is inside the valley
	# shoulder but outside the channel: partly suppressed, partly carved.
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
	# The curve cache is transparent: a warm field and a cold one agree on
	# a river tile's geometry to the bit.
	assert_eq(field.nearest_channel_geometry(34, 14), _field_for(TEST_MIN_DISCHARGE).nearest_channel_geometry(34, 14))


## --- geometry for the river flow overlay (RiverCatalog.nearest_river_at's shape) ---


func test_channel_geometry_reports_distance_side_and_downstream_bearing():
	# The outlet channel runs north (toward the sea row) down column x=35.
	var west: Dictionary = field.nearest_channel_geometry(34, 14)
	var east: Dictionary = field.nearest_channel_geometry(35, 14)
	assert_almost_eq(west["distance_tiles"], 0.5, 1e-6)
	assert_almost_eq(east["distance_tiles"], 0.5, 1e-6)
	# 1e-3, not 1e-6: the bearing is the tangent of a sampled Bezier, not
	# an exact cell step, so due north lands 0.0004 deg off. That is four
	# ten-thousandths of a degree -- below what the flow map can express
	# and eight orders of magnitude below the drift a real bend produces.
	assert_almost_eq(west["course_bearing_deg"], 0.0, 1e-3, "flow is due north")
	# Same convention as the catalog: tangent.cross(point - closest), so the
	# two banks have opposite signs and equal magnitude.
	assert_almost_eq(west["signed_across_tiles"], -east["signed_across_tiles"], 1e-6)
	assert_almost_eq(absf(east["signed_across_tiles"]), 0.5, 1e-6)
	assert_gt(east["discharge"], 0.0)


func test_signed_across_has_the_true_distance_as_its_magnitude_everywhere():
	# Along a curve, |signed across| must equal the distance at every tile
	# -- the cross product alone undershoots near joints (the sawtooth).
	for y in range(6, 30):
		for x in [33, 34, 36, 37]:
			var geometry: Dictionary = field.nearest_channel_geometry(x, y)
			if geometry.is_empty():
				continue
			assert_almost_eq(absf(geometry["signed_across_tiles"]), geometry["distance_tiles"], 1e-6)


func test_channel_geometry_is_empty_away_from_any_channel():
	assert_true(field.nearest_channel_geometry(65, 45).is_empty())


func test_a_channel_is_as_wide_as_its_own_discharge_says():
	# Half-width comes from the cell's discharge (one tile at the
	# threshold, one more per doubling), so the overlay and the read agree
	# tile for tile and a bigger river is visibly wider.
	var geometry: Dictionary = field.nearest_channel_geometry(35, 14)
	var expected := field.width_tiles_for_discharge(geometry["discharge"]) / 2.0
	assert_almost_eq(geometry["half_width_tiles"], expected, 0.15, "interpolated along the curve, near the cell's own width at its centre")
	assert_eq(field.probe(35, 14, 0.6)["kind"], "river", "inside the half-width")
	assert_eq(field.probe(35 + 4, 14, 0.6)["kind"], "", "outside it")


## --- confluence, springs, curves (first playtest feedback) ---


func test_width_grows_where_discharges_add_up():
	# One more doubling of discharge is one more tile of width, so the
	# reach below a confluence is wider than either branch above it.
	var branch := field.width_tiles_for_discharge(TEST_MIN_DISCHARGE * 4.0)
	var combined := field.width_tiles_for_discharge(TEST_MIN_DISCHARGE * 8.0)
	assert_almost_eq(combined - branch, HydrologyField.WIDTH_TILES_PER_DOUBLING, 1e-9)


func test_the_outlet_is_wider_than_the_reach_feeding_it():
	# Cell (3,1) carries everything cell (3,2) does plus its own
	# catchment: 35 cells against 34. That growth is real but NOT legible
	# downstream of the bake. Discharge ships as an 8-bit LOG byte, and 3%
	# is far inside one log step, so both reaches decode to the same
	# number. Nor would it matter if they did not: width is 1 tile per
	# DOUBLING of Q, so 3% is 0.04 of a tile.
	#
	# So this asserts the growth where it exists -- on the raw network --
	# and only monotonicity on the decoded field. The width response to a
	# real doubling is test_width_grows_where_discharges_add_up.
	var network = DrainageNetwork.new().build(_crater(), 7, 7, SEA_LEVEL)
	var unit := PackedFloat32Array()
	unit.resize(49)
	unit.fill(1.0)
	var raw: PackedFloat32Array = network.accumulate_weighted(unit)
	assert_gt(raw[1 * 7 + 3], raw[2 * 7 + 3], "the outlet does carry more, before encoding")
	var outlet: Dictionary = field.nearest_channel_geometry(35, 14)
	var feeder: Dictionary = field.nearest_channel_geometry(35, 24)
	assert_gte(outlet["discharge"], feeder["discharge"])
	assert_gte(outlet["half_width_tiles"], feeder["half_width_tiles"])


## A parallel-columns bake: sea along the top, land rising southward one
## step per row, so every column is its own straight stream. Read as a
## 77-tile world (11 tiles per cell) so cell centres land on tile centres.
func _slope_field() -> HydrologyField:
	var heights := PackedFloat32Array()
	heights.resize(49)
	for y in 7:
		for x in 7:
			heights[y * 7 + x] = 0.2 if y == 0 else 0.5 + 0.05 * float(y)
	var network = DrainageNetwork.new().build(heights, 7, 7, SEA_LEVEL)
	var weights := PackedFloat32Array()
	weights.resize(49)
	weights.fill(1.0)
	var data := HydrologyData.new()
	data.build_from_network(network, network.accumulate_weighted(weights))
	var built := HydrologyField.new(data, 77, 77)
	built.river_min_discharge = TEST_MIN_DISCHARGE
	return built


func test_a_river_tapers_in_from_its_source_instead_of_starting_full_width():
	# Column 3: cells (3,1) Q=6 and (3,2) Q=5 are the river; (3,3) Q=4 is
	# the source. Cell centres: x = 38.5; y = 27.1 for row 2, 38.0 for row 3.
	var slope := _slope_field()
	var at_source: Dictionary = slope.nearest_channel_geometry(38, 37)
	var at_head: Dictionary = slope.nearest_channel_geometry(38, 27)
	assert_false(at_source.is_empty(), "the head's curve reaches back to the source")
	assert_almost_eq(at_source["half_width_tiles"], HydrologyField.SPRING_HALF_WIDTH_TILES, 0.1)
	assert_gt(at_head["half_width_tiles"], at_source["half_width_tiles"])
	assert_eq(slope.probe(38, 41, 0.75)["kind"], "", "nothing upstream of the source")


## A main channel down column 3 (weight 2 per cell, so it is the mainstem)
## and a tributary along row 3 from the west joining it at cell (3,3).
func _confluence_field() -> HydrologyField:
	var heights := PackedFloat32Array()
	heights.resize(49)
	heights.fill(0.8)
	for x in 7:
		heights[x] = 0.2
	for y in range(1, 7):
		heights[y * 7 + 3] = 0.6
	for x in range(0, 3):
		heights[3 * 7 + x] = 0.7
	var network = DrainageNetwork.new().build(heights, 7, 7, SEA_LEVEL)
	var weights := PackedFloat32Array()
	weights.resize(49)
	weights.fill(1.0)
	for y in range(1, 7):
		weights[y * 7 + 3] = 2.0
	var data := HydrologyData.new()
	data.build_from_network(network, network.accumulate_weighted(weights))
	var built := HydrologyField.new(data, WORLD_TILES, WORLD_TILES)
	built.river_min_discharge = 3.0
	return built


func test_a_tributary_reaches_the_main_channels_centreline():
	# Cell (2,3) is the tributary's last cell (Q=3); the main channel's
	# centreline runs down x=35. The tributary must run all the way to the
	# main cell's centre (35, 34.5), not stop at the midpoint x=30 -- first
	# playtest: "one of the rivers doesn't flow into the other anymore".
	var confluence := _confluence_field()
	assert_eq(confluence.probe(32, 34, 0.6)["kind"], "river", "between the midpoint and the main centreline")
	assert_eq(confluence.probe(28, 34, 0.6)["kind"], "river", "before the midpoint")
	var main: Dictionary = confluence.nearest_channel_geometry(35, 24)
	var tributary: Dictionary = confluence.nearest_channel_geometry(25, 34)
	assert_gt(main["discharge"], tributary["discharge"], "column 3 carries the mainstem")
	assert_almost_eq(tributary["course_bearing_deg"], 90.0, 1e-6, "the tributary flows east")


func test_the_across_field_is_continuous_through_a_confluence():
	# Walk a row through the junction where the tributary (along y=34.5)
	# enters the main channel (along x=35): the blended field may bend, it
	# may never jump -- a jump is what the shader draws as fans of arcs.
	#
	# The invariant is that across is a signed DISTANCE, so it is
	# 1-Lipschitz: one tile of travel can move it by at most one tile.
	# A seam is exactly what breaks that.
	#
	# This used to divide across by the half width and require steps
	# under 0.4, which is not a continuity condition at all. Walking
	# straight out of a channel moves across by a full tile per step by
	# definition, so the check failed for any channel under 2.5 tiles of
	# half width no matter how smooth the field was -- it fired on five
	# steps in this fixture, and not one of them is a seam. Measured, the
	# largest real step here is 0.96 tiles.
	var confluence := _confluence_field()
	var previous := INF
	for x in range(26, 40):
		var geometry: Dictionary = confluence.nearest_channel_geometry(x, 33)
		if geometry.is_empty():
			previous = INF
			continue
		var across: float = geometry["signed_across_tiles"]
		if previous != INF:
			assert_lte(
				absf(across - previous), 1.05,
				"jump at x=%d: %.2f -> %.2f tiles in one tile of travel" % [x, previous, across]
			)
		previous = across


func test_inside_the_main_river_the_main_decides_depth_and_width():
	# A tile inside the main channel right where the tributary enters
	# reads the main's discharge, not the tributary's.
	#
	# It reads the main AT THE JUNCTION. This used to compare against
	# (35, 24), the reach one cell BELOW the junction, which carries the
	# junction's water plus more of the column's own catchment and so is
	# legitimately larger -- a tile does not borrow its neighbour's
	# discharge, and asking it to was the test's error, not the field's.
	var confluence := _confluence_field()
	var probe: Dictionary = confluence.probe(34, 34, 0.6)
	assert_eq(probe["kind"], "river")
	var main: Dictionary = confluence.nearest_channel_geometry(35, 34)
	var tributary: Dictionary = confluence.nearest_channel_geometry(25, 34)
	assert_almost_eq(probe["discharge"], main["discharge"], 1e-6)
	assert_gt(
		float(probe["discharge"]), float(tributary["discharge"]) * 3.0,
		"the main's water, not the tributary's"
	)


## "Only around bends and where the water is deeper at the edge": traced
## with a real line-probe to a mismatch between two independently-tuned
## constants. HydrologyField's own channel-geometry reach must cover
## every tile EarthChunkManager's painter ever asks about (its bank apron
## plus its shore bleed), or the geometry query reports "no channel here"
## for a band the painter is still painting, and the generator falls back
## to an unrelated, possibly-distant curated river -- a garbage texel that
## bilinearly tears the strokes at exactly that boundary.
func test_the_geometry_reach_covers_the_painters_full_bleed():
	var painter_reach := RiverCatalog.RIVER_BANK_APRON_TILES + RiverFlowShader.SHORE_BLEED_TILES
	assert_gte(
		HydrologyField.VALLEY_HALF_WIDTH_TILES, painter_reach,
		"the geometry query must still answer everywhere the painter still paints"
	)


## The real regression, reproduced directly: a tile just past the OLD
## (3.0) reach but within the painter's actual bleed must still get a
## real channel answer, not an empty one.
func test_a_tile_just_past_the_old_reach_still_gets_real_channel_geometry():
	var beyond_old_reach := int(ceil(field.width_tiles_for_discharge(TEST_MIN_DISCHARGE) / 2.0 + 3.1))
	var geometry: Dictionary = field.nearest_channel_geometry(35 + beyond_old_reach, 14)
	assert_false(geometry.is_empty(), "the old 3.0 reach cut off a tile the painter's bleed still reaches")


func test_the_spring_is_narrower_than_the_thinnest_river():
	assert_lt(HydrologyField.SPRING_HALF_WIDTH_TILES, HydrologyField.MIN_LEGIBLE_WIDTH_TILES / 2.0)


func test_a_right_angle_corner_is_rounded_not_cut():
	# A cell whose upstream lies north and downstream lies east: the curve
	# from the north midpoint to the east midpoint must bend AROUND the
	# cell centre, never pass through it, and keep its endpoints exact.
	var north := Vector2(0.0, -5.0)
	var center := Vector2(0.0, 0.0)
	var east := Vector2(5.0, 0.0)
	var curve := HydrologyField.centerline_curve(north, center, east, HydrologyField.CURVE_SEGMENTS)
	assert_eq(curve[0], north)
	assert_eq(curve[curve.size() - 1], east)
	var nearest_to_corner := INF
	for point in curve:
		nearest_to_corner = minf(nearest_to_corner, point.distance_to(center))
	assert_gt(nearest_to_corner, 1.0, "the corner is cut off, not visited")
	# And the turn is gradual: no two consecutive pieces differ by more
	# than a few degrees, so the across field the strokes are contours of
	# has no joint a tile could see (the zig-zag artefact).
	assert_gte(HydrologyField.CURVE_SEGMENTS, 20)
	for i in range(1, curve.size() - 1):
		var a := (curve[i] - curve[i - 1]).normalized()
		var b := (curve[i + 1] - curve[i]).normalized()
		assert_lt(absf(a.angle_to(b)), deg_to_rad(6.0))


## --- lakes as a shoreline field (the same across the river bank uses) ---


func test_a_lake_bed_reads_as_deep_water_in_the_across_field():
	assert_eq(field.probe(35, 45, 0.3)["lake_across"], 0.0)


func test_the_waterline_is_the_half_coverage_contour():
	assert_almost_eq(HydrologyField.shore_across(0.5), 1.0, 1e-9)
	assert_eq(HydrologyField.shore_across(1.0), 0.0, "fully surrounded by water is the deep ceiling")
	assert_eq(HydrologyField.shore_across(0.0), HydrologyField.LAKE_ACROSS_DRY)
	assert_lt(HydrologyField.shore_across(0.6), 1.0)
	assert_gt(HydrologyField.shore_across(0.4), 1.0)


func test_a_lake_footprint_is_rounded_not_cut_square():
	# The crater is a 3x3 block of cells. Under the shoreline kernel its
	# corner is outside the waterline while the middle of a side, the same
	# distance from the nearest cell centre, is inside: the level set of a
	# blurred square is a rounded blob ("circle-ish, not a folded snake").
	assert_eq(field.probe(21, 44, 0.3)["kind"], "lake", "middle of the west side")
	assert_eq(field.probe(20, 29, 0.3)["kind"], "", "the north-west corner")
	var side_coverage: float = field.water_coverage(21, 44)["lake"]
	var corner_coverage: float = field.water_coverage(20, 29)["lake"]
	assert_gt(side_coverage, 0.5)
	assert_lt(corner_coverage, 0.5)


func test_a_tile_inside_the_footprint_above_the_spill_still_has_water_to_swim():
	var probe: Dictionary = field.probe(35, 45, 0.65)
	assert_eq(probe["kind"], "lake")
	assert_almost_eq(probe["depth_m"], HydrologyField.LAKE_MIN_DEPTH_M, 1e-6)


func test_the_sea_is_the_half_coverage_contour_of_the_baked_sea_cells():
	# Row 0 is sea. A tile just past the row boundary is mostly surrounded
	# by sea cells; a tile a third of the way into row 1 is not.
	assert_true(field.probe(35, 9, 0.2)["sea"])
	assert_false(field.probe(35, 12, 0.6)["sea"])
	assert_lt(field.probe(35, 9, 0.2)["lake_across"], 1.0)
	assert_gt(field.probe(35, 12, 0.6)["lake_across"], 1.0)


func test_a_river_mouth_runs_on_into_the_sea_and_fades():
	# The crater's outlet empties into sea cell (3,0), whose centre is at
	# tile (35, 4.9); the current is strongest at the mouth and gone twenty
	# tiles out, always running north (the outlet's own direction).
	var near_mouth: Dictionary = field.probe(35, 2, 0.2)
	assert_true(near_mouth["sea"])
	assert_gt(near_mouth["plume_factor"], 0.8)
	assert_almost_eq(near_mouth["plume_bearing_deg"], 0.0, 1e-6)
	assert_eq(field.probe(65, 45, 0.8)["plume_factor"], 0.0, "dry ground carries no plume")


func test_far_from_any_water_the_across_field_is_dry():
	assert_eq(field.probe(65, 15, 0.8)["lake_across"], HydrologyField.LAKE_ACROSS_DRY)
	assert_false(field.probe(65, 15, 0.8)["sea"])


## The map FILTER reads past the last painted cell: bilinear one texel,
## the cubic reconstruction two. A texel there that came from the far
## curated fallback carries an arbitrary SIGN, and the interpolation
## between a real +6 and a fallback -16 crosses zero inside the painted
## cell beside it -- the shader draws a hairline of water along the whole
## reach boundary (found live at the Loire: thin phantom channels running
## parallel to the river, several tiles out, on the world but never on
## the minimap). So the geometry reach must cover the filter's support
## past the bleed, not just the bleed.
func test_the_geometry_reach_covers_the_map_filters_neighbours_of_the_bleed():
	var painter_reach := RiverCatalog.RIVER_BANK_APRON_TILES + RiverFlowShader.SHORE_BLEED_TILES
	assert_gte(
		HydrologyField.GEOMETRY_REACH_TILES, painter_reach + HydrologyField.MAP_FILTER_SUPPORT_TILES,
		"the geometry query must still answer wherever the map filter reads a painted cell's neighbour"
	)
	assert_gte(HydrologyField.MAP_FILTER_SUPPORT_TILES, 2.0, "the cubic reconstruction reads two texels out")


## Reproduced directly: a tile one and a half texels past the painter's
## bleed still gets a real channel answer on the channel's own side, never
## the empty answer that hands the texel to the far fallback.
func test_a_tile_past_the_bleed_still_gets_real_channel_geometry_on_the_same_side():
	var half_width := field.width_tiles_for_discharge(TEST_MIN_DISCHARGE) / 2.0
	var bleed := half_width + RiverCatalog.RIVER_BANK_APRON_TILES + RiverFlowShader.SHORE_BLEED_TILES
	var at_bleed: Dictionary = field.nearest_channel_geometry(35 + int(floor(bleed)), 14)
	var past_bleed: Dictionary = field.nearest_channel_geometry(35 + int(ceil(bleed + 1.5)), 14)
	assert_false(at_bleed.is_empty(), "precondition: the bleed itself is covered")
	assert_false(past_bleed.is_empty(), "the filter's neighbour past the bleed must still see the channel")
	assert_eq(
		signf(past_bleed["signed_across_tiles"]), signf(at_bleed["signed_across_tiles"]),
		"the neighbour must sit on the same side as the painted cell -- no zero crossing between them"
	)
