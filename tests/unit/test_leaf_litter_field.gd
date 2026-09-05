extends GutTest

## Per-chunk fallen-leaf litter (see docs/concept/leaf_litter.md). Mirrors
## AntColony's own shape: cheap plain data, created at chunk load and erased
## at unload, advance(delta) ages/prunes. Exists so a decomposer has a real,
## individually-addressable position to forage from and remove -- the
## discrete-position contract a pure GPU density-field aggregate (the
## SnowBombShader approach, tried and abandoned twice for this exact feature)
## cannot offer.

const LeafLitterField = preload("res://src/world/leaf_litter_field.gd")


func _field() -> LeafLitterField:
	return LeafLitterField.new()


# -- empty by default ---------------------------------------------------------

func test_a_fresh_field_holds_no_leaves():
	var field := _field()
	assert_eq(field.leaves().size(), 0)


func test_a_fresh_field_finds_nothing_nearby():
	var field := _field()
	assert_eq(field.nearest_leaf_near(Vector2.ZERO, 1000.0), {})


func test_consuming_from_an_empty_field_does_nothing():
	var field := _field()
	assert_false(field.consume_leaf_at(Vector2.ZERO))


# -- add_leaf -------------------------------------------------------------

func test_add_leaf_is_reflected_in_leaves():
	var field := _field()
	field.add_leaf(Vector2(50, 60), "cherry", "autumn", 10.0)
	assert_eq(field.leaves().size(), 1)


func test_a_freshly_fallen_leaf_starts_above_its_own_landing_position():
	var field := _field()
	field.add_leaf(Vector2(50, 60), "cherry", "autumn", 10.0)
	var leaf: Dictionary = field.leaves()[0]
	assert_eq(leaf.position, Vector2(50, 60))
	assert_eq(leaf.transition_from, Vector2(50, 60 - LeafLitterField.FALL_HEIGHT))
	assert_eq(leaf.transition_start, 10.0)
	assert_eq(leaf.spawned_at, 10.0)


func test_add_leaf_keeps_species_and_season():
	var field := _field()
	field.add_leaf(Vector2(50, 60), "acorn", "summer", 0.0)
	var leaf: Dictionary = field.leaves()[0]
	assert_eq(leaf.species, "acorn")
	assert_eq(leaf.season, "summer")


# -- nearest_leaf_near ----------------------------------------------------

func test_nearest_leaf_near_finds_a_leaf_within_radius():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	var found := field.nearest_leaf_near(Vector2(105, 100), 20.0)
	assert_eq(found.get("position"), Vector2(100, 100))
	assert_eq(found.get("species"), "cherry")
	assert_eq(found.get("season"), "autumn")


func test_nearest_leaf_near_ignores_a_leaf_outside_radius():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	assert_eq(field.nearest_leaf_near(Vector2(500, 500), 20.0), {})


func test_nearest_leaf_near_picks_the_closer_of_two():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.add_leaf(Vector2(110, 100), "apple", "autumn", 0.0)
	var found := field.nearest_leaf_near(Vector2(108, 100), 50.0)
	assert_eq(found.get("species"), "apple")


# -- consume_leaf_at --------------------------------------------------------

func test_consume_leaf_at_removes_the_leaf_and_reports_success():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	assert_true(field.consume_leaf_at(Vector2(100, 100)))
	assert_eq(field.leaves().size(), 0)


func test_a_consumed_leaf_cannot_be_consumed_twice():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	assert_true(field.consume_leaf_at(Vector2(100, 100)))
	assert_false(field.consume_leaf_at(Vector2(100, 100)))


func test_consume_leaf_at_misses_a_position_with_no_leaf():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	assert_false(field.consume_leaf_at(Vector2(400, 400)))
	assert_eq(field.leaves().size(), 1, "a miss must not remove an unrelated leaf")


# -- advance: aging and pruning ----------------------------------------------

func test_advance_keeps_a_leaf_within_its_lifetime():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.advance(1.0, LeafLitterField.LIFETIME - 1.0)
	assert_eq(field.leaves().size(), 1)


func test_advance_prunes_a_leaf_past_its_lifetime():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.advance(1.0, LeafLitterField.LIFETIME + 1.0)
	assert_eq(field.leaves().size(), 0)


func test_advance_never_prunes_early():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 5.0)
	field.advance(1.0, 5.0 + LeafLitterField.LIFETIME - 0.01)
	assert_eq(field.leaves().size(), 1, "must not prune a leaf a fraction of a second early")


# -- advance: settling the fall/relocation transition ------------------------
#
# The renderer's own transition machinery (see LeafLitterRenderer) needs a
# leaf's transition_from to genuinely EQUAL position once its transition is
# over, not merely "old enough that the eased curve reads as done" -- a
# wrapped GPU clock can alias after a long enough real time (see
# LeafLitterRenderer's own doc comment), and the one thing that keeps that
# safe is a real, CPU-side, zero-offset encoding once settled.

func test_advance_snaps_the_transition_once_its_duration_has_passed():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.advance(1.0, LeafLitterField.TRANSITION_DURATION + 0.5)
	var leaf: Dictionary = field.leaves()[0]
	assert_eq(leaf.transition_from, leaf.position, "a settled leaf's transition must read as zero offset")


func test_advance_does_not_snap_a_transition_still_in_progress():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.advance(1.0, LeafLitterField.TRANSITION_DURATION * 0.5)
	var leaf: Dictionary = field.leaves()[0]
	assert_ne(leaf.transition_from, leaf.position, "a leaf mid-fall must still carry a real offset")


# -- relocate_leaf_near: the one persisted-relocation mechanism --------------
#
# Mirrors PebbleDispersion's shape: a nudge that STAYS (unlike a wake that
# recovers). Reused by all three dispersal triggers (wind/player/animal) --
# see docs/concept/leaf_litter.md.

func test_relocate_leaf_near_moves_the_leaf_to_the_new_position():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.advance(1.0, 10.0)  # let the fall-in transition settle first
	assert_true(field.relocate_leaf_near(Vector2(100, 100), 20.0, Vector2(140, 100), 12.0))
	var leaf: Dictionary = field.leaves()[0]
	assert_eq(leaf.position, Vector2(140, 100))


func test_a_relocation_starts_a_fresh_transition_from_the_old_position():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.advance(1.0, 10.0)
	field.relocate_leaf_near(Vector2(100, 100), 20.0, Vector2(140, 100), 12.0)
	var leaf: Dictionary = field.leaves()[0]
	assert_eq(leaf.transition_from, Vector2(100, 100))
	assert_eq(leaf.transition_start, 12.0)


func test_relocation_does_not_reset_the_original_lifetime_clock():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.relocate_leaf_near(Vector2(100, 100), 20.0, Vector2(140, 100), 12.0)
	var leaf: Dictionary = field.leaves()[0]
	assert_eq(leaf.spawned_at, 0.0, "a nudged leaf must not get a fresh lease on life")


func test_relocate_leaf_near_misses_when_nothing_is_within_radius():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	assert_false(field.relocate_leaf_near(Vector2(900, 900), 20.0, Vector2(940, 900), 12.0))
	var leaf: Dictionary = field.leaves()[0]
	assert_eq(leaf.position, Vector2(100, 100), "a miss must leave the unrelated leaf exactly where it was")
