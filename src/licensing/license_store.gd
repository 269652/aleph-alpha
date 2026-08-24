extends RefCounted

## Reads the player's license code from disk (see docs/licensing.md). A
## real file the customer places next to the game after purchase, not an
## in-game typed/pasted text field -- that's real FileAccess I/O, not pure
## logic, so this takes an explicit candidate-path list rather than
## hardcoding where "next to the executable" resolves to, letting a test
## point it at a real temp file instead of the actual install location.


## Reads and trims whitespace from the first candidate path that exists,
## or "" if none do. A license file legitimately holds ONLY the pasted
## code -- nothing else to parse out of it, and no case here for "found
## the file but it was somehow unreadable" needing a different result than
## "not found" -- both mean the game has no code to try verifying.
static func read_code(candidate_paths: Array[String]) -> String:
	for path in candidate_paths:
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		return file.get_as_text().strip_edges()
	return ""


## The real candidate paths the shipped game checks, in priority order:
## next to the running executable first (where a customer would naturally
## drop a file after extracting/installing the game -- the most
## discoverable location for someone who isn't a developer), then Godot's
## user:// data directory as a fallback (covers a store/launcher
## distribution that might place it there instead).
static func default_candidate_paths() -> Array[String]:
	var executable_dir := OS.get_executable_path().get_base_dir()
	var paths: Array[String] = []
	paths.append(executable_dir.path_join("license.txt"))
	paths.append("user://license.txt")
	return paths
