extends GutTest

const ProceduralOreSprite = preload("res://src/rendering/procedural_ore_sprite.gd")

var generator: ProceduralOreSprite


func before_each():
	generator = ProceduralOreSprite.new()


func test_image_matches_the_generators_canvas_size():
	var image := generator.generate_image("iron", 42)
	assert_eq(image.get_width(), ProceduralOreSprite.SIZE.x)
	assert_eq(image.get_height(), ProceduralOreSprite.SIZE.y)


func test_image_has_transparent_background_and_opaque_boulder():
	var image := generator.generate_image("iron", 42)
	var opaque := 0
	var transparent := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				opaque += 1
			else:
				transparent += 1
	assert_gt(opaque, 20)
	assert_gt(transparent, 20)


func test_same_seed_and_type_produce_identical_image():
	var a := generator.generate_image("copper", 123)
	var b := generator.generate_image("copper", 123)
	assert_eq(a.get_data(), b.get_data())


func test_different_seeds_produce_different_images():
	var a := generator.generate_image("iron", 1)
	var b := generator.generate_image("iron", 2)
	assert_ne(a.get_data(), b.get_data())


func _average_fleck_color(ore_type: String) -> Color:
	# Sum pixels that are strongly non-grey (the colored ore flecks).
	var image := generator.generate_image(ore_type, 42)
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a <= 0.5:
				continue
			var hi: float = max(max(c.r, c.g), c.b)
			var spread: float = hi - min(min(c.r, c.g), c.b)
			# A fleck is either strongly hued (iron/copper) or much darker than
			# the boulder greys (coal, near-black).
			if spread > 0.12 or hi < 0.18:
				r += c.r
				g += c.g
				b += c.b
				n += 1
	assert_gt(n, 0, "expected some colored flecks for %s" % ore_type)
	return Color(r / n, g / n, b / n)


func test_each_ore_type_has_distinct_fleck_color():
	var iron := _average_fleck_color("iron")
	var copper := _average_fleck_color("copper")
	var coal := _average_fleck_color("coal")
	var iron_v := Vector3(iron.r, iron.g, iron.b)
	var copper_v := Vector3(copper.r, copper.g, copper.b)
	var coal_v := Vector3(coal.r, coal.g, coal.b)
	assert_gt(iron_v.distance_to(copper_v), 0.15, "iron vs copper flecks too similar")
	assert_gt(iron_v.distance_to(coal_v), 0.15, "iron vs coal flecks too similar")
	assert_gt(copper_v.distance_to(coal_v), 0.15, "copper vs coal flecks too similar")


func test_iron_flecks_are_orange_brown():
	var c := _average_fleck_color("iron")
	assert_gt(c.r, c.b, "iron flecks should be warm (red > blue)")


func test_copper_flecks_are_teal_green():
	var c := _average_fleck_color("copper")
	assert_gt(c.g, c.r, "copper flecks should be green-dominant")


func test_generate_texture_wraps_image():
	var texture := generator.generate_texture("iron", 42)
	assert_not_null(texture)
	assert_eq(texture.get_width(), ProceduralOreSprite.SIZE.x)


# -- ore composited onto an illustrated base (see StoneRenderer._ore_texture_for) -
#
# An ore node is always drawn at boulder scale (see StoneRenderer._attach_body_parts'
# diameter_cm==0 branch), so once illustrated boulder art exists the ore's
# rock silhouette should come from THAT instead of the flat procedural
# ellipse, with only the ore flecks still generated here -- scattered by
# testing the base image's own alpha channel rather than ellipse geometry,
# so this works against any silhouette with no shape-specific math to keep
# in sync with the art.

## A small synthetic base: opaque left half, transparent right half -- enough
## to prove flecks respect a real silhouette boundary without depending on
## real art loading in a unit test.
func _half_opaque_base(size: int = 16) -> Image:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			if x < size / 2:
				image.set_pixel(x, y, Color(0.5, 0.5, 0.5, 1.0))
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	return image


func test_generate_image_from_base_keeps_the_base_images_size():
	var base := _half_opaque_base(16)
	var image := generator.generate_image_from_base(base, "iron", 42)
	assert_eq(image.get_width(), base.get_width())
	assert_eq(image.get_height(), base.get_height())


func test_generate_image_from_base_never_paints_outside_the_base_silhouette():
	var base := _half_opaque_base(16)
	var image := generator.generate_image_from_base(base, "iron", 42)
	for y in image.get_height():
		for x in image.get_width():
			if base.get_pixel(x, y).a <= 0.0:
				assert_eq(
					image.get_pixel(x, y).a, 0.0,
					"a fleck painted outside the base silhouette at (%d, %d)" % [x, y]
				)


func test_generate_image_from_base_adds_visible_fleck_color():
	var base := _half_opaque_base(16)
	var image := generator.generate_image_from_base(base, "iron", 42)
	assert_ne(image.get_data(), base.get_data(), "expected at least one fleck painted onto the base")


func test_generate_image_from_base_is_deterministic():
	var base := _half_opaque_base(16)
	var a := generator.generate_image_from_base(base, "copper", 123)
	var b := generator.generate_image_from_base(base, "copper", 123)
	assert_eq(a.get_data(), b.get_data())


func test_generate_texture_from_base_wraps_image():
	var base := _half_opaque_base(16)
	var texture := generator.generate_texture_from_base(base, "iron", 42)
	assert_not_null(texture)
	assert_eq(texture.get_width(), base.get_width())


## A real illustrated frame is NOT a clean two-value (opaque/transparent)
## silhouette like _half_opaque_base above -- IllustratedStoneSprite's real
## pipeline chroma-keys a magenta-background sheet (no native alpha channel
## at all), then Lanczos-resizes each cropped frame down to CANVAS_SIZE
## (_load_frames_from), then runs a second despill pass over the result
## (_scrub_magenta_fringe) that intentionally leaves a soft, PARTIALLY
## opaque halo of edge/anti-aliasing pixels around the rock's real
## silhouette rather than punching them to hard alpha=0 -- "a genuine soft
## shadow/outline stays a shadow instead of being punched into a
## hard-edged hole" (see that function's own doc comment). This third
## region -- ambiguous, low-but-nonzero alpha, neither "clearly inside"
## nor "clearly outside" -- is exactly what _half_opaque_base's hard 50/50
## split never exercises.
func _base_with_partial_alpha_halo(size: int = 30) -> Image:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var third := size / 3
	for y in size:
		for x in size:
			if x < third:
				image.set_pixel(x, y, Color(0.5, 0.5, 0.5, 1.0))  # solidly inside the rock
			elif x < third * 2:
				image.set_pixel(x, y, Color(0.6, 0.55, 0.6, 0.3))  # soft halo -- NOT the rock
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))  # fully transparent background
	return image


## Regression: reported live (playtest, 2026-08-28) as "ore illustrations
## get mangled" -- confirmed by dumping real generated ore textures to PNG
## and inspecting them directly: stray, fully-opaque fleck-colored dots
## floating outside the illustrated boulder's visible silhouette, in what
## should read as empty space around the rock. _paint_flecks_on_silhouette
## only excluded a candidate pixel when `alpha <= 0.0` -- true for the
## fully-transparent background, but false for the soft halo band real
## illustrated art leaves at a nonzero-but-low alpha (see
## _base_with_partial_alpha_halo's own doc comment), so a fleck (painted
## via `set_pixel` with the default fully-opaque alpha=1.0) gets stamped
## squarely inside that ambiguous halo, popping visibly against the
## near-transparent margin around it.
func test_generate_image_from_base_does_not_paint_on_a_partially_transparent_halo():
	var base := _base_with_partial_alpha_halo()
	var halo_x := base.get_width() / 3 + 1  # inside the halo third, not the border pixel
	for seed_value in range(20):
		var image := generator.generate_image_from_base(base, "iron", seed_value)
		for y in image.get_height():
			assert_true(
				image.get_pixel(halo_x, y).is_equal_approx(base.get_pixel(halo_x, y)),
				"a fleck was painted on a partially-transparent halo pixel at (%d, %d), seed %d" % [halo_x, y, seed_value]
			)
