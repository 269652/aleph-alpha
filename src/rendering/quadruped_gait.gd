extends RefCounted

## Two-bone (hip + knee) walk-cycle pose for a quadruped leg (see
## docs/concept/pixel_art_engine.md).
##
## Real ungulates/predators don't shift a rigid leg sideways to walk -- they
## swing it forward/back at the hip and bend at the knee during the lift
## phase. ProceduralAnimalAnimation used to fake a walk by shifting the
## leg-shaped PIXELS of one static image sideways: there was no joint to
## move, which is why "a horse should walk more like a horse" -- the
## silhouette had a leg, but nothing in it ever bent.
##
## DIAGONAL gait: front-left+back-right swing together, front-right+
## back-left swing in the opposite half of the cycle -- the walk/trot
## pattern real quadrupeds actually use, not four legs moving in lockstep.
##
## Pure trig, no nodes: testable without an Image, and reused identically by
## every legged species (only leg_length/thickness differ, from
## AnimalAnatomy -- gait shape is universal, proportions are per-species).

## Phase offset for each of the 4 legs within a 0..1 gait cycle. Front-left
## and back-right move together (phase 0); front-right and back-left are
## exactly half a cycle out of phase -- the diagonal pairing.
const LEG_PHASE := {
	"front_left": 0.0,
	"back_right": 0.0,
	"front_right": 0.5,
	"back_left": 0.5,
}

## How far the hip swings forward/back, in radians.
const STRIDE_AMPLITUDE := 0.55

## Extra knee bend during the lift half of the stride (the leg is off the
## ground and swinging forward, so it tucks up rather than dragging).
const KNEE_LIFT := 0.85


func _init() -> void:
	pass


## The hip joint's angle for `leg` at gait `phase` (0..1, wraps), in radians
## from straight down. Positive swings the leg forward (toward the head end
## of the body).
static func hip_angle(leg: String, phase: float) -> float:
	var t := fposmod(phase + float(LEG_PHASE.get(leg, 0.0)), 1.0)
	return sin(t * TAU) * STRIDE_AMPLITUDE


## The knee's bend relative to the upper leg, in radians. Zero while the leg
## is planted and pushing back (straight, bearing weight) -- otherwise every
## step would read as a limp. Rises only during the forward swing, when the
## foot is lifted clear of the ground and needs to tuck up rather than drag.
static func knee_bend(leg: String, phase: float) -> float:
	var t := fposmod(phase + float(LEG_PHASE.get(leg, 0.0)), 1.0)
	return maxf(0.0, sin(t * TAU)) * KNEE_LIFT
