extends RefCounted

## Pure I/O for the world clock (`EarthChunkManager._world_age_seconds`) --
## mirrors PlayerSave/EventStorePersistence's role: mechanics only
## (FileAccess, existence checks), no knowledge of what the number means or
## what reads it. EarthChunkManager itself owns the live value; this just
## round-trips it to disk following the SAME `store_var`/`get_var` convention
## PlayerSave/ChunkSerializer/EventStorePersistence already established,
## rather than inventing a second one for one more piece of world-scoped
## state (see docs/concept/persistence.md).
##
## Why this needs to exist at all: the clock previously wasn't persisted in
## ANY form -- a fresh EarthChunkManager always starts at world-age 0, and
## nothing ever wrote or read it back. New Game rolling a random starting
## point (see EarthChunkManager.randomize_world_age) is only meaningful if
## Load Game can resume that same point rather than landing back on the
## hardcoded 0 default -- see docs/concept/seasons.md.

const SAVE_PATH := "user://world_clock.bin"


func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


func save(world_age_seconds: float, path: String = SAVE_PATH) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var(world_age_seconds)
	file.close()


## `default` (0.0, matching EarthChunkManager's own fresh-instance value) when
## nothing has been saved yet -- the same "empty default on a missing file"
## contract PlayerSave.load_data/EventStorePersistence.load_store follow.
func load_seconds(path: String = SAVE_PATH, default: float = 0.0) -> float:
	if not FileAccess.file_exists(path):
		return default
	var file := FileAccess.open(path, FileAccess.READ)
	var value = file.get_var()
	file.close()
	return float(value)


func wipe(path: String = SAVE_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
