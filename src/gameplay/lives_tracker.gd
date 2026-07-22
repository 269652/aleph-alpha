extends RefCounted

## Nine-lives permadeath tracker: lose_life() ticks down a life; once
## lives_remaining hits 0 the character is permanently dead until a soul
## stone (add_life) revives them.

const DEFAULT_LIVES := 9

var lives_remaining: int


func _init(starting_lives: int = DEFAULT_LIVES) -> void:
	lives_remaining = starting_lives


## Decrements lives_remaining (never below 0). Returns true if the
## character is still alive afterward, false if that was the final life.
func lose_life() -> bool:
	lives_remaining = maxi(0, lives_remaining - 1)
	return lives_remaining > 0


func is_permanently_dead() -> bool:
	return lives_remaining <= 0


func add_life(amount: int = 1) -> void:
	lives_remaining += amount
