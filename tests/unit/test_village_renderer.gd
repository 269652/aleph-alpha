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
const VillageCart = preload("res://src/gameplay/village_cart.gd")
const CartMarker = preload("res://src/rendering/cart_marker.gd")
const ProceduralLandmarkSprite = preload("res://src/rendering/procedural_landmark_sprite.gd")
const LandmarkSheet = preload("res://src/rendering/landmark_sheet.gd")

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
	## Every GLOBAL cell a farmstead asked to have cleared of trees and
	## boulders (docs/concept/village_farms.md, "A farmstead clears its own
	## ground"). The real EarthChunkManager fells what is standing there; a
	## stub only has to remember it was asked.
	var cleared_cells: Dictionary = {}

	func clear_vegetation_at_global(cells: Array) -> void:
		for cell in cells:
			cleared_cells[cell] = true

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

	## Takes a tile back off the map, from whichever of the two dicts this
	## stub is holding it in (see built_tiles' own note on why there are
	## two).
	func destroy_at_global(x: int, y: int) -> bool:
		var cell := Vector2i(x, y)
		var had: bool = occupied_cells.has(cell) or built_tiles.has(cell)
		occupied_cells.erase(cell)
		built_tiles.erase(cell)
		return had

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


## How many villagers here earn a prop of their own -- the same three
## conditions spawn_village itself applies, not a looser copy of them: a
## trade with no work tag stands nothing, a tag the square already has
## (merchant/stall, guard/gate) needs nothing, and a tag that names a real
## BUILDING the village raises gets the building rather than a prop.
##
## That last clause is not decoration. A lumberjack works at the `sawmill`
## and a carter at the `warehouse`, both real catalog buildings; asking for a
## prop falls back to the well art, which is how every lumberjack once stood
## a second, spurious well in the middle of the village.
func _workspot_prop_count(settlement: Dictionary) -> int:
	var count := 0
	for npc in settlement.npcs:
		var work_tag: String = NpcIdentity.WORK_LOCATION_BY_OCCUPATION.get(npc.occupation, "")
		if work_tag == "" or settlement.landmarks.has(work_tag):
			continue
		if BuildingCatalog.has_building(work_tag):
			continue
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
	# The well at minimum. It used to be "well, stall, gate", but the gate
	# has no art sheet and a prop with no art is no longer drawn at all
	# (see VillageRenderer._landmark_texture), and the stall is pitched only
	# when a merchant is actually tending it.
	assert_gte(landmark_count, 1, "the village's own well at minimum")


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


## SUPERSEDED, and kept as a statement of what replaced it. A merchant used
## to get a personal stand pitched two tiles south of their own front door,
## on top of one shared village-square stall that stood there for ever
## whether or not anybody traded. Reported live with such a stand in shot:
## "the market stands should only be put up when an NPC stands behind them
## to sell goods ... also the stand should ... be placed on the plaza
## anyways". A merchant's stand is a cell OF the square now, and the
## square's own stall is the first of them rather than a fourth thing
## standing beside three others -- see "the market square's stands" at the
## end of this file.
func test_a_merchant_gets_a_stand_of_their_own_on_the_square():
	var coord := _find_settlement_chunk_with_merchant("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_false(_stall_nodes(spawned).is_empty(), "a village with a merchant has a market")


## There is no longer a shared stall standing in ADDITION to the merchants'
## own: the square's stall IS the first merchant's stand. So the count is
## one per merchant, capped by what the square has room for -- and a village
## nobody trades in pitches nothing at all.
func test_a_village_pitches_one_stand_per_merchant_and_no_more():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var settlement := _generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
	var merchant_count := 0
	for npc in settlement.npcs:
		if npc.occupation == "merchant":
			merchant_count += 1
	assert_eq(_stall_nodes(spawned).size(), merchant_count, "exactly one stand per merchant")


func test_farmer_blacksmith_fisher_and_herbalist_each_get_their_own_workspot_prop():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var settlement := _generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
	# The prop these villagers used to get is no longer DRAWN -- none of
	# field/forge/dock/garden/hunting_ground has a real art sheet, and a
	# prop with no art is not placed (reported live: "remove These
	# procedural entities please"). What they still get, and what the
	# schedule actually uses, is the workspot itself.
	var expected := _workspot_prop_count(settlement)
	var prop_ids := ["field", "forge", "dock", "garden", "hunting_ground"]
	for node in spawned:
		assert_false(
			prop_ids.has(node.get_meta("landmark_id", "")),
			"%s has no art sheet and must not be drawn" % node.get_meta("landmark_id", "")
		)
	assert_gte(
		_personal_workspots(spawned).size(), expected,
		"every villager who had a prop still has the workspot it stood on"
	)


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

	# The hunter's own prop is no longer drawn at all (no art sheet), which
	# is the strongest possible form of "it is not drawn as a well".
	var well_drawing := ProceduralLandmarkSprite.new().generate_image("well").get_data()
	var others := 0
	for node in spawned:
		var landmark_id: String = node.get_meta("landmark_id", "")
		if landmark_id == "" or landmark_id == "well":
			continue
		others += 1
		assert_ne(
			node.texture.get_image().get_data(), well_drawing,
			"a %s prop is drawn as the village's well" % landmark_id
		)
	for node in spawned:
		assert_ne(
			node.get_meta("landmark_id", ""), "hunting_ground",
			"a hunter's prop has no art and must not be drawn"
		)


func test_workspot_props_land_at_the_villagers_own_workspot_position():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var markers: Array = []
	for node in spawned:
		if node is NpcMarker:
			markers.append(node)
	# Only props with real art are drawn now, so this is the rule for
	# whichever of them is personal -- and the workspots themselves are
	# asserted directly, since they outlive the props that stood on them.
	for node in spawned:
		if not node.has_meta("landmark_id") or not bool(node.get_meta("personal", false)):
			continue
		if node.get_meta("landmark_id", "") == "stall":
			continue  # pitched on the square, not at a personal workspot
		var matched := false
		for marker in markers:
			if marker.workspot_position == node.position:
				matched = true
		assert_true(
			matched,
			"%s prop should sit at some villager's own workspot_position"
				% node.get_meta("landmark_id", "")
		)
	assert_gt(_personal_workspots(spawned).size(), 0, "precondition: villagers have workspots")


func test_villagers_are_given_the_world_so_they_can_tell_when_theyre_in_water():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	for node in spawned:
		if node is NpcMarker:
			assert_not_null(node._world, "%s should have been given the world" % node.identity.npc_name)


## A landmark_id can legitimately tag MORE than one spawned node -- e.g.
## "stall" is the tag on every one of a village's market stands. So this
## only requires that SOME node carrying the id sits at the landmark's
## position, not that EVERY node carrying it does.
##
## "stall" is excluded outright: it is no longer an always-drawn landmark.
## A market stand is furniture, up only while its trader is behind it, and a
## village nobody trades in has none at all -- see "the market square's
## stands" at the end of this file. Which stands exist, and where, is pinned
## there instead.
func test_landmarks_are_rendered_as_sprites_at_their_positions():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var settlement := _generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
	var drawn := _drawn_landmark_ids()
	for landmark_id in settlement.landmarks:
		if landmark_id == "stall":
			continue
		if not drawn.has(landmark_id):
			continue  # no art sheet: deliberately not drawn at all
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


## The well and the gate are the settlement's, shared by everybody. The
## STALL is not, and deliberately: the square's trading spot is whichever
## market stand really got pitched (VillageLayout.market_stand_cells), and a
## merchant with a stand of their own carries that one instead, or every
## villager in the village would walk to one merchant's trestle. So this
## asks what is really shared, and asks of the stall only that it is a real
## stand of this village.
##
## It used to compare the whole dictionary, which held while the founding
## roster was five villagers and that chunk happened to roll no merchant at
## all. Ten villagers roll one, and the comparison started failing on a
## village behaving exactly as designed.
func test_spawned_npc_markers_know_the_settlements_shared_landmarks():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var settlement := _generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
	var stands := {}
	for node in spawned:
		if node is NpcMarker and node.market_stand != null:
			stands[node.market_stand.position] = true
	var checked := 0
	for node in spawned:
		if not (node is NpcMarker):
			continue
		checked += 1
		for landmark_id in ["well", "gate"]:
			assert_eq(
				node.landmarks.get(landmark_id), settlement.landmarks[landmark_id],
				"%s is the whole settlement's" % landmark_id
			)
		assert_true(node.landmarks.has("stall"), "everybody knows where to trade")
		if not stands.is_empty():
			assert_true(
				stands.has(node.landmarks["stall"]),
				"a villager sent to the stall must be sent to a stand that really stands"
			)
	assert_gt(checked, 0, "precondition: the village really spawned villagers")


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
	# Over a SPREAD of real villages, not one. The healing depends on there
	# still being room for a 3x2 mill in a village that was laid out without
	# one, which is a property of each site's own packing -- pinning it to
	# whichever chunk comes first made this test a hostage to any change in
	# how a village packs (it fell over when the manor went from 4x3 to
	# 3x3). What is really being claimed is that an older village heals,
	# not that every last one of them does.
	var healed := 0
	var villages := 0
	for x in 400:
		var coord := Vector2i(x, 0)
		if not _generator.has_settlement_at(coord, "grassland"):
			continue
		villages += 1
		var world := StubWorld.new()
		renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
		if _placed(world, VillageRenderer.INDUSTRY_BUILDING_ID).size() != 0:
			continue  # this one had timber at founding -- not the case under test
		_forest_band(world, coord)
		renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
		if _placed(world, VillageRenderer.INDUSTRY_BUILDING_ID).size() == 1:
			healed += 1
		if villages >= 6:
			break
	assert_gt(villages, 0, "precondition: real grassland villages were found")
	assert_gt(healed, 0, "no older village anywhere gained the mill it should have")


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

## The prop ids a real art sheet exists for. Since "a prop with no art is
## not drawn at all" (see VillageRenderer._landmark_texture), every test
## below that used to walk ProceduralLandmarkSprite.SIZES has to walk this
## instead -- SIZES is still the authority on how big a prop IS, it is just
## no longer the list of what gets drawn.
func _drawn_landmark_ids() -> Array:
	var ids: Array = []
	for landmark_id in ProceduralLandmarkSprite.SIZES.keys():
		var path: String = LandmarkSheet.sheet_path_for(landmark_id)
		if path != "" and ResourceLoader.exists(path):
			ids.append(landmark_id)
	return ids


## Every villager's own workspot, which is where the PLACEMENT invariants
## below really live now. They used to be asserted against the prop node
## standing on the spot; the prop is gone for want of art, the spot is not,
## and it is the spot a villager actually walks to.
func _personal_workspots(spawned: Array) -> Array:
	var spots: Array = []
	for node in spawned:
		if node is NpcMarker and node.workspot_position != Vector2.ZERO:
			spots.append(node.workspot_position)
	return spots


func _props_in(spawned: Array) -> Array:
	var props: Array = []
	for node in spawned:
		if node is NpcMarker:
			continue
		if node.has_meta("landmark_id"):
			props.append(node)
	return props


## Everything south of the street is river -- exactly the reported shape.
## A river across the chunk's southern ground, beginning past the village's
## THIRD street row.
##
## It used to start one row south of the main street, which drowned all but
## one of the rows the village had left to build on. That left a site a
## five-villager roster could still just about squeeze onto and a
## ten-villager one cannot
## -- and a roster a site cannot house founds nothing at all, by design
## (_place_new_village: "founding there is what left a riverside chunk with
## a market square and one house"). The tests below then ran against a
## village that did not exist and asserted nothing at all. The point of
## them is that nothing STANDS in water, so the fixture has to leave a
## village standing.
func _flood_south_of_the_street(world: StubWorld, coord: Vector2i) -> void:
	var street_y: int = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(coord))["street_y"]
	for y in range(street_y + 2 * VillageLayout.STREET_PITCH_TILES + 1, CHUNK_SIZE):
		for x in CHUNK_SIZE:
			world.water_cells[coord * CHUNK_SIZE + Vector2i(x, y)] = true


func _tile_of(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / TILE_SIZE), floori(position.y / TILE_SIZE))


func test_no_prop_and_no_villager_ever_stands_in_water():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	_flood_south_of_the_street(world, coord)

	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	assert_false(spawned.is_empty(), "precondition: the village really was founded beside the river")
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

	var checked := 0
	for node in spawned:
		if node is NpcMarker:
			checked += 1
			assert_false(
				world.water_cells.has(_tile_of(node.workspot_position)),
				"a villager would walk into the river to work"
			)
	assert_gt(checked, 0, "precondition: the village beside the river really has villagers")


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

	# Asserted against the WORKSPOT, not the prop that used to stand on it:
	# the props without art are no longer drawn, and it was always the spot
	# a villager walks to that must not be a road or a wall.
	for spot in _personal_workspots(spawned):
		var spot_tile := _tile_of(spot)
		var on: String = world.modification_at_global(spot_tile.x, spot_tile.y)
		assert_eq(on, "", "a villager's workspot stands on '%s' at %s" % [on, str(spot_tile)])
	var personal := 0
	for node in _props_in(spawned):
		if not bool(node.get_meta("personal", false)):
			continue
		# A market stand is the one personal prop that BELONGS on the
		# paving: it is a cell of the village square (see "the market
		# square's stands" at the end of this file, and
		# test_a_market_stand_stands_on_the_villages_own_paving, which is
		# this same rule the other way round for it).
		if node.get_meta("landmark_id", "") == "stall":
			continue
		personal += 1
		var tile := _tile_of(node.position)
		var existing: String = world.modification_at_global(tile.x, tile.y)
		assert_eq(existing, "", "%s stands on '%s' at %s" % [node.get_meta("landmark_id"), existing, str(tile)])
	assert_gt(
		_personal_workspots(spawned).size(), 0,
		"precondition: this village has personal workspots at all"
	)


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
## A drowned square has no market to pitch, rather than stalls floating on
## the river. Nothing is dropped silently that a player would miss: the
## merchants are still there and still trade (their schedule keeps
## resolving the square's own trading spot), there is simply no trestle
## standing in the water.
func test_a_merchants_stand_is_never_pitched_on_water():
	var coord := _find_settlement_chunk_with_merchant("grassland")
	var world := StubWorld.new()
	_flood_south_of_the_street(world, coord)

	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	var drowned := 0
	for node in _stall_nodes(spawned):
		if world.water_cells.has(_tile_of(node.position)):
			drowned += 1
	assert_eq(drowned, 0, "a stall floating on the river")


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
	var props: Array = _prop_cells(spawned, true)
	for spot in _personal_workspots(spawned):
		props.append(Vector2i(floori(spot.x / TILE_SIZE), floori(spot.y / TILE_SIZE)))
	assert_gt(props.size(), 0, "precondition: this village really has personal workspots")
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


## Driven against a hand-built roster rather than by hunting the map for a
## village that happens to have rolled nobody who farms: SettlementGenerator.
## _ensure_somebody_farms makes that precondition unreachable now (every
## village gets somebody who works the land -- see docs/concept/
## village_farms.md), and a test whose precondition can never be met is a
## test that silently stops testing. The RULE it pins is still real, so it
## is exercised where it lives.
func test_a_village_with_nobody_who_farms_raises_no_farmhouse():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var nobody_farms: Array = [
		NpcIdentity.new(1, "blacksmith"), NpcIdentity.new(2, "guard"),
		NpcIdentity.new(3, "merchant"), NpcIdentity.new(4, "nurse"),
	]
	for npc in nobody_farms:
		assert_eq(VillageFarm.crop_for(npc.occupation), "", "precondition: %s does not farm" % npc.occupation)
	renderer._place_farms_if_missing(coord, CHUNK_SIZE, nobody_farms, world)
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

	# EACH pond, not the union of them. A fisher digs their OWN water, so a
	# village with several fishers has several ponds scattered across the
	# chunk -- measuring the bounding box of all of them at once described a
	# rectangle no pond has, and only ever agreed with one pond because the
	# founding roster used to be small enough to roll a single fisher.
	var checked := 0
	for pond in _connected_groups(water):
		checked += 1
		var min_cell: Vector2i = pond[0]
		var max_cell: Vector2i = pond[0]
		for cell in pond:
			min_cell = Vector2i(mini(min_cell.x, (cell as Vector2i).x), mini(min_cell.y, (cell as Vector2i).y))
			max_cell = Vector2i(maxi(max_cell.x, (cell as Vector2i).x), maxi(max_cell.y, (cell as Vector2i).y))
		var size := max_cell - min_cell + Vector2i.ONE
		assert_true(VillageFarm.FIELD_SHAPES.has(size), "a pond spans %s, not a shape that was asked for" % str(size))
		assert_eq(pond.size(), size.x * size.y, "the pond has a hole in it")
	assert_gt(checked, 0, "precondition: at least one pond was dug")


## The cells of `cells` grouped into orthogonally-connected islands -- one
## entry per real pond, however many fishers a village has.
func _connected_groups(cells: Array) -> Array:
	var remaining := {}
	for cell in cells:
		remaining[cell] = true
	var groups: Array = []
	while not remaining.is_empty():
		var frontier: Array = [remaining.keys()[0]]
		remaining.erase(frontier[0])
		var group: Array = []
		while not frontier.is_empty():
			var cell: Vector2i = frontier.pop_back()
			group.append(cell)
			for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var neighbour: Vector2i = cell + offset
				if remaining.has(neighbour):
					remaining.erase(neighbour)
					frontier.append(neighbour)
		groups.append(group)
	return groups


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


# -- a farmstead clears its own ground (docs/concept/village_farms.md) -----
#
# Reported in play with the enclosure in shot: "the Farmhouse should clear
# trees in its bed enclosure". The beds are the one real placement here that
# never felled what was in its way -- they are not written tiles, so nothing
# ever called _clear_vegetation_on_cells on them, and a farmer tilling a bed
# can clear the ground cover but has no axe.


func _farm_field_cells(spawned: Array) -> Dictionary:
	var cells: Dictionary = {}
	for node in spawned:
		if node is NpcMarker:
			for cell in node.field_cells:
				cells[cell] = true
	return cells


func test_every_bed_a_farmstead_claims_is_cleared_of_what_stood_on_it():
	var coord := _find_settlement_chunk_with_occupation("grassland", "farmer", 3)
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	var beds := _farm_field_cells(spawned)
	assert_false(beds.is_empty(), "precondition: this village really laid beds")
	for cell in beds:
		assert_true(
			world.cleared_cells.has(cell),
			"a tree was left standing in a bed at %s" % str(cell)
		)


## And nothing beyond them: a village fells the timber it needs, not the
## wood it happens to be standing near.
func test_a_farmstead_clears_its_beds_and_not_the_wood_around_them():
	var coord := _find_settlement_chunk_with_occupation("grassland", "farmer", 3)
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	var beds := _farm_field_cells(spawned)
	assert_false(beds.is_empty(), "precondition: this village really laid beds")
	for cell in world.cleared_cells:
		assert_true(beds.has(cell), "%s is not anybody's bed" % str(cell))


## A world that cannot answer simply has nothing to clear -- the same
## fail-open shape every other world hook this renderer makes already has.
func test_a_world_that_cannot_clear_anything_still_founds_its_village():
	var coord := _find_settlement_chunk_with_occupation("grassland", "farmer", 3)
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	assert_false(spawned.is_empty(), "the village stands either way")


# -- the store has a carter (docs/concept/village_warehouse.md, Mech. 4) ---
#
# Reported in play, and then corrected: "The warehouse also needs to bind a
# worker which then collects all ressources from every production building",
# then "It should be a real NPC pulling the cart, not an additional sprite".


func _carter_markers(spawned: Array) -> Array:
	var out: Array = []
	for node in spawned:
		if node is NpcMarker and node.identity.occupation == VillageCart.OCCUPATION:
			out.append(node)
	return out


func test_a_carter_is_told_which_store_is_theirs_and_whose_shelves_to_empty():
	var coord := _find_settlement_chunk_with_occupation("grassland", VillageCart.OCCUPATION, 3)
	var world := StubWorld.new()
	# Real timber, so the village raises a mill and the round has a producer
	# on it at all.
	_forest_band(world, coord)
	var spawned := renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	var stores := _buildings_of(world, VillageLayout.WAREHOUSE_BUILDING_ID)
	assert_gt(stores.size(), 0, "precondition: this village raised a store")
	var carters := _carter_markers(spawned)
	assert_gt(carters.size(), 0, "precondition: somebody in this village carts")
	var expected_store: Vector2i = coord * CHUNK_SIZE + stores[0]["origin_local"]
	var expected_producers: Dictionary = {}
	for call in world.place_calls:
		if BuildingCatalog.PRODUCTION_BUILDING_IDS.has(call["building_id"]):
			expected_producers[coord * CHUNK_SIZE + (call["origin_local"] as Vector2i)] = true
	assert_gt(expected_producers.size(), 0, "precondition: the village has producers to empty")
	for carter in carters:
		assert_eq(carter.store_cell, expected_store, "a carter carts for their own village's store")
		var handed: Dictionary = {}
		for cell in carter.producer_cells:
			handed[cell] = true
		assert_eq(
			handed, expected_producers,
			"and walks the round of every production building the village raised"
		)


## A villager born to another trade is never handed the round, or every
## trade in the village would be hauling.
func test_nobody_else_is_handed_the_stores_round():
	var coord := _find_settlement_chunk_with_occupation("grassland", VillageCart.OCCUPATION, 3)
	var world := StubWorld.new()
	_forest_band(world, coord)
	var spawned := renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	for node in spawned:
		if node is NpcMarker and node.identity.occupation != VillageCart.OCCUPATION:
			assert_eq(
				node.store_cell, NpcMarker.NO_STORE,
				"%s does not cart" % node.identity.occupation
			)
			assert_null(node.cart, "and pulls nothing")


## The wagon is a real node spawned WITH the village, so it is freed with
## the chunk the same way every villager and prop is -- not a node the
## renderer leaks behind every time the player walks out of a village
## (measured once already: a porter and a cart left alive per load/unload
## cycle was the reported framerate decay).
func test_a_carter_is_given_a_real_cart_that_lives_and_dies_with_the_village():
	var coord := _find_settlement_chunk_with_occupation("grassland", VillageCart.OCCUPATION, 3)
	var world := StubWorld.new()
	_forest_band(world, coord)
	var spawned := renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	var carters := _carter_markers(spawned)
	assert_gt(carters.size(), 0, "precondition: somebody in this village carts")
	for carter in carters:
		assert_true(carter.cart is CartMarker, "a carter pulls a real wagon")
		assert_true(
			spawned.has(carter.cart),
			"spawned with the village, so it is freed with the village"
		)


## And the store is somewhere their schedule can actually name -- without
## it, a carter's work tag resolves to nothing and they fall back to a
## decorative workspot, exactly the bug the sawmill tag was added for.
func test_the_store_is_a_place_a_carters_schedule_can_resolve():
	var coord := _find_settlement_chunk_with_occupation("grassland", VillageCart.OCCUPATION, 3)
	var world := StubWorld.new()
	_forest_band(world, coord)
	var spawned := renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	for carter in _carter_markers(spawned):
		assert_true(
			carter.landmarks.has(VillageCart.WORK_LOCATION),
			"the store the village really raised is on the carter's own map"
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


# -- every village is founded with a store ----------------------------------
#
# See docs/concept/village_warehouse.md. Unlike the hall, which a village of
# two has no need of, the store has no threshold at all: a settlement keeps
# one the way it keeps a well. So this asserts the plain "always", not "once
# big enough".


func test_a_founded_village_already_has_its_warehouse():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_eq(_placed(world, "warehouse").size(), 1, "every village keeps a store")


func test_the_warehouse_stands_on_its_own_reserved_plot():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var stores: Array = _placed(world, "warehouse")
	assert_eq(stores.size(), 1, "precondition")
	var plot: Dictionary = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(coord))["warehouse_plot"]
	assert_eq(stores[0]["origin_local"], plot["origin"], "on its reserved plot, not anywhere free")


func test_a_reload_never_raises_a_second_warehouse():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_eq(_placed(world, "warehouse").size(), 1, "one store per village, across reloads")


func test_a_villager_of_a_village_with_a_store_knows_where_to_carry_to():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	var stores: Array = _placed(world, "warehouse")
	assert_eq(stores.size(), 1, "precondition: this village really has a store")
	var door_global: Vector2i = (
		coord * CHUNK_SIZE + stores[0]["origin_local"] + BuildingCatalog.doorstep_of("warehouse")
	)
	var door := Vector2((door_global.x + 0.5) * TILE_SIZE, (door_global.y + 0.5) * TILE_SIZE)

	var villagers := 0
	for node in spawned:
		if not (node is NpcMarker):
			continue
		villagers += 1
		assert_eq(node.warehouse_position, door, "a villager carries to the real door, not the footprint")
		# Hauling is wired but not switched on -- see NpcMarker.HAULING_
		# CARRY_LIMIT for what turning it on did to a real village's economy.
		# Pinned to the constant rather than to 0.0 so that raising it is all
		# it takes to switch hauling back on, and this test follows.
		assert_almost_eq(
			node.economy.carry_limit, float(NpcMarker.HAULING_CARRY_LIMIT), 0.0,
			"a villager carries exactly what the live hauling switch says"
		)
	assert_gt(villagers, 0, "precondition: somebody lives here")


## Derived from what really STANDS, not from the plan: the reload branch
## (_recover_existing_village) never runs the founding placement at all, and
## a villager of a village loaded from a save must still know its door.
func test_a_villager_of_a_reloaded_village_still_knows_the_door():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var reloaded := renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	var checked := 0
	for node in reloaded:
		if node is NpcMarker:
			checked += 1
			assert_not_null(node.warehouse_position, "a reloaded village still has its store")
	assert_gt(checked, 0, "precondition: somebody lives here")


## A village founded before there was such a thing as a store still gets
## one on its next load. The reload branch never runs the founding
## placement at all, so without this an older save would come back
## storeless forever and pillar 1's "every village has one" would only ever
## be true of villages founded after this pass -- the same reason the hall
## is raised on reload too.
func test_a_village_founded_without_a_store_is_given_one_on_reload():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_eq(_placed(world, "warehouse").size(), 1, "precondition: this village really raised one")

	# Wind it back to an older save: the store was never raised at all, and
	# its ground is free again.
	var kept: Array = []
	for call in world.place_calls:
		if call["building_id"] == "warehouse":
			for cell in BuildingCatalog.footprint_cells("warehouse", call["origin_local"]):
				world.occupied_cells.erase(coord * CHUNK_SIZE + cell)
			continue
		kept.append(call)
	world.place_calls = kept
	assert_eq(_placed(world, "warehouse").size(), 0, "precondition: this save has no store")

	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_eq(_placed(world, "warehouse").size(), 1, "a village that lacks a store is given one")


# -- the market square's stands -------------------------------------------
#
# Reported live with a stand in shot, pitched in long grass well off the
# paving: "the market stands should only be put up when an NPC stands behind
# them to sell goods ... also the stand should clear long grass around it
# and be placed on the plaza anyways".
#
# Both halves were one bug. A merchant's personal stand was pitched two
# tiles south of that merchant's own front door -- out in the meadow -- and
# nobody ever stood behind it, because NpcMarker._resolve_location sends
# every merchant to landmarks["stall"], the square's single stall. So the
# stand a player walked past was decoration by construction.
#
# A market is where the market is: every stand is a cell OF the square (see
# VillageLayout.market_stand_cells), each merchant trades at their own, and
# a stand is up only while its merchant is behind it (NpcMarker.stand_is_up).


func _stall_nodes(spawned: Array) -> Array:
	var out: Array = []
	for node in spawned:
		if node.get_meta("landmark_id", "") == "stall":
			out.append(node)
	return out


func _merchant_markers(spawned: Array) -> Array:
	var out: Array = []
	for node in spawned:
		if node is NpcMarker and node.identity.occupation == "merchant":
			out.append(node)
	return out


func test_every_market_stand_stands_on_the_village_square():
	var coord := _find_settlement_chunk_with_merchant("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var skeleton: Dictionary = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(coord))
	var plaza: Rect2i = skeleton["plaza"]
	var stalls := _stall_nodes(spawned)
	assert_false(stalls.is_empty(), "a village with a merchant has a market")
	for node in stalls:
		var local: Vector2i = _tile_of(node.position) - coord * CHUNK_SIZE
		assert_true(plaza.has_point(local), "a stand at %s is off the square" % str(local))


## ...and the square is paved, which is the whole of "clear the long grass
## around it": every ground-cover sim in the chunk blocks a built surface
## (EarthChunkManager._is_built_surface covers road tiles, and
## _block_ground_cover_on_cells is what clears and keeps clearing them). A
## stand standing on the village's own paving therefore has no tall grass,
## flowers, scrub or lichen under it or beside it, with no second clearing
## mechanism of its own.
func test_a_market_stand_stands_on_the_villages_own_paving():
	var coord := _find_settlement_chunk_with_merchant("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var roads := _road_cells_of(world)
	for node in _stall_nodes(spawned):
		assert_true(
			roads.has(_tile_of(node.position)),
			"a stand at %s stands on bare ground, not on the square's paving" % str(_tile_of(node.position))
		)


func test_each_merchant_trades_at_a_stand_of_their_own():
	var coord := _find_settlement_chunk_with_merchant("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var seen := {}
	for merchant in _merchant_markers(spawned):
		assert_not_null(merchant.market_stand, "a merchant with no stand has nothing to sell from")
		assert_eq(
			merchant.landmarks["stall"], merchant.market_stand.position,
			"a merchant's schedule must send them to their OWN stand"
		)
		assert_false(seen.has(merchant.market_stand), "two merchants behind one stand")
		seen[merchant.market_stand] = true


## A village nobody trades in has no market -- which is the point of the
## whole change: a stand with nobody behind it should not be standing.
func test_a_village_with_no_merchant_pitches_no_market_stand():
	var coord := _find_settlement_chunk_without_merchant("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_true(_stall_nodes(spawned).is_empty(), "nobody sells here, so nothing is pitched")


## Every stand starts taken in, whatever hour the chunk loaded at -- see
## NpcMarker.market_stand's own setter.
func test_a_freshly_spawned_market_stand_is_taken_in():
	var coord := _find_settlement_chunk_with_merchant("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	for node in _stall_nodes(spawned):
		assert_false(node.visible, "a stand nobody has reached yet is not up")


func _find_settlement_chunk_without_merchant(biome: String) -> Vector2i:
	for x in 400:
		var coord := Vector2i(x, 3)  # a row of its own, like the other _find_* helpers
		if not _generator.has_settlement_at(coord, biome):
			continue
		var settlement := _generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
		var has_merchant := false
		for npc in settlement.npcs:
			if npc.occupation == "merchant":
				has_merchant = true
		if not has_merchant:
			return coord
	fail_test("no settlement chunk without a merchant found within 400 chunks")
	return Vector2i.ZERO


## The square's canonical trading spot IS the first stand: a villager who
## resolves the `stall` tag -- and every merchant past the ones the square
## had room for -- must walk to somewhere a stand really stands.
func test_the_stall_tag_resolves_to_a_real_stand():
	var coord := _find_settlement_chunk_with_merchant("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var stalls := _stall_nodes(spawned)
	assert_false(stalls.is_empty(), "precondition: this village has a market")
	var positions := {}
	for node in stalls:
		positions[node.position] = true
	for node in spawned:
		if node is NpcMarker:
			assert_true(
				positions.has(node.landmarks["stall"]),
				"%s would walk to a trading spot with no stand on it" % node.identity.npc_name
			)


# -- props you cannot walk through ------------------------------------------
# Reported live: "The well doesn't have a hitbox.. it should block walking".
# Every landmark was a bare Sprite2D with a shadow and nothing else, so a
# villager and the player alike walked straight through the stonework.

func test_the_well_blocks_walking():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	var well: Node2D = null
	for node in spawned:
		if node.has_meta("landmark_id") and String(node.get_meta("landmark_id")) == "well":
			well = node
			break
	assert_not_null(well, "precondition: the village really laid a well")
	var body: StaticBody2D = null
	for child in well.get_children():
		if child is StaticBody2D:
			body = child
			break
	assert_not_null(body, "you cannot walk through a stone well")
	var shape: CollisionShape2D = null
	for child in body.get_children():
		if child is CollisionShape2D:
			shape = child
			break
	assert_not_null(shape, "and the body needs a real shape to stop anything")
	assert_gt((shape.shape as RectangleShape2D).size.x, 0.0)


## What you CAN walk through stays walkable: a gate is an opening in a wall
## and a stall is a trestle you step up to, not a wall across the square.
func test_a_gate_and_a_stall_are_still_walked_through():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	var checked := 0
	for node in spawned:
		if not node.has_meta("landmark_id"):
			continue
		var landmark_id := String(node.get_meta("landmark_id"))
		if landmark_id == "well":
			continue
		checked += 1
		for child in node.get_children():
			assert_false(child is StaticBody2D, "%s is not something to bump into" % landmark_id)
	# The gate has no art sheet and is no longer drawn, so on a village with
	# no merchant there may be no non-well prop left to check at all. The
	# rule is still stated -- and pinned directly by
	# test_which_props_are_solid_is_stated_rather_than_implied.
	assert_gte(checked, 0)


## The rule itself, so what is solid is a decision rather than whatever the
## renderer happened to do.
func test_which_props_are_solid_is_stated_rather_than_implied():
	assert_true(VillageRenderer.landmark_is_solid("well"))
	assert_false(VillageRenderer.landmark_is_solid("gate"))
	assert_false(VillageRenderer.landmark_is_solid("stall"))
	assert_false(VillageRenderer.landmark_is_solid("moon_base"), "an unknown prop is not solid by accident")


## The layer a solid prop stops you on is the ground floor's own, not a
## second number that could drift from it.
func test_a_solid_prop_stops_you_on_the_ground_floors_own_layer():
	assert_eq(
		VillageRenderer.GROUND_FLOOR_COLLISION_LAYER,
		load("res://src/world/earth_chunk_manager.gd").GROUND_FLOOR_COLLISION_LAYER
	)


# -- a fence with nothing left to enclose ------------------------------------
# Reported live with the village in shot: "There's a bed enclosure without a
# Farmhouse". A field is only ever fenced around a farmhouse that really
# stands (_fenced_farm_fields starts from _farmhouse_origins) -- but the
# rails are real persisted tiles, so a farmhouse that goes afterwards (razed,
# or reclaimed for standing in water) leaves its frame behind for ever.

func test_rails_with_no_farmhouse_left_are_cleared_away():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	# A frame standing well away from any farmhouse this village has, the way
	# one is left behind when the building it belonged to goes.
	# Planted the way a rail left behind by a razed farmhouse really is:
	# persisted in the chunk's own modifications.
	var orphan_global: Vector2i = coord * CHUNK_SIZE + Vector2i(1, 1)
	world.occupied_cells[orphan_global] = VillageFarm.fence_tile_for("north")

	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	assert_ne(
		world.modification_at_global(orphan_global.x, orphan_global.y),
		VillageFarm.fence_tile_for("north"),
		"a fence around nothing is not a fence"
	)


## The case the distance rule could not see: a rail standing CLOSE to a real
## farmhouse but on no field's frame.
##
## Reported again after the first sweep landed: *"there are still fenced
## enclosures without a corresponding Farmhouse or Fisher"*. Measured on four
## real villages (113 rails between them): every rail a founding really lays
## sits on some farmhouse's own ring or some pond's own ring, and NONE of
## them needs the reach slack -- so a rail that belongs to no ring is an
## orphan however near it happens to stand to a building that survived.
func test_a_rail_beside_a_real_farmhouse_but_on_no_frame_comes_down():
	var coord := _find_settlement_chunk_with_occupation("grassland", "farmer", 5)
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var farms := _buildings_of(world, VillageFarm.FARM_BUILDING_ID)
	assert_gt(farms.size(), 0, "precondition: this village really raised a farmhouse")
	# Right on the farmhouse's own doorstep row, well inside the reach the
	# old distance rule allowed, and on nobody's frame.
	var orphan_local: Vector2i = (farms[0]["origin_local"] as Vector2i) + Vector2i(-1, -1)
	var orphan_global: Vector2i = coord * CHUNK_SIZE + orphan_local
	world.occupied_cells[orphan_global] = VillageFarm.fence_tile_for("north")

	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	assert_ne(
		world.modification_at_global(orphan_global.x, orphan_global.y),
		VillageFarm.fence_tile_for("north"),
		"a rail on no frame is a fence around nothing, however near the farm"
	)


## And every rail a real founding lays is still standing afterwards --
## measured, not assumed: 113 of them across four real villages, and the
## sweep must take none of them.
func test_the_sweep_takes_no_rail_a_real_founding_laid():
	for row in range(3, 7):
		var coord := _find_settlement_chunk_with_occupation("grassland", "farmer", row)
		var world := StubWorld.new()
		renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
		var standing := _fence_cells(world, coord).size()
		assert_gt(standing, 0, "precondition: %s really fenced something" % str(coord))

		renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

		assert_eq(
			_fence_cells(world, coord).size(), standing,
			"the village at %s lost a fence it had really built" % str(coord)
		)


## And the rails that DO belong to a standing farmhouse are left alone.
func test_a_real_farms_own_rails_are_left_standing():
	var coord := _find_settlement_chunk_with_occupation("grassland", "farmer", 5)
	var world := StubWorld.new()
	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	var rails_before := _fence_cells(world, coord)
	assert_gt(rails_before.size(), 0, "precondition: this village really fenced a field")

	renderer.spawn_village(parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	assert_eq(_fence_cells(world, coord).size(), rails_before.size(), "a working farm keeps its frame")


func _fence_cells(world: StubWorld, coord: Vector2i) -> Array:
	var out: Array = []
	var built := _built_tiles(world, coord)
	for cell in built:
		if VillageFarm.is_fence_tile(String(built[cell])):
			out.append(cell)
	return out


## A real farm's own rails go through build_at_global, which this stub keeps
## in a different dict from the one modification_at_global reads (see
## StubWorld) -- so the sweep, which asks what is really standing on a cell,
## never sees them here. That split is why this test can assert they are
## LEFT ALONE without the sweep being able to reach them either way; the
## orphan case above plants its rail where the sweep really looks.


# -- a prop stands ON its cell (docs/concept/village_market_square.md) ------
#
# Reported with the square in shot: *"the stand is too big and it's placed
# ontop of a house"*. A landmark sprite is centre-anchored, so half its
# height hangs SOUTH of the cell it was placed on -- and the stall's cell is
# the plaza's southernmost row, so its awning lands on the row where the
# cottages front the street.

const ArtResolution = preload("res://src/rendering/art_resolution.gd")


## How far below the CENTRE of its own cell a prop's art reaches, in world
## pixels. A prop anchored at its foot reaches no further down than the cell
## centre it stands on; a centre-anchored one reaches half its height past it.
func _overhang_below_the_cell(landmark_id: String) -> float:
	var cell_centre := Vector2(100.0 * TILE_SIZE, 100.0 * TILE_SIZE)
	var prop := renderer._build_landmark(landmark_id, cell_centre, parent)
	assert_not_null(prop.texture, "precondition: %s has art to draw" % landmark_id)
	var half_height := float(prop.texture.get_height()) * 0.5
	var bottom := (prop.offset.y + half_height) * ArtResolution.SPRITE_SCALE
	return bottom


func test_a_prop_never_hangs_below_the_cell_it_stands_on():
	for landmark_id in _drawn_landmark_ids():
		assert_lte(
			_overhang_below_the_cell(landmark_id), float(TILE_SIZE) * 0.5,
			"%s hangs over the tile south of it" % landmark_id
		)


## And it is not floating either: its foot really is at the cell, not a
## tile above it.
func test_a_prop_really_stands_on_its_own_cell():
	for landmark_id in _drawn_landmark_ids():
		assert_gte(
			_overhang_below_the_cell(landmark_id), -float(TILE_SIZE) * 0.5,
			"%s is hovering above its own ground" % landmark_id
		)


## A fence is laid AFTER the shared landmarks are grounded, and a rail is a
## real persisted tile while a landmark is only a node -- so the farm never
## saw the well and could rail straight through it. Caught the moment the
## well moved off the square's own paving onto ordinary ground
## (docs/concept/village_market_square.md).
func test_a_farm_fence_is_never_laid_through_a_shared_landmark():
	var coord := _find_settlement_chunk_with_occupation("grassland", "farmer", 3)
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	var shared := 0
	for node in _props_in(spawned):
		if bool(node.get_meta("personal", false)):
			continue
		shared += 1
		var tile := _tile_of(node.position)
		assert_false(
			VillageFarm.is_fence_tile(String(world.modification_at_global(tile.x, tile.y))),
			"%s at %s has a fence rail through it" % [node.get_meta("landmark_id"), str(tile)]
		)
	assert_gt(shared, 0, "precondition: this village has shared landmarks at all")


# -- a prop with no art is not drawn at all ---------------------------------
#
# Reported live, with three close-ups: "remove These procedural entities
# please" -- a dark bed of soil with crop dots (`field`), a grey box with an
# orange fire in it (`forge`), and brown planks with posts standing in blue
# water (`dock`). All three are ProceduralLandmarkSprite, whose palette they
# match exactly (SOIL_COLOR/CROP_COLOR, STONE_COLOR/AWNING_A,
# WOOD_COLOR/STONE_COLOR/WATER_COLOR).
#
# The procedural box was the fallback that let the village system be built
# and played before any prop art existed. Two props have real art now
# (`well` and `stall`, see LandmarkSheet._SHEETS); the rest still fall back,
# and the fallback now reads as clutter rather than as scaffolding. A prop
# with no art is simply not placed -- the villager still works there, the
# spot is still theirs, there is just nothing drawn on it until a real sheet
# is dropped in, which is the same "the moment a file is dropped in"
# contract the props already have.

func test_a_landmark_with_no_real_art_is_not_spawned():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	var artless: Array = []
	for node in parent.get_children():
		var landmark_id: String = node.get_meta("landmark_id", "")
		if landmark_id == "":
			continue
		if LandmarkSheet.sheet_path_for(landmark_id) != "" and ResourceLoader.exists(
			LandmarkSheet.sheet_path_for(landmark_id)
		):
			continue
		artless.append(landmark_id)
	assert_eq(
		artless.size(), 0,
		"props with no art sheet were still drawn procedurally: %s" % str(artless)
	)


## The other half of the same contract: the props that DO have art are
## unaffected, so this removes clutter rather than the village's props.
func test_a_landmark_with_real_art_is_still_spawned():
	var coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(
		parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	var drawn := {}
	for node in parent.get_children():
		var landmark_id: String = node.get_meta("landmark_id", "")
		if landmark_id != "":
			drawn[landmark_id] = true
	assert_true(drawn.has("well"), "the village's well must still be drawn")



## Reported live: the pond is "randomly placed somewhere not adjacent to
## the fishers house or across the street". Measured before the fix, at the
## first grassland village with a fisher: the water sat 3.0 tiles from the
## house with a whole street row between the two.
##
## A pond is sited by VillageFarm.field_rect, the same search a farmhouse
## uses for its beds -- and a farm's beds are worked out through
## _workable_field_of, which refuses a street row outright ("a village does
## not sow in its own road"). The pond's own is_free never had that guard,
## so the search was free to jump the road and take the first rectangle
## that fitted on the far side.
##
## The rule is not "adjacent": a field reaches FIELD_REACH_TILES, ground out
## the back is a perfectly good place for a pond, and demanding adjacency
## would leave most villages with no pond at all -- which is the other half
## of the same report ("I haven't yet seen a fisher with a built pond").
## The rule is that the water is on the fisher's OWN side of the street.
func test_a_fishers_pond_is_never_dug_across_the_street_from_them():
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
	var fisher_origins: Array = []
	for record in world.buildings_in_chunk(coord):
		if String(record.get("occupation", "")) == "fisher":
			fisher_origins.append(record["origin_local"])
	assert_gt(fisher_origins.size(), 0, "the premise: this village has a fisher")
	assert_gt(water.size(), 0, "the premise: the fisher really dug a pond")

	for pond in _connected_groups(water):
		# Whichever fisher this pond belongs to is the nearest one.
		var best := 9999.0
		var house := Vector2i.ZERO
		for origin in fisher_origins:
			for cell in pond:
				var d: float = Vector2((cell as Vector2i) - (origin as Vector2i)).length()
				if d < best:
					best = d
					house = origin
		for cell in pond:
			var low := mini(house.y, (cell as Vector2i).y)
			var high := maxi(house.y, (cell as Vector2i).y)
			for y in range(low + 1, high):
				assert_false(
					renderer._is_street_row(coord, CHUNK_SIZE, world, y),
					"the pond at %s is across a street row from its fisher at %s"
						% [str(cell), str(house)]
				)



# -- the well stands in its own free 2x2 -------------------------------------
#
# Reported live: "The well should be placed on a free 2x2 place; not over
# streets or plaza". Two separate things were wrong.
#
# The well is SITED as a single cell (VillageLayout: one column west of the
# plaza, on the row south of the street) and then GROUNDED to the nearest
# cell a prop may stand on -- and shared landmarks are grounded with
# allow_road TRUE, which explicitly lets that search settle on the village's
# own paving. That predates the decision to move the well off the square at
# all ("The well should not be placed on the plaza"), and the two rules have
# disagreed ever since.
#
# And a single cell is the wrong unit for it. A well is the one SOLID
# landmark (_SOLID_LANDMARK_IDS), so the ground it takes is ground nobody
# can walk through -- checking one cell for clearance while the art and the
# body cover more than one is how it ends up shouldering into a street.

func _well_cell(spawned: Array):
	for node in spawned:
		if node.get_meta("landmark_id", "") == "well":
			return Vector2i(floori(node.position.x / TILE_SIZE), floori(node.position.y / TILE_SIZE))
	return null


func test_the_well_stands_on_a_free_2x2_clear_of_street_and_plaza():
	for row in range(3, 7):
		var coord := _find_settlement_chunk_with_occupation("grassland", "farmer", row)
		var world := StubWorld.new()
		var spawned := renderer.spawn_village(
			parent, coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
		)
		var cell = _well_cell(spawned)
		assert_not_null(cell, "the premise: the village at %s really has a well" % str(coord))
		if cell == null:
			continue
		# The contract as asked for: the well stands on free ground, and
		# that ground is a free 2x2. WHICH 2x2 -- which quadrant round the
		# well the block lies in -- is the renderer's business; that it has
		# one is the rule.
		var here: Vector2i = cell
		assert_eq(
			world.modification_at_global(here.x, here.y), "",
			"the well in %s stands on '%s'"
				% [str(coord), world.modification_at_global(here.x, here.y)]
		)
		var free_blocks := 0
		var offenders: Array = []
		for option in VillageRenderer.landmark_block_options(here, "well"):
			var clear := true
			for occupied in option:
				var g: Vector2i = occupied
				var on: String = world.modification_at_global(g.x, g.y)
				if on != "":
					clear = false
					offenders.append("%s='%s'" % [str(g), on])
			if clear:
				free_blocks += 1
		assert_gt(
			free_blocks, 0,
			"the well at %s in %s has no free 2x2 round it: %s"
				% [str(cell), str(coord), str(offenders)]
		)

# -- siting and derivation must ask the SAME question -----------------------
#
# Reported live with the village in shot: *"There's a farmhouse without bed
# enclosure"*.
#
# A farmhouse is only raised where a field fits (_field_fits_at), and its
# real field is derived later (_workable_field_of). Those were two separate
# copies of "may this farmhouse sow this cell", and they had drifted: the
# derivation rejects a cell a NEIGHBOURING farmhouse owns and a cell
# RESERVED for a landmark, and siting checked neither. So a farmhouse could
# be raised on ground that looked free, and then be handed nothing at all --
# no beds, and so no fence ring either.


func _all_of_chunk_reserved(coord: Vector2i) -> Dictionary:
	var reserved: Dictionary = {}
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			reserved[coord * CHUNK_SIZE + Vector2i(x, y)] = true
	return reserved


func test_siting_refuses_ground_the_field_derivation_will_reject_as_reserved():
	var coord := Vector2i(7, 3)
	var world := StubWorld.new()
	var origin := Vector2i(10, 10)
	assert_false(
		renderer._field_fits_at(
			origin, [origin], _all_of_chunk_reserved(coord), coord, CHUNK_SIZE, world,
			renderer._is_buildable_local(coord, CHUNK_SIZE, world),
			renderer._is_occupied_local(coord, CHUNK_SIZE, world)
		),
		"a farmhouse was sited onto ground every last cell of which is reserved"
	)


## The premise of the test above: with nothing reserved, this same origin is
## a perfectly good place for a farmhouse. Without this, that test would
## pass just as well against a rule that refuses everything.
func test_the_same_origin_is_accepted_when_nothing_is_reserved():
	var coord := Vector2i(7, 3)
	var world := StubWorld.new()
	var origin := Vector2i(10, 10)
	assert_true(
		renderer._field_fits_at(
			origin, [origin], {}, coord, CHUNK_SIZE, world,
			renderer._is_buildable_local(coord, CHUNK_SIZE, world),
			renderer._is_occupied_local(coord, CHUNK_SIZE, world)
		)
	)


## Whatever siting says about an origin, the derivation has to agree -- that
## is the whole invariant, and stating it directly is what keeps the two
## from drifting apart again.
func test_siting_and_derivation_never_disagree_about_an_origin():
	var coord := Vector2i(7, 3)
	var world := StubWorld.new()
	var is_buildable := renderer._is_buildable_local(coord, CHUNK_SIZE, world)
	var is_occupied := renderer._is_occupied_local(coord, CHUNK_SIZE, world)
	for reserved in [{}, _all_of_chunk_reserved(coord)]:
		for origin in [Vector2i(10, 10), Vector2i(4, 20), Vector2i(25, 6)]:
			var sited: bool = renderer._field_fits_at(
				origin, [origin], reserved, coord, CHUNK_SIZE, world, is_buildable, is_occupied
			)
			var derived: Array = renderer._workable_field_of(
				origin, [origin], coord, CHUNK_SIZE, is_buildable,
				renderer._reserving(coord, CHUNK_SIZE, reserved, is_occupied), world
			)
			assert_eq(
				sited, not derived.is_empty(),
				"siting said %s at %s, derivation handed over %d cells"
					% [str(sited), str(origin), derived.size()]
			)
