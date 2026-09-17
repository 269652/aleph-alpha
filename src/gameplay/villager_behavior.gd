extends RefCounted

## What a villager does next, decided from what they NEED and what is around
## them rather than from a fixed schedule (docs/concept/npc_social_life.md).
##
## The sibling of CreatureBehavior, over the same BehaviorKernel and the same
## Ethogram wiring table -- a villager is an animal with a job, so its inner
## life runs on the same code every other creature's does. Adding a wiring to
## BODY_PLANS["villager"] is all it takes to add a behaviour here; this file
## keeps no private copy of the table and no opinions of its own about
## priority (the wiring ORDER is the priority, first match wins).
##
## Deliberately returns NOTHING rather than an intent when no drive is
## pressing. That is design pillar 2: the schedule says where a villager
## would BE and drives say what they DO, so a behaviour layer that always had
## an opinion would have REPLACED the schedule instead of interrupting it --
## and the schedule is what makes a blacksmith stand at a forge rather than
## milling about like an animal.

const Ethogram = preload("res://src/gameplay/ethogram.gd")
const BehaviorKernel = preload("res://src/gameplay/behavior_kernel.gd")

const BODY_PLAN := "villager"

## The intents, each one an approach named by a villager wiring. Pinned to
## those by test_every_intent_comes_from_the_ethograms_own_villager_wirings,
## so the two cannot drift.
const EAT := "eat"
const DRINK := "drink"
const REST := "rest"
const SOCIALIZE := "socialize"

## No drive pressing, or nothing around to answer the one that is. Not a
## wiring's approach and deliberately not the kernel's own WANDER either:
## "nothing to steer you" is the caller's schedule standing, which is a
## different thing from "roam".
const NOTHING := ""

## Cached for the same reason CreatureBehavior caches: decide() runs every
## frame for every villager, and Ethogram.wirings_for/express hand back fresh
## copies by contract.
var _wirings: Array = []
var _receptors := {}


## `context` carries this villager's own position and drive levels, plus
## whatever they can sense right now:
##
##   position  Vector2
##   drives    {drive_name: GAIN}, as Drives.gains() produces -- 0 below a
##             drive's own onset, 1 at its threshold, NOT raw levels. This
##             is the contract that stops a villager who is one-thousandth
##             hungry from walking to market forever: the kernel skips a
##             wiring whose gate is 0, and a gain is 0 until the need is
##             really urgent. NpcNeeds.gains() is exactly this.
##   company   Array[Vector2] -- the other villagers in reach
##   market    Vector2 or absent -- where food is bought
##   home      Vector2 or absent -- this villager's own house
##   water     Vector2 or absent -- the well
##
## Returns {"intent", "target"}: the intent is NOTHING with a null target
## whenever the schedule should simply stand.
func decide(context: Dictionary) -> Dictionary:
	if _wirings.is_empty():
		_wirings = Ethogram.wirings_for(BODY_PLAN)
		_receptors = Ethogram.express("", {}, BODY_PLAN)
	var decision := BehaviorKernel.decide(
		_wirings, _receptors, context.get("drives", {}),
		context.get("position", Vector2.ZERO), _stimuli(context)
	)
	var intent := String(decision["intent"])
	# The kernel's own "nothing fired" answer is WANDER. For a villager that
	# is not a behaviour, it is the absence of one -- see NOTHING.
	if intent == BehaviorKernel.WANDER:
		return {"intent": NOTHING, "target": null}
	var stimulus: Dictionary = decision.get("stimulus", {})
	if stimulus.is_empty():
		return {"intent": NOTHING, "target": null}
	return {"intent": intent, "target": stimulus["position"]}


## What this villager can sense right now, in the kernel's own stimulus
## shape. A channel the caller did not report is simply absent, which is what
## makes "lonely with nobody around" come back as NOTHING rather than as a
## walk toward a place that is not there.
func _stimuli(context: Dictionary) -> Array:
	var stimuli: Array = []
	for at in context.get("company", []):
		_append(stimuli, at, Ethogram.COMPANY)
	for channel in [Ethogram.MARKET, Ethogram.HOME, Ethogram.WATER]:
		var at = context.get(channel)
		if at != null:
			_append(stimuli, at, channel)
	return stimuli


static func _append(stimuli: Array, at: Vector2, channel: String) -> void:
	stimuli.append({"position": at, "features": {channel: 1.0}})
