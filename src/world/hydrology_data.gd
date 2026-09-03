extends RefCounted

## The shipped form of a DrainageNetwork (docs/concept/hydrology.md
## "Layer 0 ... Shipped outputs"): three compact per-cell rasters plus one
## JSON of depressions, written once by tools/bake_hydrology.gd and read
## by every tile query at runtime. Raw little-endian .bin files rather
## than PNGs: Godot's Image has no 16-bit grayscale format and its PNG
## loader would truncate, and a byte-per-cell raster needs no decoder.
##
## Per cell:
##   flow_direction  1 byte   DrainageNetwork direction code (0-7, 8 = sea)
##   discharge_log   1 byte   log-encoded stand-in discharge, see encode_discharge
##   depression_id   2 bytes  u16, 0 = none, else depression index + 1

const DrainageNetwork = preload("res://src/world/drainage_network.gd")

const DEFAULT_DIRECTORY := "res://assets/data/hydrology"
const META_FILE := "hydrology.json"
const FLOW_FILE := "flow_direction.bin"
const DISCHARGE_FILE := "discharge_log.bin"
const DEPRESSION_FILE := "depression_id.bin"

## byte = round(log2(1 + q) * DISCHARGE_LOG_STEPS_PER_DOUBLING). Eight
## steps per doubling is a ~9% ratio per step -- finer than the width
## formula (one tile per doubling at most) can show -- and 255 steps span
## 2^31 cells of runoff, more than the whole asset grid holds. Pinned by
## test_discharge_encoding_round_trips_within_one_log_step and
## test_discharge_encoding_is_monotone_and_never_overflows_a_byte.
const DISCHARGE_LOG_STEPS_PER_DOUBLING := 8.0

## u16 depression codes reserve 0 for "none".
const NO_DEPRESSION_CODE := 0
const MAX_DEPRESSIONS := 65535

var width := 0
var height := 0
var flow_direction := PackedByteArray()
var discharge_log := PackedByteArray()
var depression_id := PackedByteArray()
## Each {id, cell_count, spill_elevation, spill_index, floor_elevation},
## exactly DrainageNetwork.depressions.
var depressions: Array[Dictionary] = []


static func encode_discharge(discharge: float) -> int:
	if discharge <= 0.0:
		return 0
	var code := roundi(log(1.0 + discharge) / log(2.0) * DISCHARGE_LOG_STEPS_PER_DOUBLING)
	return clampi(code, 0, 255)


static func decode_discharge(code: int) -> float:
	if code <= 0:
		return 0.0
	return pow(2.0, float(code) / DISCHARGE_LOG_STEPS_PER_DOUBLING) - 1.0


## Fills every field from a built network and a per-cell discharge (the
## bake's stand-in, DrainageNetwork.accumulate_weighted). Returns self.
func build_from_network(network, discharge: PackedFloat32Array) -> RefCounted:
	width = network.width
	height = network.height
	var count := width * height
	flow_direction = network.flow_direction.duplicate()
	discharge_log.resize(count)
	depression_id.resize(count * 2)
	if network.depressions.size() > MAX_DEPRESSIONS:
		push_error("HydrologyData: %d depressions exceed the u16 code space" % network.depressions.size())
	for index in count:
		discharge_log[index] = encode_discharge(discharge[index])
		var id: int = network.depression_id[index]
		var code := NO_DEPRESSION_CODE if id == DrainageNetwork.NO_DEPRESSION else id + 1
		depression_id[index * 2] = code & 0xFF
		depression_id[index * 2 + 1] = (code >> 8) & 0xFF
	depressions.clear()
	for depression in network.depressions:
		depressions.append(depression.duplicate())
	return self


func flow_direction_at(index: int) -> int:
	return flow_direction[index]


func discharge_at(index: int) -> float:
	return decode_discharge(discharge_log[index])


## Index into `depressions`, or DrainageNetwork.NO_DEPRESSION.
func depression_at(index: int) -> int:
	var code := depression_id[index * 2] | (depression_id[index * 2 + 1] << 8)
	if code == NO_DEPRESSION_CODE:
		return DrainageNetwork.NO_DEPRESSION
	return code - 1


func is_sea(index: int) -> bool:
	return flow_direction[index] == DrainageNetwork.DIRECTION_SEA


func save_to(directory: String = DEFAULT_DIRECTORY) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	_store(directory.path_join(FLOW_FILE), flow_direction)
	_store(directory.path_join(DISCHARGE_FILE), discharge_log)
	_store(directory.path_join(DEPRESSION_FILE), depression_id)
	var meta := FileAccess.open(directory.path_join(META_FILE), FileAccess.WRITE)
	meta.store_string(JSON.stringify({
		"width": width,
		"height": height,
		"depressions": depressions,
	}))
	meta.close()


## True when a complete bake was read from `directory`. A missing bake is
## an ordinary state (the game runs without hydrology, exactly as before
## this module existed), not an error.
func load_from(directory: String = DEFAULT_DIRECTORY) -> bool:
	var meta_path := directory.path_join(META_FILE)
	if not FileAccess.file_exists(meta_path):
		return false
	var meta_file := FileAccess.open(meta_path, FileAccess.READ)
	var parsed = JSON.parse_string(meta_file.get_as_text())
	meta_file.close()
	if not (parsed is Dictionary):
		return false
	width = int(parsed["width"])
	height = int(parsed["height"])
	depressions.clear()
	for depression in parsed["depressions"]:
		depressions.append({
			"id": int(depression["id"]),
			"cell_count": int(depression["cell_count"]),
			"spill_elevation": float(depression["spill_elevation"]),
			"spill_index": int(depression["spill_index"]),
			"floor_elevation": float(depression["floor_elevation"]),
		})
	var count := width * height
	flow_direction = _read(directory.path_join(FLOW_FILE), count)
	discharge_log = _read(directory.path_join(DISCHARGE_FILE), count)
	depression_id = _read(directory.path_join(DEPRESSION_FILE), count * 2)
	return flow_direction.size() == count and discharge_log.size() == count and depression_id.size() == count * 2


func _store(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _read(path: String, expected_size: int) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var file := FileAccess.open(path, FileAccess.READ)
	var bytes := file.get_buffer(expected_size)
	file.close()
	return bytes
