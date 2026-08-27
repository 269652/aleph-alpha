extends RefCounted

## Pure I/O for the crafted-item registry -- mirrors EventStorePersistence/
## PlayerSave/ChunkSerializer's role: mechanics only (FileAccess, existence
## checks), no knowledge of what an assembly means. CraftedItemRegistry itself
## owns turning live state into/out of the plain Dictionary this reads and
## writes (see CraftedItemRegistry.to_dicts/from_dicts).
##
## Follows the same store_var/get_var convention PlayerSave/ChunkSerializer/
## EventStorePersistence already established for user://-backed Variant
## persistence, rather than inventing a second convention for one more kind of
## state. World-scoped, one file, the same shape as EventStorePersistence: an
## item's structure is not chunk-partitioned (an item travels with the player,
## and a traded one crosses chunks entirely), so chunk-per-file persistence
## would be actively wrong here rather than merely unnecessary.
##
## Written ALONGSIDE the inventory rather than inside it, deliberately. The
## inventory save is a list of {id, count}; if a structure blob lived inline
## there, one sword carried in two stacks would be serialized twice and could
## come back as two different structures. A separate id -> structure file is
## normalized by construction, and the id in the inventory is the foreign key.

const CraftedItemRegistry = preload("res://src/gameplay/crafted_item_registry.gd")

const SAVE_PATH := "user://crafted_items.bin"


func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


func save(registry: CraftedItemRegistry, path: String = SAVE_PATH) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var(registry.to_dicts())
	file.close()


func wipe(path: String = SAVE_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## Always returns a usable registry -- an empty one on a missing file, matching
## EventStorePersistence.load_store/PlayerSave.load_data's "empty default"
## contract rather than a null every caller would have to guard against
## separately. A save that survived the file system but not its contents is
## CraftedItemRegistry.from_dicts' problem, and it answers it the same way.
func load_registry(path: String = SAVE_PATH) -> CraftedItemRegistry:
	if not FileAccess.file_exists(path):
		return CraftedItemRegistry.new()
	var file := FileAccess.open(path, FileAccess.READ)
	var dicts = file.get_var()
	file.close()
	return CraftedItemRegistry.from_dicts(dicts)
