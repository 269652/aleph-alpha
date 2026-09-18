extends SceneTree

## Throwaway probe: for real settlement chunks, print the DEMAND side
## (SettlementGranary.subsistence_draw) against the SUPPLY one producer of
## each trade would really bring in over one assessment, off the chunk's own
## seeded region -- so a demand-driven roster rule is derived from measured
## magnitudes instead of guessed ones.

const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const SettlementGranary = preload("res://src/emergence/settlement_granary.gd")
const NpcProduction = preload("res://src/world/npc_production.gd")
const EcosystemSimulation = preload("res://src/world/ecosystem_simulation.gd")

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
	var production := NpcProduction.new()
	var interval: float = EarthChunkManager.SETTLEMENT_STEP_INTERVAL
	var found := 0
	var SettlementState = load("res://src/emergence/settlement_state.gd")
	print("DEMAND draw_per_household=%.2f interval=%.1f" % [
		SettlementState.FOOD_PER_HOUSEHOLD, interval
	])
	for dy in range(-10, 11):
		for dx in range(-10, 11):
			if found >= 8:
				break
			var coord := centre + Vector2i(dx, dy)
			if not gen.has_settlement_at(coord, "grassland"):
				continue
			var chunk = manager.generator.generate_chunk(coord, size)
			var biome: String = classifier.dominant_biome(chunk.biome)
			if not gen.has_settlement_at(coord, biome):
				continue
			var probe := EcosystemSimulation.new()
			probe.add_region(coord, chunk)
			var region = SettlementGranary.SeededRegion.new()
			region.vegetation_density = probe.average_vegetation_density(coord)
			region.herbivore_population = probe.herbivore_population(coord)
			region.fish_population = probe.fish_population(coord)
			var per_trade := {}
			for trade in ["farmer", "hunter", "fisher"]:
				per_trade[trade] = production.yield_per_second(trade, region, Vector2.ZERO) * interval
			var draw: int = SettlementGranary.subsistence_draw(SettlementGenerator.POPULATION)
			print("VILLAGE %s biome=%s veg=%.4f herb=%.3f fish=%.3f draw=%d farmer=%.3f hunter=%.3f fisher=%.3f" % [
				str(coord), biome, region.vegetation_density, region.herbivore_population,
				region.fish_population, draw,
				per_trade["farmer"], per_trade["hunter"], per_trade["fisher"]
			])
			found += 1
	quit()
