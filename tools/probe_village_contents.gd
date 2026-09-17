extends SceneTree

## Throwaway probe: founds the village at the reported coordinates for real
## and prints every building that actually ends up standing in it, so
## "no farmhouses" can be answered with a list instead of a screenshot.

const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")

func _initialize() -> void:
	var EarthChunkManager = load("res://src/world/earth_chunk_manager.gd")
	var tile_map_layer := TileMapLayer.new()
	var entities := Node2D.new()
	var creatures := Node2D.new()
	root.add_child(tile_map_layer)
	root.add_child(entities)
	root.add_child(creatures)
	var manager = EarthChunkManager.new(tile_map_layer, entities, creatures)

	var geo := GeoCoordinates.new()
	var size: int = EarthChunkManager.CHUNK_SIZE
	var centre := Vector2i(
		floori(float(geo.tile_for_longitude(9.6, EarthChunkGenerator.WORLD_WIDTH_TILES)) / float(size)),
		floori(float(geo.tile_for_latitude(48.1, EarthChunkGenerator.WORLD_HEIGHT_TILES)) / float(size)),
	)
	var gen := SettlementGenerator.new()
	var classifier := BiomeClassifier.new()
	var found := 0
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			if found >= 4:
				break
			var coord := centre + Vector2i(dx, dy)
			if not gen.has_settlement_at(coord, "grassland"):
				continue
			var chunk = manager.generator.generate_chunk(coord, size)
			if not gen.has_settlement_at(coord, classifier.dominant_biome(chunk.biome)):
				continue
			manager._load_chunk(coord)
			var counts := {}
			for record in manager.buildings_in_chunk(coord):
				var id: String = record.get("id", "")
				counts[id] = int(counts.get(id, 0)) + 1
			# The roster read from the SAME source _place_farms_if_missing
			# counts, not from the scene tree: walking the spawned markers
			# reported nobody farming even in the village that HAS a farmhouse,
			# which only gets built when somebody does -- a broken measurement,
			# not a finding.
			var settlement := gen.generate_settlement(
				coord, coord * size, size, 16, SettlementGenerator.POPULATION
			)
			var occupations := {}
			for npc in settlement.npcs:
				occupations[npc.occupation] = int(occupations.get(npc.occupation, 0)) + 1
			var wants_farm := int(occupations.get("farmer", 0)) + int(occupations.get("herbalist", 0))
			print("VILLAGE %s farmhouses=%d wanted_by=%d fishers=%d buildings=%s occupations=%s" % [
				str(coord), int(counts.get("farmhouse", 0)), wants_farm,
				int(occupations.get("fisher", 0)), str(counts), str(occupations)
			])
			manager._unload_chunk(coord)
			found += 1
	quit()
