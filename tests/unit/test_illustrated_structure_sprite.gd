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

const VillageFarm = preload("res://src/gameplay/village_farm.gd")

## The four oriented rails a village farmhouse fences its beds with
## (docs/concept/village_farms.md) -- one subject per facing, each its own
## column of the same divider-gridded sheet.
const _FENCE_SUBJECTS := [
	"farm_fence_north", "farm_fence_south", "farm_fence_east", "farm_fence_west",
]

const _ALL_SUBJECTS := [
	"farm", "sagewerk", "storage", "wooden_fence", "city_hall",
	"farm_fence_north", "farm_fence_south", "farm_fence_east", "farm_fence_west",
	"farm_fence_corner_west", "farm_fence_corner_east",
]

var sprite: IllustratedStructureSprite


func before_each():
	sprite = IllustratedStructureSprite.new()


func test_knows_every_subject():
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


func test_subjects_lists_every_one():
	var subjects := sprite.subjects()
	for subject in _ALL_SUBJECTS:
		assert_true(subjects.has(subject))
	assert_eq(subjects.size(), _ALL_SUBJECTS.size())


# -- footprint scaling: a placed structure's art as a Sprite2D standing on --
# -- its own tile, per IllustratedArtLoader's own documented "footprint" ----
# -- anchor -- width matches the tile, height scales by the SAME factor so --
# -- a structure taller than one tile stays taller rather than being --------
# -- squashed to fit a square. -----------------------------------------------


func test_footprint_texture_is_null_for_an_unknown_subject():
	assert_null(sprite.footprint_texture("not_a_real_subject", 16))


## Every WHOLE BUILDING, which is what the footprint anchor is about. A rail
## is deliberately not one of them any more: it scales by its own run so
## consecutive rails meet, which makes its band wider than the tile it
## stands on (see "and a run is scaled by its RUN" below).
func test_footprint_texture_width_matches_the_tile_size():
	for subject in _ALL_SUBJECTS:
		if VillageFarm.is_fence_tile(subject):
			continue
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


## The scaling contract that covers all of them, rails included: ONE factor
## for both axes, so nothing is ever squashed. Stated against the texture's
## own width rather than against the tile, because what that factor is
## differs -- a building scales its width to the tile, a rail scales its run
## to the tile -- while "the same factor on both axes" does not.
func test_footprint_texture_height_matches_the_idle_images_own_aspect_ratio():
	for subject in _ALL_SUBJECTS:
		var idle_image := sprite.idle_texture(subject).get_image()
		var texture := sprite.footprint_texture(subject, 16)
		var expected_height := (
			float(texture.get_width()) * float(idle_image.get_height()) / float(idle_image.get_width())
		)
		# Within a pixel, not exact: both axes are rounded to whole pixels
		# from ONE real factor, so back-deriving that factor from the
		# already-rounded width cannot land on the nose at a 16px tile.
		assert_almost_eq(
			float(texture.get_height()), expected_height, 1.0,
			"%s footprint height should scale by the same factor as width" % subject
		)


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


# -- sheets whose cells are divided by magenta lines ------------------------
#
# The house lifecycle sheets (house_1_1.png .. house_1_5.png) and well.png
# divide their cells with real magenta lines and carry label bands that are
# not art -- see VariantSheetGrid.art_bands. A cell of one is cut between
# those lines, never by dividing the canvas.

const _LIFECYCLE_SHEET := "res://assets/sprites/buildings/house_1_1.png"


func test_a_divider_sheets_cell_is_cut_where_its_own_lines_are():
	var VariantSheetGrid = load("res://src/rendering/variant_sheet_grid.gd")
	var SpriteSheetLoader = load("res://src/rendering/sprite_sheet_loader.gd")
	# Loaded the way the game loads it, not Image.load_from_file: these
	# sheets have .import sidecars now, so the raw path is both the wrong
	# one and a warning.
	var image: Image = SpriteSheetLoader.load_image(_LIFECYCLE_SHEET)
	assert_not_null(image, "precondition: the sheet is on disk")
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var expected: Rect2i = VariantSheetGrid.divider_cell_rect(image, 8, 10, 3, 2)
	var frame: Image = sprite.divider_frame_image(_LIFECYCLE_SHEET, 8, 10, 3, 2)
	assert_not_null(frame, "the sheet's own cell must be readable")
	assert_eq(frame.get_size(), Vector2i(expected.size.x, expected.size.y))


## An even division of this canvas would be a whole label band out.
func test_an_even_division_would_cut_a_divider_sheet_in_the_wrong_place():
	var even: Image = sprite.sheet_frame_image(_LIFECYCLE_SHEET, 8, 10, 3, 2)
	var divided: Image = sprite.divider_frame_image(_LIFECYCLE_SHEET, 8, 10, 3, 2)
	assert_not_null(even)
	assert_not_null(divided)
	assert_ne(
		even.get_size(), divided.get_size(),
		"if these agreed, the sheet would not need divider-aware slicing at all"
	)


func test_a_divider_sheets_frames_are_cached_per_cell():
	var first: Image = sprite.divider_frame_image(_LIFECYCLE_SHEET, 8, 10, 4, 1)
	var second: Image = sprite.divider_frame_image(_LIFECYCLE_SHEET, 8, 10, 4, 1)
	assert_true(first == second, "the same cell must not be re-sliced every time it is asked for")


func test_a_divider_sheet_scales_to_a_real_footprint():
	var texture: ImageTexture = sprite.footprint_frame_texture(_LIFECYCLE_SHEET, 8, 10, 3, 2, 32, 2, "dividers")
	assert_not_null(texture)
	assert_eq(texture.get_width(), 64, "two tiles wide at 32 art px per tile")


# -- the farm fence: one sheet, four orientation columns -------------------


## Every facing the rule set can build really has art, under exactly the
## subject name the tile id implies -- the one link between "a rail was
## built facing east" and "an east rail is drawn".
func test_every_rail_the_village_can_build_has_its_own_art():
	for facing in ["north", "south", "east", "west", "corner_west", "corner_east"]:
		var subject: String = VillageFarm.fence_tile_for(facing)
		assert_true(sprite.has_subject(subject), "%s has no art at all" % subject)


## And the four are really four different pictures -- a sheet read on the
## wrong grid would hand back the same cell four times, which is the exact
## failure an even division of a label-gutter sheet produces.
func test_the_four_rails_are_four_different_pictures():
	var seen: Array = []
	for subject in _FENCE_SUBJECTS:
		var image := sprite.idle_texture(subject).get_image()
		var signature := "%d|%d|%s" % [
			image.get_width(), image.get_height(), Marshalls.raw_to_base64(image.get_data())
		]
		assert_false(seen.has(signature), "%s is the same picture as another rail" % subject)
		seen.append(signature)


# -- a rail stands on its tile's INNER EDGE --------------------------------
#
# Asked for directly, with two sides arrowed in a screenshot: "move the
# fences to the inner edge of the enclosure and treat the rest of the tile
# as street". A rail's art does not sit in the middle of its tile -- its own
# GROUND LINE lands on the edge facing the beds, which is what makes the
# rest of the tile read as walkable ground. See docs/concept/
# village_farms.md, "The rail stands on the inner edge".
#
# Measured here independently of the implementation rather than pinned to
# numbers it also computes: these tests find the real wood in the delivered
# sheet with their own rule and check where the offset actually puts it.
# The sheet draws every run CENTRED in its cell with real margin all round,
# so "bottom-anchored" alone leaves a rail a fifth of a tile short of the
# edge it is meant to stand on -- the first attempt at this assumed a north
# rail already stood on its own south edge, and the art says otherwise.

const _TILE := 64

## How close to the edge a ground line has to land, in tile pixels. Not
## zero: the band is measured in sheet pixels and scaled, so a rounding of
## well under one screen pixel at the real TILE_SIZE is expected.
const _EDGE_TOLERANCE := 1.5


## The rail's real wood, as a rect in TILE-sized pixels relative to the
## band, found with this file's own brown-pixel rule (r > g > b) so it
## shares no code with what it is checking. Image.get_used_rect cannot be
## used: a pixel halfway between the sheet's magenta divider and its black
## background survives the chroma key with full alpha, which makes the used
## rect the whole cell every time.
func _wood_rect_in_tile_units(subject: String) -> Rect2:
	var image := sprite.idle_texture(subject).get_image()
	var texture := sprite.footprint_texture(subject, _TILE)
	var scale := float(texture.get_width()) / float(image.get_width())
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a < 0.5 or pixel.r < 0.2 or pixel.r <= pixel.b or pixel.g <= pixel.b:
				continue
			min_x = mini(min_x, x)
			max_x = maxi(max_x, x)
			min_y = mini(min_y, y)
			max_y = maxi(max_y, y)
	assert_gt(max_x, min_x, "%s has no wood in it at all" % subject)
	return Rect2(
		float(min_x) * scale, float(min_y) * scale,
		float(max_x - min_x + 1) * scale, float(max_y - min_y + 1) * scale
	)


## Where the art really lands inside the tile, y measured down from the
## tile's own top edge and x from its left edge: footprint_texture is
## bottom-anchored and centred on the tile (EarthChunkManager._spawn_
## structure_art_for), then shifted by footprint_offset.
##
## The band is measured from the REAL texture rather than assumed to be one
## tile wide -- a rail is scaled by its own run, not by its cell width, so
## its band is wider than the tile it stands on.
func _placed_wood_rect(subject: String) -> Rect2:
	var texture := sprite.footprint_texture(subject, _TILE)
	var band := Vector2(float(texture.get_width()), float(texture.get_height()))
	var wood := _wood_rect_in_tile_units(subject)
	var band_origin := Vector2((float(_TILE) - band.x) * 0.5, float(_TILE) - band.y)
	var offset: Vector2 = sprite.footprint_offset(subject, _TILE)
	return Rect2(wood.position + band_origin + offset, wood.size)


## A broad-side run stands on its POSTS, so the bottom of its wood is its
## ground line -- and that is what has to land on the edge facing the beds.
func test_a_broadside_runs_posts_stand_on_the_edge_facing_the_beds():
	assert_almost_eq(
		_placed_wood_rect("farm_fence_north").end.y, float(_TILE), _EDGE_TOLERANCE,
		"a north rail's beds lie south, so its posts stand on its own south edge"
	)
	assert_almost_eq(
		_placed_wood_rect("farm_fence_south").end.y, 0.0, _EDGE_TOLERANCE,
		"the arrow pointed up: a south rail's posts stand on its own north edge"
	)


## A run seen from above has no posts to stand on -- the band of rail IS its
## ground line -- so its own centre line lands on the edge instead.
func test_a_top_view_runs_centre_line_lands_on_the_edge_facing_the_beds():
	var east := _placed_wood_rect("farm_fence_east")
	assert_almost_eq(
		east.position.x + east.size.x * 0.5, 0.0, _EDGE_TOLERANCE,
		"an east rail closes the field's east side, so its beds lie west"
	)
	var west := _placed_wood_rect("farm_fence_west")
	assert_almost_eq(
		west.position.x + west.size.x * 0.5, float(_TILE), _EDGE_TOLERANCE,
		"the arrow pointed right: a west rail's beds lie east"
	)


## Every rail really moves -- including the north one the first attempt at
## this wrongly left alone.
func test_every_rail_is_moved_off_the_middle_of_its_tile():
	for facing in VillageFarm.FENCE_TILE_IDS:
		var subject: String = VillageFarm.fence_tile_for(facing)
		assert_ne(
			sprite.footprint_offset(subject, _TILE), Vector2.ZERO,
			"%s is still drawn where a whole-tile structure would be" % subject
		)


## And it moves TOWARD the beds, never away from them.
func test_the_offset_moves_the_art_toward_the_beds():
	for facing in VillageFarm.FENCE_TILE_IDS:
		var subject: String = VillageFarm.fence_tile_for(facing)
		var offset: Vector2 = sprite.footprint_offset(subject, _TILE)
		var inner: Vector2i = VillageFarm.fence_inner_direction(subject)
		assert_gt(
			offset.dot(Vector2(inner)), 0.0,
			"%s's art must move toward its own beds, not away from them" % subject
		)


## Everything that is a whole building standing on its own tile is
## untouched -- only a rail is a line on an edge.
func test_every_other_subject_still_stands_in_the_middle_of_its_tile():
	for subject in ["farm", "sagewerk", "storage", "wooden_fence", "city_hall"]:
		assert_eq(sprite.footprint_offset(subject, _TILE), Vector2.ZERO, subject)
	assert_eq(sprite.footprint_offset("not_a_subject", _TILE), Vector2.ZERO)


# -- and a run is scaled by its RUN, so consecutive rails meet --------------
#
# Asked for directly, in one word, after seeing the rails land on the edge:
# "also scale". The sheet draws each run centred in its own cell with real
# margin at both ends, so a cell scaled by its own WIDTH leaves that margin
# as a gap between one rail and the next and the fence reads as a row of
# separate pieces instead of a line. A rail is scaled so its own wood spans
# exactly one tile along the direction its run travels.


func test_a_broadside_runs_wood_spans_exactly_one_tile_across():
	for facing in ["north", "south"]:
		var placed := _placed_wood_rect(VillageFarm.fence_tile_for(facing))
		assert_almost_eq(
			placed.size.x, float(_TILE), _EDGE_TOLERANCE,
			"a %s run must meet the next one along its row, with no gap and no overlap" % facing
		)


func test_a_top_view_runs_wood_spans_exactly_one_tile_down():
	for facing in ["east", "west", "corner_west", "corner_east"]:
		var placed := _placed_wood_rect(VillageFarm.fence_tile_for(facing))
		assert_almost_eq(
			placed.size.y, float(_TILE), _EDGE_TOLERANCE,
			"a %s run must meet the next one down its column" % facing
		)


## Scaling by the run must not break where the run STANDS -- the ground line
## is still on the inner edge, which is the pair of facts that together make
## a closed frame.
func test_scaling_by_the_run_keeps_every_rail_on_its_own_inner_edge():
	assert_almost_eq(_placed_wood_rect("farm_fence_north").end.y, float(_TILE), _EDGE_TOLERANCE)
	assert_almost_eq(_placed_wood_rect("farm_fence_south").end.y, 0.0, _EDGE_TOLERANCE)
	for facing in ["east", "corner_east"]:
		var east := _placed_wood_rect(VillageFarm.fence_tile_for(facing))
		assert_almost_eq(east.position.x + east.size.x * 0.5, 0.0, _EDGE_TOLERANCE, facing)
	for facing in ["west", "corner_west"]:
		var west := _placed_wood_rect(VillageFarm.fence_tile_for(facing))
		assert_almost_eq(west.position.x + west.size.x * 0.5, float(_TILE), _EDGE_TOLERANCE, facing)


## Everything that is a whole building still scales by its own width, the
## way it always has.
func test_a_building_still_scales_its_width_to_the_tile():
	for subject in ["farm", "sagewerk", "storage", "wooden_fence", "city_hall"]:
		assert_eq(sprite.footprint_texture(subject, _TILE).get_width(), _TILE, subject)
