extends GutTest

## Per-pixel (flow-DIRECTION, flow-SPEED) data, not art -- see
## procedural_river_flow_sprite.gd and docs/concept/rivers.md. Speed added
## 2026-08-29 ("more natural water flow" -- flow speed used to be uniform
## everywhere).

const ProceduralRiverFlowSprite = preload("res://src/rendering/procedural_river_flow_sprite.gd")

var sprite: ProceduralRiverFlowSprite


func before_each():
	sprite = ProceduralRiverFlowSprite.new()


# -- direction binning --------------------------------------------------------

func test_direction_bin_for_wraps_at_360():
	assert_eq(ProceduralRiverFlowSprite.direction_bin_for(0.0), ProceduralRiverFlowSprite.direction_bin_for(360.0))


func test_direction_bin_for_covers_the_full_range():
	var bins := {}
	for i in 360:
		bins[ProceduralRiverFlowSprite.direction_bin_for(float(i))] = true
	assert_eq(bins.size(), ProceduralRiverFlowSprite.DIRECTION_BINS)


func test_angle_for_bin_round_trips_through_direction_bin_for():
	for bin in ProceduralRiverFlowSprite.DIRECTION_BINS:
		var angle := ProceduralRiverFlowSprite.angle_for_bin(bin)
		assert_eq(ProceduralRiverFlowSprite.direction_bin_for(angle), bin)


# -- baked image data -----------------------------------------------------

func test_generate_image_bakes_the_wrapped_phase_into_red():
	var image := sprite.generate_image(90.0, 0.25, 0.5)
	# 8-bit FORMAT_RGBA8 quantizes to 1/255 steps -- the same byte-precision
	# gotcha earth_elevation_source.gd documents, not a bug in the bake.
	assert_almost_eq(image.get_pixel(0, 0).r, 0.25, 0.005)


func test_generate_image_bakes_the_direction_as_a_unit_vector():
	# Due east: Godot 2D has +X east and +Y DOWN, so east is (1, 0),
	# encoded from [-1,1] into [0,1] as (1.0, 0.5).
	var east := sprite.generate_image(90.0, 0.0, 0.5).get_pixel(0, 0)
	assert_almost_eq(east.g, 1.0, 0.01)
	assert_almost_eq(east.b, 0.5, 0.01)
	var north := sprite.generate_image(0.0, 0.0, 0.5).get_pixel(0, 0)
	assert_almost_eq(north.g, 0.5, 0.01)
	assert_almost_eq(north.b, 0.0, 0.01)


func test_the_encoded_direction_decodes_back_to_a_unit_vector():
	for angle in [0.0, 45.0, 137.0, 250.0, 359.0]:
		var pixel := sprite.generate_image(angle, 0.0, 0.5).get_pixel(0, 0)
		var decoded := Vector2(pixel.g * 2.0 - 1.0, pixel.b * 2.0 - 1.0)
		assert_almost_eq(decoded.length(), 1.0, 0.02, "angle %f decoded to a non-unit vector" % angle)


func test_generate_image_is_uniform_across_the_whole_tile():
	var image := sprite.generate_image(200.0, 0.25, 0.5)
	var corner := image.get_pixel(0, 0)
	var center := image.get_pixel(ProceduralRiverFlowSprite.SIZE / 2, ProceduralRiverFlowSprite.SIZE / 2)
	assert_eq(corner, center)


func test_generate_texture_returns_a_real_texture_of_the_right_size():
	var texture := sprite.generate_texture(45.0, 0.25, 0.5)
	assert_eq(texture.get_width(), ProceduralRiverFlowSprite.SIZE)
	assert_eq(texture.get_height(), ProceduralRiverFlowSprite.SIZE)


# -- phase binning ----------------------------------------------------------

func test_phase_bins_cover_the_whole_cycle():
	var bins := {}
	for step in 200:
		bins[ProceduralRiverFlowSprite.phase_bin_for(float(step) / 200.0)] = true
	assert_eq(bins.size(), ProceduralRiverFlowSprite.PHASE_BINS)


func test_phase_bin_wraps_at_one_full_cycle():
	assert_eq(
		ProceduralRiverFlowSprite.phase_bin_for(0.0), ProceduralRiverFlowSprite.phase_bin_for(1.0)
	)


func test_phase_for_bin_round_trips():
	for bin in ProceduralRiverFlowSprite.PHASE_BINS:
		assert_eq(
			ProceduralRiverFlowSprite.phase_bin_for(ProceduralRiverFlowSprite.phase_for_bin(bin)), bin
		)


# -- style packing ----------------------------------------------------------
#
# The two coarse per-cell style values share ONE atlas dimension and ONE
# channel. They must survive the round trip exactly, or a cell would render
# with another cell's cross-section band or speed.

func test_every_style_combination_round_trips_through_the_alpha_channel():
	for band in ProceduralRiverFlowSprite.DEPTH_BANDS:
		for fast in [false, true]:
			var index := ProceduralRiverFlowSprite.style_index_for(band, fast)
			var alpha := ProceduralRiverFlowSprite.alpha_for_style(index)
			assert_eq(ProceduralRiverFlowSprite.unpack_depth_band(alpha), band)
			assert_eq(ProceduralRiverFlowSprite.unpack_is_fast(alpha), fast)


## And it must survive the 8-BIT quantisation an actual baked tile applies,
## not merely the float round trip -- that is where a naive packing breaks.
func test_the_style_survives_real_eight_bit_quantisation():
	for style_index in ProceduralRiverFlowSprite.PACKED_LEVELS:
		var alpha := ProceduralRiverFlowSprite.alpha_for_style(style_index)
		var baked := sprite.generate_image(0.0, 0.0, alpha).get_pixel(0, 0).a
		assert_eq(
			ProceduralRiverFlowSprite.unpack_combined(baked), style_index,
			"style %d did not survive being baked into 8 bits" % style_index
		)


func test_every_style_index_is_unique():
	var seen := {}
	for band in ProceduralRiverFlowSprite.DEPTH_BANDS:
		for fast in [false, true]:
			var index := ProceduralRiverFlowSprite.style_index_for(band, fast)
			assert_false(seen.has(index), "style index collision at %d" % index)
			seen[index] = true
	assert_eq(seen.size(), ProceduralRiverFlowSprite.PACKED_LEVELS)


## Five bands is what draws a channel's cross-section; three was too coarse
## to describe a shape across a four-tile river.
func test_there_are_enough_bands_to_draw_a_cross_section():
	assert_gte(ProceduralRiverFlowSprite.DEPTH_BANDS, 5)


# -- atlas packing ----------------------------------------------------------

func test_every_binned_combination_gets_a_unique_atlas_cell():
	var seen := {}
	for style_index in ProceduralRiverFlowSprite.PACKED_LEVELS:
		for phase_bin in ProceduralRiverFlowSprite.PHASE_BINS:
			for direction_bin in ProceduralRiverFlowSprite.DIRECTION_BINS:
				var cell := ProceduralRiverFlowSprite.atlas_cell_for_index(
					ProceduralRiverFlowSprite.atlas_index_for(phase_bin, direction_bin, style_index)
				)
				assert_false(seen.has(cell), "atlas cell collision at %s" % cell)
				seen[cell] = true
	assert_eq(seen.size(), ProceduralRiverFlowSprite.total_tiles())


## A single-row atlas of this many tiles would be 73,728 px wide, vastly
## past the 16,384 GL_MAX_TEXTURE_SIZE common on the integrated GPUs this
## game targets -- it would simply fail to upload.
func test_the_atlas_stays_within_a_safe_texture_width():
	assert_lte(ProceduralRiverFlowSprite.ATLAS_COLUMNS * 32, 4096)
