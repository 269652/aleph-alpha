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
## Falls back to decoding the file's own bytes whenever that imported
## resource is not really there to load -- a freshly-added sheet in a
## headless run that has never opened the project in the editor, whether it
## has no `*.png.import` sidecar yet OR has one whose artifact under
## `.godot/` was never generated (see _import_is_on_disk: ResourceLoader
## answers off the sidecar alone and cannot tell those two apart).
static func load_image(path: String) -> Image:
	if _import_is_on_disk(path):
		var resource := load(path)
		if resource is Texture2D:
			return resource.get_image()
	return _image_from_bytes(path)


## Whether this path's IMPORTED resource really exists to be loaded.
##
## [method ResourceLoader.exists] is not that question. It answers TRUE off
## the committed `*.png.import` sidecar alone, whether or not the artifact
## that sidecar points at under `.godot/imported/` has ever been generated --
## and on a fresh checkout that has never been opened in the editor, it has
## not. load() then fails on the missing `.ctex` with an engine error and
## returns null, for a sheet sitting right there on disk.
##
## Found with assets/sprites/vehicles/cart.png (test_sprite_sheet_loader.gd's
## own test_every_sheet_the_repo_ships_loads_without_an_engine_error): the
## sidecar was committed in a container that never ran an editor import, and
## the whole cart suite failed on art that loads perfectly from its own
## bytes.
##
## A path with no sidecar at all is not an imported asset, so
## ResourceLoader's own answer is the right one for it.
static func _import_is_on_disk(path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var sidecar := path + ".import"
	if not FileAccess.file_exists(sidecar):
		return true
	var config := ConfigFile.new()
	if config.load(sidecar) != OK:
		return false
	var destination = config.get_value("remap", "path", null)
	if destination == null:
		# A multi-variant import (an atlas, or per-platform compression)
		# keys its outputs "path.<suffix>" instead of a single "path".
		for key in config.get_section_keys("remap"):
			if key.begins_with("path."):
				destination = config.get_value("remap", key)
				break
	return destination != null and FileAccess.file_exists(String(destination))


## The sheet decoded straight from its own bytes, or null.
##
## Deliberately NOT [method Image.load_from_file]: on a `res://` path that
## logs the very "Loaded resource as image file, this will not work on
## export" warning this whole loader exists to avoid, which GUT counts as an
## unexpected error and fails whichever test touched the sheet first. Reading
## the file and decoding the buffer is the same pixels with nothing said
## about it.
static func _image_from_bytes(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var image := Image.new()
	var extension := path.get_extension().to_lower()
	var error := ERR_FILE_UNRECOGNIZED
	match extension:
		"png":
			error = image.load_png_from_buffer(bytes)
		"jpg", "jpeg":
			error = image.load_jpg_from_buffer(bytes)
		"webp":
			error = image.load_webp_from_buffer(bytes)
		"bmp":
			error = image.load_bmp_from_buffer(bytes)
	if error != OK:
		return null
	return image
