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
	assert_eq(a.pond_half_size, b.pond_half_size)
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
## near dead-centre EVERY TIME read as a specimen posed in the middle of an
## empty room rather than a real feature of a believable little scene.
##
## The fix used to be to shove it against one of the four randomly-chosen
## edges, which the staged composition supersedes: a roll of "bottom" now
## parks the pond in the hero's own lane, and "left"/"right" hides it
## behind a framing tree (see _pond_center_in_the_middle_ground). What the
## report was actually about survives as this -- the pond really moves
## across the frame from seed to seed, rather than always landing in the
## same place.
func test_the_pond_is_not_parked_in_the_same_spot_every_time():
	# The SHIPPED footprint, not this file's square one: how much room the
	# pond has to drift across is what the staged composition leaves
	# between the two framing trunks, and at a square footprint the pond is
	# so large relative to the frame that almost none is left. This is a
	# claim about the scene the player sees.
	var footprint: Vector2 = CharacterPreviewDioramaForLayout.FOOTPRINT
	var seen: Array[Vector2] = []
	for seed_value in 40:
		seen.append(CharacterPreviewLayout.generate(seed_value, footprint).pond_center)
	var leftmost: float = seen[0].x
	var rightmost: float = seen[0].x
	for centre in seen:
		leftmost = minf(leftmost, centre.x)
		rightmost = maxf(rightmost, centre.x)
	var radius: float = CharacterPreviewLayout.generate(0, footprint).pond_radius
	assert_gt(
		rightmost - leftmost, radius,
		"across 40 seeds the pond only ever moved %.1f units -- less than its own radius" % (rightmost - leftmost)
	)


func test_tree_positions_are_within_the_footprint():
	var rect := Rect2(Vector2.ZERO, footprint)
	for seed_value in [1, 2, 3, 4, 5]:
		var layout := CharacterPreviewLayout.generate(seed_value, footprint)
		for tree_position in layout.tree_positions:
			assert_true(rect.has_point(tree_position), "seed %d, tree %s" % [seed_value, tree_position])


## No trunk may stand in open water. Checked against the pond's own
## ELLIPSE (pond_half_size) rather than the circular envelope at
## pond_radius -- the circle is a safe outer bound for placement, but what
## a viewer actually sees is the rectangle, so this is the shape that says
## whether a trunk is really in the water.
func test_no_trunk_stands_in_the_pond():
	for seed_value in 40:
		var layout := CharacterPreviewLayout.generate(seed_value, footprint)
		for tree_position in layout.tree_positions:
			var offset: Vector2 = tree_position - layout.pond_center
			var normalized := Vector2(
				offset.x / layout.pond_half_size.x, offset.y / layout.pond_half_size.y
			)
			assert_gt(
				normalized.length(), 1.0,
				"seed %d: tree at %s stands inside the pond at %s" % [seed_value, tree_position, layout.pond_center]
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


## Pebbles used to scatter on a perfect CIRCLE at pond_radius -- fine while
## the pond itself was one, but now that its own visual/placement shape is a
## rectangle (pond_half_size, narrower on one axis than pond_radius alone --
## see that field's own doc comment), a pebble placed by the old uniform
## formula in the SHORT axis direction would land well out in the open grass,
## nowhere near the water it's meant to sit at the edge of. Checked here by
## normalizing each pebble's offset against pond_half_size (an ellipse
## matching the rectangle's own aspect) rather than a bare distance against
## one scalar radius: every pebble's normalized length should land just
## outside 1.0 (the rim) by no more than the same PEBBLE_RIM_BAND, in EITHER
## axis, not just the long one.
func test_pebble_positions_sit_near_the_ponds_elliptical_rim():
	var layout := CharacterPreviewLayout.generate(3, footprint)
	assert_gt(layout.pebble_positions.size(), 0)
	for pebble_position in layout.pebble_positions:
		var offset: Vector2 = pebble_position - layout.pond_center
		var normalized := Vector2(offset.x / layout.pond_half_size.x, offset.y / layout.pond_half_size.y)
		var band_fraction: float = CharacterPreviewLayout.PEBBLE_RIM_BAND / layout.pond_radius
		assert_between(
			normalized.length(), 1.0, 1.0 + band_fraction + 0.01,
			"pebble at %s (normalized %s) should sit just outside the ELLIPTICAL rim, not a uniform circle" % [pebble_position, normalized]
		)


## Bigger, per direct live feedback ("the pond should be bigger"): the old
## 0.22 fraction (pond diameter ~42 of a 96-unit footprint) read as closer to
## a puddle than a pond next to a full-height tree/character. Test-pinned
## (CLAUDE.md: tuned values must be a tested/pinned constant, never just an
## eyeballed comment) rather than derived, since "how big should a decorative
## pond feel" has no real-world measurement to check it against -- same
## precedent as this file's own LONG_GRASS_GROWTH/BIRD_WANDER_RADIUS.
func test_pond_radius_fraction_is_pinned_at_its_bigger_value():
	assert_eq(CharacterPreviewLayout.POND_RADIUS_FRACTION, 0.3)


## "not square / circle but a rectangle" (reported live): pond_half_size is
## the rectangle's own long/short half-extents, replacing the single scalar
## pond_radius everywhere a SHAPE (not just a containment envelope) is
## needed -- pebble placement above, and CharacterPreviewDiorama's own tile
## grid next. The long axis is pinned to pond_radius exactly (never wider
## than the circular envelope every OTHER system -- is_clear, fish, trees --
## still safely avoids), so nothing already trusting pond_radius as an outer
## bound needs to change; only the short axis shrinks, by POND_ASPECT_RATIO,
## which is what actually makes it read as a rectangle rather than a circle.
func test_pond_half_size_is_a_rectangle_inscribed_in_the_circular_envelope():
	for seed_value in [1, 2, 3]:
		var layout := CharacterPreviewLayout.generate(seed_value, footprint)
		assert_almost_eq(layout.pond_half_size.x, layout.pond_radius, 0.001, "seed %d: long axis should reach exactly pond_radius" % seed_value)
		assert_almost_eq(
			layout.pond_half_size.y, layout.pond_radius / CharacterPreviewLayout.POND_ASPECT_RATIO, 0.001,
			"seed %d: short axis should be pond_radius scaled down by POND_ASPECT_RATIO" % seed_value
		)
		assert_gt(layout.pond_half_size.x, layout.pond_half_size.y, "seed %d: should be wider than tall, not square" % seed_value)


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
	# The four cells nearest the geometric centre are no longer candidates
	# for grass at all -- the staged pond sits there now (see
	# _pond_center_in_the_middle_ground), and a cell under water cannot
	# grow a clump under ANY noise scale. Counting them would measure where
	# the pond sits rather than what this constant does.
	#
	# So the same claim is made against the ground a viewer would call "the
	# middle" today: the CLEAR cell closest to the footprint's own centre.
	# At the old 0.12 noise scale the field's peak always landed in the
	# same lattice region and the middle was structurally excluded however
	# it was ranked; that is what this guards, and it is exactly as true of
	# the nearest clear cell as it was of the geometric centre.
	var centre := footprint * 0.5
	var seeds_with_center := 0
	var num_seeds := 100
	for seed_value in num_seeds:
		var result := CharacterPreviewLayout.generate(seed_value, footprint)
		var nearest = _clear_cell_nearest(result, footprint, centre)
		if nearest != null and result.grass_positions.has(nearest):
			seeds_with_center += 1
	assert_gt(
		seeds_with_center, num_seeds / 20,
		"only %d of %d seeds grew a clump on the clear ground nearest the centre -- the noise field is still structurally excluding it" % [seeds_with_center, num_seeds]
	)


## The grass-grid cell closest to `point` that this layout left clear, or
## null when the whole grid is occupied. Walks the grid exactly the way
## generate() itself does, so "a cell" means the same thing here as there.
func _clear_cell_nearest(result, fp: Vector2, point: Vector2):
	var best = null
	var best_distance := INF
	var columns := int(fp.x / CharacterPreviewLayout.GRASS_CLUMP_SPACING)
	var rows := int(fp.y / CharacterPreviewLayout.GRASS_CLUMP_SPACING)
	for cell_y in rows:
		for cell_x in columns:
			var candidate := Vector2(
				(float(cell_x) + 0.5) * CharacterPreviewLayout.GRASS_CLUMP_SPACING,
				(float(cell_y) + 0.5) * CharacterPreviewLayout.GRASS_CLUMP_SPACING
			)
			if not result.is_clear(candidate):
				continue
			var distance := candidate.distance_to(point)
			if distance < best_distance:
				best_distance = distance
				best = candidate
	return best


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


## A framing tree is DELIBERATELY allowed to overhang the frame now -- that
## is what makes it frame rather than merely stand there. What the original
## report was about ("three quarters of a tree outside the frame", a
## canopy floating with no trunk under it) survives as the real rule: the
## TRUNK, the thing that anchors a tree to the ground, is always well
## inside the frame, and the majority of the canopy comes with it.
func test_a_framing_tree_is_anchored_in_frame_even_though_it_overhangs_it():
	# * VISUAL_SCALE: whatever the sprite draws bigger than WORLD_SIZE by
	# (see that constant's own doc comment; currently 1.0, a no-op here).
	var half_width := float(ProceduralTreeSprite.WORLD_SIZE.x) * 0.5 * ProceduralTreeSprite.VISUAL_SCALE
	var rect := Rect2(Vector2.ZERO, footprint)
	for seed_value in 60:
		var result := CharacterPreviewLayout.generate(seed_value, footprint)
		for tree_position in result.tree_positions:
			assert_true(
				rect.has_point(tree_position),
				"seed %d: trunk %s outside the frame" % [seed_value, tree_position]
			)
			var inside_left: float = minf(tree_position.x + half_width, footprint.x)
			var inside_right: float = maxf(tree_position.x - half_width, 0.0)
			assert_gt(
				inside_left - inside_right, half_width,
				"seed %d: more than half of tree %s's canopy is outside the frame" % [seed_value, tree_position]
			)


## The inset band is derived from the tree art's own DRAWN size (world size
## times VISUAL_SCALE -- see that constant's own doc comment), never an
## eyeballed margin -- if the art or its visual scale ever change, the
## placement follows. tree_bounds is no longer what places the framing
## trees (see framing_tree_positions), but it is still the shared statement
## of "how much room a tree's own drawn body needs", which both the pond's
## trunk clearance and hero_bounds' own inset are modelled on.
func test_tree_bounds_are_derived_from_the_tree_arts_own_size():
	var bounds := CharacterPreviewLayout.tree_bounds(footprint)
	var drawn_width := float(ProceduralTreeSprite.WORLD_SIZE.x) * ProceduralTreeSprite.VISUAL_SCALE
	var drawn_height := float(ProceduralTreeSprite.WORLD_SIZE.y) * ProceduralTreeSprite.VISUAL_SCALE
	assert_eq(bounds.position, Vector2(drawn_width * 0.5, drawn_height))
	assert_eq(bounds.end, Vector2(footprint.x - drawn_width * 0.5, footprint.y))


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


# -- richer scene life: flowers, butterflies, worms, a boar ------------------
##
## Reported live: "Can you make it so that the character does more things and
## the scene's livelihood increases? We need flowers, butterflies, worms...
## the character should do random things like fight a boar; fish a fish..."
## Each new placement below follows the exact same shape already established
## for trees/pebbles/birds -- a COUNT constant and either is_clear-checked
## rejection sampling (ground life) or an unchecked footprint-wide point
## (things that fly, which don't need obstacle avoidance -- see BIRD_COUNT's
## own doc comment).

func test_flower_positions_are_placed_clear_of_the_pond_and_every_tree():
	var layout := CharacterPreviewLayout.generate(11, footprint)
	assert_eq(layout.flower_positions.size(), CharacterPreviewLayout.FLOWER_COUNT)
	for flower_position in layout.flower_positions:
		assert_true(layout.is_clear(flower_position), "flower at %s should be clear of the pond/trees" % flower_position)


func test_worm_positions_are_placed_clear_of_the_pond_and_every_tree():
	var layout := CharacterPreviewLayout.generate(11, footprint)
	assert_eq(layout.worm_positions.size(), CharacterPreviewLayout.WORM_COUNT)
	for worm_position in layout.worm_positions:
		assert_true(layout.is_clear(worm_position), "worm at %s should be clear of the pond/trees" % worm_position)


func test_butterfly_positions_are_placed_inside_the_footprint():
	var layout := CharacterPreviewLayout.generate(11, footprint)
	assert_eq(layout.butterfly_positions.size(), CharacterPreviewLayout.BUTTERFLY_COUNT)
	var bounds := Rect2(Vector2.ZERO, footprint)
	for butterfly_position in layout.butterfly_positions:
		assert_true(bounds.has_point(butterfly_position), "butterfly position %s should start inside the footprint" % butterfly_position)


## One ambient boar for the hero to (harmlessly) spar with -- see
## CharacterPreviewDiorama's own FIGHT action.
func test_boar_position_is_placed_clear_of_the_pond_and_every_tree():
	var layout := CharacterPreviewLayout.generate(11, footprint)
	assert_true(layout.is_clear(layout.boar_position), "boar at %s should be clear of the pond/trees" % layout.boar_position)


func test_flower_butterfly_worm_boar_positions_are_deterministic_for_the_same_seed():
	var a := CharacterPreviewLayout.generate(42, footprint)
	var b := CharacterPreviewLayout.generate(42, footprint)
	assert_eq(a.flower_positions, b.flower_positions)
	assert_eq(a.butterfly_positions, b.butterfly_positions)
	assert_eq(a.worm_positions, b.worm_positions)
	assert_eq(a.boar_position, b.boar_position)


# -- Staging: the hero is the subject of this panel ------------------------
#
# Reported live, with the three rendered seeds in tools/diorama_renders/
# that prompted it: "make the character way bigger and a nicer scenery".
# Measured rather than eyeballed -- probe_diorama_subject_sizes.gd renders
# each subject alone at a known zoom and reads its opaque bounding box back
# in world units: hero 10.0 x 19.8, ambient boar 30.0 x 46.5. The hero was
# the smallest thing in its own portrait.

const CharacterViewForLayout = preload("res://scenes/character_view.gd")
const CharacterPreviewDioramaForLayout = preload("res://src/rendering/character_preview_diorama.gd")


## The hero's drawn height is the rig's OWN feet-to-head-top span times the
## rig's OWN scale -- both already derived constants (CharacterView.SCALE is
## itself computed from a tree's height), so this is read out of the art
## rather than pinned to a number that a rig change would silently outdate.
## Matches the rendered measurement (19.8 world units, off a pixel bounding
## box that includes a row or two of antialiasing).
func test_hero_drawn_height_is_the_rigs_own_scaled_span():
	assert_almost_eq(
		CharacterPreviewLayout.hero_drawn_height(),
		-CharacterViewForLayout.HEAD_TOP_Y * CharacterViewForLayout.SCALE,
		0.001
	)
	assert_almost_eq(CharacterPreviewLayout.hero_drawn_height(), 19.8, 0.4)


## How much of the FRAME the hero fills reduces to a single ratio, and the
## camera drops out of it entirely: the view's zoom is
## view_width / footprint.x and its height is view_width * footprint.y /
## footprint.x (uniform zoom, see main_menu.gd's DIORAMA_VIEW_SIZE), so
## hero_height * zoom / view_height is just hero_height / footprint.y. That
## is why this is a property of the LAYOUT and not of the panel: widening
## the panel cannot make the hero read bigger, and only shrinking the
## footprint can.
func test_hero_screen_fraction_is_independent_of_the_panel_size():
	var tall := CharacterPreviewLayout.hero_screen_height_fraction(Vector2(192, 96))
	assert_almost_eq(tall, CharacterPreviewLayout.hero_drawn_height() / 96.0, 0.0001)
	# Double the footprint's width (and with it the panel's, at the same
	# uniform zoom) and the hero reads exactly as small as before.
	assert_almost_eq(CharacterPreviewLayout.hero_screen_height_fraction(Vector2(384, 96)), tall, 0.0001)
	# Halve its HEIGHT and the hero doubles.
	assert_almost_eq(CharacterPreviewLayout.hero_screen_height_fraction(Vector2(192, 48)), tall * 2.0, 0.0001)


## The framing bar itself. A decorative "how much of its own portrait should
## the subject fill" has no real-world value to derive it from, so it is
## test-pinned the same way POND_RADIUS_FRACTION above it is -- but what it
## is checked AGAINST is the real footprint the diorama ships, so shipping a
## footprint that shrinks the hero fails here.
func test_the_shipped_footprint_frames_the_hero_as_the_subject():
	var fraction := CharacterPreviewLayout.hero_screen_height_fraction(
		CharacterPreviewDioramaForLayout.FOOTPRINT
	)
	assert_gte(
		fraction,
		CharacterPreviewLayout.MIN_HERO_SCREEN_FRACTION,
		"the hero fills %.1f%% of its own portrait" % (fraction * 100.0)
	)


## The hero walks in a band across the FRONT of the scene -- between the
## camera and the pond, in front of the trees and the boar. That is what
## makes it read as the subject rather than as one more thing scattered
## through a meadow, and it is also what keeps it from wandering behind a
## tree canopy.
func test_the_hero_walks_in_a_band_across_the_front_of_the_scene():
	var fp := Vector2(96, 48)
	var hero := CharacterPreviewLayout.hero_bounds(fp)
	var back := CharacterPreviewLayout.back_band(fp)
	assert_gt(hero.position.y, back.end.y, "the hero's lane starts below the scenery band")
	assert_almost_eq(hero.end.y + CharacterPreviewLayout.hero_drawn_height() * 0.0, hero.end.y, 0.001)
	assert_lte(hero.end.y, fp.y, "and ends inside the footprint")


## No seed may ever put the hero half out of frame. Two of the three
## rendered seeds did exactly that (99 and 1234 -- the hero clipped by the
## left and right edges respectively), because the stroll picked targets
## across the WHOLE footprint while the hero is drawn ~10 units wide and
## ~20 tall around that point. The lane is inset by the hero's own drawn
## extent, read from the art -- the same rule tree_bounds already applies
## to a canopy.
func test_the_heros_whole_body_stays_inside_the_frame_anywhere_in_its_lane():
	var fp := Vector2(96, 48)
	var lane := CharacterPreviewLayout.hero_bounds(fp)
	var half_width := CharacterPreviewLayout.hero_drawn_width() * 0.5
	# EPSILON, not an exact compare: the lane's own width is derived by
	# subtracting the hero's drawn width from the footprint's, so adding
	# half of it back lands a float ULP or two past the edge.
	const EPSILON := 0.001
	assert_gte(lane.position.x - half_width, -EPSILON, "left edge")
	assert_lte(lane.end.x + half_width, fp.x + EPSILON, "right edge")
	# The rig is anchored at its FEET and drawn upward, so the top of its
	# head is hero_drawn_height above the highest point it can stand on.
	assert_gte(lane.position.y - CharacterPreviewLayout.hero_drawn_height(), 0.0, "head-room")
	assert_lte(lane.end.y, fp.y, "feet stay on the ground plane")


## Trees stand at the far LEFT and far RIGHT, one each, deliberately close
## enough to the side edges that part of each canopy sits outside the
## frame. That is the framing device the rendered seeds were missing: at
## the old random scatter the two trees piled into the middle of the panel
## and stood between the camera and the hero. A canopy filling an upper
## corner reads as the scene continuing past the panel instead.
func test_trees_frame_the_scene_from_its_two_side_edges():
	var fp := Vector2(96, 48)
	for seed_value in [1, 7, 42, 1234]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var trees := CharacterPreviewLayout.framing_tree_positions(fp, rng)
		assert_eq(trees.size(), CharacterPreviewLayout.TREE_COUNT, "seed %d" % seed_value)
		var xs := [trees[0].x, trees[1].x]
		xs.sort()
		assert_lt(xs[0], fp.x * 0.25, "one tree hugs the left edge (seed %d)" % seed_value)
		assert_gt(xs[1], fp.x * 0.75, "and one the right (seed %d)" % seed_value)


## Both are rooted in the scenery band at the back, never down in the lane
## the hero walks -- a tree trunk planted in the foreground would stand in
## front of the subject rather than behind it.
func test_framing_trees_root_in_the_back_of_the_scene():
	var fp := Vector2(96, 48)
	var lane := CharacterPreviewLayout.hero_bounds(fp)
	for seed_value in [1, 7, 42, 1234]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		for tree in CharacterPreviewLayout.framing_tree_positions(fp, rng):
			assert_lt(tree.y, lane.position.y, "seed %d: %s" % [seed_value, tree])


## Each canopy really does overhang its own side edge -- the property that
## makes it read as framing rather than as two trees that happen to be far
## apart. Measured against the tree ART's own drawn width, never a margin
## picked by eye.
func test_each_framing_canopy_overhangs_its_own_side_edge():
	var fp := Vector2(96, 48)
	var half_canopy := (
		float(ProceduralTreeSprite.WORLD_SIZE.x) * ProceduralTreeSprite.VISUAL_SCALE * 0.5
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var trees := CharacterPreviewLayout.framing_tree_positions(fp, rng)
	var xs := [trees[0].x, trees[1].x]
	xs.sort()
	assert_lt(xs[0] - half_canopy, 0.0, "the left canopy reaches past the left edge")
	assert_gt(xs[1] + half_canopy, fp.x, "the right canopy reaches past the right edge")


## The ambient boar is scenery too: it stands behind the hero, in the same
## band as the trees. It rendered dead centre and in front of the pond
## before, where at 30 x 46 world units it was simply the biggest thing in
## the picture.
func test_the_ambient_boar_stands_in_the_scenery_band():
	var fp := Vector2(96, 48)
	var back := CharacterPreviewLayout.back_band(fp)
	for seed_value in 40:
		var stand := CharacterPreviewLayout.generate(seed_value, fp).boar_position
		assert_true(back.has_point(stand), "seed %d put the boar at %s" % [seed_value, stand])


## ...and it does not stand in either of the framing trees.
## ...and out of the pond, and out of both trunks -- the same is_clear
## predicate every other placement in the layout answers to. A boar
## standing in open water is not scenery, it is a bug.
func test_the_ambient_boar_stands_on_clear_ground():
	var fp := Vector2(96, 48)
	for seed_value in 40:
		var layout := CharacterPreviewLayout.generate(seed_value, fp)
		assert_true(
			layout.is_clear(layout.boar_position),
			"seed %d stood the boar at %s, in the pond at %s or a trunk" % [
				seed_value, layout.boar_position, layout.pond_center
			]
		)


## The whole staging, end to end, on the real generated layout: scenery at
## the back, water in the middle, the hero's lane at the front.
func test_generate_stages_the_scene_in_depth():
	var fp := Vector2(96, 48)
	var lane := CharacterPreviewLayout.hero_bounds(fp)
	for seed_value in [1, 7, 42, 99, 1234, 4021]:
		var result := CharacterPreviewLayout.generate(seed_value, fp)
		assert_lt(
			result.pond_center.y, lane.position.y,
			"seed %d: the pond should sit behind the hero's lane, not in it" % seed_value
		)
		for tree in result.tree_positions:
			assert_lt(tree.y, lane.position.y, "seed %d: tree in the hero's lane" % seed_value)
		assert_lt(result.boar_position.y, lane.position.y, "seed %d: boar in the hero's lane" % seed_value)
