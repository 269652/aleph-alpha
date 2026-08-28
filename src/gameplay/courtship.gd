extends RefCounted

const LifeCycle = preload("res://src/gameplay/life_cycle.gd")
const GroundSlide = preload("res://src/gameplay/ground_slide.gd")
const FlightIrregularity = preload("res://src/gameplay/flight_irregularity.gd")

## Two animals of the same kind noticing each other, dancing, and sometimes
## mating (see docs/concept/ecosystem_dynamics.md's "Courtship, and where
## births come from").
##
## Pure and engine-free, like the rest of the behaviour modules: this decides
## WHO may court, WHERE the dance puts them, and WHETHER it ends in young.
## Spawning the offspring and telling the aggregate population about it is the
## caller's job, exactly as GrazerForaging leaves taking the food to its
## caller.
##
## The point of the dance is that reproduction becomes something the player
## can WATCH rather than a number that quietly goes up: two butterflies spiral
## around each other for a few seconds, and sometimes there is a third one
## afterwards.

## How far apart two animals can be and still notice each other. Deliberately
## short -- courtship should read as two animals that happened to meet, not as
## a pairing arranged across the meadow.
const NOTICE_RADIUS_PX := 40.0

## How long the pair circle each other, and how far apart they orbit.
##
## Long enough that the player can see it happen and short enough that the
## animals get on with their lives; the radius is a couple of body-lengths, so
## the two read as one interacting pair rather than two unrelated sprites.
const DANCE_SECONDS := 4.5
const DANCE_RADIUS_PX := 9.0
const DANCE_RADIUS_M := DANCE_RADIUS_PX / GroundSlide.PX_PER_METER

## How fast a butterfly flies while doing this, in metres per second.
##
## A courtship flight is a display, not an escape: this module's own
## description of it is "a slow wide orbit". A monarch's ordinary cruising
## flight is around 2 m/s (its burst is 5 -- see SpiralFlight.BURST_SPEED_MPS,
## which is what the WHIRL is flown at), so a cruise is what a display flight
## is flown at.
const CRUISE_SPEED_MPS := 2.0

## Turns per second around the partner, DERIVED rather than chosen: a cruising
## flight speed divided by the circumference of the circle actually being
## flown.
##
## This was 0.85, described as "fast enough to read as a flutter", and that
## number was never checked against the speed it implies. At a 9-pixel radius
## -- about 70 cm at this world's scale -- 0.85 turns a second is 3.8 m/s,
## three quarters of a monarch's absolute burst speed, for a manoeuvre this
## file calls slow. Reported as "the dance is overly dramatic".
const DANCE_TURNS_PER_SECOND := CRUISE_SPEED_MPS / (TAU * DANCE_RADIUS_M)

## How far the orbit wanders off a circle, as a fraction of its radius.
##
## The dance used to be drawn as a fixed ellipse, squashed to 0.7 on one axis,
## with the stated reason that "real courtship flights wander as they turn".
## That reason is right and the shape was wrong: an ellipse is still a closed
## figure traced identically every time round, which is what the player was
## looking at when they said the dance is "only a circle". The departure from
## a circle is kept at exactly the magnitude the ellipse asserted -- it is the
## same observation -- but it is now irregular and per-pair (see
## FlightIrregularity), so no two dances trace the same figure and none of
## them traces a repeating one.
const DANCE_RADIUS_SWING := 1.0 - 0.7

## After courting, neither animal courts again for a full day.
##
## This was 40 seconds, which measured as a butterfly added every few seconds
## -- a population explosion wearing a nature documentary's clothes. The brief
## is explicit that this runs on REAL time: "1+ real day to mate, 2+ lay eggs,
## 3+ to hatch and 4-7 days to mature". So the DANCE stays a common, watchable
## thing, and what it leads to does not.
const COOLDOWN_SECONDS := LifeCycle.MATE_SECONDS

## Share of dances that produce young. A meeting is not a pregnancy -- most
## dances are just a dance, which is what keeps courtship a common sight and
## eggs a rare one.
const MATING_CHANCE := 0.25


## Species that perform the courtship DANCE.
##
## Pollinators only. The tight spiralling orbit is a butterfly's courtship
## flight; a bird doing it in a nine-pixel circle reads as a bird glitching in
## place, which is exactly how it was reported ("birds sometimes stall and
## jitter on a spot"). Birds pair off in ways this does not model, so they
## simply do not do this one.
##
## This was already assumed -- an earlier comment in AmbientFlyerRenderer
## claimed "courtship only applies to the pollinators" -- but nothing enforced
## it, which is also how a sparrow ended up with monarch wings. An assumption
## in a comment is not an invariant.
const DANCING_SPECIES := {
	"monarch": true, "swallowtail": true, "blue_morpho": true, "bee": true,
}


static func dances(species: String) -> bool:
	return DANCING_SPECIES.has(species)


## Whether these two species court each other. Same kind only -- a monarch and
## a swallowtail share a meadow, not a lineage -- and only kinds that dance.
static func can_court(species_a: String, species_b: String) -> bool:
	return species_a != "" and species_a == species_b and dances(species_a)


## Whether these two individuals are actually two individuals. Callers scan a
## node group that includes the searcher itself, and a self-pairing would be a
## partner permanently in range.
static func can_pair(id_a: int, id_b: int) -> bool:
	return id_a != id_b


## Which of a pair leads the dance. Both sides compute the same answer from
## the same two ids, so exactly one leads without them having to agree at
## runtime -- there is no message passing between animals here.
static func leads(own_id: int, partner_id: int) -> bool:
	return own_id < partner_id


## Where this animal should sit relative to the dance's centre, `elapsed`
## seconds in. Leader and follower orbit opposite each other, so the pair
## reads as two animals circling rather than one sprite drawn twice.
## Both partners are handed the SAME `seed_value`, so they compute the same
## wandering radius and the same swept angle and stay exactly opposite each
## other -- no message passing, the same property the fixed circle had.
##
## The radius is written r / (1 + k*w) and the angle is the exact integral of
## the rate that implies, for the reason SpiralFlight.converging_orbit spells
## out at length: a flyer holds an AIRSPEED, so on a radius that varies it
## comes round faster where it is tighter, and accumulating that per frame
## instead of integrating it would make the figure depend on frame rate and on
## SimulationLod's step size.
static func dance_offset(elapsed: float, seed_value: int, is_leader: bool) -> Vector2:
	var wander := FlightIrregularity.wobble(elapsed, seed_value)
	var swept := TAU * DANCE_TURNS_PER_SECOND * (
		elapsed + DANCE_RADIUS_SWING * FlightIrregularity.wobble_integral(elapsed, seed_value)
	)
	var angle := swept + FlightIrregularity.phase(seed_value)
	if not is_leader:
		angle += PI
	return Vector2.from_angle(angle) * (DANCE_RADIUS_PX / (1.0 + DANCE_RADIUS_SWING * wander))


## Whether this particular pairing produces young.
##
## Hash-derived rather than rolled, matching how the rest of the world decides
## per-individual outcomes: the same pairing always resolves the same way, so
## nothing depends on how many frames the player happened to watch for.
static func mates(pair_seed: int) -> bool:
	var roll := float(absi(hash(pair_seed)) % 10000) / 10000.0
	return roll < MATING_CHANCE


## A seed that both partners compute identically, so they agree on whether
## they mated without talking to each other.
static func pair_seed(id_a: int, id_b: int, round_index: int) -> int:
	return hash("%d_%d_%d_courtship" % [mini(id_a, id_b), maxi(id_a, id_b), round_index])
