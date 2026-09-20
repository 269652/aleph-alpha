extends RefCounted

const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")
const ProceduralLandmarkSprite = preload("res://src/rendering/procedural_landmark_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")

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
## ids in ProceduralLandmarkSprite.LANDMARK_IDS (plus EXTRA_PROP_IDS, empty
## today). Same sheet conventions the building art already uses:
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

## Props that can take real art without ProceduralLandmarkSprite knowing how
## to draw them. Empty since 2026-09-17: "hunting_ground" was the only
## entry, and it is in LANDMARK_IDS now -- an id this catalog cannot draw
## silently falls back to the WELL's sprite, which put a second and third
## well in every village with hunters in it (reported live; see that
## catalog's own _hunting_ground_image). Kept as a real, empty seam rather
## than deleted: a prop whose art arrives before anyone draws it belongs
## here, and there is then one obvious place to say so.
const EXTRA_PROP_IDS: Array[String] = []

## Props whose delivered art does not match this module's own defaults --
## one drawing, in SHEET_DIR, cells found in dark gutters. Everything a
## sheet does differently is declared here rather than assumed, per id:
##
##   path   where the file actually is, when it is not SHEET_DIR/<id>.png
##   grid   (columns, rows) when the art is a grid of variants, not one
##          drawing
##   cells  how that grid's cells are found -- see
##          IllustratedStructureSprite's GRID_* names
##
## The stall's sheet (delivered 2026-09-17, filed as stand.png rather than
## stall.png) is also a 5x5 grid with magenta divider lines, but its own
## content defeats the generic divider-band scan: every cell draws an
## open gap between the roof and the table that reads as a near-full-
## width false divider, splitting each real row into two disparate-sized
## halves the generic "least size-varied run" heuristic cannot
## distinguish from real dividers (see IllustratedStructureSprite.
## explicit_frame_image's own doc comment). row_bands/column_bands are
## measured directly off the file with tools/_probe_stand_bands.gd and
## pinned here instead of trusted to the generic scan.
const _SHEETS := {
	"well": {
		"path": "res://assets/sprites/buildings/well.png",
		"grid": Vector2i(5, 5),
		"cells": "dividers",
	},
	"stall": {
		"path": "res://assets/sprites/buildings/stand.png",
		"grid": Vector2i(5, 5),
		"cells": "explicit",
		"row_bands": [
			Vector2i(45, 225), Vector2i(286, 473), Vector2i(524, 721),
			Vector2i(770, 966), Vector2i(1016, 1215),
		],
		"column_bands": [
			Vector2i(30, 227), Vector2i(281, 475), Vector2i(534, 726),
			Vector2i(778, 975), Vector2i(1027, 1226),
		],
	},
}


## Where this prop's art file is, or "" for an id that is not a prop.
static func sheet_path_for(landmark_id: String) -> String:
	if landmark_id == "":
		return ""
	var declared: Dictionary = _SHEETS.get(landmark_id, {})
	if declared.has("path"):
		return declared["path"]
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
	return _SHEETS.get(landmark_id, {}).get("grid", Vector2i.ONE)


## How this prop's grid cells are found. Dark gutters by default, which is
## what the building variant sheets already use; a sheet that draws real
## divider lines between its cells says so.
static func cells_of(landmark_id: String) -> String:
	return _SHEETS.get(landmark_id, {}).get("cells", "gutters")


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
	var declared: Dictionary = _SHEETS.get(landmark_id, {})
	if cells_of(landmark_id) == "explicit":
		return illustrator.explicit_frame_image(
			sheet_path_for(landmark_id), declared["row_bands"], declared["column_bands"], cell.y, cell.x
		)
	if cells_of(landmark_id) == "dividers":
		return illustrator.divider_frame_image(
			sheet_path_for(landmark_id), grid.x, grid.y, cell.y, cell.x
		)
	return illustrator.variant_frame_image(
		sheet_path_for(landmark_id), grid.x, grid.y, cell.y, cell.x
	)


## The prop's art scaled to the size that prop really is: width exactly
## ArtResolution.art_size of the prop's own world width
## (ProceduralLandmarkSprite.SIZES), height by the SAME factor so nothing
## is distorted. Null when no art has been supplied.
##
## Supplied art is NOT assumed to have been authored at the prop's size.
## The well sheet's cells are ~274x206 source pixels while a well is 40x44
## world units; drawn at ArtResolution.SPRITE_SCALE alone it would stand
## about three times as wide as the procedural well it replaces -- the
## exact failure IllustratedCropSprite already hit twice and documents at
## length ("huge potato crops above soil", and again after a re-tune).
## Measuring the art and scaling it to the world is the fix that stuck
## there, and it is the rule here.
## `world_width_px` overrides how wide this prop really is in the world.
## Given one, the art is scaled to IT -- the rule a building's own sheet
## follows: width matches the ground the thing stands on, height follows
## the same factor, so a tall prop overhangs upward and nothing ever
## overhangs sideways onto a neighbour's cell.
##
## Asked for directly: *"scale the art to its footprint"*. Without it the
## size comes from `ProceduralLandmarkSprite.SIZES` -- the old procedural
## placeholder box -- which has nothing to do with the ground a prop is
## sited and reserved on. The well's box is 40 world px against a 2x2
## footprint of 32, so a quarter of a tile hung over the paving on each
## side however well it was sited.
static func world_scaled_image(
	landmark_id: String, seed_value: int, illustrator, world_width_px: int = 0
) -> Image:
	var frame := frame_image(landmark_id, seed_value, illustrator)
	if frame == null:
		return null
	var world_size: Vector2i = ProceduralLandmarkSprite.SIZES.get(landmark_id, Vector2i(20, 20))
	if world_width_px > 0:
		world_size = Vector2i(world_width_px, world_size.y)
	var target_width: int = maxi(ArtResolution.art_size(world_size).x, 1)
	if frame.get_width() == target_width:
		return frame
	var scale := float(target_width) / float(frame.get_width())
	var scaled := frame.duplicate() as Image
	scaled.resize(target_width, maxi(1, int(round(float(frame.get_height()) * scale))), Image.INTERPOLATE_LANCZOS)
	return scaled
