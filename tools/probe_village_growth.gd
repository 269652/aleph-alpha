extends SceneTree

## Throwaway probe: does a village really grow by itself, and does growing
## bring new houses and new trades?
##
## Asked directly: *"increase the village sizes from 5 houses to 10 initial
## and then it should grow by itself; adding new houses new trades"*. This
## drives the REAL settlement step on a REAL loaded settlement chunk and
## prints, every few simulated days, how many households the village has,
## how many houses really stand, and which trades are among them -- so
## "it grows" is a measurement rather than a claim.

const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const VillageImmigration = preload("res://src/emergence/village_immigration.gd")

const STEPS := 120


func _initialize() -> void:
	var EarthChunkManager = load("res://src/world/earth_chunk_manager.gd")
	var tile_map_layer := TileMapLayer.new()
	var entities := Node2D.new()
	var creatures := Node2D.new()
	root.add_child(tile_map_layer)
	root.add_child(entities)
	root.add_child(creatures)
	var manager = EarthChunkManager.new(tile_map_layer, entities, creatures)

	var size: int = EarthChunkManager.CHUNK_SIZE
	var geo := GeoCoordinates.new()
	var centre := Vector2i(
		floori(float(geo.tile_for_longitude(12.7, EarthChunkGenerator.WORLD_WIDTH_TILES)) / float(size)),
		floori(float(geo.tile_for_latitude(48.6, EarthChunkGenerator.WORLD_HEIGHT_TILES)) / float(size)),
	)
	var gen := SettlementGenerator.new()
	var classifier := BiomeClassifier.new()
	var coord = null
	for dy in range(-12, 13):
		for dx in range(-12, 13):
			var candidate := centre + Vector2i(dx, dy)
			if not gen.has_settlement_at(candidate, "grassland"):
				continue
			var chunk = manager.generator.generate_chunk(candidate, size)
			if gen.has_settlement_at(candidate, classifier.dominant_biome(chunk.biome)):
				coord = candidate
				break
		if coord != null:
			break
	if coord == null:
		print("no settlement chunk found")
		quit(1)
		return

	manager._load_chunk(coord)
	var settlement_id := EntityRef.for_settlement(coord)
	var market = manager.market_store().market_for(settlement_id)
	print("FOUNDED at %s: households=%d  roster=%d" % [
		str(coord), manager.household_count_for_settlement(settlement_id), SettlementGenerator.POPULATION
	])
	print("immigration day = %.0fs, settlement step = %.0fs" % [
		VillageImmigration.SECONDS_PER_SIMULATED_DAY, EarthChunkManager.SETTLEMENT_STEP_INTERVAL
	])

	for step in STEPS:
		# A village only draws while it is fed (VillageImmigration.
		# FED_THRESHOLD): this probe is about growth, not about whether the
		# larder fills, so it keeps the larder full deliberately.
		market.add_stock("fish", 40.0)
		var before := {}
		for item_id in ["wood", "stone", "plant_fibre"]:
			before[item_id] = market.stock.get(item_id, 0.0)
		manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
		if step < 12:
			var deltas := ""
			for item_id in ["wood", "stone", "plant_fibre"]:
				deltas += " %s %+.0f->%.0f" % [
					item_id, market.stock.get(item_id, 0.0) - float(before[item_id]),
					market.stock.get(item_id, 0.0)
				]
			var live = manager.market_store().market_for(settlement_id)
			print("  step %2d:%s  probe_market=%d live_market=%d live_wood=%s" % [
				step, deltas, market.get_instance_id(), live.get_instance_id(),
				str(live.stock.get("wood", 0))
			])
		if step % 10 != 9:
			continue
		var households: int = manager.household_count_for_settlement(settlement_id)
		var houses := 0
		var others: Dictionary = {}
		for record in manager.buildings_in_chunk(coord):
			var id: String = record.get("id", "")
			if BuildingCatalog.capacity_of(id) > 0:
				houses += 1
			else:
				others[id] = int(others.get(id, 0)) + 1
		var ids: Array = manager._households_in_settlement(settlement_id)
		var census: Dictionary = manager._village_census_for(coord, ids)
		var site = manager._growth_site_for(coord, BuildingCatalog.BUILDING_IDS[0])
		var projects: Array = manager.construction_project_store().active_projects_in_chunk(coord)
		var project_note := ""
		for project in projects:
			project_note += " %s(status=%d,%.1fh,reserved=%s)" % [
				project.blueprint_id, project.status, project.labor_hours_accumulated,
				str(project.reserved_material)
			]
		var owed: String = manager._next_growth_building_for(coord) if manager.has_method("_next_growth_building_for") else "?"
		var tiles: Dictionary = {}
		var chunk = manager._loaded_chunks.get(coord)
		if chunk != null:
			for local in chunk.modifications:
				var id: String = chunk.modifications[local]
				tiles[id] = int(tiles.get(id, 0)) + 1
		var interesting: Dictionary = {}
		for id in tiles:
			if id != "road" and id != "footprint":
				interesting[id] = tiles[id]
		var shelves: Array = manager._settlement_structure_stocks(settlement_id)
		var shelf_note := ""
		for shelf in shelves:
			if not shelf.stock.is_empty():
				shelf_note += " " + str(shelf.stock)
		print("    shelves:%s" % (shelf_note if shelf_note != "" else " (all empty)"))
		print("    stock wood=%.0f stone=%.0f fibre=%.0f owed=%s projects:%s" % [
			market.stock.get("wood", 0.0), market.stock.get("stone", 0.0),
			market.stock.get("plant_fibre", 0.0), owed, project_note
		])
		print("  t=%5.0fs households=%2d houses=%2d spare_roofs=%s growth_site=%s food/hh=%.2f ladder=%.2f others=%s" % [
			(step + 1) * EarthChunkManager.SETTLEMENT_STEP_INTERVAL, households, houses,
			str(census.get("spare_house_capacity", "?")), "yes" if site != null else "NO",
			manager._food_per_household(settlement_id, market, ids.size()),
			manager._ladder_share_for(coord) if manager.has_method("_ladder_share_for") else -1.0,
			str(others)
		])
	quit(0)
