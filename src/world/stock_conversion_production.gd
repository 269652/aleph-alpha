extends RefCounted

## A building that turns one stock into another, continuously, off its own
## real stock (docs/concept/milling_and_baking.md's "Production" section):
## the generic single-lane form of SagewerkProduction's own log -> beam/
## plank shaping. One input, one output, a real cost of input per unit of
## output and a real number of seconds of work per unit, advanced as a PURE
## function of elapsed time -- mirroring ChunkEcologyCatchup.advance's own
## "return a new state, never mutate the input" contract exactly as
## SagewerkProduction already does.
##
## The Mill (wheat -> flour, MillProduction) and the Bakery (flour -> bread,
## BakeryProduction) are two instances of this with their own pinned
## constants; the mechanics live here once. Deliberately NOT a rewrite of
## SagewerkProduction itself: its dual-lane concurrent beam/plank shaping
## off one shared woodpile is a real, already-tuned, already-tested shape
## this single-lane one does not need to replace (production_chains.md's
## own "deliberate, named narrowing").

## Units of input consumed per unit of output.
var input_cost_per_unit: float

## Seconds of work to produce one unit of output.
var seconds_per_unit: float


func _init(input_cost: float, seconds: float) -> void:
	input_cost_per_unit = input_cost
	seconds_per_unit = seconds


## Advances `state` (`input_stock`/`progress`) by `elapsed_seconds`, returning
## a NEW state dict plus this tick's `output` count. `staffed` false means
## the building sits idle -- no progress, no consumption, no output,
## regardless of stock or elapsed time -- production is the building's
## behavior while worked, not a passive timer (SagewerkProduction's own
## rule, kept identical so the two read the same way).
##
## Work only accumulates (and stock is only consumed) while enough input
## remains for at least one more unit, so running out mid-conversion stops
## consumption rather than going negative, and nothing ever "banks" work
## against an empty hopper.
func advance(state: Dictionary, elapsed_seconds: float, staffed: bool) -> Dictionary:
	var input_stock: float = state.get("input_stock", 0.0)
	var progress: float = state.get("progress", 0.0)
	var output := 0

	if staffed and elapsed_seconds > 0.0 and input_stock >= input_cost_per_unit:
		progress += elapsed_seconds
		while progress >= seconds_per_unit and input_stock >= input_cost_per_unit:
			progress -= seconds_per_unit
			input_stock -= input_cost_per_unit
			output += 1

	return {"input_stock": input_stock, "progress": progress, "output": output}
