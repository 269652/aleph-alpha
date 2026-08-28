extends RefCounted

## Pure lookup for the "timed, no extra magnitude" spell atoms (docs/concept/
## spell_runtime.md: ignite, blight, freeze, root, slow, illuminate, calm,
## fear, suppress_mutation) that resolve as a DebuffStack-tracked status
## rather than an instant effect. Generalizes VenomModel's own "what does N
## stacks of this debuff actually do" role across every status atom at once
## -- DebuffStack (apply/advance/stacks_of) stays exactly as agnostic as it
## already is for venom, and the caller (Player/CreatureMarker) still owns
## and coordinates its own DebuffStack array, exactly like Player._venom_step
## already does; a literal one-file-per-atom copy of VenomModel would be
## near-identical boilerplate repeated 8+ times for no benefit.

const IGNITE := "ignite"
const BLIGHT := "blight"
const FREEZE := "freeze"
const ROOT := "root"
const SLOW := "slow"
const ILLUMINATE := "illuminate"
const CALM := "calm"
const FEAR := "fear"
const SUPPRESS_MUTATION := "suppress_mutation"
## Tracked the same generic way as every other timed status -- a real,
## queryable "a wisp is active" flag, not yet a visual companion node (see
## docs/concept/spell_runtime.md's honest scope note on this one).
const SUMMON_WISP := "summon_wisp"

## Same cap VenomModel uses -- a status atom re-cast on an already-affected
## target intensifies rather than stacking without bound.
const MAX_STACKS := 3

## debuff_id -> damage per second per stack, for the two DoT-shaped statuses.
## Distinct values (not both copied from VenomModel's 1.5) so the two atoms
## stay mechanically distinguishable, not just differently colored --
## ignite is the cheaper, more magic-catalog-common atom (base_cost 1.5 vs
## blight's 2.0 -- see spell_atom_catalog.gd), so it hits a little harder
## per stack; blight's own atom is priced instead by lasting a duration
## longer (dur_ref 4.0 vs ignite's 3.0).
const _DAMAGE_PER_SECOND_PER_STACK := {
	IGNITE: 1.5,
	BLIGHT: 1.0,
}

## Movement speed while slowed -- meaningfully punishing (half speed) without
## being a de facto root, which is `freeze`/`root`'s own separate atom.
const SLOW_SPEED_MULTIPLIER := 0.5


func is_dot(debuff_id: String) -> bool:
	return _DAMAGE_PER_SECOND_PER_STACK.has(debuff_id)


## 0.0 for a status with no damage component (including an unknown id) --
## same "unrecognized contributes nothing" convention spell_cost.gd's own
## atom_cost uses for an unknown atom.
func damage_per_second(debuff_id: String, stacks: int) -> float:
	if not _DAMAGE_PER_SECOND_PER_STACK.has(debuff_id):
		return 0.0
	return float(clampi(stacks, 0, MAX_STACKS)) * float(_DAMAGE_PER_SECOND_PER_STACK[debuff_id])
