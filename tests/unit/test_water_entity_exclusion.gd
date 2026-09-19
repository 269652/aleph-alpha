extends GutTest

## Nothing that belongs on land may stand on a cell the game draws as
## water. Reported live with a screenshot taken while SWIMMING at
## 47.3N 19.6E: mushrooms, an ant mound, bushes, a stone and an alpaca all
## floating in open water, plus the original report of "patches of grass;
## potatoes in the river".
##
## Its own file rather than test_earth_chunk_manager.gd, which already runs
## for ten-plus minutes: this needs one real update() at the reported
## coordinates and nothing else in that file would use the fixture.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var manager: EarthChunkManager
var water_tile: Vector2i


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	var geo := GeoCoordinates.new()
	water_tile = geo.tile_for_coordinate(
		47.3, 19.6, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	manager.update(water_tile)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


## The chunk the report was taken in, and the premise every test below
## rests on: at these coordinates the ENTIRE chunk is drawn as water, and
## the narrow is_river/is_lake mask already agrees with the canonical
## is_water_at_global on every one of its cells. So nothing here is a
## mask-width problem -- anything standing on this chunk is standing there
## because its own placement never consulted a mask at all.
##
## Note the biome: a water cell keeps its LAND biome ("grassland"). That is
## exactly why seeding "by biome" puts crops, mushrooms and flowers in a
## lake -- the biome array never says water.
func test_the_reported_chunk_really_is_entirely_water():
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(water_tile)
	var chunk = manager._loaded_chunks[chunk_coord]
	assert_true(manager.is_water_at_global(water_tile.x, water_tile.y))
	assert_eq(manager.biome_at_global(water_tile.x, water_tile.y), "grassland",
		"the premise: the biome array calls this water cell land")
	var drawn_water := 0
	for y in chunk.height:
		for x in chunk.width:
			var g := chunk_coord * EarthChunkManager.CHUNK_SIZE + Vector2i(x, y)
			if manager.is_water_at_global(g.x, g.y):
				drawn_water += 1
	assert_eq(drawn_water, chunk.width * chunk.height,
		"the premise: every cell of this chunk is drawn as water")


## Every cell of a sim in this chunk, as globals.
func _cells_of(local_cells: Array, chunk_coord: Vector2i) -> Array:
	var out: Array = []
	for cell in local_cells:
		out.append(chunk_coord * EarthChunkManager.CHUNK_SIZE + cell)
	return out


func _report(kind: String, globals: Array) -> void:
	var in_water: Array = []
	for g in globals:
		if manager.is_water_at_global(g.x, g.y):
			in_water.append(g)
	assert_eq(
		in_water.size(), 0,
		"%d %s stand on cells drawn as water (e.g. %s)"
			% [in_water.size(), kind, str(in_water.slice(0, 3))]
	)


## Grass already has the mask (TallGrass takes one and honours it in both
## seeding and spread) -- this pins that it stays fixed.
func test_no_grass_grows_on_water():
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(water_tile)
	_report("grass patches", _cells_of(
		manager._grass_sims[chunk_coord].get_patch_cells(), chunk_coord))


## "potatoes in the river" -- WildCropPatch takes no mask at all and seeds
## purely on biome.
func test_no_wild_crops_grow_on_water():
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(water_tile)
	var cells: Array = []
	for crop_id in manager._wild_crop_sims[chunk_coord]:
		cells.append_array(manager._wild_crop_sims[chunk_coord][crop_id].get_patch_cells())
	_report("wild crop patches", _cells_of(cells, chunk_coord))


func test_no_mushrooms_grow_on_water():
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(water_tile)
	_report("mushroom sites", _cells_of(
		manager._mushroom_sims[chunk_coord].get_site_cells(), chunk_coord))


func test_no_flowers_grow_on_water():
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(water_tile)
	_report("flower patches", _cells_of(
		manager._flower_patches[chunk_coord].get_flower_cells(), chunk_coord))


## An ant mound is a hole in the ground with a colony living in it -- it
## cannot be in a lake.
func test_no_ant_mounds_sit_on_water():
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(water_tile)
	if not manager._ant_colonies.has(chunk_coord):
		pending("no colony in this chunk")
		return
	_report("ant mounds", _cells_of(
		manager._ant_colonies[chunk_coord].mound_cells(), chunk_coord))


## The alpaca in the screenshot. Land herbivores and predators are placed
## at a deterministic per-chunk position with no water check at all, so an
## all-water chunk gets a full land population standing on the lake.
##
## Fish and the other aquatic markers are spawned through their own paths,
## not through _loaded_creatures, so this can say "none" without qualifying
## it by species.
func test_no_land_creature_stands_on_water():
	# Every loaded chunk, not just the all-water one: an entirely flooded
	# chunk correctly ends up with NO land animals at all, so checking only
	# that one would assert against an empty list. The loaded radius here
	# spans real shoreline, which is exactly where a slid position has to
	# land somewhere dry rather than being dropped.
	var total := 0
	var on_water: Array = []
	for chunk_coord in manager._loaded_creatures:
		for creature in manager._loaded_creatures[chunk_coord]:
			if not is_instance_valid(creature):
				continue
			total += 1
			var tile := Vector2i(
				int(creature.position.x / 16.0), int(creature.position.y / 16.0)
			)
			if manager.is_water_at_global(tile.x, tile.y):
				on_water.append("%s@%s" % [
					str(creature.info.species if creature.info != null else "?"), str(tile)])
	assert_gt(total, 0, "the premise: the loaded radius must promote some land creatures")
	assert_eq(
		on_water.size(), 0,
		"%d land creatures stand on water (e.g. %s)" % [on_water.size(), str(on_water.slice(0, 4))]
	)
