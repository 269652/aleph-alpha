extends RefCounted

## One mineable vein/deposit of a nonrenewable resource: mining permanently
## depletes it (capped at what's left), but a played-out vein slowly
## regenerates back toward its max over time rather than staying gone forever.

var max_yield: float = 0.0
var remaining_yield: float = 0.0


## Extracts up to amount, capped by what remains. Returns the actual amount
## extracted, which may be less than requested near depletion.
func mine(amount: float) -> float:
	var extracted := minf(amount, remaining_yield)
	remaining_yield -= extracted
	return extracted


func is_depleted() -> bool:
	return remaining_yield <= 0.0


## Slowly restores remaining_yield toward max_yield, clamped so it never
## overshoots (a slow ore vein regen).
func regenerate(delta: float, rate: float) -> void:
	remaining_yield = minf(max_yield, remaining_yield + delta * rate)
