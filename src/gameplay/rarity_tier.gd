extends RefCounted

## Rarity/Affix Tier System (docs/concept/items.md) -- the shared "how
## interesting is this item" vocabulary used by loot drops, crafting, and
## spell gems alike. Pure logic; layers on top of Item rather than modifying
## it, so it can be reused for gear, spells, or anything else that wants a
## rarity roll.

const TIERS := ["common", "uncommon", "rare", "legendary"]

## Roll upper bounds (roll < bound -> that tier), in ascending order:
## common 65%, uncommon next 25% (65..90), rare next 8% (90..98), legendary
## the remaining 2% (98..100).
const _TIER_BOUNDS := [
	["common", 0.65],
	["uncommon", 0.90],
	["rare", 0.98],
	["legendary", 1.0],
]

## Stat multiplier applied to a base stat for items of a given tier.
const _STAT_MULTIPLIERS := {
	"common": 1.0,
	"uncommon": 1.15,
	"rare": 1.35,
	"legendary": 1.75,
}

## Standard loot-rarity UI colors, one per tier.
const _TIER_COLORS := {
	"common": Color(0.65, 0.65, 0.65),
	"uncommon": Color(0.1, 0.75, 0.15),
	"rare": Color(0.15, 0.4, 0.95),
	"legendary": Color(0.95, 0.55, 0.05),
}

## Returned by tier_color() for a tier string not in TIERS.
const FALLBACK_COLOR := Color(1.0, 1.0, 1.0)

## Complexity-to-tier bounds (2026-07-15 brainstorm, docs/concept/magic.md
## "Spell gems are sealed IP, priced by complexity": "a gem's rarity/value
## derives from the spell's complexity and material cost"). Unlike roll_tier()
## (a random seed roll), tier_from_complexity() derives a tier directly from a
## numeric complexity/cost score -- e.g. spell_cost.gd's derived_base() --
## so a costlier-to-author spell is inherently rarer. Exact boundary values
## are pinned by tests/unit/test_rarity_tier.gd (test_tier_from_complexity_*),
## not eyeballed: a single cheap starter atom (derived_base ~2-3) stays
## common, and only compositions with real breadth/power cross into legendary.
const COMPLEXITY_COMMON_MAX := 10.0
const COMPLEXITY_UNCOMMON_MAX := 25.0
const COMPLEXITY_RARE_MAX := 50.0


## Deterministic rarity tier for a given seed_value, weighted heavily toward
## "common" (see _TIER_BOUNDS for the exact thresholds).
func roll_tier(seed_value: int) -> String:
	var roll := float(absi(hash("%d_rarity_tier" % seed_value)) % 10000) / 10000.0
	for entry in _TIER_BOUNDS:
		if roll < entry[1]:
			return entry[0]
	return "legendary"


## Multiplier applied to a base stat for items of this tier; 1.0 for an
## unrecognized tier so callers degrade to an unmodified stat rather than
## crashing.
func stat_multiplier(tier: String) -> float:
	return _STAT_MULTIPLIERS.get(tier, 1.0)


## Representative UI color for this tier; FALLBACK_COLOR for an unrecognized
## tier rather than crashing.
func tier_color(tier: String) -> Color:
	return _TIER_COLORS.get(tier, FALLBACK_COLOR)


## Rarity tier derived from a numeric complexity/cost score (e.g. a spell
## gem's spell_cost.gd derived_base()) rather than a random roll -- see
## COMPLEXITY_*_MAX above. Monotonic: complexity never buys a *lower* tier.
func tier_from_complexity(complexity: float) -> String:
	if complexity < COMPLEXITY_COMMON_MAX:
		return "common"
	if complexity < COMPLEXITY_UNCOMMON_MAX:
		return "uncommon"
	if complexity < COMPLEXITY_RARE_MAX:
		return "rare"
	return "legendary"
