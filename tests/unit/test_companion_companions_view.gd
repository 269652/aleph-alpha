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
