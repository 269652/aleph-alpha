extends RefCounted

## A saved Hauling Contract TEMPLATE that decides WHEN to redispatch (see
## docs/concept/player_trade.md's "Trade Route (autotrading)") -- design
## pillar 4: no separate route simulation exists, `is_due` just gates
## dispatching a fresh, ordinary HaulingContract via build_contract(). The
## same "cheap due-check every tick, real work only when due" shape
## ConstructionPriority's own settlement-build gating already uses.
##
## A glue call site (not built yet) checks every saved route each real
## world-time step and dispatches build_contract() for any that's due --
## deliberately does NOT auto-cancel on insufficient stock: a route that
## can't currently be fulfilled just skips that tick and tries again next
## interval, the same "a real production failure caused by a real
## shortage, not a scripted event" philosophy Market.produce's own doc
## comment already commits to. Whether stock is sufficient is the call
## site's own job (PlayerTradeOffer.can_sell/can_buy), not this class's.

const HaulingContract = preload("res://src/gameplay/hauling_contract.gd")

var warehouse_position: Vector2
var settlement_id: String
var item_id: String
var count: int
var direction: int
var interval_seconds: float
## -1.0 for "never yet dispatched" -- never a real world age, matching
## DiscoveredSettlements.discovered_at's own "not a real value" sentinel.
var last_dispatched_age := -1.0


func _init(
	p_warehouse_position: Vector2, p_settlement_id: String, p_item_id: String, p_count: int,
	p_direction: int, p_interval_seconds: float
) -> void:
	warehouse_position = p_warehouse_position
	settlement_id = p_settlement_id
	item_id = p_item_id
	count = p_count
	direction = p_direction
	interval_seconds = p_interval_seconds


func is_due(world_age: float) -> bool:
	if last_dispatched_age < 0.0:
		return true
	return world_age - last_dispatched_age >= interval_seconds


func mark_dispatched(world_age: float) -> void:
	last_dispatched_age = world_age


## Builds the fresh HaulingContract this route's terms describe -- the
## caller supplies everything this route doesn't itself track (the
## settlement's current real position, the PlayerTradeOffer quote locked
## in at this moment, the current world age, and the raid roll), the same
## "pure builder, caller supplies what varies" shape SerialCodec.
## encode_payload already uses.
func build_contract(
	settlement_position: Vector2, unit_price: float, departure_age: float,
	raided: bool, raid_fraction: float
) -> HaulingContract:
	return HaulingContract.new(
		warehouse_position, settlement_id, settlement_position, item_id, count,
		direction, unit_price, departure_age, raided, raid_fraction
	)
