extends RefCounted

## Which picture a village house has, at every point in its life
## (docs/concept/building.md, "Building lifecycle variation sheets").
##
## The sheets delivered 2026-09-17 -- house_1_1.png .. house_1_5.png -- are
## a richer contract than the older 8x5 lifecycle sheet: **8 columns x 10
## rows**, cells separated by magenta divider lines, with a column-label row
## across the top and a row-label gutter down the left (read by
## VariantSheetGrid.art_bands, measured by
## tools/probe_building_lifecycle_sheet.gd). The sheets print their own row
## meanings, and these are those labels:
##
##   00 Build (Foundation)    03 Complete (Idle 1)   06 Damaged (1)
##   01 Build (Frames)        04 Idle 2 (Details)    07 Damaged (2)
##   02 Build (Construction)  05 Idle 3 (Variants)   08 Destroyed (1)
##                                                   09 Destroyed (2)
##
## Three build rows of eight frames is a real 24-frame construction
## animation per variation -- the thing the older sheets' single eight-cell
## construction row could only gesture at -- and three idle rows are 24
## finished looks on top, so a street of cottages is a street of different
## cottages AND each one is the same house it was while it was rising.
##
## Pure and static: a seed and a progress in, a cell out. Where that cell is
## in pixels is VariantSheetGrid's question; how it reaches the screen is
## IllustratedStructureSprite's.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

const COLUMNS := 8
const ROWS := 10

## The sheets' own printed row labels, in their own order. Every row of the
## sheet belongs to exactly one of these (test-pinned), so nothing is drawn
## from a row whose meaning nobody wrote down.
const BUILD_ROWS: Array[int] = [0, 1, 2]
const IDLE_ROWS: Array[int] = [3, 4, 5]
const DAMAGED_ROWS: Array[int] = [6, 7]
const DESTROYED_ROWS: Array[int] = [8, 9]

## Every frame of the build, read left to right and row by row --
## BUILD_ROWS.size() * COLUMNS. Written out because GDScript cannot call
## Array.size() in a const initialiser that another script reads, and
## pinned to that product by test_the_build_animation_is_every_frame_of_
## every_build_row so it cannot drift from the grid it describes.
const BUILD_FRAMES := 24

const _COTTAGE_VARIATIONS: Array[String] = [
	"res://assets/sprites/buildings/house_1_1.png",
	"res://assets/sprites/buildings/house_1_2.png",
	"res://assets/sprites/buildings/house_1_3.png",
	"res://assets/sprites/buildings/house_1_4.png",
	"res://assets/sprites/buildings/house_1_5.png",
]

## Which building ids have real lifecycle variation sheets.
##
## All three village HOUSES share the five cottage sheets, for the same
## reason building.md already gives for the flat variant sheet they share:
## declaring the art for only the smallest tier would leave a street half
## beautiful cottages and half boxes. The scaler sizes each cell to its own
## footprint without distorting it, so a larger house is simply a bigger
## cottage, and a different seed picks a different one anyway.
##
## Nothing that is not a home is listed. A hall, a mill or a brewery drawn
## as a cottage would be drawing the wrong building, and each already has
## its own 8x5 sheet.
const VARIATION_SHEETS := {
	"house_small": _COTTAGE_VARIATIONS,
	"house_medium": _COTTAGE_VARIATIONS,
	"house_large": _COTTAGE_VARIATIONS,
}


## Every lifecycle variation sheet declared for this building, or [] for
## one that has none. Whether the files are on disk is the renderer's
## question, not this module's -- a missing sheet falls back through the
## same chain a missing lifecycle sheet already does.
static func variation_sheets_of(building_id: String) -> Array:
	return VARIATION_SHEETS.get(building_id, [])


## Which of them THIS building draws from -- deterministic from its own
## seed, so a house is the same house on every reload. "" for a building
## with no variations.
static func sheet_for(building_id: String, seed_value: int) -> String:
	var sheets := variation_sheets_of(building_id)
	if sheets.is_empty():
		return ""
	return sheets[PixelNoise.range_index(seed_value, 53, 59, sheets.size())]


## The cell a site at `progress` in [0, 1] is rising through: the build
## frames in order, left to right and row by row, so foundation gives way
## to frames and frames to a roofed shell. Progress outside the range
## clamps to the first and last frame rather than reading off the sheet.
static func build_cell_for(progress: float) -> Vector2i:
	var frame := clampi(floori(clampf(progress, 0.0, 1.0) * BUILD_FRAMES), 0, BUILD_FRAMES - 1)
	return Vector2i(frame % COLUMNS, BUILD_ROWS[frame / COLUMNS])


## The cell a FINISHED house stands in -- one of the idle rows, on its own
## seeded column. Row and column are drawn from independent hashes of the
## same seed so the pair spreads over the whole idle block rather than
## walking a diagonal (test-pinned: all of them are reachable), the same
## shape BuildingCatalog.variant_cell_for already uses.
static func idle_cell_for(seed_value: int) -> Vector2i:
	return Vector2i(
		PixelNoise.range_index(seed_value, 61, 67, COLUMNS),
		IDLE_ROWS[PixelNoise.range_index(seed_value, 71, 73, IDLE_ROWS.size())]
	)
