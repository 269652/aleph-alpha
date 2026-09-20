extends RefCounted

## A build-palette icon: the building's OWN art, fitted into a square box
## (see docs/concept/planner_mode.md, "The build palette").
##
## The picture is cut from exactly the sheet that building will be drawn
## from once it stands -- BuildingCatalog.finished_sheet_chain, the same
## chain EarthChunkManager._spawn_building_node walks. That is pillar 2's
## "one vocabulary" applied to the menu: a hand-drawn icon set would be a
## SECOND picture of every building, free to disagree with the first, and
## the player would be choosing from pictures of buildings this game does
## not have.
##
## Pavement is not a BuildingCatalog entry, so it cannot come off a
## building sheet at all -- it draws the real road tile it will lay
## (TerrainRenderer.road_tile_image), by the same rule.

const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const BuildPlan = preload("res://src/world/build_plan.gd")
const IllustratedStructureSprite = preload("res://src/rendering/illustrated_structure_sprite.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

## The one seed every icon's art is cut at.
##
## A finished building's picture is SEEDED on purpose -- a street is a
## street of different cottages (BuildingLifecycleSheet.idle_cell_for) --
## so an icon needs one pinned seed or the menu would show a different
## cottage every time the HUD was rebuilt. Which seed does not matter;
## that it is always the same one does, and that is what
## test_the_same_building_is_always_the_same_icon pins.
const ICON_SEED := 0

var _structures := IllustratedStructureSprite.new()
## Built only when pavement is actually asked for -- every other blueprint
## reaches its art without one.
var _terrain: TerrainRenderer = null


## `source` scaled to sit inside a `box`-by-`box` square with its aspect
## intact: the constraining axis reaches the box exactly, the other falls
## short. ZERO for a degenerate source or box, so nothing divides by zero.
##
## Fitted rather than squashed, deliberately. A manor really is wider than
## it is tall and a cottage is nearly square; stretching each to fill the
## same square would report every building as the same shape, which is the
## one thing an icon exists to say.
static func fitted_size(source: Vector2i, box: int) -> Vector2i:
	if source.x <= 0 or source.y <= 0 or box <= 0:
		return Vector2i.ZERO
	var scale := minf(float(box) / float(source.x), float(box) / float(source.y))
	return Vector2i(
		clampi(int(round(float(source.x) * scale)), 1, box),
		clampi(int(round(float(source.y) * scale)), 1, box)
	)


## This blueprint's icon as a `box`-by-`box` RGBA image, transparent around
## the art. Null for a blueprint with no art to cut and for an unknown id
## -- the caller's cue to draw nothing rather than a wrong picture.
##
## Always the full box whatever the building, so a row of slots is a row
## rather than a ragged line; the fit above is what varies inside it.
func icon_image(blueprint_id: String, box: int) -> Image:
	if box <= 0:
		return null
	var source := _source_image(blueprint_id)
	if source == null:
		return null
	return _boxed(source, box)


func icon_texture(blueprint_id: String, box: int) -> ImageTexture:
	var image := icon_image(blueprint_id, box)
	if image == null:
		return null
	return ImageTexture.create_from_image(image)


## The raw art, before it is fitted: the road tile for pavement, otherwise
## the first sheet of the building's own finished chain that is really on
## disk. Null when none of them is -- the same walk-the-chain-and-take-the-
## first-that-loads shape EarthChunkManager._first_texture_of already uses,
## so an icon and the building it stands for cannot come off different
## sheets.
func _source_image(blueprint_id: String) -> Image:
	if blueprint_id == BuildPlan.PAVEMENT_BLUEPRINT_ID:
		if _terrain == null:
			_terrain = TerrainRenderer.new()
		return _terrain.road_tile_image()
	if not BuildingCatalog.has_building(blueprint_id):
		return null
	for entry in BuildingCatalog.finished_sheet_chain(blueprint_id, ICON_SEED):
		var cut := _cut(entry)
		if cut != null:
			return cut
	return null


## One chain entry's cell. Dispatches on the entry's own declared grid
## rather than assuming an even one -- all three kinds are real on disk
## (see IllustratedStructureSprite), and reading a divider sheet as an even
## one is a whole label band out.
func _cut(entry: Dictionary) -> Image:
	var path := String(entry["path"])
	var columns := int(entry["columns"])
	var rows := int(entry["rows"])
	var row := int(entry["row"])
	var column := int(entry["column"])
	match String(entry["grid"]):
		IllustratedStructureSprite.GRID_GUTTERS:
			return _structures.variant_frame_image(path, columns, rows, row, column)
		IllustratedStructureSprite.GRID_DIVIDERS:
			return _structures.divider_frame_image(path, columns, rows, row, column)
	return _structures.sheet_frame_image(path, columns, rows, row, column)


## Trimmed to its own art, fitted, and centred on a transparent square.
##
## The trim matters: a keyed cell carries however much empty sky the artist
## drew above the roof, and a row of slots each holding a small building in
## a large transparent margin is the ragged line the box was meant to
## prevent. Image.get_used_rect is that bound.
func _boxed(image: Image, box: int) -> Image:
	var used := image.get_used_rect()
	var art := image
	if used.size.x > 0 and used.size.y > 0:
		art = image.get_region(used)
	var fitted := fitted_size(Vector2i(art.get_width(), art.get_height()), box)
	if fitted == Vector2i.ZERO:
		return null
	var scaled := art.duplicate() as Image
	if scaled.get_format() != Image.FORMAT_RGBA8:
		scaled.convert(Image.FORMAT_RGBA8)
	scaled.resize(fitted.x, fitted.y, Image.INTERPOLATE_LANCZOS)
	var canvas := Image.create(box, box, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	canvas.blit_rect(
		scaled, Rect2i(Vector2i.ZERO, fitted), Vector2i((box - fitted.x) / 2, (box - fitted.y) / 2)
	)
	return canvas
