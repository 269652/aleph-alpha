extends GutTest

const CharacterPreviewDioramaScript = preload("res://src/rendering/character_preview_diorama.gd")
const CharacterPreviewLayout = preload("res://src/rendering/character_preview_layout.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")

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


func test_rebuilding_frees_the_previous_generation_of_nodes():
	var first_character_view: Node2D = diorama.character_view
	diorama.build(99)
	assert_ne(diorama.character_view, first_character_view)
