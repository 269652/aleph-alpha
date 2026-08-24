extends RefCounted

## Spawns/despawns WildCropMarker nodes to match a WildCropPatch sim's
## current cells -- the individual-Node2D-per-cell counterpart of what
## _sync_grass_sprites does with MultiMesh bands (see
## docs/concept/wild_crops.md). Wild crops are sparse (WildCropPatch.
## MAX_PATCHES is a fraction of TallGrass's) and each cell needs its own
## real identity -- hover name/actions, an independent pull animation -- so
## a plain Sprite2D-per-cell mirrors TreeRenderer/StoneRenderer here rather
## than grass's GPU-instanced band approach.

const WildCropMarker = preload("res://src/rendering/wild_crop_marker.gd")


## Builds one WildCropMarker per `sim.get_patch_cells()`, added to `parent`,
## keyed by cell. The caller (EarthChunkManager) holds onto the returned
## Dictionary and passes it back into sync_markers on later refresh ticks.
func spawn_markers(
	parent: Node, sim, crop_id: String, chunk_origin: Vector2i, tile_size: float
) -> Dictionary:
	var markers := {}
	for cell in sim.get_patch_cells():
		var marker := _build_marker(sim, crop_id, cell, chunk_origin, tile_size)
		parent.add_child(marker)
		markers[cell] = marker
	return markers


## Keeps `markers` (mutated in place) in sync with `sim`'s current patch
## cells: spawns a marker for any cell that's newly grown in (a spread
## tick), refreshes growth on every marker that's still there, and frees +
## removes any marker whose cell genuinely left the sim -- EXCEPT a cell
## still mid-pull-animation, whose cell is deliberately still present in
## the sim until the pull actually completes (see
## WildCropMarker._finish_pull), so it's never mistaken for "harvested
## elsewhere" and torn down out from under its own animation.
func sync_markers(
	parent: Node, sim, crop_id: String, chunk_origin: Vector2i, tile_size: float, markers: Dictionary
) -> void:
	var live_cells := {}
	for cell in sim.get_patch_cells():
		live_cells[cell] = true
		if markers.has(cell):
			markers[cell].growth = sim.get_growth(cell)
		else:
			var marker := _build_marker(sim, crop_id, cell, chunk_origin, tile_size)
			parent.add_child(marker)
			markers[cell] = marker

	for cell in markers.keys().duplicate():
		if not live_cells.has(cell):
			markers[cell].queue_free()
			markers.erase(cell)


func _build_marker(
	sim, crop_id: String, cell: Vector2i, chunk_origin: Vector2i, tile_size: float
) -> WildCropMarker:
	var marker := WildCropMarker.new()
	var tile: Vector2i = chunk_origin + cell
	marker.position = Vector2((tile.x + 0.5) * tile_size, (tile.y + 0.5) * tile_size)
	marker.crop_id = crop_id
	marker.sprite_seed = hash("%d_%d_wild_crop" % [tile.x, tile.y])
	marker.growth = sim.get_growth(cell)
	return marker
