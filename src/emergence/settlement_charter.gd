extends RefCounted

## docs/concept/settlement_charter.md: which buildings a settlement's own
## TIER entitles it to raise, and what it is still short of when it is not.
##
## Asked for directly: a mage guild only a CITY may build, so that helping
## a village grow is how a player gets access to one. That makes this a
## progression system whose currency is somebody else's prosperity -- the
## player unlocks the guild by making a place big enough, organised enough
## and productive enough to hold one, never by levelling.
##
## **This module introduces no new measure and no new number.**
## SettlementTier already reads households, ACTIVE institutions and
## production diversity, and already requires all three to cross together.
## That rule was written long before this and is exactly what makes "help
## them grow" a real errand: a player can carry in a hundred meals and
## still not have a city, because a city is also trades that organised
## themselves and goods that are actually being made.
##
## Pure and static, the same shape SettlementTier/VillageEstates already
## have.

const SettlementTier = preload("res://src/emergence/settlement_tier.gd")

## `building_id -> the lowest tier that may raise it`. A building ABSENT
## from this table has no charter requirement and may be raised anywhere,
## which is every building that existed before this doc.
##
## Two entries, at two different tiers, so the mechanism is demonstrated
## rather than special-cased -- and both grounded in systems that already
## exist rather than invented to fill a table. See the doc's own table for
## the grounding; in short, the guild hall is the house of the `guild`
## institutions InstitutionStore already forms, and the mage guild is the
## compile station docs/concept/magic.md has carried as an open question
## since it was written.
const MIN_TIER_BY_BUILDING := {
	"trade_hall": SettlementTier.TOWN,
	"mage_guild": SettlementTier.CITY,
}

## The per-tier thresholds, read straight off SettlementTier so there is
## ONE statement of what a town or a city is. A tier absent here asks
## nothing of anybody, which is the honest reading for the lowest rung:
## a hamlet is what a place is when it has cleared nothing.
const _THRESHOLDS := {
	SettlementTier.TOWN: {
		"households": SettlementTier.TOWN_HOUSEHOLDS,
		"institutions": SettlementTier.TOWN_INSTITUTIONS,
		"production_diversity": SettlementTier.TOWN_PRODUCTION_DIVERSITY,
	},
	SettlementTier.CITY: {
		"households": SettlementTier.CITY_HOUSEHOLDS,
		"institutions": SettlementTier.CITY_INSTITUTIONS,
		"production_diversity": SettlementTier.CITY_PRODUCTION_DIVERSITY,
	},
}


## The lowest tier that may raise `building_id`, or "" for a building
## nothing charters.
static func min_tier_for(building_id: String) -> String:
	return MIN_TIER_BY_BUILDING.get(building_id, "")


## A tier's place in the ladder; -1 for anything that is not one, so an
## unknown tier sits BELOW every real one and is refused everything
## chartered rather than accidentally allowed it.
static func tier_rank(tier: String) -> int:
	return SettlementTier.TIERS.find(tier)


## Whether a settlement at `tier` may raise `building_id`.
static func allows(building_id: String, tier: String) -> bool:
	var required := min_tier_for(building_id)
	if required == "":
		return true
	return tier_rank(tier) >= tier_rank(required)


## The tier above this one, or "" at the top (and for an unknown tier) --
## so a readout can name the errand without knowing the ladder itself.
static func next_tier_above(tier: String) -> String:
	var rank := tier_rank(tier)
	if rank < 0 or rank + 1 >= SettlementTier.TIERS.size():
		return ""
	return SettlementTier.TIERS[rank + 1]


## What a settlement is still short of, per dimension, to reach `tier`.
## Never negative: a dimension already cleared is short by NOTHING, because
## a readout saying "-3 households" is worse than no readout at all. `{}`
## for a tier that asks nothing (the lowest rung) or that is not a tier.
static func shortfall_to(
	tier: String, households: int, institutions: int, production_diversity: int
) -> Dictionary:
	if not _THRESHOLDS.has(tier):
		return {}
	var wants: Dictionary = _THRESHOLDS[tier]
	return {
		"households": maxi(int(wants["households"]) - households, 0),
		"institutions": maxi(int(wants["institutions"]) - institutions, 0),
		"production_diversity": maxi(int(wants["production_diversity"]) - production_diversity, 0),
	}


## `{}` when this settlement may raise `building_id`; otherwise the refusal
## that TEACHES (the doc's pillar 3):
##
##   building_id    what was refused
##   required_tier  the tier it wants
##   tier           the tier this settlement actually holds
##   short          what is still missing, per dimension
##
## "You cannot build that here" is a dead end and a bad game. A player
## refused a mage guild in a town should leave knowing they need two more
## households and one more trade body, and go and do it.
static func refusal_for(
	building_id: String, households: int, institutions: int, production_diversity: int
) -> Dictionary:
	var required := min_tier_for(building_id)
	if required == "":
		return {}
	var tier := SettlementTier.tier_for(households, institutions, production_diversity)
	if allows(building_id, tier):
		return {}
	return {
		"building_id": building_id,
		"required_tier": required,
		"tier": tier,
		"short": shortfall_to(required, households, institutions, production_diversity),
	}
