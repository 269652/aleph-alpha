extends GutTest

## VillageRenderer: chunk-based spawn/despawn of a settlement's real
## whole-building houses + NPC markers (docs/concept/building.md
## "Buildings are entities; interiors are scenes"), driven by
## SettlementGenerator (who) and VillageLayout (where) -- same "one call
## per chunk load, deterministic, returns spawned nodes for the caller to
## free" shape as TreeRenderer/CreatureRenderer/FishRenderer.

const VillageRenderer = preload("res://src/rendering/village_renderer.gd")
const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const TILE_SIZE := 16
const CHUNK_SIZE := 32

var renderer: VillageRenderer
var parent: Node2D
var _generator := SettlementGenerator.new()


## Duck-typed EarthChunkManager stand-in: records every place_building/
## build_at_global call instead of actually touching a chunk, and answers
## is_buildable_terrain_at/modification_at_global from its own small,
## test-controlled state (biome/water_cells/unbuildable_cells) -- mirrors
## the real occupancy contract (an already-placed building's WHOLE
## footprint reads as occupied, not just its anchor cell) so
## VillageLayout's own "no two plots overlap" behaviour is exercised for
## real here, not just re-asserted.
class StubWorld:
	var place_calls: Array = []
	var road_cells: Dictionary = {}  # Vector2i -> true
	var biome := "grassland"
	var water_cells: Dictionary = {}
	var unbuildable_cells: Dictionary = {}
	var occupied_cells: Dictionary = {}  # pre-seeded occupancy, e.g. an existing structure

	## Mirrors the REAL EarthChunkManager.place_building's own occupancy
	## check exactly (footprint cells AND the doorstep must all be
	## unoccupied, checked against the SAME occupied_cells dict
	## build_at_global also writes into) -- a stub that always returned
	## true regardless of prior occupancy could never have caught a real
	## ordering bug: VillageRenderer used to stamp road cells (which
	## include every plot's own doorstep) BEFORE calling place_building,
	## so every real placement refused itself over its own front step.
	## occupied_cells is GLOBAL-keyed throughout this stub (matching
	## build_at_global/modification_at_global and
	## test_a_building_already_occupying_ground_keeps_later_ones_off_it's
	## own pre-seeding) -- footprint_cells/doorstep_of return LOCAL cells,
	## so every key here is translated through chunk_coord first; keying
	## by the raw local cell instead would never collide with what
	## build_at_global writes (global), silently defeating this whole
	## check for any chunk_coord other than the origin.
	func place_building(
		chunk_coord: Vector2i, origin_local: Vector2i, building_id: String,
		facing: Vector2i, seed_value: int, owner_household_id: String,
		occupation: String = "", resident_seed: int = 0
	) -> bool:
		var footprint_cells: Array = BuildingCatalog.footprint_cells(building_id, origin_local)
		var required_cells: Array = footprint_cells.duplicate()
		required_cells.append(origin_local + BuildingCatalog.doorstep_of(building_id))
		for cell in required_cells:
			var g: Vector2i = chunk_coord * CHUNK_SIZE + cell
			if occupied_cells.get(g, "") != "":
				return false
		place_calls.append({
			"chunk_coord": chunk_coord, "origin_local": origin_local, "building_id": building_id,
			"facing": facing, "seed": seed_value, "owner_household_id": owner_household_id,
			"occupation": occupation, "resident_seed": resident_seed,
		})
		for cell in footprint_cells:
			occupied_cells[chunk_coord * CHUNK_SIZE + cell] = building_id
		return true

	## Mirrors the REAL EarthChunkManager.buildings_in_chunk's own record
	## shape ({"id","facing","seed","condition","progress","owner_household_id",
	## "occupation","resident_seed","chunk_coord","origin_local"}), derived
	## from place_calls -- the SAME place_building already records -- so a
	## second spawn_village call against this SAME StubWorld sees its own
	## earlier placements exactly as a real reload would.
	func buildings_in_chunk(chunk_coord: Vector2i) -> Array:
		var out: Array = []
		for call in place_calls:
			if call["chunk_coord"] != chunk_coord:
				continue
			out.append({
				"id": call["building_id"], "facing": call["facing"], "seed": call["seed"],
				"condition": 1.0, "progress": 1.0, "owner_household_id": call["owner_household_id"],
				"occupation": call.get("occupation", ""), "resident_seed": call.get("resident_seed", 0),
				"chunk_coord": chunk_coord, "origin_local": call["origin_local"],
			})
		return out

	## Mirrors the REAL EarthChunkManager.set_building_resident: rewrites the
	## two resident fields on the matching placed record (false when nothing
	## stands there), so a reload's backfill shows up in buildings_in_chunk
	## exactly as the real persisted record would.
	var resident_calls: Array = []
	func set_building_resident(chunk_coord: Vector2i, origin_local: Vector2i, occupation: String, resident_seed: int) -> bool:
		for call in place_calls:
			if call["chunk_coord"] == chunk_coord and call["origin_local"] == origin_local:
				call["occupation"] = occupation
				call["resident_seed"] = resident_seed
				resident_calls.append({"origin_local": origin_local, "occupation": occupation, "resident_seed": resident_seed})
				return true
		return false

	func build_at_global(x: int, y: int, tile_id: String) -> bool:
		road_cells[Vector2i(x, y)] = tile_id
		# Mirrors the REAL EarthChunkManager.build_at_global exactly:
		# chunk.modifications[local] = tile_id, unconditionally, with no
		# occupancy check of its own (see that function's own doc
		# comment). A stub that only recorded this into a SEPARATE dict
		# from the one modification_at_global reads let a real ordering
		# bug slip through undetected: stamping a plot's own doorstep as
		# a road cell BEFORE calling place_building made every real
		# placement refuse itself over its own front step, since
		# place_building's occupancy check reads modification_at_global.
		occupied_cells[Vector2i(x, y)] = tile_id
		return true

	func biome_at_global(x: int, y: int) -> String:
		if water_cells.has(Vector2i(x, y)):
			return "ocean"
		return biome

	func is_buildable_terrain_at(x: int, y: int) -> bool:
		if biome_at_global(x, y) == "ocean":
			return false
		return not unbuildable_cells.has(Vector2i(x, y))

	func modification_at_global(x: int, y: int) -> String:
		return occupied_cells.get(Vector2i(x, y), "")

	var founded_calls: Array = []
	func record_settlement_founded_if_new(chunk_coord: Vector2i, npcs: Array, plots: Array = []) -> void:
		founded_calls.append({"chunk_coord": chunk_coord, "npcs": npcs, "plots": plots})


func before_each():
	renderer = VillageRenderer.new()
	parent = Node2D.new()


func after_each():
	parent.free()


func _find_settlement_chunk(biome: String) -> Vector2i:
	for x in 400:
		var coord := Vector2i(x, 0)
		if _generator.has_settlement_at(coord, biome):
			return coord
	fail_test("no settlement chunk found within 400 chunks")
	return Vector2i.ZERO


## A chunk whose fixed 5-villager roster happens to include at least one
## merchant -- occupation is seeded per villager, so not every settlement
## chunk has one.
func _find_settlement_chunk_with_merchant(biome: String) -> Vector2i:
	for x in 400:
		var coord := Vector2i(x, 2)  # a row of its own, distinct from the other _find_* helpers'
		if not _generator.has_settlement_at(coord, biome):
			continue
		var settlement := _generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
		for npc in settlement.npcs:
			if npc.occupation == "merchant":
				return coord
	fail_test("no settlement chunk with a merchant found within 400 chunks")
	return Vector2i.ZERO


func _workspot_prop_count(settlement: Dictionary) -> int:
	var count := 0
	for npc in settlement.npcs:
		var work_tag: String = NpcIdentity.WORK_LOCATION_BY_OCCUPATION.get(npc.occupation, "")
		if work_tag != "" and not settlement.landmarks.has(work_tag):
			count += 1
	return count


func _find_non_settlement_chunk(biome: String) -> Vector2i:
	for x in 400:
		var coord := Vector2i(x, 1)
		if not _generator.has_settlement_at(coord, biome):
			return coord
	fail_test("no non-settlement chunk found within 400 chunks")
	return Vector2i.ZERO


func test_spawns_nothing_on_a_chunk_without_a_settlement():
	var coord := _find_non_settlement_chunk("grassland")
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland")
	assert_true(spawned.is_empty())


func test_spawns_nothing_on_an_uninhabitable_biome_even_if_the_chunk_would_otherwise_qualify():
	var coord := _find_settlement_chunk("grassland")
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "ocean")
	assert_true(spawned.is_empty())


func test_spawns_landmarks_and_npc_markers_on_a_settlement_chunk():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var npc_count := 0
	var landmark_count := 0
	for node in spawned:
		if node is NpcMarker:
			npc_count += 1
		elif node.get_meta("landmark_id", "") != "":
			landmark_count += 1
	assert_eq(npc_count, SettlementGenerator.POPULATION)
	assert_gte(landmark_count, 3, "well, stall, gate at minimum")


# -- houses are real whole-building entities (docs/concept/building.md) -----

func test_spawn_village_places_a_real_building_for_every_villager():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_gt(world.place_calls.size(), 0, "at least some villagers should get a real building")
	assert_lte(world.place_calls.size(), SettlementGenerator.POPULATION)
	for call in world.place_calls:
		assert_true(BuildingCatalog.has_building(call["building_id"]), call["building_id"])
		assert_eq(call["chunk_coord"], coord)


## Regression: real gameplay placed ZERO buildings in every real village
## after the whole-building rewrite, entirely masked in this suite until a
## real end-to-end EarthChunkManager probe caught it -- VillageRenderer
## stamped road cells (which include every plot's OWN doorstep) before
## calling place_building for that same plot, so place_building's real
## occupancy check (which reads modification_at_global, the SAME dict
## build_at_global writes into) refused every single placement over its
## own front step. StubWorld's place_building used to always return true
## regardless of prior occupancy, so this could never have failed here --
## both the stub (now a faithful occupancy check) and this explicit test
## exist so the ordering can never silently regress again.
func test_a_buildings_own_doorstep_road_cell_never_blocks_its_own_placement():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_gt(world.place_calls.size(), 0, "every real village must place at least one real building")
	assert_eq(world.place_calls.size(), SettlementGenerator.POPULATION, "a village on ample clear grassland should house everyone")


## Regression: a real settlement chunk grew a SECOND set of houses on top
## of the first every time it reloaded, because chunk.buildings persists
## but VillageLayout had no idea a fresh layout attempt's own preferred
## spots were already its OWN earlier placements -- it just found new
## clear ground nearby and placed there too. place_building itself is
## never called a second time for a chunk that already has real buildings
## (see VillageRenderer._recover_existing_village); a reload must reuse
## the exact same place_calls, not add to them.
func test_reloading_a_settlement_does_not_place_a_second_set_of_buildings():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var placed_after_first_load := world.place_calls.size()
	assert_gt(placed_after_first_load, 0, "precondition: the first load placed real buildings")

	# A second parent, mirroring how a real chunk reload rebuilds the
	# ephemeral render tree fresh (NPCs/landmarks are never persisted) --
	# only place_calls (the persisted-equivalent state) must stay put.
	var second_parent := Node2D.new()
	renderer.spawn_village(second_parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_eq(world.place_calls.size(), placed_after_first_load, "a reload must not place any NEW buildings")
	second_parent.free()


func test_every_placed_building_faces_south_onto_a_real_road_cell():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_gt(world.place_calls.size(), 0, "precondition")
	for call in world.place_calls:
		assert_eq(call["facing"], Vector2i(0, 1))
		var doorstep: Vector2i = call["origin_local"] + BuildingCatalog.doorstep_of(call["building_id"])
		var doorstep_global: Vector2i = coord * CHUNK_SIZE + doorstep
		assert_true(world.road_cells.has(doorstep_global), "doorstep %s should be a real road cell" % str(doorstep_global))


## Streets are the Road tier (docs/concept/infrastructure.md) -- a LAID
## surface with its own tile -- not the worn TRAIL they used to be drawn as.
func test_every_street_cell_is_laid_as_the_real_road_tile():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_gt(world.road_cells.size(), 0, "precondition: streets were laid")
	for cell in world.road_cells:
		assert_eq(world.road_cells[cell], TerrainRenderer.ROAD_TILE_ID, str(cell))


func test_no_two_placed_buildings_ever_overlap():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var claimed := {}
	for call in world.place_calls:
		for cell in BuildingCatalog.footprint_cells(call["building_id"], call["origin_local"]):
			assert_false(claimed.has(cell), "cell %s claimed twice" % str(cell))
			claimed[cell] = true


func test_npc_home_position_is_its_own_buildings_doorstep_not_the_raw_ring_anchor():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_gt(world.place_calls.size(), 0, "precondition")
	var settlement := _generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
	var markers: Array = []
	for node in spawned:
		if node is NpcMarker:
			markers.append(node)
	# At least one housed villager's marker must NOT sit at its own old
	# ring anchor -- it should be standing at its building's real doorstep.
	var any_moved := false
	for i in markers.size():
		if markers[i].home_position != settlement.house_positions[i]:
			any_moved = true
	assert_true(any_moved, "at least one villager should have a real doorstep home, not the raw ring anchor")


func test_a_building_is_never_placed_in_water():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	world.biome = "ocean"  # the whole chunk reads as water
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_true(world.place_calls.is_empty(), "no dry ground anywhere -- no villager should get a building forced into water")
	assert_false(spawned.is_empty(), "the village itself (landmarks, NPCs) still spawns")


func test_a_building_is_never_placed_where_the_real_terrain_check_refuses():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	for x in CHUNK_SIZE:
		for y in CHUNK_SIZE:
			world.unbuildable_cells[coord * CHUNK_SIZE + Vector2i(x, y)] = true
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_true(world.place_calls.is_empty(), "an entirely unbuildable chunk should place nothing")


func test_a_building_already_occupying_ground_keeps_later_ones_off_it():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	# Occupy almost the entire chunk, leaving only a small real pocket free.
	for x in CHUNK_SIZE:
		for y in CHUNK_SIZE:
			var cell := coord * CHUNK_SIZE + Vector2i(x, y)
			if not (x >= 14 and x < 20 and y >= 14 and y < 18):
				world.occupied_cells[cell] = "existing_structure"
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	for call in world.place_calls:
		for cell in BuildingCatalog.footprint_cells(call["building_id"], call["origin_local"]):
			var global_cell: Vector2i = coord * CHUNK_SIZE + cell
			assert_ne(world.occupied_cells.get(global_cell, ""), "existing_structure", str(global_cell))


func test_spawn_village_does_not_crash_without_a_world():
	var coord := _find_settlement_chunk("grassland")
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland")
	assert_false(spawned.is_empty(), "landmarks and NPCs still spawn with no world")
	var npc_count := 0
	for node in spawned:
		if node is NpcMarker:
			npc_count += 1
	assert_eq(npc_count, SettlementGenerator.POPULATION, "every villager still gets a marker, falling back to their ring anchor as home")


func test_merchant_villagers_get_a_personal_trading_stand_near_their_own_house():
	var coord := _find_settlement_chunk_with_merchant("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var stall_count := 0
	for node in spawned:
		if node.get_meta("landmark_id", "") == "stall":
			stall_count += 1
	assert_gte(stall_count, 2, "the shared village stall plus at least one merchant's own personal stand")


func test_non_merchant_villagers_do_not_get_a_personal_trading_stand():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var settlement := _generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
	var merchant_count := 0
	for npc in settlement.npcs:
		if npc.occupation == "merchant":
			merchant_count += 1
	var stall_count := 0
	for node in spawned:
		if node.get_meta("landmark_id", "") == "stall":
			stall_count += 1
	assert_eq(stall_count, 1 + merchant_count, "one shared stall plus exactly one per merchant")


func test_farmer_blacksmith_fisher_and_herbalist_each_get_their_own_workspot_prop():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var settlement := _generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
	var expected := _workspot_prop_count(settlement)
	var prop_ids := ["field", "forge", "dock", "garden", "hunting_ground"]
	var found := 0
	for node in spawned:
		if prop_ids.has(node.get_meta("landmark_id", "")):
			found += 1
	assert_eq(found, expected)


func test_workspot_props_land_at_the_villagers_own_workspot_position():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var markers: Array = []
	for node in spawned:
		if node is NpcMarker:
			markers.append(node)
	var prop_ids := ["field", "forge", "dock", "garden", "hunting_ground"]
	for node in spawned:
		var landmark_id: String = node.get_meta("landmark_id", "")
		if not prop_ids.has(landmark_id):
			continue
		var matched := false
		for marker in markers:
			if marker.workspot_position == node.position:
				matched = true
		assert_true(matched, "%s prop should sit at some villager's own workspot_position" % landmark_id)


func test_villagers_are_given_the_world_so_they_can_tell_when_theyre_in_water():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	for node in spawned:
		if node is NpcMarker:
			assert_not_null(node._world, "%s should have been given the world" % node.identity.npc_name)


## A landmark_id can legitimately tag MORE than one spawned node -- e.g.
## "stall" is both the settlement's own shared landmark AND the tag
## VillageRenderer gives a merchant's personal trading stand (a separate
## node at the merchant's own stand position). So this only requires that
## SOME node carrying the id sits at the shared landmark's position, not
## that EVERY node carrying it does.
func test_landmarks_are_rendered_as_sprites_at_their_positions():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var settlement := _generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
	for landmark_id in settlement.landmarks:
		var found := false
		for node in spawned:
			if node.get_meta("landmark_id", "") == landmark_id and node is Sprite2D:
				if node.position == settlement.landmarks[landmark_id]:
					found = true
		assert_true(found, landmark_id)


func test_spawned_npc_markers_have_an_identity_and_a_schedule_source():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	for node in spawned:
		if node is NpcMarker:
			assert_not_null(node.identity)
			assert_ne(node.identity.npc_name, "")


func test_spawned_npc_markers_know_the_settlements_shared_landmarks():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var settlement := _generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
	for node in spawned:
		if node is NpcMarker:
			assert_eq(node.landmarks, settlement.landmarks)


func test_positions_are_deterministic_for_the_same_chunk():
	var coord := _find_settlement_chunk("grassland")
	var world_a := StubWorld.new()
	var parent_a := Node2D.new()
	add_child(parent_a)
	renderer.spawn_village(parent_a, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world_a)

	var renderer_b := VillageRenderer.new()
	var world_b := StubWorld.new()
	var parent_b := Node2D.new()
	add_child(parent_b)
	renderer_b.spawn_village(parent_b, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world_b)

	assert_eq(world_a.place_calls.size(), world_b.place_calls.size())
	for i in world_a.place_calls.size():
		assert_eq(world_a.place_calls[i]["origin_local"], world_b.place_calls[i]["origin_local"])
		assert_eq(world_a.place_calls[i]["building_id"], world_b.place_calls[i]["building_id"])
	parent_a.free()
	parent_b.free()


# -- NPCs are whole people, not a torso and a head -------------------------

func test_villagers_are_built_from_the_same_character_view_as_the_player():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	for node in spawned:
		if node is NpcMarker:
			var has_view := false
			for child in node.get_children():
				if child.has_method("apply_appearance"):
					has_view = true
			assert_true(has_view, "%s should carry a real CharacterView" % node.identity.npc_name)


func test_npc_shadow_is_scaled_down_to_match_the_shrunk_character_view():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	for node in spawned:
		if node is NpcMarker:
			assert_gte(node.get_child_count(), 2, "%s should carry a shadow plus a character view" % node.identity.npc_name)
			var has_shadow := false
			for child in node.get_children():
				if child is Sprite2D and not child.has_method("apply_appearance"):
					has_shadow = true
			assert_true(has_shadow, "%s should have a real drop shadow sprite" % node.identity.npc_name)


# -- needs/local production economy (docs/concept/npc.md "Needs and the
# -- local production economy") -----------------------------------------

func test_every_spawned_villager_has_an_economy():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	for node in spawned:
		if node is NpcMarker:
			assert_not_null(node.economy, "%s should have a real economy" % node.identity.npc_name)
			assert_not_null(node.economy.market, "%s's economy should carry the real village market" % node.identity.npc_name)


func test_every_villager_of_the_same_settlement_shares_one_village_market():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var markets := {}
	for node in spawned:
		if node is NpcMarker:
			markets[node.economy.market] = true
	assert_eq(markets.size(), 1, "every villager in one settlement should share the identical market instance")


# -- founding is reported to the world, once ---------------------------------

func test_spawning_a_settlement_reports_it_founded():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_eq(world.founded_calls.size(), 1)
	assert_eq(world.founded_calls[0]["chunk_coord"], coord)
	assert_eq(world.founded_calls[0]["npcs"].size(), SettlementGenerator.POPULATION)


## The real VillageLayout plots (docs/concept/building.md "One house id")
## reach the founding call, not an empty default -- EarthChunkManager needs
## these to grant each villager's REAL house ownership through a
## ConstructionProject rather than a synthetic per-index id. Every plot's
## building_index must be a real, in-range villager index, and there must
## be at least one (this settlement chunk has real buildable ground, so
## some subset of villagers should always get a real plot).
func test_founding_is_reported_with_the_real_village_layout_plots():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var plots: Array = world.founded_calls[0]["plots"]
	assert_eq(plots.size(), world.place_calls.size(), "one plot per real placed building, no more no less")
	assert_gt(plots.size(), 0, "precondition: some villager should have gotten a real plot")
	for plot in plots:
		assert_between(plot["building_index"], 0, SettlementGenerator.POPULATION - 1)


func test_a_chunk_with_no_settlement_reports_nothing():
	var coord := _find_non_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_true(world.founded_calls.is_empty())


# -- who lives here: the record carries its own villager --------------------
#
# docs/concept/building.md "Entering": the resident's REAL occupation drives
# the interior, and "Residents inside" has to find the villager whose house
# this is. NPCs are regenerated on every load; only the building persists,
# so the building itself must remember its villager (occupation + the
# NpcIdentity seed), passed at placement from the exact villager the plot
# was laid out for.

func test_each_placed_building_records_its_own_villagers_occupation_and_seed():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var npcs: Array = world.founded_calls[0]["npcs"]
	var plots: Array = world.founded_calls[0]["plots"]
	assert_gt(world.place_calls.size(), 0, "precondition: real buildings were placed")
	for i in world.place_calls.size():
		var call: Dictionary = world.place_calls[i]
		var building_index: int = plots[i]["building_index"]
		assert_eq(call["occupation"], npcs[building_index].occupation, "building %d" % i)
		assert_eq(call["resident_seed"], npcs[building_index].seed_value, "building %d" % i)
		assert_ne(call["occupation"], "", "a placed village house is never anonymous")


## A save from before the record carried a resident (resident_seed 0)
## heals on its next reload: the recover path matches each villager to
## their own house by the per-index seed exactly as before, and writes
## the missing fields back through set_building_resident. A record that
## already has its resident is left alone.
func test_reloading_backfills_a_resident_onto_records_that_lack_one():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_gt(world.place_calls.size(), 0, "precondition: real buildings were placed")
	# Simulate the old on-disk shape: every record forgets its resident.
	var expected_by_origin := {}
	for call in world.place_calls:
		expected_by_origin[call["origin_local"]] = {"occupation": call["occupation"], "resident_seed": call["resident_seed"]}
		call["occupation"] = ""
		call["resident_seed"] = 0

	var second_parent := Node2D.new()
	renderer.spawn_village(second_parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	assert_eq(world.resident_calls.size(), world.place_calls.size(), "every anonymous record gets its villager back")
	for call in world.resident_calls:
		var expected: Dictionary = expected_by_origin[call["origin_local"]]
		assert_eq(call["occupation"], expected["occupation"], str(call["origin_local"]))
		assert_eq(call["resident_seed"], expected["resident_seed"], str(call["origin_local"]))

	# Third load: nothing left to heal.
	var third_parent := Node2D.new()
	renderer.spawn_village(third_parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_eq(world.resident_calls.size(), world.place_calls.size(), "a record that already knows its villager is left alone")
	second_parent.free()
	third_parent.free()


class WorldWithNoFoundingMethod:
	func place_building(_a, _b, _c, _d, _e, _f, _g = "", _h = 0) -> bool:
		return true
	func is_buildable_terrain_at(_x: int, _y: int) -> bool:
		return true
	func modification_at_global(_x: int, _y: int) -> String:
		return ""


func test_a_world_with_no_such_method_does_not_crash():
	var coord := _find_settlement_chunk("grassland")
	var world := WorldWithNoFoundingMethod.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_false(spawned.is_empty())
