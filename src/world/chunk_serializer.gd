extends RefCounted

const Chunk = preload("res://src/world/chunk.gd")


## Saves a chunk to disk using Godot's native variant binary format.
func save_chunk(chunk: Chunk, path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var({
		"width": chunk.width,
		"height": chunk.height,
		"elevation": chunk.elevation,
		"biome": chunk.biome,
		"modifications": chunk.modifications,
	})
	file.close()


## Loads a chunk previously written by save_chunk, or null if the file doesn't exist.
func load_chunk(path: String) -> Chunk:
	if not FileAccess.file_exists(path):
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	var data: Dictionary = file.get_var()
	file.close()

	var chunk := Chunk.new()
	chunk.width = data["width"]
	chunk.height = data["height"]
	chunk.elevation = data["elevation"]
	chunk.biome = data["biome"]
	chunk.modifications = data["modifications"]
	return chunk


## Saves just a chunk's player-made modifications, not its terrain data --
## terrain is deterministically regenerable (see EarthChunkManager), so only
## the modifications are worth persisting across an unload/reload.
func save_modifications(modifications: Dictionary, path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var(modifications)
	file.close()


## Loads modifications previously written by save_modifications, or an empty
## Dictionary if the file doesn't exist.
func load_modifications(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	var data: Dictionary = file.get_var()
	file.close()
	return data


## Saves a chunk's spread-grown planted trees (see TreeSpread/
## EarthChunkManager.step_tree_spread) -- the original map-generated forest is
## deterministically regenerable like terrain, so only trees that spread
## since then need persisting across an unload/reload.
func save_planted_trees(planted_trees: Array, path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var(planted_trees)
	file.close()


## Loads planted trees previously written by save_planted_trees, or an empty
## Array if the file doesn't exist.
func load_planted_trees(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []

	var file := FileAccess.open(path, FileAccess.READ)
	var data: Array = file.get_var()
	file.close()
	return data
