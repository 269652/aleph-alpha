extends GutTest

## Brambles, wired into the world (docs/concept/brambles.md). Asked for with
## the art dropped in -- *"And I added blackberry.png"* -- and then
## *"Forageable, bearing with the seasons"*.
##
## The sim is tested on its own; what is pinned here is that a loaded chunk
## really GETS one, that it is drawn, and that a building's floor clears it
## like every other ground cover. A sim nothing creates grows nothing, which
## is the bug this repo has already shipped once with wild crops -- and the
## reason its sibling ForestFern has a file just like this one.
##
## Anchored on the Harz (51.75, 10.60), a genuinely wooded chunk -- measured
## 573 of its 1024 cells forest. Berlin's own chunk, which most of these
## suites use, is 29. A fixture with almost no wood in it would pass these
## by accident.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const BlackberryBramble = preload("res://src/world/blackberry_bramble.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _chunk_coord: Vector2i


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	var geo := GeoCoordinates.new()
	var harz := Vector2i(
		geo.tile_for_longitude(10.60, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(51.75, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	_chunk_coord = Vector2i(
		floori(float(harz.x) / EarthChunkManager.CHUNK_SIZE),
		floori(float(harz.y) / EarthChunkManager.CHUNK_SIZE)
	)
	_scrub()
	manager._load_chunk(_chunk_coord)


func after_each():
	_scrub()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _scrub() -> void:
	for path in [
		manager._modifications_path(_chunk_coord), manager._roof_modifications_path(_chunk_coord),
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# -- a loaded wood really gets brambles -------------------------------------

func test_a_loaded_chunk_gets_a_bramble_sim():
	assert_true(manager._bramble_sims.has(_chunk_coord), "a wood has brambles in it")


func test_brambles_seed_only_on_this_chunks_forest_cells():
	var sim = manager._bramble_sims[_chunk_coord]
	var chunk = manager._loaded_chunks[_chunk_coord]
	for cell in sim.get_patch_cells():
		assert_eq(
			chunk.biome[cell.y * chunk.width + cell.x], "forest",
			"%s is not wood" % cell
		)


## Scattered where bracken carpets -- the same ordering the sim's own test
## pins, checked here against the REAL chunk both are seeded on rather than
## against a fixture.
func test_a_wood_holds_fewer_brambles_than_ferns():
	assert_lt(
		manager._bramble_sims[_chunk_coord].get_patch_cells().size(),
		manager._fern_sims[_chunk_coord].get_patch_cells().size()
	)


## A sim nothing draws is a sim nobody sees -- the whole of the report this
## work came from was *"not visible"*.
func test_every_bramble_is_really_drawn():
	var sim = manager._bramble_sims[_chunk_coord]
	assert_gt(sim.get_patch_cells().size(), 0, "precondition: this wood has brambles")
	var sprites: Dictionary = manager._bramble_sprites.get(_chunk_coord, {})
	assert_eq(sprites.size(), sim.get_patch_cells().size(), "one sprite per thicket")
	for cell in sim.get_patch_cells():
		assert_not_null(sprites.get(cell), "%s is drawn" % cell)
		assert_not_null(sprites[cell].texture, "...with real art")


## Two brambles in one wood must not be the same picture -- the sheet has
## twenty-five clumps precisely so a thicket is not a repeated stamp.
func test_neighbouring_brambles_do_not_all_wear_the_same_clump():
	var sprites: Dictionary = manager._bramble_sprites.get(_chunk_coord, {})
	var seen := {}
	for cell in sprites:
		seen[sprites[cell].texture.get_rid()] = true
	assert_gt(seen.size(), 1, "a wood is not one bramble stamped over and over")


func test_a_building_clears_the_brambles_under_its_floor():
	var sim = manager._bramble_sims[_chunk_coord]
	var cell: Vector2i = sim.get_patch_cells()[0]
	sim.block_cells([cell])
	assert_false(sim.has_bramble(cell), "a floor is not a thicket")


# -- and you can actually pick them ------------------------------------------
#
# Asked for directly, after the plant was standing in the world but did
# nothing: *"wire blackberry"*. The sim's pick() was tested and reachable
# from nowhere -- a mechanism nothing calls is a mechanism nobody has.
#
# Mirrors harvest_grass_near exactly: a small radius sweep round the player,
# the first patch that yields wins, the drop goes on WorldItemBus, and the
# sprites resync so what is drawn matches what is standing.

const SeasonCycle = preload("res://src/world/season_cycle.gd")
# WorldItemBus is an AUTOLOAD, so the signal lives on the singleton -- a
# preload of the script would be a different object with no listeners.
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")


func _stand_on(cell: Vector2i) -> Vector2:
	var origin := _chunk_coord * EarthChunkManager.CHUNK_SIZE
	return Vector2(
		(origin.x + cell.x + 0.5) * TerrainRenderer.TILE_SIZE,
		(origin.y + cell.y + 0.5) * TerrainRenderer.TILE_SIZE
	)


## Puts the world clock in the middle of the named season, so these test the
## real seasonal gate rather than whatever time of year the fixture began in.
func _set_season(season: String) -> void:
	var cycle := SeasonCycle.new()
	var at := (float(SeasonCycle.SEASONS.find(season)) + 0.5) / float(SeasonCycle.SEASONS.size())
	manager._world_age_seconds = at * SeasonCycle.SECONDS_PER_YEAR


func _picked_items() -> Array:
	var picked: Array = []
	WorldItemBus.item_dropped.connect(func(stack, _at): picked.append(stack))
	return picked


func test_picking_a_ripe_bramble_yields_real_blackberries():
	var sim = manager._bramble_sims[_chunk_coord]
	var cell: Vector2i = sim.get_patch_cells()[0]
	_set_season("autumn")
	var picked := _picked_items()

	assert_true(manager.pick_blackberries_near(_stand_on(cell)), "autumn brambles feed you")
	assert_eq(picked.size(), 1, "something really dropped")
	assert_eq(picked[0].item.id, "blackberry")
	assert_gt(picked[0].count, 0)


## Green fruit is not food -- the small lie brambles.md refuses.
func test_nothing_can_be_picked_in_summer():
	var sim = manager._bramble_sims[_chunk_coord]
	var cell: Vector2i = sim.get_patch_cells()[0]
	_set_season("summer")
	var picked := _picked_items()

	assert_false(manager.pick_blackberries_near(_stand_on(cell)), "you cannot eat a green one")
	assert_eq(picked.size(), 0, "and nothing dropped")


## Foraging that refills as you walk away is the permanent larder flora.md
## already refuses.
##
## The neighbours are cleared FIRST, and that is the point of the test
## rather than housekeeping. pick_blackberries_near searches a one-tile
## radius and takes the first bearing cane in it, so standing in the same
## place twice only proves the first cane is stripped if nothing else is
## within reach. At the old 3.5% density that was true by accident; the
## bump to 10% put a second thicket in the 3x3 often enough to fail this,
## which is the test catching its own premise rather than a regression.
func test_a_bramble_picked_once_gives_nothing_more_this_autumn():
	var sim = manager._bramble_sims[_chunk_coord]
	var cell: Vector2i = sim.get_patch_cells()[0]
	var neighbours: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var near: Vector2i = cell + Vector2i(dx, dy)
			if near != cell:
				neighbours.append(near)
	sim.block_cells(neighbours)
	assert_true(sim.has_bramble(cell), "precondition: the cane under test survived the clearing")
	_set_season("autumn")

	assert_true(manager.pick_blackberries_near(_stand_on(cell)), "precondition")
	assert_false(manager.pick_blackberries_near(_stand_on(cell)), "the cane is stripped")


## The cane survives: a bramble is not an annual, so what is drawn must still
## be drawn after it is picked.
func test_a_picked_bramble_is_still_standing_and_still_drawn():
	var sim = manager._bramble_sims[_chunk_coord]
	var cell: Vector2i = sim.get_patch_cells()[0]
	_set_season("autumn")
	manager.pick_blackberries_near(_stand_on(cell))

	assert_true(sim.has_bramble(cell), "the cane is still there")
	assert_not_null(
		manager._bramble_sprites.get(_chunk_coord, {}).get(cell),
		"...and still drawn, because it will bear again next year"
	)


func test_standing_nowhere_near_a_bramble_picks_nothing():
	_set_season("autumn")
	var chunk = manager._loaded_chunks[_chunk_coord]
	var sim = manager._bramble_sims[_chunk_coord]
	for y in range(chunk.height):
		for x in range(chunk.width):
			var cell := Vector2i(x, y)
			if sim.has_bramble(cell):
				continue
			var clear := true
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if sim.has_bramble(cell + Vector2i(dx, dy)):
						clear = false
			if clear:
				assert_false(manager.pick_blackberries_near(_stand_on(cell)))
				return
	pass_test("this chunk is wall-to-wall bramble, which the density forbids")


## ...and a real swing is what picks them.
##
## The verb is the SAME attack key every other harvest-shaped action already
## uses (Player._harvest_grass_step, _pull_wild_crop_step, _collect_step,
## all fired from _perform_attack). A separate "pick" button for one plant
## would be a second way to do the one thing this game already has a way to
## do.
##
## Driven here rather than in a player suite of its own because the wiring is
## only meaningful over a REAL wooded chunk, and this file already has one
## loaded -- a stub manager cannot even be assigned, since Player._chunk_
## manager is typed to the real one.
func test_a_players_swing_picks_the_bramble_they_are_standing_at():
	const PlayerScene = preload("res://scenes/player.tscn")
	var sim = manager._bramble_sims[_chunk_coord]
	var cell: Vector2i = sim.get_patch_cells()[0]
	_set_season("autumn")

	var player = PlayerScene.instantiate()
	add_child(player)
	player._chunk_manager = manager
	player.position = _stand_on(cell)
	var picked := _picked_items()

	player._pick_blackberries_step()

	assert_eq(picked.size(), 1, "a swing over a ripe bramble picks it")
	assert_eq(picked[0].item.id, "blackberry")
	player.free()


# -- what was still missing ---------------------------------------------------
#
# Reported live: *"blackberrys are still not wired and don't grow in forest
# biome"*. The sim, the sheet, the drawing and the picking were all there;
# three seams every other ground cover has were not, and each of them is
# the kind of gap that reads in play as "it isn't wired".


## A building's floor grows nothing -- the rule every other ground cover
## already obeys through the one shared seam (docs/concept/building.md's
## "Placement rules"). A bramble was not on that list, so a house could be
## raised with a blackberry thicket standing through its floor.
func test_building_on_a_bramble_clears_it_and_keeps_it_gone():
	var sim = manager._bramble_sims.get(_chunk_coord)
	assert_not_null(sim)
	assert_gt(sim.get_patch_cells().size(), 0, "precondition: this wood has brambles")
	var cell: Vector2i = sim.get_patch_cells()[0]
	var g: Vector2i = _chunk_coord * EarthChunkManager.CHUNK_SIZE + cell

	manager.build_at_global(g.x, g.y, "wood_floor")

	assert_false(sim.has_bramble(cell), "the floor was raised straight through a thicket")


## Tearing the floor up gives the GROUND back, and nothing takes it: a
## bramble has no plant() and no spread, so once a thicket is cleared that
## cell carries none for the life of the chunk.
##
## Written down rather than asserted as a bug, because the first version of
## this test asked for `sim.plant(cell)` and there is no such thing. Every
## other ground cover can re-colonise; a bramble is seeded once when its
## chunk is created and that is the whole of it. Recorded as a gap in
## docs/concept/brambles.md rather than quietly fixed here, since giving
## canes a spread is a design decision and not this pass's.
func test_a_cleared_bramble_never_comes_back():
	var sim = manager._bramble_sims.get(_chunk_coord)
	var cell: Vector2i = sim.get_patch_cells()[0]
	var g: Vector2i = _chunk_coord * EarthChunkManager.CHUNK_SIZE + cell
	manager.build_at_global(g.x, g.y, "wood_floor")
	manager.destroy_at_global(g.x, g.y)
	assert_false(
		sim.has_bramble(cell),
		"nothing re-seeds a bramble, so a cleared cell stays cleared"
	)


## ...and its DRAWING goes with it, in the same frame. A cleared thicket
## still on screen is the same lie a grazed tuft left standing would be.
func test_a_cleared_bramble_stops_being_drawn():
	var sim = manager._bramble_sims.get(_chunk_coord)
	var cell: Vector2i = sim.get_patch_cells()[0]
	var g: Vector2i = _chunk_coord * EarthChunkManager.CHUNK_SIZE + cell
	assert_true(manager._bramble_sprites.get(_chunk_coord, {}).has(cell), "precondition: it is drawn")

	manager.build_at_global(g.x, g.y, "wood_floor")

	assert_false(
		manager._bramble_sprites.get(_chunk_coord, {}).has(cell),
		"the thicket was cleared but its sprite is still standing there"
	)


## They go with the chunk, like every other loaded thing. Without this the
## sprites accumulate for every wood a player ever walks through and hang
## over ground that is no longer loaded.
func test_unloading_a_chunk_takes_its_brambles_with_it():
	assert_true(manager._bramble_sims.has(_chunk_coord), "precondition: the chunk has a sim")
	var drawn: int = manager._bramble_sprites.get(_chunk_coord, {}).size()
	assert_gt(drawn, 0, "precondition: some are drawn")

	manager._unload_chunk(_chunk_coord)

	assert_false(manager._bramble_sims.has(_chunk_coord), "the sim outlived its chunk")
	assert_false(manager._bramble_sprites.has(_chunk_coord), "the sprites outlived their chunk")
