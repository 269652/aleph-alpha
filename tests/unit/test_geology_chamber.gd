extends GutTest

## GeologyChamber.cells_for: which local Strata cells a cave entrance
## reveals -- the underground equivalent of RoomDetector's room cells (see
## docs/concept/geology.md "Reveal-on-entry, reused recursively").

const GeologyChamber = preload("res://src/world/geology_chamber.gd")


func test_includes_the_entrance_cell_itself():
	var cells := GeologyChamber.cells_for(Vector2i(5, 5))
	assert_true(cells.has(Vector2i(5, 5)))


func test_chamber_is_small_and_bounded():
	var cells := GeologyChamber.cells_for(Vector2i(0, 0))
	assert_gt(cells.size(), 1, "a chamber of just the entrance cell isn't a chamber")
	assert_lt(cells.size(), 50, "chamber must stay a small confined starter area")


func test_chamber_cells_are_all_within_the_configured_radius():
	var origin := Vector2i(10, 10)
	var cells := GeologyChamber.cells_for(origin)
	for cell in cells:
		var offset: Vector2i = cell - origin
		assert_true(
			Vector2(offset).length() <= GeologyChamber.CHAMBER_RADIUS + 0.51,
			"cell %s outside the chamber radius" % cell
		)


func test_chamber_translates_with_its_entrance():
	var at_origin := GeologyChamber.cells_for(Vector2i.ZERO)
	var shifted := GeologyChamber.cells_for(Vector2i(20, 20))
	assert_eq(at_origin.size(), shifted.size())
	for cell in at_origin:
		assert_true(shifted.has(cell + Vector2i(20, 20)))


func test_no_duplicate_cells():
	var cells := GeologyChamber.cells_for(Vector2i(3, 3))
	var seen := {}
	for cell in cells:
		assert_false(seen.has(cell), "duplicate cell %s" % cell)
		seen[cell] = true


## Regression: "small and bounded" (this file's own header comment, and
## geology.md's "deliberately small and bounded rather than an arbitrary
## big reveal") was only ever checked as a bare tile COUNT
## (test_chamber_is_small_and_bounded's `< 50`), never against what a
## player actually sees. Reported live (playtest, 2026-08-28): at
## CHAMBER_RADIUS=3, the revealed disk's 7-tile diameter renders at
## Player.TARGET_TILE_SCREEN_PX (64px/tile, the shipped camera zoom) as
## ~448px against the project's own 720px-tall default viewport
## (project.godot's [display] section) -- ~62% of the visible screen's
## shorter side, described as "a dense grid covering most of the visible
## ground," not a small starter pocket. Pinning the SCREEN-relative
## fraction rather than a tile count means a future TILE_SIZE or
## window-size change can't silently blow this back up unnoticed the way
## it did once already.
##
## Threshold raised 0.3 -> 0.4 when the camera was asked to zoom in 30%
## (Player.TARGET_TILE_SCREEN_PX 64.0 -> 83.2): CHAMBER_RADIUS is already at
## its own floor (1, the largest radius this same test allowed at the OLD
## zoom, and the smallest that still clears test_chamber_is_small_and_
## bounded's "more than just the entrance cell" lower bound) -- it cannot
## shrink further to absorb a camera-only change, so the fraction this
## pocket now genuinely occupies (3 tiles * 83.2px / 720px = 34.67%) is a
## real, correct consequence of standing closer to the ground, not a
## regression. 0.4 keeps essentially the same RELATIVE headroom the
## original 0.3 had over its own 26.67% (~12%) rather than eyeballing a
## fresh number.
func test_chamber_diameter_stays_a_small_fraction_of_the_visible_screen():
	var diameter_tiles := 2.0 * GeologyChamber.CHAMBER_RADIUS + 1.0
	var diameter_px := diameter_tiles * Player.TARGET_TILE_SCREEN_PX
	var viewport_px := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height")
	)
	var visible_shorter_side_px: float = minf(viewport_px.x, viewport_px.y)
	var fraction: float = diameter_px / visible_shorter_side_px
	assert_lt(
		fraction, 0.4,
		(
			"chamber diameter is %.0f%% of the visible screen's shorter side -- "
			+ "too big to read as a small starter pocket"
		) % [fraction * 100.0]
	)
