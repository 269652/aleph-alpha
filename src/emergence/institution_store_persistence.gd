extends RefCounted

## Pure I/O for the emergence institution store -- mirrors
## EventStorePersistence/.../MarketStorePersistence/PlayerSave's role
## exactly: mechanics only (FileAccess, existence checks), no knowledge of
## what an institution means. Same store_var/get_var convention, same
## single-file world-scoped shape.

const InstitutionStore = preload("res://src/emergence/institution_store.gd")

const SAVE_PATH := "user://emergence_institutions.bin"


func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


func save(store: InstitutionStore, path: String = SAVE_PATH) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var(store.to_dicts())
	file.close()


func load_store(path: String = SAVE_PATH) -> InstitutionStore:
	if not FileAccess.file_exists(path):
		return InstitutionStore.new()
	var file := FileAccess.open(path, FileAccess.READ)
	var dicts = file.get_var()
	file.close()
	return InstitutionStore.from_dicts(dicts)


func wipe(path: String = SAVE_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
