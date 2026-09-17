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
const VillageLayout = preload("res://src/world/village_layout.gd")
const VillageFarm = preload("res://src/gameplay/village_farm.gd")
const VillagePond = preload("res://src/gameplay/village_pond.gd")
const VillageSawmill = preload("res://src/gameplay/village_sawmill.gd")
const ProceduralLandmarkSprite = preload("res://src/rendering/procedural_landmark_sprite.gd")

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
	## Every cell this village really BUILT, global -> tile id -- roads, and
	## now the rails a farmhouse fences its beds with (docs/concept/
	## village_farms.md). Named for what it holds: build_at_global records
	## whatever it is given, and a test that wants only the streets filters
	## for the road tile (see _road_cells_of).
	var built_tiles: Dictionary = {}
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
		built_tiles[Vector2i(x, y)] = tile_id
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

	## Real forest cells, GLOBAL-keyed like everything else in this stub.
	## A village never sites IN the forest (the real rule --
	## EarthChunkManager.is_buildable_ground_at refuses the forest biome),
	## so these read as forest to biome_at_global AND as unbuildable, the
	## same pair of answers the real world gives.
	var forest_cells: Dictionary = {}

	func biome_at_global(x: int, y: int) -> String:
		if water_cells.has(Vector2i(x, y)):
			return "ocean"
		if forest_cells.has(Vector2i(x, y)):
			return "forest"
		return biome

	## The one water rule (see EarthChunkManager.is_water_at_global) -- what
	## a village's own siting really asks, now that it fells the trees it
	## needs rather than refusing ground over them. Mirrors the real one on
	## BOTH of its sources: an explicitly wet cell, and an ocean biome --
	## a stub that knew only the first let a village happily settle a chunk
	## that reads as open sea.
	func is_water_at_global(x: int, y: int) -> bool:
		return water_cells.has(Vector2i(x, y)) or biome_at_global(x, y) == "ocean"

	func is_buildable_terrain_at(x: int, y: int) -> bool:
		var cell := Vector2i(x, y)
		if biome_at_global(x, y) == "ocean" or forest_cells.has(cell):
			return false
		return not unbuildable_cells.has(cell)

	func modification_at_global(x: int, y: int) -> String:
		return occupied_cells.get(Vector2i(x, y), "")

	## Every tile stock_pond_at was called for -- the real
	## EarthChunkManager's own entry point for putting a fisher's stocking
	## into the water they just dug.
	var stocked_ponds: Array = []

	func stock_pond_at(x: int, y: int) -> void:
		stocked_ponds.append(Vector2i(x, y))

	## Mirrors EarthChunkManager.place_building_over_roads: the civic plot
	## is the paved square itself, so an ordinary place_building would
	## refuse it over its own paving.
	func place_building_over_roads(
		chunk_coord: Vector2i, origin_local: Vector2i, building_id: String, seed_value: int,
		owner_household_id: String
	) -> bool:
		if refuse_civic:
			return false
		for cell in BuildingCatalog.footprint_cells(building_id, origin_local):
			occupied_cells.erase(chunk_coord * CHUNK_SIZE + cell)
		occupied_cells.erase(chunk_coord * CHUNK_SIZE + origin_local + BuildingCatalog.doorstep_of(building_id))
		return place_building(chunk_coord, origin_local, building_id, Vector2i(0, 1), seed_value, owner_household_id)

	var founded_calls: Array = []
	func record_settlement_founded_if_new(chunk_coord: Vector2i, npcs: Array, plots: Array = []) -> void:
		founded_calls.append({"chunk_coord": chunk_coord, "npcs": npcs, "plots": plots})

	## The settlement's REAL household count (see EarthChunkManager's own
	## method of this name) -- how many villagers actually live here, which
	## grows past SettlementGenerator.POPULATION as households move in. 0
	## means "never recorded", the founding-roster fallback.
	var household_count := 0
	func household_count_for_settlement(_settlement_id: String) -> int:
		return household_count

	## Stands in for a village founded before the hall was placed at
	## founding at all -- see the older-village healing test.
	var refuse_civic := false

	## villager seed -> the LOCAL origin of the house their household owns,
	## mirroring the real EarthChunkManager.house_origin_for_villager. null
	## for a villager who owns nothing here.
	var house_origin_by_villager: Dictionary = {}
	func house_origin_for_villager(_chunk_coord: Vector2i, villager_seed: int):
		return house_origin_by_villager.get(villager_seed)


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
## hunter -- the occupation whose workspot prop used to be drawn as a
## second well (see test_no_prop_but_the_villages_own_well_is_drawn_as_one).
func _find_settlement_chunk_with_hunter(biome: String) -> Vector2i:
	for x in 400:
		var coord := Vector2i(x, 3)  # a row of its own, like the merchant helper below
		if not _generator.has_settlement_at(coord, biome):
			continue
		var settlement := _generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
		for npc in settlement.npcs:
			if npc.occupation == "hunter":
				return coord
	fail_test("no settlement chunk with a hunter found within 400 chunks")
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


## Only the HOUSES a village placed. A village also places its civic seat
## and, where there is timber, its sawmill -- real buildings, but not
## anybody's home, and every test below that counts "one per villager"
## means houses.
func _house_calls(world: StubWorld) -> Array:
	var houses: Array = []
	for call in world.place_calls:
		if BuildingCatalog.capacity_of(call["building_id"]) > 0:
			houses.append(call)
	return houses


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
	assert_gt(_house_calls(world).size(), 0, "at least some villagers should get a real building")
	assert_lte(_house_calls(world).size(), SettlementGenerator.POPULATION)
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
	assert_gt(_house_calls(world).size(), 0, "every real village must place at least one real building")
	assert_eq(_house_calls(world).size(), SettlementGenerator.POPULATION, "a village on ample clear grassland should house everyone")


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
		assert_true(world.built_tiles.has(doorstep_global), "doorstep %s should be a real road cell" % str(doorstep_global))


## A reload (the settlement's buildings already persisted) must not grow
## the street network either -- the plaza and streets are laid once.
func test_reloading_a_settlement_lays_no_new_road_cells():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var roads_after_first_load := world.built_tiles.size()
	assert_gt(roads_after_first_load, 0, "precondition")
	var second_parent := Node2D.new()
	renderer.spawn_village(second_parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_eq(world.built_tiles.size(), roads_after_first_load)
	second_parent.free()


## An older save's village (buildings persisted, but laid out before the
## plaza existed) gets its square paved on reload where the square is
## actually clear -- re-derived from VillageLayout.skeleton, nothing
## persisted -- so old villages catch up to the layout without a wipe.
func test_a_reloaded_older_village_gets_its_plaza_paved_where_the_square_is_clear():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var skeleton: Dictionary = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(coord))
	var plaza: Rect2i = skeleton["plaza"]
	# Simulate the old on-disk shape: the buildings persist, the plaza never
	# existed. (Only meaningful when this village actually got a plaza.)
	var plaza_cells: Array = []
	for y in range(plaza.position.y, plaza.end.y):
		for x in range(plaza.position.x, plaza.end.x):
			plaza_cells.append(coord * CHUNK_SIZE + Vector2i(x, y))
	if not world.built_tiles.has(plaza_cells[0]):
		pass_test("this fixture village has no plaza (its square is not clear) -- nothing to catch up")
		return
	for g in plaza_cells:
		world.built_tiles.erase(g)
		world.occupied_cells.erase(g)

	var second_parent := Node2D.new()
	renderer.spawn_village(second_parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	for g in plaza_cells:
		assert_eq(world.built_tiles.get(g, ""), TerrainRenderer.ROAD_TILE_ID, "plaza cell %s must be paved on reload" % str(g))
	second_parent.free()


## ...but never over a house: an old village whose houses stand where the
## square would go keeps its square unpaved, rather than paving through a
## building.
func test_a_reloaded_older_village_keeps_its_square_unpaved_where_a_building_stands_on_it():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var skeleton: Dictionary = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(coord))
	var plaza: Rect2i = skeleton["plaza"]
	var plaza_cells: Array = []
	for y in range(plaza.position.y, plaza.end.y):
		for x in range(plaza.position.x, plaza.end.x):
			plaza_cells.append(coord * CHUNK_SIZE + Vector2i(x, y))
	if not world.built_tiles.has(plaza_cells[0]):
		pass_test("this fixture village has no plaza -- nothing to protect")
		return
	for g in plaza_cells:
		world.built_tiles.erase(g)
		world.occupied_cells.erase(g)
	# An old house stands on one square cell.
	world.occupied_cells[plaza_cells[5]] = "house_small"

	var second_parent := Node2D.new()
	renderer.spawn_village(second_parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	for g in plaza_cells:
		assert_ne(world.built_tiles.get(g, ""), TerrainRenderer.ROAD_TILE_ID, "must not pave a square a house stands on (%s)" % str(g))
	second_parent.free()


## Streets are the Road tier (docs/concept/infrastructure.md) -- a LAID
## surface with its own tile -- not the worn TRAIL they used to be drawn as.
func test_every_street_cell_is_laid_as_the_real_road_tile():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_gt(world.built_tiles.size(), 0, "precondition: something was built")
	var streets := 0
	for cell in world.built_tiles:
		var tile: String = world.built_tiles[cell]
		# A village builds three things onto its own ground: streets, the
		# rails a farmhouse fences its beds with (docs/concept/
		# village_farms.md) and the water a fisher digs (docs/concept/
		# village_ponds.md). Everything that is neither a rail nor a pond is
		# a street, and every street is the real Road tile.
		if VillageFarm.is_fence_tile(tile) or VillagePond.is_pond_tile(tile):
			continue
		assert_eq(tile, TerrainRenderer.ROAD_TILE_ID, str(cell))
		streets += 1
	assert_gt(streets, 0, "precondition: streets were laid")


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


## REVISED (reported in play: "Some villages have no houses"). This used to
## assert that a village with nowhere dry to build still spawned its
## landmarks and villagers -- and that is precisely the reported bug, seen
## as a paved square with a stall and a sawmill and not one house. The
## no-building-forced-into-water half is unchanged and still the point; what
## flipped is what happens afterwards. See
## test_a_village_with_nowhere_to_put_a_single_house_is_not_founded_at_all
## for the rule and the measurement behind it.
func test_a_building_is_never_placed_in_water():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	world.biome = "ocean"  # the whole chunk reads as water
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_true(world.place_calls.is_empty(), "no dry ground anywhere -- no villager should get a building forced into water")
	assert_true(spawned.is_empty(), "and nothing else is founded here either -- a village needs somewhere to live")


## A village's own terrain refusal is WATER (see VillageRenderer._is_
## buildable_local): it fells the trees it needs, but it does not drain a
## river. This used to flood the chunk with a generic `unbuildable` flag,
## which conflated the two -- the rule being protected is the water one.
func test_a_building_is_never_placed_where_the_real_terrain_check_refuses():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	for x in CHUNK_SIZE:
		for y in CHUNK_SIZE:
			world.water_cells[coord * CHUNK_SIZE + Vector2i(x, y)] = true
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_true(world.place_calls.is_empty(), "a chunk that is all water should place nothing")
	for g in world.built_tiles:
		assert_false(
			TerrainRenderer.is_road_tile(world.built_tiles[g]), "a road was paved across open water at %s" % str(g)
		)


func test_a_building_already_occupying_ground_keeps_later_ones_off_it():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	# A real occupied block, but not so much of the chunk that no village
	# can settle here at all -- a site that cannot house its whole roster
	# is founded nowhere now, and then this would assert nothing.
	for x in 8:
		for y in CHUNK_SIZE:
			world.occupied_cells[coord * CHUNK_SIZE + Vector2i(x, y)] = "existing_structure"
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_gt(world.place_calls.size(), 0, "precondition: this village really was founded")
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


## Reported live: "there are 3 wells and one stand all over the place."
##
## A village has exactly ONE well, on its own square (docs/concept/
## village_growth.md's street-village grounding). The extra ones were
## HUNTERS. Measured on the real load path rather than deduced
## (tools/probe_village_props.gd, over real settlements near lat 48.6):
## every hunter in the roster stood a prop out behind the houses whose id
## was "hunting_ground" -- correct, and invisible to every existing prop
## test, because all of them check the id. What a player SEES is the
## texture, and "hunting_ground" had no drawing of its own, so it fell
## through ProceduralLandmarkSprite's unknown-id fallback to the WELL's.
## A village rolling two hunters therefore showed three wells.
##
## So this test asserts on what is drawn, not on what it is called: nothing
## in a village but the village's own well may be drawn as a well.
func test_no_prop_but_the_villages_own_well_is_drawn_as_one():
	var coord := _find_settlement_chunk_with_hunter("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	var well_drawing := ProceduralLandmarkSprite.new().generate_image("well").get_data()
	var hunter_props := 0
	for node in spawned:
		var landmark_id: String = node.get_meta("landmark_id", "")
		if landmark_id == "" or landmark_id == "well":
			continue
		if landmark_id == "hunting_ground":
			hunter_props += 1
		assert_ne(
			node.texture.get_image().get_data(), well_drawing,
			"a %s prop is drawn as the village's well" % landmark_id
		)
	assert_gt(hunter_props, 0, "precondition: this village really does have a hunter's own prop standing in it")


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
	assert_eq(plots.size(), _house_calls(world).size(), "one plot per real placed HOUSE, no more no less")
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
	# Houses only: the village also places a civic seat, which has no plot
	# and nobody living in it.
	var houses := _house_calls(world)
	assert_gt(houses.size(), 0, "precondition: real houses were placed")
	for i in houses.size():
		var call: Dictionary = houses[i]
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

	assert_eq(world.resident_calls.size(), _house_calls(world).size(), "every anonymous record gets its villager back")
	for call in world.resident_calls:
		var expected: Dictionary = expected_by_origin[call["origin_local"]]
		assert_eq(call["occupation"], expected["occupation"], str(call["origin_local"]))
		assert_eq(call["resident_seed"], expected["resident_seed"], str(call["origin_local"]))

	# Third load: nothing left to heal.
	var third_parent := Node2D.new()
	renderer.spawn_village(third_parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_eq(world.resident_calls.size(), _house_calls(world).size(), "a record that already knows its villager is left alone")
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


# -- the sawmill at the forest (docs/concept/village_growth.md mechanism 1)
#
# A village's works stand at the timber, not on its square, and a real road
# spur joins them back to the street. Placed at FOUNDING alongside the
# houses, not raised over time: a village the player discovers has been
# standing for years, and its mill is part of the fabric it was founded
# with -- the hall and the later ladder rungs are what it visibly grows
# during play.

## A band of real forest across the chunk's own southern edge, far enough
## from the street that a plot at its edge is genuinely outlying.
func _forest_band(world: StubWorld, coord: Vector2i) -> void:
	for y in range(CHUNK_SIZE - 7, CHUNK_SIZE):
		for x in CHUNK_SIZE:
			world.forest_cells[coord * CHUNK_SIZE + Vector2i(x, y)] = true


func _placed(world: StubWorld, building_id: String) -> Array:
	var out: Array = []
	for call in world.place_calls:
		if call["building_id"] == building_id:
			out.append(call)
	return out


func test_a_village_beside_a_forest_raises_a_sawmill_at_it():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	_forest_band(world, coord)
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	var mills: Array = _placed(world, VillageRenderer.INDUSTRY_BUILDING_ID)
	assert_eq(mills.size(), 1, "every village with timber in reach gets exactly one mill")
	var near_forest := false
	for cell in BuildingCatalog.footprint_cells(VillageRenderer.INDUSTRY_BUILDING_ID, mills[0]["origin_local"]):
		var g: Vector2i = coord * CHUNK_SIZE + cell
		assert_false(world.forest_cells.has(g), "the mill never stands IN the wood it cuts")
		for dy in range(-VillageLayout.INDUSTRY_FOREST_REACH_TILES, VillageLayout.INDUSTRY_FOREST_REACH_TILES + 1):
			for dx in range(-VillageLayout.INDUSTRY_FOREST_REACH_TILES, VillageLayout.INDUSTRY_FOREST_REACH_TILES + 1):
				if world.forest_cells.has(g + Vector2i(dx, dy)):
					near_forest = true
	assert_true(near_forest, "the mill stands at the timber")


func test_the_sawmills_doorstep_is_really_paved_back_to_the_main_street():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	_forest_band(world, coord)
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var mills: Array = _placed(world, VillageRenderer.INDUSTRY_BUILDING_ID)
	assert_eq(mills.size(), 1, "precondition")

	var doorstep: Vector2i = (
		coord * CHUNK_SIZE + mills[0]["origin_local"]
		+ BuildingCatalog.doorstep_of(VillageRenderer.INDUSTRY_BUILDING_ID)
	)
	var street_y: int = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(coord))["street_y"]
	var street_global_y: int = coord.y * CHUNK_SIZE + street_y

	# Flood fill over REAL paved cells only -- the mill must be walkable
	# back to the street on road, not merely near it.
	var seen := {doorstep: true}
	var frontier: Array = [doorstep]
	var reached := false
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		if cell.y == street_global_y:
			reached = true
			break
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next_cell: Vector2i = cell + step
			if seen.has(next_cell):
				continue
			if not TerrainRenderer.is_road_tile(world.built_tiles.get(next_cell, "")):
				continue
			seen[next_cell] = true
			frontier.append(next_cell)
	assert_true(TerrainRenderer.is_road_tile(world.built_tiles.get(doorstep, "")), "the doorstep itself is paved")
	assert_true(reached, "the spur must reach the street, walking only road")


func test_a_village_with_no_timber_in_reach_honestly_raises_no_sawmill():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_eq(_placed(world, VillageRenderer.INDUSTRY_BUILDING_ID).size(), 0)


func test_a_reload_never_raises_a_second_sawmill():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	_forest_band(world, coord)
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_eq(_placed(world, VillageRenderer.INDUSTRY_BUILDING_ID).size(), 1, "one mill per village, across reloads")


## An older village (its houses persisted before the mill existed, or
## founded when no timber stood in reach) gains one on its next visit --
## the same self-healing shape _lay_plaza_if_missing already has.
func test_an_older_village_gains_its_sawmill_on_a_later_visit():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_eq(_placed(world, VillageRenderer.INDUSTRY_BUILDING_ID).size(), 0, "precondition: no timber at founding")
	_forest_band(world, coord)
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_eq(_placed(world, VillageRenderer.INDUSTRY_BUILDING_ID).size(), 1)


func test_the_sawmill_never_lands_on_a_villagers_house():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	_forest_band(world, coord)
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var mills: Array = _placed(world, VillageRenderer.INDUSTRY_BUILDING_ID)
	assert_eq(mills.size(), 1, "precondition")
	var mill_cells := {}
	for cell in BuildingCatalog.footprint_cells(VillageRenderer.INDUSTRY_BUILDING_ID, mills[0]["origin_local"]):
		mill_cells[cell] = true
	for call in world.place_calls:
		if call["building_id"] == VillageRenderer.INDUSTRY_BUILDING_ID:
			continue
		for cell in BuildingCatalog.footprint_cells(call["building_id"], call["origin_local"]):
			assert_false(mill_cells.has(cell), "the mill overlaps a house at %s" % str(cell))


# -- a village that grew (docs/concept/village_growth.md mechanism 3) ------
#
# Households move in over time (EarthChunkManager.admit_household), and the
# newcomers have to actually walk around: SettlementGenerator.POPULATION is
# the FOUNDING roster, and the settlement's real household count is what
# the renderer spawns.

func _npc_count(spawned: Array) -> int:
	var count := 0
	for node in spawned:
		if node is NpcMarker:
			count += 1
	return count


func test_a_village_spawns_its_founding_roster_when_nothing_says_otherwise():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_eq(_npc_count(spawned), SettlementGenerator.POPULATION)


func test_a_village_that_grew_spawns_the_households_that_moved_in():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	world.household_count = SettlementGenerator.POPULATION + 3
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_eq(_npc_count(spawned), SettlementGenerator.POPULATION + 3, "the newcomers walk around too")


## A settlement whose households were never recorded (an isolated test, a
## world that cannot answer) falls back to the founding roster rather than
## spawning an empty village.
func test_a_world_that_cannot_answer_falls_back_to_the_founding_roster():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	world.household_count = 0
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_eq(_npc_count(spawned), SettlementGenerator.POPULATION)


## A newcomer's house was raised by the growth ladder, not stamped at
## founding, so it carries none of the founding per-index seeds. It is
## found by WHO OWNS IT instead -- otherwise every household that ever
## moved in would stand forever on the fallback ring anchor, outside the
## house it actually owns.
func test_a_newcomer_stands_at_the_house_their_household_owns():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	# Founded at its founding roster, so index POPULATION genuinely has no
	# house from that pass -- which is what a real newcomer's situation is.
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	world.household_count = SettlementGenerator.POPULATION + 1

	# The newcomer's own house, raised after founding by the growth ladder:
	# a real building the world reports as theirs, carrying none of the
	# founding per-index seeds.
	var settlement := _generator.generate_settlement(
		coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, SettlementGenerator.POPULATION + 1
	)
	var newcomer = settlement.npcs[SettlementGenerator.POPULATION]
	var origin := Vector2i(1, 1)
	world.place_calls.append({
		"chunk_coord": coord, "origin_local": origin, "building_id": "house_small",
		"facing": Vector2i(0, 1), "seed": 999999, "owner_household_id": "",
		"occupation": "", "resident_seed": 0,
	})
	world.house_origin_by_villager[newcomer.seed_value] = origin

	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	var expected_doorstep := coord * CHUNK_SIZE + origin + BuildingCatalog.doorstep_of("house_small")
	var expected_position := Vector2(
		(expected_doorstep.x + 0.5) * TILE_SIZE, (expected_doorstep.y + 0.5) * TILE_SIZE
	)
	var found := false
	for node in spawned:
		if node is NpcMarker and node.identity.seed_value == newcomer.seed_value:
			found = true
			assert_almost_eq(node.home_position.x, expected_position.x, 0.01)
			assert_almost_eq(node.home_position.y, expected_position.y, 0.01, "home is their own doorstep")
	assert_true(found, "the newcomer was spawned at all")


# -- workspot props stand on real, dry ground -----------------------------
#
# Reported from a real session with a screenshot: a farmer's field, a
# merchant's stall and a blacksmith's forge floating ON a river, and a
# villager standing in it. Both positions were a blind fixed offset south
# of the door -- four tiles for a workspot, two for a merchant's stand --
# with no terrain check of any kind, and a village street that runs along
# a riverbank puts that offset straight into the water.

func _props_in(spawned: Array) -> Array:
	var props: Array = []
	for node in spawned:
		if node is NpcMarker:
			continue
		if node.has_meta("landmark_id"):
			props.append(node)
	return props


## Everything south of the street is river -- exactly the reported shape.
func _flood_south_of_the_street(world: StubWorld, coord: Vector2i) -> void:
	var street_y: int = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(coord))["street_y"]
	for y in range(street_y + 1, CHUNK_SIZE):
		for x in CHUNK_SIZE:
			world.water_cells[coord * CHUNK_SIZE + Vector2i(x, y)] = true


func _tile_of(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / TILE_SIZE), floori(position.y / TILE_SIZE))


func test_no_prop_and_no_villager_ever_stands_in_water():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	_flood_south_of_the_street(world, coord)

	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	for node in spawned:
		var tile := _tile_of(node.position)
		assert_false(
			world.water_cells.has(tile), "%s stands in the river at %s" % [
				str(node.get_meta("landmark_id")) if node.has_meta("landmark_id") else "a villager", str(tile)
			]
		)


func test_a_villagers_workspot_is_never_in_water_either():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	_flood_south_of_the_street(world, coord)

	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	for node in spawned:
		if node is NpcMarker:
			assert_false(
				world.water_cells.has(_tile_of(node.workspot_position)),
				"a villager would walk into the river to work"
			)


## Dry ground everywhere: the props are still there. The fix must site
## them, not delete the feature.
func test_a_village_on_dry_ground_still_gets_its_workspot_props():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_gt(_props_in(spawned).size(), 0, "a dry village still has real workspots")


## A PERSONAL prop on the street, or on a house, is as wrong as one in the
## river. The three SHARED landmarks are the opposite case -- the well and
## the stall stand on the plaza's own paving and the gate on the street by
## design -- which is why the two kinds are told apart by their own meta
## rather than by an id a merchant's personal stand happens to share.
func test_a_personal_workspot_prop_never_stands_on_a_road_or_a_building():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	var personal := 0
	for node in _props_in(spawned):
		if not bool(node.get_meta("personal", false)):
			continue
		personal += 1
		var tile := _tile_of(node.position)
		var existing: String = world.modification_at_global(tile.x, tile.y)
		assert_eq(existing, "", "%s stands on '%s' at %s" % [node.get_meta("landmark_id"), existing, str(tile)])
	assert_gt(personal, 0, "precondition: this village has personal workspots at all")


## And the shared ones really are on the village's own paving -- the thing
## that makes a square read as a square.
func test_the_shared_landmarks_stand_on_the_villages_own_paving():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	for node in _props_in(spawned):
		if bool(node.get_meta("personal", false)):
			continue
		var tile := _tile_of(node.position)
		var existing: String = world.modification_at_global(tile.x, tile.y)
		assert_true(
			existing == "" or TerrainRenderer.is_road_tile(existing),
			"%s stands on '%s'" % [node.get_meta("landmark_id"), existing]
		)


## A merchant's PERSONAL stand is the same rule -- it was the other blind
## offset, two tiles south of the door.
func test_a_merchants_personal_stand_is_sited_on_real_ground():
	var coord := _find_settlement_chunk_with_merchant("grassland")
	var world := StubWorld.new()
	_flood_south_of_the_street(world, coord)

	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	for node in spawned:
		if node.has_meta("landmark_id") and node.get_meta("landmark_id") == "stall":
			assert_false(world.water_cells.has(_tile_of(node.position)), "a stall floating on the river")


# -- a village fells the trees it needs ------------------------------------
#
# Measured on real terrain near 51.2N 13.6E: with forest refused outright,
# only 12 of 22 villages (55%) got a plaza at all, and FOREST was the
# blocker in every single failing case -- water in none of them. No plaza
# means no civic plot, which means no city hall, so nearly half of all
# villages were losing their civic centre to trees they would simply have
# cleared.
#
# docs/concept/building.md's own words: "the NPCs / Player must first fell
# all trees to make space for the building". place_building and
# build_at_global already do exactly that (_clear_vegetation_on_cells,
# _block_ground_cover_on_cells), so a village siting on wooded ground
# clears it for real rather than leaving trees standing through walls.
# Water is the rule that stays: a village does not drain a river.

func _forest_over_the_street(world: StubWorld, coord: Vector2i) -> void:
	var street_y: int = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(coord))["street_y"]
	for y in range(street_y - 4, street_y + 4):
		for x in CHUNK_SIZE:
			world.forest_cells[coord * CHUNK_SIZE + Vector2i(x, y)] = true


func test_a_village_clears_the_wood_for_its_houses_and_its_square():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	_forest_over_the_street(world, coord)

	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	assert_gt(world.place_calls.size(), 0, "a wooded street is cleared and built on, not abandoned")
	var plaza: Rect2i = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(coord))["plaza"]
	var paved := 0
	for y in range(plaza.position.y, plaza.end.y):
		for x in range(plaza.position.x, plaza.end.x):
			var g: Vector2i = coord * CHUNK_SIZE + Vector2i(x, y)
			if TerrainRenderer.is_road_tile(world.built_tiles.get(g, "")):
				paved += 1
	assert_eq(paved, plaza.get_area(), "the square is cleared out of the wood and fully paved")


## The other half of the same rule, stated from the new side: a chunk that
## is ENTIRELY wooded is cleared and built on, where before it would have
## been refused outright and left villagers homeless.
func test_a_village_clears_an_entirely_wooded_chunk_rather_than_refusing_it():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	for x in CHUNK_SIZE:
		for y in CHUNK_SIZE:
			world.forest_cells[coord * CHUNK_SIZE + Vector2i(x, y)] = true

	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	assert_gt(world.place_calls.size(), 0, "a wooded chunk is cleared and settled, not abandoned")


# -- a village is founded with the hall its size entitles it to -----------
#
# Reported three times in play as simply missing. The over-time build is
# real and tested (test_earth_chunk_manager_city_hall_rising.gd), but it
# needs ~20 wood + 10 stone gathered and then 45 labour-hours accrued --
# a couple of real hours beside the village, and longer still for a poor
# one now that productivity scales the crew. A player who walks into a
# village never sees it.
#
# So the same rule the sawmill already follows: a village the player
# DISCOVERS has been standing for years, and its civic seat is part of the
# fabric it was founded with. The over-time ladder still covers every rung
# a village grows into during play.

func test_a_founded_village_already_has_its_city_hall():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_eq(_placed(world, "city_hall").size(), 1, "a village of five households has a seat")


func test_the_hall_stands_on_the_plazas_own_reserved_civic_plot():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var halls: Array = _placed(world, "city_hall")
	assert_eq(halls.size(), 1, "precondition")
	var plot: Dictionary = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(coord))["civic_plot"]
	assert_eq(halls[0]["origin_local"], plot["origin"], "on the square's own reserved plot, not anywhere free")


func test_a_reload_never_raises_a_second_hall():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_eq(_placed(world, "city_hall").size(), 1, "one seat per village, across reloads")


## An older village, founded before this existed, gains its hall on the
## next visit -- the same self-healing shape the plaza and the mill have.
func test_an_older_village_gains_its_hall_on_a_later_visit():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	world.refuse_civic = true
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_eq(_placed(world, "city_hall").size(), 0, "precondition: founded without one")

	world.refuse_civic = false
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	assert_eq(_placed(world, "city_hall").size(), 1)


## A village whose square was never paved has nowhere to put a seat, and
## honestly gets none.
func test_a_village_with_no_square_gets_no_hall():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var plaza: Rect2i = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(coord))["plaza"]
	for y in range(plaza.position.y, plaza.end.y):
		for x in range(plaza.position.x, plaza.end.x):
			world.water_cells[coord * CHUNK_SIZE + Vector2i(x, y)] = true

	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	assert_eq(_placed(world, "city_hall").size(), 0, "no square, no seat")


# -- a village is not founded where it cannot build (reported in play:
# "Some villages have no houses") -----------------------------------------
#
# Measured against the real world near lat 48.6 lon 12.7
# (tools/probe_village_houses_live.gd): 3 of 6 real villages stood with
# roads, a sawmill and five villagers, and not one dwelling. One of their
# chunks is 100% water by the same rule the water surface paints with --
# a village founded in the middle of a lake -- and the other two are 50%
# and 68% water.
#
# The biome classifier does not know about hydrology, so a lake still
# reads as "grassland" and SettlementGenerator settles it. Every house is
# then correctly refused, because the ground really is water. What was
# wrong was carrying on regardless: paving streets, raising a sawmill and
# spawning five villagers onto a lake.


func _drown_the_whole_chunk(world: StubWorld, coord: Vector2i) -> void:
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			world.water_cells[coord * CHUNK_SIZE + Vector2i(x, y)] = true


func test_a_village_with_nowhere_to_put_a_single_house_is_not_founded_at_all():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	_drown_the_whole_chunk(world, coord)

	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	assert_true(spawned.is_empty(), "no villagers, no landmarks -- there is no village here")
	assert_true(world.place_calls.is_empty(), "nothing is built on a lake, not even a sawmill")
	assert_true(world.built_tiles.is_empty(), "and no streets are paved across it")


func test_a_drowned_site_is_never_recorded_as_a_founded_settlement():
	# Recording one would leave a settlement in the ledger with no village
	# in the world -- households, a market and a build ladder for a place
	# that does not exist.
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	_drown_the_whole_chunk(world, coord)

	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	assert_true(world.founded_calls.is_empty())


func test_dry_ground_still_founds_its_village_exactly_as_before():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()

	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	assert_false(spawned.is_empty())
	assert_gt(_house_calls(world).size(), 0, "the precondition this whole rule turns on")


# -- props stand where a villager can walk up to them (reported in play:
# "all procedural stands, wells, beds etc ... are also badly placed") ------
#
# _grounded_position finds the nearest cell that is real, dry and carries
# nothing built -- and stops there. Open grass five tiles behind a house
# satisfies all of that, so a farmer's field or a merchant's own stand
# could be pushed off the street and left sitting in a meadow with no path
# to it, which is what the screenshot shows.
#
# A prop is somewhere a villager's schedule sends them, so the ground it
# stands on has to touch the village's own paving.


func _road_cells_of(world: StubWorld) -> Dictionary:
	var roads := {}
	for cell in world.built_tiles:
		if TerrainRenderer.is_road_tile(world.built_tiles[cell]):
			roads[cell] = true
	return roads


func _prop_cells(spawned: Array, personal_only: bool) -> Array:
	var cells: Array = []
	for node in spawned:
		if not node.has_meta("landmark_id"):
			continue
		if personal_only and not node.get_meta("personal", false):
			continue
		cells.append(Vector2i(floori(node.position.x / TILE_SIZE), floori(node.position.y / TILE_SIZE)))
	return cells


func _touches_a_road(cell: Vector2i, roads: Dictionary) -> bool:
	for step in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if roads.has(cell + step):
			return true
	return false


func test_every_personal_workspot_prop_stands_next_to_the_villages_paving():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()

	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	var roads := _road_cells_of(world)
	assert_gt(roads.size(), 0, "precondition: this village really paved something")
	var props := _prop_cells(spawned, true)
	assert_gt(props.size(), 0, "precondition: this village really has personal props")
	for cell in props:
		assert_true(
			_touches_a_road(cell, roads),
			"a prop a villager walks to must touch the paving, not sit in a meadow behind the houses"
		)


func test_every_shared_landmark_stands_on_or_beside_the_paving_too():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()

	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	var roads := _road_cells_of(world)
	for cell in _prop_cells(spawned, false):
		assert_true(_touches_a_road(cell, roads), "the well, the stall and the gate belong to the square")


# -- a prop draws its real art when there is any ---------------------------
#
# Asked for directly: the procedural stands, wells and beds should get real
# art like the houses and the city hall have. The renderer asks
# LandmarkSheet first and falls back to the procedural sprite, so dropping
# a PNG into assets/sprites/landmarks/ is the entire job -- and until one
# is dropped in, every prop draws exactly as it does today.


func test_a_prop_with_no_art_yet_still_draws_its_procedural_sprite():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()

	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	var props := 0
	for node in spawned:
		if not node.has_meta("landmark_id"):
			continue
		props += 1
		assert_not_null(node.texture, "%s must still be drawn" % node.get_meta("landmark_id"))
	assert_gt(props, 0, "precondition: this village really has props")


func test_the_renderer_asks_for_real_art_before_drawing_one_itself():
	# The seam itself: a prop's texture comes from LandmarkSheet when it
	# can, which is what makes supplied art take over with no other change.
	assert_true(
		renderer.has_method("_landmark_texture"),
		"the renderer must route a prop's texture through one place that can prefer real art"
	)


# -- a save whose every dwelling is gone -----------------------------------
#
# Measured in the real world with tools/probe_village_ghost.gd: chunks
# (668,143) and (670,144) near lat 48.6 lon 12.7 each stood with five
# villagers, paved streets, a sawmill, and NOT ONE dwelling -- written by a
# build from before "a site that cannot take a single house is not a
# village" shipped. The founding path refuses that site now. The RELOAD
# path did not: one persisted building, any building, sent it down the
# recovery branch, which matches villagers to houses that are not there and
# spawns the whole roster regardless.
#
# What counts is a DWELLING, not a building. A village with no home in it
# is either healed -- the ground may be perfectly good, and the houses
# simply never got built -- or it is not a village at all.


## The village's own mill, and nothing else: exactly what the two measured
## chunks hold.
func _seed_a_millsonly_save(world: StubWorld, coord: Vector2i) -> void:
	world.place_building(coord, Vector2i(2, 2), VillageRenderer.INDUSTRY_BUILDING_ID, Vector2i(0, 1), 1, "")


func test_a_saved_village_whose_dwellings_are_all_gone_builds_them_on_good_ground():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	_seed_a_millsonly_save(world, coord)
	assert_eq(_house_calls(world).size(), 0, "precondition: this save holds no dwelling at all")

	var spawned := renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	assert_gt(
		_house_calls(world).size(), 0,
		"good ground and no home on it: the houses are raised, not shrugged at"
	)
	var npc_count := 0
	for node in spawned:
		if node is NpcMarker:
			npc_count += 1
	assert_eq(npc_count, SettlementGenerator.POPULATION, "and its villagers live there")


func test_a_saved_village_with_no_dwelling_on_ground_that_takes_none_spawns_no_villagers():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	_seed_a_millsonly_save(world, coord)
	# Water everywhere but the spine itself -- the real shape of chunk
	# (668,143), whose street row is 24/26 dry while the strip a house
	# would stand on is 100% water.
	var street_y: int = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(coord))["street_y"]
	for y in CHUNK_SIZE:
		if y == street_y:
			continue
		for x in CHUNK_SIZE:
			world.water_cells[coord * CHUNK_SIZE + Vector2i(x, y)] = true

	var spawned := renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	assert_eq(_house_calls(world).size(), 0, "precondition: this ground really does take no house")
	var npc_count := 0
	for node in spawned:
		if node is NpcMarker:
			npc_count += 1
	assert_eq(npc_count, 0, "five villagers with no home between them is not a village")


# -- farmhouses: one per farming villager ----------------------------------
#
# Reported in play: "The village needs a farmer which grows wheat like in
# Anno... similar to a farmer the herbalist should build a farm house and
# plant herbs ... the farm houses are separate buildings". See
# docs/concept/village_farms.md.


## A settlement chunk whose fixed roster happens to include `occupation` --
## seeded per villager, so not every settlement chunk has one.
func _find_settlement_chunk_with_occupation(biome: String, occupation: String, row: int) -> Vector2i:
	for x in 400:
		var coord := Vector2i(x, row)
		if not _generator.has_settlement_at(coord, biome):
			continue
		var settlement := _generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
		for npc in settlement.npcs:
			if npc.occupation == occupation:
				return coord
	fail_test("no settlement chunk with a %s found within 400 chunks" % occupation)
	return Vector2i.ZERO


func _buildings_of(world: StubWorld, building_id: String) -> Array:
	var out: Array = []
	for call in world.place_calls:
		if call["building_id"] == building_id:
			out.append(call)
	return out


func _farming_villager_count(coord: Vector2i) -> int:
	var settlement := _generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
	var count := 0
	for npc in settlement.npcs:
		if VillageFarm.crop_for(npc.occupation) != "":
			count += 1
	return count


func test_a_village_raises_one_farmhouse_for_every_villager_who_farms():
	var coord := _find_settlement_chunk_with_occupation("grassland", "farmer", 3)
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var expected := _farming_villager_count(coord)
	assert_gt(expected, 0, "precondition: somebody in this village farms")
	assert_eq(
		_buildings_of(world, VillageFarm.FARM_BUILDING_ID).size(), expected,
		"a farmer and a herbalist each want their own farmhouse -- that is what makes two fields"
	)


func test_a_village_with_nobody_who_farms_raises_no_farmhouse():
	var coord := Vector2i.ZERO
	var found := false
	for x in 400:
		var candidate := Vector2i(x, 4)
		if not _generator.has_settlement_at(candidate, "grassland"):
			continue
		if _farming_villager_count(candidate) == 0:
			coord = candidate
			found = true
			break
	assert_true(found, "precondition: a settlement chunk whose whole roster happens not to farm")
	if not found:
		return
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_eq(
		_buildings_of(world, VillageFarm.FARM_BUILDING_ID).size(), 0,
		"a farmhouse nobody would ever work is a building the village should not own"
	)


func test_a_reload_never_raises_a_second_farmhouse():
	var coord := _find_settlement_chunk_with_occupation("grassland", "farmer", 3)
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var after_first := _buildings_of(world, VillageFarm.FARM_BUILDING_ID).size()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_eq(_buildings_of(world, VillageFarm.FARM_BUILDING_ID).size(), after_first)


func test_every_farmhouse_stands_where_its_own_field_really_fits():
	var coord := _find_settlement_chunk_with_occupation("grassland", "farmer", 3)
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var farmhouses := _buildings_of(world, VillageFarm.FARM_BUILDING_ID)
	assert_gt(farmhouses.size(), 0, "precondition: a farmhouse was raised")
	for call in farmhouses:
		# The whole rectangle, not a count of loose cells: those stopped
		# being the same question when the field became a 3x2.
		var is_free := func(cell: Vector2i) -> bool:
			if cell.x < 0 or cell.y < 0 or cell.x >= CHUNK_SIZE or cell.y >= CHUNK_SIZE:
				return false
			var g: Vector2i = coord * CHUNK_SIZE + cell
			return not world.is_water_at_global(g.x, g.y) and world.modification_at_global(g.x, g.y) == ""
		assert_not_null(
			VillageFarm.field_rect(call["origin_local"], VillageFarm.FARM_BUILDING_ID, is_free),
			"a farmhouse with nowhere to farm is a farmhouse that should not have been raised"
		)


func test_two_farmhouses_never_stand_on_each_others_ground():
	var coord := _find_settlement_chunk_with_occupation("grassland", "farmer", 3)
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var origins: Array = []
	for call in _buildings_of(world, VillageFarm.FARM_BUILDING_ID):
		origins.append(call["origin_local"])
	var seen: Dictionary = {}
	for origin in origins:
		for cell in BuildingCatalog.footprint_cells(VillageFarm.FARM_BUILDING_ID, origin):
			assert_false(seen.has(cell), "two farmhouses overlap at %s" % str(cell))
			seen[cell] = true



# -- and every farming villager is handed their OWN farmhouse's field -------

func _farming_markers(spawned: Array, coord: Vector2i) -> Array:
	var out: Array = []
	for node in spawned:
		if node is NpcMarker and VillageFarm.crop_for(node.identity.occupation) != "":
			out.append(node)
	return out


func test_a_farming_villager_is_handed_a_real_field():
	var coord := _find_settlement_chunk_with_occupation("grassland", "farmer", 3)
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	var farmers := _farming_markers(spawned, coord)
	assert_gt(farmers.size(), 0, "precondition: somebody in this village farms")
	for npc in farmers:
		assert_gt(
			(npc.field_cells as Array).size(), 0,
			"a %s with a farmhouse and no field would still be farming a number" % npc.identity.occupation
		)


func test_a_villager_who_does_not_farm_is_handed_nothing():
	var coord := _find_settlement_chunk_with_occupation("grassland", "farmer", 3)
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	for node in spawned:
		if node is NpcMarker and VillageFarm.crop_for(node.identity.occupation) == "":
			assert_eq((node.field_cells as Array).size(), 0, "%s does not farm" % node.identity.occupation)


func test_every_field_tile_a_villager_is_given_really_belongs_to_a_farmhouse():
	var coord := _find_settlement_chunk_with_occupation("grassland", "farmer", 3)
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	var origins: Array = []
	for call in _buildings_of(world, VillageFarm.FARM_BUILDING_ID):
		origins.append(call["origin_local"])
	for npc in _farming_markers(spawned, coord):
		for global_cell in npc.field_cells:
			var local: Vector2i = global_cell - coord * CHUNK_SIZE
			assert_not_null(
				VillageFarm.owner_of(local, origins, VillageFarm.FARM_BUILDING_ID),
				"%s lies beside no farmhouse at all" % str(local)
			)


func test_no_two_villagers_are_handed_the_same_tile():
	var coord := _find_settlement_chunk_with_occupation("grassland", "herbalist", 5)
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	var claimed: Dictionary = {}
	for npc in _farming_markers(spawned, coord):
		for cell in npc.field_cells:
			assert_false(claimed.has(cell), "%s was handed to two villagers" % str(cell))
			claimed[cell] = true


func test_no_field_tile_is_water_or_already_built_on():
	var coord := _find_settlement_chunk_with_occupation("grassland", "farmer", 3)
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	for npc in _farming_markers(spawned, coord):
		for cell in npc.field_cells:
			assert_false(world.is_water_at_global(cell.x, cell.y), "%s is water" % str(cell))
			assert_eq(
				world.modification_at_global(cell.x, cell.y), "",
				"%s already has something standing on it" % str(cell)
			)


# -- a village only settles where there is room for all of it --------------
#
# Asked for directly: "They should only settle where there's enough space
# and the square wins; houses should just be moved further away connected
# by streets". A site that can take the square but only some of the roster
# is not a site for a village -- it is how a riverside chunk ended up with
# a market square and one house.


func test_a_village_founds_nothing_where_it_cannot_house_everyone():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	# Dry only where two or three houses fit, nowhere near enough for the
	# whole roster however far out the streets go.
	var street_y: int = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(coord))["street_y"]
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			if y >= street_y - 2 and y <= street_y and x >= 4 and x < 12:
				continue
			world.water_cells[coord * CHUNK_SIZE + Vector2i(x, y)] = true

	var spawned := renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	var npc_count := 0
	for node in spawned:
		if node is NpcMarker:
			npc_count += 1
	assert_eq(npc_count, 0, "a site that houses only part of a village is not a village site")
	assert_eq(world.place_calls.size(), 0, "and nothing at all is built there")


func test_a_village_with_room_for_everyone_is_founded_as_before():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	var npc_count := 0
	for node in spawned:
		if node is NpcMarker:
			npc_count += 1
	assert_eq(npc_count, SettlementGenerator.POPULATION, "open ground still founds a whole village")
	assert_eq(
		_house_calls(world).size(), SettlementGenerator.POPULATION,
		"and every villager in it has a house"
	)


# -- and every farmhouse is really joined to the village's own streets -----
#
# Reported in play, with a screenshot of a farmhouse whose field beds sit in
# open ground: "There are still Farmhouses not connected by a street". See
# docs/concept/village_farms.md.


## Every cell this village actually paved, chunk-LOCAL.
func _paved_cells(world: StubWorld, coord: Vector2i) -> Dictionary:
	var paved: Dictionary = {}
	for global_cell in world.built_tiles:
		if world.built_tiles[global_cell] != TerrainRenderer.ROAD_TILE_ID:
			continue
		var local: Vector2i = (global_cell as Vector2i) - coord * CHUNK_SIZE
		if local.x < 0 or local.y < 0 or local.x >= CHUNK_SIZE or local.y >= CHUNK_SIZE:
			continue
		paved[local] = true
	return paved


## The paving a villager could actually walk to from the village's own main
## street, 4-connected -- the real question behind "connected by a street".
func _paving_reachable_from_the_spine(world: StubWorld, coord: Vector2i) -> Dictionary:
	var paved := _paved_cells(world, coord)
	var bones: Dictionary = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(coord))
	var frontier: Array = []
	var seen: Dictionary = {}
	for x in range(bones["street_x0"], bones["street_x1"] + 1):
		var cell := Vector2i(x, bones["street_y"])
		if paved.has(cell) and not seen.has(cell):
			seen[cell] = true
			frontier.append(cell)
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if paved.has(next) and not seen.has(next):
				seen[next] = true
				frontier.append(next)
	return seen


## Every settlement chunk in `row` whose roster includes a farmer, up to
## `limit` of them -- one village can easily have frontage on its own main
## street (paved end to end) and prove nothing about the further rows,
## which is where the report's farmhouse actually stood.
func _settlement_chunks_with_farmers(row: int, limit: int) -> Array:
	var found: Array = []
	for x in 400:
		var coord := Vector2i(x, row)
		if not _generator.has_settlement_at(coord, "grassland"):
			continue
		if _farming_villager_count(coord) > 0:
			found.append(coord)
			if found.size() >= limit:
				break
	return found


func test_every_farmhouse_doorstep_really_joins_the_villages_own_streets():
	var coords := _settlement_chunks_with_farmers(3, 6)
	assert_gt(coords.size(), 0, "precondition: settlement chunks with a farmer in them")
	var farmhouses_seen := 0
	var stranded: Array = []
	for coord in coords:
		var world := StubWorld.new()
		renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
		var network := _paving_reachable_from_the_spine(world, coord)
		for call in _buildings_of(world, VillageFarm.FARM_BUILDING_ID):
			farmhouses_seen += 1
			var doorstep: Vector2i = (
				call["origin_local"] + BuildingCatalog.doorstep_of(VillageFarm.FARM_BUILDING_ID)
			)
			if not network.has(doorstep):
				stranded.append("%s: farmhouse %s opens onto %s" % [str(coord), str(call["origin_local"]), str(doorstep)])
	assert_gt(farmhouses_seen, 0, "precondition: farmhouses were raised")
	assert_eq(
		stranded.size(), 0,
		(
			"%d of %d farmhouses open onto paving no street reaches -- a farm "
			+ "nobody can walk to is not part of the village: %s"
		) % [stranded.size(), farmhouses_seen, str(stranded.slice(0, 4))]
	)


# -- and the beds are fenced against the animals ---------------------------
#
# Asked for directly, with the field circled in a screenshot: "the farmhouse
# should build a fence around the bed so no animals enter". See
# docs/concept/village_farms.md, "The fence around the beds".


## Every tile this village really built, LOCAL -> tile id.
func _built_tiles(world: StubWorld, coord: Vector2i) -> Dictionary:
	var built: Dictionary = {}
	for global_cell in world.built_tiles:
		built[(global_cell as Vector2i) - coord * CHUNK_SIZE] = world.built_tiles[global_cell]
	return built


func test_a_farmhouse_raises_a_real_fence_around_the_beds_it_works():
	var coord := _find_settlement_chunk_with_occupation("grassland", "farmer", 3)
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	var farmers := _farming_markers(spawned, coord)
	assert_gt(farmers.size(), 0, "precondition: somebody in this village farms")
	var built := _built_tiles(world, coord)
	var rails := 0
	var facings: Dictionary = {}
	for tile_id in built.values():
		if VillageFarm.is_fence_tile(tile_id):
			rails += 1
			facings[tile_id] = true
	assert_gt(rails, 0, "a farm with no fence is a field that feeds deer")
	# A ring closes on all four sides, so a real fence uses more than one of
	# the sheet's own orientation columns.
	assert_gt(facings.size(), 1, "every rail faces the same way -- that is a wall, not a ring")


## Only the beds are enclosed, and the rails stand OUTSIDE them: a rail on a
## bed is a rail through the crop.
func test_no_rail_is_ever_built_on_a_bed_a_villager_works():
	var coord := _find_settlement_chunk_with_occupation("grassland", "farmer", 3)
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	var built := _built_tiles(world, coord)
	for npc in _farming_markers(spawned, coord):
		for global_cell in npc.field_cells:
			var local: Vector2i = (global_cell as Vector2i) - coord * CHUNK_SIZE
			assert_false(
				VillageFarm.is_fence_tile(built.get(local, "")),
				"%s is a bed, and a rail through it is a rail through the crop" % str(local)
			)


## The gate: the village's own paving is never fenced over, or the farmer
## could not walk to the farm their farmhouse fronts.
func test_the_fence_never_closes_over_the_villages_own_street():
	var coord := _find_settlement_chunk_with_occupation("grassland", "farmer", 3)
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var network := _paving_reachable_from_the_spine(world, coord)
	assert_gt(network.size(), 0, "precondition: this village paved a street")
	var built := _built_tiles(world, coord)
	for cell in network:
		assert_false(
			VillageFarm.is_fence_tile(built.get(cell, "")),
			"%s is street, and a fence laid across it walls the village off from its own farm" % str(cell)
		)


## And a rail never stands on a building, in water, or off the chunk.
func test_a_rail_only_ever_stands_on_ground_that_can_take_one():
	var coord := _find_settlement_chunk_with_occupation("grassland", "farmer", 3)
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var footprints: Dictionary = {}
	for call in world.place_calls:
		for cell in BuildingCatalog.footprint_cells(call["building_id"], call["origin_local"]):
			footprints[cell] = call["building_id"]
	var built := _built_tiles(world, coord)
	for cell in built:
		if not VillageFarm.is_fence_tile(built[cell]):
			continue
		assert_false(footprints.has(cell), "%s is a building, not open ground" % str(cell))
		assert_true(
			cell.x >= 0 and cell.y >= 0 and cell.x < CHUNK_SIZE and cell.y < CHUNK_SIZE,
			"%s is outside the chunk" % str(cell)
		)
		var g: Vector2i = coord * CHUNK_SIZE + cell
		assert_false(world.is_water_at_global(g.x, g.y), "%s is water" % str(cell))


## A farmhouse is only raised where a whole RECTANGLE fits, not merely where
## a few loose cells are clear. The two stopped being the same question when
## the field became a 3x2 (docs/concept/village_farms.md): ground with four
## scattered free cells and no rectangle in it would raise a farmhouse whose
## villager then has nowhere at all to sow.
func test_every_farmhouse_raised_really_gets_a_field_to_work():
	var stranded: Array = []
	var seen := 0
	for coord in _settlement_chunks_with_farmers(3, 14):
		var world := StubWorld.new()
		var spawned := renderer.spawn_village(
			parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
		)
		for _call in _buildings_of(world, VillageFarm.FARM_BUILDING_ID):
			seen += 1
		for npc in _farming_markers(spawned, coord):
			if (npc.field_cells as Array).is_empty():
				stranded.append("%s: a %s has a farmhouse and no field" % [str(coord), npc.identity.occupation])
	assert_gt(seen, 0, "precondition: farmhouses were raised")
	assert_eq(
		stranded.size(), 0,
		"a farmhouse with nowhere to sow should never have been raised: %s" % str(stranded.slice(0, 4))
	)


## And what a villager is handed really is the rectangle that was asked for.
func test_the_field_a_villager_works_is_a_whole_rectangle():
	for coord in _settlement_chunks_with_farmers(3, 4):
		var world := StubWorld.new()
		var spawned := renderer.spawn_village(
			parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
		)
		for npc in _farming_markers(spawned, coord):
			var cells: Array = npc.field_cells
			if cells.is_empty():
				continue
			var min_cell: Vector2i = cells[0]
			var max_cell: Vector2i = cells[0]
			for cell in cells:
				min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
				max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))
			var size := max_cell - min_cell + Vector2i.ONE
			assert_true(
				VillageFarm.FIELD_SHAPES.has(size),
				"%s beds span %s, which is not a shape that was asked for" % [str(coord), str(size)]
			)
			assert_eq(cells.size(), size.x * size.y, "the rectangle has a hole in it")


## A village never SOWS across its own street ROWS -- paved or not. Measured
## on real villages (tools/probe_village_map.gd): the founding layout paves a
## further street only between its own doorsteps, so a street row has unpaved
## gaps in it, and a crop dropped into one of those grows in the middle of
## the street with paving either side.
##
## RAILS were once held to the same rule and are not any more: a field sits
## below the house it belongs to, so one whole side of its frame lands on the
## next street row, and holding rails to it left that side open -- reported
## with the bed circled, "it's still not fully enclosing the bed". A rail
## along the edge of a road is a fence beside a road; a crop in the roadway
## is not a crop. The gate is the PAVING, which is occupied ground and stops
## a rail on its own (see
## test_a_fields_frame_closes_on_every_side_that_is_not_paving_or_a_building).
func test_no_bed_ever_lands_on_one_of_the_villages_street_rows():
	var offenders: Array = []
	var checked := 0
	for coord in _settlement_chunks_with_farmers(3, 8):
		var world := StubWorld.new()
		var spawned := renderer.spawn_village(
			parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
		)
		var street_y: int = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(coord))["street_y"]
		var on_a_street := func(y: int) -> bool:
			return y >= street_y and (y - street_y) % VillageLayout.STREET_PITCH_TILES == 0
		for npc in _farming_markers(spawned, coord):
			for global_cell in npc.field_cells:
				checked += 1
				var local: Vector2i = (global_cell as Vector2i) - coord * CHUNK_SIZE
				if on_a_street.call(local.y):
					offenders.append("%s: a bed at %s is on a street row" % [str(coord), str(local)])
	assert_gt(checked, 0, "precondition: real fields were laid")
	assert_eq(offenders.size(), 0, "%s" % str(offenders.slice(0, 6)))


## Reported in play with the bed circled: *"it's still not fully enclosing
## the bed"*. A frame was leaving a whole SIDE open wherever that side fell
## on one of the village's street ROWS -- and measured on real villages
## (tools/probe_village_map.gd), most of those cells carry no paving at all:
## a 3-wide `.....` gap directly under a field, with the frame closed on
## every other side. An unpaved gap is not a gate. The gate is the paving.
##
## States the frame as a whole rather than re-deriving the placement rule:
## every cell of a field's own ring carries a rail unless there is a real
## reason it cannot -- it is somebody's bed, it is the farmhouse, it is
## paved (which IS the gate), or it is ground nothing may stand on.
func test_a_fields_frame_closes_on_every_side_that_is_not_paving_or_a_building():
	var open_sides: Array = []
	var checked := 0
	for coord in _settlement_chunks_with_farmers(3, 8):
		var world := StubWorld.new()
		var spawned := renderer.spawn_village(
			parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
		)
		var built := _built_tiles(world, coord)
		var beds: Dictionary = {}
		var markers := _farming_markers(spawned, coord)
		for npc in markers:
			for global_cell in npc.field_cells:
				beds[(global_cell as Vector2i) - coord * CHUNK_SIZE] = true
		for npc in markers:
			var local_beds: Array = []
			for global_cell in npc.field_cells:
				local_beds.append((global_cell as Vector2i) - coord * CHUNK_SIZE)
			if local_beds.is_empty():
				continue
			var origin: Vector2i = _nearest_farmhouse_origin(world, coord, local_beds)
			for rail in VillageFarm.fence_cells(local_beds, origin, VillageFarm.FARM_BUILDING_ID):
				var cell: Vector2i = rail
				if cell.x < 0 or cell.y < 0 or cell.x >= CHUNK_SIZE or cell.y >= CHUNK_SIZE:
					continue
				if beds.has(cell):
					continue  # a neighbour's crop, not this frame
				# What the RENDERER sees standing there, not just what it
				# built: a farmhouse's own footprint closes a side without
				# any rail, and that occupancy lives in the same place the
				# placement rule reads it from.
				var standing: String = world.modification_at_global(
					coord.x * CHUNK_SIZE + cell.x, coord.y * CHUNK_SIZE + cell.y
				)
				if standing == "":
					standing = built.get(cell, "")
				if standing == TerrainRenderer.ROAD_TILE_ID:
					continue  # real paving: this is the gate
				if standing != "" and not VillageFarm.is_fence_tile(standing):
					continue  # a building or another structure closes it
				checked += 1
				if not VillageFarm.is_fence_tile(standing):
					open_sides.append("%s: the frame is open at %s" % [str(coord), str(cell)])
	assert_gt(checked, 0, "precondition: real fields with real ring cells were laid")
	assert_eq(open_sides.size(), 0, "%s" % str(open_sides.slice(0, 8)))


## The farmhouse this field belongs to -- the one whose own walls the ring
## is measured against.
func _nearest_farmhouse_origin(world: StubWorld, coord: Vector2i, local_beds: Array) -> Vector2i:
	var best := Vector2i.ZERO
	var best_distance := 0x7FFFFFFF
	for record in world.buildings_in_chunk(coord):
		if record.get("id", "") != VillageFarm.FARM_BUILDING_ID:
			continue
		var origin: Vector2i = record["origin_local"]
		var distance := 0x7FFFFFFF
		for bed in local_beds:
			var d: int = absi((bed as Vector2i).x - origin.x) + absi((bed as Vector2i).y - origin.y)
			distance = mini(distance, d)
		if distance < best_distance:
			best_distance = distance
			best = origin
	return best


## Asked for directly, with the broken stretch in shot: "When there's only a
## free gap of 1-2 tiles between two street tiles it should close the gap
## between them". The founding layout paves only between the doorsteps it
## actually joined, so a real village's street rows come out as paved
## stretches with one- and two-tile holes punched through them.
func test_a_village_leaves_no_one_or_two_tile_hole_in_its_own_streets():
	var holes: Array = []
	var checked := 0
	for coord in _settlement_chunks_with_farmers(3, 8):
		var world := StubWorld.new()
		renderer.spawn_village(
			parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
		)
		var street_y: int = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(coord))["street_y"]
		var is_paved := func(cell: Vector2i) -> bool:
			var g: Vector2i = coord * CHUNK_SIZE + cell
			return world.modification_at_global(g.x, g.y) == TerrainRenderer.ROAD_TILE_ID
		var is_free := func(cell: Vector2i) -> bool:
			var g: Vector2i = coord * CHUNK_SIZE + cell
			return world.modification_at_global(g.x, g.y) == ""
		checked += 1
		for cell in VillageLayout.short_street_gap_cells(
			is_paved, is_free, CHUNK_SIZE, street_y, VillageLayout.STREET_GAP_CLOSE_TILES
		):
			holes.append("%s: a hole in the street at %s" % [str(coord), str(cell)])
	assert_gt(checked, 0, "precondition: real villages were laid")
	assert_eq(holes.size(), 0, "%s" % str(holes.slice(0, 8)))


## The last link of "make sure wheat grows and is harvested which increases
## farmhouse stock which gets transported to city stock": a villager can
## only fill the farmhouse they work for if they know which one it is.
## Handed out with the field, by the one thing that knows whose is whose.
func test_every_farmer_is_told_which_farmhouse_the_field_belongs_to():
	var coord := _find_settlement_chunk_with_occupation("grassland", "farmer", 3)
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	var origins: Dictionary = {}
	for record in world.buildings_in_chunk(coord):
		if record.get("id", "") == VillageFarm.FARM_BUILDING_ID:
			origins[coord * CHUNK_SIZE + (record["origin_local"] as Vector2i)] = true
	assert_gt(origins.size(), 0, "precondition: this village really raised a farmhouse")
	var checked := 0
	for npc in _farming_markers(spawned, coord):
		if npc.field_cells.is_empty():
			continue
		checked += 1
		assert_true(
			origins.has(npc.stock_building_cell),
			"a farmer works a field for %s, which is no farmhouse" % str(npc.stock_building_cell)
		)
	assert_gt(checked, 0, "precondition: somebody was handed a real field")


## A fisher digs their own water where a farmer sows their own beds -- see
## docs/concept/village_ponds.md. Asked for directly: "The Fisher should
## build a similar 3x2 enclosure but filled with water".
func test_a_fisher_gets_a_real_fenced_pond_beside_their_own_house():
	var coord := _find_settlement_chunk_with_occupation("grassland", "fisher", 3)
	var world := StubWorld.new()
	renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	var built := _built_tiles(world, coord)
	var water: Array = []
	for cell in built:
		if VillagePond.is_pond_tile(built[cell]):
			water.append(cell)
	assert_gt(water.size(), 0, "the village's fisher has nowhere to fish")

	var min_cell: Vector2i = water[0]
	var max_cell: Vector2i = water[0]
	for cell in water:
		min_cell = Vector2i(mini(min_cell.x, (cell as Vector2i).x), mini(min_cell.y, (cell as Vector2i).y))
		max_cell = Vector2i(maxi(max_cell.x, (cell as Vector2i).x), maxi(max_cell.y, (cell as Vector2i).y))
	var size := max_cell - min_cell + Vector2i.ONE
	assert_true(VillageFarm.FIELD_SHAPES.has(size), "a pond spans %s, not a shape that was asked for" % str(size))
	assert_eq(water.size(), size.x * size.y, "the pond has a hole in it")


## And it is FENCED, like the field it is modelled on -- the ask says "a
## similar 3x2 enclosure", and an enclosure is the frame.
func test_a_fishers_pond_is_fenced_like_a_field():
	var coord := _find_settlement_chunk_with_occupation("grassland", "fisher", 3)
	var world := StubWorld.new()
	renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	var built := _built_tiles(world, coord)
	var water: Array = []
	for cell in built:
		if VillagePond.is_pond_tile(built[cell]):
			water.append(cell)
	assert_gt(water.size(), 0, "precondition: a pond was really dug")
	var rails := 0
	for cell in VillageFarm.fence_cells(water, Vector2i.ZERO, VillageFarm.FARM_BUILDING_ID):
		if VillageFarm.is_fence_tile(built.get(cell, "")):
			rails += 1
	assert_gt(rails, 0, "a pond with no frame at all is not an enclosure")


## Nothing is dug twice: a reload re-derives the same pond and builds
## nothing on top of it.
func test_digging_a_pond_twice_leaves_it_exactly_as_it_was():
	var coord := _find_settlement_chunk_with_occupation("grassland", "fisher", 3)
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var first := _built_tiles(world, coord).duplicate(true)
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_eq(_built_tiles(world, coord), first, "a reload changed the village")


## A dug pond is STOCKED: empty water is a hole, and the ask is fish
## swimming in it. The village puts the fisher's own stocking in as it digs.
func test_a_dug_pond_is_stocked_with_real_fish():
	var coord := _find_settlement_chunk_with_occupation("grassland", "fisher", 3)
	var world := StubWorld.new()
	renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	var built := _built_tiles(world, coord)
	var water: Array = []
	for cell in built:
		if VillagePond.is_pond_tile(built[cell]):
			water.append(cell)
	assert_gt(water.size(), 0, "precondition: a pond was dug")
	assert_gt(world.stocked_ponds.size(), 0, "the fisher's pond was left empty")
	var stocked_in_water := false
	for tile in world.stocked_ponds:
		if water.has((tile as Vector2i) - coord * CHUNK_SIZE):
			stocked_in_water = true
	assert_true(stocked_in_water, "something was stocked, but not the pond")
# -- the village sawmill has a worker (docs/concept/village_timber.md) ------
#
# Reported in play: "The sawmill also never produces any beams and doesn't
# even have a dedicated worker".


func _lumberjack_markers(spawned: Array) -> Array:
	var out: Array = []
	for node in spawned:
		if node is NpcMarker and node.identity.occupation == VillageSawmill.OCCUPATION:
			out.append(node)
	return out


func test_a_lumberjack_is_told_which_sawmill_is_theirs():
	var coord := _find_settlement_chunk_with_occupation("grassland", VillageSawmill.OCCUPATION, 3)
	var world := StubWorld.new()
	# Real timber, or the village honestly raises no mill and the test would
	# pass without ever asking its own question.
	_forest_band(world, coord)
	var spawned := renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	var mills := _buildings_of(world, VillageSawmill.SAWMILL_BUILDING_ID)
	assert_gt(mills.size(), 0, "precondition: a village beside timber raised its mill")
	var sawyers := _lumberjack_markers(spawned)
	assert_gt(sawyers.size(), 0, "precondition: somebody in this village works timber")
	var expected: Vector2i = coord * CHUNK_SIZE + mills[0]["origin_local"]
	for sawyer in sawyers:
		assert_eq(
			sawyer.sawmill_cell, expected,
			"a sawyer works the mill their own village raised"
		)


## A villager who is not a lumberjack is never handed one, or every trade
## would be felling trees.
func test_nobody_else_is_handed_a_sawmill():
	var coord := _find_settlement_chunk_with_occupation("grassland", VillageSawmill.OCCUPATION, 3)
	var world := StubWorld.new()
	_forest_band(world, coord)
	var spawned := renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	for node in spawned:
		if node is NpcMarker and node.identity.occupation != VillageSawmill.OCCUPATION:
			assert_eq(
				node.sawmill_cell, NpcMarker.NO_SAWMILL,
				"%s does not work timber" % node.identity.occupation
			)


## A fisher is told which water is theirs and which building they fill --
## the last link of the pond chain, and the same handout a farmer gets.
func test_every_fisher_is_given_their_own_pond_and_their_own_house():
	var coord := _find_settlement_chunk_with_occupation("grassland", "fisher", 3)
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	var built := _built_tiles(world, coord)
	var water: Dictionary = {}
	for cell in built:
		if VillagePond.is_pond_tile(built[cell]):
			water[coord * CHUNK_SIZE + (cell as Vector2i)] = true
	assert_gt(water.size(), 0, "precondition: a pond was dug")
	var checked := 0
	for node in spawned:
		if not (node is NpcMarker) or node.identity.occupation != "fisher":
			continue
		if node.pond_cells.is_empty():
			continue
		checked += 1
		for cell in node.pond_cells:
			assert_true(water.has(cell), "a fisher was handed %s, which is not water" % str(cell))
		assert_ne(
			node.stock_building_cell, NpcMarker.NO_STOCK_BUILDING,
			"a fisher with a pond and nowhere to put the catch"
		)
	assert_gt(checked, 0, "no fisher was handed a pond at all")
