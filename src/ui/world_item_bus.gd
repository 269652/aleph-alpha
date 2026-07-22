extends Node

## Autoload relay for spawning items into the world. Dynamically-created nodes
## (creature markers deep in chunk streaming, trees) emit `item_dropped` and
## world.gd listens once to spawn the actual DroppedItem ground node -- so the
## emitters never need a reference to the world's item layer.

signal item_dropped(item_stack, world_position: Vector2)
