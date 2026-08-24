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


## Saves a chunk's aggregate fish population -- a single scalar, one file per
## chunk like modifications/planted_trees (see
## docs/concept/fishing.md#persistence-a-gap-shared-with-land-ecology-worth-closing-here-first).
## Unlike herbivore/predator/vegetation state, this is meant to survive a
## real game restart, not just an in-session unload/reload, so "fish a hole
## out, come back tomorrow and it's still down" actually holds.
func save_fish_population(fish_population: float, path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_float(fish_population)
	file.close()


## Saves a chunk's land-ecology state so it survives a real game restart, not
## just an in-session unload/reload.
##
## This was the gap save_fish_population's own comment named: fish persisted,
## but herbivores, predators and vegetation lived only in EarthChunkManager's
## in-memory `_unloaded_ecology`, so quitting the game reset every region to a
## freshly-seeded population at full carrying capacity. A herd the player had
## hunted down, or one they had watched grow, was back to default next time
## they launched.
##
## `saved_at_unix` is WALL-CLOCK time, deliberately: the world is meant to
## have moved on when the player comes back tomorrow, and the in-game clock
## restarts with the session (see LifeCycle, which puts the whole growth
## timescale on real days for the same reason).
## `land_health` (docs/concept/world.md "Land health: overharvesting leaves
## a lasting mark, not just a slower respawn") was added AFTER this file
## format's original 4 fields -- appended at the end, not interleaved, so an
## old save (see load_ecology) still reads its first 4 fields correctly and
## simply ends before this one.
func save_ecology(state: Dictionary, path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_float(float(state.get("herbivores", 0.0)))
	file.store_float(float(state.get("predators", 0.0)))
	file.store_float(float(state.get("vegetation", 0.0)))
	file.store_double(float(state.get("saved_at_unix", 0.0)))
	file.store_float(float(state.get("land_health", 1.0)))
	file.close()


## Loads land-ecology state written by save_ecology. Returns an EMPTY
## dictionary when there is no file, so callers can tell "never persisted"
## from "persisted as zero" -- a region really can be hunted down to nothing,
## and that is a fact worth keeping rather than silently re-seeding.
##
## `land_health` reads as 1.0 (pristine) for a file saved before this field
## existed (see save_ecology's doc comment) -- checked by file position
## rather than assumed, so an old, shorter save loads its other 4 fields
## correctly instead of reading past end-of-file for a field it never wrote.
func load_ecology(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var state := {
		"herbivores": file.get_float(),
		"predators": file.get_float(),
		"vegetation": file.get_float(),
		"saved_at_unix": file.get_double(),
	}
	if file.get_position() < file.get_length():
		state["land_health"] = file.get_float()
	else:
		state["land_health"] = 1.0
	file.close()
	return state


## Loads fish population previously written by save_fish_population, or 0.0
## if the file doesn't exist. 0.0 is ALSO a legitimate persisted value (a
## fished-out chunk) -- callers that need to distinguish "never persisted"
## from "persisted as zero" must check FileAccess.file_exists themselves
## (see EarthChunkManager), the same way load_modifications's empty-dict
## default can't distinguish "never modified" from "modified back to empty".
func load_fish_population(path: String) -> float:
	if not FileAccess.file_exists(path):
		return 0.0

	var file := FileAccess.open(path, FileAccess.READ)
	var data := file.get_float()
	file.close()
	return data
