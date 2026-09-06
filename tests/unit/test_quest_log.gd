extends GutTest

## QuestLog (see docs/concept/karma_and_luck.md's "Quest lifecycle: accept,
## abandon, fulfil"): the player's own commitment record layered over
## quest.gd's stateless projections. Pure logic, no persisted state of its
## own -- Player.accepted_quest_ids/karma ARE the state, exactly, mirroring
## how quest.gd itself holds nothing but static funcs over data owned
## elsewhere.

const PlayerScene = preload("res://scenes/player.tscn")
const QuestLog = preload("res://src/emergence/quest_log.gd")
const Karma = preload("res://src/gameplay/karma.gd")

var player: Player


func before_each():
	player = PlayerScene.instantiate()
	add_child(player)


func after_each():
	remove_child(player)
	player.free()


func _shortfall_quest(household_id: String, recipe_id: String) -> Dictionary:
	return {
		"settlement_id": "settlement:1_1",
		"household_id": household_id,
		"recipe_id": recipe_id,
		"missing": [{"item_id": "stick", "need": 2}],
	}


# -- offer_id_for: derived, never allocated ----------------------------------


## Matches docs/concept/quests.md's own stated convention for the (unbuilt)
## dialogue QuestOffer shape: "<kind>:<household_id>:<recipe_id>".
func test_offer_id_for_derives_from_household_and_recipe():
	var quest := _shortfall_quest("household:7", "stone_pickaxe")
	assert_eq(QuestLog.offer_id_for(quest), "production:household:7:stone_pickaxe")


## The same real shortage -- same household, same recipe -- always yields
## the same id, even from two separately-built dicts. This is what makes
## accepting it, reloading, and re-deriving it later all agree.
func test_offer_id_for_is_stable_for_the_same_underlying_shortage():
	var a := QuestLog.offer_id_for(_shortfall_quest("household:7", "stone_pickaxe"))
	var b := QuestLog.offer_id_for(_shortfall_quest("household:7", "stone_pickaxe"))
	assert_eq(a, b)


# -- accept: pure set-membership, no world fact, no Karma --------------------


func test_accept_adds_the_offer_id_to_the_players_accepted_set():
	QuestLog.accept(player, "production:household:7:stone_pickaxe")
	assert_true(player.accepted_quest_ids.has("production:household:7:stone_pickaxe"))


## Accepting an already-accepted offer_id must not duplicate it -- the
## player's intent to take this quest is a single fact, not a counter.
func test_accept_is_idempotent():
	QuestLog.accept(player, "production:household:7:stone_pickaxe")
	QuestLog.accept(player, "production:household:7:stone_pickaxe")
	assert_eq(player.accepted_quest_ids.size(), 1)


## "Pure set-membership; no new fact about the WORLD is created, only about
## the player's own intent" (docs/concept/karma_and_luck.md) -- accepting is
## not itself a good or bad deed, so it must not move Karma at all.
func test_accept_does_not_change_karma():
	QuestLog.accept(player, "production:household:7:stone_pickaxe")
	assert_almost_eq(player.karma, 0.0, 0.0001)


# -- abandon: -1 Karma, removed from the accepted set ------------------------


func test_abandon_removes_the_offer_id():
	QuestLog.accept(player, "production:household:7:stone_pickaxe")
	QuestLog.abandon(player, "production:household:7:stone_pickaxe")
	assert_false(player.accepted_quest_ids.has("production:household:7:stone_pickaxe"))


## "Abandoning a quest... -1 Karma" -- the request's own example.
func test_abandon_applies_the_named_karma_penalty():
	QuestLog.accept(player, "production:household:7:stone_pickaxe")
	QuestLog.abandon(player, "production:household:7:stone_pickaxe")
	assert_almost_eq(player.karma, -Karma.QUEST_ABANDON_PENALTY, 0.0001)


## Abandoning an offer_id that was never accepted is a harmless no-op --
## there is no commitment to withdraw, so no penalty either. Guards against
## a stray double-call (e.g. a UI double-click) silently charging Karma
## twice for one real withdrawal.
func test_abandoning_a_never_accepted_offer_id_is_a_harmless_no_op():
	QuestLog.abandon(player, "production:household:7:stone_pickaxe")
	assert_almost_eq(player.karma, 0.0, 0.0001)
	assert_eq(player.accepted_quest_ids.size(), 0)


# -- reconcile: fulfilment is DERIVED, never a separate mutator --------------


## The whole point: an accepted quest whose real shortage genuinely
## resolved (it no longer appears in the fresh projection) is fulfilled --
## +1 Karma ("helping an NPC"), removed from the accepted set.
func test_reconcile_rewards_karma_and_clears_a_resolved_quest():
	QuestLog.accept(player, QuestLog.offer_id_for(_shortfall_quest("household:7", "stone_pickaxe")))

	QuestLog.reconcile(player, [])  # the shortage no longer appears anywhere

	assert_almost_eq(player.karma, Karma.QUEST_FULFILLED_REWARD, 0.0001)
	assert_eq(player.accepted_quest_ids.size(), 0)


## An accepted quest whose shortage is STILL real (still present in the
## fresh projection) must be left exactly alone -- reconcile only acts on
## the DIFFERENCE, never on every accepted quest unconditionally.
func test_reconcile_leaves_a_still_real_accepted_quest_untouched():
	var quest := _shortfall_quest("household:7", "stone_pickaxe")
	QuestLog.accept(player, QuestLog.offer_id_for(quest))

	QuestLog.reconcile(player, [quest])

	assert_almost_eq(player.karma, 0.0, 0.0001)
	assert_eq(player.accepted_quest_ids.size(), 1)


## Two accepted quests, one resolved and one still real: only the resolved
## one is touched, proving reconcile diffs per-quest rather than all-or-
## nothing.
func test_reconcile_only_touches_the_quest_that_actually_resolved():
	var still_real := _shortfall_quest("household:7", "stone_pickaxe")
	var resolved := _shortfall_quest("household:9", "iron_sword")
	QuestLog.accept(player, QuestLog.offer_id_for(still_real))
	QuestLog.accept(player, QuestLog.offer_id_for(resolved))

	QuestLog.reconcile(player, [still_real])

	assert_true(player.accepted_quest_ids.has(QuestLog.offer_id_for(still_real)))
	assert_false(player.accepted_quest_ids.has(QuestLog.offer_id_for(resolved)))
	assert_almost_eq(player.karma, Karma.QUEST_FULFILLED_REWARD, 0.0001)


## With nothing accepted, reconciling against any fresh set (even an empty
## one) must be a complete no-op -- there is nothing to fulfil.
func test_reconcile_with_no_accepted_quests_does_nothing():
	QuestLog.reconcile(player, [])
	assert_almost_eq(player.karma, 0.0, 0.0001)
	assert_eq(player.accepted_quest_ids.size(), 0)
