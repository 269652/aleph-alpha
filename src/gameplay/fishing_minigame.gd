extends RefCounted

## Fishing catching minigame + bait/lure system (docs/concept/fishing.md). Pure
## logic, no wall-clock dependency -- callers pass in a seed_value and/or
## caller-measured real seconds, following this codebase's hash-fraction
## determinism pattern (see TreeGenome._trait_fraction) rather than
## randi()/randf().

const MIN_BITE_DELAY := 2.0
const MAX_BITE_DELAY := 15.0

## Rarity roll upper bounds (roll < bound -> that tier), in ascending order.
## common 60%, uncommon next 25% (60..85), rare next 12% (85..97),
## legendary the remaining 3% (97..100).
const _RARITY_BOUNDS := [
	["common", 0.60],
	["uncommon", 0.85],
	["rare", 0.97],
	["legendary", 1.0],
]


## Deterministic seconds until a bite, in [MIN_BITE_DELAY, MAX_BITE_DELAY].
## Higher bait_quality (0..1) biases toward the shorter end of the range.
func bite_delay(seed_value: int, bait_quality: float) -> float:
	var roll := float(absi(hash("%d_bite_delay" % seed_value)) % 10000) / 10000.0
	var quality := clampf(bait_quality, 0.0, 1.0)
	var biased_roll := roll * (1.0 - quality)
	return lerpf(MIN_BITE_DELAY, MAX_BITE_DELAY, biased_roll)


## True if the player reacted within the bite window (reaction_time <=
## bite_window); equality counts as a successful catch.
func attempt_catch(reaction_time: float, bite_window: float) -> bool:
	return reaction_time <= bite_window


## Deterministic rarity tier for a catch, weighted heavily toward "common"
## (see _RARITY_BOUNDS for the exact thresholds).
func fish_rarity(seed_value: int) -> String:
	var roll := float(absi(hash("%d_fish_rarity" % seed_value)) % 10000) / 10000.0
	for entry in _RARITY_BOUNDS:
		if roll < entry[1]:
			return entry[0]
	return "legendary"
