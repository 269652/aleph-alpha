extends RefCounted
## Extends hover/interaction sensing range -- docs/concept/wayfinding.md's
## Spyglass item. Reveals nothing not already real; just relaxes
## hover_target_finder.gd's own HOVER_RADIUS_PX gate while equipped.

## Real spotting-scope magnification starts around 20x, which would trivialize
## the hover-tooltip system outright (HOVER_RADIUS_PX=20px * 20 = 400px, well
## past the visible screen). Pinned at a gameplay-legible 4x instead --
## test-pinned below, not eyeballed.
const MAGNIFICATION := 4.0


## The hover-tooltip radius to use, given the real base radius
## (hover_target_finder.gd's own HOVER_RADIUS_PX) and whether a Spyglass is
## currently equipped. Unequipped, the base gate is untouched.
static func effective_hover_radius(base_radius: float, equipped: bool) -> float:
	if equipped:
		return base_radius * MAGNIFICATION
	return base_radius
