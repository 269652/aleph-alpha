extends RefCounted

const EarthElevationSource = preload("res://src/world/earth_elevation_source.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const ClimateModel = preload("res://src/world/climate_model.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const TerrainRelief = preload("res://src/world/terrain_relief.gd")
const Chunk = preload("res://src/world/chunk.gd")

## World scale: ~111 tiles per degree of latitude/longitude (~1km/tile),
## giving a full, finite Earth of ~40,000 x 20,000 tiles -- explorable at a
## Minecraft-like scale, chunk-streamed so only nearby chunks are ever held
## in memory (see EarthChunkManager).
const TILES_PER_DEGREE := 111.0
const WORLD_WIDTH_TILES := 39960
const WORLD_HEIGHT_TILES := 19980

## Real elevation thresholds, calibrated against the bundled asset (see
## assets/data/CREDITS.md) -- different from BiomeClassifier's default
## fictional-noise-tuned constants, since real elevation is a different scale.
const EARTH_SEA_LEVEL := 8000.0 / 14400.0
const EARTH_MOUNTAIN_LEVEL := 0.75
## Real depth in meters at elevation 0.0 (the ocean floor of the encoding),
## for converting normalized depth to gameplay-meaningful meters.
const EARTH_OCEAN_DEPTH_RANGE_METERS := 8000.0

## Amplitude of procedural fine detail layered on top of the real (coarse)
## macro elevation, since the source image is ~10km/pixel -- far coarser than
## a 1km tile. Small enough to add per-tile texture without overriding real
## geography. Moisture is fully procedural for now (no real precipitation
## data sourced yet -- open item).
const FINE_DETAIL_AMPLITUDE := 0.03
const FINE_DETAIL_FREQUENCY := 0.1
const FINE_DETAIL_SEED := 99991
const MOISTURE_FREQUENCY := 0.02
const MOISTURE_SEED := 424242

var _elevation_source := EarthElevationSource.new()
var _geo_coordinates := GeoCoordinates.new()
var _climate_model := ClimateModel.new()
var _biome_classifier := BiomeClassifier.new()
var _terrain_relief := TerrainRelief.new()

var _fine_detail_noise := FastNoiseLite.new()
var _moisture_noise := FastNoiseLite.new()


func _init() -> void:
	_fine_detail_noise.seed = FINE_DETAIL_SEED
	_fine_detail_noise.frequency = FINE_DETAIL_FREQUENCY
	_moisture_noise.seed = MOISTURE_SEED
	_moisture_noise.frequency = MOISTURE_FREQUENCY


## Generates one chunk_size x chunk_size chunk at chunk_coord (in units of
## chunks, not tiles). Every cell is computed purely from its global tile
## coordinate, so any two chunks are automatically seamless at their shared
## border -- there is no chunk-relative state to get out of sync.
func generate_chunk(chunk_coord: Vector2i, chunk_size: int) -> Chunk:
	var elevation := PackedFloat32Array()
	elevation.resize(chunk_size * chunk_size)
	var biome := PackedStringArray()
	biome.resize(chunk_size * chunk_size)
	var moisture := PackedFloat32Array()
	moisture.resize(chunk_size * chunk_size)
	var temperature := PackedFloat32Array()
	temperature.resize(chunk_size * chunk_size)

	for local_y in chunk_size:
		var global_y := chunk_coord.y * chunk_size + local_y
		for local_x in chunk_size:
			var global_x := chunk_coord.x * chunk_size + local_x
			var index := local_y * chunk_size + local_x

			var cell_elevation := elevation_at_global(global_x, global_y)
			elevation[index] = cell_elevation
			moisture[index] = moisture_at_global(global_x, global_y)
			# Reuses the elevation computed one line above rather than making
			# temperature_at_global re-derive it -- see
			# temperature_at_elevation's own doc comment.
			temperature[index] = temperature_at_elevation(global_y, cell_elevation)
			biome[index] = _biome_at_global(
				global_x, global_y, cell_elevation, temperature[index], moisture[index]
			)

	var chunk := Chunk.new()
	chunk.width = chunk_size
	chunk.height = chunk_size
	chunk.elevation = elevation
	chunk.biome = biome
	chunk.moisture = moisture
	chunk.temperature = temperature
	return chunk


## Real macro elevation only, with no procedural fine detail -- exposed so
## the blend can be verified independently of the noise layer.
func macro_elevation_at_global(global_x: int, global_y: int) -> float:
	var latitude := _geo_coordinates.latitude_for_tile(global_y, WORLD_HEIGHT_TILES)
	var longitude := _geo_coordinates.longitude_for_tile(global_x, WORLD_WIDTH_TILES)
	return _elevation_source.elevation_at(latitude, longitude)


## Real macro elevation blended with procedural fine detail, for any global
## tile coordinate -- the single source of truth generate_chunk() slices.
func elevation_at_global(global_x: int, global_y: int) -> float:
	var macro := macro_elevation_at_global(global_x, global_y)
	var fine_detail := _fine_detail_noise.get_noise_2d(global_x, global_y) * FINE_DETAIL_AMPLITUDE
	return clampf(macro + fine_detail, 0.0, 1.0)


## Real slope in degrees at a global tile (see terrain_relief.gd's slope_at,
## docs/concept/terrain_relief.md). Reads the same RAW elevation source
## macro_elevation_at_global does, not the fine-detail-blended
## elevation_at_global -- the fine-detail layer exists to compensate for the
## source image's real ~10km/pixel coarseness (see FINE_DETAIL_AMPLITUDE's
## own doc comment), which is texture, not real geological relief, and would
## only add noise to a real slope reading rather than inform it.
func slope_at_global(global_x: int, global_y: int) -> float:
	var latitude := _geo_coordinates.latitude_for_tile(global_y, WORLD_HEIGHT_TILES)
	var longitude := _geo_coordinates.longitude_for_tile(global_x, WORLD_WIDTH_TILES)
	return _terrain_relief.slope_at(_elevation_source, latitude, longitude)


## Real aspect (compass bearing the slope faces) at a global tile -- see
## slope_at_global's own doc comment and terrain_relief.gd's aspect_at.
func aspect_at_global(global_x: int, global_y: int) -> float:
	var latitude := _geo_coordinates.latitude_for_tile(global_y, WORLD_HEIGHT_TILES)
	var longitude := _geo_coordinates.longitude_for_tile(global_x, WORLD_WIDTH_TILES)
	return _terrain_relief.aspect_at(_elevation_source, latitude, longitude)


## The raw elevation gradient at a global tile, for a caller that wants BOTH
## slope and aspect there -- the two are readings of one gradient (see
## TerrainRelief.gradient_at), so asking for them separately takes the same
## four elevation samples twice. Reads the same RAW elevation source
## slope_at_global/aspect_at_global do, for the reason spelled out in
## slope_at_global's own doc comment.
##
## Derive the two readings with TerrainRelief.slope_degrees_from_gradient and
## aspect_degrees_from_gradient, which are pure -- EarthChunkManager's
## hillshade painter is the caller this exists for.
func gradient_at_global(global_x: int, global_y: int) -> Vector2:
	var latitude := _geo_coordinates.latitude_for_tile(global_y, WORLD_HEIGHT_TILES)
	var longitude := _geo_coordinates.longitude_for_tile(global_x, WORLD_WIDTH_TILES)
	return _terrain_relief.gradient_at(_elevation_source, latitude, longitude)


## The shared TerrainRelief this generator derives slope/aspect with -- so a
## caller holding a gradient from gradient_at_global above can derive the two
## readings through the same instance rather than constructing its own.
func terrain_relief() -> TerrainRelief:
	return _terrain_relief


## Real precipitation-proxy moisture for any global tile coordinate, normalized
## to [0.0, 1.0]. Fully procedural for now (no real precipitation data sourced
## yet -- open item, see FINE_DETAIL_AMPLITUDE's comment above).
func moisture_at_global(global_x: int, global_y: int) -> float:
	return (_moisture_noise.get_noise_2d(global_x, global_y) + 1.0) / 2.0


## Real latitude/elevation-derived temperature for a tile whose elevation the
## caller ALREADY has, normalized to [0.0, 1.0] (see
## ClimateModel.temperature_at).
##
## generate_chunk and biome_at_global both compute a cell's elevation one line
## before asking for its temperature, and temperature_at_global below used to
## re-derive it from scratch -- four extra bilinear elevation samples, i.e.
## sixteen extra byte reads, per cell, for a number already sitting in a
## local. That doubled the elevation sampling of every generated chunk (8,192
## reads per 32x32 chunk where 4,096 do) and of biome_at_global, which is not
## a cold path: TerrainRenderer.paint asks it for every out-of-chunk border
## neighbour, and EarthChunkManager's water overlay asks it in an expanding
## ring around every ocean cell.
##
## Same formula and the same inputs, so the result is bit-identical -- pinned
## by test_temperature_at_elevation_is_exactly_temperature_at_global.
func temperature_at_elevation(global_y: int, cell_elevation: float) -> float:
	var latitude := _geo_coordinates.latitude_for_tile(global_y, WORLD_HEIGHT_TILES)
	var latitude_0to1 := absf(latitude) / 90.0
	var height_above_sea_level := maxf(0.0, cell_elevation - EARTH_SEA_LEVEL)
	return _climate_model.temperature_at(latitude_0to1, height_above_sea_level)


## Real latitude/elevation-derived temperature for any global tile coordinate,
## normalized to [0.0, 1.0]. The thin wrapper for callers that do NOT already
## have the tile's elevation (EarthChunkManager.step_worms, and the tests);
## signature and result unchanged.
func temperature_at_global(global_x: int, global_y: int) -> float:
	return temperature_at_elevation(global_y, elevation_at_global(global_x, global_y))


## Public per-tile biome query -- the same single-source-of-truth function
## generate_chunk() slices, exposed so callers (e.g. cross-chunk border
## blending in TerrainRenderer.paint) can see a neighbor cell's biome even
## when its chunk isn't generated/loaded.
func biome_at_global(global_x: int, global_y: int) -> String:
	var cell_elevation := elevation_at_global(global_x, global_y)
	return _biome_at_global(
		global_x,
		global_y,
		cell_elevation,
		temperature_at_elevation(global_y, cell_elevation),
		moisture_at_global(global_x, global_y)
	)


func _biome_at_global(
	global_x: int, global_y: int, cell_elevation: float, temperature: float, moisture: float
) -> String:
	return _biome_classifier.classify(
		cell_elevation, temperature, moisture, EARTH_SEA_LEVEL, EARTH_MOUNTAIN_LEVEL
	)
