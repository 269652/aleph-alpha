extends RefCounted

## Real illustrated art for the structures docs/concept/npc_farm_production.md
## and docs/concept/npc_role_consensus.md introduced: farm
## (assets/sprites/buildings/farmhouse.png), sagewerk (.../sawmill.png),
## storage (.../warehouse.png), the wooden_fence that gates a Farm's Farmer
## (assets/sprites/structures/wooden_fence.png), and city_hall
## (.../city_hall.png), a settlement's real civic seat. Sliced with a KNOWN
## FIXED GRID directly, mirroring illustrated_beehive_sprite.gd's own
## established precedent for a regular sheet, NOT SpriteSheetSlicer.
## detect_frames' column-gap heuristic (that tool slices a single
## horizontal strip; these are real 2D grids).
##
## Each of the four building sheets is a genuine construction -> idle ->
## damaged -> ruined progression, 5 rows deep (real, useful content for a
## future pass) -- but nothing in this codebase yet tracks a single-tile
## placeable's build progress or condition the way BuildingPiece walls do
## (see docs/concept/npc_farm_production.md's own Open Questions), so only
## the row that reads as "freshly built, currently in use" is wired to
## anything today. wooden_fence.png is a real intact -> weathered ->
## broken -> scattered progression, 4 rows deep; only "intact" is wired.
##
## Grid facts, confirmed empirically (probe-before-trust: a flat 256px row
## assumption on the building sheets visibly bled into the next row's roof
## when actually cropped and viewed) rather than assumed from the sheets'
## own 1536x1024 canvas size:
## - farmhouse.png: 6 columns x 5 rows. sawmill.png/warehouse.png/
##   city_hall.png: 8 columns x 5 rows (city_hall.png verified against the
##   same crop-and-view check, confirming the identical grid its sheet
##   shares with sawmill/warehouse). Columns divide the 1536px width evenly
##   (256px/192px); rows do NOT divide the 1024px height evenly
##   (1024/5 = 204.8) -- row boundaries are computed by cumulative rounding
##   (round(1024*i/5)) so 5 unequal integer rows still sum exactly to 1024,
##   rather than a flat cell height that drifts and bleeds into the next
##   row.
## - wooden_fence.png: 4 columns x 4 rows, both axes dividing 1536x1024
##   perfectly evenly (384x256) -- no special rounding needed, but the same
##   cumulative-rounding helper is reused for both anyway (a no-op on an
##   even division).
##
## Chroma key: farmhouse.png/wooden_fence.png key on magenta (their real
## background). sawmill.png/warehouse.png/city_hall.png key on near-black
## (THEIR real background, confirmed by sampling well inside a cell, away
## from the thin magenta divider line that runs along the sheet's outer
## edge and every row/column seam) -- magenta is ALSO keyed for these
## three sheets so a stray sliver of that divider line surviving at a
## cell's own edge doesn't show up as a colored fringe once cropped.

const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")
const VillageFarm = preload("res://src/gameplay/village_farm.gd")

## How a sheet's cells are found. All three are real on disk today:
## "even" divides the canvas (the original 8x5 sheets), "gutters" finds the
## dark bands between cells (house_1.png), "dividers" finds the bands
## between magenta lines and skips the label bands around them
## (house_1_1.png .. house_1_5.png, well.png).
const GRID_EVEN := "even"
const GRID_GUTTERS := "gutters"
const GRID_DIVIDERS := "dividers"
const VariantSheetGrid = preload("res://src/rendering/variant_sheet_grid.gd")

## Same measured thresholds as illustrated_beehive_sprite.gd/
## illustrated_ant_mound_sprite.gd -- reused, not reinvented.
const _MAGENTA_RED_MIN := 0.85
const _MAGENTA_BLUE_MIN := 0.85
const _MAGENTA_GREEN_MAX := 0.15
const _MAGENTA_CAST_MARGIN := 0.03

## How dark a pixel must be (per channel) to read as sawmill.png/
## warehouse.png's own near-black background -- measured directly (a real
## in-cell background sample read exactly (0,0,0)); a small margin above 0
## tolerates minor compression noise without also keying real dark browns
## in the structure's own timber shading.
const _BLACK_MAX := 0.05

const _SUBJECTS := {
	"farm": {
		"path": "res://assets/sprites/buildings/farmhouse.png",
		"columns": 6, "rows": 5, "idle_row": 1, "idle_column": 0, "keys_black": false,
	},
	"sagewerk": {
		"path": "res://assets/sprites/buildings/sawmill.png",
		"columns": 8, "rows": 5, "idle_row": 1, "idle_column": 0, "keys_black": true,
	},
	"storage": {
		"path": "res://assets/sprites/buildings/warehouse.png",
		"columns": 8, "rows": 5, "idle_row": 1, "idle_column": 0, "keys_black": true,
	},
	"wooden_fence": {
		"path": "res://assets/sprites/structures/wooden_fence.png",
		"columns": 4, "rows": 4, "idle_row": 0, "idle_column": 0, "keys_black": false,
	},
	"city_hall": {
		"path": "res://assets/sprites/buildings/city_hall.png",
		"columns": 8, "rows": 5, "idle_row": 1, "idle_column": 0, "keys_black": true,
	},
	# The rails a village farmhouse fences its beds with (docs/concept/
	# village_farms.md, "The fence around the beds"). One sheet, four
	# orientation columns by three condition rows, on the DIVIDER grid: the
	# sheet prints its own column labels across the top and its row labels
	# down a gutter at the left, so an even division would cut every cell
	# across the label bands. Row 0 is Pristine -- a freshly raised fence.
	# Written out per column rather than built by a helper: GDScript cannot
	# call a function in a const initialiser another script reads. The
	# columns are the sheet's own printed order -- North (Back), South
	# (Front), East (Top View), West (Top View) -- pinned by
	# test_the_four_rails_are_four_different_pictures.
	"farm_fence_north": {
		"path": "res://assets/sprites/buildings/fence.png",
		"columns": 4, "rows": 3, "idle_row": 0, "idle_column": 0,
		"keys_black": true, "grid": "dividers",
	},
	"farm_fence_south": {
		"path": "res://assets/sprites/buildings/fence.png",
		"columns": 4, "rows": 3, "idle_row": 0, "idle_column": 1,
		"keys_black": true, "grid": "dividers",
	},
	"farm_fence_east": {
		"path": "res://assets/sprites/buildings/fence.png",
		"columns": 4, "rows": 3, "idle_row": 0, "idle_column": 2,
		"keys_black": true, "grid": "dividers",
	},
	"farm_fence_west": {
		"path": "res://assets/sprites/buildings/fence.png",
		"columns": 4, "rows": 3, "idle_row": 0, "idle_column": 3,
		"keys_black": true, "grid": "dividers",
	},
	# A corner caps two runs at once. The sheet has no corner cell of its
	# own, so it is drawn with the same post art the side columns use --
	# which is what a real corner post is, and is what stops a horizontal
	# rail being drawn across the turn (reported: "corner pieces added so it
	# doesn't look that broken"). One per side, drawn from that side's own
	# column, because each is pushed out with the wall it caps.
	"farm_fence_corner_west": {
		"path": "res://assets/sprites/buildings/fence.png",
		"columns": 4, "rows": 3, "idle_row": 0, "idle_column": 3,
		"keys_black": true, "grid": "dividers",
	},
	"farm_fence_corner_east": {
		"path": "res://assets/sprites/buildings/fence.png",
		"columns": 4, "rows": 3, "idle_row": 0, "idle_column": 2,
		"keys_black": true, "grid": "dividers",
	},
}

static var _cache: Dictionary = {}  # subject -> ImageTexture


func has_subject(subject: String) -> bool:
	return _SUBJECTS.has(subject)


func subjects() -> Array:
	return _SUBJECTS.keys()


## The subject's canonical "freshly built, in use" texture, real illustrated
## art despilled/keyed to a transparent background -- null for an unknown
## subject.
func idle_texture(subject: String) -> ImageTexture:
	if not _SUBJECTS.has(subject):
		return null
	if not _cache.has(subject):
		_cache[subject] = ImageTexture.create_from_image(_build_idle_image(subject))
	return _cache[subject]


## The subject's idle art scaled for use as a Sprite2D standing on its own
## placed tile -- width scaled to exactly `tile_size`, height scaled by the
## SAME factor (mirrors IllustratedArtLoader's own documented "footprint"
## anchor: "a structure taller than one tile... stays taller than one tile
## rather than being squashed to fit a fixed canvas"). The caller anchors
## the returned texture's own bottom edge at the tile's bottom edge, the
## same way any bottom-anchored sprite already does. Null for an unknown
## subject.
func footprint_texture(subject: String, tile_size: int) -> ImageTexture:
	var idle := idle_texture(subject)
	if idle == null:
		return null
	var source := idle.get_image()
	var scale := float(tile_size) / float(source.get_width())
	var width := maxi(1, int(round(float(source.get_width()) * scale)))
	var height := maxi(1, int(round(float(source.get_height()) * scale)))
	var scaled := source.duplicate() as Image
	scaled.resize(width, height, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(scaled)


## Where a subject's footprint_texture really stands INSIDE its own tile, as
## an offset from the placement every whole-building subject uses:
## horizontally centred, bottom edge on the tile's bottom edge (see
## EarthChunkManager._spawn_structure_art_for). Vector2.ZERO for anything
## that stands on its whole tile, which is every subject but a rail.
##
## Asked for directly, with two sides of a real ring arrowed in a
## screenshot: *"move the fences to the inner edge of the enclosure and
## treat the rest of the tile as street"*. A rail is a LINE on the edge
## facing the beds it encloses (VillageFarm.fence_inner_direction), so its
## art's own GROUND LINE belongs on that edge -- and what counts as its
## ground line depends on which way the sheet draws that run:
##
## - A run drawn broad-side (the North/South columns) stands on its POSTS,
##   so its ground line is the bottom of its wood.
## - A run seen from above (the East/West columns) has no posts to stand on
##   -- the band of rail IS the ground line -- so it is CENTRED on the edge
##   it closes rather than based on it.
##
## MEASURED off the art, not assumed from the cell: `fence.png` draws every
## run centred in its own cell with real margin all round, so bottom-
## anchoring alone leaves a rail's posts a fifth of a tile short of the edge
## they are meant to stand on. A first pass here assumed a north rail
## already stood on its own south edge and was wrong by exactly that
## margin -- test_a_broadside_runs_posts_stand_on_the_edge_facing_the_beds
## finds the real wood independently and pins where it lands.
##
## Derived from the inner direction rather than written out as a fifth table
## of facings, so a rail cannot be drawn on one edge and block another.
func footprint_offset(subject: String, tile_size: int) -> Vector2:
	var inner := VillageFarm.fence_inner_direction(subject)
	if inner == Vector2i.ZERO:
		return Vector2.ZERO
	var idle := idle_texture(subject)
	if idle == null:
		return Vector2.ZERO
	var image := idle.get_image()
	var art := _art_rect(subject, image)
	var scale := float(tile_size) / float(image.get_width())
	if inner.y != 0:
		# Bottom-anchoring puts the BAND's bottom edge on the tile's bottom
		# edge, so the posts stand this far above it.
		var foot_above_bottom := float(image.get_height() - art.position.y - art.size.y) * scale
		if inner.y > 0:
			return Vector2(0.0, foot_above_bottom)
		return Vector2(0.0, foot_above_bottom - float(tile_size))
	# The band is centred on the tile, so the run's own centre line sits
	# here, measured from the tile's left edge.
	var centre_x := (float(art.position.x) + float(art.size.x) * 0.5) * scale
	if inner.x < 0:
		return Vector2(-centre_x, 0.0)
	return Vector2(float(tile_size) - centre_x, 0.0)


## How bright a pixel must be to count as this art rather than as the chroma
## key's own leftovers -- see _is_art_pixel.
const _ART_MIN_BRIGHTNESS := 0.2

## What share of a row or column must be art before that line counts as part
## of the art at all. Not a single pixel: the same "share of the line" shape
## VariantSheetGrid.DIVIDER_LINE_SHARE already uses, so one surviving speck
## of key fringe cannot stretch the rect to the whole cell. Measured against
## the real sheet: the thinnest real line of a top-view run still fills ~13%
## of its own row, and the emptiest row inside a broad-side run still has
## its two posts at ~12%, both an order of magnitude above this.
const _ART_LINE_SHARE := 0.03

## subject -> the Rect2i _art_rect measured for it. The scan is two passes
## over a ~330x275 cell, and every rail a village raises asks for the same
## four answers.
static var _art_rect_cache: Dictionary = {}


## Whether a pixel of a keyed cell is REAL art rather than what the chroma
## key left behind.
##
## Image.get_used_rect cannot answer this: a pixel part way between the
## sheet's magenta divider and its black background -- (128, 0, 128) and its
## neighbours -- is neither magenta enough nor black enough for
## _key_and_despill, survives at full alpha, and makes the used rect the
## whole cell every single time. What it is, though, is MAGENTA-CAST: blue
## at least as strong as green. Every real pixel of this art is wood or an
## iron fitting, brown or neutral grey, and in both green is at least blue.
static func _is_art_pixel(pixel: Color) -> bool:
	return pixel.a >= 0.5 and pixel.r >= _ART_MIN_BRIGHTNESS and pixel.g >= pixel.b


## The tight rect of a keyed cell's real art, in that cell's own pixels --
## the whole cell if nothing in it reads as art, which leaves a subject this
## cannot measure placed exactly where it always was.
func _art_rect(subject: String, image: Image) -> Rect2i:
	if _art_rect_cache.has(subject):
		return _art_rect_cache[subject]
	var width := image.get_width()
	var height := image.get_height()
	var min_x := width
	var max_x := -1
	var min_y := height
	var max_y := -1
	for y in height:
		var in_row := 0
		for x in width:
			if _is_art_pixel(image.get_pixel(x, y)):
				in_row += 1
		if float(in_row) / float(width) >= _ART_LINE_SHARE:
			min_y = mini(min_y, y)
			max_y = maxi(max_y, y)
	for x in width:
		var in_column := 0
		for y in height:
			if _is_art_pixel(image.get_pixel(x, y)):
				in_column += 1
		if float(in_column) / float(height) >= _ART_LINE_SHARE:
			min_x = mini(min_x, x)
			max_x = maxi(max_x, x)
	var rect := Rect2i(0, 0, width, height)
	if max_x >= min_x and max_y >= min_y:
		rect = Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
	_art_rect_cache[subject] = rect
	return rect


# -- whole-building entities (docs/concept/building.md "Buildings are -------
# -- entities; interiors are scenes"): any sheet following the one asset -----
# -- contract (BuildingCatalog.SHEET_COLUMNS x SHEET_ROWS lifecycle rows, -----
# -- black background, magenta dividers), read by ROW and COLUMN and scaled --
# -- to a multi-tile footprint -- generalizing idle_texture/footprint_texture --
# -- from "one subject's one idle cell" to "any cell of any contract sheet". --

## "path|row|column" -> keyed Image. Shared across instances like _cache.
static var _sheet_frame_cache: Dictionary = {}


## The (row, column) cell of the contract sheet at `path`, keyed/despilled
## to a transparent background (black background + magenta dividers, the
## same treatment sawmill/warehouse/city_hall already get). Null for a
## sheet that cannot be loaded or a cell outside the grid -- a caller falls
## back to ProceduralBuildingPlaceholderSprite then, never crashes.
func sheet_frame_image(path: String, columns: int, rows: int, row: int, column: int) -> Image:
	return _frame_image(path, columns, rows, row, column, GRID_EVEN)


## The same cut for a VARIANT sheet (docs/concept/building.md, "Building
## variant sheets"), whose cells are found in the sheet's own background
## gutters rather than assumed to sit on an exact pitch -- see
## VariantSheetGrid for why an even division is wrong for a hand-drawn
## grid, and falls back to one anyway when a sheet has no readable gutters.
func variant_frame_image(path: String, columns: int, rows: int, row: int, column: int) -> Image:
	return _frame_image(path, columns, rows, row, column, GRID_GUTTERS)


## The same cut for a sheet that draws a real MAGENTA LINE between one cell
## and the next, and carries label bands that are not art at all
## (house_1_1.png .. house_1_5.png, well.png -- see VariantSheetGrid.
## art_bands and docs/concept/building.md, "Building lifecycle variation
## sheets"). Dividing such a canvas evenly is a whole label band out.
func divider_frame_image(path: String, columns: int, rows: int, row: int, column: int) -> Image:
	return _frame_image(path, columns, rows, row, column, GRID_DIVIDERS)


## One body for all three, differing only in where the cell's rect comes
## from. Cached per (path, row, column, grid kind), so the band scan a
## detected grid needs is paid once per sheet rather than per building
## placed -- and the bands themselves are cached again below, since a
## divider scan walks the whole 1536x1024 image.
func _frame_image(path: String, columns: int, rows: int, row: int, column: int, grid: String) -> Image:
	if row < 0 or row >= rows or column < 0 or column >= columns:
		return null
	var key := "%s|%d|%d|%s" % [path, row, column, grid]
	if _sheet_frame_cache.has(key):
		return _sheet_frame_cache[key]
	var image := SpriteSheetLoader.load_image(path)
	if image == null:
		return null
	var rect := _cell_rect_for(path, image, columns, rows, row, column, grid)
	var frame := image.get_region(rect)
	if frame.get_format() != Image.FORMAT_RGBA8:
		frame.convert(Image.FORMAT_RGBA8)
	_key_and_despill(frame, true)
	_sheet_frame_cache[key] = frame
	return frame


## That cell scaled for a Sprite2D standing on a `footprint_width_tiles`-
## wide footprint: width exactly `tile_size * footprint_width_tiles`, height
## by the SAME factor (footprint_texture's own documented anchor, a building
## taller than its footprint stays taller). Null when the sheet is missing.
func footprint_frame_texture(
	path: String, columns: int, rows: int, row: int, column: int, tile_size: int, footprint_width_tiles: int,
	grid: String = GRID_EVEN
) -> ImageTexture:
	var frame := _frame_image(path, columns, rows, row, column, grid)
	if frame == null:
		return null
	var target_width := tile_size * maxi(footprint_width_tiles, 1)
	var scale := float(target_width) / float(frame.get_width())
	var height := maxi(1, int(round(float(frame.get_height()) * scale)))
	var scaled := frame.duplicate() as Image
	scaled.resize(target_width, height, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(scaled)


## Band detection is a full scan of a 1536x1024 image, so its answer is
## kept per (path, grid kind, axis, count) -- a village placing five houses
## off one sheet scans it once, not ten times.
var _grid_band_cache: Dictionary = {}


func _cell_rect_for(
	path: String, image: Image, columns: int, rows: int, row: int, column: int, grid: String
) -> Rect2i:
	match grid:
		GRID_GUTTERS:
			return Rect2i(
				_band(path, image, columns, grid, false)[column].x,
				_band(path, image, rows, grid, true)[row].x,
				_span(_band(path, image, columns, grid, false)[column]),
				_span(_band(path, image, rows, grid, true)[row])
			)
		GRID_DIVIDERS:
			return Rect2i(
				_band(path, image, columns, grid, false)[column].x,
				_band(path, image, rows, grid, true)[row].x,
				_span(_band(path, image, columns, grid, false)[column]),
				_span(_band(path, image, rows, grid, true)[row])
			)
	return _cell_rect(image, columns, rows, row, column)


func _band(path: String, image: Image, count: int, grid: String, horizontal: bool) -> Array:
	var key := "%s|%s|%d|%s" % [path, grid, count, "rows" if horizontal else "columns"]
	if not _grid_band_cache.has(key):
		if grid == GRID_DIVIDERS:
			_grid_band_cache[key] = VariantSheetGrid.art_bands(image, count, horizontal)
		else:
			_grid_band_cache[key] = (
				VariantSheetGrid.row_bands(image, count) if horizontal
				else VariantSheetGrid.column_bands(image, count)
			)
	return _grid_band_cache[key]


static func _span(band: Vector2i) -> int:
	return band.y - band.x + 1


func _build_idle_image(subject: String) -> Image:
	var entry: Dictionary = _SUBJECTS[subject]
	var image := SpriteSheetLoader.load_image(entry["path"])
	# A sheet that prints its own labels is cut on its dividers, not by even
	# division -- see the farm_fence entries. Everything delivered on the
	# older fixed grid keeps the even cut it was measured against.
	var cell := _cell_rect_for(
		entry["path"], image, entry["columns"], entry["rows"],
		entry["idle_row"], entry["idle_column"], entry.get("grid", GRID_EVEN)
	)
	var frame := image.get_region(cell)
	if frame.get_format() != Image.FORMAT_RGBA8:
		frame.convert(Image.FORMAT_RGBA8)
	_key_and_despill(frame, entry["keys_black"])
	return frame


## The pixel rect for (row, column) in a columns x rows grid over `image`,
## via cumulative rounding on both axes -- see this file's own header
## comment for why a flat division would bleed on these sheets' real
## non-evenly-divisible row count.
func _cell_rect(image: Image, columns: int, rows: int, row: int, column: int) -> Rect2i:
	var w := image.get_width()
	var h := image.get_height()
	var x0 := int(round(float(w) * column / columns))
	var x1 := int(round(float(w) * (column + 1) / columns))
	var y0 := int(round(float(h) * row / rows))
	var y1 := int(round(float(h) * (row + 1) / rows))
	return Rect2i(x0, y0, x1 - x0, y1 - y0)


func _key_and_despill(image: Image, keys_black: bool) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if _is_magenta(pixel) or (keys_black and _is_black(pixel)):
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				image.set_pixel(x, y, _despilled(pixel))


static func _is_magenta(color: Color) -> bool:
	return color.r >= _MAGENTA_RED_MIN and color.b >= _MAGENTA_BLUE_MIN and color.g <= _MAGENTA_GREEN_MAX


static func _is_black(color: Color) -> bool:
	return color.r <= _BLACK_MAX and color.g <= _BLACK_MAX and color.b <= _BLACK_MAX


static func _despilled(color: Color) -> Color:
	var cast: float = minf(color.r - color.g, color.b - color.g)
	if cast <= _MAGENTA_CAST_MARGIN:
		return color
	var removed := cast - _MAGENTA_CAST_MARGIN
	return Color(
		clampf(color.r - removed, 0.0, 1.0), color.g,
		clampf(color.b - removed, 0.0, 1.0), color.a
	)
