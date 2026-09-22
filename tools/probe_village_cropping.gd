extends SceneTree

## What a real village's fields decide to sow, and why.
##
## Reported live with the panels open: *"The farmers produce mostly herbs
## even though it says it can feed 0 / 10 ... the supply chain needs to be
## stable"*.
##
## Prints, per village: the satisfaction reading the plough and the needs
## panel share, the crop VillageCropChoice.choose picks from it, the score
## of every sowable crop, and the food the settlement really holds -- so
## "it sows herbs" can be told apart from "it sows herbs BECAUSE".

const CHUNK_SIZE := 32
const LAT := 48.6
const LON := 12.7
const STEPS := 40
const SETTLE := 3
## Real simulated time before anything is asked, so the settlement step has
## actually run and written a satisfaction reading.
const SETTLEMENT_STEPS := 20
const SETTLEMENT_STEP_SECONDS := 60.0

var _manager
var _origin: Vector2i
var _step := 0
var _settling := 0
var _seen: Dictionary = {}
var _villages := 0


func _initialize() -> void:
	var EarthChunkGenerator = load("res://src/world/earth_chunk_generator.gd")
	var GeoCoordinates = load("res://src/world/geo_coordinates.gd")
	var geo = GeoCoordinates.new()
	_origin = Vector2i(
		geo.tile_for_longitude(LON, EarthChunkGenerator.WORLD_WIDTH_TILES) / CHUNK_SIZE,
		geo.tile_for_latitude(LAT, EarthChunkGenerator.WORLD_HEIGHT_TILES) / CHUNK_SIZE
	)


func _process(_delta: float) -> bool:
	if _manager == null:
		var EarthChunkManager = load("res://src/world/earth_chunk_manager.gd")
		var tml := TileMapLayer.new()
		var ents := Node2D.new()
		var crts := Node2D.new()
		root.add_child(tml)
		root.add_child(ents)
		root.add_child(crts)
		_manager = EarthChunkManager.new(tml, ents, crts)
		print("")
		print("=== what a village decides to sow ===")
		return false
	if _step < STEPS:
		var c: Vector2i = _origin + Vector2i(_step, 0)
		_manager.update(Vector2(c * CHUNK_SIZE + Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2)))
		_step += 1
		if _settling < SETTLE:
			_settling += 1
			return false
		_settling = 0
		# A settlement only reads its own basket when it is STEPPED
		# (step_settlements -> _step_village_estates), and the satisfaction
		# the plough shares with the needs panel is written there. A probe
		# that only loads chunks measures an empty reading and would report
		# "the demand rule never fires" about its own missing clock.
		for tick in SETTLEMENT_STEPS:
			_manager.advance_world_age(SETTLEMENT_STEP_SECONDS)
			_manager.step_settlements(SETTLEMENT_STEP_SECONDS)
		for chunk_coord in _manager._loaded_chunks.keys():
			if _seen.has(chunk_coord):
				continue
			_seen[chunk_coord] = true
			_examine(chunk_coord)
		return false
	print("")
	print("villages examined: %d of %d chunks" % [_villages, _seen.size()])
	return true


func _examine(chunk_coord: Vector2i) -> void:
	var VillageCropChoice = load("res://src/gameplay/village_crop_choice.gd")
	var VillageFarm = load("res://src/gameplay/village_farm.gd")
	var EntityRef = load("res://src/emergence/entity_ref.gd")
	var farms := 0
	for record in _manager.buildings_in_chunk(chunk_coord):
		if record.get("id", "") == VillageFarm.FARM_BUILDING_ID:
			farms += 1
	if farms == 0:
		return
	var state: Dictionary = _manager._village_assembly_state(chunk_coord)
	if state.is_empty():
		print("")
		print("VILLAGE %s  farms=%d  no assembly reading yet" % [str(chunk_coord), farms])
		return
	_villages += 1
	var satisfaction: Dictionary = state.get("satisfaction", {})
	var can_bake: bool = VillageCropChoice.can_bake(state.get("present_building_ids", []))
	var scores: Dictionary = {}
	for crop_id in VillageCropChoice.SOWABLE:
		scores[crop_id] = VillageCropChoice._score_of(crop_id, satisfaction)
	var settlement_id: String = EntityRef.for_settlement(chunk_coord)
	print("")
	print("VILLAGE %s  farms=%d  households=%d" % [
		str(chunk_coord), farms, _manager.household_count_for_settlement(settlement_id)
	])
	print("   satisfaction: %s" % str(satisfaction))
	print("   can_bake=%s   scores: %s" % [str(can_bake), str(scores)])
	for default_crop in ["wheat", "herb"]:
		print("   a %s-farmer sows: %s" % [
			default_crop, VillageCropChoice.choose(satisfaction, can_bake, default_crop)
		])
