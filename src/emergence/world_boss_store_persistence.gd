extends RefCounted

## Pure I/O for the emergence world-boss store -- mirrors
## EventStorePersistence/.../InstitutionStorePersistence/PlayerSave's role
## exactly: mechanics only (FileAccess, existence checks), no knowledge of
## what a world boss means. Same store_var/get_var convention, same
## single-file world-scoped shape.

const WorldBossStore = preload("res://src/emergence/world_boss_store.gd")

const SAVE_PATH := "user://emergence_world_bosses.bin"


func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


func save(store: WorldBossStore, path: String = SAVE_PATH) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var(store.to_dicts())
	file.close()


func load_store(path: String = SAVE_PATH) -> WorldBossStore:
	if not FileAccess.file_exists(path):
		return WorldBossStore.new()
	var file := FileAccess.open(path, FileAccess.READ)
	var dicts = file.get_var()
	file.close()
	return WorldBossStore.from_dicts(dicts)


func wipe(path: String = SAVE_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
