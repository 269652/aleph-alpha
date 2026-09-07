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


# -- leaves_near -- the PLURAL counterpart nearest_leaf_near never was ------
#
# Bug report: "ants go straight to the next leaf when moving out the mound
# ... they should either explore randomly or follow pheromones." Traced to
# a real, already-named gap (see this file's own docs/concept/soil_fauna.md
# cross-reference): _forage_seed_near_mound/_forage_windfall_near_mound
# already bias their choice among several candidates toward a known-good
# PheromoneField trail (real ant recruitment, not omniscient nearest-only
# selection), but _forage_leaf_near_mound had nothing to bias AMONG --
# nearest_leaf_near only ever reports the single closest leaf. leaves_near
# is that missing plural query, mirroring nearest_leaf_near's own shape and
# radius contract exactly, just collecting every match instead of tracking
# only the best one.

func test_leaves_near_finds_every_leaf_within_radius():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.add_leaf(Vector2(110, 100), "apple", "autumn", 0.0)
	var found := field.leaves_near(Vector2(105, 100), 20.0)
	assert_eq(found.size(), 2)
	var species: Array = found.map(func(leaf): return leaf.species)
	assert_true(species.has("cherry"))
	assert_true(species.has("apple"))


func test_leaves_near_excludes_anything_outside_radius():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.add_leaf(Vector2(500, 500), "apple", "autumn", 0.0)
	var found := field.leaves_near(Vector2(105, 100), 20.0)
	assert_eq(found.size(), 1)
	assert_eq(found[0].species, "cherry")


func test_leaves_near_returns_empty_when_nothing_in_range():
	var field := _field()
	field.add_leaf(Vector2(500, 500), "cherry", "autumn", 0.0)
	assert_eq(field.leaves_near(Vector2.ZERO, 20.0), [])


func test_leaves_near_reports_position_species_and_season_per_leaf():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	var found := field.leaves_near(Vector2(100, 100), 20.0)
	assert_eq(found[0].position, Vector2(100, 100))
	assert_eq(found[0].species, "cherry")
	assert_eq(found[0].season, "autumn")


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


# -- floating on water (docs/concept/leaf_litter.md's own section) ----------
#
# A leaf/blossom that lands on a river flows with the current, gets pushed
# by nearby turbulence, and resists ordinary ground wind far more than dry
# litter (see LeafWaterDrift). Whether a position counts as "on water" at
# all is answered by the injected current probe alone (set_current_probe):
# no probe set, or a probe reporting zero speed, means off-water -- matching
# every existing test above, none of which ever calls set_current_probe, so
# none of this section changes their behaviour.

const LeafWaterDrift = preload("res://src/world/leaf_water_drift.gd")


## Reports the SAME {direction, speed_m_s} everywhere -- for tests that only
## care "is there current here at all", not any real position-dependence.
func _uniform_current(direction: Vector2, speed_m_s: float) -> Callable:
	return func(_position): return {"direction": direction, "speed_m_s": speed_m_s}


func test_a_leaf_added_with_no_probe_set_is_not_on_water():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	assert_false(field.leaves()[0].on_water)


func test_a_leaf_added_where_the_probe_reports_zero_speed_is_not_on_water():
	var field := _field()
	field.set_current_probe(_uniform_current(Vector2.RIGHT, 0.0))
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	assert_false(field.leaves()[0].on_water)


func test_a_leaf_added_where_the_probe_reports_real_speed_is_on_water():
	var field := _field()
	field.set_current_probe(_uniform_current(Vector2.RIGHT, 0.6))
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	assert_true(field.leaves()[0].on_water)


func test_an_on_water_leaf_drifts_downstream_at_the_currents_own_speed():
	var field := _field()
	field.set_current_probe(_uniform_current(Vector2.RIGHT, 0.6))
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.advance(1.0, 1.0)
	var expected_velocity := LeafWaterDrift.velocity_px_s(
		Vector2.RIGHT, 0.6, Vector2.ZERO, 0.0, PackedVector2Array(), Vector2(100, 100)
	)
	var leaf: Dictionary = field.leaves()[0]
	assert_almost_eq(leaf.position.x, 100.0 + expected_velocity.x, 0.01)
	assert_almost_eq(leaf.position.y, 100.0 + expected_velocity.y, 0.01)


func test_an_on_water_leaf_keeps_transition_from_equal_to_position_every_frame():
	# No eased "catch up" cosmetic on a floating leaf -- see LeafWaterDrift's
	# own doc comment on why a continuous glide and an occasional discrete
	# hop cannot share one transition mechanism. The renderer must see an
	# "already arrived" leaf every single frame, or it would visibly lag
	# behind its own real position for up to TRANSITION_DURATION and then
	# snap, repeatedly.
	var field := _field()
	field.set_current_probe(_uniform_current(Vector2.RIGHT, 0.6))
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	for i in 5:
		field.advance(0.2, 0.2 * (i + 1))
		var leaf: Dictionary = field.leaves()[0]
		assert_eq(leaf.transition_from, leaf.position, "frame %d" % i)


func test_an_on_water_leaf_still_decays_its_season_like_any_other():
	var field := _field()
	field.set_current_probe(_uniform_current(Vector2.RIGHT, 0.6))
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.advance(1.0, LeafLitterField.DECAY_TO_FADING_SECONDS + 1.0)
	assert_eq(field.leaves()[0].season, "fading")


func test_an_on_water_leaf_is_never_touched_by_the_discrete_wind_roll():
	# Deterministic, not probabilistic: a continuous drift's own position is
	# fully determined by delta/current, so across many throttled checks it
	# must match the closed-form prediction EXACTLY, never once landing on
	# WindDispersal.leaf_ground_drift's own (much larger, randomised) offset.
	var field := _field()
	field.set_current_probe(_uniform_current(Vector2.RIGHT, 0.6))
	field.add_leaf(Vector2(0, 0), "cherry", "autumn", 0.0)
	field.set_wind(Vector2.RIGHT, 1.0)  # a real, strong wind -- maximises wind-roll chance
	var now := 0.0
	var elapsed := 0.0
	for i in _WIND_TEST_CHECKS:
		now += LeafLitterField.WIND_DISPERSAL_INTERVAL
		elapsed += LeafLitterField.WIND_DISPERSAL_INTERVAL
		field.advance(LeafLitterField.WIND_DISPERSAL_INTERVAL, now)
		var expected_velocity := LeafWaterDrift.velocity_px_s(
			Vector2.RIGHT, 0.6, Vector2.RIGHT, 1.0, PackedVector2Array(), Vector2.ZERO
		)
		var expected_x: float = expected_velocity.x * elapsed
		assert_almost_eq(
			field.leaves()[0].position.x, expected_x, 0.5,
			"check %d: must match pure continuous drift, never a discrete ground-style jump" % i
		)


func test_wind_still_nudges_an_on_water_leaf_a_little_continuously():
	var field := _field()
	field.set_current_probe(_uniform_current(Vector2.RIGHT, 0.6))
	field.add_leaf(Vector2(0, 0), "cherry", "autumn", 0.0)
	field.set_wind(Vector2.RIGHT, 1.0)
	field.advance(1.0, 1.0)

	var without_wind := _field()
	without_wind.set_current_probe(_uniform_current(Vector2.RIGHT, 0.6))
	without_wind.add_leaf(Vector2(0, 0), "cherry", "autumn", 0.0)
	without_wind.advance(1.0, 1.0)

	assert_gt(
		field.leaves()[0].position.x, without_wind.leaves()[0].position.x,
		"a downstream gale should still push a floating leaf a little further than current alone"
	)


func test_turbulence_from_a_nearby_wader_perturbs_an_on_water_leaf():
	var field := _field()
	field.set_current_probe(_uniform_current(Vector2.RIGHT, 0.6))
	field.add_leaf(Vector2(0, 0), "cherry", "autumn", 0.0)
	field.set_nearby_waders(PackedVector2Array([Vector2(0.0, 5.0)]))
	field.advance(1.0, 1.0)

	var without_wader := _field()
	without_wader.set_current_probe(_uniform_current(Vector2.RIGHT, 0.6))
	without_wader.add_leaf(Vector2(0, 0), "cherry", "autumn", 0.0)
	without_wader.advance(1.0, 1.0)

	assert_ne(field.leaves()[0].position.y, without_wader.leaves()[0].position.y)


func test_an_on_water_leaf_stops_floating_once_the_current_it_is_in_stops():
	var field := _field()
	# A Dictionary, not a plain bool: GDScript lambdas capture a local
	# variable by VALUE at the moment they're created, so a bare `var
	# still_flowing := true` reassigned later would never be seen by the
	# already-created closure below -- a Dictionary's CONTENTS, mutated
	# after capture, are visible because the closure captured the container
	# itself, not a copy of what was in it.
	var state := {"flowing": true}
	field.set_current_probe(func(_position):
		return {"direction": Vector2.RIGHT, "speed_m_s": 0.6} if state.flowing else {"direction": Vector2.ZERO, "speed_m_s": 0.0}
	)
	field.add_leaf(Vector2(0, 0), "cherry", "autumn", 0.0)
	field.advance(1.0, 1.0)
	assert_true(field.leaves()[0].on_water, "precondition: started floating")
	var position_when_current_stopped: Vector2 = field.leaves()[0].position

	state.flowing = false
	field.advance(1.0, 2.0)
	assert_false(field.leaves()[0].on_water, "the current it was riding is gone -- falls back to ordinary litter")
	assert_eq(field.leaves()[0].position, position_when_current_stopped, "no current left to drift with")


func test_relocate_leaf_near_re_derives_on_water_at_the_new_position():
	var field := _field()
	field.set_current_probe(func(position): return {"direction": Vector2.RIGHT, "speed_m_s": 0.6} if position.x > 500.0 else {"direction": Vector2.ZERO, "speed_m_s": 0.0})
	field.add_leaf(Vector2(0, 0), "cherry", "autumn", 0.0)
	assert_false(field.leaves()[0].on_water, "precondition: starts on dry land")
	field.relocate_leaf_near(Vector2(0, 0), 10.0, Vector2(600, 0), 1.0)
	assert_true(field.leaves()[0].on_water, "nudged onto the river -- should start floating")


func test_try_disperse_near_re_derives_on_water_at_the_new_position():
	var field := _field()
	field.set_current_probe(func(position): return {"direction": Vector2.RIGHT, "speed_m_s": 0.6} if position.x > 500.0 else {"direction": Vector2.ZERO, "speed_m_s": 0.0})
	field.add_leaf(Vector2(600, 0), "cherry", "autumn", 0.0)
	field.advance(1.0, LeafLitterField.TRANSITION_DURATION + 0.1)
	assert_true(field.leaves()[0].on_water, "precondition: starts on the river")
	for attempt in 50:
		if field.try_disperse_near(Vector2(602, 0), PebbleDispersion.TRIGGER_RADIUS_PX, 10.0 + attempt):
			break
	# Whatever the roll actually did, on_water must reflect the leaf's real
	# FINAL position, never a stale flag from before the nudge.
	assert_eq(field.leaves()[0].on_water, field.leaves()[0].position.x > 500.0)


# -- waterlogging: a floating leaf sinks after a bounded, real-world- -------
# -- grounded duration --------------------------------------------------------
#
# docs/concept/soil_fauna.md's own follow-up to the leaf-litter dirty-
# tracking fix (generation() above) named a real, deliberately-deferred
# finding: an on_water leaf is the ONE case that must always look dirty
# (see test_a_floating_leaf_bumps_the_generation_every_advance_even_with_
# nothing_else_changing above), so a chunk with an actively-floating leaf
# still pays a full MultiMesh rebuild every single frame for as long as
# that leaf keeps floating -- unbounded, since nothing before this made a
# floating leaf ever STOP floating except the current itself drying up.
# Live-measured (a --solo session with the character actually wandering,
# not sitting still): this is not a rare edge case -- rivers act as
# natural walking corridors, and over a ~27-real-minute wandering session
# at least one decorating chunk had a floating leaf 92% of the time.
#
# Real-world grounding: a freshly fallen dry leaf floats at first on
# trapped air and its own waxy cuticle, but progressively absorbs water
# through its cut petiole and stomata (the "leaf conditioning"/leaching
# process stream ecology studies document) and loses buoyancy within
# roughly a day of continuous immersion -- the real mechanism behind why a
# stream's floating litter settles into a benthic "leaf pack" rather than
# drifting forever. MAX_FLOAT_SECONDS bounds how long any ONE leaf can keep
# forcing its chunk to look dirty every frame, the same way LIFETIME bounds
# how long any one leaf lingers at all.

func _floating_field(now := 0.0) -> LeafLitterField:
	var field := _field()
	field.set_current_probe(_uniform_current(Vector2.RIGHT, 0.6))
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", now)
	return field


## Not an eyeballed number -- one real-world day (the low end of the "hours
## to about a day" real waterlogging window cited above), expressed as
## 1/365 of a real year, translated through the SAME real-year ->
## compressed-game-time ratio LIFETIME's own doc comment already uses.
func test_max_float_seconds_is_pinned_to_one_real_world_day_of_compressed_time():
	assert_almost_eq(LeafLitterField.MAX_FLOAT_SECONDS, SeasonCycle.SECONDS_PER_YEAR / 365.0, 0.01)


func test_a_floating_leaf_keeps_floating_before_max_float_seconds_elapses():
	var field := _floating_field()
	field.advance(LeafLitterField.MAX_FLOAT_SECONDS - 1.0, LeafLitterField.MAX_FLOAT_SECONDS - 1.0)
	assert_true(field.leaves()[0].on_water, "not yet waterlogged")


func test_a_floating_leaf_waterlogs_and_sinks_once_max_float_seconds_elapses():
	var field := _floating_field()
	var now := LeafLitterField.MAX_FLOAT_SECONDS + 1.0
	field.advance(now, now)
	var leaf: Dictionary = field.leaves()[0]
	assert_false(leaf.on_water, "waterlogged after MAX_FLOAT_SECONDS -- sinks and rejoins ordinary litter")
	assert_eq(
		leaf.transition_from, leaf.position,
		"settles in place with no pending eased-transition cosmetic, same as the current-stopped sink path"
	)


func test_a_sunk_leaf_no_longer_bumps_the_generation_every_frame():
	var field := _floating_field()
	var now := LeafLitterField.MAX_FLOAT_SECONDS + 1.0
	field.advance(now, now)
	assert_false(field.leaves()[0].on_water, "precondition: sunk")
	var settled := field.generation()
	field.advance(1.0, now + 1.0)
	assert_eq(
		field.generation(), settled,
		"a sunk leaf must stop looking dirty every frame -- the whole point of waterlogging"
	)


func test_relocating_an_already_floating_leaf_does_not_restart_its_floating_clock():
	var field := _floating_field()
	assert_true(field.leaves()[0].on_water, "precondition: floating from the start (t=0)")
	# A lateral nudge mid-water (still onto water) does not un-waterlog a
	# leaf that has already been soaking -- the ORIGINAL floating_since (0)
	# must survive the move, not reset to this relocation's own `now` (10).
	field.relocate_leaf_near(Vector2(100, 100), 50.0, Vector2(150, 100), 10.0)
	assert_true(field.leaves()[0].on_water, "precondition: still on water after the nudge")
	# Past MAX_FLOAT_SECONDS since the ORIGINAL t=0 fall, but well short of
	# MAX_FLOAT_SECONDS since the t=10 relocation -- only sinks here if the
	# clock correctly did NOT reset.
	var probe_time := LeafLitterField.MAX_FLOAT_SECONDS + 3.0
	field.advance(probe_time, probe_time)
	assert_false(
		field.leaves()[0].on_water,
		"must have sunk by now -- the clock started at the original t=0 fall, not the t=10 relocation"
	)


func test_a_leaf_relocated_onto_water_starts_a_fresh_floating_clock():
	var field := _field()
	field.set_current_probe(func(position): return {"direction": Vector2.RIGHT, "speed_m_s": 0.6} if position.x > 500.0 else {"direction": Vector2.ZERO, "speed_m_s": 0.0})
	field.add_leaf(Vector2(0, 0), "cherry", "autumn", 0.0)
	assert_false(field.leaves()[0].on_water, "precondition: starts on dry land")
	# Relocated onto water well after MAX_FLOAT_SECONDS has already elapsed
	# since the original t=0 fall -- if floating_since wrongly stayed at its
	# stale dry-land default instead of resetting here, the very next
	# advance() call would sink it immediately.
	var relocate_time := LeafLitterField.MAX_FLOAT_SECONDS + 100.0
	field.relocate_leaf_near(Vector2(0, 0), 10.0, Vector2(600, 0), relocate_time)
	field.advance(1.0, relocate_time + 1.0)
	assert_true(
		field.leaves()[0].on_water,
		"only 1 second into its own real floating clock -- must still be floating, not sunk"
	)


func test_the_wind_roll_starts_a_fresh_floating_clock_for_a_newly_floating_leaf():
	var field := _settled_field(40)
	# Water covers the whole field now -- any leaf the wind actually blows
	# lands on it immediately, regardless of how far it travelled. Set
	# AFTER _settled_field's own add_leaf calls, so every leaf starts dry
	# (on_water only re-derives when a leaf's position is actually set --
	# see the "on_water" field's own doc comment) and only the wind-roll's
	# own relocation can flip one to floating.
	field.set_current_probe(_uniform_current(Vector2.RIGHT, 0.6))
	var now := LeafLitterField.TRANSITION_DURATION + 0.1
	var landed_on_water := false
	for i in _WIND_TEST_CHECKS:
		now += LeafLitterField.WIND_DISPERSAL_INTERVAL
		field.advance(LeafLitterField.WIND_DISPERSAL_INTERVAL, now)
		for leaf in field.leaves():
			if leaf.on_water:
				landed_on_water = true
				break
		if landed_on_water:
			break
	assert_true(
		landed_on_water,
		"a real wind should eventually blow at least one leaf onto water across %d checks" % _WIND_TEST_CHECKS
	)
	# Confirm the clock just started (this relocation's own `now`), not some
	# stale default -- advancing only a little further must not sink it.
	field.advance(1.0, now + 1.0)
	var still_floating := false
	for leaf in field.leaves():
		if leaf.on_water:
			still_floating = true
	assert_true(
		still_floating,
		"must still be floating shortly after the wind first landed it on water -- its clock just started"
	)


# -- generation: dirty-tracking for the renderer's own refill decision ------
#
# EarthChunkManager.step_leaf_litter used to call LeafLitterRenderer.fill
# unconditionally, every frame, for every decorating chunk -- rebuilding
# that chunk's entire MultiMesh instance buffer even for leaves that are
# fully settled and doing nothing. Measured live (docs/concept/soil_fauna.md
# "FPS regression round 4", on the user's own real long-played save):
# step_leaf_litter's own per-window cost climbed from ~20ms to ~578ms over
# ~19 real minutes as accumulated leaf count climbed to 2,361 -- a genuine,
# growing cost invisible to a short session because leaf litter is never
# persisted across save/load. generation(), bumped only when something
# about this field's RENDERING-relevant state actually changes, lets the
# caller skip the call entirely once a chunk's litter goes idle -- NOT a
# periodic throttle, which step_leaf_litter's own doc comment already
# explicitly rejects for this exact call site ("ANY multi-second sync lag
# here would hide the [leaf fall] animation entirely, not just delay it").

func test_a_fresh_field_starts_at_generation_zero():
	var field := _field()
	assert_eq(field.generation(), 0)


func test_add_leaf_bumps_the_generation():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	assert_eq(field.generation(), 1)


func test_consuming_a_real_leaf_bumps_the_generation():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	var after_add := field.generation()
	field.consume_leaf_at(Vector2(100, 100))
	assert_gt(field.generation(), after_add)


func test_a_missed_consume_does_not_bump_the_generation():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	var after_add := field.generation()
	field.consume_leaf_at(Vector2(900, 900))
	assert_eq(field.generation(), after_add, "nothing actually changed -- a miss must not look dirty")


func test_relocating_a_real_leaf_bumps_the_generation():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	var after_add := field.generation()
	field.relocate_leaf_near(Vector2(100, 100), 20.0, Vector2(140, 100), 1.0)
	assert_gt(field.generation(), after_add)


func test_a_missed_relocate_does_not_bump_the_generation():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	var after_add := field.generation()
	field.relocate_leaf_near(Vector2(900, 900), 20.0, Vector2(940, 900), 1.0)
	assert_eq(field.generation(), after_add)


func test_a_successful_dispersal_bumps_the_generation():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.advance(1.0, LeafLitterField.TRANSITION_DURATION + 0.1)  # settle first
	var before := field.generation()
	var moved := false
	for attempt in 50:
		if field.try_disperse_near(Vector2(102, 100), PebbleDispersion.TRIGGER_RADIUS_PX, 10.0 + attempt):
			moved = true
			break
	assert_true(moved, "precondition: a leaf this light disperses within 50 contact rolls")
	assert_gt(field.generation(), before)


func test_a_missed_dispersal_does_not_bump_the_generation():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	var after_add := field.generation()
	field.try_disperse_near(Vector2(900, 900), PebbleDispersion.TRIGGER_RADIUS_PX, 10.0)
	assert_eq(field.generation(), after_add, "nothing within radius -- must not look dirty")


func test_advancing_with_nothing_to_do_does_not_bump_the_generation():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.advance(1.0, LeafLitterField.TRANSITION_DURATION + 0.1)  # settles; its own bump(s) already done
	var settled := field.generation()
	field.advance(0.016, LeafLitterField.TRANSITION_DURATION + 0.116)
	assert_eq(field.generation(), settled, "a settled leaf doing nothing must never look dirty again")


func test_a_lifetime_prune_bumps_the_generation():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	var before := field.generation()
	field.advance(1.0, LeafLitterField.LIFETIME + 1.0)
	assert_gt(field.generation(), before)


## The renderer NEEDS the settle snap itself pushed once to stay alias-safe
## past WRAP_PERIOD (see transition_from's own doc comment, and
## test_advance_snaps_the_transition_once_its_duration_has_passed above) --
## a dirty-tracking scheme that skipped this bump would silently leave
## stale, un-snapped (non-zero-offset) data sitting in the MultiMesh
## forever once nothing else ever changes about that leaf again.
func test_the_settle_snap_itself_bumps_the_generation_once():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	var mid_fall := field.generation()
	field.advance(1.0, LeafLitterField.TRANSITION_DURATION + 0.5)
	assert_gt(field.generation(), mid_fall, "the settle snap must itself be pushed to the renderer once")


func test_a_decay_tier_transition_bumps_the_generation():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.advance(1.0, LeafLitterField.TRANSITION_DURATION + 0.1)  # settle first
	var before := field.generation()
	field.advance(1.0, LeafLitterField.DECAY_TO_FADING_SECONDS + 1.0)
	assert_gt(field.generation(), before)


func test_remaining_within_the_same_decay_tier_does_not_bump_the_generation_again():
	var field := _field()
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.advance(1.0, LeafLitterField.DECAY_TO_FADING_SECONDS + 1.0)  # crosses into "fading"
	var faded := field.generation()
	field.advance(1.0, LeafLitterField.DECAY_TO_FADING_SECONDS + 2.0)  # still fading, nothing new
	assert_eq(field.generation(), faded, "re-asserting the same season every frame must not look dirty")


func test_a_wind_relocation_bumps_the_generation():
	var field := _settled_field(40)
	var before := field.generation()
	var now := LeafLitterField.TRANSITION_DURATION + 0.1
	var bumped := false
	for i in _WIND_TEST_CHECKS:
		now += LeafLitterField.WIND_DISPERSAL_INTERVAL
		field.advance(LeafLitterField.WIND_DISPERSAL_INTERVAL, now)
		if field.generation() != before:
			bumped = true
			break
	assert_true(bumped, "a real wind-driven relocation must bump the generation")


func test_dead_calm_does_not_bump_the_generation():
	var field := _settled_field(40, Vector2.RIGHT, 0.0)
	var before := field.generation()
	var now := LeafLitterField.TRANSITION_DURATION + 0.1
	for i in _WIND_TEST_CHECKS:
		now += LeafLitterField.WIND_DISPERSAL_INTERVAL
		field.advance(LeafLitterField.WIND_DISPERSAL_INTERVAL, now)
	assert_eq(field.generation(), before, "dead calm must never look dirty")


## A floating leaf's position is driven continuously on the CPU side, every
## single advance() call -- unlike a settled/transitioning leaf, the vertex
## shader never animates it (see _advance_floating_leaf's own doc comment:
## an uncorrected eased transition would show the leaf perpetually chasing a
## target that keeps moving away from it). Dirty-tracking must never let a
## floating leaf go stale, or it would visibly freeze mid-river while the
## simulation keeps moving it underneath the frozen sprite.
func test_a_floating_leaf_bumps_the_generation_every_advance_even_with_nothing_else_changing():
	var field := _field()
	field.set_current_probe(func(_position): return {"direction": Vector2.RIGHT, "speed_m_s": 0.6})
	field.add_leaf(Vector2(0, 0), "cherry", "autumn", 0.0)
	assert_true(field.leaves()[0].on_water, "precondition: this leaf is floating")
	var floating_generation := field.generation()

	field.advance(1.0, 2.0)
	assert_gt(field.generation(), floating_generation, "a floating leaf's own continuous drift must always look dirty")

	var after_first_drift := field.generation()
	field.advance(1.0, 3.0)
	assert_gt(field.generation(), after_first_drift, "...and again on the very next frame, not just once")
