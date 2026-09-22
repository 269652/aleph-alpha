extends RefCounted

## Dodge/dash: a brief invincibility window gated behind a cooldown. The
## caller owns and ticks the two timers themselves (mirrors knockback.gd's
## style of returning plain state snapshots rather than holding it here).
##
## See docs/concept/dodge.md. This module existed, complete and tested, with
## ZERO consumers outside SpeciesBite reading two of its constants -- while
## docs/concept/predator_profiles.md balanced the entire predator roster
## against the verb it describes. The player had no i-frames of any kind.

const SprintCost = preload("res://src/gameplay/sprint_cost.gd")

## How long you are untouchable, and how long you must wait to be again.
##
## Both already here before anything called them, and both load-bearing
## elsewhere: SpeciesBite.BASE_WINDUP_SECONDS is the first (a human simple
## reaction time to a visual stimulus, about a quarter second -- the
## smallest telegraph a player can actually answer) and
## SpeciesBite.LETHAL_WINDUP_SECONDS is the second, so the heaviest bite in
## the game telegraphs for exactly one full cooldown and a player who has
## just answered something else is never killed by a bite they could not.
const INVINCIBLE_DURATION := 0.25
const COOLDOWN_DURATION := 1.5


## How far one dodge carries you, in pixels.
##
## Derived rather than typed: you move at the speed you can already move,
## for exactly as long as you are untouchable. Two things fall out of it and
## both are tests rather than remarks (test_player_dodge.gd) -- it is about
## 1.78 m at this world's play scale, which is what a real evasive dive
## covers, and it is longer than CreatureMarker.ATTACK_RANGE, so a dodge
## begun from inside a bite's reach ends outside it. If that stopped being
## true the verb would be decoration.
##
## Reads Player.SPRINT_SPEED through SprintCost's own restatement of it,
## which is pinned to the real constant by test -- a pure rule module must
## not preload a scene script.
static func distance_px() -> float:
	return SprintCost.sprint_speed_px_per_second() * INVINCIBLE_DURATION


## What one dodge takes out of the legs: exactly the sprint it is
## (docs/concept/survival.md's stamina scope -- traversal spends stamina and
## combat does not, and a dodge is traversal). Never a cheaper way to cross
## ground than running the same distance.
static func stamina_cost() -> float:
	return SprintCost.stamina_for_seconds(INVINCIBLE_DURATION, true)


## Whether a new dodge may be started given the current cooldown timer.
func can_dodge(cooldown_remaining: float) -> bool:
	return cooldown_remaining <= 0.0


## Snapshot of state right after starting a dodge.
func start_dodge() -> Dictionary:
	return {
		"invincible_time_remaining": INVINCIBLE_DURATION,
		"cooldown_remaining": COOLDOWN_DURATION,
	}


## Ticks both timers down by delta, clamped at 0.
func advance(invincible_time_remaining: float, cooldown_remaining: float, delta: float) -> Dictionary:
	return {
		"invincible_time_remaining": maxf(0.0, invincible_time_remaining - delta),
		"cooldown_remaining": maxf(0.0, cooldown_remaining - delta),
	}


## Whether the player is currently within the invincibility window.
func is_invincible(invincible_time_remaining: float) -> bool:
	return invincible_time_remaining > 0.0
