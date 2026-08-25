extends RefCounted

## Whether a settlement's real, already-tracked material stock should
## START or ABANDON a construction project -- InstitutionFormation's own
## hysteresis PATTERN (institution_formation.gd's "cross a bar to start,
## drop WELL below it, not just below it, to abandon" asymmetric two-
## threshold shape) applied to a different real number: a blueprint's own
## material requirement, per docs/concept/timber_construction.md's
## "Settlement construction ledger" section ("material stock crossing a
## blueprint's requirement to start, dropping well below it -- not just
## below it -- to abandon, the same asymmetric gap that stops formation/
## dissolution from flickering on a single unit of stock changing hands").
##
## Deliberately its OWN small pure module, not a reuse of
## InstitutionFormation itself (that module is contract-specific -- shared
## FULFILLED-contract counts between two parties) -- same asymmetric-gap
## SHAPE, a fresh, test-pinned threshold.

## How far below a blueprint's own requirement stock must fall before an
## in-progress project is considered for abandonment -- expressed as a
## FRACTION of the requirement (rather than a fixed unit gap, the way
## InstitutionFormation's FORMATION_THRESHOLD/DISSOLUTION_THRESHOLD are
## both plain contract counts) because a blueprint's own requirement varies
## wildly by recipe (3 wood for a wooden_club vs. 12 wood for a storage
## shed) -- a fixed unit gap would be meaningless for one and trivial for
## the other, where a fraction of the requirement always sits a
## meaningful, proportional gap under the start bar regardless of
## blueprint size. Tested (not eyeballed) against the flicker it prevents
## (test_construction_start_hysteresis.gd), the same "no real economy data
## yet to derive a correct number from" honesty InstitutionFormation's own
## thresholds already carry.
const ABANDON_FRACTION := 0.5


## Whether `stock_amount` has crossed `required_amount` -- the START bar.
static func should_start(stock_amount: float, required_amount: float) -> bool:
	return stock_amount >= required_amount


## Whether `stock_amount` has fallen WELL below `required_amount` -- the
## ABANDON bar, a real gap under should_start's own bar (see
## ABANDON_FRACTION's own doc comment) so a project already under way is
## not abandoned just because stock dipped slightly, only once it has
## genuinely collapsed.
static func should_abandon(stock_amount: float, required_amount: float) -> bool:
	return stock_amount < required_amount * ABANDON_FRACTION
