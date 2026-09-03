extends GutTest

## Prolonged cold as a real DURATION clock (docs/concept/survival.md, "The
## four triggers" -> "Prolonged cold, as a real duration clock").
##
## The warmth meter has tracked is_cold()/is_freezing() from real ambient
## temperature since it was written, and cold has always accelerated fitness
## loss -- but nothing read that signal for SICKNESS, so exposure had no
## memory: warm up and it is as though the afternoon never happened. This is
## the missing piece.
##
## The property that matters, and the one the doc is explicit about: clinical
## hypothermia is a duration effect, not a pass/fail temperature check. That
## is why real wind-chill charts post "time to hypothermia" in MINUTES rather
## than naming a temperature at which you are simply hypothermic.

const ColdExposure = preload("res://src/gameplay/cold_exposure.gd")
const SurvivalMeters = preload("res://src/gameplay/survival_meters.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")


## Steps `seconds` of weather through the clock and reports the exposure left.
func _endure(cold: bool, freezing: bool, seconds: float, from: float = 0.0) -> float:
	var exposure := from
	var step := 1.0
	var elapsed := 0.0
	while elapsed < seconds:
		exposure = ColdExposure.advance(exposure, cold, freezing, step)
		elapsed += step
	return exposure


# -- it is a clock, not a threshold ------------------------------------------


## The whole point. A player who steps into the cold is not hypothermic; a
## player who stays there is.
func test_a_moment_of_cold_is_not_hypothermia():
	assert_lt(
		ColdExposure.advance(0.0, true, false, 5.0),
		ColdExposure.RISK_THRESHOLD,
		"five seconds of cold already counts as exposure"
	)


func test_staying_cold_gets_you_there():
	assert_gte(
		_endure(true, false, ColdExposure.SECONDS_TO_FULL_EXPOSURE),
		ColdExposure.RISK_THRESHOLD
	)


## Being merely COLD and being FREEZING are different stages of the same
## condition, not one rate -- which is how real hypothermia is actually staged.
func test_freezing_takes_you_down_faster_than_merely_cold():
	var seconds := ColdExposure.SECONDS_TO_FULL_EXPOSURE * 0.25
	assert_gt(_endure(true, true, seconds), _endure(true, false, seconds))


func test_a_warm_player_never_accrues_exposure():
	assert_eq(_endure(false, false, ColdExposure.SECONDS_TO_FULL_EXPOSURE * 4.0), 0.0)


# -- and it has a memory -----------------------------------------------------


## Warming up sheds exposure -- standing by a fire is the cure, and it works.
func test_warming_up_sheds_exposure():
	var chilled := _endure(true, false, ColdExposure.SECONDS_TO_FULL_EXPOSURE * 0.5)
	assert_lt(_endure(false, false, 60.0, chilled), chilled)


## ...but not instantly. A body that has been cold for hours does not come
## back the moment you step inside, which is what gives exposure its memory --
## and memory is the entire difference between a debuff and a consequence.
func test_you_do_not_come_back_the_moment_you_step_inside():
	var seconds := ColdExposure.SECONDS_TO_FULL_EXPOSURE * 0.5
	var chilled := _endure(true, false, seconds)
	var rewarmed := _endure(false, false, seconds, chilled)
	assert_gt(rewarmed, 0.0, "half an exposure was undone by the same time spent warm")


func test_exposure_never_leaves_its_range():
	assert_eq(_endure(true, true, ColdExposure.SECONDS_TO_FULL_EXPOSURE * 10.0), 1.0)
	assert_eq(_endure(false, false, ColdExposure.SECONDS_TO_FULL_EXPOSURE * 10.0, 1.0), 0.0)


# -- how long is "prolonged" ------------------------------------------------


## Not an eyeballed number: an ordering against the meter this game already
## measures neglect with. You die of cold in hours and of hunger in weeks, so
## a day of cold has to be far past fatal while a day without food is only
## just the end of the hunger meter (SurvivalMeters.SECONDS_TO_STARVE is one
## whole world day).
func test_cold_takes_you_long_before_hunger_does():
	assert_lt(ColdExposure.SECONDS_TO_FULL_EXPOSURE, SurvivalMeters.SECONDS_TO_STARVE * 0.25)


## ...and long enough that it is weather you have to sit in, not weather you
## walk through. Bracketed from both sides so neither edge can drift silently.
func test_prolonged_means_a_real_part_of_a_day():
	var hours := ColdExposure.SECONDS_TO_FULL_EXPOSURE / (SeasonCycle.SECONDS_PER_DAY / 24.0)
	assert_between(hours, 1.0, 6.0)


# -- what it feeds -----------------------------------------------------------


## Exposure is handed to Sickness.infection_chance as its `exposure_level`, so
## past the staging boundary the risk has to keep RISING with time endured
## rather than switching on at full strength -- there must be no single instant
## at which the player becomes at risk. Expressed against RISK_THRESHOLD rather
## than as bare numbers so retuning the boundary cannot silently invert this.
func test_risk_rises_with_time_endured():
	var early := ColdExposure.infection_exposure(lerpf(ColdExposure.RISK_THRESHOLD, 1.0, 0.2))
	var late := ColdExposure.infection_exposure(lerpf(ColdExposure.RISK_THRESHOLD, 1.0, 0.9))
	assert_gt(late, early)
	assert_between(early, 0.0, 1.0)
	assert_between(late, 0.0, 1.0)


## Through the mild stage there is no roll at all: being chilly is not a small
## chance of hypothermia, it is no chance of hypothermia.
func test_no_risk_at_all_while_merely_chilled():
	assert_eq(ColdExposure.infection_exposure(ColdExposure.RISK_THRESHOLD * 0.5), 0.0)


## The staging boundary has to leave real room on BOTH sides -- a threshold at
## either end would collapse this back into the pass/fail check the doc is
## explicit it must not be.
func test_the_staging_boundary_leaves_room_on_both_sides():
	assert_between(ColdExposure.RISK_THRESHOLD, 0.3, 0.85)


func test_the_sickness_it_causes_is_named():
	assert_ne(ColdExposure.SICKNESS_ID, "")
