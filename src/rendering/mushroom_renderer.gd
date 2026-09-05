extends RefCounted

## Spawns/despawns MushroomMarker nodes to match a WildMushroomPatch sim's
## current fruiting cells -- WildCropRenderer's exact shape (individual
## Node2D per cell, appropriate here for the same reason: mushroom sites
## are sparse and each needs its own real identity -- hover name/actions,
## an independent identification state -- unlike grass's GPU-instanced
## band approach).

const MushroomMarker = preload("res://src/rendering/mushroom_marker.gd")


## Builds one MushroomMarker per `sim.get_fruiting_cells()`, added to
## `parent`, keyed by cell. The caller (EarthChunkManager) holds onto the
## returned Dictionary and passes it back into sync_markers on later
## refresh ticks. `identified` is the current live `Player.knows_
## mushrooms()` value, pushed onto every marker the same way WildCropRenderer
## pushes the season onto every WildCropMarker.
func spawn_markers(
	parent: Node, sim, chunk_origin: Vector2i, tile_size: float, identified: bool
) -> Dictionary:
	var markers := {}
	for cell in sim.get_fruiting_cells():
		var marker := _build_marker(sim, cell, chunk_origin, tile_size, identified)
		parent.add_child(marker)
		markers[cell] = marker
	return markers


## Keeps `markers` (mutated in place) in sync with `sim`'s current fruiting
## cells: spawns a marker for any cell that's newly fruiting, refreshes
## `identified` on every marker that's still there (Player.knows_mushrooms()
## can flip true mid-play, and an already-standing marker has to show that
## on its very next sync -- see MushroomMarker's own `identified` setter),
## and frees + removes any marker whose mushroom was picked or aged out.
func sync_markers(
	parent: Node, sim, chunk_origin: Vector2i, tile_size: float, identified: bool,
	markers: Dictionary
) -> void:
	var live_cells := {}
	for cell in sim.get_fruiting_cells():
		live_cells[cell] = true
		if markers.has(cell):
			markers[cell].identified = identified
		else:
			var marker := _build_marker(sim, cell, chunk_origin, tile_size, identified)
			parent.add_child(marker)
			markers[cell] = marker

	for cell in markers.keys().duplicate():
		if not live_cells.has(cell):
			markers[cell].queue_free()
			markers.erase(cell)


func _build_marker(
	sim, cell: Vector2i, chunk_origin: Vector2i, tile_size: float, identified: bool
) -> MushroomMarker:
	var marker := MushroomMarker.new()
	var tile: Vector2i = chunk_origin + cell
	marker.position = Vector2((tile.x + 0.5) * tile_size, (tile.y + 0.5) * tile_size)
	marker.species_id = sim.species_at(cell)
	marker.mushroom_seed = hash("%d_%d_mushroom" % [tile.x, tile.y])
	marker.identified = identified
	marker.cell = cell
	marker.mushroom_world = sim
	return marker
