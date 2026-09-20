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
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")

const VillageFarm = preload("res://src/gameplay/village_farm.gd")

## The four oriented rails a village farmhouse fences its beds with
## (docs/concept/village_farms.md) -- one subject per facing, each its own
## column of the same divider-gridded sheet.
const _FENCE_SUBJECTS := [
	"farm_fence_north", "farm_fence_south", "farm_fence_east", "farm_fence_west",
]

const StoneSize = preload("res://src/world/stone_size.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const _ALL_SUBJECTS := [
	"farm", "sagewerk", "storage", "wooden_fence", "city_hall",
	"farm_fence_north", "farm_fence_south", "farm_fence_east", "farm_fence_west",
	"farm_fence_corner_nw", "farm_fence_corner_sw",
	"farm_fence_corner_ne", "farm_fence_corner_se",
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
##
## **Reversed 2026-09-19**, and the old rule is worth stating because the
## concept doc specified it in as many words ("width matches the tile"): a
## building was drawn exactly one tile wide, which made it SMALLER THAN THE
## PERSON WHO WORKS IT. Reported live: "there's a weird shrunk farmhouse".
## A building is drawn at the footprint its own catalog twin claims now --
## the same art, at the same size, whether the village raised it as a real
## multi-tile building or the player placed it on one tile.
func test_a_building_is_drawn_at_the_footprint_its_own_catalog_twin_claims():
	for subject in _ALL_SUBJECTS:
		if VillageFarm.is_fence_tile(subject):
			continue
		var texture := sprite.footprint_texture(subject, 16)
		assert_eq(
			texture.get_width(), 16 * IllustratedStructureSprite.drawn_width_tiles(subject),
			"%s should be drawn at its own footprint width" % subject
		)


## The property the report was actually about, stated the way a player sees
## it: a building you can walk into is taller than you are. Measured off the
## real ART inside the cell (_art_rect), never the cell, for the same reason
## the rails are -- these sheets draw every subject with real margin around
## it, so the cell's own size is not the building's.
func test_a_placed_building_is_drawn_taller_than_the_person_who_works_it():
	for subject in ["farm", "sagewerk", "storage", "city_hall"]:
		var source := sprite.idle_texture(subject).get_image()
		var art: Rect2i = sprite._art_rect(subject, source)
		var texture := sprite.footprint_texture(subject, TerrainRenderer.TILE_SIZE)
		var scale := float(texture.get_width()) / float(source.get_width())
		assert_gt(
			float(art.size.y) * scale, StoneSize.PLAYER_WORLD_HEIGHT_PX,
			"%s is drawn shorter than the villager standing in it" % subject
		)


## A lone fence panel has no catalog twin and genuinely IS one tile of
## fence, so the old rule is still the right answer for it -- this is what
## keeps the change above from quietly enlarging everything with art.
func test_a_standalone_fence_panel_is_still_drawn_one_tile_wide():
	assert_eq(IllustratedStructureSprite.drawn_width_tiles("wooden_fence"), 1)
	assert_eq(sprite.footprint_texture("wooden_fence", 16).get_width(), 16)


## No fixed pitch: each of these sheets is cut on the rows its own artist
## drew, so the three of them disagree about how tall a row is.
##
## **Twice corrected, and the history is the point.** This first asserted
## the cells are "192 wide x ~205 tall" -- 205 being 1024/5, the even
## canvas division. Then it asserted they are square 192x192, after
## profiling put boundaries at 192, 384, 576. Both were a pitch assumed
## from one axis and applied to the other, and both were wrong: that 192
## pitch is the COLUMN pitch, confirmed on all four 8-column sheets (art
## starts ~12px inside each of 0, 192, 384 ... 1344). The ROWS are
## irregular -- warehouse.png's drawn boundaries sit at 188, 376, 566 and
## 786 -- so the 205 cut clipped 9px off sagewerk's roof and the 192 cut
## clipped 13px off city_hall's footings and 26 off blacksmith's last row.
## Reported live as "the warehouse has the rows cropped wrongly". See
## VariantSheetGrid.content_bands.
##
## What the test was really protecting is covered twice over now, by
## test_an_even_grid_frame_is_cut_on_the_sheets_own_drawn_row (the height
## is the drawn row) and test_footprint_texture_height_matches_the_idle_
## images_own_aspect_ratio (nothing is squashed). What is left to pin here
## is the property no pitch can have: under ANY single pitch these three
## same-size sheets would be cut to identical heights, and they are not.
func test_the_three_shared_size_sheets_are_cut_to_three_different_heights():
	var heights: Array = []
	for subject in ["sagewerk", "storage", "city_hall"]:
		heights.append(sprite.idle_texture(subject).get_image().get_height())
	assert_eq(
		heights.size(), _unique(heights).size(),
		"a pitch would give 1536x1024 sheets one height; drawn rows give three: %s" % [heights]
	)


func _unique(values: Array) -> Array:
	var seen: Array = []
	for value in values:
		if not seen.has(value):
			seen.append(value)
	return seen


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


## A building standing on a 3-tile-wide footprint is drawn INSIDE those
## three tiles, leaving BuildingCatalog.PLOT_MARGIN_SHARE of air on each
## side -- height by the same factor, so a tall building stays tall (the
## same footprint anchor footprint_texture already keeps for a 1-tile
## placeable).
##
## It used to be drawn at exactly the plot width, which is what had two
## houses on neighbouring plots touching at the pixel; see
## BuildingCatalog.PLOT_MARGIN_SHARE for the report and the measurement.
func test_footprint_frame_texture_draws_inside_the_footprint_width():
	var texture := sprite.footprint_frame_texture(_CONTRACT_SHEET, _COLUMNS, _ROWS, 2, 0, 16, 3)
	assert_not_null(texture)
	var expected_width := int(round(16.0 * BuildingCatalog.drawn_plot_width_tiles(3)))
	assert_eq(texture.get_width(), expected_width)
	assert_lt(texture.get_width(), 48, "the building fills its whole plot")
	var frame := sprite.sheet_frame_image(_CONTRACT_SHEET, _COLUMNS, _ROWS, 2, 0)
	var expected_height := int(round(
		float(expected_width) * float(frame.get_height()) / float(frame.get_width())
	))
	assert_eq(texture.get_height(), expected_height)


## Shrinking, never squashing: the picture keeps its own proportions, so a
## cottage does not become a bungalow on the way into its plot.
func test_drawing_inside_the_plot_keeps_the_pictures_own_proportions():
	var frame := sprite.sheet_frame_image(_CONTRACT_SHEET, _COLUMNS, _ROWS, 2, 0)
	var texture := sprite.footprint_frame_texture(_CONTRACT_SHEET, _COLUMNS, _ROWS, 2, 0, 16, 3)
	assert_almost_eq(
		float(texture.get_width()) / float(texture.get_height()),
		float(frame.get_width()) / float(frame.get_height()),
		0.02
	)



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


## A divider sheet is scaled to a real footprint like any other -- drawn
## INSIDE the plot since BuildingCatalog.PLOT_MARGIN_SHARE, which is what
## this test was really guarding: that the scaling happens at all and lands
## on the plot, not the exact pixel it used to land on.
func test_a_divider_sheet_scales_to_a_real_footprint():
	var texture: ImageTexture = sprite.footprint_frame_texture(_LIFECYCLE_SHEET, 8, 10, 3, 2, 32, 2, "dividers")
	assert_not_null(texture)
	assert_eq(
		texture.get_width(),
		int(round(32.0 * BuildingCatalog.drawn_plot_width_tiles(2))),
		"inside a two-tile plot at 32 art px per tile"
	)


# -- the farm fence: one sheet, four orientation columns -------------------


## Every facing the rule set can build really has art, under exactly the
## subject name the tile id implies -- the one link between "a rail was
## built facing east" and "an east rail is drawn".
func test_every_rail_the_village_can_build_has_its_own_art():
	for facing in VillageFarm.FENCE_TILE_IDS:
		var subject: String = VillageFarm.fence_tile_for(facing)
		assert_true(sprite.has_subject(subject), "%s has no art at all" % subject)


## Including the ones nothing raises any more. A rail already standing on
## ground somebody has walked past is an ordinary chunk modification, and an
## id that lost its art would also stop being overlay-only and paint a bare
## earth square there.
func test_every_rail_an_older_village_may_still_have_standing_keeps_its_art():
	for subject in VillageFarm.LEGACY_FENCE_TILE_IDS:
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


## The one rule the whole frame follows, and the thing reported last: "at
## the bottom it still overlaps half a tile". A rail's wood sits INSIDE its
## own tile, flush against the edge facing the beds -- so the frame touches
## the crop without ever covering it.
##
## A south rail is where that bites. Its posts' feet on its own north edge
## reads correctly as a fence seen from the front, but the body then rises
## over the bottom row of beds and hides half a tile of crop. Flush against
## the edge from the inside puts the same fence half a tile nearer the
## viewer, covering nothing.
func test_no_rails_wood_ever_crosses_into_the_beds():
	for facing in VillageFarm.FENCE_TILE_IDS:
		var subject: String = VillageFarm.fence_tile_for(facing)
		var inner: Vector2i = VillageFarm.fence_inner_direction(subject)
		var placed := _placed_wood_rect(subject)
		if inner.y > 0:
			assert_lte(placed.end.y, float(_TILE) + _EDGE_TOLERANCE, "%s hangs past its south edge" % facing)
		elif inner.y < 0:
			assert_gte(placed.position.y, -_EDGE_TOLERANCE, "%s hangs past its north edge" % facing)
		if inner.x > 0:
			assert_lte(placed.end.x, float(_TILE) + _EDGE_TOLERANCE, "%s hangs past its east edge" % facing)
		elif inner.x < 0:
			assert_gte(placed.position.x, -_EDGE_TOLERANCE, "%s hangs past its west edge" % facing)


## Flush AGAINST it, not merely inside: a rail that stops short of its own
## inner edge leaves a gap between the fence and the crop it encloses.
func test_every_rail_is_flush_against_the_edge_it_closes():
	for facing in VillageFarm.FENCE_TILE_IDS:
		var subject: String = VillageFarm.fence_tile_for(facing)
		var inner: Vector2i = VillageFarm.fence_inner_direction(subject)
		var placed := _placed_wood_rect(subject)
		if inner.y > 0:
			assert_almost_eq(placed.end.y, float(_TILE), _EDGE_TOLERANCE, facing)
		elif inner.y < 0:
			assert_almost_eq(placed.position.y, 0.0, _EDGE_TOLERANCE, facing)
		if inner.x > 0:
			assert_almost_eq(placed.end.x, float(_TILE), _EDGE_TOLERANCE, facing)
		elif inner.x < 0:
			assert_almost_eq(placed.position.x, 0.0, _EDGE_TOLERANCE, facing)


## Every rail really moves -- including the north one the first attempt at
## this wrongly left alone.
func test_every_rail_is_moved_off_the_middle_of_its_tile():
	for facing in VillageFarm.FENCE_TILE_IDS:
		var subject: String = VillageFarm.fence_tile_for(facing)
		assert_ne(
			sprite.footprint_offset(subject, _TILE), Vector2.ZERO,
			"%s is still drawn where a whole-tile structure would be" % subject
		)


## And the art ends up against the edge facing the beds.
##
## **Rewritten 2026-09-20.** This used to assert that the OFFSET VECTOR
## points toward the beds, which only holds while the art is SMALLER than
## its tile. A rail is scaled by its own post spacing now (see "consecutive
## rails share a post" below), so it is drawn larger than its tile: the
## band already starts outside the tile, and landing it flush against the
## edge facing the beds means pushing it back the other way. The offset's
## sign stopped meaning what this asserted; where the wood LANDS is what the
## rule was always about, and it is unchanged.
##
## Corners are held to both of their axes, which is the whole point of
## naming both sides (`corner_nw`/`ne`/`sw`/`se`).
func test_every_rails_wood_lands_flush_against_the_edge_facing_its_beds():
	for facing in VillageFarm.FENCE_TILE_IDS:
		var subject: String = VillageFarm.fence_tile_for(facing)
		var inner: Vector2i = VillageFarm.fence_inner_direction(subject)
		var placed := _placed_wood_rect(subject)
		if inner.x > 0:
			assert_almost_eq(placed.end.x, float(_TILE), _EDGE_TOLERANCE, subject)
		elif inner.x < 0:
			assert_almost_eq(placed.position.x, 0.0, _EDGE_TOLERANCE, subject)
		if inner.y > 0:
			assert_almost_eq(placed.end.y, float(_TILE), _EDGE_TOLERANCE, subject)
		elif inner.y < 0:
			assert_almost_eq(placed.position.y, 0.0, _EDGE_TOLERANCE, subject)



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


## **Rewritten 2026-09-20**, and the old rule is worth stating because it was
## deliberate: a rail's wood used to span EXACTLY one tile, so consecutive
## rails met "with no gap and no overlap". That closed the gaps and left the
## real defect standing -- two whole panels meeting put TWO posts at every
## junction, reported with an enclosure in shot: *"the enclosures render
## unnecessary vertical rails"*.
##
## A rail now overlaps its neighbour by exactly the post they SHARE, so its
## wood spans one tile plus one post rather than one tile. The post spacing
## is the property that matters and is pinned directly above; this pins the
## consequence, and that the overlap is a post's width rather than anything
## larger.
func test_a_broadside_runs_wood_spans_one_tile_plus_the_post_it_shares():
	for facing in ["north", "south"]:
		var placed := _placed_wood_rect(VillageFarm.fence_tile_for(facing))
		assert_gt(placed.size.x, float(_TILE), "a %s run overlaps its neighbour" % facing)
		assert_lt(
			placed.size.x, float(_TILE) * 1.5,
			"...by one shared post, not by half a rail" % []
		)


func test_a_top_view_runs_wood_spans_one_tile_plus_the_post_it_shares():
	for facing in ["east", "west"]:
		var placed := _placed_wood_rect(VillageFarm.fence_tile_for(facing))
		assert_gt(placed.size.y, float(_TILE), "a %s run overlaps its neighbour" % facing)
		assert_lt(placed.size.y, float(_TILE) * 1.5, "...by one shared post")


## Scaling by the run must not break where the run SITS -- flush against its
## own inner edge is the pair of facts that together make a closed frame
## that covers no crop.
func test_scaling_by_the_run_keeps_every_rail_flush_against_its_own_edge():
	assert_almost_eq(_placed_wood_rect("farm_fence_north").end.y, float(_TILE), _EDGE_TOLERANCE)
	assert_almost_eq(_placed_wood_rect("farm_fence_south").position.y, 0.0, _EDGE_TOLERANCE)
	assert_almost_eq(_placed_wood_rect("farm_fence_east").position.x, 0.0, _EDGE_TOLERANCE)
	assert_almost_eq(_placed_wood_rect("farm_fence_west").end.x, float(_TILE), _EDGE_TOLERANCE)


## Everything that is a whole building still scales by its own WIDTH, not by
## a run -- which is what this guard is for, and is unchanged. The width it
## scales to is its catalog footprint rather than a single tile since
## 2026-09-19 (see test_a_building_is_drawn_at_the_footprint_its_own_catalog_
## twin_claims: one tile made a farmhouse shorter than its own farmer).
func test_a_building_still_scales_by_its_width_not_by_a_run():
	for subject in ["farm", "sagewerk", "storage", "wooden_fence", "city_hall"]:
		assert_eq(
			sprite.footprint_texture(subject, _TILE).get_width(),
			_TILE * IllustratedStructureSprite.drawn_width_tiles(subject), subject
		)


# -- a corner post caps the runs, it does not extend past them --------------
#
# Reported with all three visible corners crossed out: "The fences still
# aren't optimal". A corner cell sits diagonally outside the beds, and its
# art was a full TILE of vertical rail -- while the run it caps sits on that
# tile's own EDGE, so the frame overshot by a whole tile at every corner.
#
# A corner closes two sides at once, so unlike a run it has a ground POINT
# rather than a ground line: the point where the two runs meet, which is the
# corner of its own tile facing the beds.


## The corners a village RAISES -- not the legacy ids, which knew one axis
## and are kept only so older ground keeps its art (see
## VillageFarm.LEGACY_FENCE_TILE_IDS).
func _corner_subjects() -> Array:
	var out: Array = []
	for facing in VillageFarm.FENCE_TILE_IDS:
		var subject: String = VillageFarm.fence_tile_for(facing)
		if VillageFarm.is_fence_corner_tile(subject):
			out.append(subject)
	return out


func test_a_corner_post_sits_in_the_corner_where_its_two_runs_meet():
	var corners := _corner_subjects()
	assert_gt(corners.size(), 0, "precondition: the sheet has corner posts")
	for subject in corners:
		var inner: Vector2i = VillageFarm.fence_inner_direction(subject)
		assert_ne(inner.x, 0, "%s must know which side wall it caps" % subject)
		assert_ne(inner.y, 0, "%s must know which run it caps, or it cannot sit on the join" % subject)


## Concretely, the thing that was on screen twice: a corner post may not
## hang past the run it caps, in either direction. It used to be drawn as a
## whole tile of vertical rail while the run sat on that tile's own edge.
func test_a_corner_post_never_hangs_past_the_run_it_caps():
	for subject in _corner_subjects():
		var inner: Vector2i = VillageFarm.fence_inner_direction(subject)
		var placed := _placed_wood_rect(subject)
		var past := (placed.position.y + placed.size.y - float(_TILE)) if inner.y > 0 else -placed.position.y
		assert_lt(
			past, _EDGE_TOLERANCE,
			"%s hangs %.0fpx past its own run, on a %dpx tile" % [subject, past, _TILE]
		)


# -- the divider fringe (IllustratedStructureSprite.even_cell_crop) --------

## sawmill/warehouse/city_hall draw a thin LIGHT line along every cell
## boundary and around the canvas. It is neither magenta nor near-black, so
## neither of the two keys these sheets use removes it -- a cell cut
## exactly on its grid square therefore keeps it as a hard opaque fringe up
## the frame's own edge, visible in game as a white hairline boxing every
## building in. Measured on warehouse.png: the pixel at cell corner
## (0, 384) reads (0.992, 0.969, 0.996).
const _FRINGE_MIN_CHANNEL := 0.85
const _FRINGE_MIN_ALPHA := 0.5

## Only the three sheets whose background keys to near-black: the divider
## survives both keys there. farm/wooden_fence key on magenta, which is
## what their own divider is drawn in, so it is already removed.
const _BLACK_KEYED_EVEN_SUBJECTS := ["sagewerk", "storage", "city_hall"]


func _opaque_light_pixels_on_the_border(image: Image) -> int:
	var found := 0
	for y in image.get_height():
		for x in image.get_width():
			var on_border := (
				x == 0 or y == 0
				or x == image.get_width() - 1 or y == image.get_height() - 1
			)
			if not on_border:
				continue
			var pixel := image.get_pixel(x, y)
			var light := (
				pixel.r >= _FRINGE_MIN_CHANNEL
				and pixel.g >= _FRINGE_MIN_CHANNEL
				and pixel.b >= _FRINGE_MIN_CHANNEL
			)
			if light and pixel.a >= _FRINGE_MIN_ALPHA:
				found += 1
	return found


func test_no_idle_frame_carries_the_sheets_divider_line_as_a_fringe():
	for subject in _BLACK_KEYED_EVEN_SUBJECTS:
		var image := sprite.idle_texture(subject).get_image()
		assert_eq(
			_opaque_light_pixels_on_the_border(image), 0,
			"%s keeps divider pixels on its own edge" % subject
		)


# -- the sheets' own rows (VariantSheetGrid.content_bands) ------------------

const VariantSheetGrid = preload("res://src/rendering/variant_sheet_grid.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")

## Every subject cut on the fixed grid, with the sheet and the cell it is
## cut from. Mirrors IllustratedStructureSprite's own _SUBJECTS entries for
## these five -- the divider-gridded fence rails are a different grid and
## are covered by their own tests.
const _EVEN_GRID_SUBJECTS := {
	"farm": ["res://assets/sprites/buildings/farmhouse.png", 6, 5, 1],
	"sagewerk": ["res://assets/sprites/buildings/sawmill.png", 8, 5, 1],
	"storage": ["res://assets/sprites/buildings/warehouse.png", 8, 5, 1],
	"wooden_fence": ["res://assets/sprites/structures/wooden_fence.png", 4, 4, 0],
	"city_hall": ["res://assets/sprites/buildings/city_hall.png", 8, 5, 1],
}


## Reported live: "the warehouse has the rows cropped wrongly". These
## sheets' rows are irregular -- warehouse.png's boundaries sit at 188,
## 376, 566 and 786 -- so a frame has to be cut on the row the artist
## actually drew, not on any pitch. An even fifth of the canvas (204.8)
## clipped 9px off the top of sagewerk's roof; the column pitch (192)
## clipped 13px off the bottom of city_hall.
func test_an_even_grid_frame_is_cut_on_the_sheets_own_drawn_row():
	for subject in _EVEN_GRID_SUBJECTS:
		var entry: Array = _EVEN_GRID_SUBJECTS[subject]
		var sheet: Image = SpriteSheetLoader.load_image(entry[0])
		var band: Vector2i = VariantSheetGrid.content_bands(sheet, entry[2], true)[entry[3]]
		var frame := sprite.idle_texture(subject).get_image()
		assert_eq(
			frame.get_height(), band.y - band.x + 1,
			"%s is cut to the row its art is drawn on" % subject
		)


## The columns are the one axis that really is on a pitch -- 1536/8 is
## exactly 192 and the art in every column starts ~12px inside it,
## confirmed on all four 8-column sheets. So the width stays the even cell
## minus the divider, and only the height comes from detection.
func test_an_even_grid_frame_keeps_the_measured_column_pitch():
	var frame := sprite.idle_texture("storage").get_image()
	var cell: int = 1536 / 8
	assert_eq(frame.get_width(), cell - IllustratedStructureSprite.CELL_INSET * 2)


# -- the house tiers read as a ladder, in the real art ----------------------
#
# Asked directly, with the street in shot: *"also scale down cottage to be
# smaller than house"*. Measured before changing anything
# (tools/probe_building_fit.gd): a cottage drew 26.0 x 26.0 world px against
# a house's 39.5 x 24.0 -- the smallest tier was the tallest building on the
# street, because both are drawn at the same share of their own plot width
# and the art's aspect does the rest (a cottage square, a house low and
# wide).
#
# Asked of the REAL sheets through the REAL chain, not of the catalog's
# arithmetic: what a player compares is the picture.


func _drawn_size_of(building_id: String, seed_value: int) -> Vector2i:
	var footprint := BuildingCatalog.footprint_of(building_id)
	var chosen: Dictionary = BuildingCatalog.finished_sheet_for(building_id, seed_value)
	var texture: ImageTexture = sprite.footprint_frame_texture(
		String(chosen["path"]), int(chosen["columns"]), int(chosen["rows"]),
		int(chosen["row"]), int(chosen["column"]), 32, footprint.x,
		String(chosen["grid"]), building_id
	)
	assert_not_null(texture, "%s draws nothing at all" % building_id)
	return Vector2i(texture.get_width(), texture.get_height())


func test_a_cottage_really_draws_smaller_than_a_house():
	for seed_value in [3, 29, 91]:
		var cottage := _drawn_size_of("house_small", seed_value)
		var house := _drawn_size_of("house_medium", seed_value)
		assert_lt(cottage.x, house.x, "seed %d: a cottage is narrower" % seed_value)
		assert_lt(cottage.y, house.y, "seed %d: and shorter -- it was taller" % seed_value)


func test_a_house_really_draws_smaller_than_a_manor():
	for seed_value in [3, 29, 91]:
		var house := _drawn_size_of("house_medium", seed_value)
		var manor := _drawn_size_of("house_large", seed_value)
		assert_lt(house.y, manor.y, "seed %d: a manor looms over a house" % seed_value)
		assert_lte(house.x, manor.x, "seed %d" % seed_value)


## Still a building standing on its plot rather than a model of one -- the
## same floor PLOT_MARGIN_SHARE is already pinned against.
func test_a_cottage_still_fills_most_of_its_plot():
	var cottage := _drawn_size_of("house_small", 29)
	assert_gt(float(cottage.x) / float(2 * 32), 0.6, "a cottage this small is a doll's house")


# -- the crop must hold the WHOLE drawing (2026-09-20) ----------------------
#
# Reported live with five cottages in shot: *"Cottages are still slightly
# clipped at the top despite having free space in the 2x2 tile."* They
# were, and the cut happened in the SLICER, long before anything placed
# them: the roof apex, its finial and the chimney cap were all outside the
# cropped cell.
#
# The cause is measurable and is not about houses. `divider_bands` calls a
# sheet row a divider when 60% of it is magenta, which is true of a row
# crossing eight roof APEXES -- sparse art against background reads as
# background. On cottage_*.png and manor_*.png there is no drawn divider to
# find at all (no row anywhere is even 99% magenta; measured max 0.989),
# so the band simply started wherever the roofs' silhouette happened to
# thin past the threshold.
#
# The invariant below is the one that catches that class of bug whatever
# its cause: **the sheet row directly above a cell's crop must be clear of
# that cell's own art.** If it is not, the crop cut through the drawing.

## Every house sheet a real building draws from, with the grid kind and
## cell the game itself would ask for.
func _house_sheet_cells() -> Array:
	var cells: Array = []
	for building_id in BuildingCatalog.BUILDING_IDS:
		for seed_value in [1, 3, 7, 42]:
			var chain: Array = BuildingCatalog.finished_sheet_chain(building_id, seed_value)
			if chain.is_empty():
				continue
			var entry: Dictionary = chain[0]
			entry["building_id"] = building_id
			cells.append(entry)
	return cells


## How much of one sheet row has anything on it at all -- anything that is
## not the chroma-key background -- across `from_x`..`to_x`.
func _drawn_share(image: Image, y: int, from_x: int, to_x: int) -> float:
	var span := to_x - from_x + 1
	if span <= 0:
		return 0.0
	var drawn := 0
	for x in range(from_x, to_x + 1):
		var color := image.get_pixel(x, y)
		var background: bool = color.r >= 0.85 and color.b >= 0.85 and color.g <= 0.15
		if not background:
			drawn += 1
	return float(drawn) / float(span)


## The band of "partly covered" that means a crop sliced through a picture.
##
## The row directly above a correct crop is one of two things, and neither
## is partial:
##
## - **essentially empty** (0% to 17% covered) -- open background where the
##   sheet simply spaces its rows apart, the remainder being antialiasing
##   where a chimney cap meets the gap;
## - **essentially full** (100%) -- the sheet's own boundary, which on
##   these sheets is two rows deep (a solid dark line under a pale rule),
##   or the bottom edge of the neighbouring cell.
##
## A row that is *partly* covered is neither: it is the silhouette of a
## roof, which is exactly the thing a bad crop cuts through. Every cut
## measured before the fix sat at **40% to 52%**. So the test is a band,
## not a bound -- and that shape is the finding, not a convenience.
const _CUT_ROW_MIN := 0.25
const _CUT_ROW_MAX := 0.90


func test_no_house_crop_cuts_through_the_top_of_its_own_drawing():
	var sprite := IllustratedStructureSprite.new()
	for entry in _house_sheet_cells():
		var image: Image = (load(entry["path"]) as Texture2D).get_image()
		var rect: Rect2i = sprite._cell_rect_for(
			entry["path"], image, entry["columns"], entry["rows"], entry["row"], entry["column"], entry["grid"]
		)
		var above := rect.position.y - 1
		if above < 0:
			continue  # a cell on the sheet's own top edge has nothing above it
		var share := _drawn_share(image, above, rect.position.x, rect.position.x + rect.size.x - 1)
		assert_false(
			share >= _CUT_ROW_MIN and share <= _CUT_ROW_MAX,
			"%s (%s cell %d,%d): the sheet row above the crop is %d%% covered -- neither empty nor a boundary, so the crop sliced through a roof"
			% [entry["building_id"], String(entry["path"]).get_file(), entry["column"], entry["row"], int(share * 100.0)]
		)


## The other half of the same fix. Reading a cell by where its ART is
## reaches up past the roof -- and on some cells that is far enough to
## swallow the sheet's own drawn RULE LINE, which then ships as a pale bar
## across the top of the cottage. A roof apex is sparse (9 to 31 opaque
## pixels of ~174); a rule line spans the whole cell. Measured: cottage_2
## and cottage_4 grew one, cottage_3 did not.
func test_no_house_crop_opens_with_the_sheets_own_rule_line():
	var sprite := IllustratedStructureSprite.new()
	for entry in _house_sheet_cells():
		var frame: Image = sprite._frame_image(
			entry["path"], entry["columns"], entry["rows"], entry["row"], entry["column"], entry["grid"]
		)
		assert_not_null(frame, "%s draws nothing" % entry["building_id"])
		if frame == null:
			continue
		for y in mini(3, frame.get_height()):
			assert_false(
				_is_rule_line_row(frame, y),
				"%s (%s cell %d,%d): row %d of the crop is the sheet's rule line, not the drawing"
				% [entry["building_id"], String(entry["path"]).get_file(), entry["column"], entry["row"], y]
			)


## A full-width bar of pale pixels: the sheet's drawn rule, never a roof.
func _is_rule_line_row(image: Image, y: int) -> bool:
	var width := image.get_width()
	var opaque := 0
	var pale := 0
	for x in width:
		var color := image.get_pixel(x, y)
		if color.a <= 0.02:
			continue
		opaque += 1
		if color.r >= 0.85 and color.g >= 0.85 and color.b >= 0.85:
			pale += 1
	if opaque < int(float(width) * 0.8):
		return false
	return float(pale) / float(maxi(opaque, 1)) >= 0.5


# -- and consecutive rails SHARE a post, rather than merely meeting ---------
#
# Reported with a finished enclosure in shot: *"the enclosures render
# unnecessary vertical rails"*.
#
# Every cell of fence.png is a whole panel -- a post at EACH end with rails
# between. Making a rail's wood span exactly one tile (the "also scale" pass
# above) closed the gaps between rails and left this untouched: two whole
# panels meeting put TWO posts at every junction, a few pixels apart, which
# is what reads as a doubled rail. A run of six rails showed twelve posts
# where it should show seven.
#
# The fix is one number, and it is measured from the art rather than assumed
# (see _post_spacing_of): a rail is scaled so its own two POST CENTRES sit
# exactly one tile apart. Its posts then land on its tile's two edges, the
# neighbour's near post lands on the same point, and the two draw as one.


## The distance between the drawn panel's two post centres, along the axis
## its run travels -- measured on the DRAWN texture, so this checks the
## result a player sees rather than the arithmetic that produced it. Uses
## IllustratedStructureSprite's own reader, since inventing a second one here
## would just be a second thing to get wrong; the reader ITSELF is pinned
## against the real sheet by the art-fact test below.
func _drawn_post_spacing(subject: String) -> float:
	var image := sprite.footprint_texture(subject, _TILE).get_image()
	var inner: Vector2i = VillageFarm.fence_inner_direction(subject)
	# a fresh key per call: the production cache is keyed by SUBJECT, and the
	# drawn image is not the source one it was measured from
	return IllustratedStructureSprite._post_spacing_of(
		"drawn:%s:%d" % [subject, _TILE], image, inner.x != 0
	)


## The reader is only trustworthy if it finds real posts in the real sheet,
## so pin what it measures at SOURCE resolution: all four facings are the
## same panel design, and their posts sit around 0.62-0.65 of the run apart.
## If the art is ever redrawn or re-exported this fails and says so, rather
## than silently rescaling every fence in the world.
func test_the_post_reader_finds_two_posts_about_two_thirds_of_the_run_apart():
	for facing in ["north", "south", "east", "west"]:
		var subject := VillageFarm.fence_tile_for(facing)
		var source := sprite.idle_texture(subject).get_image()
		var inner: Vector2i = VillageFarm.fence_inner_direction(subject)
		var vertical_run: bool = inner.x != 0
		var along := source.get_height() if vertical_run else source.get_width()
		var spacing: float = IllustratedStructureSprite._post_spacing_of(
			"source:%s" % subject, source, vertical_run
		)
		assert_between(
			spacing / float(along), 0.55, 0.72,
			"%s: two posts, about two thirds of the run apart" % facing
		)


## The reported defect itself, on every facing: one tile between a rail's own
## two posts is what makes the next rail's post land on the same spot.
func test_consecutive_rails_share_a_post_rather_than_doubling_it():
	for facing in ["north", "south", "east", "west"]:
		var subject := VillageFarm.fence_tile_for(facing)
		assert_almost_eq(
			_drawn_post_spacing(subject), float(_TILE), 1.0,
			"a %s rail's posts must sit one tile apart, so the next rail shares one" % facing
		)


## Six rails in a row show SEVEN posts -- the property stated the way a
## player counts it, and checked by actually laying six rails out and
## counting, rather than by deriving a number from the spacing above.
##
## Composited exactly as EarthChunkManager._spawn_structure_art_for places
## them: each panel centred on its own tile, bottom-anchored, shifted by
## footprint_offset. The end posts come out a shade narrower than the inner
## ones because half of each hangs past the end of the run, which is what an
## end post should do.
func test_a_run_of_six_rails_really_shows_seven_posts():
	const RUN := 6
	var subject := "farm_fence_north"
	var panel := sprite.footprint_texture(subject, _TILE).get_image()
	var offset: Vector2 = sprite.footprint_offset(subject, _TILE)
	var canvas := Image.create(
		RUN * _TILE + panel.get_width(), _TILE * 2, false, Image.FORMAT_RGBA8
	)
	for i in range(RUN):
		var centre_x := float(i) * _TILE + _TILE * 0.5
		var left := int(round(centre_x - float(panel.get_width()) * 0.5 + offset.x))
		var top := int(round(float(_TILE) - float(panel.get_height()) + offset.y)) + _TILE / 2
		canvas.blend_rect(
			panel, Rect2i(Vector2i.ZERO, panel.get_size()),
			Vector2i(left + panel.get_width() / 2, maxi(top, 0))
		)
	assert_eq(_posts_across(canvas), RUN + 1, "one post per tile boundary, and one at each end")


## How many posts a composited run really shows: columns standing above the
## rail level, in bands wide enough not to be a stray.
func _posts_across(canvas: Image) -> int:
	var coverage: Array[float] = []
	var content: Array[float] = []
	for x in range(canvas.get_width()):
		var opaque := 0
		for y in range(canvas.get_height()):
			if canvas.get_pixel(x, y).a > 0.5:
				opaque += 1
		var v := float(opaque) / float(canvas.get_height())
		coverage.append(v)
		if v > 0.02:
			content.append(v)
	if content.size() < 3:
		return 0
	content.sort()
	var rail_level: float = content[content.size() / 2]
	var high: float = content[mini(int(float(content.size()) * 0.9), content.size() - 1)]
	var threshold: float = rail_level + (high - rail_level) * 0.4
	var posts := 0
	var run_start := -1
	for x in range(canvas.get_width()):
		var is_post: bool = coverage[x] >= threshold
		if is_post and run_start < 0:
			run_start = x
		if (not is_post) and run_start >= 0:
			if x - run_start >= 3:
				posts += 1
			run_start = -1
	if run_start >= 0 and canvas.get_width() - run_start >= 3:
		posts += 1
	return posts
