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
