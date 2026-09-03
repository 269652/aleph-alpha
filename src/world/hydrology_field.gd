extends RefCounted

## The tile read of docs/concept/hydrology.md ("Layer 5: what a chunk
## actually gets", plus "Valleys are read back into the elevation"): given
## a game tile's global coordinate and its own macro elevation, answers
## whether it is in a lake or on a river channel, how deep the water is in
## real metres, and how much the valley there suppresses procedural fine
## detail and lowers the ground. Reads only the baked HydrologyData (the
## tile's asset cell and its 3x3 neighbourhood), so a chunk stays a pure
## slice of one global function -- no chunk-relative state, no seams.
##
## Phase 1 stand-ins (hydrology.md "Implementation order"): every lake
## candidate is filled to its spill (the live lake balance is phase 3),
## discharge is the bake's latitude-rain accumulation, and channels are
## straight cell-centre polylines (the seeded meander is a follow-up).

const HydrologyData = preload("res://src/world/hydrology_data.gd")
const DrainageNetwork = preload("res://src/world/drainage_network.gd")
const TerrainRelief = preload("res://src/world/terrain_relief.gd")

## Real metres per unit of the normalized elevation encoding
## (EarthElevationSource: 0.0 = -8000m, 1.0 = +6400m).
const METERS_PER_ELEVATION_UNIT := TerrainRelief.ELEVATION_MAX_M - TerrainRelief.ELEVATION_MIN_M

## Discharge (stand-in units: asset cells of full rain accumulated) at
## which a channel first counts as a river. Below it the channel is a dry
## bed, not absent. Thirty cells of full rain is a ~3,000 km^2 catchment in
## the wettest belt at the asset's ~10km/cell -- a real small river, and
## the smallest thing a 1km tile can show as a one-tile-wide channel.
const RIVER_MIN_DISCHARGE := 30.0

## Hydraulic geometry (Leopold & Maddock 1953: w ~ Q^0.5, d ~ Q^0.4) with
## the width exaggerated toward legibility exactly as stone.md does for
## pebbles -- a real 300m river is narrower than one 1km tile and would be
## invisible -- so widths are stretched at the small end, monotone, and
## capped. Depth is NOT exaggerated: it feeds water_movement_model.gd's
## wade/swim line in real metres.
const MIN_LEGIBLE_WIDTH_TILES := 1.0
const WIDTH_TILES_PER_DOUBLING := 0.5
const MAX_WIDTH_TILES := 12.0
## d = DEPTH_COEFFICIENT_M * Q^DEPTH_EXPONENT: 1.2m at the threshold (a
## fordable stream, under WaterMovementModel.WADE_DEPTH_METERS), ~5m at
## 1,000, ~30m at 100,000 -- the right order for the largest rivers.
const DEPTH_COEFFICIENT_M := 0.3
const DEPTH_EXPONENT := 0.4

## The valley: fine detail is fully suppressed on the channel, ramps back
## to full over this many tiles beyond the channel's edge, and the ground
## along the channel is lowered by a few metres per doubling of discharge
## so slope, hillshade and passability all see a valley with the river at
## its floor.
const VALLEY_HALF_WIDTH_TILES := 3.0
const VALLEY_CARVE_METERS_PER_DOUBLING := 6.0

const NO_LAKE := -1.0

## Overridable so a synthetic 7x7 bake (tests) can have rivers at all.
var river_min_discharge := RIVER_MIN_DISCHARGE

var _data: HydrologyData
var _world_width: int
var _world_height: int


func _init(data: HydrologyData, world_width_tiles: int, world_height_tiles: int) -> void:
	_data = data
	_world_width = world_width_tiles
	_world_height = world_height_tiles


## --- coordinate mapping (the same equirectangular relationship
## EarthElevationSource.elevation_at uses, so the asset cell a tile reads
## here is the one its elevation was sampled from) ---


## Continuous asset-pixel coordinate of a tile's top-left corner.
func pixel_of_tile(global_x: int, global_y: int) -> Vector2:
	return Vector2(
		float(global_x) / float(_world_width) * float(_data.width),
		float(global_y) / float(_world_height - 1) * float(_data.height)
	)


## Continuous tile coordinate of an asset cell's centre.
func tile_of_pixel_center(pixel_x: int, pixel_y: int) -> Vector2:
	return Vector2(
		(float(pixel_x) + 0.5) / float(_data.width) * float(_world_width),
		(float(pixel_y) + 0.5) / float(_data.height) * float(_world_height - 1)
	)


## Flat index of asset cell (pixel_x, pixel_y): wraps east-west, clamps
## at the poles, exactly as DrainageNetwork routed it.
func cell_index_at(pixel_x: int, pixel_y: int) -> int:
	return clampi(pixel_y, 0, _data.height - 1) * _data.width + posmod(pixel_x, _data.width)


func cell_of_tile(global_x: int, global_y: int) -> int:
	var pixel := pixel_of_tile(global_x, global_y)
	return cell_index_at(floori(pixel.x), floori(pixel.y))


## --- lakes ---


## Water-surface elevation (normalized) over this tile if its cell is in
## a lake candidate, else NO_LAKE. Phase 1: every candidate sits at its
## spill.
func lake_surface_at_global(global_x: int, global_y: int) -> float:
	var depression := _data.depression_at(cell_of_tile(global_x, global_y))
	if depression == DrainageNetwork.NO_DEPRESSION:
		return NO_LAKE
	return _data.depressions[depression]["spill_elevation"]


## --- hydraulic geometry ---


func width_tiles_for_discharge(discharge: float) -> float:
	if discharge < river_min_discharge:
		return 0.0
	var doublings := log(discharge / river_min_discharge) / log(2.0)
	return clampf(
		MIN_LEGIBLE_WIDTH_TILES + WIDTH_TILES_PER_DOUBLING * doublings,
		MIN_LEGIBLE_WIDTH_TILES, MAX_WIDTH_TILES
	)


func depth_meters_for_discharge(discharge: float) -> float:
	return DEPTH_COEFFICIENT_M * pow(discharge, DEPTH_EXPONENT)


func _carve_for_discharge(discharge: float) -> float:
	var doublings := log(discharge / river_min_discharge) / log(2.0)
	return VALLEY_CARVE_METERS_PER_DOUBLING * maxf(doublings, 0.0) / METERS_PER_ELEVATION_UNIT


## --- the read ---


## Everything the chunk generator needs for one tile, in one pass:
##   kind               "lake" | "river" | ""
##   depth_m            real metres of water over the tile (0 when dry)
##   discharge          the channel's discharge when kind is "river"
##   fine_detail_scale  0..1 multiplier on EarthChunkGenerator's noise term
##   carve              normalized elevation to subtract along the channel
func probe(global_x: int, global_y: int, macro_elevation: float) -> Dictionary:
	var lake_surface := lake_surface_at_global(global_x, global_y)
	if lake_surface != NO_LAKE and macro_elevation < lake_surface:
		return {
			"kind": "lake",
			"depth_m": (lake_surface - macro_elevation) * METERS_PER_ELEVATION_UNIT,
			"discharge": 0.0,
			"fine_detail_scale": 0.0,
			"carve": 0.0,
		}

	var channel := _nearest_channel(global_x, global_y)
	if channel.is_empty():
		return {"kind": "", "depth_m": 0.0, "discharge": 0.0, "fine_detail_scale": 1.0, "carve": 0.0}

	var discharge: float = channel["discharge"]
	var half_width: float = channel["width_tiles"] / 2.0
	var distance: float = channel["distance_tiles"]
	var full_carve := _carve_for_discharge(discharge)
	if distance <= half_width:
		return {
			"kind": "river",
			"depth_m": depth_meters_for_discharge(discharge),
			"discharge": discharge,
			"fine_detail_scale": 0.0,
			"carve": full_carve,
		}
	var shoulder := clampf((distance - half_width) / VALLEY_HALF_WIDTH_TILES, 0.0, 1.0)
	return {
		"kind": "",
		"depth_m": 0.0,
		"discharge": 0.0,
		"fine_detail_scale": shoulder,
		"carve": full_carve * (1.0 - shoulder),
	}


## The channel whose centreline is nearest this tile, in valley reach, as
## {discharge, width_tiles, distance_tiles}; empty when none of the 3x3
## surrounding cells carries a river. A tile inside several channels'
## reach takes the one it is closest to, measured in channel-edge terms,
## so a big river's valley wins over a tributary's beside it.
func _nearest_channel(global_x: int, global_y: int) -> Dictionary:
	var tile_center := Vector2(float(global_x) + 0.5, float(global_y) + 0.5)
	var pixel := pixel_of_tile(global_x, global_y)
	var pixel_x := floori(pixel.x)
	var pixel_y := floori(pixel.y)
	var best := {}
	var best_reach := INF
	for dy in range(-1, 2):
		var y := pixel_y + dy
		if y < 0 or y >= _data.height:
			continue
		for dx in range(-1, 2):
			var cell := cell_index_at(pixel_x + dx, y)
			if _data.is_sea(cell):
				continue
			var discharge := _data.discharge_at(cell)
			if discharge < river_min_discharge:
				continue
			var width_tiles := width_tiles_for_discharge(discharge)
			var distance := _distance_to_centerline(tile_center, cell)
			var reach := distance - width_tiles / 2.0
			if reach > VALLEY_HALF_WIDTH_TILES or reach >= best_reach:
				continue
			best_reach = reach
			best = {"discharge": discharge, "width_tiles": width_tiles, "distance_tiles": distance}
	return best


## Distance (tiles) from a point to a channel cell's centreline: the
## polyline mainstem-upstream centre -> this centre -> downstream centre
## (the downstream may be the sea cell: that segment is the river mouth).
## Every polyline point is shifted by whole world widths to sit nearest
## the point, so a channel crossing the date-line seam measures correctly.
func _distance_to_centerline(point: Vector2, cell: int) -> float:
	var center := _nearest_wrapped(tile_of_pixel_center(cell % _data.width, _cell_y(cell)), point)
	var best := INF
	var upstream := _mainstem_upstream(cell)
	if upstream >= 0:
		var upstream_center := _nearest_wrapped(tile_of_pixel_center(upstream % _data.width, _cell_y(upstream)), point)
		best = minf(best, _distance_to_segment(point, upstream_center, center))
	var downstream := _downstream(cell)
	if downstream >= 0:
		var downstream_center := _nearest_wrapped(tile_of_pixel_center(downstream % _data.width, _cell_y(downstream)), point)
		best = minf(best, _distance_to_segment(point, center, downstream_center))
	if best == INF:
		best = point.distance_to(center)
	return best


func _nearest_wrapped(candidate: Vector2, point: Vector2) -> Vector2:
	var world_width := float(_world_width)
	var dx := candidate.x - point.x
	if dx > world_width / 2.0:
		candidate.x -= world_width
	elif dx < -world_width / 2.0:
		candidate.x += world_width
	return candidate


static func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_squared := ab.length_squared()
	if length_squared == 0.0:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)
	return point.distance_to(a + ab * t)


func _cell_y(cell: int) -> int:
	@warning_ignore("integer_division")
	return cell / _data.width


## The cell `cell` drains into, or -1 for a sea cell / off the poles.
func _downstream(cell: int) -> int:
	var direction := _data.flow_direction_at(cell)
	if direction == DrainageNetwork.DIRECTION_SEA:
		return -1
	var y := _cell_y(cell) + DrainageNetwork.NEIGHBOR_DY[direction]
	if y < 0 or y >= _data.height:
		return -1
	return cell_index_at(cell % _data.width + DrainageNetwork.NEIGHBOR_DX[direction], y)


## Of the neighbours draining into `cell`, the one carrying the most
## discharge (the mainstem), or -1 for a headwater.
func _mainstem_upstream(cell: int) -> int:
	var best := -1
	var best_discharge := -1.0
	var x := cell % _data.width
	var y := _cell_y(cell)
	for direction in 8:
		var ny := y + DrainageNetwork.NEIGHBOR_DY[direction]
		if ny < 0 or ny >= _data.height:
			continue
		var neighbor := cell_index_at(x + DrainageNetwork.NEIGHBOR_DX[direction], ny)
		if _data.is_sea(neighbor) or _downstream(neighbor) != cell:
			continue
		var discharge := _data.discharge_at(neighbor)
		if discharge > best_discharge:
			best_discharge = discharge
			best = neighbor
	return best
