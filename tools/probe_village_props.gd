extends SceneTree

## What props a real village actually ends up with, and where they stand.
## Reported live: "there are 3 wells and one stand all over the place."
##
## Runs the REAL EarthChunkManager load path (the same one
## tools/probe_village_houses_live.gd uses) and, per settlement chunk,
## reports every spawned landmark prop: its own id, whether it is one of
## the settlement's shared landmarks or a villager's personal one, the tile
## it stands on, its distance from the village square -- and, crucially,
## which sprite it is actually DRAWN as, since ProceduralLandmarkSprite
## falls back to the well's drawing for any id it does not know.
##
## MEASURED (2026-09-17), 3 real settlements near lat 48.6 lon 12.7, before
## and after the fix this probe drove:
##  - BEFORE: every village showed its own well on the square PLUS one
##    well-looking prop per hunter, out in the fields behind the houses --
##    those props' ids were "hunting_ground", which had no drawing of its
##    own and fell through ProceduralLandmarkSprite's unknown-id fallback
##    to the WELL's. A roster with two hunters is three wells.
##  - AFTER: exactly one well per village, and a hunter's prop drawn as
##    itself (a drying rack).
## The stalls are two per village with a merchant in it, by design: the
## shared one on the square, and that merchant's own stand at their house
## (docs/concept/npc.md).
##
## Runs in _process, not _init/_initialize: see
## tools/probe_village_houses_live.gd's own doc comment.

const CHUNK_SIZE := 32
const LAT := 48.6
const LON := 12.7
const STEPS := 30

var _manager
var _village_layout_script
var _landmark_sprite_script
var _origin: Vector2i
var _step := -1
var _seen := {}


func _initialize() -> void:
	var EarthChunkGenerator = load("res://src/world/earth_chunk_generator.gd")
	var GeoCoordinates = load("res://src/world/geo_coordinates.gd")
	_village_layout_script = load("res://src/world/village_layout.gd")
	_landmark_sprite_script = load("res://src/rendering/procedural_landmark_sprite.gd")
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


func _sample() -> void:
	for chunk_coord in _manager._loaded_villages:
		if _seen.has(chunk_coord):
			continue
		var occupations: Array = []
		var props: Array = []
		for node in _manager._loaded_villages[chunk_coord]:
			if not is_instance_valid(node):
				continue
			if node.has_method("setup_economy"):
				occupations.append(node.identity.occupation)
			elif node.has_meta("landmark_id"):
				props.append({
					"id": node.get_meta("landmark_id"),
					"personal": node.get_meta("personal"),
					"position": node.position,
				})
		if occupations.is_empty():
			continue
		_seen[chunk_coord] = {"occupations": occupations, "props": props}


func _report() -> void:
	var TerrainRenderer = load("res://src/rendering/terrain_renderer.gd")
	var tile_size: int = TerrainRenderer.TILE_SIZE
	var known: Array = _landmark_sprite_script.LANDMARK_IDS
	var drawn_totals := {}
	print("\n=== village props (%d settlements) ===" % _seen.size())
	for chunk_coord in _seen:
		var entry: Dictionary = _seen[chunk_coord]
		var bones: Dictionary = _village_layout_script.skeleton(
			CHUNK_SIZE, _village_layout_script.seed_for(chunk_coord), _dry_in(chunk_coord)
		)
		var plaza: Rect2i = bones["plaza"]
		var plaza_centre := Vector2(plaza.position) + Vector2(plaza.size) * 0.5
		print("\nchunk %s  occupations=%s" % [chunk_coord, entry.occupations])
		print("  plaza tiles %s..%s   layout landmarks %s" % [plaza.position, plaza.end, bones["landmarks"]])
		var looks_like := {}
		for prop in entry.props:
			var local_tile := Vector2(prop.position) / float(tile_size) - Vector2(chunk_coord * CHUNK_SIZE)
			var drawn: String = prop.id if known.has(prop.id) else "well (fallback)"
			looks_like[drawn] = looks_like.get(drawn, 0) + 1
			drawn_totals[drawn] = drawn_totals.get(drawn, 0) + 1
			print("  %-16s personal=%-5s tile=(%5.1f,%5.1f)  %5.1f tiles from the square   drawn as %s" % [
				prop.id, prop.personal, local_tile.x, local_tile.y,
				(local_tile - plaza_centre).length(), drawn,
			])
		print("  -> looks like: %s" % looks_like)
	print("\n=== totals, by what it LOOKS like on screen ===")
	print(drawn_totals)


func _dry_in(chunk_coord: Vector2i) -> Callable:
	var manager = _manager
	return func(cell: Vector2i) -> bool:
		var g: Vector2i = chunk_coord * CHUNK_SIZE + cell
		return not manager.is_water_at_global(g.x, g.y)
