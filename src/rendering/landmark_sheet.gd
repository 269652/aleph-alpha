extends RefCounted

const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")

## Where a village prop's real art lives, and what happens until it does.
##
## Asked for directly: the stands, wells, beds and workspot props are drawn
## from code (ProceduralLandmarkSprite) and look out of place beside the
## real pixel art the houses and the city hall now have. This is the same
## contract BuildingCatalog._VARIANT_SHEETS gives a building, pointed at
## props -- a file at a known path takes over, and until that file exists
## the procedural sprite is drawn exactly as before, so nothing breaks
## while the art is still being made.
##
## ## What to draw, and where to put it
##
## One PNG per prop at `res://assets/sprites/landmarks/<id>.png`, for the
## ids in ProceduralLandmarkSprite.LANDMARK_IDS plus "hunting_ground" (a
## hunter's own prop, which has never had art and falls back to the well's
## sprite today). Same sheet conventions the building art already uses:
## a BLACK background, which is keyed out (IllustratedStructureSprite's own
## black threshold), and art authored oversized for pixel detail -- the
## renderer scales it back by ArtResolution.SPRITE_SCALE so the world
## footprint is unchanged whatever size the file is.
##
## ## One image is enough
##
## A building's sheet is a 5x5 grid because twenty-five cottages make a
## street look unrepeated. A well is a well; asking for twenty-five
## drawings of one to get one on screen is the wrong trade, so a plain
## single-image file is the default and the whole requirement. A prop that
## someone DOES draw variants for declares its grid in _SHEET_GRIDS below
## and then draws from it seeded, exactly the way a house does -- the grid
## is gutter-detected at load, so the cells need not be evenly spaced.

const SHEET_DIR := "res://assets/sprites/landmarks/"

## The hunter's own prop, absent from ProceduralLandmarkSprite.LANDMARK_IDS
## because it has no procedural drawing of its own -- it falls back to the
## well's sprite today (a known cosmetic gap). Art dropped in for it is
## picked up like any other.
const EXTRA_PROP_IDS: Array[String] = ["hunting_ground"]

## Props whose art is a grid of variants rather than one drawing, as
## (columns, rows). Empty by default: every prop is one image until someone
## decides a particular one is worth varying.
const _SHEET_GRIDS := {}


## Where this prop's art file goes, or "" for an id that is not a prop.
static func sheet_path_for(landmark_id: String) -> String:
	if landmark_id == "":
		return ""
	return SHEET_DIR + landmark_id + ".png"


## Whether real art has actually been supplied for this prop. False keeps
## the procedural sprite, which is what every prop draws today.
static func has_sheet(landmark_id: String) -> bool:
	var path := sheet_path_for(landmark_id)
	if path == "":
		return false
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)


## This prop's variant grid: one cell unless it declares otherwise.
static func grid_of(landmark_id: String) -> Vector2i:
	return _SHEET_GRIDS.get(landmark_id, Vector2i.ONE)


## Which cell of this prop's grid a given seed draws.
static func variant_cell_for(landmark_id: String, seed_value: int) -> Vector2i:
	return variant_cell_for_grid(seed_value, grid_of(landmark_id))


## Column and row from INDEPENDENT hashes of the same seed, so the pair
## spreads over the whole grid rather than walking its diagonal -- the same
## shape BuildingCatalog.variant_cell_for uses, and pinned the same way.
static func variant_cell_for_grid(seed_value: int, grid: Vector2i) -> Vector2i:
	if grid.x <= 1 and grid.y <= 1:
		return Vector2i.ZERO
	return Vector2i(
		absi(hash("%d_prop_column" % seed_value)) % maxi(grid.x, 1),
		absi(hash("%d_prop_row" % seed_value)) % maxi(grid.y, 1)
	)


## The prop's own art as an image, black keyed out and ready to scale, or
## null when no art has been supplied -- the caller then draws the
## procedural sprite exactly as before.
static func frame_image(landmark_id: String, seed_value: int, illustrator) -> Image:
	if not has_sheet(landmark_id):
		return null
	var grid := grid_of(landmark_id)
	var cell := variant_cell_for(landmark_id, seed_value)
	return illustrator.variant_frame_image(
		sheet_path_for(landmark_id), grid.x, grid.y, cell.y, cell.x
	)
