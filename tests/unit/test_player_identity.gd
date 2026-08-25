extends GutTest

## PlayerIdentity: deterministic entity id for the local player (see
## docs/concept/player_citizenship.md's "no player concept exists today"
## gap). Pins that the player's id is a real, valid EntityRef, the same
## "<kind>:<key>" scheme every other emergence entity already uses.

const PlayerIdentity = preload("res://src/emergence/player_identity.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")


# -- PLAYER_ENTITY_ID: a real, valid EntityRef ------------------------------

func test_player_entity_id_is_a_valid_entity_ref():
	assert_true(EntityRef.is_valid(PlayerIdentity.PLAYER_ENTITY_ID))


func test_player_entity_id_kind_is_player():
	assert_eq(EntityRef.kind_of(PlayerIdentity.PLAYER_ENTITY_ID), "player")
