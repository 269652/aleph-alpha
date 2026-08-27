extends GutTest

## When a tree wears which canopy (see docs/concept/seasons.md#winter-stays-
## bare-the-canopy-has-its-own-phenology).
##
## Reported from a world that started in WINTER: pink blossom and green crowns
## standing in a frozen world. Nothing was mis-mapped -- SeasonTransition spends
## the last third of every season turning into the next, so a third of winter
## already reported "turning into spring", and the blossom frame is 2.5x as
## dense a picture as bare branches, so one step of six already reads as pink.
##
## A canopy therefore gets its OWN schedule: bare all winter, blossom briefly
## in early spring, then leaf. The ground keeps SeasonTransition -- a colour
## lerp and a frame replacement do not express the same progress the same way.

const TreePhenology = preload("res://src/world/tree_phenology.gd")
const SeasonTransition = preload("res://src/world/season_transition.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")
const IllustratedTree = preload("res://src/rendering/illustrated_tree.gd")


## The year fraction `within` of the way through `season`.
func _at(season: String, within: float) -> float:
	var count := float(SeasonCycle.SEASONS.size())
	return (float(SeasonCycle.SEASONS.find(season)) + within) / count


## Whether blossom is any part of what is drawn at this moment.
func _shows_blossom(state: Dictionary) -> bool:
	if state.progress <= 0.0:
		return state.from == TreePhenology.BLOSSOM
	return state.from == TreePhenology.BLOSSOM or state.to == TreePhenology.BLOSSOM


# -- winter is bare, all of it -----------------------------------------------

## The report, as a test: a winter world has no blossom in it anywhere.
func test_a_winter_world_shows_no_blossom_at_any_point_in_it():
	for step in 400:
		var state := TreePhenology.canopy_state_at(_at("winter", float(step) / 400.0))
		assert_false(
			_shows_blossom(state),
			"blossom is on screen %d/400 of the way through winter" % step
		)


func test_winter_is_bare_from_end_to_end():
	for step in 400:
		var state := TreePhenology.canopy_state_at(_at("winter", float(step) / 400.0))
		assert_eq(state.from, TreePhenology.BARE, "winter is not bare at %d/400" % step)
		assert_eq(state.progress, 0.0, "winter is turning into something at %d/400" % step)


## Winter's pre-turn is SUPPRESSED, not redirected to a bare->bare blend.
##
## The pre-turn exists so a season arrives already saturated instead of
## swapping on a frame boundary -- but a canopy's spring arrival state IS bare,
## because a real tree in late winter has not moved yet. There is nothing to
## blend toward, and every distinct progress value is a whole tree picture to
## composite and cache (ProceduralTreeSprite), so a bare->bare ramp would cost
## six identical images per species to express a no-op.
func test_the_ground_pre_turns_into_spring_and_the_canopy_does_not():
	var late_winter := _at("winter", 1.0 - SeasonTransition.TURN_FRACTION * 0.5)
	var ground := SeasonTransition.state_at(late_winter)
	assert_eq(ground.from, "winter", "the premise: this moment is late winter")
	assert_eq(ground.to, "spring", "the premise: the ground is already turning")
	assert_gt(ground.progress, 0.0, "the premise: the ground is part way over")

	var canopy := TreePhenology.canopy_state_at(late_winter)
	assert_eq(canopy.from, TreePhenology.BARE)
	assert_eq(canopy.progress, 0.0, "the canopy must not pre-turn out of winter")


# -- blossom is a brief early-spring event -----------------------------------

## Gradual, not a swap: the winter/spring boundary is the one place a hard
## frame change would be most visible, and SeasonTransition exists precisely
## because a wood that changes between one step and the next reads as a bug.
func test_a_tree_comes_INTO_blossom_gradually_across_the_start_of_spring():
	var seen := {}
	for step in 60:
		var within := TreePhenology.OPENING_FRACTION * float(step) / 60.0
		var state := TreePhenology.canopy_state_at(_at("spring", within))
		assert_eq(state.from, TreePhenology.BARE, "opening from the wrong frame")
		assert_eq(state.to, TreePhenology.BLOSSOM, "opening into the wrong frame")
		seen[state.progress] = true
	assert_gte(seen.size(), 4, "blossom snapped on rather than opening")


func test_a_tree_then_stands_in_full_blossom_rather_than_passing_through_it():
	var mid_hold := (TreePhenology.OPENING_FRACTION + TreePhenology.BLOSSOM_FRACTION) * 0.5
	var state := TreePhenology.canopy_state_at(_at("spring", mid_hold))
	assert_eq(state.from, TreePhenology.BLOSSOM)
	assert_eq(state.progress, 0.0, "full bloom is a settled stage, not a mid-turn")


func test_blossom_gives_way_to_leaf_gradually():
	var seen := {}
	for step in 60:
		var within := (
			TreePhenology.BLOSSOM_FRACTION
			+ TreePhenology.LEAF_OUT_FRACTION * float(step) / 60.0
		)
		var state := TreePhenology.canopy_state_at(_at("spring", within))
		assert_eq(state.from, TreePhenology.BLOSSOM, "leafing out of the wrong frame")
		assert_eq(state.to, TreePhenology.LEAF, "leafing into the wrong frame")
		seen[state.progress] = true
	assert_gte(seen.size(), 4, "the petals dropped all at once")


func test_the_rest_of_spring_is_simply_in_leaf():
	var done := TreePhenology.BLOSSOM_FRACTION + TreePhenology.LEAF_OUT_FRACTION
	assert_lt(done, 0.5, "the premise: a tree is in leaf by the middle of spring")
	for step in 60:
		var within := done + (1.0 - done) * float(step) / 60.0
		if within >= 1.0:
			continue
		var state := TreePhenology.canopy_state_at(_at("spring", within))
		assert_eq(state.from, TreePhenology.LEAF, "late spring is not in leaf")
		assert_eq(state.progress, 0.0, "late spring should be settled")


## Spring's own last third used to be the blossom->leaf turn. It is now
## leaf->leaf and must do nothing -- otherwise the tree would leave spring
## mid-change and summer would have to finish it.
func test_springs_own_turn_window_no_longer_changes_anything():
	var state := TreePhenology.canopy_state_at(_at("spring", 0.999))
	assert_eq(state.from, TreePhenology.LEAF)
	assert_eq(state.progress, 0.0)


# -- how long "brief" is, and where the number comes from --------------------

## Derived from real bloom records, not chosen (CLAUDE.md: a tuned value must
## be a tested function, never an eyeballed constant).
func test_the_blossom_window_is_derived_from_real_bloom_records():
	assert_almost_eq(
		TreePhenology.BLOSSOM_FRACTION,
		(TreePhenology.REAL_OPENING_DAYS + TreePhenology.REAL_FULL_BLOOM_DAYS)
			/ TreePhenology.REAL_SPRING_DAYS,
		0.0001,
		"the window must be the real ratio, not a number someone liked"
	)
	assert_almost_eq(
		TreePhenology.LEAF_OUT_FRACTION,
		TreePhenology.REAL_LEAF_OUT_DAYS / TreePhenology.REAL_SPRING_DAYS,
		0.0001
	)


## The in-game clock the fraction lands on: a SeasonCycle year is 48 in-game
## days, so a season is 12 and the blossom window is a little over a day and a
## half of them.
func test_the_window_lands_on_the_worlds_own_clock():
	assert_almost_eq(
		TreePhenology.season_days(),
		SeasonCycle.DAYS_PER_YEAR / float(SeasonCycle.SEASONS.size()),
		0.0001,
		"a season is a quarter of the calendar year, in in-game days"
	)
	assert_almost_eq(
		TreePhenology.blossom_days(),
		TreePhenology.season_days() * TreePhenology.BLOSSOM_FRACTION,
		0.0001
	)
	assert_gt(TreePhenology.blossom_days(), 1.0, "under an in-game day is a flicker")
	assert_lt(TreePhenology.blossom_days(), 2.0, "a fortnight, not a month")


## Brief MEANS brief: shorter than any other seasonal change in the game.
func test_blossom_is_briefer_than_an_ordinary_season_turn():
	assert_lt(
		TreePhenology.BLOSSOM_FRACTION, SeasonTransition.TURN_FRACTION,
		"blossom lasting longer than a season turn is not an event"
	)


# -- nothing snaps -----------------------------------------------------------

## The canopy walks bare -> blossom -> leaf -> turning -> bare and never skips
## one, so no wood can ever change between two frames.
func test_the_canopy_never_skips_a_stage_anywhere_in_the_year():
	var steps := 4000
	var previous := TreePhenology.canopy_position_at(0.0)
	var travelled := 0.0
	for step in range(1, steps + 1):
		var position := TreePhenology.canopy_position_at(float(step) / float(steps))
		var delta := position - previous
		if delta < 0.0:
			delta += float(TreePhenology.STAGE_COUNT)  # the year wrapped round
		assert_lt(delta, 1.0, "the canopy jumped a whole stage at step %d" % step)
		travelled += delta
		previous = position
	assert_almost_eq(
		travelled, float(TreePhenology.STAGE_COUNT), 0.01,
		"a year should be exactly one trip round the four canopy stages"
	)


## Quantised on the SAME steps the ground turns on: every distinct value is a
## whole tree picture to composite and cache.
func test_progress_comes_in_the_same_small_number_of_steps_the_ground_uses():
	var values := {}
	for step in 800:
		values[TreePhenology.canopy_state_at(float(step) / 800.0).progress] = true
	assert_lte(values.size(), SeasonTransition.TURN_STEPS + 1)
	assert_gte(values.size(), 4, "too few steps to read as gradual")


# -- summer and autumn are untouched -----------------------------------------

## Only winter and spring were wrong. Summer and autumn must still turn on
## exactly the schedule the lawn beneath them turns on.
func test_summer_and_autumn_still_turn_on_the_grounds_own_schedule():
	for season in ["summer", "autumn"]:
		for step in 100:
			var year_fraction := _at(season, float(step) / 100.0)
			var ground := SeasonTransition.state_at(year_fraction)
			var canopy := TreePhenology.canopy_state_at(year_fraction)
			assert_almost_eq(
				float(canopy.progress), float(ground.progress), 0.0001,
				"%s %d/100 turns at a different rate from the ground" % [season, step]
			)
			if ground.progress > 0.0:
				assert_eq(canopy.from, ground.from, "%s turns out of the wrong frame" % season)
				assert_eq(canopy.to, ground.to, "%s turns into the wrong frame" % season)


# -- the stages are the sheet ------------------------------------------------

## A stage index and a canopy frame index are the same number. Pinned because
## it is otherwise exactly the kind of coincidence that silently rots.
func test_a_stage_index_is_the_canopy_frame_index_of_the_same_name():
	var trees := IllustratedTree.new()
	var frames := trees.canopy_frames_for("cherry")
	assert_eq(TreePhenology.CANOPY_KEYS.size(), TreePhenology.STAGE_COUNT)
	assert_eq(frames.size(), TreePhenology.STAGE_COUNT, "the premise: four frames")
	for index in TreePhenology.STAGE_COUNT:
		assert_eq(
			trees.canopy_for("cherry", TreePhenology.CANOPY_KEYS[index]), frames[index],
			"stage %d does not select sheet frame %d" % [index, index]
		)


func test_the_named_stages_are_the_four_keys_in_walking_order():
	assert_eq(
		TreePhenology.CANOPY_KEYS,
		[
			TreePhenology.BARE,
			TreePhenology.BLOSSOM,
			TreePhenology.LEAF,
			TreePhenology.TURNING,
		]
	)


## The shape the renderer already consumes, unchanged -- so this can be dropped
## in wherever SeasonTransition.state_at fed a canopy.
func test_a_canopy_state_is_the_shape_the_renderer_already_consumes():
	var state := TreePhenology.canopy_state_at(0.3)
	assert_true(state.has("from"))
	assert_true(state.has("to"))
	assert_true(state.has("progress"))
	assert_true(SeasonCycle.SEASONS.has(state.from), "from is not a canopy key")
	assert_true(SeasonCycle.SEASONS.has(state.to), "to is not a canopy key")
