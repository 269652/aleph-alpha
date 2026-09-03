extends RefCounted

## The trail a wounded animal leaves behind it (docs/concept/olfaction.md,
## "Blood: the trail a wounded animal leaves").
##
## A struck animal runs, and `FlightDistance` makes it run early -- so a hit
## that did not kill outright meant the animal was simply gone, and the hunt
## ended not because the player failed but because the world stopped
## representing what had happened. There was no third state between dead and
## untouched. This is that state.
##
## Holds one animal's own "how far since the last drop" cursor and nothing
## else: WHERE the marks go is the caller's business (EarthChunkManager owns
## the marks, the same way it owns guano), and how much they hurt is
## WoundModel's. This module answers only "does a drop fall here, and what does
## it smell of by now".

const Olfaction = preload("res://src/gameplay/olfaction.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const WoundModel = preload("res://src/gameplay/wound_model.gd")

## How far a lightly wounded animal runs between drops, in world pixels.
##
## Spaced along the GROUND rather than dropped per frame, which is what makes
## this a trail rather than a stain -- and what stops an animal that has
## stopped moving from bleeding a puddle the size of the tile it is standing on
## (test_an_animal_standing_still_does_not_pool_marks). Comfortably over a tile
## so a trail reads as a line of separate marks rather than a painted stripe.
const SPACING_PX := float(TerrainRenderer.TILE_SIZE) * 1.5

## How much closer together a badly wounded animal drops them. The trail itself
## tells you how hard you hit it, which is real tracking rather than a marker
## on a map.
const WORST_SPACING_FRACTION := 0.4

## How long a mark stays followable.
##
## Long enough to outlast the flight that made it -- a trail that expired as
## fast as the animal ran would be useless -- and short enough that following
## one is something you do NOW rather than a permanent annotation on the map.
## Bracketed from both sides by test_a_trail_outlasts_the_flight_that_made_it.
const MARK_LIFETIME_SECONDS := 90.0

## What a drop of blood emits when it is fresh, and what it turns into as it
## goes over. Blood does not simply get quieter with age: it dries and rots,
## which is a different smell with a different meaning -- and is the whole
## reason BLOOD and DECAY are separate molecules (see Olfaction.BLOOD).
const FRESH_BLOOD := 1.0
const AGED_DECAY := 0.8

## How far this animal has run since its last drop, and where it was last
## seen -- the only state a trail carries.
var _since_last_mark := 0.0
var _last_position := Vector2.ZERO
var _has_last_position := false


## Advances this animal's trail by however far it has moved, and reports
## whether a drop falls here.
##
## `wound_stacks` is its open-wound count (see WoundModel): zero leaves nothing
## at all, and a worse wound marks more often.
func step(position: Vector2, wound_stacks: int, _delta: float) -> bool:
	if wound_stacks <= 0:
		_since_last_mark = 0.0
		_last_position = position
		_has_last_position = true
		return false
	if not _has_last_position:
		_last_position = position
		_has_last_position = true
		return false
	_since_last_mark += _last_position.distance_to(position)
	_last_position = position
	if _since_last_mark < spacing_for(wound_stacks):
		return false
	_since_last_mark = 0.0
	return true



## How far this animal runs between drops, given how badly it is wounded.
static func spacing_for(wound_stacks: int) -> float:
	var severity := float(clampi(wound_stacks, 0, WoundModel.MAX_STACKS)) / float(WoundModel.MAX_STACKS)
	return SPACING_PX * lerpf(1.0, WORST_SPACING_FRACTION, severity)


## How fresh a mark laid `seconds` ago still is, 1 at the moment it falls and 0
## once it is no longer worth following.
static func freshness_after(seconds: float) -> float:
	return clampf(1.0 - seconds / MARK_LIFETIME_SECONDS, 0.0, 1.0)


## What a mark of this freshness emits into the shared smells_near field.
##
## Fresh blood is BLOOD; an old mark has dried and begun to rot, so it reads
## increasingly as DECAY -- a scavenger's signal rather than a hunter's.
static func mixture_for(freshness: float) -> Dictionary:
	var fresh := clampf(freshness, 0.0, 1.0)
	return {
		Olfaction.BLOOD: FRESH_BLOOD * fresh,
		Olfaction.DECAY: AGED_DECAY * (1.0 - fresh),
	}
