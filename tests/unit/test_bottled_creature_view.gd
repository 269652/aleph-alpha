extends GutTest

## Red-first spec for bottled_creature_view.gd (docs/concept/capture_dsl.md's
## "Rendering a bottled catch"): back sprite -> live creature -> front
## sprite, composited in that draw order. Reuses ProceduralButterflySprite's
## existing flap/settled frame generators and WingbeatBounce's real-physics
## bob wholesale -- nothing here draws a new creature frame from scratch.

const BottledCreatureView = preload("res://src/rendering/bottled_creature_view.gd")
const BottledCreatureWander = preload("res://src/gameplay/bottled_creature_wander.gd")


func _view(species: String, wander_seed: int = 5) -> BottledCreatureView:
	var view := BottledCreatureView.new()
	view.species = species
	view.wander_seed = wander_seed
	add_child_autofree(view)
	return view


func test_a_covered_species_gets_a_live_creature_layer():
	var view := _view("monarch")
	assert_not_null(view._creature, "monarch is covered by ProceduralButterflySprite")


func test_an_uncovered_species_shows_only_the_bottle():
	var view := _view("sparrow")
	assert_null(view._creature, "sparrow has no butterfly-generator art -- an honest fallback, not an error")


func test_back_and_front_sprites_always_exist_regardless_of_species():
	for species in ["monarch", "sparrow"]:
		var view := _view(species)
		assert_not_null(view._back.texture)
		assert_not_null(view._front.texture)


func test_the_creature_starts_with_a_real_texture():
	var view := _view("monarch")
	view._animate_creature()
	assert_not_null(view._creature.texture)


func test_the_creatures_position_stays_within_the_interior_bounds():
	var view := _view("monarch")
	for t in range(0, 100):
		view._elapsed = float(t) * 0.2
		view._animate_creature()
		assert_true(
			BottledCreatureView.INTERIOR_BOUNDS.has_point(view._creature.position),
			"creature escaped its interior bounds at t=%f" % view._elapsed
		)


func test_a_settled_moment_shows_a_settled_frame_not_a_flap_frame():
	var view := _view("monarch")
	# Find a moment BottledCreatureWander itself reports as resting, and
	# confirm the view actually drew from settled_frames, not flap_frames.
	var t := 0.0
	while not BottledCreatureWander.is_resting(t, view.wander_seed) and t < 30.0:
		t += 0.1
	assert_lt(t, 30.0, "expected to find a resting moment within 30s")
	view._elapsed = t
	view._animate_creature()
	assert_true(
		view._settled_frames.has(view._creature.texture),
		"a resting moment should show a settled (wings-folded) frame"
	)
