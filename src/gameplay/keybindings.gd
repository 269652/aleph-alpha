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
	# Hold to stalk (see docs/concept/animal_husbandry.md "The approach").
	# Ctrl is where a player's hand already goes for "crouch", and it was the
	# only unclaimed modifier left in this registry -- KEY_X and KEY_Z, which
	# the husbandry doc named as free when it was written, have since been
	# taken by secondary_action and cast.
	{"action": "crouch", "label": "Crouch (Stalk)", "default": KEY_CTRL},
	{"action": "pickup", "label": "Pick Up Nearby Items", "default": KEY_E},
	{"action": "kick", "label": "Kick Nearby Stone", "default": KEY_K},
	# The "put this down" complement to E's "pick this up into hand" (see
	# docs/concept/stone.md's held-item concept, generalized to any real
	# physical object in docs/concept/wild_crops.md) -- stashes whatever
	# is currently held into the inventory.
	{"action": "stash", "label": "Stash Held Item / Put Bait Down", "default": KEY_H},
	{"action": "fish", "label": "Fish / Reel", "default": KEY_F},
	# Moved off R to make room for the primary slot, which now covers what this
	# did: Lasso/Release/Order are scored candidates (see AnimalActions), so
	# the key a player's hand already goes to at an animal does the obvious
	# thing to it. Kept as its own binding rather than deleted -- the
	# single-purpose rope key is still there for anyone who wants it, it just
	# cannot share R, because one press firing two verbs is the bug that
	# sharing would create.
	{"action": "lasso", "label": "Throw / Release Lasso", "default": KEY_J},
	{"action": "mount", "label": "Mount / Dismount", "default": KEY_V},
	{"action": "trade", "label": "Trade with Merchant", "default": KEY_T},
	# Selling is its own verb rather than another meaning stacked onto T,
	# which already branches two ways (buy from a merchant, or sell food to a
	# villager when there is none). Defaulted to the key next door so the two
	# halves of trading sit together under one hand -- see
	# docs/concept/economy.md's "Selling to the market".
	{"action": "sell", "label": "Sell to Merchant", "default": KEY_Y},
	# Two CONTEXT slots rather than a verb each. What they do is decided by
	# whatever is under the cursor and the state it is in -- a tied, hungry
	# horse offers Feed on the primary; a loose one offers nothing until you
	# are holding a rope (see AnimalActions.for_animal). One key that always
	# does the obvious thing beats a keyboard of verbs the player has to
	# remember the applicability rules for.
	{"action": "primary_action", "label": "Primary Action", "default": KEY_R},
	{"action": "secondary_action", "label": "Secondary Action", "default": KEY_X},
	{"action": "talk", "label": "Talk to Villager", "default": KEY_G},
	{"action": "build", "label": "Place Earth", "default": KEY_B},
	{"action": "destroy", "label": "Remove Tile", "default": KEY_Q},
	# Casting is a wholly new trigger, not routed through the hotbar/item
	# system (see docs/concept/spell_runtime.md) -- it needs its own real
	# key, not a repurposed one.
	{"action": "cast", "label": "Cast Spell", "default": KEY_Z},
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


## The key `action` is bound to RIGHT NOW, named the way a player would find it
## on their keyboard ("R", "Space", "Escape") -- for putting in on-screen text.
##
## Reads the live InputMap rather than this registry's own `_overrides`, and
## that is the point: World._apply_keybindings writes every resolved keycode
## (overrides included) into InputMap, so InputMap is the one source of truth
## every caller can reach. Player holds no Keybindings instance of its own, and
## a freshly constructed one would report DEFAULTS -- telling a player who
## rebound the lasso to press the key they moved it off.
##
## Static for the same reason: a prompt should not have to be handed a registry
## to be able to name a key.
##
## Empty for an action the InputMap has never heard of. That is a real case, not
## defensiveness -- a Player stepped in isolation runs before World registers
## the map (see Player._unhandled_input's own has_action guard) -- and a prompt
## that degrades to naming no key is far better than one that errors.
static func display_key_for(action: String) -> String:
	if not InputMap.has_action(action):
		return ""
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key: InputEventKey = event
			# physical_keycode is what ACTIONS stores and what _apply_keybindings
			# writes; keycode is the layout-dependent one and is 0 here.
			return OS.get_keycode_string(key.physical_keycode)
	return ""


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
