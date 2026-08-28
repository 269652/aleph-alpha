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


# -- richer scene life: flowers, butterflies, worms, a boar ------------------
##
## Reported live: "We need flowers, butterflies, worms..." Each follows the
## same "reuse the real rendering, no gameplay behind it" contract the
## diorama's fish/birds already have -- ProceduralFlowerSprite/
## ProceduralWormSprite (thin Sprite2D wrappers, the same pattern
## EarthChunkManager._sync_flower_sprites/_sync_worm_sprites already use) and
## AmbientFlyerRenderer.build_flyer (already a ready-made non-bird wrapper,
## no new rendering code at all).

func test_build_creates_the_expected_number_of_flowers():
	assert_eq(diorama.flower_nodes.size(), CharacterPreviewLayout.FLOWER_COUNT)
	for flower in diorama.flower_nodes:
		assert_not_null(flower.texture)
		assert_true(flower.is_inside_tree())


func test_build_creates_the_expected_number_of_worms():
	assert_eq(diorama.worm_nodes.size(), CharacterPreviewLayout.WORM_COUNT)
	for worm in diorama.worm_nodes:
		assert_not_null(worm.texture)
		assert_true(worm.is_inside_tree())


func test_build_creates_the_expected_number_of_butterflies():
	assert_eq(diorama.butterfly_nodes.size(), CharacterPreviewLayout.BUTTERFLY_COUNT)
	for butterfly in diorama.butterfly_nodes:
		assert_true(butterfly.is_inside_tree())


func test_build_creates_one_ambient_boar():
	assert_not_null(diorama.boar_node)
	assert_true(diorama.boar_node.is_inside_tree())
	assert_eq(diorama.boar_node.position, diorama.get("_layout").boar_position)


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


## "not square / circle but a rectangle" (reported live): the grid's own
## column/row counts now come from CharacterPreviewLayout.pond_half_size's
## two DIFFERENT axes (see _build_pond), not a single pond_radius doubled
## into a square. Checked on the live diorama's own default seed (42),
## not a hand-picked one, since a real regression here should show up on
## whatever seed the fixture already builds.
func test_pond_grid_is_wider_than_it_is_tall():
	assert_gt(
		CharacterPreviewDioramaScript._pond_columns_for(diorama.get("_layout")),
		CharacterPreviewDioramaScript._pond_rows_for(diorama.get("_layout"))
	)


## No lake/organic-blob generator exists anywhere in this codebase to reuse
## (the real world's own water silhouette comes from a bundled Earth
## elevation DEM lookup, not synthesized shape -- see EarthChunkGenerator/
## BiomeClassifier -- which has nothing to look up for a standalone diorama
## pond); built from the SAME PixelNoise primitive CharacterPreviewLayout
## already uses for its own grass-clump scatter. Pure and static, no Godot
## nodes, so it's directly testable without a live diorama -- same split
## this file already keeps for _pick_long_grass_positions.
##
## The always-kept core (POND_EROSION_SAFE_FRACTION) must never itself be
## eroded, for any seed -- a pond that could vanish, or fray down to
## disconnected puddles, isn't a pond.
func test_generate_pond_cells_always_keeps_a_solid_core():
	for seed_value in [1, 2, 3, 4, 5]:
		var kept: Dictionary = CharacterPreviewDioramaScript._generate_pond_cells(6, 4, seed_value)
		assert_true(kept.has(Vector2i(3, 2)), "seed %d: the centre-most cell should always be kept" % seed_value)


func test_generate_pond_cells_is_deterministic_for_the_same_seed():
	var a: Dictionary = CharacterPreviewDioramaScript._generate_pond_cells(6, 4, 7)
	var b: Dictionary = CharacterPreviewDioramaScript._generate_pond_cells(6, 4, 7)
	assert_eq(a.keys(), b.keys())


## The actual "organic shape" property the user asked for: at least one
## outer-ring cell must be excluded for at least one of a handful of seeds --
## proof the grid ISN'T just re-deriving a perfect, crisp rectangle (which a
## fixed row==0-style edge test, the OLD land_directions logic, always drew
## regardless of seed).
func test_generate_pond_cells_erodes_at_least_one_outer_cell_for_some_seed():
	var columns := 6
	var rows := 4
	var any_erosion := false
	for seed_value in range(20):
		var kept: Dictionary = CharacterPreviewDioramaScript._generate_pond_cells(columns, rows, seed_value)
		for row in rows:
			for column in columns:
				if not kept.has(Vector2i(column, row)):
					any_erosion = true
	assert_true(any_erosion, "no seed out of 20 ever eroded a single outer cell -- the shape is still a crisp rectangle")


## The other half of the same organic-shape property: it must NOT erode so
## much that it stops reading as a rectangle at all -- most of the grid
## should still normally be kept.
func test_generate_pond_cells_keeps_most_of_the_grid_on_average():
	var columns := 6
	var rows := 4
	var total_kept := 0
	var num_seeds := 20
	for seed_value in range(num_seeds):
		var kept: Dictionary = CharacterPreviewDioramaScript._generate_pond_cells(columns, rows, seed_value)
		total_kept += kept.size()
	var average_fraction := float(total_kept) / float(num_seeds * columns * rows)
	assert_gt(average_fraction, 0.6, "average kept fraction %f -- eroding away too much of the rectangle" % average_fraction)


## land_directions has to reflect the SHAPE actually kept, not just "is this
## cell on the grid's own outer edge" (the old logic, correct only because
## every cell used to be kept) -- a cell can now be interior to the GRID but
## still border an eroded neighbour, and needs the shore fade facing that
## neighbour too.
func test_land_directions_for_cell_includes_an_eroded_interior_neighbor():
	var kept := {Vector2i(1, 1): true, Vector2i(2, 1): true, Vector2i(1, 2): true}
	# (2, 2) deliberately absent -- an "eroded" interior neighbour of (1, 2)
	# and (2, 1), even though neither sits on the 3x3 grid's own outer rim.
	var directions: Array[Vector2i] = CharacterPreviewDioramaScript._land_directions_for_cell(Vector2i(1, 2), kept, 3, 3)
	assert_true(directions.has(Vector2i(1, 0)), "the cell east of (1,2) is missing from `kept` and should read as land")


func test_land_directions_for_cell_is_empty_for_a_fully_surrounded_cell():
	var kept := {}
	for row in 3:
		for column in 3:
			kept[Vector2i(column, row)] = true
	var directions: Array[Vector2i] = CharacterPreviewDioramaScript._land_directions_for_cell(Vector2i(1, 1), kept, 3, 3)
	assert_eq(directions.size(), 0, "the centre of a fully-kept 3x3 grid touches no land at all")


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


## Reported live: "the fishes don't speed boost and they don't swim
## naturally like in game." Measured first, not guessed: the boost
## mechanism itself was already fully intact (glide/flap speeds matched
## FISH_SWIM_SPEED and FISH_SWIM_SPEED*FLAP_SPEED_MULTIPLIER exactly, and a
## burst genuinely fired several times within a realistic 30s window at the
## new, correctly-rarer interval -- see the eleventh live pass in
## docs/progress.md). What a live dump of real fish/pond numbers actually
## showed: at FISH_SWIM_SPEED=4.0, a fish takes 14.4s just to cross the
## POND's own long axis, and the pond itself is now considerably bigger
## than when 4.0 was chosen (see FOOTPRINT's own doc comment) -- at the
## diorama's own actual on-screen scale that reads as barely moving at all,
## boost included, however correctly the mechanism itself was firing.
## Checked here as a real property -- how long a fish takes to cross its
## OWN configured wander diameter (not the whole pond, which it never tries
## to fully cross) -- rather than the bare constant, so a future pond-size
## or wander-fraction change is automatically re-measured against this same
## "reads as swimming, not creeping" bar instead of silently drifting stale
## again.
func test_fish_swim_speed_crosses_its_own_wander_circle_briskly():
	var layout := CharacterPreviewLayout.generate(42, CharacterPreviewDioramaScript.FOOTPRINT)
	var wander_diameter := 2.0 * layout.pond_radius * CharacterPreviewLayout.FISH_SAFE_RADIUS_FRACTION
	var glide_crossing_time := wander_diameter / CharacterPreviewDioramaScript.FISH_SWIM_SPEED
	assert_lt(
		glide_crossing_time, 3.0,
		"a fish takes %.1fs to glide across its own roam circle -- too slow to read as swimming" % glide_crossing_time
	)


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
## Checked as a RISING EDGE across the whole loop, not "is the buffer non-
## empty at the very end" -- disturbances decay out of _disturbance_positions
## after WaterShader.RIPPLE_LIFETIME (2.2s -- see advance_disturbances), far
## shorter than a fish's own gap between ripple bursts once that gap was
## widened to genuinely read as occasional rather than continuous (reported
## live: "the fish still produce ripples all the time" -- see FishMarker.
## RIPPLE_INTERVAL_MIN's own doc comment). A final-count-only check happened
## to keep passing at the OLD, much shorter interval purely by luck (a
## recent, undecayed ripple was almost always sitting in the buffer at
## whatever moment the check ran) and would otherwise fail here even once a
## burst genuinely fired mid-loop, exactly the same false-negative already
## documented on the hero's own identical tests just below.
func test_fish_swimming_eventually_records_a_water_disturbance():
	var fish: Node2D = diorama.fish_nodes[0]
	var previous_count := 0
	var ever_recorded := false
	for i in 300:
		diorama._process(0.2)
		fish._process(0.2)
		var current_count: int = diorama.get("_water_shader")._disturbance_positions.size()
		if current_count > previous_count:
			ever_recorded = true
		previous_count = current_count
	assert_true(ever_recorded, "no water disturbance was ever recorded while the fish swam")


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


## FIGHT (reported live: "the character should do random things like fight a
## boar"). CreatureMarker's own attack pose is gated behind real AI/
## perception with no public trigger (confirmed: no callable "play the
## attack pose now" method exists, unlike CharacterView.play_attack_swing --
## rigging a fake threat to trip the real AI for one scripted beat would be
## fragile), so the boar itself stays a passive, harmlessly ambient presence
## -- exactly the same "reuse the real rendering, no gameplay behind it"
## contract the diorama's fish/birds already have. What DOES reuse real,
## already-triggerable behavior: the hero walks to sparring range and
## genuinely swings, the same play_attack_swing SWING already uses, just
## aimed at the boar instead of empty air.
func test_character_walks_to_and_swings_at_the_boar_during_fight():
	var boar_position: Vector2 = diorama.get("_layout").boar_position
	diorama.character_view.position = boar_position + Vector2(60, 0)
	diorama._enter_action(CharacterActionPicker.Action.FIGHT)
	diorama.set("_action_time_remaining", 1000.0)
	for i in 100:
		diorama._process(0.1)
	# Within sparring range, not on top of the boar -- CreatureMarker.ATTACK_
	# RANGE is the real game's own idea of "close enough to fight", reused
	# here rather than a diorama-only number.
	var CreatureMarker = load("res://src/rendering/creature_marker.gd")
	assert_lt(
		diorama.character_view.position.distance_to(boar_position), CreatureMarker.ATTACK_RANGE + 4.0,
		"the hero should have closed to sparring range of the boar"
	)
	diorama.character_view._process(0.05)
	assert_gt(diorama.character_view.tool_slot_rotation(), 0.0, "the hero should genuinely swing at the boar, not just stand near it")


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


## FISH used to just stand still facing the pond once arrived -- no cast, no
## bobber, nothing that actually reads as "fishing" (reported live,
## alongside the request for more scene life: "the character should do
## random things like ... fish a fish"). Player._start_cast_visuals sets the
## precedent this diorama's own hero now follows exactly: reuse the SAME
## swing animation as a melee attack for the rod-throw, plus a bobber
## Sprite2D at FishingCast.cast_point -- no new animation needed, the real
## game's own fishing has never had one either.
func test_arriving_at_the_fishing_spot_casts_a_line_with_a_swing_and_a_bobber():
	var fishing_spot: Vector2 = diorama.get("_fishing_spot")
	diorama.character_view.position = fishing_spot + Vector2(30, 0)
	diorama._enter_action(CharacterActionPicker.Action.FISH)
	diorama.set("_action_time_remaining", 1000.0)
	for i in 300:
		diorama._process(0.1)
	assert_true(diorama.get("_bobber").visible, "the bobber should be showing once the hero has actually cast a line")
	# Mid-arc, the same check test_character_swings_the_weapon_during_swing
	# above uses for the ordinary SWING action -- proof play_attack_swing
	# genuinely fired for the cast, not just a flag.
	diorama.character_view._process(0.05)
	assert_gt(diorama.character_view.tool_slot_rotation(), 0.0, "the cast should visibly swing the rod like a real attack")


## The real player (scenes/player.gd, _step_water_ripples) already records a
## water disturbance while genuinely swimming/wading -- the diorama's own
## hero, driven by its own separate movement code rather than Player, never
## did (reported live: "player doesnt cause water ripples"). Walking TO the
## fishing spot crosses genuinely-moving-while-in-water, exactly the case
## the real player's own WATER_RIPPLE_MODES/input_direction gate covers.
##
## Checked as a RISING EDGE of the water shader's own disturbance count
## across every step, not the count at the end of the loop -- a ripple's
## own RIPPLE_LIFETIME (2.2s) is far shorter than this loop's full
## simulated duration (300 * 0.1 = 30s), so by the very last step whatever
## fired long ago has already faded back out on its own; checking only the
## final count would make this test pass or fail on decay timing rather
## than on whether a disturbance was ever actually recorded at all (an
## earlier version of this test did exactly that, and failed even once the
## real fix landed).
func test_the_hero_records_a_water_disturbance_while_swimming_toward_the_fishing_spot():
	var fishing_spot: Vector2 = diorama.get("_fishing_spot")
	diorama.character_view.position = fishing_spot + Vector2(30, 0)
	diorama._enter_action(CharacterActionPicker.Action.FISH)
	diorama.set("_action_time_remaining", 1000.0)
	var previous_count := 0
	var ever_recorded := false
	for i in 300:
		diorama._process(0.1)
		var current_count: int = diorama.get("_water_shader")._disturbance_positions.size()
		if current_count > previous_count:
			ever_recorded = true
		previous_count = current_count
	assert_true(ever_recorded, "no water disturbance was ever recorded while the hero swam toward the fishing spot")


## The real player's own gate stops ripples the instant it stops moving
## (input_direction.length() <= 0.01), even while still standing in the
## water -- an idle float doesn't ripple, only movement does. Checked the
## same rising-edge way as the test above, restricted to steps AFTER the
## hero has genuinely arrived and is holding still: natural ripple decay
## (RIPPLE_LIFETIME, far shorter than this test's own loop) would make a
## plain "is the count now zero" check pass regardless of whether new
## ripples kept firing or not.
func test_the_hero_stops_rippling_once_it_holds_still_in_the_water():
	var fishing_spot: Vector2 = diorama.get("_fishing_spot")
	diorama.character_view.position = fishing_spot + Vector2(30, 0)
	diorama._enter_action(CharacterActionPicker.Action.FISH)
	diorama.set("_action_time_remaining", 1000.0)
	var previous_count := 0
	var new_ripple_while_still := false
	for i in 300:
		diorama._process(0.1)
		var current_count: int = diorama.get("_water_shader")._disturbance_positions.size()
		var arrived: bool = diorama.character_view.position.distance_to(fishing_spot) <= 2.5
		if arrived and current_count > previous_count:
			new_ripple_while_still = true
		previous_count = current_count
	assert_false(new_ripple_while_still, "a new ripple was recorded while the hero was holding still, already arrived, in the water")
