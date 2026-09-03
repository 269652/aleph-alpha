extends RefCounted

const EarthElevationSource = preload("res://src/world/earth_elevation_source.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const ClimateModel = preload("res://src/world/climate_model.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const TerrainRelief = preload("res://src/world/terrain_relief.gd")
const Chunk = preload("res://src/world/chunk.gd")
const RiverCatalog = preload("res://src/world/river_catalog.gd")
const RiverDepth = preload("res://src/world/river_depth.gd")
const RiverDischarge = preload("res://src/world/river_discharge.gd")
const OpenChannelFlow = preload("res://src/world/open_channel_flow.gd")
const HydrologyData = preload("res://src/world/hydrology_data.gd")
const HydrologyField = preload("res://src/world/hydrology_field.gd")

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
var _river_catalog := RiverCatalog.new()

var _fine_detail_noise := FastNoiseLite.new()
var _moisture_noise := FastNoiseLite.new()

## --- hydrology (docs/concept/hydrology.md, phase 1) ---

## Whether hydrology channels count as rivers everywhere a curated river
## does not reach -- the connectivity-aware procedural fallback rivers.md's
## "Procedural fallback" section asked for after the noise-contour proxy
## was reverted ("scattered everywhere"). Shipped off until the bake had
## been run over the real asset; switched on 2026-09-03 when the spawn
## moved onto an emergent river (see World.SPAWN_LATITUDE). Lakes and the
## valley carve never depended on it. Pinned by
## test_hydrology_rivers_are_on_by_default.
const HYDROLOGY_RIVERS_ENABLED := true

## Real m^3/s per stand-in discharge unit. One unit is one asset cell
## (~108 km^2 at ~10.4 km/px) receiving a full year of the wettest belt's
## rain: ~2,000 mm/yr at a ~0.4 runoff coefficient is 0.8 m over 1.08e8 m^2,
## 8.6e7 m^3/yr, 2.7 m^3/s. Phase 3 replaces the stand-in with the live
## climate grid and this constant with it.
const STAND_IN_DISCHARGE_M3_S_PER_UNIT := 2.7

## The baked drainage network, read once per process like the elevation
## decode -- null when no bake is shipped, in which case every query below
## behaves exactly as it did before hydrology existed. Pinned by
## test_a_generator_without_a_bake_reports_no_hydrology.
static var _shared_hydrology_data: HydrologyData = null
static var _hydrology_load_attempted := false

## What hydrology_at_global reports without a bake: dry ground, full fine
## detail, nothing carved.
const _NO_HYDROLOGY := {
	"kind": "", "depth_m": 0.0, "discharge": 0.0, "fine_detail_scale": 1.0, "carve": 0.0
}

var _hydrology: HydrologyField = null
var hydrology_rivers_enabled := HYDROLOGY_RIVERS_ENABLED


func _init() -> void:
	_fine_detail_noise.seed = FINE_DETAIL_SEED
	_fine_detail_noise.frequency = FINE_DETAIL_FREQUENCY
	_moisture_noise.seed = MOISTURE_SEED
	_moisture_noise.frequency = MOISTURE_FREQUENCY
	_hydrology = _shared_hydrology_field()


static func _shared_hydrology_field() -> HydrologyField:
	if not _hydrology_load_attempted:
		_hydrology_load_attempted = true
		var data := HydrologyData.new()
		if data.load_from(HydrologyData.DEFAULT_DIRECTORY):
			_shared_hydrology_data = data
	if _shared_hydrology_data == null:
		return null
	return HydrologyField.new(_shared_hydrology_data, WORLD_WIDTH_TILES, WORLD_HEIGHT_TILES)


## Replaces (or, with null, removes) the hydrology this generator reads --
## a test injects a synthetic bake this way; the game never calls it.
func set_hydrology(field: HydrologyField) -> void:
	_hydrology = field


func has_hydrology() -> bool:
	return _hydrology != null


## HydrologyField.probe for a tile (see that doc comment for the keys), or
## _NO_HYDROLOGY without a bake.
func hydrology_at_global(global_x: int, global_y: int) -> Dictionary:
	return _hydrology_for(global_x, global_y, macro_elevation_at_global(global_x, global_y))


func _hydrology_for(global_x: int, global_y: int, macro_elevation: float) -> Dictionary:
	if _hydrology == null:
		return _NO_HYDROLOGY
	return _hydrology.probe(global_x, global_y, macro_elevation)


## A tile under the water surface of a depression the bake found, filled
## to its spill (hydrology.md Layer 5). An overlay flag exactly like
## is_river_at_global: the tile's biome is untouched land.
func is_lake_at_global(global_x: int, global_y: int) -> bool:
	return hydrology_at_global(global_x, global_y)["kind"] == "lake"


## Real metres of lake water over a tile (spill minus the tile's own
## macro elevation), 0.0 off a lake -- Player._resolve_water_state reads it
## beside ocean and river depth.
func lake_depth_meters_at_global(global_x: int, global_y: int) -> float:
	var probe := hydrology_at_global(global_x, global_y)
	if probe["kind"] != "lake":
		return 0.0
	return probe["depth_m"]


func _is_hydrology_river(probe: Dictionary) -> bool:
	return hydrology_rivers_enabled and probe["kind"] == "river"


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
	var is_river := PackedByteArray()
	is_river.resize(chunk_size * chunk_size)
	var is_lake := PackedByteArray()
	is_lake.resize(chunk_size * chunk_size)

	for local_y in chunk_size:
		var global_y := chunk_coord.y * chunk_size + local_y
		for local_x in chunk_size:
			var global_x := chunk_coord.x * chunk_size + local_x
			var index := local_y * chunk_size + local_x

			# One hydrology probe per cell, shared by the elevation blend
			# (valley carve, fine-detail suppression), the lake flag and
			# the river flag -- the same "compute once, hand the value
			# along" rule temperature_at_elevation's doc comment established.
			var macro := macro_elevation_at_global(global_x, global_y)
			var probe := _hydrology_for(global_x, global_y, macro)
			var cell_elevation := _blend_elevation(global_x, global_y, macro, probe)
			elevation[index] = cell_elevation
			moisture[index] = moisture_at_global(global_x, global_y)
			# Reuses the elevation computed one line above rather than making
			# temperature_at_global re-derive it -- see
			# temperature_at_elevation's own doc comment.
			temperature[index] = temperature_at_elevation(global_y, cell_elevation)
			biome[index] = _biome_at_global(
				global_x, global_y, cell_elevation, temperature[index], moisture[index]
			)
			is_river[index] = 1 if _is_river_for(global_x, global_y, probe) else 0
			is_lake[index] = 1 if probe["kind"] == "lake" else 0

	var chunk := Chunk.new()
	chunk.width = chunk_size
	chunk.height = chunk_size
	chunk.elevation = elevation
	chunk.biome = biome
	chunk.moisture = moisture
	chunk.temperature = temperature
	chunk.is_river = is_river
	chunk.is_lake = is_lake
	return chunk


## Real macro elevation only, with no procedural fine detail -- exposed so
## the blend can be verified independently of the noise layer.
func macro_elevation_at_global(global_x: int, global_y: int) -> float:
	var latitude := _geo_coordinates.latitude_for_tile(global_y, WORLD_HEIGHT_TILES)
	var longitude := _geo_coordinates.longitude_for_tile(global_x, WORLD_WIDTH_TILES)
	return _elevation_source.elevation_at(latitude, longitude)


## Real macro elevation blended with procedural fine detail, for any global
## tile coordinate -- the single source of truth generate_chunk() slices.
## With a hydrology bake, the fine detail is scaled to nothing on a river
## channel or lake bed and the channel is carved a few metres into the
## macro surface (hydrology.md "Valleys are read back into the
## elevation"): the same function, so slope, hillshade and passability all
## see the valley. Without a bake this is exactly macro + fine detail.
func elevation_at_global(global_x: int, global_y: int) -> float:
	var macro := macro_elevation_at_global(global_x, global_y)
	return _blend_elevation(global_x, global_y, macro, _hydrology_for(global_x, global_y, macro))


## The fine detail is texture, never geography (see FINE_DETAIL_AMPLITUDE
## and slope_at_global's doc comment), so it may not move a tile across
## sea level: land stays land, sea stays sea, and the coastline is the
## macro data's own contour. Before this clamp every coastal plain within
## +-432 m of sea level was a speckle of ocean-biome tiles (first
## playtest: "dozens of small ponds to the sides of rivers"). The carve
## is applied after the clamp: a channel may cut into land, never below
## the sea. Pinned by test_fine_detail_never_flips_land_to_sea_or_sea_to_land.
const SEA_LEVEL_MARGIN := 1e-6


func _blend_elevation(global_x: int, global_y: int, macro: float, probe: Dictionary) -> float:
	var fine_detail := _fine_detail_noise.get_noise_2d(global_x, global_y) * FINE_DETAIL_AMPLITUDE
	var scale: float = probe["fine_detail_scale"]
	var carve: float = probe["carve"]
	var textured := macro + fine_detail * scale
	if macro >= EARTH_SEA_LEVEL:
		textured = maxf(textured - carve, EARTH_SEA_LEVEL + SEA_LEVEL_MARGIN)
	else:
		textured = minf(textured, EARTH_SEA_LEVEL - SEA_LEVEL_MARGIN)
	return clampf(textured, 0.0, 1.0)


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
## The shared RiverCatalog this generator resolves courses through -- so a
## caller needing the same course geometry (EarthChunkManager's dam-ponding
## walk) reuses this instance and its cached tile-space polylines rather
## than building a second one. Same reasoning as terrain_relief() below.
func river_catalog() -> RiverCatalog:
	return _river_catalog


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


## True if (global_x, global_y) should render with the water overlay as a
## river: a curated real river's course (RiverCatalog) -- see
## docs/concept/rivers.md. Deliberately NEVER changes biome_at_global's own
## result (a river never becomes an eighth BiomeClassifier.KNOWN_BIOMES
## entry); this is consulted by EarthChunkManager's water overlay and by
## worldgen decoration placement (trees, grass) alike, layered over/
## excluded from whatever land biome is already there.
##
## Curated-only (see docs/concept/rivers.md's "Procedural fallback
## reverted" section): a noise-contour procedural fallback (ProceduralRiver)
## was live-wired here originally, but real playtesting reported it as
## "scattered everywhere" -- disconnected patches with no relationship to
## real geography, not "one coherent stream." Measured: ~6% of tiles in a
## curated-river-free region tested true via the procedural proxy alone.
## The module itself (procedural_river.gd) stays real and tested, just no
## longer consulted here -- pinned by
## test_procedural_fallback_is_not_live_wired_far_from_any_curated_river.
##
## With HYDROLOGY_RIVERS_ENABLED (see that constant), a channel of the
## baked drainage network (docs/concept/hydrology.md) is a river too --
## the connectivity-aware fallback that section asked for -- but a curated
## river is authoritative wherever it reaches.
func is_river_at_global(global_x: int, global_y: int) -> bool:
	if _river_catalog.is_river_tile(global_x, global_y, WORLD_WIDTH_TILES, WORLD_HEIGHT_TILES):
		return true
	return _is_hydrology_river(hydrology_at_global(global_x, global_y))


func _is_river_for(global_x: int, global_y: int, probe: Dictionary) -> bool:
	if _river_catalog.is_river_tile(global_x, global_y, WORLD_WIDTH_TILES, WORLD_HEIGHT_TILES):
		return true
	return _is_hydrology_river(probe)


## RiverCatalog.nearest_river_at, extended: the curated answer wherever a
## curated river is within its bank apron, otherwise (with hydrology
## rivers enabled) the nearest baked channel in the same dictionary shape
## with an empty name, so EarthChunkManager._paint_river_flow_overlay draws
## both through one code path. Far from everything, the curated answer
## (a large distance) is returned as before.
func nearest_river_at(global_x: int, global_y: int) -> Dictionary:
	var curated := _river_catalog.nearest_river_at(
		global_x, global_y, WORLD_WIDTH_TILES, WORLD_HEIGHT_TILES
	)
	# Every answer carries its own half-width: the catalog's uniform one
	# for a curated river, the discharge-derived one for a baked channel
	# (a confluence widens where discharges add up).
	curated["half_width_tiles"] = RiverCatalog.RIVER_HALF_WIDTH_TILES
	var apron := RiverCatalog.RIVER_HALF_WIDTH_TILES + RiverCatalog.RIVER_BANK_APRON_TILES
	if curated.distance_tiles <= apron or _hydrology == null or not hydrology_rivers_enabled:
		return curated
	var channel := _hydrology.nearest_channel_geometry(global_x, global_y)
	if channel.is_empty() or channel["distance_tiles"] >= curated.distance_tiles:
		return curated
	return {
		"name": "",
		"distance_tiles": channel["distance_tiles"],
		"course_fraction": 0.0,
		"course_bearing_deg": channel["course_bearing_deg"],
		"signed_across_tiles": channel["signed_across_tiles"],
		"half_width_tiles": channel["half_width_tiles"],
	}


## Whether a tile lies on a river or on the bank apron the flow overlay
## paints just past its waterline -- the gate for a boulder to bend the
## water. A rock sitting ON the bank (first playtest: "wrap shorelines
## around edge boulders") is exactly the case is_river_at_global misses:
## the waterline has to part around it, so it must be an obstacle too.
func is_within_river_apron(global_x: int, global_y: int) -> bool:
	var nearest := nearest_river_at(global_x, global_y)
	var half_width: float = nearest.get("half_width_tiles", RiverCatalog.RIVER_HALF_WIDTH_TILES)
	return nearest.distance_tiles <= half_width + RiverCatalog.RIVER_BANK_APRON_TILES


## Real meters of river depth at (global_x, global_y) -- the depth SOLVED
## from the river's real discharge (see river_hydraulics_at_global), not an
## authored taper. Consulted by Player._resolve_water_state (wading/
## swimming/submersion-tint/water-ripples) exactly the way ocean depth
## already is -- a river never changes biome_at_global's own result, so
## nothing else would otherwise notice it.
func river_depth_meters_at_global(global_x: int, global_y: int) -> float:
	return river_hydraulics_at_global(global_x, global_y).depth_m


## The full real hydraulic state of a river cell -- see
## docs/concept/rivers.md's "Real hydraulics" section and
## open_channel_flow.gd for the physics:
##   {discharge_m3_s, width_m, depth_m, velocity_m_s, bed_pressure_pa,
##    slope, river_name, course_fraction}
## All zero (and river_name "") away from any curated river.
##
## Depth, velocity and discharge are ONE self-consistent answer, not three
## independent numbers: continuity (Q = width * depth * velocity) binds
## them, and the normal-depth solve is what satisfies it. Depth used to be
## an authored linear taper from a centreline maximum, with velocity
## separately faked from slope alone and no pressure at all -- three
## inventions that could not have agreed with each other even in principle.
##
## Feasible per-tile on a chunk-streamed world only because every input is
## local or curated: discharge is real published gauge data (never
## integrated from an upstream catchment that is not loaded), slope comes
## from the elevation gradient already sampled here, and the normal-depth
## solve is closed-form rather than iterated.
##
## A hydrology channel (HYDROLOGY_RIVERS_ENABLED, no curated river in
## reach) goes through the same solve with its stand-in discharge scaled to
## m^3/s (STAND_IN_DISCHARGE_M3_S_PER_UNIT) and a width derived from that
## discharge (RiverDischarge.derived_width_m), river_name "".
func river_hydraulics_at_global(global_x: int, global_y: int) -> Dictionary:
	var nearest := _river_catalog.nearest_river_at(
		global_x, global_y, WORLD_WIDTH_TILES, WORLD_HEIGHT_TILES
	)
	var river_name := ""
	var course_fraction := 0.0
	var discharge := 0.0
	var width := 0.0
	if nearest.distance_tiles <= RiverCatalog.RIVER_HALF_WIDTH_TILES:
		river_name = nearest.name
		course_fraction = nearest.course_fraction
		discharge = RiverDischarge.discharge_at(river_name, course_fraction)
		width = RiverDischarge.channel_width_m(river_name, course_fraction)
	else:
		var probe := hydrology_at_global(global_x, global_y)
		if not _is_hydrology_river(probe):
			return _no_flow()
		discharge = probe["discharge"] * STAND_IN_DISCHARGE_M3_S_PER_UNIT
		width = RiverDischarge.derived_width_m(discharge)
	if discharge <= 0.0 or width <= 0.0:
		return _no_flow()

	# Manning's S is the energy-grade slope as a dimensionless rise/run, so
	# the gradient's ANGLE has to become a tangent -- feeding degrees
	# straight in would be a unit error of a factor of ~57.
	var slope := tan(deg_to_rad(slope_at_global(global_x, global_y)))
	slope = maxf(slope, MIN_HYDRAULIC_SLOPE)

	# Roughness needs a hydraulic radius and the radius needs a depth, so
	# take one cheap first pass at depth with the lowland roughness, then
	# re-solve once with the roughness that depth implies. Two passes, not a
	# convergence loop: the exponents are small enough that a second pass
	# moves the answer by a few percent and a third by far less.
	var first_depth := OpenChannelFlow.normal_depth(
		discharge, width, slope, OpenChannelFlow.LOWLAND_MANNING_N
	)
	var radius := OpenChannelFlow.hydraulic_radius(first_depth, width)
	var roughness := OpenChannelFlow.manning_n(slope, radius)
	var depth := OpenChannelFlow.normal_depth(discharge, width, slope, roughness)

	# Velocity from continuity rather than from Manning again, so
	# Q = width * depth * velocity holds EXACTLY instead of only to within
	# the wide-channel approximation the depth solve makes.
	var velocity := discharge / (width * depth) if depth > 0.0 else 0.0

	return {
		"discharge_m3_s": discharge,
		"width_m": width,
		"depth_m": depth,
		"velocity_m_s": velocity,
		"bed_pressure_pa": OpenChannelFlow.hydrostatic_pressure_pa(depth),
		"slope": slope,
		"river_name": river_name,
		"course_fraction": course_fraction,
	}


## A real river is never perfectly level -- and Manning's velocity goes to
## zero at zero slope, which would make a flat reach infinitely deep via
## continuity. This floor is the gentlest slope the model will admit,
## roughly the real gradient of a very sluggish lowland river (1 cm per km).
const MIN_HYDRAULIC_SLOPE := 0.00001


func _no_flow() -> Dictionary:
	return {
		"discharge_m3_s": 0.0, "width_m": 0.0, "depth_m": 0.0, "velocity_m_s": 0.0,
		"bed_pressure_pa": 0.0, "slope": 0.0, "river_name": "", "course_fraction": 0.0,
	}


func _biome_at_global(
	global_x: int, global_y: int, cell_elevation: float, temperature: float, moisture: float
) -> String:
	var slope_deg := _slope_override_deg_for(global_x, global_y, cell_elevation)
	return _biome_classifier.classify(
		cell_elevation, temperature, moisture, EARTH_SEA_LEVEL, EARTH_MOUNTAIN_LEVEL, slope_deg
	)


## Slope reading to hand BiomeClassifier.classify() for a cell already known
## to be at cell_elevation -- real TerrainRelief.slope_at (see
## slope_at_global) costs four FRESH elevation samples, so this only pays
## that cost for a cell whose biome ISN'T already decided by elevation
## alone. An ocean cell or an already-elevation-mountain cell can't change
## outcome on a slope reading either way (classify() checks ocean first,
## unconditionally, and elevation>=mountain_level before ever consulting
## slope), so sampling slope there would be pure waste -- paid on EVERY
## cell of EVERY generated chunk, since terrain is regenerated from scratch
## on every chunk load rather than cached. Unconditional sampling would
## double generation's own elevation-sampling cost again, the same
## regression temperature_at_elevation's own doc comment already fixed
## once for temperature. Returns BiomeClassifier.SLOPE_NOT_PROVIDED for a
## cell slope can't affect; pinned by
## test_slope_override_is_not_provided_for_an_ocean_cell and
## test_slope_override_is_not_provided_for_an_already_elevation_mountain_cell.
func _slope_override_deg_for(global_x: int, global_y: int, cell_elevation: float) -> float:
	if cell_elevation < EARTH_SEA_LEVEL or cell_elevation >= EARTH_MOUNTAIN_LEVEL:
		return BiomeClassifier.SLOPE_NOT_PROVIDED
	return slope_at_global(global_x, global_y)
