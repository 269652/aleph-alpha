extends GutTest

## StockConversionProduction (docs/concept/milling_and_baking.md, "Production"):
## the generic single-lane form of SagewerkProduction's own continuous,
## stock-fed conversion -- one input stock, one output, a real cost per unit
## and a real seconds-per-unit, advanced as a pure function of elapsed time.
## The Mill (wheat -> flour) and the Bakery (flour -> bread) are two
## instances of this with their own pinned constants (see test_mill_
## production.gd / test_bakery_production.gd); this file pins the shared
## mechanics once.

const StockConversionProduction = preload("res://src/world/stock_conversion_production.gd")

var production: StockConversionProduction


func before_each():
	# 2 units of input per output, 5 seconds of work per output.
	production = StockConversionProduction.new(2.0, 5.0)


func test_no_output_before_one_full_units_worth_of_work():
	var result := production.advance({"input_stock": 10.0, "progress": 0.0}, 4.9, true)
	assert_eq(result["output"], 0)
	assert_eq(result["input_stock"], 10.0, "nothing is consumed until a unit actually completes")
	assert_almost_eq(result["progress"], 4.9, 0.0001, "the work done so far carries over")


func test_one_output_after_one_units_worth_of_work_consumes_the_cost():
	var result := production.advance({"input_stock": 10.0, "progress": 0.0}, 5.0, true)
	assert_eq(result["output"], 1)
	assert_eq(result["input_stock"], 8.0)
	assert_almost_eq(result["progress"], 0.0, 0.0001)


func test_a_long_elapsed_time_yields_several_units_at_once():
	var result := production.advance({"input_stock": 10.0, "progress": 0.0}, 17.0, true)
	assert_eq(result["output"], 3, "17s of work at 5s/unit is three whole units")
	assert_eq(result["input_stock"], 4.0)
	assert_almost_eq(result["progress"], 2.0, 0.0001)


func test_production_stops_when_the_input_runs_out_rather_than_going_negative():
	var result := production.advance({"input_stock": 3.0, "progress": 0.0}, 100.0, true)
	assert_eq(result["output"], 1, "only one unit's worth of input (2 of 3) is actually there")
	assert_eq(result["input_stock"], 1.0)


func test_no_progress_at_all_without_enough_input_for_one_unit():
	var result := production.advance({"input_stock": 1.0, "progress": 0.0}, 100.0, true)
	assert_eq(result["output"], 0)
	assert_almost_eq(result["progress"], 0.0, 0.0001, "work does not accumulate against an empty hopper")


func test_unstaffed_production_sits_idle():
	var result := production.advance({"input_stock": 10.0, "progress": 0.0}, 100.0, false)
	assert_eq(result["output"], 0)
	assert_eq(result["input_stock"], 10.0)
	assert_almost_eq(result["progress"], 0.0, 0.0001)


func test_advance_is_pure_and_never_mutates_its_input_state():
	var state := {"input_stock": 10.0, "progress": 0.0}
	production.advance(state, 50.0, true)
	assert_eq(state["input_stock"], 10.0)
	assert_eq(state["progress"], 0.0)


func test_missing_state_keys_default_to_an_empty_idle_lane():
	var result := production.advance({}, 50.0, true)
	assert_eq(result["output"], 0)
	assert_eq(result["input_stock"], 0.0)
