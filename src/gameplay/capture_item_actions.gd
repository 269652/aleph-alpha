extends RefCounted

## What a held capture device's own SECONDARY action is, independent of
## whatever (if anything) is under the player (docs/concept/capture_dsl.md).
## "Put into bottle" needs no hover target at all -- only what's in the
## player's hand and what's in their bag.
##
## A sibling of animal_actions.gd, deliberately not an extension of it:
## AnimalActions' whole contract is keyed off a live animal's
## animal_state(), which a loaded net's own state has nothing to do with.
## Same "a verb that cannot be carried out scores exactly zero and is never
## offered" contract, kept small because v1 has exactly one verb.
##
## Consulted by Player._action_slots_step only as a FALLBACK: the existing
## hover-verb path (AnimalActions, on whatever is under the player) is tried
## first and wins unchanged whenever it offers something for that slot --
## this only fires when it offers nothing, so Feed/Ride/Order/Release stay
## provably untouched.

## The rebindable input this fires on -- the SAME key AnimalActions' own
## secondary slot already uses, never a new keybind.
const SLOT_ACTION := "secondary_action"


## Score of "Put into bottle" for `tool_item`, given whether the player's
## inventory holds at least one glass_bottle. 0.0 means "not offered".
static func score_of(tool_item, has_bottle: bool) -> float:
	if tool_item == null or not tool_item.is_holding_captive():
		return 0.0
	if not has_bottle:
		return 0.0
	return 1.0


## The action for this slot, or {} if none applies.
static func for_tool(tool_item, has_bottle: bool) -> Dictionary:
	if score_of(tool_item, has_bottle) <= 0.0:
		return {}
	return {"verb": "Put into bottle", "action": SLOT_ACTION}
