extends RefCounted

## The player's experience/level/skill-point track (see concept/progression.md).
## Stateful but pure (no engine deps): holds total XP, current level, and
## unspent skill points; adding XP rolls the level forward and accrues one point
## per level gained. The XP-per-level curve is a test-pinned linear ramp so the
## HUD bar and the level always agree.

## XP needed to go from level 1 to 2; each further level costs XP_STEP more.
const BASE_XP := 20
const XP_STEP := 12
## Skill points granted per level gained.
const POINTS_PER_LEVEL := 1

var total_xp := 0
var level := 1
var unspent_points := 0


## XP required to advance from `for_level` to the next level.
func xp_cost_of_level(for_level: int) -> int:
	return BASE_XP + (for_level - 1) * XP_STEP


## XP required to advance from the current level to the next.
func xp_for_next_level() -> int:
	return xp_cost_of_level(level)


## Total XP accumulated at the start of `target_level` (level 1 == 0).
func _xp_at_level_start(target_level: int) -> int:
	var sum := 0
	for l in range(1, target_level):
		sum += xp_cost_of_level(l)
	return sum


## How far into the current level the player is, in XP.
func xp_into_level() -> int:
	return total_xp - _xp_at_level_start(level)


## Fraction [0,1] of the way to the next level, for the HUD bar.
func progress_fraction() -> float:
	return clampf(float(xp_into_level()) / float(xp_for_next_level()), 0.0, 1.0)


## Adds XP, rolling the level forward across every threshold crossed and
## granting POINTS_PER_LEVEL skill points per level gained. Returns the number
## of levels gained (0 if none) so the caller can react (heal, flash level-up).
func add_xp(amount: int) -> int:
	total_xp += maxi(0, amount)
	var gained := 0
	while xp_into_level() >= xp_for_next_level():
		level += 1
		unspent_points += POINTS_PER_LEVEL
		gained += 1
	return gained


## Spends one skill point (see the skill tree). Returns false if none available.
func spend_point() -> bool:
	return spend_points(1)


## Spends `count` skill points at once (a skill node can cost more than one).
## Returns false and spends nothing if fewer than `count` are available.
func spend_points(count: int) -> bool:
	if count <= 0 or unspent_points < count:
		return false
	unspent_points -= count
	return true
