extends RefCounted

## One farmable tile's plant/tend/harvest lifecycle (see
## docs/concept/farming.md's "farming loop"). Mirrors TreeGenome/TreeMaturity's
## deterministic seed-driven growth pattern, adapted to a plant/water/harvest
## loop instead of grow-and-spread: growth_time and harvest count both derive
## from seed_value so the same seed always plays out the same way, and growth
## additionally depends on the player's tending (see advance()).

## Same 20-60s range TreeGenome uses for tree maturity_time -- a plausible
## real-time crop cycle without making the player wait too long to see it.
const MIN_GROWTH_TIME := 20.0
const MAX_GROWTH_TIME := 60.0

## A plot has this fraction of its own growth_time to be re-watered before
## it's considered neglected and withers -- half the crop's growth time, so
## a quick-growing crop needs more frequent attention than a slow one,
## proportionally.
const WATER_GRACE_FRACTION := 0.5

const MIN_YIELD_COUNT := 2
const MAX_YIELD_COUNT := 4

var state: String = "empty"
var crop_id: String = ""
var seed_value: int = 0
var growth_time: float = 0.0
var time_growing: float = 0.0
var time_since_watered: float = 0.0


## Starts a fresh growth cycle: derives a deterministic growth_time from
## seed_value (same hash-fraction pattern as TreeGenome) and counts the plot
## as just-watered so the player has a full grace window before their first
## water() call.
func plant(a_crop_id: String, a_seed_value: int) -> void:
	crop_id = a_crop_id
	seed_value = a_seed_value
	growth_time = lerpf(MIN_GROWTH_TIME, MAX_GROWTH_TIME, _seed_fraction("growth_time"))
	time_growing = 0.0
	time_since_watered = 0.0
	state = "growing"


## Resets the neglect clock -- call whenever the player tends the plot.
func water() -> void:
	time_since_watered = 0.0


## Advances simulation time. Growth only accrues while watered within the
## grace window; exceeding it withers the plot instead of letting it reach
## "ready".
func advance(delta: float) -> void:
	if state != "growing":
		return
	time_since_watered += delta
	if time_since_watered > growth_time * WATER_GRACE_FRACTION:
		state = "withered"
		return
	time_growing += delta
	if time_growing >= growth_time:
		state = "ready"


func is_ready() -> bool:
	return state == "ready"


func is_withered() -> bool:
	return state == "withered"


## Harvesting a ready plot yields a seed-deterministic count (same
## hash-fraction pattern as growth_time) and resets the plot to "empty".
## A no-op on a growing/withered/empty plot -- state is left untouched and
## an empty-crop zero-count result is returned instead.
func harvest() -> Dictionary:
	if state != "ready":
		return {"crop_id": "", "count": 0}
	var count: int = MIN_YIELD_COUNT + int(_seed_fraction("yield_count") * float(MAX_YIELD_COUNT - MIN_YIELD_COUNT + 1))
	var result := {"crop_id": crop_id, "count": count}
	state = "empty"
	crop_id = ""
	return result


func _seed_fraction(salt: String) -> float:
	return float(absi(hash("%d_%s" % [seed_value, salt])) % 10000) / 10000.0
