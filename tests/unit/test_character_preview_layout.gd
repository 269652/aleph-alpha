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


## FISH_SAFE_RADIUS_FRACTION must keep a fish's whole drawn BODY inside the
## region the pond's own water shader renders as fully, unambiguously
## opaque water -- not just inside the pond's nominal geometric radius, which
## is considerably bigger than the visually-obvious water (reported live:
## "fish are still spawned on land" -- they were inside pond_radius, just
## well into the shore's own alpha fade). _build_pond (character_preview_
## diorama.gd) renders with all 4 cardinal land_directions, so
## ProceduralShoreDistanceSprite's own per-pixel value is the MIN distance
## to whichever tile edge is nearest -- for a point straight out from centre
## along one axis (the worst case: a diagonal point of the same Euclidean
## distance sits further from every edge, so it fades later), that raw value
## is exactly 0.5 * (1.0 - radius_fraction) of the pond's own radius. Mirrors
## that one geometric fact locally (the shore-tile SHAPE is this diorama's
## own rendering choice, not something WaterShader itself knows about) and
## hands it to WaterShader.edge_alpha_for_shore_distance -- the shader's own
## real fade curve -- for the actual opacity verdict, so this constant is
## checked against the SAME math the GPU draws with, not a separately
## eyeballed fraction.
func _worst_case_shore_distance(radius_fraction: float) -> float:
	var WaterShader = load("res://src/rendering/water_shader.gd")
	var raw := 0.5 * (1.0 - radius_fraction)
	return sqrt(maxf(raw, 0.0))


func test_fish_safe_radius_fraction_keeps_a_fishs_whole_body_fully_opaque():
	var WaterShader = load("res://src/rendering/water_shader.gd")
	var ProceduralFishSprite = load("res://src/rendering/procedural_fish_sprite.gd")
	var FishRenderer = load("res://src/rendering/fish_renderer.gd")

	# Centre-to-longest-edge, in world units -- see FISH_SAFE_RADIUS_
	# FRACTION's own doc comment on this exact derivation.
	var fish_half_extent: float = float(ProceduralFishSprite.WORLD_SIZE.x) * FishRenderer.FISH_WORLD_SCALE * 0.5
	var pond_radius: float = minf(footprint.x, footprint.y) * CharacterPreviewLayout.POND_RADIUS_FRACTION

	# The farthest a fish's own SPAWN can land (genuinely circular) or its
	# ongoing wander TARGET (also circular -- see CharacterStroll.random_
	# point_in_circle) is exactly FISH_SAFE_RADIUS_FRACTION of the pond's
	# radius; its drawn body then extends fish_half_extent further still.
	var worst_case_edge_fraction := CharacterPreviewLayout.FISH_SAFE_RADIUS_FRACTION + (fish_half_extent / pond_radius)
	var shore_dist := _worst_case_shore_distance(worst_case_edge_fraction)
	var alpha: float = WaterShader.edge_alpha_for_shore_distance(shore_dist)
	assert_eq(alpha, 1.0, "a fish's own far edge (fraction %.3f of the pond radius) reads at only %.3f opacity, not fully opaque water" % [worst_case_edge_fraction, alpha])


## Birds fly overhead, not on the ground -- unlike pebbles/trees/grass they
## don't need is_clear() obstacle avoidance, just to start somewhere inside
## the scene (reported live, alongside the long-grass request: "add ...
## birds"). Own field on Result, same as every other placement, so a reroll
## gives a different-looking flock deterministically (the design doc's
## Determinism pillar) using the layout's own isolated rng -- not the
## diorama's shared one, the exact coupling FISH_SAFE_RADIUS_FRACTION's own
## retuning just got bitten by (see character_preview_diorama.gd's
## _pick_new_fish_target).
func test_bird_positions_are_placed_inside_the_footprint():
	var layout := CharacterPreviewLayout.generate(6, footprint)
	assert_eq(layout.bird_positions.size(), CharacterPreviewLayout.BIRD_COUNT)
	var bounds := Rect2(Vector2.ZERO, footprint)
	for bird_position in layout.bird_positions:
		assert_true(bounds.has_point(bird_position), "bird position %s should start inside the footprint" % bird_position)


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


## The footprint's own grid (6x6 cells, GRASS_CLUMP_SPACING=16) is smaller
## than ONE noise lattice cell at TallGrass's own FIELD_NOISE_SCALE (0.12):
## every cell index 0..5, times 0.12, stays under 1.0, so the "noise" never
## crosses a lattice boundary and degenerates into a single smooth MONOTONIC
## gradient across the whole grid rather than genuine organic variation. The
## "kept" top-SEED_CHANCE share of a monotonic gradient is always whichever
## corner/edge the gradient happens to peak at for that seed -- STRUCTURALLY
## never the middle, for any seed (reported live, twice: "grass blades
## exist, but they should be more in the center", then again "still not in
## the center" after the first attempt -- picking the CLOSEST available
## clump to centre, see character_preview_diorama.gd's own
## _pick_long_grass_positions, can only pick from what's actually in the
## kept pool, and the pool itself excluded the centre no matter how it was
## ranked). GRASS_FIELD_NOISE_SCALE spans enough lattice cells across this
## grid that the "peak" can genuinely land anywhere per seed, while staying
## small enough that nearby cells still correlate (so the meadow still
## clumps -- see test_kept_grass_cells_clump_together, just below, which
## this constant must keep passing). Measured, not eyeballed: at the old
## 0.12, 0/100 sampled seeds ever placed a clump on any of the 4 cells
## nearest the footprint's own centre; at 0.5, 37/100 did, with the meadow's
## own clump-touch ratio only dropping from 0.97 to 0.92.
func test_grass_field_noise_scale_lets_the_centre_actually_receive_grass():
	var center := footprint * 0.5
	var near_center: Array[Vector2] = [Vector2(40, 40), Vector2(56, 40), Vector2(40, 56), Vector2(56, 56)]
	var seeds_with_center := 0
	var num_seeds := 100
	for seed_value in num_seeds:
		var result := CharacterPreviewLayout.generate(seed_value, footprint)
		for nc in near_center:
			if result.grass_positions.has(nc):
				seeds_with_center += 1
				break
	assert_gt(
		seeds_with_center, num_seeds / 10,
		"only %d/%d seeds ever placed grass near the footprint's own centre -- the noise field is still structurally excluding it" % [seeds_with_center, num_seeds]
	)


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
