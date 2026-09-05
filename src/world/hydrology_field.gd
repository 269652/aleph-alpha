extends RefCounted

## The tile read of docs/concept/hydrology.md ("Layer 5: what a chunk
## actually gets", plus "Valleys are read back into the elevation"): given
## a game tile's global coordinate and its own macro elevation, answers
## whether it is sea, lake or river, how deep the water is in real metres,
## how wide the channel is right there, how far a river's current reaches
## into the still water it empties into, and how much the valley
## suppresses procedural fine detail and lowers the ground. Reads only the
## baked HydrologyData (the tile's asset cell and the cells around it), so
## a chunk stays a pure slice of one global function -- no chunk-relative
## state, no seams.
##
## Channel geometry (first playtest, 2026-09-03: "make curves smoother",
## "springs -- rivers just start out of nothing", "two rivers flowing into
## each other should produce the combined volume"):
##   - each channel cell owns one quadratic Bezier from the midpoint toward
##     its mainstem upstream, through its own centre, to the midpoint toward
##     its downstream (or to the downstream's centre when this cell is a
##     tributary or a mouth); adjacent cells share endpoints and tangents;
##   - width is hydraulic geometry of the cell's own discharge, interpolated
##     along the curve, so a confluence widens where the discharges add up;
##   - a headwater cell's curve starts at its SOURCE at spring width.
##
## Shorelines (third playtest: "circle-ish, derived from the contour path
## of the basin, not a folded-up snake"): the sea's and every lake's
## footprint is the bake's own cell mask, and the waterline is the
## half-coverage contour of that mask under a smooth kernel about a cell
## and a half wide. A binary mask blurred that way has rounded, blob-like
## level sets (the metaball construction), and the same field decides
## both what is drawn and what the player swims in. The bilinear elevation
## contour this replaced was, on 8-bit ~10 km data, a staircase of
## pixel-edge hyperbolas.
##
## Phase 1 stand-ins: every lake candidate is filled to its spill (the live
## lake balance is phase 3) and discharge is the bake's latitude-rain
## accumulation.

const HydrologyData = preload("res://src/world/hydrology_data.gd")
const DrainageNetwork = preload("res://src/world/drainage_network.gd")
const TerrainRelief = preload("res://src/world/terrain_relief.gd")
const RiverCatalog = preload("res://src/world/river_catalog.gd")

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
## capped: one tile at the threshold, one more per doubling of discharge,
## twelve at most. Depth is NOT exaggerated: it feeds the wade/swim line in
## real metres.
const MIN_LEGIBLE_WIDTH_TILES := 1.0
const WIDTH_TILES_PER_DOUBLING := 1.0
const MAX_WIDTH_TILES := 12.0
## d = DEPTH_COEFFICIENT_M * Q^DEPTH_EXPONENT: 1.2m at the threshold (a
## fordable stream, under WaterMovementModel.WADE_DEPTH_METERS), ~5m at
## 1,000, ~30m at 100,000 -- the right order for the largest rivers.
const DEPTH_COEFFICIENT_M := 0.3
const DEPTH_EXPONENT := 0.4

## Half-width of a river at its source: the spring. Narrower than the
## thinnest river (MIN_LEGIBLE_WIDTH_TILES / 2), so a headwater tapers IN
## to its first cell rather than bulging at the start.
const SPRING_HALF_WIDTH_TILES := 0.3

## How many straight pieces each cell's Bezier is sampled into for the
## distance query. The across field the strokes are contours of inherits
## a kink at every joint, and six pieces per ten-tile cell drew visible
## zig-zags along every bend (third playtest); twenty-four puts a joint
## well under every tile, and the curve is cached per cell so the cost
## is paid once.
const CURVE_SEGMENTS := 24

## The valley: fine detail is fully suppressed on the channel, ramps back
## to full over this many tiles beyond the channel's edge, and the ground
## along the channel is lowered by a few metres per doubling of discharge
## so slope, hillshade and passability all see a valley with the river at
## its floor.
## MUST stay >= RiverCatalog.RIVER_BANK_APRON_TILES (0.75) +
## RiverFlowShader.SHORE_BLEED_TILES (3.0) -- the painter's own total
## paint reach beyond a channel's bank. When this constant was smaller
## than that sum, _channel_hits (below) reported "no channel here" for a
## band of tiles the painter was STILL actively painting; EarthChunkGenerator.
## nearest_river_at then fell back to whatever curated river exists
## ANYWHERE ON THE PLANET (in one real case, 900+ tiles away, with a
## wildly different width and bearing), and that garbage texel bilinearly
## blended against its real neighbour -- the torn, chunky zigzag reported
## "only around bends and where the water is deeper at the edge" (a huge
## |across| clamps the depth shading to its darkest band, and the reach
## boundary is least stable exactly where a bend's curve departs most
## from a straight-line extrapolation). Pinned by
## test_the_geometry_reach_covers_the_painters_full_bleed.
const VALLEY_HALF_WIDTH_TILES := 4.0

## How far past the last painted cell the flow map's FILTER still reads:
## one texel for the bilinear sampler, two for the cubic reconstruction
## (RiverFlowShader.texture_bicubic). A texel in that band that came from
## the far curated fallback carries an arbitrary SIGN, and interpolating
## between a real +6 and a fallback -16 crosses zero INSIDE the painted
## cell beside it -- the shader drew a hairline of water along the whole
## reach boundary (found live at the Loire: thin phantom channels running
## parallel to the river several tiles out, on the world, never on the
## minimap). Pinned by
## test_the_geometry_reach_covers_the_map_filters_neighbours_of_the_bleed.
const MAP_FILTER_SUPPORT_TILES := 2.0

## The channel-geometry query's own reach past a bank: the valley, plus
## the filter support above, so every texel the map filter can blend into
## a painted cell still describes the channel's own side. The valley
## shoulder (probe) keeps ramping over VALLEY_HALF_WIDTH_TILES alone.
const GEOMETRY_REACH_TILES := VALLEY_HALF_WIDTH_TILES + MAP_FILTER_SUPPORT_TILES
const VALLEY_CARVE_METERS_PER_DOUBLING := 6.0

## The shoreline kernel: radius in asset cells of the smooth bump each
## water cell contributes to the coverage field. A cell and a half rounds
## a square footprint's corners without swallowing a one-cell gap between
## two basins.
const COVERAGE_KERNEL_RADIUS_CELLS := 1.6
## How much coverage one unit of the flow overlay's across spans on either
## side of the half-coverage waterline: across = 1 + (0.5 - coverage) /
## COVERAGE_BAND, so deep water (coverage 0.85+) reads 0 and open ground
## (0.15-) reads the dry ceiling. Pinned by
## test_the_waterline_is_the_half_coverage_contour.
const COVERAGE_BAND := 0.35
## across value handed back where no water is anywhere near: dry.
const LAKE_ACROSS_DRY := 2.0
## A tile inside a lake's footprint whose own macro elevation sits at or
## above the spill still swims: real lakes are never shallower than this
## at the shore-side of their footprint.
const LAKE_MIN_DEPTH_M := 1.0

## A river's current keeps running into the still water it empties into,
## fading to nothing over this many tiles from the mouth, at this speed at
## the mouth itself (the slowest reach the Manning solve admits) -- third
## playtest: "inflow doesn't reach into the sea as currents".
const PLUME_TILES := 20.0
const PLUME_SPEED_M_S := 0.4

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


## Continuous asset-pixel coordinate of a tile's centre.
func pixel_of_tile_center(global_x: int, global_y: int) -> Vector2:
	return Vector2(
		(float(global_x) + 0.5) / float(_world_width) * float(_data.width),
		(float(global_y) + 0.5) / float(_world_height - 1) * float(_data.height)
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


## --- shorelines: sea and lake coverage ---


## The smoothed water masks at a tile, as {sea, lake, surface}: sea and
## lake are 0..1 coverages of the bake's ocean cells and lake cells under
## the shoreline kernel (they sum to at most 1; the rest is land), surface
## the highest spill among the lake cells that contributed (NO_LAKE if
## none). A below-sea-level pocket the bake flagged inland_sea counts as a
## lake, never as sea.
func water_coverage(global_x: int, global_y: int) -> Dictionary:
	var pixel := pixel_of_tile_center(global_x, global_y)
	var cell_x := floori(pixel.x)
	var cell_y := floori(pixel.y)
	var total := 0.0
	var sea := 0.0
	var lake := 0.0
	var surface := NO_LAKE
	for dy in range(-2, 3):
		var y := cell_y + dy
		if y < 0 or y >= _data.height:
			continue
		for dx in range(-2, 3):
			var center := Vector2(float(cell_x + dx) + 0.5, float(y) + 0.5)
			var distance := pixel.distance_to(center) / COVERAGE_KERNEL_RADIUS_CELLS
			if distance >= 1.0:
				continue
			var falloff := 1.0 - distance * distance
			var weight := falloff * falloff
			total += weight
			var cell := cell_index_at(cell_x + dx, y)
			var depression := _data.depression_at(cell)
			if depression != DrainageNetwork.NO_DEPRESSION:
				lake += weight
				surface = maxf(surface, _data.depressions[depression]["spill_elevation"])
			elif _data.is_sea(cell):
				sea += weight
	if total <= 0.0:
		return {"sea": 0.0, "lake": 0.0, "surface": NO_LAKE}
	return {"sea": sea / total, "lake": lake / total, "surface": surface}


## The flow overlay's across value for a shoreline: below 1 is water, 1 is
## the waterline (half coverage), above is dry, capped at LAKE_ACROSS_DRY.
static func shore_across(coverage: float) -> float:
	return clampf(1.0 + (0.5 - coverage) / COVERAGE_BAND, 0.0, LAKE_ACROSS_DRY)


## Kept for callers that still think in elevation: the spill (or NO_LAKE)
## that could cover this tile.
func lake_surface_at_global(global_x: int, global_y: int) -> float:
	return water_coverage(global_x, global_y)["surface"]


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


## Everything the chunk generator and the water painter need for one tile:
##   kind               "lake" | "river" | ""
##   sea                true where sea coverage passes half: the tile IS sea
##   depth_m            real metres of water over the tile (0 when dry; sea
##                      depth comes from the bathymetry, not from here)
##   discharge          the channel's discharge when kind is "river"
##   half_width_tiles   the channel's half-width at this tile's nearest point
##   lake_across        the still-water shoreline field (sea or lake,
##                      whichever is nearer; LAKE_ACROSS_DRY when none near)
##   plume_factor       0..1 strength of a river mouth's current here
##   plume_bearing_deg  the direction that current runs
##   fine_detail_scale  0..1 multiplier on EarthChunkGenerator's noise term
##   carve              normalized elevation to subtract along the channel
## A lake outranks a river (a channel entering a lake disappears under
## it); a river outranks the sea (a mouth keeps flowing into the sea).
func probe(global_x: int, global_y: int, macro_elevation: float) -> Dictionary:
	var coverage := water_coverage(global_x, global_y)
	var lake_coverage: float = coverage["lake"]
	var sea_coverage: float = coverage["sea"]
	var still_across := minf(shore_across(lake_coverage), shore_across(sea_coverage))
	var is_sea := sea_coverage > 0.5

	if lake_coverage > 0.5:
		var surface: float = coverage["surface"]
		var plume := mouth_plume(global_x, global_y)
		return {
			"kind": "lake",
			"sea": false,
			"depth_m": maxf((surface - macro_elevation) * METERS_PER_ELEVATION_UNIT, LAKE_MIN_DEPTH_M),
			"discharge": 0.0,
			"half_width_tiles": 0.0,
			"lake_across": still_across,
			"plume_factor": plume["factor"],
			"plume_bearing_deg": plume["bearing_deg"],
			"fine_detail_scale": 0.0,
			"carve": 0.0,
		}

	var channel := _nearest_channel(global_x, global_y)
	if channel.is_empty():
		var plume := mouth_plume(global_x, global_y) if is_sea else {"factor": 0.0, "bearing_deg": 0.0}
		return {
			"kind": "", "sea": is_sea, "depth_m": 0.0, "discharge": 0.0, "half_width_tiles": 0.0,
			"lake_across": still_across, "plume_factor": plume["factor"],
			"plume_bearing_deg": plume["bearing_deg"], "fine_detail_scale": 1.0, "carve": 0.0,
		}

	var discharge: float = channel["discharge"]
	var half_width: float = channel["half_width_tiles"]
	var distance: float = channel["distance_tiles"]
	var full_carve := _carve_for_discharge(discharge)
	if distance <= half_width:
		return {
			"kind": "river",
			"sea": is_sea,
			"depth_m": depth_meters_for_discharge(discharge),
			"discharge": discharge,
			"half_width_tiles": half_width,
			"lake_across": still_across,
			"plume_factor": 0.0,
			"plume_bearing_deg": 0.0,
			"fine_detail_scale": 0.0,
			"carve": full_carve,
		}
	var shoulder := clampf((distance - half_width) / VALLEY_HALF_WIDTH_TILES, 0.0, 1.0)
	var plume := mouth_plume(global_x, global_y) if is_sea else {"factor": 0.0, "bearing_deg": 0.0}
	return {
		"kind": "",
		"sea": is_sea,
		"depth_m": 0.0,
		"discharge": 0.0,
		"half_width_tiles": half_width,
		"lake_across": still_across,
		"plume_factor": plume["factor"],
		"plume_bearing_deg": plume["bearing_deg"],
		"fine_detail_scale": shoulder if not is_sea else 0.0,
		"carve": full_carve * (1.0 - shoulder) if not is_sea else 0.0,
	}


## How strongly, and in which direction, a river mouth's current still
## runs at this tile: {factor 0..1, bearing_deg}. The nearest mouth within
## PLUME_TILES of the tile wins; a mouth is where a channel cell drains
## into a sea cell or a lake cell, at that cell's centre (the end of the
## channel's own curve), running the way the last piece of channel ran.
func mouth_plume(global_x: int, global_y: int) -> Dictionary:
	var tile_center := Vector2(float(global_x) + 0.5, float(global_y) + 0.5)
	var pixel := pixel_of_tile(global_x, global_y)
	var cell_x := floori(pixel.x)
	var cell_y := floori(pixel.y)
	var best_factor := 0.0
	var best_bearing := 0.0
	for dy in range(-2, 3):
		var y := cell_y + dy
		if y < 0 or y >= _data.height:
			continue
		for dx in range(-2, 3):
			var cell := cell_index_at(cell_x + dx, y)
			if _data.is_sea(cell) or _data.discharge_at(cell) < river_min_discharge:
				continue
			var downstream := _downstream(cell)
			if downstream < 0:
				continue
			var into_still_water := _data.is_sea(downstream) or _data.depression_at(downstream) != DrainageNetwork.NO_DEPRESSION
			if not into_still_water:
				continue
			var mouth := _nearest_wrapped(_center_of(downstream), tile_center)
			var from := _nearest_wrapped(_center_of(cell), tile_center)
			var factor := clampf(1.0 - tile_center.distance_to(mouth) / PLUME_TILES, 0.0, 1.0)
			if factor <= best_factor:
				continue
			best_factor = factor
			best_bearing = RiverCatalog.bearing_degrees(mouth - from)
	return {"factor": best_factor, "bearing_deg": best_bearing}


## The nearest channel's geometry in exactly the shape
## RiverCatalog.nearest_river_at answers with (plus the local half-width),
## so the river flow overlay draws a hydrology channel through the same
## code path as a curated river: {distance_tiles, signed_across_tiles,
## course_bearing_deg, discharge, half_width_tiles}, or empty when no
## channel is within valley reach. Sign and bearing follow the catalog's
## conventions (tangent.cross(point - closest); compass bearing of the
## downstream tangent).
## How far past a channel's bank its field still counts toward the blend
## (see nearest_channel_geometry): two tiles fades a tributary's field out
## across the main river's bank instead of cutting it.
const BLEND_BAND_TILES := 2.0

func nearest_channel_geometry(global_x: int, global_y: int) -> Dictionary:
	var hits := _channel_hits(global_x, global_y)
	if hits.is_empty():
		return {}
	var point := Vector2(float(global_x) + 0.5, float(global_y) + 0.5)
	# WHERE CHANNELS OVERLAP, BLEND -- never switch. Each hit's normalized
	# across (the MAGNITUDE is the true distance to its curve, the cross
	# product only picks the side -- the cross product alone undershoots
	# near every joint, the old one-tile sawtooth) is averaged with weight
	# membership x discharge^2: membership is 1 inside the channel and
	# fades to 0 BLEND_BAND_TILES past its bank, and the square makes the
	# main river dominate a tributary wherever both reach. Picking one
	# winner per tile stitched the field from two channels and left a
	# jump along the seam (a tributary's centreline 0 beside the main's
	# 0.7); the shader interpolated across the jump and drew the crowded
	# contour fans reported as arcs (fourth playtest, read straight off
	# the across field dump).
	var weight_sum := 0.0
	var across_sum := 0.0
	var half_sum := 0.0
	var tangent_sum := Vector2.ZERO
	# "Nearest" is by BANK reach (distance minus half-width), never raw
	# distance: a tile a tenth of a tile past the main river's bank is the
	# main's apron, not the tributary's, even when the tributary's
	# centreline happens to be closer (found as a dry hole at a junction).
	var nearest: Dictionary = hits[0]
	var nearest_reach := INF
	var dominant: Dictionary = hits[0]
	for hit in hits:
		var reach: float = hit["distance_tiles"] - hit["half_width_tiles"]
		if reach < nearest_reach:
			nearest_reach = reach
			nearest = hit
		if hit["discharge"] > dominant["discharge"]:
			dominant = hit
		var across: float = hit["distance_tiles"] / hit["half_width_tiles"]
		# Only a channel that CONTAINS the tile contributes, weighted by
		# discharge^2 and by how far the tile is from that channel's own
		# bank: at the main river's bank the main weighs almost nothing,
		# so a tributary entering there hands over gradually along its
		# mouth instead of being cut off at the main's bank line.
		if across > 1.0:
			continue
		var bank_distance := 1.0 - across
		var weight: float = hit["discharge"] * hit["discharge"] * (bank_distance * bank_distance + 0.01)
		var tangent: Vector2 = hit["tangent"]
		var side := tangent.cross(point - hit["closest"])
		across_sum += weight * (across if side >= 0.0 else -across)
		half_sum += weight * hit["half_width_tiles"]
		tangent_sum += weight * tangent
		weight_sum += weight
	if weight_sum <= 0.0:
		# Only dry apron around: the nearest channel's own frame, as before.
		var tangent: Vector2 = nearest["tangent"]
		var side := tangent.cross(point - nearest["closest"])
		var distance: float = nearest["distance_tiles"]
		return {
			"distance_tiles": distance,
			"signed_across_tiles": distance if side >= 0.0 else -distance,
			"course_bearing_deg": RiverCatalog.bearing_degrees(tangent),
			"discharge": nearest["discharge"],
			"half_width_tiles": nearest["half_width_tiles"],
		}
	var half := half_sum / weight_sum
	var direction: Vector2 = dominant["tangent"]
	if tangent_sum.length() > 1e-6:
		direction = tangent_sum.normalized()
	# DISTANCE AND ACROSS MUST DESCRIBE THE SAME GEOMETRY. This used to
	# report `nearest["distance_tiles"]` beside a blended across, and the
	# two are not the same channel: `nearest` is whichever hit has the
	# smallest BANK REACH, while the blend is over the hits that actually
	# CONTAIN the tile. A narrow spring running past a wide river wins the
	# reach comparison without contributing to the blend at all, so the
	# pair came back describing two different watercourses -- measured at
	# 0.45 tiles of distance beside 0.73 of across.
	#
	# That split the wet/dry verdict in two. probe() calls a tile river
	# when distance <= half_width; the shader calls it wet when
	# |across| / half < 1. Fed different numbers they disagree tile by
	# tile, which is a ragged stepped edge rather than a waterline.
	var signed_across := across_sum / weight_sum * half
	return {
		"distance_tiles": absf(signed_across),
		"signed_across_tiles": signed_across,
		"course_bearing_deg": RiverCatalog.bearing_degrees(direction),
		"discharge": dominant["discharge"],
		"half_width_tiles": half,
	}


var _hits_cache: Dictionary = {}


## Every channel within valley reach of the tile, each as {discharge,
## distance_tiles, half_width_tiles, closest, tangent} -- the raw material
## nearest_channel_geometry blends and _nearest_channel picks from.
func _channel_hits(global_x: int, global_y: int) -> Array:
	var key := Vector2i(global_x, global_y)
	var cached = _hits_cache.get(key)
	if cached != null:
		return cached
	if _hits_cache.size() >= CURVE_CACHE_CAP:
		_hits_cache.clear()
	var tile_center := Vector2(float(global_x) + 0.5, float(global_y) + 0.5)
	var pixel := pixel_of_tile(global_x, global_y)
	var pixel_x := floori(pixel.x)
	var pixel_y := floori(pixel.y)
	var hits: Array = []
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
			var hit := _nearest_on_curve(tile_center, cell)
			if hit["distance"] - hit["half_width"] > GEOMETRY_REACH_TILES:
				continue
			hits.append({
				"cell": cell,
				"discharge": discharge,
				"distance_tiles": hit["distance"],
				"half_width_tiles": hit["half_width"],
				"closest": hit["closest"],
				"tangent": hit["tangent"],
			})
	hits = _one_hit_per_stream(hits)
	_hits_cache[key] = hits
	return hits


## Consecutive pieces of ONE river are not two channels: pieces linked by
## mainstem continuation (b is a's downstream and a is b's mainstem
## upstream) form a stream, and only the stream's nearest piece is kept.
## Blending a reach's own neighbouring pieces put a periodic bump along
## every river (their distances are to the shared endpoints, not to the
## curve); a tributary joining the main is a different stream and does
## get blended.
func _one_hit_per_stream(hits: Array) -> Array:
	var by_cell := {}
	for hit in hits:
		by_cell[hit["cell"]] = hit
	var nearest_by_root := {}
	for hit in hits:
		var root: int = hit["cell"]
		var steps := 0
		while steps < 16:
			var down := _downstream(root)
			if down < 0 or not by_cell.has(down) or _mainstem_upstream(down, true) != root:
				break
			root = down
			steps += 1
		var current = nearest_by_root.get(root)
		if current == null or hit["distance_tiles"] < current["distance_tiles"]:
			nearest_by_root[root] = hit
	return nearest_by_root.values()


## The channel whose bank is nearest this tile, in valley reach, as
## {discharge, distance_tiles, half_width_tiles, closest, tangent}; empty
## when none of the 3x3 surrounding cells carries a river. Measured in
## bank terms (distance minus local half-width) so a big river's valley
## wins over a tributary's beside it.
func _nearest_channel(global_x: int, global_y: int) -> Dictionary:
	# Asked twice per tile (the probe, then the painter's geometry), so
	# the answer is kept per tile.
	var key := Vector2i(global_x, global_y)
	var cached = _channel_cache.get(key)
	if cached != null:
		return cached
	if _channel_cache.size() >= CURVE_CACHE_CAP:
		_channel_cache.clear()
	var answer := _nearest_channel_uncached(global_x, global_y)
	_channel_cache[key] = answer
	return answer


var _channel_cache: Dictionary = {}


func _nearest_channel_uncached(global_x: int, global_y: int) -> Dictionary:
	# Inside a channel, the biggest one wins (a tributary's field never
	# decides depth or width inside the main river); outside every channel,
	# the nearest bank does.
	var best := {}
	var best_reach := INF
	var best_inside_discharge := -1.0
	for hit in _channel_hits(global_x, global_y):
		var reach: float = hit["distance_tiles"] - hit["half_width_tiles"]
		if reach <= 0.0:
			if hit["discharge"] > best_inside_discharge:
				best_inside_discharge = hit["discharge"]
				best = hit
			continue
		if best_inside_discharge >= 0.0 or reach >= best_reach:
			continue
		best_reach = reach
		best = hit
	return best


## The cell's centreline: a quadratic Bezier from `start` through the
## cell centre (the control point) to `end`, as {points, half_widths} --
## CURVE_SEGMENTS + 1 samples with the half-width interpolated from
## `start_half_width` to `end_half_width`. Every point is shifted by whole
## world widths to sit nearest `near`, so a channel crossing the date-line
## seam measures correctly.
func _curve_for_cell(cell: int, near: Vector2) -> Dictionary:
	var center := _nearest_wrapped(_center_of(cell), near)
	var own_half := width_tiles_for_discharge(_data.discharge_at(cell)) / 2.0

	var start := center
	var start_half := SPRING_HALF_WIDTH_TILES
	var upstream := _mainstem_upstream(cell, true)
	if upstream >= 0:
		var upstream_center := _nearest_wrapped(_center_of(upstream), near)
		start = (upstream_center + center) / 2.0
		start_half = (width_tiles_for_discharge(_data.discharge_at(upstream)) / 2.0 + own_half) / 2.0
	else:
		# A headwater: the curve begins at the SOURCE, the cell draining
		# into this one even below the river threshold, at spring width --
		# the river tapers in from a point instead of starting full-width.
		var source := _mainstem_upstream(cell, false)
		if source >= 0:
			start = _nearest_wrapped(_center_of(source), near)

	var end := center
	var end_half := own_half
	var downstream := _downstream(cell)
	if downstream >= 0:
		var downstream_center := _nearest_wrapped(_center_of(downstream), near)
		if _data.is_sea(downstream) or _mainstem_upstream(downstream, true) != cell:
			# The mouth runs to the sea cell's centre; a TRIBUTARY runs to
			# the main cell's centre, where the mainstem's own curve passes
			# -- the mainstem's curve starts toward ITS upstream, not toward
			# this one, so stopping at the midpoint left a gap ("one of the
			# rivers doesn't flow into the other anymore").
			end = downstream_center
		else:
			end = (center + downstream_center) / 2.0
			end_half = (own_half + width_tiles_for_discharge(_data.discharge_at(downstream)) / 2.0) / 2.0

	var half_widths := PackedFloat32Array()
	half_widths.resize(CURVE_SEGMENTS + 1)
	for i in CURVE_SEGMENTS + 1:
		half_widths[i] = lerpf(start_half, end_half, float(i) / float(CURVE_SEGMENTS))
	return {"points": centerline_curve(start, center, end, CURVE_SEGMENTS), "half_widths": half_widths}


## A quadratic Bezier from `a` to `b` bending toward `control`, sampled
## into `segments` straight pieces (segments + 1 points). The curve passes
## through both endpoints and never through the control point itself, so
## a right-angle corner between cells becomes a rounded bend.
static func centerline_curve(a: Vector2, control: Vector2, b: Vector2, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.resize(segments + 1)
	for i in segments + 1:
		var t := float(i) / float(segments)
		var u := 1.0 - t
		points[i] = a * (u * u) + control * (2.0 * u * t) + b * (t * t)
	return points


## A cell's curve is a property of the cell, and every tile within reach
## asks for it (nine cells per tile, a thousand tiles per chunk), so it
## is built once and kept -- in the cell's OWN frame (its centre
## unwrapped), with the seam wrap applied to the query point instead.
## Found live as chunk streaming crawling at a chunk every few seconds.
const CURVE_CACHE_CAP := 16384
var _curve_cache: Dictionary = {}


func _cached_curve(cell: int) -> Dictionary:
	var cached = _curve_cache.get(cell)
	if cached != null:
		return cached
	if _curve_cache.size() >= CURVE_CACHE_CAP:
		_curve_cache.clear()
	var curve := _curve_for_cell(cell, _center_of(cell))
	# The curve's bounding box, grown by the farthest any tile can be
	# affected (valley shoulder plus the widest half-width): a tile outside
	# it skips the segment loop entirely, which most of a tile's nine
	# neighbouring cells do.
	var points: PackedVector2Array = curve["points"]
	var low := points[0]
	var high := points[0]
	for point in points:
		low = Vector2(minf(low.x, point.x), minf(low.y, point.y))
		high = Vector2(maxf(high.x, point.x), maxf(high.y, point.y))
	var reach := VALLEY_HALF_WIDTH_TILES + MAX_WIDTH_TILES / 2.0 + 1.0
	curve["low"] = low - Vector2(reach, reach)
	curve["high"] = high + Vector2(reach, reach)
	_curve_cache[cell] = curve
	return curve


## The closest point on a channel cell's centreline curve to `point`, as
## {distance, closest, tangent, half_width} with the tangent pointing
## DOWNSTREAM and the half-width interpolated along the curve.
func _nearest_on_curve(point: Vector2, cell: int) -> Dictionary:
	var curve := _cached_curve(cell)
	var points: PackedVector2Array = curve["points"]
	var half_widths: PackedFloat32Array = curve["half_widths"]
	# Into the cell's frame: shift the point by whole world widths to sit
	# nearest the cell's centre, and shift the answer back the same way.
	var shift := _nearest_wrapped(point, _center_of(cell)) - point
	var local := point + shift
	var best := {
		"distance": INF, "closest": points[0] - shift, "tangent": Vector2(0.0, -1.0), "half_width": half_widths[0]
	}
	var low: Vector2 = curve["low"]
	var high: Vector2 = curve["high"]
	if local.x < low.x or local.y < low.y or local.x > high.x or local.y > high.y:
		return best
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var ab := b - a
		var length_squared := ab.length_squared()
		var t := 0.0
		if length_squared > 0.0:
			t = clampf((local - a).dot(ab) / length_squared, 0.0, 1.0)
		var closest := a + ab * t
		var distance := local.distance_to(closest)
		if distance >= best["distance"]:
			continue
		var tangent: Vector2 = ab.normalized() if length_squared > 0.0 else best["tangent"]
		best = {
			"distance": distance,
			"closest": closest - shift,
			"tangent": tangent,
			"half_width": lerpf(half_widths[i], half_widths[i + 1], t),
		}
	return best


func _center_of(cell: int) -> Vector2:
	return tile_of_pixel_center(cell % _data.width, _cell_y(cell))


func _nearest_wrapped(candidate: Vector2, point: Vector2) -> Vector2:
	var world_width := float(_world_width)
	var dx := candidate.x - point.x
	if dx > world_width / 2.0:
		candidate.x -= world_width
	elif dx < -world_width / 2.0:
		candidate.x += world_width
	return candidate


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
## discharge (the mainstem), or -1 if none. With `channels_only`, only
## neighbours that are rivers themselves count -- a headwater has none.
func _mainstem_upstream(cell: int, channels_only: bool) -> int:
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
		if channels_only and discharge < river_min_discharge:
			continue
		if discharge > best_discharge:
			best_discharge = discharge
			best = neighbor
	return best
