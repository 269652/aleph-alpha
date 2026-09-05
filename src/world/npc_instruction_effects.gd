extends RefCounted

## The impure edge for the NPC instruction DSL (docs/concept/
## npc_instructions.md, "Turning a resolved action into a real effect is the
## impure edge, mirroring spell_atom_effects.gd's role exactly"): takes a
## resolved haul/gather action descriptor (npc_instruction_primitives.gd's
## own {"fn": "haul"/"gather", ...} shape) plus a live, duck-typed
## world/EarthChunkManager reference and actually performs the gather --
## moving a real item from the live world into the NPC's own
## npc_inventory.gd-shaped Dictionary.
##
## Reuses whatever real "nearest-X-near" spatial query the world already
## exposes for a resource, per the concept doc's own "no new spatial-query
## shape needed": `nearest_liftable_stone_near` for stone-family resources
## (stone/iron/gold), and `harvest_peak_fruit_near` for fruit-family
## resources (berries) -- the SAME two queries and consume convention
## scenes/player.gd's own `_try_pick_stone_into_hand`/
## `_try_harvest_peak_fruit` already establish: a found stone is consumed by
## calling `stone.queue_free()` directly (no Item/Inventory-class
## round-trip -- LiftableStone.pick_up expects a picker with a full
## Item-based Inventory, which is not what NpcMarker.inventory is); a found
## fruit needs no separate consume step at all, since
## `harvest_peak_fruit_near` is READ-ONLY by design (`hanging_at` is a pure
## function of elapsed time, not a depletable stock -- see that function's
## own doc comment in earth_chunk_manager.gd).
##
## `world` is duck-typed exactly like npc_production.gd's own `world`
## parameter -- null, or missing the accessor, fails open to "nothing
## found" (never a crash). A found stone is only ever consumed if it
## exposes `queue_free` (every real Node2D does; a test double must provide
## one too).
##
## WOOD IS NOT SUPPORTED YET, on purpose. There is no real nearest-tree/wood
## query anywhere in this codebase today -- confirmed during this DSL's own
## research: ChoppableTree/TreeRenderer carry no chunk-coordinate or
## EarthChunkManager reference at all, the same underlying gap
## docs/progress.md's "Land Health" entry already documents for a different
## feature ("tree felling does NOT yet feed land health ... wiring it would
## mean threading a manager reference through the tree-spawning pipeline AND
## inventing a new amount from nothing, a structurally different and larger
## follow-up, not attempted here"). Building that plumbing is out of scope
## here too -- `dispatch()` below returns a clear
## `{"ok": false, "reason": "unsupported_resource"}` for "wood" (and any
## other unmapped resource id) rather than crashing or silently no-op'ing.
## This is a real, deliberate, documented gap, not a hidden failure -- and
## it means the concept doc's OWN canonical worked example
## (`haul(wood, base)`) still cannot be executed against live world state
## through this module.

const NpcInventory = preload("res://src/world/npc_inventory.gd")

## How far (in pixels) an NPC can reach to gather a resource. Mirrors
## scenes/player.gd's own PICKUP_RADIUS (34.0) rather than a separately
## eyeballed number -- that constant is the real precedent for "how close
## is close enough" against these exact same two spatial queries.
const GATHER_RADIUS_PX := 34.0

## Flat amount gathered per successful dispatch. Matches the player's own
## one-unit-per-harvest convention for fruit (Player._try_harvest_peak_fruit's
## `inventory.add(_item_catalog.make(species_id), 1)`) -- stone's own real
## per-pickup yield (StoneSize.rock_yield, mass-derived) is Item/mass-
## specific tuning this flat DSL resource count doesn't need to replicate.
const GATHER_YIELD := 1

## Resource ids backed by the liftable-stone query -- the same non-wood,
## non-berries family npc_instruction_cost.gd's own _RESOURCE_RARITY table
## already lists together.
const _STONE_FAMILY: Array[String] = ["stone", "iron", "gold"]

## Resource ids backed by the fruit query.
const _FRUIT_FAMILY: Array[String] = ["berries"]


## Turns a resolved action descriptor into a real effect against `world`,
## adding whatever was gathered into `inventory` (an npc_inventory.gd-shaped
## Dictionary) and returning a clear result. Pure with respect to
## `inventory` -- never mutates the Dictionary passed in, matching
## npc_inventory.gd's own add()/remove() contract; the caller stores
## `result["inventory"]` on success.
##
## Only performs the FETCH half of `haul` -- finding a real source and
## moving it into the NPC's own inventory. Actually carrying it on to
## `destination_tag` is the flagged, unresolved "haul's carry-phase state"
## open question (concept doc, Execution/wiring) -- not attempted here;
## NpcMarker's existing `_entry_for_instructed_action` already walks the NPC
## toward `destination_tag`, this module only makes what it's carrying real.
##
## Returns one of:
##   {"ok": true, "inventory": Dictionary, "resource_id": String, "amount": int}
##   {"ok": false, "reason": "unsupported_resource", "resource_id": String}
##   {"ok": false, "reason": "not_found", "resource_id": String}
static func dispatch(action: Dictionary, world, npc_position: Vector2, inventory: Dictionary) -> Dictionary:
	var resource_id := _resource_id_for(action)
	if _STONE_FAMILY.has(resource_id):
		return _gather_stone(resource_id, world, npc_position, inventory)
	if _FRUIT_FAMILY.has(resource_id):
		return _gather_fruit(resource_id, world, npc_position, inventory)
	return {"ok": false, "reason": "unsupported_resource", "resource_id": resource_id}


## The resource id a resolved action names -- haul's `item`, or gather's
## `resource_tag`. "" for an action shape this module doesn't recognise at
## all; dispatch() fails closed on that just like any other unmapped id.
static func _resource_id_for(action: Dictionary) -> String:
	match action.get("fn", ""):
		"haul":
			return String(action.get("item", ""))
		"gather":
			return String(action.get("resource_tag", ""))
	return ""


static func _gather_stone(resource_id: String, world, npc_position: Vector2, inventory: Dictionary) -> Dictionary:
	if world == null or not world.has_method("nearest_liftable_stone_near"):
		return {"ok": false, "reason": "not_found", "resource_id": resource_id}
	var stone = world.nearest_liftable_stone_near(npc_position, GATHER_RADIUS_PX)
	if stone == null:
		return {"ok": false, "reason": "not_found", "resource_id": resource_id}
	if stone.has_method("queue_free"):
		stone.queue_free()
	return {
		"ok": true,
		"inventory": NpcInventory.add(inventory, resource_id, GATHER_YIELD),
		"resource_id": resource_id,
		"amount": GATHER_YIELD,
	}


static func _gather_fruit(resource_id: String, world, npc_position: Vector2, inventory: Dictionary) -> Dictionary:
	if world == null or not world.has_method("harvest_peak_fruit_near"):
		return {"ok": false, "reason": "not_found", "resource_id": resource_id}
	var found: Dictionary = world.harvest_peak_fruit_near(npc_position, GATHER_RADIUS_PX)
	if found.is_empty():
		return {"ok": false, "reason": "not_found", "resource_id": resource_id}
	return {
		"ok": true,
		"inventory": NpcInventory.add(inventory, resource_id, GATHER_YIELD),
		"resource_id": resource_id,
		"amount": GATHER_YIELD,
	}
