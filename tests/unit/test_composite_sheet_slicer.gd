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
## frame -- see IllustratedTree), a trunk drawn once per canopy column
## (season-tinted, five copies -- see IllustratedTree._trunk_row, which
## collapses these back to one), and a much richer fruit block than the
## sheet used to carry: 20 more drawings below the trunk row, a mix of
## on-tree and harvested stages. 30 total, not the 10 this test pinned
## against the sheet's old, simpler layout (5 canopies + 1 trunk + 4
## fruit) -- CompositeSheetSlicer's job is only to find every real drawing,
## whatever the sheet's own layout turns out to be; IllustratedTree is what
## gives meaning to which of them is which.
func test_it_finds_every_drawing_on_the_sheet():
	var regions := CompositeSheetSlicer.regions_in(_sheet())
	assert_eq(regions.size(), 30)


# -- splitting a blob with more than one solid core --------------------------
#
# The real bug this guards against, measured on the current tree art: two
# neighbouring canopy crowns drawn close enough that their edges touch
# (cherry blossom against the leaf canopy beside it), and a canopy column
# fused straight into its own trunk by a scatter of falling-leaf debris in
# the gap between them (hazelnut, apple). Both are two real drawings joined
# by content that is real but never more than a coarse cell thin -- see
## CompositeSheetSlicer's own doc comment on _is_thick for the fix.

## Two solid blobs joined only by a thin connecting line must be found as
## two drawings, not fused into one -- the thin bridge is real content (not
## background), so it survives is_background, and it is connected (not
## background-separated), so a plain flood fill fuses it with both sides.
func test_two_solid_blobs_joined_by_a_thin_bridge_are_found_separately():
	var image := Image.create(200, 100, false, Image.FORMAT_RGBA8)
	_fill_rect(image, Rect2i(10, 10, 48, 48))
	_fill_rect(image, Rect2i(142, 10, 48, 48))
	# A single-pixel-tall connecting line, clear of both blobs' own rows --
	# a coarse (DETECTION_STEP) sample still catches it as connected content,
	# but no 2x2 block of coarse cells around it is ever entirely filled.
	for x in range(58, 143):
		image.set_pixel(x, 36, Color(0, 0, 0, 1))
	var regions := CompositeSheetSlicer.regions_in(image)
	assert_eq(regions.size(), 2, "a thin bridge should not fuse two real drawings into one")


## The safety this must not cost: a single real drawing with one solid mass
## and thin extremities reaching out from it (a trunk with bare branches --
## exactly the bare-winter canopy's own shape) must stay ONE region, not
## fragment at every thin stretch just because it, too, is only a coarse
## cell wide there.
func test_a_single_blob_with_thin_extremities_stays_one_region():
	var image := Image.create(200, 100, false, Image.FORMAT_RGBA8)
	_fill_rect(image, Rect2i(80, 40, 40, 40))
	# Four thin "branches" radiating out from the one solid core -- never
	# more than a pixel wide, exactly like the bridge above, but attached to
	# only one real mass rather than joining two.
	for x in range(20, 80):
		image.set_pixel(x, 60, Color(0, 0, 0, 1))
	for x in range(120, 180):
		image.set_pixel(x, 60, Color(0, 0, 0, 1))
	for y in range(0, 40):
		image.set_pixel(100, y, Color(0, 0, 0, 1))
	for y in range(80, 100):
		image.set_pixel(100, y, Color(0, 0, 0, 1))
	var regions := CompositeSheetSlicer.regions_in(image)
	assert_eq(regions.size(), 1, "thin extremities of a single drawing must not fragment it")


func _fill_rect(image: Image, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			image.set_pixel(x, y, Color(0, 0, 0, 1))


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
## acorn and apple were the two sheets this used to exercise against real
## art -- both have SINCE been re-exported with real alpha (measured:
## FORMAT_RGBA8, transparent corner), so needs_keying now reads false for
## every one of the six current sheets and cut_out no-ops on all of them.
## The mechanism this protects -- reachability keying, and the aggressive
## erosion only the bare-winter frame may ever use -- stays real, reachable
## code (a sheet regeneration has already reintroduced an opaque background
## once before; nothing stops a future one doing it again), so it stays
## tested here against a synthetic sheet built to have the exact shape of
## problem the real ones used to, rather than losing coverage along with
## the two real sheets that used to demonstrate it.

## A synthetic sheet with an opaque, near-white background and no alpha
## channel of its own -- exactly the shape needs_keying's own doc comment
## describes -- carrying two drawings side by side:
##
## - A "bare-branch" drawing (left half): a coloured frame enclosing a
##   background-coloured interior that never touches the crop's own edge --
##   the real bug this regresses against, where the gaps between real bare
##   branches stayed opaque because reachability alone cannot reach an
##   ENCLOSED pocket of background-coloured pixels.
## - A "snow" drawing (right half): the same enclosing-frame shape, so it is
##   exactly as unreachable from its own crop's edge, but standing in for
##   real near-white content colour alone cannot tell from background (see
##   CANOPY_SNOW) rather than an actual gap.
##
## Structurally identical on purpose: the only thing that may ever tell
## them apart is which ROLE IllustratedTree asks cut_out to treat them as
## (aggressive for the bare-winter frame only, default everywhere else),
## never anything intrinsic to the pixels -- which is exactly the design
## tension the `aggressive` flag exists to resolve.
func _opaque_background_sheet() -> Image:
	var image := Image.create(120, 60, false, Image.FORMAT_RGB8)
	image.fill(Color(0.99, 0.99, 0.99, 1.0))
	_frame_with_enclosed_interior(image, Rect2i(10, 10, 40, 40))
	_frame_with_enclosed_interior(image, Rect2i(70, 10, 40, 40))
	return image


## A 4px-thick coloured frame around `rect`'s edge, leaving its interior at
## the sheet's own background colour -- enclosed, and so unreachable from
## outside the frame.
func _frame_with_enclosed_interior(image: Image, rect: Rect2i) -> void:
	var frame_color := Color(0.3, 0.2, 0.1, 1.0)
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var on_edge: bool = (
				x < rect.position.x + 4 or x >= rect.position.x + rect.size.x - 4
				or y < rect.position.y + 4 or y >= rect.position.y + rect.size.y - 4
			)
			if on_edge:
				image.set_pixel(x, y, frame_color)


func _opaque_fraction(image: Image) -> float:
	var opaque := 0
	var total := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			total += 1
			if image.get_pixel(x, y).a > 0.5:
				opaque += 1
	return float(opaque) / float(maxi(total, 1))


## A sheet with no alpha channel at all needs cut_out to convert the cropped
## piece before it can key anything out, or every set_pixel(..., transparent)
## is silently a no-op (see cut_out's own doc comment on this) -- the bug
## this regresses against, found on acorn's and apple's sheets back when
## they still had this shape.
func test_needs_keying_sheets_have_no_alpha_channel_of_their_own():
	assert_eq(_opaque_background_sheet().get_format(), Image.FORMAT_RGB8)


## The bug this regresses against: a bare-winter canopy frame stayed almost
## entirely opaque after cut_out, both from the format bug above and from
## plain reachability leaving the gaps between branches -- which do not
## touch the crop's own edge -- untouched. `aggressive` fixes both: the
## enclosed interior is real background colour here, so aggressive keying
## should clear nearly all of it.
func test_aggressive_keying_makes_the_bare_winter_frame_read_sparse():
	var sheet := _opaque_background_sheet()
	var bare := CompositeSheetSlicer.cut_out(sheet, Rect2i(10, 10, 40, 40), true)
	assert_lt(
		_opaque_fraction(bare), 0.4,
		"an aggressively-keyed bare-winter frame should read mostly sparse, not solid"
	)


## The danger this guards against: a sheet may also carry a snow-covered
## canopy frame (see IllustratedTree.CANOPY_SNOW) with real near-white
## content colour alone cannot tell from background. Default (non-
## aggressive) cut_out -- the only mode ever used on this frame -- must
## leave it mostly intact: its enclosed interior is exactly as unreachable
## as the bare-winter frame's own, but reachability-only keying protects
## anything it cannot reach, whatever colour it is.
func test_default_keying_leaves_real_snow_content_alone():
	var sheet := _opaque_background_sheet()
	var snow := CompositeSheetSlicer.cut_out(sheet, Rect2i(70, 10, 40, 40))
	assert_gt(
		_opaque_fraction(snow), 0.9,
		"a default-keyed snow frame should stay almost entirely opaque -- it is real content, not background"
	)


## Demonstrates exactly why `aggressive` must stay off everywhere but the
## bare-winter frame: run on the very same shape of enclosed content, it
## erodes real content far below what default keying leaves it at. This is
## the reason IllustratedTree only ever passes aggressive=true for canopy
## index 0, and never for the snow frame, the other three seasons, the
## trunk, or any fruit stage.
func test_aggressive_keying_would_wrongly_erode_the_snow_frame_if_ever_used_there():
	var sheet := _opaque_background_sheet()
	var snow_region := Rect2i(70, 10, 40, 40)
	var protected_fraction := _opaque_fraction(CompositeSheetSlicer.cut_out(sheet, snow_region))
	var eroded_fraction := _opaque_fraction(CompositeSheetSlicer.cut_out(sheet, snow_region, true))
	assert_lt(
		eroded_fraction, protected_fraction - 0.2,
		"aggressive keying should visibly eat into real snow content -- proof it must stay scoped"
	)
