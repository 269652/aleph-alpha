extends SceneTree

## Replays the FOUNDING layout of the reported village (chunk (676,148),
## lat 47.2 lon 15.1) on virgin ground -- nothing modified, nothing paved,
## exactly what VillageRenderer._place_new_village saw the first time -- and
## asks the one question the live probe left open: why was the square
## abandoned, so that two houses ended up standing on the civic plot?

const CHUNK_SIZE := 32
const CHUNK := Vector2i(676, 148)

var _manager
var _done := false


func _process(_delta: float) -> bool:
	if _manager == null:
		var EarthChunkManager = load("res://src/world/earth_chunk_manager.gd")
		var tml := TileMapLayer.new()
		var ents := Node2D.new()
		var crts := Node2D.new()
		root.add_child(tml)
		root.add_child(ents)
		root.add_child(crts)
		_manager = EarthChunkManager.new(tml, ents, crts)
		_manager.update(Vector2(CHUNK * CHUNK_SIZE + Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2)))
		return false
	if not _done:
		_done = true
		_report()
		_dump_records()
	return true


func _report() -> void:
	var VillageLayout = load("res://src/world/village_layout.gd")
	var VillageRenderer = load("res://src/rendering/village_renderer.gd")
	var BuildingCatalog = load("res://src/gameplay/building_catalog.gd")
	# Virgin ground: water is the only veto, nothing is modified, nothing paved.
	var is_buildable := func(cell: Vector2i) -> bool:
		var g: Vector2i = CHUNK * CHUNK_SIZE + cell
		return not _manager.is_water_at_global(g.x, g.y)
	var never := func(_cell: Vector2i) -> bool: return false
	var is_forest := func(cell: Vector2i) -> bool:
		var g: Vector2i = CHUNK * CHUNK_SIZE + cell
		return _manager.biome_at_global(g.x, g.y) == "forest"
	var seed_value: int = VillageLayout.seed_for(CHUNK)
	var bones: Dictionary = VillageLayout.skeleton(CHUNK_SIZE, seed_value, is_buildable)
	var plaza: Rect2i = bones["plaza"]
	print("")
	print("FOUNDING REPLAY chunk %s  plaza=%s  civic=%s" % [
		str(CHUNK), str(plaza), str(bones["civic_plot"]["origin"])
	])
	var industry: Dictionary = VillageLayout.industry_plot(
		"sawmill", CHUNK_SIZE, seed_value, is_buildable, is_forest, never, Callable(), never
	)
	if industry.is_empty():
		print("   no industry plot")
	else:
		var reserved: Dictionary = VillageRenderer._reserved_cells(industry)
		var on_plaza: Array = []
		for cell in reserved:
			if plaza.has_point(cell):
				on_plaza.append(cell)
		print("   sawmill origin=%s doorstep=%s spur=%d cells" % [
			str(industry["origin"]), str(industry["doorstep"]), (industry["road_spur"] as Array).size()
		])
		print("   spur: %s" % str(industry["road_spur"]))
		print("   RESERVED CELLS INSIDE THE SQUARE: %s" % str(on_plaza))
		# and the one question that decides the square's fate
		var occupied := func(cell: Vector2i) -> bool: return reserved.has(cell)
		var clear_with: bool = VillageLayout._every_cell_clear(
			VillageLayout._rect_cells(plaza), CHUNK_SIZE, is_buildable, occupied
		)
		var clear_without: bool = VillageLayout._every_cell_clear(
			VillageLayout._rect_cells(plaza), CHUNK_SIZE, is_buildable, never
		)
		print("   has_plaza with the mill reserved = %s ; without it = %s" % [
			str(clear_with), str(clear_without)
		])
		var civic_hit: Array = []
		for cell in BuildingCatalog.footprint_cells("city_hall", bones["civic_plot"]["origin"]):
			if reserved.has(cell):
				civic_hit.append(cell)
		print("   reserved cells on the CIVIC PLOT: %s" % str(civic_hit))


func _dump_records() -> void:
	var BuildingCatalog = load("res://src/gameplay/building_catalog.gd")
	var VillageLayout = load("res://src/world/village_layout.gd")
	var is_buildable := func(cell: Vector2i) -> bool:
		var g: Vector2i = CHUNK * CHUNK_SIZE + cell
		return not _manager.is_water_at_global(g.x, g.y)
	var plaza: Rect2i = VillageLayout.skeleton(
		CHUNK_SIZE, VillageLayout.seed_for(CHUNK), is_buildable
	)["plaza"]
	print("")
	print("REAL RECORDS (keys of the first): ")
	var first := true
	for record in _manager.buildings_in_chunk(CHUNK):
		if first:
			first = false
			print("   %s" % str(record.keys()))
		var id: String = record.get("id", "")
		var origin_local = record.get("origin_local", record.get("origin", null))
		var on_plaza := false
		if origin_local != null:
			for cell in BuildingCatalog.footprint_cells(id, origin_local):
				if plaza.has_point(cell):
					on_plaza = true
		print("   %s origin_local=%s on_plaza=%s seed=%s" % [
			id, str(origin_local), str(on_plaza), str(record.get("seed", "-"))
		])
