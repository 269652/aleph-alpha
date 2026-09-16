extends SceneTree

## Measures how often a REAL settlement chunk near Berlin actually qualifies
## for its sawmill (docs/concept/village_growth.md mechanism 1): does real
## forest stand close enough to a buildable, outlying, spur-reachable plot?
## Reports the rate and, for the misses, how far the nearest forest cell was
## -- so any relaxation of INDUSTRY_FOREST_REACH_TILES is grounded in a
## measurement rather than guessed at.

const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const VillageLayout = preload("res://src/world/village_layout.gd")

const CHUNK_SIZE := 32


func _init() -> void:
	var generator := EarthChunkGenerator.new()
	var settlements := SettlementGenerator.new()
	var classifier := BiomeClassifier.new()
	var geo := GeoCoordinates.new()
	var centre := Vector2i(
		floori(float(geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES)) / float(CHUNK_SIZE)),
		floori(float(geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)) / float(CHUNK_SIZE)),
	)

	var scanned := 0
	var with_mill := 0
	var forest_cell_counts: Array = []
	var nearest_forest_distances: Array = []
	for dy in range(-22, 23):
		for dx in range(-22, 23):
			var coord := centre + Vector2i(dx, dy)
			if not settlements.has_settlement_at(coord, "grassland"):
				continue
			var chunk := generator.generate_chunk(coord, CHUNK_SIZE)
			if not settlements.has_settlement_at(coord, classifier.dominant_biome(chunk.biome)):
				continue
			scanned += 1

			var forest := {}
			for y in CHUNK_SIZE:
				for x in CHUNK_SIZE:
					if chunk.biome[y * CHUNK_SIZE + x] == "forest":
						forest[Vector2i(x, y)] = true
			forest_cell_counts.append(forest.size())

			var is_forest := func(cell: Vector2i) -> bool: return forest.has(cell)
			var is_buildable := func(cell: Vector2i) -> bool:
				if cell.x < 0 or cell.y < 0 or cell.x >= CHUNK_SIZE or cell.y >= CHUNK_SIZE:
					return false
				var biome: String = chunk.biome[cell.y * CHUNK_SIZE + cell.x]
				return biome != "forest" and biome != "ocean" and biome != "lake" and biome != "river"
			var never_occupied := func(_cell: Vector2i) -> bool: return false

			var plot: Dictionary = VillageLayout.industry_plot(
				"sawmill", CHUNK_SIZE, VillageLayout.seed_for(coord), is_buildable, is_forest, never_occupied
			)
			if not plot.is_empty():
				with_mill += 1
			elif not forest.is_empty():
				# How far is the nearest forest from the nearest legal
				# outlying site? Reported so a relaxation is measured.
				var best := 9999
				for cell in forest:
					var offset: Vector2i = cell - Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2)
					best = mini(best, maxi(absi(offset.x), absi(offset.y)))
				nearest_forest_distances.append(best)

	print("settlement chunks scanned: %d" % scanned)
	print("with a qualifying sawmill plot: %d (%.1f%%)" % [
		with_mill, 100.0 * float(with_mill) / maxf(float(scanned), 1.0)
	])
	var with_any_forest := 0
	var total_forest := 0
	for count in forest_cell_counts:
		total_forest += count
		if count > 0:
			with_any_forest += 1
	print("chunks with ANY forest cell: %d" % with_any_forest)
	print("mean forest cells per settlement chunk: %.1f" % (float(total_forest) / maxf(float(scanned), 1.0)))
	print("misses that DID have forest: %d" % nearest_forest_distances.size())
	quit()
