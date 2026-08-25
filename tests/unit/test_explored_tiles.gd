extends GutTest

## ExploredTiles: per-player explored-chunk tracking (see
## docs/concept/wayfinding.md's Map item -- "nothing currently tracks
## has this player seen this tile").

const ExploredTiles = preload("res://src/world/explored_tiles.gd")


# -- mark_visited: newly-marking returns true, re-marking is idempotent ----

func test_marking_a_fresh_chunk_returns_true():
	var tracker := ExploredTiles.new()
	assert_true(tracker.mark_visited(Vector2i(2, 3)))


func test_marking_a_fresh_chunk_makes_it_visited():
	var tracker := ExploredTiles.new()
	tracker.mark_visited(Vector2i(2, 3))
	assert_true(tracker.is_visited(Vector2i(2, 3)))


func test_marking_an_already_visited_chunk_returns_false():
	var tracker := ExploredTiles.new()
	tracker.mark_visited(Vector2i(2, 3))
	assert_false(tracker.mark_visited(Vector2i(2, 3)))


func test_marking_an_already_visited_chunk_does_not_change_the_count():
	var tracker := ExploredTiles.new()
	tracker.mark_visited(Vector2i(2, 3))
	tracker.mark_visited(Vector2i(2, 3))
	assert_eq(tracker.visited_count(), 1)


# -- is_visited: false for anything never marked ---------------------------

func test_is_visited_is_false_for_a_chunk_never_marked():
	var tracker := ExploredTiles.new()
	assert_false(tracker.is_visited(Vector2i(5, -7)))


func test_is_visited_is_false_on_a_brand_new_tracker_with_no_history():
	var tracker := ExploredTiles.new()
	assert_false(tracker.is_visited(Vector2i.ZERO))


# -- visited_chunks / visited_count: reflect multiple distinct chunks ------

func test_visited_count_reflects_multiple_distinct_chunks():
	var tracker := ExploredTiles.new()
	tracker.mark_visited(Vector2i(0, 0))
	tracker.mark_visited(Vector2i(1, 0))
	tracker.mark_visited(Vector2i(0, 1))
	assert_eq(tracker.visited_count(), 3)


func test_visited_chunks_contains_every_distinct_marked_chunk():
	var tracker := ExploredTiles.new()
	tracker.mark_visited(Vector2i(0, 0))
	tracker.mark_visited(Vector2i(1, 0))
	tracker.mark_visited(Vector2i(0, 1))
	var chunks := tracker.visited_chunks()
	assert_eq(chunks.size(), 3)
	assert_true(chunks.has(Vector2i(0, 0)))
	assert_true(chunks.has(Vector2i(1, 0)))
	assert_true(chunks.has(Vector2i(0, 1)))


func test_visited_chunks_on_a_brand_new_tracker_is_empty():
	var tracker := ExploredTiles.new()
	assert_eq(tracker.visited_chunks().size(), 0)


# -- Vector2i value equality holds for Dictionary keys ---------------------

func test_two_vector2i_with_same_components_are_treated_as_the_same_chunk():
	var tracker := ExploredTiles.new()
	tracker.mark_visited(Vector2i(4, 9))
	# A freshly-constructed Vector2i with identical components is a
	# different object but must be the same Dictionary key/visited chunk --
	# confirmed here directly rather than assumed.
	var same_coord := Vector2i(4, 9)
	assert_true(tracker.is_visited(same_coord))
	assert_false(tracker.mark_visited(same_coord))
	assert_eq(tracker.visited_count(), 1)
