extends RefCounted

## Picks which ambient action the character preview diorama's hero performs
## next, and for how long -- pure logic (an injected RNG in, an action +
## duration out), kept separate from the Node wiring the same way
## CharacterStroll/LegGaitCycle already are (see docs/concept/
## character_creator_preview_scene.md). Reported live: "make it so that
## the char does random actions like swinging the sword or fishing or
## just staying still then wandering".

enum Action { WANDER, IDLE, SWING, FISH }

## Relative weight per action -- WANDER is the default "just walking
## around" ambient state and stays most common; the other three are
## occasional flavor, not an even 1-in-4 split.
const WEIGHTS := {
	Action.WANDER: 5,
	Action.IDLE: 2,
	Action.SWING: 2,
	Action.FISH: 2,
}

## Matches Player.SWING_DURATION exactly -- a swing has its own fixed real
## animation length regardless of how long this state machine would
## otherwise hold the action for, so it isn't a randomized range like the
## other three actions below.
const SWING_DURATION := 0.2

## How long each action holds, in seconds, before the next one is picked --
## Vector2(min, max), randomized per pick.
const DURATION_RANGE := {
	Action.WANDER: Vector2(3.0, 6.0),
	Action.IDLE: Vector2(1.5, 3.0),
	Action.SWING: Vector2(SWING_DURATION, SWING_DURATION),
	Action.FISH: Vector2(3.0, 5.0),
}


## The next action to perform and how long to hold it (`{"action":
## Action, "duration": float}`), using `rng` for reproducible-if-needed
## randomness -- the same injected-RandomNumberGenerator convention
## CharacterStroll.pick_target already follows.
static func pick_next(rng: RandomNumberGenerator) -> Dictionary:
	var action := _weighted_pick(rng)
	var duration_range: Vector2 = DURATION_RANGE[action]
	var duration := rng.randf_range(duration_range.x, duration_range.y)
	return {"action": action, "duration": duration}


static func _weighted_pick(rng: RandomNumberGenerator) -> Action:
	var total := 0
	for weight in WEIGHTS.values():
		total += weight
	var roll := rng.randi_range(0, total - 1)
	var cumulative := 0
	for action in WEIGHTS:
		cumulative += WEIGHTS[action]
		if roll < cumulative:
			return action
	return Action.WANDER  # unreachable if WEIGHTS is well-formed
