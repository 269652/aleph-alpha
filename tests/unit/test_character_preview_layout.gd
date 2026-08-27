extends GutTest

const CharacterPreviewLayout = preload("res://src/rendering/character_preview_layout.gd")
## The real world's own grassland rule and the real tree art's own size --
## the diorama is a corner of that world, so both its meadow density and its
## placement margins are checked against the originals, never against a
## number invented for the preview (see each test's own doc comment).
const TallGrass = preload("res://src/world/tall_grass.gd")
const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")

var footprint := Vector2(96, 96)


## How many of the footprint's grass cells are free of the pond and trees --
## the denominator the meadow's coverage is measured against, walked exactly
## the way generate() itself walks them.
func _clear_cell_count(result, fp: Vector2) -> int:
	var count := 0
	var columns := int(fp.x / CharacterPreviewLayout.GRASS_CLUMP_SPACING)
	var rows := int(fp.y / CharacterPreviewLayout.GRASS_CLUMP_SPACING)
	for cell_y in rows:
		for cell_x in columns:
			var point := Vector2(
				(float(cell_x) + 0.5) * CharacterPreviewLayout.GRASS_CLUMP_SPACING,
				(float(cell_y) + 0.5) * CharacterPreviewLayout.GRASS_CLUMP_SPACING
			)
			if result.is_clear(point):
				count += 1
	return count


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


## The diorama is a corner of the REAL world, so its meadow has to read at
## the real world's own grassland density -- TallGrass.SEED_CHANCE, the
## reference coverage TallGrass's field-noise threshold is itself pinned to
## (see FIELD_NOISE_THRESHOLD's own doc comment). Placing a clump on EVERY
## clear cell was ~100% coverage, ~5x that, and since each clump draws
## IllustratedGrassPatch.CARD_COUNT overlapping full-tile cards the hero
## read as buried in a hedge rather than walking through a field (reported
## live: "grass tufts several times his height").
func test_grass_coverage_matches_the_real_worlds_own_meadow_density():
	var clear_cells := 0
	var grass_cells := 0
	for seed_value in 200:
		var result := CharacterPreviewLayout.generate(seed_value, footprint)
		clear_cells += _clear_cell_count(result, footprint)
		grass_cells += result.grass_positions.size()
	var coverage := float(grass_cells) / float(clear_cells)
	assert_almost_eq(
		coverage, TallGrass.SEED_CHANCE, 0.03,
		"meadow coverage %f should match the real world's own %f" % [coverage, TallGrass.SEED_CHANCE]
	)


## The guard against over-correcting into a bald diorama: thinning the
## meadow must never leave a seed with no grass at all.
func test_every_seed_still_places_some_grass():
	for seed_value in 200:
		var result := CharacterPreviewLayout.generate(seed_value, footprint)
		assert_gt(result.grass_positions.size(), 0, "seed %d placed no grass at all" % seed_value)


## The grass that IS kept has to clump, not speckle: a meadow reads as
## drifts of grass, which is why the cells are chosen by the same smooth
## noise field TallGrass seeds a chunk with rather than by an independent
## per-cell roll. Measured as "most kept cells touch another kept cell" --
## an independent 20% roll over a 6x6 grid would leave most of them
## isolated.
func test_kept_grass_cells_clump_together():
	var touching := 0
	var total := 0
	for seed_value in 60:
		var result := CharacterPreviewLayout.generate(seed_value, footprint)
		for a in result.grass_positions:
			total += 1
			for b in result.grass_positions:
				if a != b and a.distance_to(b) <= CharacterPreviewLayout.GRASS_CLUMP_SPACING * 1.5:
					touching += 1
					break
	assert_gt(
		float(touching) / float(total), 0.5,
		"only %d of %d kept grass cells neighbour another -- the meadow is speckling, not drifting" % [touching, total]
	)


## The camera frames exactly the footprint (see CharacterPreviewDiorama's
## own FOOTPRINT and main_menu's derived camera zoom), and a tree is drawn
## from its trunk FOOT upward across ProceduralTreeSprite.WORLD_SIZE -- so a
## position sampled from the raw footprint puts canopies above the frame's
## top edge and trunks past its sides (reported live: trees clipped by the
## frame).
func test_tree_positions_leave_room_for_the_trees_own_drawn_body():
	var half_width := float(ProceduralTreeSprite.WORLD_SIZE.x) * 0.5
	var height := float(ProceduralTreeSprite.WORLD_SIZE.y)
	for seed_value in 60:
		var result := CharacterPreviewLayout.generate(seed_value, footprint)
		for tree_position in result.tree_positions:
			assert_gte(tree_position.x - half_width, 0.0, "seed %d: tree %s clipped at the left" % [seed_value, tree_position])
			assert_lte(tree_position.x + half_width, footprint.x, "seed %d: tree %s clipped at the right" % [seed_value, tree_position])
			assert_gte(tree_position.y - height, 0.0, "seed %d: tree %s canopy clipped at the top" % [seed_value, tree_position])
			assert_lte(tree_position.y, footprint.y, "seed %d: tree %s clipped at the bottom" % [seed_value, tree_position])


## The inset band is derived from the tree art's own world size, never an
## eyeballed margin -- if the art ever changes size the placement follows it.
func test_tree_bounds_are_derived_from_the_tree_arts_own_size():
	var bounds := CharacterPreviewLayout.tree_bounds(footprint)
	assert_eq(bounds.position, Vector2(float(ProceduralTreeSprite.WORLD_SIZE.x) * 0.5, float(ProceduralTreeSprite.WORLD_SIZE.y)))
	assert_eq(bounds.end, Vector2(footprint.x - float(ProceduralTreeSprite.WORLD_SIZE.x) * 0.5, footprint.y))


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
