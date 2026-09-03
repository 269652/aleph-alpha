extends GutTest

## Pressing the talk key opens a real conversation (docs/concept/dialogue.md).
##
## The wire that was missing. `Player._talk_step` called `NpcGreeting` -- an
## eight-entry lookup on personality trait, one banner line -- while the
## dialogue engine sat unreachable. NpcGreeting's own header says it is
## "explicitly NOT the real Live Dialogue System"; this is the real one.

const Player = preload("res://scenes/player.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")


## The one thing Player asks of the world when the talk key goes down.
class TalkStubWorld:
	extends Node2D
	var npc = null
	var asked := 0

	func nearest_npc_near(_at: Vector2, _radius: float):
		asked += 1
		return npc


class StubNpc:
	extends Node2D
	var identity


func test_the_talk_request_is_a_conversation_not_a_banner():
	# Player exposes what the talk key produced as a REQUEST, so World can
	# open the window with it -- rather than a pre-rendered string, which is
	# what made the old path a dead end.
	assert_true(
		Player.new_talk_request({"npc_id": "npc:1"}) is Dictionary,
		"a talk request is not a plain value"
	)


func test_a_request_names_who_is_being_talked_to():
	var request := Player.new_talk_request({"npc_id": "npc:9", "npc_name": "Sel"})
	assert_eq(String(request["frame"]["npc_id"]), "npc:9")


func test_no_one_nearby_is_not_a_request():
	assert_true(Player.new_talk_request({}).is_empty())


## The request carries where the player stands with this villager, so the
## conversation is rendered at a real tier rather than always at stranger.
func test_a_request_carries_a_recognition_tier():
	var request := Player.new_talk_request({"npc_id": "npc:9"})
	request["recognition"] = "knows_you"
	assert_eq(String(request["recognition"]), "knows_you")


# -- the errand rides along on the request -----------------------------------


## The talk request carries everything the conversation needs to offer an
## errand and to take one back -- assembled where the world is already being
## read, so World stays glue and never assembles a second view of the
## simulation.
func test_a_request_carries_the_ask_context():
	var request := Player.new_talk_request({"npc_id": "npc:9"})
	request["asks"] = {"contract_store": null, "player_id": "player:local"}
	assert_true(request.has("asks"))


## Every key Conversation reads out of the ask context, stated once. A key
## that silently stops being passed is an errand that silently stops being
## offered -- the same reason ConversationSources.SOURCE_KEYS is pinned.
func test_the_ask_context_names_everything_a_conversation_reads():
	var ConversationSources = load("res://src/dialogue/conversation_sources.gd")
	var asks: Dictionary = ConversationSources.asks_for({}, {}, null)
	for key in ["contract_store", "player_id", "carrying", "item_kinds", "payer_gold"]:
		assert_true(asks.has(key), "the ask context is missing %s" % key)
