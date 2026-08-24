extends RefCounted

## Shared image-loading helper for every illustrated sprite sheet in this
## codebase.
##
## `Image.load_from_file()` reads a PNG straight off disk, bypassing the
## resource/import system entirely. That is fine in the editor, but it (a)
## logs an engine WARNING ("Loaded resource as image file, this will not
## work on export") that GUT's test runner counts as an unhandled error and
## fails the test over even when every assertion in it passes, and (b) is a
## genuine export-time bug: a raw source PNG under res:// does not ship in
## an exported build the way its imported resource does.
##
## `load_image` prefers the imported resource -- via `load()`, which reads
## the checked-in `.import` file -- and only falls back to a raw file read
## when the path is not a registered resource at all (e.g. a fixture written
## at runtime, or an unimported PNG in a headless test run before
## `--import` has been run).
static func load_image(path: String) -> Image:
	if ResourceLoader.exists(path):
		var resource := load(path)
		if resource is Texture2D:
			return resource.get_image()
	return Image.load_from_file(path)
