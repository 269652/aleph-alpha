extends RefCounted

## Pure I/O for TerrainRenderer's baked atlas image (see
## docs/concept/art_resolution.md#boot-performance). build_tile_set() paints
## thousands of tiles, TILE_SIZE^2 pixels each -- fully deterministic, so its
## output only ever needs generating once per atlas VERSION rather than once
## per game session. Mirrors PlayerSave's shape (mechanics only, path
## arguments default to the real location but are overridable so tests never
## touch it) adapted for an Image: `Image.save_png`/`Image.load` is a faster,
## more compact round-trip for pixel data than store_var's generic Variant
## encoding.

const CACHE_PATH := "user://terrain_atlas_cache.png"
const VERSION_PATH := "user://terrain_atlas_cache_version.txt"


## True only if a cached image exists AND was saved under this exact
## `version` string -- callers bump their version constant whenever the
## generation logic changes, so a cache from an older build is never
## silently reused.
func has_valid_cache(version: String, cache_path: String = CACHE_PATH, version_path: String = VERSION_PATH) -> bool:
	if not FileAccess.file_exists(cache_path) or not FileAccess.file_exists(version_path):
		return false
	var file := FileAccess.open(version_path, FileAccess.READ)
	var cached_version := file.get_as_text()
	file.close()
	return cached_version == version


func save(image: Image, version: String, cache_path: String = CACHE_PATH, version_path: String = VERSION_PATH) -> void:
	image.save_png(cache_path)
	var file := FileAccess.open(version_path, FileAccess.WRITE)
	file.store_string(version)
	file.close()


## Null (not a crash) if the file is missing or fails to decode -- callers
## should fall back to regenerating rather than trust a damaged cache.
func load_image(cache_path: String = CACHE_PATH) -> Image:
	if not FileAccess.file_exists(cache_path):
		return null
	var image := Image.new()
	var error := image.load(cache_path)
	if error != OK:
		return null
	return image


func wipe(cache_path: String = CACHE_PATH, version_path: String = VERSION_PATH) -> void:
	if FileAccess.file_exists(cache_path):
		DirAccess.remove_absolute(cache_path)
	if FileAccess.file_exists(version_path):
		DirAccess.remove_absolute(version_path)
