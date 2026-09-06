extends RefCounted

## Spawns/despawns MushroomMarker nodes to match a WildMushroomPatch sim's
## current fruiting cells -- WildCropRenderer's exact shape (individual
## Node2D per cell: mushrooms are sparse, and each needs its own real
## identity -- hover name/actions).

const MushroomMarker = preload("res://src/rendering/mushroom_marker.gd")


## Builds one MushroomMarker per `sim.get_fruiting_cells()`, added to
## `parent`, keyed by cell. The caller (EarthChunkManager) holds onto the
## returned Dictionary and passes it back into sync_markers on later
## refresh ticks.
func spawn_markers(parent: Node, sim, chunk_origin: Vector2i, tile_size: float) -> Dictionary:
	var markers := {}
	for cell in sim.get_fruiting_cells():
		var marker := _build_marker(sim, cell, chunk_origin, tile_size)
		parent.add_child(marker)
		markers[cell] = marker
	return markers


## Keeps `markers` (mutated in place) in sync with `sim`'s current fruiting
## cells: spawns a marker for any cell that's newly fruiting, and frees +
## removes any marker whose mushroom was picked or aged out.
##
## Crushed/bitten corpses (see docs/concept/soil_fauna.md's "A corpse is
## new ground", WildMushroomPatch.is_corpse/corpse_kind) also count as
## live for this sync -- a corpse lingers for the same recovery window a
## fresh flush waits out rather than vanishing the instant it stops
## fruiting, mirroring EarthChunkManager._sync_worm_sprites' own
## is_corpse check. A cell whose corpse_kind CHANGED since its marker was
## built (impossible today -- a corpse can only be created once per
## recovery cycle -- but cheap to keep correct) is handled the same way a
## newly-fruiting cell is: free the stale marker and rebuild, since
## _build_marker is the one place corpse_kind gets baked into a marker at
## all.
func sync_markers(parent: Node, sim, chunk_origin: Vector2i, tile_size: float, markers: Dictionary) -> void:
	var live_cells := {}
	for cell in sim.get_fruiting_cells():
		live_cells[cell] = true
		if not markers.has(cell):
			var marker := _build_marker(sim, cell, chunk_origin, tile_size)
			parent.add_child(marker)
			markers[cell] = marker

	for cell in sim.get_site_cells():
		if not sim.is_corpse(cell):
			continue
		live_cells[cell] = true
		var kind: String = sim.corpse_kind(cell)
		if markers.has(cell) and markers[cell].corpse_kind == kind:
			continue
		if markers.has(cell):
			markers[cell].queue_free()
		var marker := _build_marker(sim, cell, chunk_origin, tile_size)
		parent.add_child(marker)
		markers[cell] = marker

	for cell in markers.keys().duplicate():
		if not live_cells.has(cell):
			markers[cell].queue_free()
			markers.erase(cell)


func _build_marker(sim, cell: Vector2i, chunk_origin: Vector2i, tile_size: float) -> MushroomMarker:
	var marker := MushroomMarker.new()
	var tile: Vector2i = chunk_origin + cell
	marker.position = Vector2((tile.x + 0.5) * tile_size, (tile.y + 0.5) * tile_size)
	marker.species_id = sim.species_at(cell)
	marker.mushroom_seed = hash("%d_%d_mushroom" % [tile.x, tile.y])
	marker.cell = cell
	marker.mushroom_world = sim
	marker.corpse_kind = sim.corpse_kind(cell)
	return marker
