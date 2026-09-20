extends SceneTree

## What the settlement card says against what the player can actually count.
##
## Reported live with the card in shot: *"The villages population is
## declining but there still run around more NPCs than the number displays
## also there's still not enough food even though the warehouse is full"*.
##
## Three complaints, and this prints all three side by side for a real
## village: the card's own rows, how many villager markers really stand in
## the chunk, and what food the village is holding where.
##
## Usage: godot --headless -s tools/probe_village_population.gd

const CHUNK_SIZE := 32
const STEPS := 40

var _manager
var _origin: Vector2i
var _step := -1
var _measured := false
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

	if _step < STEPS and not _measured:
		_manager.update(_origin + Vector2i(_step * CHUNK_SIZE, 0))
		_sample()
		_step += 1
		return false

	for line in _lines:
		print(line)
	if _lines.is_empty():
		print("VILLAGE no settlement was met in %d chunk-widths" % STEPS)
	return true


func _sample() -> void:
	if _measured:
		return
	var SettlementReadout = load("res://src/ui/settlement_readout.gd")
	for chunk_coord in _manager._loaded_villages:
		var state: Dictionary = _manager.settlement_readout_at(chunk_coord)
		if state.is_empty():
			continue
		_measured = true
		_lines.append("")
		_lines.append("VILLAGE at %s -- the card says:" % str(chunk_coord))
		_lines.append("  %s" % SettlementReadout.title_for(state))
		for line in SettlementReadout.lines_for(state):
			_lines.append("    %s" % line)

		var villagers := 0
		for node in _manager._loaded_villages[chunk_coord]:
			if is_instance_valid(node) and node.has_method("setup_economy"):
				villagers += 1
		_lines.append("  villager markers really standing here: %d" % villagers)
		_lines.append(
			"  the card's Population row says %d -- %s"
			% [
				int(state.get("households", 0)),
				(
					"they agree"
					if villagers == int(state.get("households", 0))
					else "OFF BY %d" % absi(villagers - int(state.get("households", 0)))
				),
			]
		)
		_report_food(chunk_coord)
		return


## Where this village's food actually is, and whether its own people can
## reach it -- the third complaint. A shelf the settlement counts but
## nobody may eat from is the bug that was reported as a full warehouse
## beside a hungry village.
func _report_food(chunk_coord: Vector2i) -> void:
	var ItemCatalog = load("res://src/gameplay/item_catalog.gd")
	var catalog = ItemCatalog.new()
	var total := 0
	for record in _manager.buildings_in_chunk(chunk_coord):
		var tile: Vector2i = chunk_coord * CHUNK_SIZE + Vector2i(record["origin_local"])
		var held: Dictionary = _manager.structure_stock_contents_at(tile.x, tile.y)
		var food := 0
		for item_id in held:
			if catalog.kind_of(String(item_id)) == "food":
				food += int(held[item_id])
		if food <= 0:
			continue
		total += food
		var pixel := (Vector2(tile) + Vector2(0.5, 0.5)) * 16.0
		_lines.append(
			"  %-12s at %s holds %d food -- a villager standing there %s eat it"
			% [
				String(record["id"]), str(tile), food,
				"CAN" if _manager.has_village_meal_near(pixel) else "CANNOT",
			]
		)
	if total == 0:
		_lines.append("  no building in this village is holding any food at all")
