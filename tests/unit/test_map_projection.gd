extends GutTest

## MapProjection: pure "what is visible on the map" projection over
## already-explored-tiles state (see docs/concept/wayfinding.md's Map item).

const MapProjection = preload("res://src/world/map_projection.gd")


# -- is_chunk_explored: membership check against the explored-chunks list --

func test_is_chunk_explored_true_when_coord_is_in_the_list():
	var explored: Array = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 3)]
	assert_true(MapProjection.is_chunk_explored(explored, Vector2i(1, 0)))


func test_is_chunk_explored_false_when_coord_is_not_in_the_list():
	var explored: Array = [Vector2i(0, 0), Vector2i(1, 0)]
	assert_false(MapProjection.is_chunk_explored(explored, Vector2i(5, 5)))


func test_is_chunk_explored_false_for_an_empty_explored_list():
	var explored: Array = []
	assert_false(MapProjection.is_chunk_explored(explored, Vector2i(0, 0)))


# -- landmarks_visible_on_map: only explored landmarks pass through --------

func test_unexplored_landmark_is_filtered_out():
	var explored: Array = [Vector2i(0, 0)]
	var landmarks: Array = [{"chunk_coord": Vector2i(9, 9), "name": "Farhold"}]
	var visible := MapProjection.landmarks_visible_on_map(explored, landmarks)
	assert_eq(visible.size(), 0)


func test_explored_landmark_passes_through_with_all_original_keys_intact():
	var explored: Array = [Vector2i(2, 3)]
	var landmark := {"chunk_coord": Vector2i(2, 3), "name": "Riverbend", "kind": "settlement"}
	var visible := MapProjection.landmarks_visible_on_map(explored, [landmark])
	assert_eq(visible.size(), 1)
	assert_eq(visible[0], landmark)


func test_empty_explored_list_hides_every_landmark():
	var landmarks: Array = [
		{"chunk_coord": Vector2i(0, 0), "name": "Ashford"},
		{"chunk_coord": Vector2i(1, 1), "name": "Kellwick"},
	]
	var visible := MapProjection.landmarks_visible_on_map([], landmarks)
	assert_eq(visible.size(), 0)


func test_multiple_landmarks_in_the_same_explored_chunk_all_show():
	var explored: Array = [Vector2i(4, 4)]
	var landmarks: Array = [
		{"chunk_coord": Vector2i(4, 4), "name": "Old Well"},
		{"chunk_coord": Vector2i(4, 4), "name": "Watchtower"},
	]
	var visible := MapProjection.landmarks_visible_on_map(explored, landmarks)
	assert_eq(visible.size(), 2)


func test_visible_landmarks_preserve_the_original_relative_order():
	var explored: Array = [Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 2)]
	var landmarks: Array = [
		{"chunk_coord": Vector2i(2, 2), "name": "Third"},
		{"chunk_coord": Vector2i(0, 0), "name": "First"},
		{"chunk_coord": Vector2i(1, 1), "name": "Second"},
	]
	var visible := MapProjection.landmarks_visible_on_map(explored, landmarks)
	assert_eq(visible.size(), 3)
	assert_eq(visible[0]["name"], "Third")
	assert_eq(visible[1]["name"], "First")
	assert_eq(visible[2]["name"], "Second")


func test_landmark_missing_chunk_coord_key_is_safely_excluded_not_crashing():
	var explored: Array = [Vector2i(0, 0)]
	var landmarks: Array = [{"name": "No Coord At All"}]
	var visible := MapProjection.landmarks_visible_on_map(explored, landmarks)
	assert_eq(visible.size(), 0)
