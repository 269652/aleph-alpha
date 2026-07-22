extends RefCounted

## Deterministic ore-deposit placement layered on top of StonePlacement. Ore
## nodes are a rarer subset of the plain-stone cells: a cell that already
## carries a boulder (StonePlacement.has_stone_at) has an ORE_FRACTION chance of
## being upgraded to an ore-bearing boulder instead. The orchestrator checks
## is_ore_at first, so a cell is never both a plain stone and an ore node.

const StonePlacement = preload("res://src/world/stone_placement.gd")

const ORE_TYPES: Array[String] = ["iron", "copper", "coal"]

## Fraction of stone cells that become ore nodes (~0.3 of boulders).
const ORE_FRACTION := 0.3

var _stone_placement := StonePlacement.new()


## Whether an ore node sits at this global tile. Only ever true where a plain
## stone already exists, and rarer than plain stone by ORE_FRACTION.
func is_ore_at(global_x: int, global_y: int, biome_name: String) -> bool:
	if not _stone_placement.has_stone_at(global_x, global_y, biome_name):
		return false
	var value := float(absi(hash("%d_%d_ore" % [global_x, global_y])) % 10000) / 10000.0
	return value < ORE_FRACTION


## Deterministic ore type for this cell. Independent of is_ore_at so callers can
## query it freely; only meaningful where is_ore_at is true.
func ore_type_at(global_x: int, global_y: int) -> String:
	var idx := absi(hash("%d_%d_ore_type" % [global_x, global_y])) % ORE_TYPES.size()
	return ORE_TYPES[idx]


## Deterministic per-tile seed for this ore node's sprite variation.
func seed_at(global_x: int, global_y: int) -> int:
	return hash("%d_%d_ore_seed" % [global_x, global_y])
