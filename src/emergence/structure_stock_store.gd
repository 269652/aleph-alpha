extends RefCounted

## One StructureStock per placed structure instance -- mirrors MarketStore's
## "one Market per settlement, keyed by settlement id" shape exactly
## (src/emergence/market_store.gd), keyed instead by the structure's own
## position string (EarthChunkManager builds this key from a global tile
## coordinate -- see structure_stock_at/deposit_to_structure_at). Two
## structures standing right next to each other must never share a stock,
## the same way two settlements' markets don't.
##
## Serves both a Storage building's real player/logistics-visible inventory
## AND (see StructureStock's own doc comment) any future production
## building's own accumulated-output queue -- one store, one shape, keyed by
## position, regardless of which structure id sits there.

const StructureStock = preload("res://src/emergence/structure_stock.gd")

var _stocks: Dictionary = {}   # instance_key -> StructureStock


## The stock for `instance_key`, creating a fresh empty one on first access --
## idempotent, the same shape MarketStore.market_for already uses, so a
## second call never silently discards stock the first call's object holds.
func stock_for(instance_key: String) -> StructureStock:
	if not _stocks.has(instance_key):
		_stocks[instance_key] = StructureStock.new()
	return _stocks[instance_key]


## For persistence -- pure serialization, no FileAccess (same split
## EventStore/EventStorePersistence and MarketStore/MarketStorePersistence
## already use).
func to_dicts() -> Array:
	var out: Array = []
	for instance_key in _stocks:
		out.append({"instance_key": instance_key, "stock": _stocks[instance_key].to_dict()})
	return out


static func from_dicts(dicts: Array) -> RefCounted:
	var store = new()
	for d in dicts:
		store._stocks[d.get("instance_key", "")] = StructureStock.from_dict(d.get("stock", {}))
	return store
