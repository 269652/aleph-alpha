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


# -- advance: decaying through "fading" to "winter", a leaf's terminal ------
# -- stage --------------------------------------------------------------------
#
# Reported directly, across two rounds: first "fallen leaves should change
# the season from autumn to winter if they keep lying on the ground ...
# winter is last stage for a leaf", then, once that shipped as a single
# jump straight to "winter", "leaf decay should be 3 seasons" -- clarified
# as "leafs should take roughly 270 days to rot / decay / vanish". 270
# real-world days is ~3 of the 4 real seasons a year has (~91 days each),
# the genuine real-world timescale leaf litter actually takes to fully
# decompose -- so a settled leaf's own `season` field now passes through
# exactly 3 distinct values over its life (its own fall colour, then
## "fading", then "winter"), evenly spaced across LIFETIME, itself now
# grounded in that same ~270-day/3-season real-world figure (see
# LIFETIME's own doc comment) rather than an arbitrary "tidiness" cutoff.

const SeasonCycle = preload("res://src/world/season_cycle.gd")

## Not an eyeballed number -- 270 real-world days (reported directly:
## "leafs should take roughly 270 days to rot / decay / vanish") is ~3 of
## the 4 real seasons a year actually has (~91 days each) -- expressed as
## exactly 3/4 of a real year, translated through the SAME real-year ->
## compressed-game-year ratio every other real-world-grounded timing
## constant in this codebase already uses (SeasonCycle.SECONDS_PER_YEAR).
func test_lifetime_is_pinned_to_three_quarters_of_a_compressed_game_year():
	assert_almost_eq(LeafLitterField.LIFETIME, 0.75 * SeasonCycle.SECONDS_PER_YEAR, 0.01)


## Not eyeballed either -- an even three-way split of LIFETIME (see that
## constant's own doc comment), so a settled leaf spends an equal,
## deliberately chosen third of its whole time on the ground looking
## freshly fallen, halfway faded, and fully decayed, rather than any one
## stage swallowing most of it.
func test_decay_thresholds_are_pinned_to_an_even_three_way_split_of_lifetime():
	assert_almost_eq(
		LeafLitterField.DECAY_TO_FADING_SECONDS, LeafLitterField.LIFETIME / 3.0, 0.01
	)
	assert_almost_eq(
		LeafLitterField.DECAY_TO_WINTER_SECONDS, LeafLitterField.LIFETIME * 2.0 / 3.0, 0.01
	)


func test_advance_keeps_the_fallen_season_before_the_fading_threshold():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.advance(1.0, LeafLitterField.DECAY_TO_FADING_SECONDS - 1.0)
	assert_eq(field.leaves()[0].season, "autumn")


func test_fading_never_happens_early():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.advance(1.0, LeafLitterField.DECAY_TO_FADING_SECONDS - 0.01)
	assert_eq(
		field.leaves()[0].season, "autumn", "must not fade a fraction of a second early"
	)


func test_advance_fades_once_the_first_threshold_passes():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.advance(1.0, LeafLitterField.DECAY_TO_FADING_SECONDS + 1.0)
	assert_eq(field.leaves()[0].season, "fading")


func test_advance_stays_fading_between_the_two_thresholds():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.advance(1.0, LeafLitterField.DECAY_TO_WINTER_SECONDS - 1.0)
	assert_eq(field.leaves()[0].season, "fading")


func test_winter_never_happens_early():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.advance(1.0, LeafLitterField.DECAY_TO_WINTER_SECONDS - 0.01)
	assert_eq(
		field.leaves()[0].season, "fading", "must not decay to winter a fraction of a second early"
	)


func test_advance_decays_to_winter_once_the_second_threshold_passes():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.advance(1.0, LeafLitterField.DECAY_TO_WINTER_SECONDS + 1.0)
	assert_eq(field.leaves()[0].season, "winter")


## Every season a leaf can actually fall in reaches the same terminal stage
## through the same middle stage -- "fading"/"winter" are not autumn-
## exclusive.
func test_a_summer_fallen_leaf_also_progresses_through_fading_to_winter():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "summer", 0.0)
	field.advance(1.0, LeafLitterField.DECAY_TO_FADING_SECONDS + 1.0)
	assert_eq(field.leaves()[0].season, "fading")
	field.advance(1.0, LeafLitterField.DECAY_TO_WINTER_SECONDS + 1.0)
	assert_eq(field.leaves()[0].season, "winter")


func test_a_spring_fallen_leaf_also_progresses_through_fading_to_winter():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "spring", 0.0)
	field.advance(1.0, LeafLitterField.DECAY_TO_FADING_SECONDS + 1.0)
	assert_eq(field.leaves()[0].season, "fading")
	field.advance(1.0, LeafLitterField.DECAY_TO_WINTER_SECONDS + 1.0)
	assert_eq(field.leaves()[0].season, "winter")


## Winter is the LAST stage -- once decayed, further real time passing (short
## of the leaf being pruned outright at LIFETIME) must never move it on to
## anything else.
func test_winter_is_a_terminal_stage_not_a_cycle():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.advance(1.0, LeafLitterField.DECAY_TO_WINTER_SECONDS + 1.0)
	assert_eq(field.leaves()[0].season, "winter")
	field.advance(1.0, LeafLitterField.LIFETIME - 1.0)
	assert_eq(field.leaves()[0].season, "winter", "winter must not advance to any further stage")


## A leaf still mid-transition (just fallen, or just relocated) is left
## alone even if it is already old enough by the clock -- "keep LYING on the
## ground" implies actually at rest, the same "only a SETTLED leaf is
## eligible" gate the wind-dispersal roll right below in this same function
## already applies for the identical reason.
func test_decay_does_not_apply_to_a_leaf_still_mid_transition():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	# Relocate it right at the moment it would otherwise fade, restarting
	# its own transition -- it must not decay while still easing into the
	# new spot, even though `now - spawned_at` already clears the threshold.
	field.relocate_leaf_near(
		Vector2(100, 100), 10.0, Vector2(120, 100), LeafLitterField.DECAY_TO_FADING_SECONDS
	)
	field.advance(1.0, LeafLitterField.DECAY_TO_FADING_SECONDS + 0.1)
	assert_eq(
		field.leaves()[0].season, "autumn", "a leaf still mid-transition must not decay yet"
	)


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


# -- wind-driven relocation: one of the three dispersal triggers -------------
#
# Reuses WindDispersal.landing_offset (WEIGHT_LEAF) at this field's own
# throttled cadence -- see docs/concept/leaf_litter.md. No new weather
# state: set_wind just stores whatever EarthChunkManager.step_leaf_litter
# already reads off the live per-chunk WeatherModel, the same wiring
## step_flowers already has for seed dispersal.

func _settled_field(count: int, wind_direction := Vector2.RIGHT, wind_strength := 1.0) -> LeafLitterField:
	var field := _field()
	for i in count:
		field.add_leaf(Vector2(i * 40.0, 0.0), "cherry", "autumn", 0.0)
	# Let every leaf's own fall-in transition finish before wind gets a
	# chance to touch it -- advance() never relocates a leaf still mid-
	# transition (see the "still mid transition" test below).
	field.advance(LeafLitterField.TRANSITION_DURATION + 0.1, LeafLitterField.TRANSITION_DURATION + 0.1)
	field.set_wind(wind_direction, wind_strength)
	return field


func _positions(field: LeafLitterField) -> Array:
	var out: Array = []
	for leaf in field.leaves():
		out.append(leaf.position)
	return out


## Bounded well under LIFETIME (90s): at WIND_DISPERSAL_INTERVAL (2s) a side
## that ran long enough to start pruning leaves would silently "pass" this
## test for the wrong reason (an empty field trivially matches nothing) --
## see LeafLitterField.LIFETIME.
const _WIND_TEST_CHECKS := 30


func test_wind_does_not_relocate_anything_in_dead_calm():
	var field := _settled_field(40, Vector2.RIGHT, 0.0)
	var before := _positions(field)
	var now := LeafLitterField.TRANSITION_DURATION + 0.1
	for i in _WIND_TEST_CHECKS:
		now += LeafLitterField.WIND_DISPERSAL_INTERVAL
		field.advance(LeafLitterField.WIND_DISPERSAL_INTERVAL, now)
	assert_eq(_positions(field), before, "dead calm must not spontaneously scatter settled litter")


func test_wind_eventually_relocates_at_least_one_settled_leaf():
	var field := _settled_field(40)
	var before := _positions(field)
	var now := LeafLitterField.TRANSITION_DURATION + 0.1
	var moved := false
	for i in _WIND_TEST_CHECKS:
		now += LeafLitterField.WIND_DISPERSAL_INTERVAL
		field.advance(LeafLitterField.WIND_DISPERSAL_INTERVAL, now)
		if _positions(field) != before:
			moved = true
			break
	assert_true(moved, "a real wind should eventually nudge at least one settled leaf")


## Proves this is a per-leaf PROBABILITY, not "windy == every leaf jumps at
## once" -- the same "occasional, not universal" shape AntColony.
## FORAGE_CHANCE's own doc comment describes for a background effect.
func test_wind_does_not_relocate_every_leaf_on_the_very_first_check():
	var field := _settled_field(40)
	var before := _positions(field)
	field.advance(LeafLitterField.WIND_DISPERSAL_INTERVAL, LeafLitterField.TRANSITION_DURATION + 0.1 + LeafLitterField.WIND_DISPERSAL_INTERVAL)
	var after := _positions(field)
	var unchanged := 0
	for i in before.size():
		if before[i] == after[i]:
			unchanged += 1
	assert_gt(unchanged, 0, "at least one of 40 leaves should still be untouched after a single check")


func test_wind_relocation_starts_a_fresh_transition():
	var field := _settled_field(40)
	var now := LeafLitterField.TRANSITION_DURATION + 0.1
	for i in _WIND_TEST_CHECKS:
		now += LeafLitterField.WIND_DISPERSAL_INTERVAL
		field.advance(LeafLitterField.WIND_DISPERSAL_INTERVAL, now)
		for leaf in field.leaves():
			if leaf.transition_from != leaf.position:
				assert_almost_eq(leaf.transition_start, now, 0.001)
				return
	fail_test("no leaf was ever relocated across %d windy checks" % _WIND_TEST_CHECKS)


## A leaf still visibly falling must not ALSO get wind-relocated on top of
## its own unfinished fall-in transition.
func test_wind_never_touches_a_leaf_still_mid_transition():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.set_wind(Vector2.RIGHT, 1.0)
	# Advance past several throttle intervals, but never past
	# TRANSITION_DURATION -- the leaf never gets the chance to settle.
	field.advance(0.01, 0.01)
	var leaf: Dictionary = field.leaves()[0]
	assert_eq(leaf.transition_from, Vector2(100, 100 - LeafLitterField.FALL_HEIGHT), "still mid-fall, untouched by wind")


# -- contact dispersion: the player/animal trigger shape --------------------
#
# Mirrors PebbleDispersion's own mass-weighted per-contact roll
# (LiftableStone.try_disperse) -- a footstep/creature brushing a settled
# leaf has a real chance of nudging it, rolled fresh every contact, deter-
# ministic off the leaf's own seed (never engine randf() -- see PixelNoise's
# own doc comment on why). LEAF_EFFECTIVE_MASS_KG is small enough that this
# lands at PebbleDispersion.MAX_DISPERSION_CHANCE_PER_CONTACT in practice
# (see test_a_leaf_is_light_enough_to_hit_the_max_dispersion_chance) --
# real dry litter is light enough that almost any footstep disturbs it.

const PebbleDispersion = preload("res://src/rendering/pebble_dispersion.gd")


func test_a_leaf_is_light_enough_to_hit_the_max_dispersion_chance():
	assert_almost_eq(
		PebbleDispersion.dispersion_chance(LeafLitterField.LEAF_EFFECTIVE_MASS_KG),
		PebbleDispersion.MAX_DISPERSION_CHANCE_PER_CONTACT, 0.001
	)


func test_try_disperse_near_moves_the_nearest_leaf_within_radius():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.advance(1.0, LeafLitterField.TRANSITION_DURATION + 0.1)  # let it settle first
	var moved := false
	for attempt in 50:
		if field.try_disperse_near(Vector2(102, 100), PebbleDispersion.TRIGGER_RADIUS_PX, 10.0 + attempt):
			moved = true
			break
	assert_true(moved, "a leaf this light should disperse within 50 contact rolls")
	assert_ne(field.leaves()[0].position, Vector2(100, 100), "a dispersed leaf must actually move")


func test_try_disperse_near_misses_when_nothing_is_within_radius():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	assert_false(field.try_disperse_near(Vector2(900, 900), PebbleDispersion.TRIGGER_RADIUS_PX, 10.0))
	assert_eq(field.leaves()[0].position, Vector2(100, 100))


func test_try_disperse_near_pushes_the_leaf_away_from_the_walker():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.advance(1.0, LeafLitterField.TRANSITION_DURATION + 0.1)
	for attempt in 50:
		if field.try_disperse_near(Vector2(102, 100), PebbleDispersion.TRIGGER_RADIUS_PX, 10.0 + attempt):
			# The walker stands to the LEFT (x=102 -> leaf at x=100 is to
			# its own left); a push AWAY must move the leaf further left
			# still, mirroring PebbleDispersion.nudge's own "shoved out from
			# underfoot" contract.
			assert_lt(field.leaves()[0].position.x, 100.0)
			return
	fail_test("a leaf this light never dispersed across 50 contact rolls")


func test_wind_does_not_roll_before_its_own_throttle_interval_elapses():
	var field := _settled_field(40)
	var before := _positions(field)
	# _settled_field's own settling advance() call already contributed
	# TRANSITION_DURATION + 0.1 (~1.0) toward the wind accumulator (advance
	# always accumulates delta, whether or not this tick's roll actually
	# fires) -- a small delta here, safely under the remaining headroom to
	# WIND_DISPERSAL_INTERVAL (2.0), proves the interval genuinely gates the
	# roll rather than happening to land past it by coincidence.
	field.advance(0.1, LeafLitterField.TRANSITION_DURATION + 0.2)
	assert_eq(_positions(field), before, "an unelapsed throttle interval must never roll early")
