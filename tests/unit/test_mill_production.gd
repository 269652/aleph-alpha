extends GutTest

## The Mill (docs/concept/milling_and_baking.md): wheat -> flour, one
## instance of StockConversionProduction with its own pinned constants. The
## constants' RELATIONSHIPS are what the concept doc grounds ("milling is
## fast, baking is a batch"; "wholemeal, not white" -- whole units, no
## hidden loss rate), so they are pinned here rather than left as comments,
## per this project's no-manual-tuning rule.

const MillProduction = preload("res://src/world/mill_production.gd")
const BakeryProduction = preload("res://src/world/bakery_production.gd")


func test_a_mill_grinds_whole_wheat_into_flour_at_its_pinned_cost():
	var mill := MillProduction.new()
	var result := mill.advance(
		{"input_stock": MillProduction.WHEAT_PER_FLOUR * 3.0, "progress": 0.0},
		MillProduction.MILL_SECONDS_PER_FLOUR, true
	)
	assert_eq(result["output"], 1)
	assert_eq(result["input_stock"], MillProduction.WHEAT_PER_FLOUR * 2.0)


func test_milling_costs_whole_units_of_wheat_with_no_hidden_loss_rate():
	assert_gte(MillProduction.WHEAT_PER_FLOUR, 1.0)
	assert_eq(
		MillProduction.WHEAT_PER_FLOUR, floor(MillProduction.WHEAT_PER_FLOUR),
		"a village quern grinds whole kernels into wholemeal -- a whole-unit cost, not a fractional extraction rate"
	)


func test_milling_is_faster_than_baking():
	assert_lt(
		MillProduction.MILL_SECONDS_PER_FLOUR, BakeryProduction.BAKE_SECONDS_PER_BREAD,
		"a quern grinds grain steadily as it arrives; an oven bakes in fired batches"
	)
	assert_gt(MillProduction.MILL_SECONDS_PER_FLOUR, 0.0)
