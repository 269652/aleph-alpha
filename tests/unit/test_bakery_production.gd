extends GutTest

## The Bakery (docs/concept/milling_and_baking.md): flour -> bread, the
## second StockConversionProduction instance. Pins its own constants the
## same way test_mill_production.gd pins the Mill's.

const BakeryProduction = preload("res://src/world/bakery_production.gd")


func test_a_bakery_bakes_flour_into_bread_at_its_pinned_cost():
	var bakery := BakeryProduction.new()
	var result := bakery.advance(
		{"input_stock": BakeryProduction.FLOUR_PER_BREAD * 2.0, "progress": 0.0},
		BakeryProduction.BAKE_SECONDS_PER_BREAD, true
	)
	assert_eq(result["output"], 1)
	assert_eq(result["input_stock"], BakeryProduction.FLOUR_PER_BREAD)


func test_baking_costs_whole_units_of_flour():
	assert_gte(BakeryProduction.FLOUR_PER_BREAD, 1.0)
	assert_eq(BakeryProduction.FLOUR_PER_BREAD, floor(BakeryProduction.FLOUR_PER_BREAD))
	assert_gt(BakeryProduction.BAKE_SECONDS_PER_BREAD, 0.0)
