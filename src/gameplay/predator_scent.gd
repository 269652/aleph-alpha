extends RefCounted

## A predator that hunts you by nose (docs/concept/olfaction.md, "The wind
## carries it").
##
## The wind already made the PLAYER smellable, and prey already flees earlier
## when the player is upwind of it -- which made the wind a TOOL, something the
## player manages in order to get close to a deer. This is the other edge of
## the same blade: a wolf downwind of you knows you are there long before you
## can see it, so the wind is an exposure as well as an advantage. Nothing
## about the mechanic is new; this is the missing consumer.
##
## Pure and engine-free. Whether a given predator is actually downwind is
## `WindScent.effective_distance_tiles`' job -- the SAME call the prey side
## makes, so the two halves cannot disagree about which way the wind blows.

const Olfaction = preload("res://src/gameplay/olfaction.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

## How far a hunting nose reaches for a player, in tiles, measured in
## WIND-EFFECTIVE distance rather than true distance.
##
## The mechanic is dead unless the nose beats the eyes: a predator that could
## only smell you as far as it can see you would behave exactly as before. So
## this is bracketed from below against `CreatureMarker.SENSE_RADIUS` (the
## radius creatures acquire threats at) and from above against
## `Olfaction.MAX_RANGE_TILES` (the scent field's own reach), rather than
## picked -- test_a_nose_reaches_further_than_an_eye and
## test_a_nose_does_not_reach_across_the_world.
const HUNT_RANGE_TILES := 14.0

## How strongly a species must want MUSK before it counts as hunting by nose.
## Above zero rather than at it: every animal with a nose registers musk, and
## most of them read it as a warning. What separates a hunter is that it reads
## musk as a MEAL, which in Olfaction's terms is a real positive response.
const MIN_MUSK_RESPONSE := 0.5


## Whether this species hunts by smell at all.
##
## Read off the species' own receptor row rather than from a second list of
## hunters: what makes an animal a scent hunter is that it is drawn to musk,
## and Olfaction already knows that for every species in the roster (including
## ones added later, which inherit their diet's nose).
static func hunts_by_scent(species: String) -> bool:
	var receptors := Olfaction.receptors_for(species)
	if receptors.is_empty():
		return false
	var response: Dictionary = receptors.get("response", {})
	return float(response.get(Olfaction.MUSK, 0.0)) >= MIN_MUSK_RESPONSE


## Whether a predator of `species` picks the player up at `effective_tiles` --
## the wind-effective distance from WindScent.effective_distance_tiles, NOT the
## true one, which is what makes standing downwind of a wolf dangerous at a gap
## that is safe upwind of it.
static func acquires(species: String, effective_tiles: float) -> bool:
	if not hunts_by_scent(species):
		return false
	return effective_tiles <= HUNT_RANGE_TILES
