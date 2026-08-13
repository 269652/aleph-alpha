extends GutTest

## Small bird pixel art, shared by ambient songbirds and the fish-eating
## kingfisher (see docs/concept/ecosystem_dynamics.md's Species roster).
## Same "one shared shape, per-species color variants" approach as
## ProceduralFishSprite.

const ProceduralBirdSprite = preload("res://src/rendering/procedural_bird_sprite.gd")

var generator := ProceduralBirdSprite.new()


func test_image_has_the_expected_size():
	var image := generator.generate_image("sparrow", 0)
	assert_eq(image.get_width(), ProceduralBirdSprite.SIZE.x)
	assert_eq(image.get_height(), ProceduralBirdSprite.SIZE.y)


func test_has_transparent_corners_and_an_opaque_body():
	var image := generator.generate_image("sparrow", 0)
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	var mid := Vector2i(ProceduralBirdSprite.SIZE.x / 2, ProceduralBirdSprite.SIZE.y / 2)
	assert_gt(image.get_pixel(mid.x, mid.y).a, 0.0)


func test_is_deterministic_for_the_same_species_and_seed():
	var a := generator.generate_image("robin", 5)
	var b := generator.generate_image("robin", 5)
	assert_eq(a.get_data(), b.get_data())


func test_every_known_species_has_a_distinct_base_color():
	var seen_colors := {}
	for species in ProceduralBirdSprite.SPECIES_IDS:
		seen_colors[ProceduralBirdSprite.SPECIES_BASE_COLORS[species]] = true
	assert_eq(
		seen_colors.size(), ProceduralBirdSprite.SPECIES_IDS.size(),
		"every species should have a unique base color"
	)


## Unlike butterflies (genuinely vivid in life), real songbirds like sparrows
## are drab -- forcing every species to be "vividly saturated" would be
## unrealistic. Only the kingfisher (a real fish-eating bird with famously
## vivid blue/orange plumage) is required to be vivid.
func test_kingfisher_is_vividly_saturated():
	var color: Color = ProceduralBirdSprite.SPECIES_BASE_COLORS["kingfisher"]
	assert_gt(color.s, 0.4, "kingfisher should read as vividly colored, matching real kingfisher plumage")


func test_different_species_render_different_images():
	var a := generator.generate_image("sparrow", 0)
	var b := generator.generate_image("robin", 0)
	assert_ne(a.get_data(), b.get_data())


func test_unknown_species_falls_back_to_a_valid_image_rather_than_crashing():
	var image := generator.generate_image("not_a_real_bird", 0)
	assert_eq(image.get_width(), ProceduralBirdSprite.SIZE.x)


func test_generate_texture_returns_an_image_texture():
	var texture := generator.generate_texture("kingfisher", 3)
	assert_eq(texture.get_width(), ProceduralBirdSprite.SIZE.x)


# -- wing flap frames -------------------------------------------------------
#
# Birds were built as a single static sprite, so they glided across the sky
# with their wings frozen. A bird banks slowly but FLAPS FAST, so the wings
# are the one part that must animate.

func test_a_flap_cycle_has_several_distinct_frames():
	var frames := generator.generate_flap_images("sparrow", 3)
	assert_eq(frames.size(), ProceduralBirdSprite.FLAP_FRAME_COUNT)
	var distinct := {}
	for frame in frames:
		distinct[frame.get_data()] = true
	assert_gte(distinct.size(), 3, "a flap needs genuinely different wing positions")


func test_flap_frames_all_match_the_sprite_size():
	for frame in generator.generate_flap_images("robin", 1):
		assert_eq(frame.get_width(), ProceduralBirdSprite.SIZE.x)
		assert_eq(frame.get_height(), ProceduralBirdSprite.SIZE.y)


## The wing must actually move: frames differ in how much of the sprite the
## wing occupies above and below the body.
func test_the_wing_position_changes_across_the_cycle():
	var frames := generator.generate_flap_images("sparrow", 3)
	var heights := []
	for frame in frames:
		var top: int = frame.get_height()
		for y in frame.get_height():
			for x in frame.get_width():
				if frame.get_pixel(x, y).a > 0.0:
					top = mini(top, y)
					break
		heights.append(top)
	var distinct_heights := {}
	for h in heights:
		distinct_heights[h] = true
	assert_gt(distinct_heights.size(), 1, "the wing should rise and fall through the cycle")


func test_flap_frames_are_deterministic():
	var a := generator.generate_flap_images("kingfisher", 5)
	var b := generator.generate_flap_images("kingfisher", 5)
	for i in a.size():
		assert_eq(a[i].get_data(), b[i].get_data())
