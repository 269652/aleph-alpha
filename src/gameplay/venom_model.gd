extends RefCounted

## Pure damage-over-time model for a venomous snake's bite (see
## docs/concept/ecosystem_dynamics.md's Species roster -- venomous_snake).
## Stacking state itself is tracked by the existing generic DebuffStack
## (apply/advance/stacks_of) -- this module only adds the "how much does N
## stacks hurt per second" rule DebuffStack is deliberately agnostic about.

const DEBUFF_ID := "venom"

## A real venom dose lingers rather than an instant burst -- each bite
## refreshes the duration and adds a stack (see DebuffStack.apply), up to
## MAX_STACKS. Pinned constants, not eyeballed.
const DURATION_SECONDS := 8.0
const MAX_STACKS := 3
const DAMAGE_PER_SECOND_PER_STACK := 1.5


func damage_per_second(stacks: int) -> float:
	return float(clampi(stacks, 0, MAX_STACKS)) * DAMAGE_PER_SECOND_PER_STACK
