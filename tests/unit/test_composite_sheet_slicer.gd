extends GutTest

## Cutting a composite sheet into its individual drawings (see
## CompositeSheetSlicer).
##
## The tree art arrives as ONE image holding a canopy strip, a trunk and
## several fruit -- laid out for a human to read, not on a fixed grid. The
## regions are different sizes and there are different numbers of them per
## species, so the slicer finds them rather than being told where they are.

const CompositeSheetSlicer = preload("res://src/rendering/composite_sheet_slicer.gd")


func _sheet() -> Image:
	return Image.load_from_file("res://assets/sprites/trees/composite_walnut.png")


# -- finding the drawings ----------------------------------------------------

## The walnut sheet holds four canopies, a trunk and four fruit.
func test_it_finds_every_drawing_on_the_sheet():
	var regions := CompositeSheetSlicer.regions_in(_sheet())
	assert_eq(regions.size(), 9, "expected 4 canopies + 1 trunk + 4 fruit")


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
