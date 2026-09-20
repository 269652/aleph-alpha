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

## The middle tier's own five sheets, on the 8x10 contract described above.
const _HOUSE_VARIATIONS: Array[String] = [
	"res://assets/sprites/buildings/house_1_1.png",
	"res://assets/sprites/buildings/house_1_2.png",
	"res://assets/sprites/buildings/house_1_3.png",
	"res://assets/sprites/buildings/house_1_4.png",
	"res://assets/sprites/buildings/house_1_5.png",
]

## The smallest tier's own five, delivered 2026-09-19 -- and on the OLDER
## 8x5 contract (BuildingCatalog.SHEET_COLUMNS/SHEET_ROWS: construction,
## active, idle, burning, ruined), not house_1_*'s richer one.
##
## MEASURED, not assumed, per this codebase's own "probe before you trust a
## grid" convention: tools/probe_building_lifecycle_sheet.gd reads five
## divider-separated row bands and eight columns off cottage_1.png, and the
## rendered cells say the rows really mean what the 8x5 contract says --
## row 0 is a foundation ring, row 2 a finished cottage, row 3 a cottage on
## fire.
const _COTTAGE_VARIATIONS: Array[String] = [
	"res://assets/sprites/buildings/cottage_1.png",
	"res://assets/sprites/buildings/cottage_2.png",
	"res://assets/sprites/buildings/cottage_3.png",
	"res://assets/sprites/buildings/cottage_4.png",
	"res://assets/sprites/buildings/cottage_5.png",
]

## The largest tier's own five, delivered the same day and on the same 8x5
## contract -- and really manors: row 2 of manor_1.png is a turreted,
## bannered stone house, not a scaled-up cottage.
const _MANOR_VARIATIONS: Array[String] = [
	"res://assets/sprites/buildings/manor_1.png",
	"res://assets/sprites/buildings/manor_2.png",
	"res://assets/sprites/buildings/manor_3.png",
	"res://assets/sprites/buildings/manor_4.png",
	"res://assets/sprites/buildings/manor_5.png",
]

## The two grids a variation set can be drawn on, and which rows of each
## mean what. A set carries its own, because the three house tiers are no
## longer on one contract.
##
## The 8x5 one is BuildingCatalog's own asset contract, restated here as
## rows rather than restated as numbers: one construction row of eight
## stages, then active, idle, burning, ruined. Only the IDLE row is a
## finished look -- "active" is an eight-frame animation of smoke and lit
## windows, not a second standing variant, and burning and ruined are
## states this module must never hand a finished building.
const _GRID_8X5 := {
	"columns": 8, "rows": 5, "build_rows": [0], "idle_rows": [2],
}

## The 8x10 one, whose own printed labels are quoted at the top of this
## file: three build rows (24 real frames) and three idle rows (24 finished
## looks).
const _GRID_8X10 := {
	"columns": COLUMNS, "rows": ROWS, "build_rows": BUILD_ROWS, "idle_rows": IDLE_ROWS,
}

## Which building ids have real lifecycle variation sheets, and what each
## one is drawn from.
##
## One tier, one building. Asked directly once the art landed: *"I added
## cottage and manor sprites... please fix that villages use scaled houses
## for those and use the real illustrations"*. All three used to share the
## house_1_* sheets, which was deliberate while it was the only house art
## there was -- declaring it for the smallest tier alone would have left a
## street half cottages and half boxes -- and building.md said exactly what
## would end it: "when grander art for those tiers lands they get their own
## entries here and nothing else changes".
##
## Nothing that is not a home is listed. A hall, a mill or a brewery drawn
## as a cottage would be drawing the wrong building, and each already has
## its own 8x5 sheet.
const VARIATION_SHEETS := {
	"house_small": _COTTAGE_VARIATIONS,
	"house_medium": _HOUSE_VARIATIONS,
	"house_large": _MANOR_VARIATIONS,
}

## Which grid each set's own art is drawn on (see _GRID_8X5/_GRID_8X10).
const _VARIATION_GRIDS := {
	"house_small": _GRID_8X5,
	"house_medium": _GRID_8X10,
	"house_large": _GRID_8X5,
}


## Every lifecycle variation sheet declared for this building, or [] for
## one that has none. Whether the files are on disk is the renderer's
## question, not this module's -- a missing sheet falls back through the
## same chain a missing lifecycle sheet already does.
static func variation_sheets_of(building_id: String) -> Array:
	return VARIATION_SHEETS.get(building_id, [])


## The grid this building's own variation art is drawn on -- {columns, rows,
## build_rows, idle_rows} -- or {} for a building with no variations. What
## the sheet chain reads to slice the right cells out of the right sheet.
static func grid_for(building_id: String) -> Dictionary:
	return _VARIATION_GRIDS.get(building_id, {})


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
static func build_cell_for(building_id: String, progress: float) -> Vector2i:
	var grid := grid_for(building_id)
	if grid.is_empty():
		return Vector2i.ZERO
	var columns := int(grid["columns"])
	var build_rows: Array = grid["build_rows"]
	var frames := columns * build_rows.size()
	var frame := clampi(floori(clampf(progress, 0.0, 1.0) * float(frames)), 0, frames - 1)
	return Vector2i(frame % columns, build_rows[frame / columns])


## The cell a FINISHED house stands in -- one of the idle rows, on its own
## seeded column. Row and column are drawn from independent hashes of the
## same seed so the pair spreads over the whole idle block rather than
## walking a diagonal (test-pinned: all of them are reachable), the same
## shape BuildingCatalog.variant_cell_for already uses.
static func idle_cell_for(building_id: String, seed_value: int) -> Vector2i:
	var grid := grid_for(building_id)
	if grid.is_empty():
		return Vector2i.ZERO
	var idle_rows: Array = grid["idle_rows"]
	return Vector2i(
		PixelNoise.range_index(seed_value, 61, 67, int(grid["columns"])),
		idle_rows[PixelNoise.range_index(seed_value, 71, 73, idle_rows.size())]
	)
