extends RefCounted

## Pure I/O for the settlement construction ledger (ConstructionProjectStore)
## -- the exact sibling of MarketStorePersistence/InstitutionStorePersistence,
## closing docs/concept/timber_construction.md's own long-named "no
## persistence wrapper yet -- to_dicts/from_dicts are real but nothing calls
## them from a save path" gap: a City Hall takes real hours of labour
## (docs/concept/civic_construction.md), and an in-memory ledger threw every
## hour away on restart. Saved and loaded with the other emergence stores
## (World._save_local_player / the Load Game path), wiped by New Game.

const ConstructionProjectStore = preload("res://src/emergence/construction_project_store.gd")

const SAVE_PATH := "user://emergence_construction_projects.bin"


func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


func save(store: ConstructionProjectStore, path: String = SAVE_PATH) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var(store.to_dicts())
	file.close()


func load_store(path: String = SAVE_PATH) -> ConstructionProjectStore:
	if not FileAccess.file_exists(path):
		return ConstructionProjectStore.new()
	var file := FileAccess.open(path, FileAccess.READ)
	var dicts = file.get_var()
	file.close()
	return ConstructionProjectStore.from_dicts(dicts)


func wipe(path: String = SAVE_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
