extends RefCounted

## What the PRIMARY and SECONDARY action on an animal are, right now.
##
## The ordering is the whole feature. A fixed verb per species ("horses are for
## riding") is wrong at almost every moment that matters: the horse in front of
## you is loose, or on a rope and starving, or tame and waiting. What the
## player should press changes with the animal's own state, so the animal's
## state is what decides it.
##
## Pure and engine-free: the same list feeds the hover tooltip (which shows the
## verbs with their live keys) and Player's action router (which performs
## whichever slot was pressed). One ordering, read twice, so the prompt can
## never advertise a verb the press would not carry out.
##
## Reported: "we should implement a primary action and secondary action feature
## ... so when the lasso is tied and player has carrot in hand the horses
## primary action should be feed (when it's tied up and hungry)".

const Taming = preload("res://src/gameplay/taming.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const CaptureTool = preload("res://src/gameplay/capture_tool.gd")

## The treat taming runs on (see Player.TAMING_TREAT_ID, docs/concept/wild_crops.md's
## wild carrot -- the same meadow that supplies the rope supplies the reward).
const TREAT_ITEM_ID := "carrot"

## How many actions a player can be offered at once: one primary, one
## secondary. Not a display limit -- it is how many keys exist to press, and
## offering a third would be advertising something unreachable.
const MAX_SLOTS := 2

## The rebindable input each slot is pressed with, in order.
const SLOT_ACTIONS := ["primary_action", "secondary_action"]


## The ordered actions for `state` (CreatureMarker.animal_state) given what the
## player is holding. Index 0 is the primary, index 1 the secondary.
##
## Only ever offers what the player can actually DO right now. A verb they
## cannot carry out -- feeding with no food, lassoing a wolf -- is worse than
## silence, because they will press it and conclude the mechanic is broken.
## What the animal NEEDS is shown separately as state (hungry/cold/thirsty), so
## "it wants feeding and you have no carrot" still reaches the player; it just
## does not masquerade as a button.
static func for_animal(state: Dictionary, held_item_id: String) -> Array:
	var actions: Array = []
	var restrained: bool = bool(state.get("restrained", false))
	var tame: bool = bool(state.get("tame", false))
	var species := String(state.get("species", ""))

	# Feeding leads whenever it is possible, including over riding: a hungry
	# animal you are already holding food for is asking for something, and it
	# is the only action here that MOVES the relationship (see
	# Taming.trust_after_feeding -- only a hungry feed earns trust). The ride
	# will still be there afterwards.
	if restrained and bool(state.get("hungry", false)) and held_item_id == TREAT_ITEM_ID:
		actions.append({"verb": "Feed", "action": "primary_action"})

	if tame:
		if Taming.can_be_mounted(species):
			actions.append({"verb": "Ride", "action": "mount"})
		# Orders are what being tame buys a species that will never carry
		# anyone -- without this a tamed sheep would offer nothing at all.
		actions.append({"verb": "Order", "action": "lasso"})
	elif restrained:
		actions.append({"verb": "Release", "action": "lasso"})
	elif Taming.can_be_tamed(species, held_item_id):
		# The verb names the tool actually in hand, because the right tool is
		# species-specific: a serpent needs a snare, a mouse a trap, a flyer a
		# net (see CaptureTool.required_tool_for). Offering "Lasso" while
		# holding a snare would name the wrong thing, and offering it while
		# holding the WRONG tool would promise a catch that cannot happen --
		# can_be_tamed is what decides, so the offer follows it exactly.
		actions.append({"verb": _capture_verb_for(held_item_id), "action": "lasso"})

	# The SLOT decides the key, not the verb. Every verb here also has its own
	# dedicated binding (mount, lasso) and those keep working -- but a player
	# should not have to remember which verb sits on which key to do the
	# obvious thing to the animal in front of them. One key that always does
	# what the animal most needs is the whole point of the feature.
	var slotted: Array = []
	for i in mini(actions.size(), MAX_SLOTS):
		slotted.append({
			"verb": actions[i]["verb"],
			"action": SLOT_ACTIONS[i],
		})
	return slotted


## What holding this tool is called, so the prompt reads as the thing the
## player is about to do rather than a generic "capture".
static func _capture_verb_for(tool_id: String) -> String:
	match tool_id:
		CaptureTool.NET:
			return "Net"
		CaptureTool.SNARE:
			return "Snare"
		CaptureTool.TRAP:
			return "Trap"
		_:
			return "Lasso"
