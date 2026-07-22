extends RefCounted

## Manages a set of active timed debuffs, each {"debuff_id", "stacks",
## "time_remaining"}. Callers own the array; every method returns a NEW
## array rather than mutating the one passed in, so callers can diff/undo
## or hold onto a prior snapshot safely.


## Applies debuff_id to active: refreshes time_remaining to duration and
## adds a stack (capped at max_stacks) if already present, otherwise
## appends a fresh entry with 1 stack.
func apply(active: Array, debuff_id: String, duration: float, max_stacks: int) -> Array:
	var result: Array = active.duplicate()
	for i in result.size():
		var entry: Dictionary = result[i]
		if entry["debuff_id"] == debuff_id:
			var refreshed: Dictionary = entry.duplicate()
			refreshed["stacks"] = mini(int(entry["stacks"]) + 1, max_stacks)
			refreshed["time_remaining"] = duration
			result[i] = refreshed
			return result
	result.append({"debuff_id": debuff_id, "stacks": 1, "time_remaining": duration})
	return result


## Reduces time_remaining on every entry by delta, dropping any entry
## whose time_remaining falls to 0-or-below (expired debuffs disappear).
func advance(active: Array, delta: float) -> Array:
	var result: Array = []
	for entry in active:
		var remaining: float = float(entry["time_remaining"]) - delta
		if remaining > 0.0:
			var updated: Dictionary = entry.duplicate()
			updated["time_remaining"] = remaining
			result.append(updated)
	return result


## Returns debuff_id's current stack count, or 0 if not present.
func stacks_of(active: Array, debuff_id: String) -> int:
	for entry in active:
		if entry["debuff_id"] == debuff_id:
			return entry["stacks"]
	return 0
