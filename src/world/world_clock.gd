extends RefCounted

## Length of one in-game day, in real seconds.
const DAY_LENGTH_SECONDS := 600.0

## Normalized time of day in [0.0, 1.0): 0.0 = midnight, 0.5 = noon.
var time_of_day := 0.0
## Number of full in-game days elapsed.
var day := 0


## Advances the clock by delta_seconds, wrapping time_of_day and incrementing
## day for each full day boundary crossed.
func advance(delta_seconds: float) -> void:
	time_of_day += delta_seconds / DAY_LENGTH_SECONDS
	while time_of_day >= 1.0:
		time_of_day -= 1.0
		day += 1
