extends RefCounted

const GroundSlide = preload("res://src/gameplay/ground_slide.gd")

## The small vertical bob a flying body makes once per wingbeat -- asked for
## as "maybe also make them bounce slightly with each wing flap" (see
## docs/concept/ecosystem_dynamics.md's "The wingbeat bounce").
##
## ## Why a flying body bounces at all
##
## Lift is not delivered smoothly. It is generated in PULSES, essentially all
## of it on the downstroke, so over a single beat the force holding the animal
## up swings above and below its weight and the body genuinely rises and falls
## once per beat. In a butterfly, whose beat is slow and whose body is light,
## that undulation is large enough to be most of what its flight LOOKS like.
##
## ## Where the amplitude comes from, and why nothing here was chosen
##
## Model the lift as swinging sinusoidally about body weight:
##
##     lift(t) / m = g * (1 + e * sin(w t)),   w = TAU * wingbeat frequency
##
## then the vertical acceleration is g*e*sin(w t) and integrating twice gives
## a displacement of amplitude
##
##     A = e * g / w^2
##
## `e` is not a tuning knob. A wing cannot pull the body DOWN through its
## stroke, so the lift can dip to zero and no further: e <= 1. Taking e = 1
## makes A the physical CEILING on the bob rather than a guess at where inside
## the range to sit, which is the only defensible place to put it when the
## honest answer ("somewhere below this") is not measurable from the art.
##
## For a monarch -- ~10 beats a second, ~25 mm of body -- that comes out at
## about 2.5 mm, or a fifth of its own body from the bottom of the cycle to
## the top. Which is what a monarch in the air actually looks like.
##
## ## Why the answer is a FRACTION OF THE BODY and not a distance
##
## This world draws its small flyers well above life size. A monarch's real
## 10 cm wingspan is about 1.3 world pixels at GroundSlide.PX_PER_METER; its
## sprite is several times that (ProceduralButterflySprite.WORLD_SIZE). A
## physically exact 2.5 mm bob would therefore be three hundredths of a world
## pixel and would not exist on screen. What transfers into a stylised world
## is the RATIO -- the same reasoning behind
## FlyerPersonality.ESCAPE_SPEED_MULTIPLIER, which carries the real
## burst/cruise ratio rather than a real absolute speed.
##
## ## There is no species gate here, and none is needed
##
## The bob goes as 1 / (frequency^2 x body length). A honeybee beats about 230
## times a second and a house sparrow carries fourteen centimetres of body, so
## both of them fall out of this at an amplitude nothing could draw -- without
## a branch, a list, or an "only butterflies" flag that would go stale the
## next time a species is added. Structural rather than conditional, the same
## way a bee simply cannot enter SpiralFlight.
##
## ## What calls this
##
## AmbientFlyerMarker._animate_wings, and only that. It applies the result to
## the sprite's `offset` -- a DRAW-TIME property -- and never to `position`.
## That distinction is load-bearing rather than stylistic: `position` feeds
## containment, the courtship orbit, the spiral flight, partner-distance
## checks and Y-sorting, and a per-frame bob folded into it would put a
## wobble through all five (pinned by
## test_the_wingbeat_bounce_never_touches_the_flyers_position).

## Real wingbeat frequency (Hz) and real body length (m) per flyer.
##
## Body length is the BODY -- head to abdomen tip -- not the wingspan, because
## that is what the amplitude above is a fraction of and it is also what the
## sprite's own height stands in for at the call site (a butterfly is drawn
## from above with its body running up the canvas).
##
## Frequencies are the ordinary cruising beat, which for the butterflies is
## the slow, deep one everybody recognises; bees and flies are the famous
## high-frequency asynchronous fliers, and small passerines sit in between.
const FLIGHT := {
	# ~10 beats a second on a 25 mm body -- the classic slow monarch flap.
	"monarch": {"wingbeat_hz": 10.0, "body_length_m": 0.025},
	# Bigger wings, slower beat, longer body than a monarch.
	"swallowtail": {"wingbeat_hz": 8.0, "body_length_m": 0.030},
	# The slow deep flapper of the three, which is why it is also the
	# bounciest -- morpho flight is a visible up-and-down.
	"blue_morpho": {"wingbeat_hz": 6.0, "body_length_m": 0.035},
	# Asynchronous flight muscle: a couple of hundred beats a second. This is
	# what makes a bee buzz, and what makes its bob vanish.
	"bee": {"wingbeat_hz": 230.0, "body_length_m": 0.013},
	"fly": {"wingbeat_hz": 200.0, "body_length_m": 0.007},
	# Small passerines beat in the low tens on a body an order of magnitude
	# longer than a butterfly's.
	"sparrow": {"wingbeat_hz": 13.0, "body_length_m": 0.14},
	"robin": {"wingbeat_hz": 11.0, "body_length_m": 0.14},
	"kingfisher": {"wingbeat_hz": 8.0, "body_length_m": 0.17},
}

## What an unlisted flyer is treated as. The monarch, because every flyer this
## file has ever been asked about is either in the table or a butterfly.
const FALLBACK_SPECIES := "monarch"


## How far this species' body rises and falls either side of its flight path,
## as a fraction of its own body length. See the derivation above: this is the
## physical ceiling e = 1, not a chosen fraction of it.
static func amplitude_bodies(species: String) -> float:
	var beat: Dictionary = FLIGHT.get(species, FLIGHT[FALLBACK_SPECIES])
	var omega: float = TAU * float(beat["wingbeat_hz"])
	var metres: float = GroundSlide.GRAVITY_MPS2 / (omega * omega)
	return metres / float(beat["body_length_m"])


## The bob at `elapsed_seconds`, in whatever units `body_px` was given in.
## NEGATIVE is up: screen-up is -Y in this top-down world.
##
## Phase-locked to the WING ANIMATION rather than to the real wingbeat, and
## the difference is worth stating plainly. The sprite's beat is stylised:
## four frames at AmbientFlyerMarker.FLAP_SECONDS_PER_FRAME is under three
## beats a second, where a real monarch does ten. Locking the bob to the real
## frequency would give a body oscillating four times faster than the wings
## driving it -- two motions at once instead of one animal. So the PERIOD
## comes from the animation, which is what the player can see, and the
## AMPLITUDE comes from the physics, which is what the player cannot.
##
## Phase origin is frame 0 of the beat, where the wings are fully spread
## (ProceduralButterflySprite.generate_flap_images) -- the closest thing a
## four-frame cycle has to mid-downstroke. Displacement lags the lift pulse by
## a quarter cycle, which is why this is a plain sine of the cycle rather than
## a peak sitting on top of the frame.
static func bounce_offset(
	species: String,
	elapsed_seconds: float,
	seconds_per_frame: float,
	frame_count: int,
	body_px: float
) -> float:
	# A flyer whose generator gave it no frames has no beat to lock to (see
	# AmbientFlyerMarker._animate_wings' own empty-frames fallback), and a zero
	# frame time is the same statement. Nothing to bob against, so it holds
	# still rather than dividing by zero.
	if frame_count <= 0 or seconds_per_frame <= 0.0:
		return 0.0
	var cycle_seconds := seconds_per_frame * float(frame_count)
	var phase := elapsed_seconds / cycle_seconds
	return -amplitude_bodies(species) * body_px * sin(TAU * phase)
