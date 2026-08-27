extends RefCounted

## The New Game side of docs/concept/persistence.md: backs up, and then wipes,
## the user://-backed state a previous run left behind -- directories of
## per-chunk persistence files and the single-file stores alike. Used on every
## one of EarthChunkManager's persistence dirs (MODIFICATIONS_DIR/
## PLANTED_TREES_DIR/FISH_POPULATION_DIR, read as its already-public constants
## -- this doesn't modify EarthChunkManager itself) so a freshly spawned
## character loads into a genuinely clean world instead of inheriting a
## previous run's edits.
##
## The backup half exists because New Game is the only irreversible action in
## the game and it had no undo at all: it destroyed a whole world's chunk
## edits, planted trees, fish populations, every emergence store, the world
## clock and the player's save, and the 60-second autosave then overwrote
## player_save.bin, closing even the file-recovery window.


## What a pre-wipe backup is called: the original's own path with this
## appended, so the copy lives right next to what it is a copy of.
##
## Exactly ONE generation, overwritten by each New Game -- enough to undo the
## last accidental wipe, not an archive that grows without bound. New Game is
## the only irreversible button in the game (see docs/concept/persistence.md,
## pillar 1: "New Game means new... and recoverable").
const BACKUP_SUFFIX := ".bak"


## Copies `path` aside to `path + BACKUP_SUFFIX` before something removes it,
## replacing any previous backup. Returns whether a backup was written --
## false means there was nothing there to copy (a first-ever New Game), which
## is not an error.
func backup_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var backup := path + BACKUP_SUFFIX
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	return DirAccess.copy_absolute(path, backup) == OK


## Copies every file directly inside `dir_path` into `dir_path +
## BACKUP_SUFFIX`, emptying that backup directory first so it mirrors exactly
## ONE wipe rather than accumulating every world ever destroyed. No-op, no
## error, when `dir_path` doesn't exist.
func backup_directory(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var backup_dir := dir_path + BACKUP_SUFFIX
	DirAccess.make_dir_recursive_absolute(backup_dir)
	wipe_directory(backup_dir)
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			DirAccess.copy_absolute(dir_path + "/" + entry, backup_dir + "/" + entry)
		entry = dir.get_next()
	dir.list_dir_end()


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
