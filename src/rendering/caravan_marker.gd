extends Node2D

## A real caravan walking a real regional-trade route (see
## docs/concept/trade.md). Deliberately NOT built on NpcMarker/CreatureMarker
## -- a caravan doesn't have a daily schedule or a sense/perceive/act loop,
## it has exactly one straight route between two real settlements' wells and
## one real outcome at the end (arrival or raid). Mirrors DecomposerMarker's
## own reasoning for staying off the full AI stack: the wrong shape for a
## walker whose entire behaviour is already fully decided by a pure
## CaravanTrip the moment it departs.
##
## Position is NOT advanced by this node's own _process -- CaravanTrip's
## position_at(world_age) is a pure closed-form function of elapsed time, so
## EarthChunkManager.step_caravans drives this marker directly via sync(),
## the same "behavior decides WHEN, the marker just supplies the engine
## effect" split as every other creature/NPC pair in this codebase, except
## here the pure side needs no per-frame ticking of its own at all.

const ProceduralCaravanSprite = preload("res://src/rendering/procedural_caravan_sprite.gd")

const GROUP_NAME := "caravan"

## Set by the caller before the marker is first synced -- purely descriptive
## (for a future hover tooltip / dev-console listing), not read by any
## movement logic here.
var item_id := ""
var count := 0


func _ready() -> void:
	add_to_group(GROUP_NAME)
	var sprite := Sprite2D.new()
	sprite.texture = ProceduralCaravanSprite.new().generate_texture()
	add_child(sprite)


## Moves this marker to the caravan's real current position -- called once
## per EarthChunkManager.step_caravans tick with the trip's own
## position_at(world_age), so this node's visible position is always
## exactly what the pure trip says it should be, never independently
## simulated.
func sync(new_position: Vector2) -> void:
	position = new_position
