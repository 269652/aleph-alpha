extends RefCounted

## Raid-risk math for one real caravan trip (docs/concept/trade.md, the
## "real raid risk" half that builds on top of docs/concept/regional_trade.md's
## already-real nearest-supplier resupply). Reuses RegionDifficulty's own
## existing distance-from-spawn danger tiers instead of inventing a second
## danger scale, the same "reuse a real signal" discipline RegionalTrade
## already applies to shortage/surplus.
##
## No RandomNumberGenerator (see DesertScrub's own doc comment on why): a
## trip's outcome is hash-derived from its own real identity (who shipped
## what to whom, and when), so the SAME trip always resolves the SAME way no
## matter how many times a caller re-derives it -- not engine RNG state that
## a save/reload or a second query could see differently.

const RegionDifficulty = preload("res://src/world/region_difficulty.gd")

## Per-trip raid probability by region tier. EASY (RegionDifficulty's own
## "same metro area" band around the world's spawn point) is a genuinely
## safe first supply line -- nothing raids a shipment a few chunks from
## home. HARD carries real, felt risk (roughly one trip in five) without
## regional trade collapsing into a coin flip; MEDIUM sits between the two.
## Test-pinned (test_caravan_raid.gd) -- no real-world banditry statistic
## exists to derive these from, the same honesty RegionalTrade.MIN_SURPLUS's
## own comment already states for its number.
const RAID_CHANCE := {
	RegionDifficulty.Tier.EASY: 0.0,
	RegionDifficulty.Tier.MEDIUM: 0.08,
	RegionDifficulty.Tier.HARD: 0.22,
}


## `tier`'s real raid probability -- HARD (an unrecognized/out-of-range tier
## included) if `tier` isn't one of the three known ones, the same
## fail-dangerous default RegionDifficulty._difficulty_tier_at itself uses
## for an unconfigured world.
static func raid_chance_for_tier(tier: int) -> float:
	return RAID_CHANCE.get(tier, RAID_CHANCE[RegionDifficulty.Tier.HARD])


## Whether a trip through `tier` is raided, given one deterministic `roll`
## in [0, 1) -- see roll_for for where that roll actually comes from.
static func is_raided(tier: int, roll: float) -> bool:
	return roll < raid_chance_for_tier(tier)


## One deterministic, real-identity-derived roll in [0, 1). `salt`
## distinguishes independent rolls drawn for the SAME trip (e.g. "did it get
## raided at all" vs. "where along the route") so they don't collapse to the
## same value -- the same per-purpose hash-seeding convention
## SettlementGenerator._house_position's own _unit_float helper already
## uses per house/purpose.
static func roll_for(
	supplier_id: String, shortage_settlement_id: String, item_id: String,
	departure_age: float, salt: String
) -> float:
	var h := hash("%s|%s|%s|%.3f|%s" % [supplier_id, shortage_settlement_id, item_id, departure_age, salt])
	return float(absi(h) % 1000000) / 1000000.0
