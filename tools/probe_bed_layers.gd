extends SceneTree

## What a farm bed actually draws, layer by layer, as a fraction of its tile.
##
## Reported live with three beds in shot: *"weird sil tiles"* -- beds reading
## as separate brown squares with grass between them. A bed's pitch on screen
## IS one tile (beds are keyed by tile and centred on it), and the dirt
## measured 0.8 of that pitch, so whatever is drawn covers four fifths of the
## tile. The soil GROUND frame is solid and covers exactly one tile
## (tools/probe_soil_ground_size.gd), so this asks which layer is really on
## screen and how big each one is.

const FarmPlotMarker = preload("res://src/rendering/farm_plot_marker.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")


func _describe(name: String, sprite: Sprite2D) -> void:
	if sprite == null:
		print("RESULT %s=absent" % name)
		return
	if sprite.texture == null:
		print("RESULT %s visible=%s texture=null" % [name, sprite.visible])
		return
	var w := sprite.texture.get_width()
	var h := sprite.texture.get_height()
	print(
		"RESULT %s visible=%s tex=%dx%d scale=%.4f drawn_tiles=%.3f x %.3f z=%d"
		% [
			name, sprite.visible, w, h, sprite.scale.x,
			float(w) * sprite.scale.x / float(TerrainRenderer.TILE_SIZE),
			float(h) * sprite.scale.y / float(TerrainRenderer.TILE_SIZE),
			sprite.z_index,
		]
	)


func _initialize() -> void:
	var marker := FarmPlotMarker.new()
	marker.position = Vector2(1.5, 1.5) * TerrainRenderer.TILE_SIZE
	root.add_child(marker)
	await process_frame
	print("RESULT --- freshly built (untilled) ---")
	_describe("soil_ground", marker.soil_ground())
	_describe("mound", marker.mound())
	print("RESULT is_showing_soil=%s is_showing_mound=%s"
		% [marker.is_showing_soil(), marker.is_showing_mound()])

	marker.till_and_plant("wheat", 12345)
	print("RESULT --- after till_and_plant(wheat) ---")
	_describe("soil_ground", marker.soil_ground())
	_describe("mound", marker.mound())
	print("RESULT is_showing_soil=%s is_showing_mound=%s"
		% [marker.is_showing_soil(), marker.is_showing_mound()])
	quit()
