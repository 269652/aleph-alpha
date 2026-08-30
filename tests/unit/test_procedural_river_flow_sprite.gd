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


# -- speed binning --------------------------------------------------------

func test_speed_bin_for_slowest_fraction_is_the_first_bin():
	assert_eq(ProceduralRiverFlowSprite.speed_bin_for(0.0), 0)


func test_speed_bin_for_fastest_fraction_is_the_last_bin():
	assert_eq(ProceduralRiverFlowSprite.speed_bin_for(1.0), ProceduralRiverFlowSprite.SPEED_BINS - 1)


func test_speed_bin_for_increases_monotonically():
	var previous := -1
	for step in 10:
		var fraction := float(step) / 9.0
		var bin := ProceduralRiverFlowSprite.speed_bin_for(fraction)
		assert_gte(bin, previous)
		previous = bin


func test_speed_bin_for_clamps_beyond_the_unit_range():
	assert_eq(ProceduralRiverFlowSprite.speed_bin_for(5.0), ProceduralRiverFlowSprite.SPEED_BINS - 1)
	assert_eq(ProceduralRiverFlowSprite.speed_bin_for(-5.0), 0)


func test_speed_for_bin_round_trips_back_into_the_same_bin():
	for bin in ProceduralRiverFlowSprite.SPEED_BINS:
		var fraction := ProceduralRiverFlowSprite.speed_for_bin(bin)
		assert_eq(ProceduralRiverFlowSprite.speed_bin_for(fraction), bin)


# -- baked image data -----------------------------------------------------
#
# Channel layout changed with the phase-field rewrite (see
# procedural_river_flow_sprite.gd): R is now the continuous course phase,
# G/B are the flow direction as a unit VECTOR (not a bearing -- which saves
# the shader a radians/sin/cos and removes the 0/360 wrap hazard), and A is
# the speed fraction.

func test_generate_image_bakes_the_wrapped_phase_into_red():
	var image := sprite.generate_image(90.0, 0.5, 0.25)
	# 8-bit FORMAT_RGBA8 quantizes to 1/255 steps (~0.0039) -- the same
	# byte-precision gotcha earth_elevation_source.gd's own doc comment
	# documents, not a bug in the bake itself.
	assert_almost_eq(image.get_pixel(0, 0).r, 0.25, 0.005)


func test_generate_image_bakes_the_direction_as_a_unit_vector():
	# Due east: Godot 2D has +X east and +Y DOWN, so east is (1, 0),
	# encoded from [-1,1] into [0,1] as (1.0, 0.5).
	var east := sprite.generate_image(90.0, 0.5, 0.0).get_pixel(0, 0)
	assert_almost_eq(east.g, 1.0, 0.01)
	assert_almost_eq(east.b, 0.5, 0.01)
	# Due north is -Y, i.e. (0, -1) -> (0.5, 0.0).
	var north := sprite.generate_image(0.0, 0.5, 0.0).get_pixel(0, 0)
	assert_almost_eq(north.g, 0.5, 0.01)
	assert_almost_eq(north.b, 0.0, 0.01)


## The encoded direction must survive the round trip back through the
## [-1,1] mapping as a real unit vector -- that is what the shader
## normalizes and projects along.
func test_the_encoded_direction_decodes_back_to_a_unit_vector():
	for angle in [0.0, 45.0, 137.0, 250.0, 359.0]:
		var pixel := sprite.generate_image(angle, 0.5, 0.0).get_pixel(0, 0)
		var decoded := Vector2(pixel.g * 2.0 - 1.0, pixel.b * 2.0 - 1.0)
		assert_almost_eq(decoded.length(), 1.0, 0.02, "angle %f decoded to a non-unit vector" % angle)


func test_generate_image_bakes_the_speed_fraction_into_alpha():
	var slow := sprite.generate_image(0.0, 0.0, 0.25)
	var fast := sprite.generate_image(0.0, 1.0, 0.25)
	assert_lt(slow.get_pixel(0, 0).a, fast.get_pixel(0, 0).a)


func test_generate_image_is_uniform_across_the_whole_tile():
	var image := sprite.generate_image(200.0, 0.7, 0.25)
	var corner := image.get_pixel(0, 0)
	var center := image.get_pixel(ProceduralRiverFlowSprite.SIZE / 2, ProceduralRiverFlowSprite.SIZE / 2)
	assert_eq(corner, center)


func test_generate_texture_returns_a_real_texture_of_the_right_size():
	var texture := sprite.generate_texture(45.0, 0.3, 0.25)
	assert_eq(texture.get_width(), ProceduralRiverFlowSprite.SIZE)
	assert_eq(texture.get_height(), ProceduralRiverFlowSprite.SIZE)


# -- phase binning + atlas packing -----------------------------------------

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


## Every (phase, direction, speed) combination must map to its OWN atlas
## cell -- a collision would silently draw one reach with another's data.
func test_every_binned_combination_gets_a_unique_atlas_cell():
	var seen := {}
	for speed_bin in ProceduralRiverFlowSprite.SPEED_BINS:
		for phase_bin in ProceduralRiverFlowSprite.PHASE_BINS:
			for direction_bin in ProceduralRiverFlowSprite.DIRECTION_BINS:
				var cell := ProceduralRiverFlowSprite.atlas_cell_for_index(
					ProceduralRiverFlowSprite.atlas_index_for(phase_bin, direction_bin, speed_bin)
				)
				assert_false(seen.has(cell), "atlas cell collision at %s" % cell)
				seen[cell] = true
	assert_eq(seen.size(), ProceduralRiverFlowSprite.total_tiles())


## A single-row atlas of this many tiles would be 768 * 32 = 24,576 px
## wide, past the 16,384 GL_MAX_TEXTURE_SIZE common on the integrated GPUs
## this game targets -- it would simply fail to upload. The 2D grid exists
## for that reason, so the row width must stay well inside the limit.
func test_the_atlas_stays_within_a_safe_texture_width():
	assert_lte(ProceduralRiverFlowSprite.ATLAS_COLUMNS * 32, 4096)
