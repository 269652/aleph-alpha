extends RefCounted
## Per-player explored-chunk tracking (Vector2i chunk coordinates), docs/
## concept/wayfinding.md's Map item's real prerequisite. In-memory/session
## only for this pass -- deliberately NOT yet persisted across save/load
## (a named, documented gap, not an oversight -- matches this project's own
## convention of shipping a mechanism before its persistence layer, e.g.
## courtship/life_cycle's own documented persistence gap in docs/progress.md).

var _visited: Dictionary = {}  # Vector2i chunk_coord -> true


## Marks `chunk_coord` as explored. Returns true only if this chunk was
## newly marked (idempotent -- calling again for an already-visited chunk
## returns false and changes nothing).
func mark_visited(chunk_coord: Vector2i) -> bool:
	if _visited.has(chunk_coord):
		return false
	_visited[chunk_coord] = true
	return true


## Whether `chunk_coord` has ever been marked visited.
func is_visited(chunk_coord: Vector2i) -> bool:
	return _visited.has(chunk_coord)


## Every distinct chunk coordinate marked visited so far.
func visited_chunks() -> Array:
	return _visited.keys()


## How many distinct chunks have been marked visited so far.
func visited_count() -> int:
	return _visited.size()
