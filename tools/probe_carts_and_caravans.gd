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
	_lines.append("")
	_lines.append("CARAVAN %d in flight" % _manager._active_caravans.size())
	# A caravan departs only on a real regional shortage, which this sweep
	# may never produce -- so the ROUTE is built from the same two well
	# positions a real trip is given (_well_position_for_settlement, which
	# generates a settlement without needing its chunk loaded). The SHAPE of
	# the line is the question; who happens to be shipping grain is not.
	var EntityRef = load("res://src/emergence/entity_ref.gd")
	var here := Vector2i(
		floori(float(_origin.x + (_step - 1) * CHUNK_SIZE) / CHUNK_SIZE), floori(float(_origin.y) / CHUNK_SIZE)
	)
	var pairs := 0
	var routes_crossing := 0
	var total_crossed := 0
	var total_loaded := 0
	var nearest_approach := 1.0e20
	for away in [2, 3, 4, 6, 8, 12, 18, 30]:
		for direction in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 0)]:
			var far := here + Vector2i(direction.x * away, direction.y * maxi(1, away / 2))
			var wa: Vector2 = _manager._well_position_for_settlement(EntityRef.for_settlement(here))
			var wb: Vector2 = _manager._well_position_for_settlement(EntityRef.for_settlement(far))
			var n := 400
			var hit := 0
			var seen := 0
			for i in n + 1:
				var at: Vector2 = wa.lerp(wb, float(i) / float(n))
				var cc := _cell(at)
				var ch := Vector2i(floori(float(cc.x) / CHUNK_SIZE), floori(float(cc.y) / CHUNK_SIZE))
				if not _manager._loaded_chunks.has(ch):
					continue
				seen += 1
				if _manager.has_building_at_global(cc.x, cc.y):
					hit += 1
				else:
					# How close the line ever came to one, in tiles -- a
					# route that merely misses by a hair is a route that
					# will clip once a village grows.
					for dx in range(-3, 4):
						for dy in range(-3, 4):
							if _manager.has_building_at_global(cc.x + dx, cc.y + dy):
								nearest_approach = minf(
									nearest_approach, Vector2(dx, dy).length()
								)
			pairs += 1
			total_loaded += seen
			total_crossed += hit
			if hit > 0:
				routes_crossing += 1
	_lines.append(
		"  %d well-to-well routes sampled; %d of them cross a building; %d of %d answerable points in one"
		% [pairs, routes_crossing, total_crossed, total_loaded]
	)
	_lines.append(
		"  nearest a route ever came to a building: %.1f tiles"
		% (nearest_approach if nearest_approach < 1.0e19 else -1.0)
	)
	for away in [4, 12, 30]:
		var there := here + Vector2i(away, away / 2)
		var a: Vector2 = _manager._well_position_for_settlement(EntityRef.for_settlement(here))
		var b: Vector2 = _manager._well_position_for_settlement(EntityRef.for_settlement(there))
		var samples := 400
		var loaded := 0
		var crossed := 0
		for i in samples + 1:
			var at: Vector2 = a.lerp(b, float(i) / float(samples))
			var c := _cell(at)
			var chunk := Vector2i(floori(float(c.x) / CHUNK_SIZE), floori(float(c.y) / CHUNK_SIZE))
			if not _manager._loaded_chunks.has(chunk):
				continue
			loaded += 1
			if _manager.has_building_at_global(c.x, c.y):
				crossed += 1
		_lines.append(
			"  %d chunks away: route %.0f px; %d / %d sampled points sit in a LOADED chunk (%.1f%%), %d of those in a building"
			% [away, a.distance_to(b), loaded, samples + 1, 100.0 * float(loaded) / float(samples + 1), crossed]
		)
