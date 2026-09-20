extends SceneTree

## Where does a building's hitbox really stand, against the tiles it really
## owns?
##
## Reported live: *"houses hitbox extend by 20% above their tiles blocking
## movement"*. This prints, for every building in a real loaded village, the
## footprint rows the catalog gives it and the world rectangle its
## StaticBody2D actually covers -- so "the collider is too tall" can be told
## apart from "something else is blocking that tile", which feel identical
## when you walk into them.

const CHUNK_SIZE := 32


func _initialize() -> void:
	var EarthChunkManager = load("res://src/world/earth_chunk_manager.gd")
	var EarthChunkGenerator = load("res://src/world/earth_chunk_generator.gd")
	var GeoCoordinates = load("res://src/world/geo_coordinates.gd")
	var TerrainRenderer = load("res://src/rendering/terrain_renderer.gd")
	var BuildingCatalog = load("res://src/gameplay/building_catalog.gd")
	var SettlementGenerator = load("res://src/world/settlement_generator.gd")

	var tile_map_layer := TileMapLayer.new()
	var entities_parent := Node2D.new()
	var creatures_parent := Node2D.new()
	get_root().add_child(entities_parent)
	var manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)

	var geo = GeoCoordinates.new()
	# A chunk we KNOW loads, with a house placed into it by hand. Hunting a
	# generated village for one was how the first run of this probe measured
	# nothing at all: the settlement generator says a village belongs at a
	# coordinate, and whether the real chunk there can carry one is a
	# separate question it does not answer.
	var tile := float(TerrainRenderer.TILE_SIZE)
	var home := Vector2i(
		geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	var found := Vector2i(floori(float(home.x) / CHUNK_SIZE), floori(float(home.y) / CHUNK_SIZE))
	manager._load_chunk(found)

	var house_id: String = BuildingCatalog.BUILDING_IDS[0]
	var placed := false
	var origin_used := Vector2i.ZERO
	for y in range(4, 24):
		for x in range(4, 24):
			if manager.place_building(found, Vector2i(x, y), house_id, Vector2i(0, 1), 7, ""):
				placed = true
				origin_used = Vector2i(x, y)
				break
		if placed:
			break
	if not placed:
		print("could not place a house anywhere in %s" % str(found))
		quit()
		return

	print("chunk %s, tile %d px; placed a %s at %s" % [
		str(found), TerrainRenderer.TILE_SIZE, house_id, str(origin_used)
	])
	print()
	print("%-14s %-9s %-19s %-19s %s" % ["building", "footprint", "tiles own (y)", "collider (y)", "overhang"])

	var worst := 0.0
	var checked := 0
	var records: Array = manager.buildings_in_chunk(found)
	var node_count := 0
	for by_origin in manager._building_nodes.values():
		node_count += by_origin.size()
	print("records: %d, spawned building nodes: %d" % [records.size(), node_count])
	for record in records:
		var building_id: String = record.get("id", "")
		var footprint: Vector2i = BuildingCatalog.footprint_of(building_id)
		if footprint == Vector2i.ZERO:
			continue
		var origin_local: Vector2i = record.get("origin_local", Vector2i.ZERO)
		var node = manager._building_nodes.get(found, {}).get(origin_local)
		if node == null:
			print("  %s at %s: no spawned node" % [building_id, str(origin_local)])
			continue
		var body = node.get_node_or_null("BuildingCollision")
		if body == null:
			print("  %s at %s: node has no BuildingCollision child" % [building_id, str(origin_local)])
			continue
		var shape_node = body.get_child(0)
		var size: Vector2 = shape_node.shape.size
		# World-space extent of the collider.
		var centre_y: float = node.position.y + shape_node.position.y
		var top: float = centre_y - size.y * 0.5
		var bottom: float = centre_y + size.y * 0.5
		var origin_global: Vector2i = found * CHUNK_SIZE + origin_local
		var owns_top: float = float(origin_global.y) * tile
		var owns_bottom: float = float(origin_global.y + footprint.y) * tile
		var overhang: float = owns_top - top  # positive => collider reaches ABOVE its tiles
		worst = maxf(worst, overhang)
		checked += 1
		if checked <= 10:
			print("%-14s %-9s %-19s %-19s %+.2f px (%+.0f%% of a tile)" % [
				building_id, "%dx%d" % [footprint.x, footprint.y],
				"%.1f..%.1f" % [owns_top, owns_bottom],
				"%.1f..%.1f" % [top, bottom],
				overhang, 100.0 * overhang / tile,
			])
	var Player = load("res://scenes/player.gd")
	print()
	print("the player's own collider: %dx%d px (%.0f%% of a tile), centred on the player's origin" % [
		Player.PLAYER_SIZE, Player.PLAYER_SIZE, 100.0 * float(Player.PLAYER_SIZE) / tile,
	])
	print("  so their leading edge reaches %.2f px (%.0f%% of a tile) ahead of that origin" % [
		float(Player.PLAYER_SIZE) * 0.5, 100.0 * float(Player.PLAYER_SIZE) * 0.5 / tile,
	])
	print()
	print("%d buildings checked; worst overhang above its own tiles: %+.2f px (%+.0f%% of a tile)" % [
		checked, worst, 100.0 * worst / tile,
	])
	quit()
