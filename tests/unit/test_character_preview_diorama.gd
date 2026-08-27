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


func test_build_creates_a_pond_sprite():
	var found := false
	for child in diorama.get_children():
		if child is Sprite2D and child.texture != null and child.name == "Pond":
			found = true
	assert_true(found)


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


func test_ground_draws_beneath_the_pond_and_the_grass():
	var pond: Sprite2D = diorama.get_node("Pond")
	var grass: MultiMeshInstance2D = diorama.get_node("Grass")
	for tile in diorama.ground_tiles:
		assert_lt(tile.z_index, pond.z_index, "ground must draw under the pond")
		assert_lt(tile.z_index, grass.z_index, "ground must draw under the grass")


## build() frees every previous child immediately (see its own doc comment);
## the ground array has to be reset with the others or it holds freed nodes.
func test_rebuilding_replaces_the_ground_rather_than_stacking_it():
	var first_count: int = diorama.ground_tiles.size()
	diorama.build(99)
	assert_eq(diorama.ground_tiles.size(), first_count)
	for tile in diorama.ground_tiles:
		assert_true(is_instance_valid(tile), "a freed ground tile is still in the array")


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


## FishMarker's own built-in wander (CreatureWander.WANDER_RADIUS, 40 world
## units) is tuned for a real ocean/lake, not this diorama's own ~21-unit
## pond -- reported live: "the pond has no fish" (they were there, just no
## longer visibly in the pond by the time it was looked at). Each fish's
## own _process is disabled and driven from here instead, confined to the
## pond -- checked the same way test_character_stays_within_the_footprint_
## while_strolling checks the hero, over many steps, not just one frame.
func test_fish_stay_within_the_pond_while_swimming():
	var pond_bounds := Rect2(
		diorama.get("_layout").pond_center - Vector2.ONE * diorama.get("_layout").pond_radius,
		Vector2.ONE * diorama.get("_layout").pond_radius * 2.0
	).grow(1.0)
	for i in 200:
		diorama._process(0.2)
		for fish in diorama.fish_nodes:
			assert_true(
				pond_bounds.has_point(fish.position),
				"fish left the pond at step %d: %s" % [i, fish.position]
			)


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
	diorama.set("_action_time_remaining", 30.0)  # long enough to actually arrive
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
