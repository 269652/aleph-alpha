extends GutTest

## LoadingOverlay (see World._show_loading_overlay and, as of this pass,
## MainMenu's own character-creator build -- docs/concept/intro_splash.md).
## Previously only exercised indirectly, through World's own source-text
## ordering tests (test_world_intro_splash_after_load_fanout.gd) -- this is
## its first direct coverage, added alongside set_progress's own new `unit`
## parameter.

const LoadingOverlay = preload("res://scenes/loading_overlay.gd")


func _overlay() -> LoadingOverlay:
	var overlay := LoadingOverlay.new()
	add_child_autofree(overlay)
	return overlay


## The pre-existing chunk-loading callers (World._on_chunk_load_progress)
## pass no unit at all -- the new parameter must default to exactly the
## wording they already show, or every existing "N / M chunks" loading
## screen silently changes.
func test_set_progress_defaults_to_chunks_for_existing_callers():
	var overlay := _overlay()
	overlay.show_with_text("Loading your world...")

	overlay.set_progress(3, 10)

	assert_eq(overlay.status_text(), "Loading your world... (3 / 10 chunks)")


## New callers (MainMenu's own character-creator build, see test_main_menu.gd)
## need real, correctly-worded progress too -- "3 / 7 chunks" would be a
## real, honest lie about what's actually being counted.
func test_set_progress_accepts_a_different_unit_for_non_chunk_callers():
	var overlay := _overlay()
	overlay.show_with_text("Building character creator...")

	overlay.set_progress(2, 7, "portraits")

	assert_eq(overlay.status_text(), "Building character creator... (2 / 7 portraits)")
