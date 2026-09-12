extends RefCounted

## Where a new game begins: a random point along a random curated river
## (docs/concept/rivers.md "Spawn: a random curated river"; pinned by
## tests/unit/test_spawn_river_picker.gd).
##
## Pure. `courses` is RiverCatalog.tile_polylines(...)'s shape -- river name
## -> Array of Vector2 tile points along the smoothed course -- `rng` is the
## caller's seeded RandomNumberGenerator (a real new game randomizes it, a
## dev launch fixes it so a measurement lands in the same place every
## time), and `is_acceptable(tile) -> bool` is the caller's own verdict on
## whether a person could stand there: World checks the tile is above sea
## level and below the mountain line, warm enough, and really a river tile.
##
## A river's first and last points are never candidates -- a spring is a
## mountain and a mouth is the sea -- so a course needs at least three
## points to have an interior at all. Rivers are drawn by name in sorted
## order so the same seed means the same place on every machine (a
## Dictionary's own iteration order is not a contract). Each attempt draws
## a fresh river and a fresh interior point, so a river with no acceptable
## point simply costs one attempt and another river comes up; after
## `attempts` rejections the result is {} and the caller falls back to its
## fixed spawn (World.SPAWN_LATITUDE/LONGITUDE, the Loire at Nantes).


static func pick(courses: Dictionary, rng: RandomNumberGenerator, is_acceptable: Callable, attempts: int) -> Dictionary:
	var names: Array = []
	for name in courses:
		if courses[name].size() >= 3:
			names.append(name)
	if names.is_empty():
		return {}
	names.sort()
	for _attempt in attempts:
		var name: String = names[rng.randi_range(0, names.size() - 1)]
		var course: Array = courses[name]
		var point: Vector2 = course[rng.randi_range(1, course.size() - 2)]
		var tile := Vector2i(point)
		if is_acceptable.call(tile):
			return {"river": name, "tile": tile}
	return {}
