extends GutTest

## FootprintField: per-chunk record of individual footprint stamps (see
## FootstepGait). Mirrors LeafLitterField's exact shape -- plain
## Dictionary-per-instance data, no scene nodes, GPU-instanced by
## FootprintRenderer -- but deliberately simpler: a footprint is static
## once stamped (no wind drift, no settle transition, no multi-stage
## colour decay the way a leaf has), so this has no animation machinery
## to mirror, just add/prune/generation.

const FootprintField = preload("res://src/world/footprint_field.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")

var field: FootprintField


func before_each():
	field = FootprintField.new()


func test_starts_empty():
	assert_eq(field.count(), 0)
	assert_eq(field.prints(), [])


func test_add_print_records_a_real_entry():
	field.add_print(Vector2(10, 20), "left", "snow", Vector2(0, -1), 0.0)
	assert_eq(field.count(), 1)
	var p: Dictionary = field.prints()[0]
	assert_eq(p.position, Vector2(10, 20))
	assert_eq(p.side, "left")
	assert_eq(p.surface, "snow")
	assert_eq(p.heading, Vector2(0, -1))
	assert_eq(p.spawned_at, 0.0)


func test_add_print_bumps_generation():
	var before := field.generation()
	field.add_print(Vector2.ZERO, "left", "snow", Vector2.UP, 0.0)
	assert_gt(field.generation(), before)


func test_multiple_prints_accumulate_in_order():
	field.add_print(Vector2(0, 0), "left", "snow", Vector2.UP, 0.0)
	field.add_print(Vector2(1, 1), "right", "snow", Vector2.UP, 0.0)
	assert_eq(field.count(), 2)
	assert_eq(field.prints()[0].side, "left")
	assert_eq(field.prints()[1].side, "right")


# -- lifetime pruning: a footprint is an ephemeral mark, not persistent ---
# -- litter, and fades on its own real clock ------------------------------

func test_a_fresh_print_survives_advance():
	field.add_print(Vector2.ZERO, "left", "snow", Vector2.UP, 0.0)
	field.advance(1.0)
	assert_eq(field.count(), 1)


func test_a_print_is_pruned_once_its_lifetime_elapses():
	field.add_print(Vector2.ZERO, "left", "snow", Vector2.UP, 0.0)
	field.advance(FootprintField.LIFETIME_SECONDS + 1.0)
	assert_eq(field.count(), 0)


func test_pruning_bumps_generation():
	field.add_print(Vector2.ZERO, "left", "snow", Vector2.UP, 0.0)
	var before := field.generation()
	field.advance(FootprintField.LIFETIME_SECONDS + 1.0)
	assert_gt(field.generation(), before)


func test_advance_with_nothing_to_prune_leaves_generation_unchanged():
	field.add_print(Vector2.ZERO, "left", "snow", Vector2.UP, 0.0)
	field.advance(1.0)
	var after_first := field.generation()
	field.advance(2.0)
	assert_eq(field.generation(), after_first)


## Real design knob, deliberately far shorter than LeafLitterField.LIFETIME
## (0.75 real years -- a footprint is an ephemeral mark, not persistent
## litter) -- expressed as a fraction of a real in-game day, not a raw
## eyeballed second count.
func test_lifetime_is_a_fraction_of_a_real_day_not_eyeballed():
	assert_almost_eq(FootprintField.LIFETIME_SECONDS, SeasonCycle.SECONDS_PER_DAY * 0.5, 0.01)


func test_only_the_actually_expired_print_is_pruned_not_everything():
	field.add_print(Vector2(0, 0), "left", "snow", Vector2.UP, 0.0)
	field.advance(FootprintField.LIFETIME_SECONDS + 1.0)
	field.add_print(Vector2(1, 1), "right", "snow", Vector2.UP, FootprintField.LIFETIME_SECONDS + 1.0)
	field.advance(FootprintField.LIFETIME_SECONDS + 1.5)
	assert_eq(field.count(), 1, "the fresh second print should survive even though the first one just expired")
	assert_eq(field.prints()[0].side, "right")
