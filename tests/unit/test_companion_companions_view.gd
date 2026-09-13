extends GutTest

## CompanionCompanionsView: renders Player.to_save_dict()'s bonded_companions
## list -- a plain [{"species": String}, ...] array, nothing richer persisted
## today. Deliberately named "Companions", not "Bestiary": a full
## every-creature-encountered bestiary has no data source anywhere in this
## codebase (confirmed by whole-repo search -- see
## docs/concept/companion_server.md's Companions section for the full
## reasoning), so this view only ever claims to show what's real.

const CompanionCompanionsView = preload("res://src/companion_server/companion_companions_view.gd")


func test_lists_a_bonded_companions_species():
	var html := CompanionCompanionsView.render({"bonded_companions": [{"species": "songbird"}]})
	assert_true(html.contains("songbird"))


func test_lists_multiple_companions():
	var save_dict := {"bonded_companions": [{"species": "songbird"}, {"species": "butterfly"}]}
	var html := CompanionCompanionsView.render(save_dict)
	assert_true(html.contains("songbird"))
	assert_true(html.contains("butterfly"))


func test_an_empty_list_shows_a_friendly_empty_state_not_a_blank_page():
	var html := CompanionCompanionsView.render({"bonded_companions": []})
	assert_true(html.length() > 0)
	assert_true(html.contains("none") or html.contains("No "))


func test_a_missing_key_is_treated_as_no_companions_rather_than_a_crash():
	# A save from before bonded_companions existed, or a hand-built fixture
	# that omits it, must degrade to the empty state rather than error.
	var html := CompanionCompanionsView.render({})
	assert_true(html.length() > 0)


## -- kept_animals: real trust/order/wander_seed, scanned across chunks -------
##
## KeptAnimals (src/world/kept_animals.gd) persists real per-individual
## trust/order/is_tied/tied_to/wander_seed, per chunk. The default empty
## array keeps every call above (and every other call site) green while
## adding a real second data source: CompanionKeptAnimalsReader's flattened,
## chunk-tagged records.

func test_default_kept_animals_argument_keeps_the_existing_single_arg_call_green():
	# No second argument at all -- the exact shape every existing call site
	# (including every test above) uses.
	var html := CompanionCompanionsView.render({"bonded_companions": []})
	assert_true(html.length() > 0)


func test_a_kept_animal_shows_its_species_and_chunk_coordinate():
	var kept_animals := [{
		"species": "horse",
		"position": Vector2(10, 20),
		"trust": 1.0,
		"order": 1,
		"is_tied": true,
		"tied_to": Vector2(5, 5),
		"wander_seed": 42,
		"chunk_coord": Vector2i(2, -1),
	}]
	var html := CompanionCompanionsView.render({"bonded_companions": []}, kept_animals)
	assert_true(html.contains("horse"))
	assert_true(html.contains("2, -1") or html.contains("(2, -1)"))


func test_a_kept_animal_shows_tied_status_and_order_label():
	var kept_animals := [{
		"species": "horse", "position": Vector2.ZERO, "trust": 1.0, "order": 1,
		"is_tied": true, "tied_to": Vector2.ZERO, "wander_seed": 1, "chunk_coord": Vector2i.ZERO,
	}]
	var html := CompanionCompanionsView.render({}, kept_animals)
	assert_true(html.contains("Tied"))
	assert_true(html.contains("Stay"))


func test_a_loose_followed_kept_animal_shows_loose_and_follow():
	var kept_animals := [{
		"species": "wolf", "position": Vector2.ZERO, "trust": 0.5, "order": 0,
		"is_tied": false, "tied_to": Vector2.ZERO, "wander_seed": 2, "chunk_coord": Vector2i.ZERO,
	}]
	var html := CompanionCompanionsView.render({}, kept_animals)
	assert_true(html.contains("Loose"))
	assert_true(html.contains("Follow"))


func test_a_fully_tame_kept_animal_shows_the_tame_trust_stage():
	var kept_animals := [{
		"species": "horse", "position": Vector2.ZERO, "trust": 1.0, "order": 1,
		"is_tied": true, "tied_to": Vector2.ZERO, "wander_seed": 1, "chunk_coord": Vector2i.ZERO,
	}]
	var html := CompanionCompanionsView.render({}, kept_animals)
	assert_true(html.contains("Tame"))


func test_a_kept_animal_shows_a_live_fitness_number_derived_from_wander_seed():
	const AnimalFitness = preload("res://src/world/animal_fitness.gd")
	var wander_seed := 12345
	var expected_score := AnimalFitness.new().fitness_score(AnimalFitness.new().phenotype_for(wander_seed))
	var kept_animals := [{
		"species": "horse", "position": Vector2.ZERO, "trust": 1.0, "order": 1,
		"is_tied": true, "tied_to": Vector2.ZERO, "wander_seed": wander_seed, "chunk_coord": Vector2i.ZERO,
	}]
	var html := CompanionCompanionsView.render({}, kept_animals)
	assert_true(html.contains(("%.2f" % expected_score)))


func test_multiple_kept_animals_each_render_their_own_row():
	var kept_animals := [
		{"species": "horse", "position": Vector2.ZERO, "trust": 1.0, "order": 1,
		 "is_tied": true, "tied_to": Vector2.ZERO, "wander_seed": 1, "chunk_coord": Vector2i.ZERO},
		{"species": "wolf", "position": Vector2.ZERO, "trust": 0.2, "order": 0,
		 "is_tied": false, "tied_to": Vector2.ZERO, "wander_seed": 2, "chunk_coord": Vector2i(1, 1)},
	]
	var html := CompanionCompanionsView.render({}, kept_animals)
	assert_true(html.contains("horse"))
	assert_true(html.contains("wolf"))


func test_no_kept_animals_shows_a_friendly_empty_state_for_that_section():
	var html := CompanionCompanionsView.render({}, [])
	assert_true(html.contains("none") or html.contains("No "))
