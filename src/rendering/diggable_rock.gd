extends StaticBody2D

## A real underground rock cell, revealed inside a cave chamber (see
## GeologyChamber / docs/concept/geology.md "Reveal-on-entry, reused
## recursively"). Mirrors MinableOre's shape exactly -- same "stone" swing
## group, same mine()-drops-via-WorldItemBus-then-queue_free contract, same
## hover-tooltip contract -- because it is the underground counterpart of
## exactly that node: a SOLID cell mines like a plain boulder (stone only),
## an ORE cell mines like an ore-bearing boulder (stone + ore scaled by
## pickaxe power, see OreYield).
##
## Unlike a surface stone/ore node, mining this also writes back into the
## chunk's own Strata instance (`strata.mine_at`) -- the cell must read as
## TUNNEL forever after, even once this node itself is gone, so a chamber
## re-revealed later shows the tunnel rather than a freshly-solid cell.

const Item = preload("res://src/gameplay/item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")
const OreYield = preload("res://src/gameplay/ore_yield.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const Strata = preload("res://src/world/strata.gd")

const GROUP_NAME := "stone"

## Plain stone yielded by a SOLID cell -- same figure OreYield.STONE_PER_MINE
## uses for the stone chipped off an ore node, so a plain rock cell pays the
## same base rate an ore cell's non-ore half already does.
const STONE_PER_SOLID_MINE := 2

## Set by GeologyChamber at spawn time. `strata`/`local_cell` are what
## mine() writes the permanent TUNNEL state back into; `kind` is cached at
## spawn (SOLID or ORE) rather than re-read from strata every time, since a
## node only ever exists for a cell strata itself reports as not-yet-mined.
var strata: Strata
var local_cell: Vector2i
var kind: String = Strata.KIND_SOLID
var ore_type := "iron"
var ore_seed := 0

var _ore_yield := OreYield.new()
var _item_catalog := ItemCatalog.new()


func _ready() -> void:
	add_to_group(GROUP_NAME)
	add_to_group(HoverTargetFinder.GROUP_NAME)


## For World's mouse-hover tooltip (see HoverTargetFinder). Same
## ore-item-name lookup as MinableOre.get_display_name for an ORE cell; a
## SOLID cell is just "Rock".
func get_display_name() -> String:
	if kind != Strata.KIND_ORE:
		return "Rock"
	var ore_item_id := ore_type + "_ore"
	if _item_catalog.has(ore_item_id):
		return _item_catalog.make(ore_item_id).display_name
	if _item_catalog.has(ore_type):
		return _item_catalog.make(ore_type).display_name
	return ore_type.capitalize()


## Bound to "attack" -- mining underground rock shares the same swing every
## other world-object interaction in this project uses (see CLAUDE.md's
## house style, MinableOre.get_hover_actions).
func get_hover_actions() -> Array:
	return [{"verb": "Mine", "action": "attack"}]


## Mines the node with a pickaxe of `pickaxe_power` (0 = bare hands, stone
## only for either kind). Drops every yielded item stack into the world,
## marks the underlying Strata cell as a permanent tunnel, and frees the
## node -- the exact MinableOre contract, plus the Strata write-back.
func mine(pickaxe_power: float) -> void:
	var drops: Array = (
		_ore_yield.yields(ore_type, pickaxe_power, ore_seed) if kind == Strata.KIND_ORE
		else [{"item_id": "stone", "count": STONE_PER_SOLID_MINE}]
	)
	var offset := Vector2.ZERO
	for drop in drops:
		WorldItemBus.item_dropped.emit(_stack_for(drop), position + offset)
		offset += Vector2(6, 4)
	if strata != null:
		strata.mine_at(local_cell)
	queue_free()


func _stack_for(drop: Dictionary) -> ItemStack:
	var item_id: String = drop["item_id"]
	var item := _item_catalog.make(item_id) if _item_catalog.has(item_id) else Item.new(item_id, item_id, "material", 40)
	return ItemStack.new(item, drop["count"])
