extends RefCounted

## The player's worn equipment: one Item per slot (see concept/items.md's
## equipment slots). Pure logic -- the Player holds one of these, equips/
## unequips from the inventory UI, and reads total_armor() for damage
## mitigation. Weapons occupy the "weapon" slot but don't contribute armor.

const SLOTS := ["head", "chest", "legs", "feet", "weapon"]

var _worn: Dictionary = {}  # slot -> Item


## Equips `item` into its slot, returning whatever it displaced (the previously
## worn item in that slot, or null). A non-equippable item is returned straight
## back so the caller keeps it (nothing changes).
func equip(item):
	var slot: String = item.equip_slot_name()
	if slot == "" or not SLOTS.has(slot):
		return item
	var previous = _worn.get(slot)
	_worn[slot] = item
	return previous


## Removes and returns whatever is worn in `slot` (null if empty).
func unequip(slot: String):
	var item = _worn.get(slot)
	_worn.erase(slot)
	return item


func equipped_in(slot: String):
	return _worn.get(slot)


## Every currently-worn item (unordered).
func equipped_items() -> Array:
	return _worn.values()


## Combined flat armor of every worn piece (weapons have armor 0).
func total_armor() -> float:
	var total := 0.0
	for item in _worn.values():
		total += item.armor
	return total
