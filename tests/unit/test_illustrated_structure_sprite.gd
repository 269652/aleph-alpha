extends GutTest

## Real illustrated art for farm/sagewerk/storage/wooden_fence/city_hall
## (see docs/concept/npc_farm_production.md, docs/concept/
## npc_role_consensus.md), sliced from five user-supplied reference sheets
## with a KNOWN FIXED GRID, mirroring illustrated_beehive_sprite.gd's own
## established precedent. Grid/row boundaries verified empirically against
## real cropped frames before writing this class (see its own header doc
## comment) -- these tests pin the resulting contract, not the pixel
## archaeology itself.

const IllustratedStructureSprite = preload("res://src/rendering/illustrated_structure_sprite.gd")

const _ALL_SUBJECTS := ["farm", "sagewerk", "storage", "wooden_fence", "city_hall"]

var sprite: IllustratedStructureSprite


func before_each():
	sprite = IllustratedStructureSprite.new()


func test_knows_all_five_subjects():
	for subject in _ALL_SUBJECTS:
		assert_true(sprite.has_subject(subject), "%s should be a known subject" % subject)


func test_does_not_know_an_unrelated_subject():
	assert_false(sprite.has_subject("campfire"))


func test_idle_texture_is_null_for_an_unknown_subject():
	assert_null(sprite.idle_texture("not_a_real_subject"))


func test_idle_texture_returns_a_real_texture_for_every_subject():
	for subject in _ALL_SUBJECTS:
		var texture := sprite.idle_texture(subject)
		assert_not_null(texture, "%s should resolve to a real texture" % subject)
		var image := texture.get_image()
		assert_gt(image.get_width(), 0)
		assert_gt(image.get_height(), 0)


## Chroma-keyed: the background must be gone, not just recolored -- the
## same "actually transparent, not still opaque magenta/black" contract
## illustrated_beehive_sprite.gd's own despill pass guarantees.
func test_idle_texture_background_is_transparent_not_opaque():
	for subject in _ALL_SUBJECTS:
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
	for subject in _ALL_SUBJECTS:
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
	for subject in _ALL_SUBJECTS:
		var image := sprite.idle_texture(subject).get_image()
		var magenta_survivors := 0
		for y in image.get_height():
			for x in image.get_width():
				var c := image.get_pixel(x, y)
				if c.a >= 0.99 and c.r >= 0.85 and c.b >= 0.85 and c.g <= 0.15:
					magenta_survivors += 1
		assert_eq(magenta_survivors, 0, "%s should have no surviving opaque magenta" % subject)


func test_subjects_lists_all_five():
	var subjects := sprite.subjects()
	for subject in _ALL_SUBJECTS:
		assert_true(subjects.has(subject))
	assert_eq(subjects.size(), 5)


# -- footprint scaling: a placed structure's art as a Sprite2D standing on --
# -- its own tile, per IllustratedArtLoader's own documented "footprint" ----
# -- anchor -- width matches the tile, height scales by the SAME factor so --
# -- a structure taller than one tile stays taller rather than being --------
# -- squashed to fit a square. -----------------------------------------------


func test_footprint_texture_is_null_for_an_unknown_subject():
	assert_null(sprite.footprint_texture("not_a_real_subject", 16))


func test_footprint_texture_width_matches_the_tile_size():
	for subject in _ALL_SUBJECTS:
		var texture := sprite.footprint_texture(subject, 16)
		assert_eq(texture.get_width(), 16, "%s footprint width should match tile_size" % subject)


## sagewerk/storage/city_hall's own source cells are visibly taller than
## wide (192 wide x ~205 tall, the same 8-column grid all three sheets
## share) -- a uniform scale-by-width factor should therefore leave the
## scaled height GREATER than tile_size, not squashed down to it, the
## whole point of the footprint anchor over a plain square resize.
## farm/wooden_fence's own cells are wider than tall (a landscape house
## scene; a horizontal fence rail) -- their footprint height legitimately
## comes out smaller than tile_size, a real difference in the source art,
## not a bug (see test_footprint_texture_height_matches_the_idle_images_
## own_aspect_ratio for the actual scaling contract that covers all five).
func test_footprint_texture_preserves_aspect_ratio_taller_than_the_tile():
	for subject in ["sagewerk", "storage", "city_hall"]:
		var texture := sprite.footprint_texture(subject, 16)
		assert_gt(texture.get_height(), 16, "%s footprint height should stay taller than one tile" % subject)


func test_footprint_texture_height_matches_the_idle_images_own_aspect_ratio():
	for subject in _ALL_SUBJECTS:
		var idle_image := sprite.idle_texture(subject).get_image()
		var expected_height := int(round(16.0 * float(idle_image.get_height()) / float(idle_image.get_width())))
		var texture := sprite.footprint_texture(subject, 16)
		assert_eq(texture.get_height(), expected_height, "%s footprint height should scale by the same factor as width" % subject)


# -- whole-building entities (docs/concept/building.md "Buildings are -------
# -- entities; interiors are scenes"): any sheet following the one asset -----
# -- contract (8 columns x 5 lifecycle rows, black background, magenta ------
# -- dividers), read by ROW and COLUMN, scaled to a multi-tile footprint. ----
# -- blacksmith.png is the real fixture -- it is exactly that contract. -------

const _CONTRACT_SHEET := "res://assets/sprites/buildings/blacksmith.png"
const _COLUMNS := 8
const _ROWS := 5


func test_sheet_frame_image_reads_any_row_and_column_of_a_contract_sheet():
	var construction := sprite.sheet_frame_image(_CONTRACT_SHEET, _COLUMNS, _ROWS, 0, 0)
	var ruined := sprite.sheet_frame_image(_CONTRACT_SHEET, _COLUMNS, _ROWS, 4, 7)
	assert_not_null(construction)
	assert_not_null(ruined)
	assert_gt(construction.get_width(), 0)
	assert_ne(construction.get_data(), ruined.get_data(), "the first construction stage and the last ruin frame are different drawings")


func test_sheet_frame_image_is_keyed_to_a_transparent_background():
	var image := sprite.sheet_frame_image(_CONTRACT_SHEET, _COLUMNS, _ROWS, 2, 0)
	var transparent := 0
	var opaque := 0
	for y in image.get_height():
		for x in image.get_width():
			var a := image.get_pixel(x, y).a
			if a <= 0.01:
				transparent += 1
			elif a >= 0.99:
				opaque += 1
	assert_gt(transparent, 0, "the black background around the building is keyed away")
	assert_gt(opaque, 100, "the building itself survives")


func test_sheet_frame_image_is_null_for_a_missing_sheet_or_an_out_of_range_cell():
	assert_null(sprite.sheet_frame_image("res://assets/sprites/buildings/not_a_real_sheet.png", _COLUMNS, _ROWS, 0, 0))
	assert_null(sprite.sheet_frame_image(_CONTRACT_SHEET, _COLUMNS, _ROWS, _ROWS, 0), "row past the sheet")
	assert_null(sprite.sheet_frame_image(_CONTRACT_SHEET, _COLUMNS, _ROWS, 0, _COLUMNS), "column past the sheet")


## A building standing on a 3-tile-wide footprint is drawn 3 tiles wide --
## height by the same factor, so a tall building stays tall (the same
## footprint anchor footprint_texture already keeps for a 1-tile placeable).
func test_footprint_frame_texture_scales_to_the_footprint_width():
	var texture := sprite.footprint_frame_texture(_CONTRACT_SHEET, _COLUMNS, _ROWS, 2, 0, 16, 3)
	assert_not_null(texture)
	assert_eq(texture.get_width(), 48)
	var frame := sprite.sheet_frame_image(_CONTRACT_SHEET, _COLUMNS, _ROWS, 2, 0)
	var expected_height := int(round(48.0 * float(frame.get_height()) / float(frame.get_width())))
	assert_eq(texture.get_height(), expected_height)


func test_footprint_frame_texture_is_null_for_a_missing_sheet():
	assert_null(sprite.footprint_frame_texture("res://assets/sprites/buildings/not_a_real_sheet.png", _COLUMNS, _ROWS, 2, 0, 16, 2))


func test_sheet_frame_image_is_deterministic_and_cached_per_cell():
	var a := sprite.sheet_frame_image(_CONTRACT_SHEET, _COLUMNS, _ROWS, 1, 3)
	var b := sprite.sheet_frame_image(_CONTRACT_SHEET, _COLUMNS, _ROWS, 1, 3)
	assert_eq(a.get_data(), b.get_data())
