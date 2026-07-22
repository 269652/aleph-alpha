extends RefCounted

## POI Loot Rarity Integration (concept/exploration.md "POI Loot Rarity
## Integration") -- scales loot quality and quantity by a point-of-interest's
## danger tier. Layers on top of rarity_tier.gd's TIERS ordering (see
## src/gameplay/rarity_tier.gd) rather than modifying it, so a POI danger
## level just names a floor into that existing rarity index space.

## danger level -> {min_rarity_index into RarityTier.TIERS, loot_count_bonus}.
## Higher danger has a higher floor and a bigger loot count bonus.
const POI_DANGER_LEVELS := {
	"low": {"min_rarity_index": 0, "loot_count_bonus": 0},
	"medium": {"min_rarity_index": 1, "loot_count_bonus": 1},
	"high": {"min_rarity_index": 2, "loot_count_bonus": 2},
	"extreme": {"min_rarity_index": 3, "loot_count_bonus": 4},
}


## Lowest rarity index guaranteed at this danger level; 0 (common) for an
## unknown level rather than crashing.
func min_guaranteed_rarity(poi_danger_level: String) -> int:
	if not POI_DANGER_LEVELS.has(poi_danger_level):
		return 0
	return POI_DANGER_LEVELS[poi_danger_level]["min_rarity_index"]


## base_count plus this danger level's loot count bonus; base_count
## unmodified for an unknown level rather than crashing.
func loot_count_for(poi_danger_level: String, base_count: int) -> int:
	if not POI_DANGER_LEVELS.has(poi_danger_level):
		return base_count
	return base_count + POI_DANGER_LEVELS[poi_danger_level]["loot_count_bonus"]
