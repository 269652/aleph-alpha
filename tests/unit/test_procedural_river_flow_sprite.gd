extends GutTest

## Per-tile (flow-DIRECTION, signed ACROSS-offset, fast flag) data, not art
## -- see procedural_river_flow_sprite.gd and docs/concept/rivers.md.
##
## The across dimension is what killed the "individual squares": the shader
## reconstructs every FRAGMENT's own distance to the centreline from the
## tile centre's baked signed offset plus the within-tile delta, so the
## cross-section shades continuously through tiles and the water clips at
## the real bank curve instead of the tile grid.

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

func test_generate_image_bakes_the_direction_as_a_unit_vector():
	# Due east: Godot 2D has +X east and +Y DOWN, so east is (1, 0),
	# encoded from [-1,1] into [0,1] as (1.0, 0.5).
	var east := sprite.generate_image(90.0, 0.0, 0.25).get_pixel(0, 0)
	assert_almost_eq(east.g, 1.0, 0.01)
	assert_almost_eq(east.b, 0.5, 0.01)
	var north := sprite.generate_image(0.0, 0.0, 0.25).get_pixel(0, 0)
	assert_almost_eq(north.g, 0.5, 0.01)
	assert_almost_eq(north.b, 0.0, 0.01)


func test_the_encoded_direction_decodes_back_to_a_unit_vector():
	for angle in [0.0, 45.0, 137.0, 250.0, 359.0]:
		var pixel := sprite.generate_image(angle, 0.0, 0.25).get_pixel(0, 0)
		var decoded := Vector2(pixel.g * 2.0 - 1.0, pixel.b * 2.0 - 1.0)
		assert_almost_eq(decoded.length(), 1.0, 0.02, "angle %f decoded to a non-unit vector" % angle)


func test_generate_image_is_uniform_across_the_whole_tile():
	var image := sprite.generate_image(200.0, 0.3, 0.25)
	var corner := image.get_pixel(0, 0)
	var center := image.get_pixel(ProceduralRiverFlowSprite.SIZE / 2, ProceduralRiverFlowSprite.SIZE / 2)
	assert_eq(corner, center)


func test_generate_texture_returns_a_real_texture_of_the_right_size():
	var texture := sprite.generate_texture(45.0, 0.3, 0.25)
	assert_eq(texture.get_width(), ProceduralRiverFlowSprite.SIZE)
	assert_eq(texture.get_height(), ProceduralRiverFlowSprite.SIZE)


# -- across binning -----------------------------------------------------------
#
# The tile centre's SIGNED cross-channel offset, in half-widths: negative on
# one bank, positive on the other, |1| exactly at the bank line, out to
# ACROSS_RANGE so the painter's apron cells (just past the bank, where the
# smooth waterline runs) still carry real data.

func test_across_bins_cover_the_whole_signed_range():
	var bins := {}
	for step in 400:
		var fraction := lerpf(
			-ProceduralRiverFlowSprite.ACROSS_RANGE + 0.001,
			ProceduralRiverFlowSprite.ACROSS_RANGE - 0.001,
			float(step) / 399.0
		)
		bins[ProceduralRiverFlowSprite.across_bin_for(fraction)] = true
	assert_eq(bins.size(), ProceduralRiverFlowSprite.ACROSS_BINS)


func test_across_bin_round_trips_through_its_own_centre():
	for bin in ProceduralRiverFlowSprite.ACROSS_BINS:
		assert_eq(
			ProceduralRiverFlowSprite.across_bin_for(
				ProceduralRiverFlowSprite.fraction_for_bin(bin)
			),
			bin
		)


func test_across_bins_clamp_rather_than_wrap_outside_the_range():
	assert_eq(ProceduralRiverFlowSprite.across_bin_for(-99.0), 0)
	assert_eq(
		ProceduralRiverFlowSprite.across_bin_for(99.0),
		ProceduralRiverFlowSprite.ACROSS_BINS - 1
	)


## The quantisation step is the worst tile-to-tile seam the reconstruction
## can show -- it must stay well under what a full depth band used to jump.
func test_the_across_quantisation_step_is_small():
	var step := 2.0 * ProceduralRiverFlowSprite.ACROSS_RANGE / float(ProceduralRiverFlowSprite.ACROSS_BINS)
	assert_lte(step, 0.1, "across bins step %f of a half-width" % step)


## The encoded red channel must survive the real 8-bit bake for EVERY bin.
func test_every_across_bin_survives_eight_bit_quantisation():
	for bin in ProceduralRiverFlowSprite.ACROSS_BINS:
		var fraction := ProceduralRiverFlowSprite.fraction_for_bin(bin)
		var baked := sprite.generate_image(0.0, fraction, 0.25).get_pixel(0, 0).r
		var decoded := (baked * 2.0 - 1.0) * ProceduralRiverFlowSprite.ACROSS_RANGE
		# One full 8-bit step of slack, not half: Godot's float-to-byte
		# conversion truncates rather than rounds, measured here.
		var lsb := 2.0 * ProceduralRiverFlowSprite.ACROSS_RANGE / 255.0
		assert_almost_eq(
			decoded, fraction, lsb + 0.0001,
			"across bin %d did not survive being baked into 8 bits" % bin
		)


# -- fast-flag packing --------------------------------------------------------
#
# The alpha channel now carries ONLY the fast flag -- the depth band it used
# to pack is gone, replaced by the continuous per-fragment reconstruction.

func test_the_fast_flag_round_trips_through_the_alpha_channel():
	for fast in [false, true]:
		var alpha := ProceduralRiverFlowSprite.alpha_for_fast(fast)
		var baked := sprite.generate_image(0.0, 0.0, alpha).get_pixel(0, 0).a
		assert_eq(ProceduralRiverFlowSprite.unpack_is_fast(baked), fast)


# -- atlas packing ----------------------------------------------------------

func test_every_binned_combination_gets_a_unique_atlas_cell():
	var seen := {}
	for fast in ProceduralRiverFlowSprite.SPEED_LEVELS:
		for across_bin in ProceduralRiverFlowSprite.ACROSS_BINS:
			for direction_bin in ProceduralRiverFlowSprite.DIRECTION_BINS:
				var cell := ProceduralRiverFlowSprite.atlas_cell_for_index(
					ProceduralRiverFlowSprite.atlas_index_for(direction_bin, across_bin, fast)
				)
				assert_false(seen.has(cell), "atlas cell collision at %s" % cell)
				seen[cell] = true
	assert_eq(seen.size(), ProceduralRiverFlowSprite.total_tiles())


## The atlas is laid out as a grid rather than one row, and must stay inside
## the 16,384 GL_MAX_TEXTURE_SIZE common on the integrated GPUs this game
## targets -- a texture past that simply fails to upload.
func test_the_atlas_stays_within_a_safe_texture_width():
	assert_lte(ProceduralRiverFlowSprite.ATLAS_COLUMNS * 32, 4096)


## The atlas carries exactly the per-cell data the shader actually reads,
## and nothing more. A TileMapLayer cell can only select an atlas tile, so
## every dimension here multiplies the number of tiles that must be
## generated and uploaded -- a dimension the shader ignores is paid for in
## full and returns nothing (the lesson the removed phase dimension left).
func test_the_atlas_carries_direction_across_and_speed_and_nothing_else():
	assert_eq(
		ProceduralRiverFlowSprite.total_tiles(),
		ProceduralRiverFlowSprite.DIRECTION_BINS
			* ProceduralRiverFlowSprite.ACROSS_BINS
			* ProceduralRiverFlowSprite.SPEED_LEVELS
	)
