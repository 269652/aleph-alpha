extends RefCounted

const GroundSlide = preload("res://src/gameplay/ground_slide.gd")
const SpiralFlight = preload("res://src/gameplay/spiral_flight.gd")
const DnaCrossover = preload("res://src/gameplay/dna_crossover.gd")

## A butterfly's own PERSONALITY, and what it does about the player because of
## it (see docs/concept/ecosystem_dynamics.md's "The butterfly that knows
## you" and docs/concept/dna.md's "Bloodlines").
##
## ## What this is for
##
## Flyers carried no individuality at all before this: a `species` and a
## `wander_seed`, and every monarch in a meadow behaved identically. The
## player asked for butterflies that "dance around a player's head or fly away
## based on personality (dna derived)". The word that matters there is DNA:
## the point is not that some butterflies are bold, it is that boldness is
## INHERITED, so who the player leaves alive changes what the meadow is made
## of.
##
## ## The emergent payoff, which is the reason this is genes and not a hash
##
## Both halves of the loop already existed. Courtship already produces
## offspring (Courtship / AmbientFlyerMarker._finish_courtship), the shipped
## DnaCrossover already crosses two parents' trait dictionaries, and the
## butterfly net is already a real, craftable tool (CaptureTool.NET). Put a
## heritable boldness between them and a player becomes a SELECTION PRESSURE
## without a single line saying so: net the butterflies that come close and
## the shy ones are what is left to breed, so the meadow gets shyer. Nothing
## scripts that. It is arithmetic, and
## test_a_meadow_the_player_nets_the_bold_out_of_grows_shy_over_generations
## measures it happening.
##
## ## Who calls this, honestly
##
## AmbientFlyerMarker calls traits_from_seed (every flyer gets a personality
## at spawn), player_response (every frame a butterfly is near the player) and
## inherit (at the end of a courtship that produced young, which is the path
## that carries a parent's boldness into its child).
##
## One honest gap, named here rather than left to be discovered (a second
## used to be listed here -- netting was once unwired; docs/concept/
## capture_dsl.md's Capture DSL closed that gap, and Player._attempt_net_
## catch now reads THIS trait directly at catch time, not just at flee/dance
## time, so the selection pressure this file exists for is live, not dormant):
##
## - Ambient flyers are not persisted. A chunk's flyers are re-derived from
##   their cells' seeds on load, so a meadow the player has been selecting on
##   reverts to its founding personalities when that chunk unloads. Boldness
##   drifts within a session, not across one. Offspring are not persisted at
##   all -- they never were.
##
## Pure and engine-free like the rest of the behaviour modules: this decides
## WHAT an individual is like and WHAT it wants to do about the player.
## Driving it is AmbientFlyerMarker's job.

## World pixels per real metre -- this project's one yardstick, derived from
## the player's real height (see GroundSlide.PX_PER_METER). Every distance
## below is stated in METRES and converted here.
const PX_PER_METER := GroundSlide.PX_PER_METER

## The trait. One trait, not a vector of five: boldness is the one the player
## actually asked for, it is the one with a behaviour attached, and a trait
## that changes nothing is a save-format liability rather than a feature.
## Named as a string key because that is the shape DnaCrossover crosses (see
## inherit) and the shape tree_genome.gd already established.
const TRAIT_BOLDNESS := "boldness"

## What a flyer with no personality filled in is taken to be -- the
## unremarkable middle. A missing trait must not read as 0.0, which is the
## SHYEST possible animal: every hand-placed butterfly (the character-preview
## diorama, a marker built in a test) would bolt from the player.
const MIDDLING_BOLDNESS := 0.5

## Responses to a player, returned by player_response.
const NONE := "none"
const FLEE := "flee"
const DANCE := "dance"


## Which species have a personality that steers them at all.
##
## The true butterflies -- the SAME roster that already whirls (see
## SpiralFlight.spirals), deliberately read off that module rather than
## re-listed here, because a second copy of "which flyers are butterflies" is
## exactly the kind of silently drifting duplicate this corner of the codebase
## has been bitten by before (see AmbientFlyerRenderer.FLYER_WORLD_SCALE's own
## warning).
##
## A sparrow bolting from the player would be a second, unrelated flight
## response bolted onto a bird that has none, and a bee orbiting a head is not
## a thing bees do. Structural, not a branch: a bee cannot enter this at all.
static func reacts_to_player(species: String) -> bool:
	return SpiralFlight.spirals(species)


# -- the trait vector --------------------------------------------------------

## How many independent halves boldness is averaged from.
##
## TWO, and not as a knob: the sum of two independent uniforms is the
## TRIANGULAR distribution -- peaked in the middle, thin at both ends, and
## bounded to [0, 1] by construction. That is the shape the brief asks for
## ("most butterflies should do neither dramatically; the extremes should be
## noticeable and uncommon"), and it is also the honest shape for a trait that
## really is the average of two contributions, which is exactly what an
## inherited trait is.
##
## Both alternatives were rejected for measurable reasons, pinned by
## test_most_butterflies_are_middling_and_the_extremes_are_rare:
##
## - a single uniform hash (the obvious one, and what every other
##   per-individual roll in this codebase does) makes the extremes exactly as
##   common as the middle -- a meadow where a third of the butterflies bolt
##   and a third mob you;
## - a Gaussian would have to be CLAMPED into [0, 1], and a clamp piles the
##   whole tail up on the endpoint, making 0.0 and 1.0 the two commonest
##   values in the population. That is the opposite of rare extremes.
const BELL_HALVES := 2


## The personality an individual is born with when it had no parents -- the
## adults a meadow is seeded with (see AmbientFlyerRenderer._spawn_species).
##
## Deterministic from `seed_value`, which callers pass as the flyer's own
## `wander_seed`. That seed is itself derived from the flyer's world cell, so
## a butterfly's personality survives a chunk unload/reload without being
## stored anywhere: the butterfly that comes back is the one that left.
static func traits_from_seed(seed_value: int) -> Dictionary:
	return {TRAIT_BOLDNESS: _bell(seed_value, TRAIT_BOLDNESS)}


## This individual's boldness, or the middling default for anything that has
## none. Clamped, because an inherited value can be nudged a hair outside
## [0, 1] by DnaCrossover's mutation and every consumer below assumes a
## fraction.
static func boldness_of(individual: Dictionary) -> float:
	return clampf(float(individual.get(TRAIT_BOLDNESS, MIDDLING_BOLDNESS)), 0.0, 1.0)


## The child of two parents, through the SHIPPED DnaCrossover -- there is
## deliberately no second crossover in this file. This exists only so callers
## do not each have to construct one and know the trait-dictionary shape, and
## so "the flyers use the same genetics as everything else" is a fact about
## one line rather than a claim in a comment.
static func inherit(parent_a: Dictionary, parent_b: Dictionary, child_seed: int) -> Dictionary:
	return DnaCrossover.new().crossover(parent_a, parent_b, child_seed)


static func _bell(seed_value: int, trait_name: String) -> float:
	var total := 0.0
	for half in BELL_HALVES:
		total += _unit(seed_value, trait_name, half)
	return total / float(BELL_HALVES)


## A deterministic fraction in [0, 1), the same hash-derived shape the rest of
## the world uses for per-individual variation rather than RNG state.
static func _unit(seed_value: int, trait_name: String, index: int) -> float:
	var salted := "%d_%s_%d_personality" % [seed_value, trait_name, index]
	return float(absi(hash(salted)) % 10000) / 10000.0


# -- flushing: the shy half --------------------------------------------------

## FLIGHT INITIATION DISTANCE for the shyest possible individual, in metres.
##
## FID is a real, measured quantity in the escape-behaviour literature: how
## close an approaching threat gets before the animal breaks and flies. It is
## the standard field measure of boldness across taxa precisely because bolder
## individuals reliably have shorter ones. Butterfly FIDs are measured in the
## low metres -- a walking human flushes them from a couple of metres out,
## with the shyest species/individuals at the top of that band and habituated
## ones letting you almost touch them.
##
## This constant is that top end, because it is the SHYEST individual's
## endpoint, not the population's average.
const SHYEST_FLUSH_DISTANCE_M := 3.0

## The bold endpoint is ZERO, and that is a claim rather than a convenience:
## bold individuals of many taxa show effectively no flight response to a
## human at all. A butterfly that still bolted at some short range could never
## dance round a player's head, because the head is inside that range -- see
## test_nothing_ever_both_flees_and_dances.
const BOLDEST_FLUSH_DISTANCE_M := 0.0


## How close the player gets before this individual breaks and flies.
##
## Linear between the two measured endpoints. A curve would let the middle of
## the population sit wherever an exponent was chosen to put it, and this file
## has no exponent to justify -- the rarity of dramatic behaviour comes from
## the DISTRIBUTION of boldness (see BELL_HALVES), which is where it belongs,
## not from bending the response.
static func flight_initiation_distance_px(boldness: float) -> float:
	var held := clampf(boldness, 0.0, 1.0)
	var metres := lerpf(SHYEST_FLUSH_DISTANCE_M, BOLDEST_FLUSH_DISTANCE_M, held)
	return metres * PX_PER_METER


## How far it gets before it settles again.
##
## An escape does not stop on the line it started at. In the escape-distance
## literature an animal that flushes at its FID typically puts about that much
## distance again between itself and the threat before it settles, so the
## release distance is FID + distance-fled. It also happens to be the
## hysteresis that stops the flee/don't-flee decision chattering frame to
## frame at the boundary -- but it is not a fudge chosen for that.
const FLEE_RELEASE_FACTOR := 2.0


static func flee_release_distance_px(boldness: float) -> float:
	return flight_initiation_distance_px(boldness) * FLEE_RELEASE_FACTOR


## A butterfly's ordinary cruising speed, m/s. Monarchs cruise around 2 m/s;
## SpiralFlight.BURST_SPEED_MPS already owns the other end of the same
## measurement (the ~5 m/s a butterfly manages flat out).
const CRUISE_SPEED_MPS := 2.0

## How much faster than its own cruise a fleeing butterfly travels.
##
## DERIVED from the two real speeds rather than stated as an absolute, and
## that matters: this world's butterfly cruise is its own stylised number
## (AmbientFlyerRenderer.BUTTERFLY_SPEED), so dropping a literal 5 m/s on top
## of it would read as a teleport. The RATIO is what transfers between the
## real world and a stylised one.
const ESCAPE_SPEED_MULTIPLIER := SpiralFlight.BURST_SPEED_MPS / CRUISE_SPEED_MPS


# -- dancing: the bold half --------------------------------------------------

## The boldness at which a butterfly will come and orbit the player.
##
## DERIVED, not chosen. The dance is a SpiralFlight held at
## SpiralFlight.SPIRAL_RADIUS_M -- a butterfly holds the same distance from a
## thing it is investigating whether that thing is another butterfly or a head
## -- so an individual may only be counted bold enough to dance once its own
## flight initiation distance has fallen BELOW that orbit radius. Anything
## shyer would be fleeing from inside its own dance, and the two behaviours
## would fight every frame.
##
## Inverting flight_initiation_distance_px at SPIRAL_RADIUS_M is what this is.
## With the numbers as they stand it lands near 0.88, which the triangular
## distribution makes roughly one butterfly in forty -- a few per meadow (see
## test_a_meadow_full_of_butterflies_holds_a_few_that_will_dance_at_you).
const DANCE_BOLDNESS_THRESHOLD := (
	1.0 - (SpiralFlight.SPIRAL_RADIUS_M - BOLDEST_FLUSH_DISTANCE_M)
	/ (SHYEST_FLUSH_DISTANCE_M - BOLDEST_FLUSH_DISTANCE_M)
)


static func is_bold_enough_to_dance(boldness: float) -> bool:
	return boldness > DANCE_BOLDNESS_THRESHOLD


## What this individual wants to do about a player `distance_px` away: NONE,
## FLEE or DANCE.
##
## The two reactions are the two tails of ONE continuum, and they can never
## both be live for the same animal (test_nothing_ever_both_flees_and_dances
## walks the whole range to prove it), so the order they are tested in is a
## readability choice rather than a precedence.
##
## The dance's notice radius is SpiralFlight.NOTICE_RADIUS_PX, reused rather
## than re-derived: that constant already IS "how far off a butterfly reacts
## to a passing object", grounded on territorial butterflies launching at
## conspecifics, birds, leaves and thrown pebbles from several metres. A
## person walking through a meadow is exactly such an object.
static func player_response(boldness: float, distance_px: float) -> String:
	if is_bold_enough_to_dance(boldness):
		if distance_px <= SpiralFlight.NOTICE_RADIUS_PX:
			return DANCE
		return NONE
	if distance_px <= flight_initiation_distance_px(boldness):
		return FLEE
	return NONE
