extends RefCounted

## One real in-flight shipment between two real settlements' markets -- the
## "goods really in transit, real risk" half of docs/concept/trade.md, built
## on top of docs/concept/regional_trade.md's already-real nearest-supplier
## resupply. Where RegionalTrade only decides WHICH settlement resupplies
## whom, this decides the real walk in between: the supplier's stock is
## already gone (deducted at departure, unchanged), but the shortage
## settlement's stock and the "shipped" event only become real once a trip
## like this actually finishes walking there -- or the goods scatter into
## the world if raided instead (see CaravanRaid).
##
## Pure data + pure math only, same split every other creature/NPC behaviour
## in this codebase uses (a pure module decides WHEN, a thin Node2D marker
## supplies the actual engine effect -- see CarrionForageBehavior +
## DecomposerMarker). Whether/where a trip is raided is decided by the
## CALLER (EarthChunkManager, via CaravanRaid's own hash-derived rolls) and
## handed in here as plain raided/raid_fraction values -- this class doesn't
## know how a raid roll is derived, only how to report when one lands.

## Walking pace -- the same ordinary on-foot NPC speed as NpcMarker.WALK_SPEED.
## No cart/wagon vehicle exists yet (docs/concept/transportation.md only
## models boats, horses-as-mounts, and fast travel) -- a caravan is a porter
## walking the route, not a driven vehicle, so it gets no speed bonus over
## any other NPC on foot.
const WALK_SPEED_PX_PER_SEC := 20.0

var supplier_id: String
var shortage_settlement_id: String
var item_id: String
var count: int
var origin: Vector2
var destination: Vector2
var departure_age: float
var tier: int

## Precomputed at construction (see CaravanRaid.is_raided/roll_for) -- not
## re-rolled on every query, so a trip's fate is fixed the moment it departs,
## exactly like a real shipment's fate is sealed once it's on the road.
var raided: bool
## Only meaningful when raided: how far along [0, 1) the route the raid
## happens.
var raid_fraction: float


func _init(
	p_supplier_id: String, p_shortage_settlement_id: String, p_item_id: String, p_count: int,
	p_origin: Vector2, p_destination: Vector2, p_departure_age: float, p_tier: int,
	p_raided: bool, p_raid_fraction: float
) -> void:
	supplier_id = p_supplier_id
	shortage_settlement_id = p_shortage_settlement_id
	item_id = p_item_id
	count = p_count
	origin = p_origin
	destination = p_destination
	departure_age = p_departure_age
	tier = p_tier
	raided = p_raided
	raid_fraction = p_raid_fraction


## Total real seconds this trip's route takes end to end, at walking pace.
## 0.0 for a same-position trip counts as already arrived (see progress_at's
## own guard), not a divide-by-zero.
func travel_seconds() -> float:
	return origin.distance_to(destination) / WALK_SPEED_PX_PER_SEC


## [0, 1] how far along the route `world_age` puts this trip -- 0 at
## departure, 1 once it has fully walked the distance. Clamped, so a query
## long after arrival still reads as exactly done, not overshooting past 1.
func progress_at(world_age: float) -> float:
	var total := travel_seconds()
	if total <= 0.0:
		return 1.0
	return clampf((world_age - departure_age) / total, 0.0, 1.0)


## Real current position along the straight real route from origin to
## destination -- the same lerp every other marker in this codebase walks a
## route with.
func position_at(world_age: float) -> Vector2:
	return origin.lerp(destination, progress_at(world_age))


## The tile `position_at(world_age)` falls on, at `tile_size` -- the real
## PathScarring.step_on input a caller advances the caravan's route wear
## with (see EarthChunkManager.step_caravans). A plain floor-division tile
## conversion, the same one EarthChunkManager._world_tile_for_pixel already
## uses for every other pixel->tile lookup.
func tile_at(world_age: float, tile_size: int) -> Vector2i:
	var position := position_at(world_age)
	return Vector2i(floori(position.x / tile_size), floori(position.y / tile_size))


func is_arrived(world_age: float) -> bool:
	return progress_at(world_age) >= 1.0


## Whether `world_age` has reached the real point along the route this
## trip's raid actually happens -- always false for a trip that was never
## raided to begin with.
func raid_triggered(world_age: float) -> bool:
	return raided and progress_at(world_age) >= raid_fraction
