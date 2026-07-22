extends RefCounted

## Dodge/dash: a brief invincibility window gated behind a cooldown. The
## caller owns and ticks the two timers themselves (mirrors knockback.gd's
## style of returning plain state snapshots rather than holding it here).

const INVINCIBLE_DURATION := 0.25
const COOLDOWN_DURATION := 1.5


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
