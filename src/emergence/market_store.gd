extends RefCounted

## One Market per settlement -- "local buyer/seller matching systems... do
## not use one global price" (docs/emergence/03), so markets are keyed by
## settlement the same way HouseholdStore/ContractStore are keyed by
## whatever real entity they belong to.

const Market = preload("res://src/emergence/market.gd")

var _markets: Dictionary = {}   # settlement_id -> Market


## The market for `settlement_id`, creating a fresh empty one on first
## access -- idempotent, the same shape HouseholdStore.form_household
## already uses, so a second call never silently discards stock the first
## call's market already holds.
func market_for(settlement_id: String) -> Market:
	if not _markets.has(settlement_id):
		_markets[settlement_id] = Market.new()
	return _markets[settlement_id]


## For MarketStorePersistence -- pure serialization, no FileAccess (same
## split EventStore/EventStorePersistence already use).
func to_dicts() -> Array:
	var out: Array = []
	for settlement_id in _markets:
		out.append({"settlement_id": settlement_id, "market": _markets[settlement_id].to_dict()})
	return out


static func from_dicts(dicts: Array) -> RefCounted:
	var store = new()
	for d in dicts:
		store._markets[d.get("settlement_id", "")] = Market.from_dict(d.get("market", {}))
	return store
