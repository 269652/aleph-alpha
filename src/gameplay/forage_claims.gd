extends RefCounted

## Which bloom each pollinator is currently flying to (see
## docs/concept/flora.md#pollinators-scatter-rather-than-queueing).
##
## Pollinators pick the nearest forageable bloom within a tight distance band
## (see PollinatorForaging.SCATTER_BAND_TILES), and scatter between the
## candidates in that band using a per-flyer seed. Measured in a real world,
## that band holds exactly ONE candidate 86.5% of the time -- so the scatter
## seed usually has nothing to choose between, every co-located flyer reaches
## the same answer, and 62.1% of pollinator pairs within four tiles of each
## other were flying to the same bloom. The leader drains it and the
## followers arrive at an empty flower (mean nectar on arrival: 0.182).
##
## Seeded scatter cannot fix that on its own -- with one candidate there is
## nothing to vary -- so pollinators need to know what their neighbours have
## already committed to. This is that shared knowledge, and nothing more: it
## records intent, not ownership. PollinatorForaging DEMOTES a claimed bloom
## rather than refusing it, so a claim never makes a flyer skip a closer
## flower or stall with nothing to do.
##
## Deliberately a plain RefCounted with no nodes, signals or scene
## dependencies: the chunk manager owns one and hands it around, the same way
## it owns the flower patches themselves.

## flyer instance id (int) -> the bloom it is heading for (Vector2, world
## pixels).
##
## Keying by FLYER rather than by bloom is what makes this structurally
## leak-proof: the table can never hold more entries than there are live
## pollinators, no matter how long a session runs or how many blooms get
## visited. Claiming again simply replaces that flyer's row, which also means
## a recycled instance id (Godot reuses them) takes over the dead flyer's
## slot instead of leaving a bloom claimed forever.
var _claims: Dictionary = {}

## Reserved id meaning "exclude nobody" in claimed_positions_near. Real
## instance ids are never 0.
const NO_FLYER := 0


func _init() -> void:
	pass


## Records that `flyer_id` is heading for `flower_position`, replacing
## whatever it was heading for before.
func claim(flower_position: Vector2, flyer_id: int) -> void:
	_claims[flyer_id] = flower_position


## Forgets `flyer_id`'s claim. Safe to call for a flyer that holds none, so
## callers can release unconditionally on abandon/despawn without checking.
func release(flyer_id: int) -> void:
	_claims.erase(flyer_id)


## Drops the claims of every flyer in `flyer_ids` -- the chunk-unload path,
## where a whole chunk's worth of pollinators is freed at once.
func release_many(flyer_ids: Array) -> void:
	for flyer_id in flyer_ids:
		_claims.erase(int(flyer_id))


## Drops every claim (full teardown).
func release_all() -> void:
	_claims.clear()


## How many claims are live. Bounded by the number of live pollinators -- see
## _claims. Exposed mainly so leak-safety can be asserted directly.
func claim_count() -> int:
	return _claims.size()


## Blooms within `radius` (world pixels) of `position` that some OTHER flyer
## is already heading for. `exclude_flyer_id` is the asking flyer, so it is
## never warned off its own target while it re-decides.
##
## Scans every live claim. That is O(pollinators on screen) -- a couple of
## hundred at most, since the table is bounded by flyer count rather than by
## bloom count or session length -- and comfortably cheaper than the flower
## lookup the caller has already done to get here.
func claimed_positions_near(
	position: Vector2, radius: float, exclude_flyer_id: int = NO_FLYER
) -> Array:
	var out: Array = []
	var radius_squared := radius * radius
	for flyer_id in _claims:
		if flyer_id == exclude_flyer_id:
			continue
		var claimed: Vector2 = _claims[flyer_id]
		if position.distance_squared_to(claimed) <= radius_squared:
			out.append(claimed)
	return out
