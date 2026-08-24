extends Node2D

## Visual marker for a placed cave entrance (see CaveEntrancePlacement,
## docs/concept/geology.md). Deliberately walkable -- no CollisionShape2D --
## since walking ONTO it is exactly what triggers GeologyRenderer.
## reveal_chamber (the ninety-degrees-rotated equivalent of walking under a
## roof, see RoomDetector/paint_roofs). Not part of the "stone" swing group
## and carries no hover-tooltip contract -- entering is a proximity/tile
## interaction, not a swing action, so there is no verb to advertise.

const GROUP_NAME := "cave_entrance"


func _ready() -> void:
	add_to_group(GROUP_NAME)
