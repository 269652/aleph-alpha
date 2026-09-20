extends SceneTree

## Does every farmhouse a village raises really get a field of its own?
##
## Reported live with the village in shot: *"There's a farmhouse without bed
## enclosure and the NPC only sows 4 / 6 tiles"*. Two questions, so two
## measurements: how many farmhouses end up with an EMPTY field (no beds, so
## no fence ring either), and how many cells the fields that do exist hold --
## a 3x2 or 2x3 is six, and anything less is a field that was trimmed.
##
## Uses the REAL settlement generator and the REAL VillageRenderer against
## the same flat-ground StubWorld probe_village_map.gd already established,
## so the layout, the farmhouses and every field are the ones the game lays
## out. Scans many chunks rather than one, because a farmhouse only loses
## its ground when a NEIGHBOURING farmhouse is close enough to own it, and
## one lucky village proves nothing either way.

const CHUNK_SIZE := 32
const TILE_SIZE := 16
const CHUNKS_TO_SCAN := 400

class StubWorld:
	var place_calls: Array = []
	var built: Dictionary = {}
	var occupied: Dictionary = {}
	var BuildingCatalog = load("res://src/gameplay/building_catalog.gd")

	func place_building(chunk_coord, origin_local, building_id, facing, seed_value, owner, occupation = "", resident = 0) -> bool:
		var cells: Array = BuildingCatalog.footprint_cells(building_id, origin_local)
		for cell in cells + [origin_local + BuildingCatalog.doorstep_of(building_id)]:
			if occupied.get(chunk_coord * CHUNK_SIZE + cell, "") != "":
				return false
		place_calls.append({"origin_local": origin_local, "building_id": building_id, "chunk_coord": chunk_coord,
			"facing": facing, "seed": seed_value, "owner_household_id": owner, "occupation": occupation, "resident_seed": resident})
		for cell in cells:
			occupied[chunk_coord * CHUNK_SIZE + cell] = building_id
		return true

	func place_building_over_roads(chunk_coord, origin_local, building_id, seed_value, owner) -> bool:
		for cell in BuildingCatalog.footprint_cells(building_id, origin_local):
			occupied.erase(chunk_coord * CHUNK_SIZE + cell)
		occupied.erase(chunk_coord * CHUNK_SIZE + origin_local + BuildingCatalog.doorstep_of(building_id))
		return place_building(chunk_coord, origin_local, building_id, Vector2i(0, 1), seed_value, owner)

	func buildings_in_chunk(chunk_coord) -> Array:
		var out: Array = []
		for call in place_calls:
			out.append({"id": call["building_id"], "origin_local": call["origin_local"], "chunk_coord": chunk_coord,
				"facing": call["facing"], "seed": call["seed"], "condition": 1.0, "progress": 1.0,
				"owner_household_id": call["owner_household_id"], "occupation": call["occupation"], "resident_seed": call["resident_seed"]})
		return out

	func build_at_global(x: int, y: int, tile_id: String) -> bool:
		built[Vector2i(x, y)] = tile_id
		occupied[Vector2i(x, y)] = tile_id
		return true

	func biome_at_global(_x, _y) -> String: return "grassland"
	func is_water_at_global(_x, _y) -> bool: return false
	func is_buildable_terrain_at(_x, _y) -> bool: return true
	func modification_at_global(x, y) -> String: return occupied.get(Vector2i(x, y), "")
	func record_settlement_founded_if_new(_c, _n, _p = []) -> void: pass
	func household_count_for_settlement(_s) -> int: return 0
	func house_origin_for_villager(_c, _s): return null
	func set_building_resident(_c, _o, _oc, _r) -> bool: return true



func _initialize() -> void:
	var SettlementGenerator = load("res://src/world/settlement_generator.gd")
	var VillageRenderer = load("res://src/rendering/village_renderer.gd")
	var VillageFarm = load("res://src/gameplay/village_farm.gd")
	var generator = SettlementGenerator.new()

	var villages := 0
	var farmhouses := 0
	var without_a_field := 0
	var siting_disagreed := 0
	var field_sizes: Dictionary = {}
	var offenders: Array = []

	for x in CHUNKS_TO_SCAN:
		var coord := Vector2i(x, 3)
		if not generator.has_settlement_at(coord, "grassland"):
			continue
		var settlement = generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
		var farmers := 0
		for npc in settlement.npcs:
			if VillageFarm.crop_for(npc.occupation) != "":
				farmers += 1
		if farmers == 0:
			continue
		villages += 1
		var world = StubWorld.new()
		var parent := Node2D.new()
		root.add_child(parent)
		var renderer = VillageRenderer.new()
		renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
		# The reserved landmark cells spawn_village really passes. Without
		# them this measures a MORE PERMISSIVE world than the game's, which
		# is exactly how the first run of this probe reported every field
		# intact while the report said otherwise.
		var reserved: Dictionary = renderer._landmark_cells(settlement.landmarks, TILE_SIZE)
		var fields: Dictionary = renderer._fenced_farm_fields(coord, CHUNK_SIZE, world, reserved)
		for origin in fields:
			farmhouses += 1
			var size: int = (fields[origin] as Array).size()
			field_sizes[size] = int(field_sizes.get(size, 0)) + 1
			if size == 0:
				without_a_field += 1
				# Would the SITING rule have accepted this origin? If it
				# would, the two disagree, which is the whole bug: a
				# farmhouse is raised where a field "fits" and then derived
				# against a stricter rule that leaves it nothing.
				var is_buildable = renderer._is_buildable_local(coord, CHUNK_SIZE, world)
				var is_occupied = renderer._is_occupied_local(coord, CHUNK_SIZE, world)
				var sited_here: bool = renderer._field_fits_at(
					origin, coord, CHUNK_SIZE, world, is_buildable, is_occupied
				)
				if sited_here:
					siting_disagreed += 1
				if offenders.size() < 8:
					offenders.append("chunk %s farmhouse at %s (of %d here) -- siting said it fits: %s"
						% [str(coord), str(origin), fields.size(), str(sited_here)])
		parent.queue_free()

	print("villages with at least one farmer: %d" % villages)
	print("farmhouses raised:                 %d" % farmhouses)
	print("farmhouses with NO field at all:   %d  (%.1f%%)" % [
		without_a_field, 100.0 * float(without_a_field) / maxf(float(farmhouses), 1.0),
	])
	print("...of which siting said a field FITS: %d  <- the two rules disagree" % siting_disagreed)
	print()
	print("field size -> how many farmhouses")
	for size in field_sizes:
		print("  %d cells: %d" % [size, field_sizes[size]])
	print()
	for line in offenders:
		print("  " + line)
	quit()
