extends RefCounted

## Technological Era Progression (docs/concept/eras.md), scoped down to a
## simple linear era-advancement state machine: NOT the full multi-planet/
## reincarnation system described there, just "cumulative progress crosses a
## threshold -> advance to the next era, capped at the last one".

## Ordered eras with the cumulative progress required to advance past each
## one into the next. The final era's progress_required is unused for
## advancement (there is no next era) but kept for a consistent shape.
const _ERAS := [
	{"name": "medieval", "progress_required": 100.0},
	{"name": "industrial_revolution", "progress_required": 300.0},
	{"name": "ai_boom", "progress_required": 600.0},
	{"name": "space_exploration", "progress_required": 1000.0},
]


## Ordered era definitions, each a {"name": String, "progress_required": float}
## Dictionary; a duplicate so callers can't mutate internal state.
func era_definitions() -> Array:
	return _ERAS.duplicate(true)


## Era that the given cumulative progress falls into. Progress 0 is the
## first era; crossing an era's progress_required advances to the next one;
## progress past every threshold stays at the last era rather than erroring.
func current_era(progress: float) -> String:
	for i in range(_ERAS.size() - 1):
		if progress < float(_ERAS[i]["progress_required"]):
			return _ERAS[i]["name"]
	return _ERAS[-1]["name"]


## Position of era_name in the ordered era list, or -1 if unknown.
func era_index(era_name: String) -> int:
	for i in range(_ERAS.size()):
		if _ERAS[i]["name"] == era_name:
			return i
	return -1


## How much more progress is needed to reach the next era; 0.0 once at the
## final era, since there is no next era to reach.
func progress_to_next_era(progress: float) -> float:
	var idx := era_index(current_era(progress))
	if idx == _ERAS.size() - 1:
		return 0.0
	return float(_ERAS[idx]["progress_required"]) - progress


## Era for a given cumulative progress, with an additional "a signature world
## boss for the current era was defeated" advancement trigger layered on top
## (docs/concept/eras.md "Era transitions can be boss-gated",
## docs/concept/worldbosses.md "Era-gated bosses") -- either trigger alone is
## enough to have advanced past an era: defeating the boss advances one era
## beyond whatever progress alone would give, capped at the final era same
## as current_era(). This is additive to current_era(), not a replacement --
## progress-threshold advancement still works exactly as before when no boss
## has been defeated.
func current_era_with_boss_defeat(progress: float, boss_defeated: bool) -> String:
	var era_by_progress := current_era(progress)
	if not boss_defeated:
		return era_by_progress
	var idx := era_index(era_by_progress)
	if idx == _ERAS.size() - 1:
		return era_by_progress
	return _ERAS[idx + 1]["name"]
