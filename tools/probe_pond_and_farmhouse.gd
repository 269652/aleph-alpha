extends SceneTree

## Two reports, measured on REAL villages before anything is changed:
##
##   "Now there's a pond, but grass grows in it and no fish are in it and
##    no Fisher Hut is near."
##   "Also now the plaza is back and the city hall, but not a single
##    Farmhouse even though there's plenty of space."
##
## Per this repo's probe-before-you-trust convention. Four separate claims
## live in those two sentences and each gets its own column, because three
## of them could be true while the fourth is a misreading of the picture:
##
##   GRASS  tall-grass patches standing ON the pond's own water cells
##   FISH   the pond's stock, and the markers actually swimming in it
##   HUT    whether a fisher_hut stands, and how far from the water
##   FARM   farmhouses against the trades the village actually has
##
## Structural notes are probe_village_supply.gd's (work in _process, load()
## at runtime, ask the manager for its own loaded villages, print each line
## the moment it is known -- a survey that only speaks at the end tells you
## nothing while it runs, and a village founding is slow).

const CHUNK_SIZE := 32
const STEPS := 26

var _manager
var _origin: Vector2i
var _step := -1
var _seen: Dictionary = {}

var _villages := 0
var _unstamped := 0
var _revisiting := false
var _ponds := 0
var _ponds_with_grass := 0
var _ponds_without_fish := 0
var _ponds_without_hut := 0
var _villages_wanting_a_farmhouse := 0

var _VillagePond
var _VillageFarm
var _VillageAssembly
var _BuildingCatalog


func _initialize() -> void:
	var EarthChunkGenerator = load("res://src/world/earth_chunk_generator.gd")
	var GeoCoordinates = load("res://src/world/geo_coordinates.gd")
	var geo = GeoCoordinates.new()
	_origin = Vector2i(
		geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)


func _process(_delta: float) -> bool:
	if _step < 0:
		_VillagePond = load("res://src/gameplay/village_pond.gd")
		_VillageFarm = load("res://src/gameplay/village_farm.gd")
		_VillageAssembly = load("res://src/emergence/village_assembly.gd")
		_BuildingCatalog = load("res://src/gameplay/building_catalog.gd")
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
		_survey()
		_step += 1
		return false

	# ...and then WALK BACK. Everything a village keeps between visits is
	# only tested by a second visit: the water is a persisted modification
	# and comes back for free, and the question this probe exists to answer
	# is what comes back WITH it.
	if _step < STEPS * 2:
		if _step == STEPS:
			print("")
			print("######## walking back: every village below is a REVISIT ########")
			_seen.clear()
			_revisiting = true
		_manager.update(_origin + Vector2i((STEPS * 2 - 1 - _step) * CHUNK_SIZE, 0))
		_survey()
		_step += 1
		return false

	print("")
	print("== TOTALS over %d villages, %d ponds ==" % [_villages, _ponds])
	print("  ponds with grass growing in them : %d" % _ponds_with_grass)
	print("  ponds holding no fish            : %d" % _ponds_without_fish)
	print("  ponds with no hut on their bank  : %d" % _ponds_without_hut)
	print("  villages wanting a farmhouse     : %d" % _villages_wanting_a_farmhouse)
	print("  chunks registered but not stamped: %d" % _unstamped)
	return true


func _survey() -> void:
	for chunk_coord in _manager._loaded_villages.keys():
		if _seen.has(chunk_coord):
			continue
		_seen[chunk_coord] = true
		# A chunk registered as a village but carrying nothing at all was
		# never STAMPED -- _loaded_villages holds a node list, not a
		# promise that the ground was built on. Counting those as villages
		# is how the first version of this probe reported 90 of them with
		# 0 buildings each.
		if _manager.buildings_in_chunk(chunk_coord).is_empty():
			_unstamped += 1
			continue
		_villages += 1
		_report(chunk_coord)


func _report(chunk_coord: Vector2i) -> void:
	print("")
	print("== village at chunk %s%s ==" % [
		str(chunk_coord), "  (REVISIT)" if _revisiting else "  (first visit)"
	])
	var records: Array = _manager.buildings_in_chunk(chunk_coord)
	_report_farm(chunk_coord, records)
	_report_ponds(chunk_coord, records)


## Farmhouses against the trades the village really has. A village of
## fishers raising no farmstead is BY DESIGN (VillageAssembly.
## FOOD_WORKS_BY_TRADE maps fisher -> ""), so the number that answers
## "not a single Farmhouse" is how many villagers wanted one.
func _report_farm(chunk_coord: Vector2i, records: Array) -> void:
	var by_occupation: Dictionary = {}
	var by_id: Dictionary = {}
	for record in records:
		var occupation := String(record.get("occupation", ""))
		if occupation != "":
			by_occupation[occupation] = int(by_occupation.get(occupation, 0)) + 1
		var id := String(record.get("id", ""))
		by_id[id] = int(by_id.get(id, 0)) + 1
	var farmhouses := int(by_id.get(_VillageFarm.FARM_BUILDING_ID, 0))
	var wants := 0
	for trade in by_occupation:
		if String(_VillageAssembly.FOOD_WORKS_BY_TRADE.get(trade, "")) == _VillageAssembly.FOOD_WORKS_ID:
			wants += int(by_occupation[trade])
	if wants > 0 and farmhouses == 0:
		_villages_wanting_a_farmhouse += 1
	print("  FARM  %d farmhouse(s); %d villager(s) of a farmhouse trade%s" % [
		farmhouses, wants, "   <-- WANTED ONE, HAS NONE" if wants > 0 and farmhouses == 0 else ""
	])
	print("        trades=%s" % ("(none)" if by_occupation.is_empty() else str(by_occupation)))
	print("        buildings=%s" % str(by_id))


## Every dug pond in the chunk, flooded from its own water rather than
## looked up in a record -- a pond is a set of modification tiles and
## nothing else is stored about it.
func _report_ponds(chunk_coord: Vector2i, records: Array) -> void:
	var water: Dictionary = {}
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			var g: Vector2i = chunk_coord * CHUNK_SIZE + Vector2i(x, y)
			if _VillagePond.is_pond_tile(_manager.modification_at_global(g.x, g.y)):
				water[Vector2i(x, y)] = true
	if water.is_empty():
		print("  POND  none dug in this chunk")
		return
	var huts: Array = []
	for record in records:
		if String(record.get("id", "")) == _VillagePond.HUT_BUILDING_ID:
			huts.append(record.get("origin_local", Vector2i.ZERO))
	for body in _bodies(water):
		_ponds += 1
		_report_pond(chunk_coord, body, huts)


## One pond is one connected body of water, flooded out of the set -- the
## same "one pond however many cells" the fish stock is keyed by.
func _bodies(water: Dictionary) -> Array:
	var remaining := water.duplicate()
	var bodies: Array = []
	while not remaining.is_empty():
		var start: Vector2i = remaining.keys()[0]
		var body: Array = []
		var queue: Array = [start]
		remaining.erase(start)
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_back()
			body.append(cell)
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var next: Vector2i = cell + step
				if remaining.has(next):
					remaining.erase(next)
					queue.append(next)
		bodies.append(body)
	return bodies


func _report_pond(chunk_coord: Vector2i, body: Array, huts: Array) -> void:
	var first: Vector2i = chunk_coord * CHUNK_SIZE + (body[0] as Vector2i)
	var grassy: Array = []
	for cell in body:
		if _manager._grass_sims.has(chunk_coord) and _manager._grass_sims[chunk_coord].has_grass(cell):
			grassy.append(cell)
	var stock: float = _manager.pond_fish_at(first.x, first.y)
	var markers: int = _manager.pond_fish_marker_count_at(first.x, first.y)
	# From the hut's whole FOOTPRINT, not its origin: VillagePond.hut_origin
	# sites the hut by _hut_distance_to, which is footprint-to-water. The
	# first run of this probe measured origin-to-water and reported a hut
	# correctly standing on the bank as "4.1 tiles away, NO HUT".

	var nearest_hut := INF
	for hut in huts:
		for cell in _BuildingCatalog.footprint_cells(_VillagePond.HUT_BUILDING_ID, hut as Vector2i):
			for wet in body:
				nearest_hut = minf(
					nearest_hut, Vector2(cell as Vector2i).distance_to(Vector2(wet as Vector2i))
				)
	if not grassy.is_empty():
		_ponds_with_grass += 1
	if stock <= 0.0:
		_ponds_without_fish += 1
	if nearest_hut > float(_VillagePond.HUT_BANK_REACH_TILES):
		_ponds_without_hut += 1
	print("  POND  %d cell(s) at %s" % [body.size(), str(body[0])])
	print("        GRASS %d of %d cell(s) carry a grass patch%s" % [
		grassy.size(), body.size(), "   <-- GRASS IN THE WATER" if not grassy.is_empty() else ""
	])
	print("        FISH  stock=%.2f, %d marker(s) swimming%s" % [
		stock, markers, "   <-- EMPTY" if stock <= 0.0 else ""
	])
	_report_hut_road(chunk_coord, huts)
	print("        HUT   %d in chunk, nearest %s tiles from the water%s" % [
		huts.size(),
		"none" if nearest_hut == INF else "%.1f" % nearest_hut,
		"   <-- NO HUT ON THE BANK" if nearest_hut > float(_VillagePond.HUT_BANK_REACH_TILES) else "",
	])


## Whether a hut\'s door really reaches the village, reported live:
## *"Fisher hut is there but not connected to street system"*. A front
## step is one paved cell; a road home is a run of them that arrives
## somewhere. So this floods the paving OUT from the doorstep and says how
## far it gets, and whether it ever meets the village\'s own street row.
func _report_hut_road(chunk_coord: Vector2i, huts: Array) -> void:
	if huts.is_empty():
		return
	var TerrainRenderer = load("res://src/rendering/terrain_renderer.gd")
	var BuildingCatalog = load("res://src/gameplay/building_catalog.gd")
	var VillageLayout = load("res://src/world/village_layout.gd")
	var is_buildable := func(cell: Vector2i) -> bool:
		var g: Vector2i = chunk_coord * CHUNK_SIZE + cell
		return not _manager.is_water_at_global(g.x, g.y)
	var street_y: int = int(VillageLayout.skeleton(
		CHUNK_SIZE, VillageLayout.seed_for(chunk_coord), is_buildable
	)["street_y"])
	for hut in huts:
		var step: Vector2i = (hut as Vector2i) + BuildingCatalog.doorstep_of(
			_VillagePond.HUT_BUILDING_ID
		)
		var seen: Dictionary = {}
		var queue: Array = []
		var g0: Vector2i = chunk_coord * CHUNK_SIZE + step
		if TerrainRenderer.is_road_tile(_manager.modification_at_global(g0.x, g0.y)):
			seen[step] = true
			queue.append(step)
		var reached_street := false
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_back()
			if (cell.y - street_y) % VillageLayout.STREET_PITCH_TILES == 0 and cell.y >= street_y:
				reached_street = true
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var next: Vector2i = cell + d
				if seen.has(next) or next.x < 0 or next.y < 0 \
						or next.x >= CHUNK_SIZE or next.y >= CHUNK_SIZE:
					continue
				var g: Vector2i = chunk_coord * CHUNK_SIZE + next
				if not TerrainRenderer.is_road_tile(_manager.modification_at_global(g.x, g.y)):
					continue
				seen[next] = true
				queue.append(next)
		print("        ROAD  hut %s: door %s, %d paved cell(s) joined to it, street row %s" % [
			str(hut), "paved" if seen.has(step) else "BARE", seen.size(),
			"reached" if reached_street else "NOT REACHED",
		])
