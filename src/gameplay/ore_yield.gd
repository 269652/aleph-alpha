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

## How far luck (see docs/concept/karma_and_luck.md, always in [-1, 1]) can
## shift the extra-ore roll's own position within its [0, span] range: at
## full good luck the roll's normalized position moves up by this much
## (capped at the top of the range), at full bad luck it moves down by the
## same amount (capped at the bottom). The roll itself stays the same
## deterministic per-seed draw -- luck only relocates where that draw lands,
## the same "nudge an existing formula, never invent a new one" shape
## Taming.break_free_chance's own luck parameter uses.
const LUCK_ORE_ROLL_SHIFT_FRACTION := 0.5

## Ore item id per ore type.
const ORE_ITEM := {
	"iron": "iron_ore",
	"copper": "copper_ore",
	"coal": "coal",
}


## Drops for mining one ore node of `ore_type` with a pickaxe of `pickaxe_power`,
## seeded by `seed_value`. Returns an Array of {item_id, count} dictionaries.
##
## `luck` (Player.luck(), see docs/concept/karma_and_luck.md -- always in
## [-1, 1]) shifts the extra-ore roll's own position within its [0, span]
## range by up to LUCK_ORE_ROLL_SHIFT_FRACTION, never the guaranteed base:
## bad luck can only make bonus ore rarer, it can never take away ore a swing
## already earned. At luck 0 this is a no-op (round() recovers the exact
## original roll), so a character with neutral karma sees byte-identical
## drops to before this parameter existed (see test_yields_is_unchanged_
## with_zero_luck).
func yields(ore_type: String, pickaxe_power: float, seed_value: int, luck: float = 0.0) -> Array:
	var drops := [{"item_id": "stone", "count": STONE_PER_MINE}]
	if pickaxe_power <= 0.0:
		return drops

	var ore_item: String = ORE_ITEM.get(ore_type, "iron_ore")
	var ceiling := BASE_ORE + int(ceil(pickaxe_power * ORE_PER_POWER))
	# Seeded roll in [0, ceiling - BASE_ORE], added to the guaranteed base.
	var span := ceiling - BASE_ORE
	var extra := 0
	if span > 0:
		var raw_roll := absi(hash("%d_%s_ore_roll" % [seed_value, ore_type])) % (span + 1)
		var raw_fraction := float(raw_roll) / float(span)
		var shift := clampf(luck, -1.0, 1.0) * LUCK_ORE_ROLL_SHIFT_FRACTION
		var biased_fraction := clampf(raw_fraction + shift, 0.0, 1.0)
		extra = int(round(biased_fraction * span))
	var count := BASE_ORE + extra
	drops.append({"item_id": ore_item, "count": count})
	return drops
