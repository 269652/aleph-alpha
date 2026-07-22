extends GutTest

const TreeGenome = preload("res://src/gameplay/tree_genome.gd")
const FruitingModel = preload("res://src/world/fruiting_model.gd")

var model


func before_each():
	model = FruitingModel.new()


func _genome(seed_value: int, fruit_yield: float) -> Object:
	var g := TreeGenome.new(seed_value)
	g.fruit_yield = fruit_yield
	return g


func test_state_is_a_dictionary_with_growing_and_ripe_counts():
	var g := _genome(1, 0.8)
	var s = model.state_at(g, 0.0, 0.5)
	assert_true(s.has("growing"))
	assert_true(s.has("ripe"))
	assert_typeof(s["growing"], TYPE_INT)
	assert_typeof(s["ripe"], TYPE_INT)


func test_deterministic_for_same_inputs():
	var g := _genome(7, 0.6)
	var a = model.state_at(g, 100.0, 0.4)
	var b = model.state_at(g, 100.0, 0.4)
	assert_eq(a["growing"], b["growing"])
	assert_eq(a["ripe"], b["ripe"])


func test_crop_cap_scales_with_fruit_yield():
	# Sample ripe over a full cycle and take the peak crop for two yields.
	var low := _genome(3, 0.2)
	var high := _genome(3, 0.9)
	low.maturity_time = 40.0
	high.maturity_time = 40.0
	var peak_low := 0
	var peak_high := 0
	for i in range(0, 200):
		var t = float(i) * 0.5
		peak_low = maxi(peak_low, model.state_at(low, t, 0.5)["ripe"])
		peak_high = maxi(peak_high, model.state_at(high, t, 0.5)["ripe"])
	assert_gt(peak_high, peak_low, "higher fruit_yield yields a larger crop cap")
	assert_lte(peak_high, FruitingModel.MAX_CROP)


func test_warmer_tree_ripens_at_least_as_fast():
	# At a fixed mid time, the warmer tree has ripened at least as much.
	var g := _genome(11, 0.9)
	g.maturity_time = 50.0
	var t = g.maturity_time * 0.4
	var cold = model.state_at(g, t, 0.2)
	var warm = model.state_at(g, t, 0.9)
	assert_gte(warm["ripe"], cold["ripe"])


func test_zero_yield_genome_bears_no_fruit():
	var g := _genome(5, 0.0)
	var total_fallen = 0
	for i in range(0, 100):
		var s = model.state_at(g, float(i), 0.5)
		assert_eq(s["ripe"], 0)
		assert_eq(s["growing"], 0)
	total_fallen = model.fallen_between(g, 0.0, 1000.0, 0.5)
	assert_eq(total_fallen, 0)


func test_fallen_accumulates_over_multiple_cycles():
	var g := _genome(9, 0.8)
	g.maturity_time = 30.0
	var total = model.fallen_between(g, 0.0, 3000.0, 0.6)
	assert_gt(total, g.maturity_time, "many bearing cycles should drop many fruits")


func test_fallen_over_a_span_equals_sum_of_subintervals():
	var g := _genome(4, 0.7)
	g.maturity_time = 30.0
	var whole = model.fallen_between(g, 0.0, 600.0, 0.5)
	var part_a = model.fallen_between(g, 0.0, 300.0, 0.5)
	var part_b = model.fallen_between(g, 300.0, 600.0, 0.5)
	# Continuous cumulative model: additive within rounding tolerance.
	assert_almost_eq(whole, part_a + part_b, 2)
