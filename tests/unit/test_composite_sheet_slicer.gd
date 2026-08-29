extends GutTest

## Cutting a composite sheet into its individual drawings (see
## CompositeSheetSlicer).
##
## The tree art arrives as ONE image holding a canopy strip, a trunk and
## several fruit -- laid out for a human to read, not on a fixed grid. The
## regions are different sizes and there are different numbers of them per
## species, so the slicer finds them rather than being told where they are.

const CompositeSheetSlicer = preload("res://src/rendering/composite_sheet_slicer.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")


## SpriteSheetLoader rather than a raw Image.load_from_file: this sheet
## already has a real .import (assets/sprites/trees/composite_walnut.png.
## import), so a raw file read logs "Loaded resource as image file, this
## will not work on export" -- and since this helper has no cache, every one
## of this file's tests calls it fresh, so every one of them failed GUT's
## unhandled-engine-error check (see SpriteSheetLoader's own doc comment).
func _sheet() -> Image:
	return SpriteSheetLoader.load_image("res://assets/sprites/trees/composite_walnut.png")


# -- finding the drawings ----------------------------------------------------

## The walnut sheet holds five canopies (four seasons plus the CANOPY_SNOW
## frame -- see IllustratedTree), a trunk and four fruit.
func test_it_finds_every_drawing_on_the_sheet():
	var regions := CompositeSheetSlicer.regions_in(_sheet())
	assert_eq(regions.size(), 10, "expected 5 canopies + 1 trunk + 4 fruit")


## Regions come back in reading order -- top to bottom, then left to right
## within a band -- because that is the order a person laid them out in.
func test_regions_come_back_in_reading_order():
	var regions := CompositeSheetSlicer.regions_in(_sheet())
	for index in range(1, regions.size()):
		var previous: Rect2i = regions[index - 1]
		var current: Rect2i = regions[index]
		var same_band: bool = current.position.y < previous.position.y + previous.size.y
		if same_band:
			assert_gte(current.position.x, previous.position.x, "band is out of order")
		else:
			assert_gte(current.position.y, previous.position.y, "bands are out of order")


## Every region actually contains a drawing -- an empty rectangle means the
## gutter detection cut in the wrong place.
func test_every_region_holds_something():
	var sheet := _sheet()
	for region in CompositeSheetSlicer.regions_in(sheet):
		assert_gt(
			_content_share(sheet.get_region(region)), 0.02,
			"an empty region at %s" % region
		)


## No region may swallow a neighbour: the biggest is the trunk, and even that
## is a fraction of the sheet. A single region covering everything means the
## gutters were never found.
func test_no_region_swallows_the_whole_sheet():
	var sheet := _sheet()
	var sheet_area := sheet.get_width() * sheet.get_height()
	for region in CompositeSheetSlicer.regions_in(sheet):
		assert_lt(
			float(region.size.x * region.size.y) / float(sheet_area), 0.5,
			"one region covers half the sheet -- the gutters were missed"
		)


## Regions must not overlap; a drawing belongs to exactly one of them.
func test_regions_do_not_overlap():
	var regions := CompositeSheetSlicer.regions_in(_sheet())
	for outer in regions.size():
		for inner in range(outer + 1, regions.size()):
			assert_false(
				regions[outer].intersects(regions[inner]),
				"%s overlaps %s" % [regions[outer], regions[inner]]
			)


# -- the background ----------------------------------------------------------

## The sheets come with a mix of backgrounds: mostly transparent, but with
## semi-opaque near-white in places. Treating only alpha as background found
## no gutters at all on the walnut sheet.
func test_both_transparent_and_white_count_as_background():
	assert_true(CompositeSheetSlicer.is_background(Color(0, 0, 0, 0)))
	assert_true(CompositeSheetSlicer.is_background(Color(0.99, 0.99, 0.99, 0.9)))
	assert_true(CompositeSheetSlicer.is_background(Color(1, 1, 1, 1)))


## ...but pale DRAWING is not background. Walnut meat and cherry blossom are
## both nearly white, and losing them would eat the fruit off the sheet.
func test_pale_drawing_is_not_background():
	assert_false(CompositeSheetSlicer.is_background(Color(0.93, 0.85, 0.65, 1.0)))
	assert_false(CompositeSheetSlicer.is_background(Color(0.96, 0.88, 0.9, 1.0)))


func _content_share(image: Image) -> float:
	var content := 0
	var total := 0
	for y in range(0, image.get_height(), 3):
		for x in range(0, image.get_width(), 3):
			total += 1
			if not CompositeSheetSlicer.is_background(image.get_pixel(x, y)):
				content += 1
	return float(content) / float(maxi(total, 1))


# -- cutting out an opaque (needs_keying) background -------------------------
##
## acorn and apple are the only two of the six species that still arrive
## with an opaque background rather than real alpha (see needs_keying's own
## doc comment) -- everything below exercises cut_out against their real art.

func _acorn_sheet() -> Image:
	return SpriteSheetLoader.load_image("res://assets/sprites/trees/composite_acorn.png")


func _apple_sheet() -> Image:
	return SpriteSheetLoader.load_image("res://assets/sprites/trees/composite_apple.png")


func _opaque_fraction(image: Image) -> float:
	var opaque := 0
	var total := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			total += 1
			if image.get_pixel(x, y).a > 0.5:
				opaque += 1
	return float(opaque) / float(maxi(total, 1))


## Both sheets decode with no alpha channel at all -- cut_out has to convert
## the cropped piece before it can key anything out, or every
## set_pixel(..., transparent) is silently a no-op (see cut_out's own doc
## comment on this).
func test_needs_keying_sheets_have_no_alpha_channel_of_their_own():
	assert_eq(_acorn_sheet().get_format(), Image.FORMAT_RGB8)
	assert_eq(_apple_sheet().get_format(), Image.FORMAT_RGB8)


## The bug this regresses against: the bare-winter canopy frame (the first
## region in the canopy band -- see IllustratedTree.CANOPY_BARE) stayed
## almost entirely opaque after cut_out, both from the format bug above and
## from plain reachability leaving the gaps between branches -- which do not
## touch the crop's own edge -- untouched. `aggressive` fixes both.
##
## Measured opaque fraction once fixed: 0.31 (acorn), 0.24 (apple), against
## ~1.0 before -- the threshold below leaves real margin against noise while
## still catching a regression back toward "so opaque it never shed the
## gaps at all".
func test_aggressive_keying_makes_the_bare_winter_frame_read_sparse():
	var acorn := _acorn_sheet()
	var acorn_bare := CompositeSheetSlicer.cut_out(
		acorn, CompositeSheetSlicer.regions_in(acorn)[0], true
	)
	assert_lt(
		_opaque_fraction(acorn_bare), 0.4,
		"acorn's bare-winter frame should read mostly sparse, not solid"
	)
	var apple := _apple_sheet()
	var apple_bare := CompositeSheetSlicer.cut_out(
		apple, CompositeSheetSlicer.regions_in(apple)[0], true
	)
	assert_lt(
		_opaque_fraction(apple_bare), 0.4,
		"apple's bare-winter frame should read mostly sparse, not solid"
	)


## The danger this guards against: both sheets also carry a fifth, snow-
## covered canopy frame (see IllustratedTree.CANOPY_SNOW) with real
## near-white content colour alone cannot tell from background. Default
## (non-aggressive) cut_out -- the only mode ever used on this frame -- must
## leave it mostly intact.
##
## Measured opaque fraction: 0.55 (acorn), 0.59 (apple); a real margin below
## both is pinned here.
func test_default_keying_leaves_real_snow_content_alone():
	var acorn := _acorn_sheet()
	var acorn_snow := CompositeSheetSlicer.cut_out(acorn, CompositeSheetSlicer.regions_in(acorn)[4])
	assert_gt(
		_opaque_fraction(acorn_snow), 0.45,
		"acorn's snow frame should stay mostly opaque -- it is real content, not background"
	)
	var apple := _apple_sheet()
	var apple_snow := CompositeSheetSlicer.cut_out(apple, CompositeSheetSlicer.regions_in(apple)[4])
	assert_gt(
		_opaque_fraction(apple_snow), 0.45,
		"apple's snow frame should stay mostly opaque -- it is real content, not background"
	)


## Demonstrates exactly why `aggressive` must stay off everywhere but the
## bare-winter frame: run on the very same snow frame, it erodes real
## content far below what default keying leaves it at -- measured 0.55 ->
## 0.23 (acorn). This is the reason IllustratedTree only ever passes
## aggressive=true for canopy index 0, and never for the snow frame, the
## other three seasons, the trunk, or any fruit stage.
func test_aggressive_keying_would_wrongly_erode_the_snow_frame_if_ever_used_there():
	var acorn := _acorn_sheet()
	var snow_region: Rect2i = CompositeSheetSlicer.regions_in(acorn)[4]
	var protected_fraction := _opaque_fraction(CompositeSheetSlicer.cut_out(acorn, snow_region))
	var eroded_fraction := _opaque_fraction(CompositeSheetSlicer.cut_out(acorn, snow_region, true))
	assert_lt(
		eroded_fraction, protected_fraction - 0.2,
		"aggressive keying should visibly eat into real snow content -- proof it must stay scoped"
	)
