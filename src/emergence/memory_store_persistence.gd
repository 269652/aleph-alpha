extends RefCounted

## Pure I/O for the emergence memory store -- mirrors EventStorePersistence/
## PlayerSave's role exactly: mechanics only (FileAccess, existence checks),
## no knowledge of what a memory means. MemoryStore itself owns turning live
## state into/out of the plain Array this reads and writes (see
## MemoryStore.to_dicts/from_dicts).
##
## Same store_var/get_var convention, same single-file world-scoped shape as
## EventStorePersistence -- one more piece of world state following the one
## convention this project already established, not a second one.

const MemoryStore = preload("res://src/emergence/memory_store.gd")

const SAVE_PATH := "user://emergence_memories.bin"


func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


func save(bank: MemoryStore, path: String = SAVE_PATH) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var(bank.to_dicts())
	file.close()


func load_bank(path: String = SAVE_PATH) -> MemoryStore:
	if not FileAccess.file_exists(path):
		return MemoryStore.new()
	var file := FileAccess.open(path, FileAccess.READ)
	var dicts = file.get_var()
	file.close()
	return MemoryStore.from_dicts(dicts)


func wipe(path: String = SAVE_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
