extends RefCounted

## Pure, deterministic drop calculation for mining an ore node. Every strike
## produces some plain stone, plus (with a pickaxe) 1..N units of the node's ore
## item scaling with pickaxe power. Bare hands (power 0) chip off only stone.
##
## This is the stateless "what does one mined ore node drop" table; the stateful
## depletion/regeneration of a vein lives in mining_yield.gd, which does not fit
## here (that models a continuous resource pool, not discrete item drops).

## Plain stone always chipped off when mining an ore node.
const STONE_PER_MINE := 2

## Ore units guaranteed once any pickaxe is used (power > 0).
const BASE_ORE := 1

## Additional ore units per unit of pickaxe power (before the seeded roll).
const ORE_PER_POWER := 1.0

## Ore item id per ore type.
const ORE_ITEM := {
	"iron": "iron_ore",
	"copper": "copper_ore",
	"coal": "coal",
}


## Drops for mining one ore node of `ore_type` with a pickaxe of `pickaxe_power`,
## seeded by `seed_value`. Returns an Array of {item_id, count} dictionaries.
func yields(ore_type: String, pickaxe_power: float, seed_value: int) -> Array:
	var drops := [{"item_id": "stone", "count": STONE_PER_MINE}]
	if pickaxe_power <= 0.0:
		return drops

	var ore_item: String = ORE_ITEM.get(ore_type, "iron_ore")
	var ceiling := BASE_ORE + int(ceil(pickaxe_power * ORE_PER_POWER))
	# Seeded roll in [0, ceiling - BASE_ORE], added to the guaranteed base.
	var span := ceiling - BASE_ORE
	var extra := 0
	if span > 0:
		extra = absi(hash("%d_%s_ore_roll" % [seed_value, ore_type])) % (span + 1)
	var count := BASE_ORE + extra
	drops.append({"item_id": ore_item, "count": count})
	return drops
