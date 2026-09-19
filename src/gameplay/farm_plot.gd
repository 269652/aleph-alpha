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

## The shortest drought tolerance any bed can have, in seconds, whatever it
## is sown with -- ONE NIGHT.
##
## Reported in play three times over, most recently with the field in shot:
## *"Planted crops still vanish and don't grow and no harvest happens"*.
## Measured against a real village (tools/probe_village_farming.gd): thirteen
## of eighteen beds ended withered over ten simulated days, two of three
## farmhouses took in nothing at all, and the farmer was working 2750 of 6000
## ticks the whole time. They were not idle. They could not be there.
##
## The arithmetic is not close. WATER_GRACE_FRACTION alone gave a bed ten to
## thirty seconds of tolerance; a villager's day is sixty seconds across four
## blocks and nobody farms while they sleep, so a field goes untended for up
## to three of them on every day of its life. Every bed died every night, and
## the farmer spent each morning replanting ground that would die again by
## evening.
##
## So: the village's own night, taken from the simulated day and the
## schedule's own blocks (EarthChunkManager.SECONDS_PER_SIMULATED_DAY = 60,
## NpcSchedule.TIME_BLOCKS = 4, at worst one of them worked). Written here
## rather than imported -- a pure gameplay rule does not reach into the chunk
## manager -- and pinned against both by
## test_the_night_a_bed_must_survive_is_the_villages_own_night, which is what
## keeps the two from drifting.
##
## Not a forgiving number picked to make a field work: a field is not a pot
## on a windowsill, and a crop that dies because nobody came for one evening
## is a crop nobody in this world could farm, the player included.
const MIN_WATER_GRACE_SECONDS := 45.0

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
	if time_since_watered > grace_seconds():
		state = "withered"
		return
	time_growing += delta
	if time_growing >= growth_time:
		state = "ready"


## How long this bed can go unwatered before it withers: its own crop-scaled
## window, or one night, whichever is longer (see MIN_WATER_GRACE_SECONDS).
## The floor raises a short window and never shortens a long one, so a slow
## crop keeps the longer tolerance its own growth time earns it.
func grace_seconds() -> float:
	return maxf(growth_time * WATER_GRACE_FRACTION, MIN_WATER_GRACE_SECONDS)


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
