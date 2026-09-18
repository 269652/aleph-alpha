extends GutTest

## The village porter's own art (see ProceduralPorterSprite, LogisticsMarker).
##
## Reported live with the Bollerwagen in shot: *"The cart is not being pulled
## by a worker, but by a floor tile???"*. The porter was drawn with
## ProceduralStructureSprite's own `storage` TILE, left in as a placeholder
## when the worker was written and never replaced -- so a shed appeared to be
## pulling the wagon.

const ProceduralPorterSprite = preload("res://src/rendering/procedural_porter_sprite.gd")
const ProceduralLumberjackSprite = preload("res://src/rendering/procedural_lumberjack_sprite.gd")
const ProceduralStructureSprite = preload("res://src/rendering/procedural_structure_sprite.gd")

var sprite := ProceduralPorterSprite.new()


func test_it_draws_at_a_walkers_size_not_a_buildings():
	var image := sprite.generate_image()
	assert_eq(image.get_width(), ProceduralPorterSprite.SIZE)
	assert_eq(image.get_height(), ProceduralPorterSprite.SIZE)


## The same tiny walker size the Sägewerk's own Lumberjack is drawn at: both
## are purpose-built walkers rather than CharacterView's full rig, and two
## people in one village should read as the same scale.
func test_a_porter_is_the_same_size_as_the_other_village_walker():
	assert_eq(ProceduralPorterSprite.SIZE, ProceduralLumberjackSprite.SIZE)


## And is a PERSON: something stands there, and it is not the storage tile
## that used to.
func test_a_porter_is_drawn_rather_than_left_blank():
	var image := sprite.generate_image()
	var drawn := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				drawn += 1
	assert_gt(drawn, 0, "somebody is standing there")
	assert_lt(drawn, image.get_width() * image.get_height(), "and they are not a solid block")


func test_a_porter_does_not_look_like_the_storage_shed_it_used_to():
	var porter := sprite.generate_image()
	var shed: Image = ProceduralStructureSprite.new().generate_texture("storage").get_image()
	assert_ne(
		Vector2i(porter.get_width(), porter.get_height()),
		Vector2i(shed.get_width(), shed.get_height()),
		"a person is not a building"
	)


## Skin above tunic, the same read the Lumberjack has: a head over a body, so
## a glance says "somebody" rather than "a thing".
func test_a_porter_reads_as_a_head_over_a_body():
	var image := sprite.generate_image()
	var head_row: int = int(ProceduralPorterSprite.SIZE * 0.25)
	var body_row: int = int(ProceduralPorterSprite.SIZE * 0.6)
	assert_true(_row_has_colour(image, head_row, ProceduralPorterSprite.SKIN_COLOR), "a head")
	assert_true(_row_has_colour(image, body_row, ProceduralPorterSprite.TUNIC_COLOR), "over a body")


## Within a couple of 8-bit steps: an RGBA8 image quantises every channel, so
## a colour written as 0.75 reads back as 191/255, and an exact comparison
## finds nothing however faithfully it was drawn.
func _row_has_colour(image: Image, row: int, colour: Color) -> bool:
	var tolerance := 2.0 / 255.0
	for x in image.get_width():
		var pixel := image.get_pixel(x, row)
		if (
			pixel.a > 0.5
			and absf(pixel.r - colour.r) <= tolerance
			and absf(pixel.g - colour.g) <= tolerance
			and absf(pixel.b - colour.b) <= tolerance
		):
			return true
	return false
