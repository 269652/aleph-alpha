extends SceneTree

## The whole village, drawn on the grid: what does a player actually see?
## Reported with a screenshot of rails scattered over half the village.
## Uses the REAL settlement generator and the REAL VillageRenderer against a
## stub world (flat ground), so the layout, the farmhouses, the fields and
## every rail are the ones the game would place.

const CHUNK_SIZE := 32
const TILE_SIZE := 16

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
	var BuildingCatalog = load("res://src/gameplay/building_catalog.gd")
	var TerrainRenderer = load("res://src/rendering/terrain_renderer.gd")
	var generator = SettlementGenerator.new()

	var shown := 0
	for x in 400:
		if shown >= 2:
			break
		var coord := Vector2i(x, 3)
		if not generator.has_settlement_at(coord, "grassland"):
			continue
		var settlement = generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
		var farms := 0
		for npc in settlement.npcs:
			if VillageFarm.crop_for(npc.occupation) != "":
				farms += 1
		if farms < 2:
			continue
		shown += 1
		var world = StubWorld.new()
		var parent := Node2D.new()
		root.add_child(parent)
		var renderer = VillageRenderer.new()
		var spawned = renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

		var glyphs := {}
		for cell in world.built:
			var tile: String = world.built[cell]
			var local: Vector2i = (cell as Vector2i) - coord * CHUNK_SIZE
			if tile == TerrainRenderer.ROAD_TILE_ID:
				glyphs[local] = ":"
			elif VillageFarm.is_fence_tile(tile):
				glyphs[local] = {
					"farm_fence_north": "^", "farm_fence_south": "v",
					"farm_fence_east": ">", "farm_fence_west": "<",
				}.get(tile, "+")  # every corner, whatever it is called, is a post
		for call in world.place_calls:
			var letter := "B"
			if call["building_id"] == VillageFarm.FARM_BUILDING_ID:
				letter = "F"
			elif call["building_id"].begins_with("house"):
				letter = "h"
			for cell in BuildingCatalog.footprint_cells(call["building_id"], call["origin_local"]):
				glyphs[cell] = letter
		var beds := 0
		for node in spawned:
			if node.get("field_cells") == null:
				continue
			for g in node.field_cells:
				glyphs[(g as Vector2i) - coord * CHUNK_SIZE] = "#"
				beds += 1

		print("== chunk ", coord, "  villagers ", settlement.npcs.size(), "  farmers ", farms, "  beds ", beds)
		for y in CHUNK_SIZE:
			var row := "  "
			for cx in CHUNK_SIZE:
				row += glyphs.get(Vector2i(cx, y), ".")
			print(row)
		parent.free()
	quit()
