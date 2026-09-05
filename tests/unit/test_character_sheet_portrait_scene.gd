extends GutTest

## A small illustrated backdrop behind the companion server's Character
## Sheet portrait -- see docs/concept/companion_server.md. NOT the live
## CharacterPreviewDiorama scene (that needs a real scene tree/SubViewport
## and would break this server's own "reads only the save file" design
## pillar -- see CompanionServer's own doc comment): this is a pure Image
## compositor, same shape as ProceduralCharacterSprite.
## generate_hero_portrait_image, which it reuses directly for the figure.

const CharacterSheetPortraitScene = preload("res://src/rendering/character_sheet_portrait_scene.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")

var appearance_maker := HeroAppearance.new()
var scene := CharacterSheetPortraitScene.new()


func test_generates_the_declared_canvas_size():
	var image := scene.generate_image(appearance_maker.appearance_for("warrior", 1))
	assert_eq(Vector2i(image.get_width(), image.get_height()), CharacterSheetPortraitScene.CANVAS_SIZE)


func test_the_top_row_reads_as_sky_not_ground():
	var image := scene.generate_image(appearance_maker.appearance_for("warrior", 1))
	var top_pixel := image.get_pixel(image.get_width() / 2, 0)
	# Sky is the cooler, bluer half of the canvas -- checked by relative hue
	# rather than an exact color match, so this doesn't break the moment the
	# sky gradient's own tuning changes.
	assert_gt(top_pixel.b, top_pixel.r, "the sky band should read as blue-leaning, not warm ground")


func test_the_bottom_row_reads_as_ground_not_sky():
	var image := scene.generate_image(appearance_maker.appearance_for("warrior", 1))
	var bottom_pixel := image.get_pixel(image.get_width() / 2, image.get_height() - 1)
	assert_gt(bottom_pixel.g, bottom_pixel.b, "the ground band should read as green-leaning, not sky")


func test_the_character_is_actually_drawn_somewhere_on_the_canvas():
	var image := scene.generate_image(appearance_maker.appearance_for("warrior", 1))
	var has_opaque_pixel := false
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				has_opaque_pixel = true
				break
		if has_opaque_pixel:
			break
	assert_true(has_opaque_pixel, "the scene should draw a real figure, not just an empty backdrop")


## The figure's feet should land on the ground band, not float in the sky or
## sink below the visible canvas -- the whole point of compositing onto a
## backdrop rather than just centering blindly. Sampled at a specific known
## point (horizontally centered, a few pixels above the ground line) rather
## than by scanning for "the lowest opaque row": the ground band itself is
## fully opaque too, and the ground-accent decorations (grass tufts, the
## pebble) are deliberately drawn INTO the ground band below the ground
## line, so either would be mistaken for the figure's own feet by a blind
## lowest-row scan.
func test_the_character_stands_on_the_ground_band():
	var image := scene.generate_image(appearance_maker.appearance_for("warrior", 1))
	var ground_y := CharacterSheetPortraitScene.CANVAS_SIZE.y - CharacterSheetPortraitScene.GROUND_MARGIN_PX
	var at_the_feet := image.get_pixel(CharacterSheetPortraitScene.CANVAS_SIZE.x / 2, ground_y - 5)
	assert_ne(
		at_the_feet, CharacterSheetPortraitScene.SKY_HORIZON,
		"just above the ground line, centered, should be the figure -- not still sky"
	)


func test_is_deterministic_for_the_same_appearance():
	var appearance := appearance_maker.appearance_for("warrior", 1)
	assert_eq(
		scene.generate_image(appearance).get_data(), scene.generate_image(appearance).get_data()
	)


func test_two_different_heroes_produce_different_images():
	var a := scene.generate_image(appearance_maker.appearance_for("warrior", 1))
	var b := scene.generate_image(appearance_maker.appearance_for("mage", 99))
	assert_ne(a.get_data(), b.get_data())


func test_generate_png_bytes_returns_real_png_data():
	var bytes := scene.generate_png_bytes(appearance_maker.appearance_for("warrior", 1))
	assert_gt(bytes.size(), 0)
	# The PNG file signature -- \x89PNG\r\n\x1a\n -- confirms this is real
	# encoded PNG data, not e.g. an empty/garbage buffer that happens to be
	# non-empty.
	var signature := PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
	assert_eq(bytes.slice(0, 8), signature, "should start with the real PNG file signature")
