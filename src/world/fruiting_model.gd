extends RefCounted

## Per-tree fruit phenology (docs/concept/ecosystem_dynamics.md, "Plant
## phenology"). Models one tree's repeating bearing cycle as a continuous
## fruit stock over elapsed time: fruits grow (immature) -> ripen (hang,
## edible) -> abscise (fall to the ground) -> the tree re-enters growing.
## Deterministic: purely a function of the genome and time, no RNG.

## Peak crop a maximally fruitful tree (fruit_yield == 1) can bear at once.
const MAX_CROP := 12

## Fraction of a bearing cycle spent growing immature fruit before any is ripe.
const GROW_FRAC := 0.5
## Fraction of a cycle at which ripe fruit begins to abscise (fall). Ripe fruit
## hangs on the canopy from GROW_FRAC until here, then drops by cycle end.
const ABSCISSION_START := 0.8
## How much warmth (growing-degree-day analogue) speeds ripening: at warmth 1
## the bearing cycle is this-many times shorter, so fruit ripens sooner.
const WARMTH_SPEEDUP := 1.0


## Crop potential (max simultaneous ripe fruit) for a genome.
func crop_potential(genome) -> int:
	return int(round(genome.fruit_yield * MAX_CROP))


## Length in seconds of one full grow->ripen->fall cycle, shortened by warmth.
func _cycle_length(genome, warmth: float) -> float:
	return genome.maturity_time / (1.0 + clampf(warmth, 0.0, 1.0) * WARMTH_SPEEDUP)


## {growing:int, ripe:int} at a point in time: immature and ripe-hanging counts.
func state_at(genome, elapsed_seconds: float, warmth: float) -> Dictionary:
	var crop := crop_potential(genome)
	if crop <= 0:
		return {"growing": 0, "ripe": 0}
	var length := _cycle_length(genome, warmth)
	var phase := fposmod(elapsed_seconds, length) / length
	var growing := 0
	var ripe := 0
	if phase < GROW_FRAC:
		growing = int(round(crop * (phase / GROW_FRAC)))
	elif phase < ABSCISSION_START:
		ripe = crop
	else:
		var remaining := 1.0 - (phase - ABSCISSION_START) / (1.0 - ABSCISSION_START)
		ripe = int(round(crop * remaining))
	return {"growing": growing, "ripe": ripe}


## Ripe fruits abscised (fell) during (t0, t1]. Driven by the abscission window
## of each bearing cycle; accumulates across repeated cycles.
func fallen_between(genome, t0: float, t1: float, warmth: float) -> int:
	if t1 <= t0:
		return 0
	var crop := crop_potential(genome)
	if crop <= 0:
		return 0
	var length := _cycle_length(genome, warmth)
	return int(round(_cumulative_fallen(crop, length, t1) - _cumulative_fallen(crop, length, t0)))


## Continuous count of fruits fallen from time 0 up to t (monotonic in t):
## a full `crop` per completed cycle, ramping linearly through the abscission
## window of the in-progress cycle.
func _cumulative_fallen(crop: int, length: float, t: float) -> float:
	if t <= 0.0:
		return 0.0
	var full_cycles := floorf(t / length)
	var phase := fposmod(t, length) / length
	var partial := 0.0
	if phase > ABSCISSION_START:
		partial = (phase - ABSCISSION_START) / (1.0 - ABSCISSION_START)
	return crop * (full_cycles + partial)
