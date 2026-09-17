extends SceneTree

## Does a real merchant ever actually stand behind their own stand?
##
## docs/concept/village_market_square.md makes a stand's visibility depend on
## its trader being within a tile of it during their work block. A merchant
## whose schedule never quite brings them there would leave the market
## permanently taken in -- a worse bug than the unattended stand this
## replaced, and one no unit test can see, since only the real planner and
## the real square decide where a merchant walks.
##
## Structural notes are probe_village_hunting.gd's.

const CHUNK_SIZE := 32
const STEPS := 120
const SIMULATED_SECONDS := 180.0
const SLICE := 0.1

var _manager
var _origin: Vector2i
var _step := -1
var _measured := false
var _report_lines: Array = []


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

	for line in _report_lines:
		print(line)
	if _report_lines.is_empty():
		print("MARKET no merchant was ever met in %d chunk-widths" % STEPS)
	return true


func _sample() -> void:
	if _measured:
		return
	for chunk_coord in _manager._loaded_villages:
		var merchants: Array = []
		for node in _manager._loaded_villages[chunk_coord]:
			if not is_instance_valid(node) or not node.has_method("setup_economy"):
				continue
			if node.identity != null and node.identity.occupation == "merchant":
				merchants.append(node)
		if merchants.is_empty():
			continue
		_measured = true
		# EVERY villager of the settlement is ticked, not just the merchant.
		# Ticking one villager alone is a broken measurement, not a finding:
		# nobody else gathers, so the shared VillageMarket stays empty, so a
		# merchant with an empty purse is hungry for ever and the hunger
		# interrupt overrides their work block on every frame. That reads
		# exactly like "the market is never up" while actually being "the
		# probe never let the village run".
		var villagers: Array = []
		for node in _manager._loaded_villages[chunk_coord]:
			if is_instance_valid(node) and node.has_method("setup_economy"):
				villagers.append(node)
		_report_lines.append(
			"MARKET village %s villagers=%d merchants=%d"
			% [str(chunk_coord), villagers.size(), merchants.size()]
		)
		_run(villagers, merchants)
		return


func _run(villagers: Array, merchants: Array) -> void:
	var stats := {}
	for merchant in merchants:
		stats[merchant] = {"up": 0, "at": 0, "hungry": 0, "closest": INF}
	var total := 0
	var elapsed := 0.0
	while elapsed < SIMULATED_SECONDS:
		for villager in villagers:
			villager._process(SLICE)
		_manager.step_farm_plots(SLICE)
		elapsed += SLICE
		total += 1
		for merchant in merchants:
			var stand = merchant.market_stand
			if stand == null:
				continue
			var row: Dictionary = stats[merchant]
			if stand.visible:
				row["up"] = int(row["up"]) + 1
			var distance: float = merchant.position.distance_to(stand.position)
			if distance <= merchant.market_stand_reach():
				row["at"] = int(row["at"]) + 1
			row["closest"] = minf(float(row["closest"]), distance)
			if merchant.economy != null and merchant.economy.needs.is_hungry():
				row["hungry"] = int(row["hungry"]) + 1
	for merchant in merchants:
		if merchant.market_stand == null:
			_report_lines.append("  MERCHANT %s has NO stand" % merchant.identity.npc_name)
			continue
		var row: Dictionary = stats[merchant]
		_report_lines.append(
			"  MERCHANT %s up %d/%d (%.0f%%)  at_stand %d/%d  hungry %d/%d  closest=%.1fpx reach=%.1fpx  market=%s"
			% [
				merchant.identity.npc_name, int(row["up"]), total,
				100.0 * float(row["up"]) / float(total), int(row["at"]), total,
				int(row["hungry"]), total, float(row["closest"]), merchant.market_stand_reach(),
				str(merchant.economy.market.stock) if merchant.economy != null and merchant.economy.market != null else "{}",
			]
		)
