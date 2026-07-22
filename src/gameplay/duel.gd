extends RefCounted

## Consensual PvP dueling: request/accept/decline/expire state machine, plus
## the "Flagged Contested Zones" union rule from docs/concept/pvp.md (zone
## flag OR an active duel both permit PvP damage). Combat resolution itself
## lives elsewhere; this only tracks consent.

const REQUEST_TIMEOUT := 15.0


## Snapshot of state right after issuing a duel request.
func request_duel() -> Dictionary:
	return {
		"state": "requested",
		"time_remaining": REQUEST_TIMEOUT,
	}


## Ticks the timer down by delta. A "requested" duel whose timer reaches 0
## auto-declines by expiring; any other state just has its timer counted
## down without changing.
func advance(state: String, time_remaining: float, delta: float) -> Dictionary:
	var new_time_remaining: float = maxf(0.0, time_remaining - delta)
	var new_state: String = state
	if state == "requested" and new_time_remaining <= 0.0:
		new_state = "expired"
	return {
		"state": new_state,
		"time_remaining": new_time_remaining,
	}


## Accepting only does something to a pending request.
func accept(state: String) -> String:
	if state == "requested":
		return "accepted"
	return state


## Declining only does something to a pending request.
func decline(state: String) -> String:
	if state == "requested":
		return "declined"
	return state


## Whether PvP damage between the two duelists is currently permitted by consent alone.
func is_active(state: String) -> bool:
	return state == "accepted"


## Whether a new duel may be requested given the current state.
func can_request(state: String) -> bool:
	return state == "none" or state == "declined" or state == "expired"


## "Flagged Contested Zones" union rule: open PvP zone flag OR an active accepted duel.
func is_pvp_allowed_in_zone(zone_flagged: bool, duel_state: String) -> bool:
	return zone_flagged or is_active(duel_state)
