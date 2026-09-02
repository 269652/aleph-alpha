extends RefCounted

## Active foraging for land herbivores -- see docs/concept/ecosystem_dynamics.md's
## "Grazing is an act, not an aura".
##
## Until this existed, a hungry horse standing anywhere on a grassland tile
## simply stopped being hungry: EarthChunkManager._graze_by_herbivores ate
## whatever tuft the creature's wander happened to walk over, and
## CreatureMarker._satisfy_needs_in_place reset hunger off the BIOME under
## its feet. Nothing about that was visible, and the animals read as
## wandering scenery rather than as animals making a living.
##
## Two halves, both pure and engine-free so the whole feeding cycle is unit-
## testable headlessly (same split as GroundForageBehavior, which does this
## for a robin working worms):
##
##   1. A DIET -- which of the world's edible entities this animal will walk
##      to, keyed off the diet label CreatureInfo already assigns, with
##      per-species overrides where the label is too coarse.
##   2. A PHASE MACHINE -- seek -> approach -> graze -> seek. It decides only
##      WHEN things happen; actually removing the tuft/fruit/worm from the
##      world is the caller's job (CreatureMarker, via EarthChunkManager's
##      take_* mutators), exactly as GroundForageBehavior splits the robin's
##      strike from the worm's removal.

const PollinatorForaging = preload("res://src/gameplay/pollinator_foraging.gd")
const FoodConsumption = preload("res://src/gameplay/food_consumption.gd")

## The edible entity kinds a land animal can walk to. Each one has both a
## "what's near me" query and a "take it" mutator on EarthChunkManager --
## a food kind the world can show but not remove would be an animal miming
## a meal forever.
const FOOD_GRASS := "grass"
const FOOD_FRUIT := "fruit"
const FOOD_SEED := "seed"
const FOOD_WORM := "worm"
## Food a PERSON put on the ground for this animal (see
## docs/concept/animal_husbandry.md "The approach").
##
## Its own kind rather than a reuse of FOOD_FRUIT, because it is the one kind
## that is NOT part of any species' ordinary diet: an animal crossing a field
## for something it would not normally forage for is exactly what baiting
## means, and it is what lets a plain grazer -- whose whole diet is
## FOOD_GRASS -- be drawn by a carrot at all. Deliberately absent from
## FORAGE_KINDS_BY_DIET below: nothing forages for bait by default, an animal
## only ever arrives at it by SMELL.
const FOOD_BAIT := "bait"

## The fallback "bite": whatever is growing on the tile the animal already
## stands on, with no entity behind it. Not a diet entry -- an animal that can
## see nothing to walk to but is standing on living ground crops that instead
## of starving, which is what biome grazing always was. The difference is that
## it now costs a full head-down bout like any other bite, rather than
## silently zeroing hunger the instant a hungry animal touched a green tile.
const FOOD_UNDERFOOT := "underfoot"

## Blooms are deliberately NOT edible here. They are the pollinators'
## resource and the seed loop's source (see flora.md); letting grazers crop
## them would quietly eat the butterflies' food supply to feed the horses.
## Grazers take the grass between the flowers, which is what they mostly do.

## Default forage by CreatureInfo.DIET_BY_SPECIES label, so a species added
## later inherits a sensible diet instead of silently never foraging.
const FORAGE_KINDS_BY_DIET := {
	"Grazer": [FOOD_GRASS],
	"Omnivore": [FOOD_FRUIT, FOOD_SEED, FOOD_WORM, FOOD_GRASS],
	"Forager": [FOOD_SEED, FOOD_FRUIT],
}

## Species whose real diet the label is too coarse for.
##
## A deer is a mixed feeder rather than a strict grazer: grass and forbs, but
## also windfall fruit and hard mast, which is why deer turn up under apple
## trees and horses don't. It shares the "Grazer" label with the horse
## because that label is also the creature-info panel's user-facing text.
const FORAGE_KINDS_BY_SPECIES := {
	"deer": [FOOD_GRASS, FOOD_FRUIT],
}

## How far a land animal looks for its next bite, in tiles. Between the
## robin's tight feeding territory (GroundForageBehavior.SEARCH_TILES, 10)
## and the bee's commute (PollinatorForaging.FORAGE_SEARCH_TILES, 18): a
## grazing herd works its way across open ground rather than holding one
## square metre, but still only eats what it can see. Comfortably inside the
## 3x3 chunk window EarthChunkManager's *_near queries actually scan.
const SEARCH_TILES := 12.0

## How long one head-down bout lasts, and how long the animal steps between
## bouts. The RATIO is the part that matters and the part that is tested
## (test_a_grazer_spends_most_of_its_day_head_down): real grazers spend the
## bulk of their active day feeding and only walk between mouthfuls, so a
## bout that isn't much longer than the walk reads as snacking.
const GRAZE_SECONDS := 6.0
const REGRAZE_SECONDS := 1.5

## Close enough to have arrived. Shared with the radius at which the world
## already lets a herbivore pick a food item off the ground
## (World._step_herbivore_food_consumption), because "close enough to eat it"
## is one question and two answers would be two bugs.
const ARRIVAL_DISTANCE := FoodConsumption.EAT_RADIUS

## How long a committed approach may run before the animal gives up. A target
## goes stale constantly out there -- another animal got it first, a tree sits
## between, the chunk unloaded -- and CreatureMovementGate can legitimately
## refuse to advance at all. Without this the animal walks at a dead point
## forever, which is exactly what the old stuck-against-a-tree bugs looked like.
const APPROACH_TIMEOUT := 10.0

## Where in the bout the mouthful is actually taken: the middle, so the tuft
## disappears while the muzzle is in it rather than on the frame the head
## comes down or the frame it lifts.
const SWALLOW_FRACTION := 0.5

enum Phase { SEEKING, APPROACHING, GRAZING }

var phase := Phase.SEEKING

var _phase_elapsed := 0.0
## True once this bout's mouthful has been reported, so advance() reports it
## exactly once while the bout keeps running for the animation.
var _swallowed := false


## What `species` will walk to, given the diet label CreatureInfo assigned it.
## Hunters get an empty list -- they feed by catching prey (CreatureBehavior's
## "hunt" intent) and must not also be handed a grazing cycle.
static func forage_kinds(species: String, diet_label: String) -> Array:
	if FORAGE_KINDS_BY_SPECIES.has(species):
		return FORAGE_KINDS_BY_SPECIES[species]
	return FORAGE_KINDS_BY_DIET.get(diet_label, [])


static func eats(species: String, diet_label: String, food_kind: String) -> bool:
	return forage_kinds(species, diet_label).has(food_kind)


## Which of the visible bites this animal should go for.
##
## Delegates to PollinatorForaging.choose_target for the same reason
## GroundForageBehavior.choose_worm does: it is not really about nectar, it is
## "one of the nearest few, scattered per individual". That scatter is why a
## herd standing together spreads over the meadow instead of single-filing
## behind one tuft with only the leader ever eating. Entries carry no
## "nectar" key, which choose_target defaults to available.
static func choose_bite(position: Vector2, candidates: Array, seed_value: int) -> Dictionary:
	return PollinatorForaging.choose_target(position, candidates, [], 0.0, seed_value)


## Whether the animal is willing to commit to a bite right now: between
## bouts, and past the stepping interval.
func can_commit() -> bool:
	return phase == Phase.SEEKING and _phase_elapsed >= REGRAZE_SECONDS


## Commits to a bite the caller has picked. A no-op returning false if the
## animal is mid-bout or hasn't stepped far enough yet, so a caller can just
## offer a target and let this decide.
func begin_approach() -> bool:
	if not can_commit():
		return false
	_enter(Phase.APPROACHING)
	return true


## The animal has reached the bite. Ends the approach on ARRIVAL rather than
## on a timer -- how long the walk takes depends on how far the bite was.
func arrive() -> bool:
	if phase != Phase.APPROACHING:
		return false
	_enter(Phase.GRAZING)
	return true


## Gives up on the current target -- for when the bite is gone by the time
## the animal gets there. Costs the full stepping interval, so an animal that
## whiffs moves on rather than instantly re-targeting the same spot.
func abort() -> void:
	_enter(Phase.SEEKING)


## Advances by `delta`. Returns true exactly once per bout, on the tick the
## mouthful is taken -- the caller should remove the food from the world then.
func advance(delta: float) -> bool:
	_phase_elapsed += delta
	var swallowed := false
	# A single large delta can cross more than one phase boundary, so a
	# transition carries the remainder forward instead of zeroing it. Bounded
	# by the phase count, so it can never spin.
	for _i in Phase.size():
		if phase == Phase.GRAZING and not _swallowed and _phase_elapsed >= GRAZE_SECONDS * SWALLOW_FRACTION:
			_swallowed = true
			swallowed = true
		var duration := _phase_duration()
		if duration <= 0.0 or _phase_elapsed < duration:
			break
		_enter(_phase_after(), _phase_elapsed - duration)
	return swallowed


## Whether the animal is standing with its head down. Drives both the "eat"
## action and the fact that it doesn't move -- a grazing animal is planted.
func is_grazing() -> bool:
	return phase == Phase.GRAZING


func _phase_duration() -> float:
	match phase:
		Phase.APPROACHING:
			return APPROACH_TIMEOUT
		Phase.GRAZING:
			return GRAZE_SECONDS
		_:
			return 0.0


func _phase_after() -> int:
	# A timed-out approach and a finished bout both put the animal back to
	# looking, with a fresh stepping interval to walk out.
	return Phase.SEEKING


func _enter(next_phase: int, carried_elapsed: float = 0.0) -> void:
	phase = next_phase
	_phase_elapsed = carried_elapsed
	_swallowed = false
