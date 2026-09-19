extends GutTest

## The Sägewerk's own production formula (see
## docs/concept/timber_construction.md's material-pipeline pillar: a Balken
## costs more log volume and takes longer to shape -- hewing -- than a
## Planke -- riving/sawing). Pure: log stock + staffed + elapsed time in,
## new stock/progress/output out. Mirrors npc_production.gd's own pure
## rate-formula shape.

const SagewerkProduction = preload("res://src/world/sagewerk_production.gd")

var production: SagewerkProduction


func before_each():
	production = SagewerkProduction.new()


func _fresh_state(log_stock: float) -> Dictionary:
	return {"log_stock": log_stock, "beam_progress": 0.0, "plank_progress": 0.0}


func test_an_unstaffed_sagewerk_produces_nothing_no_matter_how_much_stock_it_has():
	var result := production.advance(_fresh_state(1000.0), 1000.0, false)
	assert_eq(result["beam_output"], 0)
	assert_eq(result["plank_output"], 0)
	assert_eq(result["log_stock"], 1000.0, "unstaffed stock should not drain either")


func test_a_staffed_sagewerk_with_no_logs_produces_nothing():
	var result := production.advance(_fresh_state(0.0), 1000.0, true)
	assert_eq(result["beam_output"], 0)
	assert_eq(result["plank_output"], 0)


func test_enough_time_and_logs_produces_a_beam():
	var result := production.advance(
		_fresh_state(SagewerkProduction.LOG_COST_PER_BEAM * 10.0),
		SagewerkProduction.SHAPE_SECONDS_PER_BEAM,
		true
	)
	assert_gt(result["beam_output"], 0)


func test_enough_time_and_logs_produces_a_plank():
	var result := production.advance(
		_fresh_state(SagewerkProduction.LOG_COST_PER_PLANK * 10.0),
		SagewerkProduction.SHAPE_SECONDS_PER_PLANK,
		true
	)
	assert_gt(result["plank_output"], 0)


## Real-world grounding: hewing a Balken costs more log volume than riving a
## Planke -- see docs/concept/timber_construction.md's "Hewing vs. riving".
func test_a_beam_costs_more_log_volume_than_a_plank():
	assert_gt(SagewerkProduction.LOG_COST_PER_BEAM, SagewerkProduction.LOG_COST_PER_PLANK)


## Real-world grounding: hewing is slow, skilled work; riving/sawing is
## faster -- same doc section.
func test_a_beam_takes_longer_to_shape_than_a_plank():
	assert_gt(SagewerkProduction.SHAPE_SECONDS_PER_BEAM, SagewerkProduction.SHAPE_SECONDS_PER_PLANK)


func test_producing_a_beam_consumes_logs():
	var before := SagewerkProduction.LOG_COST_PER_BEAM * 5.0
	var result := production.advance(_fresh_state(before), SagewerkProduction.SHAPE_SECONDS_PER_BEAM, true)
	assert_lt(result["log_stock"], before)


func test_running_out_of_logs_mid_shaping_stops_production():
	# Not even enough log stock for one Planke (the cheaper of the two) --
	# plenty of elapsed time, but the mill cannot shape wood it does not have.
	var scant_stock: float = minf(SagewerkProduction.LOG_COST_PER_BEAM, SagewerkProduction.LOG_COST_PER_PLANK) * 0.5
	var result := production.advance(_fresh_state(scant_stock), SagewerkProduction.SHAPE_SECONDS_PER_BEAM * 10.0, true)
	assert_eq(result["beam_output"], 0)
	assert_eq(result["plank_output"], 0)
	assert_almost_eq(result["log_stock"], scant_stock, 0.001)


## A long, unattended elapsed jump with ample stock produces multiple units,
## not just one -- so a Sägewerk left running genuinely keeps working, not
## capped at one output per call.
func test_a_long_staffed_run_with_ample_stock_produces_multiple_beams():
	var result := production.advance(
		_fresh_state(SagewerkProduction.LOG_COST_PER_BEAM * 100.0),
		SagewerkProduction.SHAPE_SECONDS_PER_BEAM * 5.5,
		true
	)
	assert_gte(result["beam_output"], 5)


func test_progress_carries_over_between_calls_rather_than_resetting():
	var half_time := SagewerkProduction.SHAPE_SECONDS_PER_PLANK * 0.5
	var first := production.advance(_fresh_state(1000.0), half_time, true)
	var second := production.advance(first, half_time, true)
	assert_gt(second["plank_output"], 0, "two half-ticks should add up to a full shape")


func test_beams_and_planks_shape_concurrently_from_the_same_stock():
	var result := production.advance(
		_fresh_state(1000.0),
		maxf(SagewerkProduction.SHAPE_SECONDS_PER_BEAM, SagewerkProduction.SHAPE_SECONDS_PER_PLANK),
		true
	)
	assert_gt(result["beam_output"], 0)
	assert_gt(result["plank_output"], 0)


# -- the beam has first call on the woodpile --------------------------------
# Reported live: "it only produced 6xLogs but no beams". Hewing and riving
# draw from ONE pile, and riving is three times cheaper per log and faster
# per piece -- so the plank lane emptied the pile continuously and the pile
# almost never held the three logs a beam needs for the eight seconds it
# needs them. A mill on a steady trickle of timber produced planks and never
# a single beam, which is what the village's own construction needs least.

## Ticked the way a real mill is ticked -- one frame at a time, not one
## whole shaping time in a single call. That is where the starvation lives:
## the plank lane finishes every 3 seconds and takes a log with it, so the
## pile drops below a beam's cost long before the beam's 8 seconds are up,
## and the beam lane's progress is frozen from then on.
func _run_in_frames(state: Dictionary, seconds: float) -> Dictionary:
	var frame := 1.0 / 60.0
	var beams := 0
	var planks := 0
	var elapsed := 0.0
	var current := state
	while elapsed < seconds:
		current = production.advance(current, frame, true)
		beams += int(current["beam_output"])
		planks += int(current["plank_output"])
		elapsed += frame
	current["beam_output"] = beams
	current["plank_output"] = planks
	return current


## A pile just big enough for one beam is spent on the beam, not rived away
## underneath it.
func test_a_thin_woodpile_still_squares_its_beam():
	var result := _run_in_frames(
		_fresh_state(SagewerkProduction.LOG_COST_PER_BEAM),
		SagewerkProduction.SHAPE_SECONDS_PER_BEAM * 2.0
	)
	assert_eq(result["beam_output"], 1, "the beam has first call on the pile")


## And the plank lane rives what is really left over, so a mill with plenty
## still does both (the concurrency this file already pins).
func test_a_deep_woodpile_still_rives_planks_alongside():
	var result := production.advance(
		_fresh_state(1000.0),
		maxf(SagewerkProduction.SHAPE_SECONDS_PER_BEAM, SagewerkProduction.SHAPE_SECONDS_PER_PLANK),
		true
	)
	assert_gt(result["beam_output"], 0)
	assert_gt(result["plank_output"], 0)


## A trickle that never reaches a beam's cost is still rived rather than
## hoarded: the reserve holds logs for work the beam lane can really finish,
## not against a beam it will never start.
func test_a_pile_too_small_for_a_beam_is_still_rived():
	var result := _run_in_frames(
		_fresh_state(SagewerkProduction.LOG_COST_PER_BEAM - 1.0),
		SagewerkProduction.SHAPE_SECONDS_PER_PLANK * 2.0
	)
	assert_eq(result["beam_output"], 0, "there was never enough for a beam")
	assert_gt(result["plank_output"], 0, "and the mill does not simply sit on it")
