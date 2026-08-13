extends RefCounted

## Pure I/O for the player's persisted state (see docs/concept/persistence.md)
## -- mirrors ChunkSerializer's role: mechanics only (FileAccess, existence
## checks), no knowledge of what the saved Dictionary's keys mean. Player
## itself owns turning live state into/out of that plain Dictionary (see
## Player.to_save_dict/apply_save_dict).
##
## Follows the same `store_var`/`get_var` convention EarthChunkManager's
## ChunkSerializer already established for user://-backed Variant persistence
## -- a `file_exists` guard, an empty default on a missing file -- rather than
## inventing a second convention.

## Single local save slot -- no multi-save-slot UI exists or is planned.
const SAVE_PATH := "user://player_save.bin"


func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


func save(data: Dictionary, path: String = SAVE_PATH) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var(data)
	file.close()


func load_data(path: String = SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var data = file.get_var()
	file.close()
	return data


func wipe(path: String = SAVE_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
