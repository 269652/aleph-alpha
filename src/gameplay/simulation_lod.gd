extends RefCounted

## How often an ambient creature runs its own logic, by how far it is from the
## player (see docs/concept/ecosystem_dynamics.md's "Variable-fidelity
## simulation").
##
## ## Why this exists
##
## Measured at 1920x1080 with vsync off, once the rendering costs had been
## dealt with (grass blade culling, per-vertex ground tint), the frame stopped
## responding to rendering at all: hiding the water overlay, the tint, every
## entity, every creature or the entire terrain each moved the frame rate by
## nothing -- 34 to 42 fps, all inside run-to-run noise -- and dropping draw
## calls from 204 to 57 did not help. Rendering into a framebuffer with a
## NINTH of the pixels did not help either.
##
## That is what CPU-bound looks like. The remaining cost is script work, it is
## per-creature, and there are a great many creatures: 266 butterflies were
## counted in one meadow, plus the birds, plus the animals. Almost none of
## them are on screen -- the camera frames about 20x11 tiles, while creatures
## live across the 3x3 chunks (96x96 tiles) kept loaded around the player.
##
## So: what the player can see updates every frame, and what they cannot see
## updates as often as it needs to stay believable and no more. The same
## principle as DecorationLod, applied to simulation instead of drawing.
##
## Creatures still keep living out there -- this changes the RATE, never the
## behaviour. Each update is handed the accumulated time since its last one,
## so a butterfly that updates six times a second still ages, forages and
## flies exactly as far as one updating sixty times a second.

## Inside this radius a creature updates every frame. Comfortably larger than
## the half-diagonal of what the camera can show (see
## test_the_full_rate_radius_covers_more_than_the_visible_screen), because a
## creature stepping visibly is far worse than a creature costing a little
## more -- and things just off screen walk on screen a moment later.
const FULL_RATE_RADIUS_PX := 420.0

## How much further out the rate falls away over, and the floor it lands on.
## The cap matters: a creature that stopped updating entirely would be a
## creature that had stopped existing, and this world is supposed to keep
## living while nobody is watching.
const FALLOFF_PX := 900.0
const MAX_INTERVAL_SECONDS := 0.5


## Seconds between updates for a creature `distance_px` from the player.
## Zero means "every frame".
static func update_interval(distance_px: float) -> float:
	if distance_px <= FULL_RATE_RADIUS_PX:
		return 0.0
	var beyond := distance_px - FULL_RATE_RADIUS_PX
	var fraction := clampf(beyond / FALLOFF_PX, 0.0, 1.0)
	# Eased in rather than stepped, so a creature walking toward the player
	# speeds up smoothly instead of visibly changing gear at a threshold --
	# the same reason the flee and caution radii are ramps and not switches.
	return lerpf(1.0 / 30.0, MAX_INTERVAL_SECONDS, fraction)
