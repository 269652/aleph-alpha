extends RefCounted

## The New Game side of docs/concept/persistence.md: wipes a user://-backed
## directory of per-chunk persistence files. Used on every one of
## EarthChunkManager's persistence dirs (MODIFICATIONS_DIR/PLANTED_TREES_DIR/
## FISH_POPULATION_DIR, read as its already-public constants -- this doesn't
## modify EarthChunkManager itself) so a freshly spawned character loads into
## a genuinely clean world instead of inheriting a previous run's edits.


## Deletes every file directly inside `dir_path` (no-op, no error, if the
## directory doesn't exist). Leaves the directory itself in place and usable.
func wipe_directory(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			dir.remove(entry)
		entry = dir.get_next()
	dir.list_dir_end()
