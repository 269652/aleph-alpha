extends RefCounted

## Forage-coupled mass growth for fish -- see docs/concept/aquatic_foraging.md's
## "Revised (2026-09-07): real per-species diet and forage-coupled mass".
##
## Deliberately NOT MammalGrowth (a land creature grows from a fixed
## newborn fraction to full size over a fixed real-time duration,
## regardless of whether it ever finds food) -- a fish's mass_kg only
## advances on a REAL successful graze (see FishMarker._step_foraging), the
## direct mechanical answer to "can properly forage and grow mass" being
## one connected fact rather than two independent ones.
##
## Pure static functions, no instance state -- called from FishMarker at
## setup and on every successful graze.

## Where a freshly-promoted FishMarker starts: half its species' own adult
## mass (see FishMass). Deliberately NOT MammalGrowth.NEWBORN_SCALE
## territory (a literal fry/fingerling): this game does not model a hatch
## event for fish (FishRenderer.spawn_fish promotes population into
## markers directly -- see docs/concept/fishing.md), so there is no real
## "just born" moment to anchor a tiny starting fraction against the way a
## live mammal birth has one. Starting already half-grown is the honest
## reading of "a fish that exists in the world, not yet fully grown"
## rather than pretending a birth event that isn't modeled.
const JUVENILE_START_FRACTION := 0.5

## How much of a species' own adult mass a single successful meal adds --
## a FRACTION of adult mass, not a flat kg amount, so a small species and a
## large one both take roughly the same NUMBER of good meals to mature,
## proportional to their own real size. The identical species-scaled-by-
## proportion reasoning MammalGrowth already applies to maturation
## DURATION (a mouse and a bear both grow up "quickly" relative to their
## own lifespan, not in the same wall-clock time) -- reused here for meals
## instead of seconds. Chosen so a fish reaches full size in roughly 5 real
## successful grazes (JUVENILE_START_FRACTION's own 0.5 gap / 0.1) --
## generous enough that growing up is something a returning player can
## actually see happen, the same "visible, not just a number that flips"
## standard MammalGrowth's own doc comment already holds itself to.
const GROWTH_PER_MEAL_FRACTION := 0.1


## Where a freshly-promoted fish of this species starts.
static func starting_mass_for(adult_mass_kg: float) -> float:
	return adult_mass_kg * JUVENILE_START_FRACTION


## One real successful graze's worth of growth -- linear toward the species'
## own adult mass, never past it. Monotonic: no starvation-driven shrinkage
## is modeled (no existing hunger/needs system in this codebase currently
## drives mass downward for anything, land creatures included, so this
## doesn't invent a first instance of it for fish alone).
static func feed(current_mass_kg: float, adult_mass_kg: float) -> float:
	return minf(current_mass_kg + adult_mass_kg * GROWTH_PER_MEAL_FRACTION, adult_mass_kg)


## How large a fish should render, as a fraction of its full-grown visual
## size, given its own current and adult mass. Mass scales with the CUBE of
## a linear dimension -- the identical reasoning CreatureMass.
## _mass_from_world_scale already uses in the other direction (deriving a
## mythical species' mass FROM its visual scale); this reuses that same
## real relationship to go the other way, deriving a grown fish's visual
## scale FROM its real mass. A linear mass-to-scale mapping would make a
## young fish look comically flat/thin (the same "distorted... very
## large/small" failure shape this project already hit and fixed once for
## SquashCrushEffect) -- the cube root reads as visibly, believably smaller
## instead.
static func visual_scale_fraction(mass_kg: float, adult_mass_kg: float) -> float:
	if adult_mass_kg <= 0.0:
		return 1.0
	return pow(clampf(mass_kg / adult_mass_kg, 0.0, 1.0), 1.0 / 3.0)
