extends RefCounted

## What activating a hotbar slot should do, decided purely from the held
## item's kind (see Item.kind). Weapons/tools get equipped; consumables
## (food/potion) get used up for their effect; a placeable (e.g. campfire,
## furnace -- a structure you build into the world, see item_catalog.gd)
## becomes the item Player.build_action places on the next build-input press
## instead of the default bare-earth tile; everything else (raw materials)
## does nothing when clicked/hotkeyed. Pure logic -- the Player applies the
## returned intent (see Player.activate_hotbar_slot).

const EQUIP := "equip"
const USE := "use"
const PLACE := "place"
const NONE := "none"

const _ACTION_BY_KIND := {
	"weapon": EQUIP,
	"tool": EQUIP,
	"armor": EQUIP,
	"food": USE,
	"potion": USE,
	"placeable": PLACE,
}


func action_for(item_kind: String) -> String:
	return _ACTION_BY_KIND.get(item_kind, NONE)
