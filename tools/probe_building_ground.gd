extends SceneTree

## What ground a real village's buildings actually stand on, and what the
## terrain painter paints there.
##
## Reported live (screenshot): "the background of the houses 2x2 should be
## variable; if the city hall is placed on the plaza it should have
## cobblestone background so it looks seamless" -- every building in the
## shot sits on its own flat square, visibly seamed against the plaza
## paving it was raised on.
##
## Runs the REAL EarthChunkManager load path (same shape as
## tools/probe_village_props.gd) and, per settlement chunk, reports for
## every placed building: its id and origin, the modification ids its own
## footprint carries, the tile the painter puts down there (compared by
## name against the plain earth / road / earth-blend families), and the
## composition of its KERB -- the ring of cells immediately around the
## footprint -- which is what says whether it stands on a paved square or
## on open ground.
##
## Runs in _process, not _initialize: see tools/probe_village_houses_live.gd.
##
## Usage: godot --headless --path . -s tools/probe_building_ground.gd

const CHUNK_SIZE := 32
const LAT := 48.6
const LON := 12.7
const STEPS := 30

var _manager
var _village_layout_script
var _building_catalog_script
var _terrain_renderer_script
var _origin: Vector2i
var _step := -1
var _seen := {}


func _initialize() -> void:
	var EarthChunkGenerator = load("res://src/world/earth_chunk_generator.gd")
	var GeoCoordinates = load("res://src/world/geo_coordinates.gd")
	_village_layout_script = load("res://src/world/village_layout.gd")
	_building_catalog_script = load("res://src/gameplay/building_catalog.gd")
	_terrain_renderer_script = load("res://src/rendering/terrain_renderer.gd")
	var geo = GeoCoordinates.new()
	_origin = Vector2i(
		geo.tile_for_longitude(LON, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(LAT, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)


func _process(_delta: float) -> bool:
	if _step < 0:
		var EarthChunkManager = load("res://src/world/earth_chunk_manager.gd")
		var tile_map_layer := TileMapLayer.new()
		var entities := Node2D.new()
		var creatures := Node2D.new()
		root.add_child(tile_map_layer)
		root.add_child(entities)
		root.add_child(creatures)
		_manager = EarthChunkManager.new(tile_map_layer, entities, creatures)
		_step = 0
		return false
	if _step < STEPS:
		_manager.update(_origin + Vector2i(_step * CHUNK_SIZE, 0))
		_sample()
		_step += 1
		return false
	_report()
	return true


## Measured WHILE the chunk is loaded, not at report time: a chunk that
## has streamed back out has no modifications to read and no painted cell
## to look at, which reads as a village of unpaved buildings that is not
## there at all.
func _sample() -> void:
	for chunk_coord in _manager._loaded_chunks:
		if _seen.has(chunk_coord):
			continue
		var buildings: Array = _manager.buildings_in_chunk(chunk_coord)
		if buildings.is_empty():
			continue
		var bones: Dictionary = _village_layout_script.skeleton(
			CHUNK_SIZE, _village_layout_script.seed_for(chunk_coord), _dry_in(chunk_coord)
		)
		var plaza: Rect2i = bones["plaza"]
		var measured: Array = []
		for record in buildings:
			var building_id: String = record["id"]
			var origin_local: Vector2i = record["origin_local"]
			var footprint: Vector2i = _building_catalog_script.footprint_of(building_id)
			var kerb := _kerb_of(chunk_coord, origin_local, footprint)
			measured.append({
				"id": building_id, "origin": origin_local, "footprint": footprint,
				"paved": kerb["paved"], "total": kerb["total"],
				"on_plaza": plaza.has_point(origin_local),
				"painted": _painted_name(chunk_coord, origin_local),
			})
		_seen[chunk_coord] = {"plaza": plaza, "buildings": measured}


func _report() -> void:
	print("\n=== building ground (%d chunks with buildings) ===" % _seen.size())
	var totals := {}
	for chunk_coord in _seen:
		var plaza: Rect2i = _seen[chunk_coord]["plaza"]
		print("\nchunk %s   plaza %s..%s" % [chunk_coord, plaza.position, plaza.end])
		for measured in _seen[chunk_coord]["buildings"]:
			var paved: int = measured["paved"]
			var total: int = measured["total"]
			var key := "%s on %s" % [measured["painted"], "plaza" if measured["on_plaza"] else "open ground"]
			totals[key] = totals.get(key, 0) + 1
			print("  %-12s origin=%s %dx%d  kerb %2d/%2d paved (%3d%%)  plaza=%-5s  painted as %s" % [
				measured["id"], measured["origin"], measured["footprint"].x, measured["footprint"].y,
				paved, total, 0 if total == 0 else int(round(100.0 * paved / total)),
				measured["on_plaza"], measured["painted"],
			])
	print("\n=== totals ===")
	print(totals)


## The ring of cells immediately around the footprint -- how many of them
## carry the village's own paving.
func _kerb_of(chunk_coord: Vector2i, origin_local: Vector2i, footprint: Vector2i) -> Dictionary:
	var paved := 0
	var total := 0
	for y in range(origin_local.y - 1, origin_local.y + footprint.y + 1):
		for x in range(origin_local.x - 1, origin_local.x + footprint.x + 1):
			var cell := Vector2i(x, y)
			if Rect2i(origin_local, footprint).has_point(cell):
				continue
			if cell.x < 0 or cell.y < 0 or cell.x >= CHUNK_SIZE or cell.y >= CHUNK_SIZE:
				continue
			total += 1
			var g: Vector2i = chunk_coord * CHUNK_SIZE + cell
			if _terrain_renderer_script.is_road_tile(_manager.modification_at_global(g.x, g.y)):
				paved += 1
	return {"paved": paved, "total": total}


## Which tile FAMILY the painter really put on the anchor cell, by name --
## the atlas coordinate alone says nothing a reader can check.
func _painted_name(chunk_coord: Vector2i, origin_local: Vector2i) -> String:
	var renderer = _manager.terrain_renderer()
	var layer: TileMapLayer = _manager._tile_map_layer
	var g: Vector2i = chunk_coord * CHUNK_SIZE + origin_local
	var coords: Vector2i = layer.get_cell_atlas_coords(g)
	var named := {
		"earth (flat)": renderer.atlas_coords_for_modification(_terrain_renderer_script.EARTH_TILE_ID),
		"road (cobbles)": renderer.atlas_coords_for_modification(_terrain_renderer_script.ROAD_TILE_ID),
		"trail": renderer.atlas_coords_for_modification(_terrain_renderer_script.TRAIL_TILE_ID),
	}
	for name in named:
		if named[name] == coords:
			return name
	return "other %s" % coords


func _dry_in(chunk_coord: Vector2i) -> Callable:
	var manager = _manager
	return func(cell: Vector2i) -> bool:
		var g: Vector2i = chunk_coord * CHUNK_SIZE + cell
		return not manager.is_water_at_global(g.x, g.y)
