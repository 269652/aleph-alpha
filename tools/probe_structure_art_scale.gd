extends SceneTree

## How big is a placed structure actually DRAWN, next to a person?
##
## Reported live: *"Also there's a weird shrunk farmhouse fix that too"* -- a
## farmhouse smaller than the villager standing beside it.
## IllustratedStructureSprite._footprint_scale scales a whole building so its
## CELL is one tile wide, which npc_farm_production.md's "Real art" section
## specifies in as many words ("width matches the tile"). This measures what
## that rule really produces: the cell, the real art inside it (the sheet
## draws each subject with margin, exactly like fence.png did), the drawn
## size in tiles, and the same subject's own footprint in BuildingCatalog,
## which is what the village raises the very same art at.

const IllustratedStructureSprite = preload("res://src/rendering/illustrated_structure_sprite.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const StoneSize = preload("res://src/world/stone_size.gd")

## The catalog building each placeable structure's art is shared with -- the
## village raises the same sheet as a real multi-tile building.
const CATALOG_TWIN := {
	"farm": "farmhouse",
	"sagewerk": "sawmill",
	"storage": "warehouse",
	"city_hall": "city_hall",
}


func _initialize() -> void:
	var sprite := IllustratedStructureSprite.new()
	var tile := float(TerrainRenderer.TILE_SIZE)
	var person_tiles: float = StoneSize.PLAYER_WORLD_HEIGHT_PX / tile
	print("tile %d px; a person is %.2f tiles tall (%.0f cm)" % [
		TerrainRenderer.TILE_SIZE, person_tiles, StoneSize.PLAYER_HEIGHT_CM,
	])
	print()
	print("%-11s %-13s %-15s %-15s %-9s %s" % [
		"subject", "cell", "art in cell", "drawn (tiles)", "vs person", "catalog twin",
	])
	for subject in CATALOG_TWIN:
		var idle := sprite.idle_texture(subject)
		if idle == null:
			print("%-11s no art" % subject)
			continue
		var source := idle.get_image()
		var art: Rect2i = sprite._art_rect(subject, source)
		var drawn := sprite.footprint_texture(subject, TerrainRenderer.TILE_SIZE)
		# What the eye actually sees: the ART, scaled by the same factor the
		# whole cell was, not the cell's own full width.
		var scale := float(drawn.get_width()) / float(source.get_width())
		var art_w := float(art.size.x) * scale / tile
		var art_h := float(art.size.y) * scale / tile
		var twin: String = CATALOG_TWIN[subject]
		var footprint: Vector2i = BuildingCatalog.footprint_of(twin)
		print("%-11s %-13s %-15s %-15s %-9s %s %s" % [
			subject,
			"%dx%d" % [source.get_width(), source.get_height()],
			"%dx%d (%d%%)" % [art.size.x, art.size.y, roundi(100.0 * float(art.size.x) / float(source.get_width()))],
			"%.2f x %.2f" % [art_w, art_h],
			"%.2fx" % (art_h / person_tiles),
			twin,
			"%dx%d" % [footprint.x, footprint.y] if footprint != Vector2i.ZERO else "(none)",
		])
	print()
	print("drawn (tiles) is the REAL art's size on screen, not the cell's.")
	print("vs person: how tall the building reads next to a villager -- under")
	print("1.0x means the building is shorter than the person standing in it.")
	quit()
