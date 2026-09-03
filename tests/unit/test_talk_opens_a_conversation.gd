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
