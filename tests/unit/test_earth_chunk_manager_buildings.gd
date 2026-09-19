extends GutTest

## Whole-building entities (docs/concept/building.md "Buildings are
## entities; interiors are scenes"): EarthChunkManager.place_building and
## its siblings -- one anchor cell carries the building id (so every
## existing "is a structure here" scan keeps working unchanged), every
## other footprint cell carries BuildingCatalog.FOOTPRINT_TILE_ID, the
## node is one Sprite2D + one StaticBody2D over the whole footprint,
## anchored at the footprint's bottom edge (not its centre -- the bug the
## single-tile placeable pipeline has today), and Chunk.buildings carries
## the rest of a building's own state (condition/progress/owner).
##
## Berlin's real chunk, loaded directly via _load_chunk (see
## test_earth_chunk_manager.gd's own known-slow-file note) -- persisted
## files scrubbed before and after, since tests share one real user://
## dir.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _chunk_coord: Vector2i
var _origin: Vector2i  # a real, dry, buildable LOCAL origin inside _chunk_coord


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	var geo := GeoCoordinates.new()
	var berlin := Vector2i(
		geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	_chunk_coord = Vector2i(
		floori(float(berlin.x) / EarthChunkManager.CHUNK_SIZE), floori(float(berlin.y) / EarthChunkManager.CHUNK_SIZE)
	)
	_scrub()
	manager._load_chunk(_chunk_coord)
	_origin = _a_clear_footprint_origin(Vector2i(4, 3))


func after_each():
	_scrub()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _scrub() -> void:
	for path in [
		manager._modifications_path(_chunk_coord), manager._buildings_path(_chunk_coord),
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## A local origin, well inside the chunk with a margin, where a whole
## `footprint`-sized building AND its doorstep are real dry buildable
## ground and nothing else is modified there yet.
func _a_clear_footprint_origin(footprint: Vector2i):
	for y in range(2, EarthChunkManager.CHUNK_SIZE - footprint.y - 2):
		for x in range(2, EarthChunkManager.CHUNK_SIZE - footprint.x - 2):
			var origin := Vector2i(x, y)
			var ok := true
			for cell in [origin] + [origin + footprint]:
				var g: Vector2i = _chunk_coord * EarthChunkManager.CHUNK_SIZE + cell
				if not manager.is_buildable_terrain_at(g.x, g.y) or manager.modification_at_global(g.x, g.y) != "":
					ok = false
					break
			if ok:
				return origin
	fail_test("no clear footprint origin found in this chunk")
	return Vector2i.ZERO


func _global(local: Vector2i) -> Vector2i:
	return _chunk_coord * EarthChunkManager.CHUNK_SIZE + local


# -- placement: the anchor id, the footprint markers, the record ------------

func test_place_building_writes_the_anchor_id_and_footprint_markers():
	assert_true(manager.place_building(_chunk_coord, _origin, "house_medium", Vector2i(0, 1), 1, ""))
	for cell in BuildingCatalog.footprint_cells("house_medium", _origin):
		var g := _global(cell)
		if cell == _origin:
			assert_eq(manager.modification_at_global(g.x, g.y), "house_medium", "the anchor carries the real id")
		else:
			assert_eq(manager.modification_at_global(g.x, g.y), BuildingCatalog.FOOTPRINT_TILE_ID, str(cell))


func test_place_building_records_facing_seed_condition_progress_owner():
	manager.place_building(_chunk_coord, _origin, "house_small", Vector2i(1, 0), 42, "household_7")
	var record := manager.building_at_global(_global(_origin).x, _global(_origin).y)
	assert_eq(record["id"], "house_small")
	assert_eq(record["facing"], Vector2i(1, 0))
	assert_eq(record["seed"], 42)
	assert_almost_eq(float(record["condition"]), 1.0, 0.001)
	assert_almost_eq(float(record["progress"]), 1.0, 0.001)
	assert_eq(record["owner_household_id"], "household_7")


## Who lives here (docs/concept/building.md "Entering": the resident's REAL
## occupation drives the interior, and "Residents inside" needs to find
## the villager) -- carried on the record itself, since a village's NPCs
## are regenerated on every load and only the building persists.
func test_place_building_records_the_residents_occupation_and_seed():
	manager.place_building(_chunk_coord, _origin, "house_small", Vector2i(0, 1), 42, "", "blacksmith", 9001)
	var record := manager.building_at_global(_global(_origin).x, _global(_origin).y)
	assert_eq(record["occupation"], "blacksmith")
	assert_eq(record["resident_seed"], 9001)


## Every existing caller passes six arguments -- a record placed that way
## must still be well-formed (empty occupation, no resident), never a
## missing key a reader has to guard against.
func test_place_building_without_a_resident_records_an_empty_occupation_and_zero_seed():
	manager.place_building(_chunk_coord, _origin, "house_small", Vector2i(0, 1), 42, "")
	var record := manager.building_at_global(_global(_origin).x, _global(_origin).y)
	assert_eq(record["occupation"], "")
	assert_eq(record["resident_seed"], 0)


## The backfill hook for buildings persisted before the record carried a
## resident (see VillageRenderer._recover_existing_village): sets both
## fields on an existing record and persists them.
func test_set_building_resident_backfills_an_existing_record():
	manager.place_building(_chunk_coord, _origin, "house_small", Vector2i(0, 1), 42, "")

	assert_true(manager.set_building_resident(_chunk_coord, _origin, "fisher", 77))

	var record := manager.building_at_global(_global(_origin).x, _global(_origin).y)
	assert_eq(record["occupation"], "fisher")
	assert_eq(record["resident_seed"], 77)


func test_set_building_resident_is_false_when_nothing_stands_there():
	assert_false(manager.set_building_resident(_chunk_coord, _origin, "fisher", 77))


func test_place_building_refuses_an_unknown_id():
	assert_false(manager.place_building(_chunk_coord, _origin, "not_a_building", Vector2i(0, 1), 1, ""))
	assert_eq(manager.modification_at_global(_global(_origin).x, _global(_origin).y), "")


func test_place_building_refuses_when_the_footprint_is_already_occupied():
	manager.place_building(_chunk_coord, _origin, "house_small", Vector2i(0, 1), 1, "")
	assert_false(manager.place_building(_chunk_coord, _origin, "house_small", Vector2i(0, 1), 2, ""), "second placement on the same site")


func test_place_building_refuses_for_an_unloaded_chunk():
	assert_false(manager.place_building(Vector2i(9999, 9999), Vector2i.ZERO, "house_small", Vector2i(0, 1), 1, ""))


## building_at_global answers for ANY footprint cell, not just the anchor.
func test_building_at_global_answers_for_every_footprint_cell():
	manager.place_building(_chunk_coord, _origin, "house_medium", Vector2i(0, 1), 3, "")
	for cell in BuildingCatalog.footprint_cells("house_medium", _origin):
		var g := _global(cell)
		var record := manager.building_at_global(g.x, g.y)
		assert_eq(record.get("id", ""), "house_medium", str(cell))
		assert_eq(record.get("origin_local", null), _origin, str(cell))


func test_building_at_global_is_empty_for_a_cell_with_no_building():
	assert_true(manager.building_at_global(_global(_origin).x, _global(_origin).y).is_empty())


# -- removal ------------------------------------------------------------------

func test_remove_building_clears_the_anchor_and_every_footprint_marker():
	manager.place_building(_chunk_coord, _origin, "house_medium", Vector2i(0, 1), 1, "")
	assert_true(manager.remove_building(_chunk_coord, _origin))
	for cell in BuildingCatalog.footprint_cells("house_medium", _origin):
		var g := _global(cell)
		assert_eq(manager.modification_at_global(g.x, g.y), "", str(cell))
	assert_true(manager.building_at_global(_global(_origin).x, _global(_origin).y).is_empty())


func test_remove_building_is_false_when_nothing_stands_there():
	assert_false(manager.remove_building(_chunk_coord, _origin))


# -- buildings_in_chunk -------------------------------------------------------

func test_buildings_in_chunk_lists_every_placed_building():
	manager.place_building(_chunk_coord, _origin, "house_small", Vector2i(0, 1), 1, "")
	var list := manager.buildings_in_chunk(_chunk_coord)
	assert_eq(list.size(), 1)
	assert_eq(list[0]["id"], "house_small")


func test_buildings_in_chunk_is_empty_for_an_unloaded_chunk():
	assert_true(manager.buildings_in_chunk(Vector2i(9999, 9999)).is_empty())


# -- building_door_near: the Enter-prompt scan --------------------------------

func test_building_door_near_finds_the_doorstep_within_radius():
	manager.place_building(_chunk_coord, _origin, "house_medium", Vector2i(0, 1), 1, "")
	var doorstep := _global(_origin + BuildingCatalog.doorstep_of("house_medium"))
	var pixel := (Vector2(doorstep) + Vector2(0.5, 0.5)) * TerrainRenderer.TILE_SIZE
	var found := manager.building_door_near(pixel, 3.0)
	assert_false(found.is_empty())
	assert_eq(found["id"], "house_medium")
	assert_eq(found["doorstep_global"], doorstep)


func test_building_door_near_is_empty_when_nothing_is_within_radius():
	manager.place_building(_chunk_coord, _origin, "house_medium", Vector2i(0, 1), 1, "")
	var far_pixel := Vector2(-99999, -99999)
	assert_true(manager.building_door_near(far_pixel, 3.0).is_empty())


func test_building_door_near_does_not_trigger_from_inside_the_footprint_away_from_the_door():
	manager.place_building(_chunk_coord, _origin, "house_large", Vector2i(0, 1), 1, "")
	# The far (north) corner of a 4x3 house is outside a tight radius of the
	# doorstep even though it's the same building.
	var far_corner := _global(_origin)
	var pixel := (Vector2(far_corner) + Vector2(0.5, 0.5)) * TerrainRenderer.TILE_SIZE
	assert_true(manager.building_door_near(pixel, 0.5).is_empty())


# -- occupancy: ground cover / tree apron / siting all read the anchor+marker -

func test_a_building_blocks_ground_cover_on_its_whole_footprint():
	manager.place_building(_chunk_coord, _origin, "house_medium", Vector2i(0, 1), 1, "")
	for cell in BuildingCatalog.footprint_cells("house_medium", _origin):
		assert_true(manager._built_local_cells(manager._loaded_chunks[_chunk_coord]).has(cell), str(cell))


func test_occupancy_scans_already_used_by_siting_see_the_whole_footprint():
	manager.place_building(_chunk_coord, _origin, "house_medium", Vector2i(0, 1), 1, "")
	# The exact predicate VillageLayout/siting will read: any non-empty
	# modification means occupied, for every footprint cell.
	for cell in BuildingCatalog.footprint_cells("house_medium", _origin):
		var g := _global(cell)
		assert_ne(manager.modification_at_global(g.x, g.y), "", str(cell))


# -- the Road tier (docs/concept/infrastructure.md): a laid surface, so -----
# -- nothing grows on it -- the same built-cell rule a house's footprint has --

func test_a_road_cell_counts_as_built_so_ground_cover_is_blocked_on_it():
	var g := _global(_origin)
	assert_true(manager.build_at_global(g.x, g.y, TerrainRenderer.ROAD_TILE_ID))
	assert_true(manager._built_local_cells(manager._loaded_chunks[_chunk_coord]).has(_origin))


## A trail is worn ground, not a laid surface -- it stays open to grass
## exactly as before (the worn tiers are untouched by the Road tier).
func test_a_trail_cell_still_does_not_count_as_built():
	var g := _global(_origin)
	assert_true(manager.build_at_global(g.x, g.y, TerrainRenderer.TRAIL_TILE_ID))
	assert_false(manager._built_local_cells(manager._loaded_chunks[_chunk_coord]).has(_origin))


func test_destroying_a_road_cell_opens_it_to_ground_cover_again():
	var g := _global(_origin)
	manager.build_at_global(g.x, g.y, TerrainRenderer.ROAD_TILE_ID)
	assert_true(manager.destroy_at_global(g.x, g.y))
	assert_false(manager._built_local_cells(manager._loaded_chunks[_chunk_coord]).has(_origin))


func test_nothing_takes_root_on_a_road_cell():
	var g := _global(_origin)
	manager.build_at_global(g.x, g.y, TerrainRenderer.ROAD_TILE_ID)
	var chunk = manager._loaded_chunks[_chunk_coord]
	var pixel := (Vector2(g) + Vector2(0.5, 0.5)) * TerrainRenderer.TILE_SIZE
	assert_false(manager._can_root_at(chunk, _chunk_coord, pixel))


# -- water reclaim: a building whose entrance is wet does not survive a load -

func _water_cell():
	for y in EarthChunkManager.CHUNK_SIZE:
		for x in EarthChunkManager.CHUNK_SIZE:
			var g: Vector2i = _global(Vector2i(x, y))
			if manager.is_water_at_global(g.x, g.y):
				return g
	return null


## Writes the record a building standing in water leaves behind, exactly as
## place_building used to write it and as a save made before that rule
## existed still contains it. NOT through place_building, which refuses a
## wet footprint or doorstep outright now (pinned just below) -- this is the
## LEGACY state the reload sweep exists to heal, and the only way to
## construct it is to write it.
func _plant_a_legacy_building(origin_local: Vector2i, building_id: String) -> void:
	var chunk = manager._loaded_chunks[_chunk_coord]
	for local in BuildingCatalog.footprint_cells(building_id, origin_local):
		chunk.modifications[local] = (
			building_id if local == origin_local else BuildingCatalog.FOOTPRINT_TILE_ID
		)
	chunk.buildings[origin_local] = {
		"id": building_id, "facing": Vector2i(0, 1), "seed": 1,
		"condition": 1.0, "progress": 1.0, "owner_household_id": "",
		"occupation": "", "resident_seed": 0,
	}


## A building's own door/doorstep just happening to be a real wet cell
## (Berlin's chunk has the Spree) is removed on the next load -- the same
## protection _reclaim_pieces_standing_in_water already gives legacy piece
## houses, for the entity model.
##
## Still worth having now that place_building refuses to CREATE one: a river
## that moves under a village it was founded beside, and every save written
## before the refusal existed, both put a building on wet ground that no
## placement call is ever asked about again.
func test_a_building_whose_doorstep_is_water_is_removed_on_reload():
	var wet = _water_cell()
	assert_not_null(wet, "precondition: Berlin's chunk has water (the Spree)")
	if wet == null:
		return
	var door_local := BuildingCatalog.door_of("house_small")
	var wet_origin: Vector2i = manager._local_coord(wet.x, wet.y) - door_local
	_plant_a_legacy_building(wet_origin, "house_small")
	assert_false(manager.building_at_global(wet.x, wet.y).is_empty(), "precondition: really there")

	manager._unload_chunk(_chunk_coord)
	manager._load_chunk(_chunk_coord)

	assert_true(manager.building_at_global(wet.x, wet.y).is_empty(), "the wet building is gone")
	for cell in BuildingCatalog.footprint_cells("house_small", wet_origin):
		var g := _global(cell)
		assert_eq(manager.modification_at_global(g.x, g.y), "", str(cell))


## And nothing new is ever put there in the first place. Reported live with
## the screenshot: *"Buildings are placed in rivers"*. place_building used to
## refuse only cells already modified, so any caller that forgot to check the
## ground was free to put a house in the Spree.
func test_a_building_is_never_placed_on_water_in_the_first_place():
	var wet = _water_cell()
	assert_not_null(wet, "precondition: Berlin's chunk has water (the Spree)")
	if wet == null:
		return
	var wet_origin: Vector2i = manager._local_coord(wet.x, wet.y)

	assert_false(
		manager.place_building(_chunk_coord, wet_origin, "house_small", Vector2i(0, 1), 1, ""),
		"a house is not raised in the river"
	)
	assert_true(manager.building_at_global(wet.x, wet.y).is_empty(), "and nothing was written")


## The doorstep counts too: a house on dry ground whose only way in is off a
## riverbank is a house nobody can enter.
func test_a_building_whose_doorstep_would_be_water_is_refused():
	var wet = _water_cell()
	assert_not_null(wet, "precondition: Berlin's chunk has water (the Spree)")
	if wet == null:
		return
	var doorstep_local := BuildingCatalog.doorstep_of("house_small")
	var wet_origin: Vector2i = manager._local_coord(wet.x, wet.y) - doorstep_local
	var dry_footprint := true
	for cell in BuildingCatalog.footprint_cells("house_small", wet_origin):
		var g := _global(cell)
		if manager.is_water_at_global(g.x, g.y):
			dry_footprint = false
	if not dry_footprint:
		return  # this particular wet cell has the house itself in the water too

	assert_false(
		manager.place_building(_chunk_coord, wet_origin, "house_small", Vector2i(0, 1), 1, ""),
		"the front door opens onto the river"
	)


func test_a_building_on_dry_ground_survives_a_reload():
	manager.place_building(_chunk_coord, _origin, "house_small", Vector2i(0, 1), 1, "")
	manager._unload_chunk(_chunk_coord)
	manager._load_chunk(_chunk_coord)
	assert_false(manager.building_at_global(_global(_origin).x, _global(_origin).y).is_empty())


# -- terrain_renderer(): HouseInteriorView's own real need -----------------

## The SAME instance every load already paints the world with -- not a
## fresh one -- so a caller building HouseInteriorView.build_tile_set()
## against it hits TerrainRenderer's own process-wide static cache rather
## than paying to rebuild the atlas from scratch on every Enter.
func test_terrain_renderer_returns_the_same_instance_every_call():
	assert_same(manager.terrain_renderer(), manager.terrain_renderer())


# -- art resolution (docs/concept/art_resolution.md) ----------------------
#
# The one factor separating "how many art PIXELS a thing is drawn with"
# from "how much WORLD it occupies". Terrain already paints at
# ART_TILE_SIZE (DETAIL_MULTIPLIER art pixels per world unit) and scales
# back by LAYER_SCALE; a building drawn at TILE_SIZE carries HALF the
# detail per world unit of the ground it stands on -- which is exactly the
# resolution a finely-drawn cottage variant sheet would be thrown away at.

const ArtResolution = preload("res://src/rendering/art_resolution.gd")


func _building_sprite_at(origin_local: Vector2i) -> Sprite2D:
	var node: Node2D = manager._building_nodes.get(_chunk_coord, {}).get(origin_local)
	if node == null:
		return null
	for child in node.get_children():
		if child is Sprite2D:
			return child
	return null


## A building is drawn INSIDE its own plot (BuildingCatalog.
## PLOT_MARGIN_SHARE), in world units -- whatever the art resolution.
## That "whatever the art resolution" is what this test is really for: the
## world width must follow the footprint and not the pixel count.
func test_a_buildings_drawn_world_width_is_its_footprint_less_its_margin():
	assert_true(manager.place_building(_chunk_coord, _origin, "house_large", Vector2i(0, 1), 5, ""))
	var sprite := _building_sprite_at(_origin)
	assert_not_null(sprite, "a placed building has a sprite")

	var footprint := BuildingCatalog.footprint_of("house_large")
	var drawn_world_width: float = sprite.texture.get_width() * sprite.scale.x
	assert_almost_eq(
		drawn_world_width,
		float(TerrainRenderer.TILE_SIZE) * BuildingCatalog.drawn_plot_width_tiles(footprint.x),
		0.51,
		"the drawn width must be the footprint's own world width less its margin"
	)
	assert_lt(
		drawn_world_width, float(footprint.x * TerrainRenderer.TILE_SIZE),
		"a building drawn across its whole plot touches its neighbours"
	)


func test_a_building_carries_the_same_art_detail_per_world_unit_as_the_ground_it_stands_on():
	assert_true(manager.place_building(_chunk_coord, _origin, "house_large", Vector2i(0, 1), 5, ""))
	var sprite := _building_sprite_at(_origin)
	assert_not_null(sprite, "precondition")

	# The claim is about DETAIL, not about width: however wide a building
	# is drawn, its art must carry DETAIL_MULTIPLIER pixels per world unit
	# -- the same as the ground it stands on. Asserted as that ratio rather
	# than as a pixel count, so it survives a change to how much of its
	# plot a building covers (which is exactly what PLOT_MARGIN_SHARE was).
	var art_pixels_per_world_unit: float = (
		float(sprite.texture.get_width()) / (float(sprite.texture.get_width()) * sprite.scale.x)
	)
	assert_almost_eq(
		art_pixels_per_world_unit, float(ArtResolution.DETAIL_MULTIPLIER), 0.001,
		"a building's art must be authored/scaled at the same pixels-per-world-unit as terrain"
	)
	assert_eq(
		sprite.texture.get_width(),
		int(round(
			float(TerrainRenderer.ART_TILE_SIZE)
			* BuildingCatalog.drawn_plot_width_tiles(BuildingCatalog.footprint_of("house_large").x)
		)),
		"sliced at the ART tile size, not the world one"
	)
	assert_almost_eq(sprite.scale.x, ArtResolution.SPRITE_SCALE, 0.001)
	assert_almost_eq(sprite.scale.y, ArtResolution.SPRITE_SCALE, 0.001)


## The sprite is anchored at the footprint's bottom edge, so a building
## taller than its own ground footprint overhangs NORTH -- unchanged by the
## resolution bump, and the thing that would break first if the scale were
## applied to one axis and not the other.
func test_a_taller_building_still_overhangs_north_of_its_footprint():
	assert_true(manager.place_building(_chunk_coord, _origin, "house_large", Vector2i(0, 1), 5, ""))
	var sprite := _building_sprite_at(_origin)
	assert_not_null(sprite, "precondition")
	assert_lt(sprite.position.y, 0.0, "the sprite rises from the footprint's bottom edge")
	assert_almost_eq(
		sprite.position.y, -sprite.texture.get_height() * 0.5 * sprite.scale.y, 0.01,
		"anchored at its own bottom edge in WORLD units, not art pixels"
	)
