extends RefCounted

## Station-tier gating of blueprint complexity (docs/concept/crafting.md):
## higher-tier stations unlock more advanced blueprints. Tier 0 means
## "no station"/hand-craftable only and is never assigned to a real station.

const STATION_TIERS: Dictionary = {
	"campfire": 1,
	"forge": 2,
	"arcane_altar": 3,
}


## Returns the station's tier, or 0 for an unknown station_id.
func tier_of(station_id: String) -> int:
	if STATION_TIERS.has(station_id):
		return STATION_TIERS[station_id]
	return 0


## True if station_id's tier meets or exceeds required_tier.
func can_craft_at(station_id: String, required_tier: int) -> bool:
	return tier_of(station_id) >= required_tier


## Every defined station_id.
func station_ids() -> Array:
	return STATION_TIERS.keys()


## Every station_id whose tier meets or exceeds required_tier, sorted alphabetically.
func stations_at_or_above(required_tier: int) -> Array:
	var result: Array = []
	for station_id in STATION_TIERS:
		if STATION_TIERS[station_id] >= required_tier:
			result.append(station_id)
	result.sort()
	return result
