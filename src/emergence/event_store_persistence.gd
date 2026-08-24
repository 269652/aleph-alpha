extends RefCounted

## Pure I/O for the emergence event store -- mirrors PlayerSave/
## ChunkSerializer's role: mechanics only (FileAccess, existence checks), no
## knowledge of what an event means. EventStore itself owns turning live
## state into/out of the plain Array this reads and writes (see
## EventStore.to_dicts/from_dicts).
##
## Follows the same store_var/get_var convention PlayerSave/ChunkSerializer
## already established for user://-backed Variant persistence, rather than
## inventing a second convention for one more kind of world state. World-
## scoped, one file, the same shape as PlayerSave -- events are not naturally
## chunk-partitioned the way tree/fish data is (an event's location is a data
## field, not a partition key), so chunk-per-file persistence is deliberately
## not used here; revisit if/when the store's size becomes a real concern.

const EventStore = preload("res://src/emergence/event_store.gd")

const SAVE_PATH := "user://emergence_events.bin"


func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


func save(store: EventStore, path: String = SAVE_PATH) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var(store.to_dicts())
	file.close()


func wipe(path: String = SAVE_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## Always returns a usable store -- an empty one on a missing file, matching
## PlayerSave.load_data's "empty default" contract rather than a null a caller
## would have to guard against separately.
func load_store(path: String = SAVE_PATH) -> EventStore:
	if not FileAccess.file_exists(path):
		return EventStore.new()
	var file := FileAccess.open(path, FileAccess.READ)
	var dicts = file.get_var()
	file.close()
	return EventStore.from_dicts(dicts)
