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
##   shares with sawmill/warehouse). wooden_fence.png: 4 columns x 4 rows.
## - The COLUMNS are on an exact pitch: 1536/8 is 192 and 1536/6 is 256,
##   and profiling the sheets confirms the art in every column really does
##   start ~12px inside one of 0, 192, 384 ... 1344. So a column is cut by
##   even division, minus CELL_INSET for the rule line the sheets draw on
##   the boundary.
## - The ROWS are on NO pitch at all, and two different wrong guesses were
##   shipped before that was measured. warehouse.png's drawn row
##   boundaries sit at 188, 376, 566 and 786; sawmill.png's at 190, 387,
##   578 and 789; city_hall.png's and blacksmith.png's elsewhere again.
##   An even fifth of the canvas (204.8) clipped 9px off sagewerk's roof;
##   the column pitch (192) clipped 13px off city_hall's footings, 26 off
##   blacksmith's last row, and cut wooden_fence's 256px rows at 384. So
##   rows are READ OFF THE SHEET by VariantSheetGrid.content_bands, which
##   falls back to even division on any sheet it cannot resolve.
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
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")

## How a sheet's cells are found. All three are real on disk today:
## "even" divides the canvas (the original 8x5 sheets), "gutters" finds the
## dark bands between cells (house_1.png), "dividers" finds the bands
## between magenta lines and skips the label bands around them
## (house_1_1.png .. house_1_5.png, well.png).
const GRID_EVEN := "even"
const GRID_GUTTERS := "gutters"
const GRID_DIVIDERS := "dividers"

## Cells found by asking where the ART is, on BOTH axes.
##
## For a sheet that has no drawn divider between its cells at all -- only
## the background showing through, and a near-white rule line the magenta
## key cannot see. `dividers` reads such a sheet by accident and badly: a
## row crossing eight roof APEXES is mostly background, so a band begins
## where the silhouette thins rather than where the drawing ends, and the
## apex, the finial and the chimney cap are cut off above it. Measured on
## cottage_3.png: the divider band is rows 421..569 where the art really
## runs 390..570, and the columns lose 13px a side as well.
const GRID_CONTENT := "content"

## Every grid kind _cell_rect_for can actually read.
##
## Listed off the constants rather than written out again wherever
## somebody needs to check one, so a sheet declaring a kind this reader
## does not have fails loudly instead of silently falling through to the
## even cut -- which is exactly how cottage_*.png spent its life being read
## the wrong way.
const GRID_KINDS: Array[String] = [GRID_EVEN, GRID_GUTTERS, GRID_DIVIDERS, GRID_CONTENT]
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
	"farm_fence_corner_nw": {
		"path": "res://assets/sprites/buildings/fence.png",
		"columns": 4, "rows": 3, "idle_row": 0, "idle_column": 3,
		"keys_black": true, "grid": "dividers",
	},
	"farm_fence_corner_sw": {
		"path": "res://assets/sprites/buildings/fence.png",
		"columns": 4, "rows": 3, "idle_row": 0, "idle_column": 3,
		"keys_black": true, "grid": "dividers",
	},
	"farm_fence_corner_ne": {
		"path": "res://assets/sprites/buildings/fence.png",
		"columns": 4, "rows": 3, "idle_row": 0, "idle_column": 2,
		"keys_black": true, "grid": "dividers",
	},
	"farm_fence_corner_se": {
		"path": "res://assets/sprites/buildings/fence.png",
		"columns": 4, "rows": 3, "idle_row": 0, "idle_column": 2,
		"keys_black": true, "grid": "dividers",
	},
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
	var scale := _footprint_scale(subject, source, tile_size)
	var width := maxi(1, int(round(float(source.get_width()) * scale)))
	var height := maxi(1, int(round(float(source.get_height()) * scale)))
	var scaled := source.duplicate() as Image
	scaled.resize(width, height, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(scaled)


## How much a subject's own cell is scaled to stand on a tile.
##
## A whole building scales its WIDTH to the tile, which is the footprint
## anchor footprint_texture documents and every one of them still uses.
## The catalog building each placeable structure shares its art with. The
## village raises the very same sheet as a real, multi-tile building (see
## BuildingCatalog's own "farmhouse" row: "npc_farm_production.md's Farm,
## raised as a real building rather than a single tile"), so the catalog
## already holds the answer to how big this picture is meant to be drawn.
## Read from there rather than restated here, so one building cannot end up
## two sizes depending on who put it down.
const _CATALOG_TWIN := {
	"farm": "farmhouse",
	"sagewerk": "sawmill",
	"storage": "warehouse",
	"city_hall": "city_hall",
}


## How many tiles wide this subject is DRAWN. One, for anything with no
## catalog twin -- a lone fence panel genuinely is one tile of fence.
##
## Note this is about the PICTURE, not the ground: a placed structure still
## occupies its single tile, exactly as before. A real tree already draws a
## canopy far wider than the one tile its trunk stands on; a building is the
## same kind of thing.
static func drawn_width_tiles(subject: String) -> int:
	var twin := String(_CATALOG_TWIN.get(subject, ""))
	if twin.is_empty():
		return 1
	return maxi(BuildingCatalog.footprint_of(twin).x, 1)


## Reported live: *"Also there's a weird shrunk farmhouse fix that too"*.
##
## A whole building used to scale its cell to exactly ONE tile, which
## npc_farm_production.md's "Real art" section specified in as many words
## ("width matches the tile ... rather than squashed into a single small
## tile texture"). The intent was right and the number was not. Measured
## (tools/probe_structure_art_scale.gd), at a 16px tile against a villager
## 1.23 tiles tall:
##
##     farm       drawn 0.85 x 0.70 tiles   0.57x a person
##     sagewerk   drawn 0.88 x 0.82 tiles   0.67x a person
##     storage    drawn 0.83 x 0.89 tiles   0.72x a person
##     city_hall  drawn 0.84 x 0.96 tiles   0.78x a person
##
## Every one of them was shorter than the person who works it -- the
## farmhouse barely half his height, which is what got reported. Drawn at
## its own catalog footprint now (see drawn_width_tiles).
##
## A RAIL scales by its RUN instead. Asked for in one word, after the rails
## landed on their inner edges: *"also scale"*. The sheet draws every run
## centred in its own cell with real margin at both ends, so a cell scaled
## by its width leaves that margin as a GAP between one rail and the next --
## measured, 52 of 64 across for a broad-side run and 39 of 64 down for a
## top-view one, which reads as a row of separate pieces rather than a fence
## line. Scaling so the run's own WOOD spans exactly one tile along the
## direction it travels is what makes consecutive rails meet.
func _footprint_scale(subject: String, image: Image, tile_size: int) -> float:
	var inner := VillageFarm.fence_inner_direction(subject)
	if inner == Vector2i.ZERO:
		return float(tile_size * drawn_width_tiles(subject)) / float(image.get_width())
	var art := _art_rect(subject, image)
	# A run travels ACROSS the direction it closes: a rail whose beds lie
	# north or south runs east-west, and one whose beds lie east or west
	# runs north-south.
	#
	# A CORNER travels neither way -- it is a post on a join. It takes the
	# side wall's own scale (the vertical run it caps), so its timber is
	# exactly as thick as the run it meets; scaling it by its own length
	# instead is what turned a post into a whole tile of rail.
	if inner.x != 0 and inner.y != 0:
		return float(tile_size) / float(maxi(art.size.y, 1))
	if inner.y != 0:
		return float(tile_size) / float(maxi(art.size.x, 1))
	return float(tile_size) / float(maxi(art.size.y, 1))


## Where a subject's footprint_texture really stands INSIDE its own tile, as
## an offset from the placement every whole-building subject uses:
## horizontally centred, bottom edge on the tile's bottom edge (see
## EarthChunkManager._spawn_structure_art_for). Vector2.ZERO for anything
## that stands on its whole tile, which is every subject but a rail.
##
## A rail's wood sits inside its own tile, FLUSH against the edge facing the
## beds it encloses (VillageFarm.fence_inner_direction) -- one rule for
## every facing, and for a corner, which is flush against both of its. The
## frame then touches the crop on every side without ever covering it.
##
## Three reports got here, each one narrowing it:
##
## - *"move the fences to the inner edge of the enclosure"* -- a rail was
##   drawn in the middle of its tile, a whole tile from the bed.
## - *"the fences still aren't optimal"*, corners crossed out -- a corner
##   knew one axis, so it was placed as a whole tile of vertical rail while
##   the run it caps sat on that tile's edge.
## - *"at the bottom it still overlaps half a tile"* -- this. A SOUTH rail's
##   posts standing on its own north edge is a fence seen from the front and
##   reads correctly, but the body then rises over the bottom row of beds
##   and hides half a tile of crop. Flush from the inside puts the same
##   fence half a tile nearer the viewer and covers nothing.
##
## The offsets are MEASURED off the art (_art_rect), never assumed from the
## cell: `fence.png` draws every run centred in its own cell with real
## margin all round, and an earlier pass that assumed the cell's own edge
## was where the wood ended was wrong by a fifth of a tile.
##
## Derived from the inner direction rather than a table of facings, so a
## rail cannot be drawn against one edge and block another.
func footprint_offset(subject: String, tile_size: int) -> Vector2:
	var inner := VillageFarm.fence_inner_direction(subject)
	if inner == Vector2i.ZERO:
		return Vector2.ZERO
	var idle := idle_texture(subject)
	if idle == null:
		return Vector2.ZERO
	var image := idle.get_image()
	var art := _art_rect(subject, image)
	var scale := _footprint_scale(subject, image, tile_size)
	# Where the wood lands with no offset at all: the band is centred on the
	# tile and bottom-anchored (EarthChunkManager._spawn_structure_art_for),
	# and is NOT one tile wide once a rail is scaled by its own run, so where
	# its edges fall has to be carried rather than assumed away.
	var band_left := (float(tile_size) - float(image.get_width()) * scale) * 0.5
	var band_top := float(tile_size) - float(image.get_height()) * scale
	var left := band_left + float(art.position.x) * scale
	var top := band_top + float(art.position.y) * scale
	var offset := Vector2.ZERO
	if inner.x > 0:
		offset.x = float(tile_size) - (left + float(art.size.x) * scale)
	elif inner.x < 0:
		offset.x = -left
	if inner.y > 0:
		offset.y = float(tile_size) - (top + float(art.size.y) * scale)
	elif inner.y < 0:
		offset.y = -top
	return offset


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


## The same cut for a sheet whose per-cell own content reads as a false
## extra divider to the generic band scan -- assets/sprites/buildings/
## stand.png (the "stall" landmark) draws each cell as a roof/awning over
## an open gap over a table, and that gap is near-full-width magenta in
## every one of the 5 columns at once, so VariantSheetGrid.art_bands' own
## "least size-varied run of `count` consecutive bands" heuristic prefers
## grabbing the size-consistent noise slivers beside every true divider
## over the genuinely different-sized roof/table halves it was supposed to
## find (measured directly: tools/_probe_stand_bands.gd's raw
## divider_bands come back as 16 row / 11 column entries for a real 5x5
## grid, not 5). `row_bands`/`column_bands` are measured off the real file
## and pinned here instead -- the same "generic detector cannot help,
## explicit bands can" call illustrated_terrain_sprite.gd's "soil" entry
## already made for its own near-black gutters.
func explicit_frame_image(
	path: String, row_bands: Array, column_bands: Array, row: int, column: int
) -> Image:
	if row < 0 or row >= row_bands.size() or column < 0 or column >= column_bands.size():
		return null
	var key := "%s|explicit|%d|%d" % [path, row, column]
	if _sheet_frame_cache.has(key):
		return _sheet_frame_cache[key]
	var image := SpriteSheetLoader.load_image(path)
	if image == null:
		return null
	var row_band: Vector2i = row_bands[row]
	var column_band: Vector2i = column_bands[column]
	var rect := Rect2i(
		column_band.x, row_band.x,
		column_band.y - column_band.x + 1, row_band.y - row_band.x + 1
	)
	var frame := image.get_region(rect)
	if frame.get_format() != Image.FORMAT_RGBA8:
		frame.convert(Image.FORMAT_RGBA8)
	_key_and_despill(frame, true)
	_sheet_frame_cache[key] = frame
	return frame


## The same cut, by the grid kind a chain entry NAMES rather than by
## picking one of the wrappers above.
##
## BuildingCatalog.finished_sheet_chain carries a `grid` per entry because
## the kind is a property of the SHEET (see GRID_CONTENT's own comment and
## docs/concept/building.md) -- so a caller holding an entry has the answer
## already and must not re-derive it. A caller that matched on a
## hand-written subset of kinds instead would fall silently through to the
## even cut for any kind it did not know, which is exactly what cost every
## cottage its roof. Fails loudly for a kind nothing can read, the same way
## GRID_KINDS exists so a sheet naming one fails loudly.
func frame_image(
	path: String, columns: int, rows: int, row: int, column: int, grid: String
) -> Image:
	assert(GRID_KINDS.has(grid), "unreadable grid kind: %s" % grid)
	return _frame_image(path, columns, rows, row, column, grid)


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
## wide footprint: drawn INSIDE the plot, at
## `BuildingCatalog.drawn_plot_width_tiles` of it, with height by the SAME
## factor (footprint_texture's own documented anchor, a building taller
## than its footprint stays taller). Null when the sheet is missing.
##
## It used to be exactly the plot width, which is what had two houses on
## neighbouring plots touching at the pixel with no street between them --
## see BuildingCatalog.PLOT_MARGIN_SHARE for the report and the
## measurement behind it. The margin lives there rather than here so this
## path and the procedural placeholder cannot disagree about how much of a
## plot a building covers.
func footprint_frame_texture(
	path: String, columns: int, rows: int, row: int, column: int, tile_size: int, footprint_width_tiles: int,
	grid: String = GRID_EVEN, building_id: String = ""
) -> ImageTexture:
	var frame := _frame_image(path, columns, rows, row, column, grid)
	if frame == null:
		return null
	# Named, so a building drawn at less of its plot than the plot alone
	# would say gets its own size (BuildingCatalog._DRAW_SCALES -- a cottage
	# is a smaller building than a house, and the art's own aspect does not
	# say so). "" is exactly the old answer, so a caller with no id in hand
	# is untouched.
	var target_width := maxi(
		1,
		int(round(
			float(tile_size)
			* BuildingCatalog.drawn_plot_width_tiles(footprint_width_tiles, building_id)
		))
	)
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
		GRID_DIVIDERS, GRID_CONTENT:
			var found := Rect2i(
				_band(path, image, columns, grid, false)[column].x,
				_band(path, image, rows, grid, true)[row].x,
				_span(_band(path, image, columns, grid, false)[column]),
				_span(_band(path, image, rows, grid, true)[row])
			)
			return _trimmed_of_rule_lines(image, found) if grid == GRID_CONTENT else found
	# The even grid is even on ONE axis. Columns really are on a pitch
	# (1536/8 is exactly 192, and every column's art starts ~12px inside
	# it); rows are not, so they are read off the sheet itself.
	var band: Vector2i = _band(path, image, rows, _CONTENT_ROWS, true)[clampi(row, 0, rows - 1)]
	var cell := _cell_rect(image, columns, rows, row, column)
	return Rect2i(cell.position.x, band.x, cell.size.x, band.y - band.x + 1)


## Cache key for the row bands read off a fixed-grid sheet's own art. Not
## one of the GRID_* kinds a subject declares -- it is how the rows of the
## GRID_EVEN kind are found, not a grid a caller can ask for.
const _CONTENT_ROWS := "content_rows"


func _band(path: String, image: Image, count: int, grid: String, horizontal: bool) -> Array:
	var key := "%s|%s|%d|%s" % [path, grid, count, "rows" if horizontal else "columns"]
	if not _grid_band_cache.has(key):
		if grid == _CONTENT_ROWS or grid == GRID_CONTENT:
			_grid_band_cache[key] = VariantSheetGrid.content_bands(image, count, horizontal)
		elif grid == GRID_DIVIDERS:
			_grid_band_cache[key] = VariantSheetGrid.art_bands(image, count, horizontal)
		else:
			_grid_band_cache[key] = (
				VariantSheetGrid.row_bands(image, count) if horizontal
				else VariantSheetGrid.column_bands(image, count)
			)
	return _grid_band_cache[key]


## `rect` with any of the sheet's own drawn RULE LINES shaved off its top
## and bottom edges.
##
## Reading a cell by where its art is (GRID_CONTENT) reaches up past the
## roof, which is the point -- but on some cells it reaches far enough to
## swallow the pale rule the sheet draws between its rows, and that ships
## as a bright bar across the top of a cottage. Trading a clipped roof for
## a white scratch is not a fix.
##
## A rule line is told apart from a drawing by SPAN, not by colour alone: a
## roof apex is sparse where it meets the background (measured: 9 to 31
## opaque pixels across a ~174-wide cell) while a rule runs the whole way.
## So a row is shaved only when it is nearly full width AND mostly pale --
## which no top-of-roof row in these sheets is, and every rule line is.
func _trimmed_of_rule_lines(image: Image, rect: Rect2i) -> Rect2i:
	var top := rect.position.y
	var bottom := rect.position.y + rect.size.y - 1
	# A rule line found INSIDE the edge of a band means the band reached
	# across the boundary it is drawn on, so everything up to and including
	# it belongs to the neighbouring cell -- not just the line itself. That
	# is the real shape of the miss: a chimney tip from the row above
	# survives one or two rows ABOVE the rule, so trimming only the line
	# leaves the tip behind and the scratch with it.
	var reach: int = maxi(_RULE_ROW_REACH, int(float(rect.size.y) * _RULE_ROW_REACH_SHARE))
	for offset in mini(reach, bottom - top):
		if _is_rule_line_row(image, rect, top + offset):
			top += offset + 1
	for offset in mini(reach, bottom - top):
		if _is_rule_line_row(image, rect, bottom - offset):
			bottom -= offset + 1
	return Rect2i(rect.position.x, top, rect.size.x, maxi(1, bottom - top + 1))


## How much of a row must be drawn on before it can be a rule rather than
## the sparse top of a drawing, and how much of that must be pale.
const _RULE_ROW_COVERAGE := 0.8
const _RULE_ROW_PALENESS := 0.5

## How far into a band's edge a rule line may be looked for. A rule sits on
## the boundary, so it is always within a few rows; searching further would
## start finding pale things that are really part of the drawing (a
## whitewashed gable, a snow-covered roof).
const _RULE_ROW_REACH := 6
const _RULE_ROW_REACH_SHARE := 0.05


func _is_rule_line_row(image: Image, rect: Rect2i, y: int) -> bool:
	var drawn := 0
	var pale := 0
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		var color := image.get_pixel(x, y)
		if VariantSheetGrid.is_background(color):
			continue
		drawn += 1
		if color.r >= VariantSheetGrid.RULE_LINE_MIN and color.g >= VariantSheetGrid.RULE_LINE_MIN and color.b >= VariantSheetGrid.RULE_LINE_MIN:
			pale += 1
	if drawn < int(float(rect.size.x) * _RULE_ROW_COVERAGE):
		return false
	return float(pale) / float(maxi(drawn, 1)) >= _RULE_ROW_PALENESS


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


## The pixels taken for (row, column) in a columns x rows grid over
## `image`: the square grid cell (even_cell_rect) minus the sheet's own
## divider line (even_cell_crop).
func _cell_rect(image: Image, columns: int, rows: int, row: int, column: int) -> Rect2i:
	return even_cell_crop(image.get_width(), image.get_height(), columns, rows, row, column)


## The COLUMN grid: square cells sized by the column pitch, anchored
## top-left. Only the horizontal half of this rect is used for a real
## frame -- the vertical half comes from the sheet's own drawn rows (see
## this file's header) -- but it stays square so the two axes can be
## compared, and so the inset below trims the same amount either way.
##
## The pitch is measured, not assumed: every production/civic sheet on
## disk is 1536x1024, 1536/8 is exactly 192, and the art in each column
## starts ~12px inside one of 0, 192, 384 ... 1344 on all four 8-column
## sheets.
##
## A sheet whose canvas ALREADY matches its grid exactly is divided exactly
## as before (pinned by
## test_a_sheet_that_already_divided_evenly_is_cut_exactly_as_before), so
## this only changes what was wrong.
##
## Clamped to the canvas: a sheet smaller than its own declared grid asks
## for pixels that do not exist otherwise, and get_region on an
## out-of-bounds rect is not something to find out about at draw time.
static func even_cell_rect(
	width: int, height: int, columns: int, rows: int, row: int, column: int
) -> Rect2i:
	var cell: int = maxi(1, int(float(width) / float(maxi(columns, 1))))
	var x0: int = mini(column * cell, maxi(width - 1, 0))
	var y0: int = mini(row * cell, maxi(height - 1, 0))
	return Rect2i(x0, y0, mini(cell, width - x0), mini(cell, height - y0))


## How far inside its own grid square a cell is actually cut, to clear the
## thin light divider the sheets draw between cells and around the canvas.
##
## Measured, not guessed. On warehouse.png the pixel at the cell corner
## (0, 384) reads (0.992, 0.969, 0.996) -- near-white, so neither the
## magenta key nor the near-black key removes it, and the sheet's own
## magenta background only starts 5px in. A cell cut exactly on the grid
## carries that line up its own edge as a hard opaque fringe. The line runs
## 1-3px, and the real art starts 8px inside a cell boundary, so 3 takes
## the divider and never the building (pinned by
## test_the_inset_clears_the_divider_without_reaching_the_art).
const CELL_INSET := 3

## An inset is only worth taking while it costs a small part of the cell.
## Trimming both edges of a 192px cell loses 3% of it; on a cell small
## enough to lose more than this share, the fringe is the lesser evil --
## so the rule is the share, not a hand-picked minimum cell size.
const MAX_INSET_SHARE := 0.1


static func inset_for_cell(cell: int) -> int:
	return CELL_INSET if float(CELL_INSET * 2) <= float(cell) * MAX_INSET_SHARE else 0


## The pixels actually taken for cell (row, column): its grid square minus
## the divider, on all four edges. The divider straddles a boundary, so the
## neighbour's half of it lands on this cell's far edge as well as its own
## near edge -- and trimming all four keeps the crop square, which is the
## whole point of the square-cell rule above.
static func even_cell_crop(
	width: int, height: int, columns: int, rows: int, row: int, column: int
) -> Rect2i:
	var cell := even_cell_rect(width, height, columns, rows, row, column)
	var inset := inset_for_cell(mini(cell.size.x, cell.size.y))
	if inset <= 0:
		return cell
	return Rect2i(
		cell.position.x + inset,
		cell.position.y + inset,
		maxi(1, cell.size.x - inset * 2),
		maxi(1, cell.size.y - inset * 2)
	)


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
