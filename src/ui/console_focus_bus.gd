extends Node

## Autoload flag DevConsole sets while it holds keyboard focus. Player's
## movement/attack/build/destroy all read Input.is_action_pressed/get_vector
## directly (not through Godot's Control focus system), so simply focusing
## the console's LineEdit does NOT stop WASD from also moving the player --
## typing "d" while the console is open would otherwise walk the player east.
## Player checks this flag itself in its local-input reads to suppress that.

var is_open := false
