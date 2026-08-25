extends RefCounted

## The Sägewerk's own production: converting a log stockpile into beam/plank
## output over time, while staffed by its Lumberjack (see
## docs/concept/timber_construction.md's material-pipeline pillar). This is
## the BUILDING's behavior -- separate from the Lumberjack's own SEEK/
## APPROACH/FELL/CARRY/DEPOSIT gathering loop (LumberjackBehavior) -- mirrors
## the pure-formula shape npc_production.gd already uses for producer-
## occupation yield rates, applied here to a worksite instead of a person.
##
## Real-world grounding (docs/concept/timber_construction.md's "Hewing vs.
## riving"): squaring a round log into a beam (hewing, with a broadaxe --
## scoring the log then splitting/dressing the waste off) loses material and
## is slow, skilled work; splitting/sawing a log into boards (riving) yields
## more board footage per log but nothing structural, and is faster. A
## Balken should therefore cost more of the stockpile and take longer to
## shape than a Planke of the same footprint -- LOG_COST_PER_BEAM >
## LOG_COST_PER_PLANK and SHAPE_SECONDS_PER_BEAM > SHAPE_SECONDS_PER_PLANK
## encode exactly that, pinned by test_a_beam_costs_more_log_volume_than_a_
## plank / test_a_beam_takes_longer_to_shape_than_a_plank rather than left as
## an eyeballed comment (this project's no-manual-tuning rule).

## Logs consumed to shape one Balken -- more than a Planke's cost (hewing
## wastes sapwood/offcuts squaring a round log).
const LOG_COST_PER_BEAM := 3.0

## Logs consumed to shape one Planke -- riving/sawing is efficient by
## comparison.
const LOG_COST_PER_PLANK := 1.0

## Seconds of shaping work to produce one Balken -- hewing is slow, skilled
## work.
const SHAPE_SECONDS_PER_BEAM := 8.0

## Seconds of shaping work to produce one Planke -- riving/sawing is faster.
const SHAPE_SECONDS_PER_PLANK := 3.0


## Advances `state` (`log_stock`/`beam_progress`/`plank_progress`) by
## `elapsed_seconds`, returning a NEW state dict plus this tick's
## `beam_output`/`plank_output` counts -- pure, no mutation of the input,
## mirroring ChunkEcologyCatchup.advance's own contract shape. `staffed`
## false (no Lumberjack currently assigned) means the mill sits idle: no
## progress, no consumption, no output, regardless of stock or elapsed time
## -- production is the building's behavior while worked, not a passive
## timer.
##
## Beam and plank shaping progress accumulate independently but draw from
## the SAME shared log_stock -- a real sawmill's hewing block and riving
## station work concurrently off one woodpile. Each lane only advances (and
## only consumes stock) while enough logs remain for at least one more unit
## of that lane's own product, so running out of logs mid-shape stops
## consumption rather than going negative.
func advance(state: Dictionary, elapsed_seconds: float, staffed: bool) -> Dictionary:
	var log_stock: float = state.get("log_stock", 0.0)
	var beam_progress: float = state.get("beam_progress", 0.0)
	var plank_progress: float = state.get("plank_progress", 0.0)
	var beam_output := 0
	var plank_output := 0

	if staffed and elapsed_seconds > 0.0:
		if log_stock >= LOG_COST_PER_BEAM:
			beam_progress += elapsed_seconds
			while beam_progress >= SHAPE_SECONDS_PER_BEAM and log_stock >= LOG_COST_PER_BEAM:
				beam_progress -= SHAPE_SECONDS_PER_BEAM
				log_stock -= LOG_COST_PER_BEAM
				beam_output += 1
		if log_stock >= LOG_COST_PER_PLANK:
			plank_progress += elapsed_seconds
			while plank_progress >= SHAPE_SECONDS_PER_PLANK and log_stock >= LOG_COST_PER_PLANK:
				plank_progress -= SHAPE_SECONDS_PER_PLANK
				log_stock -= LOG_COST_PER_PLANK
				plank_output += 1

	return {
		"log_stock": log_stock,
		"beam_progress": beam_progress,
		"plank_progress": plank_progress,
		"beam_output": beam_output,
		"plank_output": plank_output,
	}
