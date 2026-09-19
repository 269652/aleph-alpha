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
## litter). No longer a fraction of a day: it is DERIVED from the half-life
## that was asked for, so the two cannot contradict each other.
func test_lifetime_is_derived_from_the_half_life_not_eyeballed():
	assert_almost_eq(
		FootprintField.LIFETIME_SECONDS,
		FootprintField.HALF_LIFE_SECONDS * (log(1.0 / FootprintField.VISIBLE_FLOOR) / log(2.0)),
		0.01,
		"the lifetime is exactly the time to fade below the visible floor"
	)


func test_only_the_actually_expired_print_is_pruned_not_everything():
	field.add_print(Vector2(0, 0), "left", "snow", Vector2.UP, 0.0)
	field.advance(FootprintField.LIFETIME_SECONDS + 1.0)
	field.add_print(Vector2(1, 1), "right", "snow", Vector2.UP, FootprintField.LIFETIME_SECONDS + 1.0)
	field.advance(FootprintField.LIFETIME_SECONDS + 1.5)
	assert_eq(field.count(), 1, "the fresh second print should survive even though the first one just expired")
	assert_eq(field.prints()[0].side, "right")


# -- size_scale: how big a mark THIS print's own creature left, driven by --
# -- its real mass (see EarthChunkManager.record_footstep/CreatureMass. ----
# -- linear_scale_for_mass_ratio, docs/concept/snow_cover.md's ------------
# -- "Footprints depend on real mass, not just surface") -------------------

func test_add_print_records_a_real_size_scale():
	field.add_print(Vector2.ZERO, "left", "snow", Vector2.UP, 0.0, 2.5)
	assert_almost_eq(field.prints()[0].size_scale, 2.5, 0.001)


## Every pre-existing 5-arg call site across the whole project (this test
## file's own helpers above included) must keep rendering at exactly
## today's size -- a fresh optional 6th parameter, not a behavior change.
func test_add_print_defaults_size_scale_to_one_for_every_pre_existing_caller():
	field.add_print(Vector2.ZERO, "left", "snow", Vector2.UP, 0.0)
	assert_almost_eq(field.prints()[0].size_scale, 1.0, 0.001)


# -- decay: a print fades from the moment it is made, and rain hurries it --
#
# Asked for directly: "Can you add decay to the footprints? Rain should
# increase decay speed.. Should be visible for ~30 real minutes", then "Make
# the decay gradually", then "Ok make the half life time 2 minutes".


func test_a_print_is_at_half_strength_after_one_half_life():
	assert_almost_eq(
		FootprintField.HALF_LIFE_SECONDS, 2.0 * 60.0, 0.01, "asked for: a two real minute half-life"
	)
	field.add_print(Vector2.ZERO, "left", "snow", Vector2.UP, 0.0)
	field.advance(FootprintField.HALF_LIFE_SECONDS)
	assert_almost_eq(FootprintField.opacity_of(field.prints()[0]), 0.5, 0.001)


## A half-life is exponential by definition: every further half-life halves
## what is left, rather than subtracting a fixed amount.
func test_every_further_half_life_halves_what_is_left():
	field.add_print(Vector2.ZERO, "left", "snow", Vector2.UP, 0.0)
	var expected := 1.0
	for lives in range(1, 5):
		expected *= 0.5
		field.advance(FootprintField.HALF_LIFE_SECONDS * float(lives))
		assert_almost_eq(FootprintField.opacity_of(field.prints()[0]), expected, 0.001)


func test_a_fresh_print_is_at_full_strength():
	field.add_print(Vector2.ZERO, "left", "snow", Vector2.UP, 0.0)
	assert_almost_eq(FootprintField.opacity_of(field.prints()[0]), 1.0, 0.0001)


## "Make the decay gradually": fainter at every step of its life, not full
## strength and then a cliff.
func test_a_print_fades_gradually_across_its_whole_life():
	field.add_print(Vector2.ZERO, "left", "snow", Vector2.UP, 0.0)
	var previous := 1.0001
	var step := FootprintField.LIFETIME_SECONDS / 20.0
	for i in range(1, 20):
		field.advance(step * float(i))
		assert_eq(field.count(), 1, "precondition: still there to be looked at")
		var opacity: float = FootprintField.opacity_of(field.prints()[0])
		assert_lt(opacity, previous, "a print must be fainter than it was a step ago")
		previous = opacity
	assert_lt(previous, 0.1, "and nearly gone by the end of its life")


## The record is dropped exactly when it stops being worth drawing -- not
## carried around invisible, which in this project is how frame rates die.
func test_a_print_is_kept_exactly_as_long_as_it_can_be_seen():
	field.add_print(Vector2.ZERO, "left", "snow", Vector2.UP, 0.0)
	field.advance(FootprintField.LIFETIME_SECONDS * 0.99)
	assert_eq(field.count(), 1, "still faintly there")
	assert_lt(
		FootprintField.opacity_of(field.prints()[0]), 0.05,
		"though only just -- it is at the edge of visibility by now"
	)
	field.advance(FootprintField.LIFETIME_SECONDS + 1.0)
	assert_eq(field.count(), 0, "and dropped once nobody could see it")


func test_dry_ground_decays_at_its_own_pace_and_rain_multiplies_it():
	assert_almost_eq(FootprintField.decay_rate_for(0.0), 1.0, 0.0001)
	assert_almost_eq(
		FootprintField.decay_rate_for(1.0), float(FootprintField.RAIN_DECAY_MULTIPLIER), 0.0001
	)
	assert_gt(FootprintField.decay_rate_for(0.5), FootprintField.decay_rate_for(0.0))
	assert_lt(FootprintField.decay_rate_for(0.5), FootprintField.decay_rate_for(1.0))


## In a downpour the half-life is a quarter of what it is on dry ground.
func test_rain_shortens_the_half_life_by_the_pinned_multiple():
	var wet := FootprintField.new()
	wet.add_print(Vector2.ZERO, "left", "snow", Vector2.UP, 0.0)
	wet.advance(FootprintField.HALF_LIFE_SECONDS / float(FootprintField.RAIN_DECAY_MULTIPLIER), 1.0)
	assert_almost_eq(FootprintField.opacity_of(wet.prints()[0]), 0.5, 0.001)


func test_rain_fades_a_print_faster_than_dry_weather():
	var wet := FootprintField.new()
	wet.add_print(Vector2.ZERO, "left", "snow", Vector2.UP, 0.0)
	field.add_print(Vector2.ZERO, "left", "snow", Vector2.UP, 0.0)
	var a_while := FootprintField.HALF_LIFE_SECONDS * 0.5
	wet.advance(a_while, 1.0)
	field.advance(a_while, 0.0)
	assert_lt(
		FootprintField.opacity_of(wet.prints()[0]), FootprintField.opacity_of(field.prints()[0]),
		"the same print, the same elapsed time, but one of them stood out in the rain"
	)


## Rain that starts halfway through a print's life hurries only what is LEFT
## of it. This is exactly why decay ACCUMULATES per step rather than being
## recomputed from spawned_at: the weather at the moment somebody asks is not
## the weather the print has actually lived through.
func test_rain_only_hurries_the_life_that_is_left():
	field.add_print(Vector2.ZERO, "left", "snow", Vector2.UP, 0.0)
	field.advance(FootprintField.HALF_LIFE_SECONDS, 0.0)
	assert_almost_eq(FootprintField.opacity_of(field.prints()[0]), 0.5, 0.001)
	# One more half-life's worth of decay, but in a downpour it takes a
	# quarter of the time -- and it halves what is LEFT, not the original.
	field.advance(
		FootprintField.HALF_LIFE_SECONDS
		+ FootprintField.HALF_LIFE_SECONDS / float(FootprintField.RAIN_DECAY_MULTIPLIER),
		1.0
	)
	assert_almost_eq(FootprintField.opacity_of(field.prints()[0]), 0.25, 0.001)


## Every caller that predates rain passes no wetness at all, and must keep
## the dry pace rather than silently getting a default downpour.
func test_an_advance_that_says_nothing_about_weather_is_dry():
	field.add_print(Vector2.ZERO, "left", "snow", Vector2.UP, 0.0)
	field.advance(FootprintField.HALF_LIFE_SECONDS)
	assert_almost_eq(FootprintField.opacity_of(field.prints()[0]), 0.5, 0.001)


## The renderer rebuilds its instance buffer only when generation() changes,
## and that dirty check is the fix for FPS regression round 4. A fade that
## bumped it every advance would hand that regression straight back.
func test_fading_bumps_the_generation_once_per_band_not_once_per_advance():
	field.add_print(Vector2.ZERO, "left", "snow", Vector2.UP, 0.0)
	var before := field.generation()
	var band := FootprintField.HALF_LIFE_SECONDS / 200.0
	for i in range(1, 21):
		field.advance(band * float(i))
	var bumps := field.generation() - before
	assert_gt(bumps, 0, "a fade the renderer never hears about is a fade nobody sees")
	assert_lt(bumps, 20, "but not one rebuild per advance -- that is the round 4 regression")
