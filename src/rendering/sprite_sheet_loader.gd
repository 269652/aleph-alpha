extends RefCounted

## Loads an illustrated-art sheet PNG as an [Image], preferring Godot's own
## imported resource over a raw file read.
##
## [method Image.load_from_file] on a `res://` path bypasses the import
## system entirely: it works, but logs "Loaded resource as image file, this
## will not work on export" -- a real warning, not just noise, since a raw
## source PNG under `res://` does not ship in an exported build the way its
## imported resource does (every sheet under assets/sprites/ already carries
## its own *.png.import, generated the first time the project opened in the
## editor). [method @GlobalScope.load] uses that imported resource instead,
## which is exactly what the warning's own message asks for -- and avoids the
## warning outright.
##
## That warning also intermittently failed tests: GUT treats any unhandled
## engine warning as an "Unexpected Error", so whichever test happened to be
## first to load a given sheet in a run would fail (illustrated-art classes
## then cache the sliced frames, so every later test touching the same sheet
## passed clean) -- an order-dependent flake confirmed in
## test_stone_renderer.gd. IllustratedTree hit this same warning first and
## fixed it with the load()-first shape this reuses (see its own
## _load_image); this pulls that fix into a shared loader every
## illustrated-art class can use instead of duplicating it per file.
##
## Falls back to reading the raw file when the path has no import yet -- a
## freshly-added sheet in a headless test run that has never opened the
## project in the editor, before Godot has generated its .import.
static func load_image(path: String) -> Image:
	if ResourceLoader.exists(path):
		var resource := load(path)
		if resource is Texture2D:
			return resource.get_image()
	if FileAccess.file_exists(path):
		return Image.load_from_file(path)
	return null
