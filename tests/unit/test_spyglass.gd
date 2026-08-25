extends GutTest

## Spyglass: extends hover/interaction sensing range (see docs/concept/
## wayfinding.md's Spyglass section) by relaxing hover_target_finder.gd's
## own real HOVER_RADIUS_PX gate while equipped -- no new "detection" stat,
## no new reveal, just a wider radius on the same real lookup.

const Spyglass = preload("res://src/gameplay/spyglass.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")


# -- effective_hover_radius: relaxes the real hover gate while equipped -----

func test_equipped_multiplies_base_radius_by_magnification():
	var base_radius := HoverTargetFinder.HOVER_RADIUS_PX
	var expected := base_radius * Spyglass.MAGNIFICATION
	assert_almost_eq(Spyglass.effective_hover_radius(base_radius, true), expected, 0.001)


func test_unequipped_returns_base_radius_unchanged():
	var base_radius := HoverTargetFinder.HOVER_RADIUS_PX
	assert_almost_eq(Spyglass.effective_hover_radius(base_radius, false), base_radius, 0.001)


# -- MAGNIFICATION: the constant's own claimed property -----

func test_magnification_is_greater_than_one():
	assert_gt(Spyglass.MAGNIFICATION, 1.0)
