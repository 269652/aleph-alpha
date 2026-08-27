extends RefCounted

## Unloaded-settlement construction catch-up integration (variable-fidelity
## LOD), mirroring chunk_ecology_catchup.gd's EXACT contract shape. See
## docs/concept/timber_construction.md's "NPC construction: the two
## fidelities" section's own "Unloaded / offscreen fidelity" subsection.
##
## A settlement near the player builds via real per-NPC agents (loaded
## fidelity, not this module's concern). A settlement far away instead has
## its builders' aggregate labor integrated in closed form over however long
## the chunk sat unloaded -- the same "same causal process, cheaper
## computation" philosophy chunk_ecology_catchup.gd already established for
## vegetation/herbivores/predators/fish/land_health, applied here to a
## ConstructionProject's own labor-hours accumulator instead of a population
## count.
##
## This IS the minimum-build-time floor the doc's own framing names
## directly: a project completes only once labor_hours_accumulated reaches
## labor_hours_required (see construction_labor.gd for how that requirement
## is itself derived from the project's real recipe). No amount of elapsed
## wall-clock time skips that faster than builder_count many NPCs' worth of
## hours can accumulate -- a lone, unpopulated hamlet cannot will a house
## into existence just by sitting unloaded for a thousand years, because
## builder_count (supplied by the caller, derived from real settlement
## population the same way SettlementState.carrying_capacity already derives
## a number from real stock) is what throttles how fast labor accumulates.

const ChunkEcologyCatchup = preload("res://src/world/chunk_ecology_catchup.gd")

## Reuses chunk_ecology_catchup.gd's OWN day/second exchange rate rather than
## inventing a second one -- one real elapsed second means the same fraction
## of a "day" here as it does for ecology catch-up, so a single elapsed-time
## value handed to both integrations advances both by a consistent notion of
## time.
const SECONDS_PER_DAY := ChunkEcologyCatchup.SECONDS_PER_DAY

## Labor-hours ONE builder contributes per full day of continuous work.
## Grounded the same way construction_labor.gd's own HOURS_PER_UNIT_MATERIAL
## comment is: an 8-hour real workday is the conventional unit a "labor-hour"
## budget is denominated in, so one builder present for one full day
## contributes 8 labor-hours toward a project -- the same real-world-grounded
## reasoning SagewerkProduction's SHAPE_SECONDS_PER_BEAM uses for its own
## per-unit rate. Pinned directly by
## test_one_builder_working_a_full_day_accumulates_the_pinned_hours_per_day
## rather than left as an eyeballed comment, per this project's
## no-manual-tuning rule.
const HOURS_PER_BUILDER_PER_DAY := 8.0

## Reuses EarthChunkManager.MAX_CATCHUP_DAYS's own exact value and
## justification ("logistic growth converges anyway" / here: a project
## either completes well within this cap or an unpopulated settlement was
## never going to finish it regardless of how long it sat unloaded) rather
## than inventing a second cap with a different number -- the same bounded-
## integration precedent the doc's own "Unloaded / offscreen fidelity"
## subsection points at directly ("the same MAX_CATCHUP_DAYS-style cap
## chunk_ecology_catchup.gd's own callers already use elsewhere"). Not a
## preload of a numeric constant off EarthChunkManager (that file is a large
## engine-dependent singleton this pure module must not depend on) -- the
## value itself is the shared precedent, pinned independently here by
## test_huge_elapsed_time_jump_is_safe_and_bounded_in_one_call.
const MAX_CATCHUP_DAYS := 120.0


## Integrate a ConstructionProject's aggregate labor forward by
## `elapsed_seconds` in one closed-form step. Pure: does not mutate `state`;
## returns a fresh Dictionary.
##
## `state`    -> {labor_hours_accumulated, labor_hours_required}
## `capacity` -> {builder_count}
##
## labor_hours_accumulated advances LINEARLY with elapsed time (not
## logistic/exponential like ecology's own vegetation/population curves --
## construction labor is a straightforward hours-worked accumulator, not a
## capacity-bounded growth process) scaled by builder_count and
## HOURS_PER_BUILDER_PER_DAY, capped at labor_hours_required so a project
## can never "overshoot" done, and elapsed time itself is capped at
## MAX_CATCHUP_DAYS worth of seconds so a huge unloaded duration is bounded
## arithmetic in one call rather than an unbounded loop.
func advance(state: Dictionary, elapsed_seconds: float, capacity: Dictionary) -> Dictionary:
	var elapsed := maxf(0.0, elapsed_seconds)
	var elapsed_days := minf(elapsed / SECONDS_PER_DAY, MAX_CATCHUP_DAYS)

	var labor_hours_accumulated: float = state.get("labor_hours_accumulated", 0.0)
	var labor_hours_required: float = state.get("labor_hours_required", 0.0)
	var builder_count: float = capacity.get("builder_count", 0.0)

	var earned := builder_count * HOURS_PER_BUILDER_PER_DAY * elapsed_days
	var new_accumulated := minf(labor_hours_accumulated + earned, labor_hours_required)

	return {
		"labor_hours_accumulated": new_accumulated,
		"labor_hours_required": labor_hours_required,
	}
