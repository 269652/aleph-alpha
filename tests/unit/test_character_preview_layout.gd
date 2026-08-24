extends GutTest

const CharacterPreviewLayout = preload("res://src/rendering/character_preview_layout.gd")

var footprint := Vector2(96, 96)


func test_generate_is_deterministic_for_the_same_seed():
	var a := CharacterPreviewLayout.generate(42, footprint)
	var b := CharacterPreviewLayout.generate(42, footprint)
	assert_eq(a.pond_center, b.pond_center)
	assert_eq(a.pond_radius, b.pond_radius)
	assert_eq(a.tree_positions, b.tree_positions)
	assert_eq(a.pebble_positions, b.pebble_positions)


func test_generate_produces_different_pond_centers_for_different_seeds():
	var a := CharacterPreviewLayout.generate(1, footprint)
	var b := CharacterPreviewLayout.generate(2, footprint)
	assert_ne(a.pond_center, b.pond_center)


func test_pond_stays_within_the_footprint():
	for seed_value in [1, 2, 3, 4, 5]:
		var layout := CharacterPreviewLayout.generate(seed_value, footprint)
		var rect := Rect2(Vector2.ZERO, footprint)
		assert_true(rect.has_point(layout.pond_center), "seed %d" % seed_value)


## Reported live: "the fish pond should be at the edge" -- a pond parked
## near dead-centre every time read as a specimen posed in the middle of
## an empty room rather than a real feature of a believable little scene.
## Checked as "close to WHICHEVER edge is nearest," not one specific side,
## since which edge is picked is itself seeded/random.
func test_pond_sits_close_to_one_edge_of_the_footprint():
	for seed_value in [1, 2, 3, 4, 5, 6, 7, 8]:
		var layout := CharacterPreviewLayout.generate(seed_value, footprint)
		var distance_to_nearest_edge: float = minf(
			minf(layout.pond_center.x, footprint.x - layout.pond_center.x),
			minf(layout.pond_center.y, footprint.y - layout.pond_center.y)
		)
		assert_almost_eq(
			distance_to_nearest_edge, layout.pond_radius, 8.0,
			"seed %d: pond centre %s should sit close to an edge of %s" % [seed_value, layout.pond_center, footprint]
		)


func test_tree_positions_are_within_the_footprint():
	var rect := Rect2(Vector2.ZERO, footprint)
	for seed_value in [1, 2, 3, 4, 5]:
		var layout := CharacterPreviewLayout.generate(seed_value, footprint)
		for tree_position in layout.tree_positions:
			assert_true(rect.has_point(tree_position), "seed %d, tree %s" % [seed_value, tree_position])


func test_tree_positions_do_not_overlap_the_pond():
	for seed_value in [1, 2, 3, 4, 5]:
		var layout := CharacterPreviewLayout.generate(seed_value, footprint)
		for tree_position in layout.tree_positions:
			var clearance: float = tree_position.distance_to(layout.pond_center)
			assert_true(
				clearance >= layout.pond_radius,
				"seed %d: tree at %s is only %.1f from a %.1f-radius pond" % [seed_value, tree_position, clearance, layout.pond_radius]
			)


func test_fish_positions_stay_inside_the_pond():
	var layout := CharacterPreviewLayout.generate(4, footprint)
	assert_gt(layout.fish_positions.size(), 0)
	for fish_position in layout.fish_positions:
		assert_true(fish_position.distance_to(layout.pond_center) < layout.pond_radius)


func test_pebble_positions_sit_near_the_ponds_rim():
	var layout := CharacterPreviewLayout.generate(3, footprint)
	assert_gt(layout.pebble_positions.size(), 0)
	for pebble_position in layout.pebble_positions:
		var distance_from_center: float = pebble_position.distance_to(layout.pond_center)
		# At or just outside the rim -- not deep in the water, not far out
		# in the grass.
		assert_between(distance_from_center, layout.pond_radius, layout.pond_radius + 6.0)


func test_grass_positions_avoid_the_pond():
	var layout := CharacterPreviewLayout.generate(5, footprint)
	for grass_position in layout.grass_positions:
		assert_true(grass_position.distance_to(layout.pond_center) > layout.pond_radius)


func test_grass_positions_avoid_the_trees():
	var layout := CharacterPreviewLayout.generate(5, footprint)
	for grass_position in layout.grass_positions:
		for tree_position in layout.tree_positions:
			assert_true(grass_position.distance_to(tree_position) >= CharacterPreviewLayout.TREE_MARGIN)


func test_is_clear_rejects_a_point_inside_the_pond():
	var layout := CharacterPreviewLayout.generate(9, footprint)
	assert_false(layout.is_clear(layout.pond_center))


func test_is_clear_rejects_a_point_too_close_to_a_tree():
	var layout := CharacterPreviewLayout.generate(9, footprint)
	assert_false(layout.is_clear(layout.tree_positions[0]))


func test_is_clear_accepts_a_point_far_from_the_pond_and_every_tree():
	var layout := CharacterPreviewLayout.generate(9, footprint)
	# The footprint's own corner is as far as it gets from a roughly
	# centred pond and trees kept away from the pond.
	var corner := Vector2.ZERO
	assert_true(layout.is_clear(corner))
