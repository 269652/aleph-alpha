extends RefCounted

const LifeCycle = preload("res://src/gameplay/life_cycle.gd")

## Bird courtship: two eligible birds noticing each other, closing distance
## to a small held gap, and displaying there (both playing the tail-fanned
## `court_frames` pose) before, sometimes, producing young -- see
## docs/concept/ecosystem_dynamics.md's "Courtship, and where births come
## from" and its bird-specific follow-up. Requested directly: "no dancing
## ... wire this all up".
##
## Reuses `Courtship`'s species-agnostic pairing primitives (can_pair/
## pair_seed/mates/leads) exactly as `MammalCourtship` already does for
## land mammals -- only the MOTION and the species GATE are bird-specific,
## per the explicit design note in docs/concept/animal_genetics.md's "do
## not widen DANCING_SPECIES" section: a bird pairing does not spiral-orbit
## the way a butterfly's courtship flight does (`Courtship.dance_offset`),
## because the display itself is a HELD pose (wings spread, tail fanned),
## not a flight figure -- so this is simpler than either existing
## courtship: close to a fixed offset and hold, no orbit math at all.
##
## Pure and engine-free, like every other behaviour module here: this
## decides WHO may court, WHERE the two hold station, and WHETHER it ends
## in young. Actually moving a marker and spawning the offspring stays the
## caller's job (see AmbientFlyerMarker._step_pair_interactions).

## The three AmbientFlyerMarker songbirds -- NOT kingfisher, despite it
## also having real `court` art (IllustratedBirdSprite covers all four):
## a kingfisher is a PiscivoreBirdMarker, an entirely separate class that
## never runs AmbientFlyerMarker._step_pair_interactions at all, so this
## mechanism structurally cannot reach it. Kingfisher courtship (if ever
## built) is PiscivoreBirdMarker's own follow-up, not a gap in this gate.
const DANCING_SPECIES := {
	"sparrow": true, "robin": true, "blackbird": true,
}

## How far apart two birds can be and still notice each other -- matches
## Courtship.NOTICE_RADIUS_PX: the same "two animals that happened to
## meet" scale, not a pairing arranged across the meadow.
const NOTICE_RADIUS_PX := 40.0

## How long the pair holds its display, and how far apart -- a few body
## lengths (IllustratedBirdSprite.BASE_WORLD_WIDTH), so the two read as an
## interacting pair rather than one sprite overlapping another.
const DISPLAY_SECONDS := 4.5
const HOLD_RADIUS_PX := 9.0

## After displaying, neither bird courts again for a full day -- see
## Courtship.COOLDOWN_SECONDS's own reasoning: the display stays a common,
## watchable sight, and what it leads to does not.
const COOLDOWN_SECONDS := LifeCycle.MATE_SECONDS

## Share of displays that produce young.
const MATING_CHANCE := 0.25


static func dances(species: String) -> bool:
	return DANCING_SPECIES.has(species)


## Same kind only.
static func can_court(species_a: String, species_b: String) -> bool:
	return species_a != "" and species_a == species_b and dances(species_a)


## Whether this particular pairing produces young.
static func mates(pair_seed: int) -> bool:
	var roll := float(absi(hash(pair_seed)) % 10000) / 10000.0
	return roll < MATING_CHANCE


## A seed both partners compute identically, so they agree on the mating
## roll without messaging -- mirrors Courtship.pair_seed exactly (a
## different salt string, so the two courtship kinds never collide even
## if the same pair of ids somehow qualified for both in the same round,
## which can't currently happen since a species only ever dances one way).
static func pair_seed(id_a: int, id_b: int, round_index: int) -> int:
	return hash("%d_%d_%d_bird_courtship" % [mini(id_a, id_b), maxi(id_a, id_b), round_index])


## Where this bird should sit relative to the pairing's centre, `elapsed`
## seconds in: moves in a straight LINE from its own actual position at
## the moment the pairing began (`start_offset`) to a HELD point
## `HOLD_RADIUS_PX` out (`target_offset`, opposite the partner's own --
## see AmbientFlyerMarker._begin_bird_court) and then simply stays there
## for the rest of the display. No orbit: unlike a butterfly's courtship
## flight, the display itself is what's being watched, not a flight
## figure.
##
## LINEAR, not eased -- deliberately: `closing_seconds` is meant to be
## derived from FlightTransition.crossing_seconds (gap / airspeed), which
## that function's own doc comment reserves for crossings that really ARE
## linear (as opposed to settling_seconds, for an eased one) -- a constant
## rate over that exact duration means the bird's speed here is always
## precisely its own airspeed, never over it, with no separate ease-peak
## factor to keep in sync.
static func hold_offset(
	elapsed: float, start_offset: Vector2, target_offset: Vector2, closing_seconds: float
) -> Vector2:
	if closing_seconds <= 0.0:
		return target_offset
	var t := clampf(elapsed / closing_seconds, 0.0, 1.0)
	return start_offset.lerp(target_offset, t)
