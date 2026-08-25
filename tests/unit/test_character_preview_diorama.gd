extends GutTest

const CharacterPreviewDioramaScript = preload("res://src/rendering/character_preview_diorama.gd")
const CharacterPreviewLayout = preload("res://src/rendering/character_preview_layout.gd")
const CharacterActionPicker = preload("res://src/rendering/character_action_picker.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")
## The real world's own tile size -- the diorama's ground has to agree with
## it, not restate a number of its own (see the ground tests below).
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var diorama: Node2D


func before_each():
	diorama = CharacterPreviewDioramaScript.new()
	add_child(diorama)
	diorama.build(42)


func after_each():
	remove_child(diorama)
	diorama.free()


func test_build_creates_a_character_view():
	assert_not_null(diorama.character_view)
	assert_true(diorama.character_view.is_inside_tree())


func test_build_creates_the_expected_number_of_trees_and_pebbles():
	assert_eq(diorama.tree_nodes.size(), CharacterPreviewLayout.TREE_COUNT)
	assert_eq(diorama.pebble_nodes.size(), CharacterPreviewLayout.PEBBLE_COUNT)


## Fish positions themselves are already pinned inside the pond by
## test_character_preview_layout.gd's own test_fish_positions_stay_inside_
## the_pond -- this just confirms the diorama actually MATERIALIZES the
## fish that layout decided on, as real nodes with real art (reported
## live: "there are no fish in the pond").
func test_build_creates_the_expected_number_of_fish():
	assert_eq(diorama.fish_nodes.size(), CharacterPreviewLayout.FISH_COUNT)
	for fish in diorama.fish_nodes:
		assert_not_null(fish.texture)
		assert_true(fish.is_inside_tree())


## Reported live, alongside the long-grass request: "add ... birds" -- a few
## songbirds circling overhead, purely decorative ambience the same way the
## fish are (see AmbientFlyerRenderer.build_bird's own doc comment on why no
## scent/worm/seed/fruit world is wired for them here).
func test_build_creates_a_few_birds():
	assert_gt(diorama.bird_nodes.size(), 0)
	for bird in diorama.bird_nodes:
		assert_not_null(bird.texture)
		assert_true(bird.is_inside_tree())


## Not a strict containment guarantee the way the pond's fish need (a bird
## flying briefly out of frame and back is ordinary, unlike a fish that must
## never leave water) -- just a sanity check against a gross placement bug,
## generous enough that the real world's own BIRD_RADIUS wander never trips
## it by itself.
func test_birds_start_reasonably_within_the_footprint():
	var AmbientFlyerRenderer = load("res://src/rendering/ambient_flyer_renderer.gd")
	var generous := Rect2(Vector2.ZERO, CharacterPreviewDioramaScript.FOOTPRINT).grow(AmbientFlyerRenderer.BIRD_RADIUS)
	for bird in diorama.bird_nodes:
		assert_true(generous.has_point(bird.position), "bird spawned wildly outside the diorama: %s" % bird.position)


## The pond is a Node2D grouping several tile sprites now (see the grid
## tests below), not a single Sprite2D directly on the diorama root -- see
## _build_pond's own doc comment on why.
func test_build_creates_a_pond_container_with_at_least_one_tile():
	var pond: Node2D = diorama.get_node("Pond")
	assert_not_null(pond)
	var found := false
	for child in pond.get_children():
		if child is Sprite2D and child.texture != null:
			found = true
	assert_true(found)


# -- the pond is a real multi-tile grid, not one stretched texture -- reused
# -- from the real world's own water rendering (ProceduralShoreDistanceSprite
# -- generate_deep_water_image for tiles with no land neighbour,
# -- generate_image(land_directions) only for tiles that actually touch the
# -- pond's own rim), instead of one single tile with ALL 4 directions
# -- active stretched over the whole pond -- which faded from EVERY side at
# -- once regardless of how big the pond was, so the deep, fully-opaque
# -- "obviously water" core barely existed (reported live: "it's supposed
# -- to fill the entire rectangle").

func _pond_tiles() -> Array:
	var pond: Node2D = diorama.get_node("Pond")
	return pond.get_children()


func test_pond_tiles_cover_a_grid_at_the_real_worlds_own_tile_size():
	var tiles := _pond_tiles()
	assert_gt(tiles.size(), 1, "a single stretched tile is exactly the bug being fixed")
	for tile in tiles:
		assert_almost_eq(tile.scale.x * tile.texture.get_width(), CharacterPreviewDioramaScript.POND_TILE_WORLD_SIZE, 0.01)
		assert_almost_eq(tile.scale.y * tile.texture.get_height(), CharacterPreviewDioramaScript.POND_TILE_WORLD_SIZE, 0.01)


## A tile with no land-facing side at all must be the real world's own
## generate_deep_water_image() -- uniformly Color(1,1,1,1), never faded.
func test_the_grids_own_centre_tile_is_fully_opaque_deep_water():
	var tiles := _pond_tiles()
	var center: Vector2 = diorama.get("_layout").pond_center
	var closest = null
	var closest_distance := INF
	for tile in tiles:
		var d: float = tile.position.distance_to(center)
		if d < closest_distance:
			closest_distance = d
			closest = tile
	var image: Image = closest.texture.get_image()
	assert_eq(image.get_pixel(image.get_width() / 2, image.get_height() / 2), Color(1, 1, 1, 1))


## A tile at the grid's own rim (its position is the furthest from centre)
## must still show the real shore-distance fade -- proof the fix is a
## GRID, not just "make everything deep water".
func test_a_rim_tile_still_shows_the_shore_distance_fade():
	var tiles := _pond_tiles()
	var center: Vector2 = diorama.get("_layout").pond_center
	var farthest = null
	var farthest_distance := 0.0
	for tile in tiles:
		var d: float = tile.position.distance_to(center)
		if d > farthest_distance:
			farthest_distance = d
			farthest = tile
	var image: Image = farthest.texture.get_image()
	assert_ne(image.get_pixel(0, 0), Color(1, 1, 1, 1), "the rim tile's own corner should read as faded, not full deep water")


# -- the ground the whole scene stands on (reported live: the grass, pond,
# pebbles and trees floated on the frame's own near-black panel background,
# and the pond -- whose shore fade is pure ALPHA -- read as a hard-edged
# blue rectangle because there was nothing behind it to fade into) ---------

## One diorama ground tile covers exactly one REAL world tile, read from
## TerrainRenderer rather than restated, so the diorama can never disagree
## with the world about how much ground a tile is -- the same rule the grass
## cards already follow (IllustratedGrassPatch.WORLD_SIZE == TILE_SIZE).
func test_a_ground_tile_covers_exactly_one_real_world_tile():
	assert_eq(
		CharacterPreviewDioramaScript.GROUND_TILE_WORLD_SIZE,
		float(TerrainRenderer.TILE_SIZE)
	)


## The camera frames exactly Rect2(0, 0, FOOTPRINT), so anything short of
## full coverage shows the frame's own near-black panel through the gap.
func test_build_lays_ground_tiles_across_the_whole_footprint():
	assert_gt(diorama.ground_tiles.size(), 0, "the diorama stands on nothing at all")
	var tile_size := Vector2.ONE * CharacterPreviewDioramaScript.GROUND_TILE_WORLD_SIZE
	var covered := Rect2(diorama.ground_tiles[0].position, tile_size)
	for tile in diorama.ground_tiles:
		covered = covered.merge(Rect2(tile.position, tile_size))
	assert_true(
		covered.encloses(Rect2(Vector2.ZERO, CharacterPreviewDioramaScript.FOOTPRINT)),
		"ground covers %s, needs to cover %s" % [covered, CharacterPreviewDioramaScript.FOOTPRINT]
	)


## Real ground art, not a flat fill -- the diorama is a corner of the real
## world (the design doc's first pillar), so it stands on the very art
## TerrainRenderer lays down for grassland.
func test_ground_tiles_carry_real_terrain_art():
	for tile in diorama.ground_tiles:
		assert_not_null(tile.texture, "a ground tile with no texture is a hole in the world")


## The pond is now a Node2D grouping several tile sprites (see the grid
## tests further down) -- each tile carries its own z_index directly, the
## same "every z-sensitive node sets it explicitly" convention the grass/
## ground already follow, rather than relying on container/relative
## inheritance.
func test_ground_draws_beneath_the_pond_and_the_grass():
	var pond: Node2D = diorama.get_node("Pond")
	var grass: MultiMeshInstance2D = diorama.get_node("Grass")
	for tile in diorama.ground_tiles:
		for pond_tile in pond.get_children():
			assert_lt(tile.z_index, pond_tile.z_index, "ground must draw under every pond tile")
		assert_lt(tile.z_index, grass.z_index, "ground must draw under the grass")


## build() frees every previous child immediately (see its own doc comment);
## the ground array has to be reset with the others or it holds freed nodes.
func test_rebuilding_replaces_the_ground_rather_than_stacking_it():
	var first_count: int = diorama.ground_tiles.size()
	diorama.build(99)
	assert_eq(diorama.ground_tiles.size(), first_count)
	for tile in diorama.ground_tiles:
		assert_true(is_instance_valid(tile), "a freed ground tile is still in the array")


# -- fish now swim through FishMarker's own REAL _process (the same path
# -- every other in-game fish uses -- shore-avoidance, TURN_RATE-smoothed
# -- heading, tail-wag speed bursts, ripples), not the diorama's own
# -- earlier point-to-point movement or FishMarker's "no world" standalone
# -- fallback (which skips all of that). Reported live, after the earlier
# -- CreatureWander-based fix still fell short: "fish still don't move
# -- natural like ingame also no ripples". The diorama itself is the
# -- duck-typed "world" FishMarker.setup expects (biome_at_global,
# -- record_water_disturbance) -- see those two methods' own doc comments.

func test_biome_at_global_reads_ocean_inside_the_pond_and_grassland_outside():
	var pond_tile := Vector2i(
		int(diorama.get("_layout").pond_center.x / CharacterPreviewDioramaScript.POND_TILE_WORLD_SIZE),
		int(diorama.get("_layout").pond_center.y / CharacterPreviewDioramaScript.POND_TILE_WORLD_SIZE)
	)
	assert_eq(diorama.biome_at_global(pond_tile.x, pond_tile.y), "ocean")
	assert_eq(diorama.biome_at_global(-100, -100), CharacterPreviewDioramaScript.GROUND_BIOME)


func test_record_water_disturbance_forwards_to_the_ponds_own_water_shader():
	var pos: Vector2 = diorama.get("_layout").pond_center
	diorama.record_water_disturbance(pos)
	assert_eq(diorama.get("_water_shader")._disturbance_positions.size(), 1)
	assert_eq(diorama.get("_water_shader")._disturbance_positions[0], pos)


## Fish are no longer driven by the diorama's own _process at all -- their
## OWN _process, called directly here exactly the way the real SceneTree
## calls it every frame in a live game (see test_fish_marker.gd's own
## identical convention), is what moves them now.
func test_fish_move_through_their_own_real_process():
	var fish: Node2D = diorama.fish_nodes[0]
	var start := fish.position
	for i in 50:
		fish._process(0.1)
	assert_ne(fish.position, start)


func test_fish_stay_within_the_ponds_real_bounds_via_shore_avoidance():
	var bounds: Rect2 = diorama.get("_pond_bounds").grow(1.0)
	for i in 200:
		diorama._process(0.2)
		for fish in diorama.fish_nodes:
			fish._process(0.2)
			assert_true(
				bounds.has_point(fish.position),
				"fish left the pond's own real bounds: %s not in %s" % [fish.position, bounds]
			)


## The real shore-avoidance path emits ripples via record_water_disturbance
## once a fish has genuinely moved -- confirms the diorama's own duck-typed
## world is actually WIRED to a live fish, not just present on the diorama
## (reported live: "no ripples").
func test_fish_swimming_eventually_records_a_water_disturbance():
	var fish: Node2D = diorama.fish_nodes[0]
	for i in 300:
		diorama._process(0.2)
		fish._process(0.2)
	assert_gt(diorama.get("_water_shader")._disturbance_positions.size(), 0)


func test_apply_appearance_dresses_the_live_character_view():
	var appearance := HeroAppearance.new().appearance_for("mage", 5)
	diorama.apply_appearance(appearance)
	# A real, non-default texture on the body confirms apply_appearance
	# actually reached the live CharacterView, not just accepted the call.
	assert_not_null(diorama.character_view.get_node("Body").texture)


func test_character_strolls_over_time():
	var start: Vector2 = diorama.character_view.position
	for i in 60:
		diorama._process(0.1)
	var moved: Vector2 = diorama.character_view.position
	assert_ne(start, moved)


func test_character_stays_within_the_footprint_while_strolling():
	var rect := Rect2(Vector2.ZERO, CharacterPreviewDioramaScript.FOOTPRINT).grow(1.0)
	for i in 200:
		diorama._process(0.2)
		assert_true(
			rect.has_point(diorama.character_view.position),
			"stroll left the footprint at step %d: %s" % [i, diorama.character_view.position]
		)


# -- a few clumps render taller than the rest (reported live: "add a few
# -- long grass blades") -- CharacterPreviewDiorama._pick_long_grass_
# -- positions is the pure, static selection logic (no Godot nodes needed to
# -- test it), checked directly against CharacterPreviewLayout's own grass
# -- scatter for a real seed.

func test_pick_long_grass_positions_picks_a_real_subset():
	var positions: Array[Vector2] = diorama.get("_layout").grass_positions
	var long_positions: Array[Vector2] = CharacterPreviewDioramaScript._pick_long_grass_positions(positions)
	assert_gt(long_positions.size(), 0, "at least one clump should be picked as long")
	assert_lte(
		long_positions.size(),
		CharacterPreviewDioramaScript.LONG_GRASS_MAX_COUNT,
		"'a few' must stay bounded regardless of how much grass a seed has"
	)
	for picked in long_positions:
		assert_true(positions.has(picked), "a picked position must be a real grass clump, not invented")


func test_pick_long_grass_positions_is_deterministic_for_the_same_input():
	var positions: Array[Vector2] = diorama.get("_layout").grass_positions
	var first := CharacterPreviewDioramaScript._pick_long_grass_positions(positions)
	var second := CharacterPreviewDioramaScript._pick_long_grass_positions(positions)
	assert_eq(first, second)


func test_pick_long_grass_positions_never_exceeds_the_available_clumps():
	var few: Array[Vector2] = [Vector2(1, 1)]
	var picked := CharacterPreviewDioramaScript._pick_long_grass_positions(few)
	assert_eq(picked.size(), 1)


## Picked purely by hash rank the first time round, the long clumps could
## land anywhere the ordinary scatter did -- including right at a corner,
## easy to miss entirely (reported live: "grass blades exist, but they
## should be more in the center"). Ranked by distance to the footprint's own
## centre instead, so the accent actually reads as part of the scene most
## people are looking at, not a coin-flip. More candidates than LONG_GRASS_
## MAX_COUNT on purpose -- with exactly MAX_COUNT candidates every one gets
## picked regardless of ranking, which would prove nothing.
func test_pick_long_grass_positions_prefers_positions_near_the_footprint_centre():
	var center: Vector2 = CharacterPreviewDioramaScript.FOOTPRINT * 0.5
	var near_center := center + Vector2(3, -2)
	var far_corners: Array[Vector2] = [
		Vector2(2, 2),
		Vector2(CharacterPreviewDioramaScript.FOOTPRINT.x - 2, 2),
		Vector2(2, CharacterPreviewDioramaScript.FOOTPRINT.y - 2),
		Vector2(CharacterPreviewDioramaScript.FOOTPRINT.x - 2, CharacterPreviewDioramaScript.FOOTPRINT.y - 2),
	]
	var positions: Array[Vector2] = [near_center]
	positions.append_array(far_corners)
	var picked := CharacterPreviewDioramaScript._pick_long_grass_positions(positions)
	assert_true(picked.has(near_center), "the clump nearest the centre should be picked ahead of every far corner")


func test_rebuilding_frees_the_previous_generation_of_nodes():
	var first_character_view: Node2D = diorama.character_view
	diorama.build(99)
	assert_ne(diorama.character_view, first_character_view)


## build() called on a diorama that is NOT YET inside a live scene tree
## (this file's own before_each always adds it first -- every OTHER test
## here already covers that path) -- the real crash this reproduces:
## CharacterView's @onready _tool_slot stays null until its own _ready
## fires, which add_child only fires SYNCHRONOUSLY when its ancestor chain
## is already live. Reported as a real crash inside test_main_menu.gd's
## own suite once this diorama started equipping a weapon: "Invalid
## assignment of property or key 'texture' ... on a base object of type
## 'Nil'".
func test_build_before_being_added_to_the_tree_still_equips_the_weapon_once_ready():
	var detached := CharacterPreviewDioramaScript.new()
	detached.build(7)  # must not crash
	add_child(detached)
	await get_tree().process_frame
	assert_not_null(detached.character_view.tool_slot_texture())
	remove_child(detached)
	detached.free()


# -- random ambient actions (reported live: "make it so that the char does
# random actions like swinging the sword or fishing or just staying still
# then wandering") -- each action forced directly via _enter_action rather
# than waiting on the real random picker, so these are deterministic, not
# flaky.

func test_build_starts_with_a_real_action_and_a_positive_duration():
	assert_true(CharacterActionPicker.WEIGHTS.has(diorama.get("_current_action")))
	assert_gt(diorama.get("_action_time_remaining"), 0.0)


func test_character_holds_still_during_idle():
	diorama._enter_action(CharacterActionPicker.Action.IDLE)
	diorama.set("_action_time_remaining", 10.0)
	var start: Vector2 = diorama.character_view.position
	diorama._process(0.5)
	assert_eq(diorama.character_view.position, start)
	assert_eq(diorama.character_view.movement_state, diorama.character_view.MovementState.IDLE)


func test_character_swings_the_weapon_during_swing():
	diorama._enter_action(CharacterActionPicker.Action.SWING)
	# play_attack_swing was already triggered once, inside _enter_action --
	# it sets up the swing's own state (duration/facing), but the actual
	# tool-slot ROTATION is applied by CharacterView's own _process, same
	# as any other CharacterView animation -- one real tick of that (not
	# the diorama's own _process, which doesn't drive this) is what
	# actually moves the swing partway through its arc.
	diorama.character_view._process(0.05)
	assert_gt(diorama.character_view.tool_slot_rotation(), 0.0)


## The fishing spot sits just INSIDE the pond's own rim now (see
## _compute_fishing_spot's own doc comment: a shallow wade, not a shore-
## side stand, so the water-tinting submersion shader actually has
## something to show) -- once arrived, the hero should be in SWIMMING
## state, not IDLE, since it is genuinely standing in the water.
func test_character_walks_to_the_fishing_spot_during_fish_then_swims_in_place():
	var fishing_spot: Vector2 = diorama.get("_fishing_spot")
	diorama.character_view.position = fishing_spot + Vector2(30, 0)  # start well away from it
	diorama._enter_action(CharacterActionPicker.Action.FISH)
	# Comfortably longer than the loop below (300 * 0.1 = 30s) -- NOT just
	# "long enough to arrive". The two used to be the same 30.0, so the
	# action timer could expire on the loop's own last step and hand off to
	# a freshly-rolled next action (see CharacterActionPicker.pick_next)
	# before the assertions below ever ran, occasionally moving the hero
	# again right at the finish line. That coincidence broke for real once
	# _pick_new_fish_target started drawing from the SAME shared _rng at a
	# different cadence (a smaller, circular roam area arrives and re-targets
	# more often) -- a shared-RNG coupling between the fish and the hero's
	# own action timer that has nothing to do with what THIS test checks, so
	# it's the test's own timing that's fixed here, not the coupling itself.
	diorama.set("_action_time_remaining", 1000.0)
	for i in 300:
		diorama._process(0.1)
	# Within CharacterStroll.ARRIVAL_RADIUS (2.0), not exactly on top of it
	# -- "arrived" stops advancing once inside that radius, same as the
	# hero's own ordinary wander target.
	assert_true(diorama.character_view.position.distance_to(fishing_spot) <= 2.5)
	assert_eq(diorama.character_view.movement_state, diorama.character_view.MovementState.SWIMMING)
	# Genuinely inside the pond, not just close to its centre -- the whole
	# point of moving the spot here in the first place.
	assert_lt(diorama.character_view.position.distance_to(diorama.get("_layout").pond_center), diorama.get("_layout").pond_radius)
