extends GutTest

## Real illustrated art for farm/sagewerk/storage/wooden_fence (see
## docs/concept/npc_farm_production.md), sliced from four user-supplied
## reference sheets with a KNOWN FIXED GRID, mirroring
## illustrated_beehive_sprite.gd's own established precedent. Grid/row
## boundaries verified empirically against real cropped frames before
## writing this class (see its own header doc comment) -- these tests pin
## the resulting contract, not the pixel archaeology itself.

const IllustratedStructureSprite = preload("res://src/rendering/illustrated_structure_sprite.gd")

var sprite: IllustratedStructureSprite


func before_each():
	sprite = IllustratedStructureSprite.new()


func test_knows_all_four_subjects():
	for subject in ["farm", "sagewerk", "storage", "wooden_fence"]:
		assert_true(sprite.has_subject(subject), "%s should be a known subject" % subject)


func test_does_not_know_an_unrelated_subject():
	assert_false(sprite.has_subject("campfire"))


func test_idle_texture_is_null_for_an_unknown_subject():
	assert_null(sprite.idle_texture("not_a_real_subject"))


func test_idle_texture_returns_a_real_texture_for_every_subject():
	for subject in ["farm", "sagewerk", "storage", "wooden_fence"]:
		var texture := sprite.idle_texture(subject)
		assert_not_null(texture, "%s should resolve to a real texture" % subject)
		var image := texture.get_image()
		assert_gt(image.get_width(), 0)
		assert_gt(image.get_height(), 0)


## Chroma-keyed: the background must be gone, not just recolored -- the
## same "actually transparent, not still opaque magenta/black" contract
## illustrated_beehive_sprite.gd's own despill pass guarantees.
func test_idle_texture_background_is_transparent_not_opaque():
	for subject in ["farm", "sagewerk", "storage", "wooden_fence"]:
		var image := sprite.idle_texture(subject).get_image()
		var transparent_pixels := 0
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a <= 0.01:
					transparent_pixels += 1
		assert_gt(transparent_pixels, 0, "%s should have a real transparent background" % subject)


## The actual building/fence content must survive keying -- a real opaque
## drawing remains, not an all-transparent blank frame.
func test_idle_texture_keeps_real_opaque_content():
	for subject in ["farm", "sagewerk", "storage", "wooden_fence"]:
		var image := sprite.idle_texture(subject).get_image()
		var opaque_pixels := 0
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a >= 0.99:
					opaque_pixels += 1
		assert_gt(opaque_pixels, 100, "%s should keep real drawn content" % subject)


## No leftover fully-saturated magenta should survive keying+despill
## anywhere in the frame (the same "despill, don't just threshold" contract
## illustrated_beehive_sprite.gd's own tests pin).
func test_idle_texture_has_no_surviving_opaque_magenta():
	for subject in ["farm", "sagewerk", "storage", "wooden_fence"]:
		var image := sprite.idle_texture(subject).get_image()
		var magenta_survivors := 0
		for y in image.get_height():
			for x in image.get_width():
				var c := image.get_pixel(x, y)
				if c.a >= 0.99 and c.r >= 0.85 and c.b >= 0.85 and c.g <= 0.15:
					magenta_survivors += 1
		assert_eq(magenta_survivors, 0, "%s should have no surviving opaque magenta" % subject)


func test_subjects_lists_all_four():
	var subjects := sprite.subjects()
	for subject in ["farm", "sagewerk", "storage", "wooden_fence"]:
		assert_true(subjects.has(subject))
	assert_eq(subjects.size(), 4)


# -- footprint scaling: a placed structure's art as a Sprite2D standing on --
# -- its own tile, per IllustratedArtLoader's own documented "footprint" ----
# -- anchor -- width matches the tile, height scales by the SAME factor so --
# -- a structure taller than one tile (every one of these four is) stays ----
# -- taller than one tile rather than being squashed to fit a square. -------


func test_footprint_texture_is_null_for_an_unknown_subject():
	assert_null(sprite.footprint_texture("not_a_real_subject", 16))


func test_footprint_texture_width_matches_the_tile_size():
	for subject in ["farm", "sagewerk", "storage", "wooden_fence"]:
		var texture := sprite.footprint_texture(subject, 16)
		assert_eq(texture.get_width(), 16, "%s footprint width should match tile_size" % subject)


## sagewerk/storage's own source cells are visibly taller than wide (192
## wide x ~205 tall) -- a uniform scale-by-width factor should therefore
## leave the scaled height GREATER than tile_size, not squashed down to it,
## the whole point of the footprint anchor over a plain square resize.
## farm/wooden_fence's own cells are wider than tall (a landscape house
## scene; a horizontal fence rail) -- their footprint height legitimately
## comes out smaller than tile_size, a real difference in the source art,
## not a bug (see test_footprint_texture_height_matches_the_idle_images_
## own_aspect_ratio for the actual scaling contract that covers all four).
func test_footprint_texture_preserves_aspect_ratio_taller_than_the_tile():
	for subject in ["sagewerk", "storage"]:
		var texture := sprite.footprint_texture(subject, 16)
		assert_gt(texture.get_height(), 16, "%s footprint height should stay taller than one tile" % subject)


func test_footprint_texture_height_matches_the_idle_images_own_aspect_ratio():
	for subject in ["farm", "sagewerk", "storage", "wooden_fence"]:
		var idle_image := sprite.idle_texture(subject).get_image()
		var expected_height := int(round(16.0 * float(idle_image.get_height()) / float(idle_image.get_width())))
		var texture := sprite.footprint_texture(subject, 16)
		assert_eq(texture.get_height(), expected_height, "%s footprint height should scale by the same factor as width" % subject)
