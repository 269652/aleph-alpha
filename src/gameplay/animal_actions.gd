extends RefCounted

## What the PRIMARY and SECONDARY action on an animal are, right now.
##
## Every candidate verb SCORES itself against the situation, and the two
## highest-scoring fill the two slots. There is no ladder of if/elses deciding
## the order, which matters because a ladder puts the reasoning in the shape of
## the branches: adding a verb means hand-placing it against every existing
## one, and "why did it pick that?" has no answer you can print.
##
## Two things make up a score, and both are things the player can see:
##
##   RELEVANCE -- how much what they are HOLDING points at this verb. Holding a
##   carrot at a hungry animal is the clearest statement of intent available;
##   holding the right capture tool at a loose one is the same statement about
##   a different verb.
##
##   URGENCY -- how badly the animal needs it. A starving animal wants the
##   carrot more than a peckish one, so feeding climbs as hunger does, and a
##   content animal stops asking entirely.
##
## An action the player cannot carry out scores exactly ZERO and is never
## offered. That is not the same as scoring low: a prompt they will press and
## watch do nothing is worse than no prompt at all, and what the animal NEEDS
## still reaches them as state (hungry/cold/thirsty) on the card and the
## tooltip. The offer is for things that will happen.
##
## Pure and engine-free: the same ranking feeds the hover tooltip (which shows
## the verbs against their slot keys) and Player's action router (which
## performs whichever slot was pressed), so the prompt can never advertise a
## verb the press would not carry out.
##
## Reported: "we should implement a primary action and secondary action feature
## ... so when the lasso is tied and player has carrot in hand the horses
## primary action should be feed", and then: "by a generic mechanism which
## scores priority on context / item relevance".

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

## Score a verb earns purely for being possible -- the floor that makes it
## offerable at all. Every weight below is relative to this, and none of them
## is asserted anywhere: what the tests pin is which verb WINS in a given
## situation, because that is the design. The arithmetic is how it is
## expressed, not what it means.
const BASE_POSSIBLE := 1.0

## Holding the item a verb consumes or uses. The strongest single signal of
## intent there is -- a player with a carrot in their hand, standing at a
## hungry animal, has already said what they want.
const HELD_ITEM_RELEVANCE := 3.0

## How much an unmet need can add on top. Scaled by how bad the need actually
## is, so feeding climbs with hunger rather than switching on at a threshold.
const NEED_URGENCY_WEIGHT := 2.0

## The payoff verb for a finished relationship. Above a bare possible action so
## a tame mount offers the ride rather than a housekeeping verb, but below a
## held-item intent so it never talks over what the player is holding out.
const PAYOFF_RELEVANCE := 1.5


## Every candidate that scores above zero, best first, each carrying the score
## that ranked it and a short `why`. The `why` is not decoration: an ordering
## nobody can explain is an ordering nobody can tune, and this is the string
## that answers "why is my primary key doing THAT?".
static func scored_for(state: Dictionary, held_item_id: String) -> Array:
	var scored: Array = []
	for verb in _candidates(held_item_id):
		var score := score_of(verb, state, held_item_id)
		if score <= 0.0:
			continue
		scored.append({
			"verb": verb,
			"score": score,
			"why": _why(verb, held_item_id),
		})
	# Descending by score. `sort_custom` with a strict `>` keeps equal scores in
	# their original candidate order, which is fixed -- two runs of the same
	# situation must never disagree about which key does what.
	scored.sort_custom(func(a, b): return a["score"] > b["score"])
	return scored


## The ordered actions for `state` given what the player is holding: index 0 is
## the primary, index 1 the secondary. Each carries the SLOT it is pressed
## with, not the verb's own dedicated key -- a player should not have to
## remember which verb sits on which key to do the obvious thing to the animal
## in front of them.
static func for_animal(state: Dictionary, held_item_id: String) -> Array:
	var out: Array = []
	var scored := scored_for(state, held_item_id)
	for i in mini(scored.size(), MAX_SLOTS):
		out.append({
			"verb": scored[i]["verb"],
			"action": SLOT_ACTIONS[i],
		})
	return out


## What `verb` is worth in this situation. 0.0 means "cannot be done right
## now", which is why callers can treat it as the offerable test too.
static func score_of(verb: String, state: Dictionary, held_item_id: String) -> float:
	match verb:
		"Feed":
			# A loose animal is not standing still to be fed; only a HUNGRY
			# feed earns any trust (Taming.trust_after_feeding), so offering
			# one to a full animal would be offering a no-op; and the food has
			# to be in hand.
			if not bool(state.get("restrained", false)):
				return 0.0
			if not bool(state.get("hungry", false)):
				return 0.0
			if held_item_id != TREAT_ITEM_ID:
				return 0.0
			return (
				BASE_POSSIBLE
				+ HELD_ITEM_RELEVANCE
				+ NEED_URGENCY_WEIGHT * _urgency(state, "hunger_urgency")
			)
		"Ride":
			if not bool(state.get("tame", false)):
				return 0.0
			if not Taming.can_be_mounted(String(state.get("species", ""))):
				return 0.0
			return BASE_POSSIBLE + PAYOFF_RELEVANCE
		"Order":
			# What being tame BUYS a species that will never carry anyone --
			# without this a tamed sheep would offer nothing at all.
			if not bool(state.get("tame", false)):
				return 0.0
			return BASE_POSSIBLE
		"Release":
			if not bool(state.get("restrained", false)):
				return 0.0
			if bool(state.get("tame", false)):
				return 0.0  # a tame animal takes orders instead
			return BASE_POSSIBLE
		"":
			return 0.0
		_:
			# Every capture verb (Lasso/Snare/Net/Trap) scores the same way:
			# possible only with the tool this body plan actually needs, and
			# lifted by holding it, because holding the right tool at a loose
			# animal is the same statement of intent a carrot is at a hungry
			# one. can_be_tamed is the authority on the match (see
			# CaptureTool.required_tool_for).
			if verb != _capture_verb_for(held_item_id):
				return 0.0
			if bool(state.get("restrained", false)) or bool(state.get("tame", false)):
				return 0.0
			if not Taming.can_be_tamed(String(state.get("species", "")), held_item_id):
				return 0.0
			return BASE_POSSIBLE + HELD_ITEM_RELEVANCE


## Which verbs are worth scoring here. Includes the capture verb named after
## whatever is in hand, so a snare offers "Snare" rather than a generic
## "Capture" -- the prompt names the thing the player is holding.
static func _candidates(held_item_id: String) -> Array:
	return ["Feed", "Ride", "Order", "Release", _capture_verb_for(held_item_id)]


## How bad a need is, 0..1. Falls back to "just past the threshold" when the
## caller reports only the boolean, so a state dict without the fraction still
## ranks sensibly rather than scoring no urgency at all.
static func _urgency(state: Dictionary, key: String) -> float:
	if state.has(key):
		return clampf(float(state[key]), 0.0, 1.0)
	return 0.5


static func _why(verb: String, held_item_id: String) -> String:
	match verb:
		"Feed":
			return "holding %s for a hungry animal" % held_item_id
		"Ride":
			return "a tame mount"
		"Order":
			return "a tame animal takes orders"
		"Release":
			return "held on a rope"
		_:
			return "holding the tool its body plan needs"


## What holding this tool is called, so the prompt reads as the thing the
## player is about to do rather than a generic "capture". Empty for anything
## that is not a capture tool, which scores zero and is never offered.
static func _capture_verb_for(tool_id: String) -> String:
	match tool_id:
		CaptureTool.NET:
			return "Net"
		CaptureTool.SNARE:
			return "Snare"
		CaptureTool.TRAP:
			return "Trap"
		CaptureTool.LASSO, CaptureTool.REINFORCED_ROPE:
			return "Lasso"
		_:
			return ""
