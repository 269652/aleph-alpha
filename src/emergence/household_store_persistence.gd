extends RefCounted

## Pure I/O for the emergence household store -- mirrors EventStorePersistence/
## MemoryStorePersistence/PlayerSave's role exactly: mechanics only
## (FileAccess, existence checks), no knowledge of what a household means.
## Same store_var/get_var convention, same single-file world-scoped shape.

const HouseholdStore = preload("res://src/emergence/household_store.gd")

const SAVE_PATH := "user://emergence_households.bin"


func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


func save(store: HouseholdStore, path: String = SAVE_PATH) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var(store.to_dicts())
	file.close()


func load_store(path: String = SAVE_PATH) -> HouseholdStore:
	if not FileAccess.file_exists(path):
		return HouseholdStore.new()
	var file := FileAccess.open(path, FileAccess.READ)
	var dicts = file.get_var()
	file.close()
	return HouseholdStore.from_dicts(dicts)


func wipe(path: String = SAVE_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
