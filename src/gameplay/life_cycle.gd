extends RefCounted

## How long it takes an animal to be conceived, hatch and grow up, in REAL
## time (see docs/concept/ecosystem_dynamics.md's "Courtship, and where births
## come from").
##
## Specified directly: "reproduction + growth should take 7 real days for a
## newborn child to mature... butterflies [need to be watched] 1+ real day to
## mate, 2+ lay eggs, 3+ to hatch and 4-7 days to mature".
##
## ## Why wall-clock, and why so slow
##
## These are real days, not in-game ones, and they are far longer than any
## session. That is deliberate and it is what makes the two-fidelity
## simulation honest. A player who parks in a meadow for an afternoon does not
## get to farm butterflies: they see courtship, and if they came back
## tomorrow they might see eggs. The population work happens where it belongs,
## in the aggregate model that runs over whole regions whether anyone is
## watching or not (see EcosystemSimulation).
##
## Before this, courtship ran on a 40-second cooldown and produced a flying
## adult immediately -- measured adding a butterfly every few seconds, which
## is a population explosion wearing a nature documentary's clothes.

const SECONDS_PER_REAL_DAY := 86400.0

## Stage boundaries, measured from the moment a pair begins courting.
## Ordered, and each is a whole day, because the request was in whole days.
const MATE_SECONDS := 1.0 * SECONDS_PER_REAL_DAY
const EGG_SECONDS := 2.0 * SECONDS_PER_REAL_DAY
const HATCH_SECONDS := 3.0 * SECONDS_PER_REAL_DAY
## "4-7 days to mature" -- the far end, so a newborn takes the full week the
## brief asks for, and the range in between is the juvenile growing (see
## size_scale_at).
const MATURE_SECONDS := 7.0 * SECONDS_PER_REAL_DAY

## Ordered so a stage can be compared with `<` and `>=`, and so
## test_an_animal_never_gets_younger can assert monotonicity directly.
const STAGE_COURTING := 0
const STAGE_MATED := 1
const STAGE_EGG := 2
const STAGE_JUVENILE := 3
const STAGE_ADULT := 4

## How big a just-hatched animal is relative to its adult size. Small enough
## to read as young at a glance, big enough to still be visible at this
## game's zoom.
const HATCHLING_SCALE := 0.45


static func stage_at(seconds: float) -> int:
	if seconds >= MATURE_SECONDS:
		return STAGE_ADULT
	if seconds >= HATCH_SECONDS:
		return STAGE_JUVENILE
	if seconds >= EGG_SECONDS:
		return STAGE_EGG
	if seconds >= MATE_SECONDS:
		return STAGE_MATED
	return STAGE_COURTING


## Size relative to an adult, at a given age. A hatchling starts small and
## grows into its full size across the juvenile stage, so "it grew up" is
## something the player can see rather than a number that flips.
static func size_scale_at(seconds: float) -> float:
	if seconds >= MATURE_SECONDS:
		return 1.0
	if seconds < HATCH_SECONDS:
		return HATCHLING_SCALE
	var grown := (seconds - HATCH_SECONDS) / (MATURE_SECONDS - HATCH_SECONDS)
	return lerpf(HATCHLING_SCALE, 1.0, clampf(grown, 0.0, 1.0))


## Only a grown animal breeds. Without this the young of a watched pair would
## start courting themselves, and a population with no age gate on breeding
## grows without bound however long each individual step takes.
static func can_court_at(age_seconds: float) -> bool:
	return stage_at(age_seconds) == STAGE_ADULT
