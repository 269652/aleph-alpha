extends RefCounted

## One real, player-dispatched shipment between a Warehouse and a
## discovered settlement (see docs/concept/player_trade.md's "Hauling
## Contract"). Deliberately mirrors CaravanTrip's own pure travel math
## byte-for-byte (same WALK_SPEED_PX_PER_SEC, same progress_at/
## position_at/is_arrived/raid_triggered shape) rather than inventing a
## second travel model -- a Hauling Contract IS a caravan trip, just
## player-initiated instead of autonomous, plus the trade terms (item,
## count, direction, price) a settlement-to-settlement CaravanTrip never
## needed.
##
## Pure data + pure math only, same split every other creature/NPC/
## shipment behaviour in this codebase uses -- a thin HaulingMarker
## Node2D (not built yet, see docs/concept/player_trade.md's Status) would
## drive visible movement off this the same way CaravanMarker already
## drives off CaravanTrip. Whether/where this trip is raided is decided
## by the CALLER (CaravanRaid's own hash-derived rolls, unchanged) and
## handed in here as plain raided/raid_fraction values, exactly like
## CaravanTrip -- this class doesn't know how a raid roll is derived,
## only how to report when one lands.
##
## No mutable "resolved" status of its own, matching CaravanTrip: a
## caller queries is_arrived/raid_triggered against the current world age
## each time and decides what to do (credit the settlement's Market, pay
## the player's Wallet, scatter the goods) -- resolving a contract exactly
## once and removing it from an active list is the caller's job, the same
## split EarthChunkManager.step_caravans already owns for CaravanTrip.

## Same ordinary on-foot NPC pace as CaravanTrip.WALK_SPEED_PX_PER_SEC --
## a Hauling Contract's courier is a porter walking the route, not a
## driven vehicle, exactly like a regional-trade caravan (see
## docs/concept/transportation.md: no cart/wagon vehicle exists yet).
const WALK_SPEED_PX_PER_SEC := 20.0

enum Direction { SELL, BUY }

var warehouse_position: Vector2
var settlement_id: String
var settlement_position: Vector2
var item_id: String
var count: int
var direction: int
## The PlayerTradeOffer quote locked in at dispatch -- NOT re-read on
## arrival (see docs/concept/player_trade.md: a trip's terms are sealed
## the moment it departs, same discipline trade.md already commits to for
## NPC caravans).
var unit_price: float
var departure_age: float
var raided: bool
var raid_fraction: float


func _init(
	p_warehouse_position: Vector2, p_settlement_id: String, p_settlement_position: Vector2,
	p_item_id: String, p_count: int, p_direction: int, p_unit_price: float,
	p_departure_age: float, p_raided: bool, p_raid_fraction: float
) -> void:
	warehouse_position = p_warehouse_position
	settlement_id = p_settlement_id
	settlement_position = p_settlement_position
	item_id = p_item_id
	count = p_count
	direction = p_direction
	unit_price = p_unit_price
	departure_age = p_departure_age
	raided = p_raided
	raid_fraction = p_raid_fraction


## Total real seconds this contract's route takes end to end, at walking
## pace. 0.0 for a same-position contract counts as already arrived (see
## progress_at's own guard), not a divide-by-zero.
func travel_seconds() -> float:
	return warehouse_position.distance_to(settlement_position) / WALK_SPEED_PX_PER_SEC


## [0, 1] how far along the route `world_age` puts this contract -- 0 at
## departure, 1 once it has fully walked the distance. Clamped, so a
## query long after arrival still reads as exactly done.
func progress_at(world_age: float) -> float:
	var total := travel_seconds()
	if total <= 0.0:
		return 1.0
	return clampf((world_age - departure_age) / total, 0.0, 1.0)


## Real current position along the straight route from the Warehouse to
## the settlement -- the same lerp every other marker in this codebase
## walks a route with.
func position_at(world_age: float) -> Vector2:
	return warehouse_position.lerp(settlement_position, progress_at(world_age))


func is_arrived(world_age: float) -> bool:
	return progress_at(world_age) >= 1.0


## Whether `world_age` has reached the real point along the route this
## contract's raid actually happens -- always false for a contract that
## was never raided to begin with.
func raid_triggered(world_age: float) -> bool:
	return raided and progress_at(world_age) >= raid_fraction


## The full amount owed/paid for this contract -- unit_price already
## reflects PlayerTradeOffer's buy/sell spread, locked in at dispatch.
func total_price() -> float:
	return float(count) * unit_price
