extends GutTest

## TunnelSupport.collapse_chance_for: real span-squared bending-stress
## relationship (see docs/concept/geology.md "Collapse: stress grows with
## the square of the span").

const TunnelSupport = preload("res://src/world/tunnel_support.gd")

var support: TunnelSupport


func before_each():
	support = TunnelSupport.new()


func test_collapse_chance_is_zero_below_the_safe_span():
	assert_eq(support.collapse_chance_for(0.0), 0.0)
	assert_eq(support.collapse_chance_for(TunnelSupport.SAFE_SPAN_M), 0.0)
	assert_eq(support.collapse_chance_for(TunnelSupport.SAFE_SPAN_M * 0.5), 0.0)


func test_collapse_chance_grows_past_the_safe_span():
	var a: float = support.collapse_chance_for(TunnelSupport.SAFE_SPAN_M + 1.0)
	var b: float = support.collapse_chance_for(TunnelSupport.SAFE_SPAN_M + 2.0)
	assert_gt(a, 0.0)
	assert_gt(b, a)


## The core real-world claim: bending stress under a beam's own weight
## scales with the SQUARE of the span, not linearly -- so doubling how far
## past the safe span you are should roughly quadruple the chance, not
## double it (while still under the ceiling).
func test_collapse_chance_scales_with_the_square_of_excess_span():
	var one_unit_past: float = support.collapse_chance_for(TunnelSupport.SAFE_SPAN_M + 1.0)
	var two_units_past: float = support.collapse_chance_for(TunnelSupport.SAFE_SPAN_M + 2.0)
	assert_almost_eq(two_units_past, one_unit_past * 4.0, 0.001)


func test_collapse_chance_reaches_its_ceiling_at_the_ceiling_span():
	assert_almost_eq(
		support.collapse_chance_for(TunnelSupport.CEILING_SPAN_M),
		TunnelSupport.MAX_COLLAPSE_CHANCE,
		0.001
	)


func test_collapse_chance_never_exceeds_its_ceiling_beyond_the_ceiling_span():
	assert_almost_eq(
		support.collapse_chance_for(TunnelSupport.CEILING_SPAN_M + 50.0),
		TunnelSupport.MAX_COLLAPSE_CHANCE,
		0.001
	)


func test_collapse_chance_never_negative_for_negative_span():
	assert_eq(support.collapse_chance_for(-5.0), 0.0)
