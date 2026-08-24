extends RefCounted

## The single source of truth for every rebindable input action: its default
## physical keycode and its human-readable label, plus per-action overrides
## the player sets in the settings menu. Pure logic -- World reads this to
## (re)apply the InputMap and to persist overrides to disk; the settings
## overlay reads it to render and edit the bindings. Keeping the registry
## here (not scattered across Player/World's own _bind_* calls) is what makes
## rebinding possible at all.

## Ordered so the settings menu lists related actions together. Each entry:
## {action, label, default}. `default` is a physical keycode (Key enum).
const ACTIONS := [
	{"action": "move_up", "label": "Move Up", "default": KEY_W},
	{"action": "move_down", "label": "Move Down", "default": KEY_S},
	{"action": "move_left", "label": "Move Left", "default": KEY_A},
	{"action": "move_right", "label": "Move Right", "default": KEY_D},
	{"action": "attack", "label": "Attack / Use Tool", "default": KEY_SPACE},
	{"action": "block", "label": "Block", "default": KEY_SHIFT},
	{"action": "pickup", "label": "Pick Up Nearby Items", "default": KEY_E},
	{"action": "kick", "label": "Kick Nearby Stone", "default": KEY_K},
	# The "put this down" complement to E's "pick this up into hand" (see
	# docs/concept/stone.md's held-item concept, generalized to any real
	# physical object in docs/concept/wild_crops.md) -- stashes whatever
	# is currently held into the inventory.
	{"action": "stash", "label": "Stash Held Item", "default": KEY_H},
	{"action": "fish", "label": "Fish / Reel", "default": KEY_F},
	{"action": "lasso", "label": "Throw / Release Lasso", "default": KEY_R},
	{"action": "mount", "label": "Mount / Dismount", "default": KEY_V},
	{"action": "trade", "label": "Trade with Merchant", "default": KEY_T},
	{"action": "talk", "label": "Talk to Villager", "default": KEY_G},
	{"action": "build", "label": "Place Earth", "default": KEY_B},
	{"action": "destroy", "label": "Remove Tile", "default": KEY_Q},
	{"action": "hotbar_1", "label": "Hotbar Slot 1", "default": KEY_1},
	{"action": "hotbar_2", "label": "Hotbar Slot 2", "default": KEY_2},
	{"action": "hotbar_3", "label": "Hotbar Slot 3", "default": KEY_3},
	{"action": "hotbar_4", "label": "Hotbar Slot 4", "default": KEY_4},
	{"action": "hotbar_5", "label": "Hotbar Slot 5", "default": KEY_5},
	{"action": "toggle_inventory", "label": "Toggle Inventory", "default": KEY_I},
	{"action": "toggle_crafting", "label": "Toggle Crafting", "default": KEY_C},
	# Moved off K (the very next key over, an easy muscle-memory shift) to
	# make room for "kick" -- see docs/concept/stone.md.
	{"action": "toggle_skills", "label": "Toggle Skill Tree", "default": KEY_L},
	{"action": "toggle_settings", "label": "Toggle Settings", "default": KEY_ESCAPE},
	{"action": "toggle_console", "label": "Toggle Console", "default": KEY_QUOTELEFT},
]

## action -> keycode, only for actions the player has changed from default.
var _overrides: Dictionary = {}


func action_names() -> Array:
	var names := []
	for entry in ACTIONS:
		names.append(entry["action"])
	return names


func is_rebindable(action: String) -> bool:
	return _entry_for(action) != null


func label_for(action: String) -> String:
	var entry = _entry_for(action)
	return entry["label"] if entry != null else ""


func default_keycode_for(action: String) -> int:
	var entry = _entry_for(action)
	return entry["default"] if entry != null else 0


## The keycode currently bound to `action`: the player's override if any,
## otherwise the default. 0 for an action this registry doesn't know.
func keycode_for(action: String) -> int:
	if not is_rebindable(action):
		return 0
	return _overrides.get(action, default_keycode_for(action))


func set_keycode(action: String, keycode: int) -> void:
	if is_rebindable(action):
		_overrides[action] = keycode


func reset_action(action: String) -> void:
	_overrides.erase(action)


func reset() -> void:
	_overrides.clear()


## Only the overrides need persisting -- defaults live in ACTIONS. Unknown
## actions are dropped so a stale saved file can't inject phantom bindings.
func to_dict() -> Dictionary:
	return _overrides.duplicate()


func apply_dict(saved: Dictionary) -> void:
	for action in saved:
		if is_rebindable(action):
			_overrides[action] = int(saved[action])


func _entry_for(action: String):
	for entry in ACTIONS:
		if entry["action"] == action:
			return entry
	return null
