extends GutTest

## Footprints in snow: walking displaces it, and fresh snow fills the tracks
## back in (see docs/concept/snow_cover.md's "Footprints" section).
##
## Rewritten 2026-09-03 from a per-tile scalar to real, distance-spaced,
## facing-oriented marks. The tile version had one caller call `step_on`
## every rendered frame the player stood in snow rather than once per real
## stride, so a whole tile reached MAX_TREAD within three frames of first
## being entered however far the player then walked -- one crossing looked
## identical to a hundred, and the "displacement" was a flat scalar spread
## uniformly across an entire tile rather than anything shaped like a boot.
## `step` now mirrors `BloodTrail.step`'s own distance-gated shape: a mark is
## recorded only once real stride length has passed, and it carries a real
## world position and facing rather than a tile index.

const SnowTrail = preload("res://src/world/snow_trail.gd")
const Snowfall = preload("res://src/world/snowfall.gd")
const WeatherModel = preload("res://src/world/weather_model.gd")


# -- walking displaces it, once per real stride, not once per frame ---------

## The FIRST call places one mark right where you are standing -- you did
## not teleport there, so the ground under your very first tracked position
## already shows a print (see VISIBLE_TREAD). Standing there afterwards adds
## nothing further.
func test_standing_in_place_after_the_first_step_places_no_further_marks():
	var trail := SnowTrail.new()
	assert_true(trail.step(Vector2.ZERO, Vector2.DOWN, 0.1))
	assert_false(trail.step(Vector2.ZERO, Vector2.DOWN, 0.1))
	assert_eq(trail.tracked_mark_count(), 1, "standing still is not a second footstep")


## The whole reason this module was rewritten: the caller calls `step` every
## frame regardless of movement, so gating has to live HERE, not in how often
## the caller remembers to call it.
func test_a_second_mark_is_not_placed_until_a_real_stride_has_passed():
	var trail := SnowTrail.new()
	trail.step(Vector2.ZERO, Vector2.DOWN, 0.1)
	var short_of_a_stride := Vector2(SnowTrail.STRIDE_PX * 0.5, 0.0)
	assert_false(trail.step(short_of_a_stride, Vector2.DOWN, 0.1))
	assert_eq(trail.tracked_mark_count(), 1, "half a stride is not a second footstep")


func test_a_full_stride_places_a_mark():
	var trail := SnowTrail.new()
	trail.step(Vector2.ZERO, Vector2.DOWN, 0.1)
	var far := Vector2(SnowTrail.STRIDE_PX * 2.0, 0.0)
	assert_true(trail.step(far, Vector2.RIGHT, 0.1))
	assert_gt(trail.tread_at(far), 0.0)


func test_walking_displaces_snow():
	var trail := SnowTrail.new()
	assert_eq(trail.tread_at(Vector2(40.0, 40.0)), 0.0, "untrodden snow is untouched")
	trail.step(Vector2.ZERO, Vector2.DOWN, 0.1)
	trail.step(Vector2(0.0, SnowTrail.STRIDE_PX * 2.0), Vector2.DOWN, 0.1)
	assert_gt(trail.tread_at(Vector2(0.0, SnowTrail.STRIDE_PX * 2.0)), 0.0)


## Walking the same LINE repeatedly now deepens the trail by laying down
## many marks along it, not by any one mark exceeding MAX_TREAD -- real
## strides never land in the exact same spot twice, so the reinforcement is
## spatial (a continuous, wide path) rather than one saturating number.
func test_walking_the_same_line_repeatedly_widens_the_trodden_area():
	var trail := SnowTrail.new()
	var pos := Vector2.ZERO
	# A real stride is never a perfectly straight line -- a small, DETERMINISTIC
	# zig-zag rather than noise, so this test's own result never depends on
	# an unseeded RNG.
	for step in 6:
		var side := 1.0 if step % 2 == 0 else -1.0
		pos += Vector2(SnowTrail.STRIDE_PX * 1.1, side)
		trail.step(pos, Vector2.RIGHT, 0.1)
	assert_gt(trail.tracked_mark_count(), 1, "repeated walking should lay down more than one mark")


## Real repeated treading of the SAME spot -- standing and shuffling, or
## pacing a tight line -- has to actually deepen it, all the way to
## MAX_TREAD, not stop at whatever one single footstep's own mark is worth.
## This is the literal original complaint ("walking back and forth doesn't
## deepen it") and the OLD per-tile scalar got it right by simple
## accumulation; splitting into real oriented marks must not lose that for
## the case where marks genuinely do overlap.
func test_repeatedly_treading_the_same_spot_deepens_it_to_the_full_depth():
	var trail := SnowTrail.new()
	var pos := Vector2(200.0, 200.0)
	trail.step(pos, Vector2.DOWN, 0.1)
	var after_one := trail.tread_at(pos)
	assert_lt(after_one, SnowTrail.MAX_TREAD, "one step should not already be maximally deep")

	# Nudge by less than a stride each time -- SnowTrail.step's own gate only
	# controls whether a NEW mark is placed, not whether overlapping marks
	# already there combine; walk in place at sub-stride jitter to place
	# several marks squarely on top of one another.
	for i in 6:
		trail._has_last_position = false  # force each nudge to register as its own step
		trail.step(pos + Vector2(0.2, 0.0) * float(i % 2), Vector2.DOWN, 0.1)

	assert_almost_eq(
		trail.tread_at(pos), SnowTrail.MAX_TREAD, 0.001,
		"real repeated treading of one spot should reach the full depth, not one step's own cap"
	)


## Marks spaced along a real path do NOT combine at a point neither of them
## individually covers -- accumulation is real overlap, not every mark ever
## placed leaking into everywhere else.
func test_marks_far_apart_do_not_combine_where_neither_reaches():
	var trail := SnowTrail.new()
	trail.step(Vector2.ZERO, Vector2.DOWN, 0.1)
	trail.step(Vector2(0.0, SnowTrail.STRIDE_PX * 4.0), Vector2.DOWN, 0.1)
	var midpoint := Vector2(0.0, SnowTrail.STRIDE_PX * 2.0)
	assert_eq(trail.tread_at(midpoint), 0.0, "a point neither mark reaches should read untrodden")


## Snow only goes so flat: past a point one mark is trodden bare and further
## treading of that exact spot changes nothing.
func test_one_marks_tread_cannot_go_deeper_than_the_snow():
	var trail := SnowTrail.new()
	var pos := Vector2.ZERO
	for step in 50:
		trail.step(pos, Vector2.DOWN, 0.1)
		pos += Vector2(0.0, SnowTrail.STRIDE_PX * 2.0)
	for step in 50:
		assert_lte(trail.tread_at(Vector2(0.0, float(step) * SnowTrail.STRIDE_PX * 2.0)), 1.0)


func test_untrodden_ground_stays_untouched():
	var trail := SnowTrail.new()
	trail.step(Vector2.ZERO, Vector2.DOWN, 0.1)
	trail.step(Vector2(0.0, SnowTrail.STRIDE_PX * 2.0), Vector2.DOWN, 0.1)
	assert_eq(
		trail.tread_at(Vector2(500.0, 500.0)), 0.0,
		"ground nowhere near a footstep should read as untrodden"
	)


# -- a mark is a place AND a facing -------------------------------------------

## A mark's shape is oriented along the facing it was placed with -- so a
## point directly ahead of/behind the step reads deeper than a point off to
## its SIDE at the same distance, which is what "facing" actually buys.
func test_a_marks_shape_is_oriented_along_its_facing():
	var trail := SnowTrail.new()
	trail.step(Vector2.ZERO, Vector2.DOWN, 0.1)
	trail.step(Vector2(0.0, SnowTrail.STRIDE_PX * 2.0), Vector2.DOWN, 0.1)
	var mark_at := Vector2(0.0, SnowTrail.STRIDE_PX * 2.0)
	var ahead := mark_at + Vector2(0.0, SnowTrail.FOOT_HALF_LENGTH_PX * 0.8)
	var to_the_side := mark_at + Vector2(SnowTrail.FOOT_HALF_LENGTH_PX * 0.8, 0.0)
	assert_gt(
		trail.tread_at(ahead), trail.tread_at(to_the_side),
		"a mark facing down should extend further ahead/behind than to its side"
	)


## Real displacement, not a stencil: the value tapers away from the mark's
## own centreline rather than being flat everywhere inside its shape.
func test_a_marks_value_is_graded_not_flat():
	var trail := SnowTrail.new()
	trail.step(Vector2.ZERO, Vector2.DOWN, 0.1)
	var centre := Vector2.ZERO
	var edge := Vector2(SnowTrail.FOOT_RADIUS_PX * 0.9, 0.0)
	assert_gt(trail.tread_at(centre), trail.tread_at(edge))


## The mark's own size is a real, tested floor -- large enough to actually
## show as an oriented mark at MASK_TEXELS_PER_TILE resolution, the same
## "big enough to read, not the true sub-pixel anatomical size" reasoning
## VISIBLE_TREAD and (elsewhere) WORKER_WORLD_WIDTH_PX are pinned by.
func test_a_footprint_mark_is_bigger_than_one_mask_texel():
	var texel_size := float(SnowTrail.TILE_SIZE_PX) / float(SnowTrail.MASK_TEXELS_PER_TILE)
	assert_gt(SnowTrail.FOOT_HALF_LENGTH_PX * 2.0, texel_size)


## A mark narrower than this can fall entirely between two texel CENTRES
## depending on exactly where it lands (the mark's own world position is
## never guaranteed to avoid the single worst-case grid corner), which would
## make a footstep render or not render depending on alignment nobody
## controls -- an intermittent bug, not a visual choice. Pins the
## RELATIONSHIP (FOOT_RADIUS_PX vs. the grid it is rasterized onto), not
## just today's literal value.
func test_a_footprint_radius_clears_the_texel_grid_floor():
	assert_gt(SnowTrail.FOOT_RADIUS_PX, SnowTrail.min_radius_for_texel_grid())


# -- snow fills the tracks in ------------------------------------------------

func test_fresh_snow_fills_the_tracks_in():
	var trail := SnowTrail.new()
	trail.step(Vector2.ZERO, Vector2.DOWN, 0.1)
	var deep := trail.tread_at(Vector2.ZERO)
	trail.advance(SnowTrail.SECONDS_TO_FILL * 0.5, true)
	assert_lt(trail.tread_at(Vector2.ZERO), deep)


func test_tracks_do_not_fade_on_their_own():
	var trail := SnowTrail.new()
	trail.step(Vector2.ZERO, Vector2.DOWN, 0.1)
	var made := trail.tread_at(Vector2.ZERO)
	trail.advance(SnowTrail.SECONDS_TO_FILL * 4.0, false)
	assert_almost_eq(
		trail.tread_at(Vector2.ZERO), made, 0.001,
		"a track should last until it snows again"
	)


func test_a_snowfall_fills_its_tracks_before_it_ends():
	assert_lt(
		SnowTrail.SECONDS_TO_FILL, WeatherModel.WEATHER_PERIOD_SECONDS,
		"a snowfall must be able to fill its tracks within one spell"
	)
	assert_lt(
		SnowTrail.SECONDS_TO_FILL, Snowfall.SECONDS_TO_COVER,
		"a footprint should drift full faster than a whole field is buried"
	)


func test_a_spell_of_snow_erases_a_walked_trail():
	var trail := SnowTrail.new()
	trail.step(Vector2.ZERO, Vector2.DOWN, 0.1)
	var elapsed := 0.0
	while elapsed < WeatherModel.WEATHER_PERIOD_SECONDS:
		trail.advance(10.0, true)
		elapsed += 10.0
	assert_eq(trail.tread_at(Vector2.ZERO), 0.0, "a spell of snow should bury a trail")


## A filled-in mark is forgotten rather than kept at zero forever -- otherwise
## a long walk leaves the world remembering every step ever taken.
func test_filled_marks_are_forgotten():
	var trail := SnowTrail.new()
	var pos := Vector2.ZERO
	for step in 20:
		trail.step(pos, Vector2.DOWN, 0.1)
		pos += Vector2(0.0, SnowTrail.STRIDE_PX * 2.0)
	assert_gt(trail.tracked_mark_count(), 0)
	trail.advance(SnowTrail.SECONDS_TO_FILL * 5.0, true)
	assert_eq(trail.tracked_mark_count(), 0, "the world should not remember erased marks")


## A very long, snow-free walk must not accumulate marks without bound --
## nothing erases them without a snowfall, so something else has to.
func test_a_very_long_walk_does_not_grow_the_mark_list_forever():
	var trail := SnowTrail.new()
	var pos := Vector2.ZERO
	for step in SnowTrail.MAX_TRACKED_MARKS * 3:
		trail.step(pos, Vector2.DOWN, 0.1)
		pos += Vector2(0.0, SnowTrail.STRIDE_PX * 2.0)
	assert_lte(trail.tracked_mark_count(), SnowTrail.MAX_TRACKED_MARKS)


# -- what it is for ----------------------------------------------------------

func test_a_single_footprint_is_already_visible():
	var trail := SnowTrail.new()
	trail.step(Vector2.ZERO, Vector2.DOWN, 0.1)
	assert_gte(
		trail.tread_at(Vector2.ZERO), SnowTrail.VISIBLE_TREAD,
		"one step should already show"
	)


# -- the GPU trail mask -------------------------------------------------------
#
# SnowBombShader.set_trail_mask wants a real R8 Texture2D window in WORLD
# pixels -- build_mask_texture is the bridge: a small window centred on the
# player's own WORLD POSITION (not a tile any more -- marks are continuous),
# read back as an Image so these tests can assert real pixel values rather
# than trust the GPU. The window now packs MASK_TEXELS_PER_TILE texels per
# game tile, not one -- a single texel per tile is exactly the resolution
# that made an oriented mark impossible to express at all.

func test_mask_texture_is_the_requested_size_in_texels():
	var trail := SnowTrail.new()
	var texture := trail.build_mask_texture(Vector2.ZERO, 8)
	var expected := 8 * SnowTrail.MASK_TEXELS_PER_TILE
	assert_eq(texture.get_width(), expected)
	assert_eq(texture.get_height(), expected)


func test_an_untrodden_window_is_all_zero():
	var trail := SnowTrail.new()
	var image := trail.build_mask_texture(Vector2.ZERO, 8).get_image()
	for y in image.get_height():
		for x in image.get_width():
			assert_eq(image.get_pixel(x, y).r, 0.0, "untrodden ground should read as untrodden")


## Finds the brightest texel within `radius` texels of (cx, cy) -- a mark's
## own radius is deliberately small relative to one texel step (see
## FOOT_RADIUS_PX's own doc comment), so which EXACT texel a mark's centre
## lands on is a texel-quantization detail, not something these tests should
## pin. What has to be true is that the mark shows up close to where it was
## placed, not that it lands on one predicted-in-advance texel index.
func _brightest_near(image: Image, cx: int, cy: int, radius: int) -> float:
	var best := 0.0
	for y in range(maxi(0, cy - radius), mini(image.get_height(), cy + radius + 1)):
		for x in range(maxi(0, cx - radius), mini(image.get_width(), cx + radius + 1)):
			best = maxf(best, image.get_pixel(x, y).r)
	return best


## The window is centred ON the given world position -- so a mark placed at
## the centre position itself must land somewhere near the image's own
## centre texel.
func test_the_window_is_centred_on_the_given_position():
	var trail := SnowTrail.new()
	trail.step(Vector2(100.0, 100.0), Vector2.DOWN, 0.1)
	var image := trail.build_mask_texture(Vector2(100.0, 100.0), 8).get_image()
	var centre := image.get_width() / 2
	assert_gt(
		_brightest_near(image, centre, centre, 2), 0.0,
		"a mark at the window's own centre position should land near its centre texel"
	)


## A mark off-centre still lands at its own real offset, not just the centre
## -- otherwise every footprint would draw in the same place.
func test_a_marks_lands_at_its_real_offset():
	var trail := SnowTrail.new()
	var window_world_px := float(8 * SnowTrail.TILE_SIZE_PX)
	var offset := Vector2(window_world_px * 0.25, 0.0)
	trail.step(offset, Vector2.RIGHT, 0.1)
	var image := trail.build_mask_texture(Vector2.ZERO, 8).get_image()
	var texel_size := float(SnowTrail.TILE_SIZE_PX) / float(SnowTrail.MASK_TEXELS_PER_TILE)
	var texels := 8 * SnowTrail.MASK_TEXELS_PER_TILE
	var expected_x := int(texels / 2 + offset.x / texel_size)
	assert_gt(_brightest_near(image, expected_x, texels / 2, 2), 0.0)


## A mark far outside the window must not crash and must not bleed onto an
## in-window pixel via wraparound indexing.
func test_a_mark_outside_the_window_does_not_appear_or_crash():
	var trail := SnowTrail.new()
	trail.step(Vector2(100000.0, 100000.0), Vector2.DOWN, 0.1)
	var image := trail.build_mask_texture(Vector2.ZERO, 8).get_image()
	for y in image.get_height():
		for x in image.get_width():
			assert_eq(image.get_pixel(x, y).r, 0.0, "a far-off mark should not appear in this window")


## Real tread values must survive being packed into an 8-bit channel and read
## back, within one texel step -- not just "something nonzero".
## The mask is a real sample of the SAME continuous field `tread_at` answers
## point queries against -- not compared at the mark's own un-quantized
## peak (a graded shape sampled onto a texel grid is never exactly equal to
## its own peak value unless a texel happens to land exactly on it, which is
## a coincidence of alignment, not a property this module should promise).
## Instead: pick the texel nearest the mark, ask `tread_at` for exactly the
## world point THAT texel represents, and require the two to agree -- they
## are the same math (`_mark_value_at`) reached two different ways, so they
## must never disagree.
func test_mask_values_track_the_real_tread_field_not_just_presence():
	var trail := SnowTrail.new()
	# Deliberately off-grid: a real footstep is never at a round number.
	var mark_position := Vector2(37.0, -19.0)
	trail.step(mark_position, Vector2.DOWN, 0.1)

	var window_centre := Vector2(32.0, -16.0)
	var window_tiles := 4
	var image := trail.build_mask_texture(window_centre, window_tiles).get_image()
	var texel_size := float(SnowTrail.TILE_SIZE_PX) / float(SnowTrail.MASK_TEXELS_PER_TILE)
	var texels := window_tiles * SnowTrail.MASK_TEXELS_PER_TILE
	var origin := window_centre - Vector2(texels, texels) * texel_size * 0.5

	# The texel nearest the actual mark position.
	var tx := clampi(int((mark_position.x - origin.x) / texel_size), 0, texels - 1)
	var ty := clampi(int((mark_position.y - origin.y) / texel_size), 0, texels - 1)
	var texel_world_point := origin + Vector2(tx + 0.5, ty + 0.5) * texel_size

	assert_gt(image.get_pixel(tx, ty).r, 0.0, "the mark should reach the texel nearest it")
	assert_almost_eq(
		image.get_pixel(tx, ty).r, trail.tread_at(texel_world_point), 1.0 / 255.0,
		"the mask must sample the same field tread_at answers, not a different one"
	)
