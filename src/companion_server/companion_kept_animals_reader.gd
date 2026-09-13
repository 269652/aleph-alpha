extends RefCounted

## Scans the bounded chunk_kept_animals directory
## (EarthChunkManager.KEPT_ANIMALS_DIR, "user://chunk_kept_animals" by
## default) and flattens every chunk's KeptAnimals.load_all() records into
## one Array, each tagged with the chunk_coord its filename encoded --
## KeptAnimals itself only ever reads/writes ONE chunk's file at a time
## (`_kept_animals_path(chunk_coord)`), so nothing else in the codebase
## already does this scan. See docs/concept/companion_server.md's
## Companions section.
##
## Filenames are "{x}_{y}.bin" where x and y are each a plain base-10
## integer that may itself carry a leading "-" (a negative chunk
## coordinate) -- splitting the stem on "_" and taking exactly the first
## two parts is safe specifically because a signed int's own "-" is never
## itself an "_", so it never introduces an extra split point.

const KeptAnimals = preload("res://src/world/kept_animals.gd")


static func read_all(dir_path := "user://chunk_kept_animals") -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".bin"):
			var chunk_coord := _chunk_coord_from_filename(entry)
			var path := "%s/%s" % [dir_path, entry]
			for animal in KeptAnimals.load_all(path):
				animal["chunk_coord"] = chunk_coord
				out.append(animal)
		entry = dir.get_next()
	dir.list_dir_end()
	return out


static func _chunk_coord_from_filename(filename: String) -> Vector2i:
	var stem := filename.substr(0, filename.length() - ".bin".length())
	var parts := stem.split("_")
	return Vector2i(int(parts[0]), int(parts[1]))
