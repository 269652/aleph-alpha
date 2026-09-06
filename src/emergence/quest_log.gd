extends RefCounted

## QuestLog: the player's own commitment record layered over quest.gd's
## stateless projections (see docs/concept/karma_and_luck.md's "Quest
## lifecycle: accept, abandon, fulfil").
##
## `src/emergence/quest.gd` is a pure, stateless PROJECTION over live
## household/market state -- it is never itself a persisted entity, and
## this file does not change that. What it never had, because nothing
## consumed it yet, is any record of the PLAYER'S OWN commitment to one.
## This adds exactly that, as a thin layer that references the live
## projection rather than duplicating it: every function here is a static
## func with no state of its own, reading/writing Player.accepted_quest_ids
## and Player.karma directly -- the same "logic in a pure module, data on
## Player" split Taming/OreYield's own `luck` parameter already uses.

const Karma = preload("res://src/gameplay/karma.gd")


## Derived, never allocated -- matching docs/concept/quests.md's own stated
## convention for the (unbuilt) dialogue QuestOffer shape:
## "production:<household_id>:<recipe_id>". The same real shortage always
## yields the same id, so accepting it twice, or across a save/reload, is
## never a fresh commitment.
static func offer_id_for(quest: Dictionary) -> String:
	return "production:%s:%s" % [quest["household_id"], quest["recipe_id"]]


## The player commits. Pure set-membership -- no new fact about the WORLD
## is created, only about the player's own intent, so this never touches
## Karma. Idempotent: accepting an already-accepted offer_id is a no-op,
## not a duplicate entry.
static func accept(player: Player, offer_id: String) -> void:
	if not player.accepted_quest_ids.has(offer_id):
		player.accepted_quest_ids.append(offer_id)


## The player explicitly withdraws -- `-1` Karma (the request's own
## example: "Abandoning a quest... -1 Karma"). A no-op, Karma untouched, if
## offer_id was never actually accepted, so a stray double-call can never
## charge the penalty twice for one real withdrawal.
static func abandon(player: Player, offer_id: String) -> void:
	if not player.accepted_quest_ids.has(offer_id):
		return
	player.accepted_quest_ids.erase(offer_id)
	player.apply_karma_delta(-Karma.QUEST_ABANDON_PENALTY)


## Fulfilment is DERIVED, never a separate mutator -- matching this whole
## system's "rewards are re-derived from live state, never trusted from the
## offer" rule (quests.md's own "Rewards are derived, and re-derived"
## section). `fresh_quests` is the CURRENT, live result of re-running the
## projection (see EarthChunkManager.all_production_shortfall_quests): any
## accepted offer_id whose underlying quest no longer appears in it had its
## real shortage genuinely resolved -- `+1` Karma each ("helping an NPC",
## since every quest this codebase's real slice implements is literally one
## NPC's own stated need), removed from the accepted set. An accepted
## offer_id still present in `fresh_quests` is left exactly alone: this
## acts only on the DIFFERENCE, never on every accepted quest
## unconditionally.
static func reconcile(player: Player, fresh_quests: Array) -> void:
	var fresh_offer_ids := {}
	for quest in fresh_quests:
		fresh_offer_ids[offer_id_for(quest)] = true

	for offer_id in player.accepted_quest_ids.duplicate():
		if not fresh_offer_ids.has(offer_id):
			player.accepted_quest_ids.erase(offer_id)
			player.apply_karma_delta(Karma.QUEST_FULFILLED_REWARD)
