extends RefCounted
## Pure "what is visible on the map" projection over already-explored-tiles
## state -- docs/concept/wayfinding.md's Map item. Never stores anything
## itself; a real settlement/landmark only appears once its own chunk has
## actually been explored, never as a hint marker for something unfound.
##
## Reads two already-real inputs it does not own: an explored-chunks list
## (Array of Vector2i, the shape src/world/explored_tiles.gd's
## visited_chunks() returns) and a known-landmark registry (Array of
## Dictionary, each carrying at least a "chunk_coord" key). This module
## never mutates either -- it only filters.


## Whether `chunk_coord` is present in `explored_chunks`.
static func is_chunk_explored(explored_chunks: Array, chunk_coord: Vector2i) -> bool:
	return explored_chunks.has(chunk_coord)


## The subset of `known_landmarks` whose "chunk_coord" has actually been
## explored, in the same relative order they were given. A landmark
## dictionary is read with Dictionary.get (never direct indexing) so one
## missing "chunk_coord" key is safely excluded rather than crashing the
## whole projection.
static func landmarks_visible_on_map(explored_chunks: Array, known_landmarks: Array) -> Array:
	var visible: Array = []
	for landmark in known_landmarks:
		var chunk_coord = landmark.get("chunk_coord", null)
		if chunk_coord != null and is_chunk_explored(explored_chunks, chunk_coord):
			visible.append(landmark)
	return visible
