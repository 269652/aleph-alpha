extends GutTest

## Sims-4-style witty loading tips (see docs/concept/persistence.md's
## "Loading screens" section, LoadingTips). Requested live: "make the
## loading screens use SIMS 4 style loading descriptions (funny witty
## progress lines)." Pure rotation logic, no Node/Control dependency --
## the same "pure model, thin Node" split LoadingSpinner.frame_for_elapsed
## already uses for the identical reason.

const LoadingTips = preload("res://src/ui/loading_tips.gd")


func test_returns_a_real_non_empty_tip_at_zero_elapsed():
	assert_true(LoadingTips.tip_for_elapsed(0.0, 0).length() > 0)


func test_stays_on_the_same_tip_within_one_interval():
	assert_eq(
		LoadingTips.tip_for_elapsed(0.0, 0),
		LoadingTips.tip_for_elapsed(LoadingTips.TIP_INTERVAL_SECONDS - 0.01, 0)
	)


func test_advances_to_the_next_tip_once_the_interval_elapses():
	assert_ne(
		LoadingTips.tip_for_elapsed(0.0, 0),
		LoadingTips.tip_for_elapsed(LoadingTips.TIP_INTERVAL_SECONDS + 0.01, 0)
	)


## A long real load (measured 39-90s+, see this doc's own "Loading
## screens" section) must not error or silently repeat the same tip
## forever once it runs past the end of the pool -- it should wrap.
func test_wraps_around_the_list_rather_than_erroring_past_the_end():
	var far_future := LoadingTips.TIP_INTERVAL_SECONDS * (LoadingTips.TIPS.size() * 3 + 1)
	var tip := LoadingTips.tip_for_elapsed(far_future, 0)
	assert_true(LoadingTips.TIPS.has(tip))


## Different loads should open on a different tip (see tip_for_elapsed's
## own doc comment on why the caller rolls a start offset once, rather
## than always starting the list at index 0 every single time).
func test_a_different_start_offset_opens_on_a_different_tip():
	assert_ne(LoadingTips.tip_for_elapsed(0.0, 0), LoadingTips.tip_for_elapsed(0.0, 1))


func test_start_offset_wraps_too():
	assert_eq(
		LoadingTips.tip_for_elapsed(0.0, LoadingTips.TIPS.size()),
		LoadingTips.tip_for_elapsed(0.0, 0)
	)


## A real, deliberate UX choice, not an eyeballed guess left untested --
## CLAUDE.md: tuned values/thresholds must be tested, never an eyeballed
## comment. Revised (2026-09-10), reported live after actually watching a
## real launch: the original 4.5s read as "it doesn't rotate" on a load
## short enough not to reach even one full interval -- 2.0s is short
## enough that rotation is visible even on a brief load, still long
## enough to read a short line without feeling rushed.
func test_tip_interval_is_a_real_reasonable_reading_duration():
	assert_gt(LoadingTips.TIP_INTERVAL_SECONDS, 1.0)
	assert_lt(LoadingTips.TIP_INTERVAL_SECONDS, 4.0)


func test_every_tip_is_non_empty_and_reasonably_short():
	for tip in LoadingTips.TIPS:
		assert_true(tip.length() > 0)
		# A loading-screen line, not a paragraph -- stays comfortably
		# readable within one TIP_INTERVAL_SECONDS window.
		assert_lt(tip.length(), 120, tip)


## A rotating pool needs real variety, or a long load just loops the same
## handful of lines and the "Sims 4 style" ask falls flat.
func test_has_a_real_pool_not_just_a_couple_of_tips():
	assert_gt(LoadingTips.TIPS.size(), 14)


func test_every_tip_is_unique():
	var seen := {}
	for tip in LoadingTips.TIPS:
		assert_false(seen.has(tip), "duplicate tip: %s" % tip)
		seen[tip] = true


## Requested live: "can you increase the number of tips to 1000?" A flat
## 1000-line literal would be unmaintainable (and, hand-written one at a
## time, would run out of genuinely distinct jokes long before genuinely
## distinct WORDING) -- see _generated_tips's own doc comment for the
## template x subject combinator this drives instead. The hand-curated
## originals stay too, so the real total is comfortably OVER 1000, not
## trimmed down to exactly it.
func test_pool_reaches_at_least_a_thousand_tips():
	assert_gt(LoadingTips.TIPS.size(), 999)


## Every generated (template, subject) combination must be a real,
## non-degenerate sentence -- catches a malformed template (a stray `%s`
## left in, or a missing one so the subject never gets substituted at
## all) that per-item length/uniqueness checks alone wouldn't necessarily
## flag.
func test_generated_tips_have_no_leftover_placeholder_or_missing_substitution():
	for tip in LoadingTips.TIPS:
		assert_false(tip.contains("%s"), "unsubstituted template: %s" % tip)


## The combinator's own arithmetic should be exact and boring -- template
## count times subject count, no silent dedup shrinkage from an
## accidental duplicate template or subject slipping in (that class of
## bug would otherwise only show up as "count is a bit low," easy to miss
## next to the >=1000 threshold above).
func test_generated_tip_count_matches_templates_times_subjects_exactly():
	assert_eq(
		LoadingTips._generated_tips().size(),
		LoadingTips._TEMPLATES.size() * LoadingTips._SUBJECTS.size()
	)


## Confirmed to actually happen while spot-checking real generated output:
## "Making sure the kingfisher haven't wandered off again." -- `_SUBJECTS`
## deliberately mixes singular ("the kingfisher", "karma", "the world
## boss") and plural ("the ants", "the wolves") real nouns, so an
## auxiliary verb that conjugates for the SUBJECT'S number (haven't/
## hasn't, and the same family) can never safely follow `%s` in a
## template -- every template must route around needing one at all (see
## `_TEMPLATES`' own doc comment for how). Pins the class of bug, not just
## the one instance, so a future template addition can't reintroduce it a
## different way.
func test_no_template_uses_a_subject_number_agreeing_auxiliary_verb():
	var hazards := ["haven't", "hasn't", "have wandered", "has wandered"]
	for template in LoadingTips._TEMPLATES:
		for hazard in hazards:
			assert_false(
				template.contains(hazard),
				"'%s' risks singular/plural agreement in: %s" % [hazard, template]
			)
