extends RefCounted

## One frame's step of an easing-out knockback: instead of teleporting the
## full displacement instantly, each step consumes a fraction of whatever
## displacement is still left, proportional to how much of the knockback's
## duration has elapsed. That naturally front-loads the motion (a fast
## initial shove) and tapers smoothly to zero as time runs out -- a slide,
## not a teleport.


## remaining: displacement still left to cover. time_remaining: seconds left
## in the knockback. delta: this frame's time step (clamped to time_remaining
## so an oversized delta can't overshoot). Returns {step, remaining, time_remaining}.
func step(remaining: Vector2, time_remaining: float, delta: float) -> Dictionary:
	if time_remaining <= 0.0 or remaining == Vector2.ZERO:
		return {"step": Vector2.ZERO, "remaining": Vector2.ZERO, "time_remaining": 0.0}

	var clamped_delta := minf(delta, time_remaining)
	var fraction := clamped_delta / time_remaining
	var step_vector := remaining * fraction

	return {
		"step": step_vector,
		"remaining": remaining - step_vector,
		"time_remaining": maxf(0.0, time_remaining - delta),
	}
