extends GutTest

## ProceduralFootprintSprite: no real hand-illustrated footprint/boot art
## exists anywhere in this project yet (confirmed by a dedicated search
## before writing this file) -- generates a real, simple, recognizable
## sole shape directly, the same "procedural first, real art can replace
## it later" precedent ProceduralMushroomSprite/LeafLitterAtlas's own
## procedural fallback already establish. One canonical shape per surface
## ("snow"/"grass"/"forest") -- left vs right is a render-time horizontal
## flip (see FootprintRenderer), not a second generated shape, the same
## flip_h idiom AntForagerMarker/DecomposerMarker's own facing already
## uses.

const ProceduralFootprintSprite = preload("res://src/rendering/procedural_footprint_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const GroundSlide = preload("res://src/gameplay/ground_slide.gd")

var sprite: ProceduralFootprintSprite


func before_each():
	sprite = ProceduralFootprintSprite.new()


func _has_opaque_pixel(image: Image) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				return true
	return false


func test_draws_a_real_non_blank_shape_for_every_real_surface():
	for surface in ["snow", "grass", "forest"]:
		var image := sprite.generate_image(surface)
		assert_true(_has_opaque_pixel(image), "%s should draw a real print, not a blank canvas" % surface)


func test_an_unknown_surface_falls_back_rather_than_crashing():
	var image := sprite.generate_image("lava")
	assert_true(_has_opaque_pixel(image))


## "Stamped ... with displacement" (reported live) -- a real pressed-in
## mark needs more than one flat fill colour: a darker core (the actual
## depression) plus a distinctly different rim tone (material pushed up
## at the edge), not a single-colour silhouette.
func test_the_print_has_at_least_two_distinct_opaque_tones_not_one_flat_fill():
	var image := sprite.generate_image("snow")
	var seen_colors := {}
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a > 0.5:
				seen_colors[c] = true
	assert_gt(seen_colors.size(), 1, "a real stamped print should show more than one opaque tone")


## Different surfaces must not all secretly render the identical look --
## snow, grass, and forest are visually distinct grounds.
func test_different_surfaces_look_different_from_each_other():
	var snow := sprite.generate_image("snow").get_data()
	var grass := sprite.generate_image("grass").get_data()
	var forest := sprite.generate_image("forest").get_data()
	assert_ne(snow, grass)
	assert_ne(grass, forest)
	assert_ne(snow, forest)


func test_generate_texture_returns_a_real_texture():
	var texture := sprite.generate_texture("snow")
	assert_not_null(texture)
	assert_true(_has_opaque_pixel(texture.get_image()))


## A real footprint is longer than it is wide (heel to toe > side to
## side) -- not a plain round blob, which would read as a paw print or a
## puddle rather than a human print.
func test_the_print_reads_longer_than_it_is_wide():
	assert_gt(ProceduralFootprintSprite.SIZE.y, ProceduralFootprintSprite.SIZE.x)


## Real average adult shoe length, converted via GroundSlide.PX_PER_METER
## -- the same real-human-scale idiom FootstepGait's own STRIDE_LENGTH_
## METERS/STANCE_WIDTH_METERS already use, not an eyeballed pixel count.
func test_world_scale_is_derived_from_a_real_meter_measurement_not_eyeballed():
	var expected := (
		ProceduralFootprintSprite.PRINT_LENGTH_METERS * GroundSlide.PX_PER_METER
		/ float(ProceduralFootprintSprite.SIZE.y)
	)
	assert_almost_eq(ProceduralFootprintSprite.PRINT_WORLD_SCALE, expected, 0.0001)


## Art authored at ArtResolution.DETAIL_MULTIPLIER-times oversize, same
## "more art pixels per world unit, identical world layout" convention
## every other entity sprite in this codebase already follows.
func test_canvas_is_authored_at_the_shared_detail_multiplier():
	assert_eq(ProceduralFootprintSprite.SIZE.x % ArtResolution.DETAIL_MULTIPLIER, 0)
	assert_eq(ProceduralFootprintSprite.SIZE.y % ArtResolution.DETAIL_MULTIPLIER, 0)
