extends SceneTree

## Do carts and caravans walk through buildings?
##
## The two walkers the building gate did not reach. Asked for directly
## after the rest landed: *"fix the caravan and cart markers too"*.
##
## They are not the same problem and this measures them separately:
##
##   - A CART is pulled. It integrates a step toward whoever holds its
##     shaft (`position += to_puller.normalized() * step`), so it has a
##     step to gate -- but no world reference to gate against.
##   - A CARAVAN does not integrate anything. Its position is a pure
##     closed-form lerp of elapsed time along a straight route between two
##     settlements' wells (CaravanTrip.position_at), driven by
##     EarthChunkManager.step_caravans. Most of that route is over chunks
##     that are not even loaded.
##
## And one thing found while reading, which the numbers here decide:
## VillageRenderer spawns each cart at `store_centre`, the literal CENTRE
## of the warehouse footprint, and hands the carter the same point as their
## work landmark. With the building gate live, that is a cart parked inside
## a wall and a carter who can never arrive.
##
## Usage: godot --headless -s tools/probe_carts_and_caravans.gd

const CHUNK_SIZE := 32
const STEPS := 40
const FRAMES := 600
const SLICE := 0.05
const TILE := 16

var _manager
var _origin: Vector2i
var _step := -1
var _done := false
var _lines: Array = []


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

	if _step < STEPS and not _done:
		_manager.update(_origin + Vector2i(_step * CHUNK_SIZE, 0))
		_sample()
		_step += 1
		return false

	for line in _lines:
		print(line)
	if _lines.is_empty():
		print("CART/CARAVAN nothing to measure in %d chunk-widths" % STEPS)
	return true


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))


func _in_building(p: Vector2) -> bool:
	var c := _cell(p)
	return _manager.has_building_at_global(c.x, c.y)


func _carts() -> Array:
	var found: Array = []
	for chunk_coord in _manager._loaded_villages:
		for node in _manager._loaded_villages[chunk_coord]:
			if is_instance_valid(node) and node.is_in_group("cart"):
				found.append(node)
	return found


func _carters() -> Array:
	var found: Array = []
	for chunk_coord in _manager._loaded_villages:
		for node in _manager._loaded_villages[chunk_coord]:
			if is_instance_valid(node) and node.has_method("setup_economy") and "cart" in node:
				if node.cart != null:
					found.append(node)
	return found


func _sample() -> void:
	if _done:
		return
	var carts := _carts()
	if carts.is_empty():
		return
	_done = true
	_measure_carts(carts)
	_measure_caravans()


func _measure_carts(carts: Array) -> void:
	_lines.append("CART %d carts in loaded villages" % carts.size())
	var parked_in_a_building := 0
	for cart in carts:
		if _in_building(cart.position):
			parked_in_a_building += 1
	_lines.append("  spawned standing INSIDE a building: %d / %d" % [parked_in_a_building, carts.size()])

	var carters := _carters()
	_lines.append("  carters with a cart               : %d" % carters.size())
	var work_inside := 0
	for carter in carters:
		var VillageCart = load("res://src/gameplay/village_cart.gd")
		var work = carter.landmarks.get(VillageCart.WORK_LOCATION, null)
		if work != null and _in_building(work):
			work_inside += 1
	_lines.append("  ...whose WORK LANDMARK is inside one: %d" % work_inside)

	# Now run them. A cart follows its puller in a straight line, so it is
	# the corner of a house it cuts, not the middle of one.
	var inside_frames := 0
	var total := 0
	var moved := 0.0
	for frame in FRAMES:
		for carter in carters:
			carter._process(SLICE)
		for cart in carts:
			var before: Vector2 = cart.position
			cart._process(SLICE)
			moved += before.distance_to(cart.position)
			total += 1
			if _in_building(cart.position):
				inside_frames += 1
	_lines.append(
		"  frames a cart stood inside a building: %d / %d (%.1f%%)"
		% [inside_frames, total, 100.0 * float(inside_frames) / maxf(1.0, float(total))]
	)
	_lines.append("  total cart travel                 : %.0f px" % moved)


func _measure_caravans() -> void:
	# A caravan departs only on a real regional shortage, which this sweep
	# may never produce -- and the ROUTE is the question anyway. Swept over
	# real village layouts and every direction a caravan can leave in.
	#
	# The first cut of this sampled FIVE directions and reported that a
	# caravan never crosses a building. It does: 30.2% of directions did,
	# before VillageLayout.road_exit_toward existed. Five samples of a
	# circle is not a measurement of a circle.
	var VillageLayout = load("res://src/world/village_layout.gd")
	var BuildingCatalog = load("res://src/gameplay/building_catalog.gd")
	var ids := ["house_small", "house_medium", "house_large", "house_small", "house_medium"]
	var straight_crossed := 0
	var routed_crossed := 0
	var routes := 0
	for seed_value in range(1, 61):
		var layout = VillageLayout.new()
		var result: Dictionary = layout.layout(
			ids, CHUNK_SIZE, seed_value, _always_true, _always_false
		)
		var bones: Dictionary = VillageLayout.skeleton(CHUNK_SIZE, seed_value, _always_true)
		var landmarks: Dictionary = bones.get("landmarks", {})
		if not landmarks.has("well") or (result["plots"] as Array).is_empty():
			continue
		var occupied := {}
		for plot in result["plots"]:
			for c in BuildingCatalog.footprint_cells(plot["building_id"], plot["origin"]):
				occupied[c] = true
		for key in ["civic_plot", "warehouse_plot"]:
			var pl: Dictionary = result.get(key, {})
			if not pl.is_empty():
				for c in BuildingCatalog.footprint_cells(pl["building_id"], pl["origin"]):
					occupied[c] = true
		var well := (Vector2(landmarks["well"] as Vector2i) + Vector2(0.5, 0.5)) * float(TILE)
		for step in 360:
			var angle := deg_to_rad(float(step))
			var far: Vector2 = well + Vector2(cos(angle), sin(angle)) * float(CHUNK_SIZE * TILE) * 6.0
			routes += 1
			if _leg_hits(occupied, well, far):
				straight_crossed += 1
			var out: Array = VillageLayout.road_exit_toward(
				bones, Vector2i.ZERO, float(TILE), far
			)
			if out.size() != 2:
				continue
			if (
				_leg_hits(occupied, well, out[0])
				or _leg_hits(occupied, out[0], out[1])
				or _leg_hits(occupied, out[1], far)
			):
				routed_crossed += 1
	_lines.append("")
	_lines.append("CARAVAN %d routes out of 60 real village layouts, every direction" % routes)
	_lines.append("  straight from the well   : %d cross a building (%.1f%%)" % [
		straight_crossed, 100.0 * float(straight_crossed) / maxf(1.0, float(routes))
	])
	_lines.append("  out by the road instead  : %d cross a building (%.1f%%)" % [
		routed_crossed, 100.0 * float(routed_crossed) / maxf(1.0, float(routes))
	])


func _always_true(_c: Vector2i) -> bool:
	return true


func _always_false(_c: Vector2i) -> bool:
	return false


func _leg_hits(occupied: Dictionary, a: Vector2, b: Vector2) -> bool:
	var steps := int(a.distance_to(b) / float(TILE) * 4.0) + 1
	for i in steps + 1:
		var at: Vector2 = a.lerp(b, float(i) / float(steps))
		if occupied.has(Vector2i(floori(at.x / float(TILE)), floori(at.y / float(TILE)))):
			return true
	return false
