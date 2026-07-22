extends RefCounted

const HeightmapGenerator = preload("res://src/world/heightmap_generator.gd")
const HydraulicErosion = preload("res://src/world/hydraulic_erosion.gd")
const ClimateModel = preload("res://src/world/climate_model.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const Chunk = preload("res://src/world/chunk.gd")

## Offset applied to the world seed for the moisture noise field, so it
## doesn't just mirror the elevation noise.
const MOISTURE_SEED_OFFSET := 10007

var _heightmap_generator := HeightmapGenerator.new()
var _hydraulic_erosion := HydraulicErosion.new()
var _climate_model := ClimateModel.new()
var _biome_classifier := BiomeClassifier.new()


## Generates a whole small world in one pass: elevation (eroded), then a
## biome per cell from elevation + latitude-derived temperature + moisture.
## Returns a Chunk with no player modifications yet.
##
## See recommended_erosion_iterations() for a sane erosion_iterations value:
## passing more iterations than there are cells over-erodes into scattered
## pits instead of coherent rivers.
func generate_world(width: int, height: int, seed_value: int, erosion_iterations: int) -> Chunk:
	var elevation := _heightmap_generator.generate(width, height, seed_value)
	elevation = _hydraulic_erosion.erode(elevation, width, height, erosion_iterations, seed_value)
	var moisture := _heightmap_generator.generate(width, height, seed_value + MOISTURE_SEED_OFFSET)

	var biome := PackedStringArray()
	biome.resize(width * height)

	for y in height:
		var latitude := latitude_at(y, height)
		for x in width:
			var index := y * width + x
			var temperature := _climate_model.temperature_at(latitude, elevation[index])
			biome[index] = _biome_classifier.classify(elevation[index], temperature, moisture[index])

	var chunk := Chunk.new()
	chunk.width = width
	chunk.height = height
	chunk.elevation = elevation
	chunk.biome = biome
	return chunk


## An erosion_iterations value that keeps generate_world's terrain spatially
## coherent (large landmasses) rather than over-eroded into scattered pits.
## Each iteration carves one droplet's path, so this scales with cell count.
const EROSION_ITERATIONS_PER_CELL := 0.125


func recommended_erosion_iterations(width: int, height: int) -> int:
	return int(width * height * EROSION_ITERATIONS_PER_CELL)


## Returns latitude in [0.0, 1.0]: 0.0 at the vertical center (equator), 1.0 at
## the top/bottom edges. The world wraps top-to-bottom (see WorldCoordinates),
## so both edges being coldest keeps the wrap climatically continuous rather
## than jumping from cold straight to hot.
func latitude_at(world_y: int, world_height: int) -> float:
	var half := (world_height - 1) / 2.0
	if half == 0.0:
		return 0.0
	return clampf(absf(world_y - half) / half, 0.0, 1.0)
